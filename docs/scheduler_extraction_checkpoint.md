# Scheduler Extraction Checkpoint

> Historical pre-cutover checkpoint. Superseded for current ownership and
> callable surfaces by `scheduler_responsibility_map.md` and the Phase 6 exit
> audit in `../RFC/`.

## 1. Purpose
This is a post-helper-extraction checkpoint before touching higher-risk scheduler/provider/dispatch/readiness areas in `unified_scheduler.lua`.

It records what has already moved, what still remains local, and a conservative next-task order that avoids behavior drift.

## 2. Extracted Module Summary

### `uc_scheduler_locks.lua`
- Functions: `p1_pending_is_live_state`, `p1_duplicate_suppressed`, `p1_get_locks`, `p1_hard_lock_reject`, `p1_build_lock_summary`, `reset_runtime_locks`
- Classification: side-effect-free but state-aware (operates on passed scheduler/globals/action state)
- Dependency injection: yes (`scheduler`, `ctx`, `globals`, helper callbacks)
- Caveats: lock semantics are behavior-critical; keep pending/duplicate contracts stable.

### `uc_scheduler_pending.lua`
- Functions: `p1_update_pending_state`, `p1_set_pending_globals`, `p1_pending_mark_complete`
- Classification: stateful (mutates pending state/globals via passed objects)
- Dependency injection: yes (`scheduler`, `ctx`, helper callbacks)
- Caveats: deadline/timeout behavior must remain exact.

### `uc_scheduler_action_state.lua`
- Functions: `action_state`, `action_mark_sent`, `action_mark_packet_start`, `action_mark_packet_end`, `action_is_acting`, `action_dispatch_blocked`
- Classification: stateful (mutates `scheduler.action_state`)
- Dependency injection: yes (`scheduler`, `now_s`, `globals`)
- Caveats: action lock timing is sensitive.

### `uc_scheduler_dispatch_plan.lua`
- Functions: `p1_build_dispatch_plan`, `p1_revalidate_plan_commit`
- Classification: side-effect-free but state-aware
- Dependency injection: yes (`scheduler`, `ctx`, `windower`, helper callbacks)
- Caveats: commit revalidation behavior controls dispatch gating.

### `uc_scheduler_rank_output.lua`
- Functions: `p1_format_top3`, `p1_format_top3_verbose`, `p1_format_topn_lines`, `p1_capture_topn_items`, `p1_reject_top`
- Classification: pure/formatting
- Dependency injection: yes (`scheduler`, `p1_number`)
- Caveats: debug output shape should remain stable for UI/tools.

### `uc_scheduler_reject_history.lua`
- Functions: `p1_push_recent_rejects`
- Classification: stateful (mutates reject history arrays)
- Dependency injection: yes (`scheduler`, `ctx`)
- Caveats: history retention limits and item shape must stay unchanged.

### `uc_scheduler_pending_record.lua`
- Functions: `p1_record_legacy_dispatch`
- Classification: stateful
- Dependency injection: yes (`scheduler`, `ctx`, `p1_number`)
- Caveats: pending record schema is contract-sensitive.

### `uc_scheduler_dryrun_publish.lua`
- Functions: `publish`
- Classification: stateful/observability (writes scheduler phase fields and globals)
- Dependency injection: yes (many callbacks and structures)
- Caveats: large integration surface; keep output keys unchanged.

### `uc_scheduler_target_utils.lua`
- Functions: `p1_is_tank_enmity_selected`, `p1_target_distance_to_id`
- Classification: side-effect-free but Windower-read dependent
- Dependency injection: minimal (uses scheduler placeholder and Windower lookups)
- Caveats: distance/target validity behavior affects prep gates.

### `uc_scheduler_geometry.lua`
- Functions: `normalize_angle_rad`, `target_is_in_front_arc`
- Classification: pure-ish (`target_is_in_front_arc` reads Windower mob state)
- Dependency injection: none
- Caveats: used by facing/range readiness checks.

### `uc_scheduler_action_predicates.lua`
- Functions: `ja_targets_enemy`, `ja_requires_engaged_front`
- Classification: pure predicates
- Dependency injection: none
- Caveats: impacts JA targeting and front-arc requirements.

### `uc_scheduler_text_utils.lua`
- Functions: `to_roman_numeral`, `ucfirst`, `decode_json_escapes`, `normalize_action_name_like_healbot`
- Classification: pure string helpers
- Dependency injection: none
- Caveats: normalization impacts lookup keys and command names.

### `uc_scheduler_numeric_utils.lua`
- Functions: `p1_number`, `p1_clamp_urgency`
- Classification: pure numeric helpers
- Dependency injection: none
- Caveats: scoring/ctx math depends on exact fallback behavior.

### `uc_scheduler_proposal_keys.lua`
- Functions: `family_key`, `attempt_key`
- Classification: pure key builders
- Dependency injection: none
- Caveats: duplicate suppression and family tracking depend on key stability.

### `uc_scheduler_maintenance_utils.lua`
- Functions: `dedupe_numeric_ids`, `split_actions`, `canon_name`, `count_matching_buffs`, `count_buff_occurrences`
- Classification: pure helpers
- Dependency injection: none
- Caveats: maintenance parsing behavior should remain unchanged.

### `uc_scheduler_defensive_utils.lua`
- Functions: `debuff_spell_for_buff_id`, `has_buff`, `estimate_missing_hp`, `resolve_doom_buff_id`, `player_has_doom`, `member_priority`, `pri_default`, `danger_level`, `cure_better`, `cure_tier_for_missing_hp`, `is_bard_song`
- Classification: mostly pure helpers; doom helpers are cache-aware via caller-owned cache pass-through
- Dependency injection: yes for doom resolver callback and spell lookup callback
- Caveats: `doom_buff_id` canonical cache ownership remains in `unified_scheduler.lua` wrapper.

### `uc_scheduler_action_metadata.lua`
- Functions: `action_target_mode`, `action_status_id`, `action_duration_seconds`, `action_effective_range`
- Classification: side-effect-free metadata helpers
- Dependency injection: yes (resource lookups and `SCHED_RANGE_MULT`)
- Caveats: wrapper signatures must remain unchanged.

### `uc_scheduler_command_builder.lua`
- Functions: `build_action_command`
- Classification: pure command string builder
- Dependency injection: yes (`action_target_mode`)
- Caveats: command string spacing/quoting/target token formatting is behavior-critical.

### `uc_scheduler_status_snapshot_parser.lua`
- Functions: `parse_status_snapshot_063`
- Classification: pure parser / side-effect-free parser
- Dependency injection: none
- Caveats: parser contract is behavior-sensitive; extraction was gated by fixture parity.
- Fixture parity summary: 8 fixtures passed (nil/empty/short/wrong-type/single-row/multi-row/missing-fields/coercion-order cases).

## 3. Remaining Local Functions in `unified_scheduler.lua`

Legend for side-effect status:
- `pure`
- `stateful_no_side_effect`
- `reads_windower`
- `writes_scheduler_or_global`
- `performs_side_effects`
- `unknown_mixed`

### Public API / facade
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `get_settings` | `reads_windower` | facade/local | low | later | Facade accessor; thin and stable. |
| `bool_setting` | `pure` | `uc_scheduler_context` | low | later | Generic bool coercion helper. |

### Tick orchestration
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `now_s` | `unknown_mixed` | `uc_scheduler_context` | medium | later | Time-source fallback logic touches runtime invariants. |
| `run_movement_coordinator_tick` | `performs_side_effects` | movement/dispatcher lane | high | do not extract yet | Owns run/stop/freeze coordination. |
| `p1_run_dry` | `writes_scheduler_or_global` | orchestration split | high | do not extract yet | Central dry-run orchestration and state publication. |
| `p1_try_dark_launch_dispatch` | `performs_side_effects` | dispatcher lane | high | do not extract yet | Dispatch authority + command execution. |

### Context/snapshot building
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `current_zone_id` | `reads_windower` | `uc_scheduler_context` | low | now | Standalone helper. |
| `build_partner_target_set` | `reads_windower` | `uc_scheduler_context` | medium | later | Used by proposal collectors. |
| `is_city_zone_for_maintenance` | `reads_windower` | `uc_scheduler_context` | low | later | Small but used by maintenance cadence. |
| `get_party_members` | `reads_windower` | `uc_scheduler_context` | medium | later | Large snapshot builder with IPC overlay. |
| `p1_build_party_id_set` | `pure` | `uc_scheduler_context` | low | now | Pure helper over party snapshot. |
| `p1_prime_unclaimed_party_aggressive_ok` | `reads_windower` | combat provider module | medium | later | Context-derived engagement predicate. |
| `in_party_cast_range` | `reads_windower` | provider/shared helper | medium | later | Range gating depends on live player/target. |
| `p1_build_ctx` | `reads_windower` | `uc_scheduler_context` | high | later | Core context contract for all providers/ranker. |

### Resource lookup / action readiness
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `get_spell_resource` | `stateful_no_side_effect` | action metadata/readiness | medium | later | Reads + caches spell resources. |
| `spell_known_flag` | `pure` | readiness helper module | low | now | Simple coercion helper. |
| `job_id_by_short` | `pure` | readiness helper module | low | now | Static mapping helper. |
| `spell_usable_by_current_job` | `reads_windower` | readiness helper module | medium | later | Depends on live main/sub job state. |
| `spell_known_and_usable` | `reads_windower` | readiness helper module | medium | later | Job/known checks used widely in readiness. |
| `get_ja_resource` | `stateful_no_side_effect` | action metadata/readiness | medium | later | JA cache ownership still local. |
| `spell_ready` | `reads_windower` | readiness module | high | do not extract yet | Recast/MP/status gating critical. |
| `available_cure_tier_max` | `reads_windower` | defensive/readiness | medium | later | Calls `spell_ready`; readiness-coupled. |
| `get_usable_cure_from_tier` | `reads_windower` | defensive/readiness | medium | later | Readiness-coupled tier fallback. |
| `ja_ready` | `reads_windower` | readiness module | high | do not extract yet | Recast/range/front/TP/MP gates + status checks. |
| `action_ready` | `reads_windower` | readiness module | high | do not extract yet | Dispatcher-critical readiness multiplexer. |

### Proposal collection
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `build_defensive_candidates` | `writes_scheduler_or_global` | defensive provider module | high | do not extract yet | Dense behavior + throttles + provider interactions. |
| `p1_collect_defensive_internal` | `writes_scheduler_or_global` | defensive provider module | high | do not extract yet | Provider lane logic. |
| `p1_collect_defensive_healbot` | `writes_scheduler_or_global` | defensive provider module | high | do not extract yet | Provider lane + delegated behavior. |
| `p1_collect_combat_offense` | `reads_windower` | combat provider module | high | do not extract yet | Core offense proposal generation. |
| `p1_collect_enemy_buff_removal` | `writes_scheduler_or_global` | combat/utility provider | high | do not extract yet | Depends on enemy effect state/attempt throttles. |
| `p1_collect_combat_engage` | `reads_windower` | combat provider module | high | do not extract yet | Movement/engage lane coupling. |
| `p1_collect_target_control` | `reads_windower` | target-control provider | high | do not extract yet | Retarget/approach proposal lane. |
| `p1_collect_pull_control` | `reads_windower` | pull provider module | high | do not extract yet | Pull-loop behavior-sensitive. |
| `p1_collect_combat_tank_enmity` | `reads_windower` | combat provider module | high | do not extract yet | High-priority tank lane. |
| `p1_collect_combat_ja` | `reads_windower` | combat provider module | high | do not extract yet | JA provider lane coupling. |
| `p1_collect_maintenance` | `writes_scheduler_or_global` | maintenance provider module | high | do not extract yet | BRD/COR/GEO cadence and cache state. |
| `p1_collect_proposals` | `writes_scheduler_or_global` | provider orchestrator | high | do not extract yet | Aggregates all provider lanes. |

### Validation/scoring/ranking
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `p1_validate_proposal` | `reads_windower` | rank/validation module | high | do not extract yet | Central behavior gate for dispatch candidate safety. |
| `p1_score` | `stateful_no_side_effect` | rank module | high | do not extract yet | Ranking math directly changes selected proposal. |
| `p1_rank` | `stateful_no_side_effect` | rank module | high | do not extract yet | Winner ordering + deterministic tie behavior. |

### Dispatch / dark-launch execution
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `p1_try_target_prep` | `performs_side_effects` | dispatcher | high | do not extract yet | Contains target selection side effect. |
| `p1_target_distance_to_id` | `reads_windower` | target utils | medium | later | Could be merged after dispatcher boundaries settle. |
| `p1_is_tank_enmity_selected` | `stateful_no_side_effect` | target utils/combat lane | low | later | Small predicate wrapper. |

### Movement coordinator
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `p1_apply_face_to_target` | `performs_side_effects` | movement module | high | do not extract yet | Owns turn side effect and settle behavior. |
| `p1_move_toward_mob` | `performs_side_effects` | movement module | high | do not extract yet | Owns run/stop behavior. |

### Defensive / doom side-effect paths
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `resolve_doom_buff_id` | `stateful_no_side_effect` | keep wrapper | low | later | Wrapper preserves local doom cache ownership. |
| `player_has_doom` | `stateful_no_side_effect` | keep wrapper | low | later | Wrapper over extracted helper. |
| `try_doom_water_emergency` | `performs_side_effects` | dispatcher/legacy bridge | high | do not extract yet | Owns Holy Water emergency side effects. |
| `choose_defensive_action` | `stateful_no_side_effect` | defensive provider | medium | later | Pure selection but coupled to candidate shapes. |
| `try_delegate_healbot` | `performs_side_effects` | legacy bridge | high | do not extract yet | Sends external addon command calls. |
| `try_internal_defensive_action` | `performs_side_effects` | legacy bridge/dispatcher | high | do not extract yet | Direct command path. |

### Maintenance state/cadence
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `set_recent_gain` | `writes_scheduler_or_global` | maintenance state module | medium | later | Mutates `scheduler.recent_gain`. |
| `get_recent_gain` | `writes_scheduler_or_global` | maintenance state module | medium | later | Reads coupled maintenance cache keys. |
| `family_tokens_for` | `writes_scheduler_or_global` | maintenance state module | medium | later | Initializes/mutates token store. |
| `ensure_maintenance_buff_cache` | `writes_scheduler_or_global` | maintenance module | medium | later | Cache ownership still local. |
| `count_matching_buffs` | `pure` | maintenance utils | low | now | Small pure helper candidate. |
| `ensure_maintenance_state_tables` | `writes_scheduler_or_global` | maintenance state module | medium | later | Initializes shared maintenance state.
 |

### Enemy effect tracking / dispel state
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `load_enemy_dispel_map_from_json` | `performs_side_effects` | enemy effect module | medium | do not extract yet | File IO (`io.open`) + data ownership. |
| `load_targetbar_catalogs_once` | `stateful_no_side_effect` | enemy effect module | medium | later | Module-loading and cache init. |
| `apply_effect_list_to_target` | `writes_scheduler_or_global` | enemy effect module | medium | later | Mutates effect state tables. |
| `apply_catalog_effects` | `writes_scheduler_or_global` | enemy effect module | medium | later | Effect-state update path. |
| `enemy_dispel_diag` | `writes_scheduler_or_global` | observability module | low | later | Logging helper. |
| `enemy_dispel_log` | `writes_scheduler_or_global` | observability module | low | later | Logging helper. |
| `enemy_dispel_attempt_map` | `writes_scheduler_or_global` | enemy effect module | medium | later | Initializes mutable map. |
| `enemy_effect_state_map` | `writes_scheduler_or_global` | enemy effect module | medium | later | Initializes mutable map. |
| `enemy_effect_state_set` | `writes_scheduler_or_global` | enemy effect module | medium | later | State mutation helper. |
| `enemy_effect_state_clear` | `writes_scheduler_or_global` | enemy effect module | medium | later | State mutation helper. |
| `enemy_effect_state_clear_target` | `writes_scheduler_or_global` | enemy effect module | medium | later | State mutation helper. |
| `enemy_effect_state_prune_expired` | `writes_scheduler_or_global` | enemy effect module | medium | later | Time-based state prune. |
| `enemy_effect_state_sweep` | `writes_scheduler_or_global` | enemy effect module | medium | later | Bulk prune + guard logic. |
| `can_attempt_enemy_dispel` | `writes_scheduler_or_global` | enemy effect module | medium | later | Reads/writes attempt map gating. |
| `mark_enemy_dispel_attempt` | `writes_scheduler_or_global` | enemy effect module | medium | later | Mutates attempt map. |
| `enemy_dispel_choose_action` | `stateful_no_side_effect` | enemy effect module | medium | later | Selection over mutable effect state. |
| `is_enemy_mob_id` | `reads_windower` | enemy effect module | medium | later | Live mob classification helper. |
| `ingest_enemy_effects_from_raw_action_028` | `writes_scheduler_or_global` | enemy effect module | high | do not extract yet | Core packet ingestion path. |

### Packet/action observation
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `split_pipe` | `pure` | packet utilities | low | now | Standalone parser helper. |
| `split_csv_numbers` | `pure` | packet utilities | low | now | Standalone parser helper. |
| `encode_party_state_payload` | `stateful_no_side_effect` | IPC/context module | medium | later | Serialization shape must remain stable. |
| `maybe_broadcast_party_state_ipc` | `performs_side_effects` | IPC/context module | high | do not extract yet | Sends IPC messages. |
| `apply_party_state_ipc_message` | `writes_scheduler_or_global` | IPC/context module | medium | later | Updates shared IPC cache. |
| `get_party_state_ipc_entry` | `writes_scheduler_or_global` | IPC/context module | medium | later | Initializes entry cache. |

### Logging/diagnostics
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `log_ja_sched` | `writes_scheduler_or_global` | observability module | low | later | Output helper; stable shape required. |
| `log_tank_sched` | `writes_scheduler_or_global` | observability module | low | later | Output helper. |
| `log_combat_sched` | `writes_scheduler_or_global` | observability module | low | later | Output helper. |
| `log_def_sched` | `writes_scheduler_or_global` | observability module | low | later | Output helper. |
| `ensure_diag_logs_initialized` | `writes_scheduler_or_global` | observability module | medium | later | Initializes file-backed logs and globals. |
| `tank_enmity_diag` | `writes_scheduler_or_global` | observability module | low | later | Diagnostic-only logging wrapper. |

### Unknown/mixed or wrapper-forwarders
| Function | Side-effect status | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|
| `to_roman_numeral` | `pure` | keep wrapper / text utils | low | do not extract yet | Already wrapper to extracted module. |
| `ucfirst` | `pure` | keep wrapper / text utils | low | do not extract yet | Already wrapper to extracted module. |
| `decode_json_escapes` | `pure` | keep wrapper / text utils | low | do not extract yet | Already wrapper to extracted module. |
| `normalize_action_name_like_healbot` | `pure` | keep wrapper / text utils | low | do not extract yet | Already wrapper to extracted module. |
| `set_has` | `pure` | shared util | low | later | Tiny helper, not urgent. |
| `action_state` | `stateful_no_side_effect` | keep wrapper / action_state module | low | do not extract yet | Already wrapper. |
| `action_mark_sent` | `stateful_no_side_effect` | keep wrapper / action_state module | low | do not extract yet | Already wrapper. |
| `action_mark_packet_start` | `stateful_no_side_effect` | keep wrapper / action_state module | low | do not extract yet | Already wrapper. |
| `action_mark_packet_end` | `stateful_no_side_effect` | keep wrapper / action_state module | low | do not extract yet | Already wrapper. |
| `action_is_acting` | `stateful_no_side_effect` | keep wrapper / action_state module | low | do not extract yet | Already wrapper. |
| `action_dispatch_blocked` | `stateful_no_side_effect` | keep wrapper / action_state module | low | do not extract yet | Already wrapper. |
| `action_effective_range` | `pure` | keep wrapper / action_metadata module | low | do not extract yet | Already wrapper. |
| `ja_targets_enemy` | `pure` | keep wrapper / predicates module | low | do not extract yet | Already wrapper. |
| `normalize_angle_rad` | `pure` | keep wrapper / geometry module | low | do not extract yet | Already wrapper. |
| `target_is_in_front_arc` | `reads_windower` | keep wrapper / geometry module | low | do not extract yet | Already wrapper. |
| `ja_requires_engaged_front` | `pure` | keep wrapper / predicates module | low | do not extract yet | Already wrapper. |
| `has_buff` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `action_status_id` | `stateful_no_side_effect` | keep wrapper / action_metadata module | low | do not extract yet | Already wrapper. |
| `estimate_missing_hp` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `cure_tier_for_missing_hp` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `dedupe_numeric_ids` | `pure` | keep wrapper / maintenance module | low | do not extract yet | Already wrapper. |
| `action_target_mode` | `stateful_no_side_effect` | keep wrapper / action_metadata module | low | do not extract yet | Already wrapper. |
| `build_action_command` | `pure` | keep wrapper / command_builder module | low | do not extract yet | Already wrapper. |
| `member_priority` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `pri_default` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `danger_level` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `cure_better` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `debuff_spell_for_buff_id` | `pure` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `split_actions` | `pure` | keep wrapper / maintenance module | low | do not extract yet | Already wrapper. |
| `family_key` | `pure` | keep wrapper / proposal_keys module | low | do not extract yet | Already wrapper. |
| `attempt_key` | `pure` | keep wrapper / proposal_keys module | low | do not extract yet | Already wrapper. |
| `count_buff_occurrences` | `pure` | keep wrapper / maintenance module | low | do not extract yet | Already wrapper. |
| `is_bard_song` | `stateful_no_side_effect` | keep wrapper / defensive module | low | do not extract yet | Already wrapper. |
| `action_duration_seconds` | `stateful_no_side_effect` | keep wrapper / action_metadata module | low | do not extract yet | Already wrapper. |
| `parse_status_snapshot_063` | `pure` | keep wrapper / status_snapshot_parser module | low | do not extract yet | Already wrapper to extracted parser helper with parity-validated contract. |
| `p1_number` | `pure` | keep wrapper / numeric module | low | do not extract yet | Already wrapper. |
| `p1_clamp_urgency` | `pure` | keep wrapper / numeric module | low | do not extract yet | Already wrapper. |
| `p1_pending_is_live_state` | `pure` | keep wrapper / locks module | low | do not extract yet | Already wrapper. |
| `p1_update_pending_state` | `writes_scheduler_or_global` | keep wrapper / pending module | low | do not extract yet | Already wrapper. |
| `p1_duplicate_suppressed` | `stateful_no_side_effect` | keep wrapper / locks module | low | do not extract yet | Already wrapper. |
| `p1_get_locks` | `stateful_no_side_effect` | keep wrapper / locks module | low | do not extract yet | Already wrapper. |
| `p1_hard_lock_reject` | `pure` | keep wrapper / locks module | low | do not extract yet | Already wrapper. |
| `p1_format_top3` | `pure` | keep wrapper / rank_output module | low | do not extract yet | Already wrapper. |
| `p1_format_top3_verbose` | `pure` | keep wrapper / rank_output module | low | do not extract yet | Already wrapper. |
| `p1_format_topn_lines` | `pure` | keep wrapper / rank_output module | low | do not extract yet | Already wrapper. |
| `p1_capture_topn_items` | `pure` | keep wrapper / rank_output module | low | do not extract yet | Already wrapper. |
| `p1_push_recent_rejects` | `writes_scheduler_or_global` | keep wrapper / reject_history module | low | do not extract yet | Already wrapper. |
| `p1_reject_top` | `pure` | keep wrapper / rank_output module | low | do not extract yet | Already wrapper. |
| `p1_build_dispatch_plan` | `stateful_no_side_effect` | keep wrapper / dispatch_plan module | low | do not extract yet | Already wrapper. |
| `p1_revalidate_plan_commit` | `reads_windower` | keep wrapper / dispatch_plan module | low | do not extract yet | Already wrapper. |
| `p1_set_pending_globals` | `writes_scheduler_or_global` | keep wrapper / pending module | low | do not extract yet | Already wrapper. |
| `p1_build_lock_summary` | `pure` | keep wrapper / locks module | low | do not extract yet | Already wrapper. |
| `p1_record_legacy_dispatch` | `writes_scheduler_or_global` | keep wrapper / pending_record module | low | do not extract yet | Already wrapper. |
| `p1_pending_mark_complete` | `writes_scheduler_or_global` | keep wrapper / pending module | low | do not extract yet | Already wrapper. |

## 4. Remaining Side-Effect Owners

Direct side-effect owners currently observed in active runtime files:

| File | Function/area | Why it still owns side effect | Temporary vs long-term | Target future owner |
|---|---|---|---|---|
| `unified_scheduler.lua` | `try_doom_water_emergency`, `p1_try_target_prep`, `p1_apply_face_to_target`, `p1_move_toward_mob`, `p1_try_dark_launch_dispatch`, `run_movement_coordinator_tick` | Scheduler still performs dark-launch dispatch and movement/facing coordination in-phase. | Temporary | Dispatcher/movement ownership split in later phase. |
| `unified_combat_core.lua` | combat/tank execution paths | Legacy + partial scheduler coexistence; core still executes some direct actions. | Temporary | Dispatcher-owned execution lane. |
| `UnifiedCombat.lua` | lifecycle stop movement call | Entrypoint-level lifecycle control. | Temporary | Movement facade/dispatcher path. |
| `uc_party_follow.lua` | follow run/stop | Follow subsystem currently owns run vectors. | Mixed/uncertain | Movement facade (if later centralized). |
| `uc_pathing.lua` | path run/stop | Pathing module owns run vectors. | Mixed/uncertain | Movement facade (if later centralized). |
| `uc_add_control.lua` | attack/target command pipeline | Add-control still direct command emitter. | Temporary | Dispatcher/target-control lane. |
| `remote_bridge.lua` | reload command helper | Explicit bridge operation (`reload`) not proposal dispatch. | Long-term likely | Stay bridge-owned unless re-scoped. |
| `dd2_engine.lua`, `dd2_module.lua`, `melee_engine.lua` | legacy execution paths | Legacy subsystems outside current narrow scheduler extraction scope. | Temporary in migration context | Out-of-scope for immediate scheduler helper work. |

## 5. Candidate Next Tasks (Top 5)

1. Task: `Scheduler Wrapper Audit (Doc-Only)`
- Target: `docs/scheduler_extraction_checkpoint.md` (append/update)
- Scope: mark wrapper-only locals vs real owned locals in `unified_scheduler.lua`
- Runtime code changes: no
- Risk: low
- Why next: clarifies what is truly left to extract
- Must not change: any Lua/runtime behavior

2. Task: `Maintenance Parser Boundary Design (Doc-Only)`
- Target: `docs/scheduler_extraction_checkpoint.md` and/or companion design notes
- Scope: define parser vs maintenance-state ownership boundaries and contract invariants after parser extraction
- Runtime code changes: no
- Risk: low
- Why next: parser helper extraction is complete; remaining maintenance work is state-coupled and needs explicit boundaries first
- Must not change: any runtime behavior

3. Task: `Maintenance Ownership Design (Doc-Only)`
- Target: docs-only
- Scope: map `ensure_maintenance_state_tables`, `set_recent_gain`, `get_recent_gain`, `family_tokens_for`, and cadence gates into explicit ownership lanes
- Runtime code changes: no
- Risk: low
- Why next: avoids unsafe stateful extraction churn
- Must not change: any runtime behavior

4. Task: `Enemy-Effect State Ownership Design (Doc-Only)`
- Target: docs-only
- Scope: define boundaries for attempt/state maps (`enemy_dispel_attempt_map`, `enemy_effect_state_*`) before any stateful runtime move
- Runtime code changes: no
- Risk: low
- Why next: state mutators remain behavior-sensitive and intertwined with providers
- Must not change: any runtime behavior

5. Task: `Replay Validation Runbook (Doc-Only)`
- Target: docs-only
- Scope: require live-log or packet-replay validation gates for future parser/state extractions beyond `parse_status_snapshot_063`
- Runtime code changes: no
- Risk: low
- Why next: preserves contract fidelity for packet-derived behaviors
- Must not change: runtime code or side-effect locations

## 6. Stop Conditions
Do not touch these until later phase with explicit scope:
- `p1_try_dark_launch_dispatch`
- `run_movement_coordinator_tick`
- `p1_collect_*` provider functions
- `p1_validate_proposal`, `p1_score`, `p1_rank` (unless explicitly scoped)
- `action_ready`, `spell_ready`, `ja_ready` unless dependency/state ownership is explicitly designed
- enemy effect tracker/dispel state logic unless separately scoped
- relocation of direct side-effect calls (`send_command`, `ffxi.run`, `ffxi.turn`, `uc_settarget.select_by_id`)

## 7. Validation Snapshot
- Syntax:
  - `luac -p unified_scheduler.lua` passed
  - `luac -p` passed for all extracted modules:
    - `uc_scheduler_locks.lua`
    - `uc_scheduler_pending.lua`
    - `uc_scheduler_action_state.lua`
    - `uc_scheduler_dispatch_plan.lua`
    - `uc_scheduler_rank_output.lua`
    - `uc_scheduler_reject_history.lua`
    - `uc_scheduler_pending_record.lua`
    - `uc_scheduler_dryrun_publish.lua`
    - `uc_scheduler_target_utils.lua`
    - `uc_scheduler_geometry.lua`
    - `uc_scheduler_action_predicates.lua`
    - `uc_scheduler_text_utils.lua`
    - `uc_scheduler_numeric_utils.lua`
    - `uc_scheduler_proposal_keys.lua`
    - `uc_scheduler_maintenance_utils.lua`
    - `uc_scheduler_defensive_utils.lua`
    - `uc_scheduler_action_metadata.lua`
    - `uc_scheduler_command_builder.lua`
    - `uc_scheduler_enemy_effect_utils.lua`
    - `uc_scheduler_status_snapshot_parser.lua`
- Grep counts (current repo snapshot):
  - `windower.send_command` = `112`
  - `windower.ffxi.run` = `65`
  - `windower.ffxi.turn` = `9`
  - `uc_settarget.select_by_id` = `4`
- Extracted modules direct side-effect calls:
  - none found in any extracted module listed above.

## 8. Recommended Next Prompt
"Documentation-only follow-up: codify parser/state-provider ownership boundaries and a replay-validation gate for any future maintenance/parser/state extraction beyond `parse_status_snapshot_063`."
