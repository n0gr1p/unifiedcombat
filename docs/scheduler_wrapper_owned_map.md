# Scheduler Wrapper vs Owned Map

> Historical pre-cutover map. Superseded for current ownership and callable
> surfaces by `scheduler_responsibility_map.md` and the Phase 6 exit audit in
> `../RFC/`.

## 1. Purpose
This is a post-extraction map to prevent future tasks from targeting wrapper-only functions in `unified_scheduler.lua`.

The intent is to separate:
- `wrapper`: thin pass-through preserved for API/signature stability
- `owned`: implementation still lives in `unified_scheduler.lua`
- `mixed/uncertain`: partial delegation but still owns meaningful behavior/state

## 2. Summary counts
- Total `local function` in `unified_scheduler.lua`: **142**
- Wrapper functions: **71**
- Owned functions: **70**
- Mixed/uncertain functions: **1**
- Owned functions that perform side effects: **6**
- Owned functions that read Windower state: **25**
- Owned functions that are pure: **31**
- Owned functions that write scheduler/global state: **19**

Notes:
- Counts are code-observed from current file contents.
- Side-effect/read/write/pure labels are conservative and can overlap by function behavior.

## 3. Wrapper function table
| Function | Target module | Target module function | Inline `require(...)` | Dependencies passed through | Why not a future extraction target |
|---|---|---|---|---|---|
| to_roman_numeral | uc_scheduler_text_utils.lua | to_roman_numeral | yes | none | Already extracted; local name preserved only. |
| ucfirst | uc_scheduler_text_utils.lua | ucfirst | yes | none | Already extracted. |
| decode_json_escapes | uc_scheduler_text_utils.lua | decode_json_escapes | yes | none | Already extracted. |
| normalize_action_name_like_healbot | uc_scheduler_text_utils.lua | normalize_action_name_like_healbot | yes | none | Already extracted. |
| normalize_status_removal_key | uc_scheduler_enemy_effect_utils.lua | normalize_status_removal_key | yes | none | Already extracted enemy-effect helper. |
| action_state | uc_scheduler_action_state.lua | action_state | yes | scheduler | Already extracted state helper. |
| action_mark_sent | uc_scheduler_action_state.lua | action_mark_sent | yes | scheduler, now_s | Already extracted state helper. |
| action_mark_packet_start | uc_scheduler_action_state.lua | action_mark_packet_start | yes | scheduler, now_s | Already extracted state helper. |
| action_mark_packet_end | uc_scheduler_action_state.lua | action_mark_packet_end | yes | scheduler, now_s | Already extracted state helper. |
| action_is_acting | uc_scheduler_action_state.lua | action_is_acting | yes | scheduler, now_s | Already extracted state helper. |
| action_dispatch_blocked | uc_scheduler_action_state.lua | action_dispatch_blocked | yes | scheduler, now_s, _G | Already extracted state helper. |
| set_has | uc_scheduler_maintenance_utils.lua | set_has | yes | none | Already extracted utility helper. |
| split_pipe | uc_scheduler_text_utils.lua | split_pipe | yes | none | Already extracted parser helper. |
| split_csv_numbers | uc_scheduler_text_utils.lua | split_csv_numbers | yes | none | Already extracted parser helper. |
| current_zone_id | uc_scheduler_context_utils.lua | current_zone_id | yes | none | Already extracted context helper. |
| get_settings | uc_scheduler_context_utils.lua | get_settings | yes | none | Already extracted context helper. |
| bool_setting | uc_scheduler_numeric_utils.lua | bool_setting | yes | none | Already extracted numeric helper. |
| player_has_doom | uc_scheduler_defensive_utils.lua | player_has_doom | yes | resolve_doom_buff_id callback | Already extracted; wrapper keeps call signature. |
| build_partner_target_set | uc_scheduler_context_utils.lua | build_partner_target_set | yes | bool_setting, uc_partner_list | Already extracted context helper. |
| is_city_zone_for_maintenance | uc_scheduler_context_utils.lua | is_city_zone_for_maintenance | yes | maintenance_blocked_zone_names | Already extracted context helper. |
| action_effective_range | uc_scheduler_action_metadata.lua | action_effective_range | yes | SCHED_RANGE_MULT | Already extracted metadata helper. |
| ja_targets_enemy | uc_scheduler_action_predicates.lua | ja_targets_enemy | yes | none | Already extracted predicate helper. |
| normalize_angle_rad | uc_scheduler_geometry.lua | normalize_angle_rad | yes | none | Already extracted geometry helper. |
| target_is_in_front_arc | uc_scheduler_geometry.lua | target_is_in_front_arc | yes | none | Already extracted geometry helper. |
| ja_requires_engaged_front | uc_scheduler_action_predicates.lua | ja_requires_engaged_front | yes | none | Already extracted predicate helper. |
| has_buff | uc_scheduler_defensive_utils.lua | has_buff | yes | none | Already extracted defensive helper. |
| action_status_id | uc_scheduler_action_metadata.lua | action_status_id | yes | get_spell_resource, get_ja_resource | Already extracted metadata helper. |
| estimate_missing_hp | uc_scheduler_defensive_utils.lua | estimate_missing_hp | yes | none | Already extracted defensive helper. |
| cure_tier_for_missing_hp | uc_scheduler_defensive_utils.lua | cure_tier_for_missing_hp | yes | cure_by_tier | Already extracted defensive helper. |
| dedupe_numeric_ids | uc_scheduler_maintenance_utils.lua | dedupe_numeric_ids | yes | none | Already extracted maintenance helper. |
| action_target_mode | uc_scheduler_action_metadata.lua | action_target_mode | yes | get_spell_resource, get_ja_resource | Already extracted metadata helper. |
| build_action_command | uc_scheduler_command_builder.lua | build_action_command | yes | action_target_mode | Already extracted command builder helper. |
| member_priority | uc_scheduler_defensive_utils.lua | member_priority | yes | none | Already extracted defensive helper. |
| pri_default | uc_scheduler_defensive_utils.lua | pri_default | yes | none | Already extracted defensive helper. |
| danger_level | uc_scheduler_defensive_utils.lua | danger_level | yes | none | Already extracted defensive helper. |
| cure_better | uc_scheduler_defensive_utils.lua | cure_better | yes | none | Already extracted defensive helper. |
| debuff_spell_for_buff_id | uc_scheduler_defensive_utils.lua | debuff_spell_for_buff_id | yes | res | Already extracted defensive helper. |
| split_actions | uc_scheduler_maintenance_utils.lua | split_actions | yes | none | Already extracted maintenance helper. |
| family_key | uc_scheduler_proposal_keys.lua | family_key | yes | none | Already extracted key helper. |
| attempt_key | uc_scheduler_proposal_keys.lua | attempt_key | yes | none | Already extracted key helper. |
| count_buff_occurrences | uc_scheduler_maintenance_utils.lua | count_buff_occurrences | yes | none | Already extracted maintenance helper. |
| is_bard_song | uc_scheduler_defensive_utils.lua | is_bard_song | yes | get_spell_resource | Already extracted defensive helper. |
| action_duration_seconds | uc_scheduler_action_metadata.lua | action_duration_seconds | yes | get_spell_resource, get_ja_resource | Already extracted metadata helper. |
| spell_known_flag | uc_scheduler_action_metadata.lua | spell_known_flag | yes | none | Already extracted readiness helper. |
| job_id_by_short | uc_scheduler_action_metadata.lua | job_id_by_short | yes | res.jobs | Already extracted readiness helper. |
| parse_status_snapshot_063 | uc_scheduler_status_snapshot_parser.lua | parse_status_snapshot_063 | yes | none | Already extracted parser helper; local wrapper preserves signature. |
| p1_number | uc_scheduler_numeric_utils.lua | p1_number | yes | none | Already extracted numeric helper. |
| p1_clamp_urgency | uc_scheduler_numeric_utils.lua | p1_clamp_urgency | yes | none | Already extracted numeric helper. |
| danger_weight_to_priority | uc_scheduler_enemy_effect_utils.lua | danger_weight_to_priority | yes | none | Already extracted enemy-effect helper. |
| p1_build_party_id_set | uc_scheduler_context_utils.lua | p1_build_party_id_set | yes | get_party_members callback | Already extracted context helper. |
| p1_pending_is_live_state | uc_scheduler_locks.lua | p1_pending_is_live_state | no (module local binding) | none | Already extracted lock helper. |
| p1_update_pending_state | uc_scheduler_pending.lua | p1_update_pending_state | no | scheduler, ctx, callbacks | Already extracted pending helper. |
| p1_duplicate_suppressed | uc_scheduler_locks.lua | p1_duplicate_suppressed | no | scheduler, ctx, proposal, p1_number | Already extracted lock helper. |
| p1_get_locks | uc_scheduler_locks.lua | p1_get_locks | no | scheduler, ctx, p1_number, _G | Already extracted lock helper. |
| p1_hard_lock_reject | uc_scheduler_locks.lua | p1_hard_lock_reject | no | locks, proposal | Already extracted lock helper. |
| p1_format_top3 | uc_scheduler_rank_output.lua | p1_format_top3 | yes | scheduler, ranked, p1_number | Already extracted rank-output helper. |
| p1_format_top3_verbose | uc_scheduler_rank_output.lua | p1_format_top3_verbose | yes | scheduler, ranked, p1_number | Already extracted rank-output helper. |
| p1_format_topn_lines | uc_scheduler_rank_output.lua | p1_format_topn_lines | yes | scheduler, ranked, n, p1_number | Already extracted rank-output helper. |
| p1_capture_topn_items | uc_scheduler_rank_output.lua | p1_capture_topn_items | yes | scheduler, ranked, n, p1_number | Already extracted rank-output helper. |
| p1_push_recent_rejects | uc_scheduler_reject_history.lua | p1_push_recent_rejects | yes | scheduler, ctx, rejected | Already extracted reject-history helper. |
| enemy_effect_log_label | uc_scheduler_enemy_effect_utils.lua | enemy_effect_log_label | yes | res.buffs | Already extracted enemy-effect helper. |
| p1_reject_top | uc_scheduler_rank_output.lua | p1_reject_top | yes | scheduler, reject_counts, proposal_count | Already extracted rank-output helper. |
| p1_build_dispatch_plan | uc_scheduler_dispatch_plan.lua | p1_build_dispatch_plan | yes | scheduler, ctx, selected, p1_number | Already extracted dispatch-plan helper. |
| p1_revalidate_plan_commit | uc_scheduler_dispatch_plan.lua | p1_revalidate_plan_commit | yes | scheduler, ctx, selected, plan, p1_number, windower | Already extracted dispatch-plan helper. |
| p1_set_pending_globals | uc_scheduler_pending.lua | p1_set_pending_globals | no | scheduler, _G | Already extracted pending helper. |
| p1_build_lock_summary | uc_scheduler_locks.lua | p1_build_lock_summary | no | ctx, locks, p1_get_locks | Already extracted lock helper. |
| p1_record_legacy_dispatch | uc_scheduler_pending_record.lua | p1_record_legacy_dispatch | yes | scheduler, ctx, p1_number | Already extracted pending-record helper. |
| p1_pending_mark_complete | uc_scheduler_pending.lua | p1_pending_mark_complete | no | scheduler, now, result_code | Already extracted pending helper. |
| p1_is_tank_enmity_selected | uc_scheduler_target_utils.lua | p1_is_tank_enmity_selected | yes | scheduler, selected | Already extracted target helper. |
| p1_target_distance_to_id | uc_scheduler_target_utils.lua | p1_target_distance_to_id | yes | scheduler, target_id | Already extracted target helper. |
| enemy_dispel_claim_valid | uc_scheduler_enemy_effect_utils.lua | enemy_dispel_claim_valid | yes | none | Already extracted enemy-effect helper. |

## 4. Owned function table
| Function | Category | Side-effect classification | Likely future module | Risk | Priority | Reason |
|---|---|---|---|---|---|---|
| load_enemy_dispel_map_from_json | enemy effect/dispel | performs side effects | enemy-effect module | high | do not touch yet | File IO + fatal errors. |
| now_s | tick/context | unknown/mixed | context/time module | medium | later | Time source gate + fatal path. |
| load_targetbar_catalogs_once | enemy effect/dispel | reads Windower state | enemy-effect module | medium | later | Catalog load/caching boundary. |
| apply_effect_list_to_target | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Mutates effect map via helper. |
| apply_catalog_effects | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | State update utility. |
| enemy_dispel_diag | logging/diag | writes scheduler/global state | observability module | low | later | Writes debug global. |
| enemy_dispel_log | logging/diag | writes scheduler/global state | observability module | low | later | Diagnostic logging wrapper. |
| enemy_dispel_attempt_map | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Map initializer/owner. |
| enemy_effect_state_map | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Map initializer/owner. |
| enemy_effect_state_set | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Effect state mutation. |
| enemy_effect_state_clear | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Effect state mutation. |
| enemy_effect_state_clear_target | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Target-wide state mutation. |
| enemy_effect_state_prune_expired | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Time-based prune logic. |
| enemy_effect_state_sweep | enemy effect/dispel | reads Windower state | enemy-effect module | medium | later | Uses live mob state and mutates map. |
| can_attempt_enemy_dispel | enemy effect/dispel | side-effect-free but stateful | enemy-effect module | medium | later | Reads attempt map. |
| mark_enemy_dispel_attempt | enemy effect/dispel | writes scheduler/global state | enemy-effect module | medium | later | Mutates attempt map. |
| enemy_dispel_choose_action | enemy effect/dispel | reads Windower state | enemy-effect module | medium | later | Depends on readiness pipeline. |
| is_enemy_mob_id | enemy effect/dispel | reads Windower state | enemy-effect module | medium | later | Live mob lookup helper. |
| ingest_enemy_effects_from_raw_action_028 | packet/action observation | writes scheduler/global state | enemy-effect module | high | do not touch yet | Packet parser + state ingestion. |
| encode_party_state_payload | IPC/context | reads Windower state | context/IPC module | medium | later | Snapshot serialization from live state. |
| maybe_broadcast_party_state_ipc | IPC/context | performs side effects | context/IPC module | high | do not touch yet | Sends IPC messages. |
| apply_party_state_ipc_message | IPC/context | writes scheduler/global state | context/IPC module | medium | later | Mutates IPC cache map. |
| get_party_state_ipc_entry | IPC/context | writes scheduler/global state | context/IPC module | medium | later | TTL/cache helper. |
| try_doom_water_emergency | defensive/doom | performs side effects | dispatcher/legacy lane | high | do not touch yet | Emits command and movement stop. |
| log_ja_sched | logging/diag | writes scheduler/global state | observability module | low | later | Diagnostic wrapper. |
| log_tank_sched | logging/diag | writes scheduler/global state | observability module | low | later | Diagnostic wrapper. |
| log_combat_sched | logging/diag | writes scheduler/global state | observability module | low | later | Diagnostic wrapper. |
| log_def_sched | logging/diag | writes scheduler/global state | observability module | low | later | Diagnostic wrapper + optional file log. |
| ensure_diag_logs_initialized | logging/diag | writes scheduler/global state | observability module | medium | later | Initializes log writers. |
| run_movement_coordinator_tick | movement coordinator | performs side effects | movement module | high | do not touch yet | Owns run/stop/freeze behavior. |
| tank_enmity_diag | logging/diag | writes scheduler/global state | observability module | low | later | Diagnostic state updates. |
| get_party_members | context/snapshot | reads Windower state | context module | medium | later | Large live-state aggregation helper. |
| p1_prime_unclaimed_party_aggressive_ok | context/combat | reads Windower state | combat provider util | medium | later | Gating predicate with live state. |
| in_party_cast_range | context/combat | reads Windower state | context/provider utils | medium | later | Range predicate with mob distance. |
| get_spell_resource | action metadata/readiness | side-effect-free but stateful | action metadata module | medium | later | Local cache owner and lookup logic. |
| spell_usable_by_current_job | readiness | reads Windower state | readiness module | medium | later | Job-level gate helper. |
| spell_known_and_usable | readiness | reads Windower state | readiness module | medium | later | Learned/usable gate helper. |
| get_ja_resource | action metadata/readiness | side-effect-free but stateful | action metadata module | medium | later | Local JA cache owner. |
| spell_ready | action readiness | reads Windower state | readiness module | high | do not touch yet | Core readiness gate. |
| available_cure_tier_max | defensive/readiness | reads Windower state | defensive/readiness | medium | later | Coupled to spell_ready. |
| get_usable_cure_from_tier | defensive/readiness | reads Windower state | defensive/readiness | medium | later | Coupled to spell_ready. |
| ja_ready | action readiness | reads Windower state | readiness module | high | do not touch yet | Core readiness + target/range checks. |
| attempt_allowed | defensive/maintenance state | side-effect-free but stateful | defensive/maintenance state module | medium | later | Reads scheduler attempt map. |
| mark_attempt | defensive/maintenance state | writes scheduler/global state | defensive/maintenance state module | medium | later | Mutates scheduler attempt map. |
| set_recent_gain | maintenance state | writes scheduler/global state | maintenance state module | medium | later | Mutates recent gain table. |
| get_recent_gain | maintenance state | side-effect-free but stateful | maintenance state module | medium | later | Reads state table with TTL. |
| family_tokens_for | maintenance state | writes scheduler/global state | maintenance state module | medium | later | Initializes token table entries. |
| build_defensive_candidates | defensive provider | writes scheduler/global state | defensive provider module | high | do not touch yet | Large provider orchestration body. |
| choose_defensive_action | defensive provider | pure | defensive provider module | medium | later | Selection logic but behavior-sensitive. |
| try_delegate_healbot | defensive/legacy bridge | performs side effects | legacy bridge/dispatcher | high | do not touch yet | Emits external command/action calls. |
| try_internal_defensive_action | defensive/legacy bridge | performs side effects | legacy bridge/dispatcher | high | do not touch yet | Direct command emission path. |
| p1_build_ctx | tick context | reads Windower state | context module | high | do not touch yet | Central context contract for all lanes. |
| p1_collect_defensive_internal | provider collection | writes scheduler/global state | defensive provider module | high | do not touch yet | Provider lane with proposal writes. |
| p1_collect_defensive_healbot | provider collection | writes scheduler/global state | defensive provider module | high | do not touch yet | Provider lane with delegate checks. |
| p1_collect_combat_offense | provider collection | reads Windower state | combat provider module | high | do not touch yet | Combat proposal generation core path. |
| p1_collect_enemy_buff_removal | provider collection | writes scheduler/global state | enemy buff removal provider | high | do not touch yet | Uses enemy effect/attempt state. |
| p1_collect_combat_engage | provider collection | reads Windower state | combat engage provider | high | do not touch yet | Engage lane behavior-sensitive. |
| p1_collect_target_control | provider collection | reads Windower state | target control provider | high | do not touch yet | Target-control lane behavior-sensitive. |
| p1_collect_pull_control | provider collection | reads Windower state | pull provider | high | do not touch yet | Pull lane behavior-sensitive. |
| p1_collect_combat_tank_enmity | provider collection | reads Windower state | tank enmity provider | high | do not touch yet | High-priority enmity lane. |
| p1_collect_combat_ja | provider collection | reads Windower state | combat JA provider | high | do not touch yet | JA lane behavior-sensitive. |
| p1_collect_maintenance | provider collection | writes scheduler/global state | maintenance provider | high | do not touch yet | Cadence/state heavy provider path. |
| p1_collect_proposals | provider orchestration | writes scheduler/global state | provider orchestrator | high | do not touch yet | Aggregates all proposal lanes. |
| p1_validate_proposal | validation | reads Windower state | rank/validation module | high | do not touch yet | Hard behavior gate before ranking. |
| p1_score | ranking | side-effect-free but stateful | rank module | high | do not touch yet | Changes proposal score outcomes. |
| p1_rank | ranking | side-effect-free but stateful | rank module | high | do not touch yet | Winner selection logic. |
| p1_run_dry | orchestration | writes scheduler/global state | scheduler orchestrator | high | do not touch yet | Core dry-run state publication pipeline. |
| p1_try_target_prep | dispatch-prep | performs side effects | dispatcher | high | do not touch yet | Owns `uc_settarget` side effect. |
| p1_move_toward_mob | movement | performs side effects | movement module | high | do not touch yet | Owns `windower.ffxi.run` side effect. |
| p1_try_dark_launch_dispatch | dispatch | performs side effects | dispatcher | high | do not touch yet | Primary dark-launch command execution owner. |

## 5. Mixed/uncertain function table
| Function | Why mixed/uncertain | What must be understood before moving | Likely future owner | Risk |
|---|---|---|---|---|
| resolve_doom_buff_id | Delegates to extracted helper but still owns canonical local doom cache mutation in wrapper (`doom_buff_id` update). | Cache ownership/reset semantics across calls/reload must remain exactly unchanged. | keep wrapper in `unified_scheduler.lua` (or explicit cache-owner design later) | medium |

## 6. Next owned-pure candidates (owned-only)
| Function | Exact dependencies | Proposed target module | Safe? | Runtime code changes next task? | Future extraction acceptance criterion |
|---|---|---|---|---|---|
| none | n/a | n/a | n/a | n/a | n/a |

## 7. Stop list
Do not target yet:
- `p1_try_dark_launch_dispatch`
- `run_movement_coordinator_tick`
- `p1_collect_*` provider functions
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `action_ready`
- `spell_ready`
- `ja_ready`
- enemy effect/dispel state functions
- any function that emits commands, movement, facing, or target selection side effects

## 8. Validation snapshot
- `luac -p unified_scheduler.lua`: passed
- `luac -p` extracted modules: all passed
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
- Side-effect grep counts (`*.lua`):
  - `windower.send_command`: `112`
  - `windower.ffxi.run`: `65`
  - `windower.ffxi.turn`: `9`
  - `uc_settarget.select_by_id`: `4`

Confirmations:
- No runtime files were changed in this task.
- No existing docs were modified in this task.
- `docs/scheduler_wrapper_owned_map.md` was created.

## 9. Recommended next prompt
Documentation-only next step: define maintenance parser/state-provider boundaries and required live-log or packet-replay validation gates before any further stateful maintenance extraction.
