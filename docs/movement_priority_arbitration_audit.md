# Movement Priority Arbitration Audit

## Scope

This is a docs-only audit of the observed yoyo behavior seen during scheduler ownership field testing after the first target died and an aggro mob became the next practical combat target.

T2.8b adds a default-off runtime guard based on this audit.

## Observed Scenario

During Stage 7 field testing, TJ:

- killed a first mob,
- then had a nearby aggressive mob become the next practical combat target,
- but yoyoed between returning toward Nyoo/follow position and moving toward the aggro mob.

The same yoyo behavior reproduced with vector run ownership disabled, so it is not an ownership regression.

When both movement scheduler and combat scheduler were disabled, the yoyo did not occur and the transition to the aggro mob was smooth.

## Reproduction Notes

- Combat/autotarget behavior was active.
- Party-follow / return-to-leader behavior was also active in the same general runtime.
- The yoyo appeared during the post-kill transition window rather than during initial approach to the first target.
- Stage 7 audit also showed the scheduler vector ownership path was not the live owner for this movement.

## Likely Competing Movement Sources

### 1. Party Follow / Return-To-Leader

`uc_party_follow.lua` actively issues movement vectors in `M.prerender()` when follow is enabled and not suppressed.

Relevant behavior:

- `combat_engine_suppresses_follow(s)` suppresses follow only when one of several combat windows is active:
  - player is engaged,
  - `_G.UC_PREENGAGE_APPROACH_ACTIVE == true`,
  - `now < _G.UC_COMBAT_INTENT_UNTIL`,
  - cast-freeze / pull-wait states.
- If those suppressors are not active, party follow can issue:
  - `windower.ffxi.run((lx - self_mob.x) / len, (ly - self_mob.y) / len)`
  - `windower.ffxi.run(false)`
- Party follow also writes:
  - `_G.UC_MOVEMENT_OWNER = 'follow'`
  - `_G.UC_MOVEMENT_LOCK_UNTIL = now + 0.20/0.25`

This means party-follow can reacquire movement very quickly if the combat suppression window expires between combat transitions.

### 2. Path Follow / Return Along Route

`uc_pathing.lua` owns route-follow movement in `tick_follow(settings)`.

Relevant behavior:

- `should_pause_for_combat()` pauses path-follow when:
  - `_G.UC_MOVEMENT_OWNER` is non-`none` and non-`path` and lock is still active,
  - `_G.UC_PULL_APPROACH_UNTIL` is active,
  - `_G.UC_PREENGAGE_APPROACH_ACTIVE == true`,
  - engaged state is active,
  - pull wait is active.
- If no pause is active, path-follow resumes route movement with `run_to_point(...)`.

This means path-follow can also resume as soon as core/follow ownership windows stop refreshing.

### 3. Core Combat / Prime / Autotarget Movement

`unified_combat_core.lua` owns the live combat-close movement path today.

Relevant behavior:

- `apply_movement(settings, target)` issues direct run/mover movement toward combat targets.
- `move_toward_target_for_pull(target)` issues direct run for pull approach.
- During target acquisition / transition, core sets:
  - `_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.8`
  - `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL = uc_now_s() + party_follow_hold_seconds(s)`
  - `set_movement_owner('core', 0.8)`
- If no target exists, core clears:
  - `_G.UC_COMBAT_INTENT_UNTIL = 0`
  - pre-engage / pull approach flags
  - then may stop current run.

This creates a short combat-intent ownership window, but only while core believes a valid target currently exists.

## Why the Yoyo Can Happen

The likely conflict window is:

1. first target dies,
2. core briefly loses a stable combat target or clears target/intent state,
3. follow/return logic sees combat suppression drop,
4. follow reasserts movement back toward leader,
5. core reacquires the next aggro/combat target and reasserts forward movement,
6. repeated short alternation creates the visible yoyo.

In other words, both systems do not need to issue movement in the exact same function call to compete; they only need adjacent ticks with alternating ownership refresh.

## Existing Arbitration Fields / Hooks

The repo already has useful movement-arbitration fields:

- `_G.UC_MOVEMENT_OWNER`
- `_G.UC_MOVEMENT_LOCK_UNTIL`
- `_G.UC_COMBAT_INTENT_UNTIL`
- `_G.UC_PREENGAGE_APPROACH_ACTIVE`
- `_G.UC_PULL_APPROACH_UNTIL`
- `_G.UC_PULL_SPELL_WAITING`
- `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL`
- follow pause reasons in `uc_pathing.lua`
- follow suppression gate in `uc_party_follow.lua`

This means a future fix does not need a brand-new movement ownership system; it can likely extend the existing suppression/intent windows.

## Conservative Priority Rule

Recommended conservative rule:

> If the character is a combat participant and either has a valid live combat target or is in an immediate autotarget/prime transition window to the next combat target, suppress follow/return-to-leader movement until the combat target becomes invalid and the combat-transition window ends.

Practical interpretation:

- follow/return movement should not reacquire control in the short post-kill gap when core is actively transitioning to the next valid combat target,
- combat-close movement should keep priority through that transition,
- follow/path return should resume only after target loss is stable rather than momentary.

## Risks of the Priority Rule

### Risk 1: Over-suppressing Follow

If the suppression window is too long, the character may ignore legitimate follow recovery after combat ends.

### Risk 2: Stale Combat Intent

If combat-transition state is not cleared reliably, follow/path movement may remain suppressed after the target is gone.

### Risk 3: Pull / Tank / Spell Interaction

Movement suppression already interacts with:

- pull approach,
- pull spell wait,
- tank settle / tank spell wait,
- pre-engage approach.

A new rule must not accidentally extend those states beyond their intended duration.

### Risk 4: Path-Hunter Edge Cases

Path-hunter intentionally mixes route-follow and combat target acquisition. A broader combat-priority rule could mask cases where route-follow should actually resume immediately.

## Recommended Next Implementation Slice

Recommended next runtime slice:

1. keep the change narrow and do not touch ownership helpers or dispatcher,
2. patch only the follow/path arbitration layer,
3. extend existing combat-intent suppression so follow/return movement cannot reacquire during immediate post-kill autotarget/prime transitions,
4. validate specifically against the reproduced yoyo scenario.

Most conservative candidate:

- teach `uc_party_follow.lua` and/or `uc_pathing.lua` to treat the current post-kill combat-transition window as a hard suppressor for follow/return movement when:
  - combat participant is true,
  - autotarget/prime transition target is still actionable or being reacquired,
  - and target loss is not yet stable.

## Implemented Guard

T2.8b implements a default-off flag:

- `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION == true`

Any other value preserves current behavior.

Guarded locations:

- `uc_party_follow.lua`
  - `combat_engine_suppresses_follow(...)`
- `uc_pathing.lua`
  - `should_pause_for_combat()`

The shared suppression helper uses existing state only:

- `_G.UC_COMBAT_INTENT_UNTIL`
- `_G.UC_MOVEMENT_OWNER`
- `_G.UC_MOVEMENT_LOCK_UNTIL`
- `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL`
- `_G.UC_PREENGAGE_APPROACH_ACTIVE`
- combat-participant status

## T2.8c Hardening Result

Default-off field testing passed:

- reload with the flag set to `false` succeeded,
- two-character follow testing with the flag set to `false` succeeded,
- and the original yoyo still reproduced with the flag off, confirming default-off behavior is preserved.

The earlier flag-on freeze was reviewed and the most likely cause was over-broad suppression in the T2.8b helper:

- the helper previously suppressed follow/path behavior on any live combat target,
- which was broader than the intended “immediate combat transition window,”
- and could stall movement across characters whenever combat targeting remained live.

T2.8c narrows the flag-on path so it now uses only explicit transition signals:

- `_G.UC_COMBAT_INTENT_UNTIL`
- `_G.UC_MOVEMENT_OWNER == 'core'` with active `_G.UC_MOVEMENT_LOCK_UNTIL`
- `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL`
- `_G.UC_PREENGAGE_APPROACH_ACTIVE`

It no longer suppresses solely because a live target exists.

No require/import cycle was found. `uc_pathing.lua` already depended on `uc_party_follow.lua`, and the hardened path only reuses the exported helper through that existing one-way dependency.

## Field-Test Recommendation

Field testing with:

```lua
_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = true
```

may resume, but only for the original reproduced post-kill yoyo scenario.

The flag-on path is now narrowed to explicit transition windows rather than broad live-target suppression.

Additional field testing then confirmed two things with the flag set to `true`:

- the original post-kill yoyo was fixed,
- but follow/return-to-leader could stay suppressed briefly after combat ended even when no valid combat target remained.

That post-combat delay did not track the configured follow hold timer, which points back to stale arbitration windows rather than the normal follow hold behavior.

## T2.8d Release Refinement

T2.8d keeps the T2.8c yoyo fix but tightens the release rule so stale combat-intent or fight-follow windows no longer suppress follow by themselves.

The shared helper in `uc_party_follow.lua` now suppresses only while one of these actively remains true:

- `_G.UC_MOVEMENT_OWNER == 'core'` and `now < _G.UC_MOVEMENT_LOCK_UNTIL`
- `_G.UC_PREENGAGE_APPROACH_ACTIVE == true`
- `now < _G.UC_COMBAT_INTENT_UNTIL` and a live combat transition target still exists
- `now < _G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL` and a live combat transition target still exists

It now releases follow promptly when combat state is gone:

- no valid live target remains,
- no active preengage/approach remains,
- and no active core movement lock remains.

Reason strings were also tightened so field debugging can distinguish active suppression from stale-window release:

- suppression: `movement_lock`, `preengage`, `combat_intent_target`, `fight_follow_hold_target`
- release: `combat_intent_stale`, `fight_follow_hold_stale`, `none`

## Expected Field-Test Scenario

- Enable combat/autotarget/prime behavior in the same setup that previously reproduced the yoyo.
- Repeat once with `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = false` or unset.
- Repeat once with `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = true`.
- Compare whether post-kill return-to-leader/path-resume reassertion still fights the next aggro/combat transition.
- With the flag on, also confirm the combat character returns to the follow target promptly once no valid combat target, preengage, or core movement lock remains.

## Rollback

- Set `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = false`
- or remove it from `local_ownership_flags.lua`

## Recommendation

- Do not change ownership routing for this issue.
- Treat this as a movement arbitration bug in the live core/follow/path systems.
- The first focused post-kill combat-transition suppression slice is now implemented behind the default-off arbitration flag before any additional vector-run work.
