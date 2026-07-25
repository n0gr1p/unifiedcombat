# Readiness and Resource-Cache Ownership Design

## 1. Purpose

This document defines the ownership design for readiness and resource-cache logic before any future extraction or refactor.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create harness code.

This document does not move readiness/resource-cache code.

Readiness/resource-cache logic is high-risk because false positives and false negatives directly affect proposal generation and dispatch eligibility.

Any future movement of readiness/resource-cache logic requires replay fixtures, readiness matrix coverage, and old-vs-new parity evidence.

## 2. Current ownership snapshot

| Function | Current owner | Current status | Target module if extracted | Reads | Writes | Dependencies | Side effects | Consumers | Risk level | Extraction status / future prerequisite |
|---|---|---|---|---|---|---|---|---|---|---|
| `get_spell_resource` | `unified_scheduler.lua` | owned | none | `res.spells`, `_libs.lor.resources.lc_res.spells`, local caches | `spell_name_cache.by_name`, `spell_name_cache.built` | `decode_json_escapes`, `normalize_action_name_like_healbot`, `res` | none observed (lookup/cache-only) | `spell_ready`, `action_ready`, metadata wrappers, defensive helpers | high | do not move before cache schema freeze + replay contract |
| `spell_usable_by_current_job` | `unified_scheduler.lua` | owned | none | `windower.ffxi.get_player`, `res.jobs` (via `job_id_by_short`) | none observed | `job_id_by_short` wrapper | none observed | `spell_known_and_usable` | high | requires job-eligibility fixture matrix and fail-fast fixtures |
| `spell_known_and_usable` | `unified_scheduler.lua` | owned | none | `windower.ffxi.get_spells`, `spell_usable_by_current_job` | none observed | `spell_known_flag`, `spell_usable_by_current_job` | none observed | `spell_ready` | high | requires learned/usable parity fixtures and semantic reason-code checks |
| `get_ja_resource` | `unified_scheduler.lua` | owned | none | `res.job_abilities`, `_libs.lor.resources.lc_res.job_abilities`, local caches | `ja_name_cache.by_name`, `ja_name_cache.built` | `decode_json_escapes`, `normalize_action_name_like_healbot`, `res` | none observed (lookup/cache-only) | `ja_ready`, `action_ready`, metadata wrappers | high | do not move before JA cache schema freeze + replay contract |
| `spell_ready` | `unified_scheduler.lua` | owned | none | `get_spell_resource`, `spell_known_and_usable`, `windower.ffxi.get_spell_recasts`, `windower.ffxi.get_player` | none observed | readiness reason-code contract | none observed (read-only runtime lookups) | `action_ready`, cure selection helpers, proposal collectors | critical | blocked until full readiness parity suite and guard-safe replay adapters |
| `ja_ready` | `unified_scheduler.lua` | owned | none | `get_ja_resource`, `windower.ffxi.get_abilities`, `windower.ffxi.get_player`, `windower.ffxi.get_mob_by_id`, `windower.ffxi.get_mob_by_target`, `windower.ffxi.get_ability_recasts` | none observed | `ja_targets_enemy`, `ja_requires_engaged_front`, `action_effective_range`, `target_is_in_front_arc` | none direct; runtime reads are extensive | `action_ready`, proposal collectors | critical | blocked until target/range/front/recast parity fixtures are complete |
| `action_ready` | `unified_scheduler.lua` (function variable assignment) | owned | none | `get_spell_resource`, `get_ja_resource`, `spell_ready`, `ja_ready` | none observed | spell/JA readiness branches + action kind return contract | none observed | multiple proposal/maintenance paths through `action_ready` callback | critical | blocked until spell/JA branch parity and unknown-action fail-fast parity |
| `available_cure_tier_max` | `unified_scheduler.lua` | owned | none | `cure_by_tier`, `spell_ready` | none observed | cure tier table | none observed | defensive proposal path | high | requires cure-tier readiness fixtures and MP/recast/known gating parity |
| `get_usable_cure_from_tier` | `unified_scheduler.lua` | owned | none | `cure_by_tier`, `spell_ready` | none observed | cure tier loop contract | none observed | defensive proposal path | high | requires downgrade-floor fixtures and deterministic tier fallback parity |
| `action_status_id` | wrapper in `unified_scheduler.lua` | wrapper | `uc_scheduler_action_metadata.lua` (`M.action_status_id`) | spell/JA resources via callbacks | none observed | `get_spell_resource`, `get_ja_resource` callbacks | none observed | readiness/proposal metadata paths | medium | extracted helper; keep wrapper signature stable |
| `action_duration_seconds` | wrapper in `unified_scheduler.lua` | wrapper | `uc_scheduler_action_metadata.lua` (`M.action_duration_seconds`) | spell/JA resources via callbacks | none observed | `get_spell_resource`, `get_ja_resource` callbacks | none observed | proposal metadata and cooldown semantics | medium | extracted helper; validate duration parity paths |
| `action_effective_range` | wrapper in `unified_scheduler.lua` | wrapper | `uc_scheduler_action_metadata.lua` (`M.action_effective_range`) | numeric range and `SCHED_RANGE_MULT` | none observed | metadata module + range multiplier table | none observed | `ja_ready`, range gating | high | extracted helper; range mapping parity remains mandatory |
| `action_target_mode` | wrapper in `unified_scheduler.lua` | wrapper | `uc_scheduler_action_metadata.lua` (`M.action_target_mode`) | spell/JA target metadata | none observed | `get_spell_resource`, `get_ja_resource` callbacks | none observed | command builder and targeting semantics | high | extracted helper; must keep target mode parity |
| `spell_known_flag` | wrapper in `unified_scheduler.lua` | wrapper | `uc_scheduler_action_metadata.lua` (`M.spell_known_flag`) | primitive known flags | none observed | metadata module | none observed | `spell_known_and_usable` | medium | extracted helper; semantic parity required (`true/1/'true'`) |
| `job_id_by_short` | wrapper in `unified_scheduler.lua` | wrapper | `uc_scheduler_action_metadata.lua` (`M.job_id_by_short`) | `res.jobs` via `english_short` lookup | none observed | metadata module + resource table | none observed | `spell_usable_by_current_job` | medium | extracted helper; fallback semantics require parity coverage |

Conservative unknowns to inspect before movement:

- cache reset lifecycle for `spell_name_cache` and `ja_name_cache` across reload/session boundaries (owner behavior is local, explicit reset points should be confirmed).
- whether any consumer expects non-deterministic live-resource fallback behavior from `_libs.lor.resources.lc_res`.
- whether additional readiness-relevant consumers exist outside visible proposal paths (search for indirect callback injection usage).

## 3. Ownership lanes

### 3.1 Resource lookup lane

Scope:

- spell/JA resource lookup
- `res.spells` / `res.job_abilities` / `res.jobs` reads
- cache shape and lifecycle if present

Functions:

- `get_spell_resource`
- `get_ja_resource`
- `job_id_by_short`

Risks:

- wrong resource match changes all readiness behavior.
- cache mutation can leak between fixtures/runs.
- resource lookup fallbacks can hide missing test data.

### 3.2 Spell usability lane

Scope:

- learned/known flags
- job/subjob eligibility
- spell usability by current job

Functions:

- `spell_known_flag`
- `spell_usable_by_current_job`
- `spell_known_and_usable`

Risks:

- false known/usable means invalid spell proposals.
- false blocked means missed healing/maintenance/dispel opportunities.

### 3.3 Spell/JA readiness lane

Scope:

- MP/resource checks
- recast checks
- target validity checks
- status/restriction checks
- range/front restrictions where applicable

Functions:

- `spell_ready`
- `ja_ready`
- `action_ready`

Risks:

- direct change in proposal eligibility.
- dispatch can be attempted when action is unavailable.
- readiness false negatives reduce automation coverage.

### 3.4 Cure readiness lane

Scope:

- available cure tier
- cure tier selection
- cure-related MP/known/usable gating

Functions:

- `available_cure_tier_max`
- `get_usable_cure_from_tier`

Risks:

- defensive proposal correctness.
- MP use.
- cure strength selection.

### 3.5 Action metadata lane

Scope:

- target mode
- status id
- duration
- range/effective range
- command-builder metadata dependencies

Functions:

- `action_status_id`
- `action_duration_seconds`
- `action_effective_range`
- `action_target_mode`

Extraction note:

- these helpers are already extracted into `uc_scheduler_action_metadata.lua` and consumed through wrappers in `unified_scheduler.lua`.

## 4. State/cache schemas to freeze

| Schema domain | Current owner | Intended future owner | Key shape | Value shape | Lifecycle/reset rules | Known consumers | Unknowns to inspect before movement |
|---|---|---|---|---|---|---|---|
| spell resource cache | `unified_scheduler.lua` (`spell_name_cache`) | readiness/resource lookup module (future) | lowercase normalized spell label | `res.spells` entry table | lazy-built on first use; explicit reset rules not documented | `get_spell_resource`, downstream readiness/metadata wrappers | verify reset triggers and stale-cache behavior |
| JA resource cache | `unified_scheduler.lua` (`ja_name_cache`) | readiness/resource lookup module (future) | lowercase normalized JA label | `res.job_abilities` entry table | lazy-built on first use; explicit reset rules not documented | `get_ja_resource`, downstream readiness/metadata wrappers | verify reset triggers and cache invalidation expectations |
| job lookup cache | none observed / lookup-only | none observed / possible future optional index | n/a | n/a | n/a | `job_id_by_short` wrapper reads `res.jobs:with` directly | confirm no hidden memoization elsewhere |
| recast data inputs | runtime Windower reads | deterministic `deps` stub contract in replay | spell/JA recast id keys (numeric expected) | recast remaining numeric | per-read runtime snapshot; no local cache | `spell_ready`, `ja_ready` | define strict key typing and missing-key semantics in fixtures |
| MP/player state inputs | runtime Windower reads | deterministic `deps.windower` fixture stubs | player vitals/status fields | numeric/status fields | per-read runtime snapshot; no local cache | `spell_ready`, `ja_ready`, spell usability | confirm fallback defaults are intentional and parity-covered |
| status/buff restriction inputs | runtime Windower reads + known spell flags | deterministic fixture stubs | spell id / status values | bool/numeric flags | per-read runtime snapshot | `spell_known_and_usable`, `ja_ready` | capture all restriction reasons into fixture matrix |
| target/mob/range inputs | runtime Windower reads | deterministic fixture stubs | mob id and target selectors | mob table with `distance`,`hpp`,`spawn_type`,`valid_target` | per-read runtime snapshot | `ja_ready`, range/front checks | freeze minimal required mob schema for replay |
| readiness decision result object | none explicit (tuple returns) | future normalized adapter result detail | tuple `(ok, reason[, action_kind])` today | reason string + action kind for `action_ready` | immediate return; no stored cache | proposal collectors, defensive paths | define normalized shape for replay adapters without changing runtime behavior |

If no explicit cache exists:

- job lookup cache is currently `none observed / lookup-only`.
- this must be re-verified before any extraction by direct code inspection of new/adjacent readiness modules.

## 5. Readiness decision contract

Proposed normalized readiness result contract for future adapters/harness work:

```lua
{
  ok = true or false,
  action_name = "string",
  action_kind = "spell" or "ja" or "unknown",
  reason = nil or "string",
  detail = {},
  resource = {},
  recast_remaining = nil or number,
  mp_required = nil or number,
  mp_available = nil or number,
  target_id = nil or number,
  target_name = nil or string,
}
```

Contract notes:

- this is a replay/adapter normalization contract, not a runtime return-shape change.
- runtime readiness functions currently return tuple-style values; adapters must map tuple outputs into this normalized contract deterministically.
- `reason` strings must preserve existing blocking taxonomy to prevent false parity.
- `detail` must capture lane-relevant context used for triage (for example `missing_dep_path`, `recast_id`, `status`, `range`, `front_arc_required`).

## 6. Wrapper vs owned readiness boundaries

Wrapper/extracted helpers:

- `spell_known_flag` -> `uc_scheduler_action_metadata.lua`
- `job_id_by_short` -> `uc_scheduler_action_metadata.lua`
- `action_status_id` -> `uc_scheduler_action_metadata.lua`
- `action_duration_seconds` -> `uc_scheduler_action_metadata.lua`
- `action_effective_range` -> `uc_scheduler_action_metadata.lua`
- `action_target_mode` -> `uc_scheduler_action_metadata.lua`

Still-owned readiness/resource-cache logic in `unified_scheduler.lua`:

- `get_spell_resource`
- `spell_usable_by_current_job`
- `spell_known_and_usable`
- `get_ja_resource`
- `spell_ready`
- `ja_ready`
- `action_ready`
- `available_cure_tier_max`
- `get_usable_cure_from_tier`

Boundary rule:

- do not treat wrapper extraction as readiness-lane extraction completion.
- readiness ownership remains local while gating/caches and runtime-read dependencies remain local.

## 7. Validation requirements before any movement

Required before attempting runtime movement of owned readiness/resource-cache functions:

- fixture coverage rows for all readiness IDs and dependent shared IDs are `CLEAR` in `docs/replay_fixture_coverage_matrix.md`.
- lane-specific fail-fast fixtures for missing deps/schema violations are in place and passing.
- side-effect guard strict-mode parity fixtures confirm zero prohibited side effects.
- deterministic repeat-run evidence (`S8`) for readiness-sensitive fixtures.
- old-vs-new parity report marked `CONFORMANCE_APPROVED` with no unresolved readiness mismatches.

Additional readiness-specific requirements:

- explicit fixture matrix for spell/JA recast, MP gates, status restrictions, target validity, range/front-arc checks.
- explicit fixture matrix for cure tier fallback behavior and minimum-tier floor behavior.
- key-type and semantic preservation fixtures (`nil` vs `false`, numeric-key integrity).

## 8. Replay fixture requirements for readiness lanes

Minimum fixture classes required for readiness/resource-cache movement readiness:

- resource lookup positive fixtures:
  - canonical spell name hit
  - normalized spell name hit
  - canonical JA name hit
  - normalized JA name hit
- resource lookup negative fixtures:
  - unknown spell
  - unknown JA
  - missing resource table/dependency
- spell usability fixtures:
  - known + usable
  - known + not usable by job
  - unknown/not learned
- spell readiness fixtures:
  - recast blocked
  - MP blocked
  - no player blocked
  - pass case
- JA readiness fixtures:
  - JA not owned
  - status blocked
  - target invalid blocked
  - out-of-range blocked
  - front-arc blocked
  - recast blocked
  - pass case
- action readiness branch fixtures:
  - spell branch selected
  - JA branch selected
  - unknown action blocked
- cure readiness fixtures:
  - highest available tier
  - fallback to lower tier
  - no usable tier

## 9. Dependencies to freeze

High-risk dependency boundaries to freeze before movement:

- `windower.ffxi.get_player`
- `windower.ffxi.get_spells`
- `windower.ffxi.get_spell_recasts`
- `windower.ffxi.get_abilities`
- `windower.ffxi.get_ability_recasts`
- `windower.ffxi.get_mob_by_id`
- `windower.ffxi.get_mob_by_target`
- `res.spells`
- `res.job_abilities`
- `res.jobs`
- `_libs.lor.resources.lc_res` fallback lookups

Freeze rule:

- any dependency contract change requires documented comparator/fixture update first.

## 10. Known high-risk mismatch classes

- resource resolution drift (wrong spell/JA mapping).
- learned/usable eligibility drift (job id and known-flag handling).
- recast/MP/status gate drift.
- target validation/range/front gating drift for JA.
- tuple-to-normalized adapter mapping drift.
- cache lifecycle leakage across runs.

These mismatch classes are conformance-blocking until resolved.

## 11. Non-goals and stop conditions

This design does not permit moving:

- `spell_ready`
- `ja_ready`
- `action_ready`
- `p1_collect_proposals`
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `p1_run_dry`
- `dispatch_selected_plan`
- `run_movement_coordinator_tick`
- any direct side-effect owner

No immediate provider extraction is allowed.

No runtime movement is authorized by this document.

## 12. Recommended next tasks

1. Docs-only readiness fixture matrix document that maps each readiness failure reason to explicit fixture names.
2. Docs-only normalized readiness reason-code catalog with stable code-to-condition mapping.
3. Docs-only replay adapter mapping note for tuple readiness returns to normalized readiness contract.
4. Create non-runtime readiness validator/comparator skeleton only after policy docs are approved.
5. Revisit readiness/resource cache reset lifecycle design before any stateful runtime movement.

## 13. Validation snapshot

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
- only `docs/readiness_resource_cache_ownership_design.md` was created for this task
