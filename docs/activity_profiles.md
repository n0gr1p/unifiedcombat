# Activity Profiles

## Purpose

Activity profiles let the WinForms UI capture and apply a coordinated set of
durable profile-v2 configurations across every currently connected
UnifiedCombat session. Activity selection is global to the UI; it is not a
per-session setting.

## Storage

The UI owns activity bundles under:

```text
data/activity_profiles/<activity-id>/
  activity.json
  profiles/<safe-character>_<MAIN_JOB>_<SUB_JOB>.lua
  ui_profiles/<safe-character>_<MAIN_JOB>_<SUB_JOB>.json
```

`activity.json` uses schema version 2. It groups exact main-job/sub-job profile
variants by character and records SHA-256 checksums for both the addon profile
and UI snapshot.

An activity can retain multiple job variants for the same character. Updating
an activity replaces the variants for the currently connected job
combinations and retains the character's other stored variants. Deleting an
activity removes only its bundle; it does not delete the canonical
`data/profiles_v2` files.

## Capture behavior

Create and Update operate on the complete active-session cohort. The UI:

1. captures the selected session's current working form state;
2. resolves every other connected session's exact individual UI profile;
3. builds a structured profile-v2 snapshot for every exact
   character/main-job/sub-job identity;
4. stores the corresponding flat UI state for every identity; and
5. writes or updates the activity bundle without changing individual UI
   profiles or canonical profile-v2 files used by the live addons.

Missing, malformed, or duplicate active identities stop capture with an
explicit error. Runtime state such as engine running state, targets, pending
actions, locks, and camp coordinates remains outside activity snapshots because
the structured profile-v2 writer already excludes those fields.

The UI's auxiliary JSON working profiles are also keyed by exact
character/main-job/sub-job identity. On first access, an older
character/main-job JSON file is copied once into the exact path so existing UI
profiles can migrate without combining future subjob edits.

## Activation behavior

Selecting an activity from the global dropdown only selects it for inspection,
Update, Delete, or Apply. It does not change any session. **Apply to all
sessions** activates the selected activity against a snapshot of all sessions
active at that moment. Running engines do not block activation. When one or
more engines are running, the confirmation warns that configuration changes
take effect immediately and already-issued actions are not cancelled.

Activation requires one exact stored variant for every active
character/main-job/sub-job identity. Offline characters stored in the activity
do not block activation. An unsupported active job, duplicate identity,
missing snapshot, or checksum mismatch blocks the entire cohort before profile
deployment. A schema-version-1 variant remains selectable for Update and Delete,
but it cannot be applied until that exact character/job is recaptured with
Update so the required UI snapshot exists.

Canonical profile-v2 files and exact-job UI JSON files are staged together with
rollback copies. The UI then sends an acknowledged `profile_v2_reload` request
to every active addon session. Each addon validates and applies its exact
canonical file and returns its current identity plus the post-apply durable diff
count. The activity is marked active only when all sessions report success and
zero differences. After success, cached working profiles are discarded and the
selected editor reloads the applied UI snapshot immediately.

If a reload fails, the UI restores both the prior canonical and UI files and
requests another reload for the full cohort. The failure remains visible even
when runtime restoration succeeds. Verification failures identify the
character/job, first differing config path, file value, and runtime value.
Restoration failures retain the corresponding per-session details instead of
reporting only a count.

The activation is one-shot. A newly connected session or a job change after a
successful activation is shown as requiring Apply again; it is not silently
modified.

## Verification

Run the activity storage and deployment tests with:

```powershell
dotnet run --project .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Debug --no-build -- --selftest-activity-profiles
```

The test covers multi-job retention, exact live-job selection, global cohort
coverage, rejection of unsupported or duplicate live identities, checksum
validation, synchronized canonical/UI deployment, legacy-variant upgrade,
rollback, commit, and delete isolation.
