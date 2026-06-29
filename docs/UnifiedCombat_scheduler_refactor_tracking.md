# UnifiedCombat Scheduler Refactor Tracking

Source RFC: `RFC/UnifiedCombat_scheduler_refactor_RFC_for_Codex.md`  
Purpose: a living progress tracker for implementation scope, completed work, and remaining scope.

## 1) Overall Status Snapshot

- Current phase focus: scheduler runtime parity slices that stay inside existing ownership policy, plus replay/static coverage for those slices.
- Completed in this phase: core harness foundation plus fixture suites for extracted modules, plus targeted runtime parity fixes through `T3.6e`, the tank configured-JA starvation fix in `T3.6o`, and the tank-enmity spell self run-stop promotion in `T3.6p`.
- Tank-family run-stop promotion is complete; Doom command/run-stop remain default-off after the T3.6r audit, and vector-run remains deferred.
- `T3.6s` finalized the scheduler ownership baseline docs; there is no active ownership promotion task recommended now.
- `T3.7a` started a parallel profile/UI file contract audit during scheduler soak; no runtime changes were made.
- `T3.7b` added pure profile validation/status scaffolding without wiring live runtime behavior yet.
- `T3.7c` wires that validation into the existing profile load/reload path and exposes read-only contract status through the bridge.
- `T3.7d` audits a future canonical config object for lower Lua 5.1 local/register pressure and profile/UI contract alignment; no runtime behavior or bridge/profile migration changed.
- `T3.7e` adds a pure canonical config normalizer and focused replay coverage; no runtime callers have migrated yet.
- `T3.7f` exposes compact read-only normalized config status through addon and bridge snapshots; runtime callers still use `_G.UC_SETTINGS`.
- `T3.7g` adds an explicit `//uc configstatus export` diagnostic file export for that compact status; it does not export full config or change runtime readers.
- `T3.7h` migrates the first low-risk config consumer group: legacy in-game overlay visibility reads `config.ui.show_ingame_ui`; scheduler/provider action-decision reads still use `_G.UC_SETTINGS`.
- `T3.7i` audits active config consumers, finds the `T3.7h` files are likely legacy/orphaned in the current runtime, and selects active bridge read-only `config_contract_status` publication as the next low-risk migration candidate.
- `T3.7j` migrates that active bridge read-only `config_contract_status` consumer to `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)`; this is the first active runtime read-path config migration and remains compact/read-only.
- `T3.7k` audits remaining active bridge read-only settings consumers, keeps runtime and bridge behavior unchanged, confirms `T3.7j` live sanity passed, and recommends pausing bridge migration unless a future task is limited to a newly proven read-only/status-only bridge field.
- `T3.8a` adds structured profile/config read compatibility at the pure normalizer/contract-test layer. Live v1 profile load/save, bridge writes, and scheduler/provider action-decision reads remain unchanged.
- `T3.8b` adds an explicit `//uc profilev2 export` command that writes a separate structured v2 profile artifact for inspection. Live v1 profile load/save, bridge writes, and scheduler/provider action-decision reads remain unchanged.
- Not started in this phase: broad provider extraction/cutover beyond existing scheduler ownership policy and any fallback-removal pass outside explicitly migrated slices.

## Latest Task Notes

### `T3.8b` Add structured v2 profile export command

- Status: `DONE`
- Changed files:
  - `UnifiedCombat.lua`
  - `uc_profile_v2_export.lua`
  - `tests/replay/harness/selftest_profile_v2_export.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `tests/replay/harness/selftest_runtime_parse.lua`
  - `.gitignore`
  - `docs/profile_v2_structured_config_shape.md`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/active_config_consumer_migration_audit.md`
  - `docs/bridge_readonly_config_consumer_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added `//uc profilev2 export` to write `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua`.
  - Export content is a structured `return { version = 2, profile = {...}, config = {...} }` Lua table for inspection.
  - Kept live v1 profile load/save behavior unchanged and kept the bridge as the live UI write path.
  - Kept scheduler/provider action-decision reads on `_G.UC_SETTINGS`; no runtime consumer migration was added.
- Next step:
  - Field-test the explicit export against real loaded profiles, then decide whether to add opt-in v2 load/dry-run support later.

### `T3.8a` Add structured profile config read compatibility

- Status: `DONE`
- Changed files:
  - `uc_config_normalizer.lua`
  - `uc_profile_contract.lua`
  - `tests/replay/harness/selftest_structured_profile_config.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/profile_v2_structured_config_shape.md`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/active_config_consumer_migration_audit.md`
  - `docs/bridge_readonly_config_consumer_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added pure normalizer support for future structured payloads with durable grouped settings under `settings.config` and metadata under `settings.profile`.
  - Kept direct canonical-domain input support for focused tests and future adapters.
  - Added a conservative `validate_structured_profile_config(payload)` helper without wiring it into the live loader.
  - Added focused replay coverage for structured parity, defaults, malformed input safety, input immutability, output clone safety, runtime accessors, and contract validation.
  - Documented the supported v2 shape and confirmed current profile load/save behavior, bridge write behavior, and scheduler/provider action-decision reads remain unchanged.
- Next step:
  - Wire structured read compatibility into the live profile load path in fail-safe/read-only mode, or add a sample/generated v2 profile fixture before live load-path wiring.

### `T3.7k` Audit active bridge read-only settings consumers

- Status: `DONE`
- Changed files:
  - `docs/bridge_readonly_config_consumer_audit.md`
  - `docs/active_config_consumer_migration_audit.md`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Audited `remote_bridge.lua` state/options/hello snapshots and live command/edit handlers.
  - Confirmed the only safe active bridge read-only config publication, `config_contract_status`, was already migrated in `T3.7j`.
  - Classified remaining bridge option fields as derived UI edit choices, `Start_Engine` as command state, profile/config contract fields as addon-owned status, and all `set`/`apply_set(...)`/`cfg_version` paths as protected write protocol.
  - Confirmed no runtime behavior, bridge behavior, profile load/save behavior, or scheduler/action behavior changed.
  - Recorded that `T3.7j` live sanity passed before this audit.
- Next step:
  - Pause bridge migration for now, or migrate only the narrow non-bridge diagnostic candidate: `unified_scheduler.lua` `enemy_dispel_diag(msg)` / `enemy_dispel_log(msg)` debug gates through focused `uc_config_runtime` parity helper(s). Do not migrate scheduler/provider action-decision reads.

### `T3.7d` Audit canonical config migration

- Status: `DONE`
- Changed files:
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Audited the current flat `_G.UC_SETTINGS` surface, profile-persisted fields, bridge-editable fields, ambiguous runtime-looking fields, and local-variable pressure hotspots.
  - Proposed a domain-grouped canonical `config` shape covering combat, defensive, movement, maintenance, follow, targeting, tank, sleep, abilities, spells, debug, profile, and UI.
  - Confirmed no profile load/save behavior, bridge write behavior, scheduler ownership defaults, or runtime action behavior changed.
- Next step:
  - Add pure `uc_config_normalizer.lua` with tests for canonical shape, default normalization, and compatibility with current flat profile/settings data.

### `T3.7e` Add pure canonical config normalizer

- Status: `DONE`
- Changed files:
  - `uc_config_normalizer.lua`
  - `tests/replay/harness/selftest_config_normalizer.lua`
  - `tests/replay/harness/selftest_runtime_parse.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added a pure `uc_config_normalizer.lua` adapter that groups the current flat `_G.UC_SETTINGS` / profile data into canonical `profile`, `ui`, `command`, `combat`, `abilities`, `defensive`, `movement`, `follow`, `targeting`, `tank`, `sleep`, `spells`, `maintenance`, `debug`, `ownership`, and `legacy` domains.
  - Preserved compatibility with current flat keys while tolerating nested bridge-shaped input and copying list/table values so the normalized config can be used without mutating source tables.
  - Kept runtime callers on `_G.UC_SETTINGS`; no profile load/save behavior or bridge write behavior changed.
- Validation:
  - Parser and replay validation passed.
- Next step:
  - Build a read-only status or config consumer around the normalized object, or migrate one low-risk domain to `ctx.config` after field-test confidence is high.

### `T3.7f` Expose normalized config read-only status

- Status: `DONE`
- Changed files:
  - `UnifiedCombat.lua`
  - `remote_bridge.lua`
  - `tests/replay/harness/selftest_config_status.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `tests/replay/harness/selftest_side_effect_inventory.lua`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added `UC_CONFIG_CONTRACT_STATUS` as a compact read-only summary built from current `_G.UC_SETTINGS` during existing load/reload paths.
  - Published `config_contract_status` in bridge `state` and `options` snapshots without exporting the full normalized config table.
  - Kept runtime readers on `_G.UC_SETTINGS`; no scheduler/provider reads migrated to `ctx.config`.
  - Kept profile load/save behavior and bridge write behavior unchanged.
- Next step:
  - Field-test status parity against real loaded settings, then migrate one low-risk domain to `ctx.config` with focused replay coverage.

### `T3.7g` Export config status diagnostic

- Status: `DONE`
- Changed files:
  - `UnifiedCombat.lua`
  - `uc_config_status_export.lua`
  - `tests/replay/harness/selftest_config_status_export.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `tests/replay/harness/selftest_runtime_parse.lua`
  - `tests/replay/harness/selftest_side_effect_inventory.lua`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added `//uc configstatus export` to write `data/status/<safe_character>_config_contract_status.lua`.
  - Export content is a compact `return { ... }` Lua-table diagnostic containing only status fields.
  - Kept the full normalized config, `_G.UC_SETTINGS`, scheduler state, pending/lock state, target data, party data, and mob snapshots out of the export.
  - Kept export explicit-command-only; no automatic tick, bridge, scheduler, polling, or combat writes were added.
  - Kept runtime readers on `_G.UC_SETTINGS`; profile load/save behavior and bridge write behavior are unchanged.
- Next step:
  - Field-test exported status parity, then migrate one low-risk config domain to `ctx.config` with focused replay coverage.

### `T3.7h` Migrate first low-risk config consumer

- Status: `DONE`
- Changed files:
  - `.gitignore`
  - `uc_config_runtime.lua`
  - `melee_engine.lua`
  - `dd2_module.lua`
  - `tests/replay/harness/selftest_config_first_consumer.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added a small runtime config accessor that builds canonical config from current `_G.UC_SETTINGS` and reads `config.ui.show_ingame_ui`.
  - Migrated only the legacy in-game overlay visibility helpers in `melee_engine.lua` and `dd2_module.lua`.
  - Preserved the previous display fallback for nil/missing `show_ingame_ui`; normalizer unavailable or failure keeps the old display behavior.
  - Kept combat, tank, defensive, movement, targeting, scheduler/provider, profile load/save, and bridge write behavior unchanged.
  - Kept the full normalized config out of bridge snapshots and export files.
- Next step:
  - Field-test this low-risk UI migration, then either keep soaking or migrate the next low-risk read-only domain with focused parity coverage.

### `T3.7i` Audit active config consumers

- Status: `DONE`
- Changed files:
  - `docs/active_config_consumer_migration_audit.md`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Audited active config consumers in `UnifiedCombat.lua`, `unified_engine.lua`, `unified_scheduler.lua`, `remote_bridge.lua`, config helpers, and modules required from the active engine/scheduler path.
  - Found no active require path from current UnifiedCombat runtime into `melee_engine.lua` or `dd2_module.lua`; `T3.7h` likely proved the migration pattern more than active runtime behavior.
  - Inventoried active `_G.UC_SETTINGS` reads and classified candidates by status/debug/gating/action/movement/legacy risk.
  - Selected read-only bridge `config_contract_status` publication in `remote_bridge.lua` state/options snapshots as the next active low-risk migration candidate.
  - Confirmed no runtime behavior, profile load/save behavior, bridge write behavior, or scheduler/action behavior changed.
- Next step:
  - Migrate only the selected active read-only bridge status consumer with focused parity coverage; do not migrate scheduler/provider action-decision reads or combat/tank/defensive/movement/targeting domains.

### `T3.7j` Migrate bridge config status consumer

- Status: `DONE`
- Changed files:
  - `uc_config_runtime.lua`
  - `remote_bridge.lua`
  - `tests/replay/harness/selftest_bridge_config_status_consumer.lua`
  - `tests/replay/harness/selftest_config_status.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/active_config_consumer_migration_audit.md`
  - `docs/canonical_config_migration_audit.md`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added `uc_config_runtime.config_contract_status(...)` for compact read-only status access.
  - Migrated active bridge `state` and `options` `config_contract_status` publication away from direct `_G.UC_CONFIG_CONTRACT_STATUS` coupling and onto the runtime accessor.
  - Kept the bridge field compact/read-only and did not expose full normalized config or `_G.UC_SETTINGS`.
  - Kept profile load/save behavior, bridge write behavior, `apply_set(...)`, `cfg_version`, scheduler/provider action-decision reads, and combat/tank/defensive/movement/targeting consumers unchanged.
  - Added focused parity coverage for compact fields, unavailable-normalizer status, no full-config/settings exposure, and unchanged bridge write shape.
- Next step:
  - Soak this first active runtime read-path migration, then choose only another status/debug/UI active consumer if the next config migration is needed.

### `T3.7c` Wire profile validation into existing load path

- Status: `DONE`
- Changed files:
  - `UnifiedCombat.lua`
  - `remote_bridge.lua`
  - `uc_profile_contract.lua`
  - `tests/replay/harness/selftest_profile_contract.lua`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Wired validation into the existing profile load/reload path without changing save behavior, naming/keying, or bridge write commands.
  - Added a read-only `UC_PROFILE_CONTRACT_STATUS` snapshot that the bridge can include in `state` and `options` messages.
  - Kept profile load fail-safe: invalid trees are rejected, and validation availability is reported without introducing live apply or polling.
- Validation:
  - Parser and replay validation passed.
- Next step:
  - No further profile contract wiring is needed before soak unless the field snapshot reveals a missing status field.

### `T3.7b` Add profile validation and status contract scaffolding

- Status: `DONE`
- Changed files:
  - `uc_profile_contract.lua`
  - `tests/replay/harness/selftest_profile_contract.lua`
  - `tests/replay/harness/selftest_runtime_parse.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/profile_ui_file_contract_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Added a pure profile validation module with conservative structural checks.
  - Added ownership classification helpers and a status contract snapshot helper.
  - Added focused replay coverage and aggregate registration.
  - Kept live profile load/save and remote bridge behavior unchanged.
- Validation:
  - Parser and replay validation passed.
- Next step:
  - Decide whether to wire read-only status output or integrate validation into the load path after soak.

### `T3.6l` Reset local ownership flags baseline

- Status: `DONE`
- Changed files:
  - `local_ownership_flags.lua`
  - `docs/local_ownership_flags_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Reset `local_ownership_flags.lua` to a clean baseline with only commented examples and no active overrides, so source defaults are once again the normal runtime behavior.
  - Kept runtime scheduler code unchanged.
  - Documented that tank behavior should be field-tested again before deeper action-economy diagnosis.
- Validation:
  - Parse/replay validation remains green.
- Next step:
  - Reload the addon and re-test tank behavior with a clean local override file before further diagnosis.

### `T3.6m` Diagnose tank configured job ability starvation

- Status: `DONE`
- Planned / changed files:
  - `docs/tank_configured_ja_starvation_diagnostic.md`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `tests/replay/harness/selftest_tank_configured_ja_starvation.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
- Working diagnosis:
  - The scheduler still has two distinct JA lanes: generic configured JAs gated by `ability_active`, and tank-enmity JAs/spells gated by `tank` + `autotarget` through `tank_enmity_actions`.
  - The tank-enmity lane is evaluated before the generic configured-JA lane and carries the higher band, so a clean baseline can make normal configured JAs look starved even when the tank lane is healthy.
  - No runtime behavior change was intended, and the diagnosis was resolved by the `T3.6o` priority-band fix.
- Next step:
  - No further tank configured-JA work is expected unless a new regression appears.

### `T3.6o` Fix tank configured job ability starvation

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_tank_configured_ja_starvation.lua`
  - `docs/tank_configured_ja_starvation_diagnostic.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
- Outcome:
  - Raised the tank-mode configured-JA band from the generic `70` baseline to `99` while keeping the non-tank baseline unchanged.
  - Preserved the separate tank-enmity lane, the `ability_active` gate, and the existing ownership policy.
  - Addressed the observed starvation window without broad scheduler refactoring.
- Validation:
  - Parser, ownership, and replay validation passed for the updated regression slice.
- Next step:
  - Continue tank-family ownership work only if a new field issue appears; this tuning fix itself is complete.

### `T3.6p` Promote tank enmity spell self run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/tank_configured_ja_starvation_diagnostic.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Promoted `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` to default-on semantics while preserving explicit `false` opt-out, the shared promoted kill switch, dispatcher fallback behavior, and runtime parity.
  - Left Doom and vector-run deferred.
  - Did not revisit tank configured-JA priority.
- Validation:
  - Parser, ownership, and replay validation passed for the updated promotion slice.
- Next step:
  - Continue only with non-tank deferred work if the roadmap calls for it.

### `T3.6q` Close tank run-stop ownership phase and audit remaining ownership surface

- Status: `DONE`
- Changed files:
  - `docs/tank_run_stop_ownership_phase_closure.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/local_ownership_flags_audit.md`
  - `docs/tank_configured_ja_starvation_diagnostic.md`
- Outcome:
  - Captured the completed tank-family run-stop promotion phase in a dedicated closure document.
  - Confirmed the remaining default-off surface is Doom plus vector/dormant paths, with no tank-family run-stop seam left to promote.
  - Left runtime behavior unchanged.
- Validation:
  - Parser, ownership, and replay validation passed for the closure audit baseline.
- Next step:
  - Audit Doom/vector separately only if a future task explicitly asks for it.

### `T3.6r` Audit Doom ownership promotion readiness

- Status: `DONE`
- Changed files:
  - `docs/doom_ownership_promotion_readiness_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/tank_run_stop_ownership_phase_closure.md`
- Outcome:
  - Confirmed both Doom ownership seams remain default-off and should stay conservative for now.
  - Documented the emergency-path risk, existing replay/static coverage, and the gap in safe live Doom field testing.
  - Left vector run deferred separately.
- Validation:
  - Validation passes are recorded for the audit baseline.
- Next step:
  - Keep Doom default-off unless a future task adds a safe replay/mock coverage plan.

### `T3.6s` Finalize scheduler ownership promotion baseline

- Status: `DONE`
- Changed files:
  - `docs/scheduler_ownership_final_baseline.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/tank_run_stop_ownership_phase_closure.md`
  - `docs/doom_ownership_promotion_readiness_audit.md`
  - `docs/local_ownership_flags_audit.md`
  - `docs/tank_configured_ja_starvation_diagnostic.md`
  - `docs/aggregate_replay_failure_baseline.md`
- Outcome:
  - Collapsed the remaining stale promotion language into a final baseline summary.
  - Confirmed the promoted surfaces are stable, local ownership overrides are clean, and Doom/vector stay parked.
  - Left runtime behavior unchanged.
- Validation:
  - Full parse/replay validation passed.
- Next step:
  - No ownership promotion is recommended now; future work should begin with a separate readiness plan if needed.

### `T3.6n` Promote tank enmity spell target run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/tank_configured_ja_starvation_diagnostic.md`
- Outcome:
  - Promoted `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` to default-on semantics while preserving explicit `false` opt-out, the shared promoted kill switch, helper-owned fallback, and the existing tank spell target send-adjacent behavior.
  - Promoted tank-enmity spell self default-on, left Doom/vector deferred, and did not alter tank configured-JA priority/starvation behavior.
  - Preserved the scheduler closure invariant: no direct `windower.send_command(`, `windower.ffxi.run(`, `windower.ffxi.turn(`, or `uc_settarget.select_by_id(` callsites were introduced.
- Validation:
  - `luac -p local_ownership_flags.lua`
  - `luac -p UnifiedCombat.lua`
  - `luac -p unified_scheduler.lua`
  - `luac -p uc_scheduler_run_stop_ownership.lua`
  - `luac -p uc_scheduler_action_state.lua`
  - `lua tests/replay/harness/selftest_runtime_parse.lua`
  - `lua tests/replay/harness/selftest_side_effect_inventory.lua`
  - `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`
  - `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`
  - `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`
  - `lua tests/replay/harness/selftest_tank_configured_ja_starvation.lua`
  - `lua tests/replay/harness/selftest_all_replay_fixtures.lua`
- Next step:
  - Tank-family promotion is complete; continue only with Doom/vector or leave the configured-JA diagnosis unchanged.

### `T3.6k` Audit local ownership flag overrides

- Status: `DONE`
- Changed files:
  - `docs/local_ownership_flags_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Audited `local_ownership_flags.lua`, confirmed it is tracked and loaded via protected `pcall(require, 'local_ownership_flags')` during addon bootstrap, and found multiple stale tank/ownership opt-outs that can plausibly explain the reported tank starvation.
  - Did not change scheduler runtime behavior or rewrite the local file.
- Validation:
  - Runtime and replay validation remained green for the existing scheduler/tank ownership harnesses.
- Next step:
  - Remove the stale promoted-default-on false overrides from the local file before deeper tank runtime diagnosis.

### `T3.6j` Promote tank spell-settle run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Promoted `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` to default-on semantics while preserving explicit `false` opt-out and the shared promoted kill switch.
  - Kept tank action-settle, tank-enmity JA self, and tank spell-settle promoted default-on, left tank enmity spell target/self default-off, and left Doom/vector unchanged.
  - Preserved helper-routed fallback behavior and did not add any direct scheduler side-effect callsites.
- Validation:
  - Ownership static/runtime coverage now treats the tank spell-settle seam as promoted and still confirms the remaining tank-family branches stay explicit `== true` default-off checks.
  - Full aggregate replay remains green.
- Next step:
  - Continue tank-family promotion only with the remaining helper-routed default-off seams, starting from tank-enmity spell target if the next task wants the narrowest remaining branch.

### `T3.6i` Promote tank enmity JA self run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/scheduler_remaining_run_stop_coverage_plan.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Promoted `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` to default-on semantics while preserving explicit `false` opt-out and the shared promoted kill switch.
  - Kept tank action-settle promoted default-on, left tank spell-settle and tank enmity spell target/self default-off, and left Doom/vector unchanged.
  - Preserved helper-routed fallback behavior and did not add any direct scheduler side-effect callsites.
- Validation:
  - Ownership static/runtime coverage now treats the tank-enmity JA self seam as promoted and still confirms the remaining tank-family branches stay explicit `== true` default-off checks.
  - Full aggregate replay remains green.
- Next step:
  - Continue tank-family promotion only with the remaining helper-routed default-off seams, starting from tank-enmity spell target if the next task wants the narrowest remaining branch.

### `T3.6h` Promote tank action-settle run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Promoted `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` to default-on semantics while preserving explicit `false` opt-out and the shared promoted kill switch.
  - Left the other tank-family run-stop seams default-off, with Doom and vector run still outside the promotion path.
  - Preserved helper-routed fallback behavior and did not add any direct scheduler side-effect callsites.
- Validation:
  - Ownership static/runtime coverage now treats the tank action-settle seam as promoted and still confirms the remaining tank-family branches stay explicit `== true` default-off checks.
  - Full aggregate replay remains green.
- Next step:
  - If tank-family promotion continues, the next audit candidate is the tank spell-settle seam.

### `T3.6g` Select safest tank-family run-stop ownership promotion candidate

- Status: `DONE`
- Changed files:
  - `docs/tank_run_stop_ownership_promotion_audit.md`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Audited the remaining tank-family run-stop seams and selected `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` as the next safest promotion candidate.
  - Kept Doom and vector run out of scope and left the other tank seams default-off.
  - No runtime behavior changed.
- Validation:
  - Existing ownership static/runtime coverage already tracks all five tank-family branches, so no test updates were needed for this audit-only slice.
  - Full aggregate replay remains green after T3.6f.
- Next step:
  - Promote only the selected tank action-settle seam in the next task if field rollout is desired.

### `T3.6f` Fix aggregate-only action economy timeline logging harness leakage

- Status: `DONE`
- Changed files:
  - `tests/replay/harness/selftest_action_economy_timeline_logging.lua`
  - `docs/aggregate_replay_failure_baseline.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Fixed the aggregate-only `selftest_action_economy_timeline_logging` failure by isolating the suite's fake clock from the scheduler's socket-backed clock source.
  - The suite now snapshots/restores the socket stub and drives both clocks from the same harness-controlled value, so the cast-complete release path no longer leaks across aggregate ordering.
  - Runtime files were untouched.
- Validation:
  - The standalone timeline suite passes.
  - `lua tests/replay/harness/selftest_all_replay_fixtures.lua` now passes in full.
- Next step:
  - `T3.6s` finalized the ownership baseline; no active ownership promotion slice is recommended now.

### `T3.6e` Refresh stale replay fixture expectations only

- Status: `DONE`
- Changed files:
  - `tests/replay/harness/selftest_engage_dispatch_priority.lua`
  - `tests/replay/harness/selftest_sleep_target_state_suppression.lua`
  - `tests/replay/fixtures/action_state/action_state_fixtures.lua`
  - `docs/aggregate_replay_failure_baseline.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Refreshed the stale spell-release, Sleep suppression, and action-state fixture expectations without touching runtime code.
  - Reconfirmed the three stale suites now pass individually.
  - Aggregate replay still fails only on `selftest_action_economy_timeline_logging`, which now looks like harness isolation/order leakage rather than a runtime regression.
- Validation:
  - Required parser and ownership validations passed.
  - The aggregate replay suite still fails, as expected from the remaining harness issue.
- Next step:
  - Inspect aggregate-suite isolation/order leakage before the next ownership promotion.

### `T3.6d` Classify aggregate replay fixture failures

- Status: `DONE`
- Changed files:
  - `docs/aggregate_replay_failure_baseline.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Outcome:
  - Classified the current aggregate replay failures as mostly stale expectations and aggregate harness contamination rather than a T3.6b/T3.6c regression.
  - Confirmed the combat spell settle/prep-wait promotions do not appear implicated.
- Validation:
  - Aggregate replay still fails on the six named suites, but the required ownership/parser validation set remains green.
- Next step:
  - Refresh the stale fixture pins first, then inspect aggregate-suite isolation before the next ownership promotion.

### `T3.6c` Promote combat spell prep-wait run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Promoted `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` to default-on semantics.
  - Preserved explicit `false` opt-out, the shared promoted ownership kill switch, dispatcher fallback, and helper ownership boundaries.
  - Left Doom, tank-family, and vector run ownership unchanged and deferred.
- Validation summary:
  - Updated existing ownership static/runtime coverage to treat combat spell prep-wait as promoted default-on alongside settle.
  - Confirmed no direct scheduler side-effect callsites were introduced.
- Field-test instructions:
  - No new field test is needed beyond the existing combat-spell packet if someone wants a spot check.
  - Keep Doom, tank-family, and vector run off or deferred in this task.

### `T3.6b` Promote combat spell settle run-stop ownership default-on

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_runtime.lua`
  - `tests/replay/harness/selftest_run_stop_ownership_static.lua`
  - `tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`
  - `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/scheduler_ownership_promotion_plan.md`
  - `docs/scheduler_ownership_promotion_readiness_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Promoted only `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` to default-on semantics.
  - Preserved explicit `false` opt-out, the shared promoted ownership kill switch, dispatcher fallback, and helper ownership boundaries.
  - Left combat spell prep-wait, Doom, tank-family, and vector run ownership unchanged at the time; prep-wait was promoted later in `T3.6c`.
- Validation summary:
  - Updated existing ownership static/runtime coverage to treat combat spell settle as promoted default-on; prep-wait was promoted later in `T3.6c`.
  - Confirmed no direct scheduler side-effect callsites were introduced.
- Field-test instructions:
  - No new field test is needed beyond the existing combat-spell spell-settle packet if someone wants a spot check.
  - Keep Doom, tank-family, and vector run off or deferred in this task.

### `T3.6a` Re-establish scheduler ownership baseline after spell lifecycle cleanup

- Status: `DONE`
- Changed files:
  - `docs/scheduler_ownership_resume_baseline.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - No runtime behavior changed.
  - The spell lifecycle cleanup detour is now treated as resolved and non-blocking for ownership work.
  - `unified_scheduler.lua` still has zero direct textual side-effect callsites for `windower.send_command(`, `windower.ffxi.run(`, `windower.ffxi.turn(`, and `uc_settarget.select_by_id(`.
- Validation summary:
  - Ownership seams remain behind the existing dispatcher/wrapper helpers.
  - Existing closure/promotion/source-guard coverage remains the right guardrail for this area; no new framework was added.
- Field-test instructions:
  - No new runtime field test is needed for this audit-only task.
  - If the next seam is promoted, use the existing combat-spell spell-settle packet and verify stop timing stays unchanged.

### `T3.4n` Complete explicit attack-on action-state bypass for WS/JA/spell/post-spell gates

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `uc_scheduler_action_state.lua`
  - `tests/replay/harness/selftest_engage_action_state_bypass.lua`
  - `tests/replay/harness/selftest_action_economy_timeline_logging.lua`
  - `docs/engage_action_state_bypass_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Completed the T3.4m partial explicit-engage policy so scheduler `attack_on` may bypass local `weaponskill`, `job_ability`, `spell`, `post_spell_tail`, and generic `cooldown` state when the player is not already engaged, not dead, the target is still valid, and retry cadence is ready.
  - Kept bounded explicit engage retry/debounce behavior intact through the existing pending-engage and engage-duplicate state instead of reintroducing generic action-state hard blocking.
  - Added clearer blocker logging for legitimate holds such as `pending_engage_retry_wait` and `BLOCK_PLAYER_DEAD`.
- Validation summary:
  - Expanded focused engage-bypass coverage to include WS, JA, spell, post-spell tail, generic cooldown, dead-player, invalid-target, and already-engaged cases.
  - Kept ownership/default-off policy unchanged and did not add direct scheduler side-effect calls.
- Field-test instructions:
  - Enable `_G.UC_DEBUG_ACTION_TIMELINE = true` and verify explicit `attack_on` can send promptly after target selection even when stale WS/JA/spell/post-tail state is still visible locally.
  - Confirm retry cadence still prevents every-tick engage spam and that message id `94` continues to drive bounded retry scheduling.
  - Confirm critical Cure still overrides, while non-critical Cure/maintenance/Sleep remain behind pending engage.

### `T3.4i` Add focused action-economy timeline logging for target/engage/cure/buff ordering

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `uc_scheduler_action_state.lua`
  - `tests/replay/harness/selftest_action_economy_timeline_logging.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/action_economy_timeline_logging.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Added a default-off action-economy timeline logger behind `_G.UC_DEBUG_ACTION_TIMELINE = true`.
  - Timeline output is passive, event-only, and rate-limited; no ranking or ownership behavior changes when disabled.
  - Logging covers target acquisition, engage proposal/dispatch, status transitions, Cure/maintenance/Sleep proposal+dispatch, spell start/success/failure, and engage-relevant action-state blocking/release.
- Validation summary:
  - Added focused static+mock coverage for default-off gating, event code coverage, blocker code coverage, low-noise formatting, and rate-limited repeated blocker logging.
  - Kept T3.4g/T3.4h behavior unchanged and did not add direct scheduler side-effect calls.
- Field-test instructions:
  - Set `_G.UC_DEBUG_ACTION_TIMELINE = true`, reload, and compare per-character `action_timeline_<character>.log` files for tank vs DPS pull timing.
  - Inspect the ordering of `TARGET_SELECTED`, `ENGAGE_PROPOSED`, `ENGAGE_DISPATCHED`, `STATUS_CHANGED`, and any Cure/maintenance/Sleep dispatch events.

### `T3.4h` Prevent engage dispatch from being starved by non-critical actions and stale post-spell lockout

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `uc_scheduler_action_state.lua`
  - `tests/replay/harness/selftest_engage_dispatch_priority.lua`
  - `tests/replay/harness/selftest_tank_engage_priority.lua`
  - `tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/engage_dispatch_priority_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Added a narrow engage-preemption rule so a valid engage proposal is selected ahead of non-critical Cure, maintenance buffs, Sleep, and other routine actions once the next target is already selected.
  - Preserved the critical Cure exception using the existing critical-threshold classification.
  - Shortened generic local spell success/interruption lockout for engage follow-up and explicitly clear matching tank spell wait on local spell completion/failure.
- Validation summary:
  - Added focused coverage for engage winning over non-critical action competition, the preserved critical Cure exception, and bounded generic post-spell action-state release after confirmed spell success/interruption.
  - Kept T3.4g target acquisition intact and left ownership/default-off policy unchanged.
- Field-test instructions:
  - Verify a selected valid target engages promptly even when non-critical self-buffs, routine Cure, or Sleep are also available.
  - Verify critical Cure still wins first at or below the existing critical HP threshold.
  - Verify completed or interrupted spells no longer leave a visible stale engage lockout.

### `T3.4g` Decouple next-target acquisition from tank defensive action economy

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_target_acquire_nonblocking.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/target_acquire_nonblocking_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Added a narrow pre-action nonblocking target-acquire lane that runs before ranked action dispatch and before defensive spell wait can stall the tick.
  - Target acquisition still uses the existing target ownership helper seam, but no longer creates a normal pending action lock that can couple target selection to spell/JA/WS action economy.
  - A short role-neutral `0.20` second debounce remains to prevent target-selection spam.
- Validation summary:
  - Added focused static+mock coverage for target acquisition proceeding promptly despite pending Cure, maintenance, Sleep, and critical defensive action contexts, while preserving existing target safety gates and no-direct-side-effect ownership rules.
  - T3.4f engage priority remains intact; this patch decouples the earlier target-acquire stage only.
- Field-test instructions:
  - Compare tank and non-tank next-target selection on the same pull flow and verify both acquire the next valid target promptly.
  - Verify critical Cure may still win action dispatch, but does not delay target selection itself.
  - Verify target selection does not spam repeatedly on the same mob.

### `T3.4f` Prioritize tank next-target engage above non-critical defensive actions

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_tank_engage_priority.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/tank_engage_priority_audit.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Restored explicit scoped engage priority values inside `p1_collect_combat_engage(...)`, fixing a ranking bug where tank engage could lose because undefined locals collapsed its effective score.
  - Raised tank-only pre-engage target acquisition above non-critical defensive actions so tanks can acquire the next valid mob before engage is available.
  - Kept critical Cure above both tank target acquire and tank engage, and left non-tank behavior unchanged.
- Validation summary:
  - Added focused static+mock coverage for tank target-acquire/engage outranking non-critical Cure, maintenance buffs, and Sleep; preserved the critical Cure exception; and confirmed duplicate engage suppression remains intact.
  - No direct scheduler side-effect call expressions were introduced, and ownership promotion/default-off policy did not change.
- Field-test instructions:
  - With `tank` and `autotarget` enabled, verify an unengaged tank acquires and engages the next valid target before spending another non-critical Cure/support action.
  - Verify critical Cure still wins when HP is at or below the existing critical threshold.
  - Verify non-tank characters still behave as before.

### `T3.4e` Hotfix scheduler Sleep runtime nil helper `p1_target_distance_to_id`

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_sleep_toggle.lua`
  - `docs/scheduler_sleep_toggle_parity.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Fixed one invalid bare `p1_target_distance_to_id(...)` callsite by routing it through the existing shared helper table as `p1_combat_helpers.target_distance_to_id(...)`.
  - No Sleep feature behavior changed beyond removing the runtime nil-helper crash.
  - The hard `6.0`-yalm Sleep boundary, first-available configured spell selection, and T3.4d slept-target suppression remain unchanged.
- Validation summary:
  - Added static coverage that fails if the scheduler reintroduces a bare `p1_target_distance_to_id(...)` call where only the shared helper-table function exists.
  - Added mock coverage for the target-id spell revalidation path used by Sleep sends, including both inside-`6.0` and beyond-`6.0` yalm paths.
- Field-test instructions:
  - Keep `Sleep` enabled, present an eligible add within `6.0` yalms, and confirm the scheduler casts without any `p1_target_distance_to_id` runtime error.
  - Move an otherwise eligible add beyond `6.0` yalms and confirm the scheduler still rejects the cast.
  - Sleep target A, then verify target A stays suppressed while target B can still be slept independently.

### `T3.4d` Prevent redundant Sleep casts on already-slept targets

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_sleep_toggle.lua`
  - `tests/replay/harness/selftest_sleep_target_state_suppression.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/scheduler_sleep_toggle_parity.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Scheduler Sleep now rejects targets already controlled by a configured Sleep-family effect before proposing another Sleep cast.
  - Detection prefers the existing scheduler enemy-effect map using configured Sleep-family status ids, then falls back to a bounded local success cache keyed by target id after confirmed local combat Sleep success.
  - The bounded local cache expires after `45.0` seconds and clears on death, despawn/invalid-target sweep, zoning, or known sleep-effect removal.
  - Ordered first-available Sleep spell selection remains intact for other eligible unslept mobs, including while not engaged, and the `6.0`-yalm target boundary remains unchanged.
- Validation summary:
  - Added focused static+mock coverage for already-slept target suppression, per-target scoping, timeout expiry, death clear, effect-tracking precedence, and unchanged first-available spell fallback behavior.
  - No direct scheduler side-effect call expressions were introduced, and ownership promotion/default-off policy remains unchanged.
  - Requested validation sweep passed: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_targeting_common.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_sleep_target_state_suppression.lua`, `lua tests/replay/harness/selftest_scheduler_sleep_toggle.lua`, `lua tests/replay/harness/selftest_sleep_spell_selection.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, and `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- Field-test instructions:
  - Enable `Sleep` with an ordered Sleep spell list and verify the first successful Sleep on target A suppresses repeat Sleep casts on target A.
  - While target A remains slept, present target B and verify the scheduler still uses the first available configured Sleep spell on target B.
  - Verify suppression clears naturally after wake/death/despawn or after the bounded timeout if no exact live effect state is available.

### `T3.4b` complete Sleep spell list UI integration and resolve T3.4a validation blockers

- Status: `DONE`
- Changed files:
  - `UnifiedCombat.lua`
  - `remote_bridge.lua`
  - `unified_scheduler.lua`
  - `UnifiedCombatWinForms/MainForm.cs`
  - `UnifiedCombatWinForms/MainForm.ParityUi.cs`
  - `UnifiedCombatWinForms/MainForm.ParityLogic.cs`
  - `UnifiedCombatWinForms/MainForm.ProfileStore.cs`
  - `tests/replay/harness/selftest_scheduler_sleep_toggle.lua`
  - `tests/replay/harness/selftest_sleep_spell_selection.lua`
  - `tests/replay/harness/selftest_side_effect_inventory.lua`
  - `docs/scheduler_sleep_toggle_parity.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - The real WinForms UI now owns an ordered **Sleep spells** list and sends list edits through `remote_bridge.lua` into the same `settings.sleepspells` data used by slash commands.
  - `settings.sleepspell` remains the backward-compatible first-entry mirror of the ordered list.
  - Scheduler Sleep behavior is unchanged apart from remaining parse-clean under Lua 5.1; Sleep still works while not engaged and still uses the first available configured spell.
- Validation summary:
  - Fixed the Lua 5.1 parse blocker by moving Sleep/spell-target helper logic onto a shared `p1_combat_helpers` table, reducing top-level chunk locals without changing behavior.
  - Confirmed the side-effect inventory mismatches were line-pin drift only and updated `UnifiedCombat.lua | windower.ffxi.run(` to line `355` plus `remote_bridge.lua | windower.send_command(` to line `1572`.
  - Requested Lua validation sweep now passes, and `UnifiedCombatWinForms.csproj` also builds cleanly in `Release`.
- Field-test instructions:
  - Open the session in WinForms, toggle `Sleep`, edit the ordered **Sleep spells** list, and click Save so the bridge pushes the list into runtime settings.
  - Verify `//uc sleep list` matches the UI order, then verify Sleep still falls through to the next configured spell when the first choice is unavailable.
  - Verify Sleep remains usable pre-engage / while not engaged and does not steal the current kill target.

### `T3.4c` enforce 6-yalm Sleep target boundary in scheduler Sleep behavior

- Status: `DONE`
- Changed files:
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_sleep_toggle.lua`
  - `tests/replay/harness/selftest_sleep_spell_selection.lua`
  - `docs/scheduler_sleep_toggle_parity.md`
  - `docs/UnifiedCombat_scheduler_refactor_tracking.md`
- Runtime behavior:
  - Scheduler Sleep now enforces a hard `SLEEP_MAX_TARGET_DISTANCE = 6.0` rule before proposal emission.
  - Selected spell range still matters, but the effective allowed range is now `min(spell cast range, 6.0)`.
  - First-available spell selection remains intact; it only runs on targets inside the 6-yalm Sleep boundary.
- Validation summary:
  - Added static+mock coverage for pre-engage and engaged Sleep inside `6.0` yalms, rejection beyond `6.0`, and fallback-to-next-spell behavior within the hard boundary.
  - No scheduler ownership routing changed and no new direct scheduler side-effect expressions were introduced.
- Field-test instructions:
  - Keep `Sleep` enabled, position an eligible add at `6.0` yalms or closer, and verify Sleep can still trigger.
  - Move an otherwise eligible add just beyond `6.0` yalms and verify no Sleep proposal/cast occurs even when the configured spell would normally reach farther.
  - Verify both pre-engage and engaged add-control Sleep obey the same `6.0`-yalm limit.

### `T3.4a` scheduler-owned Sleep toggle with UI-owned configurable Sleep spell list

- Status: `DONE`
- Changed files:
  - `UnifiedCombat.lua`
  - `unified_scheduler.lua`
  - `tests/replay/harness/selftest_scheduler_sleep_toggle.lua`
  - `tests/replay/harness/selftest_sleep_spell_selection.lua`
  - `tests/replay/harness/selftest_all_replay_fixtures.lua`
  - `docs/scheduler_sleep_toggle_parity.md`
- Runtime behavior:
  - Existing `sleep` toggle now gates a scheduler-owned Sleep proposal path when scheduler combat ownership is active.
  - Sleep spell selection is now driven by ordered `settings.sleepspells`, with legacy `settings.sleepspell` preserved as a backward-compatible first-entry mirror.
  - Scheduler Sleep casts send by target id through the existing combat spell ownership seam, so Sleep can work while not engaged without hijacking the current target.
- Validation summary:
  - Added focused static+mock coverage for ordered Sleep spell selection and scheduler Sleep proposal gating/ranking.
  - Full requested validation command set pending per-task run after code/doc updates.
- Field-test instructions:
  - Use `//uc sleep list|set <spell>|add <spell>|remove <n>|clear` to configure the ordered spell list.
  - Enable scheduler combat ownership, turn `sleep` on, and verify Sleep triggers only for live eligible adds and falls through to the next configured spell when the first choice is unavailable.

## 2) Progress Board

Legend:
- `DONE` = implemented and self-tested.
- `IN PROGRESS` = partially implemented.
- `NOT STARTED` = not yet implemented in code.

| Area | Status | Notes |
| --- | --- | --- |
| Replay harness base (copy/guard/compare) | DONE | Includes side-effect trap and structural compare foundation. |
| Fixture schema validation | DONE | Fixture validator + self-test implemented. |
| Single fixture execution harness | DONE | Fixture runner + self-test implemented. |
| Fixture suite execution harness | DONE | Suite runner + self-test implemented, with expected pass/fail fixture support. |
| Aggregate replay self-test runner | DONE | Single-command aggregate self-test for full harness + fixture layer coverage. |
| Runtime parse self-test | DONE | Parse-only compile-check for runtime Lua files; included in aggregate replay self-test runner. |
| Side-effect callsite inventory self-test | DONE | Source-text baseline inventory for side-effect callsite counts/locations; included in aggregate replay self-test runner. |
| Dispatcher contract skeleton | IN PROGRESS | Dark-launch dispatcher contract module + fixture coverage added; not wired into scheduler side-effect execution yet. |
| T2.1 dark-launch command intent construction | IN PROGRESS | One scheduler `send_command` path validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.2 dark-launch target-select intent construction | IN PROGRESS | One scheduler `select_by_id` path validates dispatcher intent beside existing call; publishes object-form validation status and leaves target-select execution unchanged. |
| T2.3 dark-launch run intent construction | IN PROGRESS | One scheduler `run` path validates dispatcher intent beside existing call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.3c dark-launch turn intent construction | IN PROGRESS | One scheduler `turn` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves turn execution unchanged. |
| T2.3d dark-launch combat command intent construction | IN PROGRESS | One scheduler combat/non-defensive `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3e dark-launch JA command intent construction | IN PROGRESS | One scheduler JA target-send `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3f dark-launch JA self-command intent construction | IN PROGRESS | One scheduler JA self-send `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3g dark-launch spell target-command intent construction | IN PROGRESS | One scheduler spell target-send `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3h dark-launch spell self-command intent construction | IN PROGRESS | One scheduler spell self-send `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3i dark-launch defensive_internal command intent construction | IN PROGRESS | One scheduler `defensive_internal` `send_command(cmd)` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3j dark-launch maintenance_cor command intent construction | IN PROGRESS | One scheduler `maintenance_cor` `send_command(maintenance_cor_command)` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3k dark-launch Doom Holy Water command intent construction | IN PROGRESS | One scheduler Doom emergency `send_command(doom_holy_water_command)` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3l T2.1 status-shape normalization | DONE | Older T2.1 scheduler command validation now publishes the object-form status payload used by newer command slices; command execution remains unchanged. |
| T2.3m T2.2 target status-shape normalization | DONE | Older T2.2 target-select validation now publishes object-form status while target selection execution remains unchanged. |
| T2.3n T2.3 run status-shape normalization | DONE | Older T2.3 run validation now publishes object-form status while movement execution remains unchanged. |
| T2.3o tracker wording cleanup | DONE | T2.1/T2.2/T2.3 tracker wording now reflects object-form validation status while preserving validation-only and unchanged live execution descriptions. |
| T2.3b run-vector dispatcher contract pin | IN PROGRESS | Dispatcher contract and fixtures now pin canonical `run_x`/`run_y` vector semantics (including coercion/rejection and deps.run dispatch), while dark-launch runtime execution remains unchanged. |
| T2.4b movement-stop dispatcher contract pin | IN PROGRESS | Dispatcher contract and fixtures now pin `kind='run_stop'` stop-movement semantics: no run vector required, dry-run remains no-op, and execute mode uses injected `deps.run(false)`. |
| T2.4c dark-launch run_stop intent construction | IN PROGRESS | One scheduler cast-freeze prep `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4d dark-launch pull-cast-hold run_stop intent construction | IN PROGRESS | The scheduler `MOVE_COORD_PULL_CAST_HOLD` `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4e dark-launch pull-spell-wait run_stop intent construction | IN PROGRESS | The scheduler `MOVE_COORD_PULL_SPELL_WAIT` `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4f dark-launch tank-action-settle run_stop intent construction | IN PROGRESS | The scheduler tank enmity action settle `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4g dark-launch tank-spell-settle run_stop intent construction | IN PROGRESS | The scheduler tank enmity spell settle `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4h dark-launch tank-enmity spell send run_stop intent construction | IN PROGRESS | One scheduler tank-enmity spell target-send-adjacent `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4i dark-launch tank-enmity spell self-send run_stop intent construction | IN PROGRESS | The scheduler tank-enmity spell self-send-adjacent `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4j dark-launch Doom emergency run_stop intent construction | IN PROGRESS | The scheduler Doom emergency `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call before Holy Water use; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4k dark-launch tank-enmity JA self-send run_stop intent construction | IN PROGRESS | The scheduler tank-enmity JA self-send-adjacent `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4l dark-launch combat spell-settle run_stop intent construction | IN PROGRESS | The scheduler generic combat spell-settle `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4m dark-launch combat spell prep-wait run_stop intent construction | IN PROGRESS | The scheduler generic combat spell prep-wait `windower.ffxi.run(false)` path now validates `kind='run_stop'` beside the existing stop call; publishes object-form validation status and leaves movement execution unchanged. |
| T2.4n run_stop dark-launch coverage audit | DONE | Audit confirmed every current scheduler `windower.ffxi.run(false)` callsite has nearby validation-only `kind='run_stop'` coverage with object-form status; no runtime code changed. |
| T2.4o full scheduler side-effect dark-launch coverage audit | DONE | Audit confirmed every current scheduler side-effect callsite tracked for `send_command`, `run`, `turn`, and `select_by_id` has nearby validation-only dispatcher intent coverage with object-form status; no runtime code changed. |
| T2.4p dispatcher fixture coverage audit | DONE | Audit confirmed scheduler dark-launch intent kinds have dispatcher fixture coverage for validation, dry-run no-call behavior, execute dependency calls, and missing-dependency failure; added fixture coverage and pinned scheduler-used `select_target` dispatcher support. |
| T2.5a first dispatcher runtime-ownership candidate audit | DONE | Audit recommends the isolated scheduler face-to-target `turn` callsite as the first runtime-ownership migration candidate; no runtime code changed. |
| T2.5b default-off turn dispatcher ownership flag | IN PROGRESS | The selected face-to-target `turn` callsite now routes through dispatcher only when `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP == true`; default behavior remains the direct `windower.ffxi.turn(heading)` call, with direct-call fallback on dispatcher failure. |
| T2.5c turn ownership static selftest | DONE | Added focused static selftest coverage for the T2.5b default-off turn ownership guard, dispatcher execute dependency injection, direct fallback callsite, and ownership/fallback status fields. |
| T2.5d turn ownership runtime-style test feasibility audit | DONE | Audit found no safe existing Windower-free runtime-style seam for executing the exact face-to-target turn branch without broad scheduler load or brittle source extraction; no runtime code or tests changed. |
| T2.5e turn ownership helper seam | IN PROGRESS | Added `uc_scheduler_turn_ownership.lua` as a Windower-free injected-dependency helper and runtime-style selftest coverage for default-off direct turn, flag-on dispatcher success, and flag-on fallback behavior. |
| T2.5f second dispatcher runtime-ownership candidate audit | DONE | Audit recommends the scheduler target-select path as the next ownership candidate, using a narrow helper seam that preserves `select_by_id(tid) == true` return semantics by capturing the injected dispatcher dependency return. |
| T2.5g target ownership helper seam | IN PROGRESS | Added `uc_scheduler_target_ownership.lua`, extended dispatcher execute results to expose injected target-select return semantics, and routed only `p1_try_target_prep` through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP == true` with direct-call fallback on dispatcher failure. |
| T2.5h maintenance COR command ownership helper seam | IN PROGRESS | Added `uc_scheduler_command_ownership.lua` and routed only the isolated maintenance COR `send_command` path through it behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == true`, with direct-send fallback on dispatcher failure and fail-safe skip on blank command. |
| T2.5i defensive_internal command ownership routing | IN PROGRESS | Reused `uc_scheduler_command_ownership.lua` for the isolated `provider == 'defensive_internal'` command path behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == true`, with default-off direct send, dispatch execute on flag-on, and direct-send fallback on dispatcher failure. |
| T2.5j Doom Holy Water command ownership routing | IN PROGRESS | Reused `uc_scheduler_command_ownership.lua` for the isolated Doom Holy Water emergency command path behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP == true`, preserving the prior stop and cooldown gates while moving only the item command send behind default-off ownership with direct-send fallback on dispatcher failure. |
| T2.5k remaining direct send_command ownership review | IN PROGRESS | Reviewed the six remaining direct scheduler `windower.send_command(` callsites and stopped without additional routing because every remaining path is broad combat or shared dispatch behavior with target-state, settle/stop, or combat-timing coupling that makes fallback safety and duplicate-send parity unclear without a larger contract decision. |
| T2.5l combat JA command family ownership routing | IN PROGRESS | Reused `uc_scheduler_command_ownership.lua` for the combat JA target/self command family behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true`, preserving the existing readiness, target, and stop checks while moving only the final JA command sends behind default-off family ownership with direct-send fallback on dispatcher failure. |
| T2.5m combat spell command family ownership routing | IN PROGRESS | Reused `uc_scheduler_command_ownership.lua` for the combat spell target/self command family behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true`, preserving the existing readiness, target, settle, prep-wait, and stop checks while moving only the final spell command sends behind default-off family ownership with direct-send fallback on dispatcher failure. |
| T2.5n combat WS command ownership routing | IN PROGRESS | Reused `uc_scheduler_command_ownership.lua` for the combat WS command path behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP == true`, preserving the existing readiness, TP, target, and action checks while moving only the final WS command send behind default-off ownership with direct-send fallback on dispatcher failure. |
| T2.5o final internal dispatch send ownership routing | IN PROGRESS | Reused `uc_scheduler_command_ownership.lua` for the final shared T2.1 internal defensive dispatch command path behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP == true`, preserving the existing block/cooldown/order semantics while moving only the final shared direct send behind default-off ownership with direct-send fallback on dispatcher failure. |
| T2.6a first run_stop ownership helper seam | IN PROGRESS | Added `uc_scheduler_run_stop_ownership.lua` and routed only the isolated Doom Holy Water emergency stop through it behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP == true`, preserving the existing stop-before-item ordering while keeping default-off direct `run(false)` behavior and direct fallback on dispatcher failure. |
| T2.6b movement-coordinator run_stop ownership routing | IN PROGRESS | Reused `uc_scheduler_run_stop_ownership.lua` for the movement-coordinator freeze/pull stop family behind branch-specific default-off flags, preserving the existing `CAST_FREEZE` block reasons and returning the same movement-block decisions while moving only the final `run(false)` stops behind runtime ownership with direct fallback on dispatcher failure. |
| T2.6c combat-spell run_stop ownership routing | IN PROGRESS | Reused `uc_scheduler_run_stop_ownership.lua` for the generic combat-spell settle/prep-wait stop pair behind branch-specific default-off flags, preserving the existing spell prep/settle gating and block returns while moving only the final `run(false)` stops behind runtime ownership with direct fallback on dispatcher failure. |
| T2.6d tank-enmity spell send-adjacent run_stop ownership routing | IN PROGRESS | Reused `uc_scheduler_run_stop_ownership.lua` for the tank-enmity spell target/self send-adjacent stop pair behind branch-specific default-off flags, preserving the existing tank spell branch gating and adjacent owned spell-send order while moving only the final `run(false)` stops behind runtime ownership with direct fallback on dispatcher failure. |
| T2.6f vector run ownership parity and routing | IN PROGRESS | Added `uc_scheduler_run_ownership.lua` and routed the final vector run path behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP == true` after proving parity through a heading-preserving injected dispatcher adapter; default-off keeps the original direct heading call and dispatcher failure falls back to the same heading call once. |
| T2.7a scheduler side-effect ownership phase closure | DONE | Added static closure coverage confirming `unified_scheduler.lua` now has zero direct textual side-effect call expressions for `send_command`, `run`, `turn`, and `select_by_id`; cleaned stale current-state tracker wording; ownership remains routed through helper/dispatcher seams behind default-off flags and runtime behavior is unchanged. |
| T2.7b ownership promotion plan and flag guard | DONE | Added a promotion-readiness manifest for all default-off ownership flags plus a static flag guard that inventories scheduler ownership flags, enforces explicit `== true` checks, confirms rollback/default-off wording in the plan, and leaves runtime behavior unchanged with no flags promoted. |
| T2.7c ownership field-test packet and evidence template | DONE | Added a staged field-test packet covering all 21 ownership flags, a reusable evidence/results template, and a static doc guard that verifies packet coverage, rollback/default-off warnings, and stage references; runtime behavior remains unchanged and no flags were promoted. |
| T2.7d local ownership field-test flag loader | DONE | Added an optional protected `local_ownership_flags.lua` load in `UnifiedCombat.lua` so manual field testing can set ownership globals without changing defaults; missing file keeps behavior unchanged, load failures warn without crashing, and docs now include an exact Stage 1 example file. |
| Stage 7 vector run ownership reachability audit | DONE | Audited `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` and found the vector run ownership status is only written from `p1_move_toward_mob(...)`, which currently has no live caller in scheduler runtime dispatch flow; updated Stage 7 docs/results to mark the slice deferred/not live-reachable rather than failed. |
| T2.8a movement priority and vector run decision audit | DONE | Added docs-only audit coverage for the follow/return-to-leader vs prime/autotarget combat movement conflict, documented the recommended conservative arbitration rule, and recorded the recommendation to leave `p1_move_toward_mob(...)` dormant until a future explicit runtime movement decision. |
| T2.8b default-off movement priority arbitration guard | DONE | Added a default-off combat-transition arbitration guard for follow/path resume behavior behind `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION == true`, reusing existing combat intent/owner/lock fields without altering combat movement or scheduler ownership helpers. |
| T2.8c movement arbitration flag-on hardening audit | DONE | Confirmed default-off safety, reviewed the earlier flag-on freeze, and hardened the flag-on path by removing over-broad live-target suppression so only explicit transition signals can suppress follow/path resume behavior; no runtime redesign or ownership changes were made. |
| T2.8d movement arbitration release refinement | DONE | Kept the flag-on yoyo fix but refined the release condition so stale combat-intent or fight-follow timeouts no longer suppress follow after combat ends unless a live transition target, active preengage, or active core movement lock still exists. |
| T2.9a 0 HP death-animation target validity audit | DONE | Added a docs-only audit for the post-WS 0 HP / death-animation yoyo, confirmed that many scan-time checks already require `hpp > 0` but some final engage / WS / movement revalidation paths still rely on `valid_target` + id only, and recommended a narrow commit-time actionable-target predicate as the next slice. |
| T2.9b final actionable-target predicate for 0 HP targets | DONE | Added `is_live_actionable_combat_target(...)` in `unified_combat_core.lua`, wired it into core engage plus scheduler engage / WS commit-time revalidation, and added focused harness coverage for 0 HP, malformed, and recent-death target cases without changing broad scan logic. |
| T2.9c remaining 0 HP WS-animation movement churn guard | DONE | Confirmed T2.9b fixed engage / WS recommit but missed the end-of-tick combat movement path, then guarded `apply_movement(...)` with the same actionable-target predicate so 0 HP / recent-death current targets no longer produce movement intent while different live targets still transition normally. |
| T3.0a scheduler ownership promotion readiness audit | DONE | Added a docs-only ownership promotion readiness audit that inventories all 21 scheduler ownership flags, separates scheduler-owned seams from core/pathing/follow systems, recommends 11 low-risk default-on candidates, keeps 9 flags default-off for now, and marks vector run ownership as unreachable/dormant rather than promotion-ready. |
| T3.0b promote low-risk field-tested scheduler ownership flags | DONE | Promoted 11 low-risk scheduler ownership paths to default-on by extending helper gating semantics, preserved per-flag `false` opt-out plus shared temporary kill switch `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true`, and left deferred/tank/Doom/vector flags on explicit default-off behavior. |
| T3.0c close promoted ownership field-test pass and define remaining default-off policy | DONE | Closed the T3.0b promotion field test as PASS in docs, confirmed the 11 promoted paths remain accepted as default-on with no rollback/opt-out needed, and documented the near-term default-off policy for Doom, combat-spell run_stop, tank run_stop, and dormant vector-run ownership without changing runtime behavior. |
| T3.1a targeted coverage plan for remaining default-off scheduler run_stop ownership paths | DONE | Added a docs-only per-path coverage plan for the remaining default-off Doom, combat-spell, and tank ownership branches, separated replay/mock-first work from realistic field-packet work, kept vector run parked as a separate dormant path, and recommended a replay/mock-first T3.1b slice without changing runtime behavior. |
| T3.2a alliance target-scope audit for targeting, claim, and aggro validity | DONE | Added a docs-only audit of party-only target-validity assumptions across core, scheduler, and fight-leader helpers; identified the central party-only claim/id collectors that should become friendly combat group helpers for alliance support; paused T3.1b temporarily; and left runtime behavior unchanged. |
| T3.2b alliance-aware friendly combat target scope | DONE | Added default-off alliance-aware friendly combat member helpers in `uc_targeting_common.lua` and wired them into low-risk claim validity, prime/aggressive-target inference, scheduler engage/dispel claim checks, and tank victim detection while intentionally leaving fight-leader, follow/pathing, spacing, and party TP/WS observation party-only. |
| T3.2c alliance target-scope field-test closure | DONE | Documented the successful T3.2b field-test PASS, confirmed no regressions were observed, kept the alliance scope flag optional for now, and unpaused the scheduler ownership track so `T3.1b` can resume next without changing runtime behavior. |
| T3.1b replay/mock coverage for remaining Doom and combat-spell default-off ownership branches | DONE | Added focused static+mock coverage for the Doom Holy Water command, Doom run_stop, combat spell settle run_stop, and combat spell prep-wait run_stop default-off branches, confirmed they remain explicit `== true` paths with fallback preserved, and left runtime behavior unchanged. |
| T3.1c combat-spell default-off run_stop promotion policy decision | DONE | Documented that the combat-spell settle/prep-wait run_stop pair are future promotion candidates only after targeted live confirmation, kept Doom command/run_stop intentionally default-off, and left runtime behavior unchanged. |
| T3.1d targeted combat-spell run_stop field-test packet | DONE | Added a focused field-test packet for the combat-spell settle/prep-wait run-stop pair, kept Doom branches outside the packet, and left runtime behavior unchanged. |
| T3.1e scheduler tank-spell movement-lock mismatch fix | DONE | Fixed the scheduler tank-spell runtime bug where movement could resume after the pre-send stop while the spell was still in flight by adding a bounded scheduler-local tank-spell wait lock; ownership promotion policy remains unchanged. |
| T3.1e cure-cast movement-stop audit correction | DONE | Audited the corrected Cure-cast movement-stop report, found the most likely source in the scheduler defensive Cure paths rather than tank spell routing, documented the missing stop/lock lifecycle, and left runtime behavior unchanged. |
| T3.1f scheduler defensive Cure movement-stop/lock lifecycle fix | DONE | Fixed the scheduler defensive Cure/spell runtime bug by adding a bounded scheduler-owned stop/lock lifecycle at the direct and ranked defensive internal spell send points, while leaving ownership promotion policy unchanged. |
| T3.1g defensive Cure priority audit and chooser fix | DONE | Audited defensive candidate generation and confirmed valid Cure candidates were losing to normal self-buff selection in `choose_defensive_action(...)`; applied the first narrow chooser fix for ordinary self-buff preemption, which was later refined in T3.1h after Majesty-over-Cure field-use correction. |
| T3.1h Majesty-over-Cure restoration and defensive JA-to-Cure follow-up | DONE | Restored Majesty as a special defensive setup action that can beat Cure, kept ordinary self-buffs from beating valid Cure candidates, and added a bounded defensive-only Majesty->Cure action-state allowance so the follow-up Cure is not delayed behind the generic JA acting/cooldown block. |
| T3.1i bounded JA/WS weave allowance between repeated Cure actions | DONE | Added a narrow final-selection weave policy so repeated non-critical defensive Cure sends can allow exactly one eligible combat JA or WS between Cure casts, without restoring ordinary self-buff starvation or changing ownership policy. |
| T3.1i hb_buff_maint Majesty preference in defensive buff candidate selection | DONE | Confirmed the remaining Majesty gap was upstream of the chooser and updated `uc_hb_buff_maint.choose(...)` so an eligible missing ready Majesty candidate is surfaced ahead of other ordinary defensive buffs, while preserving existing readiness/recast/missing/throttle gates and leaving ownership policy unchanged. |
| T3.1j cast interruption action-state audit | DONE | Audited incoming `0x029` action-message handling and found broad self action-message packet-end wiring plus core pull/tank spell retry clearing, but no exact `<playername>'s casting is interrupted` handling and no scheduler defensive spell-wait interruption bridge; no runtime behavior changed. |
| T3.1k local-player scheduler defensive spell interruption handling | DONE | Added a narrow scheduler `0x029` local-player defensive spell interruption/failure bridge that clears scheduler defensive spell wait, clears/shortens local defensive spell action-state cooldown, and only shortens scheduler-owned movement lock; unrelated JA/WS/core state and ownership policy remain unchanged. |
| T3.1l spell cast start/success handling audit | DONE | Audited local-player and other-player spell start/success handling across action packets and raw `0x029` action messages, confirmed scheduler action-state start/end behavior, and documented that scheduler defensive spell success still releases by later polling instead of an explicit success bridge; no runtime behavior changed. |
| T3.1m local-player scheduler defensive spell success handling | DONE | Added a narrow scheduler `0x029` local-player defensive spell success bridge that clears scheduler defensive spell wait promptly, shortens local defensive spell action-state and scheduler-owned movement lock to bounded tails, removes `spell_finish` from the scheduler start-marker bucket, and leaves ownership policy unchanged. |
| T3.1n delayed target acquisition and engage audit | DONE | Audited the full death→target→engage pipeline and found the strongest evidence-backed delay candidate in scheduler action-state: successful engage sends enter the generic 8-second acting timeout path via `action_mark_sent('engage')`, but no engage-specific completion bridge is visible; target-control/engage sequencing and short engaged/sticky windows appear secondary. No runtime behavior changed and no diagnostics were added. |
| T3.1o scheduler engage action-state release fix | DONE | Added a narrow engage-specific scheduler action-state policy so successful engage sends no longer enter the generic 8-second acting timeout path, and now leave only a short bounded cooldown debounce while preserving duplicate/pending suppression and leaving spell/JA/WS timing and ownership policy unchanged. |
| T3.4a scheduler-owned Sleep toggle with UI-owned configurable Sleep spell list | DONE | Added ordered `sleepspells` settings + legacy `sleepspell` migration in `UnifiedCombat.lua`, added a scheduler combat Sleep proposal path with first-available spell selection in `unified_scheduler.lua`, preserved existing ownership promotion/default-off policy, and added focused static+mock replay coverage plus parity docs. |
| 0x063 status snapshot parser fixtures | DONE | Real extracted parser module covered by permanent fixtures and suite. |
| Enemy effect utils fixtures | DONE | Full helper coverage including edge-case top-up completed. |
| Text utils fixtures | DONE | Core text normalization/decoding/splitting helpers covered. |
| Action metadata fixtures | DONE | Metadata coercion/lookup/range/target-mode helpers covered. |
| Command builder fixtures | DONE | String command construction coverage added (no command execution). |
| Numeric utils fixtures | DONE | Numeric coercion, urgency clamp, bool setting behavior covered. |
| Proposal key fixtures | DONE | Family/attempt key construction behavior covered. |
| Maintenance utils fixtures | DONE | Set, dedupe, split/canon, buff counting helpers covered. |
| Defensive utils fixtures | DONE | Full exported helper coverage added. |
| Action predicates fixtures | DONE | JA enemy-target and engaged-front predicates covered. |
| Geometry fixtures | DONE | Angle normalization and front-arc checks covered via windower stubs. |
| Context utils fixtures | DONE | Global/stub-driven context helpers covered with safe restore logic. |
| Target utils fixtures | DONE | Tank-enmity selection and target distance helper coverage completed with windower stubs. |
| Rank output fixtures | DONE | Ranking output formatting/capture/reject-summary helpers covered. |
| Pending record fixtures | DONE | Pending-record build/no-op/duplicate suppression helper behavior covered. |
| Reject history fixtures | DONE | Reject line/item capture and max-keep trimming helper behavior covered. |
| Action state fixtures | DONE | Action-state lifecycle/timeout/blocking helpers covered. |
| Locks fixtures | DONE | Lock-state helpers and reset behavior covered in non-runtime fixtures. |
| Dispatch plan fixtures | DONE | Dispatch-plan build and commit revalidation helpers covered. |
| Pending fixtures | DONE | Pending-state lifecycle/global publish/complete-mark helpers covered. |
| Dryrun publish fixtures | DONE | Dry-run publish phase/global output helper coverage completed. |
| Dispatcher ownership migration | NOT STARTED | RFC T2.x runtime migration work remains. |
| Provider extraction/cutover | NOT STARTED | RFC T3.x runtime migration work remains. |
| Movement ownership runtime migration | NOT STARTED | RFC T4.x runtime migration work remains. |
| Domain cutover checklists and fallback removal | NOT STARTED | RFC T5.x and post-parity runtime cleanup remain. |

### 2.1 T2.4n run_stop coverage audit

| Line | Stop context | Covering slice | Status |
| --- | --- | --- | --- |
| 865 | Doom Holy Water emergency stop before item path | T2.4j | covered |
| 1089 | Movement coordinator cast-freeze prep block | T2.4c | covered |
| 1113 | Movement coordinator pull-cast-hold block | T2.4d | covered |
| 1136 | Movement coordinator pull-spell-wait block | T2.4e | covered |
| 3836 | Tank-enmity action settle before JA/spell dispatch | T2.4f | covered |
| 4013 | Tank-enmity JA self-send-adjacent stop | T2.4k | covered |
| 4079 | Generic combat spell-settle stop | T2.4l | covered |
| 4105 | Generic combat spell prep-wait stop | T2.4m | covered |
| 4149 | Tank-enmity spell settle stop | T2.4g | covered |
| 4188 | Tank-enmity spell target-send-adjacent stop | T2.4h | covered |
| 4235 | Tank-enmity spell self-send-adjacent stop | T2.4i | covered |

### 2.2 T2.4o full scheduler side-effect coverage audit

Historical note: the callsite tables in sections 2.2 through 2.4 are pre-ownership audit snapshots kept for rollout history. Current scheduler closure state is tracked by T2.7a, not by these pre-routing inventories or candidate recommendations.

#### `windower.send_command(`

| Line | Side-effect call | Context | Intent kind | Covering slice | Validation global | Status |
| --- | --- | --- | --- | --- | --- | --- |
| 891 | `windower.send_command(doom_holy_water_command)` | Doom Holy Water emergency item command | `send_command` | T2.3k | `_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE` | covered |
| 2202 | `windower.send_command(cmd)` | Internal defensive action command | `send_command` | T2.1 | `_G.UC_SCHED_P1_DARKLAUNCH_DISPATCH_VALIDATE` | covered |
| 3934 | `windower.send_command(ws_command)` | Combat WS fallback command | `send_command` | T2.3d | `_G.UC_SCHED_P1_DARKLAUNCH_COMBAT_COMMAND_VALIDATE` | covered |
| 3986 | `windower.send_command(ja_target_command)` | Combat JA target-send command | `send_command` | T2.3e | `_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE` | covered |
| 4034 | `windower.send_command(ja_self_command)` | Combat JA self-send command | `send_command` | T2.3f | `_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE` | covered |
| 4210 | `windower.send_command(spell_target_command)` | Combat spell target-send command | `send_command` | T2.3g | `_G.UC_SCHED_P1_DARKLAUNCH_SPELL_TARGET_COMMAND_VALIDATE` | covered |
| 4256 | `windower.send_command(spell_self_command)` | Combat spell self-send command | `send_command` | T2.3h | `_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE` | covered |
| 4334 | `windower.send_command(cmd)` | Phase-1 defensive_internal command | `send_command` | T2.3i | `_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE` | covered |
| 4421 | `windower.send_command(maintenance_cor_command)` | Maintenance COR self JA command | `send_command` | T2.3j | `_G.UC_SCHED_P1_DARKLAUNCH_MAINTENANCE_COR_COMMAND_VALIDATE` | covered |

#### `windower.ffxi.run(`

| Line | Side-effect call | Context | Intent kind | Covering slice | Validation global | Status |
| --- | --- | --- | --- | --- | --- | --- |
| 865 | `windower.ffxi.run(false)` | Doom Holy Water emergency stop before item path | `run_stop` | T2.4j | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE` | covered |
| 1089 | `windower.ffxi.run(false)` | Movement coordinator cast-freeze prep block | `run_stop` | T2.4c | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE` | covered |
| 1113 | `windower.ffxi.run(false)` | Movement coordinator pull-cast-hold block | `run_stop` | T2.4d | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE` | covered |
| 1136 | `windower.ffxi.run(false)` | Movement coordinator pull-spell-wait block | `run_stop` | T2.4e | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE` | covered |
| 3682 | `windower.ffxi.run(heading)` | Vector run toward target mob | `run` | T2.3 | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` | covered |
| 3836 | `windower.ffxi.run(false)` | Tank-enmity action settle before JA/spell dispatch | `run_stop` | T2.4f | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE` | covered |
| 4013 | `windower.ffxi.run(false)` | Tank-enmity JA self-send-adjacent stop | `run_stop` | T2.4k | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE` | covered |
| 4079 | `windower.ffxi.run(false)` | Generic combat spell-settle stop | `run_stop` | T2.4l | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE` | covered |
| 4105 | `windower.ffxi.run(false)` | Generic combat spell prep-wait stop | `run_stop` | T2.4m | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE` | covered |
| 4149 | `windower.ffxi.run(false)` | Tank-enmity spell settle stop | `run_stop` | T2.4g | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE` | covered |
| 4188 | `windower.ffxi.run(false)` | Tank-enmity spell target-send-adjacent stop | `run_stop` | T2.4h | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE` | covered |
| 4235 | `windower.ffxi.run(false)` | Tank-enmity spell self-send-adjacent stop | `run_stop` | T2.4i | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE` | covered |

#### `windower.ffxi.turn(`

| Line | Side-effect call | Context | Intent kind | Covering slice | Validation global | Status |
| --- | --- | --- | --- | --- | --- | --- |
| 3653 | `windower.ffxi.turn(heading)` | Scheduler-owned face-to-target turn | `turn` | T2.3c | `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` | covered |

#### `uc_settarget.select_by_id(`

| Line | Side-effect call | Context | Intent kind | Covering slice | Validation global | Status |
| --- | --- | --- | --- | --- | --- | --- |
| 3599 | `uc_settarget.select_by_id(tid)` | Scheduler target prep by mob id | `select_target` | T2.2 | `_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE` | covered |

### 2.3 T2.4p dispatcher fixture coverage audit

| Intent kind | Scheduler dark-launch source | Existing/new fixture coverage | Status |
| --- | --- | --- | --- |
| `send_command` | T2.1, T2.3d-k command validation globals | Added valid validation, dry-run no-call, execute via injected `deps.send_command`, and missing `deps.send_command` failure; existing missing-command validation retained. | covered |
| `select_target` | T2.2 target validation global `_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE` | Added valid validation, invalid target-id rejection, dry-run no-call, execute via injected `deps.set_target`, and missing `deps.set_target` failure; dispatcher now supports scheduler-used `kind='select_target'` while retaining existing `set_target` fixtures. | covered |
| `run` | T2.3 vector-run validation global `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` | Existing valid validation, invalid/missing vector validation, dry-run no-call, and execute via injected `deps.run` retained; added missing `deps.run` failure. | covered |
| `run_stop` | T2.4c-m run-stop validation globals | Existing valid validation, dry-run no-call, execute via injected `deps.run(false)`, and missing `deps.run` failure retained; no additional required fields apply. | covered |
| `turn` | T2.3c turn validation global `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` | Added valid validation, missing heading rejection, dry-run no-call, and execute via injected `deps.turn`; existing missing `deps.turn` failure retained. | covered |

### 2.4 T2.5a first dispatcher runtime-ownership candidate audit

| Candidate | Current live side-effect | Existing intent/global | Dispatcher kind | Risk level | Required guard/flag for migration | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| Target-select path | `uc_settarget.select_by_id(tid)` at scheduler target prep | `_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE` from T2.2 | `select_target` | Medium | Dedicated runtime ownership flag plus preserved boolean result semantics from `select_by_id` | Defer; isolated and fixture-covered, but current dispatcher execute result does not propagate the dependency return that scheduler stores in `ok`. |
| Doom Holy Water command path | `windower.send_command(doom_holy_water_command)` after Doom checks and item cooldown | `_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE` from T2.3k | `send_command` | High | Emergency-path-specific ownership flag and rollback path that restores direct send immediately | Defer; semantics are clear but gameplay/emergency risk is higher than needed for the first ownership cutover. |
| Isolated run_stop path | Example: Doom emergency `windower.ffxi.run(false)` or movement coordinator stop blocks | T2.4c-m `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_*_VALIDATE` globals | `run_stop` | Medium | Per-callsite ownership flag with exact `run(false)` execution parity and quick direct-call rollback | Defer; dispatcher contract is ready, but movement-stop ownership can affect casting/movement timing and should follow a lower-risk non-returning callsite. |
| Turn heading path | `windower.ffxi.turn(heading)` in `p1_apply_face_to_target` | `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` from T2.3c | `turn` | Low | One narrowly scoped scheduler ownership flag, default off; when enabled, execute through dispatcher with injected `turn = windower.ffxi.turn`, retaining direct call as rollback path for the slice | Choose first; isolated single callsite, stable intent already adjacent, no live return value to preserve, execute/missing-dependency fixtures exist, and rollback is a one-line restoration to direct `windower.ffxi.turn(heading)`. |
| Run vector path | `windower.ffxi.run(heading)` in `p1_move_toward_mob` | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` from T2.3 | `run` | High | Movement ownership flag plus confirmed parity between heading-based live call and dispatcher vector `run_x`/`run_y` execution | Defer; current live call uses heading while dispatcher execution owns vector arguments, so migration needs explicit parity proof before ownership cutover. |
| Combat/maintenance send_command paths | Existing scheduler action command sends | T2.1, T2.3d-k command validation globals | `send_command` | Medium to High | Per-family ownership flags and action-send parity checks | Defer; action sends are numerous and gameplay-visible, making them less suitable than the isolated turn call for first ownership migration. |

Historical recommendation: T2.5b routed the scheduler face-to-target `turn` callsite through dispatcher ownership behind a default-off guard/flag, preserving validation status and a direct rollback path for that slice.

### 2.5 T2.5b default-off turn dispatcher ownership

| Item | Detail |
| --- | --- |
| Selected callsite | Face-to-target `windower.ffxi.turn(heading)` in `p1_apply_face_to_target`, covered by `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE`. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP == true`; default is off because any value other than literal `true` uses the direct call path. |
| Default-off behavior | Runtime behavior remains the existing direct `windower.ffxi.turn(heading)` call; dispatcher validation status is still published. |
| Flag-on behavior | Scheduler calls `dispatch_intent(intent, { execute = true, turn = windower.ffxi.turn })` for the existing `kind='turn'` intent. |
| Failure behavior | If dispatcher execution does not return `{ ok=true, executed=true }`, scheduler publishes dispatch failure fields and falls back to the existing direct `windower.ffxi.turn(heading)` call. |
| Status fields | `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` now includes `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Side-effect inventory | No scheduler side-effect callsite count changed; the single textual `windower.ffxi.turn(` callsite remains single, while downstream pinned `send_command`/`run` line numbers shifted. |

### 2.6 T2.5c turn ownership static selftest

| Assertion area | Static coverage |
| --- | --- |
| Ownership flag | Confirms `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP == true` exists in the selected turn branch. |
| Dispatcher execution | Confirms the flag-on path calls `dispatcher.dispatch_intent(intent, { ... })` with `execute = true`. |
| Injected dependency | Confirms `turn = windower.ffxi.turn` is passed as the dispatcher dependency. |
| Direct fallback | Confirms the branch preserves `windower.ffxi.turn(heading)` and that `unified_scheduler.lua` has exactly one textual `windower.ffxi.turn(` callsite. |
| Status shape | Confirms `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` still exists and includes `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Harness scope | Static/source-only test; it does not execute Windower APIs or scheduler runtime code. |

### 2.7 T2.5d turn ownership runtime-style feasibility audit

| Finding | Detail |
| --- | --- |
| Safe existing seam | Not present. The selected branch lives inside local `p1_apply_face_to_target`, and `unified_scheduler.lua` returns only the scheduler table. |
| Full module load risk | Loading `unified_scheduler.lua` requires broad Windower globals, addon-path file reads, resource modules, and many runtime dependencies before the selected branch can even be reached. |
| Direct branch access | Not available without modifying runtime exports or extracting source text into a synthetic chunk, which would be brittle and would not execute the actual loaded branch safely. |
| Side-effect safety | A safe test must not call real `windower.ffxi.turn`, `windower.ffxi.run`, `windower.send_command`, or `uc_settarget.select_by_id`; no existing harness exposes the turn branch with dependency injection while guaranteeing that scope. |
| Exact seam needed | A narrow exported/testable helper or injected-dependency helper for the face-to-target turn ownership branch that accepts mocked `windower`, dispatcher, settings, target id, and mob lookup dependencies, then returns/publishes the same status shape. |
| Recommendation | Do not add a runtime-style test in T2.5d. Next safe slice should create the smallest explicit seam first, then add Windower-free runtime-style tests for default-off, flag-on success, and flag-on fallback. |

### 2.8 T2.5e turn ownership helper seam

| Item | Detail |
| --- | --- |
| Helper module | `uc_scheduler_turn_ownership.lua` exposes `apply_turn_ownership(opts)`. |
| Helper inputs | Injected `dispatcher`, `direct_turn`, dispatcher `turn` dependency, `ownership_enabled`, and `intent`; the helper does not reference global Windower APIs. |
| Default-off behavior | `ownership_enabled ~= true` calls `direct_turn(intent.heading)` once, does not dispatch, and returns ownership status with `dispatched=false` and `fallback_used=false`. |
| Flag-on success | `ownership_enabled == true` calls `dispatcher.dispatch_intent(intent, { execute=true, turn=opts.turn })`, treats `{ ok=true, executed=true }` as success, and does not call fallback direct turn. |
| Flag-on failure | Dispatcher failure returns `dispatch_ok=false`, records `dispatch_reason`, sets `fallback_used=true`, and calls `direct_turn(intent.heading)` once. |
| Scheduler integration | The face-to-target turn branch now calls the helper with `direct_turn = windower.ffxi.turn` and `turn = windower.ffxi.turn`; `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` preserves the same ownership/fallback status fields. |
| Runtime-style test | `tests/replay/harness/selftest_turn_ownership_runtime.lua` uses mocked `direct_turn`, dispatcher, and injected `turn` dependency; no real Windower APIs execute. |
| Static test update | `tests/replay/harness/selftest_turn_ownership_static.lua` now pins the helper-backed scheduler shape, helper dispatch/fallback internals, and verifies no textual `windower.ffxi.turn(` callsite remains in `unified_scheduler.lua`. |
| Side-effect inventory | Scheduler tracked side-effect callsite counts and sets remain unchanged for `send_command`, `run`, and `select_by_id`; line pins shifted downward after helper extraction. |

### 2.9 T2.5f second dispatcher runtime-ownership candidate audit

| Candidate | Current live side effect | Return/behavior dependency | Proposed helper seam | Risk level | Recommendation |
| --- | --- | --- | --- | --- | --- |
| `select_target` path | `uc_settarget.select_by_id(tid)` in `p1_try_target_prep`; scheduler stores `ok = (uc_settarget.select_by_id(tid) == true)` and returns that boolean. | Must preserve exact boolean result. Dispatcher `dispatch_intent` does not return dependency return values, so the helper must inject a `set_target` wrapper that calls the real select function once, captures its return, and returns `captured_result == true` on dispatcher success. If dispatcher fails before the wrapper executes, fallback must call the direct select function once and return that exact boolean. | New Windower-free helper, e.g. `uc_scheduler_target_ownership.lua`, accepting injected `dispatcher`, `direct_select`, dispatcher `set_target` wrapper target, `ownership_enabled`, and `intent`. Runtime selftest can mock all dependencies and cover default-off, flag-on success true/false, and dispatcher failure fallback. | Low to Medium | Choose next. It is a single isolated scheduler-owned callsite with existing intent/global and dispatcher execute/missing-dependency fixtures; boolean return preservation is clear if the helper captures the injected dependency result. |
| Isolated `send_command` path | Candidates include Doom Holy Water, defensive internal, combat WS/JA/spell, and maintenance COR command sends. | No useful return value, but sends are gameplay-visible actions; Doom Holy Water is emergency behavior and combat/maintenance sends may trigger actions/items. Fallback should call direct send exactly once on dispatcher failure. | A command helper seam is straightforward, accepting injected `send_command`, dispatcher, ownership flag, and intent/command; runtime tests can mock command sends. | Medium to High | Defer. Semantics are easier than target-select, but gameplay risk is higher because these are action/item commands rather than target prep. |
| One `run_stop` path | Candidates include movement coordinator cast-freeze/pull stops, tank settle stops, Doom stop, and combat spell wait/settle stops. | No return value, but timing affects movement/casting/settle behavior; fallback should call direct `run(false)` once on dispatcher failure. | A `run_stop` helper seam is straightforward, accepting injected `run`, dispatcher, ownership flag, and intent. | Medium | Defer. Dispatcher support is ready, but movement-stop timing is riskier than target selection and should follow another non-movement cutover. |
| `run` vector path | `p1_move_toward_mob` currently calls `windower.ffxi.run(heading)` and returns `true`; dark-launch intent uses `run_x`/`run_y`. | Live execution uses heading, while dispatcher execute uses vector arguments (`run_x`, `run_y`); parity is not proven. Fallback should preserve heading-based direct behavior. | Requires a parity decision or helper that can explicitly map heading vs vector semantics before ownership. | High | Do not choose yet. Needs explicit movement contract/parity proof before routing through dispatcher ownership. |

Historical recommendation: T2.5g created a Windower-free target-select ownership helper and default-off scheduler integration for only `p1_try_target_prep`, preserving `uc_settarget.select_by_id(tid) == true` exactly by capturing the injected dispatcher dependency return and falling back to direct select on dispatcher failure.

### 2.10 T2.5g target ownership helper seam

| Item | Details |
| --- | --- |
| Helper | Added `uc_scheduler_target_ownership.lua` with `apply_target_ownership(opts)` taking only injected `dispatcher`, `direct_select_target`, `set_target`, `ownership_enabled`, `intent`, and `target_id`. |
| Dispatcher return semantics | `uc_scheduler_dispatcher.lua` now returns `dep_result` for executed `select_target`/`set_target` dispatches so the helper can preserve the real injected `set_target` boolean instead of guessing from generic dispatcher success. |
| Scheduler routing | `unified_scheduler.lua` routes only `p1_try_target_prep` through the helper; default-off still calls the injected direct select path, and flag-on falls back to the direct select path only when dispatcher execution itself fails. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE` now keeps the existing validation fields and adds `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `selected`. |
| Runtime-style test | `tests/replay/harness/selftest_target_ownership_runtime.lua` covers default-off true/false direct behavior, flag-on dispatcher success with true/false injected return, and dispatcher failure fallback. |
| Static test update | `tests/replay/harness/selftest_target_ownership_static.lua` pins the helper-backed scheduler shape, default-off flag guard, injected `uc_settarget.select_by_id` dependencies, status fields, and verifies no extra textual `uc_settarget.select_by_id(` callsite remains in `unified_scheduler.lua`. |
| Side-effect inventory | Scheduler tracked side-effect callsite counts and sets remain unchanged; the direct `uc_settarget.select_by_id(` textual callsite was replaced by dependency injection, so its baseline count in `unified_scheduler.lua` is now zero. |
| Validation | `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

### 2.11 T2.5h maintenance COR command ownership helper seam

| Item | Details |
| --- | --- |
| Selected candidate | Maintenance COR self-JA command path using `maintenance_cor_command`; it already has a local command variable, no return-value dependency, a dedicated dark-launch validation global, and a narrower branch surface than the combat/defensive command families. |
| Helper | Added `uc_scheduler_command_ownership.lua` with `apply_command_ownership(opts)` taking only injected `dispatcher`, `direct_send_command`, `send_command`, `ownership_enabled`, `intent`, and `command`. |
| Scheduler routing | `unified_scheduler.lua` routes only the maintenance COR `windower.send_command(maintenance_cor_command)` path through the helper; default-off preserves direct send semantics, and flag-on falls back to direct send only when dispatcher execution fails. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == true`; any other value keeps default-off direct behavior. |
| Missing command safety | The helper treats blank/missing `command` as `command_present = false`, returns `dispatch_reason = "missing_command"`, and performs no dispatch or direct send. The selected scheduler branch still supplies a nonblank command, so normal runtime behavior is unchanged. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_MAINTENANCE_COR_COMMAND_VALIDATE` keeps its existing validation fields and now adds `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `command_present`. |
| Runtime-style test | `tests/replay/harness/selftest_command_ownership_runtime.lua` covers default-off direct behavior, flag-on dispatcher success, flag-on dispatcher failure fallback, and blank-command no-op behavior. |
| Static test update | `tests/replay/harness/selftest_command_ownership_static.lua` pins the helper-backed maintenance COR branch, explicit `== true` flag guard, injected `windower.send_command` dependencies, status fields, and confirms no extra textual `windower.send_command(` callsite was added. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5h maintenance COR command ownership helper seam slice. Status change: T2.5h maintenance COR command ownership helper seam marked `IN PROGRESS`; selected the isolated maintenance COR self-JA command path because it already uses a local `maintenance_cor_command`, has no return-value dependency, publishes a dedicated dark-launch validation global, and is narrower than the generic combat/defensive command families. Added `uc_scheduler_command_ownership.lua` as a Windower-free injected-dependency helper, updated `unified_scheduler.lua` so only the maintenance COR command routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, and added fail-safe blank-command no-op handling. Files created: `uc_scheduler_command_ownership.lua`, `tests/replay/harness/selftest_command_ownership_runtime.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.12 T2.5i defensive_internal command ownership routing

| Item | Details |
| --- | --- |
| Selected path | The existing `provider == 'defensive_internal'` branch using local `cmd`; it stays narrow, has early empty-command exit, already publishes `_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE`, and has no return-value dependency to preserve. |
| Scheduler routing | `unified_scheduler.lua` now routes only the defensive_internal `send_command(cmd)` path through `uc_scheduler_command_ownership.apply_command_ownership(...)`. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == true`; any value other than literal `true` leaves the branch on default-off direct send behavior. |
| Default-off behavior | The helper calls injected `direct_send_command(cmd)` once, so runtime behavior remains the same when the flag is off. |
| Flag-on behavior | The helper dispatches the existing `kind='send_command'` intent with `execute = true` and injected `send_command = windower.send_command`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_send_command(cmd)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE` now includes `ok`, `reason`, `kind`, `source`, `command_present`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Static coverage | `tests/replay/harness/selftest_command_ownership_static.lua` now pins both maintenance COR and defensive_internal ownership flags, helper usage, status fields, and the reduced direct scheduler `windower.send_command(` count. |
| Side-effect inventory | The direct textual scheduler `windower.send_command(cmd)` call in the defensive_internal branch was removed and is now represented by injected `windower.send_command` references passed to the helper; remaining pinned scheduler direct send callsites drop from 8 to 7 with no duplicate direct send introduced. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5i defensive_internal command ownership routing slice. Status change: T2.5i defensive_internal command ownership routing marked `IN PROGRESS`; reused the existing `uc_scheduler_command_ownership.lua` helper for the isolated `provider == 'defensive_internal'` command path because the branch already had a local `cmd`, early blank-command exit, a dedicated dark-launch validation global, and no return-value dependency. Updated `unified_scheduler.lua` so only this branch routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, expanded focused static coverage, and intentionally reduced the scheduler textual `windower.send_command(` callsite count from 8 to 7. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.13 T2.5j Doom Holy Water command ownership routing

| Item | Details |
| --- | --- |
| Routed path | The isolated Doom Holy Water emergency command path using local `doom_holy_water_command`; it remains clearly identifiable, has no return-value dependency, and still performs its stop and cooldown gating before the item command send. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP == true`; any value other than literal `true` keeps default-off direct send behavior. |
| Default-off behavior | The helper calls injected `direct_send_command(doom_holy_water_command)` once, preserving the existing one-send behavior after the stop and cooldown checks. |
| Flag-on behavior | The helper dispatches the existing `kind='send_command'` intent with `execute = true` and injected `send_command = windower.send_command`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_send_command(doom_holy_water_command)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE` now includes `ok`, `reason`, `kind`, `source`, `command_present`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Static coverage | `tests/replay/harness/selftest_command_ownership_static.lua` now pins Doom, defensive_internal, and maintenance COR ownership flags, helper usage, status fields, and the reduced direct scheduler `windower.send_command(` count. |
| Side-effect inventory | The direct textual scheduler `windower.send_command(doom_holy_water_command)` call was removed and is now represented by injected `windower.send_command` references passed to the helper; remaining pinned scheduler direct send callsites drop from 7 to 6 with no duplicate direct send introduced. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5j Doom Holy Water command ownership routing slice. Status change: T2.5j Doom Holy Water command ownership routing marked `IN PROGRESS`; reused the existing `uc_scheduler_command_ownership.lua` helper for the isolated Doom Holy Water emergency command path because it already had a local `doom_holy_water_command`, a dedicated dark-launch validation global, no return-value dependency, and clear pre-send stop/cooldown gates. Updated `unified_scheduler.lua` so only the Doom Holy Water command routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, expanded focused static coverage, and intentionally reduced the scheduler textual `windower.send_command(` callsite count from 7 to 6. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.14 T2.5k remaining direct send_command ownership review

| Remaining direct callsite | Context | Review outcome | Blocker |
| --- | --- | --- | --- |
| `windower.send_command(cmd)` | T2.1 internal defensive action dispatch path | Skip | Shared maintenance/defensive dispatch branch, not a narrow provider seam; `cmd` and follow-up state mutation are part of a broader action-dispatch contract rather than an isolated ownership slice. |
| `windower.send_command(ws_command)` | Combat WS fallback command | Skip | Broad combat family path; depends on combat state, target readiness, and action timing, and fallback parity is unclear without deciding how WS family sends should be owned together. |
| `windower.send_command(ja_target_command)` | Combat JA target-send command | Skip | Coupled to scheduler target prep and current-target validation; direct fallback safety depends on exact target-state parity at send time. |
| `windower.send_command(ja_self_command)` | Combat JA self-send command | Skip | Shares tank-enmity stop-adjacent timing behavior with self-target combat JA dispatch, so isolated ownership risks hidden timing/duplicate-send ambiguity. |
| `windower.send_command(spell_target_command)` | Combat spell target-send command | Skip | Broad combat spell family path with target-state and readiness coupling; ownership should not be split from adjacent stop/settle semantics without a larger combat send contract. |
| `windower.send_command(spell_self_command)` | Combat spell self-send command | Skip | Shares tank-enmity stop-adjacent timing and combat spell dispatch behavior; fallback safety is not proven for a single isolated self-send slice. |

| Summary | Details |
| --- | --- |
| Routed paths | None. |
| Reviewed count | All 6 remaining direct scheduler `windower.send_command(` callsites were inspected. |
| Safe isolated candidates found | None. The easy provider-specific non-combat seams are exhausted after maintenance COR, defensive_internal, and Doom Holy Water. |
| Side-effect inventory | No runtime files changed in T2.5k, so direct scheduler `windower.send_command(` count remains 6 and no inventory update was required. |
| Recommendation | Stop here unless a broader combat-send ownership contract is explicitly approved, likely at the family level rather than one command callsite at a time. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5k remaining direct send_command ownership review. Status change: T2.5k remaining direct send_command ownership review marked `IN PROGRESS`; inspected all 6 remaining direct scheduler `windower.send_command(` callsites after the maintenance COR, defensive_internal, and Doom Holy Water ownership slices and stopped without additional routing because every remaining path is either a broad combat send family or a shared dispatch branch with target-state, settle/stop, or combat-timing coupling. No safe additional isolated send_command ownership slice was found under the current one-callsite-at-a-time constraint. Files modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.15 T2.5l combat JA command family ownership routing

| Item | Details |
| --- | --- |
| Reviewed JA paths | Combat JA target/mob send and combat JA self send. |
| Routed JA paths | Both. They already had local command variables (`ja_target_command` / `ja_self_command`), branch-specific validation globals, no return-value dependency, and the helper only replaces the final send after all existing readiness/target/stop checks have executed. |
| Skipped JA paths | None. Both branches were part of the same family pattern and safe to migrate together. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true`; any other value keeps default-off direct send behavior for both JA target and JA self paths. |
| Default-off behavior | The helper calls injected `direct_send_command(...)` once for the selected JA command, preserving the existing one-send behavior. |
| Flag-on behavior | The helper dispatches the existing `kind='send_command'` JA intent with `execute = true` and injected `send_command = windower.send_command`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_send_command(...)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE` and `_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE` now include `ok`, `reason`, `kind`, `source`, `command_present`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Static coverage | `tests/replay/harness/selftest_command_ownership_static.lua` now pins the JA family ownership flag, JA target/self status globals, helper usage, status fields, and the reduced direct scheduler `windower.send_command(` count. |
| Side-effect inventory | The direct textual scheduler `windower.send_command(ja_target_command)` and `windower.send_command(ja_self_command)` calls were removed and are now represented by injected `windower.send_command` references passed to the helper; remaining pinned scheduler direct send callsites drop from 6 to 4 with no duplicate direct send introduced. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5l combat JA command family ownership routing slice. Status change: T2.5l combat JA command family ownership routing marked `IN PROGRESS`; reused the existing `uc_scheduler_command_ownership.lua` helper for both combat JA target and JA self sends because the family already had local command strings, branch-specific validation globals, no return-value dependency, and clear pre-send readiness/target/stop semantics. Updated `unified_scheduler.lua` so the selected JA target/self branches route through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, expanded focused static coverage, and intentionally reduced the scheduler textual `windower.send_command(` callsite count from 6 to 4. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.16 T2.5m combat spell command family ownership routing

| Item | Details |
| --- | --- |
| Reviewed spell paths | Combat spell target/mob send and combat spell self send. |
| Routed spell paths | Both. They already had local command variables (`spell_target_command` / `spell_self_command`), branch-specific validation globals, no return-value dependency, and all readiness, target, settle, prep-wait, and stop checks complete before the final send helper call. |
| Skipped spell paths | None. Both branches were part of the same family pattern and safe to migrate together. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true`; any other value keeps default-off direct send behavior for both spell target and spell self paths. |
| Default-off behavior | The helper calls injected `direct_send_command(...)` once for the selected spell command, preserving the existing one-send behavior. |
| Flag-on behavior | The helper dispatches the existing `kind='send_command'` spell intent with `execute = true` and injected `send_command = windower.send_command`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_send_command(...)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_SPELL_TARGET_COMMAND_VALIDATE` and `_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE` now include `ok`, `reason`, `kind`, `source`, `command_present`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Static coverage | `tests/replay/harness/selftest_command_ownership_static.lua` now pins the spell family ownership flag, spell target/self status globals, helper usage, status fields, and the reduced direct scheduler `windower.send_command(` count. |
| Side-effect inventory | The direct textual scheduler `windower.send_command(spell_target_command)` and `windower.send_command(spell_self_command)` calls were removed and are now represented by injected `windower.send_command` references passed to the helper; remaining pinned scheduler direct send callsites drop from 4 to 2 with no duplicate direct send introduced. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5m combat spell command family ownership routing slice. Status change: T2.5m combat spell command family ownership routing marked `IN PROGRESS`; reused the existing `uc_scheduler_command_ownership.lua` helper for both combat spell target and spell self sends because the family already had local command strings, branch-specific validation globals, no return-value dependency, and clear pre-send readiness/target/settle/prep-wait/stop semantics. Updated `unified_scheduler.lua` so the selected spell target/self branches route through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, expanded focused static coverage, and intentionally reduced the scheduler textual `windower.send_command(` callsite count from 4 to 2. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.18 T2.5n combat WS command ownership routing

| Item | Details |
| --- | --- |
| Selected candidate | Combat WS command path using local `ws_command`; all readiness, TP, target, and action gating still happens before the final command send. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP == true`; any other value keeps default-off direct send behavior. |
| Default-off behavior | The helper calls injected `direct_send_command(ws_command)` once, preserving the existing one-send WS runtime behavior. |
| Flag-on behavior | The helper dispatches the existing `kind='send_command'` WS intent with `execute = true` and injected `send_command = windower.send_command`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_send_command(ws_command)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_COMBAT_COMMAND_VALIDATE` now includes `ok`, `reason`, `kind`, `source`, `command_present`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Static coverage | `tests/replay/harness/selftest_command_ownership_static.lua` now pins the WS ownership flag, WS status global, helper usage, status fields, and the reduced direct scheduler `windower.send_command(` count. |
| Side-effect inventory | The direct textual scheduler `windower.send_command(ws_command)` call was removed and is now represented by injected `windower.send_command` references passed to the helper; remaining pinned scheduler direct send callsites drop from 2 to 1 with no duplicate direct send introduced, leaving only the shared T2.1 internal defensive dispatch branch. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5n combat WS command ownership routing slice. Status change: T2.5n combat WS command ownership routing marked `IN PROGRESS`; reused the existing `uc_scheduler_command_ownership.lua` helper for the isolated combat WS command path because the branch already had a local `ws_command`, a dedicated dark-launch validation global, no return-value dependency, and clear pre-send readiness, TP, target, and action gating. Updated `unified_scheduler.lua` so only the WS command send routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, expanded focused static coverage, and intentionally reduced the scheduler textual `windower.send_command(` callsite count from 2 to 1. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.19 T2.5o final internal dispatch send ownership routing

| Item | Details |
| --- | --- |
| Routed decision | Routed as one shared ownership seam; the remaining T2.1 branch already had a stable local `cmd`, no return-value dependency, clear default-off/fallback semantics, and identical final-send behavior across its shared internal defensive action modes. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP == true`; any other value keeps default-off direct send behavior. |
| Default-off behavior | The helper calls injected `direct_send_command(cmd)` once, preserving the existing one-send internal dispatch runtime behavior. |
| Flag-on behavior | The helper dispatches the existing `kind='send_command'` internal dispatch intent with `execute = true` and injected `send_command = windower.send_command`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_send_command(cmd)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_DISPATCH_VALIDATE` now includes `ok`, `reason`, `kind`, `source`, `command_present`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Static coverage | `tests/replay/harness/selftest_command_ownership_static.lua` now pins the internal dispatch ownership flag, `_G.UC_SCHED_P1_DARKLAUNCH_DISPATCH_VALIDATE`, helper usage, status fields, and the zero remaining direct scheduler `windower.send_command(` count. |
| Side-effect inventory | The final textual scheduler `windower.send_command(cmd)` call was removed and is now represented by injected `windower.send_command` references passed to the helper; direct scheduler `windower.send_command(` count drops from 1 to 0 with no duplicate direct send introduced. Remaining tracked scheduler side effects are the expected `windower.ffxi.run(` pins and zero `uc_settarget.select_by_id(` textual callsites. |
| Validation | `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.5o final internal dispatch send ownership routing slice. Status change: T2.5o final internal dispatch send ownership routing marked `IN PROGRESS`; reused the existing `uc_scheduler_command_ownership.lua` helper for the remaining shared T2.1 internal defensive dispatch command path because the branch already had a stable local `cmd`, no return-value dependency, an existing dark-launch validation global, and clear pre-send block/cooldown ordering with identical final-send semantics across the shared branch. Updated `unified_scheduler.lua` so the final shared direct send routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP == true`, preserved default-off direct send behavior, used direct-send fallback only on dispatcher failure, expanded focused static coverage, and intentionally reduced the scheduler textual `windower.send_command(` callsite count from 1 to 0. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_command_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.20 T2.6a first run_stop ownership helper seam

| Item | Details |
| --- | --- |
| Selected run_stop path | Doom Holy Water emergency stop before the already-owned Holy Water command path. |
| Why safe | The stop is isolated, runs only after confirming Doom, happens immediately before the emergency item branch, has no return-value dependency, and already has dedicated `run_stop` validation coverage. |
| Helper | Added `uc_scheduler_run_stop_ownership.lua` exposing `apply_run_stop_ownership(opts)` with injected-only `dispatcher`, `direct_run`, `run`, `ownership_enabled`, and `intent`. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP == true`; any other value keeps default-off direct `run(false)` behavior. |
| Default-off behavior | The helper calls injected `direct_run(false)` once and does not dispatch. |
| Flag-on behavior | The helper dispatches the existing `kind='run_stop'` intent with `execute = true` and injected `run = windower.ffxi.run`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_run(false)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE` now includes `ok`, `reason`, `kind`, `source`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `stop`. |
| Test coverage | Added `tests/replay/harness/selftest_run_stop_ownership_runtime.lua` and `tests/replay/harness/selftest_run_stop_ownership_static.lua`, and added both to `tests/replay/harness/selftest_all_replay_fixtures.lua`. |
| Side-effect inventory | The direct textual scheduler `windower.ffxi.run(false)` Doom stop call was removed and is now represented by injected `windower.ffxi.run` helper dependencies; the scheduler direct `windower.ffxi.run(` count drops by one with no duplicate direct run callsite introduced. |
| Validation | `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.6a first run_stop ownership helper seam slice. Status change: T2.6a first run_stop ownership helper seam marked `IN PROGRESS`; selected the Doom Holy Water emergency stop because it is the lowest-risk isolated `run(false)` path, already validated as `kind='run_stop'`, and sits immediately before the already-owned Holy Water command branch. Added `uc_scheduler_run_stop_ownership.lua` as a Windower-free injected-dependency helper, updated `unified_scheduler.lua` so only the Doom stop routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP == true`, preserved default-off direct `run(false)` behavior, used direct-run fallback only on dispatcher failure, added focused runtime/static selftests plus aggregate registration, and intentionally reduced the scheduler textual `windower.ffxi.run(` callsite count by one. Files modified: `uc_scheduler_run_stop_ownership.lua`, `tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `tests/replay/harness/selftest_run_stop_ownership_static.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.21 T2.6b movement-coordinator run_stop ownership routing

| Item | Details |
| --- | --- |
| Stops reviewed | `MOVE_COORD_CAST_FREEZE_PREP`, `MOVE_COORD_PULL_CAST_HOLD`, and `MOVE_COORD_PULL_SPELL_WAIT`. |
| Routed stops | All three. Each branch already sets explicit `CAST_FREEZE` movement mode plus a branch-specific block reason before the final stop, has no return-value dependency, and returns immediately after the stop with clear fallback parity. |
| Skipped stops | None in this family. Timing/fallback semantics matched closely enough to batch safely. |
| Ownership flags | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP == true`; `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP == true`; `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP == true`. Any other value keeps default-off direct `run(false)` behavior per branch. |
| Default-off behavior | The helper calls injected `direct_run(false)` once for the selected stop and does not dispatch. |
| Flag-on behavior | The helper dispatches the existing `kind='run_stop'` intent with `execute = true` and injected `run = windower.ffxi.run`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_run(false)` once. |
| Status payloads | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE`, `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE`, and `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE` now include `ok`, `reason`, `kind`, `source`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `stop`. |
| Static coverage | `tests/replay/harness/selftest_run_stop_ownership_static.lua` now pins the Doom plus movement-coordinator ownership flags, selected status globals, ownership/fallback fields, and the reduced direct scheduler `windower.ffxi.run(` count. |
| Side-effect inventory | The three direct textual movement-coordinator `windower.ffxi.run(false)` callsites were removed and are now represented by injected `windower.ffxi.run` helper dependencies; direct scheduler `windower.ffxi.run(` count drops from 11 to 8 with no duplicate direct run introduced. Remaining pinned run callsites are the expected vector, tank, and combat-spell stops. |
| Validation | `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.6b movement-coordinator run_stop ownership routing slice. Status change: T2.6b movement-coordinator run_stop ownership routing marked `IN PROGRESS`; reviewed the three movement-coordinator freeze/pull stops and routed all three because each branch already publishes explicit `CAST_FREEZE` mode plus a branch-specific block reason immediately before the stop, has no return-value dependency, and returns immediately after the final `run(false)` with clear default-off/fallback parity. Updated `unified_scheduler.lua` so `MOVE_COORD_CAST_FREEZE_PREP`, `MOVE_COORD_PULL_CAST_HOLD`, and `MOVE_COORD_PULL_SPELL_WAIT` route through `uc_scheduler_run_stop_ownership.apply_run_stop_ownership(...)` behind branch-specific default-off flags, preserved direct-run fallback only on dispatcher failure, expanded static coverage, and intentionally reduced the scheduler textual `windower.ffxi.run(` callsite count from 11 to 8. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_run_stop_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.22 T2.6c combat-spell run_stop ownership routing

| Item | Details |
| --- | --- |
| Combat-spell stops reviewed | Generic combat spell settle stop and generic combat spell prep-wait stop. |
| Routed stops | Both. The pair shares the same `UC_MOVE_FREEZE_PREP_KEY` / `UC_MOVE_FREEZE_PREP_UNTIL` gating family, has explicit stop reasons and immediate block returns, and the helper replaces only the final `run(false)` call. |
| Skipped stops | None in this pair. The timing/fallback semantics matched closely enough to batch safely. |
| Ownership flags | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP == true`; `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP == true`. Any other value keeps default-off direct `run(false)` behavior per branch. |
| Default-off behavior | The helper calls injected `direct_run(false)` once for the selected stop and does not dispatch. |
| Flag-on behavior | The helper dispatches the existing `kind='run_stop'` intent with `execute = true` and injected `run = windower.ffxi.run`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_run(false)` once. |
| Status payloads | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE` and `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE` now include `ok`, `reason`, `kind`, `source`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `stop`. |
| Static coverage | `tests/replay/harness/selftest_run_stop_ownership_static.lua` now pins the combat-spell settle/prep-wait ownership flags, the selected status globals, ownership/fallback fields, and the reduced direct scheduler `windower.ffxi.run(` count. |
| Side-effect inventory | The two direct textual combat-spell `windower.ffxi.run(false)` callsites were removed and are now represented by injected `windower.ffxi.run` helper dependencies; direct scheduler `windower.ffxi.run(` count drops from 8 to 6 with no duplicate direct run introduced. Remaining pinned run callsites are the expected vector and tank-related stops. |
| Validation | `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.6c combat-spell run_stop ownership routing slice. Status change: T2.6c combat-spell run_stop ownership routing marked `IN PROGRESS`; reviewed the generic combat spell settle/prep-wait pair and routed both because each branch already has explicit spell prep/settle stop semantics, no return-value dependency, clear block-return behavior, and the helper replaces only the final `run(false)` side effect. Updated `unified_scheduler.lua` so the combat spell settle and combat spell prep-wait stops route through `uc_scheduler_run_stop_ownership.apply_run_stop_ownership(...)` behind branch-specific default-off flags, preserved direct-run fallback only on dispatcher failure, expanded static coverage, and intentionally reduced the scheduler textual `windower.ffxi.run(` callsite count from 8 to 6. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_run_stop_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.23 T2.6d tank-enmity spell send-adjacent run_stop ownership routing

| Item | Details |
| --- | --- |
| Tank-enmity spell send-adjacent stops reviewed | Tank-enmity spell target-send-adjacent stop and tank-enmity spell self-send-adjacent stop. |
| Routed stops | Both. Each stop is gated by the tank-enmity spell branch, occurs immediately before an already-owned spell command send, has no return-value dependency, and the helper replaces only the final `run(false)` side effect. |
| Skipped stops | None in this pair. The target/self branches matched closely enough to batch safely. |
| Ownership flags | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP == true` with explicit false opt-out and promoted kill switch support; `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP == true` with explicit false opt-out and promoted kill switch support. Any other value keeps the existing branch-specific direct `run(false)` fallback behavior. |
| Default-off behavior | The helper calls injected `direct_run(false)` once for the selected stop and does not dispatch. |
| Flag-on behavior | The helper dispatches the existing `kind='run_stop'` intent with `execute = true` and injected `run = windower.ffxi.run`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_run(false)` once. |
| Status payloads | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE` and `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE` now include `ok`, `reason`, `kind`, `source`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `stop`. |
| Static coverage | `tests/replay/harness/selftest_run_stop_ownership_static.lua` now pins the tank-enmity spell target/self ownership flags, the selected status globals, ownership/fallback fields, and the reduced direct scheduler `windower.ffxi.run(` count. |
| Side-effect inventory | The two direct textual tank-enmity spell send-adjacent `windower.ffxi.run(false)` callsites were removed and are now represented by injected `windower.ffxi.run` helper dependencies; direct scheduler `windower.ffxi.run(` count drops from 6 to 4 with no duplicate direct run introduced. Remaining pinned run callsites are the expected vector plus tank settle and JA self-send-adjacent stops. |
| Validation | `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.6d tank-enmity spell send-adjacent run_stop ownership routing slice. Status change: T2.6d tank-enmity spell send-adjacent run_stop ownership routing marked `IN PROGRESS`; reviewed the tank-enmity spell target/self send-adjacent pair and routed both because each stop is tank-enmity gated, occurs immediately before an already-owned spell send, has no return-value dependency, and the helper replaces only the final `run(false)` side effect while preserving branch order. Updated `unified_scheduler.lua` so the tank-enmity spell target/self stops route through `uc_scheduler_run_stop_ownership.apply_run_stop_ownership(...)` behind branch-specific default-off flags, preserved direct-run fallback only on dispatcher failure, expanded static coverage, and intentionally reduced the scheduler textual `windower.ffxi.run(` callsite count from 6 to 4. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_run_stop_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.24 T2.6e remaining tank run_stop ownership routing

| Item | Details |
| --- | --- |
| Tank stops reviewed | Tank-enmity action settle stop, tank-enmity spell settle stop, and tank-enmity JA self-send-adjacent stop. |
| Routed stops | All three. Each branch already had explicit settle or self-send-adjacent stop semantics, no return-value dependency, and all gating/state updates occur before the final stop side effect. |
| Skipped stops | The vector run path was intentionally not touched; it remains the only direct scheduler `windower.ffxi.run(` callsite because heading-based live semantics still need explicit parity proof before ownership routing. |
| Ownership flags | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` now uses promoted default-on semantics with explicit `false` opt-out and shared kill switch support; `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` now uses promoted default-on semantics with explicit `false` opt-out and shared kill switch support; `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` now uses promoted default-on semantics with explicit `false` opt-out and shared kill switch support. |
| Default-off behavior | The helper still calls injected `direct_run(false)` once for the selected stop and does not dispatch for the remaining default-off tank branches. |
| Flag-on behavior | The helper dispatches the existing `kind='run_stop'` intent with `execute = true` and injected `run = windower.ffxi.run`. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_run(false)` once. |
| Status payloads | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE`, `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE`, and `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE` now include `ok`, `reason`, `kind`, `source`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, `fallback_used`, and `stop`. |
| Static coverage | `tests/replay/harness/selftest_run_stop_ownership_static.lua` now pins the three new ownership flags, the three status globals, helper usage, ownership/fallback fields, and the reduced direct scheduler `windower.ffxi.run(` count. |
| Side-effect inventory | The three direct textual tank-related `windower.ffxi.run(false)` callsites were removed and are now represented by injected `windower.ffxi.run` helper dependencies; direct scheduler `windower.ffxi.run(` count drops from 4 to 1 with no duplicate direct run introduced. The remaining pinned direct callsite is the vector run path. |
| Validation | `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.6e remaining tank run_stop ownership routing slice. Status change: T2.6e remaining tank run_stop ownership routing marked `IN PROGRESS`; reviewed the remaining tank-related stop family and routed the tank action settle, tank spell settle, and tank-enmity JA self-send-adjacent stops because each branch already has explicit settle or self-send-adjacent stop semantics, no return-value dependency, and the helper replaces only the final `run(false)` side effect while preserving branch order. Updated `unified_scheduler.lua` so the three selected stops route through `uc_scheduler_run_stop_ownership.apply_run_stop_ownership(...)` behind branch-specific default-off flags, preserved direct-run fallback only on dispatcher failure, expanded static coverage, and intentionally reduced the scheduler textual `windower.ffxi.run(` callsite count from 4 to 1, leaving only the vector run path. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_run_stop_ownership_static.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.25 T2.6f vector run ownership parity and routing

| Item | Details |
| --- | --- |
| Parity decision | Safe to route. The live scheduler call shape is `windower.ffxi.run(heading)`, while dispatcher `kind='run'` execute semantics call injected `deps.run(run_x, run_y)`. Exact runtime parity is preserved by injecting a heading-preserving adapter for dispatcher execution. |
| Evidence | `p1_move_toward_mob` already computes both `heading` and the derived vector `run_x = math.cos(heading)`, `run_y = math.sin(heading)` in the same branch before the final side effect, so the dispatcher still validates the same canonical vector intent while the adapter preserves the original heading call shape. |
| Helper | Added `uc_scheduler_run_ownership.lua` exposing `apply_run_ownership(opts)` with injected-only `dispatcher`, `direct_run`, `run`, `ownership_enabled`, `intent`, and `heading`. |
| Ownership flag | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP == true`; any other value keeps default-off direct heading behavior. |
| Default-off behavior | The helper calls injected `direct_run(heading)` once and does not dispatch. |
| Flag-on behavior | The helper dispatches the existing `kind='run'` intent with `execute = true` and injected `run = dispatcher_run`, where the adapter preserves old runtime behavior by calling the aliased direct heading runner. |
| Failure behavior | If dispatcher execution does not return `{ ok = true, executed = true }`, the helper falls back to injected `direct_run(heading)` once. |
| Status payload | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` now includes `ok`, `reason`, `kind`, `source`, `run_x`, `run_y`, `heading`, `ownership_enabled`, `dispatched`, `dispatch_ok`, `dispatch_reason`, and `fallback_used`. |
| Test coverage | Added `tests/replay/harness/selftest_run_ownership_runtime.lua` and `tests/replay/harness/selftest_run_ownership_static.lua`, and added both to `tests/replay/harness/selftest_all_replay_fixtures.lua`. |
| Side-effect inventory | The final direct textual scheduler `windower.ffxi.run(heading)` call was removed and is now represented by injected helper dependencies (`direct_run` plus the dispatcher adapter); direct scheduler `windower.ffxi.run(` count drops from 1 to 0 with no duplicate direct run callsite introduced. |
| Validation | `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`; `luac -p uc_scheduler_run_ownership.lua`; `lua tests/replay/harness/selftest_run_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_ownership_static.lua`. |

- 2026-06-11: Completed T2.6f vector run ownership parity and routing slice. Status change: T2.6f vector run ownership parity and routing marked `IN PROGRESS`; audited the final live `windower.ffxi.run(heading)` scheduler path against the dispatcher `kind='run'` execute contract (`deps.run(run_x, run_y)`) and routed it only after proving safe parity through an injected heading-preserving adapter. Added `uc_scheduler_run_ownership.lua` as a Windower-free injected-dependency helper, updated `unified_scheduler.lua` so the final vector run path routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP == true`, preserved default-off direct heading behavior, used direct-run fallback only on dispatcher failure, added focused runtime/static selftests plus aggregate registration, and intentionally reduced the scheduler textual `windower.ffxi.run(` callsite count from 1 to 0. Files created: `uc_scheduler_run_ownership.lua`, `tests/replay/harness/selftest_run_ownership_runtime.lua`, `tests/replay/harness/selftest_run_ownership_static.lua`. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_run_ownership.lua`, `lua tests/replay/harness/selftest_run_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_ownership_static.lua`.

### 2.26 T2.7a scheduler side-effect ownership phase closure

| Item | Details |
| --- | --- |
| Closure assertions | Added a source-only closure selftest that confirms `unified_scheduler.lua` contains zero direct textual call expressions for `windower.send_command(`, `windower.ffxi.run(`, `windower.ffxi.turn(`, and `uc_settarget.select_by_id(` while allowing safe injected dependency references to remain. |
| Helper usage confirmation | The closure test also confirms the scheduler requires/uses `uc_scheduler_command_ownership`, `uc_scheduler_run_stop_ownership`, `uc_scheduler_run_ownership`, `uc_scheduler_target_ownership`, and `uc_scheduler_turn_ownership`. |
| Current scheduler state | Command ownership closure complete, run_stop ownership closure complete, vector run ownership closure complete, turn ownership closure complete, and target ownership closure complete. `unified_scheduler.lua` now has zero direct textual scheduler side-effect call expressions for send/run/turn/select. |
| Runtime behavior | Unchanged by this task. Side effects continue to route through helper/dispatcher seams behind existing default-off ownership flags; this task does not promote flags, remove fallbacks, or change helper/dispatcher contracts. |
| Stale wording cleanup | Updated stale tracker sections that previously read as current inventories or current migration recommendations so they are explicitly labeled as historical audit snapshots or historical recommendations. Historical completion logs remain unchanged. |
| Validation | `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_run_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_run_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.7a scheduler side-effect ownership phase closure. Status change: T2.7a scheduler side-effect ownership phase closure marked `DONE`; added a final static closure selftest for `unified_scheduler.lua`, confirmed helper usage across command/run_stop/run/target/turn ownership seams, and cleaned stale tracker wording that still described old direct scheduler side-effect callsites or migration recommendations as current state. Scheduler runtime behavior remains default-off unchanged, no flags were promoted, and no helper or dispatcher contracts changed. Files created: `tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_run_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_run_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.27 T2.7b ownership promotion plan and flag guard

| Item | Details |
| --- | --- |
| Promotion artifact | Added `docs/scheduler_ownership_promotion_plan.md` describing current closure state, ownership families, all scheduler ownership flags, conservative promotion order, field smoke-test checklist, and promotion gates. |
| Flag inventory | Extracted every scheduler `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP == true` flag from `unified_scheduler.lua`, grouped them by family, and documented routed behavior, preserved fallback behavior, smoke scenario, and rollback instruction. |
| Static guard | Added `tests/replay/harness/selftest_scheduler_ownership_flags_static.lua` to inventory scheduler ownership flags, enforce explicit `== true` guards, reject default-on/truthy scheduler flag checks, verify every flag appears in the promotion plan, and confirm the plan says flags remain default-off with clear rollback language. |
| Runtime behavior | Unchanged by this task. No ownership flags were promoted, no defaults changed, and no helper/dispatcher/runtime code was modified. |
| Validation | `lua tests/replay/harness/selftest_scheduler_ownership_flags_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_command_ownership_runtime.lua`; `lua tests/replay/harness/selftest_command_ownership_static.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`; `lua tests/replay/harness/selftest_run_ownership_runtime.lua`; `lua tests/replay/harness/selftest_run_ownership_static.lua`; `lua tests/replay/harness/selftest_target_ownership_runtime.lua`; `lua tests/replay/harness/selftest_target_ownership_static.lua`; `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`; `lua tests/replay/harness/selftest_turn_ownership_static.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_dispatcher.lua`; `luac -p uc_scheduler_command_ownership.lua`; `luac -p uc_scheduler_run_stop_ownership.lua`; `luac -p uc_scheduler_run_ownership.lua`; `luac -p uc_scheduler_target_ownership.lua`; `luac -p uc_scheduler_turn_ownership.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. |

- 2026-06-11: Completed T2.7b ownership promotion plan and flag guard. Status change: T2.7b ownership promotion plan and flag guard marked `DONE`; created a promotion-readiness manifest for all scheduler ownership families and flags, added a static scheduler flag guard that verifies explicit `== true` checks plus plan/rollback/default-off coverage, and left runtime behavior unchanged with no flags promoted. Files created: `docs/scheduler_ownership_promotion_plan.md`, `tests/replay/harness/selftest_scheduler_ownership_flags_static.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_scheduler_ownership_flags_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_run_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_run_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.28 T2.7c ownership field-test packet and evidence template

| Item | Details |
| --- | --- |
| Field-test packet | Added `docs/scheduler_ownership_field_test_packet.md` with preconditions, a global rollback rule, seven conservative manual stages, exact flags per stage, minimum scenarios, expected behavior, failure signs, rollback instructions, and evidence capture guidance. |
| Evidence template | Added `docs/scheduler_ownership_field_test_results_template.md` with reusable tester/date/build/character/job/subjob, enabled flags, scenario, expected behavior, observed behavior, pass/fail, rollback needed, notes/log snippets, and next action sections. |
| Static doc guard | Added `tests/replay/harness/selftest_scheduler_ownership_field_docs_static.lua` to inventory scheduler ownership flags, verify every flag appears in the field-test packet, enforce rollback/default-off/fallback warnings, confirm all seven stages are referenced, and confirm the results template keeps the required evidence fields. |
| Runtime behavior | No runtime behavior changed. |
| Flag promotion | No ownership flags were promoted. |
| Validation summary | Added the new static doc selftest to the aggregate replay runner and validated the full requested ownership/static/runtime parse suite. |

- 2026-06-12: Completed T2.7c ownership field-test packet and evidence template. Status change: T2.7c ownership field-test packet and evidence template marked `DONE`; created a staged manual field-test packet for all 21 ownership flags, added a reusable evidence/results template, and added a static doc guard that verifies packet coverage plus rollback/default-off warnings and required evidence fields. Runtime behavior remains unchanged, no flags were promoted, and the aggregate replay runner now includes the new static doc coverage. Files created: `docs/scheduler_ownership_field_test_packet.md`, `docs/scheduler_ownership_field_test_results_template.md`, `tests/replay/harness/selftest_scheduler_ownership_field_docs_static.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_scheduler_ownership_field_docs_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_flags_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_command_ownership_runtime.lua`, `lua tests/replay/harness/selftest_command_ownership_static.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`, `lua tests/replay/harness/selftest_run_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_ownership_static.lua`, `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_run_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.29 T2.7d local ownership field-test flag loader

| Item | Details |
| --- | --- |
| Optional loader | Added a protected `pcall(require, 'local_ownership_flags')` load in `UnifiedCombat.lua` immediately after addon-local package-path setup and before runtime modules start consuming scheduler globals. |
| Missing-file behavior | If `local_ownership_flags.lua` does not exist, the loader treats the standard Lua module-not-found error as optional and leaves addon behavior unchanged. |
| Load failure behavior | If `local_ownership_flags.lua` exists but throws during load, the addon does not crash and instead warns through `windower.add_to_chat(...)`. |
| Defaults and contracts | No ownership flag was made default-on, no fallback behavior was removed, and no ownership helper contract changed. |
| Field-test docs | Updated the field-test packet with the exact local file path plus a Stage 1 target/turn example file. |

- 2026-06-12: Completed T2.7d local ownership field-test flag loader. Status change: T2.7d local ownership field-test flag loader marked `DONE`; added an optional protected local flag file load in `UnifiedCombat.lua` so manual field testing can set `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP` globals from `local_ownership_flags.lua` without changing defaults. The loader runs after addon-local package-path setup, ignores the standard missing-module case so behavior is unchanged when the file is absent, and warns without crashing if the file exists but fails to load. Updated the field-test packet with the exact Stage 1 local file path and example content. Files modified: `UnifiedCombat.lua`, `docs/scheduler_ownership_field_test_packet.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_flags_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_field_docs_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.30 Stage 7 vector run ownership reachability audit

| Item | Details |
| --- | --- |
| Status writer | `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` is written only inside `p1_move_toward_mob(...)` in `unified_scheduler.lua`. |
| Live caller audit | Current scheduler runtime audit found no caller to `p1_move_toward_mob(...)`; `p1_try_dark_launch_dispatch(...)` only routes `target_control`, `pull_control`, and `combat` providers and never calls the vector helper path. |
| Live movement owner | Hunter/pathing/pull movement currently uses other movement systems, including `unified_combat_core.lua` direct/core movement logic and `uc_pathing.lua` route-follow behavior, rather than scheduler vector run ownership. |
| Field-test result | Stage 7 is deferred/not live-reachable in the current runtime flow. No ownership failure was observed, and lack of `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` output means live ownership execution could not be confirmed. |
| Baseline observation | The observed yoyo behavior reproduces with vector ownership disabled and is recorded as baseline scheduler movement-priority behavior rather than a vector ownership regression. |
| Documentation update | Updated the field-test packet, promotion plan, and Stage 7 field-test result note to reflect current reachability and the deferred status. |

- 2026-06-13: Completed Stage 7 vector run ownership reachability audit. Audited the current runtime scheduler flow and confirmed `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` is only written from `p1_move_toward_mob(...)`, while `p1_move_toward_mob(...)` has no live caller in current scheduler dispatch flow. Hunter/pathing movement currently uses other movement systems, so Stage 7 vector run ownership cannot be confirmed through current live field testing. Updated `docs/scheduler_ownership_field_test_packet.md`, `docs/scheduler_ownership_promotion_plan.md`, and `docs/TestResults/scheduler_ownership_field_test_results_stage7_vector_run.md` to mark Stage 7 deferred/not live-reachable, preserve the no-regression conclusion, and record the yoyo behavior as baseline movement-priority behavior for future cleanup. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_run_ownership.lua`, `lua tests/replay/harness/selftest_run_ownership_runtime.lua`, `lua tests/replay/harness/selftest_run_ownership_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_field_docs_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_flags_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.31 T2.8a movement priority and vector run decision audit

| Item | Details |
| --- | --- |
| Movement-priority audit | Added `docs/movement_priority_arbitration_audit.md` documenting the observed yoyo scenario, the likely competition between party-follow/path return and core combat/autotarget movement, the existing movement owner/intent fields, a conservative suppression rule, and its risks. |
| Vector decision | Added `docs/vector_run_reachability_decision.md` documenting that `p1_move_toward_mob(...)` has no live caller today, recommending it stay dormant for now, and separating that decision from the live movement-priority bug. |
| Runtime impact | No runtime behavior changed. |
| Recommended next slice | Narrow runtime patch in follow/path arbitration only: suppress follow/return movement during immediate post-kill combat target transitions, then re-validate the reproduced yoyo scenario. |

- 2026-06-13: Completed T2.8a movement priority and vector run decision audit. Added `docs/movement_priority_arbitration_audit.md` and `docs/vector_run_reachability_decision.md` after auditing live movement ownership across `uc_party_follow.lua`, `uc_pathing.lua`, and `unified_combat_core.lua`. Findings: follow/return-to-leader movement can reacquire control when short combat-intent windows lapse during post-kill target transition, while `p1_move_toward_mob(...)` remains dormant with no live caller in current scheduler dispatch flow. Recommended next implementation slice is a conservative follow/path suppression patch during immediate combat transition, with vector run reconnect/removal deferred to a later explicit decision. No runtime behavior changed. Validation: `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_pathing.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.32 T2.8b default-off movement priority arbitration guard

| Item | Details |
| --- | --- |
| Flag | Added `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION == true` as the default-off gate. |
| Guarded locations | `uc_party_follow.lua` follow suppression path and `uc_pathing.lua` path-follow combat pause path. |
| Suppression rule | When the flag is on and the character is a combat participant, suppress follow/return/path resume if combat transition is active via core movement lock, combat intent window, fight-follow hold window, preengage flag, or a live combat target. |
| Combat movement | No combat/autotarget movement behavior changed. |
| Coverage | Added `tests/replay/harness/selftest_movement_priority_arbitration.lua` and registered it in the aggregate replay runner. |
| Recommended field test | Reproduce the post-kill yoyo scenario once with the flag off/unset and once with the flag on, using the same prime/autotarget + follow setup. |

- 2026-06-13: Completed T2.8b default-off movement priority arbitration guard. Added a small shared suppression helper in `uc_party_follow.lua` and reused it from `uc_pathing.lua` so follow/return/path-resume movement yields during immediate combat-transition windows only when `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION == true`. The helper uses existing combat intent, movement owner/lock, fight-follow hold, preengage, and live-target state; combat/autotarget movement itself is unchanged. Added `tests/replay/harness/selftest_movement_priority_arbitration.lua` for default-off, combat-intent, movement-lock, idle, expiry, and live-target cases, and added the suite to `tests/replay/harness/selftest_all_replay_fixtures.lua`. Updated `docs/movement_priority_arbitration_audit.md` with the implemented flag, guarded locations, field-test scenario, and rollback instruction. Validation: `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `luac -p unified_combat_core.lua`, `lua tests/replay/harness/selftest_movement_priority_arbitration.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.33 T2.8c movement arbitration flag-on hardening audit

| Item | Details |
| --- | --- |
| Default-off safety | Field results confirmed `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = false` preserves current behavior, including the original yoyo reproduction. |
| Freeze review | No import cycle or repeated event registration bug was found. The most likely freeze cause was over-broad flag-on suppression on any live combat target, which could stall follow/path movement across active characters. |
| Hardening change | Removed the live-target suppression branch so flag-on arbitration now keys only off explicit transition signals: combat intent window, core movement lock, fight-follow hold, and preengage flag. |
| Fail-closed status | The flag-on path remains enabled, but in a narrower and safer form; it no longer suppresses solely because a live combat target exists. |
| Coverage | Expanded `selftest_movement_priority_arbitration.lua` to confirm live-target-only state does not suppress and that `uc_pathing.lua` still loads safely through the existing one-way helper dependency. |
| Next field test | Re-run only the original post-kill yoyo scenario with the flag off and on; do not interpret unrelated movement stalls as ownership issues. |

- 2026-06-13: Completed T2.8c movement arbitration flag-on hardening audit. Confirmed default-off safety from field results, reviewed the earlier flag-on freeze, and found no new require/import cycle or repeated registration issue. The most likely root cause was the T2.8b helper's broad live-target suppression, which could suppress follow/path behavior whenever combat targeting remained live instead of only during immediate transition windows. Hardened the flag-on path by removing that branch so arbitration now depends only on explicit transition signals already maintained by core movement state. Updated `tests/replay/harness/selftest_movement_priority_arbitration.lua` to cover the hardened fail-closed live-target-only case plus safe `uc_pathing.lua` load behavior, and updated `docs/movement_priority_arbitration_audit.md` with the field result summary and flag-on recommendation. Validation: `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `luac -p unified_combat_core.lua`, `lua tests/replay/harness/selftest_movement_priority_arbitration.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.34 T2.8d movement arbitration release refinement

| Item | Details |
| --- | --- |
| Yoyo status | Field testing confirmed the flag-on T2.8c behavior fixed the original post-kill yoyo without reintroducing the earlier freeze. |
| New issue | Follow/return-to-leader could remain suppressed after combat ended, even when no valid combat target remained. |
| Release refinement | `uc_party_follow.lua` now treats `_G.UC_COMBAT_INTENT_UNTIL` and `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL` as suppressors only while a live combat transition target still exists; stale windows now release follow promptly. |
| Preserved suppressors | Active `UC_PREENGAGE_APPROACH_ACTIVE` and active core `UC_MOVEMENT_LOCK_UNTIL` still suppress as before, so the yoyo fix remains in the true transition window. |
| Coverage | Expanded `tests/replay/harness/selftest_movement_priority_arbitration.lua` for active-transition-target, stale-intent release, stale-fight-follow release, combat-ended release, and expiry coverage. |
| Next field test | Re-run the same flag-on yoyo scenario and confirm both behaviors: no transition yoyo during retarget, and prompt return to follow once combat state fully clears. |

- 2026-06-13: Completed T2.8d movement arbitration release refinement. Kept the default-off behavior unchanged and preserved the T2.8c yoyo fix, but narrowed timeout-based suppression so `_G.UC_COMBAT_INTENT_UNTIL` and `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL` only suppress follow/path return while a live combat transition target still exists. Active preengage and active core movement locks still suppress immediately. Added clearer helper reasons for active-target suppression versus stale-window release, updated `tests/replay/harness/selftest_movement_priority_arbitration.lua` for stale timeout and combat-ended release cases, and updated `docs/movement_priority_arbitration_audit.md` with the new field expectation. Validation: `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `luac -p unified_combat_core.lua`, `lua tests/replay/harness/selftest_movement_priority_arbitration.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.35 T2.9a 0 HP death-animation target validity audit

| Item | Details |
| --- | --- |
| Observed behavior | After a Weapon Skill kill, a mob can sit at `0 HP` during death animation while still appearing targetable, which can cause a short re-engage / move-toward yoyo. |
| Existing handling | Many scan-time combat-target checks already require `valid_target == true`, `spawn_type == 16`, and `hpp > 0`; follow suppression and path pause logic also already use `hpp > 0`. |
| Gap found | Some final commit-time paths still revalidate with `valid_target` + target id only, especially core `ensure_target_and_attack(...)` and scheduler engage / WS dispatch revalidation, which leaves a race after collection/selection if the target dies before send/commit. |
| Existing reusable signal | Core already maintains `death_event_active_for_id(id)` via `core.last_death_target_id`, `core.last_death_at`, and `DEATH_SWITCH_WINDOW`, but that signal is not yet applied uniformly across final actionable-target checks. |
| Recommended next slice | Add a narrow shared actionable-target predicate for final engage / WS / movement commit-time checks so `hpp <= 0` and recent death-window targets are rejected before re-engage or movement recommit. |
| Runtime changes | None in T2.9a; docs-only audit. |

- 2026-06-13: Completed T2.9a 0 HP death-animation target validity audit. Added `docs/zero_hp_death_animation_target_validity_audit.md` to document the post-WS 0 HP / death-animation yoyo, map the engage/movement/autotarget/follow validity paths, and confirm that `hpp > 0` is already enforced in many scan-time checks but not all final commit-time revalidations. The audit found an existing short recent-death signal in `death_event_active_for_id(id)` that could be reused later, and recommended a narrow next slice that hardens final actionable-target checks before engage, WS, and movement recommit rather than broadening cooldown/reject behavior. Validation: `luac -p unified_combat_core.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.36 T2.9b final actionable-target predicate for 0 HP targets

| Item | Details |
| --- | --- |
| Predicate | Added `is_live_actionable_combat_target(mob_or_target, now, include_recent_death)` in `unified_combat_core.lua` and exported it for scheduler reuse. |
| Rejects | Nil/malformed targets, missing/zero id, `valid_target ~= true`, non-combat spawn type, missing `hpp`, `hpp <= 0`, and recent-death ids when `include_recent_death == true`. |
| Guarded callsites | Core `ensure_target_and_attack(...)`, scheduler engage dispatch revalidation, scheduler WS dispatch revalidation. |
| Scope | Commit-time hardening only; broad scan logic, ownership routing, and movement arbitration behavior remain unchanged. |
| Coverage | Added `tests/replay/harness/selftest_zero_hp_actionable_target.lua` and registered it in `tests/replay/harness/selftest_all_replay_fixtures.lua`. |
| Recommended field test | Reproduce the WS-kill death-animation window and confirm no re-engage/re-WS/move-toward churn on the dead target while prompt transition to a different live target still works. |

- 2026-06-13: Completed T2.9b final actionable-target predicate for 0 HP targets. Added `is_live_actionable_combat_target(...)` in `unified_combat_core.lua`, backed by the existing `death_event_active_for_id(...)` signal for recent-death rejection, and reused it in the three narrow commit-time callsites identified by T2.9a: core `ensure_target_and_attack(...)`, scheduler engage dispatch revalidation, and scheduler WS dispatch revalidation. Added `tests/replay/harness/selftest_zero_hp_actionable_target.lua` to cover live, zero-HP, malformed, missing-`hpp`, recent-death same-id, recent-death different-id, and expired-window cases. Updated `docs/zero_hp_death_animation_target_validity_audit.md` with the implemented predicate, exact guarded callsites, field-test scenario, and rollback note. Validation: `luac -p unified_combat_core.lua`, `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_zero_hp_actionable_target.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.37 T2.9c remaining 0 HP WS-animation movement churn guard

| Item | Details |
| --- | --- |
| T2.9b field result | The visible WS-animation mini-yoyo still reproduced after T2.9b, which showed that the remaining live path was not final engage / WS commit. |
| Remaining path found | Core end-of-tick combat movement still called `apply_movement(...)` with the current target object, and that function did not yet validate the target through `is_live_actionable_combat_target(...)`. |
| Guard added | `apply_movement(...)` now rejects 0 HP / recent-death targets immediately via `is_live_actionable_combat_target(target, uc_now_s(), true)` before producing movement intent. |
| Why narrow | The fix reuses the existing target-id-scoped predicate, does not alter broad scan logic, and still allows rescan / fast-switch to a different live target. |
| Coverage | Expanded `tests/replay/harness/selftest_zero_hp_actionable_target.lua` to confirm 0 HP and recent-death current targets produce no movement intent while a different live target still does. |
| Next field test | Re-run the WS-kill death-animation scenario and confirm there is no re-engage, re-WS, or move-toward churn on the dead target while prompt transition to another live target still works. |

- 2026-06-13: Completed T2.9c remaining 0 HP WS-animation movement churn guard. Field results from T2.9b showed the visible yoyo was still present, which narrowed the remaining path to combat movement intent rather than final engage / WS commit. Guarded `apply_movement(...)` in `unified_combat_core.lua` with `is_live_actionable_combat_target(target, uc_now_s(), true)` so end-of-tick movement now rejects 0 HP and recent-death current targets. Extended `tests/replay/harness/selftest_zero_hp_actionable_target.lua` to cover zero-HP movement-intent rejection, recent-death same-id movement rejection, and different-live-target movement preservation. Updated `docs/zero_hp_death_animation_target_validity_audit.md` with the T2.9b field result, remaining path found, and narrow guard rationale. Validation: `luac -p unified_combat_core.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `lua tests/replay/harness/selftest_zero_hp_actionable_target.lua`, `lua tests/replay/harness/selftest_movement_priority_arbitration.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.38 T3.0a scheduler ownership promotion readiness audit

| Item | Details |
| --- | --- |
| Audit file | Added `docs/scheduler_ownership_promotion_readiness_audit.md`. |
| Inventory scope | Audits all 21 `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP` flags. |
| Promote candidates | 11 low-risk, field-tested scheduler-owned flags: target, turn, isolated command paths, combat command families, and the Stage 5 movement-coordinator run-stop trio. |
| Keep default-off | 9 conservative flags: Doom command/run_stop, generic combat-spell run-stop paths, and partially/unconfirmed tank run-stop paths. |
| Retire / park | `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` remains not live-reachable and should not be promoted with the current runtime flow. |
| Non-scheduler-owned paths | Core combat movement, pathing pause/resume, follow suppression, movement arbitration, and zero-HP cleanup are explicitly separated from scheduler ownership promotion work. |
| Next slice | Recommend T3.0b to promote only the low-risk field-tested scheduler flags while retaining a temporary kill switch for rollback. |

- 2026-06-13: Completed T3.0a scheduler ownership promotion readiness audit. Added `docs/scheduler_ownership_promotion_readiness_audit.md` to inventory every scheduler ownership flag, helper seam, field-test result, replay/static coverage family, live reachability status, and promotion recommendation. Updated `docs/scheduler_ownership_promotion_plan.md` with a T3.0a readiness summary plus staged T3.0b/T3.0c/T3.0d/T3.0e promotion structure. Updated the tracker to record that 11 low-risk scheduler-owned flags are promotion candidates, 9 should remain default-off for now, and vector run ownership remains unreachable/dormant rather than promotion-ready. No runtime or helper behavior changed. Validation: `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.39 T3.0b promote low-risk field-tested scheduler ownership flags

| Item | Details |
| --- | --- |
| Promoted paths | 11 scheduler-owned paths: target, turn, isolated internal/maintenance commands, combat command families, and the three Stage 5 movement-coordinator run-stop paths. |
| Kill switch | Shared temporary kill switch: `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true`. |
| Per-flag opt-out | Any promoted path can be disabled explicitly by setting its ownership flag to `false` in `local_ownership_flags.lua`. |
| Deferred/default-off paths | Doom command/run_stop, combat spell settle/prep wait run_stop, all tank run-stop paths, and vector run ownership remain default-off. |
| Implementation shape | Existing callsite `== true` markers remain for legacy static coverage, while helper gating now treats promoted paths as enabled when unset unless explicitly opted out or globally killed. |
| Added test | `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua` covers promoted default-on behavior, per-flag `false` opt-out, global kill switch behavior, default-off flag preservation, and vector non-promotion. |
| Next field test | Re-run the previously passing Stage 1 / 2 / 3 / 5 practical scenarios with no opt-outs set, then use the global kill switch or per-flag `false` as rollback if needed. |

- 2026-06-13: Completed T3.0b promotion of low-risk field-tested scheduler ownership flags. Updated `unified_scheduler.lua` to pass promotion metadata for the 11 approved flags while leaving deferred/default-off flags unchanged. Extended `uc_scheduler_command_ownership.lua`, `uc_scheduler_run_stop_ownership.lua`, `uc_scheduler_target_ownership.lua`, and `uc_scheduler_turn_ownership.lua` so promoted paths are enabled by default when unset, but disable cleanly when their flag is explicitly `false` or when `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true`. Added `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua` and aggregate registration, updated promotion docs with the promoted list, kill switch, and field-test instructions, and kept vector run ownership explicitly unpromoted. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_command_ownership.lua`, `luac -p uc_scheduler_run_stop_ownership.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.40 T3.0c close promoted ownership field-test pass and define remaining default-off policy

| Item | Details |
| --- | --- |
| Field-test result | T3.0b promotion field test is documented as PASS. |
| Promoted status | The 11 promoted scheduler-owned paths remain accepted as default-on. |
| Rollback outcome | No global kill switch rollback was required, and no promoted per-flag `false` opt-out was needed. |
| Remaining default-off policy | Doom Holy Water command and Doom run_stop stay default-off due to unsafe/impractical live testing; combat spell settle/prep-wait run_stop stays default-off pending replay/mock coverage; tank action/tank spell/tank enmity run_stop stays default-off pending a targeted field-test packet; vector run ownership remains dormant/unreachable and should be retired/unwired or left explicitly parked until reconnection is an intentional task. |
| Runtime impact | Documentation-only; no runtime behavior changed. |
| Recommended next task | `T3.1a — targeted coverage plan for remaining default-off run_stop paths`. |

- 2026-06-13: Completed T3.0c documentation closure for promoted scheduler ownership. Updated `docs/TestResults/scheduler_ownership_promotion_t3_0b_results.md`, `docs/scheduler_ownership_promotion_plan.md`, and `docs/scheduler_ownership_promotion_readiness_audit.md` to record the T3.0b field-test PASS, confirm the 11 promoted default-on paths remained stable without rollback, and define the near-term policy for the remaining default-off Doom, combat-spell run_stop, tank run_stop, and dormant vector-run ownership paths. Updated the tracker with the closed promotion status and the recommended next task `T3.1a — targeted coverage plan for remaining default-off run_stop paths`. No runtime behavior changed. Validation: `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.41 T3.1a targeted coverage plan for remaining default-off scheduler run_stop ownership paths

| Item | Details |
| --- | --- |
| New plan doc | Added `docs/scheduler_remaining_run_stop_coverage_plan.md`. |
| Remaining scope | Covers Doom Holy Water command ownership, Doom run_stop ownership, combat spell settle/prep-wait run_stop ownership, and the remaining tank action/tank spell/tank enmity run_stop ownership paths. |
| Per-path policy | Assigns each remaining path to replay/mock-first coverage, a targeted field-test packet, continued parking, or later retirement/unwiring based on reachability and safety. |
| Vector status | Keeps `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` separate from run_stop planning and parked as dormant/unreachable. |
| Recommended next task | `T3.1b — Add replay/mock coverage for the remaining Doom and combat-spell default-off ownership branches`. |
| Runtime impact | No runtime behavior changed. |

- 2026-06-14: Completed T3.1a targeted coverage planning for the remaining default-off scheduler ownership branches. Added `docs/scheduler_remaining_run_stop_coverage_plan.md` with per-path reachability, safety, replay/mock feasibility, exact scenario requirements, next-action recommendations, promotion risk, and rollback posture for Doom, combat-spell, tank, and vector-owned leftovers. Updated `docs/scheduler_ownership_promotion_plan.md` and `docs/scheduler_ownership_promotion_readiness_audit.md` so the remaining default-off set is governed by the new coverage plan rather than treated as one undifferentiated promotion bucket. Updated the tracker with the recommended next task `T3.1b — Add replay/mock coverage for the remaining Doom and combat-spell default-off ownership branches`. No runtime behavior changed. Validation: `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.42 T3.2a alliance target-scope audit for targeting, claim, and aggro validity

| Item | Details |
| --- | --- |
| New audit doc | Added `docs/alliance_target_scope_audit.md`. |
| Audit scope | Claim validity, aggro detection, prime/autotarget selection, combat target validity, assist/engage decisions, current target reuse, and fast-switch/transition targeting. |
| Party-only centralizers found | `uc_targeting_common.build_party_claims()`, `unified_combat_core.lua` `is_party_member_id()`, scheduler `get_party_members()` / `p1_build_party_id_set()`, and `UnifiedCombat.lua` fight-leader name lookup. |
| Alliance data status | Current code uses `windower.ffxi.get_party()` heavily but scans only `p0` through `p5`; alliance slots are not currently consumed in audited runtime paths. |
| T3.1b status | Paused temporarily while this gameplay targeting-scope audit is addressed. |
| Recommended next task | `T3.2b — Add a centralized friendly combat member id/claim helper, wire it into claim validity, prime/aggressive-target inference, scheduler engage validity, and tank violation target checks, while leaving follow/pathing and other non-combat party semantics unchanged unless explicitly required.` |
| Runtime impact | No runtime behavior changed. |

- 2026-06-14: Completed T3.2a alliance target-scope audit. Added `docs/alliance_target_scope_audit.md` documenting current party-only assumptions in `uc_targeting_common.lua`, `unified_combat_core.lua`, `unified_scheduler.lua`, and `UnifiedCombat.lua`, including claim validity, prime/autotarget aggressive-target inference, tank violation victim detection, scheduler engage policy, fight-leader lookup, and party-only spacing/TP helpers. The audit concludes that alliance support should be implemented through a centralized friendly combat member id/claim helper rather than duplicated slot scans. T3.1b replay/mock coverage work is paused temporarily while this gameplay targeting-scope requirement is addressed. No runtime behavior changed. Validation: `luac -p unified_combat_core.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.43 T3.2b alliance-aware friendly combat target scope

| Item | Details |
| --- | --- |
| Feature flag | `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE == true` |
| Default behavior | Unset or non-`true` values preserve current party-only behavior. |
| New helpers | `uc_targeting_common.get_friendly_combat_member_ids(opts)`, `uc_targeting_common.build_friendly_claims(opts)`, and `uc_targeting_common.is_friendly_party_or_alliance_member_id(id, opts)`. |
| Core wiring | Widened low-risk combat-validity paths for prime/aggressive target checks, candidate claim validity, tank victim detection, and current-target claim-owner resolution. |
| Scheduler wiring | Widened friendly id / claim validity only for engage-prime and enemy-buff-removal combat paths. |
| Explicitly not widened | `UnifiedCombat.lua` fight-leader lookup, follow/pathing, spacing, party TP / WS observation, and other non-combat party semantics. |
| Test coverage | Added `tests/replay/harness/selftest_alliance_target_scope.lua` and registered it in the aggregate replay suite. |
| Recommended field test | Enable the flag locally, use alliance-only claim/aggro scenarios outside the immediate party, and confirm combat-valid targeting broadens without changing non-combat party-only behavior. |

- 2026-06-14: Completed T3.2b alliance-aware friendly combat target scope. Added default-off friendly combat member helpers in `uc_targeting_common.lua`, kept `unified_combat_core.lua` party-only WS observation intentionally unchanged, and widened only low-risk combat target-validity paths in `unified_combat_core.lua` and `unified_scheduler.lua` for alliance-aware claim validity, aggressive-target inference, current-target claim ownership, and tank victim selection. Added `tests/replay/harness/selftest_alliance_target_scope.lua`, updated the aggregate replay suite, and refreshed the line-pin side-effect inventory to reflect helper insertion shifts only. Validation: `luac -p uc_targeting_common.lua`, `luac -p unified_combat_core.lua`, `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_alliance_target_scope.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.44 T3.2c alliance target-scope field-test closure

| Item | Details |
| --- | --- |
| Result file | `docs/TestResults/alliance_target_scope_t3_2b_results.md` records T3.2b as a field-test PASS. |
| Field result | Alliance claim validity, alliance aggro/victim validity, unrelated claim rejection, zero-HP/death-animation safety, and flag-off party-only baseline behavior all passed with no observed regressions. |
| Runtime impact | No runtime behavior changed in T3.2c. |
| Flag recommendation | Keep `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE == true` as an optional enable for now. |
| Scheduler track status | `T3.1b` is no longer paused and should resume next. |
| Recommended next task | `T3.1b — Add replay/mock coverage for the remaining Doom and combat-spell default-off ownership branches`. |

- 2026-06-14: Completed T3.2c documentation closure for alliance target scope. Updated `docs/TestResults/alliance_target_scope_t3_2b_results.md`, `docs/alliance_target_scope_audit.md`, and `docs/UnifiedCombat_scheduler_refactor_tracking.md` to record the successful T3.2b field-test PASS, confirm that flag-off party-only behavior remained preserved, note that no regressions were observed, and keep `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE` optional for now as a controlled gameplay expansion. No runtime behavior changed. The scheduler ownership track is now unpaused and `T3.1b` should resume next. Validation: `lua tests/replay/harness/selftest_alliance_target_scope.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.45 T3.1b replay/mock coverage for remaining Doom and combat-spell default-off ownership branches

| Item | Details |
| --- | --- |
| New test | Added `tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`. |
| Coverage approach | Static scheduler branch verification plus helper-level mock execution for explicit true routing and fallback preservation. |
| Branches covered | `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`, `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`, `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`, and `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`. |
| Default-off status | All four remain explicit `== true` branches with no promotion in this task. |
| Kill switch interaction | Verified these four branches do not gain promoted default-on / false-opt-out / kill-switch wiring. |
| Runtime impact | No runtime behavior changed. |
| Recommended next task | `T3.1c — decide whether combat-spell default-off run_stop branches are promotion candidates or should remain intentionally default-off pending targeted live confirmation`. |

- 2026-06-14: Completed T3.1b replay/mock coverage for the remaining Doom and combat-spell default-off ownership branches. Added `tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua` and registered it in the aggregate replay suite, using static branch verification plus helper-level mock execution to prove default-off semantics, explicit true routing through the intended ownership helpers, preserved fallback behavior, and absence of promoted kill-switch/default-on wiring for the four scoped branches. Updated `docs/scheduler_remaining_run_stop_coverage_plan.md`, `docs/scheduler_ownership_promotion_plan.md`, `docs/scheduler_ownership_promotion_readiness_audit.md`, and this tracker to reflect the new coverage status. No runtime behavior changed. Validation: `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.46 T3.1c combat-spell default-off run_stop promotion policy decision

| Item | Details |
| --- | --- |
| Scope | Docs-only decision for `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` and `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`, while confirming Doom branches remain default-off. |
| Combat-spell decision | Do not promote now; require a targeted live field-test packet before any promotion decision. |
| Doom policy | `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP` and `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP` remain intentionally default-off with no real Doom live-test recommendation. |
| Runtime impact | No runtime behavior changed. |
| Recommended next task | `T3.1d — targeted combat-spell run_stop field-test packet for settle/prep-wait branches`. |

- 2026-06-14: Completed T3.1c promotion-policy decision for the combat-spell default-off run_stop branches. Applied the T3.1b coverage status to the planning docs, recorded that replay/mock confidence is strong for ownership routing but still insufficient to replace targeted live confirmation of settle/prep-wait timing behavior, kept both combat-spell run_stop flags default-off pending a focused field-test packet, and reaffirmed that the Doom command/run_stop pair remain intentionally default-off without recommending real Doom live testing. Updated `docs/scheduler_remaining_run_stop_coverage_plan.md`, `docs/scheduler_ownership_promotion_plan.md`, `docs/scheduler_ownership_promotion_readiness_audit.md`, and this tracker. No runtime behavior changed. Validation: `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.47 T3.1d targeted combat-spell run_stop field-test packet

| Item | Details |
| --- | --- |
| New doc | Added `docs/scheduler_combat_spell_run_stop_field_test_packet.md`. |
| Packet scope | `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` and `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` only. |
| Excluded scope | Doom command/run_stop, tank run-stop paths, and vector run ownership are explicitly outside this packet. |
| Runtime impact | No runtime behavior changed. |
| Recommended next action | Run the packet and record field results before any promotion decision. |

- 2026-06-14: Completed T3.1d targeted combat-spell run-stop field-test packet. Added `docs/scheduler_combat_spell_run_stop_field_test_packet.md` with purpose, exact flags under test, required local flag setup, a safe local flag snippet, setup guidance, scenario list, pass/fail criteria, a copy/paste result template, and explicit promotion-decision rules. Updated `docs/scheduler_remaining_run_stop_coverage_plan.md`, `docs/scheduler_ownership_promotion_plan.md`, `docs/scheduler_ownership_promotion_readiness_audit.md`, and this tracker to mark the packet as created with no promotion yet. No runtime behavior changed. Validation: `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.48 T3.1e scheduler tank-spell movement-lock mismatch fix

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Keep scheduler tank-spell movement suppressed after the existing pre-send `run_stop` so movement does not resume while the spell is still in flight. |
| Runtime files changed | `unified_scheduler.lua` |
| Test files changed | `tests/replay/harness/selftest_scheduler_tank_spell_movement_lock.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/scheduler_remaining_run_stop_coverage_plan.md`, `docs/scheduler_ownership_promotion_plan.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Root cause | The scheduler tank-spell branch issued the existing stop but did not carry forward the bounded post-send movement lock / wait bookkeeping already present in the core tank-spell flow. |
| Fix summary | Added scheduler-local tank-spell wait state after tank spell send and refreshed a short bounded scheduler movement lock while the spell remains in-flight or in immediate spell cooldown. |
| Ownership policy impact | None. Tank run-stop ownership flags remain in their prior default-off/default-on states. |
| Validation summary | `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_pathing.lua`; `luac -p uc_party_follow.lua`; `lua tests/replay/harness/selftest_scheduler_tank_spell_movement_lock.lua`; `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Next field test | Reproduce the Terrasjr tank-enmity spell scenario with schedulers enabled and confirm the character stops for the spell, does not run through the mob, and resumes movement only after the cast window clears. |

- 2026-06-17: Completed T3.1e scheduler tank-spell movement-lock mismatch fix. Updated `unified_scheduler.lua` so tank spell sends now create bounded scheduler-local wait bookkeeping and a refreshed short scheduler movement lock while the in-flight spell remains active, preventing movement from resuming immediately after the existing pre-send `run_stop`. Added `tests/replay/harness/selftest_scheduler_tank_spell_movement_lock.lua` and registered it in the aggregate replay suite to pin the new wait-state fields, helper lifecycle, bounded lock refresh, provider-entry guard, and post-send wiring for both target and self tank-spell sends. Updated `docs/scheduler_remaining_run_stop_coverage_plan.md`, `docs/scheduler_ownership_promotion_plan.md`, and this tracker to record the bugfix as a runtime parity repair rather than an ownership-promotion decision. Ownership promotion policy did not change. Validation: `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_pathing.lua`, `luac -p uc_party_follow.lua`, `lua tests/replay/harness/selftest_scheduler_tank_spell_movement_lock.lua`, `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.49 T3.1e cure-cast movement-stop audit correction

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Audit the corrected report that the observed movement-stop failure was a Cure cast during initial mob approach, not a tank-enmity spell. |
| Files changed | `docs/cure_cast_movement_stop_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Runtime behavior changed | No |
| Most likely source | Scheduler defensive Cure send paths in `unified_scheduler.lua`, especially `try_internal_defensive_action()` and ranked `provider == 'defensive_internal'`, which send Cure commands without `run_stop`, movement-owner refresh, movement-lock refresh, or cast-wait state. |
| Secondary source | Scheduler healbot wrapper also provides no stop/lock lifecycle of its own, though the underlying healer implementation was outside this audit scope. |
| Not the source | The corrected report does not match the tank-spell runtime path; no evidence in the audited proposal collectors shows Cure routing through the generic combat spell family today. |
| Recommended next task | Add a narrow scheduler defensive spell-cast movement-stop/lock fix at the Cure/defensive spell send point, without changing ownership promotion policy. |
| Validation summary | `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_party_follow.lua`; `luac -p uc_pathing.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |

- 2026-06-17: Completed the corrected Cure-cast movement-stop audit. Added `docs/cure_cast_movement_stop_audit.md` documenting the observed field behavior, the corrected context that the spell was Cure rather than tank enmity, the Cure-capable path inventory, and a comparison against spell flows that already stop correctly. The audit finds the strongest evidence in the scheduler defensive Cure paths inside `unified_scheduler.lua`: they can send Cure while moving, but they do not issue `run_stop`, do not set `_G.UC_MOVEMENT_OWNER`, do not refresh `_G.UC_MOVEMENT_LOCK_UNTIL`, and do not create a cast-wait state. Movement consumers in `uc_pathing.lua` and `uc_party_follow.lua` already honor those kinds of locks/waits when present, which makes the missing defensive spell lifecycle the most likely source. No runtime behavior changed. Recommended next step: a narrow defensive spell-cast movement-lock fix at the Cure send point, separate from tank spell ownership/promotion work. Validation: `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.50 T3.1f scheduler defensive Cure movement-stop/lock lifecycle fix

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Patch the scheduler defensive Cure/spell send lifecycle so defensive spell casts establish a bounded movement stop/lock lifecycle at send time. |
| Runtime files changed | `unified_scheduler.lua` |
| Test files changed | `tests/replay/harness/selftest_scheduler_defensive_cure_movement_lock.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/cure_cast_movement_stop_audit.md`, `docs/scheduler_remaining_run_stop_coverage_plan.md`, `docs/scheduler_ownership_promotion_plan.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Root cause | Confirmed: the scheduler defensive Cure/internal spell send paths were sending spells without a scheduler-owned stop, without movement-owner/lock refresh, and without a bounded post-send spell wait lifecycle. |
| Exact patched paths | `try_internal_defensive_action()` direct internal defensive spell send and ranked `provider == 'defensive_internal'` dispatch send in `unified_scheduler.lua`. |
| Healbot wrapper finding | No broad healbot rewrite was needed in this task; the healbot wrapper still delegates to `_G.healer:take_action(...)` and should be field-verified separately if symptoms persist under `defensive_provider='healbot'`. |
| Fix summary | Added a scheduler-local defensive spell stop helper using the existing run-stop seam with unchanged ownership policy, plus bounded defensive spell wait bookkeeping refreshed before later movement ticks. |
| Side-effect invariant | No new direct textual scheduler side-effect call expressions were introduced. |
| Ownership policy impact | None. No promoted/default-off ownership policy changed. |
| Validation summary | `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_party_follow.lua`; `luac -p uc_pathing.lua`; `lua tests/replay/harness/selftest_scheduler_defensive_cure_movement_lock.lua`; `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Next field test | Reproduce the original Cure-during-approach scenario with `defensive_provider='internal'`, confirm the character stops for Cure and resumes movement after the bounded spell window, then separately verify whether any remaining symptom is healbot-specific. |

- 2026-06-17: Completed T3.1f scheduler defensive Cure movement-stop/lock lifecycle fix. Updated `unified_scheduler.lua` so the direct internal defensive spell sender and the ranked `provider == 'defensive_internal'` send path now apply a bounded scheduler-owned stop/lock lifecycle at the spell send point. The fix uses the existing `uc_scheduler_run_stop_ownership` seam with unchanged ownership policy, sets `_G.UC_MOVEMENT_OWNER` / `_G.UC_MOVEMENT_LOCK_UNTIL`, records a scheduler-local defensive spell wait state after send, and refreshes that lock before later scheduler movement ticks while the spell remains active or in immediate cooldown. Added `tests/replay/harness/selftest_scheduler_defensive_cure_movement_lock.lua` and registered it in the aggregate replay suite to pin the new helper fields, bounded wait lifecycle, send-point wiring, stale-target guard, process-tick refresh order, side-effect invariant, and unchanged ownership policy. Updated the Cure audit and promotion-planning docs to record the bugfix separately from ownership promotion work. Validation: `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_party_follow.lua`, `luac -p uc_pathing.lua`, `lua tests/replay/harness/selftest_scheduler_defensive_cure_movement_lock.lua`, `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.51 T3.1g defensive Cure priority audit and chooser fix

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Audit why valid ally Cure opportunities were losing to self-buffs and apply the narrowest safe fix if the cause was clear. |
| Runtime files changed | `unified_scheduler.lua` |
| Test files changed | `tests/replay/harness/selftest_defensive_cure_priority.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/defensive_cure_priority_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Cure candidates missing or losing | Losing |
| Exact rule causing issue | `choose_defensive_action(...)` previously allowed normal `c.buff` and Majesty to beat an already-valid Cure candidate based on low self-buff `prio` vs higher ally Cure `prio`. |
| Diagnostics added | No |
| Fix summary | Removed the normal buff-vs-cure preemption in the Cure branch as the first pass. Majesty handling was later refined in T3.1h. |
| Runtime behavior changed | Yes, narrowly in defensive pre-selection only |
| Validation summary | `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_targeting_common.lua`; `lua tests/replay/harness/selftest_defensive_cure_priority.lua`; `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Reproduce the yellow/red ally HP scenario with overwrite disabled and confirm Cure is selected over self-buffs whenever a valid Cure candidate exists; recheck solo self-buff and self-Paralyna behavior afterward. |

- 2026-06-17: Completed T3.1g defensive Cure priority audit and chooser fix. Added `docs/defensive_cure_priority_audit.md` documenting the defensive candidate flow, Cure generation gates, and the exact chooser rule that let a low-priority self-buff beat a valid ally Cure candidate before the scheduler ever ranked the proposal. The audit confirmed Cure candidates were being generated but were losing inside `choose_defensive_action(...)`, not disappearing from candidate generation. Updated `unified_scheduler.lua` narrowly so Majesty no longer preempts an available Cure candidate and normal `c.buff` no longer beats `c.cure` inside the Cure branch, while preserving overwrite behavior and self-Paralyna/debuff priority handling. Added `tests/replay/harness/selftest_defensive_cure_priority.lua` and registered it in the aggregate replay suite to pin the new chooser behavior and the key source-text invariants. Validation: `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_targeting_common.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.52 T3.1h Majesty-over-Cure restoration and defensive JA-to-Cure follow-up

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Restore Majesty-over-Cure priority while keeping ordinary self-buffs behind valid Cure candidates, and remove the overly broad JA action-state delay for the immediate defensive Cure follow-up. |
| Runtime files changed | `unified_scheduler.lua`, `uc_scheduler_action_state.lua` |
| Test files changed | `tests/replay/harness/selftest_defensive_cure_priority.lua`, `tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/defensive_cure_priority_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Majesty-vs-Cure policy | Majesty is restored as a special setup action that may beat an available Cure candidate. |
| Ordinary buff-vs-Cure policy | Ordinary self-buffs still do not beat valid Cure candidates. |
| Root cause of delayed Cure follow-up | Generic JA action-state acting/cooldown blocking in `uc_scheduler_action_state.lua` was also gating the immediate defensive Cure that should follow Majesty. |
| Action-state change | Added last-action metadata plus a bounded defensive-only Majesty -> Cure bypass in `action_dispatch_blocked(...)`, keyed by transient `_G.UC_DEFENSIVE_CHAIN_ACTION` context set around the defensive scheduler block check. |
| Generic JA lock outside this chain | Preserved |
| Ownership policy impact | None. No promoted/default-off ownership policy changed. |
| Validation summary | `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_defensive_cure_priority.lua`; `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`; `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Enable the same defensive scheduler setup used for the earlier Cure tests, reproduce a Majesty -> Cure opportunity on an injured ally, confirm Majesty still fires first, confirm the Cure follows immediately without waiting out the full JA pause, and confirm ordinary self-buffs still do not preempt valid Cure opportunities. |

- 2026-06-17: Completed T3.1h Majesty-over-Cure restoration and defensive JA-to-Cure follow-up. Refined the T3.1g chooser change in `unified_scheduler.lua` so Majesty again wins as a special defensive setup action, while ordinary `c.buff` candidates still lose to valid Cure candidates and self-Paralyna keeps its higher urgency behavior. Audited `uc_scheduler_action_state.lua` and confirmed the real follow-up delay came from the generic JA acting/cooldown block after Majesty. Added lightweight last-action metadata plus a narrow bounded bypass that only applies to the defensive_internal Majesty -> Cure chain, and wired the ranked defensive scheduler branch to publish the chain context before `action_dispatch_blocked()` and clear it immediately after. Added `tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, updated `tests/replay/harness/selftest_defensive_cure_priority.lua`, and kept ownership promotion/default-off policy unchanged. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.53 T3.1i bounded JA/WS weave allowance between repeated Cure actions

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Prevent repeated non-critical defensive Cure selection from fully starving eligible instant JA/WS actions, while keeping Cure dominant when healing is urgent. |
| Runtime files changed | `unified_scheduler.lua`, `uc_scheduler_action_state.lua` |
| Test files changed | `tests/replay/harness/selftest_defensive_cure_priority.lua`, `tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `tests/replay/harness/selftest_defensive_cure_weave_policy.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/defensive_cure_priority_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Root cause of starvation | Defensive Cure proposals repeatedly won ranked selection because they score at `priority_band = 100/110`, while ordinary combat JA/WS proposals usually score around `70`; this was primarily a ranking/selection issue rather than a generic action-block issue. |
| Weave policy | After a recent defensive Cure send, if the next top-ranked action is another non-critical defensive Cure and an eligible combat JA or WS also passes final commit-time revalidation, the scheduler may select exactly one such instant action before Cure resumes. |
| Eligible weave actions | Combat WS and combat JA proposals only. |
| Critical Cure safety | No weave is allowed when the Cure target is at or below the configured critical HP threshold. |
| Ordinary self-buffs vs Cure | Preserved: ordinary self-buffs still do not beat a valid Cure candidate. |
| Majesty behavior | Preserved from T3.1h. |
| Ownership policy impact | None. No promoted/default-off ownership policy changed. |
| Validation summary | `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_defensive_cure_priority.lua`; `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`; `lua tests/replay/harness/selftest_defensive_cure_weave_policy.lua`; `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Keep a non-critical injured ally in sustained healing range, confirm one eligible JA/WS can weave between repeated Cure casts, confirm only one instant action is woven before Cure resumes, then separately confirm critical Cure still blocks that weave. |

- 2026-06-17: Completed T3.1i bounded JA/WS weave allowance between repeated Cure actions. Audited the ranked scheduler flow and confirmed the starvation came from defensive Cure proposals repeatedly winning at `priority_band = 100/110` while ordinary combat JA/WS proposals sat around `70`, not from the T3.1h Majesty follow-up allowance itself. Updated `uc_scheduler_action_state.lua` to arm a bounded recent-Cure weave window after defensive Cure sends, then refined `unified_scheduler.lua` at the final ranked selection seam so only a non-critical repeated defensive Cure may be temporarily displaced by one commit-valid combat JA or WS. The next Cure resumes priority naturally after that single instant action because the last-send kind is no longer the defensive spell, and the bounded timeout cleans up unused allowance. Added `tests/replay/harness/selftest_defensive_cure_weave_policy.lua`, registered it in the aggregate replay suite, and kept ordinary self-buff suppression, Majesty priority, critical Cure safety, and ownership promotion policy unchanged. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `lua tests/replay/harness/selftest_defensive_cure_weave_policy.lua`, `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.54 T3.1i hb_buff_maint Majesty preference in defensive buff candidate selection

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Prefer Majesty in `hb_buff_maint.choose(...)` when it is missing and eligible, so the defensive chooser actually receives a Majesty candidate before Cure when appropriate. |
| Runtime files changed | `uc_hb_buff_maint.lua` |
| Test files changed | `tests/replay/harness/selftest_hb_buff_maint_majesty_priority.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/defensive_cure_priority_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Root cause confirmed or revised | Revised/confirmed upstream: `uc_hb_buff_maint.choose(...)` previously returned the first eligible missing ready buff in listed order, so Majesty could fail to surface as the single buff candidate passed into `choose_defensive_action(...)`. |
| Majesty selection behavior | If Majesty is missing and eligible, it now wins over earlier ordinary defensive buffs inside `hb_buff_maint.choose(...)`; otherwise the prior first-eligible non-Majesty behavior remains. |
| Readiness/recast/throttle bypass | None. Majesty still respects existing readiness, missing-buff, and attempt/throttle gates. |
| Ordinary self-buffs vs Cure | Preserved: ordinary self-buffs still do not beat valid Cure candidates. |
| Majesty-vs-Cure chooser behavior | Preserved from T3.1h. |
| Ownership policy impact | None. No promoted/default-off ownership policy changed. |
| Validation summary | `luac -p uc_hb_buff_maint.lua`; `luac -p unified_scheduler.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_hb_buff_maint_majesty_priority.lua`; `lua tests/replay/harness/selftest_defensive_cure_priority.lua`; `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`; `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Keep Majesty absent while another ordinary defensive buff is also missing, confirm Majesty is selected first when ready, then confirm ordinary buffs resume normal selection only when Majesty is unavailable, already active, or gated. |

- 2026-06-17: Completed T3.1i hb_buff_maint Majesty preference in defensive buff candidate selection. Confirmed the remaining repeated-Cure-without-Majesty behavior was not explained by the chooser-level T3.1h policy alone, because `build_defensive_candidates()` only receives one buff candidate from `uc_hb_buff_maint.choose(...)`. Updated `uc_hb_buff_maint.lua` so the module still evaluates buff eligibility exactly as before, but now remembers the first eligible non-Majesty buff and returns Majesty immediately if it is also eligible and missing. This preserves all existing readiness, missing-buff, and attempt/throttle gates, while ensuring the defensive chooser actually sees a Majesty candidate when it should. Added `tests/replay/harness/selftest_hb_buff_maint_majesty_priority.lua`, registered it in the aggregate replay suite, and left the T3.1h chooser policy plus ownership promotion/default-off policy unchanged. Validation: `luac -p uc_hb_buff_maint.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_hb_buff_maint_majesty_priority.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.55 T3.1j cast interruption action-state audit

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Determine whether incoming spell interruption outcomes such as `<playername>'s casting is interrupted` are currently parsed and bridged into scheduler action state, spell waits, and movement locks. |
| Runtime files changed | None |
| Docs changed | `docs/cast_interruption_action_state_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Incoming handlers found | `UnifiedCombat.lua` incoming chunk hook; raw `0x029` action-message parsing forwarded to both core and scheduler; scheduler `on_incoming_chunk`, `on_action`, and `on_action_message`; core `on_action_message`. |
| Exact `casting is interrupted` handling found | No |
| Cast interruption currently detected | Not explicitly in scheduler paths; core pull/tank spell wait uses a generic non-init/non-success action-message retry branch, but no explicit interruption classification was found. |
| Scheduler action state consumes interruption | Not explicitly. Scheduler action state currently uses outbound send markers, action starts, broad self action-message packet-end handling, and timeout/cooldown release; no interruption-specific defensive spell-wait bridge was found. |
| Likely future implementation hook | `scheduler.on_action_message(msg)` using existing raw `0x029` action-message parsing, scoped first to local-player spell interruption only. |
| Runtime behavior changed | No |
| Validation summary | `luac -p UnifiedCombat.lua`; `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Recommended next task | Add replay/mock coverage for local-player spell interruption `0x029` outcomes, then bridge only scheduler defensive spell wait and local spell action-state release from that event. |

- 2026-06-17: Completed T3.1j cast interruption action-state audit. Audited `UnifiedCombat.lua`, `unified_scheduler.lua`, `unified_combat_core.lua`, and `uc_scheduler_action_state.lua` for incoming packet/message handling related to the exact game message `<playername>'s casting is interrupted`. Found existing raw `0x029` action-message parsing and forwarding into both core and scheduler, plus actor-centric scheduler `action_mark_packet_end()` for any non-zero local-player action message and generic core pull/tank spell retry clearing when a spell message is neither initiating nor successful. Did not find explicit interruption text handling, an interruption-specific message-id bucket, or a scheduler defensive-spell-wait bridge that clears immediately on interruption. Documented the disconnect and recommended the narrowest future implementation hook in `scheduler.on_action_message(msg)` scoped to local-player spell interruption only, with replay/mock coverage before field rollout. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.56 T3.1k local-player scheduler defensive spell interruption handling

| Item | Details |
| --- | --- |
| Status | DONE |
| Goal | Clear scheduler defensive spell wait and local defensive spell action-state promptly on confirmed local-player interruption/failure, without clearing unrelated JA/WS/core state. |
| Runtime files changed | `unified_scheduler.lua`, `uc_scheduler_action_state.lua` |
| Test files changed | `tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/cast_interruption_action_state_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Interruption classification used | Parsed local-player `0x029` action message during active scheduler defensive spell wait where target matches pending target when present and `message_id` is non-zero, not a known spell-init id, and not a known spell-success id. |
| Scheduler state cleared | `clear_defensive_spell_wait_state()` plus local defensive spell action-state acting/cooldown shortening via `clear_local_defensive_spell_interruption()`. |
| State intentionally not cleared | JA state, WS state, another player's action state, core pull/tank spell wait state, and movement locks owned by unrelated systems. |
| Movement-lock behavior | Scheduler-owned movement lock is shortened to a brief tail (`min(current_lock_until, now + 0.2)`) rather than dropped immediately, to reduce self-interrupt loop risk. |
| Ownership policy impact | None. No promoted/default-off ownership policy changed. |
| Runtime behavior changed | Yes, narrowly for local-player scheduler defensive spell interruption/failure only. |
| Validation summary | `luac -p UnifiedCombat.lua`; `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`; `lua tests/replay/harness/selftest_defensive_cure_priority.lua`; `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Trigger a scheduler defensive Cure or spell, interrupt it via movement/hit, confirm defensive spell wait clears immediately, confirm local action-state no longer waits for timeout, and confirm only a short scheduler movement-lock tail remains before retry/reselection. |

- 2026-06-17: Completed T3.1k local-player scheduler defensive spell interruption handling. Reused the existing `0x029` action-message plumbing in `UnifiedCombat.lua` and `unified_scheduler.lua` to classify local-player scheduler defensive spell interruption/failure narrowly as a non-zero action message received during active scheduler defensive spell wait that is neither a known spell-init id nor a known spell-success id, with pending-target matching when present. Updated `uc_scheduler_action_state.lua` with a narrow helper that clears only local defensive spell acting/cooldown state when the last send was a defensive spell provider, then updated `scheduler.on_action_message(msg)` to clear scheduler defensive spell wait and shorten only scheduler-owned movement lock to a brief tail. Added `tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`, registered it in the aggregate replay suite, and left ownership promotion, JA/WS state, and core pull/tank spell wait behavior unchanged. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.57 T3.1l spell cast start/success handling audit

| Item | Details |
| --- | --- |
| Status | DONE |
| Runtime behavior changed | No |
| Files modified | `docs/cast_success_action_state_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Incoming spell-start handlers found | `UnifiedCombat.lua` action listener -> `UC_COMBAT_CORE.on_action(act)` and `_G.UC_SCHED_OnAction(act)`; raw `0x029` incoming chunk -> `UC_COMBAT_CORE.on_action_message(msg)` and `_G.UC_SCHED_OnActionMessage(msg)` |
| Known spell-init ids | `3`, `43`, `326`, `327`, `675`, `716` |
| Known spell-success ids | `2`, `236`, `237`, `252`, `268`, `271` |
| Scheduler spell-start state | `scheduler.on_action(act)` calls `action_mark_packet_start()` for local-player `spell` and also `spell_finish`, so action-state enters acting until a later end signal or timeout. |
| Scheduler spell-success state | `scheduler.on_action_message(msg)` calls `action_mark_packet_end()` for any non-zero local-player action message, including spell success, then generic action-state cooldown tail is applied on the next `action_is_acting()` evaluation. |
| Scheduler defensive spell wait on success | No success-specific clear exists today; wait remains active until `refresh_defensive_spell_wait_lock()` later observes `not acting` and cooldown expiry, then clears with `released_complete`. |
| Movement lock on success | While defensive spell wait remains active, `_G.UC_MOVEMENT_OWNER = 'scheduler'` and `_G.UC_MOVEMENT_LOCK_UNTIL` keeps being refreshed to a short rolling tail; release is poll-based rather than success-message-based. |
| Core pull/tank spell success comparison | `core.on_action_message(msg)` explicitly clears pull/tank spell waits on known success ids, and `core.on_action(act)` also clears those waits on local-player `spell_finish` when target/name match. |
| Main gap found | Scheduler interruption handling is now more precise than scheduler success handling; defensive spell success does not explicitly clear scheduler defensive spell wait or shorten the scheduler-owned movement-lock tail promptly on success. |
| Recommended next task | T3.1m — Add local-player scheduler defensive spell success bridge with replay/mock coverage and bounded post-cast release behavior. |
| Validation summary | `luac -p UnifiedCombat.lua`; `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |

- 2026-06-17: Completed T3.1l spell cast start/success handling audit. Audited `UnifiedCombat.lua`, `unified_scheduler.lua`, `unified_combat_core.lua`, and `uc_scheduler_action_state.lua` for local-player and other-player spell start/success handling through the action listener and raw `0x029` action-message path. Confirmed the scheduler marks local-player spell start through `scheduler.on_action(act)` and ends generic local-player action-state on any non-zero self action message through `scheduler.on_action_message(msg)`, but does not explicitly clear scheduler defensive spell wait on known spell-success ids. Documented that scheduler defensive spell wait and scheduler-owned movement lock currently release by later polling after the generic cooldown tail, while core pull/tank spell waits already clear explicitly on known success ids and matching `spell_finish` action packets. No runtime behavior changed in this audit. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.58 T3.1m local-player scheduler defensive spell success handling

| Item | Details |
| --- | --- |
| Status | DONE |
| Runtime behavior changed | Yes, narrowly for local-player scheduler defensive spell success only |
| Runtime files changed | `unified_scheduler.lua`, `uc_scheduler_action_state.lua` |
| Test files changed | `tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/cast_success_action_state_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Success classification used | Parsed local-player `0x029` action message during active scheduler defensive spell wait where target matches pending target when present and `message_id` is a known spell-success id (`2`, `236`, `237`, `252`, `268`, `271`) and not a known spell-init id (`3`, `43`, `326`, `327`, `675`, `716`). |
| Scheduler state cleared on success | `clear_defensive_spell_wait_state()` plus local defensive spell action-state shortening via `clear_local_defensive_spell_success()`. |
| State intentionally not cleared | JA state, WS state, another player's action-state, core pull/tank spell wait state, and movement locks owned by unrelated systems. |
| Movement-lock behavior | Scheduler-owned movement lock is shortened to a bounded tail (`min(current_lock_until, now + 0.2)`) so follow/path/reselection can release promptly without hard-dropping unrelated protections. |
| `spell_finish` review result | Removed `spell_finish` from scheduler start-lock categories because spell completion is not a start signal and could refresh `action_start` immediately before success-message handling. |
| Ownership policy impact | None. No promoted/default-off ownership policy changed. |
| Validation summary | `luac -p UnifiedCombat.lua`; `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`; `lua tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`; `lua tests/replay/harness/selftest_defensive_cure_priority.lua`; `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Trigger a scheduler defensive Cure or spell while movement-maintenance/follow behavior is active, confirm spell success clears scheduler defensive spell wait immediately, confirm follow/path releases after only the short bounded tail, confirm interruption behavior from T3.1k still works, and confirm JA/WS behavior remains unchanged. |

- 2026-06-17: Completed T3.1m local-player scheduler defensive spell success handling. Added a narrow local-player scheduler defensive spell success bridge in `scheduler.on_action_message(msg)` that classifies only known spell-success ids during active scheduler defensive spell wait, requires pending-target match when present, clears scheduler defensive spell wait promptly, shortens local defensive spell action-state to a bounded `0.2` post-cast tail, and shortens only scheduler-owned movement lock to the same bounded tail. Added `clear_local_defensive_spell_success()` in `uc_scheduler_action_state.lua`, removed `spell_finish` from the scheduler start-marker bucket so completion no longer refreshes `action_start`, added `tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, registered it in the aggregate replay suite, and left ownership promotion, JA/WS state, core pull/tank spell waits, and unrelated movement locks unchanged. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, `lua tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.59 T3.1n delayed target acquisition and engage audit

| Item | Details |
| --- | --- |
| Status | DONE |
| Runtime behavior changed | No |
| Diagnostics added | No |
| Files modified | `docs/target_engage_delay_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Audit scope | Target death/current-target invalidation, next-target scan, claim validity, scheduler target proposal, scheduler engage proposal, ranking, ownership dispatch, target prep, engage dispatch, action-state blocking, movement-lock blocking, duplicate suppression, and long-lived state that can survive extended play. |
| Strongest blocker candidate | Scheduler engage dispatch calls `action_mark_sent('engage')`, which enters the generic action-state acting path with `lag_timeout = 8.0`, but the audit did not find an engage-specific completion bridge; if `/attack on` does not generate a usable local self action-message end signal, the next engage can stay blocked until timeout. |
| Secondary blocker candidates | Short post-kill engaged-state / sticky windows, pre-engage target-control then engage sequencing, and hunter claim-timeout/ignore-cooldown flow in claim-transition scenarios. |
| Ownership dispatch finding | Promoted target/turn ownership helpers fall back immediately in-process and are unlikely to create multi-second delay; engage attack-on is direct `uc_attack.engage_target(...)`, not command-ownership routed. |
| Validation summary | `luac -p UnifiedCombat.lua`; `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_targeting_common.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Recommended next task | `T3.1o — Add a narrow scheduler engage completion/release bridge, or remove engage from the generic 8-second acting timeout path if no reliable local completion signal exists.` |

- 2026-06-18: Completed T3.1n delayed target acquisition and engage audit. Added `docs/target_engage_delay_audit.md` tracing the full death→target→engage pipeline across core target selection, scheduler target/engage proposal creation, ranking, ownership dispatch, target prep, engage dispatch, and action-state/movement-lock gates. The audit found the strongest evidence-backed blocker at the scheduler action-state layer: successful engage dispatch currently calls `action_mark_sent('engage')`, which enters the generic acting path with `lag_timeout = 8.0`, but the current scheduler audit did not find an engage-specific completion bridge analogous to the recent spell interruption/success bridges. If `/attack on` does not emit a usable local action-message end signal, the next valid target can wait until timeout before engage dispatch unblocks, which matches the reported 5–10 second symptom window. Secondary contributors documented were short post-kill engaged/sticky windows, target-control→engage serialization, and hunter claim timeout flow for claim-transition scenarios. No runtime behavior changed and no diagnostics were added. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_targeting_common.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

### 2.60 T3.1o scheduler engage action-state release fix

| Item | Details |
| --- | --- |
| Status | DONE |
| Runtime behavior changed | Yes, narrowly for scheduler engage action-state release only |
| Runtime files changed | `unified_scheduler.lua`, `uc_scheduler_action_state.lua` |
| Test files changed | `tests/replay/harness/selftest_scheduler_engage_action_state_release.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Docs changed | `docs/target_engage_delay_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md` |
| Root cause | Confirmed from the T3.1n audit: successful scheduler engage dispatch entered the generic action-state acting path via `action_mark_sent('engage')`, but no engage-specific completion bridge was visible, so engage could stay blocked until the generic `lag_timeout = 8.0` if no useful local completion signal arrived. |
| Before patch | Successful engage send entered generic acting state and could block later engage dispatch through `action_dispatch_blocked()` until local packet-end/message evidence arrived or the generic `8.0` second timeout expired. |
| After patch | Successful engage send uses an engage-specific action-state helper that does not enter generic acting state and instead leaves only a bounded cooldown/debounce tail of `0.35` seconds. |
| Generic timing unchanged | Spell, JA, and WS action-state timing remain on their prior generic / JA-specific timeout paths. |
| Ownership policy impact | None. No promoted/default-off ownership flags, dispatcher behavior, or ownership helpers changed. |
| Validation summary | `luac -p UnifiedCombat.lua`; `luac -p unified_scheduler.lua`; `luac -p unified_combat_core.lua`; `luac -p uc_scheduler_action_state.lua`; `lua tests/replay/harness/selftest_scheduler_engage_action_state_release.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`; `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`; `lua tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`; `lua tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`; `lua tests/replay/harness/selftest_runtime_parse.lua`; `lua tests/replay/harness/selftest_side_effect_inventory.lua`; `lua tests/replay/harness/selftest_all_replay_fixtures.lua` |
| Field-test instructions | Reproduce a kill-to-next-target transition where delayed engage previously appeared, confirm the next valid target engages without the old 5–10 second stall, confirm no per-tick `/attack on` spam appears, and confirm spell/JA/WS behavior remains unchanged. |

- 2026-06-18: Completed T3.1o scheduler engage action-state release fix. Confirmed the T3.1n root-cause candidate and patched it narrowly by adding `action_mark_engage_sent()` in `uc_scheduler_action_state.lua`, then wiring the scheduler engage dispatch branch in `unified_scheduler.lua` to use that helper instead of the generic `action_mark_sent('engage')`. The new engage-specific helper does not enter the generic acting state and instead leaves only a bounded `0.35` second cooldown/debounce tail, while existing pending and duplicate-suppression windows continue to prevent attack-on spam. Added `tests/replay/harness/selftest_scheduler_engage_action_state_release.lua`, registered it in the aggregate replay suite, and left spell/JA/WS action-state timing, recent defensive spell interruption/success handling, dispatcher behavior, and ownership promotion policy unchanged. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_scheduler_engage_action_state_release.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, `lua tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.

## 3) Completed Work (Concrete File Deliverables)

### 3.1 Harness foundation

- `tests/replay/harness/deep_copy.lua`
- `tests/replay/harness/side_effect_guard.lua`
- `tests/replay/harness/structural_compare.lua`
- `tests/replay/harness/fixture_validator.lua`
- `tests/replay/harness/fixture_runner.lua`
- `tests/replay/harness/fixture_suite_runner.lua`

Self-tests:
- `tests/replay/harness/selftest_replay_harness.lua`
- `tests/replay/harness/selftest_fixture_validator.lua`
- `tests/replay/harness/selftest_fixture_runner.lua`
- `tests/replay/harness/selftest_fixture_suite_runner.lua`
- `tests/replay/harness/selftest_runtime_parse.lua`
- `tests/replay/harness/selftest_side_effect_inventory.lua`
- `tests/replay/harness/selftest_turn_ownership_static.lua`
- `tests/replay/harness/selftest_turn_ownership_runtime.lua`
- `tests/replay/harness/selftest_all_replay_fixtures.lua`

Runtime foundation files:
- `uc_scheduler_dispatcher.lua`
- `uc_scheduler_turn_ownership.lua`

### 3.2 Parser + helper module fixture suites completed

- Status snapshot parser:
  - `tests/replay/fixtures/parser/status_snapshot_063_fixtures.lua`
  - `tests/replay/harness/status_snapshot_063_fixture_runner.lua`
  - `tests/replay/harness/selftest_status_snapshot_063_fixtures.lua`

- Enemy effect utils:
  - `tests/replay/fixtures/enemy_effect/enemy_effect_utils_fixtures.lua`
  - `tests/replay/harness/enemy_effect_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_enemy_effect_utils_fixtures.lua`

- Text utils:
  - `tests/replay/fixtures/text/text_utils_fixtures.lua`
  - `tests/replay/harness/text_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_text_utils_fixtures.lua`

- Action metadata:
  - `tests/replay/fixtures/action_metadata/action_metadata_fixtures.lua`
  - `tests/replay/harness/action_metadata_fixture_runner.lua`
  - `tests/replay/harness/selftest_action_metadata_fixtures.lua`

- Command builder:
  - `tests/replay/fixtures/command_builder/command_builder_fixtures.lua`
  - `tests/replay/harness/command_builder_fixture_runner.lua`
  - `tests/replay/harness/selftest_command_builder_fixtures.lua`

- Numeric utils:
  - `tests/replay/fixtures/numeric/numeric_utils_fixtures.lua`
  - `tests/replay/harness/numeric_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_numeric_utils_fixtures.lua`

- Proposal keys:
  - `tests/replay/fixtures/proposal_keys/proposal_keys_fixtures.lua`
  - `tests/replay/harness/proposal_keys_fixture_runner.lua`
  - `tests/replay/harness/selftest_proposal_keys_fixtures.lua`

- Maintenance utils:
  - `tests/replay/fixtures/maintenance/maintenance_utils_fixtures.lua`
  - `tests/replay/harness/maintenance_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_maintenance_utils_fixtures.lua`

- Defensive utils:
  - `tests/replay/fixtures/defensive/defensive_utils_fixtures.lua`
  - `tests/replay/harness/defensive_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_defensive_utils_fixtures.lua`

- Action predicates:
  - `tests/replay/fixtures/action_predicates/action_predicates_fixtures.lua`
  - `tests/replay/harness/action_predicates_fixture_runner.lua`
  - `tests/replay/harness/selftest_action_predicates_fixtures.lua`

- Geometry:
  - `tests/replay/fixtures/geometry/geometry_fixtures.lua`
  - `tests/replay/harness/geometry_fixture_runner.lua`
  - `tests/replay/harness/selftest_geometry_fixtures.lua`

- Context utils:
  - `tests/replay/fixtures/context/context_utils_fixtures.lua`
  - `tests/replay/harness/context_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_context_utils_fixtures.lua`

- Target utils:
  - `tests/replay/fixtures/target/target_utils_fixtures.lua`
  - `tests/replay/harness/target_utils_fixture_runner.lua`
  - `tests/replay/harness/selftest_target_utils_fixtures.lua`

- Rank output:
  - `tests/replay/fixtures/rank_output/rank_output_fixtures.lua`
  - `tests/replay/harness/rank_output_fixture_runner.lua`
  - `tests/replay/harness/selftest_rank_output_fixtures.lua`

- Pending record:
  - `tests/replay/fixtures/pending_record/pending_record_fixtures.lua`
  - `tests/replay/harness/pending_record_fixture_runner.lua`
  - `tests/replay/harness/selftest_pending_record_fixtures.lua`

- Reject history:
  - `tests/replay/fixtures/reject_history/reject_history_fixtures.lua`
  - `tests/replay/harness/reject_history_fixture_runner.lua`
  - `tests/replay/harness/selftest_reject_history_fixtures.lua`

- Action state:
  - `tests/replay/fixtures/action_state/action_state_fixtures.lua`
  - `tests/replay/harness/action_state_fixture_runner.lua`
  - `tests/replay/harness/selftest_action_state_fixtures.lua`

- Locks:
  - `tests/replay/fixtures/locks/locks_fixtures.lua`
  - `tests/replay/harness/locks_fixture_runner.lua`
  - `tests/replay/harness/selftest_locks_fixtures.lua`

- Dispatch plan:
  - `tests/replay/fixtures/dispatch_plan/dispatch_plan_fixtures.lua`
  - `tests/replay/harness/dispatch_plan_fixture_runner.lua`
  - `tests/replay/harness/selftest_dispatch_plan_fixtures.lua`

- Pending:
  - `tests/replay/fixtures/pending/pending_fixtures.lua`
  - `tests/replay/harness/pending_fixture_runner.lua`
  - `tests/replay/harness/selftest_pending_fixtures.lua`

- Dryrun publish:
  - `tests/replay/fixtures/dryrun_publish/dryrun_publish_fixtures.lua`
  - `tests/replay/harness/dryrun_publish_fixture_runner.lua`
  - `tests/replay/harness/selftest_dryrun_publish_fixtures.lua`

- Dispatcher:
  - `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`
  - `tests/replay/harness/dispatcher_fixture_runner.lua`
  - `tests/replay/harness/selftest_dispatcher_fixtures.lua`

## 4) Scope Remaining (Mapped to RFC)

### 4.1 High-priority remaining implementation scope

1. Runtime ownership migration foundation (RFC T2.x):
   - Dispatcher contract enforcement for side effects.
   - Dark-launch dispatch path routed through dispatcher.
   - Movement-side effect routing ownership tightening.

2. Provider extraction and scheduler slimming (RFC T3.x):
   - Defensive/combat/tank/maintenance/target-control provider extraction.
   - Preserve behavior while removing scheduler overload.

3. Movement ownership decision + migration (RFC T4.x):
   - Clarify follow/pathing/coordinator ownership boundaries.
   - Migrate one path at a time with parity checks.

4. Cutover readiness and fallback retirement (RFC T5.x):
   - Domain-specific cutover checklists.
   - Remove fallback only after parity validation.

### 4.2 Remaining non-runtime harness opportunities

Potential next extracted module fixture suites:

## 5) How To Keep This Updated

For each new task completion, append:
- Date
- Task slice name
- Status change (`NOT STARTED` -> `DONE`)
- Files created/modified
- Validation run summary (selftest + `luac -p`)

## 6) Update Log

- 2026-05-25: Initial tracker created from current completed harness/fixture implementation state.
- 2026-05-25: Completed `uc_scheduler_target_utils.lua` fixture suite slice. Status change: target utils coverage marked `DONE`. Files created: `tests/replay/fixtures/target/target_utils_fixtures.lua`, `tests/replay/harness/target_utils_fixture_runner.lua`, `tests/replay/harness/selftest_target_utils_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_target_utils_fixtures.lua`, `luac -p tests/replay/fixtures/target/target_utils_fixtures.lua`, `luac -p tests/replay/harness/target_utils_fixture_runner.lua`, regression smoke `lua tests/replay/harness/selftest_context_utils_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_rank_output.lua` fixture suite slice. Status change: rank output coverage marked `DONE`. Files created: `tests/replay/fixtures/rank_output/rank_output_fixtures.lua`, `tests/replay/harness/rank_output_fixture_runner.lua`, `tests/replay/harness/selftest_rank_output_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_rank_output_fixtures.lua`, `luac -p tests/replay/fixtures/rank_output/rank_output_fixtures.lua`, `luac -p tests/replay/harness/rank_output_fixture_runner.lua`, regression smoke `lua tests/replay/harness/selftest_target_utils_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_pending_record.lua` fixture suite slice. Status change: pending record coverage marked `DONE`. Files created: `tests/replay/fixtures/pending_record/pending_record_fixtures.lua`, `tests/replay/harness/pending_record_fixture_runner.lua`, `tests/replay/harness/selftest_pending_record_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_pending_record_fixtures.lua`, `luac -p tests/replay/fixtures/pending_record/pending_record_fixtures.lua`, `luac -p tests/replay/harness/pending_record_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_pending_record_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_reject_history.lua` fixture suite slice. Status change: reject history coverage marked `DONE`. Files created: `tests/replay/fixtures/reject_history/reject_history_fixtures.lua`, `tests/replay/harness/reject_history_fixture_runner.lua`, `tests/replay/harness/selftest_reject_history_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_reject_history_fixtures.lua`, `luac -p tests/replay/fixtures/reject_history/reject_history_fixtures.lua`, `luac -p tests/replay/harness/reject_history_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_reject_history_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_action_state.lua` fixture suite slice. Status change: action state coverage marked `DONE`. Files created: `tests/replay/fixtures/action_state/action_state_fixtures.lua`, `tests/replay/harness/action_state_fixture_runner.lua`, `tests/replay/harness/selftest_action_state_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_action_state_fixtures.lua`, `luac -p tests/replay/fixtures/action_state/action_state_fixtures.lua`, `luac -p tests/replay/harness/action_state_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_action_state_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_locks.lua` fixture suite slice. Status change: locks coverage marked `DONE`. Files created: `tests/replay/fixtures/locks/locks_fixtures.lua`, `tests/replay/harness/locks_fixture_runner.lua`, `tests/replay/harness/selftest_locks_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_locks_fixtures.lua`, `luac -p tests/replay/fixtures/locks/locks_fixtures.lua`, `luac -p tests/replay/harness/locks_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_locks_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_dispatch_plan.lua` fixture suite slice. Status change: dispatch plan coverage marked `DONE`. Files created: `tests/replay/fixtures/dispatch_plan/dispatch_plan_fixtures.lua`, `tests/replay/harness/dispatch_plan_fixture_runner.lua`, `tests/replay/harness/selftest_dispatch_plan_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_dispatch_plan_fixtures.lua`, `luac -p tests/replay/fixtures/dispatch_plan/dispatch_plan_fixtures.lua`, `luac -p tests/replay/harness/dispatch_plan_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_dispatch_plan_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_pending.lua` fixture suite slice. Status change: pending coverage marked `DONE`. Files created: `tests/replay/fixtures/pending/pending_fixtures.lua`, `tests/replay/harness/pending_fixture_runner.lua`, `tests/replay/harness/selftest_pending_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_pending_fixtures.lua`, `luac -p tests/replay/fixtures/pending/pending_fixtures.lua`, `luac -p tests/replay/harness/pending_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_pending_fixtures.lua`.
- 2026-05-25: Completed `uc_scheduler_dryrun_publish.lua` fixture suite slice. Status change: dryrun publish coverage marked `DONE`. Files created: `tests/replay/fixtures/dryrun_publish/dryrun_publish_fixtures.lua`, `tests/replay/harness/dryrun_publish_fixture_runner.lua`, `tests/replay/harness/selftest_dryrun_publish_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_dryrun_publish_fixtures.lua`, `luac -p tests/replay/fixtures/dryrun_publish/dryrun_publish_fixtures.lua`, `luac -p tests/replay/harness/dryrun_publish_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_dryrun_publish_fixtures.lua`.
- 2026-05-25: Completed aggregate replay self-test runner slice. Status change: aggregate replay self-test runner marked `DONE`. Files created: `tests/replay/harness/selftest_all_replay_fixtures.lua`. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-25: Completed runtime parse self-test slice. Status change: runtime parse self-test marked `DONE`, and aggregate replay self-test runner now includes runtime parse validation. Files created: `tests/replay/harness/selftest_runtime_parse.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_runtime_parse.lua`, `luac -p tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-25: Completed side-effect callsite inventory self-test slice. Status change: side-effect callsite inventory self-test marked `DONE`, and aggregate replay self-test runner now includes side-effect inventory validation. Files created: `tests/replay/harness/selftest_side_effect_inventory.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `luac -p tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-25: Completed T2.0 dispatcher contract skeleton (dark-launch) slice. Status change: dispatcher contract skeleton marked `IN PROGRESS` under runtime ownership migration foundation; dispatcher is not wired into scheduler side-effect execution yet. Files created: `uc_scheduler_dispatcher.lua`, `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `tests/replay/harness/dispatcher_fixture_runner.lua`, `tests/replay/harness/selftest_dispatcher_fixtures.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `tests/replay/harness/selftest_runtime_parse.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `luac -p tests/replay/harness/dispatcher_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-25: Completed T2.1 dark-launch command intent construction slice. Status change: T2.1 dark-launch command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler runtime execution is unchanged (`windower.send_command` remains the live path), with object-form validation status now published. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-25: Completed T2.2 dark-launch target-select intent construction slice. Status change: T2.2 dark-launch target-select intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler target-selection runtime execution is unchanged (`uc_settarget.select_by_id` remains the live path), with object-form validation status now published. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-26: Completed T2.3 dark-launch run intent construction slice. Status change: T2.3 dark-launch run intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler movement runtime execution is unchanged (`windower.ffxi.run` remains the live path), with object-form validation status now published. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-26: Completed T2.3b run-vector dispatcher contract pin slice. Status change: T2.3b run-vector dispatcher contract pin marked `IN PROGRESS`; dispatcher canonical run contract is `kind='run'` plus `run_x`/`run_y` vectors (numeric or numeric-string), with missing/nonnumeric vector rejection and injected deps.run execution semantics pinned by fixtures. Files modified: `uc_scheduler_dispatcher.lua`, `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `tests/replay/harness/selftest_dispatcher_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p uc_scheduler_dispatcher.lua`, `luac -p tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `luac -p tests/replay/harness/dispatcher_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-26: Completed T2.3c dark-launch turn intent construction slice. Status change: T2.3c dark-launch turn intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler turn runtime execution is unchanged (`windower.ffxi.turn` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-26: Completed T2.3d dark-launch combat command intent construction slice. Status change: T2.3d dark-launch combat command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler combat/non-defensive command runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_COMBAT_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-26: Completed T2.3e dark-launch JA command intent construction slice. Status change: T2.3e dark-launch JA command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler JA target-send runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-26: Completed T2.3f dark-launch JA self-command intent construction slice. Status change: T2.3f dark-launch JA self-command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler JA self-send runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-30: Completed T2.3g dark-launch spell target-command intent construction slice. Status change: T2.3g dark-launch spell target-command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler spell target-send runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_SPELL_TARGET_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-30: Completed T2.3h dark-launch spell self-command intent construction slice. Status change: T2.3h dark-launch spell self-command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler spell self-send runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-30: Completed T2.3i dark-launch defensive_internal command intent construction slice. Status change: T2.3i dark-launch defensive_internal command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler defensive_internal runtime execution is unchanged (`windower.send_command(cmd)` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-06-10: Completed T2.3j dark-launch maintenance_cor command intent construction slice. Status change: T2.3j dark-launch maintenance_cor command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler maintenance COR runtime execution is unchanged (`windower.send_command(maintenance_cor_command)` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_MAINTENANCE_COR_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-06-10: Completed T2.3k dark-launch Doom Holy Water command intent construction slice. Status change: T2.3k dark-launch Doom Holy Water command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler Doom emergency runtime execution is unchanged (`windower.send_command(doom_holy_water_command)` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-06-10: Completed T2.3l T2.1 status-shape normalization slice. Status change: T2.3l T2.1 status-shape normalization marked `IN PROGRESS`; older T2.1 scheduler command validation now publishes `_G.UC_SCHED_P1_DARKLAUNCH_DISPATCH_VALIDATE` as `{ ok, reason, kind, source, command_present }`, while runtime execution is unchanged (`windower.send_command(cmd)` remains the live path) and no behavior branches on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-06-10: Completed T2.3m T2.2 target status-shape normalization slice. Status change: T2.3m T2.2 target status-shape normalization marked `IN PROGRESS`; older T2.2 target-select validation now publishes `_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE` as `{ ok, reason, kind, source, target_id }`, while runtime execution is unchanged (`uc_settarget.select_by_id(tid)` remains the live path) and no behavior branches on validation result. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-06-10: Completed T2.3n T2.3 run status-shape normalization slice. Status change: T2.3n T2.3 run status-shape normalization marked `IN PROGRESS`; older T2.3 run validation now publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` as `{ ok, reason, kind, source, run_x, run_y }`, while runtime execution is unchanged (`windower.ffxi.run(heading)` remains the live path) and no behavior branches on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-06-10: Completed T2.3o tracker wording cleanup. Updated T2.1/T2.2/T2.3 tracker wording to reflect object-form validation status while preserving validation-only/dark-launch and unchanged live execution descriptions. Files modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.3p normalization tracker finalization. Status change: T2.3l, T2.3m, T2.3n, and T2.3o tracker rows marked `DONE`; implementation descriptions remain unchanged except for the added T2.3o board row. Files modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.3q main row status review. Decision: T2.1, T2.2, and T2.3 main dark-launch construction rows remain `IN PROGRESS` because nearby dark-launch construction rows are tracked as validation-only/runtime-migration work until dispatcher ownership is complete; no implementation descriptions changed. Files modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4b movement-stop dispatcher contract pin slice. Status change: T2.4b movement-stop dispatcher contract pin marked `IN PROGRESS`; dispatcher now accepts `kind='run_stop'` without `run_x`/`run_y`, preserves dry-run no-op behavior, and dispatches execute mode through injected `deps.run(false)` only. Files modified: `uc_scheduler_dispatcher.lua`, `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `tests/replay/harness/selftest_dispatcher_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p unified_scheduler.lua`.
- 2026-06-10: Completed T2.4c dark-launch run_stop intent construction slice. Status change: T2.4c dark-launch run_stop intent construction marked `IN PROGRESS`; selected the movement coordinator cast-freeze prep stop (`MOVE_COORD_CAST_FREEZE_PREP`) because it sets `UC_MOVEMENT_MODE='CAST_FREEZE'` and `UC_MOVEMENT_BLOCK_REASON='MOVE_COORD_CAST_FREEZE_PREP'` immediately before the existing `windower.ffxi.run(false)`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4d dark-launch pull-cast-hold run_stop intent construction slice. Status change: T2.4d dark-launch pull-cast-hold run_stop intent construction marked `IN PROGRESS`; selected the adjacent movement coordinator pull-cast hold stop (`MOVE_COORD_PULL_CAST_HOLD`) because it sets `UC_MOVEMENT_MODE='CAST_FREEZE'` and `UC_MOVEMENT_BLOCK_REASON='MOVE_COORD_PULL_CAST_HOLD'` immediately before the existing `windower.ffxi.run(false)`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4e dark-launch pull-spell-wait run_stop intent construction slice. Status change: T2.4e dark-launch pull-spell-wait run_stop intent construction marked `IN PROGRESS`; selected the adjacent movement coordinator pull-spell wait stop (`MOVE_COORD_PULL_SPELL_WAIT`) because it sets `UC_MOVEMENT_MODE='CAST_FREEZE'` and `UC_MOVEMENT_BLOCK_REASON='MOVE_COORD_PULL_SPELL_WAIT'` immediately before the existing `windower.ffxi.run(false)`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4f dark-launch tank-action-settle run_stop intent construction slice. Status change: T2.4f dark-launch tank-action-settle run_stop intent construction marked `IN PROGRESS`; selected the tank enmity action settle stop because the surrounding regression guard explicitly stops before tank JA/spell dispatch to avoid carrying a previous run vector, using `tank_action_settle_key` and `tank_action_settle_until` before the existing `windower.ffxi.run(false)`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4g dark-launch tank-spell-settle run_stop intent construction slice. Status change: T2.4g dark-launch tank-spell-settle run_stop intent construction marked `IN PROGRESS`; selected the tank enmity spell settle stop because the surrounding settle guard uses `tank_spell_settle_key` and `tank_spell_settle_until` before the existing `windower.ffxi.run(false)` and wait block, preventing spell dispatch while a previous run vector settles. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4h dark-launch tank-enmity spell send run_stop intent construction slice. Status change: T2.4h dark-launch tank-enmity spell send run_stop intent construction marked `IN PROGRESS`; selected the tank-enmity spell target-send-adjacent stop because it runs only in the `target_kind == 'mob'` tank-enmity branch immediately before constructing and sending `spell_target_command` by target id. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4i dark-launch tank-enmity spell self-send run_stop intent construction slice. Status change: T2.4i dark-launch tank-enmity spell self-send run_stop intent construction marked `IN PROGRESS`; selected the tank-enmity spell self-send-adjacent stop because it runs only in the spell self branch when `tank_enmity` is true, immediately before constructing and sending `spell_self_command`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4j dark-launch Doom emergency run_stop intent construction slice. Status change: T2.4j dark-launch Doom emergency run_stop intent construction marked `IN PROGRESS`; selected the Doom emergency stop because it runs only after confirming the player has Doom and immediately before the Holy Water emergency item path. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4k dark-launch tank-enmity JA self-send run_stop intent construction slice. Status change: T2.4k dark-launch tank-enmity JA self-send run_stop intent construction marked `IN PROGRESS`; selected the tank-enmity JA self-send-adjacent stop because it runs only in the JA self branch when `tank_enmity` is true, immediately before constructing and sending `ja_self_command`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4l dark-launch combat spell-settle run_stop intent construction slice. Status change: T2.4l dark-launch combat spell-settle run_stop intent construction marked `IN PROGRESS`; selected the generic combat spell-settle stop because it creates a new `UC_MOVE_FREEZE_PREP_KEY`/`UC_MOVE_FREEZE_PREP_UNTIL` and immediately calls `windower.ffxi.run(false)` before returning `BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_SPELL_SETTLE`. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4m dark-launch combat spell prep-wait run_stop intent construction slice. Status change: T2.4m dark-launch combat spell prep-wait run_stop intent construction marked `IN PROGRESS`; selected the generic combat spell prep-wait stop because it runs only while `prep_now < prep_until`, immediately calls `windower.ffxi.run(false)`, and returns `BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_SPELL_PREP` without sending the spell yet. Dispatcher validation is `kind='run_stop'` only, publishes `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE`, and does not branch or route execution through dispatcher. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4o full scheduler side-effect dark-launch coverage audit. Status change: T2.4o full scheduler side-effect dark-launch coverage audit marked `DONE`; audit confirmed all current `unified_scheduler.lua` scheduler-owned side-effect callsites tracked for `windower.send_command`, `windower.ffxi.run`, `windower.ffxi.turn`, and `uc_settarget.select_by_id` have nearby validation-only dispatcher intent coverage and object-form status. No runtime code changed. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.4p dispatcher fixture coverage audit. Status change: T2.4p dispatcher fixture coverage audit marked `DONE`; audit covered scheduler dark-launch intent kinds `send_command`, `select_target`, `run`, `run_stop`, and `turn`. Added the smallest missing dispatcher fixtures for valid validation, invalid/missing required fields, dry-run no-call behavior, execute injected dependency calls, and missing dependency failures; fixture audit also proved `select_target` was scheduler-used but unsupported by the dispatcher, so dispatcher support was pinned without changing scheduler routing. Files modified: `uc_scheduler_dispatcher.lua`, `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `tests/replay/harness/selftest_dispatcher_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p unified_scheduler.lua`.
- 2026-06-10: Completed T2.5a first dispatcher runtime-ownership candidate audit. Status change: T2.5a first dispatcher runtime-ownership candidate audit marked `DONE`; reviewed scheduler dark-launch side-effect groups `send_command`, `select_target`, `run`, `run_stop`, and `turn`, and recommended the isolated face-to-target `windower.ffxi.turn(heading)` path as the first dispatcher runtime-ownership migration candidate because it has adjacent stable intent, dispatcher execute fixture coverage, no live return value to preserve, low gameplay risk, and an easy direct-call rollback. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-10: Completed T2.5b default-off turn dispatcher ownership flag slice. Status change: T2.5b default-off turn dispatcher ownership flag marked `IN PROGRESS`; selected the existing face-to-target `windower.ffxi.turn(heading)` callsite covered by `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE`, added default-off ownership flag `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP == true`, routes through `dispatch_intent(..., { execute = true, turn = windower.ffxi.turn })` only when enabled, and falls back to the existing direct turn call if dispatcher execution fails. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-11: Completed T2.5c turn ownership static selftest slice. Status change: T2.5c turn ownership static selftest marked `DONE`; added `tests/replay/harness/selftest_turn_ownership_static.lua` and included it in the aggregate replay runner to pin the T2.5b default-off ownership flag, dispatcher execute call, injected `turn` dependency, direct fallback callsite, and ownership/fallback status fields without executing Windower APIs. Files created: `tests/replay/harness/selftest_turn_ownership_static.lua`. Files modified: `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-11: Completed T2.5d turn ownership runtime-style test feasibility audit. Status change: T2.5d turn ownership runtime-style test feasibility audit marked `DONE`; inspected the selected face-to-target turn branch and existing replay harnesses, and found no safe existing Windower-free runtime-style seam because `p1_apply_face_to_target` is local-only, the returned scheduler table does not expose it, and full module load requires broad Windower/file/module stubbing before the branch can be reached. No runtime-style selftest was added. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-11: Completed T2.5e turn ownership helper seam slice. Status change: T2.5e turn ownership helper seam marked `IN PROGRESS`; added `uc_scheduler_turn_ownership.lua` as a Windower-free injected-dependency helper for the selected face-to-target turn ownership branch, updated `unified_scheduler.lua` to call the helper with injected `windower.ffxi.turn` function references, added `tests/replay/harness/selftest_turn_ownership_runtime.lua` for default-off direct behavior, flag-on dispatcher success, and flag-on fallback behavior, and updated static coverage for the helper-backed shape. Files created: `uc_scheduler_turn_ownership.lua`, `tests/replay/harness/selftest_turn_ownership_runtime.lua`. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `tests/replay/harness/selftest_turn_ownership_static.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-11: Completed T2.5f second dispatcher runtime-ownership candidate audit. Status change: T2.5f second dispatcher runtime-ownership candidate audit marked `DONE`; reviewed `select_target`, isolated `send_command`, `run_stop`, and `run` vector candidates after the turn helper seam, and recommends `select_target` as the next candidate because it is a single isolated callsite with existing validation and dispatcher execute coverage, and its boolean return can be preserved by a helper that captures the injected `set_target` dependency return through dispatcher execution. File modified: `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-11: Completed T2.5g target ownership helper seam slice. Status change: T2.5g target ownership helper seam marked `IN PROGRESS`; added `uc_scheduler_target_ownership.lua` as a Windower-free injected-dependency helper for the scheduler target-select branch, extended `uc_scheduler_dispatcher.lua` execute results for `select_target`/`set_target` to return the injected dependency result as `dep_result`, updated `unified_scheduler.lua` so only `p1_try_target_prep` routes through the helper behind `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP == true`, preserved default-off direct selection semantics and dispatcher-failure fallback, added focused runtime/static selftests, added the new suites to the aggregate runner, and updated side-effect line pins after confirming the callsite counts and set remained unchanged. Files created: `uc_scheduler_target_ownership.lua`, `tests/replay/harness/selftest_target_ownership_runtime.lua`, `tests/replay/harness/selftest_target_ownership_static.lua`. Files modified: `uc_scheduler_dispatcher.lua`, `unified_scheduler.lua`, `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `tests/replay/harness/dispatcher_fixture_runner.lua`, `tests/replay/harness/selftest_dispatcher_fixtures.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `lua tests/replay/harness/selftest_target_ownership_runtime.lua`, `lua tests/replay/harness/selftest_target_ownership_static.lua`, `lua tests/replay/harness/selftest_turn_ownership_runtime.lua`, `lua tests/replay/harness/selftest_turn_ownership_static.lua`, `luac -p unified_scheduler.lua`, `luac -p uc_scheduler_dispatcher.lua`, `luac -p uc_scheduler_target_ownership.lua`, `luac -p uc_scheduler_turn_ownership.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-06-18: Completed T3.3a Bard song identity tracking slice. Status change: T3.3a marked `DONE`; narrowed the fix to Bard defensive buff maintenance by preserving exact same-family song identity after confirmed local defensive spell success, without changing scheduler ownership routing, movement arbitration, or non-song maintenance behavior. `uc_hb_buff_maint.lua` now stores bounded per-target/per-family exact song confirmations and clips them to the current live family-effect count so generic `March` packets can still satisfy exact songs like `Honor March` versus `Victory March`. `unified_scheduler.lua` now records confirmed Bard song identity only from the local defensive spell success path, using the already-tracked pending spell name and target id/name. Files created: `docs/bard_song_identity_tracking_audit.md`, `tests/replay/harness/selftest_bard_song_identity_tracking.lua`. Files modified: `uc_hb_buff_maint.lua`, `unified_scheduler.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p uc_hb_buff_maint.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p UnifiedCombat.lua`, `lua tests/replay/harness/selftest_bard_song_identity_tracking.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. Field test: configure same-family Bard songs such as `Honor March|Victory March`, confirm a successful `Honor March` followed by only a generic `March` effect no longer triggers immediate `Honor March` recast, and verify interrupted `Honor March` remains eligible.
- 2026-06-18: Completed T3.4j pending engage confirmation guard slice. Status change: T3.4j marked `DONE`; added scheduler-owned pending engage confirmation between `attack_on` send and actual `status=1`, detects the game-side wait-longer rejection by raw action message id `94`, retries on a bounded `0.40s` delay inside a bounded `1.75s` timeout window, blocks non-critical ranked and legacy defensive actions while pending engage is live, preserves critical Cure override, and keeps target acquisition nonblocking. `uc_scheduler_action_state.lua` now reports explicit bounded post-spell tail duration so field logs no longer inflate the intended `0.2s` tail. Files created: `docs/pending_engage_confirmation_audit.md`, `tests/replay/harness/selftest_pending_engage_confirmation.lua`, `tests/replay/harness/selftest_engage_rejection_retry.lua`. Files modified: `unified_scheduler.lua`, `uc_scheduler_action_state.lua`, `tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `tests/replay/harness/selftest_scheduler_engage_action_state_release.lua`, `tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_pending_engage_confirmation.lua`, `lua tests/replay/harness/selftest_engage_rejection_retry.lua`, `lua tests/replay/harness/selftest_engage_dispatch_priority.lua`, `lua tests/replay/harness/selftest_target_acquire_nonblocking.lua`, `lua tests/replay/harness/selftest_tank_engage_priority.lua`, `lua tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, `lua tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. Field test: enable `_G.UC_DEBUG_ACTION_TIMELINE = true`, force an engage immediately after a spell or Cure tail, confirm `PENDING_ENGAGE_*` events appear between `ENGAGE_DISPATCHED` and `STATUS_CHANGED ... to=1`, confirm wait-longer rejection logs id `94` plus bounded retry events, and confirm non-critical Cure / maintenance / Sleep no longer dispatch during the pending-engage window.
- 2026-06-19: Completed T3.4k stale spell action-state release and retry-aware pending timeout slice. Status change: T3.4k marked `DONE`; added a narrow target-aware stale combat-spell lock release so old mob-target combat spell cooldown/tail does not block next-target engage after target death/status-zero transition, while leaving actual in-progress casts, defensive Cure/self-buff spells, JA, and WS state untouched. Pending-engage timeout is now refreshed from the latest engage attempt/retry rather than remaining anchored to the first send, and timeout logs now include `age_s` from the latest attempt plus `retry_count`. Files created: `tests/replay/harness/selftest_stale_spell_lockout_target_transition.lua`. Files modified: `unified_scheduler.lua`, `uc_scheduler_action_state.lua`, `tests/replay/harness/selftest_pending_engage_confirmation.lua`, `tests/replay/harness/selftest_engage_rejection_retry.lua`, `tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/pending_engage_confirmation_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_stale_spell_lockout_target_transition.lua`, `lua tests/replay/harness/selftest_pending_engage_confirmation.lua`, `lua tests/replay/harness/selftest_engage_rejection_retry.lua`, `lua tests/replay/harness/selftest_engage_dispatch_priority.lua`, `lua tests/replay/harness/selftest_scheduler_spell_success_action_state.lua`, `lua tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. Field test: enable `_G.UC_DEBUG_ACTION_TIMELINE = true`, send a mob-target combat spell immediately before the old target dies, confirm the next target transition logs `STALE_SPELL_LOCK_RELEASE` and engage proceeds without waiting on the old spell tail, then force one or more wait-longer engage retries and confirm timeout age is measured from the latest retry attempt rather than the first engage send.
- 2026-06-19: Completed T3.4l engage duplicate suppression audit and hotfix. Status change: T3.4l marked `DONE`; audited the live engage seam and confirmed scheduler engage still dispatches through explicit `uc_attack.engage_target(...)` / `attack_on`, not console `/attack`, command ownership, or dispatcher routing. Replaced the stale generic engage duplicate lockout during `status ~= 1` with a scheduler-local explicit attack-on retry debounce (`0.30s`), kept the existing pending-engage wait-longer retry gate (`0.40s`), and added targeted reset/logging for target-change and wait-longer rejection recovery. Runtime behavior changed narrowly in `unified_scheduler.lua`; non-critical pending-engage blocking, critical Cure override, target acquisition behavior, and ownership policy remain unchanged. Files created: `docs/engage_duplicate_suppression_audit.md`, `tests/replay/harness/selftest_engage_duplicate_suppression.lua`. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_pending_engage_confirmation.lua`, `tests/replay/harness/selftest_engage_rejection_retry.lua`, `tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/pending_engage_confirmation_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_engage_duplicate_suppression.lua`, `lua tests/replay/harness/selftest_pending_engage_confirmation.lua`, `lua tests/replay/harness/selftest_engage_rejection_retry.lua`, `lua tests/replay/harness/selftest_engage_dispatch_priority.lua`, `lua tests/replay/harness/selftest_target_acquire_nonblocking.lua`, `lua tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. Field test: enable `_G.UC_DEBUG_ACTION_TIMELINE = true`, force engage retries while still not engaged, confirm `ENGAGE_DUPLICATE_SUPPRESSED` no longer creates multi-second delay, confirm `ENGAGE_DUPLICATE_RESET_REJECTION` appears after wait-longer rejection, and confirm target-change plus pending-engage non-critical blocking behavior remains intact.
- 2026-06-19: Completed T3.4m explicit attack-on action-state bypass slice. Status change: T3.4m marked `DONE`; confirmed the remaining tank engage delay was the generic pre-send action-state gate, not duplicate suppression. `unified_scheduler.lua` now validates engage target selection/actionability before the engage-specific action-state check, attempts stale mob-target combat spell release immediately on proven target transition, and routes explicit `attack_on` engage through a narrow action-state gate. `uc_scheduler_action_state.lua` now allows explicit attack-on to bypass stale WS/JA/spell-cooldown action-state while still holding active in-progress spell casts and engage retry debounce, and stale combat-spell release can now clear immediately on proven target transition even in the previously acting case. Files created: `docs/engage_action_state_bypass_audit.md`, `tests/replay/harness/selftest_engage_action_state_bypass.lua`. Files modified: `unified_scheduler.lua`, `uc_scheduler_action_state.lua`, `tests/replay/harness/selftest_stale_spell_lockout_target_transition.lua`, `tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, `docs/engage_duplicate_suppression_audit.md`, `docs/pending_engage_confirmation_audit.md`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p UnifiedCombat.lua`, `luac -p unified_scheduler.lua`, `luac -p unified_combat_core.lua`, `luac -p uc_scheduler_action_state.lua`, `lua tests/replay/harness/selftest_engage_action_state_bypass.lua`, `lua tests/replay/harness/selftest_engage_duplicate_suppression.lua`, `lua tests/replay/harness/selftest_pending_engage_confirmation.lua`, `lua tests/replay/harness/selftest_engage_rejection_retry.lua`, `lua tests/replay/harness/selftest_engage_dispatch_priority.lua`, `lua tests/replay/harness/selftest_stale_spell_lockout_target_transition.lua`, `lua tests/replay/harness/selftest_action_economy_timeline_logging.lua`, `lua tests/replay/harness/selftest_defensive_cure_priority.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`, `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`. Field test: enable `_G.UC_DEBUG_ACTION_TIMELINE = true`, confirm stale WS/JA action-state no longer delays the first `ENGAGE_DISPATCH_ATTEMPT`, confirm active spell casts log `ENGAGE_ACTION_STATE_HELD_ACTIVE_CAST` instead of bypassing, and confirm wait-longer `94` handling plus pending-engage non-critical blocking remain intact.
