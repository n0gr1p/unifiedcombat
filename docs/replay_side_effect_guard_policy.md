# Replay Side-Effect Guard Policy

## 1. Purpose

This document defines policy for the future replay harness side-effect guard.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create guard code.

This document defines policy only.

Guard policy is required before implementing `side_effect_guard.lua`.

Replay fixtures must fail closed if forbidden side effects are attempted.

Maintenance and enemy-effect replay fixtures expect zero runtime side effects by default.

## 2. Guard design principles

- Block execution; do not mock-success forbidden side effects.
- Record attempted call metadata.
- Fail fixture on first violation by default.
- Allow diagnostic continuation only by explicit option.
- Preserve attempted argument values for triage.
- Never call live Windower execution APIs.
- Never send IPC during replay.
- Never write files during replay.
- Avoid requiring full runtime scheduler modules.
- Make violation output deterministic.
- Integrate with comparator `side_effects` section.

## 3. Prohibited side-effect API table

| API / operation | Category | Default replay policy | Allowed in maintenance fixtures? | Allowed in enemy-effect fixtures? | Violation code | Notes |
|---|---|---|---|---|---|---|
| `windower.send_command` | `command_execution` | Forbidden, record, fail | No | No | `COMMAND_EXECUTION_ATTEMPT` | Includes all command strings. |
| `windower.ffxi.run` | `movement_execution` | Forbidden, record, fail | No | No | `MOVEMENT_EXECUTION_ATTEMPT` | Includes run start/stop vectors. |
| `windower.ffxi.turn` | `facing_execution` | Forbidden, record, fail | No | No | `FACING_EXECUTION_ATTEMPT` | Any facing mutation attempt is blocked. |
| `uc_settarget.select_by_id` | `target_selection` | Forbidden, record, fail | No | No | `TARGET_SELECTION_ATTEMPT` | No live target changes in replay. |
| `windower.send_ipc_message` | `ipc_send` | Forbidden, record, fail | No | No | `IPC_SEND_ATTEMPT` | IPC send never allowed. |
| `windower.register_event` | `event_registration` | Forbidden, record, fail | No | No | `EVENT_REGISTRATION_ATTEMPT` | Includes any runtime listener setup. |
| `windower.unregister_event` | `event_registration` | Forbidden, record, fail | No | No | `EVENT_REGISTRATION_ATTEMPT` | Treated same as registration changes. |
| `io.open` write mode (`w`,`w+`) | `file_write` | Forbidden, record, fail | No | No | `FILE_WRITE_ATTEMPT` | Hard block file writes. |
| `io.open` append mode (`a`,`a+`) | `file_write` | Forbidden, record, fail | No | No | `FILE_WRITE_ATTEMPT` | Hard block append writes. |
| `os.execute` | `process_execution` | Forbidden, record, fail | No | No | `PROCESS_EXECUTION_ATTEMPT` | No subprocess execution. |
| coroutine/thread/timer startup | `async_runtime_start` | Forbidden, record, fail | No | No | `ASYNC_RUNTIME_START_ATTEMPT` | Includes async loops/timers starting runtime behavior. |
| unknown direct command emitter | `unknown_runtime_side_effect` | Forbidden, record, fail | No | No | `UNKNOWN_SIDE_EFFECT_ATTEMPT` | Catch-all for unmapped runtime side effects. |

Default policy: forbidden for maintenance replay and enemy-effect replay; record and fail.

## 4. Allowed read-only API policy

Read-only APIs may be represented by deterministic stubs only.

Examples:

- `windower.ffxi.get_info`
- `windower.ffxi.get_player`
- `windower.ffxi.get_mob_by_id`
- `windower.ffxi.get_mob_by_index`
- resource lookups
- catalog lookups
- parser helpers
- pure extracted helpers

Rules:

- Live calls are not allowed in non-runtime replay.
- Fixture-backed stubs are allowed.
- Missing stub values must fail with `MISSING_STUB` or `MISSING_DEP` (adapter error), never fallback to live state.
- Read-only file loading is not allowed in default provider replay fixtures unless explicitly scoped as a loader-contract fixture.

## 5. File IO policy

Default policy:

- No file writes.
- No append writes.
- No runtime log writes.
- No fixture mutation writes.

Read-only exceptions:

- Read-only file access is disabled by default.
- Read-only loader-contract fixtures may be allowed later, but must be separate from provider/state replay fixtures.
- Any read-only exception must be explicit in fixture metadata and guard options.
- Loader-contract fixtures must compare error/fatal behavior deterministically.

`io.open` mode handling:

- nil/omitted mode: treat as read mode, but blocked unless read-only fixture explicitly allows it.
- `"r"`: read-only, blocked by default unless explicit read fixture.
- `"w"`, `"a"`, `"r+"`, `"w+"`, `"a+"`: forbidden.
- unknown mode: forbidden.

## 6. IPC policy

Default policy:

- `windower.send_ipc_message` is forbidden.
- IPC receive/apply logic may be replayed only from fixture-provided messages.
- No live IPC sends.
- No live IPC receives.
- IPC side effects must be recorded as violations if attempted.

Allowed fixture model:

- `fixture.inputs.ipc_messages`
- `fixture.state_before.party_ipc_cache`
- `expected.state_after.party_ipc_cache`

## 7. Event registration policy

- No Windower event registration in replay.
- No event unregistration in replay.
- Adapters must not require modules that register events on load.
- Any event registration attempt is `EVENT_REGISTRATION_ATTEMPT`.
- Replay harness must not invoke live `on_incoming_chunk`/`on_action` hooks directly unless through isolated adapter functions defined later.

## 8. Guard modes

### 8.1 Strict mode

Default.

Behavior:

- Record violation.
- Mark result `ok=false`.
- Stop lane execution.
- Comparator checks `side_effects` before state/proposal sections.

### 8.2 Diagnostic mode

Explicit only.

Behavior:

- Record violation.
- Continue execution where possible.
- Result still fails unless fixture explicitly expects violation.
- Used only for triage, not parity approval.

### 8.3 Loader-contract mode

Future explicit mode only.

Behavior:

- May allow read-only file access.
- Still forbids writes.
- Still forbids command/movement/IPC.
- Must not be mixed with provider/state replay fixtures.

## 9. Violation taxonomy

| Violation code | Category | Triggering API examples | Default severity | Expected fixture outcome | Comparator mismatch path |
|---|---|---|---|---|---|
| `COMMAND_EXECUTION_ATTEMPT` | `command_execution` | `windower.send_command` | high | fail | `side_effects.count_by_api["windower.send_command"]` |
| `MOVEMENT_EXECUTION_ATTEMPT` | `movement_execution` | `windower.ffxi.run` | high | fail | `side_effects.count_by_api["windower.ffxi.run"]` |
| `FACING_EXECUTION_ATTEMPT` | `facing_execution` | `windower.ffxi.turn` | high | fail | `side_effects.count_by_api["windower.ffxi.turn"]` |
| `TARGET_SELECTION_ATTEMPT` | `target_selection` | `uc_settarget.select_by_id` | high | fail | `side_effects.count_by_api["uc_settarget.select_by_id"]` |
| `IPC_SEND_ATTEMPT` | `ipc_send` | `windower.send_ipc_message` | high | fail | `side_effects.count_by_api["windower.send_ipc_message"]` |
| `EVENT_REGISTRATION_ATTEMPT` | `event_registration` | `windower.register_event`, `windower.unregister_event` | high | fail | `side_effects.first_violation.violation_code` |
| `FILE_WRITE_ATTEMPT` | `file_write` | `io.open("...","w")`, `io.open("...","a")` | high | fail | `side_effects.count_by_api["io.open.write_or_append"]` |
| `FILE_READ_ATTEMPT` | `file_write` (guarded IO policy) | `io.open("...","r")` without loader-contract allowance | medium | fail | `side_effects.first_violation.violation_code` |
| `PROCESS_EXECUTION_ATTEMPT` | `process_execution` | `os.execute` | high | fail | `side_effects.first_violation.violation_code` |
| `ASYNC_RUNTIME_START_ATTEMPT` | `async_runtime_start` | timer/thread/coroutine runtime starters | high | fail | `side_effects.first_violation.violation_code` |
| `LIVE_WINDOWER_READ_ATTEMPT` | `unknown_runtime_side_effect` | direct live Windower reads bypassing stubs | high | fail | `side_effects.first_violation.violation_code` |
| `LIVE_SCHEDULER_REQUIRE_ATTEMPT` | `unknown_runtime_side_effect` | direct `require('unified_scheduler')` in adapter path | high | fail | `side_effects.first_violation.violation_code` |
| `UNKNOWN_SIDE_EFFECT_ATTEMPT` | `unknown_runtime_side_effect` | unmapped mutable runtime operation | high | fail | `side_effects.first_violation.violation_code` |

## 10. Guard call record schema

```lua
{
  api = "windower.send_command",
  category = "command_execution",
  violation_code = "COMMAND_EXECUTION_ATTEMPT",
  args = {},
  fixture_name = "string",
  lane = "maintenance" or "enemy_effect",
  adapter_id = "old" or "new",
  phase = "adapter_setup" or "execution" or "normalization",
  call_index = 1,
  stack_hint = "optional string",
}
```

Schema rules:

- `call_index` is monotonic per adapter run.
- `args` preserves raw attempted arguments (no lossy formatting).
- `stack_hint` is optional and deterministic when available.

## 11. Guard result schema

```lua
{
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
  violations = {},
  mode = "strict" or "diagnostic" or "loader_contract",
}
```

Rules:

- `first_violation` equals `violations[1]` when any violations exist.
- `attempted=true` iff `#violations > 0`.
- `count_by_api` keys must be stable across fixtures for comparator determinism.

## 12. Lane-specific expectations

Maintenance fixtures:

- Expected side-effect counts are all zero.
- Any violation fails parity run.
- Diagnostic mode allowed for triage only.

Enemy-effect fixtures:

- Expected side-effect counts are all zero.
- Ingestion/provider replay may read only fixture-backed stubs.
- Any command/movement/target/IPC/file-write attempt fails run.

Loader-contract fixtures (future separate lane/mode):

- May allow explicit read-only file IO.
- Must still report and fail on command/movement/IPC/writes.

## 13. Side-effect comparison integration

Comparator integration policy:

- Compare `side_effects` section before state/proposals by default.
- Any non-zero prohibited API count is a mismatch unless fixture explicitly expects it.
- `first_violation.violation_code` mismatch is treated as high-severity difference.
- Side-effect mismatch paths follow comparator path format policy.

Comparator-first triage ordering:

1. side-effect violations
2. adapter `error`
3. state mismatches
4. proposal mismatches

## 14. Fixture expectation rules

Default fixture expectations:

- `expected.side_effects.attempted = false`
- all guarded API counts `= 0`
- `expected.side_effects.first_violation = nil`

If a fixture intentionally validates violation behavior (diagnostic/testing only):

- Fixture must explicitly mark `expects_violation=true`.
- Fixture must list expected `violation_code` and API count changes.
- Such fixtures are not parity-approval fixtures.

## 15. Future implementation constraints

Future `side_effect_guard.lua` implementation must:

- Be deterministic in violation ordering.
- Avoid global state leakage between fixtures.
- Support per-fixture mode (`strict`, `diagnostic`, optional `loader_contract`).
- Expose stable `count_by_api` key set.
- Prevent fallback to live runtime APIs.
- Integrate with adapter normalized result schema without extra post-processing.

Implementation must not:

- execute blocked APIs
- auto-retry blocked calls
- downgrade severity silently
- rewrite attempted arguments before record capture

## 16. Stop conditions

This document does not permit moving:

- `p1_collect_maintenance`
- `p1_collect_enemy_buff_removal`
- `ingest_enemy_effects_from_raw_action_028`
- enemy-effect state mutators
- enemy dispel attempt mutators
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

## 17. Recommended next tasks

1. Docs-only fixture schema versioning and validation rules.
2. Docs-only adapter conformance checklist for old/new implementations.
3. Docs-only comparator test-case matrix for maintenance and enemy-effect fixtures.
4. Docs-only loader-contract fixture policy (separate from provider/state fixtures).
5. Revisit readiness/resource-cache ownership design before stateful extraction.

## 18. Validation snapshot

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
- Only `docs/replay_side_effect_guard_policy.md` was created for this task.
