using System.Text.Json;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private ComboBox _magicBurstMaxTier = null!;

    private static readonly string[] MagicBurstAutoSelections =
    [
        "Auto Spell",
        "Auto -ra",
        "Auto Helix",
    ];

    private static bool IsMagicBurstAutoSelection(string? value)
    {
        return MagicBurstAutoSelections.Contains((value ?? "").Trim(), StringComparer.Ordinal);
    }

    private static string MagicBurstFamilyForSelection(string? value)
    {
        return (value ?? "").Trim() switch
        {
  "Auto -ra" => "ra",
  "Auto Helix" => "helix",
  "Auto Spell" => "spell",
  _ => "spell",
        };
    }

    private static string MagicBurstAutoDisplay(string family)
    {
        return (family ?? "spell").Trim().ToLowerInvariant() switch
        {
  "ra" => "Auto -ra",
  "helix" => "Auto Helix",
  _ => "Auto Spell",
        };
    }

    private string MagicBurstModeValue()
    {
        return IsMagicBurstAutoSelection(_magicBurstSpell.Text) ? "auto" : "exact";
    }

    private string MagicBurstFamilyValue()
    {
        return MagicBurstModeValue() == "auto"
  ? MagicBurstFamilyForSelection(_magicBurstSpell.Text)
  : "spell";
    }

    private string MagicBurstPersistedSpellValue(string sid)
    {
        if (MagicBurstModeValue() == "exact")
        {
  return (_magicBurstSpell.Text ?? "").Trim();
        }
        if (_workingProfileBySid.TryGetValue(sid, out var existing)
  && existing.TryGetPropertyValue("spell", out var node)
  && node is not null)
        {
  try
  {
      return (node.GetValue<string>() ?? "").Trim();
  }
  catch
  {
      // Preserve compatibility by falling back to empty when the legacy value is malformed.
  }
        }
        return "";
    }

    private int MagicBurstMaxTierValue()
    {
        return (_magicBurstMaxTier.SelectedItem?.ToString() ?? "Auto") switch
        {
  "I" => 1,
  "II" => 2,
  "III" => 3,
  "IV" => 4,
  "V" => 5,
  _ => 0,
        };
    }

    private static string MagicBurstTierDisplay(int tier)
    {
        return tier switch
        {
  1 => "I",
  2 => "II",
  3 => "III",
  4 => "IV",
  5 => "V",
  _ => "Auto",
        };
    }

    private int MagicBurstFamilyTierLimit()
    {
        if (MagicBurstModeValue() != "auto")
        {
  return 0;
        }
        return MagicBurstFamilyValue() switch
        {
  "helix" => 2,
  "ra" => 3,
  _ => 5,
        };
    }

    private void RefreshMagicBurstTierOptions(int requestedTier)
    {
        var previousSuppress = _suppressEvents;
        _suppressEvents = true;
        try
        {
  var limit = MagicBurstFamilyTierLimit();
  _magicBurstMaxTier.Items.Clear();
  _magicBurstMaxTier.Items.Add("Auto");
  for (var tier = 1; tier <= limit; tier++)
  {
      _magicBurstMaxTier.Items.Add(MagicBurstTierDisplay(tier));
  }
  var normalized = requestedTier <= 0 ? 0 : Math.Min(requestedTier, limit);
  var display = MagicBurstTierDisplay(normalized);
  _magicBurstMaxTier.SelectedItem = display;
  if (_magicBurstMaxTier.SelectedIndex < 0)
  {
      _magicBurstMaxTier.SelectedIndex = 0;
  }
  _magicBurstMaxTier.Enabled = limit > 0;
        }
        finally
        {
  _suppressEvents = previousSuppress;
        }
    }

    private void UpdateMagicBurstTierUi()
    {
        var currentTier = MagicBurstMaxTierValue();
        RefreshMagicBurstTierOptions(currentTier);
    }

    private void ApplyMagicBurstFromSnapshot(JsonElement snapshot)
    {
        _magicBurstEnabled.Checked = SessionStateHelper.GetBool(snapshot, "magic_burst_enabled", false);
        var mode = SessionStateHelper.GetString(snapshot, "magic_burst_mode", "exact").Trim().ToLowerInvariant();
        var family = SessionStateHelper.GetString(snapshot, "magic_burst_family", "spell").Trim().ToLowerInvariant();
        var maxTier = Math.Clamp(SessionStateHelper.GetInt(snapshot, "magic_burst_max_tier", 0), 0, 5);
        if (mode is not ("exact" or "auto"))
        {
  throw new InvalidDataException($"Unsupported magic burst mode '{mode}'.");
        }
        if (family is not ("spell" or "ra" or "helix"))
        {
  throw new InvalidDataException($"Unsupported magic burst family '{family}'.");
        }
        var selected = mode == "auto"
  ? MagicBurstAutoDisplay(family)
  : SessionStateHelper.GetString(snapshot, "spell");
        RefreshMagicBurstSpellOptions(selected);
        RefreshMagicBurstTierOptions(maxTier);
    }
}
