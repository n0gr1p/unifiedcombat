# Vector Run Reachability Decision

## Current Reachability Evidence

The current repo state shows:

- `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` is written only in `p1_move_toward_mob(...)` inside `unified_scheduler.lua`.
- Repo search finds no live caller to `p1_move_toward_mob(...)`.
- `p1_try_dark_launch_dispatch(...)` routes only:
  - `target_control`
  - `pull_control`
  - `combat`
- none of those branches call `p1_move_toward_mob(...)`.

Live movement currently comes from other systems:

- `unified_combat_core.lua`
  - `move_toward_target_for_pull(...)`
  - `apply_movement(...)`
- `uc_pathing.lua`
  - route-follow movement
- `uc_party_follow.lua`
  - leader-follow movement

## Status of `p1_move_toward_mob(...)`

Current recommendation: treat `p1_move_toward_mob(...)` as dormant scheduler movement code rather than live runtime behavior.

It is not proven to be accidental dead code, but it is also not connected to the current runtime dispatch flow.

## Decision Recommendation

Recommended decision:

- do **not** reconnect `p1_move_toward_mob(...)` in the current phase,
- do **not** promote Stage 7/vector ownership based on current live testing,
- leave the code documented as dormant until there is an explicit scheduler-movement design decision.

## Why Not Remove It Immediately

Immediate removal would be premature because:

- it still documents an older/alternate scheduler-owned movement intent shape,
- it anchors the existing run ownership helper/tests/status global,
- removing it now would blur whether the future intent is:
  - full deletion,
  - later reconnection,
  - or replacement by a new explicit scheduler movement path.

## Why Not Reconnect It Immediately

Immediate reconnection would be risky because:

- live movement is currently owned by core/path/follow systems,
- reconnecting scheduler vector movement would change locomotion ownership rules,
- that would reopen movement parity and promotion questions after ownership-phase closure,
- and it would mix two separate issues:
  - dormant vector reachability,
  - current yoyo movement-priority conflict.

## Impact on Stage 7 / Vector Ownership Promotion

Stage 7 should remain:

- deferred / not live-reachable

This means:

- no ownership regression is proven,
- no successful live ownership execution is proven,
- vector ownership should not be promoted based on current field evidence.

## Recommended Follow-Up

Recommended sequence:

1. fix or audit the live movement arbitration issue first,
2. then decide whether scheduler-owned vector movement still has product/runtime value,
3. if yes, reconnect it only behind a new explicit runtime movement path with parity validation,
4. if no, retire the dormant vector path in a separate cleanup slice.

## Final Recommendation

`p1_move_toward_mob(...)` should be left dormant and documented for now, not removed immediately and not reconnected during the current audit.

Any future reconnect should be an explicit new runtime movement task, not a byproduct of ownership promotion cleanup.
