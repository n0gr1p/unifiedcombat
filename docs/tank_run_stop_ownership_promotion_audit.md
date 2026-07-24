# Tank Run-Stop Ownership Promotion Audit

> **Historical Phase 1 artifact (2026-07-24):** Phase 2 retired the tank
> ownership flags and direct fallbacks audited below. See
> `RFC/UnifiedCombat_scheduler_refactor_tracking.md`.

## Aggregate replay status

- `lua tests/replay/harness/selftest_all_replay_fixtures.lua`: passes.
- Runtime files were unchanged in this audit task.

## Current promoted run-stop seams

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`

## Remaining tank-family seams

| Flag | Runtime context | Stop purpose | Timing | Target id dependency | Tank enmity dependency | Tank spell wait lock | Movement lock | Dispatcher fallback parity | Existing coverage | Risk | Recommended status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` | Tank JA/spell dispatch block just before send | One bounded stop before tank JA/spell dispatch while the action settles | Before JA / before spell | Yes | Yes | No | No direct interaction | Yes | Static, runtime, aggregate, and field packet coverage exist | Low | `promoted_default_on` |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` | Tank-enmity JA self-send-adjacent path | One stop before self JA send | Send-adjacent | No target send payload, but tank context still applies | Yes | No | No direct interaction | Yes | Static, aggregate, and field confirmation now exist | Medium | `promoted_default_on` |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | Tank spell-settle path | One stop before tank spell settle / wait window | Before spell settle | Yes | Yes | Yes | Indirectly via the spell wait path | Yes | Static, runtime, aggregate, and field packet coverage now exist | Medium | `promoted_default_on` |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` | Tank-enmity spell target send-adjacent path | One stop before target spell send | Send-adjacent | Yes | Yes | Yes | Indirectly through tank spell wait | Yes | Static and aggregate coverage only; live confirmation now accepted | Medium | `promoted_default_on` |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | Tank-enmity spell self-send-adjacent path | One stop before self spell send | Send-adjacent | No target send payload | Yes | Yes | Indirectly through tank spell wait | Yes | Static, aggregate, and live confirmation now exist | Medium | `promoted_default_on` |

## Selected next candidate

- `None`
- All tank-family run-stop seams are now promoted default-on.
- Tank configured-JA starvation was fixed in `T3.6o` and should not be treated as a run-stop promotion signal.

## Why this was safest

- All tank-family run-stop seams are now promoted default-on, so no tank-family next candidate remains.
- Doom and vector are the remaining deferred families.
- Tank configured-JA starvation is a separate tuning fix and does not change the run-stop ownership matrix.

## Why the others stay default-off

- `TANK_ENMITY_JA_SELF` is send-adjacent and now has field confirmation, so it can follow the same promoted default-on ownership shape as action-settle.
- `TANK_SPELL_SETTLE` is coupled to the scheduler-local tank spell wait lifecycle and movement-lock refresh behavior, and it is now promoted default-on with explicit `false` opt-out and shared kill switch support.
- `TANK_ENMITY_SPELL_TARGET` is now promoted default-on with explicit `false` opt-out and shared kill switch support.
- `TANK_ENMITY_SPELL_SELF` is now promoted default-on with explicit `false` opt-out and shared kill switch support.
- `T3.6o` resolved the separate tank configured-JA starvation issue by retuning the configured-JA band; that was a behavior fix, not an ownership promotion.

## Field-test notes

- Allow the flag to remain unset for default-on behavior, or set `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true` explicitly to confirm the positive path.
- Allow `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` to remain unset for default-on behavior, or set it to `true` explicitly to confirm the positive path.
- Allow `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` to remain unset for default-on behavior, or set it to `false` explicitly to confirm the local opt-out.
- Keep the promoted kill switch disabled.
- Verify one `TANK_ACTION_SETTLE` stop occurs before tank JA/spell dispatch.
- Verify the validate global reports `ownership_enabled=true`, `dispatched=true`, `ok=true`, and `fallback_used=false`.
- Verify rollback by setting the flag back to `false`/`nil`.
- Tank-family run-stop promotion is complete; future promotion work should start outside tank scope.
- Do not treat the configured-JA starvation fix as a signal to alter the run-stop ownership matrix.

## Rollback / opt-out

- Set the selected flag to `false` or remove it locally to restore the direct fallback path.
- Keep Doom and vector run out of this task; they remain separate risk categories.
- Do not promote the whole tank family in one step.
