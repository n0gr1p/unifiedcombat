# Scheduler Ownership Field Test Results — Stage 1 Target + Turn

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat scheduler ownership field-test build
**Character / Session:** Redrogue
**Job / Subjob:** Not recorded
**Stage:** Stage 1 — Target ownership + Turn ownership

## Enabled Ownership Flags

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP = true
```

## Relevant UI / Runtime Settings

Stage 1 testing was performed with the scheduler target/turn path active.

Relevant enabled settings:

```text
Run combat engine: enabled
Auto Target: enabled
Face: enabled
Scheduler combat dispatch: enabled
```

Other ownership families were not intentionally under test for this result.

## Scenario 1 — Initial Pull Smoke Test

### Expected Behavior

With target and turn ownership flags enabled:

* Scheduler should acquire/select the correct target.
* Facing behavior should continue to work normally.
* No duplicate target changes should occur.
* No missed target prep should occur.
* No turn/facing spam should occur.
* No twitchy facing should occur.
* No visible gameplay behavior should differ from default-off behavior.
* No local ownership flag loader warning should appear.

### Observed Pulls

1. Pull 1: one claimed mob.
2. Pull 2: one claimed mob plus one aggro mob.
3. Pull 3: additional mob pull completed.

### Observed Behavior

No errors or incorrect behavior were observed after three mob pulls.

Observed behavior was normal across:

* Single claimed mob pull.
* Claimed mob plus aggro mob scenario.
* Additional follow-up pull.

No visible target ownership issue was observed.

No visible turn/facing ownership issue was observed.

### Result

**PASS**

## Scenario 2 — Multi-Mob Target Transition Test

### Expected Behavior

Scheduler should continue to acquire/engage the remaining mob, face the correct target, and avoid:

* target bounce
* missed target prep
* turn spam
* twitchy facing
* visible targeting/facing regression

### Observed Behavior

The character engaged the additional mobs as expected.

No errors were observed.

No target bounce was observed.

No missed targeting or target-prep issue was observed.

No facing/turn spam was observed.

No twitchy facing was observed.

### Observation

The expected “fast switch target” behavior did not occur. Instead, the character appeared to allow disengage/re-engage before continuing.

At this point it was not yet confirmed whether this behavior was related to scheduler target/turn ownership or current baseline behavior.

### Initial Result

**PASS with observation pending baseline comparison**

## Scenario 3 — A/B Follow-up: Fast Switch Baseline Check

### Reason for Follow-up

During the multi-mob transition test, the character did not perform the expected “fast switch target” behavior. The concern was whether target ownership routing changed target transition behavior.

### A/B Test Performed

Repeated the same multi-mob transition scenario multiple times with Stage 1 ownership flags disabled.

Disabled flags:

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP = false
```

### Observed Behavior with Flags Disabled

The fast switch behavior still did not occur with ownership flags disabled.

### Conclusion

The missing fast switch behavior appears to be current baseline behavior, not caused by scheduler target/turn ownership routing.

## Overall Stage 1 Result

**PASS**

## Rollback Needed

**Rollback needed:** No

No rollback was required during Stage 1 testing.

## Notes / Log Snippets

No warning or error output was observed during the test.

No target-selection regression was observed.

No facing/turning regression was observed.

No ownership-related regression was observed.

The missing fast-switch behavior was reproduced with ownership flags disabled, so it is recorded as baseline behavior rather than an ownership failure.

## Final Conclusion

Stage 1 target + turn ownership smoke testing passed.

Target acquisition, continued engagement, and facing behavior worked as expected with ownership flags enabled.

No target bounce, missed target prep, turn spam, twitchy facing, or visible ownership-related regression was observed.

## Next Action

Proceed to Stage 2 field testing.

Recommended Stage 2 scope: isolated command ownership paths only.

Do not enable combat command family flags yet.

Do not enable run/run_stop ownership flags yet.
