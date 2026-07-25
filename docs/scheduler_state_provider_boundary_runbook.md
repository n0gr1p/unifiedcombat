# Scheduler State-Provider Boundary Runbook

> Historical extraction runbook. Superseded for current runtime ownership by
> `scheduler_responsibility_map.md` and the Phase 6 exit audit in `../RFC/`.

## 1. Purpose

The low-risk pure-helper extraction lane is complete. Future runtime refactor work in `unified_scheduler.lua` must be gated by explicit ownership boundaries and replay/live-log validation before stateful/provider/dispatcher/readiness movement.

This document does not change runtime code.

This runbook is a prerequisite before moving stateful, provider, dispatcher, movement, readiness, packet-ingestion, or IPC/cache ownership.

`parse_status_snapshot_063` in `uc_scheduler_status_snapshot_parser.lua` is the first extracted parser and was fixture-parity validated.

Fixture parity is necessary but not sufficient for broader packet/state/provider refactors. Future movement requires live-log or packet-replay validation in addition to fixtures.

## 2. Current safe stopping point

Current post-helper-extraction state (from `docs/scheduler_wrapper_owned_map.md` and `docs/scheduler_extraction_checkpoint.md`):

- Total local functions in `unified_scheduler.lua`: 142
- Wrapper functions: 71
- Owned functions: 70
- Mixed/uncertain functions: 1
- Next owned-pure candidates: none
- Extracted parser module exists: `uc_scheduler_status_snapshot_parser.lua`
- Extracted parser function: `parse_status_snapshot_063`
- Remaining owned runtime candidates are mostly stateful, Windower-reading, provider-owned, dispatcher-owned, readiness-owned, or side-effect-owning.

Current direct side-effect grep counts (`*.lua`, current repo snapshot):

- `windower.send_command`: 112
- `windower.ffxi.run`: 65
- `windower.ffxi.turn`: 9
- `uc_settarget.select_by_id`: 4
- `io.open`: 6

## 3. Ownership lanes

### 3.1 Parser lane

Scope:

- Pure packet/payload parsing.
- Table-in/string-in to table-out behavior.
- No scheduler mutation.
- No Windower reads.
- No globals.
- No IO.
- No proposal generation.

Current module:

- `uc_scheduler_status_snapshot_parser.lua`

Current function:

- `parse_status_snapshot_063`

Allowed future moves:

- Only pure parser functions with fixture parity and replay parity.

Not allowed:

- Packet event handlers.
- State mutation.
- IPC mutation.
- Provider proposal writes.

### 3.2 Maintenance state lane

Scope:

- `scheduler.maintenance_state` ownership.
- Recent gain state.
- Family token state.
- Buff cache lifecycle.
- Cadence timestamps.

Relevant current local functions:

- `ensure_maintenance_state_tables`
- `ensure_maintenance_buff_cache`
- `set_recent_gain`
- `get_recent_gain`
- `family_tokens_for`

Risk:

- Medium/high. State shape and timing directly affect cadence and proposal churn.

Required before runtime extraction:

- Explicit state schema.
- Lifecycle/reset contract.
- Replay fixtures for state transitions.
- Before/after debug snapshots.

### 3.3 Maintenance provider lane

Scope:

- Proposal generation for BRD/COR/GEO maintenance.
- Use of parsed status snapshots.
- Cadence gates.
- Action selection and priority generation.

Relevant current local functions:

- `p1_collect_maintenance`

Risk:

- High. It changes emitted intents and action timing.

Required before runtime extraction:

- Provider input/output contract.
- Proposal snapshot fixture tests.
- Replay logs showing same proposals before/after.
- Debug output parity.

### 3.4 Enemy-effect parser/state lane

Scope:

- Enemy-effect observed state.
- Dispel attempt state.
- Catalog loading boundaries.
- Raw action ingestion boundaries.

Relevant current local functions:

- `load_enemy_dispel_map_from_json`
- `load_targetbar_catalogs_once`
- `apply_effect_list_to_target`
- `apply_catalog_effects`
- `enemy_dispel_attempt_map`
- `enemy_effect_state_map`
- `enemy_effect_state_set`
- `enemy_effect_state_clear`
- `enemy_effect_state_clear_target`
- `enemy_effect_state_prune_expired`
- `enemy_effect_state_sweep`
- `can_attempt_enemy_dispel`
- `mark_enemy_dispel_attempt`
- `enemy_dispel_choose_action`
- `is_enemy_mob_id`
- `ingest_enemy_effects_from_raw_action_028`

Risk:

- Medium/high. Packet ingestion, attempt throttling, and proposal behavior are coupled.

Required before runtime extraction:

- State schema.
- Attempt throttle contract.
- Raw action replay fixtures.
- Observed effect before/after snapshots.
- Proposal parity for `p1_collect_enemy_buff_removal`.

### 3.5 IPC/context lane

Scope:

- Party state serialization.
- IPC broadcast.
- IPC apply/read cache.
- `get_party_members` snapshot behavior.

Relevant current local functions:

- `encode_party_state_payload`
- `maybe_broadcast_party_state_ipc`
- `apply_party_state_ipc_message`
- `get_party_state_ipc_entry`
- `get_party_members`
- `p1_build_ctx`

Risk:

- Medium/high. Stale IPC or snapshot drift can affect every provider.

Required before runtime extraction:

- Payload schema contract.
- TTL/staleness contract.
- Replay fixtures for IPC payloads.
- Party snapshot before/after comparison.

### 3.6 Readiness/resource-cache lane

Scope:

- Spell resource cache.
- JA resource cache.
- Spell known/usable checks.
- JA readiness.
- Action readiness multiplexer.

Relevant current local functions:

- `get_spell_resource`
- `spell_usable_by_current_job`
- `spell_known_and_usable`
- `get_ja_resource`
- `spell_ready`
- `ja_ready`
- `action_ready`
- `available_cure_tier_max`
- `get_usable_cure_from_tier`

Risk:

- High. False positives/false negatives directly change dispatch.

Required before runtime extraction:

- Resource cache ownership design.
- Player-state input contract.
- Readiness matrix fixtures.
- Before/after readiness decision logs.

### 3.7 Dispatcher/movement side-effect lane

Scope:

- Command emission.
- Target selection.
- Movement.
- Facing.
- Run/turn/send side effects.

Relevant current local functions:

- `p1_try_dark_launch_dispatch`
- `p1_try_target_prep`
- `p1_apply_face_to_target`
- `p1_move_toward_mob`
- `run_movement_coordinator_tick`
- `try_doom_water_emergency`
- `try_delegate_healbot`
- `try_internal_defensive_action`

Risk:

- Highest. This lane owns runtime side effects.

Required before runtime extraction:

- Explicit dispatcher ownership model.
- Side-effect allowlist update.
- Command string parity.
- Movement/facing replay or controlled in-game validation.
- Rollback plan.

## 4. Runtime extraction gates

Before any stateful runtime extraction, all gates below must be satisfied:

1. Function category identified.
2. Current owner and future owner named.
3. State read/write list complete.
4. Side-effect list complete.
5. Inputs and outputs documented.
6. Error/fallback behavior documented.
7. Debug/global outputs documented.
8. Fixture parity plan created.
9. Replay/live-log validation plan created.
10. Rollback plan created.
11. One-function or one-state-cluster scope confirmed.
12. Stop conditions named.

## 5. Replay/live-log validation runbook

### 5.1 Capture requirements

For live-log or replay inputs, capture:

- Incoming packet/chunk payloads relevant to the lane.
- Action packets for enemy-effect state.
- IPC messages for party state.
- Scheduler debug globals before/after.
- Proposal list before ranking.
- Selected proposal.
- Reject reasons.
- Pending/action/lock state.
- Emitted commands or explicit absence of commands.

### 5.2 Replay harness expectations

A replay harness should:

- Feed identical inputs into old and new implementations.
- Compare outputs structurally, not only as strings.
- Compare ordering where order is meaningful.
- Compare nil/fallback behavior.
- Compare numeric coercion.
- Compare state mutations after each step.
- Report first mismatch with enough context to debug quickly.

### 5.3 Required comparison dimensions

Compare:

- Table keys.
- Value types.
- Row/item order.
- Numeric coercion.
- Nil vs false vs empty string behavior.
- Timestamps/deadlines when deterministic or normalized.
- Proposal count.
- Proposal fields.
- Selected proposal identity.
- Reject reasons.
- Side-effect call counts.
- Command strings when applicable.

### 5.4 Minimum replay scenarios

Maintenance:

- No active buffs.
- Existing buffs with future endtimes.
- Missing/expired buff state.
- BRD/COR/GEO available and unavailable.
- City-zone maintenance blocked case.
- Cadence not yet due.
- Cadence due.

Enemy-effect:

- Mob gains one dispellable buff.
- Mob gains multiple buffs.
- Buff expires or is cleared.
- Claim invalid.
- Claim valid.
- Attempt throttled.
- Unknown buff id.
- Catalog-derived buff.
- Packet replay with duplicate observations.

IPC/context:

- No IPC.
- Fresh IPC.
- Stale IPC.
- Malformed IPC.
- Multiple partners.
- Partner target set with missing mob.
- Party member missing id/name fields.

Readiness:

- Known spell ready.
- Unknown spell.
- Spell known but not usable by current job.
- Recast blocked.
- MP blocked.
- JA recast blocked.
- JA range/front blocked.
- Target invalid.

Dispatcher/movement:

- Selected command emitted.
- Dispatch blocked by action state.
- Target prep required.
- Target prep fails.
- Movement required.
- Facing required.
- No side effect when blocked.

## 6. State schema appendix

### 6.1 `scheduler.maintenance_state`

- Owner today: `unified_scheduler.lua` (`ensure_maintenance_state_tables`, maintenance collector).
- Intended future owner: maintenance state lane module (boundary TBD, docs-first).
- Keys: `buffs`, `debuffs`, `status_snapshot`.
- Value shape: table maps/containers; exact nested schema partially unknown.
- TTL/deadline rules: partially unknown; cadence interactions are provider-coupled.
- Reset behavior: initialized lazily in `ensure_maintenance_state_tables`; full reset contract not yet documented.
- Debug/global mirrors: unknown/indirect.
- Known consumers: `p1_collect_maintenance`, packet/status integration paths.
- Pre-move inspection required: nested `buffs`/`debuffs` row schema, status snapshot overwrite semantics, reset points.

### 6.2 `scheduler.recent_gain`

- Owner today: `unified_scheduler.lua` (`set_recent_gain`, `get_recent_gain`).
- Intended future owner: maintenance state lane.
- Keys: `family_key(member_name, buff_id)`.
- Value shape: `{ name = <spell_name>, ts = <number> }`.
- TTL/deadline rules: `get_recent_gain(..., max_age, now)` age gate.
- Reset behavior: table-level reset currently implicit (runtime reload/reset lifecycle).
- Debug/global mirrors: none known.
- Known consumers: maintenance overwrite/cadence suppression logic.

### 6.3 `scheduler.attempted`

- Owner today: `unified_scheduler.lua` (`attempt_allowed`, `mark_attempt`).
- Intended future owner: readiness/maintenance shared attempt-throttle lane (TBD).
- Keys: attempt/family keys as strings.
- Value shape: numeric timestamp.
- TTL/deadline rules: age-gated in caller logic.
- Reset behavior: table persists during runtime; cleared on addon reload.
- Debug/global mirrors: none known.
- Known consumers: maintenance/defensive anti-spam gates.

### 6.4 Enemy effect state map

- Owner today: `unified_scheduler.lua` (`enemy_effect_state_map`, set/clear/prune/sweep mutators).
- Intended future owner: enemy-effect parser/state lane.
- Keys: first-level target id, second-level effect id.
- Value shape: effect rows include observation timestamp and source metadata; exact canonical row schema must be frozen before movement.
- TTL/deadline rules: prune/sweep logic via `enemy_effect_state_prune_expired` and `enemy_effect_state_sweep`.
- Reset behavior: explicit clear APIs (`clear`, `clear_target`) plus prune expiration.
- Debug/global mirrors: overlay/diag paths consume derived view.
- Known consumers: `p1_collect_enemy_buff_removal`, packet/action observers.
- Pre-move inspection required: exact row keys (`at`, `source`, optional duration/deadline fields) and prune thresholds.

### 6.5 Enemy dispel attempt map

- Owner today: `unified_scheduler.lua` (`enemy_dispel_attempt_map`, `can_attempt_enemy_dispel`, `mark_enemy_dispel_attempt`).
- Intended future owner: enemy-effect parser/state lane.
- Keys: dispel attempt key (string).
- Value shape: numeric timestamp.
- TTL/deadline rules: cooldown via `DISPell_ATTEMPT_COOLDOWN_S` and caller now-time.
- Reset behavior: lazy-init map, expiration by age checks.
- Debug/global mirrors: indirect via reject/proposal diagnostics.
- Known consumers: `enemy_dispel_choose_action`, `p1_collect_enemy_buff_removal`.

### 6.6 Party IPC cache (`scheduler.party_state_ipc`)

- Owner today: `unified_scheduler.lua` (encode/broadcast/apply/get entry).
- Intended future owner: IPC/context lane.
- Keys: `last_sent_at`, `send_interval`, `ttl`, `by_id`.
- Value shape: `by_id[member_id]` rows hold member snapshot + timestamp data; exact row schema must be frozen.
- TTL/deadline rules: staleness based on `ttl` and entry timestamp.
- Reset behavior: lazy-table normalization in apply/get helpers.
- Debug/global mirrors: none known.
- Known consumers: `get_party_members`, `p1_build_ctx`, provider collectors.
- Pre-move inspection required: malformed payload behavior and stale-entry eviction semantics.

### 6.7 Pending record (`scheduler.phase1.pending`)

- Owner today: pending/action-state helpers called from `unified_scheduler.lua` (`uc_scheduler_pending.lua`, pending record wrapper).
- Intended future owner: dispatcher lane (explicitly owned pending lifecycle).
- Keys: partially known, includes `state`, `lock_class`, `target_id`, `action_name`, `ack_at` and related deadlines/expectations.
- Value shape: table record for in-flight selected action.
- TTL/deadline rules: live-state checks and timeout completion gates.
- Reset behavior: mark-complete transitions and no-send cleanup paths.
- Debug/global mirrors: pending globals via `p1_set_pending_globals`.
- Known consumers: locks, ranking reject paths, packet/message observers, dispatcher commit path.
- Pre-move inspection required: full field inventory and state machine transitions.

### 6.8 Action state (`scheduler.action_state`)

- Owner today: `uc_scheduler_action_state.lua` via wrappers in `unified_scheduler.lua`.
- Intended future owner: dispatcher/action-state lane.
- Keys: `action_start`, `action_end`, `action_delay`, `last_action`, `last_acting_state`, `cooldown_until`, `lag_timeout`, `ja_lag_timeout`, `last_send_kind`.
- Value shape: numeric timestamps + string send-kind.
- TTL/deadline rules: cooldown and lag timeout checks in action-state helpers.
- Reset behavior: `scheduler.reset_runtime_locks` path plus per-action updates.
- Debug/global mirrors: action/pending-related globals.
- Known consumers: dispatch blocking, movement/dispatch gating, pending transitions.

## 7. Stop conditions

The following must not be moved by simple mechanical extraction:

- `p1_try_dark_launch_dispatch`
- `run_movement_coordinator_tick`
- `p1_collect_*` provider functions
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `action_ready`
- `spell_ready`
- `ja_ready`
- `p1_run_dry`
- Enemy-effect state mutators
- Maintenance state mutators
- IPC side-effect owners
- Direct command/movement/facing/target-selection side-effect owners

## 8. Recommended next tasks

1. Build maintenance replay fixture design (docs-only).
2. Build enemy-effect replay fixture design (docs-only).
3. Create a non-runtime replay harness skeleton isolated from runtime modules.
4. Extract one state cluster only after replay harness parity checks exist.
5. Revisit readiness/resource-cache ownership design and freeze contracts before code movement.

No immediate provider extraction is recommended.

## 9. Validation snapshot

Runtime syntax checks and side-effect grep checks must be rerun for every boundary-doc update or extraction proposal to confirm no behavior drift.

Validation commands executed for this update are captured in task output:

- `luac -p unified_scheduler.lua`
- `luac -p uc_scheduler_status_snapshot_parser.lua`
- `luac -p uc_scheduler_enemy_effect_utils.lua`
- `luac -p uc_scheduler_context_utils.lua`
- `luac -p uc_scheduler_numeric_utils.lua`
- `luac -p uc_scheduler_maintenance_utils.lua`
- `luac -p uc_scheduler_text_utils.lua`
- `luac -p uc_scheduler_command_builder.lua`
- `luac -p uc_scheduler_action_metadata.lua`
- `luac -p uc_scheduler_defensive_utils.lua`
- `luac -p uc_scheduler_proposal_keys.lua`
- `luac -p uc_scheduler_action_predicates.lua`
- `luac -p uc_scheduler_geometry.lua`
- `luac -p uc_scheduler_target_utils.lua`
- `luac -p uc_scheduler_dryrun_publish.lua`
- `luac -p uc_scheduler_pending_record.lua`
- `luac -p uc_scheduler_reject_history.lua`
- `luac -p uc_scheduler_rank_output.lua`
- `luac -p uc_scheduler_dispatch_plan.lua`
- `luac -p uc_scheduler_locks.lua`
- `luac -p uc_scheduler_pending.lua`
- `luac -p uc_scheduler_action_state.lua`

And grep counts:

- `grep -R "windower.send_command" -n *.lua`
- `grep -R "windower.ffxi.run" -n *.lua`
- `grep -R "windower.ffxi.turn" -n *.lua`
- `grep -R "uc_settarget.select_by_id" -n *.lua`
- `grep -R "io.open" -n *.lua`

Required confirmations for this boundary document and any follow-up extraction:

- No runtime `.lua` files changed.
- No side-effect call sites moved.
- No existing docs changed except creation of `docs/scheduler_state_provider_boundary_runbook.md`.
