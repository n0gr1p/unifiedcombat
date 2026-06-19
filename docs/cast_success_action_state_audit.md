# T3.1l — Spell Cast Start/Success Handling Audit

## Scope

This audit covers the incoming spell-cast lifecycle messages:

- `<player> starts casting <spell> on <target>`
- `<player> casts <spell>`
- `<player> casts <spell> on <target>`

The goal is to document how current runtime code updates scheduler action-state, defensive spell wait state, movement lock state, and retry/reselection timing when a spell starts and when a spell completes successfully.

No runtime behavior changed in this task.

## T3.1m implementation summary

T3.1m implemented a narrow local-player scheduler defensive spell success bridge.

Current success bridge behavior:

- Uses only parsed local-player `0x029` action messages
- Treats only known spell-success ids as success:
  - `2`, `236`, `237`, `252`, `268`, `271`
- Excludes known spell-init ids:
  - `3`, `43`, `326`, `327`, `675`, `716`
- Clears scheduler defensive spell wait promptly on confirmed local-player defensive spell success
- Shortens local defensive spell action-state to a bounded `0.2` second post-cast tail
- Shortens only scheduler-owned movement lock to a bounded `0.2` second tail
- Leaves unrelated JA/WS/core state unchanged

T3.1m also removed `spell_finish` from the scheduler start-marker bucket.
That review concluded `spell_finish` is not a true cast-start signal for scheduler action-state, and treating it as one could refresh `action_start` immediately before the success message path.

## Incoming handlers found

### `UnifiedCombat.lua`

Two incoming feeds matter here:

1. `ActionPacket.open_listener(...)`
   - Forwards parsed action packets to:
     - `UC_COMBAT_CORE.on_action(act)`
     - `_G.UC_SCHED_OnAction(act)`
2. `windower.register_event('incoming chunk', ...)`
   - For raw `0x029` action-message packets, parses a small message table and forwards it to:
     - `UC_COMBAT_CORE.on_action_message(msg)`
     - `_G.UC_SCHED_OnActionMessage(msg)`

This means the addon currently uses:

- `0x028`/action packet listener style data for action-category lifecycle
- `0x029` action-message data for start/success/failure style messages

## Known spell message-id buckets

`unified_combat_core.lua` defines the shared message-id buckets currently reused by the scheduler:

- Spell initiating ids:
  - `3`, `43`, `326`, `327`, `675`, `716`
- Spell success ids:
  - `2`, `236`, `237`, `252`, `268`, `271`

`unified_scheduler.lua` exposes helper checks that use the same buckets:

- `scheduler.is_spell_initiating_message_id(message_id)`
- `scheduler.is_spell_success_message_id(message_id)`

## Current spell-start handling

### Local-player spell start in scheduler

`unified_scheduler.lua:scheduler.on_action(act)` is the first scheduler-side start hook.

Current behavior:

- It computes an action category from the parsed action packet.
- For the local player only (`actor_id == my_id`), it calls `action_mark_packet_start()` when the category is one of:
  - `spell`
  - `spell_finish`
  - `job_ability`
  - `job_ability_unblinkable`
  - `weaponskill`
  - `weapon_skill`
  - `ranged_attack`
  - `item`

Scheduler effect of spell start:

- `action_mark_packet_start()` sets `action_start = now`
- `action_end` is not changed there
- `action_is_acting()` therefore sees `action_end < action_start` and treats the scheduler as actively acting until a matching end signal or timeout arrives

Updated review result:

- Before T3.1m, `spell_finish` was included in the same scheduler start bucket as `spell`
- T3.1m removed `spell_finish` from that scheduler start bucket
- Current result: only actual action-start categories refresh scheduler start-state, while spell completion is left to the success/message-end path

### Local-player spell start in scheduler defensive spell wait

Scheduler defensive spell wait is not created by the incoming start message itself.
It is created earlier when the scheduler decides to cast a defensive spell:

- `begin_defensive_spell_wait(action_name, target_id, at)` sets:
  - `defensive_spell_waiting = true`
  - `defensive_spell_wait_until = now + 8.0`
  - pending action/target metadata

Once active, `refresh_defensive_spell_wait_lock(at)` keeps the wait alive while:

- `last_send_kind == 'spell'`, and
- either `action_is_acting()` is still true, or cooldown has not yet expired

While that wait is active it also keeps movement locked by forcing:

- `_G.UC_MOVEMENT_OWNER = 'scheduler'`
- `_G.UC_MOVEMENT_LOCK_UNTIL = min(wait_until, now + 0.6)`

### Start-message handling in core pull/tank spell waits

`unified_combat_core.lua:core.on_action_message(msg)` explicitly recognizes spell-init messages for pull/tank spell waits.

For local-player pull/tank spell waits, if actor and target match the pending spell:

- initiating ids keep the wait active
- status/diagnostic fields are refreshed to waiting state

That is a more explicit start-message interpretation than the scheduler defensive spell wait currently has.

### Other-player spell start

No scheduler action-state or defensive spell wait is updated for other players' spell-start messages.

Current scheduler start logic is local-player scoped through `actor_id == my_id`.
Core pull/tank wait logic is also local-player scoped through `aid == my_id`.

## Current spell-success handling

### Local-player spell success in scheduler action-state

`scheduler.on_action_message(msg)` currently handles local-player success through a broad actor-centric rule:

- if `actor_id == my_id` and `message_id ~= 0`, it always calls `action_mark_packet_end()`

Effect:

- `action_end = now`
- `action_is_acting()` stops reporting active once it next evaluates with `action_end >= action_start`
- when that transition is observed, `action_is_acting()` adds the generic post-action tail:
  - `action_delay = 0.5`
  - `last_action = now`
  - `cooldown_until = max(cooldown_until, now + 0.5)`

This success handling is:

- local-player scoped
- not success-specific for generic action-state
- not target-aware for generic action-state
- shared with many non-zero self action messages, not just spell completion

### Local-player spell success in scheduler defensive spell wait

T3.1m added a success-specific scheduler defensive spell wait clear in `scheduler.on_action_message(msg)`.

Current explicit spell classification branches are:

- success bridge:
  - if defensive spell wait is active
  - pending target matches when present
  - message id is a known spell-success id
  - scheduler clears local defensive spell success state immediately
  - scheduler clears defensive spell wait immediately
  - scheduler shortens only scheduler-owned movement lock to a bounded `0.2` tail
- if defensive spell wait is active
- and the message is neither initiating nor success
- then scheduler clears defensive spell wait/action-state immediately

Current success lifecycle for scheduler defensive spells is:

1. self success message sets `action_end`
2. success bridge verifies defensive spell provider/scope
3. local defensive spell action-state is shortened to a bounded `0.2` cooldown tail
4. scheduler defensive spell wait is cleared immediately
5. scheduler-owned movement lock is shortened to a bounded `0.2` tail
6. follow/path/retry/reselection can release promptly after that bounded tail

### Movement lock behavior on spell success

After T3.1m:

- scheduler defensive spell success no longer leaves defensive spell wait active to keep refreshing movement lock
- if `_G.UC_MOVEMENT_OWNER == 'scheduler'`, remaining movement lock is shortened to `min(current_lock_until, now + 0.2)`
- movement locks owned by unrelated systems are not touched

This now matches the bounded-tail style already used by the T3.1k interruption path.

### Local-player spell success in core pull/tank waits

Core pull/tank spell waits are more explicit on success.

`core.on_action_message(msg)`:

- if the message is a known success id and actor/target match local pending pull spell, it immediately clears pull spell wait
- if the message is a known success id and actor/target match local pending tank spell, it immediately clears tank spell wait

`core.on_action(act)` also has a second success-style path:

- when the local player gets `category == 'spell_finish'`
- and pull/tank spell wait is active
- it matches pending target/name and clears the wait immediately

So core pull/tank spell success handling is both:

- more explicit than scheduler defensive spell success handling
- more target/name aware than generic scheduler action-state end handling

### Other-player spell success

Scheduler generic action-state is not affected by other players' success messages because the broad end hook is gated by `actor_id == my_id`.

Core pull/tank spell waits also ignore other-player success messages because they require `aid == my_id`.

No scheduler defensive spell wait or movement lock is updated from other-player spell success.

## Defensive Cure vs offensive/combat spell success

Within scheduler action-state, both defensive Cure success and offensive spell success currently use the same broad local-self `message_id ~= 0` end rule.

The difference is in surrounding wait systems:

- scheduler defensive Cure path can leave `defensive_spell_waiting` alive until post-cast cooldown expiry
- generic offensive/combat spell flows do not use that same scheduler defensive spell wait path
- core pull/tank spell paths have their own success-specific clearing logic

So defensive Cure success and offensive spell success share the same generic packet-end marker, but they do **not** share the same surrounding wait-release behavior.

## Retry/reselection timing implications

Current success handling affects retry/reselection timing in two different ways:

1. Generic scheduler action-state
   - success ends active acting state
   - then imposes the normal `0.5` second cooldown tail before action blocking fully releases
2. Scheduler defensive spell wait
   - because success does not clear the wait immediately, retry/reselection stays blocked until the next `refresh_defensive_spell_wait_lock()` pass sees both:
     - not acting
     - cooldown expired

This means success handling can lag behind the packet evidence even though a success message already arrived.

By comparison, T3.1k interruption handling now short-circuits much earlier for the narrow defensive-spell interruption case.

## Comparison against T3.1k interruption handling

T3.1k introduced a narrow local-player scheduler defensive spell interruption bridge.

Interruption/failure path now does all of the following immediately:

- classifies the message as not init and not success
- clears local defensive spell action-state through `clear_local_defensive_spell_interruption()`
- clears `defensive_spell_waiting`
- shortens only scheduler-owned movement lock to a brief tail
- completes pending state with interruption-specific reason text

Success path now mirrors that precision much more closely.

Current contrast:

- interruption: explicit, narrow, target-aware when pending target exists
- success: explicit, narrow, target-aware when pending target exists, with bounded local action-state and movement-lock shortening

Interruption and success are now aligned in shape for the local-player scheduler defensive spell path.

## Current gaps and likely bugs

### Remaining gaps

1. Generic scheduler action-state end handling is still broad for all non-zero local self action messages.
2. Core and scheduler spell waits still use separate implementations, even though their success behavior is now more aligned.
3. The generic packet-end path remains non-target-aware by design outside the narrow defensive spell success/interruption bridges.

### `spell_finish` review result

- T3.1m removed `spell_finish` from `scheduler.on_action(act)` start-lock categories
- reason: completion is not a start signal, and leaving it in the start bucket could refresh `action_start` immediately before success-message handling
- result: scheduler action-state now treats spell completion solely through the end/success path, which is easier to reason about and safer for bounded release

## Narrowest recommended future implementation

Implemented slice:

1. Added a local-player success-only bridge in `scheduler.on_action_message(msg)` for scheduler defensive spells.
2. Scoped it to known spell-success ids.
3. Required the current pending target to match when one exists.
4. Cleared scheduler defensive spell wait immediately on success.
5. Preserved only a bounded `0.2` second post-cast action/movement tail.
6. Did not clear JA/WS state.
7. Did not touch unrelated movement locks or ownership policy.

That would make scheduler defensive spell success handling match the new interruption bridge more closely without broadening behavior across unrelated action families.

## Proposed replay/mock coverage

Current coverage added in T3.1m:

1. Local-player defensive spell success helper exists and is bounded.
2. Success helper does not clear JA state.
3. Success helper does not clear WS state.
4. Success helper does not clear unrelated combat spell state.
5. Timeout fallback remains available.
6. Aggregate replay suite includes the new success selftest.

## Proposed field-test plan

Field-test with:

1. Defensive Cure cast while movement-maintenance/follow behavior is active.
2. Confirm cast start still stops/holds correctly.
3. Confirm successful cast releases scheduler spell wait promptly.
4. Confirm follow/path resumes after only the bounded short post-cast tail rather than the previous longer poll-based release.
5. Confirm interruption behavior from T3.1k still releases correctly.
6. Confirm offensive spell and JA/WS behavior remain unchanged.

## State intentionally not cleared on success

T3.1m success handling intentionally does **not** clear:

- JA state
- WS state
- another player's action-state
- core pull/tank spell waits
- movement locks owned by unrelated systems

## Risks and rollback note

Main risk:

- the bounded `0.2` tail could still be slightly too short or too long in live use for some defensive spell sequences

Rollback note:

- revert the T3.1m success bridge in `scheduler.on_action_message(msg)`
- restore previous scheduler defensive spell success behavior if a regression is found
- keep T3.1k interruption handling intact unless the regression proves both paths need a shared redesign
