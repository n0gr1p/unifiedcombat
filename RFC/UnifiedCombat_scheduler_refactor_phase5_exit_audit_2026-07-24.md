# UnifiedCombat Scheduler Refactor — Phase 5 Exit Audit

Audit date: 2026-07-24

Baseline commit: `fe4de055580860949b24a1134b7313f6f917641a`

Audited state: uncommitted Phase 5 complete working tree on
`scheduler-refactor`

Verdict: **PASS / FIELD VERIFIED WITH ACCEPTED PATH-FOLLOW RISK**

## RFC requirements

| Requirement | Result | Evidence |
| --- | --- | --- |
| Define unambiguous domain ownership terminology | `PASS` | `UnifiedCombat_scheduler_refactor_phase5_ownership_terminology.md` defines `domain_*_enabled` as runtime authority and the old dark-launch fields as compatibility data only. |
| Retain serialized compatibility keys during migration | `PASS` | WinForms still reads/writes the four `scheduler_dark_launch_*` keys, displays them read-only, and exposes the five authoritative domain controls. |
| Cut combat over with no core fallback | `PASS` | `unified_engine.lua` calls only `scheduler.process_tick`; combat collection/dispatch is domain-gated, and scheduler pull requires `uc_scheduler_pull_executor.lua`. |
| Cut defensive behavior over with no scheduler-local fallback | `PASS` | The defensive domain gates the Doom prepass, waits, provider collection, and dispatch. Post-ranking direct internal/HealBot calls are removed. |
| Cut maintenance behavior over | `PASS` | The maintenance domain gates COR/BRD collection, Bard lane ownership, and dispatch. No engine/core fallback exists. |
| Cut movement behavior over | `PASS` | Scheduler movement and pathing honor the movement domain; follow remains independently governed by the follow domain; active owners execute through the shared dispatcher-backed movement API. |
| Preserve behavior through automated and field evidence | `PASS WITH RECORDED LIMITATIONS` | Lua replay/static suites, side-effect inventory, WinForms build/self-test, prior Phase 3/4 field evidence, and the current five-character multibox session all pass. |

## Runtime ownership audit

| Domain | Authoritative gate | Active execution | Legacy fallback |
| --- | --- | --- | --- |
| Combat | `domain_combat_enabled` | Scheduler-ranked dispatcher path | None from the engine |
| Defensive | `domain_defensive_enabled` | Scheduler defensive provider and dispatcher/delegated HealBot path | None after ranking |
| Maintenance | `domain_maintenance_enabled` | Scheduler COR/BRD path and Bard action lane | None |
| Movement/pathing | `domain_movement_enabled` | Shared movement dispatcher | None from the engine |
| Party follow | `domain_follow_enabled` | Independent follow decisions through shared movement dispatcher | None |

The four `scheduler_dark_launch_*` values remain serialized and visible only
for compatibility and diagnostics. They do not participate in active runtime
ownership decisions.

## Automated verification

Completed before the field report:

- runtime parse: 86/86 runtime Lua files;
- aggregate replay/static runner: 118/118 suites;
- side-effect inventory: 135 runtime files, 19 allowlisted files, 285 exact
  file-pattern assertions, and 236 observed tracked hits;
- WinForms build: zero warnings and zero errors;
- WinForms structured-profile v2 self-test: pass;
- live-party profile sanity check: all five exact character/job v2 files
  validate, match their embedded character/main/sub metadata, enable all five
  authoritative domains, and enable v2 autoload plus file-change auto-reload;
- focused domain cutover, scheduler pull executor, movement arbitration,
  provider, dispatcher, Bard, COR, defensive, target, engage, Sleep, and
  lifecycle suites: pass;
- active engine/scheduler/provider/pathing marker search: no runtime ownership
  dependency on `scheduler_dark_launch_*`.

The validated profile files were:

- `data/profiles_v2/nyoourke_PLD_WAR.lua`;
- `data/profiles_v2/terrasjr_MNK_WAR.lua`;
- `data/profiles_v2/niightsiide_GEO_RDM.lua`;
- `data/profiles_v2/redrogue_BRD_WHM.lua`;
- `data/profiles_v2/ponponponponpon_COR_DNC.lua`.

`uc_profile_v2.default_export_path` derives those filenames from the live
player's character, main job, and subjob. `UnifiedCombat.lua` validates and
applies that exact path when v2 autoload is enabled. This proves the on-disk
configuration and selection contract. The earlier successful reload and live
behavior report provide the runtime evidence that the profiles applied without
an observed error.

## Live acceptance record

The current live characters and profiles completed several full cycles of mob
songs and COR rolls with no observed regression or bug:

| Character | Job | Recorded coverage |
| --- | --- | --- |
| Nyoourke | PLD/WAR | Tank and normal combat participation |
| Terrasjr | MNK/WAR | DPS, target/engage, combat movement, and actions |
| Niightsiide | GEO/RDM | Passive participant using an external GEO addon; camp-anchor setup |
| Redrogue | BRD/WHM | Repeated BRD song maintenance |
| Ponponponponpon | COR/DNC | Repeated COR roll maintenance |

This party provides broad simultaneous positive-path coverage across combat,
movement, Bard maintenance, COR maintenance, and party interaction. Prior
Phase 3/4 live acceptance supplies direct evidence for defensive spell casting,
Bard Pianissimo atomicity, cast movement lockout, party follow, and lifecycle
stop.

## Recorded limitations and accepted risks

- Live path-follow remains untested and is explicitly accepted risk. Focused
  path execution, ownership, arbitration, and movement-domain stop tests pass.
- The five current live profiles have all four legacy compatibility markers set
  to `true`. False-marker independence is proven by replay/static tests, not by
  this live session.
- The one-domain-at-a-time disable matrix was not separately performed live.
  Disabled-domain behavior and absence of fallback execution are proven by the
  focused domain-cutover tests.
- Niightsiide used an external GEO addon. No UnifiedCombat GEO-maintenance
  implementation or field pass is claimed; the existing proposal-only scaffold
  remains accurately documented.
- Pull, skillchain-controlled WS, HealBot, Doom/Holy Water, formation, and
  Nyzul were not isolated in the current report. Their focused tests remain
  green, and no regression was observed in the reported party cycles.

## Phase 6 boundary

Phase 5 completion does not delete every compatibility surface. Phase 6 still
owns:

- deletion of unreachable legacy combat, defensive, and movement execution
  branches in `unified_combat_core.lua` and scheduler dead helpers;
- removal or deliberate retention of `_G.UC_CoreCombatTickOnce`;
- retirement or migration of serialized `scheduler_dark_launch_*` keys after
  profile compatibility is addressed;
- renaming old dark-launch diagnostic/helper terminology where public
  compatibility permits;
- removal of duplicate helpers and simplification of the scheduler facade
  without changing proposal keys, priority bands, rejection taxonomy, provider
  order, or public behavior.

## Conclusion

The Phase 5 domain cutover is complete. Active runtime ownership is controlled
only by the authoritative domain settings, the engine and scheduler-local
fallback paths are closed, and automated plus multibox field evidence supports
behavior parity. The unperformed path-follow field test is retained as an
explicitly accepted risk rather than overstated as a pass.
