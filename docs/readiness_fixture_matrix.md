# Readiness Fixture Matrix

## 1. Purpose

This document defines the fixture matrix required before any readiness/resource-cache movement.

No runtime code is changed by this document.

This document does not permit readiness extraction.

This document does not permit provider extraction.

This document does not create harness code.

This document does not create fixture files.

This document defines fixture coverage policy only.

Readiness false positives and false negatives are conformance-blocking.

Future readiness movement requires old-vs-new parity across this matrix.

## 2. Readiness fixture principles

- Fixtures must be deterministic.
- All Windower reads must be fixture-backed stubs.
- All resource lookups must use fixture-backed resource tables.
- All time/recast decisions must use fixture values.
- No fallback to live Windower state.
- No fallback to live resource tables unless fixture explicitly models that path.
- Numeric IDs must remain numeric.
- `nil` vs `false` vs empty string must be preserved.
- Each failure reason must map to at least one fixture.
- Each positive path must have at least one fixture.
- Side effects must remain zero.

## 3. Readiness function coverage map

| function | current status | primary fixture group | required positive fixtures | required negative fixtures | required stubs | expected output type | conformance priority | blocks readiness movement? |
|---|---|---|---|---|---|---|---|---|
| `get_spell_resource` | owned | resource lookup | `readiness_resource_spell_exact_name_pass`, `readiness_resource_spell_normalized_name_pass` | `readiness_resource_spell_unknown_fail`, `readiness_resource_spell_missing_table_failfast` | `res.spells`, optional `_libs.lor.resources.lc_res.spells` | resource table or `nil` | P0 | YES |
| `spell_usable_by_current_job` | owned | spell usability | `readiness_usable_spell_main_job_pass`, `readiness_usable_spell_sub_job_pass` | `readiness_usable_spell_job_block_fail`, `readiness_usable_spell_invalid_input_fail` | `windower.ffxi.get_player`, `res.jobs` | boolean | P0 | YES |
| `spell_known_and_usable` | owned | spell usability | `readiness_known_usable_pass` | `readiness_known_not_learned_fail`, `readiness_known_job_block_fail`, `readiness_known_invalid_spell_fail` | `windower.ffxi.get_spells`, spell usability stubs | tuple `(bool, reason)` | P0 | YES |
| `get_ja_resource` | owned | resource lookup | `readiness_resource_ja_exact_name_pass`, `readiness_resource_ja_normalized_name_pass` | `readiness_resource_ja_unknown_fail`, `readiness_resource_ja_missing_table_failfast` | `res.job_abilities`, optional `_libs.lor.resources.lc_res.job_abilities` | resource table or `nil` | P0 | YES |
| `spell_ready` | owned | spell readiness | `readiness_spell_ready_pass` | `readiness_spell_ready_unknown_spell_fail`, `readiness_spell_ready_recast_fail`, `readiness_spell_ready_no_player_fail`, `readiness_spell_ready_no_mp_fail`, `readiness_spell_ready_not_learned_fail`, `readiness_spell_ready_job_block_fail` | spell lookup, known/usable, `windower.ffxi.get_spell_recasts`, `windower.ffxi.get_player` | tuple `(bool, reason)` | P0 | YES |
| `ja_ready` | owned | JA readiness | `readiness_ja_ready_pass`, `readiness_ja_ready_enemy_target_pass` | `readiness_ja_ready_unknown_ja_fail`, `readiness_ja_ready_not_owned_fail`, `readiness_ja_ready_status_block_fail`, `readiness_ja_ready_bad_target_fail`, `readiness_ja_ready_out_of_range_fail`, `readiness_ja_ready_not_front_fail`, `readiness_ja_ready_recast_fail`, `readiness_ja_ready_chivalry_tp_low_fail`, `readiness_ja_ready_chivalry_mp_high_fail` | JA lookup, abilities, player, target mobs, recasts, predicates, geometry/range metadata | tuple `(bool, reason)` | P0 | YES |
| `action_ready` | owned | readiness branch routing | `readiness_action_ready_spell_branch_pass`, `readiness_action_ready_ja_branch_pass` | `readiness_action_ready_unknown_action_fail` | spell/JA lookups + `spell_ready` + `ja_ready` | tuple `(bool, reason, kind)` | P0 | YES |
| `available_cure_tier_max` | owned | cure readiness | `readiness_cure_max_tier_pass` | `readiness_cure_no_available_tier_fail` | `spell_ready`, cure tier table | number (`0..6`) | P1 | YES |
| `get_usable_cure_from_tier` | owned | cure readiness | `readiness_cure_fallback_pass`, `readiness_cure_floor_pass` | `readiness_cure_none_usable_fail`, `readiness_cure_start_below_floor_fail` | `spell_ready`, cure tier table | tuple `(name,tier)` or `nil` | P1 | YES |
| `spell_known_flag` | wrapper/extracted | spell usability metadata | `readiness_meta_spell_known_true_pass` | `readiness_meta_spell_known_false_fail` | primitive input values only | boolean | P1 | YES |
| `job_id_by_short` | wrapper/extracted | resource lookup metadata | `readiness_meta_job_id_lookup_pass` | `readiness_meta_job_id_unknown_zero_pass` | `res.jobs:with('english_short',...)` | number | P1 | YES |
| `action_status_id` | wrapper/extracted | action metadata | `readiness_meta_action_status_spell_pass`, `readiness_meta_action_status_ja_pass` | `readiness_meta_action_status_missing_nil_pass` | resource lookup callbacks | number or `nil` | P1 | YES |
| `action_duration_seconds` | wrapper/extracted | action metadata | `readiness_meta_action_duration_spell_pass` | `readiness_meta_action_duration_default_pass` | resource lookup callbacks | number | P1 | YES |
| `action_effective_range` | wrapper/extracted | action metadata | `readiness_meta_action_range_scaled_pass`, `readiness_meta_action_range_direct_pass` | `readiness_meta_action_range_zero_pass` | `SCHED_RANGE_MULT` | number | P1 | YES |
| `action_target_mode` | wrapper/extracted | action metadata | `readiness_meta_target_mode_self_only_pass`, `readiness_meta_target_mode_normal_pass` | `readiness_meta_target_mode_unknown_action_normal_pass` | resource lookup callbacks | string (`self_only` or `normal`) | P1 | YES |

## 4. Fixture naming convention

Pattern:

```text
readiness_<area>_<scenario>_<expected>
```

Rules:

- `area` examples: `resource`, `usable`, `known`, `spell_ready`, `ja_ready`, `action_ready`, `cure`, `meta`.
- `scenario` must describe the condition under test.
- `expected` must describe the result class (`pass`, `fail`, `failfast`, `reject`, `parity`).
- Use lowercase snake_case only.
- Once published in conformance evidence, names remain stable.

## 5. Failure reason to fixture mapping

| failure reason | required fixtures | expected outcome | checklist IDs covered |
|---|---|---|---|
| `BLOCK_DEFENSIVE_UNKNOWN_SPELL` | `readiness_spell_ready_unknown_spell_fail` | `spell_ready` returns `(false, BLOCK_DEFENSIVE_UNKNOWN_SPELL)` | S5, M9/E9, readiness owned gate |
| `BLOCK_DEFENSIVE_NOT_LEARNED` | `readiness_known_not_learned_fail`, `readiness_spell_ready_not_learned_fail` | known check rejects deterministically | S6, M7/E7 parity semantics |
| `BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL` | `readiness_usable_spell_job_block_fail`, `readiness_spell_ready_job_block_fail` | usability check rejects with explicit reason | S6, M9/E9 |
| `BLOCK_DEFENSIVE_RECAST` (spell) | `readiness_spell_ready_recast_fail` | spell recast gate blocks | S5, M4/E4 |
| `BLOCK_DEFENSIVE_NO_PLAYER` | `readiness_spell_ready_no_player_fail` | missing player snapshot blocks | S2, S6 |
| `BLOCK_DEFENSIVE_NO_MP` | `readiness_spell_ready_no_mp_fail` | MP gate blocks | M1/M4 parity |
| `BLOCK_DEFENSIVE_UNKNOWN_JA` | `readiness_ja_ready_unknown_ja_fail` | unknown JA blocks | S5, M9/E9 |
| `BLOCK_DEFENSIVE_JA_NOT_OWNED` | `readiness_ja_ready_not_owned_fail` | JA ownership gate blocks | S6, M4/E4 |
| `BLOCK_ACTION_STATUS3` | `readiness_ja_ready_status_block_fail` | status restriction blocks | S6, M4/E4 |
| `BLOCK_JA_BAD_TARGET` | `readiness_ja_ready_bad_target_fail` | target validity gate blocks | S5, E1/E4 |
| `BLOCK_JA_OUT_OF_RANGE` | `readiness_ja_ready_out_of_range_fail` | range gate blocks | S5, E4 |
| `BLOCK_JA_NOT_FRONT` | `readiness_ja_ready_not_front_fail` | front-arc gate blocks | S5, E4 |
| `BLOCK_CHIVALRY_TP_LOW` | `readiness_ja_ready_chivalry_tp_low_fail` | TP threshold enforced | S6, M4/E4 |
| `BLOCK_CHIVALRY_MP_TOO_HIGH` | `readiness_ja_ready_chivalry_mp_high_fail` | MP% threshold enforced | S6, M4/E4 |
| `BLOCK_DEFENSIVE_UNKNOWN_ACTION` | `readiness_action_ready_unknown_action_fail` | action routing returns `kind='none'` | S5, M10/E10 |
| deterministic repeatability failure | `readiness_spell_ready_pass` (repeat), `readiness_ja_ready_pass` (repeat), `readiness_action_ready_spell_branch_pass` (repeat) | repeated outputs identical | S8 |
| numeric key integrity drift | resource and recast fixtures with numeric keys | no stringified IDs in result/compare paths | M8/E7 |
| `nil` vs `false` semantic collision | known/meta fixtures + readiness fail fixtures | semantics preserved | M7, S6 |

## 6. Required stub schema per fixture group

| fixture group | mandatory stubs | optional stubs | forbidden live dependencies |
|---|---|---|---|
| resource lookup | `res.spells` / `res.job_abilities` / `res.jobs` tables | modeled `_libs.lor.resources.lc_res` fallback | live `res` globals not modeled by fixture |
| spell usability | `windower.ffxi.get_player`, `windower.ffxi.get_spells`, `res.jobs` | job-points table modeling | live player/jobs state |
| spell readiness | spell usability stubs + `windower.ffxi.get_spell_recasts`, player vitals | none | live recasts/player |
| JA readiness | `windower.ffxi.get_abilities`, `windower.ffxi.get_player`, `windower.ffxi.get_mob_by_id`, `windower.ffxi.get_mob_by_target`, `windower.ffxi.get_ability_recasts`, JA resources | modeled target variants | live target/mob/recast state |
| action routing | spell and JA lookup/readiness stubs | none | live lookup/readiness functions outside fixture scope |
| cure readiness | `spell_ready` deterministic stub behavior per cure tier | none | live spell readiness |
| metadata wrappers | resource lookup callbacks + `SCHED_RANGE_MULT` | none | live modules/resources not fixture-backed |

## 7. Zero-side-effect readiness gate

Readiness fixture runs must satisfy:

- `side_effects.attempted == false`
- all guarded API counts are `0`:
  - `windower.send_command`
  - `windower.ffxi.run`
  - `windower.ffxi.turn`
  - `uc_settarget.select_by_id`
  - `windower.send_ipc_message`
  - `io.open.write_or_append`

Coverage requirement:

- at least one parity fixture per readiness lane group must explicitly assert zero side effects.
- diagnostic violation fixtures are allowed for guard validation but are never approval fixtures.

## 8. Coverage gates for conformance and movement

| gate | requirement | blocking condition |
|---|---|---|
| readiness conformance gate | every P0 readiness row in Section 3 has passing fixture evidence | any P0 row missing or failing |
| readiness metadata parity gate | metadata wrapper fixtures (P1) are passing and deterministic | unresolved metadata drift affecting readiness outcomes |
| failure reason completeness gate | each declared readiness failure reason has at least one mapped fixture | unmapped reason |
| deterministic gate | repeat-run evidence for readiness pass/fail fixtures is stable | nondeterministic output |
| side-effect gate | parity fixtures show zero side effects | any unexpected side effect |
| extraction consideration gate | all Section 3 rows marked as movement-blocking are `CLEAR` in evidence | any unresolved blocking row |

## 9. Evidence artifacts required

For each readiness fixture group, conformance report must include:

- fixture names and lane classification
- old/new normalized outputs
- comparator result (pass or first mismatch path/reason)
- side-effect guard summary
- checklist IDs impacted
- rerun status if previously failed

Artifact locations should be recorded in:

- `docs/replay_adapter_conformance_report_template.md`:
  - `Fixture Set Metadata`
  - `Checklist Matrix`
  - `Comparator Summary`
  - `Failure Details`
  - `Evidence Package Inventory`

## 10. Stop conditions

This document does not permit moving:

- `get_spell_resource`
- `spell_usable_by_current_job`
- `spell_known_and_usable`
- `get_ja_resource`
- `spell_ready`
- `ja_ready`
- `action_ready`
- `available_cure_tier_max`
- `get_usable_cure_from_tier`
- `p1_collect_proposals`
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `p1_run_dry`
- `p1_try_dark_launch_dispatch`
- `run_movement_coordinator_tick`
- any direct side-effect owner

No immediate readiness extraction is allowed.

No immediate provider extraction is allowed.

## 11. Recommended next tasks

1. Docs-only readiness reason-code catalog with canonical reason-to-condition mapping.
2. Docs-only readiness comparator strict-section profile addendum for tuple-to-normalized mapping.
3. Docs-only cache lifecycle/reset policy for spell/JA name caches.
4. Create non-runtime readiness fixture validator skeleton only after policy docs are approved.
5. Create non-runtime readiness comparator skeleton only after policy docs are approved.

## 12. Validation snapshot

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

Run grep or PowerShell `Select-String` equivalent counts:

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `io.open`

Required confirmations:

- no runtime files were changed
- no side-effect call sites were moved
- only `docs/readiness_fixture_matrix.md` was created for this task
