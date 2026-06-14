# Scheduler Ownership Field Test Results — Stage 5 Movement-Coordinator Run Stop

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat scheduler ownership field-test build
**Stage:** Stage 5 — Movement-coordinator run_stop ownership paths

## Enabled Ownership Flags

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP = true
```

## Relevant UI / Runtime Settings

Relevant scheduler settings used during Stage 5 testing:

```text
Scheduler movement dispatch: enabled
Hunter/pathing behavior: enabled for the tested scenario
```

Other ownership families were not the focus of this test.

## Scenario — Hunter Pathing Pull Movement Stop

### Expected Behavior

With movement-coordinator run_stop ownership enabled:

* Character should move toward the pull/cast position normally.
* Character should stop cleanly when reaching the valid pull/cast range.
* Pull action should execute normally.
* No repeated start/stop movement spam should occur.
* Character should not run through the intended pull/cast position.
* Character should not get stuck after stopping.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

Using hunter pathing, the character moved into range, stopped, and pulled as expected.

No strange movement behavior was observed.

No stutter-running was observed.

No failure to stop was observed.

No failure to pull was observed.

No stuck movement state was observed after the pull.

## Internal Path Coverage

A temporary Stage 5 debug dump was added to `local_ownership_flags.lua` during testing to inspect the scheduler run_stop validation globals.

Live chat output confirmed all three Stage 5 scheduler movement-coordinator run_stop paths fired during the test.

### MOVE_COORD_CAST_FREEZE_PREP

Observed status:

```text
CAST_FREEZE_PREP kind=run_stop source=unified_scheduler:T2.4c_darklaunch
ownership=true dispatched=true ok=true fallback=false
```

Result:

```text
ownership_enabled=true
dispatched=true
dispatch_ok=true
fallback_used=false
```

### MOVE_COORD_PULL_CAST_HOLD

Observed status:

```text
PULL_CAST_HOLD kind=run_stop source=unified_scheduler:T2.4d_darklaunch
ownership=true dispatched=true ok=true fallback=false
```

Result:

```text
ownership_enabled=true
dispatched=true
dispatch_ok=true
fallback_used=false
```

### MOVE_COORD_PULL_SPELL_WAIT

Observed status:

```text
PULL_SPELL_WAIT kind=run_stop source=unified_scheduler:T2.4e_darklaunch
ownership=true dispatched=true ok=true fallback=false
```

Result:

```text
ownership_enabled=true
dispatched=true
dispatch_ok=true
fallback_used=false
```

## Result

**PASS**

## Rollback Needed

**Rollback needed:** No

No rollback was required during Stage 5 testing.

## Notes / Log Snippets

No warning or error output was observed during the test.

The movement behavior was normal under hunter/pathing pull behavior.

The character moved into range, stopped, and pulled without visible ownership-related movement regression.

All three Stage 5 scheduler movement-coordinator ownership paths executed through dispatcher ownership successfully.

No fallback was used for any of the three confirmed paths.

The temporary debug dump should be removed from `local_ownership_flags.lua` after recording this result to avoid continued chat spam.

## Final Conclusion

Stage 5 movement-coordinator run_stop ownership smoke testing passed.

The hunter/pathing pull scenario confirmed path-specific live coverage for all three Stage 5 scheduler movement-coordinator run_stop paths:

* `MOVE_COORD_CAST_FREEZE_PREP`
* `MOVE_COORD_PULL_CAST_HOLD`
* `MOVE_COORD_PULL_SPELL_WAIT`

Each path executed with ownership enabled, dispatched successfully, and did not require fallback.

No visible movement regression was observed.

## Next Action

Proceed to Stage 6 field testing.

Recommended Stage 6 scope: tank/combat-spell run_stop paths.

Keep vector run ownership disabled until Stage 7.
