# Aggregate Replay Failure Baseline

## Current Aggregate Status

- Command: `lua tests/replay/harness/selftest_all_replay_fixtures.lua`
- Status: `PASS`
- Aggregate failure list: none.

## Individual Suite Results

- `selftest_engage_dispatch_priority.lua`: passes standalone after refreshing the spell-release helper signature pins.
- `selftest_action_economy_timeline_logging.lua`: passes standalone and now passes in the aggregate replay run after the harness clock/socket stub was isolated.
- `selftest_sleep_target_state_suppression.lua`: passes standalone after refreshing the Sleep suppression source pin.
- `selftest_action_state_fixtures.lua`: passes standalone after refreshing the action-state bookkeeping fixture shape.
- `selftest_locks_fixtures.lua`: passes standalone.
- `selftest_pending_fixtures.lua`: passes standalone.

## Classification Table

| Suite | Classification | Likely related task | Blocks next promotion? | Recommended next action |
| --- | --- | --- | --- | --- |
| `selftest_engage_dispatch_priority` | `stale_expectation` | `T3.5l` spell lifecycle cleanup | No, after refresh | Source-shape pin is now aligned to the current helper signatures. |
| `selftest_action_economy_timeline_logging` | `resolved_harness_issue` | Aggregate runner / fixture isolation | No | The suite now snapshots and restores the scheduler clock/socket stub so aggregate ordering no longer breaks the local spell-release path. |
| `selftest_sleep_target_state_suppression` | `stale_expectation` | Sleep suppression source-shape drift from earlier Sleep work | No, after refresh | Source pin is now aligned to the current call shape. |
| `selftest_action_state_fixtures` | `stale_expectation` | `T3.5l` spell lifecycle metadata expansion | No, after refresh | Fixture shape now includes the intentional lifecycle bookkeeping fields. |
| `selftest_locks_fixtures` | `harness_issue` | Aggregate runner / fixture isolation | No, standalone pass | Recheck shared state cleanup between suites only if the aggregate still flakes here. |
| `selftest_pending_fixtures` | `harness_issue` | Aggregate runner / fixture isolation | No, standalone pass | Recheck shared state cleanup between suites only if the aggregate still flakes here. |

## Implication Check

- `T3.6b` combat spell settle run-stop promotion does not appear implicated; that was a historical false lead.
- `T3.6c` combat spell prep-wait run-stop promotion does not appear implicated; that was a historical false lead.
- The aggregate suite is green, so this doc now serves as a historical failure-baseline note rather than an active blocker list.

## Recommended Next Task

- Keep the scheduler ownership baseline stable.
- Use a separate readiness plan if new ownership work is ever reopened.
