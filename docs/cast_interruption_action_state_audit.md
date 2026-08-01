# Cast Interruption Action-State Audit

## Scope

Audit target:

- exact game message: `<playername>'s casting is interrupted`

Question:

- does UnifiedCombat currently detect this incoming spell interruption outcome
- and if so, does it clear scheduler action state, spell-wait state, or movement locks immediately

Result before T3.1k:

- incoming action traffic was partially wired
- exact cast interruption handling was **not** found
- scheduler action state relied on broad self action-message completion and timeout-based release rather than an interruption-specific path

## Incoming Packet / Message Handlers Found

### `UnifiedCombat.lua`

Incoming event registration:

- `windower.register_event('incoming chunk', ...)` in `UnifiedCombat.lua`

Current forwarding behavior:

- forwards all incoming chunks to `_G.UC_SCHED_OnIncomingChunk(id, data)` if present
- directly parses raw `0x029` action-message bytes and forwards the parsed table to:
  - `UC_COMBAT_CORE.on_action_message(msg)`
  - `_G.UC_SCHED_OnActionMessage(msg)`

No direct raw text matching was found for:

- `casting is interrupted`
- `spell interrupted`
- `unable to cast`

### `unified_scheduler.lua`

Scheduler packet hook:

- `scheduler.on_incoming_chunk(id, data)`

Current packet handling:

- `0x028`: enemy effect tracking from raw action packet bytes
- `0x029`: raw action message parsing, enemy effect cleanup, then `scheduler.on_action_message(msg)`
- `0x063`: status snapshot ingestion

### `unified_combat_core.lua`

Core message hook:

- `core.on_action_message(msg)`

Current message-id buckets found:

- `spell_initiating_message_ids`
- `spell_success_message_ids`
- generic fallback branch used as retry/failure handling for pull/tank spell wait

## What the Repo Currently Detects

### Spell start

Yes.

Two distinct mechanisms exist:

1. `unified_scheduler.lua`
   - `scheduler.on_action(act)` calls `action_mark_packet_start()` when the local player is the actor and the action category matches spell/JA/WS/item start categories.
2. `unified_combat_core.lua`
   - `core.on_action_message(msg)` keeps pull/tank spell wait alive when message ids fall into `spell_initiating_message_ids`

### Spell finish / generic self action completion

Partially yes.

`unified_scheduler.lua`:

- `scheduler.on_action_message(msg)` calls `action_mark_packet_end()` for **any** non-zero action message where:
  - local player is the actor
  - `message_id ~= 0`

This is actor-centric and broad; it is not interruption-specific.

### Spell interruption

Not explicitly.

Findings:

- no exact match for the text `<playername>'s casting is interrupted`
- no explicit interruption message-id table was found
- no branch named or scoped to interruption in scheduler action-state handling
- no interruption-specific release path was found for:
  - scheduler defensive spell wait
  - scheduler tank spell wait
  - scheduler movement owner / movement lock

### Action failure / unable-to-cast style outcomes

Partially, but only in narrow core spell-wait paths.

`unified_combat_core.lua`:

- for pull spell wait and tank spell wait:
  - if local actor/target match and message id is neither a spell-init id nor a spell-success id
  - code falls into a generic `retry` branch
  - that branch clears the **core** pull/tank spell wait state immediately

Important limitation:

- this logic is specific to core pull/tank spell waits
- it is not wired into scheduler defensive spell wait
- it does not classify exact interruption reasons separately from other cast failures

## Exact `casting is interrupted` Handling

### Exact text handling

Not found.

No raw chat-text parsing path was found for:

- `<playername>'s casting is interrupted`
- `casting is interrupted`

### Exact interruption message-id handling

T3.1k does **not** add a single named interruption-only id table from external text parsing.

Instead it uses the existing parsed `0x029` action-message style already present in the repo and classifies local-player scheduler defensive spell interruption/failure narrowly as:

- local player is the actor
- scheduler defensive spell wait is active
- target matches the pending defensive spell target when one exists
- message id is non-zero
- message id is **not** one of the known spell-init ids
- message id is **not** one of the known spell-success ids

This matches the same broad packet/message style already used in core pull/tank spell retry handling, but is scoped specifically to scheduler defensive spell state.

## Whether Scheduler Action State Consumes Interruption

### `uc_scheduler_action_state.lua`

Current exported state behavior:

- `action_mark_sent(...)`
- `action_mark_packet_start(...)`
- `action_mark_packet_end(...)`
- `action_is_acting(...)`
- `action_dispatch_blocked(...)`

Observed model:

- outbound send marks in-flight state
- incoming self action start can refresh start state
- incoming self action messages broadly mark packet end
- otherwise release falls back to timeout/cooldown logic

Missing bridge:

- no API or branch specifically says “local spell interrupted”
- no interruption-specific shortening/clearing of action-state cooldown was found

### Scheduler defensive Cure / spell wait

`unified_scheduler.lua`:

- `begin_defensive_spell_wait(...)`
- `refresh_defensive_spell_wait_lock(...)`
- `clear_defensive_spell_wait_state()`

Observed release behavior:

- expires by bounded timeout
- clears when last send kind is no longer `spell`
- clears when action is no longer acting and cooldown has passed

T3.1k adds that missing bridge:

- on confirmed local-player scheduler defensive spell interruption/failure
  - `clear_defensive_spell_wait_state()` is called
  - local defensive spell in-flight action-state cooldown is cleared/shortened
  - scheduler movement lock is only shortened when current movement owner is `scheduler`

### Scheduler tank spell wait

`unified_scheduler.lua`:

- `p1_begin_tank_spell_wait(...)`
- `p1_refresh_tank_spell_wait_lock(...)`
- `p1_clear_tank_spell_wait_state(...)`

Observed release behavior:

- bounded timeout
- send-kind mismatch
- acting/cooldown completion

No direct scheduler interruption branch was found here either.

### Core pull/tank spell wait

`unified_combat_core.lua` does have a narrower incoming-message response:

- unknown/non-success spell message for local actor/expected target clears:
  - pull spell wait
  - tank spell wait

So the core spell-wait paths do have a generic incoming-failure release.

But that disconnect remains:

- scheduler defensive spell wait does not consume the same failure/interruption outcome
- scheduler action-state does not classify interruption as its own event

## T3.1k Implementation Hook Used

Implemented hook:

1. Continue using existing raw `0x029` action-message parsing already present in `UnifiedCombat.lua`
2. Classify interruption/failure inside `scheduler.on_action_message(msg)`
3. Scope it to:
   - local player only
   - scheduler defensive spell wait only
   - local defensive spell action-state only

Exact scheduler state cleared/shortened by T3.1k:

- clears scheduler defensive spell wait:
  - `defensive_spell_waiting`
  - `defensive_spell_wait_until`
  - `defensive_pending_action`
  - `defensive_pending_target_id`
  - `defensive_pending_sent_at`
- clears/shortens local defensive spell action state by:
  - ending acting state immediately
  - zeroing `cooldown_until`
  - zeroing `action_delay`
- shortens movement lock only when:
  - `_G.UC_MOVEMENT_OWNER == 'scheduler'`
  - current lock is still active
  - shortened tail becomes `min(current_lock_until, now + 0.2)`

State intentionally **not** cleared:

- JA state
- WS state
- another player's action state
- core pull/tank spell wait state
- movement locks owned by unrelated systems

If the correct interruption message ids are not already known, the next task should first add replay/mock coverage around raw `0x029` action-message ids before field rollout.

## Test Strategy

Recommended next implementation test strategy:

T3.1k coverage added:

- `tests/replay/harness/selftest_scheduler_spell_interruption_action_state.lua`

Covered:

- helper exists for local defensive spell interruption clear
- interruption path is scoped to defensive spell providers only
- interruption path does not clear JA state
- interruption path does not clear WS state
- scheduler `on_action_message(msg)` contains spell-init / spell-success exclusion checks
- scheduler defensive spell wait is cleared on interruption/failure classification
- scheduler-owned movement lock is only shortened, not broadly dropped

## Field-Test Plan

Field test after T3.1k:

1. Start a local defensive Cure or other scheduler spell
2. Interrupt it by movement / incoming hit / forced reposition
3. Confirm:
   - action-state no longer remains “acting” until timeout
   - defensive spell wait clears immediately
   - scheduler movement lock only shortens to a brief tail instead of being dropped instantly
   - unrelated JA/WS locks remain intact

## Risks

- clearing local scheduler state from another player's interruption message
- over-broad message-id matching that clears on ordinary spell outcomes
- clearing JA/WS locks because a spell interruption path is not spell-scoped
- stale/late interruption message arriving after a retry has already started
- multi-character / IPC ambiguity if remote actor messages are not filtered strictly
- movement lock release too early, causing immediate self-interrupt loops
- localization risk if raw chat text were used instead of packet/message ids

## Rollback Risk

Moderate if done carelessly, low if scoped narrowly.

The biggest risk is not packet ingestion itself — that already exists.
The risk is incorrectly bridging interruption into scheduler-owned state and releasing movement/action locks for the wrong local action.

Rollback note:

- T3.1k is scoped to scheduler defensive spell state only
- if rollback is needed, revert the interruption branch in `scheduler.on_action_message(msg)` and the narrow action-state clear helper
- no ownership-policy rollback is involved
