# Profile / UI File Contract Audit

## Scaffolding status

- `T3.7b` added a pure profile validation module and a status contract snapshot helper.
- `T3.7c` wires validation into the existing profile load / reload path and publishes a read-only status snapshot back through the bridge.
- The validation layer is fail-safe: malformed profile trees are rejected on load, and missing validation support is reported without changing save behavior.
- No profile polling or live apply behavior has been implemented.
- The bridge remains the live UI write path for now.

## Current profile/settings model

- Profile files live at `data/profiles/<safe character name>.lua`.
- The file payload is a Lua table returned as `return { version = 1, profiles = { UC = { [MAIN_JOB] = ... } } }`.
- Profiles are keyed by character plus main job; subjob is runtime metadata, not part of the on-disk profile key.
- `UnifiedCombat.lua` loads the profile file on addon load and again on job change / explicit reload.
- `UnifiedCombat.lua` now validates the loaded profile tree before applying it and records the validation outcome in `UC_PROFILE_CONTRACT_STATUS`.
- `UnifiedCombat.lua` writes the profile file through `files.new(path, true)` and `files.write(...)`.
- Write behavior is a direct overwrite; no temp-file rename, no backup file, and no atomic write contract is present today.
- Profile reads are fail-safe: `loadstring/load` is wrapped in `pcall`, and malformed content returns `nil` rather than crashing the addon.

## Current UI / bridge interaction

- `remote_bridge.lua` is the live external UI bridge.
- It sends status snapshots with `op = 'state'` containing `engine`, `Start_Engine`, `char`, `job`, `sub_job`, zone-suspend state, and the read-only `profile_contract_status` snapshot.
- It sends option snapshots with `op = 'options'` containing job-dependent option lists for the external UI plus the same read-only `profile_contract_status` snapshot.
- It accepts `set` messages and writes them into `_G.UC_SETTINGS` through `apply_set(...)`.
- It accepts one-shot runtime commands: `start_engine`, `stop_engine`, `save`, `reload`, `addon_reload`, `request_state`, and `request_options`.
- It uses `cfg_version` monotonic gating for incoming config messages, but it does not do file hashing, file mtime polling, or profile-file change detection.

## Ownership classification

| Field / state | Classification | Notes |
| --- | --- | --- |
| Engine on/off | `command_owned` | Runtime start/stop is a command; `engine_enabled` is persisted today but behaves like a runtime control surface. |
| Current active profile name | `status_output_owned_by_addon` | Derived by addon from character + main job; not a standalone editable file field. |
| Job / main / subjob identity | `status_output_owned_by_addon` | Read-only runtime identity for the UI, with main job also used for profile selection. |
| Combat / defensive / movement / maintenance enable flags | `profile_owned_by_ui` | Long-lived editable settings. |
| Configured abilities | `profile_owned_by_ui` | Long-lived editable settings. |
| Tank flag / tank enmity settings | `profile_owned_by_ui` | Long-lived editable settings. |
| Spell lists | `profile_owned_by_ui` | Long-lived editable settings. |
| Sleep spell order | `profile_owned_by_ui` | UI-owned ordered profile data. |
| COR / GEO / BRD maintenance settings | `profile_owned_by_ui` | Long-lived editable settings. |
| Target / follow / pathing settings | `profile_owned_by_ui` | Long-lived editable settings. |
| Debug flags | `profile_owned_by_ui` | Persisted config/debug toggles; not runtime state. |
| Local ownership flags | `legacy_or_ambiguous` | Local-only manual override file; not part of the editable profile contract. |
| Scheduler action state | `runtime_owned_by_addon` | Transient scheduler runtime state. |
| Pending / lock state | `runtime_owned_by_addon` | Transient runtime state. |
| Current selected action / overlay state | `runtime_owned_by_addon` | Runtime state; if shown to UI, it should be mirrored as status output. |

## Proposed target file contract

### Editable profile file

- One file per character-mainjob-subjob profile family is the desired end state, but the current code is effectively character + main job keyed.
- The editable profile should remain the source of truth for long-lived settings.
- External UI should write the file atomically.
- The addon should read and validate the file.

### Addon status output

- Addon-owned read-only status should cover engine state, loaded profile identity, scheduler/action state summary, current action, and warnings/errors.
- The UI should read status for display only.

### Optional command channel

- One-shot runtime commands should stay separate from profile editing.
- Good candidates: engine start/stop, profile reload, profile switch, addon reload, and save confirmation.

## Hash / polling recommendation

- Full-file hashing is not necessary for ordinary change detection.
- Modified time plus file size is enough for a normal file-watch layer if the UI writes atomically.
- The UI should write via temp file + rename to avoid partial reads.
- If a checksum is needed, use it as a validation step, not the primary detection mechanism.
- Polling should be low-rate and debounced; use a short idle interval and defer apply while combat/action-state is active.
- If the profile changes while the engine is running, validate immediately but defer apply until a safe boundary.

## Safe apply rules

- Safe immediately / next scheduler tick: non-structural profile edits that only affect proposal selection or display, after validation.
- Safe only when engine stopped: changes that can perturb live movement, current target flow, or active scheduler state.
- Safe only after addon reload: schema or migration changes that alter load-time assumptions.
- Unsafe / should stay runtime command: engine start/stop, addon reload, and explicit profile switch.

## Migration plan

1. Audit only.
2. Add profile contract docs.
3. Add read-only status output contract.
4. Add profile validation layer.
5. Define atomic profile writer expectations for the UI.
6. Add low-rate change detection.
7. Define safe live-apply rules.
8. Migrate external UI to file source of truth.
9. Reduce bridge write responsibility to runtime commands and acknowledgements.

## Risks

- The current profile file format is not atomic and can be partially overwritten if external tooling writes unsafely.
- `engine_enabled` is persisted today, so separating runtime control from profile defaults will need careful contract wording.
- The current bridge is still the only live runtime edit path, so migration must avoid breaking the existing UI until file validation is proven.
- `local_ownership_flags.lua` must remain separate from editable profiles.

## Recommended next implementation task

- Next step after this scaffolding: wire read-only status output or integrate validation into the load path, depending on soak results, before moving any external UI write path off the bridge.
