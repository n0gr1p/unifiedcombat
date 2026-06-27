# Scheduler Ownership Resume Baseline

## Scope

This baseline resumes the scheduler ownership refactor after the T3.4 action-economy work.

It does **not** change runtime behavior.

It does **not** promote any ownership flag.

It treats T3.4j through T3.4n engage/action-economy behavior as out of scope for ownership work.

## Current Baseline

- `unified_scheduler.lua` still has zero direct textual scheduler side-effect call expressions for:
  - `windower.send_command(`
  - `windower.ffxi.run(`
  - `windower.ffxi.turn(`
  - `uc_settarget.select_by_id(`
- The promoted/default-on scheduler ownership set remains:
  - target ownership
  - turn ownership
  - defensive/internal/shared command ownership
  - maintenance COR command ownership
  - combat WS / JA / spell command ownership
  - movement-coordinator cast-freeze / pull-cast-hold / pull-spell-wait run-stop ownership
- The remaining action-economy ownership work is the default-off set plus the parked vector-run path.

## Remaining Default-Off / Parked Ownership Branches

| Family bucket | Flag | Current default behavior | Fallback behavior | Existing coverage | Live field testing practical | Recommended next action |
| --- | --- | --- | --- | --- | --- | --- |
| Command ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP` | Default-off; direct Doom Holy Water command path remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct emergency item command send. | `selftest_command_ownership_static.lua`, `selftest_command_ownership_runtime.lua`, `selftest_scheduler_default_off_ownership_branches.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | No. Real Doom live testing is intentionally impractical. | Keep parked default-off; do not choose as the next slice. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP` | Default-off; direct Doom emergency `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct emergency stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, `selftest_scheduler_default_off_ownership_branches.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | No. Real Doom live testing is intentionally impractical. | Keep parked default-off; do not choose as the next slice. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | Default-off; direct combat spell-settle `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct combat spell-settle stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, `selftest_scheduler_default_off_ownership_branches.lua`, `docs/scheduler_combat_spell_run_stop_field_test_packet.md`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Yes. Targeted live testing is practical and already packetized. | Best next single slice candidate; take this one path alone before the paired prep-wait branch. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` | Default-off; direct combat spell prep-wait `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct combat spell prep-wait stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, `selftest_scheduler_default_off_ownership_branches.lua`, `docs/scheduler_combat_spell_run_stop_field_test_packet.md`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Yes. Targeted live testing is practical and already packetized. | Hold one step behind spell-settle; keep as the immediate follow-on slice if settle passes. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` | Default-off; direct tank action-settle `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct tank settle stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Mixed. Field testing is practical, but Stage 6 remained partial and the tank family is still incomplete. | Defer until after the combat-spell settle path; avoid grouped tank promotion. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` | Default-off; direct tank JA self-send-adjacent `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct adjacent stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Partial at best. Realistic path-specific field proof is weaker than combat-spell settle. | Defer. Not the smallest safe next slice. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | Default-off; direct tank spell-settle `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct tank spell settle stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Partial at best. Field proof remains incomplete. | Defer. Not the smallest safe next slice. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` | Default-off; direct tank spell target-send-adjacent `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct adjacent stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Partial at best. Field proof remains incomplete. | Defer. Not the smallest safe next slice. |
| Run-stop ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | Default-off; direct tank spell self-send-adjacent `run(false)` remains live unless flag is explicitly `true`. | Dispatcher failure falls back to one direct adjacent stop. | `selftest_run_stop_ownership_static.lua`, `selftest_run_stop_ownership_runtime.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage. | Partial at best. Field proof remains incomplete. | Defer. Not the smallest safe next slice. |
| Target/turn ownership | none remaining default-off | Target and turn ownership are already in the promoted/default-on set when flags are unset, subject to explicit `false` opt-out and the global promoted-ownership kill switch. | Both still preserve direct fallback on dispatcher failure. | `selftest_target_ownership_static.lua`, `selftest_target_ownership_runtime.lua`, `selftest_turn_ownership_static.lua`, `selftest_turn_ownership_runtime.lua`, promotion/closure/runtime-parse/side-effect-inventory coverage. | Already practical and field-tested; no new default-off slice remains here. | No change in the next task. |
| Vector/run ownership | `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` | Default-off and effectively parked; direct heading-based run path remains live if the dormant path is ever reconnected. | Dispatcher failure falls back to the same direct heading run call once. | `selftest_run_ownership_static.lua`, `selftest_run_ownership_runtime.lua`, closure/promotion/runtime-parse/side-effect-inventory coverage, plus reachability audit docs. | No. Live reachability is not proven in current runtime flow. | Keep parked; do not choose until a separate reachability/reconnection task exists. |

## Recommended Next Single Slice

### Slice

`UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`

### Why this is next

- It is the smallest remaining action-economy ownership seam with:
  - existing ownership helper routing already in place,
  - focused default-off branch coverage already present,
  - generic run-stop helper static/runtime coverage already present,
  - practical live field testing already prepared in the combat-spell packet,
  - and lower risk than Doom, tank-family grouping, or vector run.
- It avoids:
  - Doom emergency behavior,
  - grouped tank migrations,
  - and dormant vector-run work.
- It stays fully out of T3.4j through T3.4n engage behavior.

## What Codex Should Change In The Next Task

- If Peter wants a code change next, change exactly one thing:
  - promote only `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` from explicit default-off to the same promoted-default-on semantics already used by the earlier low-risk promoted seams.
- Do **not** group in:
  - combat spell prep-wait,
  - any tank run-stop path,
  - Doom,
  - vector run,
  - or any engage/action-economy logic.

## What Peter Should Field-Test Manually

- Enable only `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true` in `local_ownership_flags.lua`.
- Use the existing combat-spell run-stop field-test packet.
- Confirm:
  - one stop occurs at the spell-settle point,
  - spell timing/order remains unchanged,
  - dispatcher success/fallback status looks sane,
  - and no duplicate or missing stop appears.
- Do **not** test Doom for this slice.

## Next-Task Validation Commands

- `luac -p unified_scheduler.lua`
- `lua tests/replay/harness/selftest_runtime_parse.lua`
- `lua tests/replay/harness/selftest_side_effect_inventory.lua`
- `lua tests/replay/harness/selftest_scheduler_ownership_closure_static.lua`
- `lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua`
- `lua tests/replay/harness/selftest_scheduler_default_off_ownership_branches.lua`
- `lua tests/replay/harness/selftest_run_stop_ownership_static.lua`
