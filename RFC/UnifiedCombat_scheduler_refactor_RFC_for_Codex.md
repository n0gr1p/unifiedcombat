# RFC: UnifiedCombat Scheduler Ownership Refactor and Legacy Cutover Plan

**Status:** Draft for Codex implementation  
**Primary audience:** Codex / code agent running GPT-5.3 Codex  
**Repository:** `UnifiedCombat` Windower addon  
**Authoring context:** Generated from review of `UnifiedCombat.zip` uploaded by Peter  
**Intended use:** Feed this document to Codex as the top-level implementation guide. Use individual task slices from this RFC as separate Codex prompts to avoid context-window overload.

---

## 0. Executive summary

UnifiedCombat began as a single-threaded, mostly linear combat tool. It has grown into a multi-domain runtime with combat, defensive, maintenance, movement, follow, pathing, targeting, add control, packet observation, UI, and remote state concerns.

The current codebase already contains a strong scheduler design direction in these documents:

- `docs/unified_scheduler_rfc.md`
- `docs/unified_scheduler_phase1_amendment.md`
- `docs/unified_scheduler_design.md`
- `docs/scheduler_work_tracking.md`
- `docs/core_vs_scheduler_gap_checklist.md`
- `docs/movement_coordinator_implementation_checklist.md`

This RFC does **not** replace those specs. It extends them with a concrete, small-task refactor/cutover plan intended for Codex.

The target architecture is:

```text
Windower events
  -> runtime engine tick
  -> one tick-stable world/context snapshot
  -> scheduler collects proposals from providers
  -> scheduler validates/scores/selects exactly one primary action plan
  -> dispatcher is the only module allowed to perform side effects
  -> locks/pending ledger dedupe stale or repeated action attempts
```

The main refactor objective is to move from the current hybrid state:

```text
providers propose
scheduler selects
scheduler sometimes directly dispatches
movement coordinator directly moves
core sometimes still dispatches
follow/pathing can directly move
legacy fallback can still act
```

Into the target state:

```text
providers propose only
scheduler arbitrates only
movement coordinator owns only movement coordination rules, or emits dispatcher requests through one API
one dispatcher performs all side effects
one lock/pending subsystem governs duplicate/stale execution
legacy fallback is removed per domain after parity validation
```

The purpose of this work is **maintainability and ownership clarity**, not true parallelism. Lua/Windower remains cooperative/single-threaded. The win comes from reducing hidden side effects and making every domain own its proposal generation while one authority owns execution.

---

## 1. Repository snapshot observed during review

### 1.1 Key active files

Observed active files and approximate responsibility:

| File | Approx. role | Current risk |
| --- | --- | --- |
| `UnifiedCombat.lua` | Addon entrypoint, settings defaults, event registration, global hooks, profile handling | Event registration is centralized, but global callbacks bridge to both core and scheduler. |
| `unified_engine.lua` | Runtime tick loop, scheduler invocation, overlay rendering, fallback to core tick | Still decides when core fallback can run based on dark-launch flags. |
| `unified_scheduler.lua` | Scheduler, providers, ranking, dispatch, locks, pending, enemy effects, party IPC, diagnostics | Too large and overloaded; ~5,300 lines and many responsibilities. |
| `unified_combat_core.lua` | Legacy/core combat logic, movement helpers, targeting/tank/pull behavior, scheduler helper exports | Still contains direct side effects and scheduler helper bridge functions. |
| `uc_party_follow.lua` | Party follow, IPC, run/stop behavior | Direct movement side effects exist. Must be handled carefully. |
| `uc_pathing.lua` | Path follow/recording movement | Direct movement side effects exist. |
| `uc_add_control.lua` | Add targeting/retarget action support | Direct attack/target side effects exist. |
| `uc_cor_maintenance.lua` | COR maintenance decision support | Should remain proposal/support logic where possible. |
| `uc_enemy_effect_tracker.lua` | Enemy effect tracking support | Candidate for extraction or consolidation with scheduler effect state. |
| `remote_bridge.lua` | External UI / session state bridge | Includes scheduler state exposure; should not own core decisions. |
| `melee_engine.lua`, `dd2_engine.lua`, `dd2_module.lua` | Legacy engines/modules | Should not be expanded unless a task explicitly targets legacy parity or removal. |

### 1.2 Direct side-effect inventory observed

The following files contain direct side-effect calls such as `windower.send_command`, `windower.ffxi.run`, or `uc_settarget.select_by_id`:

```text
unified_scheduler.lua       direct side effects observed
unified_combat_core.lua     direct side effects observed
uc_party_follow.lua         direct movement side effects observed
uc_pathing.lua              direct movement side effects observed
uc_add_control.lua          direct target/attack side effects observed
remote_bridge.lua           direct reload command observed
melee_engine.lua            legacy direct side effects observed
dd2_engine.lua              legacy direct side effects observed
dd2_module.lua              legacy direct side effects observed
lor/lor_actor.lua           library movement/command helpers observed
```

This RFC focuses first on the active `UnifiedCombat.lua` -> `unified_engine.lua` -> `unified_scheduler.lua` -> `unified_combat_core.lua` runtime path. Do **not** begin by rewriting legacy engines unless specifically assigned.

### 1.3 Current runtime shape observed

`UnifiedCombat.lua` registers Windower events and forwards observations into core and scheduler:

- `load`
- `incoming chunk`
- `ipc message`
- `outgoing chunk`
- `prerender`
- `job change`
- `zone change`
- `unload`
- `logout`
- `status change`
- `addon command`
- `login`

`unified_engine.lua` owns the 5 Hz engine cadence through `coroutine.schedule(tick, engine.tick_interval)` with `engine.tick_interval = 0.20`.

`unified_engine.lua` calls:

```lua
scheduler.process_tick({
  now = now,
  next_defensive_at = engine.next_defensive_at,
  next_maintenance_at = engine.next_maintenance_at,
})
```

Then it may fall back to:

```lua
do_active_combat_tick()
```

when scheduler domains are not fully owned.

`unified_scheduler.process_tick()` currently does multiple things in one function:

1. updates scheduler settings/debug flags
2. broadcasts party state IPC
3. handles emergency doom-water path
4. runs dry-run proposal/ranking path
5. tries dark-launch dispatch path
6. runs movement coordinator tick
7. may run legacy defensive provider path
8. updates globals/overlay state

This is the core hybrid area to refactor.

---

## 2. Problem statement

The current implementation is difficult to reason about because behavior ownership is split across multiple layers:

- Some domains generate proposals.
- Some scheduler code directly dispatches selected actions.
- The movement coordinator directly calls movement side effects.
- Core still contains direct execution paths and scheduler helper functions.
- Follow and pathing can move the character outside the ranked scheduler path.
- Legacy fallback paths still exist and can be active depending on settings.
- State is communicated through many `_G.UC_*` globals.

This creates these maintenance risks:

1. **Action ownership ambiguity**  
   It is hard to know whether scheduler, core, follow, pathing, or add-control owns the current action.

2. **Movement/cast contention**  
   Movement can accidentally interrupt casting or create stutter if multiple paths issue run/stop commands.

3. **Duplicate or stale dispatch**  
   A selected action may be repeated before packet/action state catches up.

4. **Target churn**  
   Retargeting can be triggered by competing paths.

5. **Provider migration drift**  
   A provider may appear scheduler-owned while still retaining a direct dispatch path somewhere else.

6. **Context-window overload for code agents**  
   `unified_scheduler.lua` is too large for safe all-at-once modification.

---

## 3. Goals

### 3.1 Architecture goals

- Establish one runtime authority for action dispatch.
- Keep provider modules focused on proposal/intent generation.
- Keep scheduler focused on collection, validation, scoring, selection, and planning.
- Keep side effects behind a dispatcher API.
- Keep duplicate suppression, pending action lifecycle, and locks in one module.
- Remove legacy fallback paths domain-by-domain only after parity validation.
- Preserve current runtime behavior unless a task explicitly changes behavior.

### 3.2 Code-agent goals

- Give Codex small, bounded tasks.
- Avoid broad rewrites.
- Avoid hallucinated APIs.
- Require validation after each task.
- Require an explicit file list for each task.
- Require behavior-preserving extraction before behavior change.
- Preserve existing settings and profile compatibility.

### 3.3 Player/runtime goals

- Keep 5 Hz engine cadence stable.
- Use wall-clock time via `socket.gettime`, not `os.clock`, for scheduler decisions.
- Prevent action spam.
- Prevent movement from self-interrupting spells.
- Keep debug observability useful in-game and through remote bridge.
- Allow domain-by-domain rollback through existing flags until cutover is proven.

---

## 4. Non-goals

These are explicitly out of scope for the initial refactor sequence:

- True Lua parallelism or OS-threaded addons.
- Replacing Windower event architecture.
- Large behavior rewrite of combat decisions.
- Full rewrite of `unified_combat_core.lua`.
- Full deletion of legacy `melee_engine.lua`, `dd2_engine.lua`, or `dd2_module.lua` before active runtime cutover is proven.
- UI redesign.
- Optimization/learning/prediction systems.
- Multi-action macro choreography beyond the existing `prelude + primary` plan model.

---

## 5. Terms and definitions

### 5.1 Runtime

The runtime is the high-level engine loop responsible for ticking the system at a stable cadence.

Current primary file:

```text
unified_engine.lua
```

### 5.2 Scheduler

The scheduler is the central arbiter. It should:

- build or receive tick context
- collect proposals
- validate proposals
- score proposals
- select a winner
- build a dispatch plan
- ask the dispatcher to execute the plan
- update observability state

The scheduler should **not** directly call `windower.send_command`, `windower.ffxi.run`, or direct target selection after the dispatcher exists.

### 5.3 Provider

A provider generates proposals only.

Examples:

- defensive/internal
- defensive/healbot bridge
- combat offense
- tank enmity
- enemy buff removal
- target control
- pull control
- maintenance/COR
- maintenance/GEO
- maintenance/BRD
- movement/follow/pathing if later converted to proposal form

Provider contract:

```lua
collect(ctx, out) -> nil
```

or:

```lua
collect(ctx) -> proposals
```

The current implementation often appends proposals to `out`; preserve existing style unless a task explicitly changes the interface.

### 5.4 Proposal / intent

A proposal is a candidate action. It describes what should happen and why, but it should not execute the action.

Use the schema in `docs/unified_scheduler_phase1_amendment.md` as the normative source. Do not rename fields casually.

Important fields include:

- `proposal_id`
- `family_id`
- `provider`
- `action_type`
- `action_name`
- `target_kind`
- `target_id`
- `target_name`
- `priority_band`
- `urgency`
- `created_at`
- `expires_at`
- `commit_deadline`
- `movement_policy`
- `range_policy`
- `recast_key`
- `duplicate_suppression_key`
- `lock_class`
- `expected_ack`
- `expected_effect`
- `reason_code`
- `detail`
- temporary compatibility field: `legacy_command`

### 5.5 Dispatch plan

A dispatch plan is the scheduler-selected execution plan. It may have:

- zero or one prelude
- zero or one primary action

Allowed Phase 1 prelude types from the existing amendment:

- `none`
- `stop`
- `retarget`
- `face`

### 5.6 Dispatcher

The dispatcher is the only module that may perform action side effects.

Side effects include:

- `windower.send_command(...)`
- `windower.ffxi.run(...)`
- `uc_settarget.select_by_id(...)`
- `input /attack ...`
- `input /ma ...`
- `input /ja ...`
- `input /ws ...`
- target/attack commands

The dispatcher must perform commit-time validation through the scheduler/locks API before sending a command.

### 5.7 Pending ledger

The pending ledger tracks selected/sent/acknowledged/effect/complete/failed actions so the system does not dispatch duplicates while game state is still catching up.

### 5.8 Locks

Locks express short-lived state constraints:

- `movement_lock`
- `cast_lock`
- `target_lock`
- `duplicate_lock`
- `movement_goal_hold`
- `zone_guard_lock`

The existing amendment remains the source of truth for lock semantics.

### 5.9 Legacy fallback

Any direct execution path outside the scheduler/dispatcher architecture is considered legacy fallback once that domain is migrated.

Legacy fallback should remain operational only until that domain is proven scheduler-owned.

---

## 6. Non-negotiable invariants

These are the rules Codex must preserve or move toward.

### 6.1 One executor rule

After dispatcher extraction, only the dispatcher may call direct Windower side effects for scheduler-managed domains.

Forbidden outside dispatcher for migrated domains:

```lua
windower.send_command(...)
windower.ffxi.run(...)
uc_settarget.select_by_id(...)
```

Temporary exceptions must be documented in an allowlist.

### 6.2 Provider purity rule

Providers may inspect state and emit proposals. Providers may not dispatch commands once their domain is scheduler-owned.

### 6.3 One primary action per tick

The scheduler may execute at most one selected primary action per tick. A legal plan may include one prelude plus one primary if the existing plan model permits it.

### 6.4 No stale action rule

Every dispatch candidate must have:

- `created_at`
- `expires_at` or an equivalent TTL check
- `duplicate_suppression_key` where repeat risk exists

The dispatcher must reject expired or duplicate actions.

### 6.5 Wall-clock time rule

Scheduler, movement, locks, cooldown, and pending lifecycle timing must use `socket.gettime` or the existing `now_s()` wrapper that resolves to `socket.gettime`.

Do not introduce new `os.clock()` timing for runtime scheduling.

### 6.6 Behavior preservation during extraction

Extraction tasks should move code without changing logic. Behavior changes should be separate tasks with explicit acceptance criteria.

### 6.7 Settings compatibility

Existing settings/profile keys must continue to load.

Relevant current keys include:

```text
domain_combat_enabled
domain_defensive_enabled
domain_movement_enabled
domain_maintenance_enabled
domain_follow_enabled
scheduler_dark_launch_combat
scheduler_dark_launch_defensive
scheduler_dark_launch_movement
scheduler_dark_launch_maintenance
```

Do not remove or rename these in early refactor tasks.

### 6.8 Debug compatibility

Keep existing `_G.UC_*` debug globals working until a replacement is explicitly implemented.

Examples:

```text
UC_LAST_BLOCK_REASON
UC_LAST_SCHED_ACTION
UC_SCHED_P1_SELECTED_PROVIDER
UC_SCHED_P1_SELECTED_FAMILY
UC_SCHED_P1_PENDING_STATE
UC_SCHED_P1_LOCK_SUMMARY
UC_MOVEMENT_MODE
UC_MOVEMENT_BLOCK_REASON
```

---

## 7. Target module structure

The desired final-ish module layout is:

```text
UnifiedCombat.lua
  Windower event registration, settings/profile load/save, global hook setup only.

unified_engine.lua
  Engine lifecycle and 5 Hz tick scheduling only.

uc_time.lua
  Wall-clock time wrapper and fail-fast behavior for missing socket.gettime.

uc_world_snapshot.lua
  Tick-stable context builder.

uc_scheduler.lua
  Small coordinator for collect -> validate -> score -> select -> plan -> dispatch.

uc_scheduler_proposals.lua
  Proposal constructors, normalization, schema validation helpers.

uc_scheduler_ranker.lua
  Validation, rejection reason taxonomy, score formula, deterministic tie-breaks.

uc_scheduler_locks.lua
  Pending action ledger, locks, duplicate suppression, action state tracking.

uc_dispatcher.lua
  The only module for Windower command/run/target side effects.

uc_scheduler_observability.lua
  Overlay/remote state snapshots, recent rejected candidates, top candidates.

uc_enemy_effect_state.lua
  Enemy dispellable effect table state and packet/catalog ingestion.

providers/
  Optional later directory if the repo style allows it.
  Otherwise keep provider modules at root with uc_provider_* names.
```

Important: this is a target. Do not attempt to create the entire tree in one Codex task.

---

## 8. Current-to-target responsibility mapping

### 8.1 `UnifiedCombat.lua`

Current responsibilities include:

- settings defaults
- profile handling
- Windower event registration
- global hook definitions
- action listener registration
- engine start/stop commands
- domain helper globals

Target:

- keep Windower event registration here
- keep settings/profile here unless a later task extracts config
- do not add scheduler logic here
- do not add provider logic here

### 8.2 `unified_engine.lua`

Current responsibilities include:

- 5 Hz tick loop
- scheduler call
- overlay rendering
- domain fallback logic

Target:

- lifecycle/tick only
- call scheduler once per tick
- eventually avoid core fallback once domains are cut over
- keep overlay rendering until observability extraction task

### 8.3 `unified_scheduler.lua`

Current responsibilities include too much:

- time wrapper
- action state
- pending ledger
- locks
- enemy effect tracking
- party state IPC
- defensive helpers
- provider collection
- validation/scoring/ranking
- dispatch/dark launch execution
- movement coordinator tick
- debug overlay state
- packet/action observation

Target:

- become a small coordinator
- delegate locks/pending to `uc_scheduler_locks.lua`
- delegate dispatch to `uc_dispatcher.lua`
- delegate proposal schema helpers to `uc_scheduler_proposals.lua`
- delegate scoring/ranking to `uc_scheduler_ranker.lua`
- delegate enemy effect state to `uc_enemy_effect_state.lua`
- eventually move provider-specific logic out

### 8.4 `unified_combat_core.lua`

Current responsibilities include legacy behavior and helper exports.

Target:

- during transition, keep core helper functions used by scheduler
- do not add new direct dispatch behavior
- gradually move domain ownership to providers/dispatcher
- suppress or remove core direct dispatch per domain after validation

### 8.5 Movement-related modules

Current state based on checklist:

- movement proposal arbitration was removed/disabled
- movement coordinator tick exists
- `scheduler_dark_launch_movement` gates coordinator behavior
- `uc_party_follow.lua` and `uc_pathing.lua` still contain direct movement calls

Target:

- either keep movement coordinator as the sole movement side-effect owner behind dispatcher, or convert movement to dispatcher requests
- avoid multiple modules independently calling `windower.ffxi.run` in conflict
- preserve smooth follow/pathing behavior during transition

---

## 9. Codex implementation rules

Use this section verbatim in Codex prompts.

### 9.1 General agent rules

1. Do not rewrite broad areas of the codebase.
2. Do not invent APIs that are not present in the repo.
3. Before changing code, inspect the relevant functions and call sites.
4. Preserve existing behavior unless the task explicitly says to change behavior.
5. Prefer mechanical extraction over redesign.
6. Keep each task to the listed files unless a discovered call site requires a minimal additional change.
7. If a required function is missing, report it instead of guessing.
8. Do not rename settings keys unless the task explicitly says to migrate settings.
9. Do not delete legacy fallback paths until an explicit removal task.
10. Do not add `os.clock()` for runtime scheduling.
11. Do not add direct `windower.send_command`, `windower.ffxi.run`, or `uc_settarget.select_by_id` calls outside the dispatcher for migrated code.
12. Keep logs/debug globals compatible.
13. Update docs/checklists when a task changes architecture or ownership.
14. Run syntax validation where available.
15. Return a concise summary of files changed, behavior impact, and validation performed.

### 9.2 Validation commands

When available in the environment, run:

```bash
luac -p UnifiedCombat.lua unified_engine.lua unified_scheduler.lua unified_combat_core.lua
```

For new modules, include them:

```bash
luac -p uc_scheduler_locks.lua uc_dispatcher.lua uc_scheduler_ranker.lua uc_scheduler_proposals.lua
```

If `luac` is not installed, report that syntax validation could not be run. Do not pretend validation passed.

Useful static searches:

```bash
grep -R "windower.send_command\|windower.ffxi.run\|uc_settarget.select_by_id" -n --include='*.lua' .

grep -R "os.clock" -n --include='*.lua' .

grep -R "scheduler_dark_launch\|domain_.*_enabled" -n --include='*.lua' .
```

### 9.3 Required Codex response format

Each Codex task should end with:

```text
Changed files:
- ...

Behavior impact:
- None / expected specific change

Validation:
- ...

Notes / risks:
- ...
```

---

## 10. Refactor roadmap

The roadmap is split into small phases. Each task is intentionally narrow.

### Phase 0 — Baseline and guardrails

Purpose: make the current hybrid state visible before changing behavior.

Tasks:

- T0.1 Generate side-effect inventory doc.
- T0.2 Generate scheduler responsibility map.
- T0.3 Add/refresh architecture tracking doc.
- T0.4 Add static guard script or checklist for direct side effects.

### Phase 1 — Mechanical decomposition of `unified_scheduler.lua`

Purpose: reduce file size and cognitive load without behavior changes.

Suggested extraction order:

1. locks/pending/action state
2. proposal schema/helpers
3. ranking/validation/scoring
4. observability/reject/top candidate formatting
5. enemy effect state
6. party IPC state if still large

### Phase 2 — Dispatcher monopoly

Purpose: create one side-effect API and route scheduler dispatch through it.

Tasks:

- create `uc_dispatcher.lua`
- move scheduler dark-launch command emission into dispatcher
- add dispatcher validation and action mark hooks
- create temporary allowlist for side effects not migrated yet

### Phase 3 — Provider purity

Purpose: make each provider own only proposal generation.

Tasks:

- extract defensive proposal provider
- extract combat offense provider
- extract tank enmity provider
- extract enemy buff removal provider
- extract maintenance/COR provider adapter
- keep core helper calls temporarily if needed, but do not dispatch inside providers

### Phase 4 — Movement ownership cleanup

Purpose: eliminate hidden movement conflicts.

Tasks:

- route movement coordinator side effects through dispatcher or a movement dispatcher facade
- document temporary exceptions for `uc_party_follow.lua` and `uc_pathing.lua`
- decide whether follow/pathing remain independent movement systems or become scheduler/dispatcher-owned domains
- preserve smooth follow behavior

### Phase 5 — Domain cutover

Purpose: remove dark-launch language and legacy fallback domain-by-domain.

Tasks:

- rename conceptual docs from dark-launch to ownership/cutover where appropriate
- keep actual setting keys until profile migration exists
- validate each domain with acceptance tests
- remove core fallback for one domain at a time

### Phase 6 — Cleanup and simplification

Purpose: remove dead code once safety is proven.

Tasks:

- delete unreachable legacy scheduler branches
- remove duplicate helpers
- collapse debug globals only after bridge/UI replacement exists
- archive old docs or mark superseded

---

## 11. Task backlog with small Codex prompts

Each task below is designed to be pasted into Codex separately. Do not run multiple tasks at once unless explicitly combining trivial doc-only updates.

---

### T0.1 — Create side-effect inventory document

**Type:** docs/static analysis  
**Risk:** low  
**Behavior change:** none

**Files to inspect:**

- all `*.lua`

**Files to change:**

- create `docs/side_effect_inventory.md`

**Prompt for Codex:**

```text
You are working in the UnifiedCombat Windower addon repo.

Task: Create docs/side_effect_inventory.md documenting all current direct side-effect call sites.

Direct side effects include:
- windower.send_command(...)
- windower.ffxi.run(...)
- uc_settarget.select_by_id(...)
- direct input /attack, /ma, /ja, /ws command construction

Do not change runtime code.

Inspect all Lua files. Group findings by file and by domain if obvious:
- scheduler
- core
- movement/follow/pathing
- add control/targeting
- legacy engines
- remote/UI utilities
- libraries

For each call site, include:
- file
- approximate line/function
- side-effect type
- likely domain
- whether it appears active runtime, legacy, helper/library, or unknown
- recommended migration target: dispatcher, movement dispatcher, keep temporarily, or legacy ignore

Do not infer behavior beyond what is visible in code. Mark uncertain cases as uncertain.

Validation:
- No runtime code changes.
- The doc should be useful as a migration allowlist/checklist.
```

**Acceptance criteria:**

- New doc exists.
- No runtime files changed.
- All obvious side-effect calls are listed or summarized.

---

### T0.2 — Create scheduler responsibility map

**Type:** docs/static analysis  
**Risk:** low  
**Behavior change:** none

**Files to inspect:**

- `unified_scheduler.lua`
- `unified_engine.lua`
- `unified_combat_core.lua`
- existing scheduler docs

**Files to change:**

- create `docs/scheduler_responsibility_map.md`

**Prompt for Codex:**

```text
Task: Create docs/scheduler_responsibility_map.md.

The goal is to document current responsibilities inside unified_scheduler.lua before extraction.

Inspect unified_scheduler.lua and group functions into categories:
- time/source helpers
- logging/diagnostics
- action state and pending lifecycle
- locks and duplicate suppression
- enemy effect tracking / dispel state
- party state IPC
- defensive helpers
- provider collection functions
- validation/scoring/ranking functions
- dispatch plan functions
- direct dark-launch dispatch functions
- movement coordinator functions
- packet/action observation functions
- public scheduler API functions

For each category include:
- function names
- current responsibility
- proposed future module name
- extraction priority high/medium/low

Do not change runtime code.
```

**Acceptance criteria:**

- New doc exists.
- It maps function names to future modules.
- No runtime behavior changes.

---

### T0.3 — Add refactor tracking checklist

**Type:** docs  
**Risk:** low  
**Behavior change:** none

**Files to change:**

- create `docs/scheduler_refactor_cutover_tracking.md`

**Prompt for Codex:**

```text
Task: Create docs/scheduler_refactor_cutover_tracking.md.

Use the existing docs/scheduler_work_tracking.md style.

This tracking doc should cover:
- Phase 0 baseline docs
- Phase 1 scheduler decomposition
- Phase 2 dispatcher monopoly
- Phase 3 provider purity
- Phase 4 movement ownership cleanup
- Phase 5 domain cutover
- Phase 6 cleanup

Use status values:
- TODO
- IN_PROGRESS
- DONE
- BLOCKED

Do not mark implementation tasks DONE unless already visibly implemented in code.

Do not change runtime code.
```

**Acceptance criteria:**

- Tracking doc exists.
- It is conservative about DONE status.

---

### T1.1 — Extract action state, pending lifecycle, locks, and duplicate suppression

**Type:** behavior-preserving mechanical extraction  
**Risk:** medium  
**Behavior change:** none intended

**Files to inspect:**

- `unified_scheduler.lua`
- `docs/unified_scheduler_phase1_amendment.md`

**Files to change:**

- create `uc_scheduler_locks.lua`
- modify `unified_scheduler.lua`

**Candidate functions to extract from `unified_scheduler.lua`:**

- `action_state`
- `action_mark_sent`
- `action_mark_packet_start`
- `action_mark_packet_end`
- `action_is_acting`
- `action_dispatch_blocked`
- `p1_pending_is_live_state`
- `p1_update_pending_state`
- `p1_duplicate_suppressed`
- `p1_get_locks`
- `p1_hard_lock_reject`
- `p1_record_legacy_dispatch`
- `p1_pending_mark_complete`
- any directly required small helpers/state for the above

**Prompt for Codex:**

```text
Task: Mechanically extract scheduler action-state, pending lifecycle, locks, and duplicate suppression into a new module uc_scheduler_locks.lua.

This is behavior-preserving extraction only. Do not redesign lock semantics.

Steps:
1. Inspect the listed functions and their dependencies in unified_scheduler.lua.
2. Create uc_scheduler_locks.lua exposing equivalent functions.
3. Keep scheduler.phase1 state compatibility if existing code expects it.
4. Update unified_scheduler.lua to call the new module.
5. Preserve all _G.UC_* debug globals currently set by these paths.
6. Do not change proposal scoring, provider collection, dispatch behavior, or movement behavior.
7. Do not rename settings.

If a function has too many dependencies to safely extract, extract a smaller subset and document what remains.

Validation:
- Run luac -p on changed Lua files if luac is available.
- Search for duplicate local definitions left behind accidentally.
- Confirm no new windower.send_command or windower.ffxi.run calls were added.
```

**Acceptance criteria:**

- New module exists.
- `unified_scheduler.lua` is smaller.
- Existing public scheduler behavior should be unchanged.
- No new side effects added.

---

### T1.2 — Extract proposal normalization/schema helpers

**Type:** behavior-preserving extraction  
**Risk:** medium  
**Behavior change:** none intended

**Files to change:**

- create `uc_scheduler_proposals.lua`
- modify `unified_scheduler.lua`

**Candidate responsibilities:**

- numeric/default helpers for proposal fields
- urgency clamp
- malformed proposal validation helpers if separable
- proposal ID/family/duplicate key normalization helpers
- action command description helpers that do not dispatch

**Prompt for Codex:**

```text
Task: Extract proposal normalization/schema helper logic from unified_scheduler.lua into uc_scheduler_proposals.lua.

Do not change the proposal schema. The normative schema is docs/unified_scheduler_phase1_amendment.md.

This task should not move provider collection functions yet. It only extracts reusable proposal helper functions.

Preserve behavior exactly.

Do not introduce new field names unless they already exist in code.
Do not remove legacy_command compatibility.
Do not change scoring/ranking.
Do not change dispatch.

Validation:
- luac -p where available.
- Existing scheduler proposal collection should still work.
```

**Acceptance criteria:**

- Proposal helper module exists.
- Scheduler still uses same proposal fields.

---

### T1.3 — Extract validation, scoring, and ranking

**Type:** behavior-preserving extraction  
**Risk:** medium/high  
**Behavior change:** none intended

**Files to change:**

- create `uc_scheduler_ranker.lua`
- modify `unified_scheduler.lua`

**Candidate functions:**

- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- rejection reason counting helpers if needed
- tie-break helpers if embedded

**Prompt for Codex:**

```text
Task: Extract scheduler proposal validation, scoring, and ranking into uc_scheduler_ranker.lua.

This is behavior-preserving. Do not change priority bands, urgency formula, tie-break order, rejection reasons, or soft/hard lock semantics.

Inputs should be explicit where practical:
- ctx
- proposals
- locks module functions where needed

If ranker needs lock checks, import/use uc_scheduler_locks if it exists from prior task. If it does not exist, stop and report dependency missing rather than inventing behavior.

Do not change provider collection.
Do not change dispatch.
Do not change movement coordinator.

Validation:
- luac -p where available.
- Confirm ranked top candidate output remains structurally compatible with overlay/debug functions.
```

**Acceptance criteria:**

- Ranker module exists.
- Scheduler selection behavior is unchanged.

---

### T1.4 — Extract scheduler observability formatting

**Type:** behavior-preserving extraction  
**Risk:** low/medium  
**Behavior change:** none intended

**Files to change:**

- create `uc_scheduler_observability.lua`
- modify `unified_scheduler.lua`

**Candidate functions:**

- `p1_format_top3`
- `p1_format_top3_verbose`
- `p1_format_topn_lines`
- `p1_capture_topn_items`
- `p1_push_recent_rejects`
- `p1_reject_top`
- lock summary formatting if not extracted with locks
- debug overlay snapshot helpers if separable

**Prompt for Codex:**

```text
Task: Extract scheduler observability and formatting helpers into uc_scheduler_observability.lua.

Behavior-preserving only.

Do not change the shape of scheduler.get_debug_overlay() output.
Do not change remote_bridge behavior.
Do not rename _G.UC_* debug globals.
Do not change ranking/scoring.

Validation:
- luac -p where available.
- Grep for get_debug_overlay call sites and confirm compatibility.
```

**Acceptance criteria:**

- Observability module exists.
- Overlay/remote state shape remains compatible.

---

### T1.5 — Extract enemy effect state

**Type:** behavior-preserving extraction  
**Risk:** medium  
**Behavior change:** none intended

**Files to inspect:**

- `unified_scheduler.lua`
- `uc_enemy_effect_tracker.lua`
- `docs/enemy_buff_removal_implementation_checklist.md`
- `docs/ffxi_enemy_dispellable_buffs.json`

**Files to change:**

- create `uc_enemy_effect_state.lua` or extend `uc_enemy_effect_tracker.lua` if that is clearly the existing intended module
- modify `unified_scheduler.lua`

**Candidate functions:**

- enemy effect state map helpers
- enemy dispel attempt map helpers
- catalog ingestion helpers if separable
- overlay table generation if tightly coupled

**Prompt for Codex:**

```text
Task: Extract enemy effect/dispel state management out of unified_scheduler.lua.

Prefer creating uc_enemy_effect_state.lua unless uc_enemy_effect_tracker.lua already contains the exact target abstractions needed.

Preserve behavior. Do not change dispel decision logic or buff danger weighting.
Do not change the JSON data file.
Do not change packet parse semantics.
Do not change overlay output shape unless unavoidable; if unavoidable, document the exact difference.

Validation:
- luac -p where available.
- Confirm scheduler.on_incoming_chunk and scheduler.on_action still feed enemy effect state.
```

**Acceptance criteria:**

- Enemy effect state logic is isolated.
- Scheduler remains packet-observation compatible.

---

### T2.1 — Create dispatcher module shell

**Type:** new module, minimal integration  
**Risk:** medium  
**Behavior change:** none or minimal

**Files to change:**

- create `uc_dispatcher.lua`
- optionally modify `unified_scheduler.lua` to require it without using it broadly yet
- update docs/tracking

**Prompt for Codex:**

```text
Task: Create uc_dispatcher.lua as a shell module for scheduler-managed side effects.

Do not migrate existing dispatch yet except for adding the module and a no-op or thin wrapper interface.

The module should expose explicit functions such as:
- execute_plan(ctx, selected, plan, hooks)
- execute_primary(ctx, selected, primary, hooks)
- execute_prelude(ctx, selected, prelude, hooks)

But do not invent complex behavior yet. If existing scheduler dispatch is too coupled, create the module with documented TODOs and minimal safe helpers.

The dispatcher contract:
- This module will become the only place for windower.send_command, windower.ffxi.run, and uc_settarget.select_by_id for scheduler-owned domains.
- It must support commit-time validation hooks supplied by scheduler.
- It must support action mark hooks supplied by locks/pending module.

Do not change runtime behavior in this task.

Validation:
- luac -p where available.
```

**Acceptance criteria:**

- Dispatcher module exists.
- No broad behavior change.
- Contract is documented in code comments.

---

### T2.2 — Route scheduler dark-launch primary dispatch through dispatcher

**Type:** controlled behavior-preserving refactor  
**Risk:** high  
**Behavior change:** should be none for supported dark-launch paths

**Files to change:**

- `uc_dispatcher.lua`
- `unified_scheduler.lua`

**Prompt for Codex:**

```text
Task: Move scheduler dark-launch primary action command emission from unified_scheduler.lua into uc_dispatcher.lua.

Scope only scheduler dark-launch paths already present in p1_try_dark_launch_dispatch.
Do not migrate movement coordinator yet.
Do not migrate core fallback yet.
Do not migrate uc_party_follow or uc_pathing yet.

Preserve exact command strings and action_mark_sent behavior.
Preserve _G.UC_LAST_SCHED_ACTION values where practical.
Preserve existing block reasons.
Preserve commit-time revalidation behavior.

The scheduler should still select and build the plan.
The dispatcher should execute the side effect.

Validation:
- luac -p where available.
- Grep p1_try_dark_launch_dispatch and confirm direct windower.send_command calls were reduced or removed for migrated paths.
- Confirm no new duplicate dispatch path was introduced.
```

**Acceptance criteria:**

- Scheduler dark-launch action dispatch uses dispatcher.
- Command strings remain equivalent.
- Existing toggles still gate behavior.

---

### T2.3 — Add side-effect allowlist guard document

**Type:** docs/static guard  
**Risk:** low  
**Behavior change:** none

**Files to change:**

- create or update `docs/side_effect_inventory.md`
- create `docs/side_effect_allowlist.md`

**Prompt for Codex:**

```text
Task: Create docs/side_effect_allowlist.md.

The allowlist should list direct side-effect call sites that are temporarily allowed after dispatcher introduction.

For each allowlisted item include:
- file
- function/line approximate
- reason it remains direct
- migration target
- owner domain
- removal condition

Do not change runtime code.

Use docs/side_effect_inventory.md if it exists.
```

**Acceptance criteria:**

- Allowlist exists.
- Direct side effects outside dispatcher are no longer invisible.

---

### T2.4 — Route movement coordinator run/stop through dispatcher facade

**Type:** controlled refactor  
**Risk:** high  
**Behavior change:** should be none if done carefully

**Files to inspect:**

- `unified_scheduler.lua`
- `unified_combat_core.lua`
- `uc_party_follow.lua`
- `uc_pathing.lua`
- `docs/movement_coordinator_implementation_checklist.md`

**Files to change:**

- `uc_dispatcher.lua`
- `unified_scheduler.lua`
- possibly `unified_combat_core.lua` only if required

**Prompt for Codex:**

```text
Task: Route movement coordinator side effects through the dispatcher or a dispatcher movement facade.

Scope:
- Only movement issued by scheduler movement coordinator / apply_movement_for_scheduler path.
- Do not refactor party follow or pathing direct movement in this task unless a tiny adapter is required.

Goal:
- The movement coordinator should no longer directly call windower.ffxi.run if the dispatcher facade can safely own it.
- Preserve movement block reasons and debug globals.
- Preserve cast freeze behavior.
- Preserve current movement_dark_launch gating.

If apply_movement_for_scheduler directly calls windower.ffxi.run internally and cannot be safely changed in one step, add a documented TODO and expose a narrower movement command abstraction instead of rewriting core movement behavior.

Validation:
- luac -p where available.
- Test by static grep that new movement side effects are centralized for the touched path.
```

**Acceptance criteria:**

- Scheduler-owned movement path is closer to dispatcher ownership.
- No follow/pathing rewrite yet.

---

### T3.1 — Extract defensive provider adapter

**Type:** provider extraction  
**Risk:** medium  
**Behavior change:** none intended

**Files to change:**

- create `uc_provider_defensive.lua`
- modify `unified_scheduler.lua`

**Candidate functions:**

- `p1_collect_defensive_internal`
- `p1_collect_defensive_healbot`
- defensive proposal construction helpers if tightly coupled

**Prompt for Codex:**

```text
Task: Extract defensive proposal collection from unified_scheduler.lua into uc_provider_defensive.lua.

Provider purity rule:
- The provider emits proposals only.
- It does not dispatch commands.
- It does not acquire locks.

Preserve proposal fields exactly.
Preserve internal and HealBot provider behavior.
Do not change defensive action selection/scoring.
Do not change try_internal_defensive_action legacy fallback in this task unless only imports need updating.

Validation:
- luac -p where available.
- Grep new provider for windower.send_command and windower.ffxi.run; there should be none.
```

**Acceptance criteria:**

- Defensive proposal collection lives in provider module.
- No direct dispatch in provider.

---

### T3.2 — Extract combat offense provider adapter

**Type:** provider extraction  
**Risk:** medium/high  
**Behavior change:** none intended

**Files to change:**

- create `uc_provider_combat.lua`
- modify `unified_scheduler.lua`

**Candidate functions:**

- `p1_collect_combat_offense`
- `p1_collect_combat_engage`
- `p1_collect_combat_ja`
- helper calls to core selection functions as needed

**Prompt for Codex:**

```text
Task: Extract combat proposal collection into uc_provider_combat.lua.

Scope only proposal collection. Do not move dispatch.
Provider must not call windower.send_command, windower.ffxi.run, or uc_settarget.select_by_id.

Preserve existing proposal fields and priorities.
Preserve scheduler_dark_launch_combat behavior.
Preserve combat-first implementation sequencing if present.

If helper functions are still in unified_combat_core.lua, call them rather than duplicating behavior.

Validation:
- luac -p where available.
- Grep provider for direct side effects; none should exist.
```

**Acceptance criteria:**

- Combat proposals are generated by provider module.
- Dispatch remains centralized.

---

### T3.3 — Extract tank enmity provider adapter

**Type:** provider extraction  
**Risk:** medium/high  
**Behavior change:** none intended

**Files to inspect:**

- `unified_scheduler.lua`
- `unified_combat_core.lua`
- `docs/tank_enmity_implementation_checklist.md`

**Files to change:**

- create `uc_provider_tank_enmity.lua` or include in `uc_provider_combat.lua` if simpler
- modify `unified_scheduler.lua`

**Prompt for Codex:**

```text
Task: Extract tank enmity proposal collection from unified_scheduler.lua.

Preserve current behavior:
- tank enmity proposals have high priority within combat domain as currently implemented.
- target prep/range approach/spell settle behavior must not change in this task.
- core.select_tank_enmity_for_scheduler may remain the source of truth if that is current behavior.

Provider must emit proposals only.
No command dispatch.
No movement side effects.
No target selection side effects.

Validation:
- luac -p where available.
- No direct windower side effects in provider.
```

**Acceptance criteria:**

- Tank enmity proposal logic isolated.
- Existing dark-launch dispatch still works.

---

### T3.4 — Extract maintenance provider adapter

**Type:** provider extraction  
**Risk:** medium  
**Behavior change:** none intended

**Files to inspect:**

- `unified_scheduler.lua`
- `uc_cor_maintenance.lua`
- `uc_hb_buff_maint.lua`

**Files to change:**

- create `uc_provider_maintenance.lua`
- modify `unified_scheduler.lua`

**Prompt for Codex:**

```text
Task: Extract maintenance proposal collection into uc_provider_maintenance.lua.

Scope:
- COR maintenance proposals currently emitted by scheduler.
- GEO/BRD scaffolding if present in current p1_collect_maintenance.

Do not change COR roll decision behavior.
Do not change incoming chunk hook behavior for uc_cor_maintenance.
Do not change settings keys cor_roll_1, cor_roll_2, scheduler_dark_launch_maintenance, or related UI/remote snapshot behavior.

Provider emits proposals only. No command dispatch.

Validation:
- luac -p where available.
- Grep provider for direct side effects; none should exist.
```

**Acceptance criteria:**

- Maintenance proposals are generated outside main scheduler.
- COR maintenance behavior remains opt-in through existing setting.

---

### T3.5 — Extract target/pull/add-control provider adapters

**Type:** provider extraction  
**Risk:** high  
**Behavior change:** none intended

**Files to inspect:**

- `unified_scheduler.lua`
- `uc_add_control.lua`
- `uc_add_priority.lua`
- `uc_targeting_common.lua`
- `uc_fight_leader.lua`
- `uc_path_hunter.lua`

**Files to change:**

- create `uc_provider_target_control.lua`
- create `uc_provider_pull_control.lua` if needed
- modify `unified_scheduler.lua`

**Prompt for Codex:**

```text
Task: Extract target-control and pull-control proposal collection out of unified_scheduler.lua.

This task must preserve behavior and avoid direct side effects in providers.

Important:
- uc_add_control.lua currently contains direct attack/target side effects. Do not rewrite those in this task.
- Provider extraction should only move proposal-generation logic currently in scheduler.
- If a helper directly dispatches, do not call it from the provider; report the coupling and leave a TODO.

Validation:
- luac -p where available.
- New providers contain no direct side effects.
```

**Acceptance criteria:**

- Target/pull proposal collection is isolated without adding new side effects.

---

### T4.1 — Define movement ownership decision record

**Type:** docs/design  
**Risk:** low  
**Behavior change:** none

**Files to inspect:**

- `docs/movement_coordinator_implementation_checklist.md`
- `uc_party_follow.lua`
- `uc_pathing.lua`
- `unified_combat_core.lua`
- `unified_scheduler.lua`

**Files to change:**

- create `docs/movement_ownership_decision.md`

**Prompt for Codex:**

```text
Task: Create docs/movement_ownership_decision.md.

Document the current movement architecture and the chosen target architecture.

Must cover:
- scheduler movement coordinator
- core.apply_movement_for_scheduler
- uc_party_follow direct movement
- uc_pathing direct movement
- cast freeze and movement block reasons
- scheduler_dark_launch_movement gating
- whether movement remains coordinator-based or becomes proposal-based later

Do not change runtime code.

Be conservative. If ownership is unclear, mark it as unclear.
```

**Acceptance criteria:**

- Movement ownership is explicitly documented before further refactor.

---

### T4.2 — Add movement side-effect adapter without changing behavior

**Type:** adapter extraction  
**Risk:** medium/high  
**Behavior change:** none intended

**Files to change:**

- create `uc_movement_dispatcher.lua` or add movement functions to `uc_dispatcher.lua`
- update one narrow movement path only

**Prompt for Codex:**

```text
Task: Add a movement side-effect adapter and route one narrow scheduler-owned movement path through it without changing behavior.

Scope one path only. Prefer the path in run_movement_coordinator_tick where it directly calls windower.ffxi.run(false) for cast freeze prep, if safe.

Do not migrate uc_party_follow or uc_pathing in this task.
Do not change movement mode decisions.
Do not change movement block reasons.

The adapter should make future movement side-effect inventory clearer.

Validation:
- luac -p where available.
- Confirm behavior-preserving command equivalent.
```

**Acceptance criteria:**

- One movement side-effect path uses adapter.
- No broad movement rewrite.

---

### T5.1 — Rename docs concept from dark-launch to ownership, without changing setting keys

**Type:** docs  
**Risk:** low  
**Behavior change:** none

**Files to change:**

- scheduler docs/tracking docs only

**Prompt for Codex:**

```text
Task: Update scheduler docs to distinguish between old setting key names and new conceptual ownership terminology.

Do not rename runtime settings keys.

Docs should explain:
- scheduler_dark_launch_* keys currently mean scheduler-owned dispatch toggles.
- Future profile migration may rename them, but not in this task.
- Domain ownership is the conceptual model.

Do not change runtime code.
```

**Acceptance criteria:**

- Docs use clearer ownership terminology.
- Runtime keys untouched.

---

### T5.2 — Combat domain cutover readiness check

**Type:** docs/static + targeted code inspection  
**Risk:** low  
**Behavior change:** none

**Files to inspect:**

- `unified_engine.lua`
- `unified_scheduler.lua`
- `unified_combat_core.lua`
- combat provider module if extracted

**Files to change:**

- create `docs/combat_domain_cutover_checklist.md`

**Prompt for Codex:**

```text
Task: Create docs/combat_domain_cutover_checklist.md.

Do not change runtime code.

The checklist should answer:
- What code path runs when scheduler_dark_launch_combat is true?
- What core direct dispatch paths are suppressed?
- What core direct dispatch paths may still run?
- What settings combinations allow fallback?
- What debug signals prove scheduler owns combat?
- What acceptance scenarios should be run before removing fallback?

Use exact function names and files from the repo.
Mark uncertain areas clearly.
```

**Acceptance criteria:**

- Combat cutover blockers are explicit.

---

### T5.3 — Defensive domain cutover readiness check

Same structure as T5.2, but for defensive/internal and defensive/healbot.

---

### T5.4 — Maintenance domain cutover readiness check

Same structure as T5.2, but for COR/GEO/BRD maintenance.

---

### T5.5 — Movement domain cutover readiness check

Same structure as T5.2, but for scheduler movement coordinator, core movement, party follow, and pathing.

---

## 12. Acceptance test matrix

These tests are conceptual/manual Windower runtime tests. They should be run after meaningful implementation phases.

### 12.1 General engine tests

| Test | Setup | Expected |
| --- | --- | --- |
| Engine start/stop | `uc start`, `uc stop` | Engine ticks start/stop; no repeated errors. |
| Zone suspend | zone while engine on | Scheduler suspends during zone guard; no commands sent. |
| Debug overlay | debug enabled | Overlay displays scheduler queue/rejects/pending/movement state. |
| Missing time source | socket unavailable if simulatable | Fail fast; no `os.clock` fallback for scheduler runtime. |

### 12.2 Duplicate/stale action tests

| Test | Expected |
| --- | --- |
| Same cure proposal across multiple ticks | One dispatch, then pending/duplicate lock suppresses repeats. |
| Same WS proposal while action pending | No spam until pending resolves or times out. |
| Expired proposal selected late | Commit revalidation rejects it. |
| Packet ack observed | Pending state advances from sent/ack/effect as supported. |

### 12.3 Combat tests

| Test | Expected |
| --- | --- |
| Combat dark launch on, defensive off | Combat scheduler still runs. |
| WS ready and valid target | Scheduler-selected WS dispatches once. |
| JA ready and valid target | Scheduler-selected JA dispatches once. |
| Target out of range | Movement/approach or block reason is clear; no command spam. |
| Tank enmity enabled | Tank enmity proposals preempt lower combat actions as currently intended. |

### 12.4 Defensive tests

| Test | Expected |
| --- | --- |
| Critical HP ally | Defensive proposal outranks offense. |
| Cure pending | Duplicate cure suppressed until result/timeout. |
| Doom water emergency | Existing emergency path still works until intentionally migrated. |
| HealBot provider unavailable | Does not block unrelated domains unexpectedly. |

### 12.5 Maintenance tests

| Test | Expected |
| --- | --- |
| COR roll missing | COR maintenance proposal emits expected roll action when toggle on. |
| COR roll already active | No unnecessary duplicate roll. |
| Double-Up/Snake Eye/Fold cases | Preserve current `uc_cor_maintenance.lua` decisions. |
| Maintenance disabled | No maintenance dispatch. |

### 12.6 Movement/follow/pathing tests

| Test | Expected |
| --- | --- |
| Engine off + follow on | Follow still works. |
| Engine on + non-fighter | Follow works; no combat-close movement. |
| Engine on + fighter + valid target | Combat movement/spacing behaves as before. |
| During spell cast | Movement freezes; no self-interrupt. |
| After combat | Fight-follow hold respected, then normal follow resumes. |
| Under high proposal volume | Movement does not stutter due to ranked queue contention. |

---

## 13. Risk register

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Broad Codex rewrite breaks behavior | High | High | Use small task prompts; forbid broad rewrites. |
| Provider extraction accidentally changes proposal fields | Medium | High | Preserve schema; validate overlay/debug output. |
| Dispatcher migration changes command strings | Medium | High | Preserve exact command formatting; compare before/after. |
| Movement refactor causes stutter | High | High | Touch one path at a time; preserve block reasons; run manual tests. |
| Legacy fallback remains active invisibly | High | Medium | Add side-effect inventory and domain cutover checklists. |
| `_G` debug compatibility breaks UI | Medium | Medium | Keep `_G.UC_*` fields until replacement exists. |
| Settings/profile migration breaks saved profiles | Medium | High | Do not rename keys early. |
| Missing `luac` means syntax issues slip through | Medium | Medium | Report validation unavailable; use focused review/static greps. |

---

## 14. Recommended immediate next Codex task

Start with **T0.1 Create side-effect inventory document** or **T0.2 Create scheduler responsibility map**.

Do **not** start with dispatcher extraction. You need a written allowlist before moving side effects, or Codex may “clean up” too broadly.

Best first prompt:

```text
Use the uploaded UnifiedCombat repo.
Read docs/unified_scheduler_rfc.md, docs/unified_scheduler_phase1_amendment.md, and this RFC.
Perform T0.1 only: create docs/side_effect_inventory.md.
Do not change runtime code.
Return changed files, behavior impact, validation, and notes/risks.
```

Second prompt:

```text
Perform T0.2 only: create docs/scheduler_responsibility_map.md.
Do not change runtime code.
Return changed files, behavior impact, validation, and notes/risks.
```

Third prompt:

```text
Perform T1.1 only: mechanically extract action state, pending lifecycle, locks, and duplicate suppression into uc_scheduler_locks.lua.
Preserve behavior. Do not redesign.
Return changed files, behavior impact, validation, and notes/risks.
```

---

## 15. Final guidance to Codex

This repo is not a greenfield project. Do not optimize for elegance first. Optimize for safe migration.

The desired pattern is:

```text
Document current behavior
Extract one responsibility
Validate no behavior change
Repeat
Only then change ownership semantics
```

The biggest architecture rule:

```text
Providers propose. Scheduler arbitrates. Dispatcher acts. Locks/pending dedupe. Legacy fallback dies only after parity.
```

If a task encounters hidden coupling, stop and document it rather than guessing.
