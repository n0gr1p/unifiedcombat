# Activity Profiles

## Purpose

Activity profiles let the WinForms UI capture and apply a coordinated set of
durable profile-v2 configurations across every currently connected
UnifiedCombat session. Activity selection is global to the UI; it is not a
per-session setting.

## In-game commands

With the updated WinForms UI running and connected, use:

- `//uc activity list` to list saved activity names.
- `//uc activity <name>` to apply a saved activity (case-insensitive exact name).
- `//uc activity apply <name>` for the explicit form, including an activity named `list`.

Names may contain spaces. The command applies globally to all matching connected
character/job sessions, just like the UI's Apply Activity button, without a
confirmation dialog. Running engines receive the configuration immediately;
already-issued actions are not cancelled. Unmatched sessions remain unchanged.
Success, unmatched counts, and failures are reported to the requesting game's chat.
Concurrent activity operations are rejected; retry after the current operation
finishes. The existing deployment validation and rollback process is shared with
the UI button. A disconnected UI produces an error; requests are not queued for
later application. Restart the rebuilt UI and reload the addon to enable this command.

## Storage

The UI owns activity bundles under:

```text
data/activity_profiles/<activity-id>/
  activity.json
  profiles/<safe-character>_<MAIN_JOB>_<SUB_JOB>.lua
  ui_profiles/<safe-character>_<MAIN_JOB>_<SUB_JOB>.json
```

`activity.json` uses schema version 2. It groups exact main-job/sub-job profile
variants by character and records SHA-256 checksums for both the canonical
Profile V2 snapshot and its bundle-local editor snapshot. The `ui_profiles`
directory is explicit activity import/export data only; it is never deployed
to the normal per-identity UI storage path and is never an automatic config
source.

An activity can retain multiple job variants for the same character. Updating
an activity replaces the variants for the currently connected job
combinations and retains the character's other stored variants. Deleting an
activity removes only its bundle; it does not delete the canonical
`data/profiles_v2` files.

## Capture behavior

Create and Update operate on the complete active-session cohort. The UI:

1. captures the selected session's current working form state;
2. resolves every other connected session from transient working state or its
   runtime active-config snapshot;
3. builds a structured profile-v2 snapshot for every exact
   character/main-job/sub-job identity;
4. stores the corresponding flat UI state for every identity; and
5. writes or updates the activity bundle without changing individual UI
   profiles or canonical profile-v2 files used by the live addons.

Missing, malformed, or duplicate active identities stop capture with an
explicit error. Runtime state such as engine running state, targets, pending
actions, locks, and camp coordinates remains outside activity snapshots because
the structured profile-v2 writer already excludes those fields.

Working editor profiles are in-memory and keyed by session. Historical
`data/ui_profiles/*.json` files are not loaded or migrated by the normal editor
lifecycle.

## Activation behavior

Selecting an activity from the global dropdown only selects it for inspection,
Update, Delete, or Apply. It does not change any session. **Apply Activity**
activates the selected activity against a snapshot of all sessions active at
that moment. Running engines do not block activation. When one or more matching
sessions have running engines, the confirmation warns that configuration
changes take effect immediately and already-issued actions are not cancelled.

Activation applies every exact stored character/main-job/sub-job variant that
matches an active session. Active identities without a variant are left
completely unchanged and are reported in a warning after activation. Missing
variants are normal; a zero-match activation still establishes the selected
activity as the current context without deploying files or requesting reloads.
Offline characters stored in the activity do not block activation. Duplicate
live identities still stop activation. A missing, malformed, checksum-invalid,
or legacy matching variant blocks activation before deployment. A
schema-version-1 variant remains selectable for Update and Delete, but it cannot
be applied until that exact character/job is recaptured with Update so the
required UI snapshot exists.

Canonical Profile V2 files are staged with rollback copies for the matched
sessions only. Bundle-local editor snapshots are copied into transient working
state after a successful apply; they are not deployed as per-identity files.
The UI then sends an acknowledged
`profile_v2_reload` request to each matched addon session. Each addon validates
and applies its exact canonical file and returns its current identity plus the
post-apply durable diff count. The activity is marked active only when all
matched sessions report success and zero differences. After success, matched
working profiles are replaced in memory with the applied bundle snapshots and
the selected editor refreshes immediately.

If a reload fails, the UI restores the prior canonical files and requests
another reload for the matched cohort. Unmatched sessions are not part
of deployment or rollback. The failure remains visible even
when runtime restoration succeeds. Verification failures identify the
character/job, first differing config path, file value, and runtime value.
Restoration failures retain the corresponding per-session details instead of
reporting only a count.

## Activity provenance

While an activity is current, the active-session list derives provenance from
each session's exact character/main-job/sub-job identity and the manifest hash
for its saved canonical profile-v2. The canonical comparison excludes
runtime-owned and UI-option-list fields while activity deployment and checksum
validation continue to keep the UI and profile-v2 snapshots paired:

* `[Activity Name]` means the current saved profile exactly matches the stored
  activity variant.
* `[Activity Name-mod]` means the identity is in that activity context but its
  saved profile differs from the stored variant.
* `[No Match]` means the activity contains no exact variant for the identity.

Unsaved form edits do not affect provenance. An individually saved unmatched
identity becomes `[Activity Name-mod]`. Saving unchanged matching content stays
exact, changed saved content becomes modified, and restoring the exact content
returns it to exact. Update retains unrelated stored variants, captures all
current active identities, and recomputes their provenance against the updated
manifest. Job/subjob changes and reconnects are classified by exact identity,
not by the prior session id. The global activity status reports matched,
modified, and no-match counts.

## Verification

Run the activity storage and deployment tests with:

```powershell
dotnet run --project .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Debug --no-build -- --selftest-activity-profiles
```

The test covers multi-job retention, exact live-job selection, partial and
zero-match activation, unmatched-session isolation, duplicate live identities,
checksum validation, synchronized canonical/UI deployment, provenance
transitions, identity changes and reconnects, legacy-variant upgrade, matched
rollback, commit, and delete isolation.
