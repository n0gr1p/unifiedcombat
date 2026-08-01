# GEO Maintenance and Camp Pulling Implementation Tracking

This file tracks implementation against
`GEO_PULLER_RFC/geo_maintenance_and_camp_pulling_rfc.md`.

## Current status

| Phase | Code status | Automated verification | Field verification |
| --- | --- | --- | --- |
| 0 — Contract and fixtures | Complete | Complete | Not applicable |
| 1 — Basic GEO maintenance | Complete | Complete | Pending |
| 2 — Entrust and luopan actions | Complete | Complete | Pending |
| 3 — Independent camp pulling | Complete | Complete | Pending |
| 4 — Pull journey resilience | Complete | Complete | Pending |
| 5 — UI polish and field acceptance | UI complete | Complete | Pending |

The implementation is default-off. Completing the automated work does not
constitute live Windower/FFXI field acceptance.

## Phase 0 — Contract and fixtures

- [x] Freeze `config.maintenance.geo` as a structured object.
- [x] Freeze `config.combat.pulling` as a structured object.
- [x] Add strict normalizer validation and deterministic legacy GEO-list
  migration.
- [x] Add profile-v2 projection and export coverage.
- [x] Add GEO and camp-puller replay fixtures.
- [x] Preserve route-hunter behavior and its existing pull executor tests.
- [x] Remove the old non-executable GEO placeholder deliberately.

Canonical operator-facing reason families are those listed in RFC section 15.
Providers may also expose a more specific `detail` value for diagnosis. New
terminal reasons include `PULL_COMBAT_DOMAIN_DISABLED`, `PULL_ZONE_CHANGE`,
`PULL_ENGINE_OFF`, and `PULL_DISABLED`.

## Phase 1 — Basic GEO maintenance

- [x] Add a pure `maintenance_geo` provider.
- [x] Emit concrete scheduler spell proposals for configured Geo and Indi
  spells.
- [x] Track luopan presence independently from the generic Indi-Colure buff.
- [x] Track exact spell identity only after owned dispatch/observation.
- [x] Hold when a pre-existing luopan or Indi effect has unknown identity.
- [x] Revalidate target identity, action resources, range, camp state, movement,
  and job eligibility at proposal commit.
- [x] Dispatch through existing scheduler command building, action-state,
  pending, and spell-wait infrastructure.

## Phase 2 — Entrust and luopan actions

- [x] Add nonblocking Entrust -> Indi -> target observation sequencing.
- [x] Require the observed Entrust buff at spell commit and dispatch the
  configured Indi directly to the resolved party member entity ID.
- [x] Add Full Circle replacement sequencing.
- [x] Add Blaze of Glory -> Geo atomic sequencing.
- [x] Replace missing luopans normally while Blaze is unavailable, track whether
  the owned luopan is Blaze-enhanced, and upgrade a normal luopan through Full
  Circle when Blaze becomes ready.
- [x] Track logical enemy fight targets independently of the selected game
  target and dispatch enemy Geo spells directly by entity ID.
- [x] Prevent Blaze from starting without a live logical enemy; when an atomic
  sequence loses its enemy, admit only camp pulling until a replacement is
  claimed and the character returns to camp.
- [x] Add optional Ecliptic Attrition and Life Cycle policies.
- [x] Complete GEO job abilities by local actor plus exact action resource ID,
  allowing luopan-targeted Ecliptic packets to release the atomic lane.
- [x] Prevent pull admission after an Entrust or Blaze consumable is observed.
- [x] Add `//uc geo status`, `//uc geo reseed`, and explicitly armed Bolster
  commands.

## Phase 3 — Independent camp pulling

- [x] Add job-independent spell or JA pull configuration.
- [x] Add quota and early-replenishment demand.
- [x] Add deterministic target ordering by configured priority, camp distance,
  then entity ID.
- [x] Add exact and substring name matching.
- [x] Enforce unclaimed, idle, full-HP, monster, valid-target, camp-leash, Z,
  ignore-list, and cooldown eligibility.
- [x] Add direct entity-ID targeting, approach, settle, action wait, reaction
  wait, and camp return states without changing the selected game target.
- [x] Reuse the shared camp anchor and scheduler pull/movement dispatchers.
- [x] Leave the route hunter and follower pull-distance gate as separate
  workflows.

## Phase 4 — Pull journey resilience

- [x] Record meaningful outbound breadcrumbs and return through them in reverse.
- [x] Use movement progress sampling with two bounded perpendicular recovery
  attempts.
- [x] Add bounded action retry, reaction timeout, and per-target cooldown.
- [x] Emit an explicit movement stop on invalid camp, engine stop, feature
  disable, combat-domain disable, and journey abort.
- [x] Publish runtime state and reason/detail diagnostics.
- [x] Add `//uc camp pullstatus`.

The first field packet should record scheduler timeline output plus the result
of `//uc camp pullstatus` at candidate selection, outbound recovery, action
dispatch, reaction, return recovery, and arrival.

## Phase 5 — UI polish and field acceptance

- [x] Add a GEO tab for durable maintenance policy.
- [x] Show GEO and SMN tabs only when the selected character has GEO or SMN
  as its main or sub job.
- [x] Add a visually separate Camp Pulling tab.
- [x] Keep UI edits offline until profile save.
- [x] Validate enabled policy before structured profile serialization.
- [x] Add command/status help text.
- [x] Publish GEO and camp-puller runtime state into the WinForms status labels.
- [ ] Run GEO enemy-Geo + self-Indi stationary-camp field check.
- [ ] Run Entrust target-cycle field check.
- [ ] Run luopan enhancement, Life Cycle, and replacement field checks.
- [ ] Run GEO-as-puller deferral/resume field check.
- [ ] Run non-GEO spell puller field check.
- [ ] Run non-GEO JA puller field check.
- [ ] Run multi-mob quota and early-replenishment field check.
- [ ] Run outbound and return obstacle field checks.
- [ ] Run shared camp set/clear/zone-mismatch field checks.
- [ ] Decide whether collision-zone learning is needed from captured evidence.

## Field acceptance record

For each run, record:

- date, character, main/sub job, zone, and camp coordinates;
- exact GEO/Indi/Entrust or pull-action policy;
- target list, quota, and leash settings;
- expected and observed state transitions;
- `//uc geo status` or `//uc camp pullstatus` output;
- scheduler diagnostic/timeline excerpt;
- outcome and any terminal reason/detail; and
- whether the scenario passed, failed, or needs a code change.

### 2026-07-29 — Niightsiide GEO/RDM spell-puller attempt

- Result: needs code change and field retest.
- Policy: `Dia II`, exact `Locus Colibri`, quota 1, 35-yalm leash,
  0.90 cast-range ratio.
- Observed: the configured pull spell completed, but ordinary combat/formation
  movement ran after the camp-puller dispatch in the same scheduler tick. It
  overrode the approach heading, drove the character into the mob, and
  repeatedly stopped or reversed the return-to-camp movement.
- Additional stall: a text-confirmed spell completion cleared action state but
  did not advance the camp-puller result state when no matching action-packet
  completion was observed.
- Change pending field retest: normal movement now yields for the full active
  camp-puller journey; text-confirmed completion/interruption advances the
  puller result; `CAMP_PULL_STATE` and `CAMP_PULL_MOVEMENT_ISOLATED` timeline
  events record target and journey geometry.
- Zone and exact camp coordinates were not captured in this attempt.

### 2026-07-29 — Niightsiide GEO/RDM follow-up

- Result: needs code change and field retest; addon was disabled to end the
  unsafe pull sequence.
- Timeline finding: the configured 1-second retry window expired while `Dia II`
  was still casting. The puller treated the in-flight action as failed, reset
  at camp, and admitted another target before the first action-packet completion
  arrived.
- Timeline finding: after a journey was selected, a later quota-satisfied
  observation did not cancel it before action dispatch.
- Change pending field retest: the puller now consults scheduler action state
  before timing out a result wait, and revalidates demand before any selected
  journey sends its pull action.
- Clarified movement/target ownership: while enabled with the combat engine
  running, camp pulling reserves movement even in `IDLE`; ordinary combat and
  formation, path, and party-follow movement may not move the puller toward
  fight targets or another anchor. Pull
  candidates are not installed as the selected game target. Approach geometry
  and action dispatch use the candidate entity ID directly.
- Timeline finding: GEO `current_enemy` incorrectly read the selected game
  target. With autotarget disabled, the selected fight mob died after Blaze of
  Glory and left the atomic Geo-Frailty step without a target while the puller
  remained in `SETTLE`.
- Change pending field retest: GEO now tracks party/alliance-claimed fight mobs
  from the scheduler mob snapshot and retains the chosen entity ID through the
  sequence. If that target dies after Blaze, the spell remains deferred while
  the camp puller claims a replacement and returns to camp; unclaimed pull
  candidates are never used as Geo spell targets.

Do not enable collision-zone learning unless obstacle evidence shows that the
bounded breadcrumb/recovery behavior is insufficient.

## Automated verification

- `lua tests/replay/harness/selftest_all_replay_fixtures.lua`
- `dotnet build UnifiedCombatWinForms/UnifiedCombatWinForms.csproj -c Debug`
- `dotnet run --project UnifiedCombatWinForms/UnifiedCombatWinForms.csproj -c Debug -- --selftest-profile-v2`
- `git diff --check`
- Source scan of `uc_geo_maintenance.lua`, `uc_camp_puller.lua`, and
  `uc_camp_puller_policy.lua` for direct command, movement, or blocking sleep
  side effects.
