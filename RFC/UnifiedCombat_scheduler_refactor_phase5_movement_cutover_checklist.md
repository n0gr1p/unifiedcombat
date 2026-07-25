# UnifiedCombat Scheduler Refactor — Phase 5 Movement Cutover Checklist

Status date: 2026-07-24

Implementation state: **DONE / FIELD VERIFIED WITH ACCEPTED PATH-FOLLOW RISK**

## Runtime path

- [x] `uc_domain_ownership.is_enabled('movement')` gates the scheduler movement
  coordinator before it can stop, turn, face, form, approach, or space.
- [x] `core.apply_movement_for_scheduler(settings, executor)` requires the
  injected scheduler movement facade and has no implicit executor.
- [x] The engine no longer reaches `core.legacy_movement_executor`.
- [x] Path recording/follow is an independent decision owner but now honors
  the movement domain. Disabling the domain stops an existing path-owned vector
  once and performs no further path work.
- [x] Active path movement publishes owner `path` with a short lock and releases
  that ownership when it stops.
- [x] Party follow remains an independent decision owner governed by
  `domain_follow_enabled`, not by the scheduler movement domain.
- [x] Disabled/suppressed party follow stops and releases only a follow-owned
  vector; it does not erase scheduler, formation, Nyzul, or path ownership.
- [x] Scheduler, pathing, follow, Nyzul, formation, and lifecycle movement all
  execute through `uc_movement_dispatcher.lua`.

## Settings combinations

| Movement domain | Follow domain | Result |
| --- | --- | --- |
| true | true | Scheduler movement and configured path/follow owners may participate under arbitration |
| true | false | Scheduler/path movement may run; party follow cannot |
| false | true | Scheduler and path movement cannot run; party follow remains available |
| false | false | No scheduler, path, or party-follow movement |

The legacy movement marker does not affect any row. There is no engine path to
legacy core movement.

## Evidence

- `tests/replay/harness/selftest_phase5_domain_cutover.lua`
- `tests/replay/harness/selftest_movement_priority_arbitration.lua`, including
  live-order path ownership, follow-owner isolation, and exactly-once
  movement-domain path stop
- shared movement dispatcher, scheduler facade, formation, follow/pathing,
  Nyzul, cast-lock, and Bard movement-safety suites
- `_G.UC_MOVEMENT_MODE`, `_G.UC_MOVEMENT_OWNER`,
  `_G.UC_MOVEMENT_LOCK_UNTIL`, and `_G.UC_MOVEMENT_BLOCK_REASON`

## Field acceptance record

| Item | Result | Evidence / disposition |
| --- | --- | --- |
| Combat approach, spacing, settle, and stop | `PASS` | Terrasjr MNK/WAR and Nyoourke PLD/WAR completed several full mob cycles without an observed movement regression. Phase 4 explicitly passed approach/spacing and automatic/lifecycle stop. |
| Cast movement lock and release | `PASS / PRIOR FIELD BASELINE` | Corrected in Phase 3 and accepted live in the Phase 3/4 multibox tests; no regression was observed in the current cycles. |
| Party follow | `PASS / PRIOR FIELD BASELINE` | Phase 4 live party-follow acceptance passed. Follow/movement domain independence is covered by focused arbitration tests. |
| Path-follow | `DEFERRED / RISK ACCEPTED` | Not live-tested. The user explicitly retained this as accepted risk; focused path execution, ownership, arbitration, and domain-stop tests pass. |
| Movement-domain disable while path owns movement | `AUTOMATED EVIDENCE ACCEPTED` | Not separately exercised live. Focused tests prove exactly-once stop and no subsequent path vector. |
| Formation and Nyzul | `NOT ISOLATED` | Not specifically reported in the current session; focused adapter/runtime tests remain green. |

The live combat movement result, prior follow/cast/stop field baseline, and
focused ownership tests satisfy the Phase 5 movement exit gate with the
path-follow limitation explicitly accepted.
