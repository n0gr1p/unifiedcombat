# Unified Scheduler Responsibility Map (Pre-Extraction Baseline)

Status: Draft (documentation-only)
Scope: Current `unified_scheduler.lua` responsibilities before mechanical extraction
Date: 2026-05-15
Related: `docs/unified_scheduler_rfc.md`, `docs/unified_scheduler_phase1_amendment.md`, `docs/unified_scheduler_design.md`, `docs/scheduler_work_tracking.md`, `docs/core_vs_scheduler_gap_checklist.md`, `docs/movement_coordinator_implementation_checklist.md`, `docs/side_effect_inventory.md`

## Purpose
This map documents what `unified_scheduler.lua` currently owns so extraction tasks can move code by verified responsibility rather than by guesswork.

Notes:
- This is a code-observed inventory, not a behavior proposal.
- When classification is ambiguous, entries are marked mixed/uncertain.
- No runtime behavior changes are defined here.

## 1) Time/source helpers
- Functions:
  - `now_s`
  - `p1_number`
  - `p1_clamp_urgency`
  - `current_zone_id`
- Important state:
  - `socket_gettime`
  - `time_source_error_reported`
- Current responsibility:
  - Provide canonical wall-clock time and numeric normalization used by cooldowns, pending deadlines, locks, and scheduler scoring fields.
- Known side effects:
  - None.
- Should eventually become:
  - `uc_scheduler_context.lua`
- Extraction priority:
  - Medium
- Extraction risk:
  - Medium (time source consistency is a coordinator/scheduler invariant)
- Dependencies/blockers:
  - Must preserve fail-fast time behavior used by movement coordinator timing expectations.

## 2) Logging/diagnostics/debug globals
- Functions:
  - `log_ja_sched`, `log_tank_sched`, `log_combat_sched`, `log_def_sched`
  - `ensure_diag_logs_initialized`
  - `enemy_dispel_diag`, `enemy_dispel_log`, `enemy_effect_log_label`
  - `p1_format_top3`, `p1_format_top3_verbose`, `p1_format_topn_lines`, `p1_capture_topn_items`, `p1_push_recent_rejects`, `p1_reject_top`
  - `scheduler.get_debug_overlay`, `scheduler.get_enemy_effect_table_overlay`
- Important state:
  - `_G.UC_LOG_*` flags, `_G.UC_SCHED_P1_*` debug globals
  - `diag_init`
  - `scheduler.phase1.last_top*`, `recent_rejects`, `recent_reject_items`
- Current responsibility:
  - Build diagnostic logs, ranked-candidate overlays, reject summaries, and exported debug fields for in-game and remote visibility.
- Known side effects:
  - File append logging to `data/logs/*_*.log`.
  - Writes many `_G.UC_SCHED_P1_*` and `_G.UC_*` observability globals.
- Should eventually become:
  - `uc_scheduler_observability.lua`
- Extraction priority:
  - High
- Extraction risk:
  - Medium (high coupling to many internals, but low gameplay authority if interfaces are preserved)
- Dependencies/blockers:
  - Keep output field names stable until downstream UI/bridge consumers are migrated.

## 3) Scheduler public API
- Functions:
  - `scheduler.process_tick`
  - `scheduler.on_ipc_message`
  - `scheduler.on_incoming_chunk`
  - `scheduler.on_action`
  - `scheduler.on_action_message`
  - `scheduler.reset_runtime_locks`
  - `scheduler.get_debug_overlay`
  - `scheduler.get_enemy_effect_table_overlay`
  - global wrappers: `_G.UC_SCHED_On*`, `_G.UC_ResetSchedulerRuntimeLocks`
- Important state:
  - `scheduler` table root
  - `scheduler.phase1`
  - `scheduler.party_state_ipc`
  - `scheduler.action_state`
- Current responsibility:
  - Own module entrypoints for tick processing, packet/action observation, runtime lock reset, and diagnostics.
- Known side effects:
  - Directly calls movement/dispatch helpers that issue commands and run controls.
- Should eventually become:
  - remain in `unified_scheduler.lua` (as facade), with internals extracted
- Extraction priority:
  - Low
- Extraction risk:
  - Medium (API surface is integration point with engine/core/global hooks)
- Dependencies/blockers:
  - Any extraction must preserve current function names/signatures used by `unified_engine.lua` and global hook callbacks.

## 4) Tick orchestration
- Functions:
  - `scheduler.process_tick`
  - `p1_run_dry`
  - `p1_try_dark_launch_dispatch`
  - `run_movement_coordinator_tick`
  - doom pre-check path: `try_doom_water_emergency`
- Important state:
  - `_sched_next_defensive_at`, `_sched_next_maintenance_at` (settings scratch)
  - `_G.UC_LAST_SCHED_ACTION`, `_G.UC_SCHED_PROVIDER`
- Current responsibility:
  - Per-tick orchestration order: diagnostics setup, party IPC broadcast, doom emergency, phase1 dry-run select, dark-launch dispatch, movement coordinator tick, and legacy defensive fallback dispatch.
- Known side effects:
  - Via called paths: command dispatch, movement stop/run, target set, global-state writes.
- Should eventually become:
  - uncertain
- Extraction priority:
  - High
- Extraction risk:
  - High (this is the highest authority path; order changes can alter behavior)
- Dependencies/blockers:
  - Must preserve current precedence ordering documented in work tracking and dark-launch assumptions.

## 5) Context/snapshot building
- Functions:
  - `p1_build_ctx`
  - `get_settings`
  - helpers feeding context/guard checks (`get_party_members`, `p1_build_party_id_set`, `build_partner_target_set`)
- Important state:
  - `scheduler.phase1.tick`
  - `scheduler.maintenance_state.status_snapshot`
  - cached player/party/mob snapshots in ctx
- Current responsibility:
  - Build per-tick scheduler context and lightweight participant snapshots.
- Known side effects:
  - None directly.
- Should eventually become:
  - `uc_scheduler_context.lua`
- Extraction priority:
  - High
- Extraction risk:
  - Medium (widely consumed by provider collectors and rank/lock logic)
- Dependencies/blockers:
  - Requires stable ctx contract before moving provider code into separate modules.

## 6) Proposal schema/normalization helpers
- Functions:
  - name/text normalization: `normalize_action_name_like_healbot`, `decode_json_escapes`, `to_roman_numeral`, `ucfirst`
  - proposal field helpers: `action_target_mode`, `build_action_command`, `family_key`, `attempt_key`
  - numeric/schema normalization: `p1_number`, `p1_clamp_urgency`
- Important state:
  - `spell_name_cache`, `ja_name_cache`
  - `scheduler.attempted`, `last_overwrite`, `family_*`
- Current responsibility:
  - Normalize names and construct proposal-compatible identifiers/commands/keys for downstream validation and dispatch.
- Known side effects:
  - None directly.
- Should eventually become:
  - `uc_scheduler_proposals.lua`
- Extraction priority:
  - Medium
- Extraction risk:
  - Medium (string normalization impacts resource lookups and duplicate keys)
- Dependencies/blockers:
  - Must remain aligned with action readiness helpers and provider output schema.

## 7) Provider collection functions
- Functions:
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
  - `p1_collect_proposals` (collector orchestrator)
- Important state:
  - `scheduler.phase1.maintenance_next_at`
  - `maintenance_buff_cache`, `maintenance_state`
- Current responsibility:
  - Convert domain logic into proposal lists across combat/defensive/target/pull/tank/maintenance lanes.
- Known side effects:
  - Collection functions are mostly proposal-only; some logging/global diagnostics updated indirectly.
- Should eventually become:
  - provider module
- Extraction priority:
  - High
- Extraction risk:
  - High (largest surface and strongest behavior-coupling risk)
- Dependencies/blockers:
  - Requires stable shared ctx helpers and proposal schema helpers.
  - Must preserve cadence assumptions (5Hz/2Hz/1Hz domains) and dark-launch lane behavior.

## 8) Validation/scoring/ranking functions
- Functions:
  - `p1_validate_proposal`
  - `p1_score`
  - `p1_rank`
  - `p1_revalidate_plan_commit`
- Important state:
  - `scheduler.phase1.pending`
  - `scheduler.phase1.recent_duplicate_until`
- Current responsibility:
  - Enforce proposal validity, lock/duplicate rejection, deterministic ranking, and commit-edge revalidation.
- Known side effects:
  - Writes eval metadata (`_score`, `_score_parts`) to ranked proposal objects.
- Should eventually become:
  - `uc_scheduler_ranker.lua`
- Extraction priority:
  - High
- Extraction risk:
  - High (directly controls winner selection and no-op reasons)
- Dependencies/blockers:
  - Strong coupling with lock/pending structures and duplicate suppression contracts.

## 9) Action state and pending lifecycle
- Functions:
  - action-state helpers: `action_state`, `action_mark_sent`, `action_mark_packet_start`, `action_mark_packet_end`, `action_is_acting`, `action_dispatch_blocked`
  - pending lifecycle: `p1_pending_is_live_state`, `p1_update_pending_state`, `p1_pending_mark_complete`, `p1_set_pending_globals`, `p1_record_legacy_dispatch`
- Important state:
  - `scheduler.action_state.*`
  - `scheduler.phase1.pending`
  - `scheduler.phase1.recent_duplicate_until`
- Current responsibility:
  - Track in-flight action state and transition pending records from selected/sent through completion/timeout.
- Known side effects:
  - Writes runtime lock/pending debug globals.
- Should eventually become:
  - `uc_scheduler_dispatcher.lua`
- Extraction priority:
  - High
- Extraction risk:
  - High (timing/lifecycle bugs can create duplicate spam or lock starvation)
- Dependencies/blockers:
  - Packet observers and dispatch paths both mutate these structures.

## 10) Locks and duplicate suppression
- Functions:
  - `p1_get_locks`
  - `p1_hard_lock_reject`
  - `p1_duplicate_suppressed`
  - `p1_build_lock_summary`
  - `scheduler.reset_runtime_locks`
- Important state:
  - pending-derived lock state
  - `recent_duplicate_until`
  - `_G.UC_MOVE_FREEZE_PREP_*`, `_G.UC_ZONE_SUSPEND_UNTIL`
- Current responsibility:
  - Synthesize lock model from pending+zone guards and enforce duplicate suppression windows.
- Known side effects:
  - Runtime reset mutates global freeze state and action-state internals.
- Should eventually become:
  - `uc_scheduler_locks.lua`
- Extraction priority:
  - High
- Extraction risk:
  - High (lock semantics are central to non-oscillation and anti-repeat guarantees)
- Dependencies/blockers:
  - Must stay consistent with pending lifecycle and movement coordinator freeze behavior.

## 11) Dispatch plan construction
- Functions:
  - `p1_build_dispatch_plan`
  - plan usage in `p1_run_dry`
- Important state:
  - `scheduler.phase1.last_plan`
- Current responsibility:
  - Build prelude+primary plan object (`none/stop` prelude in current path) from selected proposal.
- Known side effects:
  - None directly.
- Should eventually become:
  - `uc_scheduler_dispatcher.lua`
- Extraction priority:
  - Medium
- Extraction risk:
  - Medium (compact logic but contract-sensitive to amendment schema)
- Dependencies/blockers:
  - Needs lock/ranker/pending modules to agree on plan fields and commit checks.

## 12) Direct dispatch / dark-launch execution
- Functions:
  - `p1_try_dark_launch_dispatch`
  - `p1_try_target_prep`
  - `p1_target_distance_to_id`
  - `p1_move_toward_mob`
  - `p1_is_tank_enmity_selected`
  - selected direct-action send paths in this function (`/ws`, `/ja`, `/ma`, maint cor)
- Important state:
  - `scheduler.phase1.last_selected`, `last_plan`
  - `scheduler.phase1.tank_*_settle_*`
  - `_G.UC_LAST_SCHED_ACTION`
- Current responsibility:
  - Execute scheduler-selected proposals behind dark-launch toggles with pre-dispatch guards, range/target prep, settle windows, and legacy pending record updates.
- Known side effects:
  - `windower.send_command(...)`
  - `windower.ffxi.run(...)`
  - `uc_settarget.select_by_id(...)`
  - writes movement/dispatch globals.
- Should eventually become:
  - `uc_scheduler_dispatcher.lua`
- Extraction priority:
  - High
- Extraction risk:
  - High (highest side-effect density and lane-specific behavior)
- Dependencies/blockers:
  - Tight coupling to core helper APIs (`unified_combat_core.lua`), lock/pending model, and dark-launch flags.

## 13) Packet/action observation
- Functions:
  - `scheduler.on_incoming_chunk`
  - `scheduler.on_action`
  - `scheduler.on_action_message`
  - global hook wrappers `_G.UC_SCHED_On*`
- Important state:
  - `scheduler.phase1.last_action_message_sig*`
  - `scheduler.phase1.pending` transitions via observations
- Current responsibility:
  - Consume packet/action streams and advance pending/action locks and enemy effect updates.
- Known side effects:
  - Updates pending/action-state globals and effect tables.
- Should eventually become:
  - `uc_scheduler_observability.lua`
- Extraction priority:
  - Medium
- Extraction risk:
  - High (message duplication filters and completion detection are timing sensitive)
- Dependencies/blockers:
  - Must remain consistent with pending lifecycle state machine.

## 14) Enemy effect tracking / dispel state
- Functions:
  - ingestion/updates: `ingest_enemy_effects_from_raw_action_028`, `apply_effect_list_to_target`, `apply_catalog_effects`
  - state map ops: `enemy_effect_state_map`, `enemy_effect_state_set`, `enemy_effect_state_clear`, `enemy_effect_state_clear_target`, `enemy_effect_state_prune_expired`, `enemy_effect_state_sweep`
  - dispel policy: `enemy_dispel_attempt_map`, `can_attempt_enemy_dispel`, `mark_enemy_dispel_attempt`, `enemy_dispel_choose_action`, `enemy_dispel_claim_valid`, `is_enemy_mob_id`
  - data loaders: `load_enemy_dispel_map_from_json`, `load_targetbar_catalogs_once`
- Important state:
  - `scheduler.phase1.effectiveTargets`
  - `dispellable_enemy_effect_priority`, `dispellable_enemy_effect_set`
  - `enemy_effect_observed_once`
- Current responsibility:
  - Maintain scheduler-local enemy buff/effect state and select dispel candidates with anti-repeat gating.
- Known side effects:
  - File IO reads from `docs/ffxi_enemy_dispellable_buffs.json` and `TargetBar` catalogs.
- Should eventually become:
  - `uc_enemy_effect_state.lua`
- Extraction priority:
  - High
- Extraction risk:
  - Medium (domain-heavy but reasonably isolatable)
- Dependencies/blockers:
  - Needs clear contract boundary with `uc_enemy_effect_tracker` events and defensive collector logic.

## 15) Defensive helpers
- Functions:
  - buff/debuff/cure helpers: `resolve_doom_buff_id`, `player_has_doom`, `has_buff`, `estimate_missing_hp`, `available_cure_tier_max`, `cure_tier_for_missing_hp`, `get_usable_cure_from_tier`, `debuff_spell_for_buff_id`
  - action readiness/helpers: `get_spell_resource`, `spell_known_flag`, `job_id_by_short`, `spell_usable_by_current_job`, `spell_known_and_usable`, `get_ja_resource`, `action_status_id`, `spell_ready`, `ja_ready`, `action_ready`, `action_duration_seconds`
  - candidate selection internals: `build_defensive_candidates`, `choose_defensive_action`, `try_internal_defensive_action`, `try_delegate_healbot`
  - family/recent gain helpers: `set_recent_gain`, `get_recent_gain`, `family_tokens_for`, `attempt_allowed`, `mark_attempt`, `count_buff_occurrences`, `is_bard_song`, `member_priority`, `pri_default`, `danger_level`, `cure_better`
- Important state:
  - `scheduler.attempted`, `last_overwrite`, `family_tokens`, `recent_gain`
  - `doom_last_item_at`
- Current responsibility:
  - Build and execute non-combat defensive intent paths (internal + healbot-delegated), including cure/debuff/buff prioritization and anti-overwrite throttles.
- Known side effects:
  - Via execution paths: `windower.send_command` for direct legacy/internal sends.
- Should eventually become:
  - provider module
- Extraction priority:
  - Medium
- Extraction risk:
  - Medium
- Dependencies/blockers:
  - Heavily intertwined with party state snapshots and pending/attempt throttles.

## 16) COR / maintenance helpers
- Functions:
  - maintenance scaffolding: `ensure_maintenance_buff_cache`, `count_matching_buffs`, `ensure_maintenance_state_tables`, `canon_name`, `split_actions`, `dedupe_numeric_ids`, `parse_status_snapshot_063`
  - collection path: `p1_collect_maintenance`
  - packet integration hook: `_G.UC_COR_MAINT_OnIncomingChunk`
- Important state:
  - `maintenance_buff_cache`
  - `scheduler.maintenance_state`
  - `scheduler.phase1.maintenance_next_at`
- Current responsibility:
  - Maintain BRD/GEO/COR maintenance proposal generation and status cache prep; integrate COR maintenance packet updates.
- Known side effects:
  - Dark-launch maintenance dispatch path issues `/ja` send commands (inside `p1_try_dark_launch_dispatch`).
- Should eventually become:
  - provider module
- Extraction priority:
  - Medium
- Extraction risk:
  - Medium
- Dependencies/blockers:
  - Maintenance cadence and state cache ownership must be stabilized with context module extraction.

## 17) Movement coordinator functions
- Functions:
  - `run_movement_coordinator_tick`
  - `p1_apply_face_to_target`
  - `p1_move_toward_mob`
  - related geometry helpers: `normalize_angle_rad`, `target_is_in_front_arc`
- Important state:
  - `_G.UC_MOVEMENT_MODE`, `_G.UC_MOVEMENT_BLOCK_REASON`, `_G.UC_MOVEMENT_OWNER`, `_G.UC_MOVEMENT_LOCK_UNTIL`
  - `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL`, `_G.UC_MOVE_FREEZE_PREP_UNTIL`
- Current responsibility:
  - Execute per-tick coordinator-owned movement/facing gate logic independent of proposal ranking winner.
- Known side effects:
  - `windower.ffxi.run(false)` and run heading calls.
  - `windower.ffxi.turn(...)` via face helper.
- Should eventually become:
  - `uc_scheduler_movement.lua`
- Extraction priority:
  - High
- Extraction risk:
  - High (timing and owner lock interactions are sensitive)
- Dependencies/blockers:
  - Must preserve movement coordinator checklist invariants (cast freeze, role gating, follow alignment).

## 18) Party state / IPC helpers
- Functions:
  - `encode_party_state_payload`
  - `maybe_broadcast_party_state_ipc`
  - `apply_party_state_ipc_message`
  - `get_party_state_ipc_entry`
  - `scheduler.on_ipc_message`
- Important state:
  - `scheduler.party_state_ipc.last_sent_at`, `send_interval`, `ttl`, `by_id`
  - `PARTY_STATE_IPC_PREFIX`
- Current responsibility:
  - Share/consume party snapshot state over IPC and expose that state to member-resolution logic.
- Known side effects:
  - IPC send/receive side effects through Windower addon messaging.
- Should eventually become:
  - `uc_scheduler_context.lua`
- Extraction priority:
  - Medium
- Extraction risk:
  - Medium
- Dependencies/blockers:
  - Consumers in defensive/maintenance member resolution must keep same payload fields.

## 19) Legacy bridge/fallback helpers
- Functions:
  - `try_doom_water_emergency`
  - `try_internal_defensive_action`
  - `try_delegate_healbot`
  - `p1_record_legacy_dispatch`
  - `_G.UC_SCHED_On*` wrapper functions (best-effort `pcall` bridge)
- Important state:
  - doom globals/cooldowns
  - pending record backfill from legacy sends
- Current responsibility:
  - Maintain pre-existing operational paths while scheduler dark-launch migration remains partial.
- Known side effects:
  - Direct item/spell command emission and pending/lock state mutation.
- Should eventually become:
  - uncertain
- Extraction priority:
  - Low
- Extraction risk:
  - High (removal/move sequencing depends on final cutover plan)
- Dependencies/blockers:
  - Blocked on scheduler full-domain cutover and explicit deprecation plan from workboard G7.

## 20) Unknown or mixed-responsibility functions
- Mixed/uncertain examples:
  - `action_effective_range` (used by action/range checks and tank/movement prep)
  - `ja_targets_enemy`, `ja_requires_engaged_front` (combat policy + dispatch gating)
  - `in_party_cast_range` (context + defensive policy)
  - `danger_weight_to_priority` (enemy dispel policy but also ranking semantics)
  - `is_city_zone_for_maintenance` (maintenance policy + world-state guard)
- Current responsibility:
  - Cross-cutting helpers that span multiple candidate modules.
- Known side effects:
  - None directly (for listed examples).
- Should eventually become:
  - uncertain
- Extraction priority:
  - Low
- Extraction risk:
  - Medium (misplacement can increase cyclic dependencies)
- Dependencies/blockers:
  - Best moved only after primary module boundaries are concretely implemented and imports settle.

## Current Highest-Risk Extraction Areas
1. Tick orchestration (`scheduler.process_tick` path ordering and mixed fallback sequencing).
2. Direct dark-launch dispatch (`p1_try_dark_launch_dispatch`) due to side-effect concentration.
3. Pending/lock lifecycle coupling (`p1_update_pending_state`, lock synthesis, packet-driven completion).
4. Movement coordinator ownership boundaries (`run_movement_coordinator_tick` + freeze/owner globals).
5. Provider collector split (large surface and domain coupling across combat/defensive/maintenance).

## Recommended Next Task
Create extraction stubs and explicit interface contracts (no behavior change) for:
1. `uc_scheduler_context.lua` (ctx/time/party IPC)
2. `uc_scheduler_locks.lua` (lock + duplicate model)
3. `uc_scheduler_dispatcher.lua` (plan + pending lifecycle + dispatch facade)

Then wire `unified_scheduler.lua` to call those stubs while preserving current execution order and globals.
