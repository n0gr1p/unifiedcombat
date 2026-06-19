# T3.4n — Complete explicit attack-on action-state bypass audit

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

## Why T3.4m was partial

- T3.4m correctly moved explicit `attack_on` off the old generic pre-send stall for stale WS/JA state.
- But it still kept explicit engage behind:
  - active `spell` action-state
  - post-spell tail
  - generic cooldown
  - the narrow local action-state gate itself even when retry cadence and ownership already allowed another send
- That was narrower than the intended policy for explicit `uc_attack.engage_target(...)`, which is allowed to try and let message id `94` drive bounded retry if the server still wants more time.

## Completed T3.4n explicit attack-on bypass behavior

- Scheduler engage now validates target selection/actionability first, then applies an explicit attack-on action-state gate.
- For explicit `attack_on` engage while `status ~= 1` and the selected target is valid/current:
  - `weaponskill` action-state is bypassed
  - `job_ability` action-state is bypassed
  - `spell` action-state is bypassed
  - `post_spell_tail` is bypassed
  - generic `cooldown` is bypassed
- Engage retry debounce is **not** bypassed.
- Pending-engage confirmation/retry state is still respected, but only for:
  - confirmation wait
  - retry cadence
  - target validity
  - critical Cure override
- Explicit attack-on no longer uses generic scheduler action-state as a hard predictor for whether a retry attempt may be sent.

## What action-state kinds can be bypassed

- `weaponskill`
- `job_ability`
- `spell`
- `post_spell_tail`
- `cooldown`

## Remaining legitimate blockers

- explicit engage debounce from the last `attack_on` send
- pending-engage retry cadence not ready yet
- invalid or non-actionable target
- player already `status == 1`
- dead player
- critical Cure / true emergency defensive override
- actual engage-send failure conditions outside action-state

## Wait-longer rejection relationship

- T3.4n intentionally lets explicit attack-on attempt earlier and more consistently.
- If the game still refuses that attempt due to true animation lockout, the existing raw action message id `94` path continues to drive bounded retry handling.
- No new text fallback or ownership reroute was added.

## Timeline additions

- `ENGAGE_ACTION_STATE_BYPASS`
- bypass `kind` now reports:
  - `weaponskill`
  - `job_ability`
  - `spell`
  - `post_spell_tail`
  - `cooldown`
- bypass logs now also include:
  - `tid`
  - `name`
  - `status`
  - `retry_in_s`
  - `retry_count`
  - `dispatch_method`
- engage holds now log exact remaining legitimate blockers such as:
  - `pending_engage_retry_wait`
  - `BLOCK_PLAYER_DEAD`
  - `BLOCK_INVALID_TARGET`
  - `BLOCK_ALREADY_ENGAGED`

## Risks

- Explicit attack-on can now be attempted earlier against WS/JA/spell/post-tail/cooldown state; that is intentional.
- Engage debounce from T3.4l remains the anti-spam guardrail.
- Retry cadence from T3.4j/T3.4l still prevents every-tick spam.
- No ownership policy or side-effect routing changed.

## Rollback note

- Revert the explicit engage action-state gate in `uc_scheduler_action_state.lua` and the engage-path call ordering in `unified_scheduler.lua`.
- Revert `tests/replay/harness/selftest_engage_action_state_bypass.lua` and the related replay selftest/doc updates.

## Field-test instructions

1. Set `_G.UC_DEBUG_ACTION_TIMELINE = true`.
2. Reproduce a next-target transition where tank engage previously waited on stale WS/JA/spell state.
3. Confirm `TARGET_SELECTED` is followed by prompt `ENGAGE_DISPATCH_ATTEMPT` / `ENGAGE_DISPATCHED` without repeated `ENGAGE_DISPATCH_BLOCKED` from stale WS/JA state.
4. Confirm `ENGAGE_ACTION_STATE_BYPASS` logs one of `weaponskill`, `job_ability`, `spell`, `post_spell_tail`, or `cooldown` when explicit engage bypasses stale local action-state.
5. If the game still rejects the engage because it is too soon, confirm the existing `PENDING_ENGAGE_REJECTED_WAIT_LONGER` / `PENDING_ENGAGE_RETRY_READY` flow remains intact and bounded.
6. Confirm non-critical Cure, maintenance, and Sleep still stay behind pending engage, while critical Cure can still override.
7. Confirm dead-player, invalid-target, and already-engaged cases now log their explicit blocker reason without changing ownership routing.
