# Scheduler Ownership Field Test Results — Stage 6 Tank / Combat-Spell Run Stop

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat scheduler ownership field-test build
**Stage:** Stage 6 — Tank / combat-spell run_stop ownership paths

## Enabled Ownership Flags

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP = true
```

## Relevant UI / Runtime Settings

Relevant scheduler settings used during Stage 6 testing:

```text
Run combat engine: enabled
Auto Target: enabled
Tank behavior: enabled
Scheduler combat dispatch: enabled
Scheduler movement dispatch: disabled for this stage
Scheduler defensive dispatch: disabled for this stage
Scheduler maintenance dispatch: disabled for this stage
```

A temporary Stage 6 debug dump was added to `local_ownership_flags.lua` during testing to inspect tank-related run_stop validation globals.

## Scenario 1 — Tank Action Settle via Provoke

### Expected Behavior

With tank action settle run_stop ownership enabled:

* Tank action behavior should still execute normally.
* The scheduler should perform the tank action settle stop through dispatcher ownership.
* No fallback should be required.
* No duplicate stop behavior should occur.
* No visible combat or movement regression should occur.

### Observed Behavior

Tank Provoke action fired successfully.

The character continued combat normally.

No movement instability was observed.

No visible ownership-related regression was observed.

Live debug output confirmed the tank action settle run_stop path executed through dispatcher ownership.

### Observed Debug Output

```text
[UC Stage6] TANK_ACTION_SETTLE kind=run_stop source=unified_scheduler:T2.4f_darklaunch
ownership=true dispatched=true ok=true fallback=false reason=
```

This appeared repeatedly during the tested combat window while tank action behavior was active.

### Confirmed Status

```text
path=TANK_ACTION_SETTLE
kind=run_stop
source=unified_scheduler:T2.4f_darklaunch
ownership_enabled=true
dispatched=true
dispatch_ok=true
fallback_used=false
```

### Result

**PASS**

## Internal Path Coverage

### Confirmed Live Coverage

```text
TANK_ACTION_SETTLE: PASS
```

The `TANK_ACTION_SETTLE` path was confirmed live through debug output during tank Provoke behavior.

### Not Yet Confirmed / Not Covered

```text
TANK_SPELL_SETTLE: not yet confirmed
TANK_ENMITY_JA_SELF_SEND: not covered in this scenario
TANK_ENMITY_SPELL_TARGET_SEND: not yet confirmed
TANK_ENMITY_SPELL_SELF_SEND: not covered in this scenario
```

## Coverage Notes

The Provoke test exercises the tank action settle model, not every tank-related run_stop branch.

This result is a valid Stage 6 partial pass, but additional testing is needed to confirm tank spell settle and tank spell target send-adjacent paths if a practical scenario is available.

The remaining unconfirmed paths should not be considered failures unless a practical live scenario exists and produces incorrect behavior.

## Rollback Needed

**Rollback needed:** No

No rollback was required during this Stage 6 test.

## Notes / Log Snippets

No warning or error output was observed during the test.

No duplicate stop behavior was observed.

No stuck movement state was observed.

No visible tank action regression was observed.

## Final Conclusion

Stage 6 tank action settle ownership smoke testing passed.

The live Provoke tank-action scenario confirmed that the `TANK_ACTION_SETTLE` run_stop path executed through dispatcher ownership with:

```text
ownership_enabled=true
dispatched=true
dispatch_ok=true
fallback_used=false
```

No visible ownership-related regression was observed.

## Next Action

Continue Stage 6 only if a practical tank spell scenario is available.

Recommended next Stage 6 check:

```text
Configure a tank spell action and look for:
TANK_SPELL_SETTLE
TANK_ENMITY_SPELL_TARGET_SEND
```

If those paths cannot be naturally triggered, mark them as not covered in live testing and leave them covered by replay/static/helper validation only.

Keep vector run ownership disabled until Stage 7.
