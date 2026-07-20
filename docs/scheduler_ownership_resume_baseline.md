# Scheduler Ownership Resume Baseline

> **2026-07-20 WS ownership update:** References below to `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP` are historical. That seam is retired in favor of the unified core WS intent owner and atomic skillchain commit validation.

## Current invariant

`unified_scheduler.lua` must not directly perform these runtime side effects:

- `windower.send_command(`
- `windower.ffxi.run(`
- `windower.ffxi.turn(`
- `uc_settarget.select_by_id(`

Those actions should stay behind dispatcher or wrapper seams.

## Current audit result

- `unified_scheduler.lua` currently has zero direct textual callsites for the four side-effect expressions above.
- The remaining runtime actions in `unified_scheduler.lua` are routed through ownership helpers for command, run-stop, target, turn, and run-vector seams.
- `UnifiedCombat.lua` still contains one legacy direct `windower.ffxi.run(false)` in `_G.UC_ResetMovementLocksForFollow`; that lives outside the scheduler ownership surface and is not part of this baseline.
- `T3.6s` finalized this as the stable scheduler ownership baseline.
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit `false` opt-out and shared promoted kill-switch support.
- Doom Holy Water command and Doom run-stop remain default-off after the T3.6r readiness audit; no promotion is recommended yet.

## Dispatcher / wrapper seams

- `uc_scheduler_command_ownership.lua` owns command dispatch seams for promoted command paths and keeps direct fallback on dispatcher failure.
- `uc_scheduler_run_stop_ownership.lua` owns the run-stop seams for promoted and default-off stop paths.
- `uc_scheduler_target_ownership.lua` owns target selection dispatch.
- `uc_scheduler_turn_ownership.lua` owns turn dispatch.
- `uc_scheduler_run_ownership.lua` is the parked vector-run wrapper seam.

## Ownership flags and kill switches

### Promoted default-on flags

- `UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`

### Default-off flags

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`

### Parked flag

- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP`

### Explicit kill switch

- `UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP`

### Local flag loading behavior

- `UnifiedCombat.lua` loads `local_ownership_flags.lua` with `pcall(require, ...)`.
- Missing local flags are ignored.
- Other load failures are surfaced to chat and left visible for debugging.
- `local_ownership_flags.lua` is intentionally local-only and uncommitted.

## Side-effect surface classification

| Family | Status | Classification |
| --- | --- | --- |
| Target ownership | Already promoted; wrapper seam only in scheduler | `dispatcher_owned` / `wrapper_owned` |
| Turn ownership | Already promoted; wrapper seam only in scheduler | `dispatcher_owned` / `wrapper_owned` |
| Promoted command ownership | Already promoted; wrapper seam only in scheduler | `dispatcher_owned` / `wrapper_owned` |
| Promoted movement stop ownership | Already promoted; wrapper seam only in scheduler | `dispatcher_owned` / `wrapper_owned` |
| Combat spell settle run-stop | Now promoted default-on with explicit false opt-out and shared kill switch | `dispatcher_owned` / `wrapper_owned` |
| Tank-enmity JA self run-stop | Now promoted default-on with explicit false opt-out and shared kill switch | `dispatcher_owned` / `wrapper_owned` |
| Tank spell-settle run-stop | Now promoted default-on with explicit false opt-out and shared kill switch | `dispatcher_owned` / `wrapper_owned` |
| Tank-enmity spell target run-stop | Now promoted default-on with explicit false opt-out and shared kill switch | `dispatcher_owned` / `wrapper_owned` |
| Tank-enmity spell self run-stop | Now promoted default-on with explicit false opt-out and shared kill switch | `dispatcher_owned` / `wrapper_owned` |
| Doom command / run-stop paths | Still default-off and intentionally parked from live field work | `unsafe_to_move_yet` |
| Combat spell prep-wait run-stop | Now promoted default-on with explicit false opt-out and shared kill switch | `dispatcher_owned` / `wrapper_owned` |
| Remaining tank-family run-stop paths | All tank-family run-stop seams are now promoted default-on | `dispatcher_owned` / `wrapper_owned` |
| Vector run | Default-off and dormant | `unsafe_to_move_yet` |
| `UnifiedCombat.lua` reset helper run(false) | Legacy direct helper outside scheduler ownership surface | `legacy_intentional` |

## Spell lifecycle cleanup status

- Spell lifecycle release is now resolved and non-blocking from an ownership perspective.
- It does not add any direct runtime side effects back into `unified_scheduler.lua`.
- The probe remains debug-only and should not be used as a behavior seam.

## Recommended next seam

- No ownership promotion seam is recommended now.
- Why: the baseline is complete, Doom stays default-off, and vector run remains parked separately.
- Status: `baseline_finalized`; keep future work in a separate readiness plan if a new gap appears.

## What must not change next

- Do not reintroduce direct side-effect callsites into `unified_scheduler.lua`.
- Do not change spell lifecycle behavior in this ownership task.
- Do not promote Doom, tank-family, or vector-run seams in the same task.
- Do not group in Doom, tank-family, or vector-run migrations.
- Do not touch engage/action-economy ranking rules beyond the specific ownership seam.
