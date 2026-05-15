# Readiness Reason-Code Catalog

## 1. Purpose

This document defines the canonical readiness reason-code catalog for future replay adapters and fixture validation.

No runtime code is changed by this document.

This document does not permit readiness extraction.

This document does not permit provider extraction.

This document does not create harness code.

This document does not create fixture files.

This document defines catalog policy only.

Reason-code parity is required before readiness/resource-cache movement.

Reason-code drift is conformance-blocking because readiness false positives and false negatives change proposal behavior.

## 2. Catalog principles

- Reason strings/codes are behavior contract.
- Current runtime return shapes must not be changed.
- Future adapters may normalize tuple returns, but must preserve current reason meaning.
- Every block reason must map to at least one fixture.
- Every pass case must map to at least one fixture.
- Unknown/missing dependency behavior must be explicit.
- `nil` reason on pass must remain distinct from `false` or empty string.
- Reason-code changes require fixture and comparator policy updates.
- Readiness reasons must not be silently collapsed.

## 3. Current readiness return shapes

| Source function | Pass return shape | Blocked return shape | Unknowns to inspect | Future normalized adapter shape |
|---|---|---|---|---|
| `spell_ready(name)` | `(true, '')` | `(false, 'BLOCK_*')` | none observed for tuple arity; reason empty-string on pass is current runtime behavior | `{ ok, action_kind='spell', runtime_reason, normalized_reason, detail }` |
| `ja_ready(name,target_id)` | `(true, '')` | `(false, 'BLOCK_*')` | none observed for tuple arity; includes engaged/front and target gates | `{ ok, action_kind='ja', runtime_reason, normalized_reason, detail }` |
| `action_ready(name,target_id)` | spell branch: `(ok, reason, 'spell')`; JA branch: `(ok, reason, 'ja')` | unknown action: `(false, 'BLOCK_DEFENSIVE_UNKNOWN_ACTION', 'none')` | branch precedence when both spell/JA names collide should stay spell-first (current order) | `{ ok, action_kind, runtime_reason, normalized_reason, detail }` |
| `spell_known_and_usable(sp)` | `(true, '')` | `(false, 'BLOCK_DEFENSIVE_UNKNOWN_SPELL' | 'BLOCK_DEFENSIVE_NOT_LEARNED' | 'BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL')` | none observed | `{ ok, action_kind='spell', runtime_reason, normalized_reason, detail }` |
| `spell_usable_by_current_job(sp)` | `true` | `false` | no reason code returned directly; reason assigned by caller | `{ ok, detail.job_eligibility }` |
| `available_cure_tier_max()` | numeric tier `1..6` or `0` | `0` effectively represents no available tier | no explicit reason string in current runtime | `{ ok=(tier>0), tier, runtime_reason=nil, normalized_reason='READY_CURE_TIER' or 'BLOCK_CURE_NONE_USABLE' }` |
| `get_usable_cure_from_tier(orig_tier,min_tier)` | `(name, tier)` | `nil` | no explicit reason string in current runtime | `{ ok, cure_name, cure_tier, runtime_reason=nil, normalized_reason }` |
| metadata wrappers (`spell_known_flag`, `job_id_by_short`, `action_status_id`, `action_duration_seconds`, `action_effective_range`, `action_target_mode`) | scalar values as defined by helper | fallback scalar (for example `0`, `nil`, default, `normal`) | none observed in signatures; meaning is context-dependent | adapter detail enrichment only; runtime return unchanged |

## 4. Canonical reason-code table

| Reason code/string | Source function(s) | Trigger condition | Positive/negative | Required fixture name(s) | Normalized adapter reason | Detail fields required | Comparator strictness | Conformance priority | Notes |
|---|---|---|---|---|---|---|---|---|---|
| `BLOCK_DEFENSIVE_UNKNOWN_SPELL` | `spell_known_and_usable`, `spell_ready` | spell resource missing or invalid spell table/id | negative | `readiness_spell_ready_unknown_spell_fail`, `readiness_known_invalid_spell_fail` | `BLOCK_DEFENSIVE_UNKNOWN_SPELL` | `action_name`, `lookup_path`, `resource_present=false` | strict | P0 | shared between direct spell-ready and known/usable gate |
| `BLOCK_DEFENSIVE_NOT_LEARNED` | `spell_known_and_usable`, via `spell_ready` | spell id not known by player flags | negative | `readiness_known_not_learned_fail`, `readiness_spell_ready_not_learned_fail` | `BLOCK_DEFENSIVE_NOT_LEARNED` | `spell_id`, `known_flag_value` | strict | P0 | `spell_known_flag` semantics influence trigger |
| `BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL` | `spell_known_and_usable`, via `spell_ready` | job/subjob eligibility fails | negative | `readiness_usable_spell_job_block_fail`, `readiness_spell_ready_job_block_fail` | `BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL` | `main_job_id`, `sub_job_id`, `required_levels` | strict | P0 | includes main/sub level and jp checks |
| `BLOCK_DEFENSIVE_RECAST` | `spell_ready`, `ja_ready` | recast table reports remaining > 0 | negative | `readiness_spell_ready_recast_fail`, `readiness_ja_ready_recast_fail` | `BLOCK_DEFENSIVE_RECAST` | `recast_id`, `recast_remaining`, `action_kind` | strict | P0 | same code used for spell and JA recast blocks |
| `BLOCK_DEFENSIVE_NO_PLAYER` | `spell_ready` | player or player.vitals missing | negative | `readiness_spell_ready_no_player_fail` | `BLOCK_DEFENSIVE_NO_PLAYER` | `player_present`, `vitals_present` | strict | P0 | fail-fast runtime-read gate |
| `BLOCK_DEFENSIVE_NO_MP` | `spell_ready` | `mp_available < mp_cost` | negative | `readiness_spell_ready_no_mp_fail` | `BLOCK_DEFENSIVE_NO_MP` | `mp_required`, `mp_available`, `spell_id` | strict | P0 | spell-only MP gate |
| `BLOCK_DEFENSIVE_UNKNOWN_JA` | `ja_ready` | JA resource missing | negative | `readiness_ja_ready_unknown_ja_fail` | `BLOCK_DEFENSIVE_UNKNOWN_JA` | `action_name`, `resource_present=false` | strict | P0 | entry failure for JA branch |
| `BLOCK_DEFENSIVE_JA_NOT_OWNED` | `ja_ready` | JA id not in owned JA list | negative | `readiness_ja_ready_not_owned_fail` | `BLOCK_DEFENSIVE_JA_NOT_OWNED` | `ja_id`, `owned_ids` | strict | P0 | ownership gate before target/range |
| `BLOCK_ACTION_STATUS3` | `ja_ready` | player status equals 3 | negative | `readiness_ja_ready_status_block_fail` | `BLOCK_ACTION_STATUS3` | `player_status` | strict | P0 | generic hard status block in JA path |
| `BLOCK_JA_BAD_TARGET` | `ja_ready` | target missing/invalid/dead/non-enemy spawn type | negative | `readiness_ja_ready_bad_target_fail` | `BLOCK_JA_BAD_TARGET` | `target_id`, `spawn_type`, `hpp`, `valid_target` | strict | P0 | enemy-target JA validation |
| `BLOCK_JA_OUT_OF_RANGE` | `ja_ready` | computed distance exceeds effective range | negative | `readiness_ja_ready_out_of_range_fail` | `BLOCK_JA_OUT_OF_RANGE` | `target_distance`, `effective_range`, `range_raw` | strict | P0 | depends on `action_effective_range` |
| `BLOCK_JA_NOT_FRONT` | `ja_ready` | engaged-front JA and target not in front arc | negative | `readiness_ja_ready_not_front_fail` | `BLOCK_JA_NOT_FRONT` | `front_arc_required`, `front_arc_passed` | strict | P0 | depends on predicates + geometry |
| `BLOCK_CHIVALRY_TP_LOW` | `ja_ready` | action is Chivalry and TP below threshold | negative | `readiness_ja_ready_chivalry_tp_low_fail` | `BLOCK_CHIVALRY_TP_LOW` | `tp`, `tp_required=2000` | strict | P0 | JA-specific special rule |
| `BLOCK_CHIVALRY_MP_TOO_HIGH` | `ja_ready` | action is Chivalry and MP% >= threshold | negative | `readiness_ja_ready_chivalry_mp_high_fail` | `BLOCK_CHIVALRY_MP_TOO_HIGH` | `mp`, `max_mp`, `mp_pct`, `threshold_pct=50` | strict | P0 | JA-specific special rule |
| `BLOCK_DEFENSIVE_UNKNOWN_ACTION` | `action_ready` | neither spell nor JA resource matched | negative | `readiness_action_ready_unknown_action_fail` | `BLOCK_DEFENSIVE_UNKNOWN_ACTION` | `action_name`, `spell_lookup_hit=false`, `ja_lookup_hit=false` | strict | P0 | action router terminal block |
| `READY_SPELL` | `spell_ready` | spell gate passes | positive | `readiness_spell_ready_pass` | `READY_SPELL` | `runtime_reason=''`, `action_kind='spell'` | strict | P0 | runtime reason remains `''`; normalized label only in adapter |
| `READY_JA` | `ja_ready` | JA gate passes | positive | `readiness_ja_ready_pass` | `READY_JA` | `runtime_reason=''`, `action_kind='ja'` | strict | P0 | runtime reason remains `''`; normalized label only in adapter |
| `READY_ACTION_SPELL` | `action_ready` | spell branch selected and returned | positive | `readiness_action_ready_spell_branch_pass` | `READY_ACTION_SPELL` | `kind='spell'`, delegated runtime_reason | strict | P0 | branch precedence is spell-first |
| `READY_ACTION_JA` | `action_ready` | JA branch selected and returned | positive | `readiness_action_ready_ja_branch_pass` | `READY_ACTION_JA` | `kind='ja'`, delegated runtime_reason | strict | P0 | branch only after spell miss |
| `READY_CURE_TIER` | `available_cure_tier_max`, `get_usable_cure_from_tier` | at least one usable cure tier found | positive | `readiness_cure_max_tier_pass`, `readiness_cure_fallback_pass` | `READY_CURE_TIER` | `tier`, optional `cure_name` | strict | P1 | normalized-only label; runtime returns tier/name |
| `READY_METADATA_LOOKUP` | metadata wrappers | helper lookup/derivation succeeds deterministically | positive | `readiness_meta_spell_known_true_pass`, `readiness_meta_job_id_lookup_pass`, `readiness_meta_action_range_scaled_pass`, `readiness_meta_target_mode_self_only_pass` | `READY_METADATA_LOOKUP` | helper-specific fields | strict | P1 | wrapper/extracted influence on readiness reasons |

Pass-reason note:

- current runtime uses empty-string reason (`''`) for pass in `spell_ready`, `ja_ready`, `spell_known_and_usable`.
- normalized adapter may expose pass labels (`READY_*`) in `normalized_reason`, while preserving runtime-compatible reason in `runtime_reason`.

## 5. Spell readiness reason catalog

| Reason | Exact trigger | Required stubs | Fixture name | Expected old/new result | Normalized detail fields | Checklist/coverage IDs | Mismatch triage mapping |
|---|---|---|---|---|---|---|---|
| `BLOCK_DEFENSIVE_UNKNOWN_SPELL` | `get_spell_resource(name)` returns `nil` or invalid spell table | `res.spells`, optional lc fallback | `readiness_spell_ready_unknown_spell_fail` | both return `(false,'BLOCK_DEFENSIVE_UNKNOWN_SPELL')` | `action_name`, `resource_present=false` | S5, S6, readiness P0 | `missing_key`/`value_mismatch`/`error_mismatch` |
| `BLOCK_DEFENSIVE_NOT_LEARNED` | known flag for spell id is falsey by `spell_known_flag` | `windower.ffxi.get_spells`, spell resource | `readiness_spell_ready_not_learned_fail` | both return block reason exactly | `spell_id`, `known_flag_value` | S6, M7/E7 | `value_mismatch`/`nil_vs_false` |
| `BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL` | `spell_usable_by_current_job(sp)` false | `windower.ffxi.get_player`, `res.jobs` | `readiness_spell_ready_job_block_fail` | both return block reason exactly | `main_job_id`, `sub_job_id`, `required_levels` | S6, S3, readiness P0 | `value_mismatch`/`type_mismatch` |
| `BLOCK_DEFENSIVE_RECAST` | spell recast entry > 0 | `windower.ffxi.get_spell_recasts` | `readiness_spell_ready_recast_fail` | both return recast block | `recast_id`, `recast_remaining` | S5, M4/E4 | `value_mismatch`/`numeric_tolerance_exceeded` |
| `BLOCK_DEFENSIVE_NO_PLAYER` | player or vitals missing | `windower.ffxi.get_player` | `readiness_spell_ready_no_player_fail` | both return no-player block | `player_present`, `vitals_present` | S2, S6 | `missing_key`/`error_mismatch` |
| `BLOCK_DEFENSIVE_NO_MP` | mp lower than mp_cost | `windower.ffxi.get_player`, spell resource | `readiness_spell_ready_no_mp_fail` | both return no-mp block | `mp_required`, `mp_available` | S5, M1/M4 | `value_mismatch` |
| `READY_SPELL` | all spell gates pass | all spell-ready stubs | `readiness_spell_ready_pass` | both return `(true,'')` | `runtime_reason=''`, `normalized_reason='READY_SPELL'` | S8, M10/E10 | `value_mismatch`/`nondeterministic_output` |

Status restriction note:

- no additional spell status restriction reason is directly emitted in current `spell_ready`; if added later, catalog update is required before conformance.

## 6. JA readiness reason catalog

| Reason | Exact trigger | Required stubs | Fixture name | Expected old/new result | Normalized detail fields | Checklist/coverage IDs | Mismatch triage mapping |
|---|---|---|---|---|---|---|---|
| `BLOCK_DEFENSIVE_UNKNOWN_JA` | JA lookup returns `nil` | `res.job_abilities` | `readiness_ja_ready_unknown_ja_fail` | both return unknown JA block | `action_name`, `resource_present=false` | S5, S6 | `value_mismatch` |
| `BLOCK_DEFENSIVE_JA_NOT_OWNED` | JA id not present in owned JA ids | `windower.ffxi.get_abilities` | `readiness_ja_ready_not_owned_fail` | both return not-owned block | `ja_id`, `owned_ids` | S6, E1/E4 | `value_mismatch`/`missing_key` |
| `BLOCK_ACTION_STATUS3` | player status == 3 | `windower.ffxi.get_player` | `readiness_ja_ready_status_block_fail` | both return status block | `player_status` | S6, E1/E4 | `value_mismatch` |
| `BLOCK_JA_BAD_TARGET` | target missing/invalid/non-enemy/dead | target stubs by id/target | `readiness_ja_ready_bad_target_fail` | both return bad-target block | `target_id`, `spawn_type`, `hpp`, `valid_target` | S5, E1/E4 | `value_mismatch`/`type_mismatch` |
| `BLOCK_JA_OUT_OF_RANGE` | computed distance > effective range | target distance + range metadata | `readiness_ja_ready_out_of_range_fail` | both return out-of-range block | `target_distance`, `effective_range` | S5, E4 | `value_mismatch`/`numeric_tolerance_exceeded` |
| `BLOCK_JA_NOT_FRONT` | engaged-front JA and target outside front arc | predicates + geometry stubs | `readiness_ja_ready_not_front_fail` | both return not-front block | `front_arc_required`, `front_arc_passed=false` | S5, E4 | `value_mismatch` |
| `BLOCK_DEFENSIVE_RECAST` | JA recast entry > 0 | `windower.ffxi.get_ability_recasts` | `readiness_ja_ready_recast_fail` | both return recast block | `recast_id`, `recast_remaining` | S5, E4 | `value_mismatch`/`numeric_tolerance_exceeded` |
| `BLOCK_CHIVALRY_TP_LOW` | action is Chivalry and TP < 2000 | player vitals stub | `readiness_ja_ready_chivalry_tp_low_fail` | both return TP-low block | `tp`, `required_tp` | S6, E4 | `value_mismatch` |
| `BLOCK_CHIVALRY_MP_TOO_HIGH` | action is Chivalry and MP% >= 50 | player vitals stub | `readiness_ja_ready_chivalry_mp_high_fail` | both return MP-high block | `mp`, `max_mp`, `mp_pct` | S6, E4 | `value_mismatch` |
| `READY_JA` | all JA gates pass | full JA readiness stubs | `readiness_ja_ready_pass` | both return `(true,'')` | `runtime_reason=''`, `normalized_reason='READY_JA'` | S8, E10 | `nondeterministic_output`/`value_mismatch` |

## 7. Action readiness routing catalog

| Routing case | Fixture name | Expected kind output | Expected reason | Expected normalized adapter detail | Comparator strictness |
|---|---|---|---|---|---|
| spell branch selected | `readiness_action_ready_spell_branch_pass` | `spell` | delegated spell reason (pass: `''`) | `action_kind='spell'`, `branch='spell'`, `normalized_reason='READY_ACTION_SPELL'` | strict |
| JA branch selected | `readiness_action_ready_ja_branch_pass` | `ja` | delegated JA reason (pass: `''`) | `action_kind='ja'`, `branch='ja'`, `normalized_reason='READY_ACTION_JA'` | strict |
| unknown action | `readiness_action_ready_unknown_action_fail` | `none` | `BLOCK_DEFENSIVE_UNKNOWN_ACTION` | `action_kind='unknown'`, `lookup_hit={spell=false,ja=false}` | strict |
| explicit action kind spell (adapter-normalized) | `readiness_action_ready_spell_branch_pass` | `spell` | spell reason | `detail.explicit_kind='spell'` | strict |
| explicit action kind JA (adapter-normalized) | `readiness_action_ready_ja_branch_pass` | `ja` | JA reason | `detail.explicit_kind='ja'` | strict |
| spell/JA name collision | `readiness_action_ready_name_collision_spell_precedence_pass` | `spell` | spell branch reason | `detail.branch_precedence='spell_first'` | strict |

## 8. Cure readiness reason catalog

| Scenario | Fixture name | Expected tier/name output | Expected reason or nil behavior | Normalized detail fields |
|---|---|---|---|---|
| highest tier available | `readiness_cure_max_tier_pass` | `available_cure_tier_max` returns highest tier > 0 | runtime no reason string; adapter can set `READY_CURE_TIER` | `tier`, `max_tier_scan=6` |
| high tier blocked, lower available | `readiness_cure_fallback_pass` | `get_usable_cure_from_tier` returns lower tier name/tier | runtime no reason string | `start_tier`, `selected_tier`, `blocked_tiers` |
| no usable tier | `readiness_cure_none_usable_fail` | `available_cure_tier_max` returns `0` and/or `get_usable_cure_from_tier` returns `nil` | runtime no reason string | `selected_tier=nil`, `scan_result=none` |
| MP blocked path (via spell gates) | `readiness_spell_ready_no_mp_fail` + cure fixtures | blocked cure selection due to spell gate | reason comes from spell gate fixtures, not cure helper direct return | `blocked_by='BLOCK_DEFENSIVE_NO_MP'` |
| recast blocked path (via spell gates) | `readiness_spell_ready_recast_fail` + cure fixtures | blocked cure selection due to recast | reason comes from spell gate fixtures, not cure helper direct return | `blocked_by='BLOCK_DEFENSIVE_RECAST'` |
| start tier below floor | `readiness_cure_start_below_floor_fail` | `get_usable_cure_from_tier` returns `nil` | runtime no reason string | `start_tier`, `floor_tier`, `start_below_floor=true` |

## 9. Metadata helper reason influence

| Helper | Target module | Relevant readiness reason(s) | Fixture names | Expected behavior | Strict comparator fields |
|---|---|---|---|---|---|
| `spell_known_flag` | `uc_scheduler_action_metadata.lua` | `BLOCK_DEFENSIVE_NOT_LEARNED`, `READY_SPELL` | `readiness_meta_spell_known_true_pass`, `readiness_meta_spell_known_false_fail` | only `true`, `1`, `'true'` treated as known | boolean semantics, no coercion drift |
| `job_id_by_short` | `uc_scheduler_action_metadata.lua` | `BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL`, `READY_SPELL` | `readiness_meta_job_id_lookup_pass`, `readiness_meta_job_id_unknown_zero_pass` | unknown short name resolves to `0` | numeric id type and exact value |
| `action_status_id` | `uc_scheduler_action_metadata.lua` | indirect gating/metadata for readiness-adjacent consumers | `readiness_meta_action_status_spell_pass`, `readiness_meta_action_status_ja_pass`, `readiness_meta_action_status_missing_nil_pass` | prefer spell status, then JA status, else nil | number-or-nil exactness |
| `action_duration_seconds` | `uc_scheduler_action_metadata.lua` | readiness-adjacent timing/metadata | `readiness_meta_action_duration_spell_pass`, `readiness_meta_action_duration_default_pass` | spell duration used when positive, else default | duration numeric exactness |
| `action_effective_range` | `uc_scheduler_action_metadata.lua` | `BLOCK_JA_OUT_OF_RANGE`, `READY_JA` | `readiness_meta_action_range_scaled_pass`, `readiness_meta_action_range_direct_pass`, `readiness_meta_action_range_zero_pass` | scaling uses `SCHED_RANGE_MULT` or large-range fallback | effective range numeric exactness |
| `action_target_mode` | `uc_scheduler_action_metadata.lua` | routing/metadata influence on readiness consumers | `readiness_meta_target_mode_self_only_pass`, `readiness_meta_target_mode_normal_pass`, `readiness_meta_target_mode_unknown_action_normal_pass` | self-only only when no other target classes present | mode string exactness |

## 10. Normalized adapter mapping

Future adapters should map current tuple returns into normalized readiness objects without changing runtime semantics:

```lua
{
  ok = true,
  action_name = "Cure IV",
  action_kind = "spell",
  reason = nil,
  runtime_reason = nil,
  normalized_reason = "READY_SPELL",
  detail = {},
}
```

Mapping rules:

- preserve runtime-compatible reason value in `runtime_reason`:
  - current pass tuples use `''` for spell/JA/known-and-usable.
  - adapter may expose `reason=nil` for normalized convenience only if `runtime_reason` is preserved exactly.
- set `normalized_reason` to canonical pass/block label from this catalog.
- include branch detail for `action_ready` (`spell`, `ja`, `none`).
- include recast/mp/target/range/status contextual detail fields when blocked.
- do not collapse distinct runtime reasons into one normalized bucket.

## 11. Conformance and triage gates

- Any reason-code mismatch in strict sections is conformance-blocking.
- Any unmapped readiness reason discovered in runtime code blocks conformance until catalog and fixtures are updated.
- Any pass-shape drift (`(true,'')` vs other value) must be triaged as behavior drift.
- Reason-code updates require synchronized updates to:
  - readiness fixture matrix
  - comparator policy expectations
  - conformance checklist/report evidence references

## 12. Stop conditions

This document does not permit moving:

- `spell_ready`
- `ja_ready`
- `action_ready`
- `spell_known_and_usable`
- `spell_usable_by_current_job`
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

## 13. Recommended next tasks

1. Docs-only readiness comparator strict-section addendum focused on reason/code and tuple-shape parity.
2. Docs-only cache reset lifecycle policy for spell/JA lookup caches.
3. Docs-only readiness edge-case matrix for job-points and subjob-level boundaries.
4. Create non-runtime readiness validator skeleton only after policy docs are approved.
5. Create non-runtime readiness comparator skeleton only after policy docs are approved.

## 14. Validation snapshot

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
- only `docs/readiness_reason_code_catalog.md` was created for this task
