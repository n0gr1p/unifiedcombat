# Replay Comparator Mismatch Triage Playbook

## 1. Purpose

This document defines the required triage process for future replay comparator mismatches.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create harness code.

This document defines triage policy only.

Mismatch triage is required before any failed adapter conformance run can be closed.

Conformance reports must preserve first-failure details and cannot mask failures with fallback behavior.

## 2. Triage principles

- Side-effect violations are highest priority among comparator-visible failures.
- Fixture schema failures block adapter execution.
- Adapter result-shape failures block comparator trust.
- Compare first mismatch first.
- Preserve exact mismatch path.
- Do not loosen comparator policy to hide real behavior drift.
- Do not add ignored paths without written rationale.
- Distinguish fixture-authoring error from adapter bug from actual behavior drift.
- Every failed conformance report needs remediation and rerun guidance.
- Diagnostic-only runs cannot approve extraction.

## 3. Triage priority order

1. Fixture schema validation failure
- Why ordered here: invalid input means any downstream result is untrustworthy.
- Can old/new comparison continue: no.
- Required evidence: validation code, failing path, fixture name, schema version.
- Immediate conformance rejection: yes.

2. Adapter setup failure
- Why ordered here: adapter contract broken before lane logic execution.
- Can old/new comparison continue: no.
- Required evidence: structured setup error (`MISSING_DEP`, argument contract), adapter ID.
- Immediate conformance rejection: yes.

3. Side-effect guard violation
- Why ordered here: safety breach and policy violation in parity fixtures.
- Can old/new comparison continue: only diagnostic mode; not for approval.
- Required evidence: violation code, API, call record, `side_effects` mismatch path.
- Immediate conformance rejection: yes for approval runs.

4. Adapter result-shape mismatch
- Why ordered here: comparator cannot reliably compare malformed outputs.
- Can old/new comparison continue: no.
- Required evidence: missing/invalid result field paths, shape contract diff.
- Immediate conformance rejection: yes.

5. Error taxonomy mismatch
- Why ordered here: failure semantics are part of adapter contract.
- Can old/new comparison continue: limited; mismatch must be resolved first.
- Required evidence: old/new `error.code`, `error.path`, `error.message`.
- Immediate conformance rejection: yes.

6. State schema/type mismatch
- Why ordered here: state contract drift often indicates behavior correctness issues.
- Can old/new comparison continue: no for approval unless fixed.
- Required evidence: state path, mismatch reason, lane profile section.
- Immediate conformance rejection: yes.

7. Proposal count/order mismatch
- Why ordered here: ordering/count semantics directly affect action selection readiness.
- Can old/new comparison continue: no for approval unless fixed.
- Required evidence: proposal list lengths, first index mismatch path.
- Immediate conformance rejection: yes.

8. Proposal field mismatch
- Why ordered here: content drift may reflect provider/selection behavior drift.
- Can old/new comparison continue: no for approval unless fixed.
- Required evidence: proposal field path and expected/actual values.
- Immediate conformance rejection: yes.

9. Timestamp/deadline mismatch
- Why ordered here: may be either policy misuse or real behavior drift.
- Can old/new comparison continue: yes for diagnosis, no for approval until resolved.
- Required evidence: path, comparison mode, epsilon policy, fixture.now baseline.
- Immediate conformance rejection: yes if unresolved.

10. Debug/trace mismatch
- Why ordered here: usually lower correctness risk, but still contract-relevant when required.
- Can old/new comparison continue: yes for diagnosis; approval depends on profile strictness.
- Required evidence: trace/debug path, profile requirement, deterministic order proof.
- Immediate conformance rejection: conditional (yes if required by profile/report gates).

## 4. Mismatch reason taxonomy

| Comparator reason | Meaning | Likely source | Checklist ID impact | First remediation step | Requires fixture update? | Requires adapter update? | Requires comparator policy update? | Rerun required? |
|---|---|---|---|---|---|---|---|---|
| `missing_key` | Expected key absent in actual | adapter output omission or bad fixture expectation | S5, M2/M4 or E2/E4, M10/E10 | confirm contract-required field and restore it | sometimes | often | no | yes |
| `extra_key` | Actual has unexpected key | over-broad adapter snapshot or undocumented field | S5, M4/E4 | remove/contain non-contract field | sometimes | often | no | yes |
| `type_mismatch` | Same path, wrong value type | key coercion/stringification, wrong serializer | S5, M8/E7, M7 | fix type preservation at source | sometimes | often | no | yes |
| `value_mismatch` | Same type, different value | behavior drift or wrong fixture expected value | M1-M4/M10, E1-E4/E10, S9 | classify fixture error vs adapter behavior drift | sometimes | often | no | yes |
| `order_mismatch` | Sequence order differs | nondeterministic traversal or ranking leak | M3/M10, E3/E10, S8 | enforce deterministic ordered-list handling | rarely | often | maybe (if profile ambiguity) | yes |
| `nil_vs_false` | semantic nil/false collision | defaulting logic or normalization bug | M7, S5, S6 | remove coercion and preserve semantic class | sometimes | often | no | yes |
| `numeric_tolerance_exceeded` | numeric delta beyond policy | wrong timestamp path handling or true drift | E8, M4/E4, S8 | verify exact-mode requirement then correct source | sometimes | often | maybe (if policy change needed) | yes |
| `side_effect_violation` | prohibited side effect attempted | adapter lane escaped isolation | S7, M5/E5, S9 | stop side effect path; keep guard strict | no | yes | no | yes |
| `error_mismatch` | old/new structured error disagreement | inconsistent error mapping | S6, M9/E9, M10/E10 | align error code taxonomy and path detail | sometimes | often | no | yes |
| `invalid_result_shape` | normalized result contract broken | adapter contract regression | S5 | restore required result schema exactly | no | yes | no | yes |
| `fixture_validation_failure` | fixture failed schema validation | authoring error or schema mismatch | M6/E6, S2 | fix fixture schema first | yes | sometimes | no | yes |
| `unknown_field` | field not in schema/profile allowlist | fixture authoring drift | M6/E6 | remove or formally allow with policy rationale | yes | no | sometimes | yes |
| `invalid_key_type` | numeric/string key type contract violated | fixture authoring or adapter key coercion | M8/E7, M6/E6 | identify layer producing wrong key type | sometimes | often | no | yes |
| `nondeterministic_output` | repeated runs differ | live time/source leakage or state leak | S8, M10/E10 | isolate nondeterministic source and freeze inputs | no | yes | no | yes |

## 5. Checklist ID mapping

### Shared IDs (`S1`-`S10`)

- `S1` Required entrypoint exists
- Common symptoms: adapter `run`/lane entrypoint missing or wrong signature.
- Required evidence: adapter metadata, setup failure record, module reference.
- Pass/fail outcome: fail if any required entrypoint/signature is missing.
- Likely remediation: restore exact entrypoint contract.

- `S2` Required argument contract
- Common symptoms: nil args accepted silently, malformed `options` ignored.
- Required evidence: failing fixture/setup path and structured error.
- Pass/fail outcome: fail on any non-structured argument handling.
- Likely remediation: enforce fail-fast argument validation.

- `S3` Dependency contract
- Common symptoms: missing dep not reported as `MISSING_DEP`, fallback to live state.
- Required evidence: dep table, failure code, call trace.
- Pass/fail outcome: fail when required dep missing or fallback used.
- Likely remediation: require dep explicitly and error deterministically.

- `S4` Fixture immutability
- Common symptoms: `fixture.state_before` mutated, shared traces between runs.
- Required evidence: before/after fixture hash or deep-diff.
- Pass/fail outcome: fail on any fixture mutation.
- Likely remediation: deep-copy fixture-owned tables and isolate state.

- `S5` Result-shape contract
- Common symptoms: missing `side_effects`, wrong field types, malformed `error`.
- Required evidence: result schema diff path.
- Pass/fail outcome: fail if schema differs from interface spec.
- Likely remediation: normalize output exactly to contract.

- `S6` Error taxonomy contract
- Common symptoms: runtime exception string instead of structured `error.code`.
- Required evidence: old/new error payload comparison.
- Pass/fail outcome: fail if taxonomy or structure mismatches.
- Likely remediation: map failures to approved codes with path/detail.

- `S7` Side-effect guard contract
- Common symptoms: non-zero side-effect counters in parity fixtures.
- Required evidence: `first_violation`, per-API count, call record.
- Pass/fail outcome: fail on unexpected violation.
- Likely remediation: block call path and keep adapter lane-safe.

- `S8` Determinism contract
- Common symptoms: repeated same fixture gives different outputs/order.
- Required evidence: repeated run diffs and seed/time trace.
- Pass/fail outcome: fail on instability.
- Likely remediation: deterministic ordering/time and run-local state only.

- `S9` Lane isolation contract
- Common symptoms: maintenance path calls enemy-effect provider path, ranking/dispatch invoked.
- Required evidence: call trace showing forbidden lane/path invocation.
- Pass/fail outcome: fail on cross-lane or orchestration leakage.
- Likely remediation: strict lane adapter boundary and stubbed dependencies.

- `S10` Version metadata contract
- Common symptoms: missing/incorrect `interface_version` or lane metadata.
- Required evidence: adapter metadata section.
- Pass/fail outcome: fail on metadata mismatch.
- Likely remediation: align adapter metadata to interface spec.

### Maintenance IDs (`M1`-`M10`)

- `M1`/`M2`/`M3`/`M4`
- Common symptoms: missing maintenance context/state slices, proposal capture issues, comparator profile mismatch.
- Required evidence: maintenance fixture output sections and mismatch paths.
- Pass/fail outcome: fail if any required maintenance section drifts.
- Likely remediation: restore maintenance lane boundaries and required state/proposal capture.

- `M5`
- Common symptoms: side-effect counters non-zero.
- Required evidence: guard summary with violation code/path.
- Pass/fail outcome: fail.
- Likely remediation: eliminate side-effect attempts from maintenance adapter.

- `M6`
- Common symptoms: maintenance fixtures fail schema before execution.
- Required evidence: validation code/path.
- Pass/fail outcome: fail.
- Likely remediation: fix fixture authoring/schema compliance.

- `M7`/`M8`
- Common symptoms: nil/false collisions, numeric key stringification.
- Required evidence: precise path and type/value diff.
- Pass/fail outcome: fail.
- Likely remediation: preserve semantics and key types end-to-end.

- `M9`
- Common symptoms: invalid fixture/dep failure not transparent.
- Required evidence: error payload shape and code.
- Pass/fail outcome: fail.
- Likely remediation: fail-fast structured error handling.

- `M10`
- Common symptoms: unresolved old/new mismatches in required sections.
- Required evidence: comparator summary and unresolved mismatch inventory.
- Pass/fail outcome: fail until cleared.
- Likely remediation: fix root mismatch class and rerun.

### Enemy-effect IDs (`E1`-`E10`)

- `E1`/`E2`/`E3`/`E4`
- Common symptoms: missing enemy-effect context/state slices, proposal capture drift, comparator profile mismatch.
- Required evidence: enemy-effect fixture output sections and mismatch paths.
- Pass/fail outcome: fail if any required enemy-effect section drifts.
- Likely remediation: restore enemy-effect lane boundaries/state/proposal capture.

- `E5`
- Common symptoms: side-effect counters non-zero.
- Required evidence: guard violation record and count-by-api.
- Pass/fail outcome: fail.
- Likely remediation: remove direct side-effect paths.

- `E6`
- Common symptoms: enemy-effect fixture schema failures.
- Required evidence: validation code/path.
- Pass/fail outcome: fail.
- Likely remediation: fix fixture schema/authoring.

- `E7`
- Common symptoms: target/effect keys stringified.
- Required evidence: key-type mismatch path.
- Pass/fail outcome: fail.
- Likely remediation: preserve numeric keys in map creation and normalization.

- `E8`
- Common symptoms: `seen_at`/`expires_at`/attempt cooldown mismatch beyond policy.
- Required evidence: timestamp path, baseline, comparator mode.
- Pass/fail outcome: fail unless explicitly policy-compliant.
- Likely remediation: correct time source and timestamp semantics.

- `E9`
- Common symptoms: invalid fixture/deps not surfaced as structured failure.
- Required evidence: structured error diff.
- Pass/fail outcome: fail.
- Likely remediation: align failure mapping to contract.

- `E10`
- Common symptoms: unresolved parity mismatches.
- Required evidence: mismatch inventory and unresolved reasons.
- Pass/fail outcome: fail until resolved.
- Likely remediation: fix source mismatch classes and rerun.

## 6. Fixture schema failure triage

Fixture schema failures are fixed in fixture authoring, not adapter logic, unless adapter incorrectly rejected valid schema.

| Failure type | Example path | Expected validation code | Adapter execution allowed? | Remediation | Conformance report update required |
|---|---|---|---|---|---|
| missing required field | `schema_version` | `MISSING_REQUIRED_FIELD` | no | add required field/value | yes |
| unsupported `schema_version` | `schema_version` | `INVALID_SCHEMA_VERSION` | no | use supported schema version | yes |
| wrong lane | `lane` | `INVALID_FIELD_TYPE` or `LANE_PROFILE_MISMATCH` | no | set lane to `maintenance` or `enemy_effect` correctly | yes |
| unknown field | `unexpected_field` | `UNKNOWN_FIELD` | no | remove field or update schema policy with rationale | yes |
| wrong type | `expected.side_effects.attempted` | `INVALID_FIELD_TYPE` | no | fix field type exactly | yes |
| invalid numeric key type | `state_before.enemy_effect_state["17793029"]` | `INVALID_KEY_TYPE` | no | convert key to numeric and preserve through pipeline | yes |
| invalid side-effect expectation | `expected.side_effects.attempted` | `INVALID_SIDE_EFFECT_EXPECTATION` | no | restore zero-side-effect default for parity fixtures | yes |
| invalid proposal shape | `expected.proposals` | `INVALID_FIELD_TYPE` | no | provide ordered list-like proposal shape | yes |
| missing required stub | `stubs.readiness` or lane-required stub path | `MISSING_REQUIRED_FIELD` or adapter `MISSING_DEP` | no | provide required stub fixture data | yes |

## 7. Side-effect violation triage

Maintenance/enemy-effect provider-state replay fixtures require zero side effects.

Any unexpected side effect rejects conformance.

Diagnostic-only side-effect tests cannot approve runtime extraction.

| Violation type | Violation code | Comparator mismatch path | Expected fixture outcome | Required remediation | Can conformance approve with this violation? |
|---|---|---|---|---|---|
| command execution attempt | `COMMAND_EXECUTION_ATTEMPT` | `side_effects.count_by_api["windower.send_command"]` | fail | remove command-emission path from adapter lane | no |
| movement attempt | `MOVEMENT_EXECUTION_ATTEMPT` | `side_effects.count_by_api["windower.ffxi.run"]` | fail | remove movement execution from replay path | no |
| facing attempt | `FACING_EXECUTION_ATTEMPT` | `side_effects.count_by_api["windower.ffxi.turn"]` | fail | remove facing calls from replay path | no |
| target selection attempt | `TARGET_SELECTION_ATTEMPT` | `side_effects.count_by_api["uc_settarget.select_by_id"]` | fail | replace with proposal/state-only behavior | no |
| IPC send attempt | `IPC_SEND_ATTEMPT` | `side_effects.count_by_api["windower.send_ipc_message"]` | fail | block IPC send path in adapter | no |
| event registration attempt | `EVENT_REGISTRATION_ATTEMPT` | `side_effects.first_violation.violation_code` | fail | avoid requiring modules that register events | no |
| file write attempt | `FILE_WRITE_ATTEMPT` | `side_effects.count_by_api["io.open.write_or_append"]` | fail | remove write/append IO path | no |
| live Windower read attempt | `LIVE_WINDOWER_READ_ATTEMPT` | `side_effects.first_violation.violation_code` | fail | route reads through deterministic stubs only | no |
| direct `unified_scheduler` require attempt | `LIVE_SCHEDULER_REQUIRE_ATTEMPT` | `side_effects.first_violation.violation_code` | fail | remove direct runtime require and use safe adapter boundary | no |

## 8. State mismatch triage

| Failure pattern | Likely source | Checklist impact | Remediation | Rerun requirements |
|---|---|---|---|---|
| missing state table | adapter omitted required lane slice | M2/E2, M4/E4, S5 | restore required state slice capture | rerun full lane fixture set |
| extra state table | over-broad snapshot ownership | M4/E4, S5, S9 | constrain snapshot to contract-relevant lane slices | rerun affected fixtures + parity set |
| numeric key vs string key mismatch | key coercion during map build/normalize | M8/E7, M4/E4 | preserve numeric keys end-to-end | rerun key-sensitive fixtures |
| nil vs false mismatch | defaulting/normalization coercion | M7, S5 | remove coercion; preserve semantic states | rerun semantic fixtures |
| timestamp mismatch | bad time source or normalization mode | E8, M4/E4, S8 | enforce fixture.now/deps.now_s and policy mode | rerun timestamp fixtures multiple times |
| mutation scope too broad | adapter mutates unrelated lane state | S9, M2/E2 | isolate lane-local mutations | rerun lane and cross-lane fixtures |
| old/new lazy initialization differences | inconsistent table initialization | M2/E2, M10/E10 | align initialization contract | rerun full parity fixture set |
| unexpected state retained | missing clear/prune/sweep semantics | E2/E4/E10, M2/M10 | fix clear/prune logic in adapter behavior | rerun retention/cleanup fixtures |
| expected state missing after clear/prune/sweep | over-aggressive mutation | E2/E4/E10 | constrain clear/prune target scope | rerun target-specific fixtures |

Maintenance examples:

- `maintenance_state` missing key: likely missing maintenance state ownership path; impacts `M2`.
- `recent_gain` timestamp mismatch: likely non-deterministic time source; impacts `M2`, `M4`, `M10`.
- `family_tokens` key type mismatch: likely stringification; impacts `M8`.
- `maintenance_next_at` cadence mismatch: likely cadence gate drift; impacts `M1`, `M4`, `M10`.

Enemy-effect examples:

- `effectiveTargets` target key stringified: impacts `E7`, `E4`.
- effect row source mismatch: impacts `E1`, `E2`, `E4`, `E10`.
- `expires_at` mismatch: impacts `E8`, `E4`, `E10`.
- `enemy_dispel_attempt` key/timestamp mismatch: impacts `E2`, `E7`, `E8`, `E10`.
- target clear removed unrelated target: impacts `E2`, `E4`, `E10`.

## 9. Proposal mismatch triage

| Failure pattern | Likely source | Checklist impact | Remediation | Rerun requirements |
|---|---|---|---|---|
| proposal count mismatch | lane gating drift or suppression drift | M3/M10 or E3/E10, M4/E4 | align proposal emission boundaries | rerun fixture + parity set |
| proposal order mismatch | non-deterministic traversal or ranking leakage | M3/M10 or E3/E10, S8 | enforce deterministic source-order capture | rerun multi-proposal fixtures repeatedly |
| `action_name` mismatch | wrong action selection path | M1/M3/M10 or E1/E3/E10 | fix action selection logic in adapter scope | rerun action-selection fixtures |
| `target_id`/`target_name` mismatch | target resolution drift or key coercion | E1/E3/E7/E10, M3/M10 | fix target binding and key typing | rerun target fixtures |
| provider/source mismatch | wrong lane provider context | M1/M4/M10 or E1/E4/E10, S9 | restore lane-specific source mapping | rerun lane-specific suites |
| `priority_band`/`urgency` mismatch | scoring metadata drift | M4/M10 or E4/E8/E10 | restore deterministic metadata computation | rerun scoring-sensitive fixtures |
| `reason_code`/`detail` mismatch | rejection/diagnostic contract drift | M4/M9 or E4/E9, S6 | align detail/error shaping | rerun reject-path fixtures |
| `duplicate_suppression_key` mismatch | key builder drift | M3/M4/M10 or E3/E4/E10 | restore key format stability | rerun duplicate-suppression fixtures |
| `recast_key` mismatch | recast identity drift | M4/M10 or E4/E10 | align recast-key builder contract | rerun recast fixtures |
| `lock_class` mismatch | lock classification drift | M4/M10 or E4/E10 | restore lock mapping contract | rerun lock-class fixtures |
| `expected_ack`/`expected_effect` mismatch | effect expectation drift | E4/E10, M4/M10 | align expectation metadata generation | rerun effect/ack fixtures |
| `expires_at`/`commit_deadline` mismatch | timestamp policy misuse or drift | E8/E10, M4/M10 | enforce exact/time policy rules | rerun timestamp fixtures |
| `legacy_command` mismatch | command text normalization drift | M4/M10 or E4/E10 | align command builder metadata semantics | rerun command-metadata fixtures |

Maintenance examples:

- BRD/COR/GEO proposal emitted when cadence not due: likely cadence-gate drift; impacts `M1`, `M3`, `M10`.
- missing proposal when buff expired: likely maintenance context/state drift; impacts `M1`, `M2`, `M10`.
- city-zone block failed: likely maintenance context gating mismatch; impacts `M1`, `M4`, `M10`.
- `recent_gain` duplicate suppression failed: impacts `M2`, `M3`, `M10`.

Enemy-effect examples:

- proposal emitted for invalid claim: impacts `E1`, `E3`, `E10`.
- proposal missing for valid dispellable buff: impacts `E1`, `E2`, `E10`.
- wrong Dispel/Magic Finale selection: impacts `E1`, `E3`, `E10`.
- attempt throttle ignored: impacts `E2`, `E3`, `E10`.
- wrong highest-priority target/effect selected: impacts `E3`, `E4`, `E10`.

## 10. Error/failure mismatch triage

Required normalized error shape:

```lua
{
  code = "MISSING_DEP" | "INVALID_FIXTURE" | "GUARD_VIOLATION" | "UNSUPPORTED_LANE" | "ADAPTER_RUNTIME_ERROR",
  message = "human-readable summary",
  lane = "maintenance" or "enemy_effect",
  fixture_name = "string",
  path = "optional.precise.path",
  detail = {},
}
```

| Failure pattern | Checklist impact | Remediation | Report evidence required |
|---|---|---|---|
| old returns `ok=false` but new returns `ok=true` | S6, M10/E10 | align error/ok semantics for same fixture conditions | old/new result snapshots, error blocks |
| old/new error code mismatch | S6, M9/E9, M10/E10 | map both to approved taxonomy with same trigger | error code/path diff table |
| missing dependency not reported as `MISSING_DEP` | S3, S6, M9/E9 | enforce missing dep detection and code mapping | dep inventory + error payload |
| invalid fixture not reported as validation error | M6/E6, S2, M9/E9 | fail at schema layer before adapter execution | validation failure record |
| guard violation swallowed or reclassified | S7, S6, M5/E5 | preserve guard violation code/path and fail status | guard record + comparator side_effects section |
| runtime exception instead of structured error | S6, M9/E9 | catch and normalize as `ADAPTER_RUNTIME_ERROR` with context | exception trace + normalized error |

## 11. Timestamp and numeric mismatch triage

- Default comparison is exact.
- Timestamp normalization is allowed only where comparator policy explicitly permits it.
- Timestamp normalization is not allowed for fields not explicitly policy-scoped.
- Determine float noise vs behavior drift by repeated deterministic reruns using identical fixture.now/deps.now_s and checking absolute delta against allowed epsilon.
- Paths requiring extra caution: `seen_at`, `expires_at`, `commit_deadline`, `maintenance_next_at`, `enemy_dispel_attempts` cooldown timestamps, `urgency`, `priority_band`.

Examples:

- `seen_at` mismatch: check fixture baseline and policy mode; impacts `E8`.
- `expires_at` mismatch: check timestamp derivation and adapter time source; impacts `E8`, `E10`.
- `commit_deadline` mismatch: verify deterministic deadline computation; impacts `E8`/`M4`.
- `maintenance_next_at` mismatch: verify maintenance cadence semantics; impacts `M1`, `M10`.
- `urgency` mismatch: verify numeric calculation path and tolerance policy.
- `priority_band` mismatch: exact-only field; any mismatch is behavior drift.

Policy hard rule:

- IDs/counts/priorities must not use tolerance.
- Tolerance policy changes require comparator policy update and reviewer approval.

## 12. Determinism failure triage

| Failure pattern | Likely cause | Checklist impact | Remediation | Rerun requirements |
|---|---|---|---|---|
| repeated runs produce different outputs | shared mutable state or live reads | S8, M10/E10 | isolate state per run and freeze inputs | rerun same fixture >=3 times |
| map traversal order changed proposal order | unordered iteration in ordered-list field | S8, M3/E3 | canonicalize traversal before capture | rerun multi-item proposal fixtures |
| timestamps use live clock | `os.time`/live now usage | S8, E8, M10/E10 | route all time through fixture.now/deps.now_s | rerun timestamp fixtures repeatedly |
| random/uncontrolled data source | non-stubbed randomness/live resource state | S8, S3 | stub/seed deterministic source | rerun with captured traces |
| stub call order differs unexpectedly | hidden branch drift | S8, M1/E1 | align branch conditions and deterministic call flow | rerun with trace comparison |
| state leakage between runs | global/shared tables reused | S4, S8, M10/E10 | deep-copy/reset all mutable run state | rerun full fixture batch twice |

## 13. Fixture immutability failure triage

| Failure pattern | Likely cause | Checklist impact | Remediation | Required evidence after fix |
|---|---|---|---|---|
| `fixture.state_before` mutated | adapter writes into fixture-owned table | S4, M2/E2 | deep-copy before mutation | fixture before/after diff proving no mutation |
| `fixture.expected` used to drive execution | compare-only data leaked into logic | S4, S9, M9/E9 | remove execution dependency on expected block | call trace + code-path evidence from run logs |
| old adapter mutates fixture before new adapter run | shared fixture references | S4, S8, M10/E10 | isolate fixture copies per adapter run | old/new isolated input hashes |
| stub traces shared between runs | trace collector reused | S4, S8 | allocate per-run trace collector | per-run trace identity evidence |
| side-effect guard counts shared between runs | guard state reused across fixtures | S4, S8, S7 | reset guard counters each run | per-run guard summary reset evidence |

## 14. Lane isolation failure triage

| Failure pattern | Checklist impact | Stop-condition relation | Remediation |
|---|---|---|---|
| maintenance adapter calls enemy-effect path | S9, M1/M4 | violates lane-scoped replay boundary | isolate maintenance adapter to maintenance-only logic |
| enemy-effect adapter calls maintenance path | S9, E1/E4 | violates lane-scoped replay boundary | isolate enemy-effect adapter to enemy-effect-only logic |
| adapter calls `p1_collect_proposals` | S9, S7, M3/E3 | crosses forbidden orchestrator boundary | remove orchestrator call from adapter path |
| adapter calls `p1_run_dry` | S9, S7 | crosses forbidden dry-run/dispatch boundary | replace with lane-local adapter execution only |
| adapter calls ranking/scoring/dispatch | S9, M4/E4 | forbidden ownership zone | stop at proposal/state capture boundary |
| adapter invokes real `action_ready`/`spell_ready`/`ja_ready` instead of stubs | S3, S9, M4/E4 | forbidden live readiness dependency | inject deterministic readiness stubs only |

## 15. Conformance report update requirements

After any mismatch, the following fields must be filled in `docs/replay_adapter_conformance_report_template.md`:

- checklist ID
- failure code
- fixture name
- adapter ID
- lane
- mismatch path
- comparator reason
- expected value
- actual value
- root cause hypothesis
- required remediation
- rerun required
- final decision

Policy rules:

- `CONFORMANCE_REJECTED` is mandatory until rerun passes.
- Reports must not claim runtime extraction eligibility with unresolved mismatches.

## 16. Triage examples

1. Missing dependency failure
- fixture: `maint_missing_readiness_stub`
- mismatch path: `error.code`
- comparator reason: `error_mismatch`
- checklist IDs impacted: `S3`, `S6`, `M9`
- likely root cause: `deps.readiness` missing and adapter returned generic runtime error.
- remediation: enforce required dep check and emit `MISSING_DEP` with precise path.
- final conformance decision: `CONFORMANCE_REJECTED`.

2. Fixture schema invalid key type
- fixture: `enemy_key_stringified`
- mismatch path: `state_before.enemy_effect_state["17793029"]`
- comparator reason: `fixture_validation_failure` / `invalid_key_type`
- checklist IDs impacted: `E6`, `E7`
- likely root cause: fixture authoring stringified numeric target keys.
- remediation: fix fixture key types to numeric and revalidate schema.
- final conformance decision: `CONFORMANCE_REJECTED`.

3. Side-effect violation: `windower.send_command` attempted
- fixture: `enemy_dispel_attempt`
- mismatch path: `side_effects.count_by_api["windower.send_command"]`
- comparator reason: `side_effect_violation`
- checklist IDs impacted: `S7`, `E5`
- likely root cause: adapter leaked command-dispatch path.
- remediation: remove command execution path and keep proposal-only behavior.
- final conformance decision: `CONFORMANCE_REJECTED`.

4. Maintenance state timestamp mismatch
- fixture: `maint_recent_gain_rollforward`
- mismatch path: `after.state.recent_gain["Player:33"].ts`
- comparator reason: `numeric_tolerance_exceeded`
- checklist IDs impacted: `M2`, `M4`, `M10`
- likely root cause: live time source used instead of fixture.now.
- remediation: route timestamp generation to `deps.now_s`/fixture baseline only.
- final conformance decision: `CONFORMANCE_REJECTED`.

5. Maintenance proposal order mismatch
- fixture: `maint_multi_due_actions`
- mismatch path: `proposals_pre_rank[1].action_name`
- comparator reason: `order_mismatch`
- checklist IDs impacted: `M3`, `M10`, `S8`
- likely root cause: unordered map iteration controls proposal emission order.
- remediation: preserve deterministic source-order proposal capture.
- final conformance decision: `CONFORMANCE_REJECTED`.

6. Enemy-effect target key type mismatch
- fixture: `enemy_gain_dispellable`
- mismatch path: `after.state.enemy_effect_state["17793029"]`
- comparator reason: `type_mismatch`
- checklist IDs impacted: `E7`, `E4`, `E10`
- likely root cause: adapter normalize step stringified target IDs.
- remediation: preserve numeric keys in normalization and snapshots.
- final conformance decision: `CONFORMANCE_REJECTED`.

7. Enemy-effect proposal missing due to claim handling
- fixture: `enemy_valid_claim_dispellable`
- mismatch path: `proposals_pre_rank[1]` (missing_key)
- comparator reason: `missing_key`
- checklist IDs impacted: `E1`, `E3`, `E10`
- likely root cause: claim-state adapter context incorrectly marked target invalid.
- remediation: fix claim-state context mapping for enemy-effect lane.
- final conformance decision: `CONFORMANCE_REJECTED`.

8. Nondeterministic output from live `now_s`
- fixture: `enemy_attempt_cooldown_repeat`
- mismatch path: `after.state.enemy_dispel_attempts["Dispel:17793029:33"]`
- comparator reason: `nondeterministic_output`
- checklist IDs impacted: `S8`, `E8`, `E10`
- likely root cause: adapter uses live clock in one branch.
- remediation: enforce deterministic injected `now_s` in all branches.
- final conformance decision: `CONFORMANCE_REJECTED`.

## 17. Stop conditions

This playbook does not permit moving:

- `p1_collect_maintenance`
- `p1_collect_enemy_buff_removal`
- `ingest_enemy_effects_from_raw_action_028`
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

## 18. Recommended next tasks

1. Docs-only fixture-suite completeness matrix mapping checklist IDs to fixture coverage.
2. Docs-only readiness/resource-cache ownership design.
3. Docs-only loader-contract fixture profile extension policy.
4. Create non-runtime fixture validator skeleton only after policy docs are approved.
5. Create non-runtime comparator skeleton only after policy docs are approved.

Do not perform immediate provider extraction.

## 19. Validation snapshot

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

Confirm:

- no runtime files were changed
- no side-effect call sites were moved
- only `docs/replay_comparator_mismatch_triage_playbook.md` was created
