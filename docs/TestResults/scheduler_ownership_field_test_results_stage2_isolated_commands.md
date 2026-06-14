# Scheduler Ownership Field Test Results — Stage 2 Isolated Commands

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat scheduler ownership field-test build
**Stage:** Stage 2 — Isolated command ownership paths

## Enabled Ownership Flags

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP = true
```

## Relevant UI / Runtime Settings

Relevant scheduler settings used during Stage 2 testing:

```text
Scheduler defensive dispatch: enabled
Scheduler maintenance dispatch: enabled
Scheduler combat dispatch: disabled for this stage
Scheduler movement dispatch: disabled for this stage
```

## Scenario 1 — Defensive Buff / Cure

### Expected Behavior

With defensive command ownership enabled:

* Defensive scheduler actions should still issue valid commands.
* Cure behavior should execute normally.
* Defensive buff behavior should execute normally.
* No duplicate command sends should occur.
* No missed cure/buff action should occur.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

Defensive buff behavior worked correctly.

Cure behavior worked correctly.

No errors or incorrect behavior were observed.

### Result

**PASS**

## Scenario 2 — COR Maintenance Rolls

### Expected Behavior

With maintenance COR command ownership enabled:

* COR maintenance actions should still issue valid roll commands.
* Rolls should be applied normally.
* No duplicate command sends should occur.
* No missed maintenance command should occur.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

COR maintenance actions successfully put up rolls.

No errors or incorrect behavior were observed.

### Result

**PASS**

## Deferred Scenario — Doom Holy Water

### Reason Deferred

Doom Holy Water command ownership was not live-tested.

Triggering Doom is not a practical or acceptable-risk field scenario for this ownership smoke test. Doom scenarios are not routine, and intentionally creating the condition would add unnecessary gameplay risk.

### Coverage Source

This path remains covered by replay/static/helper validation only.

Live field validation is deferred unless a safe mock/status-injection method is added later.

## Overall Stage 2 Result

**PASS for live-testable isolated command paths**

## Rollback Needed

**Rollback needed:** No

No rollback was required during Stage 2 testing.

## Notes / Log Snippets

No warning or error output was observed during the test.

No duplicate command behavior was observed.

No missed defensive command behavior was observed.

No missed COR maintenance command behavior was observed.

Doom Holy Water remains intentionally deferred from live field testing.

## Final Conclusion

Stage 2 isolated command ownership smoke testing passed for the practical live-testable paths.

Defensive buff, cure, and COR maintenance roll behavior worked correctly with ownership flags enabled.

## Next Action

Proceed to Stage 3 field testing.

Recommended Stage 3 scope: combat command ownership families.

Enable only combat command ownership flags next.

Do not enable run/run_stop/vector movement ownership flags yet.
