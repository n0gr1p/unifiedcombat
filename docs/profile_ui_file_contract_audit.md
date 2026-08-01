# Profile / UI File Contract Audit

## Scaffolding status

- `T3.7b` added a pure profile validation module and a status contract snapshot helper.
- `T3.7c` wires validation into the existing profile load / reload path and publishes a read-only status snapshot back through the bridge.
- `T3.7d` starts canonical config object planning as a docs/static audit only.
- `T3.7e` adds a pure canonical config normalizer over the current flat settings/profile table.
- `T3.7f` exposes a compact read-only normalized config status snapshot through the addon and bridge.
- `T3.7g` adds a manual diagnostic export command for the compact normalized config status.
- `T3.7h` migrates the first low-risk read-only UI consumer: legacy in-game overlay visibility now reads canonical `config.ui.show_ingame_ui` through a runtime accessor.
- `T3.7i` audits active config consumers and finds the `T3.7h` files are likely legacy/orphaned in the current UnifiedCombat runtime, so that slice proves the migration pattern more than active runtime behavior.
- `T3.7j` migrates the active bridge read-only `config_contract_status` publication to `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)`, making it the first active runtime read-path migration.
- `T3.7k` audits remaining active bridge read-only settings consumers and recommends pausing bridge migration for now because the remaining bridge setting-touching paths are edit/write protocol, command state, or derived option/status data. No runtime behavior or bridge behavior changed, and `T3.7j` live sanity passed before the audit.
- `T3.8a` adds pure read compatibility for a future structured v2 profile/config payload through `uc_config_normalizer.lua` and a direct contract helper. The supported shape is documented in `docs/profile_v2_structured_config_shape.md`.
- `T3.8b` adds `//uc profilev2 export`, an explicit command-only structured export path that writes `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua` without changing the live v1 profile file contract.
- `T3.8g` keeps that export path manual-only as a migration/bootstrap seed utility, resolves it under `windower.addon_path` in live Windower, and reports terse failure reasons in chat.
- `T3.8i` renames the structured v2 helper implementation to `uc_profile_v2.lua` and keeps `uc_profile_v2_export.lua` as a compatibility shim, without changing any profile command behavior or file ownership.
- `T3.8j` adds read-only `//uc profilev2 status` plus reload-oriented `//uc profilev2 reload` semantics while keeping the addon in a consumer role for the UI-owned v2 file.
- `T3.8k` adds a hand-authored UI v2 fixture and consumer-contract tests proving validate/status/diff/reload helpers accept UI-owned files without requiring addon-export-only metadata.
- `T3.8l` publishes the read-only v2 file status through the compact config status export payload as `profile_v2`, without changing bridge write behavior or any scheduler/provider action-decision reads.
- `T4.1` migrates a low-risk debug-only runtime reader batch to `uc_active_config` accessors, classifies remaining slash-command durable writes as legacy compatibility behavior, and keeps active-profile refresh limited to startup/load/reload/apply paths.
- The validation layer is fail-safe: malformed profile trees are rejected on load, and missing validation support is reported without changing save behavior.
- No profile polling or live apply behavior has been implemented.
- The bridge remains the live UI write path for now.
- No profile file migration, bridge write migration, scheduler/provider config migration, or runtime action-decision config authority has been implemented yet.

## Current profile/settings model

- Profile files live at `data/profiles/<safe character name>.lua`.
- The file payload is a Lua table returned as `return { version = 1, profiles = { UC = { [MAIN_JOB] = ... } } }`.
- The explicit structured export writes `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua` as `return { version = 2, profile = {...}, config = {...} }`.
- The export metadata may also include `profile_key` when the current character/job identity is available.
- UI-authored v2 files may use generic metadata such as `profile.source = "ui"` and may omit addon-export-specific metadata like `exported_at` and `profile_key`.
- Structured v2 payloads are read-compatible at the pure normalizer/contract-test layer only; the live file reader still extracts v1 `profiles` trees and does not apply v2 payloads.
- Profiles are keyed by character plus main job; subjob is runtime metadata, not part of the on-disk profile key.
- `UnifiedCombat.lua` loads the profile file on addon load and again on job change / explicit reload.
- `UnifiedCombat.lua` now validates the loaded profile tree before applying it and records the validation outcome in `UC_PROFILE_CONTRACT_STATUS`.
- `UnifiedCombat.lua` writes the profile file through `files.new(path, true)` and `files.write(...)`.
- Write behavior is a direct overwrite; no temp-file rename, no backup file, and no atomic write contract is present today.
- Profile reads are fail-safe: `loadstring/load` is wrapped in `pcall`, and malformed content returns `nil` rather than crashing the addon.

## Current UI / bridge interaction

- `remote_bridge.lua` is the live external UI bridge.
- It sends status snapshots with `op = 'state'` containing `engine`, `Start_Engine`, `char`, `job`, `sub_job`, zone-suspend state, and the read-only `profile_contract_status` snapshot.
- It sends status snapshots with the read-only `config_contract_status` snapshot through the config runtime accessor. This is a compact normalized config summary and does not include the full normalized config table.
- It sends option snapshots with `op = 'options'` containing job-dependent option lists for the external UI plus the same read-only `profile_contract_status` and accessor-backed `config_contract_status` snapshots.
- It accepts `set` messages and writes them into `_G.UC_SETTINGS` through `apply_set(...)`.
- It accepts one-shot runtime commands: `start_engine`, `stop_engine`, `save`, `reload`, `addon_reload`, `request_state`, and `request_options`.
- The addon command `//uc configstatus export` writes the compact normalized config status to `data/status/<safe_character>_config_contract_status.lua` as a Lua-table diagnostic file.
- The addon command `//uc profilev2 export` writes the structured v2 profile artifact to `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua` as a Lua-table manual migration/bootstrap seed file.
- The addon command `//uc profilev2 validate` reads that same structured v2 profile artifact and validates it in dry-run mode only.
- The addon command `//uc profilev2 diff` reads and validates that same structured v2 profile artifact, then compares only its durable `config` domains against the current normalized runtime config in dry-run mode.
- The addon command `//uc profilev2 diff detail` reads and validates that same structured v2 profile artifact, then prints the first few structured diff entries with path, file-side value, runtime-side value, and value types so the exact remaining mismatch is visible.
- The addon command `//uc profilev2 status` reads and validates that same structured v2 profile artifact when possible, compares only its durable `config` domains against the current runtime config, and reports a terse read-only summary.
- The addon command `//uc profilev2 apply` reads and validates that same structured v2 profile artifact, builds a verified candidate flat runtime settings table from its durable `config` domains, and then applies that candidate to `_G.UC_SETTINGS` in place without saving to disk.
- The addon command `//uc profilev2 reload` reuses that same verified apply path and safe in-place mutation behavior, but reports reload-oriented chat.
- The durable reload/apply projection intentionally ignores the legacy compatibility mirrors that the live normalizer reconstructs after reload: `abilities.legacy_slots`, `follow.party.leader_id`, `follow.fight.leader_id`, `targeting.legacy_slots`, `targeting.add_priority_names`, and the legacy `sleep` mirrors (`sleep`, `sleepspells`, `sleepspell`) so UI-authored files can omit them without tripping conversion mismatch checks.
- Consumer-contract tests now cover a hand-authored UI fixture file, not just addon-exported bootstrap files.
- The config status export now carries `profile_v2` with the v2 file state summary so the UI can distinguish missing, invalid, valid-match, valid-diff, and error outcomes from the existing read-only status surface.
- The config status export is explicit-command-only; it is not written during bridge state requests, scheduler ticks, profile polling, or combat updates.
- The structured v2 profile export is explicit-command-only; it is not written during bridge state requests, scheduler ticks, profile polling, or combat updates.
- The structured v2 profile export is not the normal v2 profile save/edit path. External UI/tooling owns normal v2 profile writes; the addon consumes v2 files through validate/diff/apply/reload-style commands.
- The structured v2 profile validation is explicit-command-only; it does not apply config to runtime, does not mutate `_G.UC_SETTINGS`, and does not write anything back to disk.
- The structured v2 profile diff is explicit-command-only; it does not apply config to runtime, does not mutate `_G.UC_SETTINGS`, and does not write anything back to disk.
- The structured v2 profile status is explicit-command-only; it does not apply config to runtime, does not mutate `_G.UC_SETTINGS`, and does not write anything back to disk.
- The structured v2 profile apply is explicit-command-only; it does not save v1 profiles, does not write v2 files, and does not change bridge write behavior.
- The structured v2 profile reload is explicit-command-only; it reuses the same safe apply path as `profilev2 apply` and still does not save v1 profiles, write v2 files, or change bridge write behavior.
- The config status export excludes the full normalized config table, `_G.UC_SETTINGS`, scheduler state, pending/lock state, target data, party data, and mob snapshots.
- The config status export uses the existing `files.new(path, true)` / `files.write(...)` helper style and is best-effort diagnostic output, not an atomic profile-write contract.
- The structured v2 profile export now uses a best-effort temp-write in the target directory and promotes the temp file only after a successful close.
- The structured v2 profile export now resolves through `windower.addon_path` in live Windower, creates only `data/profiles_v2` when missing, and reports failures as `UC profile v2 export failed: <short reason>`.
- The WinForms UI save action now writes the durable structured v2 profile artifact directly to `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua` without depending on addon export.
- The UI writer keeps runtime/session-only and legacy command-mutated fields out of the durable file, including `fight_leader`, `fight_leader_id`, `add_priority_names`, `sleep`, `sleepspells`, `sleepspell`, the pathing runtime mirror `path_file_name`, and the engine runtime mirror `command.engine_enabled_default`.
- When the final v2 file already exists, the export helper uses a best-effort backup/promote/restore flow because plain Windows/Lua rename does not guarantee overwrite of an existing target.
- The structured v2 profile export still does not change the live v1 save contract.
- Legacy in-game overlay visibility now reads `config.ui.show_ingame_ui` for display only; it does not change bridge write behavior, profile save behavior, or scheduler/provider action decisions.
- The active bridge config-status consumer now uses the config runtime accessor with no bridge write or profile file behavior changes.
- `_G.UC_ACTIVE_PROFILE` is refreshed only on startup initialization, the existing v1 load/reload path, and explicit `profilev2 apply/reload`.
- UI-owned durable config changes should flow through the profile file plus `profilev2 reload`, not through arbitrary addon-side durable setting mutation.
- Existing slash-command durable setting writes remain legacy compatibility behavior unless they are explicitly runtime-owned toggles/state.
- `T3.7k` found no further safe active bridge read-only settings publication to migrate next; bridge write/edit protocol fields, `set`, `apply_set(...)`, `cfg_version`, runtime commands, and profile load/save triggers remain protected.
- It uses `cfg_version` monotonic gating for incoming config messages, but it does not do file hashing, file mtime polling, or profile-file change detection.

## Ownership classification

| Field / state | Classification | Notes |
| --- | --- | --- |
| Engine on/off | `command_owned` | Runtime start/stop is a command; `engine_enabled` is runtime state and `command.engine_enabled_default` is a compatibility mirror, not durable profile config. |
| Current active profile name | `status_output_owned_by_addon` | Derived by addon from character + main job; not a standalone editable file field. |
| Job / main / subjob identity | `status_output_owned_by_addon` | Read-only runtime identity for the UI, with main job also used for profile selection. |
| Combat / defensive / movement / maintenance enable flags | `profile_owned_by_ui` | Long-lived editable settings. |
| Configured abilities | `profile_owned_by_ui` | Long-lived editable settings. |
| Tank flag / tank enmity settings | `profile_owned_by_ui` | Long-lived editable settings. |
| Spell lists | `profile_owned_by_ui` | Long-lived editable settings. |
| Sleep spell order | `profile_owned_by_ui` | UI-owned ordered profile data. |
| COR / GEO / BRD maintenance settings | `profile_owned_by_ui` | Long-lived editable settings. |
| Target / follow / pathing settings | `profile_owned_by_ui` | Long-lived editable settings, except the current selected path filename (`path_file_name`) which is runtime/session state. |
| Debug flags | `profile_owned_by_ui` | Persisted config/debug toggles; not runtime state. |
| Slash-command durable edits such as `fight_leader`, `sleep`, `add_priority` | `legacy_compat_durable_write` | Still mutate `_G.UC_SETTINGS` today for compatibility, but are not the long-term profile ownership model. |
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
- A future canonical config object should be built from the validated profile/settings shape, but compatibility with the current flat keys should be preserved until read compatibility is proven. `T3.7h` only migrates read-only legacy overlay visibility to `config.ui.show_ingame_ui`; runtime action decisions still use `_G.UC_SETTINGS`.

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
5. Audit canonical config object shape and migration plan.
6. Add a pure config normalizer module with no runtime caller migration.
7. Define atomic profile writer expectations for the UI.
8. Add low-rate change detection.
9. Define safe live-apply rules.
10. Migrate external UI to file source of truth.
11. Reduce bridge write responsibility to runtime commands and acknowledgements.

## Risks

- The current profile file format is not atomic and can be partially overwritten if external tooling writes unsafely.
- `engine_enabled` is persisted today, so separating runtime control from profile defaults will need careful contract wording.
- The current bridge is still the only live runtime edit path, so migration must avoid breaking the existing UI until file validation is proven.
- `local_ownership_flags.lua` must remain separate from editable profiles.
- A canonical config object can reduce Lua 5.1 local/register pressure only if callers keep configuration grouped by domain rather than unpacking the entire object into locals.

## Recommended next implementation task

- Next step after `T3.8a`: wire structured read compatibility into the live profile load path in fail-safe/read-only mode, or add a sample/generated v2 profile fixture first. Profile save format stays unchanged, bridge write behavior stays unchanged, bridge payload shape stays unchanged, scheduler/provider action-decision reads are not migrated, and `_G.UC_SETTINGS` remains the action-decision source object until later migration work is proven.
