# UnifiedCombat Scheduler Refactor Tracking — Historical Snapshot

> Historical snapshot retained from 2026-05-25. The canonical current tracker is
> `RFC/UnifiedCombat_scheduler_refactor_tracking.md`.

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
- `uc_scheduler_target_utils.lua`
- `uc_scheduler_action_state.lua`
- `uc_scheduler_locks.lua` (pure/helper portions only; isolate runtime side effects if any)
- `uc_scheduler_rank_output.lua`
- `uc_scheduler_pending_record.lua`
- `uc_scheduler_reject_history.lua`

## 5) How To Keep This Updated

For each new task completion, append:
- Date
- Task slice name
- Status change (`NOT STARTED` -> `DONE`)
- Files created/modified
- Validation run summary (selftest + `luac -p`)

## 6) Update Log

- 2026-05-25: Initial tracker created from current completed harness/fixture implementation state.
