# UnifiedCombat Scheduler Refactor Phase 2 Exit Audit

Date: 2026-07-24
Branch: `scheduler-refactor`
Base commit: `dca8efb752cbf79bc2980d5ff8e27b48810ebdf4`
Decision: **PASS — Phase 2 is complete, replay verified, and movement smoke tested**

## Scope

This audit checks the current working tree against RFC tasks T2.1 through T2.4
and the Phase 2 architectural exit condition: scheduler-owned side effects must
cross one dispatcher contract without direct fallback execution.

Phase 3 provider extraction, Phase 4 independent movement owners, and Phase 5
legacy/core domain cutover are explicitly outside this decision.

## Requirement-by-requirement result

| Requirement | Result | Evidence |
| --- | --- | --- |
| T2.1 dispatcher module exists | PASS | `uc_scheduler_dispatcher.lua` is the established project-specific module name. It validates/normalizes intents and executes only injected dependencies. |
| Dispatcher contract documented | PASS | The module documents exactly-once crossing, no direct fallback, pre-execution commit validation, and post-execution marking. |
| Commit-time validation hook | PASS | `hooks.revalidate` runs after intent validation/dry-run gating and immediately before dependency execution. A rejection returns without executing the dependency or mark hook. |
| Action mark hook | PASS | `hooks.on_executed` runs once after successful dependency execution. Hook failure is fatal rather than silently falling back. |
| T2.2 dark-launch primary command dispatch | PASS | Eight scheduler command seams execute through `uc_scheduler_command_ownership.lua` and the dispatcher. Command strings remain constructed at their existing scheduler seams. |
| Scheduler target and turn dispatch | PASS | Target and turn ownership helpers are dispatcher-only and contain no direct executor dependency. |
| Scheduler engage/switch/disengage dispatch | PASS | Partner arbitration, reaction stop, add-control retarget, and combat engage create dispatcher intents and inject the existing `uc_attack` adapter functions. |
| Scheduler-owned skillchain WS atomic commit | PASS | `core.try_dispatch_ws_with_intent` sends through the dispatcher; `dispatch_commit` revalidation is the pre-execution hook and `mark_plan_dispatched` is the post-execution hook. |
| T2.3 human and machine allowlists | PASS | `docs/side_effect_inventory.md`, `docs/side_effect_allowlist.md`, and `tests/replay/fixtures/shared/side_effect_allowlist.lua` agree with the current scan. |
| T2.4 scheduler movement coordinator facade | PASS | `uc_scheduler_movement_facade.lua` maps stop, exact heading, forward run, turn, move-towards, and move-away operations to dispatcher intents. `core.apply_movement_for_scheduler` requires and uses this injected executor. |
| Preserve independent movement scope | PASS | Follow, pathing, Nyzul, lifecycle, and legacy core movement remain unchanged in ownership and explicitly allowlisted for Phase 4/5; formation already uses dispatcher intents. |
| Remove transitional ownership switches | PASS | Scheduler runtime contains no `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP`, promotion kill switch, `promoted_default_on`, or direct fallback injection. |
| Scheduler direct-executor monopoly guard | PASS | Static coverage rejects direct command, run, turn, target, engage, switch, and disengage call expressions in `unified_scheduler.lua`. |

## Execution-path audit

Scheduler-owned execution is divided into these dispatcher paths:

| Domain | Scheduler-facing path | Concrete adapter |
| --- | --- | --- |
| Commands: item, JA, spell, maintenance, defensive | ownership helper → dispatcher `send_command` intent | injected `windower.send_command` |
| Target selection | target ownership helper → dispatcher `select_target` intent | injected `uc_settarget.select_by_id` |
| Facing | turn ownership helper or movement facade → dispatcher `turn` intent | injected `windower.ffxi.turn` |
| Engage | dispatcher `engage` intent | injected `uc_attack.engage_target` |
| Engaged retarget | dispatcher `switch_target` intent | injected `uc_attack.switch_target` |
| Disengage | dispatcher `disengage` intent | injected `uc_attack.disengage` |
| Movement stop | run-stop ownership helper or movement facade | injected `windower.ffxi.run(false)` |
| Movement heading | movement facade → validated vector intent | injected exact-heading `windower.ffxi.run(heading)` adapter |
| Forward movement | movement facade → `run_forward` intent | injected zero-argument `windower.ffxi.run()` adapter |
| Actor movement | movement facade → move-towards/move-away intent | injected actor adapter |
| Skillchain WS | core intent owner → dispatcher `send_command` intent | injected `windower.send_command` |

There is no direct retry or fallback executor after a dispatcher rejection.
Missing dependencies and impossible execution states fail fast. Legitimate
target/packet adapter rejection is returned to the existing caller policy.

## RFC naming deviation

The RFC proposed `uc_dispatcher.lua`; the repository had already established
`uc_scheduler_dispatcher.lua` before this closeout. Renaming it would add
require/load-order risk without changing ownership, so Phase 2 keeps the
established filename. The functional contract and acceptance criteria are met.

## Side-effect inventory delta

Compared with the Phase 1 baseline:

- scheduler `uc_attack` wrapper calls: 5 → 0;
- core direct `send_command` calls: 7 → 6 because scheduler-owned skillchain WS
  moved behind the dispatcher;
- core textual direct `run` calls: 21 → 14 because the shared movement decision
  code now uses an injected executor and legacy calls are concentrated in the
  explicit legacy adapter;
- total observed guarded hits: 263 → 250;
- scheduler tracked direct executor calls: 0.

Command construction remains intentionally inventoried and is not execution.
Low-level packet adapters remain concrete executors by design.

## Verification

The following checks pass:

```text
luac -p uc_scheduler_dispatcher.lua
luac -p uc_scheduler_movement_facade.lua
luac -p uc_scheduler_command_ownership.lua
luac -p uc_scheduler_run_ownership.lua
luac -p uc_scheduler_run_stop_ownership.lua
luac -p uc_scheduler_target_ownership.lua
luac -p uc_scheduler_turn_ownership.lua
luac -p unified_combat_core.lua
luac -p unified_scheduler.lua

lua tests/replay/harness/selftest_runtime_parse.lua
  77/77 runtime files compile

lua tests/replay/harness/selftest_all_replay_fixtures.lua
  111/111 suites pass

lua tests/replay/harness/selftest_side_effect_inventory.lua
  runtime_files=126
  allowlisted_files=20
  pattern_checks=300
  observed_hits=250
```

Focused Phase 2 coverage includes:

- dispatcher validation, hook order, commit rejection, missing dependency, and
  exactly-once engage/switch/disengage execution;
- movement facade exact call-shape preservation for heading, stop, forward,
  turn, move-towards, and move-away;
- command/run/run-stop/target/turn ownership success and no-fallback failure;
- Doom Holy Water command/stop execution and rejection behavior;
- scheduler monopoly and retired-flag static guards;
- skillchain dispatcher commit/mark integration.

Live Windower verification:

- the user completed the targeted in-game scheduler movement-facade smoke test
  on 2026-07-24;
- movement, spacing, and automatic stop behavior were reported successful;
- the test used scheduler combat and movement ownership together so the legacy
  core movement fallback was not eligible to confound the result.

## Residual risks and follow-up

- The targeted movement smoke test passed, but no raw diagnostic capture was
  retained with this audit. Broader normal-play, multibox, and encounter
  regression coverage remains follow-up validation rather than a Phase 2 exit
  blocker.
- Legacy/core, follow, pathing, Nyzul, and lifecycle executors remain
  intentionally direct. They are Phase 4/5 work, not Phase 2 leakage.
- Provider functions remain local to `unified_scheduler.lua`; Phase 3 is the
  next RFC phase.

## Tracking accuracy decision

The authoritative board and Phase 2 acceptance record in
`RFC/UnifiedCombat_scheduler_refactor_tracking.md` match this inspected state.
Older detailed entries describing default-off flags and direct fallback paths
remain historical only and are covered by the tracker's superseded-history
notice. The old field and promotion documents are also marked as historical
Phase 1 artifacts.
