# Scheduler Combat-Spell Run-Stop Field-Test Packet

> **Historical Phase 1 artifact (2026-07-24):** Phase 2 retired the ownership
> flags and made these scheduler paths dispatcher-only. See
> `RFC/UnifiedCombat_scheduler_refactor_tracking.md`.

## Purpose

Validate live behavior for combat-spell run-stop ownership before any promotion decision.

This packet is limited to the two combat-spell run-stop ownership branches:

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

It does **not** cover:

- Doom ownership paths
- tank run-stop ownership paths
- vector run ownership

No runtime behavior is changed by this packet.

## Flags Under Test

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

## Required Local Flag Setup

- keep promoted ownership kill switch disabled
- enable only the two combat-spell run-stop flags under test
- do not enable Doom ownership flags
- do not enable tank run-stop flags
- do not enable vector run ownership

## Suggested `local_ownership_flags.lua` Snippet

Create or update:

`C:\Program Files (x86)\Windower\addons\UnifiedCombat\local_ownership_flags.lua`

```lua
-- T3.1d combat-spell run-stop field test only.
-- Keep promoted ownership kill switch disabled for this packet.
-- Do not enable Doom, tank, or vector-run ownership flags here.

_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP = true

-- Leave these disabled / absent:
-- _G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP = true
```

## Test Setup

### Minimum Character Count

- one combat caster is sufficient
- one support/follow character is helpful for confirming post-combat return behavior, but not strictly required

### Combat Role

- a character that regularly uses scheduler-driven combat spells
- avoid tank-specific or Doom-specific scenarios during this packet

### Target / Mob Setup

- use ordinary combat mobs with stable targetability
- avoid edge cases dominated by zero-HP death-animation cleanup while validating stop timing
- prefer a scenario where repeated combat spell attempts can occur naturally

### Movement State Needed

- begin while movement is meaningful, not fully idle for the entire scenario
- the packet is strongest when the character may still be moving or repositioning before the spell dispatch settles

### Scheduler State Needed

- scheduler combat dispatch enabled
- combat spell casting behavior enabled / naturally reachable in the user’s normal setup
- autotarget/prime may stay on if that is the normal path used to create combat spell intent

### Other Scheduler Families

Recommended to keep off unless the user specifically needs them for the scenario:

- Doom ownership flags
- tank run-stop ownership flags
- vector run ownership

Promoted default-on ownership paths may remain in their normal state because this packet is specifically about the two still-default-off combat-spell run-stop branches.

## Suggested Debug Observation

If the user wants live confirmation beyond visible behavior, watch these status globals:

- `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE`
- `_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE`

Relevant scheduler reasons seen in source:

- `COMBAT_SPELL_SETTLE`
- `COMBAT_SPELL_PREP_WAIT`

Related prep-window globals:

- `UC_MOVE_FREEZE_PREP_KEY`
- `UC_MOVE_FREEZE_PREP_UNTIL`

## Test Scenarios

### Scenario 1 — Combat Spell With Movement Settling Before Cast

Goal:

- confirm the settle stop path is reachable and behaves cleanly before a valid combat spell cast

Suggested setup:

- allow the character to engage a normal combat target
- let the character be moving or transitioning into casting range
- watch for a spell attempt that should create a new freeze-prep key and settle window

Expected branch:

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`

### Scenario 2 — Combat Spell Prep-Wait Path

Goal:

- confirm the prep-wait branch is practically reachable and does not create stop spam or timing regressions

Suggested setup:

- continue a combat spell scenario where the prep window remains active long enough for the scheduler to block again before the spell send proceeds
- this may require a slightly longer approach/reposition/cast-prep window than Scenario 1

Expected branch:

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

### Scenario 3 — Target Transition While Spell Intent Exists

Goal:

- ensure target transition does not create a stop loop, freeze, or stale spell-send behavior

Suggested setup:

- trigger a combat situation where the current target changes or dies while combat spell intent is still active
- confirm the stop behavior does not trap the character or cause repeated block/retry churn

### Scenario 4 — No-Target / Invalid-Target Cancellation

Goal:

- ensure the run-stop behavior does not cause a spell to fire onto an invalid target or preserve a stale block after cancellation

Suggested setup:

- create a moment where the target becomes invalid, unavailable, or otherwise unsuitable for the spell
- confirm cancellation or rescan behaves normally

### Scenario 5 — Normal Combat Spell Cast While Already Stationary

Goal:

- verify the ownership flags do not cause unnecessary stop churn when the character is already in a stable casting state

Suggested setup:

- engage a normal spell-casting combat scenario while already stationary
- confirm the spell still casts normally and no repeated stop/start loop appears

### Scenario 6 — Baseline Comparison With Flags Disabled

Goal:

- confirm disabling the two flags returns the behavior to the known baseline

Suggested setup:

- rerun at least one successful Scenario 1 or Scenario 5 test with both flags removed or set off
- compare for visible differences, especially freeze, stop spam, or follow-return regressions

## Expected Pass Criteria

- no freeze
- no stuck movement
- no repeated `run_stop` spam
- spell still casts when valid
- spell does not fire on invalid/dead target
- target transition does not regress into visible churn
- follow/path behavior resumes after combat
- disabling the two flags returns to baseline behavior

## Failure Criteria

- freeze or heavy lag
- spell never casts
- repeated stop/start loop
- movement lock never clears
- target transition regression
- follow return regression
- invalid/dead target cast attempt

## Result Template

Copy/paste template:

```md
# Combat-Spell Run-Stop Field Test Result

**Date:**
**Tester:**
**Build / Branch:**

## Enabled Flags

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP = true
```

## Scenario Coverage

- Scenario 1 — Combat spell with movement settling before cast:
- Scenario 2 — Combat spell prep-wait path:
- Scenario 3 — Target transition while spell intent exists:
- Scenario 4 — No-target / invalid-target cancellation:
- Scenario 5 — Normal combat spell cast when already stationary:
- Scenario 6 — Baseline comparison with flags disabled:

## Observations

- visible spell behavior:
- movement / stop behavior:
- target transition behavior:
- follow return behavior:
- any debug globals watched:
- any fallback observed:

## Result

- PASS
- PARTIAL
- FAIL
- DEFERRED

## Notes

- rollback required:
- differences with flags disabled:
- recommended next action:
```

## Promotion Decision Rule

- if both paths pass live testing, create a future task to decide promotion
- if only one path is reachable or passes, keep the other default-off
- if either path is not realistically reachable, document it as default-off pending future natural coverage
- do **not** promote in this task

## Rollback Rule

- remove the two flags or set them off
- reload if needed
- rerun the same scenario with the flags disabled

## Packet Conclusion

This packet is only meant to gather live evidence for the combat-spell settle/prep-wait run-stop pair.

It is not a promotion task.
