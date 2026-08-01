# T3.4j — Pending engage confirmation guard audit

## Field-log summary

- T3.4g restored prompt next-target selection.
- T3.4h made engage win over non-critical ranked proposals.
- T3.4i added the timeline needed to see the remaining gap.
- The remaining issue was after `ENGAGE_DISPATCHED`: `/attack on` could be sent, but `STATUS_CHANGED status=1` could lag for seconds while non-critical actions still consumed scheduler action economy.
- Post-T3.4j logs also showed two narrower residual gaps:
  - an old combat-target spell lock could still survive target death / status drop / target transition and delay the next engage through `BLOCK_POST_SPELL_TAIL`
  - pending-engage timeout was still anchored too heavily to the first attempt, so a retry could be followed by timeout just before `status=1`

## Root cause

- `ENGAGE_DISPATCHED` only proved the addon sent the engage attempt; it did not prove the game accepted it.
- The game can reject that attempt with action message id `94` / `You must wait longer to perform that action.` during action-lock or animation-tail windows.
- The scheduler had no pending-engage confirmation state between engage send and actual `status=1`.
- The observed `BLOCK_POST_SPELL_TAIL` duration looked longer than the intended `0.2s` because the end marker was only emitted once engage selection re-entered the action-state path; the new tail logging now reports the bounded tail duration directly.

## Detection used

- Wait-longer rejection is detected from raw action message id `94`.
- Confirmed engage is still detected from player `status=1`.
- Direct command-path engage failure is still detected from `uc_attack.engage_target(...) == false`.
- No raw English chat-text fallback was added.

## Pending-engage behavior

- A successful `attack_on` send now starts scheduler-owned pending engage state with:
  - target id
  - target name
  - start timestamp
  - bounded timeout
  - bounded retry-ready timestamp
- Pending engage stays active until one of:
  - `status=1`
  - message id `94` rejection plus bounded retry window
  - target invalid / dead / stale
  - timeout
  - critical Cure override
- Each engage retry attempt now refreshes `last_attempt_at` and extends the confirmation timeout from that latest attempt instead of only the initial `ENGAGE_DISPATCHED`.

## Retry behavior

- Pending engage timeout: `1.75s`
- Wait-longer retry delay: `0.40s`
- Repeated wait-longer rejections stay rate-limited by the retry-ready timestamp and the overall timeout ceiling.
- Retry readiness remains bounded, and the timeout window is now refreshed from the latest retry attempt.
- `PENDING_ENGAGE_TIMEOUT` now logs `age_s` from the most recent engage attempt plus `retry_count`.

## Stale combat-spell lock release

- A narrow target-aware stale release now applies only to old combat spells that targeted a mob.
- It does **not** clear:
  - actual in-progress casts
  - self-buffs
  - defensive Cure / defensive support spells
  - JA state
  - WS state
- It **can** clear old combat spell cooldown/tail when:
  - the old mob target is now dead / stale / invalid
  - the player has transitioned to a different valid target
  - the old combat spell is no longer actually casting
- This emits `STALE_SPELL_LOCK_RELEASE` with the spell, provider, old target id, new target id, and reason.

## Actions blocked during pending engage / retry

- non-critical Cure
- maintenance / self-buffs
- Sleep
- routine combat spells
- routine tank setup / enmity actions
- legacy defensive fallback actions when they are not critical

## Actions still allowed

- target acquisition
- packet / status handling
- cleanup on invalid or timed-out pending state
- critical Cure overrides
- engage retry once the bounded retry delay expires

## Post-spell tail audit / fix

- The bounded post-spell tail remains `0.2s`.
- `uc_scheduler_action_state.lua` now stores the explicit tail window and emits `tail_s` on `POST_SPELL_TAIL_END`.
- This keeps field logs aligned with the real bounded tail instead of making the gap look as long as the next engage-selection revisit.

## Timeline additions

- `PENDING_ENGAGE_START`
- `PENDING_ENGAGE_CONFIRMED`
- `PENDING_ENGAGE_TIMEOUT`
- `PENDING_ENGAGE_REJECTED_WAIT_LONGER`
- `PENDING_ENGAGE_RETRY_READY`
- `PENDING_ENGAGE_RETRY_ATTEMPT`
- `PENDING_ENGAGE_CLEARED_INVALID_TARGET`
- `PENDING_ENGAGE_BLOCK_NONCRITICAL`
- `PENDING_ENGAGE_ALLOW_CRITICAL`
- `STALE_SPELL_LOCK_RELEASE`
- `POST_SPELL_TAIL_END` now includes `tail_s`

## Relationship to T3.4g / T3.4h / T3.4i

- T3.4g kept next-target acquisition nonblocking.
- T3.4h kept engage priority above non-critical ranked actions.
- T3.4i made the remaining post-`attack_on` gap visible.
- T3.4j closes that gap by adding pending confirmation, rejection-aware retry, and tighter tail accounting.
- T3.4l separately relaxes the stale generic engage duplicate lockout on top of this flow; see `docs/engage_duplicate_suppression_audit.md`.
- T3.4m separately relaxes stale pre-send action-state blocking for explicit `attack_on`; see `docs/engage_action_state_bypass_audit.md`.

## Risks

- Critical-Cure override still intentionally interrupts pending engage tracking.
- Wait-longer detection assumes the raw action-message id remains `94` for this client resource set.
- This change does not promote any ownership or dispatcher behavior.

## Rollback note

- Revert the pending-engage helpers and gating in `unified_scheduler.lua`, plus the bounded tail reporting in `uc_scheduler_action_state.lua`.

## Field-test instructions

1. Set `_G.UC_DEBUG_ACTION_TIMELINE = true`.
2. Fight a target where a spell or Cure can end immediately before re-engage.
3. Confirm the log now shows:
   - `ENGAGE_DISPATCH_ATTEMPT`
   - `ENGAGE_DISPATCHED`
   - either `PENDING_ENGAGE_CONFIRMED` with `STATUS_CHANGED ... to=1`
   - or `PENDING_ENGAGE_REJECTED_WAIT_LONGER` followed by `PENDING_ENGAGE_RETRY_READY` and `PENDING_ENGAGE_RETRY_ATTEMPT`
4. Confirm non-critical Cure / maintenance / Sleep do not dispatch during pending engage.
5. Confirm critical Cure can still dispatch and clears the pending engage hold.
6. Kill or lose the original spell target, transition onto a new valid target, and confirm `STALE_SPELL_LOCK_RELEASE` appears instead of waiting several seconds on an old combat spell tail.
7. Confirm `PENDING_ENGAGE_TIMEOUT` now reports `age_s` from the latest retry attempt, and retries do not timeout immediately after a fresh retry send.
8. Confirm `POST_SPELL_TAIL_END` now reports the short bounded `tail_s` instead of an inflated gap.
