# Replay Fixture Schema Policy

## 1. Purpose

This document defines schema versioning and validation policy for future replay fixture files.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create fixture files.

This document does not create validator code.

This document defines policy only.

Fixture schema policy is required before implementing `fixture_loader.lua` or creating fixture suites.

Fixture validation must fail fast before adapter execution.

Maintenance and enemy-effect fixtures must default to zero expected side effects.

## 2. Fixture schema design principles

- Fixtures are deterministic.
- Fixtures are read-only during replay.
- Every fixture declares `schema_version`.
- Every fixture declares `lane`.
- Every fixture declares `fixture_name`.
- All required fields must be explicit.
- No fallback to live Windower state.
- No inferred settings unless fixture explicitly provides them.
- Numeric key types must be preserved where behavior depends on numeric keys.
- `nil` vs `false` vs empty string must be intentional and documented.
- Unknown fields fail by default unless explicitly allowed by schema profile.
- Fixture validation happens before old/new adapter execution.
- Validation errors use stable error codes.

## 3. Schema version policy

Required field:

```lua
schema_version = "1.0"
```

Policy:

- Validator must reject fixtures without `schema_version`.
- Validator must reject unsupported versions.
- Version is semantic text (`major.minor`).
- Current supported version set: `{"1.0"}`.

Compatibility:

- Patch-level metadata additions that do not change required shape stay within `1.0` policy notes.
- Breaking schema shape changes require major version bump.
- Backward compatibility is explicit; no implicit migration during validation.

## 4. Common fixture schema (all lanes)

Required top-level fields for all fixtures:

- `schema_version` (string)
- `fixture_name` (string, non-empty)
- `lane` (`"maintenance"` or `"enemy_effect"`)
- `description` (string)
- `now` (number)
- `settings` (table)
- `player_context` (table)
- `party_snapshot` (table)
- `mob_snapshot` (table)
- `claim_state` (table)
- `inputs` (table)
- `state_before` (table)
- `stubs` (table)
- `expected` (table)

Required nested common fields:

- `inputs.raw_packet` (any or `nil`)
- `inputs.parsed_packet` (table or `nil`)
- `inputs.parsed_status_snapshot` (table or `nil`)
- `inputs.raw_action` (any or `nil`)
- `inputs.parsed_action` (table or `nil`)
- `state_before.scheduler` (table)
- `stubs.readiness` (table)
- `stubs.windower` (table)
- `stubs.resources` (table)
- `stubs.catalog` (table)
- `stubs.now_s` (function descriptor or fixture value contract)
- `expected.state_after` (table)
- `expected.proposals` (table/list)
- `expected.debug_globals` (table)
- `expected.side_effects` (table)
- `expected.noop_or_reject_reason` (string or `nil`)

Required `expected.side_effects` defaults:

- `attempted = false`
- `count_by_api` present and all guarded APIs set to `0`
- `first_violation = nil`

## 5. Maintenance lane required profile

When `lane == "maintenance"`, required fields include:

- `state_before.maintenance_state` (table)
- `state_before.recent_gain` (table)
- `state_before.attempted` (table)
- `state_before.family_tokens` (table)
- `state_before.enemy_effect_state` (table; may be empty)
- `state_before.enemy_dispel_attempts` (table; may be empty)
- Maintenance cadence snapshot fields required by adapter profile (for example scheduler phase maintenance gates) must be explicit in `state_before.scheduler`.

Maintenance-specific input requirements:

- At least one of:
  - `inputs.parsed_status_snapshot` (table)
  - `inputs.raw_packet` for status snapshot path

Maintenance-specific expected requirements:

- `expected.state_after.maintenance_state`
- `expected.state_after.recent_gain`
- `expected.state_after.attempted` (maintenance-relevant slice)
- `expected.state_after.family_tokens`
- `expected.proposals` ordered list semantics

## 6. Enemy-effect lane required profile

When `lane == "enemy_effect"`, required fields include:

- `state_before.enemy_effect_state` (table)
- `state_before.enemy_dispel_attempts` (table)
- `state_before.maintenance_state` (table; may be empty)
- `state_before.recent_gain` (table; may be empty)
- `state_before.attempted` (table; may be empty)
- `state_before.family_tokens` (table; may be empty)

Enemy-effect-specific input requirements:

- At least one of:
  - `inputs.parsed_action` (table)
  - `inputs.raw_action` (raw payload)

Enemy-effect-specific expected requirements:

- `expected.state_after.enemy_effect_state`
- `expected.state_after.enemy_dispel_attempts`
- `expected.proposals` ordered list semantics

## 7. Optional fields policy

Allowed optional top-level fields (version `1.0`):

- `tags` (table/list of strings)
- `meta` (table)
- `notes` (string)
- `expects_violation` (boolean; diagnostic-only fixtures)

Allowed optional nested fields:

- `expected.comparator_overrides` (table)
- `expected.normalization_overrides` (table)

Rules:

- Optional fields must still pass type checks.
- Any field not required or explicitly optional is unknown and fails validation by default.

## 8. Type validation rules

Type strictness:

- `fixture_name`, `lane`, `schema_version`, `description` must be strings.
- `now` must be number.
- `settings`, snapshots, `inputs`, `state_before`, `stubs`, `expected` must be tables.
- `expected.proposals` must be list-like table (ordered).
- `expected.side_effects.attempted` must be boolean.
- `expected.side_effects.count_by_api` must be map-like table.

No coercion rules:

- No string-to-number coercion.
- No number-to-string coercion.
- No boolean coercion from numeric/string values.

Invalid values fail with typed error codes (section 12).

## 9. Key-type preservation rules

Rules:

- Numeric keys must remain numeric in maps where behavior depends on numeric IDs.
- Stringified numeric keys are invalid where numeric keys are required.
- Validator must detect mixed key types in strict numeric-key maps.

Numeric-key-sensitive paths include (non-exhaustive):

- enemy effect state: target id keys, effect id keys
- status snapshot maps keyed by buff id
- claim-set maps keyed by mob id

If key typing is wrong, fail validation before adapter run.

## 10. Invalid/missing field behavior

Validation must fail fast for:

- missing required fields
- unsupported schema version
- wrong field type
- unknown fields (unless optional-allowlisted)
- lane/profile mismatch
- missing lane-specific required state sections

Failure behavior:

- no adapter execution
- no comparator execution
- structured validation error returned

## 11. Lane-specific schema profiles

Profile selection:

- Use `lane` value to select `maintenance` or `enemy_effect` profile.

Profile behavior:

- Validate common schema first.
- Validate lane-specific requirements second.
- Validate optional allowlist last.

Strict unknown-field policy:

- Unknown fields fail by default in both profiles.
- Future relaxed behavior requires explicit profile version and documented rationale.

## 12. Validation error schema

Validation error shape:

```lua
{
  ok = false,
  code = "INVALID_SCHEMA_VERSION" | "MISSING_REQUIRED_FIELD" | "INVALID_FIELD_TYPE" | "UNKNOWN_FIELD" | "LANE_PROFILE_MISMATCH" | "INVALID_KEY_TYPE" | "INVALID_SIDE_EFFECT_EXPECTATION",
  fixture_name = "string" or nil,
  lane = "maintenance" or "enemy_effect" or nil,
  path = "string",
  message = "human-readable summary",
  expected_type = "optional string",
  actual_type = "optional string",
  detail = {},
}
```

Rules:

- `path` is required and deterministic.
- `code` values are stable and versioned with schema policy.
- First validation failure is reported by default.

## 13. Migration and versioning policy

Version advancement:

- `1.x` minor changes may add optional fields only.
- Any required-field changes require major version bump.

Migration policy:

- No silent migration during validation.
- Explicit migration tooling/policy must be documented separately if introduced.
- Fixtures must be authored against a declared supported schema version.

Deprecation policy:

- Deprecated fields remain accepted only within documented version window.
- Deprecated field acceptance must be explicit in version profile notes.

## 14. Valid fixture examples

### 14.1 Valid maintenance fixture (minimal shape)

```lua
{
  schema_version = "1.0",
  fixture_name = "maint_no_buffs_due",
  lane = "maintenance",
  description = "Maintenance emits expected proposal when due",
  now = 12345.678,
  settings = {},
  player_context = {},
  party_snapshot = {},
  mob_snapshot = {},
  claim_state = {},
  inputs = {
    raw_packet = nil,
    parsed_packet = nil,
    parsed_status_snapshot = {},
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
    now_s = {},
  },
  expected = {
    state_after = {
      maintenance_state = {},
      recent_gain = {},
      attempted = {},
      family_tokens = {},
    },
    proposals = {},
    debug_globals = {},
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
    noop_or_reject_reason = nil,
  },
}
```

### 14.2 Valid enemy-effect fixture (minimal shape)

```lua
{
  schema_version = "1.0",
  fixture_name = "enemy_gain_dispellable",
  lane = "enemy_effect",
  description = "Enemy gains dispellable effect",
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
    parsed_action = {},
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
    now_s = {},
  },
  expected = {
    state_after = {
      enemy_effect_state = {},
      enemy_dispel_attempts = {},
    },
    proposals = {},
    debug_globals = {},
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
    noop_or_reject_reason = nil,
  },
}
```

## 15. Invalid fixture examples

### 15.1 Missing schema version

```lua
{
  fixture_name = "bad_fixture",
  lane = "maintenance",
}
```

Expected error:

- `code = "MISSING_REQUIRED_FIELD"`
- `path = "schema_version"`

### 15.2 Wrong lane type

```lua
{
  schema_version = "1.0",
  fixture_name = "bad_lane_type",
  lane = 1,
}
```

Expected error:

- `code = "INVALID_FIELD_TYPE"`
- `path = "lane"`

### 15.3 Unknown top-level field

```lua
{
  schema_version = "1.0",
  fixture_name = "unknown_field",
  lane = "enemy_effect",
  description = "x",
  now = 1,
  settings = {},
  player_context = {},
  party_snapshot = {},
  mob_snapshot = {},
  claim_state = {},
  inputs = {},
  state_before = {},
  stubs = {},
  expected = {},
  unexpected_field = true,
}
```

Expected error:

- `code = "UNKNOWN_FIELD"`
- `path = "unexpected_field"`

### 15.4 Invalid numeric key type for enemy-effect map

```lua
state_before = {
  enemy_effect_state = {
    ["17793029"] = { [33] = { seen_at = 1 } },
  }
}
```

Expected error:

- `code = "INVALID_KEY_TYPE"`
- `path = "state_before.enemy_effect_state[\"17793029\"]"`

### 15.5 Invalid side-effect expectation default

```lua
expected = {
  side_effects = {
    attempted = true,
    count_by_api = {},
    first_violation = nil,
  }
}
```

Expected error (for normal parity fixtures):

- `code = "INVALID_SIDE_EFFECT_EXPECTATION"`
- `path = "expected.side_effects.attempted"`

## 16. Stop conditions

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

## 17. Recommended next tasks

1. Docs-only adapter conformance checklist for old/new implementations.
2. Docs-only comparator test-case matrix for maintenance and enemy-effect fixtures.
3. Docs-only loader-contract fixture profile extension policy.
4. Draft fixture authoring guide with lane-specific templates (docs-only).
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
- Only `docs/replay_fixture_schema_policy.md` was created for this task.
