# Unified Scheduler Responsibility Map

Status: **Phase 6 cleanup complete**
Verified: 2026-07-24 by repository-wide static/replay validation and live
acceptance on all active profiles. Live path-follow remains an accepted risk.
Phase 6 removes unreachable legacy execution and obsolete profile markers
without changing domain authority, proposal order, priority bands, or
dispatcher execution.
Runtime behavior intent: selection behavior remains stable; scheduler-owned
side effects cross one dispatcher contract, while domain providers append
proposals only.

## Purpose

This map records the implemented Phase 6 cleanup architecture. It replaces the
2026-05-15 pre-extraction draft and records the movement ownership boundary
selected in
`RFC/UnifiedCombat_scheduler_refactor_phase4_movement_ownership_decision.md`.

Current primary sizes:

| File | Lines | Current role |
| --- | ---: | --- |
| `unified_scheduler.lua` | 6,066 | Scheduler facade, provider wiring, dispatcher orchestration, movement coordination, lifecycle policy, and packet observation |
| `uc_provider_*.lua` | 1,672 across six modules | Defensive, combat, tank, enemy-buff, maintenance, and target/pull proposal generation |
| `unified_combat_core.lua` | 3,387 | Scheduler-facing selection helpers, movement decisions, WS coordination, and target-scoped skillchain state |
| `unified_engine.lua` | 359 | 0.20-second lifecycle tick, overlay rendering, and one scheduler invocation; no core fallback |
| `uc_movement_dispatcher.lua` | 169 | Shared dispatcher-backed movement execution adapter |
| `uc_domain_ownership.lua` | 42 | Strict active-config domain enablement |
| `uc_scheduler_pull_executor.lua` | 68 | Dispatcher-backed target, movement, command, and settle adapter for scheduler pull |

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
| Domain ownership policy | `uc_domain_ownership.lua` | Authoritative combat, defensive, movement, and maintenance enablement; party follow reads its own authoritative follow-domain setting |
| Context leaf helpers | `uc_scheduler_context_utils.lua` | Settings, zone, partner target, and maintenance-city helpers |
| Tick context | `uc_scheduler_context.lua` | `p1_build_ctx` wrapper; one cached context shared by target acquisition and proposal collection/ranking |
| Defensive pure helpers | `uc_scheduler_defensive_utils.lua` | Buff, cure, debuff, priority, and danger calculations |
| Dispatch-plan structure | `uc_scheduler_dispatch_plan.lua` | `p1_build_dispatch_plan`, `p1_revalidate_plan_commit` |
| Dispatcher contract | `uc_scheduler_dispatcher.lua` | Intent validation, commit validation, exactly-once post-execution hooks, and injected-dependency execution |
| Scheduler movement facade | `uc_scheduler_movement_facade.lua` | Dispatcher-backed stop, heading, forward, turn, move-towards, and move-away execution |
| Scheduler pull executor | `uc_scheduler_pull_executor.lua` | Required dispatcher-backed target, movement, action, and settle dependencies for the core pull decision helper |
| Dry-run publication | `uc_scheduler_dryrun_publish.lua` | Ranked queue/global publication |
| Enemy-effect leaf helpers | `uc_scheduler_enemy_effect_utils.lua` | Labels, normalization, priority conversion, claim validation |
| Enemy-effect state | `uc_scheduler_enemy_effect_state.lua` | Catalog loading, effect/attempt maps, raw ingestion, removal classification, and scheduler wrappers |
| Geometry | `uc_scheduler_geometry.lua` | Angle normalization and front-arc checks |
| Phase 1 locks | `uc_scheduler_locks.lua` | Pending-live predicate, duplicate suppression, lock state, summary, reset |
| Maintenance pure helpers | `uc_scheduler_maintenance_utils.lua` | Set, split, dedupe, and buff-count helpers |
| Numeric normalization | `uc_scheduler_numeric_utils.lua` | `p1_number`, urgency clamp, boolean setting |
| Partner arbitration | `uc_scheduler_partner_arbitration.lua` | Pure arbitration decision |
| Pending record/lifecycle | `uc_scheduler_pending_record.lua`, `uc_scheduler_pending.lua` | Pending construction, state transitions, globals |
| Party-state IPC | `uc_scheduler_party_state.lua` | Encode, throttle/send, parse/apply, TTL, and lookup wrappers |
| Defensive proposals | `uc_provider_defensive.lua` | Internal and HealBot proposal adapters |
| Combat proposals | `uc_provider_combat.lua` | WS, Sleep, engage, and configured-JA proposal adapters |
| Tank enmity proposals | `uc_provider_tank_enmity.lua` | Tank selector-to-proposal adapter |
| Enemy-buff removal proposals | `uc_provider_enemy_buff_removal.lua` | Authoritative enemy-effect tracker to dispel proposal adapter |
| Maintenance proposals | `uc_provider_maintenance.lua` | COR, BRD, and GEO proposal adapters |
| Target and pull proposals | `uc_provider_target_control.lua` | Target acquisition, add-control retarget, and pull proposal adapters |
| Proposal schema/normalization | `uc_scheduler_proposals.lua` | Identity validation, timestamp/default normalization, created-age, and engage-priority policy |
| Proposal keys | `uc_scheduler_proposal_keys.lua` | Family and attempt keys |
| Validation, scoring, and ranking | `uc_scheduler_ranker.lua` | Explicit dependency interface behind scheduler validation/rank wrappers |
| Rank/reject presentation | `uc_scheduler_rank_output.lua`, `uc_scheduler_reject_history.lua` | Top-N formatting/capture and recent reject history |
| Observability facade | `uc_scheduler_observability.lua` | Dry-run publication, rank/reject formatting, debug overlay, and enemy-effect overlay |
| Status snapshot parsing | `uc_scheduler_status_snapshot_parser.lua` | `0x063` parse helper |
| Target helpers | `uc_scheduler_target_utils.lua` | Target distance and tank-enmity selection predicates |
| Text helpers | `uc_scheduler_text_utils.lua` | Split, decode, normalization, Roman numeral helpers |
| Ownership seams | `uc_scheduler_command_ownership.lua`, `uc_scheduler_run_ownership.lua`, `uc_scheduler_run_stop_ownership.lua`, `uc_scheduler_target_ownership.lua`, `uc_scheduler_turn_ownership.lua` | Dispatcher-only execution and status publication; transitional flags and direct fallbacks are retired |

## Current scheduler-owned responsibilities and façade seams

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
- reads normalized active configuration through the established config facade;
- exposes state consumed by extracted modules.

Target:

- keep a small root coordinator state;
- keep tick snapshot construction behind `uc_scheduler_context.lua`;
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

- `uc_scheduler_context.lua` samples player, self mob, target, party, mob array,
  and time through explicit dependencies;
- `scheduler.process_tick` caches one context and supplies it to nonblocking
  target acquisition and proposal collection/ranking;
- providers use snapshot fields rather than resampling Windower state.

Status: **Phase 1 extracted; retain the scheduler wrapper for compatibility.**

Priority/risk: **retain / high**

### 3. Proposal providers

Functions:

- `uc_provider_defensive.collect_internal`
- `uc_provider_defensive.collect_healbot`
- `uc_provider_combat.collect_offense`
- `uc_provider_combat.collect_sleep`
- `uc_provider_combat.collect_engage`
- `uc_provider_combat.collect_ja`
- `uc_provider_tank_enmity.collect`
- `uc_provider_enemy_buff_removal.collect`
- `uc_provider_maintenance.collect`
- `uc_provider_target_control.collect_target`
- `uc_provider_target_control.collect_pull`
- `p1_collect_proposals`
- `scheduler.p1_brd_lane_blocks_proposal`

Current responsibility:

- the six dependency-injected provider modules build all primary proposals and
  apply existing domain/provider gates;
- `p1_collect_proposals` preserves the established collection sequence and
  remains the scheduler-owned coordinator;
- providers call scheduler-facing selectors in core and maintenance modules,
  but do not dispatch, acquire locks, move, turn, target, or attack.

Target:

- retain cohesive provider modules against one explicit tick context;
- preserve proposal fields, priority bands, collection order, and dispatcher
  separation during later domain cutover.

Status: **Phase 3 extracted, replay verified, and multibox field accepted.**

Priority/risk: **retain / high**

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

- `uc_scheduler_proposals.lua` validates identity and normalizes live fields;
- `uc_scheduler_ranker.lua` applies settings, pending, reaction, duplicate, and
  lock rejection, calculates score, and applies deterministic ordering;
- scheduler wrappers retain engage preemption and existing call signatures.

Status: **Phase 1 extracted and replay verified.** Strict missing-field
rejection remains a separate behavior task.

Priority/risk: **retain / high**

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
- `scheduler.apply_brd_maintenance_movement_lock`
- `scheduler.refresh_brd_maintenance_movement_lock`
- `scheduler.handle_local_spell_action_message`

Current responsibility:

- combines extracted action-state primitives with scheduler-specific spell,
  Cure, tank, Bard movement-safety, and engage policies.

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

- `uc_scheduler_enemy_effect_state.lua` owns the scheduler effect/attempt maps,
  JSON catalog, raw-action ingestion, death/removal classification, and unknown
  observation dedupe;
- `uc_enemy_effect_tracker.lua` remains the authoritative observed-effect
  tracker consumed by proposal collection;
- scheduler wrappers preserve packet/action entrypoints and overlay inputs.

Status: **Phase 1 extracted and replay verified.**

Priority/risk: **retain / high**

### 7. Party state IPC

Functions/state:

- `encode_party_state_payload`
- `maybe_broadcast_party_state_ipc`
- `apply_party_state_ipc_message`
- `get_party_state_ipc_entry`
- `scheduler.on_ipc_message`
- `scheduler.party_state_ipc`

Current responsibility:

- `uc_scheduler_party_state.lua` encodes, throttles/sends, receives, sequence
  checks, expires, and queries scheduler party state;
- the scheduler keeps its public IPC event entrypoint and state table.

Status: **Phase 1 extracted and replay verified.**

Priority/risk: **retain / medium**

### 8. Defensive and maintenance decision implementation

Functions:

- party/resource/readiness helpers from `in_party_cast_range` through
  `action_ready`
- cure, debuff, priority, attempt, duration, recent-gain, and family-token
  helpers
- `build_defensive_candidates`
- `choose_defensive_action`
- `choose_cure_spell`
- maintenance cache and song snapshot helpers

Current responsibility:

- owns defensive candidate construction and scheduler lifecycle policy;
- delegates pure leaf operations to extracted helper modules;
- extracted defensive and maintenance adapters convert existing selections into
  proposal records for the ranked scheduler path.

Target:

- retain the extracted providers and ranked scheduler execution path.

Priority/risk: **high / high**

### 9. Movement, reaction, encounter, and partner coordination

Functions:

- `scheduler.try_partner_tiebreak`
- `scheduler.apply_reaction_turn`
- `scheduler.apply_reaction_response`
- `scheduler.refresh_reaction_lock`
- `scheduler.apply_cast_movement_hold`
- `run_movement_coordinator_tick`
- `p1_apply_face_to_target`

Current responsibility:

- coordinates Nyzul, reaction, Lilith formation, cast freeze, pull holds, domain
  eligibility, and core movement decisions through an injected dispatcher facade;
- cast-freeze branches actively cancel an existing spacing run vector and hold
  scheduler movement ownership until the cast state clears;
- stops before Bard maintenance execution and refreshes scheduler movement
  ownership throughout the reserved Bard action lane, including the bounded
  late-confirmation window between dispatched Pianissimo and its paired song,
  even when a generated Pianissimo retry proposal is not dispatched;
- publishes movement owner/block diagnostics.

Status:

- scheduler movement coordinator and core movement decision helper use one
  injected dispatcher movement facade backed by `uc_movement_dispatcher.lua`;
- independent follow, pathing, Nyzul, formation, and lifecycle decision owners
  execute movement through the same shared adapter;
- legacy core movement execution is deleted.

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
- `p1_dispatch_combat`
- `scheduler.dispatch_selected_plan`
- ownership status-shape helpers

Current responsibility:

- performs commit-time live reads and domain gates;
- constructs dispatcher intents;
- calls dispatcher-only ownership helpers;
- records sent/action/pending state;
- injects low-level action and movement adapters into the dispatcher.

Status:

- scheduler selects and plans;
- dispatcher validates commits and is the only scheduler-owned action executor;
- skillchain generation marking is an exactly-once post-execution hook;
- scheduler pull injects `uc_scheduler_pull_executor.lua`; the core helper has
  no implicit direct executor.

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

- `uc_scheduler_observability.lua` combines rank/reject formatters, dry-run
  publication, debug-overlay formatting, and enemy-effect presentation;
- scheduler-owned diagnostic log/timeline event production remains local;
- scheduler public overlay methods delegate formatting while preserving
  `_G.UC_*` and bridge/overlay shapes.

Status: **Phase 1 formatting consolidation complete and replay verified.**

Priority/risk: **retain / medium-high**

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
- renders scheduler overlays.

Target:

- lifecycle and one scheduler call per tick;
- core fallback removed in Phase 5;
- move overlay rendering only after observability extraction.

### `unified_combat_core.lua`

Current:

- exposes scheduler-facing WS, tank, pull, target, and movement decision helpers;
- owns target-scoped skillchain state while its scheduler-owned WS send and
  movement path execute through injected dispatcher contracts.

Target:

- retain only helpers with proven scheduler callers;
- keep execution dependency-injected and dispatcher-backed;
- do not reintroduce the removed legacy tick or direct executors.

### Independent movement owners

Current:

- `uc_party_follow.lua`
- `uc_pathing.lua`
- `uc_nyzul_runtime.lua`
- lifecycle stop in `UnifiedCombat.lua`

`uc_lilith_easy_formation_runtime.lua` is a separate decision owner.

Execution:

- all listed owners use `uc_movement_dispatcher.lua`;
- no listed owner directly calls `windower.ffxi.run(...)`;
- follow/pathing cadence and arbitration remain independent of ranked scheduler
  proposals;
- active path movement publishes and releases owner `path`;
- disabled or suppressed follow releases only follow-owned movement and does not
  erase another owner's lock.

## Current highest-risk areas

1. Packet/action observation fan-out.
2. Defensive/tank spell and engage lifecycle state.
3. Live validation after Phase 6 deletion of unreachable legacy branches.
4. Live path-follow parity remains an accepted, unclosed field risk.

## Phase 6 completion boundary

1. Proposal keys, priority bands, rejection taxonomy, provider order, and public
   scheduler event wrappers remain unchanged.
2. The legacy core tick, its direct execution branches, scheduler-local
   defensive fallbacks, obsolete ownership markers, and unused helpers are
   removed.
3. Historical `_G.UC_SCHED_P1_DARKLAUNCH_*` validation payloads and
   `BLOCK_SCHED_P1_DARKLAUNCH_*` reason strings remain because the RFC requires
   a bridge/UI replacement before those diagnostic contracts are collapsed.
4. Live reload and multibox combat/maintenance/movement acceptance remains the
   Phase 6 exit gate. Live path-follow remains the previously accepted risk.

Treat stricter proposal validation or a proposal-based movement redesign as
separate future behavior changes.
