# T3.4m — Engage action-state bypass audit

## Field-log evidence summary

- T3.4g fixed next-target selection.
- T3.4j added pending-engage confirmation and wait-longer retry handling.
- T3.4l fixed stale generic duplicate suppression for explicit attack-on retries.
- Post-T3.4l logs still showed tank engage waiting on action-state before the first `attack_on` send:
  - `TARGET_SELECTED`
  - `ENGAGE_PROPOSED`
  - `ACTION_STATE_BLOCK_ENGAGE`
  - `ENGAGE_DISPATCH_BLOCKED`
  - repeated until `ACTION_STATE_RELEASE`
  - only then `ENGAGE_DISPATCH_ATTEMPT`

## Why duplicate suppression was no longer the primary blocker

- The explicit attack-on retry cadence from T3.4l was already reopening quickly.
- The remaining delay was earlier in the path: `action_dispatch_blocked()` still ran before engage send and treated stale WS/JA/spell state as a hard stop.
- That meant the first explicit `attack_on` packet could not even be attempted until action-state released.

## Old action-state behavior

- Combat engage still called the generic action-state gate before the send.
- That gate blocked engage for:
  - WS acting state
  - JA acting state
  - spell acting state
  - post-spell tail
  - generic cooldown
  - engage debounce
- `STALE_SPELL_LOCK_RELEASE` existed, but a stale combat-spell lock could still wait for `action_is_acting()` to clear first, so transition release could land late.

## New explicit attack-on bypass behavior

- Scheduler engage now validates target selection/actionability first, then applies an explicit attack-on action-state gate.
- For explicit `attack_on` engage while `status ~= 1` and the selected target is valid/current:
  - stale WS action-state is bypassed
  - stale JA action-state is bypassed
  - stale spell cooldown/post-tail is bypassed
  - stale generic cooldown is bypassed
- Engage retry debounce is **not** bypassed.
- Active in-progress spell casts are still held unless the old mob-target combat spell lock is proven stale by target transition and released immediately.

## What action-state kinds can be bypassed

- `ws`
- `ja`
- stale `spell` cooldown / tail
- stale generic cooldown from earlier non-engage action-state

## What action-state kinds still block

- active in-progress `spell` cast that is not yet proven stale by target transition
- explicit engage debounce from the last `attack_on` send
- actual target-invalid / already-engaged / engage-send failure conditions outside action-state

## Wait-longer rejection relationship

- This patch intentionally lets explicit attack-on attempt earlier.
- If the game still refuses that attempt due to true animation lockout, the existing raw action message id `94` path continues to drive bounded retry handling.
- No new text fallback or ownership reroute was added.

## Stale spell release timing change

- Before patch:
  - stale mob-target combat spell release could wait until `action_is_acting()` expired, which could be multiple seconds after target selection.
- After patch:
  - stale mob-target combat spell release can clear immediately on proven target transition, including the previously acting case, and now logs:
    - `age_s`
    - `immediate`

## Timeline additions

- `ENGAGE_ACTION_STATE_BYPASS`
- `ENGAGE_ACTION_STATE_HELD_ACTIVE_CAST`
- `STALE_SPELL_LOCK_RELEASE` now includes `age_s` and `immediate`

## Risks

- Explicit attack-on can now be attempted earlier against stale WS/JA/spell lock state; that is intentional.
- Engage debounce from T3.4l remains the anti-spam guardrail.
- Active spell casts still remain conservative unless target transition proves the old mob-target spell state is stale.
- No ownership policy or side-effect routing changed.

## Rollback note

- Revert the explicit engage action-state gate in `uc_scheduler_action_state.lua` and the engage-path call ordering in `unified_scheduler.lua`.
- Revert `tests/replay/harness/selftest_engage_action_state_bypass.lua` and the related replay selftest/doc updates.

## Field-test instructions

1. Set `_G.UC_DEBUG_ACTION_TIMELINE = true`.
2. Reproduce a next-target transition where tank engage previously waited on stale WS/JA/spell state.
3. Confirm `TARGET_SELECTED` is followed by prompt `ENGAGE_DISPATCH_ATTEMPT` / `ENGAGE_DISPATCHED` without repeated `ENGAGE_DISPATCH_BLOCKED` from stale WS/JA state.
4. If stale action-state is present, confirm `ENGAGE_ACTION_STATE_BYPASS` logs the old `kind`.
5. If a real active cast is still in progress, confirm `ENGAGE_ACTION_STATE_HELD_ACTIVE_CAST` appears instead of a bypass.
6. Force a stale mob-target combat spell transition and confirm `STALE_SPELL_LOCK_RELEASE` now logs promptly with `age_s` and `immediate`.
7. If the game still rejects the engage because it is too soon, confirm the existing `PENDING_ENGAGE_REJECTED_WAIT_LONGER` / retry flow remains intact.
