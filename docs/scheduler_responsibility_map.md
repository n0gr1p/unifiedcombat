# Unified Scheduler Responsibility Map

Status: **Phase 0 baseline complete**
Verified: 2026-07-24 at `ff5a56ced0158b1bdabb9413c168de5c0be6b523`
Runtime behavior change: none

## Purpose

This map records the current post-extraction hybrid architecture. It replaces
the 2026-05-15 pre-extraction draft and provides the baseline for the remaining
Phase 1 decomposition.

Current primary sizes:

| File | Lines | Current role |
| --- | ---: | --- |
| `unified_scheduler.lua` | 8,398 | Scheduler facade plus most providers, ranking, dispatch orchestration, movement coordination, enemy state, IPC, diagnostics, and packet observation |
| `unified_combat_core.lua` | 4,213 | Legacy/core combat and movement implementation plus scheduler-facing selection helpers and skillchain WS execution |
| `unified_engine.lua` | 409 | 0.20-second lifecycle tick, overlay rendering, scheduler invocation, and conditional core fallback |

The scheduler is larger than the approximately 5,300-line RFC snapshot because
new runtime behavior was added while only selected responsibilities were
extracted.

## Extracted scheduler boundaries

These modules are active and called by `unified_scheduler.lua`.

| Responsibility | Current module(s) | Scheduler compatibility surface |
| --- | --- | --- |
| Action resource metadata and predicates | `uc_scheduler_action_metadata.lua`, `uc_scheduler_action_predicates.lua` | Small local wrappers such as `action_effective_range`, `ja_targets_enemy`, and resource coercion helpers |
| Action lifecycle | `uc_scheduler_action_state.lua` | `action_state`, `action_mark_sent`, packet start/end, acting/block checks, spell completion/interruption bridges |
| Command construction | `uc_scheduler_command_builder.lua` | `build_action_command` |
| Active config readers | `uc_scheduler_config.lua` | Scheduler/provider-facing ownership, combat, tank, and debug reads |
| Context leaf helpers | `uc_scheduler_context_utils.lua` | Settings, zone, partner target, and maintenance-city helpers |
| Defensive pure helpers | `uc_scheduler_defensive_utils.lua` | Buff, cure, debuff, priority, and danger calculations |
| Dispatch-plan structure | `uc_scheduler_dispatch_plan.lua` | `p1_build_dispatch_plan`, `p1_revalidate_plan_commit` |
| Dispatcher contract | `uc_scheduler_dispatcher.lua` | Intent validation and injected-dependency execution |
| Dry-run publication | `uc_scheduler_dryrun_publish.lua` | Ranked queue/global publication |
| Enemy-effect leaf helpers | `uc_scheduler_enemy_effect_utils.lua` | Labels, normalization, priority conversion, claim validation |
| Geometry | `uc_scheduler_geometry.lua` | Angle normalization and front-arc checks |
| Phase 1 locks | `uc_scheduler_locks.lua` | Pending-live predicate, duplicate suppression, lock state, summary, reset |
| Maintenance pure helpers | `uc_scheduler_maintenance_utils.lua` | Set, split, dedupe, and buff-count helpers |
| Numeric normalization | `uc_scheduler_numeric_utils.lua` | `p1_number`, urgency clamp, boolean setting |
| Partner arbitration | `uc_scheduler_partner_arbitration.lua` | Pure arbitration decision |
| Pending record/lifecycle | `uc_scheduler_pending_record.lua`, `uc_scheduler_pending.lua` | Pending construction, state transitions, globals |
| Proposal keys | `uc_scheduler_proposal_keys.lua` | Family and attempt keys |
| Rank/reject presentation | `uc_scheduler_rank_output.lua`, `uc_scheduler_reject_history.lua` | Top-N formatting/capture and recent reject history |
| Status snapshot parsing | `uc_scheduler_status_snapshot_parser.lua` | `0x063` parse helper |
| Target helpers | `uc_scheduler_target_utils.lua` | Target distance and tank-enmity selection predicates |
| Text helpers | `uc_scheduler_text_utils.lua` | Split, decode, normalization, Roman numeral helpers |
| Ownership compatibility seams | `uc_scheduler_command_ownership.lua`, `uc_scheduler_run_ownership.lua`, `uc_scheduler_run_stop_ownership.lua`, `uc_scheduler_target_ownership.lua`, `uc_scheduler_turn_ownership.lua` | Dispatcher-first versus direct execution selection and status publication |

## Responsibilities remaining in `unified_scheduler.lua`

### 1. Time, config, and root state

Functions/state:

- `now_s`
- `get_settings`
- `scheduler.active_value_or_flat`
- `bool_setting`
- root `scheduler`, `phase1`, party IPC, maintenance, action, and spell-probe
  tables

Current responsibility:

- owns root mutable state and the scheduler wall-clock source;
- bridges flat and active config reads;
- exposes state consumed by extracted modules.

Target:

- keep a small root coordinator state;
- move tick snapshot construction into an explicit context/world-snapshot owner;
- do not duplicate settings ownership.

Priority/risk: **high / high**

### 2. Tick context construction

Functions:

- `p1_build_ctx`
- `get_party_members`
- `p1_build_party_id_set`
- `build_partner_target_set`
- `p1_prime_unclaimed_party_aggressive_ok`

Current responsibility:

- independently samples player, self mob, party, mob array, and time;
- increments `phase1.tick`.

Known boundary issue:

- `p1_try_nonblocking_target_acquire` and `p1_run_dry` build separate contexts
  during one engine tick, so the RFC tick-stable snapshot target is not met.

Target: `uc_scheduler_context.lua` or `uc_world_snapshot.lua`

Priority/risk: **high / high**

### 3. Proposal providers

Functions:

- `p1_collect_defensive_internal`
- `p1_collect_defensive_healbot`
- `p1_collect_combat_offense`
- `p1_collect_enemy_buff_removal`
- `p1_collect_combat_engage`
- `p1_collect_target_control`
- `p1_collect_pull_control`
- `p1_collect_combat_tank_enmity`
- `p1_collect_combat_ja`
- `p1_collect_maintenance`
- `p1_collect_proposals`
- `scheduler.p1_brd_lane_blocks_proposal`

Current responsibility:

- builds all primary scheduler proposals and applies domain/provider gates;
- calls scheduler-facing selectors in core and maintenance modules.

Target:

- pure provider modules grouped by defensive, combat, tank, enemy-effect,
  maintenance, target, and pull ownership;
- providers receive one explicit context and append proposals only.

Priority/risk: **high / high**

### 4. Proposal schema, validation, scoring, and ranking

Functions:

- `p1_number`
- `p1_clamp_urgency`
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `scheduler.p1_priority_bypasses_engage`
- `scheduler.p1_pick_preemptive_engage`

Current responsibility:

- normalizes proposal fields in place;
- supplies default timestamps/deadlines;
- applies settings, pending, reaction, duplicate, and lock rejection;
- calculates score and deterministic ordering;
- applies engage-specific preemption.

Target:

- `uc_scheduler_proposals.lua` for schema/normalization;
- `uc_scheduler_ranker.lua` for validation/scoring/ranking.

Extraction must preserve bands, tie-breaks, rejection taxonomy, and side-effect
counts. Strict missing-field rejection is a separate behavior task.

Priority/risk: **high / high**

### 5. Action and spell lifecycle orchestration

Functions:

- scheduler wrappers around `uc_scheduler_action_state`
- spell lifecycle probe functions
- `scheduler.on_incoming_text`
- tank spell wait functions
- defensive spell wait functions
- pending engage and engage-duplicate functions
- stale combat-spell release functions
- `scheduler.apply_defensive_spell_movement_lock`
- `scheduler.handle_local_spell_action_message`

Current responsibility:

- combines extracted action-state primitives with scheduler-specific spell,
  Cure, tank, and engage policies.

Target:

- keep domain-neutral lifecycle in `uc_scheduler_action_state.lua`;
- extract cohesive engage and defensive/tank spell policy only after interfaces
  are explicit.

Priority/risk: **high / high**

### 6. Enemy effect and dispel state

Functions/state:

- `load_enemy_dispel_map_from_json`
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
- `ingest_enemy_effects_from_raw_action_028`
- dispellable-effect tables and observed-once state

Current responsibility:

- owns a scheduler effect table in addition to using
  `uc_enemy_effect_tracker.lua`;
- ingests catalogs, raw action data, action messages, and removal events;
- feeds enemy-dispel proposals and overlays.

Target:

- one explicit enemy-effect state owner, either a new
  `uc_enemy_effect_state.lua` or a deliberately expanded
  `uc_enemy_effect_tracker.lua`.

Priority/risk: **high / high**

### 7. Party state IPC

Functions/state:

- `encode_party_state_payload`
- `maybe_broadcast_party_state_ipc`
- `apply_party_state_ipc_message`
- `get_party_state_ipc_entry`
- `scheduler.on_ipc_message`
- `scheduler.party_state_ipc`

Current responsibility:

- encodes, broadcasts, receives, expires, and queries scheduler party state.

Target: `uc_scheduler_party_state.lua` after the higher-priority context, ranker,
and enemy-state extractions.

Priority/risk: **medium / medium**

### 8. Defensive and maintenance decision implementation

Functions:

- party/resource/readiness helpers from `in_party_cast_range` through
  `action_ready`
- cure, debuff, priority, attempt, duration, recent-gain, and family-token
  helpers
- `build_defensive_candidates`
- `choose_defensive_action`
- `choose_cure_spell`
- `try_delegate_healbot`
- `try_internal_defensive_action`
- maintenance cache and song snapshot helpers

Current responsibility:

- owns candidate construction and legacy defensive execution compatibility;
- delegates pure leaf operations to extracted helper modules.

Target:

- defensive provider plus separate legacy compatibility adapter until cutover;
- maintenance provider adapters.

Priority/risk: **high / high**

### 9. Movement, reaction, encounter, and partner coordination

Functions:

- `scheduler.try_partner_tiebreak`
- `scheduler.apply_reaction_turn`
- `scheduler.apply_reaction_response`
- `scheduler.refresh_reaction_lock`
- `run_movement_coordinator_tick`
- `p1_apply_face_to_target`
- dormant `p1_move_toward_mob`

Current responsibility:

- coordinates Nyzul, reaction, Lilith formation, cast freeze, pull holds, domain
  eligibility, and core movement delegation;
- publishes movement owner/block diagnostics.

Target:

- explicit movement coordinator plus one movement execution facade;
- partner/reaction decisions remain separate pure owners where already
  extracted.

Priority/risk: **high / very high**

### 10. Dispatch orchestration

Functions:

- `try_doom_water_emergency`
- `p1_try_target_prep`
- `scheduler.p1_dispatch_target_control`
- `scheduler.p1_try_nonblocking_target_acquire`
- `p1_dispatch_combat_engage`
- `p1_dispatch_pull_control`
- `p1_dispatch_maintenance_cor`
- `scheduler.p1_dispatch_maintenance_brd`
- `p1_dispatch_defensive_internal`
- `p1_dispatch_defensive_healbot`
- `p1_try_dark_launch_combat_dispatch`
- `scheduler.p1_try_dark_launch_dispatch`
- ownership status-shape helpers

Current responsibility:

- performs commit-time live reads and domain gates;
- constructs dispatcher intents;
- calls dispatcher-first ownership helpers;
- records sent/action/pending state;
- invokes indirect attack/target/movement executors.

Target:

- scheduler selects and plans;
- dispatcher validates commit and is the only action executor;
- locks/pending receive explicit dispatch outcomes.

Priority/risk: **highest / very high**

### 11. Dry-run, ranking presentation, and observability

Functions:

- `p1_run_dry`
- local wrappers around rank-output, reject-history, dispatch-plan, pending, and
  dry-run modules
- diagnostic log functions
- action timeline functions
- `ensure_diag_logs_initialized`
- `scheduler.get_debug_overlay`
- `scheduler.get_enemy_effect_table_overlay`

Current responsibility:

- combines extracted formatters with scheduler-owned logging, globals, overlays,
  timelines, and effect presentation.

Target:

- `uc_scheduler_observability.lua` after state inputs are stable;
- preserve `_G.UC_*` and bridge/overlay shapes during extraction.

Priority/risk: **medium / medium-high**

### 12. Packet and action observation

Functions:

- `scheduler.on_incoming_chunk`
- `scheduler.seed_cached_status_snapshot`
- `scheduler.on_action`
- `scheduler.on_action_message`
- `scheduler.on_incoming_text`

Current responsibility:

- fans raw observations into action state, spell lifecycle, enemy effect state,
  reaction state, sleep suppression, Bard maintenance, COR maintenance, and
  pending lifecycle.

Target:

- keep public observation entrypoints in the scheduler facade;
- delegate each event to explicit state owners.

Priority/risk: **high / very high**

### 13. Public scheduler facade

Functions:

- `scheduler.process_tick`
- `scheduler.on_ipc_message`
- `scheduler.on_incoming_chunk`
- `scheduler.on_action`
- `scheduler.on_action_message`
- `scheduler.on_incoming_text`
- `scheduler.reset_runtime_locks`
- `scheduler.get_debug_overlay`
- `scheduler.get_enemy_effect_table_overlay`
- `_G.UC_ResetSchedulerRuntimeLocks`

Current responsibility:

- integration surface for engine and Windower event forwarding.

Target:

- remain stable while implementation moves behind it;
- `process_tick` should eventually be a small
  snapshot → collect → validate/rank → plan → dispatch → publish coordinator.

Priority/risk: **retain / very high**

## Adjacent ownership boundaries

### `unified_engine.lua`

Current:

- runs the 0.20-second cadence;
- calls `scheduler.process_tick`;
- renders scheduler overlays;
- calls `_G.UC_CoreCombatTickOnce` when combat is not scheduler-owned.

Target:

- lifecycle and one scheduler call per tick;
- remove core fallback only through domain cutover;
- move overlay rendering only after observability extraction.

### `unified_combat_core.lua`

Current:

- owns direct combat and movement execution;
- exposes scheduler-facing WS, tank, pull, target, and movement helpers;
- owns the target-scoped skillchain runtime and direct skillchain WS send.

Target:

- retain compatibility helpers during migration;
- stop executing scheduler-owned actions after dispatcher cutover;
- do not remove wrappers until callers are proven migrated.

### Independent movement owners

Current:

- `uc_party_follow.lua`
- `uc_pathing.lua`
- `uc_nyzul_runtime.lua`
- `uc_lilith_easy_formation_runtime.lua`
- lifecycle stop in `UnifiedCombat.lua`

Target:

- one explicit movement execution API with domain-specific decision owners.

## Current highest-risk areas

1. Dispatch orchestration and its direct fallback ownership helpers.
2. Movement coordination across scheduler, core, follow, pathing, formation,
   Nyzul, and lifecycle.
3. Packet/action observation fan-out.
4. Defensive/tank spell and engage lifecycle state.
5. Enemy-effect state split between scheduler and tracker.
6. Multiple context builds and live reads within one engine tick.

## Recommended Phase 1 order

1. Extract proposal schema/normalization without changing fields.
2. Extract validation/scoring/ranking unchanged.
3. Define and introduce one explicit tick-context contract.
4. Extract enemy-effect state.
5. Extract provider modules after the context and ranker interfaces are stable.
6. Extract observability and party IPC after their state inputs are explicit.

Do not combine these mechanical extractions with stricter proposal validation,
dispatcher fallback removal, domain cutover, or movement behavior changes.
