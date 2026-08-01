# UnifiedCombat Scheduler Refactor — Phase 4 Exit Audit

Audit date: 2026-07-24

Baseline commit: `3fcbcd0c5a0be1ee8bdaa87ad9f9caeedf3358aa`

Audited state: uncommitted Phase 4 complete working tree on
`scheduler-refactor`

Verdict: **PASS / FIELD VERIFIED WITH ACCEPTED PATH-FOLLOW RISK**

## RFC requirements

| Requirement | Result | Evidence |
| --- | --- | --- |
| Route scheduler movement coordinator effects through dispatcher or movement facade | `PASS` | `run_movement_coordinator_tick` injects `uc_scheduler_movement_facade.lua`; that facade now delegates to `uc_movement_dispatcher.lua`, which dispatches through `uc_scheduler_dispatcher.lua`. |
| Document follow/pathing exceptions and ownership | `PASS` | `RFC/UnifiedCombat_scheduler_refactor_phase4_movement_ownership_decision.md` records current and target ownership. The former direct-run exceptions are removed. |
| Decide whether follow/pathing remain independent or scheduler-owned | `PASS` | Follow/pathing remain independent movement decision owners and use the shared execution API. They are not ranked proposals. |
| Preserve smooth follow behavior | `PASS / FIELD VERIFIED` | Party follow passed live acceptance. Follow cadence, geometry, thresholds, ownership globals, and suppression rules remain unchanged; exact vector/stop call shapes and arbitration tests also pass. |

## Ownership audit

| Owner | Decision ownership | Execution after Phase 4 | Direct `windower.ffxi.run(...)` |
| --- | --- | --- | ---: |
| Scheduler coordinator | Scheduler plus `core.apply_movement_for_scheduler` compatibility helper | `uc_scheduler_movement_facade.lua` → `uc_movement_dispatcher.lua` → scheduler dispatcher | 0 |
| Lilith formation | `uc_lilith_easy_formation_runtime.lua` | Shared movement adapter | 0 |
| Party follow | `uc_party_follow.lua` | Shared movement adapter | 0 |
| Pathing | `uc_pathing.lua` | Shared movement adapter | 0 |
| Nyzul hold | `uc_nyzul_runtime.lua` | Shared movement adapter | 0 |
| Lifecycle reset | `UnifiedCombat.lua` | Shared movement adapter | 0 |
| Legacy core | `unified_combat_core.lua` | `core.legacy_movement_executor` and legacy pull/tank paths | 14 |

The 14 legacy core direct-run sites are not a Phase 4 omission. The
responsibility map and movement ownership decision classify them as Phase 5
domain-cutover work. `core.apply_movement_for_scheduler` already requires an
injected executor and does not silently select the legacy executor.

Legacy engines and the shared `lor` actor library also retain their previously
allowlisted movement surfaces. They are outside the active UnifiedCombat
scheduler movement cutover.

## Behavior-preservation audit

The cutover preserves:

- party-follow 0.05-second IPC/update behavior and prerender decision cadence;
- follow minimum/maximum geometry and vector normalization;
- path-follow 0.20-second cadence, route decisions, pause reasons, and resume
  index behavior;
- movement owner and lock globals;
- combat-intent, pull, cast, formation, and Nyzul suppression;
- Nyzul role state, infinite hold, acknowledgement flow, and IPC ownership;
- formation headings, goals, reasons, and run-active state;
- lifecycle reset ordering;
- scheduler movement mode/block diagnostics and
  `scheduler_dark_launch_movement` gating;
- the one-argument heading, two-argument vector, zero-argument forward, and
  `run(false)` stop Windower call shapes.

No movement decision was converted into a ranked proposal. No proposal key,
priority band, provider order, rejection taxonomy, or public scheduler wrapper
was changed.

## Verification

Completed:

- `lua tests/replay/harness/selftest_movement_dispatcher_phase4.lua`
- `lua tests/replay/harness/selftest_formation_movement_dispatcher_phase4.lua`
- `lua tests/replay/harness/selftest_scheduler_movement_facade.lua`
- `lua tests/replay/harness/selftest_movement_priority_arbitration.lua`
- `lua tests/replay/harness/selftest_nyzul_runtime.lua`
- `lua tests/replay/harness/selftest_side_effect_inventory.lua`
- `lua tests/replay/harness/selftest_runtime_parse.lua`
- `lua tests/replay/harness/selftest_all_replay_fixtures.lua`

Results:

- runtime parse: 84/84 files;
- aggregate replay/static suites: 116/116;
- side-effect inventory: 133 runtime files, 19 allowlisted files, 285 exact
  file-pattern checks, 239 observed hits;
- focused Phase 4 adapter/static contract: pass;
- migrated direct-run call sites removed: 11.

## Live acceptance record

| Test | Result | Evidence / disposition |
| --- | --- | --- |
| Reload UnifiedCombat on test characters | `PASS` | No Lua error observed. |
| Party follow | `PASS` | Follow enabled and operated successfully. |
| Path-follow | `DEFERRED / RISK ACCEPTED` | Live path-follow was not performed. The user explicitly accepted this risk; focused path execution and arbitration tests pass. |
| Combat approach and spacing | `PASS` | Fighter approach and spacing behaved acceptably. Possible settle-time fine tuning was noted as non-blocking. |
| Casting movement coordination | `PASS` | Combat/casting behavior was accepted in the same field session. |
| Lifecycle `//uc stop` | `PASS` | Movement stopped successfully. |
| Nyzul hold | `NOT FIELD TESTED` | No live result was reported. Focused Nyzul runtime/IPC hold coverage passes; live testing was conditional on the workflow being available. |

## Conclusion

The implementation satisfies the Phase 4 movement ownership requirements.
Follow smoothness, combat movement/casting, lifecycle stop, and reload safety
have live evidence. Path-follow live parity was explicitly deferred with its
risk accepted, and Nyzul retains focused runtime coverage without a claimed
field result. These dispositions are recorded rather than overstated.

Phase 4 is `DONE / FIELD VERIFIED`. Legacy core movement remains Phase 5 scope.
