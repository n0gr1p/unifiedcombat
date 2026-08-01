# Scheduler-owned WS skillchain replay results

Date: 2026-07-20
Workstream: `WS-SC`
Result: **PASS — implementation, replay, and field gates complete**

## Runtime behavior covered

- Target-scoped resonance state and monotonically increasing generations.
- Action-result-anchored ordinary and action-specific timing.
- Conservative preferred and latest-safe execution boundaries.
- Preservation on miss, interruption, and propertyless WS, including successful propertyless WS entries absent from `skills.lua`.
- Property-bearing pet/job/monster actions are observed; unqualified spells are excluded and qualified Chain Affinity-style spells remain eligible.
- Ordered directional transitions, Level 2 loops/promotions, terminal Level 4, and no speculative action-count cap.
- Chainbound Level 1 priority, two-second earliest-close timing, explicit Wild Flourish/Konzen-ittai lifetimes, and fail-closed handling for unmapped source lifetimes.
- Local actor Aeonic equipment/Aftermath effective properties and AM1/AM2/AM3 Ultimate thresholds.
- Non-Aeonic AM1/AM2/AM3 does not enable Ultimate prediction merely because a generic Aftermath buff ID is present.
- Diamond Aspis actor-specific expiry.
- Structured scheduler proposal transport and final commit-time cancellation.
- Target, generation, properties, equipment, Aftermath, WS availability, TP, status, range, reaction hold, engine, and intent invalidation.
- Scheduler ordering: critical Cure and Sleep/emergency control above continuation; continuation above Bard/routine maintenance, aftermath refresh, and ordinary offense. A pending continuation reserves this action lane until its buffered preferred time instead of allowing routine work to consume the window.
- Final commit explicitly rejects incapacitating buffs and dispatch before the conservative preferred time.
- Commit telemetry distinguishes scheduler rank admission (`rank_commit`) from the immediate pre-send validation (`dispatch_commit`).
- A dispatched target/resonance generation is reserved until its result arrives, preventing duplicate continuation sends while the result is pending.
- Explicit zone, logout, unload, engine-stop, death, and tick-discovered invalid/despawn cleanup.
- Runtime Lua 5.1 parsing and unchanged side-effect callsite inventory.

## Commands and results

```text
luac -p uc_skillchain_state.lua unified_combat_core.lua unified_scheduler.lua uc_scheduler_dispatch_plan.lua UnifiedCombat.lua remote_bridge.lua tests/replay/harness/selftest_skillchain_state.lua
PASS

lua tests/replay/harness/selftest_skillchain_state.lua
selftest_skillchain_state: OK

lua tests/replay/harness/selftest_scheduler_skillchain_integration.lua
selftest_scheduler_skillchain_integration: OK

lua tests/replay/harness/selftest_dispatch_plan_fixtures.lua
selftest_dispatch_plan_fixtures: OK

lua tests/replay/harness/selftest_scheduler_support_priority_bands.lua
selftest_scheduler_support_priority_bands: OK

lua tests/replay/harness/selftest_defensive_cure_priority.lua
selftest_defensive_cure_priority: OK

lua tests/replay/harness/selftest_scheduler_sleep_toggle.lua
selftest_scheduler_sleep_toggle: OK

lua tests/replay/harness/selftest_scheduler_ownership_promotion_static.lua
selftest_scheduler_ownership_promotion_static: OK

lua tests/replay/harness/selftest_command_ownership_static.lua
selftest_command_ownership_static: OK

lua tests/replay/harness/selftest_side_effect_inventory.lua
selftest_side_effect_inventory: OK (files=13, patterns=39)

lua tests/replay/harness/selftest_runtime_parse.lua
selftest_runtime_parse: OK (67 runtime files)

lua tests/replay/harness/selftest_all_replay_fixtures.lua
selftest_all_replay_fixtures: OK (95 suites)

git diff --check
PASS (line-ending conversion warnings only; no whitespace errors)
```

## Clock decision

`os.clock` is the approved monotonic source for process-local skillchain observation, planning, and commit comparisons. The implementation fails fast if it is unavailable. LuaSocket wall-clock time remains limited to the existing cross-process coordination domain; deadlines are translated by remaining duration and clocks are not directly compared.

## Field evidence status

Initial Nyoourke and multi-actor logs were subsequently reviewed in `scheduler_owned_ws_skillchain_field_results_2026-07-20.md`. They live-verify preferred/latest-safe timing and both successful-chain and non-chain generation replacement before dispatch.

The initial field logs exposed two issues—non-Aeonic AM3 predicting Radiance and repeated sends for one pending generation. Both were corrected and replay-verified. The focused post-reload capture then passed for Nyoourke (35 dispatches) and Ponponponponpon (13 dispatches), with all dispatches inside the preferred/latest-safe window, no duplicate target/generation dispatches, required pending-result reservations, and zero Ultimate predictions in Nyoourke's declared non-Aeonic session. `WS-SC-4` is complete. The following remain nonblocking observational items:

- live AoE selected-target packet ordering;
- practical late-window calibration by stage;
- Weapon Bash Chainbound expiry behavior needed to replace the current explicit `SC_CHAINBOUND_SOURCE_UNSUPPORTED` result with an evidenced lifetime;
- server rejection attributable specifically to line of sight.

The exact post-reload validator results are recorded in `scheduler_owned_ws_skillchain_field_results_2026-07-20.md`.
