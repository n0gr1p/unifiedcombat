# Scheduler-owned WS skillchain field test packet

Date prepared: 2026-07-20
Workstream: `WS-SC-4`
Status: **COMPLETE — FIELD PACKET EXECUTED**

Initial field evidence and corrective findings are recorded in `scheduler_owned_ws_skillchain_field_results_2026-07-20.md`.

The user completed Cases A and B. Case C is accepted as replay-only because its emergency combinations are impractical to manufacture safely in the current setup. Case D is not applicable to the current setup. After reloading the corrected worktree, the focused acceptance run passed for both Nyoourke and Ponponponponpon; no artificial C/D recreation was required.

Post-reload validation command:

```text
lua tests/replay/harness/audit_scheduler_owned_ws_skillchain_field_log.lua data/logs/action_timeline_nyoourke.log 5 non_aeonic
```

## Setup

1. Deploy/reload the same UnifiedCombat worktree on every participating character.
2. Set `_G.UC_DEBUG_ACTION_TIMELINE = true` before the run.
3. Confirm Nyoourke uses the UC/SAM smart-WS profile with scheduler-owned combat, WS enabled, `spam=false`, and `solo=false`.
4. Use a durable target and known compatible WS routes. Keep clocks and logs from all participants.
5. Preserve `data/logs/action_timeline_nyoourke.log` and the corresponding files for the other actors after the run.

## Case A — Nyoourke ready continuation

Preconditions:

- Nyoourke has the intended Aftermath state, sufficient TP, and the highest relevant party TP.
- A compatible learned/equipped WS can continue the active target resonance.
- No emergency action is pending.

Pass criteria:

- `SC_OPENER_INSTALLED` or `SC_RESULT_CONFIRMED` records the target, generation, and action-result timestamp.
- `SC_CONTINUATION_PLANNED` and `SC_CONTINUATION_PROPOSED` identify the same target/generation/WS.
- The normal proposal is not dispatched before `preferred_execute_at` and is dispatched no later than `latest_safe_at`. A proposal explicitly marked high-risk may use its earlier adjusted preferred time, but never precedes `earliest_execute_at`.
- `SC_COMMIT_RESULT commit_stage=rank_commit` records scheduler admission. The final `SC_COMMIT_RESULT commit_stage=dispatch_commit commit_result=SC_DISPATCHED` immediately precedes `SC_WS_DISPATCHED`.
- The incoming result records `SC_RESULT_CONFIRMED`; if prediction differs, `SC_PREDICTION_DISAGREEMENT` preserves the server result.
- No `TIMER_LOCK` or global three-second reset appears because that gate no longer exists.
- While the proposal is `SC_NOT_READY`, routine maintenance/offense does not dispatch through the reserved action lane; critical Cure, Doom, and configured emergency control may still preempt it.

Repeat at least five times, including one AM3 Ultimate-eligible route if practical.

## Case B — Multi-actor race

1. Allow Nyoourke to create a continuation proposal.
2. Have another actor land a property-bearing action on the same target before Nyoourke sends.
3. Confirm the server event increments the target generation.

Pass criteria:

- The stale plan records `SC_COMMIT_RESULT commit_result=SC_RESONANCE_CHANGED` or is replaced before dispatch.
- Nyoourke does not send the stale WS and does not send the configured primary WS as a fallback.
- A later tick may plan only from the new server-confirmed resonance.

Repeat once with a successful chain result and once with a successful non-chain overwrite.

## Case C — Priority and cancellation

- Force a critical Cure while a continuation is ready: critical Cure must win.
- Force an eligible Sleep/emergency-control proposal: configured emergency precedence must win.
- Allow routine Bard/maintenance and aftermath-refresh proposals while a continuation is ready: the continuation must win.
- After proposal creation, test TP loss, target switch, moving outside WS range, and equipment/Aftermath change. Each must cancel with its stable `SC_*` reason and send no fallback WS.

## Case D — Packet and timing observations

- Use one AoE WS on multiple targets and confirm only the selected target receives opener state.
- Capture at least one miss and one propertyless WS during active resonance; generation and original timing must remain unchanged.
- If available, capture Wild Flourish, Konzen-ittai, and qualifying Weapon Bash Chainbound timing. Until an evidenced Weapon Bash lifetime is codified, its event must log `SC_CHAINBOUND_SOURCE_UNSUPPORTED` and must not install a guessed opener window.
- Record action-result-to-dispatch and action-result-to-confirmed-result deltas for each successful stage.
- If a WS is rejected behind geometry, distinguish out-of-range from apparent line-of-sight rejection in the log and game message.

## Results table

| Run | Actor(s) | Target | Route / condition | Generation | Earliest | Dispatch | Latest-safe | Server result | Commit code | Pass |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 1 | Nyoourke |  |  |  |  |  |  |  |  |  |
| 2 | Nyoourke |  |  |  |  |  |  |  |  |  |
| 3 | Nyoourke |  |  |  |  |  |  |  |  |  |
| 4 | Nyoourke |  |  |  |  |  |  |  |  |  |
| 5 | Nyoourke |  |  |  |  |  |  |  |  |  |
| 6 | Multi-actor |  | successful intervening chain |  |  |  |  |  |  |  |
| 7 | Multi-actor |  | non-chain overwrite |  |  |  |  |  |  |  |

## Completion record

Completed on 2026-07-20. The bounded initial evidence, prediction/server disagreements, corrections, and post-reload validator results are recorded in `scheduler_owned_ws_skillchain_field_results_2026-07-20.md`. `WS-SC-4` and the overall implementation plan are `DONE`.
