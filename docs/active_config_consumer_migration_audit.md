# Active Config Consumer Migration Audit

> Historical migration snapshot. Its compatibility-marker descriptions are
> superseded by the Phase 6 exit audit in `../RFC/`.

Task: `T3.7i`, updated by `T3.7k`, `T3.8a`, `T4.1`, `T4.2`, `T4.3`, `T4.4`, `T4.5`, and `T4.6`

## Scope

This audit tracks the staged active-config consumer migration.

- `T3.7k`, `T3.8a`, `T3.8b`, `T3.8k`, and `T3.8l` were docs/test/read-only status milestones.
- `T4.1` changed only a conservative debug-reader batch.
- `T4.2` changes runtime follow/path reader code in `uc_party_follow.lua` and `uc_pathing.lua`, but does not change profile load/save behavior, bridge write behavior, scheduler/provider action-decision behavior, addon command behavior, or any generic sync-after-mutation path.
- `T4.3` changes a bounded defensive/maintenance/spell-related durable-reader batch in `uc_hb_buff_maint.lua`, `uc_cor_maintenance.lua`, and `unified_scheduler.lua`, while preserving flat/default fallback when active paths are missing and still deferring command-owned legacy settings such as `sleep`, `fight_leader`, and `add_priority`.
- `T4.4` adds a small scheduler-facing active-config reader facade in `uc_scheduler_config.lua` and routes a bounded combat/target/tank scheduler slice through it, while preserving flat/default fallback when active paths are missing and still deferring command-owned legacy settings such as `sleep`, `fight_leader`, and `add_priority`.
- `T4.5` adds a small read-only runtime override facade in `uc_runtime_overrides.lua` for legacy command-mutated settings. It moves bounded `fight_leader`, `fight_leader_id`, `add_priority`, and `sleep` readers away from direct flat-key reads where safe, while preserving current slash-command behavior and explicitly avoiding any `_G.UC_ACTIVE_PROFILE` mutation or profile-file write path.
- `T4.6` closes the remaining safe runtime-override reader gap in the addon command display path. `//uc sleep` status/list output now reads through `uc_runtime_overrides.lua`, while command and bridge write ownership remain on the flat compatibility keys.

`T3.7k` audited the active bridge read-only settings consumers after the `T3.7j` migration. It also made no runtime behavior changes and no bridge behavior changes. `T3.7j` live sanity passed before `T3.7k`: addon reload succeeded, no Lua errors were reported, the external UI still connected/loaded, `//uc configstatus export` succeeded, the exported file looked sane, and a short combat loop showed no weirdness.

`T3.8a` adds structured profile/config read compatibility to the pure config normalizer and contract tests only. It does not migrate an active runtime consumer, live profile loading, live profile saving, bridge writes, or scheduler/provider action-decision reads.
`T3.8b` adds an explicit structured export command (`//uc profilev2 export`) that writes a separate v2 artifact for inspection. It does not migrate live profile loading, live profile saving, bridge writes, or scheduler/provider action-decision reads.
`T3.8k` adds a hand-authored UI v2 fixture and consumer-contract tests only. It does not add runtime loading, writing, bridge behavior changes, or scheduler/provider consumer changes.
`T3.8l` publishes the v2 file state summary through the read-only config status export surface as `profile_v2`. It does not add runtime loading, writing, bridge behavior changes, or scheduler/provider consumer changes.
`T4.1` keeps active-profile refresh on startup, the existing v1 load/reload path, and explicit `profilev2 apply/reload`, while avoiding any new generic sync-after-command-mutation behavior. It migrates only a narrow debug-only batch of active runtime readers and documents slash-command durable-write caveats instead of promoting them to active-profile ownership.
`T4.2` migrates a second runtime batch of durable follow/path readers. Those readers now prefer `uc_active_config` accessors and preserve the prior flat/default behavior only when the active path is missing. `T4.2` does not add startup v2 autoload, file watching/polling, addon-driven durable writes, generic active-profile sync after arbitrary mutation, or scheduler/provider action-decision migration.
`T4.3` migrates a third active runtime batch: defensive buff maintenance readers in `uc_hb_buff_maint.lua`, COR maintenance readers in `uc_cor_maintenance.lua`, and a bounded set of defensive/maintenance/spell-related durable readers in `unified_scheduler.lua`. Those readers now prefer structured `config.defensive.*` / `config.maintenance.cor.*` / `config.ownership.*` values and preserve the prior flat/default behavior only when the active path is missing. `T4.3` does not add startup v2 autoload, file watching/polling, addon-driven durable writes, or generic active-profile sync after arbitrary command mutation.
`T4.4` adds `uc_scheduler_config.lua` so `unified_scheduler.lua` can keep consuming active-config-first durable readers without pushing more top-level locals into the scheduler file. It migrates a bounded scheduler/provider-adjacent combat/target/tank slice: combat dark-launch ownership gates, autotarget/prime/tank-mode reads, tank enmity action reads, and nearby scheduler debug-log gates now prefer structured `config.debug.*`, `config.combat.*`, `config.ownership.scheduler_dark_launch_combat`, and `config.tank.*` values while preserving the prior flat/default behavior only when the active path is missing.
`T4.5` keeps the slash-command write surfaces on `_G.UC_SETTINGS`, but routes safe runtime consumers through `uc_runtime_overrides.lua`. That facade treats the command-mutated flat keys as explicit runtime/legacy overrides, falls back to structured active config only when those override keys are absent, and never performs generic sync, active-profile mutation, or profile-file writes.
`T4.6` confirms there were no remaining safe durable-config reader migrations left after `T4.5`. The only additional safe live read still bypassing the facades was the `//uc sleep` command display helper, so that helper now also reads through `uc_runtime_overrides.lua`.

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
| `unified_scheduler.lua` / defensive and maintenance durable reader slice | Reads bounded defensive cure thresholds/toggles, provider selection, overwrite interval, enemy-buff removal toggle, and defensive/maintenance dark-launch toggles | `migrated_active_config_reader` | `T4.3` now prefers `config.defensive.*` and `config.ownership.*` for this bounded batch, with flat/default fallback when the active path is missing. Sleep, fight-leader, broader combat/tank/targeting reads, and live runtime state remain deferred. |
| `unified_scheduler.lua` / bounded combat target tank scheduler slice | Reads combat dark-launch ownership gates, autotarget/prime/tank-mode reads, and nearby scheduler debug-log gates | `migrated_active_config_reader` | `T4.4` routes these reads through `uc_scheduler_config.lua`, so the scheduler now prefers structured `config.debug.*`, `config.combat.*`, `config.ownership.scheduler_dark_launch_combat`, and `config.tank.*` values with flat/default fallback when the active path is missing. |
| `unified_scheduler.lua` / bounded runtime-override reader slice | Reads `sleep`, `sleep` spell list, `fight_leader`, and `fight_leader_id` through `uc_runtime_overrides.lua` | `migrated_runtime_override_reader` | `T4.5` reclassifies these command-mutated settings as explicit runtime/legacy overrides and removes the direct flat-key reads at safe scheduler call sites without changing write ownership. |
| `UnifiedCombat.lua` / `//uc sleep` status/list command display | Reads sleep enablement and ordered sleep spell names for chat output through `uc_runtime_overrides.lua` | `migrated_runtime_override_reader` | `T4.6` closes the remaining safe command-display read gap without changing slash-command mutation ownership or any active-profile sync behavior. |
| `unified_scheduler.lua` / remaining broader provider and dispatch paths via context settings | Reads other runtime-sensitive fields and consumes settings views built elsewhere | `high_action_selection_risk` | Still avoid broader migration; `T4.5` only swaps the safe `fight_leader` / `sleep` read points to the runtime override facade. |
| `uc_hb_buff_maint.lua` / defensive buff chooser | Reads defensive buff list, self-only gate, and overwrite settings | `migrated_active_config_reader` | `T4.3` now prefers `config.defensive.buffs.list`, `self_only`, `overwrite_enabled`, and `overwrite_interval`, with flat/default fallback when the active path is missing. `defensive_targeted_buffs` remains flat because no structured path exists yet. |
| `uc_cor_maintenance.lua` / COR roll maintenance chooser | Reads configured rolls, crooked-roll slot, elevens mode, Luzaf range override, and range requirement ids | `migrated_active_config_reader` | `T4.3` now prefers `config.maintenance.cor.*` for these durable readers, with flat/default fallback when the active path is missing. Ability-list fallback remains flat compatibility behavior. |
| `uc_party_follow.lua` / debug logging gate | Reads only `debug` for file logging enablement | `safe_debug_or_ui` | `T4.1` migrated the debug gate to `uc_active_config`. |
| `uc_party_follow.lua` / status snapshots | Reads follow flags for diagnostic status text | `migrated_active_config_reader` | `T4.2` now prefers `config.follow.party.enabled` with flat/default fallback only when the active path is missing. |
| `uc_party_follow.lua` / follow tick and packet handling | Reads `party_follow`, leader ids, leader name, puller name, follow ranges, and fight-follow minimum | `migrated_active_config_reader` | `T4.2` now prefers `config.follow.party.*`, `config.follow.fight.min`, and `config.follow.partner.puller_name` for the durable follow readers, with flat/default fallback only when the active path is missing. `follow.partner.puller_id` remains runtime/session state. |
| `uc_pathing.lua` / debug overlay gate | Reads only `debug` for overlay visibility | `safe_debug_or_ui` | `T4.1` migrated only the overlay debug gate; path/follow reads remain on `_G.UC_SETTINGS`. |
| `uc_pathing.lua` / path binding, gating, and follow control | Reads `path_recording`, `path_follow_enabled`, `path_file_name`, `path_route_type`, `path_party_gate_yalms`, `path_resume_index_window`, and party-follow gating fields | `migrated_active_config_reader` | `T4.2` now prefers `config.movement.path.*` and `config.follow.party.*` for the durable path/follow readers, but `path_file_name` is now treated as a runtime/session mirror and is ignored by durable v2 diff/status. Runtime-mutated path points/state remain flat/runtime-owned. |
| `unified_combat_core.lua` / scheduler-facing target/tank provider selectors | Builds scheduler-only settings views for target acquisition and tank enmity selection | `migrated_active_config_reader` | `T4.4` now prefers structured combat/tank values for `select_target_for_scheduler(...)` and `select_tank_enmity_for_scheduler(...)`, while leaving broader core tick/runtime ownership reads unchanged. |
| `unified_combat_core.lua` / broader core tick ownership/runtime helpers | Reads active settings for shared combat helpers | `high_action_selection_risk` | Still avoid beyond the bounded scheduler-facing view. |
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

Recommended next step after `T4.3`: keep broader scheduler/provider action-decision reads deferred. Any next migration should stay outside command-owned compatibility settings and avoid movement-owner state, locks, pending actions, current-action state, and live target-selection logic.
After `T4.4`, the same caution still applies to any remaining broader target-selection or runtime combat ownership reads: keep `fight_leader`, `add_priority`, `sleep`, add-control/fight-leader arbitration, and wider core tick ownership decisions deferred until those command-owned compatibility settings are intentionally retired or reclassified.
After `T4.5`, the same caution still applies to broader ownership and action-selection reads. The safe change here is classification, not ownership transfer: `fight_leader`, `fight_leader_id`, `add_priority`, and `sleep` now have explicit read-only runtime/legacy override accessors, but the commands and bridge paths that mutate flat compatibility keys still own those session overrides.

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

Touched by `T4.2`:

- `uc_party_follow.lua`: migrated durable readers for `party_follow`, `party_follow_id`, `party_follow_leader_name`, `party_follow_min`, `party_follow_max`, and `fight_follow_min` to active-config-first accessors with flat/default fallback when the active path is missing.
- `uc_pathing.lua`: migrated durable readers for `path_recording`, `path_follow_enabled`, `path_route_type`, `path_party_gate_yalms`, `path_resume_index_window`, and party-follow gating to active-config-first accessors with flat/default fallback when the active path is missing. `path_file_name` remains a runtime/session mirror and is ignored by durable v2 diff/status.
- `tests/replay/harness/selftest_movement_priority_arbitration.lua`: added dynamic active-vs-flat and missing-active-path fallback coverage for the migrated follow/path readers.
- `tests/replay/harness/selftest_active_config_consumer_migration.lua`: expanded focused static assertions for the newly migrated reader paths.

Touched by `T4.3`:

- `uc_hb_buff_maint.lua`: migrated defensive buff list, self-only gate, overwrite enablement, and overwrite interval readers to active-config-first accessors with flat/default fallback when the active path is missing.
- `uc_cor_maintenance.lua`: migrated configured COR roll, crooked-roll slot, elevens mode, Luzaf range override, and range requirement readers to active-config-first accessors with flat/default fallback when the active path is missing.
- `unified_scheduler.lua`: migrated a bounded defensive/maintenance/spell-related durable-reader batch including defensive enabled/provider gating, cure thresholds, enemy-buff removal gating, overwrite interval readers, and defensive/maintenance dark-launch toggles to active-config-first accessors with flat/default fallback when the active path is missing.
- `tests/replay/harness/selftest_active_config_defensive_maintenance_readers.lua`: added focused dynamic coverage for active-vs-flat and missing-active-path fallback behavior in the migrated defensive and COR maintenance readers.
- `tests/replay/harness/selftest_active_config_consumer_migration.lua`: expanded focused static assertions for the newly migrated defensive/maintenance reader paths.

Touched by `T4.4`:

- `uc_scheduler_config.lua`: added a small scheduler/provider-facing active-config reader facade for combat/tank/debug ownership reads with flat/default fallback when the active path is missing.
- `unified_scheduler.lua`: replaced scattered scheduler-facing flat/config reads for combat dark-launch ownership, autotarget, prime, tank-mode, enemy-buff diagnostic gating, and scheduler debug-log flags with facade reads.
- `unified_combat_core.lua`: added a scheduler-only settings view so `select_target_for_scheduler(...)` and `select_tank_enmity_for_scheduler(...)` can consume active-config-first combat/tank values without changing the broader core tick ownership path.
- `tests/replay/harness/selftest_scheduler_config_readers.lua`: added focused dynamic coverage for facade active-vs-flat parity and missing-active-path fallback behavior.
- `tests/replay/harness/selftest_active_config_consumer_migration.lua`: expanded focused static assertions for the new facade, the migrated scheduler/core call sites, and the deferred `fight_leader` / `add_priority` / `sleep` boundaries.

Touched by `T4.5`:

- `uc_runtime_overrides.lua`: added a read-only runtime/legacy override facade for command-mutated `fight_leader`, `fight_leader_id`, `add_priority_names`, and `sleep` readers.
- `uc_add_priority.lua`: routed ordered add-priority reads through the runtime override facade while preserving the existing mutation helpers.
- `uc_add_control.lua`: routed fight-leader enablement gating through the runtime override facade.
- `uc_fight_leader.lua`: routed fight-leader enablement and leader-id reads through the runtime override facade.
- `unified_scheduler.lua`: routed sleep toggle, sleep spell list, and fight-leader scheduler reads through the runtime override facade without adding new top-level locals.
- `tests/replay/harness/selftest_runtime_overrides.lua`: added focused dynamic precedence and non-mutation coverage for the runtime override facade.
- `tests/replay/harness/selftest_runtime_parse.lua`: registered the new runtime helper for parse coverage.
- `tests/replay/harness/selftest_all_replay_fixtures.lua`: registered the new focused selftest in the aggregate run.
- `tests/replay/harness/selftest_active_config_consumer_migration.lua`: expanded static assertions for the new facade and the migrated consumers.

Touched by `T4.6`:

- `UnifiedCombat.lua`: routed the `//uc sleep` status/list display helper through `uc_runtime_overrides.sleep_enabled(...)` and `sleep_spell_names(...)` while preserving the existing mutation path and chat output shape.
- `tests/replay/harness/selftest_active_config_consumer_migration.lua`: added static assertions that the addon command helper now uses the runtime-override facade for sleep display reads.

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
- Assert `uc_party_follow.prerender()` honors active-config follow values when active and flat differ.
- Assert `uc_party_follow.prerender()` preserves flat follow behavior when the active reader path is missing.
- Assert `uc_pathing.tick()` honors active-config path-follow enablement when active and flat differ.
- Assert `uc_pathing.tick()` preserves flat path-follow behavior when the active reader path is missing.
- Assert `uc_hb_buff_maint.choose(...)` honors active-config defensive buff values when active and flat differ.
- Assert `uc_hb_buff_maint.choose(...)` preserves flat defensive buff behavior when the active reader path is missing.
- Assert `uc_cor_maintenance.propose(...)` honors active-config COR maintenance values when active and flat differ.
- Assert `uc_cor_maintenance.propose(...)` preserves flat COR maintenance behavior when the active reader path is missing.

## Domains not recommended yet

Do not select these domains for the next migration:

- combat proposal selection
- tank behavior
- broader defensive/cure logic beyond the bounded migrated readers
- movement/follow/pathing
- targeting
- sleep action selection
- broader maintenance action selection beyond the bounded migrated readers
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

- slash-command-owned flat durable writes such as `fight_leader`, `add_priority`, and `sleep`

Still explicitly deferred after `T4.3`:

- `fight_leader` / `fight_leader_id` readers and adjacent follow ownership behavior because addon slash commands still mutate those flat keys directly.
- `add_priority` / targeting command-owned readers because addon commands still own flat compatibility mutation there.
- `sleep` command-owned readers because addon commands still mutate the flat compatibility settings directly.
- `defensive_targeted_buffs` readers because no structured `config.defensive.buffs.targeted_*` path exists yet and `T4.3` does not change the v2 schema.
- scheduler/provider action-decision reads, live movement-owner state, pending/lock/current-action state, and runtime path point mutation semantics.

Still explicitly deferred after `T4.4`:

- `fight_leader` / `fight_leader_id` readers and adjacent add-control/follow ownership behavior because addon slash commands still mutate those flat keys directly.
- `add_priority` / targeting command-owned readers because addon commands still own flat compatibility mutation there.
- `sleep` command-owned readers because addon commands still mutate the flat compatibility settings directly.
- broader core tick ownership reads in `unified_combat_core.lua` outside the scheduler-only settings view.
- scheduler/provider action-decision reads tied to live runtime state, movement-owner state, pending/lock/current-action state, and runtime path point mutation semantics.

## T4.5 runtime-override ownership classification

`T4.5` re-checks the legacy command-mutated fields with explicit runtime-override ownership in mind.

| Field | Current write surfaces inspected | Classification | T4.5 handling |
| --- | --- | --- | --- |
| `fight_leader` | `UnifiedCombat.lua` slash command, `remote_bridge.lua` fight-leader setter | `runtime_session_override` | Safe readers now use `uc_runtime_overrides.fight_leader_enabled(...)`; write behavior remains on the flat compatibility key and is not synced into `_G.UC_ACTIVE_PROFILE`. |
| `fight_leader_id` | `UnifiedCombat.lua` slash command, `remote_bridge.lua` fight-leader setter | `runtime_session_override` | Safe readers now use `uc_runtime_overrides.fight_leader_id(...)`; write behavior remains on the flat compatibility key and is not synced into `_G.UC_ACTIVE_PROFILE`. |
| `add_priority_names` | `UnifiedCombat.lua` slash command, `remote_bridge.lua` add-priority setters | `legacy_compat_override` | Safe readers now use `uc_runtime_overrides.add_priority_names(...)`; the existing flat list remains the compatibility mirror and command-owned session edit path. |
| `sleep` / `sleepspells` / `sleepspell` | `UnifiedCombat.lua` slash command, `remote_bridge.lua` sleep spell setters | `legacy_compat_override` | Safe readers now use `uc_runtime_overrides.sleep_enabled(...)` and `sleep_spell_names(...)`; write behavior remains on the flat compatibility keys and is not synced into `_G.UC_ACTIVE_PROFILE`. |

Still deferred after `T4.5`:

- command and bridge write ownership for these fields, because changing the mutation path would be higher risk than reclassifying the reads.
- broader runtime-owner logic outside the bounded readers migrated to `uc_runtime_overrides.lua`.

Remaining direct `_G.UC_SETTINGS` categories after `T4.6`:

- `flat_projection_or_sync_path`: `_G.UC_SETTINGS` initialization, normalization, profile capture/apply/reload helpers, active-profile projection, compact config-status building inputs, and facade getter entry points intentionally consume or project the flat compatibility table.
- `write_or_command_mutation_path`: `UnifiedCombat.lua` slash commands and `remote_bridge.lua` live setters still mutate flat compatibility keys for legacy/session behavior. No generic sync-after-mutation path was added.
- `runtime_or_session_state_keep_flat`: runtime-owned toggles and live mutable runtime state such as `engine_enabled` mirroring, movement-owner state, path points, and related live arbitration/session state remain flat/runtime-owned.
- `legacy_override_reader`: safe live readers for `fight_leader`, `fight_leader_id`, `add_priority_names`, `sleep`, `sleepspells`, and `sleepspell` now route through `uc_runtime_overrides.lua`. No remaining safe live reader was found still needing migration.
- `test_or_fixture_only`: replay harness fixtures and static assertions intentionally set or inspect `_G.UC_SETTINGS` to validate compatibility behavior.
