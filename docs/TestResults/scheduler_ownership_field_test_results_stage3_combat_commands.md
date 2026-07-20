# Scheduler Ownership Field Test Results — Stage 3 Combat Commands

> **Historical result:** The WS flag tested here was retired on 2026-07-20 when scheduler WS dispatch moved to the unified core intent owner for atomic skillchain-plan validation. The JA and spell evidence remains applicable to their ownership seams.

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat scheduler ownership field-test build
**Stage:** Stage 3 — Combat command ownership families

## Enabled Ownership Flags

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP = true
```

## Relevant UI / Runtime Settings

Relevant scheduler settings used during Stage 3 testing:

```text
Scheduler combat dispatch: enabled
Scheduler defensive dispatch: disabled for this stage unless needed for unrelated baseline behavior
Scheduler movement dispatch: disabled for this stage
Scheduler maintenance dispatch: disabled for this stage
```

Combat engine was enabled and the tested character/session was allowed to perform normal combat actions.

## Scenario 1 — Weapon Skill Command

### Expected Behavior

With combat WS command ownership enabled:

* Weapon Skill commands should still execute normally.
* No duplicate WS command should be sent.
* No missed WS command should occur.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

Weapon Skill behavior worked correctly.

No errors or incorrect behavior were observed.

### Result

**PASS**

## Scenario 2 — Self Job Ability Command

### Expected Behavior

With combat JA command ownership enabled:

* Self-targeted job ability commands should still execute normally.
* No duplicate self JA command should be sent.
* No missed self JA command should occur.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

Self job ability behavior worked correctly.

No errors or incorrect behavior were observed.

### Result

**PASS**

## Scenario 3 — Targeted Job Ability Command

### Expected Behavior

With combat JA command ownership enabled:

* Targeted job ability commands should still execute normally against the intended target.
* No duplicate targeted JA command should be sent.
* No missed targeted JA command should occur.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

Targeted job ability behavior worked correctly.

No errors or incorrect behavior were observed.

### Result

**PASS**

## Scenario 4 — Combat Spell Target Command

### Expected Behavior

With combat spell command ownership enabled:

* Combat spell commands should still execute normally when a combat-driven spell path is active.
* The spell should be issued against the intended target.
* No duplicate spell command should be sent.
* No missed spell command should occur.
* No visible behavior should differ from default-off behavior.

### Observed Behavior

A spell was configured as the tank action to create a practical combat-driven spell test path.

The tank spell action executed correctly.

No errors or incorrect behavior were observed.

### Result

**PASS**

## Scenario 5 — Combat Spell Self Command

### Coverage Status

**Not covered / not applicable in current combat setup**

### Reason

Self spells are not currently driven by the combat command path in this setup. They are defensive buff driven instead, so there was no practical combat-owned self-spell command scenario to exercise during Stage 3.

### Result

**Not covered**

This is not considered a Stage 3 failure because the current addon behavior does not provide a practical combat-driven self-spell trigger path.

## Overall Stage 3 Result

**PASS for practical live-testable combat command paths**

## Rollback Needed

**Rollback needed:** No

No rollback was required during Stage 3 testing.

## Notes / Log Snippets

No warning or error output was observed during the test.

No duplicate command behavior was observed.

No missed WS command behavior was observed.

No missed JA command behavior was observed.

No missed combat spell command behavior was observed.

Combat self-spell command ownership remains covered by replay/static/helper validation only, unless a practical combat-driven self-spell scenario is added later.

## Final Conclusion

Stage 3 combat command ownership smoke testing passed for the practical live-testable command families.

Weapon Skill, self job ability, targeted job ability, and combat spell target/tank-action spell behavior worked correctly with ownership flags enabled.

No visible ownership-related command regression was observed.

## Next Action

Proceed to Stage 4 field testing.

Recommended Stage 4 scope: isolated `run_stop` ownership path.

Doom Holy Water command itself remains deferred from live testing, but the Doom run-stop path should also remain deferred unless a safe mock/status-injection method is added. If no practical Stage 4 live scenario exists, mark Stage 4 as deferred and proceed to Stage 5 movement-coordinator run-stop testing.
