# Replay Fixture Coverage Matrix

## 1. Purpose

This document defines the minimum fixture coverage matrix required for future replay adapter conformance.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create fixture files.

This document does not create harness code.

This document defines coverage policy only.

Adapter conformance cannot be approved unless required coverage rows are satisfied.

Runtime extraction cannot be considered unless lane-required fixture coverage passes.

## 2. Coverage principles

- Every checklist ID must map to at least one fixture or static adapter inspection item.
- Every fixture must have a clear purpose.
- Fixture names must be stable.
- Fixture coverage must be lane-specific.
- Shared checklist coverage must apply to both lanes.
- Negative/error fixtures are required, not optional.
- Side-effect guard fixtures are diagnostic-only unless explicitly zero-side-effect parity fixtures.
- Fixture coverage should prove both valid behavior and fail-fast behavior.
- No fixture may depend on live Windower state.
- No fixture may emit side effects.
- Gaps must be explicit and block conformance approval.

## 3. Fixture naming convention

Naming pattern:

```text
<lane>_<area>_<scenario>_<expected>
```

Rules:

- `lane` must be one of `shared`, `maintenance`, `enemy`.
- `area` should describe tested contract slice (for example `schema`, `deps`, `state`, `proposal`, `guard`, `error`, `determinism`).
- `scenario` should describe condition/setup (for example `missing_dep`, `key_type`, `claim_invalid`).
- `expected` should encode expected outcome class (`pass`, `failfast`, `reject`, `parity`).
- Use lowercase snake_case only.
- Once referenced in a conformance report, fixture names are immutable.

Examples:

- `shared_deps_missing_readiness_failfast`
- `maintenance_state_recent_gain_timestamp_parity`
- `enemy_guard_send_command_reject`

## 4. Coverage matrix schema

Each matrix row uses these columns:

- `checklist_id`: one of `S1-S10`, `M1-M10`, `E1-E10`
- `lane`: `shared`, `maintenance`, `enemy_effect`
- `fixture_or_inspection`: required fixture scenario or static adapter inspection artifact
- `minimum_pass_criteria`: minimum condition that must pass
- `required_evidence_artifact`: report artifact path/section reference
- `gap_flag`: `CLEAR`, `PARTIAL`, or `MISSING`
- `priority`: `P0`, `P1`, `P2`
- `required_for_conformance_approval`: `YES` or `NO`
- `required_for_runtime_extraction_consideration`: `YES` or `NO`

Gap flag policy:

- `CLEAR`: evidence exists and pass criteria met.
- `PARTIAL`: evidence exists but incomplete or non-deterministic.
- `MISSING`: no acceptable evidence.

Conformance gate policy:

- Any `MISSING` or unresolved `PARTIAL` row with `required_for_conformance_approval=YES` rejects conformance.

Extraction gate policy:

- Runtime extraction consideration is blocked until all `required_for_runtime_extraction_consideration=YES` rows are `CLEAR`.

## 5. Shared checklist coverage matrix (`S1-S10`)

| checklist_id | lane | fixture_or_inspection | minimum_pass_criteria | required_evidence_artifact | gap_flag | priority | required_for_conformance_approval | required_for_runtime_extraction_consideration |
|---|---|---|---|---|---|---|---|---|
| `S1` | shared | `shared_interface_entrypoint_contract_pass` + static adapter signature inspection | both old/new expose `run(fixture,deps,options)` and lane entrypoint with exact signature | conformance report: adapter metadata + checklist matrix row `S1` | MISSING | P0 | YES | YES |
| `S2` | shared | `shared_args_invalid_fixture_failfast` and `shared_args_invalid_options_failfast` | invalid args fail fast with structured error; no silent pass | failure detail section + comparator/error output for fail-fast fixtures | MISSING | P0 | YES | YES |
| `S3` | shared | `shared_deps_missing_readiness_failfast` and `shared_deps_missing_windower_failfast` | missing required deps return `MISSING_DEP` and do not fallback | failure detail + error payload snapshots + trace | MISSING | P0 | YES | YES |
| `S4` | shared | `shared_fixture_immutability_pass` (old and new runs) | `fixture`, `state_before`, `inputs`, `expected` unchanged after run | fixture pre/post diff artifact + checklist row `S4` | MISSING | P0 | YES | YES |
| `S5` | shared | `shared_result_shape_contract_pass` | normalized result includes all required fields with correct types | result-shape validation output + checklist row `S5` | MISSING | P0 | YES | YES |
| `S6` | shared | `shared_error_taxonomy_contract_pass` + `shared_runtime_error_normalized_failfast` | error codes and structure follow approved taxonomy | error payload matrix + checklist row `S6` | MISSING | P0 | YES | YES |
| `S7` | shared | `shared_guard_zero_side_effect_parity` + negative guard fixtures | strict-mode parity fixtures show zero prohibited calls; violation fixtures are rejected | side-effect guard summary + count_by_api + first_violation | MISSING | P0 | YES | YES |
| `S8` | shared | `shared_determinism_repeat3_pass` | repeated identical runs produce identical outputs and traces in required sections | repeated-run compare artifact + checklist row `S8` | MISSING | P0 | YES | YES |
| `S9` | shared | `shared_lane_isolation_no_orchestrator_calls` | adapters do not call forbidden cross-lane/orchestrator/dispatch paths | call-trace/inspection artifact + checklist row `S9` | MISSING | P0 | YES | YES |
| `S10` | shared | `shared_version_metadata_contract_pass` | adapter metadata (`interface_version`,`lane`,`adapter_name`) is complete and consistent | adapter metadata section + checklist row `S10` | MISSING | P1 | YES | YES |

## 6. Maintenance checklist coverage matrix (`M1-M10`)

| checklist_id | lane | fixture_or_inspection | minimum_pass_criteria | required_evidence_artifact | gap_flag | priority | required_for_conformance_approval | required_for_runtime_extraction_consideration |
|---|---|---|---|---|---|---|---|---|
| `M1` | maintenance | `maintenance_context_minimal_valid_parity`, `maintenance_context_city_zone_block_reject`, `maintenance_context_status_input_path_parity` | context built from fixture-only inputs; city-zone and lane input gates behave deterministically | comparator summary + maintenance fixture matrix | MISSING | P0 | YES | YES |
| `M2` | maintenance | `maintenance_state_required_slices_parity`, `maintenance_state_recent_gain_update_parity`, `maintenance_state_family_tokens_parity` | required maintenance state slices present and correctly updated | before/after state snapshots + checklist row `M2` | MISSING | P0 | YES | YES |
| `M3` | maintenance | `maintenance_proposals_capture_order_parity`, `maintenance_proposals_duplicate_suppression_parity` | `proposals_pre_rank` captured before ranking/dispatch and source-order deterministic | proposal section output + order checks | MISSING | P0 | YES | YES |
| `M4` | maintenance | `maintenance_comparator_profile_strict_pass` | maintenance strict sections compare cleanly with no unapproved mismatch | comparator output for required strict sections | MISSING | P0 | YES | YES |
| `M5` | maintenance | `maintenance_guard_zero_side_effect_parity` + `maintenance_guard_violation_diagnostic_reject` | parity fixtures have zero side effects; diagnostic violations never approve parity | side-effect guard summary for maintenance fixtures | MISSING | P0 | YES | YES |
| `M6` | maintenance | `maintenance_schema_required_fields_pass`, `maintenance_schema_invalid_field_failfast`, `maintenance_schema_invalid_side_effect_expectation_failfast` | all maintenance fixtures pass schema before execution; invalid schema fixtures fail fast | schema validation logs + failure details | MISSING | P0 | YES | YES |
| `M7` | maintenance | `maintenance_semantics_nil_false_empty_parity` | `nil` vs `false` vs `\"\"` semantics preserved | comparator mismatch-free proof on semantic paths | MISSING | P1 | YES | YES |
| `M8` | maintenance | `maintenance_numeric_key_integrity_parity`, `maintenance_key_type_invalid_failfast` | numeric-key maps remain numeric; key-type violations fail | key-type assertion artifact + checklist row `M8` | MISSING | P1 | YES | YES |
| `M9` | maintenance | `maintenance_invalid_fixture_failfast`, `maintenance_missing_dep_failfast` | invalid fixture/deps produce structured fail-fast errors (no fallback) | error/failure section + taxonomy proof | MISSING | P0 | YES | YES |
| `M10` | maintenance | `maintenance_parity_full_suite_pass` | no unresolved old/new mismatches across required maintenance fixture suite | conformance report decision gate + comparator aggregate | MISSING | P0 | YES | YES |

## 7. Enemy-effect checklist coverage matrix (`E1-E10`)

| checklist_id | lane | fixture_or_inspection | minimum_pass_criteria | required_evidence_artifact | gap_flag | priority | required_for_conformance_approval | required_for_runtime_extraction_consideration |
|---|---|---|---|---|---|---|---|---|
| `E1` | enemy_effect | `enemy_context_valid_claim_dispellable_parity`, `enemy_context_invalid_claim_reject`, `enemy_context_action_input_path_parity` | enemy-effect context built deterministically from fixture-only inputs and claim/action paths | comparator summary + enemy fixture matrix | MISSING | P0 | YES | YES |
| `E2` | enemy_effect | `enemy_state_required_slices_parity`, `enemy_state_clear_prune_sweep_scope_parity` | required enemy-effect state slices present with correct target/effect scope mutation | before/after state snapshots + checklist row `E2` | MISSING | P0 | YES | YES |
| `E3` | enemy_effect | `enemy_proposals_capture_order_parity`, `enemy_proposals_attempt_throttle_parity` | proposals captured pre-rank and deterministic order preserved | proposal output + ordering artifact | MISSING | P0 | YES | YES |
| `E4` | enemy_effect | `enemy_comparator_profile_strict_pass` | enemy-effect strict sections compare cleanly with no unapproved mismatch | comparator strict-section artifact | MISSING | P0 | YES | YES |
| `E5` | enemy_effect | `enemy_guard_zero_side_effect_parity` + `enemy_guard_violation_diagnostic_reject` | zero side effects in parity fixtures; diagnostic violations cannot approve | side-effect guard summary for enemy fixtures | MISSING | P0 | YES | YES |
| `E6` | enemy_effect | `enemy_schema_required_fields_pass`, `enemy_schema_unknown_field_failfast`, `enemy_schema_invalid_key_type_failfast` | all enemy fixtures pass schema before execution; invalid fixtures fail fast | schema validation logs + failure details | MISSING | P0 | YES | YES |
| `E7` | enemy_effect | `enemy_numeric_target_effect_keys_parity`, `enemy_stringified_keys_failfast` | target/effect keys remain numeric; stringified keys rejected/mismatch surfaced | key-type evidence + checklist row `E7` | MISSING | P0 | YES | YES |
| `E8` | enemy_effect | `enemy_timestamps_exact_mode_parity`, `enemy_cooldown_timestamp_policy_parity` | time-like fields comply with comparator timestamp policy and deterministic `now` source | timestamp compare artifact + policy mode declaration | MISSING | P0 | YES | YES |
| `E9` | enemy_effect | `enemy_invalid_fixture_failfast`, `enemy_missing_dep_failfast` | invalid fixture/deps produce structured fail-fast errors | error payload artifacts + checklist row `E9` | MISSING | P0 | YES | YES |
| `E10` | enemy_effect | `enemy_parity_full_suite_pass` | no unresolved old/new mismatches across required enemy suite | conformance report decision gate + comparator aggregate | MISSING | P0 | YES | YES |

## 8. Cross-lane mandatory fixture scenarios

These scenarios are mandatory for both lanes and must be represented by lane-specific fixtures where applicable:

| scenario_group | required scenarios | minimum pass criteria | required for conformance approval | required for runtime extraction consideration |
|---|---|---|---|---|
| schema fail-fast | missing required field, unknown field, wrong type, invalid key type | schema validator fails before adapter execution | YES | YES |
| dependency fail-fast | missing `deps` elements (`readiness`, `windower`, `state_tools`) | `MISSING_DEP` with precise path/detail | YES | YES |
| guard zero baseline | strict parity fixtures with zero side-effect counts | all guarded API counts remain `0` | YES | YES |
| guard negative diagnostics | command/movement/target/IPC/file-write attempt fixtures | violation recorded and run rejected for parity | YES | YES |
| determinism repeatability | same fixture run multiple times | identical outputs in required sections | YES | YES |
| semantic preservation | `nil`/`false`/empty-string differentiation | no semantic coercion mismatches | YES | YES |
| parity aggregate | full lane suites | unresolved mismatch count is `0` | YES | YES |

## 9. Minimum pass criteria by evidence class

| evidence class | minimum pass criteria | source artifact location in conformance report |
|---|---|---|
| adapter metadata | complete old/new adapter metadata and version fields | `Adapter Metadata` section |
| fixture metadata | fixture names, lane, schema version, count are complete | `Fixture Set Metadata` section |
| checklist matrix | every required ID has explicit PASS/FAIL | `Checklist Matrix` section |
| side-effect summary | strict-mode zero baseline proven for parity fixtures | `Side-Effect Guard Summary` section |
| comparator summary | required strict sections pass with deterministic first mismatch when failing | `Comparator Summary` section |
| failure detail | first failure includes ID/code/path/remediation/rerun flag | `Failure Details` section |
| evidence inventory | all run artifacts and reproduction commands listed | `Evidence Package Inventory` section |
| approval gate | only PASS across required rows can mark approved | `Decision` section |

## 10. Gap management and blocking rules

- `MISSING` on any row with `required_for_conformance_approval=YES` blocks `CONFORMANCE_APPROVED`.
- `PARTIAL` on any `P0` row is treated as blocking until resolved to `CLEAR`.
- `PARTIAL` on `P1` rows may proceed only if explicitly accepted in writing by reviewer and does not violate policy gates.
- `MISSING` or unresolved `PARTIAL` on any row with `required_for_runtime_extraction_consideration=YES` blocks runtime extraction consideration.
- Gap status must be captured in conformance report notes and decision rationale.

## 11. Priority rubric

- `P0`: safety, schema validity, deterministic contract, parity gate rows.
- `P1`: semantic correctness rows that can still block approval/extraction.
- `P2`: supplemental confidence rows (none currently defined as required).

Policy:

- No downgrade from `P0`/`P1` without documented policy revision.

## 12. Stop conditions

This document does not permit moving:

- `p1_collect_maintenance`
- `p1_collect_enemy_buff_removal`
- `ingest_enemy_effects_from_raw_action_028`
- enemy-effect state mutators
- maintenance state mutators
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
- any direct side-effect owner

No immediate provider extraction is allowed.

No harness runtime code is created by this task.

No fixture files are created by this task.

## 13. Recommended next tasks

1. Docs-only readiness/resource-cache ownership design for adapter boundary hardening.
2. Docs-only loader-contract fixture profile extension policy.
3. Draft non-runtime fixture validator skeleton only after policy docs are approved.
4. Draft non-runtime comparator skeleton only after policy docs are approved.
5. Draft docs-only conformance evidence manifest schema for artifact consistency.

Do not perform immediate provider extraction.

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
- only `docs/replay_fixture_coverage_matrix.md` was created for this task
