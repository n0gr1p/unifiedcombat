# Zero HP Death-Animation Target Validity Field Test Results — T2.9c

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Task:** T2.9c — Find and guard the remaining 0 HP WS-animation movement churn path

## Scenario

Re-tested the Weapon Skill kill scenario that previously caused a short post-combat mini-yoyo.

The issue occurred when:

* a mob was killed by Weapon Skill,
* the mob reached `0 HP`,
* the mob was effectively dead but still targetable during the WS/death animation window,
* the character briefly tried to move toward or interact with that dead target until the animation completed.

## Expected Behavior

After T2.9c:

* no re-engage attempt on the 0 HP target,
* no extra WS attempt on the 0 HP target,
* no move-toward churn / mini-yoyo during the WS animation death window,
* normal transition to another live target if one exists,
* clean combat exit / follow return if no valid target remains.

## Observed Behavior

The test passed.

There was no more post-combat yoyo during the Weapon Skill animation death window.

The character no longer churned toward the 0 HP target while it was still visually targetable during the death animation.

## Result

**PASS**

## Conclusion

T2.9c successfully fixed the remaining 0 HP / death-animation movement churn path.

The earlier T2.9b fix correctly guarded engage and WS recommit paths, but T2.9c addressed the remaining core movement-intent path through `apply_movement(...)`.

This issue should be considered resolved unless broader multi-target regression testing reveals a new edge case.

## Rollback Needed

**Rollback needed:** No

## Next Recommended Action

Run one light regression pass during normal play with:

* a single target killed by WS,
* a multi-mob transition after WS kill,
* clean combat exit with follow return.

If those remain clean, this movement/target-validity cleanup can be closed.
