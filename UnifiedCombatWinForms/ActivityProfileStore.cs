using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace UnifiedCombatWinForms;

internal sealed record ActivityProfileIdentity(string Character, string MainJob, string SubJob)
{
    internal string Key => string.Join(
        "|",
        Character.Trim().ToUpperInvariant(),
        MainJob.Trim().ToUpperInvariant(),
        SubJob.Trim().ToUpperInvariant()
    );

    internal StructuredProfileV2Identity ToStructuredIdentity() => new(Character.Trim(), MainJob.Trim(), SubJob.Trim());
}

internal sealed record ActivityProfileCapture(
    ActivityProfileIdentity Identity,
    string ProfileContent,
    string UiProfileContent
);

internal sealed record ActivitySessionIdentity(string Sid, ActivityProfileIdentity Identity);

internal sealed record ActivityActivationEntry(
    string Sid,
    ActivityProfileIdentity Identity,
    string SourcePath,
    string DestinationPath,
    string ProfileContent,
    string UiSourcePath,
    string UiProfileContent
);

internal sealed record ActivityActivationPlan(
    string ActivityId,
    string ActivityName,
    IReadOnlyList<ActivityActivationEntry> Entries,
    IReadOnlyList<ActivitySessionIdentity> UnmatchedSessions
);

internal enum ActivityProfileProvenance
{
    Exact,
    Modified,
    NoMatch,
}

internal sealed record ActivityProfileProvenanceEntry(
    string Sid,
    ActivityProfileIdentity Identity,
    ActivityProfileProvenance Provenance
);

internal sealed record ActivityProfileProvenanceSnapshot(
    string ActivityId,
    string ActivityName,
    IReadOnlyList<ActivityProfileProvenanceEntry> Entries
);

internal sealed record ActivityProfileSummary(string Id, string Name, int CharacterCount, int VariantCount);

internal sealed class ActivityProfileManifest
{
    [JsonPropertyName("schema_version")]
    public int SchemaVersion { get; set; } = 2;

    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("updated_at_utc")]
    public string UpdatedAtUtc { get; set; } = "";

    [JsonPropertyName("characters")]
    public List<ActivityProfileCharacter> Characters { get; set; } = [];
}

internal sealed class ActivityProfileCharacter
{
    [JsonPropertyName("character")]
    public string Character { get; set; } = "";

    [JsonPropertyName("variants")]
    public List<ActivityProfileVariant> Variants { get; set; } = [];
}

internal sealed class ActivityProfileVariant
{
    [JsonPropertyName("main_job")]
    public string MainJob { get; set; } = "";

    [JsonPropertyName("sub_job")]
    public string SubJob { get; set; } = "";

    [JsonPropertyName("profile_file")]
    public string ProfileFile { get; set; } = "";

    [JsonPropertyName("sha256")]
    public string Sha256 { get; set; } = "";

    [JsonPropertyName("ui_profile_file")]
    public string UiProfileFile { get; set; } = "";

    [JsonPropertyName("ui_sha256")]
    public string UiSha256 { get; set; } = "";
}

internal sealed class ActivityProfileException : Exception
{
    internal ActivityProfileException(string message, Exception? innerException = null)
        : base(message, innerException)
    {
    }
}

internal sealed class ActivityProfileDeployment : IDisposable
{
    private sealed record DeployedFile(string DestinationPath, string BackupPath, bool HadOriginal);

    private readonly List<DeployedFile> _files;
    private bool _finished;

    internal ActivityProfileDeployment(List<(string destinationPath, string backupPath, bool hadOriginal)> files)
    {
        _files = files.Select(x => new DeployedFile(x.destinationPath, x.backupPath, x.hadOriginal)).ToList();
    }

    internal void Commit()
    {
        if (_finished)
        {
            throw new InvalidOperationException("Activity deployment is already finalized.");
        }

        foreach (var file in _files)
        {
            if (file.HadOriginal && File.Exists(file.BackupPath))
            {
                File.Delete(file.BackupPath);
            }
        }

        _finished = true;
    }

    internal void Rollback()
    {
        if (_finished)
        {
            throw new InvalidOperationException("Activity deployment is already finalized.");
        }

        for (var i = _files.Count - 1; i >= 0; i--)
        {
            var file = _files[i];
            if (file.HadOriginal)
            {
                if (!File.Exists(file.BackupPath))
                {
                    throw new ActivityProfileException($"Activity rollback backup is missing: {file.BackupPath}");
                }
                if (!File.Exists(file.DestinationPath))
                {
                    throw new ActivityProfileException($"Activity rollback destination is missing: {file.DestinationPath}");
                }
                File.Replace(file.BackupPath, file.DestinationPath, destinationBackupFileName: null, ignoreMetadataErrors: true);
            }
            else if (File.Exists(file.DestinationPath))
            {
                File.Delete(file.DestinationPath);
            }
        }

        _finished = true;
    }

    public void Dispose()
    {
        if (!_finished)
        {
            Rollback();
        }
    }
}

internal sealed class ActivityProfileStore
{
    private const int LegacySchemaVersion = 1;
    private const int SchemaVersion = 2;
    private const string ManifestFileName = "activity.json";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = false,
    };

    private readonly string _addonRoot;
    private readonly string _root;

    internal ActivityProfileStore(string addonRoot)
    {
        if (string.IsNullOrWhiteSpace(addonRoot) || !Directory.Exists(addonRoot))
        {
            throw new ActivityProfileException("Activity profile addon root does not exist.");
        }

        _addonRoot = Path.GetFullPath(addonRoot);
        _root = Path.Combine(_addonRoot, "data", "activity_profiles");
    }

    internal IReadOnlyList<ActivityProfileSummary> List()
    {
        if (!Directory.Exists(_root))
        {
            return [];
        }

        var output = new List<ActivityProfileSummary>();
        foreach (var directory in Directory.GetDirectories(_root).OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
        {
            var manifestPath = Path.Combine(directory, ManifestFileName);
            if (!File.Exists(manifestPath))
            {
                throw new ActivityProfileException($"Activity directory has no manifest: {directory}");
            }

            var manifest = LoadManifest(manifestPath, Path.GetFileName(directory));
            output.Add(
                new ActivityProfileSummary(
                    manifest.Id,
                    manifest.Name,
                    manifest.Characters.Count,
                    manifest.Characters.Sum(x => x.Variants.Count)
                )
            );
        }

        return output.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    internal ActivityProfileManifest Create(string name, IReadOnlyList<ActivityProfileCapture> captures)
    {
        var cleanName = RequireName(name);
        var existing = List();
        if (existing.Any(x => string.Equals(x.Name, cleanName, StringComparison.OrdinalIgnoreCase)))
        {
            throw new ActivityProfileException($"An activity named '{cleanName}' already exists.");
        }

        var manifest = new ActivityProfileManifest
        {
            Id = Guid.NewGuid().ToString("N"),
            Name = cleanName,
        };
        return WriteBundle(manifest, captures, isUpdate: false);
    }

    internal ActivityProfileManifest Update(string activityId, IReadOnlyList<ActivityProfileCapture> captures)
    {
        var manifest = Load(activityId);
        return WriteBundle(manifest, captures, isUpdate: true);
    }

    internal void Delete(string activityId)
    {
        var manifest = Load(activityId);
        var directory = ActivityDirectory(manifest.Id);
        Directory.Delete(directory, recursive: true);
    }

    internal ActivityProfileManifest Load(string activityId)
    {
        var id = RequireId(activityId);
        var directory = ActivityDirectory(id);
        var path = Path.Combine(directory, ManifestFileName);
        if (!File.Exists(path))
        {
            throw new ActivityProfileException($"Activity profile does not exist: {id}");
        }

        return LoadManifest(path, id);
    }

    internal ActivityActivationPlan BuildActivationPlan(
        string activityId,
        IReadOnlyList<ActivitySessionIdentity> sessions
    )
    {
        if (sessions.Count == 0)
        {
            throw new ActivityProfileException("There are no active sessions to apply this activity to.");
        }

        var duplicateSid = sessions.GroupBy(x => x.Sid, StringComparer.Ordinal).FirstOrDefault(x => x.Count() > 1);
        if (duplicateSid is not null)
        {
            throw new ActivityProfileException($"Duplicate active session id: {duplicateSid.Key}");
        }

        var duplicateIdentity = sessions.GroupBy(x => x.Identity.Key, StringComparer.Ordinal).FirstOrDefault(x => x.Count() > 1);
        if (duplicateIdentity is not null)
        {
            throw new ActivityProfileException($"Duplicate active character/job identity: {duplicateIdentity.Key}");
        }

        var manifest = Load(activityId);
        var variants = BuildVariantMap(manifest);
        var entries = new List<ActivityActivationEntry>();
        var unmatchedSessions = new List<ActivitySessionIdentity>();
        foreach (var session in sessions)
        {
            if (!variants.TryGetValue(session.Identity.Key, out var variant))
            {
                unmatchedSessions.Add(session);
                continue;
            }

            var activityDirectory = ActivityDirectory(manifest.Id);
            var sourcePath = ResolveContainedPath(activityDirectory, variant.ProfileFile);
            if (!File.Exists(sourcePath))
            {
                throw new ActivityProfileException($"Activity profile snapshot is missing: {variant.ProfileFile}");
            }

            var content = File.ReadAllText(sourcePath, Encoding.UTF8);
            var actualHash = Sha256(content);
            if (!string.Equals(actualHash, variant.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new ActivityProfileException($"Activity profile snapshot checksum failed: {variant.ProfileFile}");
            }

            if (variant.UiProfileFile.Trim().Length == 0 || variant.UiSha256.Trim().Length != 64)
            {
                throw new ActivityProfileException(
                    $"Activity '{manifest.Name}' has no UI snapshot for "
                    + $"{session.Identity.Character} {session.Identity.MainJob}/{session.Identity.SubJob}. "
                    + "Select the activity and click Update while that character/job is active."
                );
            }
            var uiSourcePath = ResolveContainedPath(activityDirectory, variant.UiProfileFile);
            if (!File.Exists(uiSourcePath))
            {
                throw new ActivityProfileException($"Activity UI snapshot is missing: {variant.UiProfileFile}");
            }
            var uiContent = File.ReadAllText(uiSourcePath, Encoding.UTF8);
            var actualUiHash = Sha256(uiContent);
            if (!string.Equals(actualUiHash, variant.UiSha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new ActivityProfileException($"Activity UI snapshot checksum failed: {variant.UiProfileFile}");
            }
            ValidateUiProfileContent(uiContent, session.Identity);

            var destination = StructuredProfileV2Writer.BuildFinalPath(_addonRoot, session.Identity.ToStructuredIdentity());
            entries.Add(
                new ActivityActivationEntry(
                    session.Sid,
                    session.Identity,
                    sourcePath,
                    destination,
                    content,
                    uiSourcePath,
                    uiContent
                )
            );
        }

        return new ActivityActivationPlan(manifest.Id, manifest.Name, entries, unmatchedSessions);
    }

    internal ActivityProfileProvenanceSnapshot BuildProvenance(
        string activityId,
        IReadOnlyList<ActivitySessionIdentity> sessions
    )
    {
        var duplicateSid = sessions.GroupBy(x => x.Sid, StringComparer.Ordinal).FirstOrDefault(x => x.Count() > 1);
        if (duplicateSid is not null)
        {
            throw new ActivityProfileException($"Duplicate active session id: {duplicateSid.Key}");
        }

        var manifest = Load(activityId);
        var variants = BuildVariantMap(manifest);
        var entries = new List<ActivityProfileProvenanceEntry>(sessions.Count);
        foreach (var session in sessions)
        {
            if (!variants.TryGetValue(session.Identity.Key, out var variant))
            {
                entries.Add(
                    new ActivityProfileProvenanceEntry(
                        session.Sid,
                        session.Identity,
                        ActivityProfileProvenance.NoMatch
                    )
                );
                continue;
            }

            var destination = StructuredProfileV2Writer.BuildFinalPath(
                _addonRoot,
                session.Identity.ToStructuredIdentity()
            );
            var provenance = ActivityProfileProvenance.Modified;
            if (File.Exists(destination))
            {
                var currentContent = File.ReadAllText(destination, Encoding.UTF8);
                if (string.Equals(Sha256(currentContent), variant.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    provenance = ActivityProfileProvenance.Exact;
                }
            }

            entries.Add(new ActivityProfileProvenanceEntry(session.Sid, session.Identity, provenance));
        }

        return new ActivityProfileProvenanceSnapshot(manifest.Id, manifest.Name, entries);
    }

    internal ActivityProfileDeployment Deploy(ActivityActivationPlan plan)
    {
        if (plan.Entries.Count == 0)
        {
            throw new ActivityProfileException("Activity activation plan contains no sessions.");
        }

        var deploymentFiles = plan.Entries
            .Select(entry => (DestinationPath: entry.DestinationPath, Content: entry.ProfileContent))
            .ToList();
        var duplicateDestination = deploymentFiles
            .GroupBy(x => Path.GetFullPath(x.DestinationPath), StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault(x => x.Count() > 1);
        if (duplicateDestination is not null)
        {
            throw new ActivityProfileException($"Activity activation has duplicate destination: {duplicateDestination.Key}");
        }

        var operationId = Guid.NewGuid().ToString("N");
        var staged = new List<(string destinationPath, string tempPath, string backupPath)>();
        var deployed = new List<(string destinationPath, string backupPath, bool hadOriginal)>();
        try
        {
            foreach (var file in deploymentFiles)
            {
                var directory = Path.GetDirectoryName(file.DestinationPath)
                    ?? throw new ActivityProfileException("Activity destination directory is unavailable.");
                Directory.CreateDirectory(directory);
                var tempPath = file.DestinationPath + $".activity.{operationId}.tmp";
                var backupPath = file.DestinationPath + $".activity.{operationId}.bak";
                if (File.Exists(tempPath) || File.Exists(backupPath))
                {
                    throw new ActivityProfileException("Activity deployment staging path already exists.");
                }

                File.WriteAllText(tempPath, file.Content, new UTF8Encoding(false));
                staged.Add((file.DestinationPath, tempPath, backupPath));
            }

            foreach (var item in staged)
            {
                var hadOriginal = File.Exists(item.destinationPath);
                if (hadOriginal)
                {
                    File.Replace(item.tempPath, item.destinationPath, item.backupPath, ignoreMetadataErrors: true);
                }
                else
                {
                    File.Move(item.tempPath, item.destinationPath);
                }

                deployed.Add((item.destinationPath, item.backupPath, hadOriginal));
            }

            return new ActivityProfileDeployment(deployed);
        }
        catch (Exception ex)
        {
            for (var i = deployed.Count - 1; i >= 0; i--)
            {
                var item = deployed[i];
                if (item.hadOriginal)
                {
                    if (!File.Exists(item.backupPath))
                    {
                        throw new ActivityProfileException($"Activity deployment recovery backup is missing: {item.backupPath}");
                    }
                    if (!File.Exists(item.destinationPath))
                    {
                        throw new ActivityProfileException($"Activity deployment recovery destination is missing: {item.destinationPath}");
                    }
                    File.Replace(item.backupPath, item.destinationPath, destinationBackupFileName: null, ignoreMetadataErrors: true);
                }
                else if (File.Exists(item.destinationPath))
                {
                    File.Delete(item.destinationPath);
                }
            }

            foreach (var item in staged)
            {
                if (File.Exists(item.tempPath))
                {
                    File.Delete(item.tempPath);
                }
            }

            throw new ActivityProfileException("Activity profile deployment failed.", ex);
        }
    }

    private ActivityProfileManifest WriteBundle(
        ActivityProfileManifest manifest,
        IReadOnlyList<ActivityProfileCapture> captures,
        bool isUpdate
    )
    {
        ValidateCaptures(captures);
        var finalDirectory = ActivityDirectory(manifest.Id);
        if (isUpdate && !Directory.Exists(finalDirectory))
        {
            throw new ActivityProfileException($"Activity directory does not exist: {manifest.Id}");
        }
        if (!isUpdate && Directory.Exists(finalDirectory))
        {
            throw new ActivityProfileException($"Activity directory already exists: {manifest.Id}");
        }

        Directory.CreateDirectory(_root);
        var stagingDirectory = Path.Combine(_root, $".{manifest.Id}.{Guid.NewGuid():N}.staging");
        var backupDirectory = Path.Combine(_root, $".{manifest.Id}.{Guid.NewGuid():N}.backup");
        if (Directory.Exists(stagingDirectory) || Directory.Exists(backupDirectory))
        {
            throw new ActivityProfileException("Activity bundle staging path already exists.");
        }

        try
        {
            if (isUpdate)
            {
                CopyDirectory(finalDirectory, stagingDirectory);
            }
            else
            {
                Directory.CreateDirectory(stagingDirectory);
            }

            var profilesDirectory = Path.Combine(stagingDirectory, "profiles");
            var uiProfilesDirectory = Path.Combine(stagingDirectory, "ui_profiles");
            Directory.CreateDirectory(profilesDirectory);
            Directory.CreateDirectory(uiProfilesDirectory);
            var variantMap = BuildVariantMap(manifest);
            foreach (var capture in captures)
            {
                var identity = capture.Identity;
                var fileStem = $"{StructuredProfileV2Writer.SafeCharacterComponent(identity.Character)}_"
                    + $"{StructuredProfileV2Writer.SafeJobComponent(identity.MainJob)}_"
                    + $"{StructuredProfileV2Writer.SafeJobComponent(identity.SubJob)}";
                var fileName = fileStem + ".lua";
                var uiFileName = fileStem + ".json";
                var relativePath = Path.Combine("profiles", fileName).Replace('\\', '/');
                var uiRelativePath = Path.Combine("ui_profiles", uiFileName).Replace('\\', '/');
                File.WriteAllText(Path.Combine(profilesDirectory, fileName), capture.ProfileContent, new UTF8Encoding(false));
                File.WriteAllText(Path.Combine(uiProfilesDirectory, uiFileName), capture.UiProfileContent, new UTF8Encoding(false));
                variantMap[identity.Key] = new ActivityProfileVariant
                {
                    MainJob = identity.MainJob.Trim().ToUpperInvariant(),
                    SubJob = identity.SubJob.Trim().ToUpperInvariant(),
                    ProfileFile = relativePath,
                    Sha256 = Sha256(capture.ProfileContent),
                    UiProfileFile = uiRelativePath,
                    UiSha256 = Sha256(capture.UiProfileContent),
                };
            }

            manifest.Characters = RebuildCharacters(variantMap, captures, manifest);
            manifest.SchemaVersion = SchemaVersion;
            manifest.UpdatedAtUtc = DateTime.UtcNow.ToString("O");
            var manifestText = JsonSerializer.Serialize(manifest, JsonOptions);
            File.WriteAllText(Path.Combine(stagingDirectory, ManifestFileName), manifestText, new UTF8Encoding(false));

            if (isUpdate)
            {
                Directory.Move(finalDirectory, backupDirectory);
                try
                {
                    Directory.Move(stagingDirectory, finalDirectory);
                }
                catch
                {
                    Directory.Move(backupDirectory, finalDirectory);
                    throw;
                }
                Directory.Delete(backupDirectory, recursive: true);
            }
            else
            {
                Directory.Move(stagingDirectory, finalDirectory);
            }

            return Load(manifest.Id);
        }
        catch (Exception ex)
        {
            if (Directory.Exists(stagingDirectory))
            {
                Directory.Delete(stagingDirectory, recursive: true);
            }
            if (Directory.Exists(backupDirectory) && !Directory.Exists(finalDirectory))
            {
                Directory.Move(backupDirectory, finalDirectory);
            }
            throw new ActivityProfileException("Activity profile bundle write failed.", ex);
        }
    }

    private static List<ActivityProfileCharacter> RebuildCharacters(
        Dictionary<string, ActivityProfileVariant> variants,
        IReadOnlyList<ActivityProfileCapture> captures,
        ActivityProfileManifest original
    )
    {
        var characterNames = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var character in original.Characters)
        {
            characterNames[character.Character.Trim().ToUpperInvariant()] = character.Character.Trim();
        }
        foreach (var capture in captures)
        {
            characterNames[capture.Identity.Character.Trim().ToUpperInvariant()] = capture.Identity.Character.Trim();
        }

        var result = new List<ActivityProfileCharacter>();
        foreach (var characterPair in characterNames.OrderBy(x => x.Value, StringComparer.OrdinalIgnoreCase))
        {
            var prefix = characterPair.Key + "|";
            var characterVariants = variants
                .Where(x => x.Key.StartsWith(prefix, StringComparison.Ordinal))
                .Select(x => x.Value)
                .OrderBy(x => x.MainJob, StringComparer.Ordinal)
                .ThenBy(x => x.SubJob, StringComparer.Ordinal)
                .ToList();
            if (characterVariants.Count > 0)
            {
                result.Add(new ActivityProfileCharacter
                {
                    Character = characterPair.Value,
                    Variants = characterVariants,
                });
            }
        }

        return result;
    }

    private static Dictionary<string, ActivityProfileVariant> BuildVariantMap(ActivityProfileManifest manifest)
    {
        var output = new Dictionary<string, ActivityProfileVariant>(StringComparer.Ordinal);
        foreach (var character in manifest.Characters)
        {
            var cleanCharacter = character.Character.Trim();
            if (cleanCharacter.Length == 0)
            {
                throw new ActivityProfileException("Activity manifest contains an empty character name.");
            }

            foreach (var variant in character.Variants)
            {
                var identity = new ActivityProfileIdentity(cleanCharacter, variant.MainJob, variant.SubJob);
                if (variant.MainJob.Trim().Length == 0 || variant.SubJob.Trim().Length == 0)
                {
                    throw new ActivityProfileException($"Activity manifest contains an incomplete job identity for {cleanCharacter}.");
                }
                if (variant.ProfileFile.Trim().Length == 0 || variant.Sha256.Trim().Length != 64)
                {
                    throw new ActivityProfileException($"Activity manifest contains invalid profile metadata for {identity.Key}.");
                }
                var hasUiProfileFile = variant.UiProfileFile.Trim().Length > 0;
                var hasUiHash = variant.UiSha256.Trim().Length > 0;
                if (hasUiProfileFile != hasUiHash || (hasUiHash && variant.UiSha256.Trim().Length != 64))
                {
                    throw new ActivityProfileException($"Activity manifest contains invalid UI profile metadata for {identity.Key}.");
                }
                if (!output.TryAdd(identity.Key, variant))
                {
                    throw new ActivityProfileException($"Activity manifest contains duplicate profile identity: {identity.Key}");
                }
            }
        }

        return output;
    }

    private ActivityProfileManifest LoadManifest(string path, string expectedId)
    {
        ActivityProfileManifest? manifest;
        try
        {
            manifest = JsonSerializer.Deserialize<ActivityProfileManifest>(File.ReadAllText(path, Encoding.UTF8), JsonOptions);
        }
        catch (Exception ex)
        {
            throw new ActivityProfileException($"Activity manifest is invalid: {path}", ex);
        }

        if (manifest is null
            || (manifest.SchemaVersion != LegacySchemaVersion && manifest.SchemaVersion != SchemaVersion))
        {
            throw new ActivityProfileException($"Activity manifest schema is unsupported: {path}");
        }
        if (!string.Equals(manifest.Id, expectedId, StringComparison.Ordinal))
        {
            throw new ActivityProfileException($"Activity manifest id does not match its directory: {path}");
        }
        RequireName(manifest.Name);
        BuildVariantMap(manifest);
        return manifest;
    }

    private string ActivityDirectory(string id) => Path.Combine(_root, RequireId(id));

    private static string RequireId(string id)
    {
        var clean = (id ?? "").Trim();
        if (clean.Length != 32 || clean.Any(ch => !Uri.IsHexDigit(ch)))
        {
            throw new ActivityProfileException("Activity id is invalid.");
        }
        return clean.ToLowerInvariant();
    }

    private static string RequireName(string name)
    {
        var clean = (name ?? "").Trim();
        if (clean.Length == 0 || clean.Length > 80)
        {
            throw new ActivityProfileException("Activity name must contain 1 through 80 characters.");
        }
        return clean;
    }

    private static void ValidateCaptures(IReadOnlyList<ActivityProfileCapture> captures)
    {
        if (captures.Count == 0)
        {
            throw new ActivityProfileException("At least one active session is required to capture an activity.");
        }

        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var capture in captures)
        {
            if (capture.Identity.Character.Trim().Length == 0
                || capture.Identity.MainJob.Trim().Length == 0
                || capture.Identity.SubJob.Trim().Length == 0)
            {
                throw new ActivityProfileException("Activity capture contains an incomplete character/job identity.");
            }
            if (capture.ProfileContent.Length == 0)
            {
                throw new ActivityProfileException($"Activity capture is empty for {capture.Identity.Key}.");
            }
            if (capture.UiProfileContent.Length == 0)
            {
                throw new ActivityProfileException($"Activity UI capture is empty for {capture.Identity.Key}.");
            }
            ValidateUiProfileContent(capture.UiProfileContent, capture.Identity);
            if (!seen.Add(capture.Identity.Key))
            {
                throw new ActivityProfileException($"Activity capture contains duplicate identity: {capture.Identity.Key}");
            }
        }
    }

    private static void ValidateUiProfileContent(string content, ActivityProfileIdentity identity)
    {
        try
        {
            using var document = JsonDocument.Parse(content);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new ActivityProfileException($"Activity UI snapshot is not an object for {identity.Key}.");
            }
        }
        catch (ActivityProfileException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new ActivityProfileException($"Activity UI snapshot is invalid for {identity.Key}.", ex);
        }
    }

    private static string ResolveContainedPath(string root, string relativePath)
    {
        if (Path.IsPathRooted(relativePath))
        {
            throw new ActivityProfileException("Activity profile path must be relative.");
        }

        var fullRoot = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        var fullPath = Path.GetFullPath(Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar)));
        if (!fullPath.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new ActivityProfileException("Activity profile path leaves its activity directory.");
        }
        return fullPath;
    }

    private static string Sha256(string content)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(content));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.GetFiles(source))
        {
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite: false);
        }
        foreach (var directory in Directory.GetDirectories(source))
        {
            CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
        }
    }
}
