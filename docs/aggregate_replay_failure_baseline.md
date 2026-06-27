# Aggregate Replay Failure Baseline

## Current Aggregate Status

- Command: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`
- Status: `FAIL`
- Aggregate failure list currently names:
  - `selftest_engage_dispatch_priority`
  - `selftest_action_economy_timeline_logging`
  - `selftest_sleep_target_state_suppression`
  - `selftest_action_state_fixtures`
  - `selftest_locks_fixtures`
  - `selftest_pending_fixtures`

## Individual Suite Results

- `selftest_engage_dispatch_priority.lua`: fails standalone with `scheduler must expose generic spell-success release helper`.
- `selftest_action_economy_timeline_logging.lua`: passes standalone.
- `selftest_sleep_target_state_suppression.lua`: fails standalone with the stale `now_s()` source-pin expectation.
- `selftest_action_state_fixtures.lua`: fails standalone because `action_mark_sent` now carries additional lifecycle bookkeeping fields beyond the fixture’s older shape.
- `selftest_locks_fixtures.lua`: passes standalone.
- `selftest_pending_fixtures.lua`: passes standalone.

## Classification Table

| Suite | Classification | Likely related task | Blocks next promotion? | Recommended next action |
| --- | --- | --- | --- | --- |
| `selftest_engage_dispatch_priority` | `stale_expectation` | `T3.5l` spell lifecycle cleanup | Yes, while the aggregate gate stays red | Refresh the source-shape assertion to the current helper signature, or waive it only if the removal is intentional. |
| `selftest_action_economy_timeline_logging` | `harness_issue` | Aggregate runner / fixture isolation | Yes, while aggregate replay stays red | Inspect aggregate-suite state reset and suite-order leakage; standalone pass suggests contamination rather than a runtime regression. |
| `selftest_sleep_target_state_suppression` | `stale_expectation` | Sleep suppression source-shape drift from earlier Sleep work | Yes, while the aggregate gate stays red | Update the exact source pin or recorded expectation to the current call shape. |
| `selftest_action_state_fixtures` | `stale_expectation` | `T3.5l` spell lifecycle metadata expansion | Yes, while the aggregate gate stays red | Refresh the fixture shape to include the newer action-state bookkeeping fields. |
| `selftest_locks_fixtures` | `harness_issue` | Aggregate runner / fixture isolation | Yes, while aggregate replay stays red | Recheck shared state cleanup between suites; standalone pass points to aggregate contamination. |
| `selftest_pending_fixtures` | `harness_issue` | Aggregate runner / fixture isolation | Yes, while aggregate replay stays red | Recheck shared state cleanup between suites; standalone pass points to aggregate contamination. |

## Implication Check

- `T3.6b` combat spell settle run-stop promotion does not appear implicated.
- `T3.6c` combat spell prep-wait run-stop promotion does not appear implicated.
- The failures that do show up are mostly fixture-shape drift or aggregate harness contamination, not the promoted combat-spell run-stop ownership paths.

## Recommended Next Task

- Triage the stale fixture expectations first, then inspect aggregate-suite isolation for the three harness-like failures.
- Do not promote tank-family ownership until the aggregate replay gate is green again or the failing suites are explicitly waived.

