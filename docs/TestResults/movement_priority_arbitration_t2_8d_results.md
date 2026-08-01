# Movement Priority Arbitration Field Test Results — T2.8d

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Build / Branch:** Current local UnifiedCombat movement-priority arbitration build
**Task:** T2.8d — Tighten movement arbitration release so follow resumes promptly after combat ends

## Enabled Flag

```lua
_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = true
```

## Scenario

Re-tested the original two-character post-kill yoyo scenario:

* Follow / return-to-leader behavior active.
* Prime / autotarget active.
* Movement scheduler enabled.
* Combat scheduler enabled.
* Character engaged combat, transitioned between targets, and exited combat.

## Expected Behavior

With movement arbitration enabled:

* The combat character should not yoyo between returning to the follow target and moving toward the next aggro/combat target during the immediate target transition.
* The combat character should return to the follow target promptly after the last valid combat target is gone.
* No Windower freeze should occur.
* No stuck movement state should occur.

## Observed Behavior

The test run was successful.

The combat character no longer yoyoed during the target transition.

On combat exit, the combat character returned to the follow target immediately.

No freeze occurred.

No stuck movement state was observed.

## Result

**PASS**

## Caveat — WS Kill / 0 HP Death Animation Targeting

One caveat was observed when a mob was killed by Weapon Skill.

The mob reaches `0 HP` and is effectively dead before the Weapon Skill animation fully completes. During that animation window, the mob can still appear targetable even though it cannot be engaged with an attack command.

During this short window, the character may attempt to engage the 0 HP target again, causing a small yoyo until the animation completes and the mob fully renders as dead / no longer targetable.

This appears to be a separate target-validity / death-animation edge case, not the same follow-vs-prime movement arbitration issue addressed by T2.8d.

## Conclusion

T2.8d successfully fixed the follow-return delay introduced by the earlier arbitration change.

The original post-kill follow-vs-prime yoyo behavior is fixed, and follow now resumes promptly after combat ends.

The remaining WS-kill yoyo behavior should be tracked separately as a 0 HP / death-animation target validity issue.

## Rollback Needed

**Rollback needed:** No

## Next Recommended Action

Open a separate audit for the 0 HP / death-animation target validity edge case.

Potential future fix direction:

* Treat targets with `hpp <= 0` as invalid for re-engage / movement intent.
* Add a short recently-dead target grace/block window after observing a target at 0 HP.
* Ensure the fix does not break loot/claim/target cleanup behavior.
