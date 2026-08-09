# T3.4i — Action economy timeline logging

## Purpose

This is a focused, default-off diagnostic log for proving the order of:

- next-target selection
- engage proposal and dispatch
- status changes into/out of engaged
- Cure / maintenance / Sleep proposal and dispatch
- spell start / success / failure path
- engage-relevant action-state blocking and release

It is intended for side-by-side tank vs DPS field comparison when visual observation is no longer enough.

## How to enable

Set the global flag before field testing:

- `_G.UC_DEBUG_ACTION_TIMELINE = true`

This task does **not** add new slash commands.

## Log file location

The logger writes one per-character file under:

- `data/logs/action_timeline_<character>.log`

Example:

- `data/logs/action_timeline_nyoourke.log`

The file is append-mode and emits a `SESSION_START` marker on first use after load/reload.

## Event codes

### Target

- `TARGET_ACQUIRE_CANDIDATE`
- `TARGET_SELECTED`
- `TARGET_SELECT_SKIPPED_ALREADY_TARGETED`
- `TARGET_SELECT_BLOCKED`
- `TARGET_SELECT_DEBOUNCED`

### Engage

- `ENGAGE_PROPOSED`
- `ENGAGE_PREEMPT_SELECTED`
- `ENGAGE_DISPATCH_ATTEMPT`
- `ENGAGE_DISPATCHED`
- `ENGAGE_DISPATCH_BLOCKED`
- `ENGAGE_DEBOUNCED`
- `ENGAGE_DUPLICATE_SUPPRESSED`

### Status

- `STATUS_CHANGED`

### Defensive / maintenance / Sleep

- `CRITICAL_CURE_PROPOSED`
- `CRITICAL_CURE_DISPATCHED`
- `NONCRITICAL_CURE_PROPOSED`
- `NONCRITICAL_CURE_DISPATCHED`
- `MAINT_BUFF_PROPOSED`
- `MAINT_BUFF_DISPATCHED`
- `SLEEP_PROPOSED`
- `SLEEP_DISPATCHED`
- `SLEEP_WAKE_PROPOSED`
- `SLEEP_WAKE_DISPATCHED`

### Spell / action-state

- `SPELL_SENT`
- `SPELL_PACKET_START`
- `SPELL_SUCCESS`
- `SPELL_FAILURE`
- `SPELL_INTERRUPTED`
- `ACTION_STATE_BLOCK_ENGAGE`
- `ACTION_STATE_RELEASE`
- `POST_SPELL_TAIL_START`
- `POST_SPELL_TAIL_END`

## Blocker reason codes

Implemented blocker reasons currently include:

- `BLOCK_CRITICAL_CURE`
- `BLOCK_ACTION_STATE`
- `BLOCK_SPELL_CASTING`
- `BLOCK_POST_SPELL_TAIL`
- `BLOCK_DUPLICATE`
- `BLOCK_DEBOUNCE`
- `BLOCK_INVALID_TARGET`
- `BLOCK_ALREADY_ENGAGED`
- `BLOCK_UNKNOWN`

## Log format

Each line is compact and machine-readable:

- `elapsed_seconds | character | EVENT_CODE | key=value ...`

Examples:

- `0.000 | Nyoourke | SESSION_START | reload=1`
- `12.351 | Nyoourke | TARGET_SELECTED | tid=178945 name=Apex_Bat`
- `12.402 | Nyoourke | ENGAGE_PROPOSED | tid=178945 name=Apex_Bat band=107 urgency=0.85`
- `12.431 | Nyoourke | ENGAGE_DISPATCHED | tid=178945 name=Apex_Bat command=attack_on`
- `12.790 | Nyoourke | STATUS_CHANGED | from=0 to=1 status=1`

## Noise control

The logger is designed to stay small enough for several minutes of field testing:

- no per-tick logging
- no generic rejected-proposal spam
- repeated identical blocker messages are rate-limited
- repeated proposal events are deduped per target/action for short windows

## Field-test procedure

1. Enable `_G.UC_DEBUG_ACTION_TIMELINE = true`.
2. Reload and confirm `SESSION_START` appears in the per-character log.
3. Run the same pull flow on a tank and a DPS character.
4. Compare the order of:
   - `TARGET_SELECTED`
   - `ENGAGE_PROPOSED`
   - `ENGAGE_DISPATCHED`
   - `STATUS_CHANGED` to `status=1`
   - any `NONCRITICAL_CURE_*`, `MAINT_BUFF_*`, or `SLEEP_*` events
5. If engage seems late, look for:
   - `ENGAGE_DISPATCH_BLOCKED`
   - `ACTION_STATE_BLOCK_ENGAGE`
   - `POST_SPELL_TAIL_START`
   - delayed `STATUS_CHANGED`

## How to compare tank vs DPS timelines

Compare the same timeline window after target selection:

- If tank shows `NONCRITICAL_CURE_DISPATCHED` or `MAINT_BUFF_DISPATCHED` before `ENGAGE_DISPATCHED`, routine actions still beat engage.
- If both show `ENGAGE_DISPATCHED` promptly but only tank delays `STATUS_CHANGED status=1`, the scheduler sent engage and the delay is after dispatch.
- If `POST_SPELL_TAIL_START` appears and `ACTION_STATE_RELEASE` / `POST_SPELL_TAIL_END` arrives much later, post-spell lockout is still involved.
- If `ENGAGE_DISPATCH_BLOCKED reason=BLOCK_CRITICAL_CURE`, the delay is the intentional critical Cure exception.

## Proven patterns

Patterns that answer the main questions:

- Was target selected before Cure/buff?
  - compare `TARGET_SELECTED` vs `*_DISPATCHED`
- Was engage proposed before Cure/buff?
  - compare `ENGAGE_PROPOSED` vs `*_DISPATCHED`
- Did engage lose to a blocker?
  - inspect `ENGAGE_DISPATCH_BLOCKED`
- Was engage action-state blocked after a spell?
  - inspect `ACTION_STATE_BLOCK_ENGAGE` + `POST_SPELL_TAIL_START`
- Was engage dispatched but status never became engaged?
  - `ENGAGE_DISPATCHED` without timely `STATUS_CHANGED status=1`

## Disable / rollback

To disable:

- unset or set `_G.UC_DEBUG_ACTION_TIMELINE = false`

Runtime behavior remains unchanged when the flag is off.
