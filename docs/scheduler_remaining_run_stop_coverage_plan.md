# Scheduler Remaining Run-Stop Coverage Plan

## Summary

T3.0b promoted 11 low-risk scheduler ownership paths to default-on.

The remaining default-off set is narrower and higher-risk:

- Doom Holy Water command ownership
- Doom run_stop ownership
- generic combat-spell settle/prep-wait run_stop ownership
- tank action/tank spell/tank enmity run_stop ownership

These paths should not all be treated the same.

- Doom remains emergency-only and should stay conservative unless a safe mock/status-injection harness is added.
- Combat-spell settle/prep-wait looks live-reachable and is a better replay/mock-first candidate than live-promotion-first.
- Tank action/tank spell/tank enmity paths split into one already live-confirmed branch plus several realistic-but-unconfirmed branches that need a narrower field-test packet.
- Vector run remains separate from run_stop planning and should stay parked as dormant/unreachable unless runtime wiring is intentionally revisited.

## Current Ownership Status

- 11 scheduler ownership paths are accepted as default-on after T3.0b field testing.
- Remaining default-off paths still require explicit `== true` enablement.
- Static closure, promotion, parse, side-effect, and aggregate replay validation are already in place.
- Existing helper/runtime coverage proves helper-level dispatcher execution and fallback behavior, but not every remaining branch-specific live scheduler scenario.

## Remaining Default-Off Inventory

| Flag | Family | Scheduler callsite / behavior | Current default-off reason |
| --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP` | command | Doom Holy Water emergency item command send after stop/cooldown checks | Emergency path with no safe practical live scenario |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP` | run_stop | Doom emergency stop before Holy Water item path | Emergency stop path with no safe practical live scenario |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | run_stop | Generic combat spell settle stop when a new freeze-prep key starts | Practical live confirmation missing |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` | run_stop | Generic combat spell prep-wait stop while freeze-prep window remains active | Practical live confirmation missing |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` | run_stop | Tank action settle stop before tank JA/spell dispatch | Live-confirmed once, but family promotion remained partial |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` | run_stop | Tank-enmity JA self send-adjacent stop | Not practically covered |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | run_stop | Tank spell settle stop before tank spell dispatch | Not practically covered |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` | run_stop | Tank-enmity spell target send-adjacent stop | Not practically covered |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | run_stop | Tank-enmity spell self send-adjacent stop | Not practically covered |

## Per-Path Coverage Recommendations

### `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`

- Live-reachable: presumed yes in the real Doom emergency flow.
- Safe to field test: no.
- Replay/mock coverage possible: yes, but only through a dedicated scheduler-branch mock/status-injection harness that can simulate Doom state and item cooldown ordering without real field risk.
- Exact test scenario needed: mocked player Doom status present, cooldown clear, one stop-before-item cycle, then one Holy Water command dispatch with no duplicate send.
- Recommended next action: add replay/mock test.
- Promotion risk: high.
- Rollback / kill-switch recommendation: keep explicit default-off and do not include in any combined live packet.

### `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`

- Live-reachable: presumed yes in the same Doom emergency flow.
- Safe to field test: no.
- Replay/mock coverage possible: yes, through the same scheduler-branch mock/status-injection approach used for Doom command planning.
- Exact test scenario needed: mocked Doom status, stop path reached before Holy Water command path, verify one dispatcher-owned `run_stop` with preserved stop-before-item ordering.
- Recommended next action: add replay/mock test.
- Promotion risk: high.
- Rollback / kill-switch recommendation: keep explicit default-off and do not promote from live inference alone.

### `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`

- Live-reachable: yes, likely reachable whenever a combat spell creates a new `UC_MOVE_FREEZE_PREP_KEY` and starts the settle window.
- Safe to field test: probably yes, but replay/mock coverage should come first.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: spell dispatch branch enters a new prep key, sets `UC_MOVE_FREEZE_PREP_UNTIL`, emits `COMBAT_SPELL_SETTLE`, and blocks once before normal spell send continues.
- Recommended next action: add replay/mock test.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off until replay/mock coverage exists, then consider a focused live packet only if branch behavior still needs confirmation.

### `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

- Live-reachable: yes, likely reachable during the active freeze-prep window after settle initialization.
- Safe to field test: probably yes, but replay/mock coverage should come first.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: existing prep key remains active, current time stays below `UC_MOVE_FREEZE_PREP_UNTIL`, branch emits `COMBAT_SPELL_PREP_WAIT`, and repeated stop behavior preserves the existing prep block timing.
- Recommended next action: add replay/mock test.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off until replay/mock timing coverage exists.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`

- Live-reachable: yes.
- Safe to field test: yes.
- Replay/mock coverage possible: yes, but field evidence already exists.
- Exact test scenario needed: tank-enmity JA or spell branch initializes `tank_action_settle_key`, produces `TANK_ACTION_SETTLE`, and shows one stop before the settle window clears; Stage 6 Provoke already demonstrated this path.
- Recommended next action: create field-test packet.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off until a tank-family packet defines whether this branch may be promoted independently or only with the rest of the tank family.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`

- Live-reachable: likely yes, but only in the tank-enmity JA self branch.
- Safe to field test: yes if a realistic self-target tank JA exists in the user’s setup; otherwise no.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: tank behavior enabled, selected action resolves to JA self under tank-enmity flow, branch emits `TANK_ENMITY_JA_SELF_SEND`, and adjacent stop occurs once before the JA command send.
- Recommended next action: create field-test packet.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off unless the packet shows a realistic repeatable self-JA scenario; if not, fall back to replay/mock-first coverage.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`

- Live-reachable: likely yes.
- Safe to field test: yes if a practical tank spell scenario can be reproduced without risky setup.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: tank-enmity spell branch selects a mob target, initializes `tank_spell_settle_key`, emits `TANK_SPELL_SETTLE`, and blocks once before the settle window clears.
- Recommended next action: create field-test packet.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off until either targeted field evidence or replay/mock branch coverage proves timing parity.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`

- Live-reachable: likely yes in tank-enmity spell target mode.
- Safe to field test: yes if the tank spell target scenario is practical.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: tank-enmity spell targets a mob by id, branch emits `TANK_ENMITY_SPELL_TARGET_SEND`, one adjacent stop occurs, then the spell target command sends normally.
- Recommended next action: create field-test packet.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off until targeted field evidence exists; if no practical scenario exists, downgrade to replay/mock-first.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`

- Live-reachable: likely yes in tank-enmity spell self mode.
- Safe to field test: yes if the configured tank spell can naturally hit the self-target branch.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: tank-enmity spell resolves to self-target behavior, branch emits `TANK_ENMITY_SPELL_SELF_SEND`, one adjacent stop occurs, then the self spell command sends normally.
- Recommended next action: create field-test packet.
- Promotion risk: medium.
- Rollback / kill-switch recommendation: keep explicit default-off until targeted field evidence exists; if no practical scenario exists, downgrade to replay/mock-first.

## Vector Run Ownership (Separate / Not Part of Run-Stop Plan)

### `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP`

- Live-reachable: no, not in current runtime flow.
- Safe to field test: no meaningful live packet exists today.
- Replay/mock coverage possible: existing helper/static coverage already exists, but it does not prove live scheduler reachability.
- Exact test scenario needed: only relevant if a future task reconnects a real caller to `p1_move_toward_mob(...)`.
- Recommended next action: keep parked.
- Promotion risk: high.
- Rollback / kill-switch recommendation: leave default-off and handle retirement/unwiring only in a separate future task.

## Proposed T3.1b Task Options

### Option A — Replay/Mock Coverage for Remaining Emergency and Combat-Spell Branches

Scope:

- Doom Holy Water command ownership
- Doom run_stop ownership
- combat spell settle run_stop ownership
- combat spell prep-wait run_stop ownership

Goal:

- add focused scheduler-branch mock/status-injection coverage for the branches that are either unsafe to live test or timing-sensitive enough to justify replay/mock proof before any new field promotion work.

### Option B — Targeted Tank Run-Stop Field-Test Packet

Scope:

- tank action settle
- tank-enmity JA self send-adjacent stop
- tank spell settle
- tank-enmity spell target send-adjacent stop
- tank-enmity spell self send-adjacent stop

Goal:

- define realistic low-risk live tank scenarios, expected validation globals, exact evidence capture, and fallback instructions for the branches that appear live-reachable but were only partially covered in Stage 6.

### Option C — Final Deferred/Parked Closure Audit

Scope:

- Doom command/run_stop
- any tank branch that proves impractical to trigger
- vector run ownership

Goal:

- convert remaining “pending” language into explicit long-term default-off or parked policy where practical coverage is unlikely to be worth the risk or setup cost.

## Recommended Immediate Next Task

Recommended next task:

`T3.1b — Add replay/mock coverage for the remaining Doom and combat-spell default-off ownership branches, using a focused scheduler-branch mock/status-injection approach and leaving runtime behavior unchanged.`

Rationale:

- Doom is too risky for live promotion-first testing.
- Combat-spell settle/prep-wait looks live-reachable but is primarily a timing/ordering problem, which is a better replay/mock-first fit.
- Tank paths can then use a narrower field-test packet once the highest-risk emergency branches are removed from the live-testing backlog.

## Risks and Rollback Policy

- Do not broaden the promoted default-on set until a path receives the specific coverage recommended above.
- Keep `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true` as the temporary rollback lever for already promoted paths.
- Keep every remaining path in this document on explicit default-off behavior.
- Do not combine Doom emergency coverage with ordinary live regression packets.
- Do not fold vector run reachability decisions into run_stop promotion work; treat vector retirement/unwiring as a separate future decision.
