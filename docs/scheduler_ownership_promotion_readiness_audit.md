# Scheduler Ownership Promotion Readiness Audit

> **2026-07-20 WS ownership update:** This audit preserves the historical promotion evidence. The combat-WS command-ownership flag is no longer live; scheduler WS dispatch now delegates to the unified core intent owner so the same target-scoped skillchain plan can be revalidated immediately before the single send. See `scheduler_owned_ws_skillchain_compliance_audit.md`.

## Scope

This audit covers every `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP` flag currently used by scheduler ownership seams.

It does **not** change runtime behavior.

It separates:

- truly scheduler-owned actions that are candidates for ownership promotion,
- scheduler-owned actions that remain too risky or insufficiently proven,
- and movement paths that are actually owned by core / pathing / follow systems rather than scheduler ownership seams.

## Current Baseline

- `unified_scheduler.lua` has zero direct textual scheduler side-effect call expressions for:
  - `windower.send_command(`
  - `windower.ffxi.run(`
  - `windower.ffxi.turn(`
  - `uc_settarget.select_by_id(`
- Closure coverage passes through `tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`.
- Full replay/static suite currently passes.
- Ownership helpers exist for:
  - command
  - run
  - run_stop
  - target
  - turn
- Movement arbitration and zero-HP death-animation cleanup were completed after field testing exposed non-ownership baseline movement issues.
- `T3.6s` finalized the ownership baseline; no new promotion is recommended now.

## Promotion Principles

Promote only when all of the following are true:

- path is genuinely scheduler-owned,
- live reachability is confirmed,
- field testing passed for a practical scenario,
- replay/static coverage exists,
- and keeping a temporary kill switch during rollout is still useful.

Keep default-off when any of the following remain true:

- live scenario is deferred or not practical,
- field coverage is only partial,
- reachability is uncertain,
- or the path is tied to emergency/high-risk behavior.

Retire or document as unreachable when:

- the path is not currently live-reachable,
- or the ownership flag covers a scheduler path that is not part of live runtime flow.

## Scheduler-Owned vs Non-Scheduler-Owned

### Truly Scheduler-Owned

- target prep ownership
- turn ownership
- scheduler-issued command families:
  - defensive/internal/maintenance commands
  - combat WS / JA / spell command sends
- scheduler-owned run-stop branches:
  - Doom stop
  - movement-coordinator stop branches
  - generic combat-spell stop branches
  - tank stop branches

### Not Actually Scheduler-Owned

These should **not** be treated as scheduler ownership promotion work:

- core combat movement in `unified_combat_core.lua`
- follow suppression / return-to-leader behavior in `uc_party_follow.lua`
- path-follow pause/resume behavior in `uc_pathing.lua`
- movement arbitration fixes from T2.8b/T2.8c/T2.8d
- zero-HP death-animation movement churn fixes from T2.9b/T2.9c

Those paths affect gameplay around scheduler ownership testing, but they are not ownership flags or scheduler-owned dispatcher promotions.

## Ownership Flag Inventory

### Promote Default-On Candidates

These are the strongest low-risk candidates for T3.0b promotion with a temporary rollback/kill switch retained during rollout.

| Flag | Helper / Path | Scheduler Behavior | Field-Test Status | Coverage | Live Reachability | Recommendation | Rationale |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP` | `uc_scheduler_target_ownership` | `p1_try_target_prep` target selection | Stage 1 PASS | Target runtime/static + closure + aggregate | Confirmed live | Promote default-on | Narrow helper seam, boolean return preserved, practical field pass, low regression surface. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP` | `uc_scheduler_turn_ownership` | face-to-target turn | Stage 1 PASS | Turn runtime/static + closure + aggregate | Confirmed live | Promote default-on | Single scheduler-owned turn path, practical field pass, no visible regression. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | defensive_internal command send | Stage 2 PASS | Command runtime/static + closure + aggregate | Confirmed live | Promote default-on | Live-tested isolated path with low ambiguity and no visible duplicate/missed sends. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | shared internal defensive dispatch send | Stage 2 PASS | Command runtime/static + closure + aggregate | Confirmed live | Promote default-on | Shared final scheduler command path closed cleanly and passed practical live testing. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | maintenance COR self command | Stage 2 PASS | Command runtime/static + closure + aggregate | Confirmed live | Promote default-on | Isolated self-command path, good field evidence, low coupling. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | combat WS command send | Stage 3 PASS | Command runtime/static + closure + aggregate | Confirmed live | Promote default-on | Practical live pass plus later zero-HP cleanup on surrounding core behavior reduced baseline churn risk. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | combat JA target/self sends | Stage 3 PASS | Command runtime/static + closure + aggregate | Confirmed live | Promote default-on | Practical live target/self coverage passed and path is clearly scheduler-owned. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | combat spell target/self sends | Stage 3 PASS for practical live paths | Command runtime/static + closure + aggregate | Confirmed live for target/tank spell path | Promote default-on with kill switch retained | Field coverage is slightly narrower than JA/WS, but replay/static coverage plus practical live pass are strong enough for cautious promotion. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | `uc_scheduler_run_stop_ownership` | generic combat spell settle stop | Stage 6 PASS | Run-stop runtime/static + closure + aggregate | Confirmed live | Promote default-on with kill switch retained | Smallest remaining action-economy stop seam, already helper-routed and now field-safe enough for default-on promotion. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP` | `uc_scheduler_run_stop_ownership` | cast-freeze prep stop | Stage 5 PASS | Run-stop runtime/static + closure + aggregate | Confirmed live | Promote default-on | Dispatcher ownership confirmed live with `ownership=true dispatched=true ok=true fallback=false`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP` | `uc_scheduler_run_stop_ownership` | pull cast-hold stop | Stage 5 PASS | Run-stop runtime/static + closure + aggregate | Confirmed live | Promote default-on | Same as above; direct live dispatcher confirmation exists. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP` | `uc_scheduler_run_stop_ownership` | pull spell-wait stop | Stage 5 PASS | Run-stop runtime/static + closure + aggregate | Confirmed live | Promote default-on | Same as above; direct live dispatcher confirmation exists. |

### Remaining Default-Off Candidates

These should remain behind kill-switch flags for now.

| Flag | Helper / Path | Scheduler Behavior | Field-Test Status | Coverage | Live Reachability | Recommendation | Rationale |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP` | `uc_scheduler_command_ownership` | Doom Holy Water command send | Deferred live | Command runtime/static + closure + aggregate | Presumed reachable but not safely field-tested | Keep default-off | Emergency item path; no safe practical field scenario. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP` | `uc_scheduler_run_stop_ownership` | Doom emergency stop | Stage 4 DEFERRED | Run-stop runtime/static + closure + aggregate | Presumed reachable but not safely field-tested | Keep default-off | Emergency stop path should remain conservative without live proof. |

All tank-family run-stop seams are now promoted default-on and are summarized in `docs/tank_run_stop_ownership_promotion_audit.md` and `docs/tank_run_stop_ownership_phase_closure.md`.

### Retire / Unreachable Candidates

| Flag | Helper / Path | Scheduler Behavior | Field-Test Status | Coverage | Live Reachability | Recommendation | Rationale |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` | `uc_scheduler_run_ownership` | scheduler vector run helper path | Stage 7 DEFERRED / NOT LIVE-REACHABLE | Run runtime/static + closure + aggregate | Not confirmed reachable | Retire as unreachable or leave explicitly documented as dormant until runtime reconnection decision | Current runtime flow does not prove the scheduler vector path executes; promotion would be misleading. |

## Ownership Inventory Summary

- Total ownership flags audited: 21
- Promote default-on candidates: 18
- Keep default-off candidates: 2
- Retire / unreachable candidates: 1

Notes:

- The single unreachable candidate is the vector run flag.
- The conservative hold set is still the emergency Doom paths; T3.6r kept them default-off.
- No broad movement ownership promotion is recommended.

## Temporary Kill Switch Recommendation

Yes: keep a temporary rollback path during promotion.

Recommended temporary promotion posture:

- flip selected flags to default-on in code,
- but retain the existing explicit flag check or an equivalent temporary override/kill-switch mechanism for at least one promotion stage,
- remove those temporary kill switches only after promoted paths survive broader real usage and a final closure audit.

This is most important for:

- combat command families,
- movement-coordinator run-stop paths,
- and any later tank run-stop promotion.

It is less critical for:

- target
- turn
- isolated internal / maintenance command paths

but still useful for one staged release.

## Recommended Promotion Strategy

### T3.0b — Promote Low-Risk, Field-Tested Scheduler Ownership Flags

Promote default-on:

- target
- turn
- defensive_internal command
- internal dispatch command
- maintenance COR command
- combat WS command
- combat JA command
- combat spell command
- movement-coordinator run-stop trio

Keep temporary kill switches during this stage.

### T3.0c — Hold High-Risk / Deferred Paths Behind Kill Switches

Keep default-off:

- Doom Holy Water command
- Doom run_stop
- all tank/combat-spell run-stop paths not fully field-confirmed

If desired, split the tank family further so `TANK_ACTION_SETTLE` can be reconsidered separately after an explicit follow-up prompt.

### T3.0d — Retire or Explicitly Park Unreachable Ownership Flags

Do not promote vector run ownership.

Either:

- retire `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` and its promotion-plan row as unreachable in current runtime flow,

or:

- leave it documented as dormant / not live-reachable pending a future explicit runtime reconnection decision.

### T3.0e — Final Closure Audit After Promotion

After any default-on flips:

- rerun closure/static/replay validation,
- confirm temporary kill-switch story is still explicit,
- and update plan/docs to distinguish promoted paths from permanently default-off or retired paths.

## Recommended Next Implementation Slice

Recommended next prompt:

> T3.1a — targeted coverage plan for remaining default-off run_stop paths. Scope the remaining Doom, combat-spell, and tank run_stop ownership families, separate indefinitely deferred emergency paths from realistically testable paths, and define whether each should receive replay/mock coverage, a targeted field-test packet, or intentional permanent default-off status.

## T3.0b Promotion Decision Applied

T3.0b applies the audit recommendation exactly:

- the 11 low-risk, field-tested scheduler-owned paths are now promoted to default-on,
- deferred / partial / Doom / tank / vector paths are not promoted,
- and no runtime ownership expansion was made beyond those 11 existing scheduler-owned paths.

The promotion remains conservative because:

- each promoted path still has a per-flag explicit `false` opt-out,
- a shared temporary kill switch exists via `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP = true`,
- and all non-promoted flags still require explicit `== true`.

## T3.0c Field-Test Result Applied

T3.0b field testing completed as PASS:

- promoted paths were exercised in their default-on state,
- no global rollback through `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP` was needed,
- and no individual promoted-path opt-out was needed.

Promoted paths should no longer be treated as pending promotion work.

## Current Post-Promotion Status

### Accepted default-on set

The following 11 paths are now accepted as promoted/default-on rather than pending:

- target ownership
- turn ownership
- defensive_internal command ownership
- shared internal dispatch command ownership
- maintenance COR command ownership
- combat WS command ownership
- combat JA command ownership
- combat spell command ownership
- movement-coordinator cast-freeze-prep run_stop ownership
- movement-coordinator pull-cast-hold run_stop ownership
- movement-coordinator pull-spell-wait run_stop ownership

### Remaining pending / deferred / dormant set

- Doom Holy Water command ownership: deferred, keep default-off.
- Doom run_stop ownership: deferred, keep default-off.
- combat spell settle/prep-wait run_stop ownership: both promoted default-on; the remaining deferred work is Doom and vector run.
- Vector run remains separately deferred.
- tank action settle, tank-enmity JA self, tank spell-settle, tank-enmity spell target, and tank-enmity spell self run_stop ownership: all promoted default-on; tank-family run-stop promotion is complete.
- vector run ownership: dormant / not live-reachable, do not treat as active promotion work.

These remaining default-off paths are now governed by `docs/scheduler_remaining_run_stop_coverage_plan.md`, which assigns replay/mock-first, targeted-field-packet, parked, or future-retirement treatment per path instead of treating them as one promotion bucket.

## T3.1b Coverage Status Update

The following four default-off branches now have focused static+mock replay coverage in `tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`:

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

Interpretation:

- coverage status improved from planning-only to static+mock branch coverage,
- readiness status was still default-off at that stage,
- and no promotion decision changed in T3.1b.

## T3.1c Readiness Decision Update

### Doom branches

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`: keep default-off.
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`: keep default-off.

Readiness interpretation:

- static+mock coverage now exists,
- live confirmation remains intentionally absent,
- and promotion readiness is still negative because safe practical Doom field testing is not recommended.

### Combat-spell run-stop branches

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`: promoted default-on with explicit false opt-out and shared kill switch rollback.
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`: promoted default-on with explicit false opt-out and shared kill-switch rollback.

Readiness interpretation:

- static+mock coverage is strong enough to remove pure branch-coverage uncertainty for both branches,
- settle has now crossed the promotion bar and is default-on,
- prep-wait has now crossed the promotion bar and is default-on.

Current readiness state for the four T3.1b-covered branches:

- Doom command: default-off / not promotion-ready
- Doom run_stop: default-off / not promotion-ready
- combat-spell settle run_stop: default-on / promoted
- combat-spell prep-wait run_stop: default-on / promoted

## T3.1d Packet Readiness Update

- `docs/scheduler_combat_spell_run_stop_field_test_packet.md` is now the active next-step packet for the two combat-spell run-stop branches
- both combat-spell branches remain pending field-test results
- Doom branches remain default-off and are not part of the combat-spell packet
