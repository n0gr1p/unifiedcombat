# Tank Run-Stop Ownership Promotion Audit

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
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | Tank-enmity spell self-send-adjacent path | One stop before self spell send | Send-adjacent | No target send payload | Yes | Yes | Indirectly through tank spell wait | Yes | Static and aggregate coverage only; live confirmation still missing | Medium | `keep_default_off` |

## Selected next candidate

- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`
- Tank configured-JA starvation is now being diagnosed separately and should not be treated as a run-stop promotion signal.

## Why this was safest

- It is the smallest tank-family seam that is already field-tested and helper-routed.
- It does not depend on the bounded tank spell wait lock introduced by the earlier tank-spell movement-lock fixes.
- It sits before the JA/spell send branches, so it is less coupled than the self-send or spell-settle variants that inherit more scheduler-local spell-wait behavior.
- It already has existing static/runtime/aggregate coverage plus a practical field packet path, so promotion risk is lower than the unconfirmed branches.

## Why the others stay default-off

- `TANK_ENMITY_JA_SELF` is send-adjacent and now has field confirmation, so it can follow the same promoted default-on ownership shape as action-settle.
- `TANK_SPELL_SETTLE` is coupled to the scheduler-local tank spell wait lifecycle and movement-lock refresh behavior, and it is now promoted default-on with explicit `false` opt-out and shared kill switch support.
- `TANK_ENMITY_SPELL_TARGET` is now promoted default-on with explicit `false` opt-out and shared kill switch support.
- `TANK_ENMITY_SPELL_SELF` remains the more coupled send-adjacent branch and stays default-off until a practical field packet exists.
- `T3.6o` resolved the separate tank configured-JA starvation issue by retuning the configured-JA band; that was a behavior fix, not an ownership promotion.

## Field-test notes

- Allow the flag to remain unset for default-on behavior, or set `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true` explicitly to confirm the positive path.
- Allow `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` to remain unset for default-on behavior, or set it to `true` explicitly to confirm the positive path.
- Keep the promoted kill switch disabled.
- Verify one `TANK_ACTION_SETTLE` stop occurs before tank JA/spell dispatch.
- Verify the validate global reports `ownership_enabled=true`, `dispatched=true`, `ok=true`, and `fallback_used=false`.
- Verify rollback by setting the flag back to `false`/`nil`.
- Pause any further tank-family promotion until the configured-JA diagnosis confirms whether normal configured JAs are intended to run for tank mode alongside the tank-enmity list.
- Do not treat the configured-JA starvation fix as a signal to alter the run-stop ownership matrix.

## Rollback / opt-out

- Set the selected flag to `false` or remove it locally to restore the direct fallback path.
- Keep Doom and vector run out of this task; they remain separate risk categories.
- Do not promote the whole tank family in one step.
