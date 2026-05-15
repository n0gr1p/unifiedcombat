# Replay Adapter Conformance Checklist

## 1. Purpose

This document defines the required conformance checklist for replay adapters before any old-vs-new parity evidence can justify runtime extraction work.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create harness code.

This document defines policy only.

Adapters must pass shared interface conformance and lane-specific conformance (`maintenance`, `enemy_effect`) before parity claims are accepted.

## 2. Scope and prerequisites

This checklist applies to:

- old maintenance adapter
- new maintenance adapter
- old enemy-effect adapter
- new enemy-effect adapter

Required prerequisite documents:

- `docs/replay_adapter_interface_spec.md`
- `docs/replay_comparator_policy_spec.md`
- `docs/replay_side_effect_guard_policy.md`
- `docs/replay_fixture_schema_policy.md`
- `docs/maintenance_replay_fixture_design.md`
- `docs/enemy_effect_replay_fixture_design.md`

Hard gate:

- No adapter pair is conformance-approved if any required checklist item is incomplete.

## 3. Conformance evidence package

Each adapter implementation under review must provide a deterministic evidence package with:

- adapter identifier (`adapter_id`, lane, interface version)
- checklist status table with explicit pass/fail per item
- fixture run matrix used for conformance
- comparator outputs for old-vs-new fixture runs
- side-effect guard summaries for all conformance fixtures
- structured failures for any non-passing item

Evidence rules:

- Evidence must be reproducible.
- Evidence must not depend on live Windower runtime state.
- Evidence must include exact fixture names.
- Evidence must preserve first-failure details (no fallback masking).

## 4. Shared adapter interface conformance checklist

All old/new adapters must pass every item below for each lane.

| ID | Requirement | Pass criteria | Failure code |
|---|---|---|---|
| `S1` | Required entrypoint exists | Adapter exposes `run(fixture, deps, options)` and lane-specific entrypoint (`run_maintenance` or `run_enemy_effect`) with matching signature. | `ADAPTER_ENTRYPOINT_MISSING` |
| `S2` | Required argument contract | Adapter fails fast on missing/invalid `fixture`, `deps`, or `options` with structured error. | `ADAPTER_ARGUMENT_CONTRACT_FAILURE` |
| `S3` | Dependency contract | Adapter requires all mandatory deps from interface spec and does not invent defaults for missing required deps. | `MISSING_DEP` |
| `S4` | Fixture immutability | Adapter does not mutate fixture-owned tables (`fixture`, `fixture.state_before`, `fixture.inputs`, `fixture.expected`). | `FIXTURE_MUTATION_DETECTED` |
| `S5` | Result-shape contract | Adapter returns normalized result shape exactly as defined in interface spec. | `RESULT_SHAPE_MISMATCH` |
| `S6` | Error taxonomy contract | Adapter uses approved error code taxonomy and preserves primary failure as first error. | `ERROR_TAXONOMY_MISMATCH` |
| `S7` | Side-effect guard contract | Adapter runs under guard; prohibited calls are blocked/recorded and never executed live. | `GUARD_CONTRACT_VIOLATION` |
| `S8` | Determinism contract | Repeated runs on same fixture/deps produce identical normalized output. | `NON_DETERMINISTIC_OUTPUT` |
| `S9` | Lane isolation contract | Adapter executes only declared lane logic and does not cross-call unrelated lane mutation paths. | `LANE_ISOLATION_VIOLATION` |
| `S10` | Version metadata contract | Adapter exposes `interface_version`, `lane`, and adapter name metadata consistent with interface spec. | `ADAPTER_VERSION_METADATA_MISMATCH` |

Shared approval rule:

- Shared interface conformance is approved only if `S1` through `S10` all pass for all old/new adapters in both lanes.

## 5. Maintenance adapter conformance checklist

Maintenance adapter conformance is lane-specific and must pass for old and new implementations independently.

| ID | Requirement | Pass criteria | Failure code |
|---|---|---|---|
| `M1` | Maintenance context build | Adapter consumes maintenance-required fixture inputs (`settings`, `player_context`, `party_snapshot`, status snapshot/raw packet lane input) and builds deterministic lane context. | `MAINT_CONTEXT_BUILD_FAILURE` |
| `M2` | Maintenance state ownership | Adapter snapshots and returns required maintenance state slices (`maintenance_state`, `recent_gain`, maintenance slice of `attempted`, `family_tokens`). | `MAINT_STATE_SLICE_MISSING` |
| `M3` | Proposal capture boundary | Adapter captures `proposals_pre_rank` before ranking/dispatch and preserves source-order determinism. | `MAINT_PROPOSAL_CAPTURE_FAILURE` |
| `M4` | Comparator profile compatibility | Adapter output satisfies maintenance comparator profile strict sections and path semantics. | `MAINT_COMPARATOR_PROFILE_MISMATCH` |
| `M5` | Side-effect zero baseline | Conformance fixtures show zero prohibited side effects under strict guard mode. | `MAINT_SIDE_EFFECT_VIOLATION` |
| `M6` | Maintenance fixture schema compliance | All maintenance conformance fixtures pass schema validation before adapter execution. | `MAINT_FIXTURE_SCHEMA_VIOLATION` |
| `M7` | Nil/false/empty handling | Adapter preserves maintenance-lane semantic distinctions (`nil`, `false`, `""`) through result normalization. | `MAINT_SEMANTIC_VALUE_COLLISION` |
| `M8` | Numeric-key integrity | Adapter preserves numeric key typing in maintenance-relevant maps. | `MAINT_KEY_TYPE_MISMATCH` |
| `M9` | Failure transparency | Invalid maintenance fixture/deps fail fast with structured error (no fallback behavior). | `MAINT_FAIL_FAST_VIOLATION` |
| `M10` | Old/new parity readiness | For maintenance conformance fixture set, comparator shows no unapproved mismatches between old and new outputs. | `MAINT_PARITY_FAILURE` |

Maintenance approval rule:

- Maintenance lane conformance is approved only if `M1` through `M10` pass for both old and new maintenance adapters.

## 6. Enemy-effect adapter conformance checklist

Enemy-effect adapter conformance is lane-specific and must pass for old and new implementations independently.

| ID | Requirement | Pass criteria | Failure code |
|---|---|---|---|
| `E1` | Enemy-effect context build | Adapter consumes enemy-effect-required fixture inputs (`mob_snapshot`, `claim_state`, catalog inputs, parsed/raw action inputs) and builds deterministic lane context. | `ENEMY_EFFECT_CONTEXT_BUILD_FAILURE` |
| `E2` | Enemy-effect state ownership | Adapter snapshots and returns required enemy-effect state slices (`enemy_effect_state`, `enemy_dispel_attempts`). | `ENEMY_EFFECT_STATE_SLICE_MISSING` |
| `E3` | Proposal capture boundary | Adapter captures `proposals_pre_rank` before ranking/dispatch and preserves source-order determinism. | `ENEMY_EFFECT_PROPOSAL_CAPTURE_FAILURE` |
| `E4` | Comparator profile compatibility | Adapter output satisfies enemy-effect comparator profile strict sections and path semantics. | `ENEMY_EFFECT_COMPARATOR_PROFILE_MISMATCH` |
| `E5` | Side-effect zero baseline | Conformance fixtures show zero prohibited side effects under strict guard mode. | `ENEMY_EFFECT_SIDE_EFFECT_VIOLATION` |
| `E6` | Enemy-effect fixture schema compliance | All enemy-effect conformance fixtures pass schema validation before adapter execution. | `ENEMY_EFFECT_FIXTURE_SCHEMA_VIOLATION` |
| `E7` | Numeric-key integrity | Adapter preserves numeric key typing for target/effect keyed maps. | `ENEMY_EFFECT_KEY_TYPE_MISMATCH` |
| `E8` | Timestamp policy compatibility | Adapter output for time-like fields follows comparator timestamp policy (exact by default, explicit opt-in only). | `ENEMY_EFFECT_TIMESTAMP_POLICY_MISMATCH` |
| `E9` | Failure transparency | Invalid enemy-effect fixture/deps fail fast with structured error (no fallback behavior). | `ENEMY_EFFECT_FAIL_FAST_VIOLATION` |
| `E10` | Old/new parity readiness | For enemy-effect conformance fixture set, comparator shows no unapproved mismatches between old and new outputs. | `ENEMY_EFFECT_PARITY_FAILURE` |

Enemy-effect approval rule:

- Enemy-effect lane conformance is approved only if `E1` through `E10` pass for both old and new enemy-effect adapters.

## 7. Cross-lane parity gate

Runtime-extraction justification is blocked unless all gates below pass:

- shared interface gate passed for all adapters (`S1`-`S10`)
- maintenance lane gate passed (`M1`-`M10`)
- enemy-effect lane gate passed (`E1`-`E10`)
- no unresolved high-severity guard violations
- no unresolved comparator mismatches in required strict sections

If any gate fails:

- parity claim is rejected
- extraction justification is rejected
- failing checklist IDs must be fixed and rerun

## 8. Checklist execution procedure

Run order:

1. Validate fixture schema for lane fixture set.
2. Run adapter conformance fixtures per adapter under strict guard mode.
3. Validate normalized result-shape and error taxonomy contract.
4. Compare old-vs-new outputs using lane comparator profile.
5. Record pass/fail for each checklist item.
6. Publish conformance evidence package.

Procedure rules:

- Stop on first critical contract breach (`S*` failures, guard violations, invalid schema).
- Do not bypass failures with adapter-local defaults.
- Do not downgrade strictness without explicit policy change.

## 9. Minimum conformance report format

Conformance report must include:

- adapter pair under test (`old`, `new`, lane)
- fixture set identifier and fixture names
- checklist matrix with item IDs and pass/fail
- side-effect guard summary (`attempted`, `count_by_api`, `first_violation`)
- comparator mismatch summary (if any) with deterministic paths
- explicit final decision:
  - `CONFORMANCE_APPROVED`
  - `CONFORMANCE_REJECTED`

Approval decision rule:

- `CONFORMANCE_APPROVED` requires every required checklist item to pass.

## 10. Stop conditions

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
- `p1_try_dark_launch_dispatch`
- `run_movement_coordinator_tick`
- any direct side-effect owner

No immediate provider extraction is allowed.

No harness runtime code is created by this task.

## 11. Recommended next tasks

1. Docs-only conformance report template for adapter checklist outputs.
2. Docs-only comparator mismatch triage playbook keyed by checklist failure IDs.
3. Docs-only fixture-suite completeness matrix mapping checklist IDs to fixture coverage.
4. Revisit readiness/resource-cache ownership design before any stateful extraction.

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

And side-effect counts (`grep` or `Select-String` equivalent):

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `io.open`

Required confirmations:

- No runtime files were changed.
- No side-effect call sites were moved.
- Only `docs/replay_adapter_conformance_checklist.md` was created for this task.
