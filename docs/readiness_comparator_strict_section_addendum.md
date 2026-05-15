# Readiness Comparator Strict-Section Addendum

## 1. Purpose

This document defines readiness-specific strict comparator policy for future replay harness work.

No runtime code is changed by this document.

This document does not permit readiness extraction.

This document does not permit provider extraction.

This document does not create harness code.

This document does not create fixture files.

This document defines comparator policy only.

Readiness tuple-shape and reason-code drift are conformance-blocking.

Future readiness movement requires old-vs-new parity using this strict profile.

## 2. Readiness comparator principles

- Compare current runtime-compatible tuple semantics first.
- Normalized adapter objects may add fields, but must not hide runtime drift.
- Runtime reason must be preserved exactly.
- Pass reason shape must be preserved exactly.
- Block reason strings must match exactly.
- `nil`, `false`, and empty string must remain distinct.
- Branch kind must match exactly for `action_ready`.
- Resource IDs and recast IDs must remain numeric.
- Detail fields are strict when declared required by fixture/profile.
- No timestamp or numeric tolerance for IDs, reasons, booleans, branch kind, action names, resource IDs, recast IDs, or target IDs.
- Side effects must remain zero.

## 3. Readiness normalized result input shape

Expected normalized readiness comparator input shape:

```lua
{
  ok = true or false,
  action_name = "string",
  action_kind = "spell" or "ja" or "none" or "unknown",
  reason = nil or "string",
  runtime_reason = nil or "string",
  normalized_reason = "string",
  tuple = {
    values = {},
    arity = number,
  },
  detail = {},
  side_effects = {},
  error = nil,
}
```

Input contract:

- Comparator receives two normalized readiness objects: `old_readiness`, `new_readiness`.
- Comparator validates schema before value comparison.
- Missing required fields fail as `invalid_result_shape`.
- `tuple.values` must preserve positional return values from runtime call site.

## 4. Runtime tuple parity policy

Strict tuple parity is mandatory:

- `spell_ready`: compare tuple arity `2`, position `[1]=ok`, `[2]=runtime_reason`.
- `ja_ready`: compare tuple arity `2`, position `[1]=ok`, `[2]=runtime_reason`.
- `action_ready`: compare tuple arity `3`, position `[1]=ok`, `[2]=runtime_reason`, `[3]=kind`.
- `spell_known_and_usable`: compare tuple arity `2`, position `[1]=ok`, `[2]=runtime_reason`.
- `available_cure_tier_max`: compare scalar numeric output exactly.
- `get_usable_cure_from_tier`: compare `(name,tier)` or `nil` exactly.

Rules:

- Tuple arity mismatch is immediate conformance failure.
- Tuple position mismatch is immediate conformance failure.
- For pass cases where runtime returns `''`, `runtime_reason` must be `''` (not `nil`).
- `normalized_reason` may be adapter-enriched, but cannot contradict runtime tuple outcome.

## 5. Readiness strict sections

Comparator strict sections for readiness profile:

1. `ok`
2. `action_name`
3. `action_kind`
4. `runtime_reason`
5. `tuple.arity`
6. `tuple.values`
7. required `detail` keys (fixture-profile-driven)
8. `side_effects` zero baseline
9. `error` (must be nil for successful readiness parity fixtures)

Section ordering rule:

- Compare in listed order and stop at first mismatch by default.

## 6. Reason parity policy

For block outcomes:

- `runtime_reason` must match exact string from runtime contract.
- `normalized_reason` must map to canonical reason in `docs/readiness_reason_code_catalog.md`.
- `runtime_reason` and `normalized_reason` must be semantically consistent.

For pass outcomes:

- Runtime pass reason for readiness tuple functions is currently `''`; comparator must enforce exact match where applicable.
- Adapter may expose pass labels (for example `READY_SPELL`) only in `normalized_reason`.
- `reason` field may be adapter-convenience `nil`, but `runtime_reason` must preserve runtime value.

Failure classes:

- `runtime_reason_mismatch`
- `normalized_reason_mismatch`
- `pass_shape_mismatch`
- `reason_semantic_mismatch`

## 7. Action branch-kind strictness

`action_ready` branch kind strict rules:

- allowed kinds: `spell`, `ja`, `none` (runtime), `unknown` (normalized only when explicitly mapped).
- tuple position 3 (`kind`) must match exactly between old and new.
- spell/JA name collision must preserve runtime precedence (spell-first).

Required mismatch reasons:

- `action_kind_mismatch`
- `branch_precedence_mismatch`
- `tuple_kind_position_mismatch`

## 8. Detail field strictness profile

Detail fields are strict when fixture declares them required.

Minimum required detail fields by scenario:

- spell recast block: `recast_id`, `recast_remaining`, `action_kind`.
- spell MP block: `mp_required`, `mp_available`, `spell_id`.
- JA target/range/front blocks: `target_id`, `effective_range`, `target_distance`, `front_arc_required`.
- Chivalry blocks: `tp` or `mp_pct` threshold context.
- unknown action block: `spell_lookup_hit`, `ja_lookup_hit`.

Rules:

- required detail key missing => `missing_key`.
- required detail value type mismatch => `type_mismatch`.
- optional detail keys may exist but must not conflict with required keys.

## 9. Numeric strictness overrides for readiness

No tolerance allowed for:

- `ok`
- reason fields (`reason`, `runtime_reason`, `normalized_reason`)
- tuple arity
- tuple positional outputs
- `action_name`
- `action_kind`
- `resource_id`, `spell_id`, `ja_id`, `recast_id`, `target_id`
- boolean gates

Allowed tolerance:

- none by default for readiness strict sections.
- any future tolerance exception requires explicit comparator policy amendment and reviewer approval.

## 10. Side-effect strictness for readiness profile

Readiness strict profile requires:

- `side_effects.attempted == false`
- guarded API counts all `0`
- no unexpected `first_violation`

Any violation triggers:

- immediate strict mismatch
- conformance rejection for parity fixtures

Diagnostic fixtures:

- may exercise violation handling
- cannot satisfy readiness parity approval

## 11. Fixture-driven strict comparison mapping

| Fixture group | Strict fields | Primary mismatch reasons |
|---|---|---|
| spell readiness block fixtures | `ok`, `runtime_reason`, tuple `[1..2]`, required detail keys | `runtime_reason_mismatch`, `tuple_arity_mismatch`, `missing_key` |
| JA readiness block fixtures | `ok`, `runtime_reason`, tuple `[1..2]`, `action_kind`, target/range detail | `action_kind_mismatch`, `value_mismatch`, `type_mismatch` |
| action routing fixtures | tuple `[1..3]`, branch kind, runtime reason | `tuple_kind_position_mismatch`, `branch_precedence_mismatch` |
| cure readiness fixtures | scalar/tuple value exactness, fallback behavior | `value_mismatch`, `type_mismatch` |
| metadata influence fixtures | helper-derived fields in detail | `value_mismatch`, `type_mismatch` |

## 12. Conformance gating with readiness strict profile

Readiness conformance cannot approve unless:

- all readiness strict fixtures pass with zero strict mismatches.
- tuple arity/value parity is clean across old/new for readiness functions.
- runtime reason exact-match parity is clean.
- side-effect zero baseline passes.

Runtime extraction consideration remains blocked unless:

- readiness strict profile passes across full required fixture matrix.
- no unresolved readiness strict mismatches remain.

## 13. Mismatch reporting addendum fields

For readiness strict mismatches, comparator output should include:

- `section = "readiness"`
- `mismatch_path`
- `reason` (one of standard reasons or readiness-specific reasons)
- `fixture_name`
- `action_name`
- `action_kind`
- `runtime_reason_old`
- `runtime_reason_new`
- `tuple_arity_old`
- `tuple_arity_new`
- `tuple_value_old`
- `tuple_value_new`

Recommended readiness-specific reasons:

- `tuple_arity_mismatch`
- `tuple_value_mismatch`
- `runtime_reason_mismatch`
- `normalized_reason_mismatch`
- `pass_shape_mismatch`
- `action_kind_mismatch`
- `branch_precedence_mismatch`

## 14. Stop conditions

This addendum does not permit moving:

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

## 15. Recommended next tasks

1. Docs-only spell/JA cache reset lifecycle policy addendum.
2. Docs-only readiness edge-case matrix for job-point/subjob boundary conditions.
3. Docs-only readiness comparator output schema appendix with example payloads.
4. Create non-runtime readiness comparator skeleton only after policy docs are approved.
5. Create non-runtime readiness validator skeleton only after policy docs are approved.

## 16. Validation snapshot

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
- only `docs/readiness_comparator_strict_section_addendum.md` was created for this task
