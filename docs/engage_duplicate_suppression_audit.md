# T3.4l — Engage duplicate suppression audit

## Current purpose of duplicate suppression

- The older engage duplicate gate came from the scheduler's generic proposal duplicate suppression.
- It was protecting the scheduler from repeated proposal spam, but it was not aware that the actual engage dispatch path is an explicit `attack_on` send rather than a console attack toggle.
- After T3.4j/T3.4k, that generic multi-second duplicate window could still outlive the bounded pending-engage retry cadence and delay legitimate engage retries while `status ~= 1`.

## Actual engage dispatch method

- Scheduler engage dispatch still calls `uc_attack.engage_target(expected_tid)` in `unified_scheduler.lua`.
- The timeline labels that dispatch as `command=attack_on`.
- The scheduler engage path is not routed through `uc_scheduler_command_ownership.lua`.
- The scheduler engage path is not routed through `uc_scheduler_dispatcher.lua`.

## Toggle-risk fallback audit

- No scheduler-side console `/attack`, `input /attack`, or command-ownership fallback path was found for the current engage dispatch seam.
- That means the live scheduler engage route is the explicit `attack_on` helper path, not a toggle-risk console command.
- Because there is no current toggle-risk fallback in this seam, the hotfix does not add or promote any new fallback behavior.

## Old suppression behavior

- Engage proposals used the generic duplicate key `engage:<target_id>`.
- Generic duplicate suppression could reject repeated engage proposals long enough to create a visible gap after `ENGAGE_PROPOSED`, even while the player was still not engaged.
- Pending-engage retry logic already existed for message id `94`, but stale generic duplicate suppression could still block a timely retry dispatch.

## New suppression behavior

- Explicit `attack_on` engage proposals now bypass the old generic duplicate lockout while `status ~= 1`.
- The scheduler now owns a dedicated engage retry debounce record for the explicit attack-on path only.
- That record is refreshed only after a successful engage send.
- The new engage duplicate gate is still rate-limited, but only by a short bounded retry cadence instead of a multi-second generic duplicate window.

## Retry cadence

- Explicit attack-on retry debounce: `0.30s`
- Pending-engage wait-longer retry delay: `0.40s`
- Effective behavior:
  - normal explicit retries can reopen after `0.30s` while still not engaged
  - wait-longer rejection still holds retries until the existing `0.40s` pending-engage retry-ready timestamp
  - retries are never reopened every scheduler tick

## Reset conditions

- Explicit engage duplicate state is cleared or bypassed on:
  - target change
  - wait-longer rejection (`message_id = 94`)
  - pending-engage confirmation (`status=1`)
  - pending-engage timeout
  - pending target invalidation
  - critical Cure override clearing the pending-engage hold
  - retry-ready reopening when stale short debounce would otherwise outlive the pending retry gate

## Timeline logging fields and events

- `ENGAGE_DUPLICATE_SUPPRESSED` now includes:
  - `tid`
  - `name`
  - `reason`
  - `status`
  - `dispatch_method`
  - `age_s`
  - `remaining_s`
  - `pending_engage`
  - `sent_for_target`
- Added engage-duplicate diagnostic events:
  - `ENGAGE_DUPLICATE_ALLOWED_RETRY`
  - `ENGAGE_DUPLICATE_RESET_TARGET_CHANGE`
  - `ENGAGE_DUPLICATE_RESET_REJECTION`

## Risks

- Explicit attack-on retries are now more willing to resend while not engaged; that is intentional and bounded.
- This change assumes the current engage seam remains the explicit `uc_attack.engage_target(...)` path.
- No ownership promotion, dispatcher rerouting, or command-toggle fallback was added.

## Rollback note

- Revert the engage-specific duplicate retry helpers and timeline additions in `unified_scheduler.lua`.
- Revert `tests/replay/harness/selftest_engage_duplicate_suppression.lua` and the related replay selftest updates.

## Relationship to pending engage

- T3.4j/T3.4k pending-engage behavior remains intact:
  - non-critical Cure / maintenance / Sleep are still blocked during pending engage
  - critical Cure still overrides
  - wait-longer rejection still uses the bounded pending retry window
- This hotfix only removes the stale generic duplicate lockout that sat on top of that existing engage-retry flow.
- T3.4m separately addresses stale pre-send action-state holding the first explicit `attack_on` attempt; see `docs/engage_action_state_bypass_audit.md`.

## Field-test instructions

1. Set `_G.UC_DEBUG_ACTION_TIMELINE = true`.
2. Fight a target where engage sometimes needs one or more retries before `status=1`.
3. Confirm `ENGAGE_DISPATCHED` is still followed by `PENDING_ENGAGE_*` behavior from the earlier slices.
4. Confirm repeated engage attempts now reopen roughly every `0.30s` while still not engaged, instead of waiting several seconds on `ENGAGE_DUPLICATE_SUPPRESSED`.
5. Force a wait-longer rejection and confirm:
   - `PENDING_ENGAGE_REJECTED_WAIT_LONGER`
   - `ENGAGE_DUPLICATE_RESET_REJECTION`
   - `PENDING_ENGAGE_RETRY_READY`
   - a new engage retry after the bounded retry window
6. Change targets mid-flow and confirm `ENGAGE_DUPLICATE_RESET_TARGET_CHANGE` appears and the new target can engage immediately.
7. Confirm non-critical Cure / maintenance / Sleep still do not dispatch during pending engage, and critical Cure still can.
