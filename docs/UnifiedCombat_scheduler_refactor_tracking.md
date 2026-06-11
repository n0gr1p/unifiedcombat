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

Recommended first migration slice: T2.5b should route only the scheduler face-to-target `turn` callsite through dispatcher ownership behind a default-off guard/flag, preserving validation status and leaving direct `windower.ffxi.turn(heading)` as the rollback path.

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
