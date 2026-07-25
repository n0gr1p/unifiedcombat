# Replay Adapter Interface Spec

## 1. Purpose

This document defines the adapter contract used by the future non-runtime replay harness.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create harness code.

Adapters are a boundary between fixture data and old/new implementations.

Adapters must never invoke live runtime side effects.

Adapters must not require `unified_scheduler.lua` directly unless a safe non-runtime entrypoint exists later.

## 2. Adapter design principles

- Adapter functions must be deterministic.
- All time comes from `fixture.now` or injected `deps.now_s`.
- All Windower reads come from fixture stubs.
- All readiness decisions come from fixture stubs.
- All state is copied from fixture `state_before`.
- Fixture input must never be mutated.
- Side effects must be trapped and recorded, not executed.
- Adapters return normalized results only.
- Old and new adapters must expose equivalent interfaces.
- Adapter scope must stay lane-specific.

## 3. Shared adapter interface

```lua
local adapter = {}

function adapter.run(fixture, deps, options)
  -- returns normalized_result
end

return adapter
```

### Shared arguments

- `fixture`: validated fixture table from replay fixture loader.
- `deps`: injected deterministic dependencies and guards.
- `options`: runner-level options (`adapter_id`, `lane`, strictness flags).

### Shared guarantees

- No mutation of `fixture`.
- No use of live Windower globals except through `deps` stubs.
- No direct command/movement/IPC/file-write execution.

## 4. Lane-specific adapter interfaces

### 4.1 Maintenance lane adapter

```lua
local adapter = {}

function adapter.run_maintenance(fixture, deps, options)
  -- returns normalized_maintenance_result
end

function adapter.run(fixture, deps, options)
  return adapter.run_maintenance(fixture, deps, options)
end

return adapter
```

Required behavior:

- Build deterministic maintenance context from fixture (`settings`, `player_context`, `party_snapshot`, parsed status snapshot input).
- Run only maintenance-lane logic under test.
- Capture proposals before ranking/dispatch.
- Return normalized before/after maintenance-related state.

### 4.2 Enemy-effect lane adapter

```lua
local adapter = {}

function adapter.run_enemy_effect(fixture, deps, options)
  -- returns normalized_enemy_effect_result
end

function adapter.run(fixture, deps, options)
  return adapter.run_enemy_effect(fixture, deps, options)
end

return adapter
```

Required behavior:

- Build deterministic enemy-effect context from fixture (`mob_snapshot`, `claim_state`, catalog input, raw/parsed action input).
- Run only enemy-effect ingestion/provider logic under test.
- Capture proposals before ranking/dispatch.
- Return normalized before/after enemy-effect and attempt state.

## 5. Injected dependency contract

`deps` must provide deterministic, lane-safe functions/tables:

- `now_s()`
- `windower` stub tree (read-only getters)
- `readiness` stub table/functions
- `resources` stub table (`buffs`, `spells`, `abilities`, jobs metadata as needed)
- `catalog` stub table (TargetBar-equivalent tables)
- `side_effect_guard` hooks
- `state_tools` (`deep_copy`, `freeze`, `snapshot`, `normalize`)
- `trace` collector for stub/guard calls

Dependency rules:

- Missing required dependency is an adapter failure.
- Adapter must not invent fallback behavior for missing required deps.
- Dependency errors must be reported through normalized error contract.

## 6. Normalized result shape

All adapters must return this structure:

```lua
{
  ok = true or false,
  lane = "maintenance" or "enemy_effect",
  adapter_id = "old" or "new" or "string",
  fixture_name = "string",

  before = {
    state = {},
    debug_globals = {},
  },

  after = {
    state = {},
    debug_globals = {},
  },

  proposals_pre_rank = {},

  side_effects = {
    attempted = false,
    count_by_api = {
      ["windower.send_command"] = 0,
      ["windower.ffxi.run"] = 0,
      ["windower.ffxi.turn"] = 0,
      ["uc_settarget.select_by_id"] = 0,
      ["windower.send_ipc_message"] = 0,
      ["io.open.write_or_append"] = 0,
    },
    first_violation = nil,
  },

  trace = {
    stubs = {},
    guards = {},
  },

  error = nil,
}
```

Normalization rules:

- Numeric values must remain numeric.
- Key types must be preserved (`number` vs `string`).
- `nil` vs `false` vs empty string must be preserved.
- Proposal ordering must remain source-order deterministic.

## 7. Prohibited runtime calls

Adapters must not directly call:

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `windower.send_ipc_message`
- file writes (`io.open` in write/append modes)

Adapters must not:

- register Windower events
- call live packet listeners
- call live scheduler tick orchestration
- require `unified_scheduler.lua` directly (current state unsafe)

## 8. Side-effect guard expectations

Guard behavior contract:

- Every prohibited API must be wrapped by guard before adapter logic executes.
- Guard records attempted calls with args and phase.
- Guard increments per-API counters.
- Guard returns a deterministic failure signal instead of executing side effect.

Adapter behavior on guard violation:

- Mark result `ok=false`.
- Populate `side_effects.attempted=true` and `first_violation`.
- Stop lane execution unless `options.continue_on_guard_violation=true`.

## 9. Fixture input ownership rules

Adapter ownership and mutability:

- `fixture`: read-only.
- `fixture.state_before`: copied into adapter-local sandbox before execution.
- `fixture.inputs`: read-only.
- `fixture.expected`: never used to mutate execution; compare-only domain.

Rules:

- Adapter must deep-copy fixture-owned tables before mutation.
- Adapter must not retain references to fixture tables in returned `after.state`.
- Adapter must fail if fixture schema is missing required lane fields.

## 10. State snapshot ownership rules

Snapshot boundaries:

- `before.state`: captured from adapter-local sandbox immediately before lane execution.
- `after.state`: captured from same sandbox immediately after execution.
- Snapshot module owns normalization for comparison; adapter returns raw structural data compatible with it.

Lane-specific required state slices:

- Maintenance lane:
  - `maintenance_state`
  - `recent_gain`
  - maintenance usage of `attempted`
  - `family_tokens`
  - maintenance cadence gate fields
- Enemy-effect lane:
  - `enemy_effect_state`
  - `enemy_dispel_attempts`
  - lane-relevant scheduler phase substate only

Adapters must not include unrelated runtime state slices unless explicitly enabled by options.

## 11. Failure and error reporting contract

Adapter failures must return `ok=false` with structured `error`:

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

Rules:

- No silent fallback behavior.
- Fail fast on invalid input or missing deterministic dependency.
- Preserve first failure as primary error.
- Include enough context for runner mismatch triage.

## 12. Old vs new compatibility contract

Old and new adapters must:

- implement identical function signatures
- accept identical dependency table structure
- return identical normalized result shape
- expose identical lane IDs and error code taxonomy

Any schema/version change requires explicit adapter interface version bump.

## 13. Adapter versioning

Recommended fields:

```lua
adapter.interface_version = "1.0"
adapter.lane = "maintenance" or "enemy_effect"
adapter.adapter_name = "old" or "new" or "custom_name"
```

Version policy:

- Patch: backward-compatible metadata additions.
- Minor: backward-compatible optional fields.
- Major: breaking signature/result-shape changes.

## 14. Safety and stop conditions

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

## 15. Recommended next tasks

1. Docs-only comparator path-format and normalization policy spec.
2. Docs-only side-effect guard policy table and violation taxonomy.
3. Docs-only fixture schema versioning and validation rules.
4. Docs-only adapter conformance checklist for old/new implementations.
5. Revisit readiness/resource-cache ownership design before any stateful extraction.

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

And side-effect counts (`grep` or `Select-String` equivalent):

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `io.open`

Required confirmations:

- No runtime files were changed.
- No side-effect call sites were moved.
- Only `docs/replay_adapter_interface_spec.md` was created for this task.
