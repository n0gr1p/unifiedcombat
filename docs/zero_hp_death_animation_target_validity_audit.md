# 0 HP / Death-Animation Target Validity Audit

## Observed Field Behavior

During live field testing after a Weapon Skill kill:

- the mob can reach `0 HP` before the WS animation fully finishes,
- the mob may still remain targetable for a short window,
- and UnifiedCombat can briefly try to re-engage or move toward that target even though it is already effectively dead.

This produces a small post-kill yoyo that is distinct from:

- scheduler ownership routing,
- vector run ownership,
- and the T2.8 follow-vs-prime arbitration issue.

The key edge case is the short animation window where `valid_target` can still be true while the target is already non-attackable in practice because `hpp <= 0`.

## Likely Code Paths Involved

Primary runtime paths:

- `unified_combat_core.lua`
  - `find_candidate_target(...)`
  - `ensure_target_and_attack(...)`
  - `apply_movement(...)`
  - engaged sticky-target / death fast-switch handling
  - combat-intent / movement-lock refresh
- `uc_party_follow.lua`
  - follow suppression helper for active combat transition targets
- `uc_pathing.lua`
  - path-follow pause logic based on live combat target state
- `unified_scheduler.lua`
  - scheduler combat engage collection / dispatch revalidation
  - scheduler target/turn combat-target validity checks

## Current Target-Validity Checks

### Attack / Engage

Core candidate selection generally treats a combat target as live only when:

- `valid_target == true`
- `spawn_type == 16`
- `hpp > 0`

Examples:

- current target stickiness and current-target reuse in `unified_combat_core.lua`
- nearest-target scan in `unified_combat_core.lua`
- scheduler engage proposal collection in `unified_scheduler.lua`

However, the final core engage helper `ensure_target_and_attack(...)` only confirms:

- target id matches,
- target selection/switch succeeds,
- and player engaged state.

It does **not** re-check `hpp > 0` after target selection/switch immediately before engage.

Scheduler engage dispatch has the same shape:

- proposal collection requires `hpp > 0`,
- but final dispatch revalidation only checks target presence, `valid_target`, and expected id before calling `uc_attack.engage_target(...)`.

That leaves a race where a target can die after collection/selection but before the final engage send.

### Movement Toward Target

Combat-close movement in `apply_movement(...)` does not perform a fresh `hpp > 0` validation on entry.

Instead, it trusts the `target` object passed into it. In the normal steady-state path that target usually came from:

- `find_candidate_target(...)`, which does require `hpp > 0`,
- or current-target scheduler-owned consumption, which also requires `hpp > 0`.

But once a target object is already selected for the current tick, `apply_movement(...)` can still consume it for that tick even if the mob has just fallen to `0 HP` during the WS/death-animation window.

### Prime / Autotarget Selection

Prime/autotarget candidate selection already uses `hpp > 0` in the main scan:

- current target live/dead split:
  - `cur_alive_monster`
  - `cur_dead_monster`
- override and nearest-target scan
- partner arbitration
- tank fallback target selection

The core also has an existing death-aware concept:

- `death_event_active_for_id(id)`
- backed by `core.last_death_target_id` and `core.last_death_at`
- using `DEATH_SWITCH_WINDOW`

This is already used to treat the current engaged target as dead for target rescans even before the target fully disappears.

That means core target selection is already partially aware of “recently dead but still targetable” targets.

### Combat Intent / Movement Lock

When core has a target, it refreshes:

- `_G.UC_COMBAT_INTENT_UNTIL`
- `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL`
- `UC_MOVEMENT_OWNER = 'core'`
- `UC_MOVEMENT_LOCK_UNTIL`

Those windows are refreshed as soon as a non-nil target survives candidate selection for the tick.

When no target is found, core clears:

- `_G.UC_COMBAT_INTENT_UNTIL = 0`
- preengage / pull-approach flags
- and may stop movement / disengage in path-hunter cases

The gap is that these windows are not necessarily cleared the instant the current target hits `0 HP`; instead they persist until the next path that concludes “no valid target remains.”

### Follow Suppression

The T2.8d helper in `uc_party_follow.lua` already treats a live transition target as requiring:

- `valid_target == true`
- `spawn_type == 16`
- `hpp > 0`

So follow suppression itself is already using `hpp > 0` correctly for its “live transition target exists” check.

`uc_pathing.lua` also uses:

- `valid_target`
- `spawn_type == 16`
- `hpp > 0`

for its local `have_live_target` check.

So the new 0 HP yoyo does **not** appear to come from the follow suppression layer.

## Is `hpp <= 0` Already Handled?

Yes, but not uniformly.

Handled in many places:

- core target scan / current-target reuse
- scheduler engage proposal collection
- scheduler turn combat-target validation
- path-follow pause / follow suppression
- multiple JA / spell readiness checks
- tank target selection

Not handled at every last-step revalidation point:

- `unified_combat_core.lua` `ensure_target_and_attack(...)`
- `unified_scheduler.lua` final engage dispatch revalidation
- `unified_scheduler.lua` WS dispatch revalidation still checks `valid_target` and id, but not `hpp > 0`
- movement execution can still use a target chosen earlier in the same tick without a fresh death check

## Can a 0 HP Target Still Look “Valid” Today?

Yes.

A target can remain “valid” in the narrow Windower/UI sense because:

- it is still selected,
- `valid_target` is still true,
- id still matches,
- and the death animation has not fully resolved yet.

But at the same time:

- `hpp <= 0`,
- the mob is effectively dead,
- and attack/engage should no longer treat it as actionable.

That mismatch explains the observed post-WS mini-yoyo.

## Existing Dead / Recently-Dead Reuse Points

There is already a reusable core concept:

- `death_event_active_for_id(id)`
- sourced from `death_message_ids`
- recorded into `core.last_death_target_id` / `core.last_death_at`
- active for `DEATH_SWITCH_WINDOW`

Current use is narrow:

- current engaged target dead detection,
- sticky target invalidation,
- death fast-switch behavior.

It is **not** currently used as a shared final “do not engage / do not move / do not treat as actionable” guard across all commit-time paths.

## Implemented T2.9b Predicate

T2.9b adds a narrow final-action predicate in `unified_combat_core.lua`:

- `is_live_actionable_combat_target(mob_or_target, now, include_recent_death)`

It rejects:

- nil / malformed targets
- missing or zero target id
- `valid_target ~= true`
- non-combat `spawn_type`
- missing `hpp`
- `hpp <= 0`
- and, when `include_recent_death == true`, target ids still inside the short `death_event_active_for_id(...)` window

Guarded commit-time callsites:

- core `ensure_target_and_attack(...)`
- scheduler engage dispatch revalidation
- scheduler WS dispatch revalidation

This slice intentionally does **not** change broad scan logic, ranking, or movement arbitration rules.

## T2.9c Remaining Path and Guard

Field testing after T2.9b showed the WS-animation mini-yoyo still happened.

That result narrowed the live path further:

- T2.9b successfully blocked final engage / WS recommit to a dead target,
- but it did **not** guard the end-of-tick combat movement path,
- so `apply_movement(...)` could still consume the current target object and issue movement toward it during the short 0 HP / death-animation window.

Remaining path found:

- `unified_combat_core.lua`
  - end-of-tick `current = get_current_target()`
  - `apply_facing(s, current)`
  - `apply_movement(s, current)`

Why T2.9b missed it:

- T2.9b only hardened final engage / WS commit-time checks,
- while `apply_movement(...)` still accepted the provided `target` object without calling `is_live_actionable_combat_target(...)`.

T2.9c adds the narrowest safe guard:

- `apply_movement(...)` now immediately rejects targets that fail `is_live_actionable_combat_target(target, uc_now_s(), true)`.

This keeps the guard target-id scoped and recent-death aware without:

- changing broad target scan logic,
- adding name-based cooldowns,
- or clearing broad combat state globally.

## Safest Future Fix

T2.9b implements the first narrow slice:

1. add one shared “live actionable combat target” predicate in `unified_combat_core.lua` for final combat action paths,
2. treat `hpp <= 0` as invalid for:
   - engage intent,
   - target-switch / attack commit,
   - and scheduler WS final dispatch revalidation,
3. fold in the existing `death_event_active_for_id(id)` window at those final-action callsites.

Most conservative implementation target:

- harden final commit-time revalidation first,
- not broad candidate ranking logic,
- and not follow suppression.

In other words, prefer:

- “do not engage or move on a target unless it is still live/actionable right now”

over:

- changing broad scan policy,
- or adding long cooldowns that could hide legitimate next-target transitions.

## Why This Is Safer Than a Broad Cooldown

A broad recently-dead reject list alone is riskier because it can interfere with:

- fast multi-mob transitions,
- same-family nearby mobs,
- partner target handoff,
- and claim-driven reacquire behavior.

The narrowest safe fix is to harden the last actionable checks first:

- before engage,
- before movement commit,
- and before WS/attack reassertion on the current target.

If that is not enough, the existing `death_event_active_for_id(id)` window is the next safest extension because it is already scoped to a specific target id and a short timebox.

## Risks / Edge Cases

### Claim / Multi-Mob Transition

- Overly broad dead-target suppression could delay immediate switch to the next valid claimed mob.
- A dead-target cache must be target-id scoped, not name scoped.

### Loot / Corpse / Animation Delay

- Some mobs may remain targetable briefly after death for client/UI reasons.
- A fix must distinguish “targetable corpse/animation residue” from “live actionable combat target.”

### Partner / Prime / Autotarget

- Death fast-switch currently relies on quick rescan and retarget.
- Any added guard must avoid blocking the switch **to the next target** while only blocking reuse of the dead one.

### Scheduler / Core Parity

- Scheduler collection already filters `hpp > 0`, but dispatch revalidation does not always.
- If only core is hardened later, scheduler dark-launch combat may still exhibit the same edge in final dispatch.

### Target Cleanup Timing

- Clearing combat intent too aggressively on every transient target wobble could break legit post-kill transitions.
- Safer approach: reject only the dead/current target at final commit, then let the normal rescan select the next live target.

## Why Broad Scan Logic Was Not Changed

Broad scan logic was left alone on purpose:

- target scans already reject `hpp <= 0` in many places,
- the observed race is specifically between selection and final commit,
- and broad scan changes would carry more risk for partner, prime, tank, and multi-target transition behavior.

T2.9b therefore hardens only the final actionable revalidation points first and lets existing normal rescan / death fast-switch behavior choose the next live target.

## Recommended Narrow Implementation Slice

Current implemented slice:

- shared final-actionable-target predicate for core + scheduler commit-time checks,
- used in:
  - `ensure_target_and_attack(...)`,
  - scheduler engage dispatch revalidation,
  - scheduler WS dispatch revalidation.

Still intentionally deferred:

- broad scan/ranking changes
- movement-entry hardening outside those final action points

Desired behavior:

- if current target is `hpp <= 0`, do not re-engage it,
- do not move toward it,
- do not hold combat intent solely because it is still targetable,
- and allow normal rescan / death fast-switch to find the next live target.

## Proposed Field Test After Implementation

Use the same live setup that reproduced the issue:

1. kill a mob with WS,
2. observe the short 0 HP death-animation window,
3. confirm the character does **not** re-engage, re-WS, or step toward the dead 0 HP target during the animation window,
4. confirm the next live target is still acquired promptly when one exists,
5. confirm combat ends cleanly with no stalled intent when no next target exists.

## Rollback Note

T2.9b has no flag gate.

Rollback is:

- revert the three commit-time predicate guards,
- and/or revert the exported predicate in `unified_combat_core.lua`.
