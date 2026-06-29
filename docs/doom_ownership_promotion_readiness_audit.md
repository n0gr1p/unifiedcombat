# Doom Ownership Promotion Readiness Audit

## Current remaining surface

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` remains deferred and dormant outside Doom.

## Doom seam classification

| Seam | Runtime purpose | Current default | Local override behavior | Helper-routed | Dispatcher fallback parity | Shared promoted kill switch if promoted later | Safe to default-on now | Risk | Recommended status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Doom Holy Water command | Emergency Holy Water item send after Doom checks and cooldown gating | Default-off | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP == true` routes through `uc_scheduler_command_ownership`; otherwise direct send stays in place | Yes | Yes; dispatcher failure falls back to one direct `send_command` | Yes, if a future promotion pass opts into promoted-default-on semantics | No | High | `keep_default_off` |
| Doom run-stop | Emergency `run(false)` before the Holy Water item path | Default-off | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP == true` routes through `uc_scheduler_run_stop_ownership`; otherwise direct stop stays in place | Yes | Yes; dispatcher failure falls back to one direct `run(false)` | Yes, if a future promotion pass opts into promoted-default-on semantics | No | High | `keep_default_off` |

## Test coverage

- `tests/replay/harness/selftest_command_ownership_static.lua` covers the Doom command flag, helper routing, injected dependency, and direct fallback preservation.
- `tests/replay/harness/selftest_command_ownership_runtime.lua` covers helper behavior for default-off, explicit true, and fallback cases.
- `tests/replay/harness/selftest_run_stop_ownership_static.lua` covers the Doom run-stop flag, helper routing, injected dependency, and direct fallback preservation.
- `tests/replay/harness/selftest_run_stop_ownership_runtime.lua` covers helper behavior for default-off, explicit true, explicit false opt-out, shared kill-switch semantics, and fallback cases.
- `tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua` covers the Doom default-off branch wiring at the scheduler surface.
- `tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua` covers promoted ownership semantics, explicit false opt-out, and kill-switch behavior for promoted slices in general.

## Coverage gaps

- No safe practical live Doom field scenario is available.
- No dedicated Doom status-injection replay harness proves the full emergency flow with real Doom state and movement interruption timing.
- Doom remains an emergency path, so false positives and repeated Holy Water spam are the main promotion risks.

## Promotion risk assessment

- Doom should not be handled like a normal command/run-stop ownership slice yet.
- The emergency behavior, stop-before-item ordering, and field risk keep both seams in the conservative bucket.
- The current audit result is to keep both Doom seams default-off.

## Rollback / opt-out notes

- Current rollback stays simple: unset/remove the flag or set it to `false`/`nil`.
- If either seam is ever promoted later, the shared promoted kill switch should be wired in during that promotion pass.

## Recommended next task

- Keep Doom default-off.
- If a future task wants to revisit Doom, add a safe replay/mock coverage plan before any promotion discussion.

## Vector note

- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` remains deferred separately and is not part of Doom promotion readiness.
