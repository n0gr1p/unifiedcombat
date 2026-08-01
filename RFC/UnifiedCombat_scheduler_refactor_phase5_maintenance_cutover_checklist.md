# UnifiedCombat Scheduler Refactor — Phase 5 Maintenance Cutover Checklist

Status date: 2026-07-24

Implementation state: **DONE / FIELD VERIFIED**

## Runtime path

- [x] `uc_domain_ownership.is_enabled('maintenance')` gates maintenance
  collection, Bard lane reservation, and COR/BRD dispatch.
- [x] COR selection remains owned by `uc_cor_maintenance.lua`; the scheduler
  ranks and dispatches the concrete JA.
- [x] BRD selection and action-lane sequencing remain owned by
  `uc_brd_maintenance.lua`; the scheduler dispatches the selected JA/spell and
  maintains movement exclusion through the atomic sequence.
- [x] Disabling the maintenance domain prevents a stale Bard lane from
  blocking other domains.
- [x] No engine or core maintenance fallback exists.

## GEO disposition

The current GEO branch in `uc_provider_maintenance.lua` is a proposal scaffold,
not an executable maintenance implementation. It emits provider `geo` with the
placeholder action `maintenance_geo`, and `p1_try_dark_launch_dispatch` has no
GEO dispatcher branch. This was true before Phase 5 and there is no legacy GEO
fallback to preserve or remove.

Phase 5 does not invent GEO spell/target semantics. The durable
`config.maintenance.geo` list remains preserved. A future GEO implementation
must define ordered Indi/Geo spell selection, targets, recast/range rules, and
luopan replacement behavior before adding a dispatcher branch. Until then, GEO
maintenance must not be represented as a working automated feature.

## Settings combinations

| `domain_maintenance_enabled` | Legacy marker | Result |
| --- | --- | --- |
| true | true or false | Eligible COR/BRD scheduler maintenance runs; GEO remains proposal-only |
| false | true or false | No maintenance collection, Bard lane reservation, or maintenance dispatch |

There is no setting combination that selects a maintenance fallback.

## Evidence

- `tests/replay/harness/selftest_phase5_domain_cutover.lua`
- COR proposal/action state tests
- Bard identity, sequencing, movement-safety, Pianissimo, and party buff-state
  tests
- `_G.UC_LAST_SCHED_ACTION`, maintenance timeline events, Bard lane diagnostics,
  and retained dispatcher validation globals

## Field acceptance record

| Item | Result | Evidence / disposition |
| --- | --- | --- |
| BRD maintenance | `PASS` | Redrogue BRD/WHM completed several full cycles of mob songs with no observed regression or bug. |
| COR maintenance | `PASS` | Ponponponponpon COR/DNC completed several full cycles of COR rolls with no observed regression or bug. |
| Bard Pianissimo atomicity | `PASS / PRIOR FIELD BASELINE` | The Phase 3 multibox retest passed the corrected Pianissimo JA-to-song lane behavior; the current repeated song cycles reported no regression. |
| False legacy-marker and disabled-domain cases | `AUTOMATED EVIDENCE ACCEPTED` | All current live profiles had true compatibility markers. Focused cutover tests prove marker independence, disabled collection/dispatch, and stale Bard-lane release. |
| UnifiedCombat GEO maintenance | `NOT CLAIMED` | Niightsiide GEO/RDM was a passive participant using an external GEO addon and setting camp. The existing UnifiedCombat GEO proposal scaffold is still not executable. |

The repeated BRD/COR live cycles plus focused negative control evidence satisfy
the Phase 5 maintenance exit gate.
