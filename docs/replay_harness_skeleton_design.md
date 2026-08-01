# Replay Harness Skeleton Design

## 1. Purpose

This document designs a non-runtime replay harness skeleton for future parity validation.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document is a prerequisite before creating actual replay harness files.

The harness must never emit commands, movement, facing, target selection, IPC sends, or file writes during replay.

The first target fixture suites are maintenance and enemy-effect.

## 2. Harness design goals

- Compare old implementation vs new implementation.
- Run deterministic fixture inputs.
- Compare structural outputs, not just strings.
- Freeze time.
- Stub Windower reads.
- Stub readiness decisions.
- Stub mob/claim/catalog lookups.
- Capture proposal lists before ranking.
- Capture before/after state.
- Detect side-effect attempts.
- Report first mismatch with a precise path.
- Support maintenance and enemy-effect suites without touching live runtime paths.

## 3. Non-goals

- Running inside live Windower.
- Emitting commands.
- Moving provider functions.
- Moving state mutators.
- Replacing current scheduler flow.
- Changing `action_ready`/`spell_ready`/`ja_ready`.
- Changing `p1_collect_maintenance`.
- Changing `p1_collect_enemy_buff_removal`.
- Changing `ingest_enemy_effects_from_raw_action_028`.
- Testing ranking/dispatch as part of first harness scope.
- Modifying runtime modules.

## 4. Proposed directory and file layout

Design-only target layout (do not create yet):

```text
tests/
  replay/
    fixtures/
      maintenance/
      enemy_effect/
    harness/
      replay_runner.lua
      structural_compare.lua
      stubs.lua
      side_effect_guard.lua
      state_snapshot.lua
      fixture_loader.lua
    README.md
```

### `tests/replay/harness/replay_runner.lua`

- Responsibility:
  - Orchestrate one fixture execution for `old` and `new` implementations.
  - Apply deterministic stubs and side-effect guards.
  - Capture `before`/`after` snapshots and pre-rank proposals.
- Inputs:
  - fixture table
  - runner configuration (`lane`, `impl_old`, `impl_new`)
- Outputs:
  - structured run result:
    - `old_result`
    - `new_result`
    - `compare_result`
- Isolation rationale:
  - No direct Windower runtime dependencies.
  - All external calls routed through injected stubs.
- Allowed requires:
  - Yes: extracted pure/helper modules and harness modules.
- `require('unified_scheduler')`:
  - Unsafe by default. Module load executes startup logic (for example enemy-dispel/catalg loader path with IO and fatal behavior), so do not require directly unless a future safe non-runtime entrypoint is explicitly added.

### `tests/replay/harness/structural_compare.lua`

- Responsibility:
  - Deep structural comparator for state/proposal/debug outputs.
  - Deterministic diff path reporting.
- Inputs:
  - expected value tree
  - actual value tree
  - comparison options (numeric normalization, key-type strictness, ordering rules)
- Outputs:
  - `{ ok = bool, mismatch_path = string, expected = any, actual = any, reason = string }`
- Isolation rationale:
  - Pure comparison module with no runtime dependencies.
- Allowed requires:
  - Yes: Lua base libs only.
- `require('unified_scheduler')`:
  - Not allowed.

### `tests/replay/harness/stubs.lua`

- Responsibility:
  - Build deterministic replacements for Windower/resource/readiness/time lookup points used by lane under test.
- Inputs:
  - fixture `stubs` block
  - fixture snapshots (`player_context`, `party_snapshot`, `mob_snapshot`, `claim_state`)
- Outputs:
  - injected stub set and call-trace table
- Isolation rationale:
  - No live Windower lookups; all values come from fixture.
- Allowed requires:
  - Yes: harness helpers; optional extracted helper modules.
- `require('unified_scheduler')`:
  - Not allowed.

### `tests/replay/harness/side_effect_guard.lua`

- Responsibility:
  - Trap and count side-effect attempts.
  - Fail fixture if forbidden side-effect API is called.
- Inputs:
  - function registry/object to wrap
  - guard policy
- Outputs:
  - `guard_result` with call counts and first violation detail
- Isolation rationale:
  - Hard-blocks behavior that would affect runtime.
- Allowed requires:
  - Yes: none beyond base/harness modules.
- `require('unified_scheduler')`:
  - Not allowed.

### `tests/replay/harness/state_snapshot.lua`

- Responsibility:
  - Canonical copy and normalization of lane-relevant state for before/after compare.
- Inputs:
  - state root tables from runner context
  - lane selector
- Outputs:
  - normalized snapshot table
- Isolation rationale:
  - Pure state-copy/normalize path.
- Allowed requires:
  - Yes: harness compare helpers.
- `require('unified_scheduler')`:
  - Not allowed.

### `tests/replay/harness/fixture_loader.lua`

- Responsibility:
  - Load fixture files/tables and validate schema contract version.
- Inputs:
  - fixture path(s)
  - lane filter
- Outputs:
  - validated fixture table array
- Isolation rationale:
  - No runtime mutation; strict schema validation only.
- Allowed requires:
  - Yes: base Lua + harness schema validator.
- `require('unified_scheduler')`:
  - Not allowed.

### `tests/replay/README.md`

- Responsibility:
  - Document fixture format, runner contract, failure triage flow, and side-effect safety guarantees.
- Inputs:
  - n/a
- Outputs:
  - documentation only
- Isolation rationale:
  - clarifies non-runtime usage and guardrails.
- Allowed requires:
  - n/a
- `require('unified_scheduler')`:
  - n/a

## 5. Fixture format contract

Shared fixture table shape:

```lua
{
  fixture_name = "string",
  lane = "maintenance" or "enemy_effect",
  description = "string",
  now = 12345.678,

  settings = {},
  player_context = {},
  party_snapshot = {},
  mob_snapshot = {},
  claim_state = {},

  inputs = {
    raw_packet = nil,
    parsed_packet = nil,
    parsed_status_snapshot = nil,
    raw_action = nil,
    parsed_action = nil,
  },

  state_before = {
    scheduler = {},
    maintenance_state = {},
    recent_gain = {},
    attempted = {},
    family_tokens = {},
    enemy_effect_state = {},
    enemy_dispel_attempts = {},
  },

  stubs = {
    readiness = {},
    windower = {},
    resources = {},
    catalog = {},
    now_s = nil,
  },

  expected = {
    state_after = {},
    proposals = {},
    debug_globals = {},
    side_effects = {},
    noop_or_reject_reason = nil,
  },
}
```

Contract notes:

- `lane` determines which state sections and comparisons are mandatory.
- `now` must always be provided and injected into all time calls.
- `expected.side_effects` must default to zero calls for all blocked APIs.
- Fixture schema versioning should be explicit (`schema_version`) once files are created.

## 6. Runner model (old vs new)

Proposed runner interface:

- `run_fixture(fixture, impl_old, impl_new, options)`
- `impl_old` and `impl_new` are pure adapter objects exposing only lane-under-test entrypoints.
- Adapter contract should avoid calling full scheduler tick flow.

Adapter example responsibilities:

- Maintenance lane:
  - run maintenance collector path against isolated state/context and return proposals + state delta.
- Enemy-effect lane:
  - run ingestion/provider path under fixture-supplied parsed/raw actions and return proposals + state delta.

Safety rule:

- Runner must reject adapters that call forbidden APIs or attempt to load full runtime scheduler module directly.

## 7. Structural comparator contract

Comparator must support:

- strict table key comparison
- key-type strictness (`"123"` vs `123`)
- ordered list comparison where ordering is semantic (proposal lists)
- unordered map comparison where ordering is not semantic
- numeric tolerance mode only when explicitly configured
- nil vs false vs empty string differentiation
- first mismatch short-circuit with precise path

Mismatch output shape:

```lua
{
  ok = false,
  fixture_name = "enemy_effect_case_07",
  lane = "enemy_effect",
  section = "state_after.enemy_effect_state",
  mismatch_path = "targets[17793029][33].source",
  expected = "raw_028_spell_msg_2",
  actual = "raw_028_spell_msg_230",
  reason = "value_mismatch",
}
```

## 8. Deterministic stubs contract

Required deterministic stubs:

- time source (`now_s`) from fixture
- player snapshot lookup
- party snapshot lookup
- mob lookup by id/index
- claim set lookup
- resource lookup (buff/spell/JA metadata)
- catalog lookup for TargetBar-like tables
- readiness results (`Magic Finale`, `Dispel`, maintenance actions)

Stub behavior rules:

- no fallback to live Windower
- missing stub values must fail fast with clear fixture path
- all stub calls logged for mismatch debugging

## 9. Side-effect guard contract

Guarded APIs to block in replay:

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `windower.send_ipc_message`
- any file write APIs (`io.open` write/append modes)

Guard response:

- immediately record violation
- mark fixture failed
- continue only if configured in diagnostics mode

Violation record example:

```lua
{
  api = "windower.send_command",
  args = { "input /ma \"Dispel\" <t>" },
  fixture_name = "enemy_effect_attempt_allowed",
  phase = "new_runner",
}
```

## 10. Snapshot capture model

Before snapshot should capture at minimum:

- lane-scoped state from fixture `state_before`
- debug global baseline (only keys under contract)

After snapshot should capture at minimum:

- mutated lane-scoped state
- proposals before ranking
- debug globals under expected contract
- side-effect guard call counts

Normalization rules:

- deterministic key ordering for serialization-only reporting
- preserve original types for compare engine
- include only lane-relevant slices to avoid false mismatches from unrelated state

## 11. Execution flow

1. Load fixture and validate schema.
2. Build deterministic stubs and side-effect guards.
3. Create isolated state sandbox from `state_before`.
4. Run old adapter in sandbox.
5. Capture old `after` snapshot + proposals.
6. Reset sandbox to original `state_before`.
7. Run new adapter in sandbox.
8. Capture new `after` snapshot + proposals.
9. Compare old vs new structurally.
10. Stop on first mismatch and emit report.

## 12. Mismatch reporting and triage

Minimum report fields:

- fixture name
- lane
- failing section (`state_after`, `proposals`, `debug_globals`, `side_effects`)
- mismatch path
- expected value
- actual value
- old/new run IDs or labels

Triage order:

1. side-effect violation
2. state schema/type mismatch
3. proposal field mismatch
4. ordering mismatch
5. debug-global mismatch

## 13. Safety and stop conditions

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

## 14. Recommended next tasks

1. Define adapter interface doc for maintenance and enemy-effect lane runners (docs-only).
2. Define comparator path-format and numeric-normalization policy (docs-only).
3. Draft fixture schema versioning and validation rules (docs-only).
4. Draft side-effect guard policy table and violation taxonomy (docs-only).
5. Revisit readiness/resource-cache ownership design before any stateful extraction.

No immediate provider extraction is recommended.

## 15. Validation snapshot

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
- Only `docs/replay_harness_skeleton_design.md` was created for this task.
