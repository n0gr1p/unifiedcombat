# Aggregate Replay Failure Baseline

## Current Aggregate Status

- Command: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`
- Status: `FAIL`
- Aggregate failure list currently names:
  - `selftest_action_economy_timeline_logging`
  - `selftest_locks_fixtures`
  - `selftest_pending_fixtures`

## Individual Suite Results

- `selftest_engage_dispatch_priority.lua`: passes standalone after refreshing the spell-release helper signature pins.
- `selftest_action_economy_timeline_logging.lua`: passes standalone, but still fails in the aggregate replay run.
- `selftest_sleep_target_state_suppression.lua`: passes standalone after refreshing the Sleep suppression source pin.
- `selftest_action_state_fixtures.lua`: passes standalone after refreshing the action-state bookkeeping fixture shape.
- `selftest_locks_fixtures.lua`: passes standalone.
- `selftest_pending_fixtures.lua`: passes standalone.

## Classification Table

| Suite | Classification | Likely related task | Blocks next promotion? | Recommended next action |
| --- | --- | --- | --- | --- |
| `selftest_engage_dispatch_priority` | `stale_expectation` | `T3.5l` spell lifecycle cleanup | No, after refresh | Source-shape pin is now aligned to the current helper signatures. |
| `selftest_action_economy_timeline_logging` | `harness_issue` | Aggregate runner / fixture isolation | Yes, while aggregate replay stays red | Inspect aggregate-suite state reset and suite-order leakage; standalone pass still points away from runtime regression. |
| `selftest_sleep_target_state_suppression` | `stale_expectation` | Sleep suppression source-shape drift from earlier Sleep work | No, after refresh | Source pin is now aligned to the current call shape. |
| `selftest_action_state_fixtures` | `stale_expectation` | `T3.5l` spell lifecycle metadata expansion | No, after refresh | Fixture shape now includes the intentional lifecycle bookkeeping fields. |
| `selftest_locks_fixtures` | `harness_issue` | Aggregate runner / fixture isolation | No, standalone pass | Recheck shared state cleanup between suites only if the aggregate still flakes here. |
| `selftest_pending_fixtures` | `harness_issue` | Aggregate runner / fixture isolation | No, standalone pass | Recheck shared state cleanup between suites only if the aggregate still flakes here. |

## Implication Check

- `T3.6b` combat spell settle run-stop promotion does not appear implicated.
- `T3.6c` combat spell prep-wait run-stop promotion does not appear implicated.
- The remaining aggregate failure looks like harness isolation/order leakage around `selftest_action_economy_timeline_logging`, not the promoted combat-spell run-stop ownership paths.

## Recommended Next Task

- Triage the aggregate-suite isolation/order leakage next.
- Do not promote tank-family ownership until the aggregate replay gate is green again or the remaining failure is explicitly waived.
