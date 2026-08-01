# Enemy-Effect Replay Fixture Design

## 1. Purpose

This document defines replay fixture and state snapshot requirements for future enemy-effect state/provider refactor work in `unified_scheduler.lua`.

No runtime code is changed by this document.

This document is required before extracting enemy-effect state helpers, raw action ingestion helpers, dispel attempt helpers, or `p1_collect_enemy_buff_removal`.

Fixture parity alone is not enough for final confidence. Live-log or packet-replay validation is still required.

`p1_collect_enemy_buff_removal` must not be moved until these fixtures exist and pass.

`ingest_enemy_effects_from_raw_action_028` must not be moved until raw action replay parity exists.

## 2. Enemy-effect ownership scope

In scope:

- Enemy effect observed state map
- Enemy dispel attempt map
- Target/effect state mutation
- Raw action `0x028` ingestion behavior
- Catalog-derived effect application
- Enemy dispel map loading behavior
- Dispel action selection
- Claim validation behavior
- Attempt cooldown/throttle behavior
- `p1_collect_enemy_buff_removal` proposal generation

Out of scope:

- Dispatch execution
- Movement/facing
- `action_ready`/`spell_ready`/`ja_ready` implementation changes
- Ranking/scoring changes
- Direct command emission
- Provider extraction
- File IO movement
- Target selection side effects

## 3. Current state/function map

| Function | Current owner | Future owner candidate | Reads | Writes | Side effects | Inputs | Outputs | State touched | Known consumers | Risk | Extraction prerequisite |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `load_enemy_dispel_map_from_json` | `unified_scheduler.lua` | Enemy-effect state/data loader module | `windower.addon_path`, JSON text, priority map | `dispellable_enemy_effect_priority`, `dispellable_enemy_effect_set` | File IO via `io.open`, fatal `error(...)` on load/parse failure | none | none | global-local dispel priority/set tables | initialization and all enemy-dispel selection paths | high | Freeze loader contract, fatal behavior, and imported map parity |
| `load_targetbar_catalogs_once` | `unified_scheduler.lua` | Enemy-effect catalog loader module | `windower.addon_path`, `TargetBar` catalog files | `tb_spells`, `tb_abilities`, `tb_skills` | `dofile(...)` file loads, fatal `error(...)` on failure | none | none | catalog caches | `ingest_enemy_effects_from_raw_action_028`, `apply_catalog_effects` | high | Freeze catalog cache-init and fatal-on-missing behavior |
| `apply_effect_list_to_target` | `unified_scheduler.lua` | Enemy-effect parser/state helper module | effect list rows | enemy effect map via set helper | none | `target_id`, `effect_list`, `source`, `at` | none | enemy effect state | `apply_catalog_effects` | medium | Freeze list row interpretation and skip semantics |
| `apply_catalog_effects` | `unified_scheduler.lua` | Enemy-effect parser/state helper module | catalog entry shape, `from_player` | enemy effect map via set helper | none | `catalog`, `action_id`, `actor_id`, `target_id`, `from_player`, `source`, `at` | none | enemy effect state | raw action ingestion | high | Replay parity for all catalog row forms (single/multi/dual target) |
| `enemy_dispel_attempt_map` | `unified_scheduler.lua` | Enemy-effect attempt-state module | `scheduler.phase1` | initializes `phase1.enemy_dispel_attempts` | none | none | map table | `scheduler.phase1.enemy_dispel_attempts` | attempt throttle/mark logic | medium | Freeze map location and lazy-init contract |
| `enemy_effect_state_map` | `unified_scheduler.lua` | Enemy-effect state module | `scheduler.phase1` | initializes `phase1.effectiveTargets` | none | none | map table | `scheduler.phase1.effectiveTargets` | all effect set/clear/prune/sweep/provider logic | medium | Freeze map location and lazy-init contract |
| `enemy_effect_state_set` | `unified_scheduler.lua` | Enemy-effect state module | target/effect ids, now/duration values | `effectiveTargets[tid][eid]` row | none | `target_id`, `effect_id`, `source`, `at`, `duration_s` | none | enemy effect state rows | ingest, catalog apply, tracker ingestion | high | Freeze row schema and timestamp/deadline rules |
| `enemy_effect_state_clear` | `unified_scheduler.lua` | Enemy-effect state module | target/effect ids | clears row key when present | none | `target_id`, `effect_id` | boolean removed flag | enemy effect state rows | ingest, action-message processing, targeted clears | high | Freeze clear return semantics and no-op behavior |
| `enemy_effect_state_clear_target` | `unified_scheduler.lua` | Enemy-effect state module | target id | removes full target row | none | `target_id` | none | enemy effect state map | action message target clear path | high | Freeze target-wide clear scope and non-target isolation |
| `enemy_effect_state_prune_expired` | `unified_scheduler.lua` | Enemy-effect state module | `expires_at`, current time | removes expired rows and empty targets | none | `at` | none | enemy effect state map | provider tick and reset paths | high | Freeze expires semantics and empty-target cleanup |
| `enemy_effect_state_sweep` | `unified_scheduler.lua` | Enemy-effect state module | mob validity (`get_mob_by_id`), `seen_at` | removes stale/invalid targets/effects | Windower read calls | `max_age_s` | none | enemy effect state map | periodic cleanup path | high | Replay/live snapshot parity for mob-validity + stale-age cleanup |
| `can_attempt_enemy_dispel` | `unified_scheduler.lua` | Enemy-effect attempt-state module | attempt map, cooldown constant | none | none | `action_name`, `target_id`, `effect_id`, `now` | `bool`, `attempt_key` | enemy dispel attempt map | provider proposal gate | high | Freeze key format and cooldown boundary behavior |
| `mark_enemy_dispel_attempt` | `unified_scheduler.lua` | Enemy-effect attempt-state module | key, now | attempt map timestamp row | none | `key`, `now` | none | enemy dispel attempt map | dispatch ack/selection follow-up | high | Freeze mark timing source and empty-key no-op behavior |
| `enemy_dispel_choose_action` | `unified_scheduler.lua` | Enemy-effect provider helper | readiness results for `Magic Finale`/`Dispel` | none | none | `target_id` | action name or empty string | none directly | `p1_collect_enemy_buff_removal` | high | Deterministic readiness stubs and action precedence parity |
| `is_enemy_mob_id` | `unified_scheduler.lua` | Enemy-effect provider/helper module | `get_mob_by_id`, spawn/hpp | none | Windower read calls | `id` | boolean | none directly | raw ingest gate and validation | medium | Freeze enemy classification rules |
| `ingest_enemy_effects_from_raw_action_028` | `unified_scheduler.lua` | Enemy-effect raw-ingestion module | packet parse output/categories/messages/catalogs | enemy effect state via set/clear/apply helpers | Fatal `error(...)` for unavailable/failed parser; Windower reads | `data_or_act` | none | enemy effect state | `on_incoming_chunk(0x028)` path | highest | Raw action replay parity across category/message branches |
| `p1_collect_enemy_buff_removal` | `unified_scheduler.lua` | Enemy-effect provider module | settings/toggles, claim set, state map, dispel priority table, readiness gates | appends proposal rows; no direct map mutation except prune call side effects | none direct (proposal-only) | `ctx`, `out` | mutates `out` | reads enemy state/attempt state and prune path | `p1_collect_proposals` before ranking | highest | Provider proposal parity + replay/live-log validation |

Conservative unknowns requiring inspection before movement:

- Complete message/category coverage intent in `ingest_enemy_effects_from_raw_action_028` for unsupported branches.
- All external consumers that rely on exact `detail` payload shape for enemy-dispel proposals.
- Whether any external path mutates `phase1.effectiveTargets` outside currently documented helpers.

## 4. State schemas to freeze

### 4.1 Enemy effect state map

- Owner today: `unified_scheduler.lua` (`enemy_effect_state_map` and mutators).
- Intended future owner: enemy-effect state module.
- First-level key shape: numeric target id (`tid`) keyed in Lua table.
- Second-level key shape: numeric effect id (`eid`) keyed under target.
- Row shape: `{ seen_at = <number>, source = <string>, expires_at = <number> }`.
- Timestamp fields: `seen_at` set from `at` or `now_s()`.
- Source metadata fields: `source` string label from caller branch.
- Duration/deadline fields: `expires_at = seen_at + duration_s` when `duration_s > 0`, else `0`.
- Observed/landed/cleared semantics: observed via `set`; cleared via effect clear/target clear/prune/sweep.
- Initialization behavior: lazy init at `scheduler.phase1.effectiveTargets = {}`.
- Reset/clear behavior: row clear, target clear, and zone/reset paths call clear helpers.
- Prune behavior: removes rows with `expires_at > 0 and <= now`; removes empty targets.
- Sweep behavior: removes target if mob missing/not enemy/dead, removes stale rows by `seen_at` cutoff, removes empty targets.
- Known consumers: `p1_collect_enemy_buff_removal`, packet/action ingestion paths, debug overlays.
- Unknowns:
  - Full caller inventory for `duration_s` usage (currently often omitted).
  - Whether any branch relies on preserving non-table malformed entries (current logic drops them).

### 4.2 Enemy dispel attempt map

- Owner today: `unified_scheduler.lua` (`enemy_dispel_attempt_map`, attempt helpers).
- Intended future owner: enemy-effect attempt-state module.
- Key shape: `"<action_name>:<target_id>:<effect_id>"`.
- Value shape: numeric timestamp.
- Timestamp behavior: last-attempt timestamp from dispatch or provided `now`.
- Cooldown behavior: blocked while `(now - last) < DISPell_ATTEMPT_COOLDOWN_S` (`3.0`).
- Reset behavior: lazy init map; lifecycle reset via phase reset/reload paths.
- Consumers: `can_attempt_enemy_dispel`, `mark_enemy_dispel_attempt`, provider gating.
- Distinction from `scheduler.attempted`:
  - Enemy dispel attempt map is enemy-effect specific and keyed by action+target+effect.
  - `scheduler.attempted` is broader action/member throttling for other lanes.

### 4.3 Enemy dispel map/catalog data

- Source files/catalogs visible:
  - `docs/ffxi_enemy_dispellable_buffs.json`
  - `TargetBar\spells.lua`
  - `TargetBar\abilities.lua`
  - `TargetBar\skills.lua`
- Loading path:
  - `load_enemy_dispel_map_from_json` loads JSON via text parse.
  - `load_targetbar_catalogs_once` loads TargetBar catalogs once.
- Key normalization behavior:
  - Buff ids parsed as numbers; only positive ids kept.
  - Effect labels use `enemy_effect_log_label` fallback `id:<n>` when unknown.
- Danger weight/priority behavior:
  - JSON `danger_weight` mapped via `danger_weight_to_priority` and max-merged into priority table.
- Removable action metadata:
  - Provider chooses `Magic Finale` first, then `Dispel`, else none.
- Fallback behavior:
  - Missing/unknown catalog entries are skipped.
  - JSON danger weight defaults to `3` when missing.
- File IO behavior:
  - `io.open/read/close` for JSON; `dofile` for catalogs.
- Fatal/error behavior:
  - hard `error(...)` on missing/empty JSON, parse guard exhaustion, zero imported ids, or failed catalog/parser loads.
- Unknowns:
  - Full expected schema of external JSON over time and compatibility constraints.

### 4.4 Raw action 0x028 ingestion rows

- Input packet/action shape:
  - accepts parsed action table or raw packet bytes parsed by `windower.packets.parse_action`.
- Target id extraction behavior:
  - from `target.id` rows within `act.targets`.
- Effect id extraction behavior:
  - from `action.param` and add-effect params depending on message/category branch.
- Claim id behavior:
  - claim gating is primarily provider-side in `p1_collect_enemy_buff_removal`; ingest path records observations independent of claim validity in many branches.
- Source actor behavior:
  - ignores actions from player actor id; records/clears actor-derived statuses for non-player actors per branch.
- Add/update/clear behavior:
  - category/message-specific set/clear/apply rules; applies spell/JA/WS catalogs and explicit clear cases.
- Duplicate observation behavior:
  - repeated set overwrites row for same target/effect with latest `seen_at/source/expires_at`.
- Unknown or unsupported effect behavior:
  - many branches intentionally no-op with parity comments; unsupported messages are not inferred.
- Consumers:
  - enemy-effect state map and downstream enemy-dispel provider decisions.

### 4.5 Enemy buff-removal proposals

- Provider/source fields:
  - `provider='defensive_internal'`, `family_id='def.enemy_dispel.primary'`.
- Action selection fields:
  - `action_type='spell'`, `action_name` from `enemy_dispel_choose_action`.
- Target fields:
  - `target_kind='mob'`, `target_id`, `target_name`.
- Priority/urgency fields:
  - `priority_band=106`, `urgency=clamp(0.65)`.
- Reason/debug fields:
  - `reason_code='enemy_buff_remove'`, `detail.enemy_effect_id`, `detail.enemy_effect_priority`, `detail.enemy_dispel_attempt_key`.
- Attempt/cooldown fields:
  - cooldown gate through `can_attempt_enemy_dispel` and keyed attempt string.
- Expected effect/ack fields:
  - `expected_ack='action_start'`, `expected_effect='enemy_effect_removed'`.
- Dispatch-plan metadata fields visible:
  - `movement_policy='must_stop'`, `range_policy={min=0,max=21,los_required=true}`, `recast_key`, `duplicate_suppression_key`, `lock_class`, `sticky`, `expires_at`, `commit_deadline`, `legacy_command`.
- Consumers:
  - ranking/validation/dispatch-plan path after provider collection.

## 5. Replay fixture input model

Recommended generic fixture shape:

```lua
{
  fixture_name = "enemy_effect_case_name",
  description = "what is being validated",
  now = 12345.678,
  settings = {
    defensive_enabled = true,
    def_remove_enemy_buffs = true,
    domain_defensive_enabled = true,
    -- other lane-specific toggles under test
  },
  player_context = {
    player_id = 1001,
    player_name = "Tester",
    main_job = "RDM",
    status = 1,
  },
  party_snapshot = {
    -- deterministic party/member data as needed
  },
  mob_snapshot = {
    -- deterministic mobs keyed by id with spawn_type/hpp/distance/claim_id
  },
  claim_state = {
    party_claim_set = { [1234] = true },
  },
  enemy_catalog_input = {
    dispel_priority_map = {},
    dispellable_set = {},
    targetbar_spells = {},
    targetbar_abilities = {},
    targetbar_skills = {},
  },
  raw_action_input = {
    raw_028 = nil,      -- optional raw payload
    parsed_action = nil -- optional reconstructed action table
  },
  enemy_effect_state_before = {},
  enemy_dispel_attempt_map_before = {},
  readiness_stubs = {
    magic_finale = { ok = false, kind = "" },
    dispel = { ok = true, kind = "spell" },
  },
  expected_enemy_effect_state_after = {},
  expected_enemy_dispel_attempt_map_after = {},
  expected_proposals = {},
  expected_noop_or_reject_reason = nil,
  expected_debug_globals = {},
  expected_side_effect_count = 0,
}
```

Rules:

- `expected_side_effect_count` is always zero for replay/provider dry-run fixtures.
- Fixture must declare whether it targets ingestion layer, provider layer, or integrated lane parity.

## 6. Minimum enemy-effect replay scenarios

### 6.1 Mob gains one dispellable buff

- Input raw action/effect: one gain event for dispellable effect.
- Expected enemy effect state after: target/effect row present with `seen_at/source`.
- Expected proposal eligibility: provider can select this target when claim valid and action ready.
- Expected no side effects: side-effect count zero.

### 6.2 Mob gains multiple dispellable buffs

- Input: effect list or repeated observations for same target.
- Expected state row count: all observed dispellable effects retained.
- Expected priority/action selection: highest `dispellable_enemy_effect_priority` effect chosen.
- Expected proposal ordering: deterministic selection rules preserved.

### 6.3 Duplicate observation of same buff

- Input: repeated packet/effect same target/effect.
- Expected overwrite/update: row updated (latest `seen_at/source`) without duplicate subrows.
- Expected proposal behavior: no duplicate proposal inflation for same evaluation tick.

### 6.4 Buff expires or is pruned

- Before: row has `expires_at` in past relative to fixture `now`.
- After prune: effect row removed; target removed if empty.
- Proposal behavior: no proposal for pruned effect.

### 6.5 Buff explicitly cleared

- Input: clear event/helper path.
- Expected removal: exact target/effect row removed.
- Expected no stale proposal: removed effect not selected.

### 6.6 Target-wide clear

- Input: multiple effects on one target then target clear.
- Expected map: target entry removed entirely.
- Expected isolation: no unrelated target mutation.

### 6.7 Claim invalid

- Claim missing/zero/not in party claim set.
- Expected proposal: none.
- State behavior: observation may still be recorded; provider eligibility blocked.
- Reject/no-op reason: capture when observable.

### 6.8 Claim valid

- Claim party-owned and target valid enemy mob.
- Expected proposal eligibility: candidate considered.
- State retained: effect rows remain until clear/prune/sweep.
- Priority/urgency shape: expected `priority_band`/urgency values preserved.

### 6.9 Attempt throttled

- Attempt map has recent timestamp under attempt key.
- Expected result: no proposal emit.
- Attempt map unchanged: no rewrite on blocked attempt path.

### 6.10 Attempt allowed

- No prior attempt or cooldown expired.
- Expected proposal: emit candidate proposal.
- Attempt-state behavior: if mark path included in layer, timestamp written exactly once.

### 6.11 Unknown buff id

- Buff id not in resources/catalog map.
- Expected label/fallback: debug label fallback `id:<n>` behavior.
- Expected proposal behavior: depends on dispellable set membership; unknown/non-dispellable should not be selected.

### 6.12 Catalog-derived buff

- Catalog marks effect dispellable.
- Expected normalized key behavior: numeric key usage and map insertion stable.
- Expected danger priority behavior: mapped/merged priority respected.
- Expected proposal selection: chosen action/target uses derived priority.

### 6.13 Multiple targets with effects

- State includes effects across multiple mobs.
- Expected selection: highest-priority, then nearest distance, then lower target id tie-break.
- Expected isolation: no cross-target mutation.

### 6.14 Mob disappears or becomes invalid

- Mob missing/not enemy/dead in snapshot.
- Expected sweep/prune: target removed.
- Expected proposal behavior: no stale proposal for invalid mob.

## 7. Expected proposal parity contract

Enemy buff-removal proposals must match exactly on:

- `kind` / `action_type`
- `action_name`
- `target_id`
- `target_name`
- `effect_id` / `buff_id` fields (in `detail`)
- effect label/debug name behavior
- `priority` / `priority_band`
- `urgency`
- danger-weight derived fields (`detail.enemy_effect_priority`)
- reason/debug fields (`reason_code`, `detail` keys)
- provider/source fields (`provider`, `family_id`, proposal id prefix semantics)
- attempt key / cooldown key fields (`detail.enemy_dispel_attempt_key`, duplicate/recast keys)
- expected effect / expected ack fields
- movement/range/targeting metadata used by dispatch plan
- `expires_at` / `commit_deadline` fields

If `p1_collect_enemy_buff_removal` produces multiple proposals in any scenario, ordering must match.

## 8. State transition parity contract

Compare before/after with:

- Table keys
- Table value types
- Target id key types
- Effect id key types
- Timestamp values (deterministic `now` injection or normalized comparison)
- `nil` vs `false` vs empty string behavior
- Missing table initialization behavior
- Mutation scope (no unrelated target/effect state changes)
- Proposal count and proposal field equality
- No side-effect execution
- Attempt map cooldown behavior
- Clear/prune/sweep behavior

## 9. Replay harness requirements

A future replay harness must:

- Load fixture tables.
- Run old and new implementations with identical inputs.
- Stub readiness functions deterministically.
- Stub Windower mob/claim lookups deterministically.
- Stub catalog/resource lookups deterministically.
- Freeze `now_s` with fixture `now`.
- Capture before/after enemy effect state.
- Capture before/after enemy dispel attempt map.
- Capture proposal list before ranking.
- Compare structural equality.
- Report first mismatch with fixture name, state path, expected value, actual value.
- Never emit command/movement/facing/target-selection side effects during replay.

## 10. Live-log validation requirements

Before moving `p1_collect_enemy_buff_removal` or `ingest_enemy_effects_from_raw_action_028`, capture in-game:

- Raw action `0x028` packets/events.
- Parsed effect list.
- Target id and target name.
- Claim id and party-claim-set state.
- Mob validity state.
- Catalog/dispel map lookup result.
- `enemy_effect_state` before/after.
- `enemy_dispel_attempt_map` before/after.
- Readiness decisions for dispel/finale/removal actions.
- Proposal list before ranking.
- Selected proposal.
- No-op/reject reason.
- Emitted command or explicit no-command result.

## 11. Stop conditions

This document does not permit moving:

- `p1_collect_enemy_buff_removal`
- `ingest_enemy_effects_from_raw_action_028`
- Enemy effect state mutators
- Enemy dispel attempt mutators
- `load_enemy_dispel_map_from_json`
- `load_targetbar_catalogs_once`
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

1. Non-runtime maintenance replay harness skeleton design.
2. Non-runtime enemy-effect replay harness skeleton design.
3. Create isolated replay fixture files only if repo convention is explicit and stable.
4. Enemy-effect state schema freeze after inspecting exact runtime state shapes.
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
- Only `docs/enemy_effect_replay_fixture_design.md` was created for this task.
