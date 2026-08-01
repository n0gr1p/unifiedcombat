# Maintenance Replay Fixture Design

## 1. Purpose

This document defines replay fixture and state snapshot requirements for future maintenance state/provider refactor work in `unified_scheduler.lua`.

No runtime code is changed by this document.

This document is required before extracting maintenance state helpers (`ensure_maintenance_state_tables`, `ensure_maintenance_buff_cache`, `set_recent_gain`, `get_recent_gain`, `family_tokens_for`) or `p1_collect_maintenance`.

Fixture parity alone is not enough for final confidence. Live-log or packet-replay validation is still required.

`p1_collect_maintenance` must not be moved until these fixtures exist and pass.

## 2. Maintenance ownership scope

In scope:

- `scheduler.maintenance_state`
- `scheduler.recent_gain`
- `scheduler.attempted` only where maintenance uses it
- Family token state (`scheduler.family_tokens`)
- Buff/debuff cache state (`maintenance_buff_cache`)
- Parsed `0x063` status snapshots (`parse_status_snapshot_063`)
- BRD/COR/GEO maintenance proposal generation in `p1_collect_maintenance`
- City-zone maintenance block behavior
- Maintenance cadence gates (`scheduler.phase1.maintenance_next_at`)

Out of scope:

- Dispatch execution
- Movement/facing
- `action_ready`/`spell_ready`/`ja_ready` implementation changes
- Ranking/scoring changes
- Direct command emission
- Provider extraction

## 3. Current state/function map

| Function | Current owner | Future owner candidate | Reads | Writes | Side effects | Inputs | Outputs | State touched | Known consumers | Risk | Extraction prerequisite |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ensure_maintenance_state_tables` | `unified_scheduler.lua` | Maintenance state module | `scheduler.maintenance_state` | Ensures `maintenance_state`, `.buffs`, `.debuffs`, `.status_snapshot` tables | None | none | table (`scheduler.maintenance_state`) | `scheduler.maintenance_state.*` | `p1_collect_maintenance`, `on_incoming_chunk(0x063)`, defensive action bookkeeping | medium | Freeze full nested schema and init/reset contract |
| `ensure_maintenance_buff_cache` | `unified_scheduler.lua` | Maintenance cache/state module | `maintenance_buff_cache.built`, `res.buffs` names | `maintenance_buff_cache.roll_ids/song_ids/indi_ids/geo_ids/built` | None | none | none | local `maintenance_buff_cache` | `p1_collect_maintenance` (BRD/COR/GEO buff counting) | medium | Freeze cache key rules and rebuild behavior |
| `set_recent_gain` | `unified_scheduler.lua` | Maintenance state module | `family_key(...)` | `scheduler.recent_gain[family_key]` row | None | `member_name`, `buff_id`, `spell_name`, `now` | none | `scheduler.recent_gain` | defensive/overwrite maintenance logic | medium | Freeze key/value/timestamp semantics |
| `get_recent_gain` | `unified_scheduler.lua` | Maintenance state module | `scheduler.recent_gain[family_key]`, `now`, `max_age` | none | None | `member_name`, `buff_id`, `max_age`, `now` | `name` or `nil` | `scheduler.recent_gain` | defensive/maintenance suppression logic | medium | Freeze TTL and nil behavior |
| `family_tokens_for` | `unified_scheduler.lua` | Maintenance state module | `family_key(...)`, `scheduler.family_tokens[k]` | Initializes `scheduler.family_tokens[k]={}` when missing | None | `member_name`, `buff_id` | table (`tokens`) | `scheduler.family_tokens` | overwrite/buff-family anti-duplicate tracking | medium | Freeze table shape and mutation lifecycle |
| `p1_collect_maintenance` | `unified_scheduler.lua` | Maintenance provider module | settings/global toggles, player/job/buffs, city-zone state, cadence gate, `maintenance_buff_cache`, `cor_maintenance.propose(...)`, `count_matching_buffs(...)` | `scheduler.phase1.maintenance_next_at` gate fields; appends to proposal list | None directly (proposal-only path) | `ctx`, `out` | mutates `out` with proposals | `scheduler.phase1.maintenance_next_at`; indirect dependence on maintenance/cache/state | `p1_collect_proposals`, dry-run/rank pipeline | high | Fixture set + replay parity + live-log validation + proposal parity contract |

Conservative unknowns requiring inspection before movement:

- Exact full nested row schema under `scheduler.maintenance_state.buffs`/`.debuffs` across all call paths.
- Whether any non-maintenance lanes read/write `scheduler.phase1.maintenance_next_at` fields beyond current visible keys.
- Any hidden consumers of maintenance proposal `detail` payload variants.

## 4. State schemas to freeze

### 4.1 scheduler.maintenance_state

Known top-level keys:

- `buffs` (table)
- `debuffs` (table)
- `status_snapshot` (table)

Nested keys if visible:

- `status_snapshot[target_id] = parse_status_snapshot_063(data)` rows (from `on_incoming_chunk` path)
- `buffs[action.entry_key]` row is used by defensive/maintenance-adjacent bookkeeping and may include keys like `attempted`, `last_attempt_reason`, `last_seen_at`, `landed` (observed in runtime writes)

Value types:

- Table containers; row-level keys include numbers/strings and nested tables.

Initialization behavior:

- Lazy initialization via `ensure_maintenance_state_tables`.

Reset behavior:

- Partial clear on outgoing chunk `0x01D` when zoning (`status_snapshot = {}` observed).
- Full lifecycle reset behavior otherwise is unknown and must be documented before movement.

Consumers:

- Maintenance collection and status integration paths.
- Defensive/overwrite bookkeeping paths touching `buffs` rows.

Unknowns:

- Canonical full row schema for `buffs` and `debuffs` across all call sites.
- Complete reset/cleanup triggers beyond observed zone clear.

### 4.2 scheduler.recent_gain

Key shape:

- `family_key(member_name, buff_id)` where `family_key = tostring(member_name) .. ':' .. tostring(buff_id)`.

Value shape:

- `{ name = <spell_name>, ts = <number> }`.

Timestamp behavior:

- `ts` is compared against fixture/runtime `now`.

max_age behavior:

- `get_recent_gain` returns `name` only when `(now - ts) <= (max_age or 20)`; otherwise returns `nil`.

Reset behavior:

- Runtime table persists for session; full reset behavior is lifecycle/reload-driven.

Consumers:

- Maintenance/overwrite duplicate suppression behavior.

### 4.3 scheduler.attempted maintenance usage

Key shape:

- `attempt_key(kind, member_name, action_name)` where `attempt_key = kind .. '::' .. member_name .. '::' .. action_name`.

Value shape:

- Numeric timestamp of last attempt.

Timestamp/cooldown behavior:

- `attempt_allowed` blocks when `(now - last) < (min_gap or 3)`.

Consumers:

- Maintenance-adjacent and defensive anti-spam checks.

Distinction from enemy dispel attempt state:

- `scheduler.attempted` is proposal-family/action throttling.
- Enemy dispel attempt state uses a separate map (`enemy_dispel_attempt_map`) and separate cooldown contract.

### 4.4 family token state

Key shape:

- `family_key(member_name, buff_id)`.

Token table shape:

- Table keyed by action/spell name, value numeric deadline/time marker.

Initialization behavior:

- Lazily created as `{}` by `family_tokens_for` when missing.

Mutation behavior:

- Mutated by setting `tokens[action_name] = <timestamp/deadline>` in maintenance-adjacent logic.

Consumers:

- Family/overwrite suppression and cadence controls.

### 4.5 parsed status snapshot rows

Source parser:

- `uc_scheduler_status_snapshot_parser.lua` (`parse_status_snapshot_063`).

Key shape:

- `status_by_id[buff_id]` where `buff_id` is parsed from chunk rows.

Row shape:

- `{ count = <number>, endtimes = <number[]> }`.

Count behavior:

- Increments per occurrence of same `buff_id` in parsed rows.

Endtimes behavior:

- Includes only positive endtimes (`> 0`).
- Sorted ascending using numeric coercion.

Early terminator behavior:

- Stops parse when `buff_id == 255`.

Nil/fallback behavior:

- Returns `nil` for non-string/short payloads or when byte 5 is not `9`.

Consumers:

- `scheduler.maintenance_state.status_snapshot[target_id]` storage and maintenance proposal logic relying on active/future buff windows.

## 5. Replay fixture input model

Recommended generic fixture shape:

```lua
{
  fixture_name = "maintenance_case_name",
  description = "what this fixture validates",
  now = 12345.678,
  settings = { -- maintenance-relevant flags only
    Start_Engine = true,
    -- plus lane-specific settings under test
  },
  job_context = {
    main_job = "BRD",
    sub_job = "WHM",
    status = 1,
    player_id = 123,
    player_name = "Tester",
    buffs = {},
  },
  party_snapshot = {
    -- deterministic party/member snapshot used by maintenance lane
  },
  status_snapshot_input = {
    raw_063 = nil, -- optional raw payload
    parsed = {},   -- optional direct parsed status map from parser contract
  },
  maintenance_state_before = {
    buffs = {},
    debuffs = {},
    status_snapshot = {},
  },
  recent_gain_before = {},
  attempted_before = {},
  family_tokens_before = {},
  maintenance_gate_before = {
    cor_rolls = 0,
    brd_songs = 0,
    geo_buffs = 0,
  },
  readiness_stubs = {
    -- deterministic return values for readiness-adjacent checks if touched
  },
  expected_maintenance_state_after = {},
  expected_recent_gain_after = {},
  expected_attempted_after = {},
  expected_family_tokens_after = {},
  expected_maintenance_gate_after = {},
  expected_proposals = {},
  expected_noop_or_reject_reason = nil,
  expected_debug_globals = {},
  expected_side_effect_count = 0,
}
```

Rules:

- `expected_side_effect_count` is always zero for replay/provider dry-run fixtures.
- Fixture may carry either `raw_063` (parser-included run) or `parsed` (provider-focused run), but contract must declare which layer is under test.

## 6. Minimum maintenance replay scenarios

### 6.1 No active buffs

- Input state: BRD/COR/GEO job variant with empty `player.buffs` and empty status snapshot.
- Expected maintenance state: no unexpected schema mutation; only expected gate/cache fields.
- Expected proposals: maintenance proposal emitted when cadence due and not city-blocked.
- Expected recent_gain changes: none for pure collection path.
- Expected no side effects: side-effect count remains zero.

### 6.2 Existing buff with future endtime

- Input parsed status snapshot: buff row has future `endtimes`.
- Expected suppression/no proposal behavior: no maintenance proposal for that maintained buff family.
- Expected cache/state behavior: no unrelated state mutation.

### 6.3 Expired or missing buff state

- Input old endtime or missing status row.
- Expected proposal behavior: proposal emitted when cadence due and readiness/context allow.
- Expected recent_gain behavior: unchanged by collection-only path.

### 6.4 BRD available

- Settings/context required: engine on, job `BRD`, not city zone, cadence due.
- Readiness stubs: deterministic spell-readiness/target viability where applicable.
- Expected proposal fields: provider `brd`, action `maintenance_songs`, target self, reason `songs_missing`.
- Expected priority/urgency shape: `priority_band=75`, urgency clamped (`0.80` or `0.50` per song count path).

### 6.5 COR available

- Settings/context required: engine on, job `COR`, not city zone, cadence due.
- Readiness stubs: deterministic `cor_maintenance.propose(...)` output.
- Expected proposal fields: provider `maintenance_cor`, action type `ja`, reason from propose payload or `cor_roll_maint`.
- Expected priority/urgency shape: `priority_band=75`, urgency clamped from propose payload.

### 6.6 GEO available

- Settings/context required: engine on, job `GEO`, not city zone, cadence due.
- Readiness stubs: deterministic GEO buff presence context.
- Expected proposal fields: provider `geo`, action `maintenance_geo`, reason `geo_missing`.
- Expected priority/urgency shape: urgency `0.80` both missing, `0.65` indi missing, `0.45` geo-only missing.

### 6.7 BRD/COR/GEO unavailable

- Readiness blocked: non-maintenance job or provider propose returns nil/blocked context.
- Expected behavior: no maintenance proposal emitted.
- Expected reject/no-op reason: if present in diagnostics, preserve exact reason text; fixture should treat reason as optional observability output.

### 6.8 City-zone maintenance blocked

- Current zone/context: city/mog/residential zone per `is_city_zone_for_maintenance` contract.
- Settings: engine on, maintenance otherwise eligible.
- Expected no proposal behavior: no proposals.
- Expected state unchanged behavior: gate values reset to `0` for `cor_rolls`, `brd_songs`, `geo_buffs`; no unrelated mutation.

### 6.9 Cadence not yet due

- Current timestamps: `maintenance_next_at[key] > now`.
- Expected no proposal: empty maintenance additions.
- Expected state unchanged behavior: gate remains unchanged except expected stable fields.

### 6.10 Cadence due

- Current timestamps: `maintenance_next_at[key] <= now`.
- Expected proposal generation: exactly one lane-appropriate proposal per due lane branch.
- Expected timestamp/state updates: gate key advanced (`+2.0` generic spell lane, `+1.0` COR branch).

### 6.11 Recent gain suppresses duplicate

- `recent_gain_before`: includes matching family key with recent `ts`.
- `max_age`: explicit test value.
- Expected suppression: duplicate overwrite/buff proposal suppressed in consuming logic.
- Expected no duplicate proposal: parity must prove no duplicate insertion for same family/action window.

### 6.12 Family tokens initialized

- Empty/missing `scheduler.family_tokens[family_key]`.
- Expected initialized shape: `family_tokens_for(...)` returns table and stores it.
- Expected no unrelated mutation: only that family key is added.

## 7. Expected proposal parity contract

Maintenance-generated proposals must match exactly for the compared run pair:

- `kind`/`action_type` semantics
- `action_name`
- target/member fields
- `target_id`
- `target_name`
- `priority_band` (priority)
- `urgency`
- score inputs if visible (`priority_band`, `urgency`, starvation/sticky related flags)
- family/attempt-related fields (`family_id`, `duplicate_suppression_key`, `recast_key`)
- reason/debug fields (`reason_code`, relevant `detail` values)
- provider/source fields (`provider`, proposal id family prefix semantics)
- prelude/metadata fields used by dispatch plan (`movement_policy`, `range_policy`, `expected_ack`, `expected_effect`, `lock_class`, `commit_deadline`, `expires_at`)

If `p1_collect_maintenance` generates multiple proposals in any scenario, ordering must match.

## 8. State transition parity contract

Before/after comparison must include:

- Table keys
- Table value types
- Numeric timestamp values (with deterministic `now` injection or normalized comparison)
- `nil` vs `false` vs empty string behavior
- Missing table initialization behavior
- Sorted/unsorted table behavior where relevant (especially parsed `endtimes` sort)
- Mutation scope (no unrelated state changes)
- Proposal count and proposal field equality
- No side-effect execution

## 9. Replay harness requirements

A future replay harness must:

- Load fixture tables.
- Run old and new implementations with identical inputs.
- Stub readiness functions deterministically.
- Stub Windower reads deterministically where needed.
- Freeze `now_s` via fixture `now`.
- Capture before/after scheduler state snapshots.
- Capture proposal list before ranking.
- Compare structural equality.
- Report first mismatch with fixture name, state path, expected value, actual value.
- Never emit command/movement/facing/target-selection side effects during replay.

## 10. Live-log validation requirements

Before moving `p1_collect_maintenance`, capture in-game:

- Incoming `0x063` status snapshot payloads.
- Parsed status snapshot output.
- Current zone and city-block state.
- Maintenance-relevant settings.
- BRD/COR/GEO readiness decisions.
- `scheduler.maintenance_state` before/after.
- `scheduler.recent_gain` before/after.
- Proposal list before ranking.
- Selected proposal.
- No-op/reject reason.
- Emitted command or explicit no-command result.

## 11. Stop conditions

This document does not permit moving:

- `p1_collect_maintenance`
- `p1_collect_proposals`
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `action_ready`
- `spell_ready`
- `ja_ready`
- `p1_run_dry`
- `dispatch_selected_plan`
- `run_movement_coordinator_tick`
- Any direct side-effect owner

## 12. Recommended next tasks

1. Docs-only enemy-effect replay fixture design.
2. Non-runtime maintenance replay harness skeleton design.
3. Create isolated replay fixture files only if repo convention is explicit and stable.
4. Maintenance state schema freeze after inspecting exact runtime state shapes.
5. Readiness/resource-cache ownership design.

Do not perform immediate provider extraction.

## 13. Validation snapshot

Run and report:

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

And side-effect counts (`grep` or `Select-String` equivalent):

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `io.open`

Required confirmations:

- No runtime files were changed.
- No side-effect call sites were moved.
- Only `docs/maintenance_replay_fixture_design.md` was created for this task.
