# Scheduler Ownership Final Baseline

## Final baseline

- Combat spell run-stop seams are promoted default-on.
- All tank-family run-stop seams are promoted default-on.
- Tank configured JA starvation was fixed in `T3.6o`.
- Doom Holy Water command ownership remains default-off.
- Doom run-stop ownership remains default-off.
- Vector run ownership remains deferred/dormant.

## Promoted surfaces

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`

## Default-off / deferred surfaces

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP`

## Local override policy

- `local_ownership_flags.lua` is clean.
- Source defaults are the runtime baseline.
- Keep local overrides empty unless intentionally bisecting or collecting diagnostics.

## Rollback / opt-out options

- Promoted default-on seams can still be disabled with explicit `false`.
- Promoted seams also honor `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true`.
- Doom and vector seams remain default-off and do not use promoted opt-out semantics.

## Known fixes and risks

- `T3.6o` resolved tank configured JA starvation by raising tank-mode configured JAs to priority band `99`.
- Doom remains parked because it is an emergency path with unsafe live promotion risk.
- Vector run remains parked because live reachability is still deferred.

## Recommended next non-ownership cleanup task

- Keep the current ownership baseline stable and move any future work to a separate readiness plan only if a new field regression or coverage gap appears.
