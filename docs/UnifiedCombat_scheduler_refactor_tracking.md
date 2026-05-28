# UnifiedCombat Scheduler Refactor Tracking

Source RFC: `RFC/UnifiedCombat_scheduler_refactor_RFC_for_Codex.md`  
Purpose: a living progress tracker for implementation scope, completed work, and remaining scope.

## 1) Overall Status Snapshot

- Current phase focus: non-runtime replay harness and extracted-helper fixture coverage.
- Completed in this phase: core harness foundation plus fixture suites for extracted modules.
- Not started in this phase: dispatcher ownership migration, provider extraction/cutover, movement ownership runtime migration, legacy fallback removal.

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
| T2.1 dark-launch command intent construction | IN PROGRESS | One scheduler `send_command` path now builds and validates dispatcher intent beside existing call; scheduler execution path remains unchanged. |
| T2.2 dark-launch target-select intent construction | IN PROGRESS | One scheduler `select_by_id` path now builds and validates dispatcher intent beside existing call; follows T2.1 validation status-publish pattern and leaves target-select execution unchanged. |
| T2.3 dark-launch run intent construction | IN PROGRESS | One scheduler `run` path now builds and validates dispatcher intent beside existing call; follows T2.1/T2.2 validation status-publish pattern and leaves movement execution unchanged. |
| T2.3c dark-launch turn intent construction | IN PROGRESS | One scheduler `turn` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves turn execution unchanged. |
| T2.3d dark-launch combat command intent construction | IN PROGRESS | One scheduler combat/non-defensive `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3e dark-launch JA command intent construction | IN PROGRESS | One scheduler JA target-send `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3f dark-launch JA self-command intent construction | IN PROGRESS | One scheduler JA self-send `send_command` path now builds and validates dispatcher intent beside existing call; publishes object-form validation status and leaves command execution unchanged. |
| T2.3b run-vector dispatcher contract pin | IN PROGRESS | Dispatcher contract and fixtures now pin canonical `run_x`/`run_y` vector semantics (including coercion/rejection and deps.run dispatch), while dark-launch runtime execution remains unchanged. |
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
- `tests/replay/harness/selftest_all_replay_fixtures.lua`

Runtime foundation files:
- `uc_scheduler_dispatcher.lua`

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
- 2026-05-25: Completed T2.1 dark-launch command intent construction slice. Status change: T2.1 dark-launch command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler runtime execution is unchanged (`windower.send_command` remains the live path). Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-25: Completed T2.2 dark-launch target-select intent construction slice. Status change: T2.2 dark-launch target-select intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler target-selection runtime execution is unchanged (`uc_settarget.select_by_id` remains the live path), following the T2.1 validation status-publish pattern. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-26: Completed T2.3 dark-launch run intent construction slice. Status change: T2.3 dark-launch run intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler movement runtime execution is unchanged (`windower.ffxi.run` remains the live path), following the T2.1/T2.2 validation status-publish pattern. Files modified: `unified_scheduler.lua`, `tests/replay/harness/selftest_side_effect_inventory.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-26: Completed T2.3b run-vector dispatcher contract pin slice. Status change: T2.3b run-vector dispatcher contract pin marked `IN PROGRESS`; dispatcher canonical run contract is `kind='run'` plus `run_x`/`run_y` vectors (numeric or numeric-string), with missing/nonnumeric vector rejection and injected deps.run execution semantics pinned by fixtures. Files modified: `uc_scheduler_dispatcher.lua`, `tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `tests/replay/harness/selftest_dispatcher_fixtures.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p uc_scheduler_dispatcher.lua`, `luac -p tests/replay/fixtures/dispatcher/dispatcher_fixtures.lua`, `luac -p tests/replay/harness/dispatcher_fixture_runner.lua`, `luac -p tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_dispatcher_fixtures.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`.
- 2026-05-26: Completed T2.3c dark-launch turn intent construction slice. Status change: T2.3c dark-launch turn intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler turn runtime execution is unchanged (`windower.ffxi.turn` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-26: Completed T2.3d dark-launch combat command intent construction slice. Status change: T2.3d dark-launch combat command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler combat/non-defensive command runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_COMBAT_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-26: Completed T2.3e dark-launch JA command intent construction slice. Status change: T2.3e dark-launch JA command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler JA target-send runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
- 2026-05-26: Completed T2.3f dark-launch JA self-command intent construction slice. Status change: T2.3f dark-launch JA self-command intent construction marked `IN PROGRESS`; dispatcher remains validation-only and scheduler JA self-send runtime execution is unchanged (`windower.send_command` remains the live path), with status published at `_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE` and no behavior branching on validation result. Files modified: `unified_scheduler.lua`, `docs/UnifiedCombat_scheduler_refactor_tracking.md`. Validation: `luac -p unified_scheduler.lua`, `lua tests/replay/harness/selftest_runtime_parse.lua`, `lua tests/replay/harness/selftest_side_effect_inventory.lua`, `lua tests/replay/harness/selftest_all_replay_fixtures.lua`, `luac -p uc_scheduler_dispatcher.lua`.
