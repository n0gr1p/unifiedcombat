# UnifiedCombat Scheduler Refactor — Phase 5 Combat Cutover Checklist

Status date: 2026-07-24

Implementation state: **DONE / FIELD VERIFIED**

## Runtime path

- [x] `uc_domain_ownership.is_enabled('combat')` is the combat participation
  gate.
- [x] `p1_collect_proposals` collects target, engage, pull, tank-enmity, Sleep,
  offense, and configured-JA proposals only when the combat domain is enabled.
- [x] Nonblocking target acquisition and partner arbitration are gated by the
  combat domain.
- [x] Target, engage/switch/disengage, pull, JA, spell, WS, Sleep, tank-enmity,
  enemy-control, and skillchain commits remain scheduler-ranked and
  dispatcher-owned.
- [x] `unified_engine.lua` calls `scheduler.process_tick` and never calls
  `_G.UC_CoreCombatTickOnce`.

## Core execution closure

- [x] The engine's `core_tick_allowed_for_domain`, all-domain ownership test,
  and conditional core-tick call are removed.
- [x] Scheduler pull no longer invokes an implicitly direct core executor.
  `core.dispatch_pull_for_scheduler(settings, target_id, executor)` requires
  `uc_scheduler_pull_executor.lua`, which routes target, movement, and command
  effects through the dispatcher.
- [x] Scheduler skillchain WS execution continues through
  `uc_scheduler_dispatcher.lua`.
- [x] Core target, tank, pull, WS-plan, and movement decision helpers may remain
  as compatibility helpers; their presence is not an engine fallback.
- [x] Legacy direct combat code remains in `run_unified_combat` for Phase 6
  deletion, but it is unreachable from `unified_engine.lua`.

`_G.UC_CoreCombatTickOnce` is still published by `UnifiedCombat.lua` as an
existing compatibility global. No repository runtime caller invokes it after
the Phase 5 engine cutover. Removing that public surface is Phase 6 work.

## Settings combinations

| `domain_combat_enabled` | Legacy marker | Result |
| --- | --- | --- |
| true | true or false | Scheduler combat path is enabled |
| false | true or false | No scheduler combat collection, target acquisition, partner arbitration, or combat dispatch |

There is no setting combination that selects the legacy core fallback.

## Evidence

- `tests/replay/harness/selftest_phase5_domain_cutover.lua`
- `tests/replay/harness/selftest_scheduler_pull_executor.lua`
- scheduler provider, target, engage, tank, Sleep, WS, action-state, and
  dispatcher suites in the aggregate replay runner
- `_G.UC_LAST_SCHED_ACTION`, `_G.UC_LAST_BLOCK_REASON`, ranked queue/reject
  overlay, action timeline, and the retained dispatcher validation globals

## Field acceptance record

| Item | Result | Evidence / disposition |
| --- | --- | --- |
| Repeated normal combat cycles | `PASS` | Nyoourke PLD/WAR and Terrasjr MNK/WAR completed several full mob cycles with no observed regression or bug. |
| Target/engage, approach, spacing, and ordinary combat actions | `PASS` | Exercised by the live tank/DPS profiles and consistent with the Phase 3/4 field baseline. |
| Tank participation | `PASS` | Nyoourke PLD/WAR participated throughout the live cycles without an observed regression. |
| False legacy-marker profile | `AUTOMATED EVIDENCE ACCEPTED` | All five live profiles had their four compatibility markers set to `true`. `selftest_phase5_domain_cutover.lua` proves combat authority is independent of either marker value. |
| Combat-domain disable | `AUTOMATED EVIDENCE ACCEPTED` | Focused replay/static coverage proves disabled combat prevents collection, acquisition, arbitration, and dispatch without enabling a core fallback. |
| Pull and skillchain-controlled WS | `NOT ISOLATED` | Not specifically reported in this session. Existing focused scheduler pull, WS, and skillchain dispatcher tests remain green. |

The live positive-path result plus focused negative and marker-independence
coverage satisfies the Phase 5 combat exit gate.
