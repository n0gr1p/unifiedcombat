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
```

`activity.json` uses schema version 1. It groups exact main-job/sub-job profile
variants by character and records a SHA-256 checksum for every stored profile
snapshot.

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
4. writes or updates the activity bundle without changing individual UI
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
deployment.

Canonical profile-v2 files are staged with rollback copies. The UI then sends
an acknowledged `profile_v2_reload` request to every active addon session. Each
addon validates and applies its exact canonical file and returns its current
identity plus the post-apply durable diff count. The activity is marked active
only when all sessions report success and zero differences.

If a reload fails, the UI restores the prior canonical files and requests
another reload for the full cohort. The failure remains visible even when
runtime restoration succeeds. Verification failures identify the character/job,
first differing config path, file value, and runtime value. Restoration failures
retain the corresponding per-session details instead of reporting only a count.

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
validation, canonical deployment, rollback, commit, and delete isolation.
