# UnifiedCombat Scheduler Refactor — Phase 5 Field Acceptance Plan

Status date: 2026-07-24

State: **COMPLETED WITH ACCEPTED RISKS**

## Recorded field result

The current live characters and profiles completed several full mob cycles with
no observed regression or bug:

| Character | Job | Coverage |
| --- | --- | --- |
| Nyoourke | PLD/WAR | Tank and normal combat participation |
| Terrasjr | MNK/WAR | DPS, target/engage, approach, spacing, and combat actions |
| Niightsiide | GEO/RDM | Passive party participant, external GEO addon, and camp-anchor setup |
| Redrogue | BRD/WHM | BRD song maintenance over repeated mob cycles |
| Ponponponponpon | COR/DNC | COR roll maintenance over repeated mob cycles |

This is accepted as comprehensive positive-path Phase 5 parity coverage for the
profiles currently used in the live party.

A repository sanity check validated each exact character/job v2 file and
confirmed all five authoritative domains, `profile_v2_autoload`, and
`profile_v2_auto_reload_on_change` are `true`. The embedded profile metadata
matches the filename selected by the runtime's character/main/subjob path
derivation.

The following limitations are recorded rather than treated as completed field
tests:

- path-follow was not tested; the user explicitly accepted this risk;
- all five live profiles have their four legacy
  `scheduler_dark_launch_*` values set to `true`, so legacy-marker independence
  is established by replay/static tests, not by this field session;
- one-domain-at-a-time disable cases were not separately exercised live; their
  gating and no-fallback behavior are established by focused replay/static
  tests;
- Niightsiide used an external GEO addon, so this session is not evidence for a
  UnifiedCombat GEO-maintenance implementation;
- isolated pull, skillchain-controlled WS, HealBot, Doom/Holy Water, formation,
  and Nyzul cases were not specifically reported in this session.

Earlier Phase 3/4 field acceptance remains relevant baseline evidence for
defensive casting, Bard Pianissimo atomicity, party follow, cast movement
lockout, and lifecycle stop.

## Configuration contract

The WinForms **Scheduler** tab now exposes the authoritative domain controls:

- `domain_combat_enabled`
- `domain_defensive_enabled`
- `domain_movement_enabled`
- `domain_maintenance_enabled`
- `domain_follow_enabled`

The four `scheduler_dark_launch_*` values are displayed read-only as legacy
profile markers. They do not control execution.

Domain values are durable active-profile configuration. After changing them in
WinForms:

1. save the profile;
2. run `//uc profilev2 reload`, or reload UnifiedCombat;
3. confirm the Scheduler tab reflects the applied values.

Do not treat an unsaved checkbox change as an applied runtime configuration.

## Baseline setup

Use the known Phase 3/4 multibox party:

- DPS/fighter: Terrasjr MNK/WAR or another known combat profile;
- tank: the known tank profile;
- BRD maintenance character;
- COR maintenance character;
- internal or HealBot defensive caster.

Set the applicable four scheduler domains to `true`. Leave
`domain_follow_enabled = true` on the party-follow test character. Preserve the
existing feature settings for combat, defense, BRD, COR, pathing, and follow.

The original plan requested at least one live combat pass with a false legacy
combat marker and `domain_combat_enabled = true`. Existing false-marker v2
examples include:

- `data/profiles_v2/etamame_DRG_DNC.lua`;
- `data/profiles_v2/niightsiide_PUP_DNC.lua`;
- `data/profiles_v2/ponponponponpon_PUP_DNC.lua`;
- `data/profiles_v2/terrasjr_DNC_WAR.lua`.

The first three have all four legacy markers false. That optional live
combination was not used in the recorded party. The automated cutover test
proves every domain ignores opposite marker values, and that evidence is
accepted for Phase 5 closeout.

## Original positive acceptance matrix

### Reload and ownership

- [ ] Reload/apply all test profiles with no Lua error.
- [ ] On one false-marker profile, confirm the enabled combat domain still
  acquires and engages a target.

### Combat

- [ ] Acquire and engage a target.
- [ ] Approach, settle, and spacing behave normally.
- [ ] Execute one configured JA and one WS.
- [ ] Exercise pull approach/action if the active profile uses pulling.
- [ ] Exercise tank enmity/add control on the applicable character.
- [ ] If practical, confirm one skillchain-controlled WS; otherwise record the
  focused replay coverage as the accepted evidence.

### Defensive

- [ ] Internal provider performs an applicable Cure, NA, or configured buff.
- [ ] HealBot provider performs one applicable action if HealBot is part of the
  field setup.
- [ ] Defensive casting stops movement and releases the movement lock after the
  action.
- [ ] Pending Cure suppression does not produce duplicate casts.
- [ ] Exercise Doom/Holy Water only if already enabled in the test profile.

### Maintenance

- [ ] COR performs the configured roll lifecycle, including any Double-Up,
  Snake Eye, or Fold state naturally reached by the test.
- [ ] BRD refreshes general songs.
- [ ] BRD completes one targeted Pianissimo JA-to-song sequence.
- [ ] No unrelated action enters between Pianissimo and its song.
- [ ] No BRD maintenance action leaves an orphaned run vector.
- [ ] GEO is not a Phase 5 field-pass item because no executable GEO
  maintenance contract exists.

### Movement and follow

- [ ] Combat approach, spacing, settle, and automatic stop pass.
- [ ] Cast movement lock and release pass.
- [ ] Party follow works with `domain_follow_enabled = true`.
- [ ] Party follow still works when `domain_movement_enabled = false`; the
  follow domain is independent.
- [ ] A known path runs with `domain_movement_enabled = true`.
- [ ] `//uc stop` stops an active movement vector.
- [ ] Nyzul hold may be deferred if that workflow is unavailable; record the
  accepted risk.

## Original negative domain controls

Apply one disabled domain at a time by saving and running
`//uc profilev2 reload`. Restore it before moving to the next row.

| Disabled setting | Required result |
| --- | --- |
| `domain_combat_enabled` | No target acquisition, engage, JA, WS, pull, tank-enmity, or add-control action |
| `domain_defensive_enabled` | No Doom prepass, internal defense, HealBot defense, or enemy-buff removal |
| `domain_maintenance_enabled` | No COR or BRD upkeep action and no stale BRD lane block |
| `domain_movement_enabled` | No scheduler/path movement; if path owns the current run vector when the profile is applied, it stops |
| `domain_follow_enabled` | No party-follow movement |

For the path-stop check:

1. run a known path with movement enabled;
2. uncheck the movement domain in WinForms and save;
3. while the path owns movement, run `//uc profilev2 reload`;
4. confirm the character stops and the path does not issue another run vector;
5. restore the movement domain, save, and reload before continuing.

## Pass-report format

Report each section as `pass`, `fail`, or `deferred with accepted risk`, plus:

- character/job used;
- legacy marker state on the false-marker combat pass;
- any observed Lua error or incorrect block reason;
- any behavior that differs from the Phase 3/4 baseline.
