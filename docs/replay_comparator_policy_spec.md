# Replay Comparator Policy Spec

## 1. Purpose

This document defines comparison rules for the future non-runtime replay harness.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create comparator code.

This document defines policy only.

Comparator policy is required before implementing `structural_compare.lua`.

Comparator results must be deterministic and useful for old-vs-new replay triage.

## 2. Comparator design principles

- Compare structure, not serialized strings.
- Preserve numeric key types.
- Preserve `nil` vs `false` vs empty string semantics.
- Fail on first mismatch by default.
- Report precise paths.
- Support lane-specific comparison profiles.
- Normalize only by explicit policy.
- Do not silently ignore unknown fields.
- Proposal order is meaningful unless explicitly declared otherwise.
- Map ordering is not meaningful.
- Fixture expected data must not be mutated.
- Old/new results must be compared after normalization into adapter result schema.

## 3. Normalized adapter result input

Comparator input shape:

```lua
{
  ok = true or false,
  lane = "maintenance" or "enemy_effect",
  adapter_id = "old" or "new",
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
    count_by_api = {},
    first_violation = nil,
  },

  trace = {
    stubs = {},
    guards = {},
  },

  error = nil,
}
```

Input contract:

- Comparator receives two already-normalized values: `old_result`, `new_result`.
- Comparator never mutates either input.
- Comparator must validate that both inputs conform to this shape before deep comparison.

## 4. Mismatch path format

Path format policy:

- Root prefixes:
  - `old.` paths for `old_result`
  - `new.` paths for `new_result`
  - `compare.` paths for logical mismatch section
- Dot notation for map/object keys that are valid identifiers.
- Bracket notation for:
  - numeric keys
  - string keys containing punctuation/whitespace
  - list indices
- List indices are 1-based to match Lua table iteration conventions for arrays.

Examples:

- `after.state.maintenance_state.status_snapshot[17793029][33].count`
- `proposals_pre_rank[1].detail.enemy_effect_priority`
- `side_effects.count_by_api["windower.send_command"]`
- `error.detail["missing_dep"]`

Path determinism rule:

- When multiple mismatches exist, the comparator reports the first mismatch in deterministic traversal order defined in section 9.

## 5. Key/type strictness policy

Strict comparison defaults:

- Key sets must match exactly unless a lane profile explicitly permits optional fields.
- Key types must match exactly (`123` and `"123"` are different keys).
- Value types must match exactly.
- `number` and `string` are never coercible.
- Boolean and numeric flags are never coercible.

Strictness examples:

- `state.after.enemy_effect_state[17793029]` and `state.after.enemy_effect_state["17793029"]` mismatch.
- `urgency = 0.65` and `urgency = "0.65"` mismatch.

## 6. Nil/false/empty-string policy

Comparator must treat these as distinct values:

- `nil`
- `false`
- `""`

Rules:

- Missing key (`nil`) is not equal to present key with `false`.
- Missing key (`nil`) is not equal to present key with empty string.
- Empty string is only equal to empty string.

Reporting:

- Mismatch reason should explicitly indicate semantic class mismatch, for example `nil_vs_false`.

## 7. Ordered list vs unordered map policy

Ordered list policy (order meaningful):

- `proposals_pre_rank`
- list-like rows that represent sequence (for example `endtimes` arrays)

Rules:

- Same length required.
- Same index-by-index values required.

Unordered map policy (order not meaningful):

- state maps keyed by ids or names
- `count_by_api`
- debug/global map-like tables

Rules:

- Compare by key membership and per-key value equality.
- Iteration order must be canonicalized (section 9).

Mixed tables:

- If a table contains both array and map portions, comparator treats it as map by default unless lane profile marks it as ordered list.

## 8. Numeric normalization policy

Default policy:

- No numeric tolerance unless explicitly enabled by profile/field rule.

Allowed numeric normalization (explicit only):

- Optional decimal epsilon for known floating-point artifacts on selected fields only.
- Integer-like fields must remain exact integer matches.

Field guidance:

- Always exact by default:
  - ids (`target_id`, `effect_id`, `buff_id`)
  - counts
  - `priority_band`
- Candidate tolerance fields (profile-gated):
  - time-like floats (`created_at`, `expires_at`, `commit_deadline`, `seen_at`, `ts`)
  - `urgency` only if both are numeric and profile says tolerance allowed

Tolerance policy (if enabled):

- Default epsilon: `1e-6`
- Use absolute difference only.
- Comparator output must report epsilon used when a numeric mismatch occurs.

## 9. Timestamp/deadline normalization policy

Deterministic expectation:

- `fixture.now` / injected `now_s` should make timestamps deterministic.

Comparison mode:

- Exact by default.
- Optional normalized mode for known derived timestamps.

Normalized mode rules (opt-in):

- Compare timestamp deltas from fixture baseline (`value - fixture.now`) for selected fields.
- Allow epsilon only where profile permits.

Fields commonly governed by timestamp policy:

- `created_at`
- `expires_at`
- `commit_deadline`
- state row timestamps like `seen_at`, `ts`
- cooldown timestamps in attempt maps

## 10. Lane-specific comparison profiles

### 10.1 Maintenance profile

Required strict sections:

- `after.state.maintenance_state`
- `after.state.recent_gain`
- maintenance slice of `after.state.attempted`
- `after.state.family_tokens`
- maintenance cadence gates
- `proposals_pre_rank`
- `side_effects`

Field behavior notes:

- `status_snapshot` rows: map keys unordered, `endtimes` ordered list.
- proposal ordering is strict.
- `noop_or_reject` semantics compared through expected debug/error fields when present.

### 10.2 Enemy-effect profile

Required strict sections:

- `after.state.enemy_effect_state`
- `after.state.enemy_dispel_attempts`
- `proposals_pre_rank`
- `side_effects`

Field behavior notes:

- enemy-effect map keys: target/effect keys are strict numeric-key maps.
- proposal ordering strict when multiple proposals are produced.
- attempt map cooldown timestamps follow timestamp policy.

## 11. Ignored-field policy

Default policy:

- Ignore nothing unless explicitly listed in profile allowlist.

Allowed ignore list mechanism:

- Profile may define exact path allowlist for non-contract, non-deterministic telemetry fields.
- Ignore entries must be explicit full paths or path patterns with clear scope.

Rules:

- Unknown fields are not silently ignored.
- If field exists in one result but not the other and not ignored, mismatch.
- Ignore policy changes must be documented with rationale.

## 12. Mismatch result schema

Comparator mismatch output:

```lua
{
  ok = false,
  fixture_name = "string",
  lane = "maintenance" or "enemy_effect",
  section = "after.state" or "proposals_pre_rank" or "side_effects" or "error" or "trace",
  mismatch_path = "string",
  reason = "value_mismatch" | "type_mismatch" | "missing_key" | "extra_key" | "order_mismatch" | "nil_vs_false" | "numeric_tolerance_exceeded",
  expected = nil,
  actual = nil,
  meta = {
    epsilon = nil,
    profile = "maintenance" or "enemy_effect",
    compared_as = "ordered_list" or "unordered_map" or "scalar",
  },
}
```

Success output:

```lua
{
  ok = true,
  fixture_name = "string",
  lane = "maintenance" or "enemy_effect",
  compared_sections = { "after.state", "proposals_pre_rank", "side_effects", "error" },
}
```

## 13. Deterministic traversal order

To ensure first-mismatch determinism:

- Scalars: direct compare.
- Ordered lists: index `1..n`.
- Maps: keys sorted by canonical order:
  - key type rank: number < string < boolean < other
  - then by value (numeric ascending, string lexicographic).

When map/list ambiguity exists:

- Use lane profile declaration.
- If unspecified, treat as map and report `ambiguous_table_shape` warning in comparator metadata.

## 14. Comparison sections and priority

Default section comparison order:

1. `ok`, `lane`, `fixture_name`
2. `error`
3. `side_effects`
4. `before.state` (optional strictness by mode)
5. `after.state`
6. `proposals_pre_rank`
7. `debug_globals`
8. `trace` (usually optional unless debugging mode)

Reason:

- Side-effect and error mismatches are highest triage priority.

## 15. Maintenance example mismatches

Example A: numeric key type mismatch

- Path: `after.state.maintenance_state.status_snapshot["17793029"]`
- Expected key type: number
- Actual key type: string
- Reason: `type_mismatch`

Example B: proposal order mismatch

- Path: `proposals_pre_rank[1].action_name`
- Expected: `maintenance_geo`
- Actual: `maintenance_songs`
- Reason: `order_mismatch`

Example C: nil vs false

- Path: `after.state.recent_gain["Player:33"].suppressed`
- Expected: `nil`
- Actual: `false`
- Reason: `nil_vs_false`

## 16. Enemy-effect example mismatches

Example A: effect row source mismatch

- Path: `after.state.enemy_effect_state[17793029][33].source`
- Expected: `raw_028_spell_msg_2`
- Actual: `raw_028_spell_msg_230`
- Reason: `value_mismatch`

Example B: attempt cooldown timestamp mismatch

- Path: `after.state.enemy_dispel_attempts["Dispel:17793029:33"]`
- Expected: `12345.678`
- Actual: `12345.6791`
- Reason: `numeric_tolerance_exceeded` (if tolerance disabled or exceeded)

Example C: side-effect violation surfaced in comparator section order

- Path: `side_effects.count_by_api["windower.send_command"]`
- Expected: `0`
- Actual: `1`
- Reason: `value_mismatch`

## 17. Stop conditions

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

## 18. Recommended next tasks

1. Docs-only side-effect guard policy table and violation taxonomy.
2. Docs-only fixture schema versioning and validation rules.
3. Docs-only adapter conformance checklist for old/new implementations.
4. Draft comparator test-case matrix (docs-only) using maintenance and enemy-effect fixtures.
5. Revisit readiness/resource-cache ownership design before stateful extraction.

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

And side-effect counts (`grep` or `Select-String` equivalent):

- `windower.send_command`
- `windower.ffxi.run`
- `windower.ffxi.turn`
- `uc_settarget.select_by_id`
- `io.open`

Required confirmations:

- No runtime files were changed.
- No side-effect call sites were moved.
- Only `docs/replay_comparator_policy_spec.md` was created for this task.
