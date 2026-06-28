# Scheduler Remaining Run-Stop Coverage Plan

## Summary

T3.0b promoted 11 low-risk scheduler ownership paths to default-on.

The remaining default-off set is now narrow:

- Doom Holy Water command ownership
- Doom run_stop ownership
- vector run ownership remains separate and deferred

These paths should not all be treated the same.

- Doom remains emergency-only and should stay conservative unless a safe mock/status-injection harness is added.
- Tank action/tank spell/tank enmity paths are now fully promoted default-on.
- Tank configured-JA starvation was resolved in `T3.6o` by retuning the tank-mode configured-JA band; the run-stop plan below stays unchanged and should not be read as evidence that generic configured JAs are part of the tank-enmity lane.
- Vector run remains separate from run_stop planning and should stay parked as dormant/unreachable unless runtime wiring is intentionally revisited.

## Current Ownership Status

- 11 scheduler ownership paths are accepted as default-on after T3.0b field testing.
- Remaining default-off paths still require explicit `== true` enablement for Doom only.
- Static closure, promotion, parse, side-effect, and aggregate replay validation are already in place.
- Existing helper/runtime coverage proves helper-level dispatcher execution and fallback behavior, but not every remaining branch-specific live scheduler scenario.
- The tank configured-JA question was handled as a separate tuning fix and remains orthogonal to this run-stop inventory.

## Remaining Default-Off Inventory

| Flag | Family | Scheduler callsite / behavior | Current default-off reason |
| --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP` | command | Doom Holy Water emergency item command send after stop/cooldown checks | Emergency path with no safe practical live scenario |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP` | run_stop | Doom emergency stop before Holy Water item path | Emergency stop path with no safe practical live scenario |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | run_stop | Generic combat spell settle stop when a new freeze-prep key starts | Practical live confirmation missing |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` | run_stop | Generic combat spell prep-wait stop while freeze-prep window remains active | Practical live confirmation missing |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | run_stop | Tank-enmity spell self send-adjacent stop | Promoted default-on |

## Per-Path Coverage Recommendations

### `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`

- Live-reachable: presumed yes in the real Doom emergency flow.
- Safe to field test: no.
- Replay/mock coverage possible: yes, but only through a dedicated scheduler-branch mock/status-injection harness that can simulate Doom state and item cooldown ordering without real field risk.
- Exact test scenario needed: mocked player Doom status present, cooldown clear, one stop-before-item cycle, then one Holy Water command dispatch with no duplicate send.
- Recommended next action: add replay/mock test.
- Promotion risk: high.
- Rollback / kill-switch recommendation: keep explicit default-off and do not include in any combined live packet.
- Current T3.1b coverage status: static+mock branch coverage added; no live evidence added.
- T3.1c decision: remain intentionally default-off. Do not recommend real Doom live testing.

### `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`

- Live-reachable: presumed yes in the same Doom emergency flow.
- Safe to field test: no.
- Replay/mock coverage possible: yes, through the same scheduler-branch mock/status-injection approach used for Doom command planning.
- Exact test scenario needed: mocked Doom status, stop path reached before Holy Water command path, verify one dispatcher-owned `run_stop` with preserved stop-before-item ordering.
- Recommended next action: add replay/mock test.
- Promotion risk: high.
- Rollback / kill-switch recommendation: keep explicit default-off and do not promote from live inference alone.
- Current T3.1b coverage status: static+mock branch coverage added; no live evidence added.
- T3.1c decision: remain intentionally default-off. Do not recommend real Doom live testing.

### `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`

- Live-reachable: yes, likely reachable whenever a combat spell creates a new `UC_MOVE_FREEZE_PREP_KEY` and starts the settle window.
- Safe to field test: probably yes, but replay/mock coverage should come first.
- Replay/mock coverage possible: yes.
- Current T3.1b coverage status: static scheduler branch verification plus helper-level mock execution now proves explicit true routing, fallback preservation, and default-off semantics.
- Exact test scenario needed: spell dispatch branch enters a new prep key, sets `UC_MOVE_FREEZE_PREP_UNTIL`, emits `COMBAT_SPELL_SETTLE`, and blocks once before normal spell send continues.
- Replay/mock confidence level: medium-high for ownership routing and fallback; lower for real live timing parity because the branch has not been directly observed in field results.
- Practical live-test scenario: targeted combat spell scenario where a new freeze-prep key starts and the scheduler emits the settle block before the spell send continues.
- Promotion risk: medium.
- T3.1c decision: do not promote now. Require a targeted live field-test packet before any promotion decision.
- Rollback / kill-switch recommendation if promoted later: keep the temporary global promoted kill switch plus per-flag false opt-out during any first promotion stage.

### `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

- Live-reachable: yes, likely reachable during the active freeze-prep window after settle initialization.
- Safe to field test: probably yes, but replay/mock coverage should come first.
- Replay/mock coverage possible: yes.
- Current T3.1b coverage status: static scheduler branch verification plus helper-level mock execution now proves explicit true routing, fallback preservation, and default-off semantics.
- Exact test scenario needed: existing prep key remains active, current time stays below `UC_MOVE_FREEZE_PREP_UNTIL`, branch emits `COMBAT_SPELL_PREP_WAIT`, and repeated stop behavior preserves the existing prep block timing.
- Replay/mock confidence level: medium-high for ownership routing and fallback; lower for real live repeated-stop timing because this wait window has not been directly observed in field results.
- Practical live-test scenario: targeted combat spell scenario where the prep window remains active long enough to emit the prep-wait block before the owned spell send proceeds.
- Promotion risk: medium.
- T3.1c decision: do not promote now. Require the same targeted live field-test packet as the settle branch before any promotion decision.
- Rollback / kill-switch recommendation if promoted later: keep the temporary global promoted kill switch plus per-flag false opt-out during any first promotion stage.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`

- Status: promoted default-on.
- Live-reachable: yes.
- Safe to field test: yes.
- Replay/mock coverage possible: yes, and field evidence already exists.
- Exact test scenario needed: tank-enmity JA or spell branch initializes `tank_action_settle_key`, produces `TANK_ACTION_SETTLE`, and shows one stop before the settle window clears; Stage 6 Provoke already demonstrated this path.
- Recommended next action: no longer a default-off candidate; use the promoted default-on flow for any confirmatory packet.
- Promotion risk: low after promotion.
- Rollback / kill-switch recommendation: use explicit `false` opt-out or the shared promoted kill switch.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`

- Status: promoted default-on.
- Live-reachable: yes.
- Safe to field test: yes.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: tank behavior enabled, selected action resolves to JA self under tank-enmity flow, branch emits `TANK_ENMITY_JA_SELF_SEND`, and adjacent stop occurs once before the JA command send.
- Recommended next action: use the promoted default-on flow for any confirmatory packet.
- Promotion risk: low after promotion.
- Rollback / kill-switch recommendation: use explicit `false` opt-out or the shared promoted kill switch.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`

- Status: promoted default-on.
- Live-reachable: yes.
- Safe to field test: yes.
- Replay/mock coverage possible: yes, and field evidence already exists.
- Exact test scenario needed: tank-enmity spell branch selects a mob target, initializes `tank_spell_settle_key`, emits `TANK_SPELL_SETTLE`, and blocks once before the settle window clears.
- Recommended next action: use the promoted default-on flow for any confirmatory packet.
- Promotion risk: low after promotion.
- Rollback / kill-switch recommendation: use explicit `false` opt-out or the shared promoted kill switch.

### `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`

- Status: promoted default-on.
- Live-reachable: likely yes in tank-enmity spell self mode.
- Safe to field test: yes if the configured tank spell can naturally hit the self-target branch.
- Replay/mock coverage possible: yes.
- Exact test scenario needed: tank-enmity spell resolves to self-target behavior, branch emits `TANK_ENMITY_SPELL_SELF_SEND`, one adjacent stop occurs, then the self spell command sends normally.
- Recommended next action: use the promoted default-on flow for any confirmatory packet.
- Promotion risk: low after promotion.
- Rollback / kill-switch recommendation: keep explicit `false` opt-out and the shared promoted kill switch.

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

- tank action settle, tank-enmity JA self, tank spell settle, and tank-enmity spell self behaviors that are already promoted default-on

Goal:

- document the now-promoted tank-family run-stop behavior as historical field evidence only; do not treat this as a pending promotion packet.

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

## T3.1b Coverage Applied

T3.1b adds focused static+mock coverage for these four remaining default-off branches:

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

Coverage style used:

- static scheduler branch verification for exact flag gating and helper routing
- helper-level mock execution for explicit true dispatch and fallback preservation
- no runtime branch behavior changes

Current post-T3.1b status:

- Doom command and Doom run_stop now have replay/mock-first coverage rather than documentation-only planning.
- Combat spell settle/prep-wait run_stop now have static+mock ownership coverage for default-off semantics, true-path routing, and fallback presence.
- No branch was promoted in T3.1b.
- These four branches remain default-off pending any future promotion decision.

Promotion consideration after T3.1b:

- Doom command / Doom run_stop: still not eligible for promotion without a stronger safety case; keep default-off.
- Combat spell settle/prep-wait run_stop: now better covered, but still not promoted by this task; any future promotion should be a separate explicit decision.

## T3.1c Promotion Decision

Decision outcome:

- Doom Holy Water command ownership remains intentionally default-off.
- Doom run_stop ownership remains intentionally default-off.
- Combat spell settle run_stop is a future promotion candidate only after a targeted live field-test packet.
- Combat spell prep-wait run_stop is a future promotion candidate only after the same targeted live field-test packet.

Recommended next action:

- create `T3.1d` as a focused combat-spell run_stop field-test packet covering both settle and prep-wait timing windows
- do not combine Doom with that packet
- if a practical combat-spell scenario still cannot be reproduced cleanly, leave both combat-spell branches default-off pending natural field coverage rather than promoting from replay/mock evidence alone

## T3.1d Field-Test Packet Status

- created `docs/scheduler_combat_spell_run_stop_field_test_packet.md`
- packet scope is limited to the combat-spell settle/prep-wait run-stop pair
- no promotion occurs in T3.1d
- Doom command/run_stop remains default-off and outside this packet

## T3.1e Tank-Spell Movement-Lock Bugfix

- Field testing uncovered a separate runtime bug in the scheduler tank-spell path: after the existing pre-send `run_stop`, movement could resume while the tank spell was still in flight.
- Root cause was not ownership promotion state. The scheduler tank-spell send path did not carry forward the bounded cast-wait movement lock model already used by the core tank-spell flow.
- `unified_scheduler.lua` now records a scheduler-local tank-spell wait state after tank spell send and refreshes a short bounded scheduler movement lock while the in-flight spell action remains active or in immediate post-action cooldown.
- This is a runtime bugfix only. No tank run-stop ownership flags were promoted or reclassified by T3.1e.
- Recommended next field test: repeat the Terrasjr tank-enmity spell repro with schedulers enabled and confirm the character stops for the spell, does not run through the mob, and resumes normal movement after the cast window clears.

## T3.1f Defensive Cure Movement-Lock Bugfix

- Run-stop field work also uncovered a separate scheduler defensive Cure/spell runtime bug: Cure could be sent during initial approach without any cast-time stop/lock lifecycle.
- T3.1f fixes that scheduler runtime bug at the defensive spell send points in `unified_scheduler.lua`.
- This is a runtime bugfix only.
- No ownership promotion decision changed.
- No default-off run-stop flag status changed.

## Risks and Rollback Policy

- Do not broaden the promoted default-on set until a path receives the specific coverage recommended above.
- Keep `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true` as the temporary rollback lever for already promoted paths.
- Keep every remaining path in this document on explicit default-off behavior.
- Do not combine Doom emergency coverage with ordinary live regression packets.
- Do not fold vector run reachability decisions into run_stop promotion work; treat vector retirement/unwiring as a separate future decision.
