# Cure Cast Movement-Stop Audit

> Historical defect audit. The direct defensive fallback described here was
> removed by Phase 5/6; use `scheduler_responsibility_map.md` for current
> ownership.

## Observed Field Behavior

- Character begins initial approach toward a mob.
- A Cure spell is attempted while the character is still moving.
- Movement does not stop/lock as if the Cure were a movement-stopping spell cast.
- The character continues moving and can run through/past the mob during or immediately after the Cure cast attempt.

## Corrected Context

- This bug is **not** the scheduler tank-enmity spell path.
- The observed spell was a **Cure spell**.
- The audit focus is therefore defensive/support Cure casting during movement, not tank spell dispatch.

## Cure-Capable Path Inventory

### 1. Scheduler internal defensive Cure path

Source:

- proposal creation: `unified_scheduler.lua:2400`
- direct non-ranked dispatch: `unified_scheduler.lua:2228`
- ranked scheduler dispatch: `unified_scheduler.lua:4648`

Decision point:

- `build_defensive_candidates()` creates Cure candidates from party members in cast range with missing HP.
- `choose_defensive_action(...)` can select a Cure action.
- `p1_collect_defensive_internal(...)` emits a proposal with `provider='defensive_internal'`, `action_type='spell'`, `movement_policy='must_stop'`, and a legacy Cure command.
- `try_internal_defensive_action()` is the non-ranked direct defensive sender used outside scheduler dark-launch ranked proposal dispatch.

Command send:

- `try_internal_defensive_action()` builds `cmd` and sends it through `uc_scheduler_command_ownership.apply_command_ownership(...)` / `windower.send_command` at `unified_scheduler.lua:2300`.
- ranked `provider == 'defensive_internal'` dispatch does the same at `unified_scheduler.lua:4700`.

Movement-stop / movement-lock behavior:

- No `run_stop` is issued before the Cure command.
- No `_G.UC_MOVEMENT_OWNER` is set or refreshed before/after the Cure command.
- No `_G.UC_MOVEMENT_LOCK_UNTIL` is set or refreshed before/after the Cure command.
- No scheduler-local spell wait/cast state is created for defensive Cure sends.
- Only `action_mark_sent(...)` runs after the command send; that affects scheduler action pacing, not locomotion ownership.

Defer guards:

- Both paths defer only when `action_kind == 'spell'`, the player is **out of combat**, and either:
  - `_G.UC_PREENGAGE_APPROACH_ACTIVE == true`, or
  - follow catch-up/run state is active.
- If the player is already combat-status engaged or otherwise not in the out-of-combat gate, these defers do not apply.

Risk:

- Once Cure is sent, follow/path/core movement can resume immediately because no ongoing locomotion lock exists.

Ownership classification:

- **Scheduler-owned** Cure decision and command send.
- **Mixed movement consequences**, because the scheduler does not own the resulting cast-time stop/lock lifecycle.

### 2. Scheduler healbot defensive Cure path

Source:

- proposal creation: `unified_scheduler.lua:2471`
- ranked dispatch wrapper: `unified_scheduler.lua:4737`
- non-ranked delegate wrapper: `unified_scheduler.lua:2188`

Decision point:

- `p1_collect_defensive_healbot(...)` accepts a healbot action from `_G.actions.get_defensive_action()`.
- Cure can reach this path when healbot returns `type='cure'`.

Command send:

- Scheduler itself does **not** build/send a Cure command here.
- It delegates to `_G.healer:take_action(...)`.

Movement-stop / movement-lock behavior in audited wrapper:

- No scheduler `run_stop` before delegating to healbot.
- No scheduler movement ownership/lock set before or after delegating to healbot.
- No scheduler spell wait state created.
- Whether healbot itself stops movement is outside the audited files.

Ownership classification:

- **Mixed / opaque**.
- Scheduler wrapper does not provide cast-time movement stop/lock.
- Underlying stop behavior depends on external healbot implementation not audited here.

### 3. Core defensive internal Cure path

Source:

- top-level direct defensive provider dispatch: `unified_scheduler.lua:4877`
- direct sender: `unified_scheduler.lua:2228`

Decision point:

- When the addon is running the non-ranked defensive provider path, `try_internal_defensive_action()` can choose and send Cure directly.

Command send:

- Same Cure command send path as the scheduler internal defensive direct path.

Movement-stop / movement-lock behavior:

- Same as above: no `run_stop`, no movement owner/lock refresh, no cast wait state.

Ownership classification:

- Although this occurs outside ranked proposal dispatch, the implementation still lives in `unified_scheduler.lua`.
- Best classified as **scheduler-side direct defensive logic**, not combat-core spell handling.

### 4. Scheduler combat spell path

Source:

- `unified_scheduler.lua:4332` onward

Audit result:

- This path is built for combat spell target/self command sends.
- It includes generic spell settle/prep stop behavior and the final spell command send helper.
- Current proposal collectors route Cure through `defensive_internal` or `defensive_healbot`, not `provider='combat'`.
- No evidence in the audited collectors shows Cure being emitted into the combat spell proposal family today.

Movement behavior:

- Generic combat spell path does issue `run_stop` for settle/prep windows.
- Tank spell subpath now also maintains a bounded wait lock after send.
- This path is **not** the most likely source of the observed Cure issue.

### 5. Core pull/combat spell paths used for comparison

#### Core pull spell path

Source:

- `unified_combat_core.lua:1968`

What it does correctly:

- Issues `windower.ffxi.run(false)` before spell send.
- Calls `set_movement_owner('core', 0.5)` during precast halt.
- Sets `_G.UC_MOVE_FREEZE_PREP_UNTIL`.
- After send, creates:
  - `core.pull_spell_waiting = true`
  - `core.pull_spell_wait_until = now + 8.0`
  - `_G.UC_PULL_SPELL_WAITING = true`
  - `_G.UC_PULL_SPELL_WAIT_UNTIL = ...`
  - `_G.UC_PULL_CAST_HOLD_UNTIL = now + 1.0`
  - `_G.UC_COMBAT_INTENT_UNTIL = ...`
  - `_G.UC_PULL_APPROACH_UNTIL = ...`

Why it works:

- It is not stop-once only.
- It establishes both pre-send stop and post-send wait/lock state that movement consumers honor.

#### Core tank spell path

Source:

- `unified_combat_core.lua:1791`
- `unified_combat_core.lua:3220`

What it does correctly:

- Issues `run(false)` before send.
- Creates `tank_spell_waiting` state after send.
- Refreshes movement ownership while waiting via `set_movement_owner('core', 0.6)`.

Why it works:

- It maintains cast-time movement suppression until completion or timeout.

## Movement Consumer Audit

### `uc_pathing.lua`

Relevant checks:

- `uc_pathing.lua:794`
- `uc_pathing.lua:810`
- `uc_pathing.lua:837`

Observed behavior:

- Path-follow pauses when `_G.UC_MOVEMENT_OWNER ~= 'none'` and `now < _G.UC_MOVEMENT_LOCK_UNTIL`.
- It also pauses for:
  - combat-transition suppression from `uc_party_follow.should_suppress_follow_or_path_return_now(...)`
  - `_G.UC_PULL_CAST_HOLD_UNTIL`
  - `_G.UC_PREENGAGE_APPROACH_ACTIVE`
  - `_G.UC_PULL_SPELL_WAITING`

Implication:

- Pathing already knows how to yield to cast-time movement locks/waits.
- Defensive Cure paths simply do not populate those locks/waits.

### `uc_party_follow.lua`

Relevant checks:

- `uc_party_follow.lua:684`
- `uc_party_follow.lua:746`

Observed behavior:

- Follow suppresses for:
  - combat-transition arbitration
  - `_G.UC_MOVE_FREEZE_PREP_UNTIL`
  - `_G.UC_MOVEMENT_MODE == 'CAST_FREEZE'`
  - `_G.UC_PULL_SPELL_WAITING`
- Follow also respects `_G.UC_MOVEMENT_OWNER == 'core'` lock windows in arbitration.

Implication:

- Follow likewise already honors explicit cast-time suppressors.
- Defensive Cure paths do not set equivalent state.

## Comparison Summary

### Successful spell paths already do one or more of:

- `run_stop` before send
- set `_G.UC_MOVEMENT_OWNER`
- refresh `_G.UC_MOVEMENT_LOCK_UNTIL`
- create a spell wait state until action completion or timeout
- create a prep/freeze/hold window that path/follow explicitly respects

### Defensive Cure paths currently do:

- send Cure command
- mark scheduler action sent
- **do not** stop movement
- **do not** create movement ownership
- **do not** create movement lock
- **do not** create cast wait state

## Most Likely Source

The most likely source is the **scheduler-side defensive Cure path** in `unified_scheduler.lua`, specifically:

- `try_internal_defensive_action()` for direct defensive sends
- `provider == 'defensive_internal'` ranked dispatch

Reason:

- This path clearly can send Cure commands.
- It does so without any pre-send `run_stop`.
- It does so without any post-send movement lock or spell wait state.
- Its only movement avoidance is an out-of-combat defer gate, which does not protect engaged / initial-combat approach scenarios.

Secondary contributor:

- The scheduler healbot wrapper also provides no stop/lock lifecycle of its own, so if Cure came from healbot the wrapper would have the same structural gap.

## Likely Ownership Classification

- **Primary source:** scheduler-owned defensive Cure dispatch with mixed movement consequences.
- Not primarily a combat-core tank spell issue.
- Not primarily the generic scheduler combat spell family.
- Potentially mixed if the real field case was healbot-driven, but even then the scheduler wrapper lacks any protective movement-stop lifecycle.

## Narrowest Safe Future Fix

Recommended slice:

1. Add a bounded spell-cast movement stop/lock lifecycle at the **defensive Cure/spell send point** in `unified_scheduler.lua`.
2. Cover both:
   - `try_internal_defensive_action()`
   - ranked `provider == 'defensive_internal'`
3. Prefer reusing existing movement-lock primitives already honored by path/follow:
   - `_G.UC_MOVEMENT_OWNER`
   - `_G.UC_MOVEMENT_LOCK_UNTIL`
   - possibly an existing spell wait/freeze signal if a safe shared defensive spell pattern exists
4. Keep it bounded and spell-only.
5. Do **not** change ownership promotion policy as part of the fix.

Smallest plausible implementation shape:

- On defensive spell send:
  - issue `run(false)` once before send,
  - set short spell-cast movement ownership/lock,
  - maintain a bounded defensive spell wait state until action completion / timeout similar in spirit to pull/tank spell handling.

## Paths That Should Not Be Changed First

- Tank spell ownership / tank run-stop promotion paths.
- Generic combat spell ownership policy.
- Movement arbitration behavior from T2.8x.
- Alliance target-scope behavior.
- Zero-HP/death-animation target-validity behavior.

## Risks

- Over-holding follow/path movement after Cure completes if release conditions are too loose.
- Accidentally affecting non-spell defensive actions if the fix is not spell-scoped.
- Introducing duplicate stop behavior if applied both in a sender helper and a caller.
- Healbot path may need separate treatment if underlying healbot casting bypasses the same send point.

## Proposed Tests

- Defensive internal Cure send while engaged/approaching:
  - stop occurs before Cure command
  - movement lock exists during spell cast window
  - movement resumes after expiry/completion
- Defensive internal buff/debuff spell path:
  - same movement-stop lifecycle if the fix is intentionally all defensive spells
- Defensive JA path:
  - unchanged, no spell lock accidentally added
- Healbot wrapper:
  - determine whether wrapper-level protection is needed or whether healbot already owns spell stop/lock

## Proposed Field-Test Plan

1. Reproduce initial mob approach with defensive Cure enabled.
2. Confirm which provider is active:
   - `internal`
   - `healbot`
3. If internal:
   - verify Cure no longer sends while movement continues through the mob
   - verify follow/path resumes after Cure completes
4. If healbot:
   - capture whether Cure came from the healbot wrapper or underlying healer logic
5. Confirm no regression to:
   - normal combat approach
   - follow return
   - defensive JA behavior

## T3.1f Bugfix Summary

- `unified_scheduler.lua` now patches the scheduler defensive spell/Cure send lifecycle at the actual send points.
- Patched send paths:
  - direct internal defensive sender from `try_internal_defensive_action()`
  - ranked `provider == 'defensive_internal'` dispatch
- The fix now:
  - issues a stop through the existing scheduler-safe `uc_scheduler_run_stop_ownership` seam with `ownership_enabled = false`
  - sets `_G.UC_MOVEMENT_OWNER = 'scheduler'`
  - sets/refreshed `_G.UC_MOVEMENT_LOCK_UNTIL` with a bounded short window
  - creates a scheduler-local defensive spell wait state after send
  - refreshes that lock on later scheduler ticks while the spell action is still active / in immediate cooldown
  - releases naturally when the spell finishes, cooldown clears, or the bounded timeout expires

## Healbot Wrapper Finding After Patch

- No additional healbot runtime patch was added in T3.1f.
- The scheduler healbot wrapper still delegates into `_G.healer:take_action(...)` rather than sending the Cure command through the same internal defensive send point.
- That means:
  - internal defensive Cure now has an explicit scheduler-owned stop/lock lifecycle
  - healbot behavior remains opaque and should be field-verified separately if Cure movement-through persists while `defensive_provider = 'healbot'`

## Field-Test Instructions After Patch

1. Set defensive provider to `internal`.
2. Reproduce the original initial-approach Cure scenario.
3. Confirm:
   - Cure stops movement before/during cast
   - character does not run through/past the mob during the Cure cast
   - movement resumes after the Cure cast window ends
4. Recheck:
   - defensive JA behavior remains unchanged
   - normal follow/path return resumes after the Cure completes
5. If the same symptom appears with `defensive_provider = 'healbot'`, capture that separately because the healbot delegate path was not broadly rewritten in T3.1f.
