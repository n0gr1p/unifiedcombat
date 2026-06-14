# Scheduler Ownership Field Test Results — Stage 7 Vector Run Ownership

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat scheduler ownership field-test build
**Stage:** Stage 7 — Vector run ownership

## Enabled Ownership Flag

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP = true
```

## Relevant UI / Runtime Settings

Stage 7 was tested using movement/combat behavior intended to cause the character to move toward a target.

Relevant settings used during the attempted test included:

```text
Run combat engine: enabled
Auto Target: enabled
Prime behavior: enabled
Face: enabled
Scheduler movement dispatch: enabled
Scheduler combat dispatch: enabled
```

## Scenario — Bound Target at Range with Aggro Transition

### Setup

A target was claimed at range using Bind to keep it far away.

TJ was configured for the test with:

```text
Auto Target: enabled
Prime: enabled
Face: enabled
```

The expected behavior was that TJ would move toward and engage the bound target, then transition to a nearby aggro mob after the first target died.

### Expected Behavior

If the scheduler vector run ownership path were live-reachable:

* Character should move normally toward the intended target.
* Character should move in the correct direction.
* Character should not run away, spin, stutter, or get stuck.
* Character should reach engagement range normally.
* After the first target dies, character should transition to the next valid target without ownership-related movement regression.
* The vector run ownership debug status should confirm dispatcher ownership execution if the scheduler vector path is reached.

Expected debug confirmation:

```text
RUN_VECTOR ... ownership=true dispatched=true ok=true fallback=false
```

## Reachability Audit Finding

`_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` is only written from `p1_move_toward_mob(...)` in `unified_scheduler.lua`.

Current runtime audit found no live caller for `p1_move_toward_mob(...)` in scheduler dispatch flow.

Live hunter/pathing/pull movement currently uses other movement systems, primarily direct/core movement ownership in `unified_combat_core.lua` and route-follow behavior in `uc_pathing.lua`, rather than the scheduler vector run helper path.

Because of that, the Stage 7 live field scenario could not confirm scheduler vector ownership execution.

## Observed Behavior with Vector Ownership Enabled

TJ moved to and engaged the bound mob as expected.

During the fight, a nearby aggressive mob also aggroed.

Between killing the first mob and transitioning to the second mob, TJ yoyoed back and forth. The behavior looked like movement was trying to return TJ to follow position on Nyoo while also trying to move toward the aggressive mob under Prime behavior.

This appeared to be a movement priority conflict rather than an execution failure of vector ownership.

## A/B Baseline Check

The same scenario was repeated with vector ownership disabled:

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP = false
```

The yoyo behavior still occurred with the vector ownership flag disabled while the movement scheduler remained enabled.

This indicates the yoyo behavior is not caused by vector run ownership.

## Additional Scheduler Baseline Observation

When both movement scheduler and combat scheduler were disabled, the yoyo behavior no longer occurred.

With movement and combat scheduler disabled, the character transitioned smoothly to the aggro mob.

This suggests the yoyo behavior is likely a scheduler movement-priority/arbitration issue, probably involving:

```text
follow/return-to-leader movement
vs
prime/autotarget combat movement toward the aggro mob
```

This should be tracked as a future movement priority cleanup item, not as a Stage 7 vector ownership failure.

## Debug Confirmation Attempt

A temporary Stage 7 debug dump was added to `local_ownership_flags.lua` to inspect:

```lua
_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE
```

No Stage 7 debug log appeared during the attempted live test.

Because the debug status did not fire, live execution of the scheduler vector run ownership path was not confirmed.

## Result

**DEFERRED / NOT LIVE-REACHABLE IN CURRENT RUNTIME FLOW**

## Reason

Stage 7 did not produce a live debug confirmation that the vector run ownership path executed.

The attempted live scenario did reveal a movement yoyo behavior, but A/B testing showed the same behavior with vector ownership disabled, so it is not considered an ownership regression.

The current evidence suggests the tested movement scenario does not hit the scheduler vector run ownership path because that path is not currently connected to live scheduler runtime flow.

## Coverage Status

```text
Visible movement toward initial target: PASS
No ownership-specific regression found: PASS
Vector ownership dispatch confirmed by debug status: NOT CONFIRMED
Yoyo behavior ownership-related: NO
Stage 7 final result: DEFERRED / NOT LIVE-REACHABLE
```

## Rollback Needed

**Rollback needed:** No

No ownership-specific failure was observed.

Vector ownership should remain disabled for promotion until live reachability is clarified or runtime wiring is intentionally restored.

## Notes / Log Snippets

No Stage 7 `RUN_VECTOR` ownership debug log was observed.

The yoyo behavior was reproduced with vector ownership disabled, and disappeared when movement/combat scheduler behavior was disabled.

This strongly suggests the yoyo behavior is baseline scheduler movement-priority behavior rather than dispatcher ownership behavior.

## Final Conclusion

Stage 7 vector run ownership was not confirmed through live field testing.

No vector ownership regression was proven, but the live vector ownership path also was not proven to execute.

The correct result is deferred/not live-reachable in current runtime flow pending future movement reachability cleanup or explicit runtime wiring work.

## Next Action

Future cleanup should audit whether scheduler vector run movement is intentionally dead code, should be removed, or should be reconnected to runtime flow.

Separately, movement priority/arbitration should be reviewed for the observed yoyo behavior between follow/return-to-leader movement and prime/autotarget combat movement.

If a live caller is restored in the future, rerun Stage 7 until debug output confirms:

```text
ownership=true
dispatched=true
dispatch_ok=true
fallback_used=false
```

The observed yoyo behavior should remain tracked as a future scheduler movement-priority cleanup item.
