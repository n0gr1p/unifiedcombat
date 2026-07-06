# Active Config Consumer Migration Audit

Task: `T3.7i`, updated by `T3.7k`, `T3.8a`, and `T4.1`

## Scope

This is a docs/static audit only. No runtime behavior, profile load/save behavior, bridge write behavior, scheduler behavior, action selection, movement, targeting, cure, tank, or combat decision code changed.

`T3.7k` audited the active bridge read-only settings consumers after the `T3.7j` migration. It also made no runtime behavior changes and no bridge behavior changes. `T3.7j` live sanity passed before `T3.7k`: addon reload succeeded, no Lua errors were reported, the external UI still connected/loaded, `//uc configstatus export` succeeded, the exported file looked sane, and a short combat loop showed no weirdness.

`T3.8a` adds structured profile/config read compatibility to the pure config normalizer and contract tests only. It does not migrate an active runtime consumer, live profile loading, live profile saving, bridge writes, or scheduler/provider action-decision reads.
`T3.8b` adds an explicit structured export command (`//uc profilev2 export`) that writes a separate v2 artifact for inspection. It does not migrate live profile loading, live profile saving, bridge writes, or scheduler/provider action-decision reads.
`T3.8k` adds a hand-authored UI v2 fixture and consumer-contract tests only. It does not add runtime loading, writing, bridge behavior changes, or scheduler/provider consumer changes.
`T3.8l` publishes the v2 file state summary through the read-only config status export surface as `profile_v2`. It does not add runtime loading, writing, bridge behavior changes, or scheduler/provider consumer changes.
`T4.1` keeps active-profile refresh on startup, the existing v1 load/reload path, and explicit `profilev2 apply/reload`, while avoiding any new generic sync-after-command-mutation behavior. It migrates only a narrow debug-only batch of active runtime readers and documents slash-command durable-write caveats instead of promoting them to active-profile ownership.

## Active runtime entry points

`UnifiedCombat.lua` is the active addon entry point. It initializes `_G.UC_SETTINGS`, profile/config contract status, profile load/save helpers, addon commands, and then loads the active runtime modules.

Active load path inspected:

| Entry point | Active role | Required active modules inspected |
| --- | --- | --- |
| `UnifiedCombat.lua` | Addon bootstrap, defaults, profile load/save, contract status, addon commands | `remote_bridge`, `unified_combat_core`, `unified_engine`, `uc_party_follow`, `uc_pathing`, `uc_config_status_export`, `uc_profile_v2`, `uc_config_normalizer`, `uc_profile_contract` |
| `unified_engine.lua` | Active tick engine and overlay coordinator | `unified_scheduler`, `unified_combat_core` |
| `unified_scheduler.lua` | Active scheduler/provider/action runtime | `unified_combat_core`, `uc_ability_pipeline`, `uc_cor_maintenance`, `uc_settarget`, `uc_attack`, `uc_partner_list`, `uc_fight_leader`, `uc_hb_buff_maint`, `uc_enemy_effect_tracker`, scheduler helper modules |
| `remote_bridge.lua` | Active external UI bridge, read-only state/options snapshots, live bridge writes | `uc_ws_memory`, `uc_ignore`, `uc_partner_list`, `uc_target_ignore`, `uc_add_priority`, `uc_path_hunter` |
| `uc_party_follow.lua` | Active follow/movement support loaded by `UnifiedCombat.lua` | Reads follow/debug settings for follow state |
| `uc_pathing.lua` | Active pathing support loaded by `UnifiedCombat.lua` | Reads path/follow/debug settings |
| `unified_combat_core.lua` | Active shared combat helpers used by engine and scheduler | Reads active settings through a local getter |
| `uc_config_runtime.lua` | Runtime accessor introduced by `T3.7h` and extended by `T3.7j` | Used by legacy `melee_engine.lua` / `dd2_module.lua` UI consumers and active bridge config status publication |
| `uc_config_normalizer.lua` | Pure canonical config normalizer | Used by status building and `uc_config_runtime.lua`; `T3.8a` also accepts structured `settings.config` and direct canonical-domain input |
| `uc_profile_v2.lua` | Pure structured v2 profile helper for export, validate, diff, status inspection, and apply | Used by `UnifiedCombat.lua` explicit `//uc profilev2 export`, `validate`, `diff`, `status`, `apply`, and `reload` commands |
| `uc_profile_v2_export.lua` | Compatibility shim returning `uc_profile_v2.lua` | Preserves existing `require('uc_profile_v2_export')` callers |
| `uc_config_status_export.lua` | Pure status export renderer | Used by `UnifiedCombat.lua` explicit `//uc configstatus export` command |

## T3.7h active-path assessment

`melee_engine.lua` and `dd2_module.lua` do not appear in the active `UnifiedCombat.lua -> unified_engine.lua -> unified_scheduler.lua` require path. A repository-wide require search found the `T3.7h` `uc_config_runtime` calls only in those two files and their static selftest.

Assessment:

| File | Required by active addon flow | Used by current UnifiedCombat runtime | Current classification |
| --- | --- | --- | --- |
| `melee_engine.lua` | No active require found | No evidence in current UC runtime path | `legacy_or_inactive` |
| `dd2_module.lua` | No active require found | No evidence in current UC runtime path | `legacy_or_inactive` |

`T3.7h` still has value because it proved a small migration pattern and test shape for `uc_config_runtime.lua`. It likely provides migration-pattern confidence more than active-runtime confidence.

## Active `_G.UC_SETTINGS` read inventory

| File / function area | Read summary | Risk class | Notes |
| --- | --- | --- | --- |
| `UnifiedCombat.lua` / domain helper globals | Reads engine/domain/follow/combat/movement flags | `moderate_runtime_gating` | Affects active domain participation helpers; avoid as next migration. |
| `UnifiedCombat.lua` / profile helpers | Reads/writes profile/default settings and contract status inputs | `moderate_runtime_gating` | Bound to load/save/apply behavior; avoid until profile contract migration is explicit. |
| `UnifiedCombat.lua` / `uc_update_config_contract_status` and `configstatus export` command | Reads `_G.UC_SETTINGS` only to build compact normalized status | `safe_read_only_status` | Active, diagnostic/status-only, no action behavior. |
| `UnifiedCombat.lua` / addon command handlers | Reads/writes settings for start/stop, fight leader, add priority, sleep commands | `moderate_runtime_gating` | Command-owned or action-related; avoid for first active migration. |
| `remote_bridge.lua` / `send_options_snapshot` and `send_state_snapshot` | Publishes `_G.UC_CONFIG_CONTRACT_STATUS` as read-only bridge fields | `safe_read_only_status` | Active bridge read-only state/options surface. Preferred next candidate. |
| `remote_bridge.lua` / `apply_set` and `process_line` set handlers | Reads/writes `_G.UC_SETTINGS` for live UI changes | `moderate_runtime_gating` | Bridge write contract; explicitly out of scope. |
| `unified_engine.lua` / `get_settings`, scheduler ownership helpers | Reads active settings for tick/domain ownership decisions and overlay gating | `moderate_runtime_gating` | Active engine behavior; not first candidate. |
| `unified_scheduler.lua` / `enemy_dispel_diag`, `enemy_dispel_log` | Reads `debug`, `log_def_sched` for diagnostic logging | `safe_debug_or_ui` | `T4.1` migrated these debug-only gates to `uc_active_config` accessors with flat-value fallback only when the active path is missing. |
| `unified_scheduler.lua` / raw enemy action/message logging | Reads `def_remove_enemy_buffs` with log flag for diagnostic raw enemy logs | `safe_debug_or_ui` | `T4.1` migrated only this diagnostic gate; no scheduler action-decision reads moved. |
| `unified_scheduler.lua` / provider and dispatch paths via context settings | Reads many combat/defensive/maintenance/tank/movement/targeting fields | `high_action_selection_risk` | Avoid until domain parity is broad. |
| `uc_party_follow.lua` / debug logging gate | Reads only `debug` for file logging enablement | `safe_debug_or_ui` | `T4.1` migrated the debug gate only; follow-state reads remain on `_G.UC_SETTINGS`. |
| `uc_party_follow.lua` / status snapshots | Reads follow flags for diagnostic status text | `deferred_legacy_compat` | Deferred because legacy flat follow mutations can still occur outside active-profile refresh paths. |
| `uc_party_follow.lua` / follow tick and packet handling | Reads `party_follow`, leader ids, follow ranges | `high_movement_or_targeting_risk` | Avoid. |
| `uc_pathing.lua` / debug overlay gate | Reads only `debug` for overlay visibility | `safe_debug_or_ui` | `T4.1` migrated only the overlay debug gate; path/follow reads remain on `_G.UC_SETTINGS`. |
| `uc_pathing.lua` / path binding, gating, and follow control | Reads path/follow settings | `high_movement_or_targeting_risk` | Deferred. |
| `unified_combat_core.lua` / `get_settings` | Reads active settings for shared combat helpers | `high_action_selection_risk` | Avoid. |
| `melee_engine.lua`, `dd2_module.lua` | Legacy overlay, ignore, reload/save reads | `legacy_or_inactive` | Not valid next active-runtime candidate. |

## Candidate risk table

| Candidate | Category | Active | Why not/why yes |
| --- | --- | --- | --- |
| Bridge `config_contract_status` publication in `state` and `options` | `safe_read_only_status` | Yes | Best next candidate: active, read-only, compact, already excludes full config/settings. |
| `UnifiedCombat.lua` `configstatus export` command status refresh | `safe_read_only_status` | Yes | Also good, but explicit command path already builds normalized status; bridge publication gives stronger active UI confidence. |
| Scheduler enemy-dispel diagnostic log gating | `safe_debug_or_ui` | Yes | Low behavioral risk, but lives inside scheduler/defensive code; keep second. |
| `uc_party_follow.lua` debug logging reads | `safe_debug_or_ui` | Yes | Low diagnostic risk, but adjacent to movement/follow runtime. |
| Engine scheduler ownership helper reads | `moderate_runtime_gating` | Yes | Affects active domain execution path. |
| Bridge write/set handlers | `moderate_runtime_gating` | Yes | Live UI write contract, explicitly out of scope. |
| Scheduler provider config reads | `high_action_selection_risk` | Yes | Affects ranking/proposal/dispatch. |
| Pathing/follow runtime reads | `high_movement_or_targeting_risk` | Yes | Movement arbitration and targeting-adjacent behavior. |
| `melee_engine.lua` / `dd2_module.lua` overlay reads | `legacy_or_inactive` | No active evidence | Useful as pattern proof only. |

## Recommended next migration candidate

Complete in `T3.7j`: the active bridge read-only `config_contract_status` publication in `remote_bridge.lua` now uses `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)`.

Implemented shape:

- The field name remains `config_contract_status`.
- The bridge gets this field through `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)` in both `send_options_snapshot` and `send_state_snapshot`.
- The accessor returns only the compact status shape and never returns the full normalized config or `_G.UC_SETTINGS`.
- `apply_set(...)`, bridge write semantics, profile load/save behavior, scheduler reads, and export file content remain unchanged.

Why this is active:

- `UnifiedCombat.lua` requires `remote_bridge.lua` during addon bootstrap.
- The bridge state/options snapshots are active UI read paths.
- `config_contract_status` is already present in both state and options snapshots, so the migration can be isolated to how the read-only status is obtained.

Why this is low-risk:

- It is read-only status publication.
- It does not participate in action selection, ranking, movement, targeting, cure/tank/combat decisions, or dispatch.
- It does not expose the full normalized config or `_G.UC_SETTINGS`.
- It can be tested by asserting the bridge snapshot still includes the same compact status table fields and excludes full config/settings.

## T3.7k bridge read-only follow-up audit

`T3.7k` added `docs/bridge_readonly_config_consumer_audit.md` and classified the active bridge read surface.

Result:

- The bridge `state` and `options` snapshots have no remaining low-risk read-only settings publication comparable to `config_contract_status`.
- Remaining bridge option fields are derived player/job/party option lists used by the UI edit protocol, not durable config values.
- `Start_Engine` is command state, not canonical config.
- `profile_contract_status` remains addon-owned profile status.
- `config_contract_status` is already migrated and should remain compact/read-only.
- `set`, `apply_set(...)`, `cfg_version`, runtime commands, profile load/save triggers, and all current flat-key edit/echo paths must not migrate yet.

Recommended next step after `T3.7k`: pause bridge migration for now. If another active config read migration is desired, use a narrow non-bridge diagnostic candidate such as `unified_scheduler.lua` `enemy_dispel_diag(msg)` / `enemy_dispel_log(msg)`, migrating only their `debug` / `log_def_sched` diagnostic gates through focused accessors. `T4.1` completes that conservative scheduler-debug slice and extends the same pattern to the `uc_party_follow.lua` file-log gate and the `uc_pathing.lua` debug-overlay gate. Scheduler/provider action-decision reads remain deferred.

After `T3.8a`, another safe profile/config migration path is to wire structured v2 read compatibility into the live profile load path in fail-safe/read-only mode, or add a generated v2 fixture before live wiring. Bridge write behavior and scheduler/provider action-decision reads should remain unchanged.

## Follow-up files and functions

Touched by `T3.7j`:

- `uc_config_runtime.lua`: added compact status accessor.
- `remote_bridge.lua`: migrated `send_options_snapshot` and `send_state_snapshot`.
- `tests/replay/harness/selftest_bridge_config_status_consumer.lua`: added focused parity coverage.
- `tests/replay/harness/selftest_config_status.lua`: updated bridge source assertion.
- `tests/replay/harness/selftest_all_replay_fixtures.lua`: registered focused selftest.

Touched by `T4.1`:

- `unified_scheduler.lua`: migrated only diagnostic `debug`, `log_def_sched`, and `def_remove_enemy_buffs` gates to `uc_active_config` accessors.
- `uc_party_follow.lua`: migrated only the file-log debug gate to `uc_active_config`.
- `uc_pathing.lua`: migrated only the debug-overlay visibility gate to `uc_active_config`.
- `tests/replay/harness/selftest_active_config_consumer_migration.lua`: added focused static coverage for migrated readers and the no-generic-command-sync rule.
- `tests/replay/harness/selftest_all_replay_fixtures.lua`: registered the focused migration selftest.

## Proposed parity tests

Implemented in `T3.7j`:

- Assert bridge publication uses `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)`.
- Assert bridge no longer publishes the field through direct `_G.UC_CONFIG_CONTRACT_STATUS` coupling.
- Assert compact status fields and representative values are preserved.
- Assert status arrays are cloned.
- Assert missing/unavailable normalizer status remains compact and reports unavailable.
- Assert bridge source still preserves `cfg_version` and `apply_set(...)` write behavior.
- Assert bridge/export do not expose full normalized config or `_G.UC_SETTINGS`.
- Assert scheduler/provider code does not require `uc_config_runtime`.
- Assert the debug-only migrated readers use `uc_active_config` accessors in `unified_scheduler.lua`, `uc_party_follow.lua`, and `uc_pathing.lua`.
- Assert addon command handlers do not introduce a generic active-profile sync after arbitrary flat setting mutation.

## Domains not recommended yet

Do not select these domains for the next migration:

- combat proposal selection
- tank behavior
- defensive/cure logic
- movement/follow/pathing
- targeting
- sleep action selection
- maintenance action selection
- WS/JA/spell dispatch selection
- scheduler/provider action-decision reads
- bridge write behavior
- profile load/save behavior

## T4.1 slash-command mutation classification

`UnifiedCombat.lua` slash-command handlers were re-checked with the active-profile ownership model in mind.

| Command surface | Current write behavior | Classification | T4.1 handling |
| --- | --- | --- | --- |
| `//uc start`, `//uc stop` | Mutate runtime `Start_Engine` and mirror `engine_enabled` in `_G.UC_SETTINGS` | `runtime_owned_toggle` | Keep as command-owned runtime state; do not treat as durable active-profile editing. |
| `//uc save`, `//uc reload` | Persist/load existing v1 profile file | `existing_profile_path` | Keep existing v1 sync path that refreshes `_G.UC_ACTIVE_PROFILE` from loaded flat settings. |
| `//uc profilev2 apply`, `//uc profilev2 reload` | Validate UI-owned v2 file, publish `_G.UC_ACTIVE_PROFILE`, then project back into `_G.UC_SETTINGS` | `explicit_ui_file_consume_path` | Keep as the explicit structured consume/apply path. |
| `//uc configstatus export`, `//uc profilev2 validate`, `diff`, `status`, `export` | Read-only/export commands | `read_only_or_export` | No active-profile ownership change. |
| `//uc fight_leader ...` | Mutates flat follow settings directly | `legacy_compat_durable_write` | Leave behavior unchanged for compatibility; do not sync arbitrary command writes into `_G.UC_ACTIVE_PROFILE`. |
| `//uc add_priority ...` | Mutates flat targeting settings directly | `legacy_compat_durable_write` | Leave behavior unchanged for compatibility; do not sync arbitrary command writes into `_G.UC_ACTIVE_PROFILE`. |
| `//uc sleep ...` | Mutates flat sleep settings directly | `legacy_compat_durable_write` | Leave behavior unchanged for compatibility; do not sync arbitrary command writes into `_G.UC_ACTIVE_PROFILE`. |

Active-profile refresh paths after `T4.1` are still limited to:

- addon startup initialization from flat settings
- existing v1 load/reload paths
- explicit `profilev2 apply`
- explicit `profilev2 reload`

Deferred because they could go stale behind legacy flat-only mutations:

- follow-domain status text in `uc_party_follow.lua`
- path/follow/movement control reads in `uc_pathing.lua`
- slash-command-owned flat durable writes such as `fight_leader`, `add_priority`, and `sleep`
