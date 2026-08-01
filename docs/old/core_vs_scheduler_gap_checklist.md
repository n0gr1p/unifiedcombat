# Core vs Scheduler Gap Checklist

Branch context: `feature/unified-scheduler-design-clean`  
Purpose: migrate from mixed core-tick ownership to a scheduler-owned runtime model while preserving world-travel follow behavior.

## Architecture Target

1. Follow works with engine OFF (travel mode).
2. Engine ON activates scheduler/runtime domains.
3. Scheduler-owned movement can preempt/suppress follow when required (combat/tank/pull/cast locks).
4. Core tick becomes orchestration shell only (state snapshot + provider collect + scheduler dispatch), not behavior owner.

---

## Domain Model (Required)

Add explicit domain gates (settings + runtime predicates):

- `engine_enabled` (global runtime loop gate)
- `domain_combat_enabled`
- `domain_defensive_enabled`
- `domain_movement_enabled`
- `domain_maintenance_enabled`
- `domain_follow_enabled` (or follow as movement subdomain with explicit travel override)

Travel guarantee:
- `domain_follow_enabled` may run even when `engine_enabled == false`.

Scheduler precedence:
- if `engine_enabled == true` and scheduler movement lock/intent is active, follow must yield.

---

## Current Gap Summary

Mixed ownership still exists:

1. Targeting/arbitration primarily in `unified_combat_core.lua`.
2. Follow suppression keyed to global engine/combat signals in `uc_party_follow.lua`.
3. Movement ownership split across core + scheduler dark-launch paths.
4. Pull/tank edge logic partly embedded in core run loop.
5. Scheduler dispatch active, but not sole authority for all movement/targeting decisions.

---

## Migration Workboard

## G1 - Domain Gate Foundation

Code:
- [x] Add canonical domain settings (with migration map).
- [ ] Add runtime predicate helpers:
  - [x] `is_combat_participant()`
  - [x] `is_defensive_participant()`
  - [x] `is_movement_participant()`
  - [x] `is_follow_participant()`
- [x] Replace ad-hoc `Start_Engine` checks in follow suppression with domain-aware predicates (combat suppression now scoped to combat participants only).

Files:
- `UnifiedCombat.lua`
- `unified_combat_core.lua`
- `uc_party_follow.lua`
- `remote_bridge.lua`
- `UnifiedCombatWinForms/*`

Acceptance:
- [ ] Follow works with engine OFF.
- [ ] No combat/maintenance/defensive dispatch when engine OFF.
- [ ] Enabling engine does not force follow suppression unless movement/combat predicates require it.

---

## G2 - Follow Ownership Split (Travel vs Combat Suppression)

Goal: preserve travel follow while allowing scheduler movement to take control under combat/mobility conditions.

Code:
- [x] Refactor `combat_engine_suppresses_follow()` in `uc_party_follow.lua`:
  - [x] remove raw “engine on => suppress” semantics for non-combat-participant profiles.
  - [x] suppress only when scheduler/core sets explicit movement ownership lock.
  - [x] maintain pull-spell/tank-cast stop conditions as hard suppressors.
- [ ] Add explicit movement ownership signal:
  - [x] `UC_MOVEMENT_OWNER = follow|scheduler|core|none` (core + scheduler writers added; follow reader added)
  - [x] `UC_MOVEMENT_LOCK_UNTIL` (core + scheduler lock window wiring added)
- [x] On suppress transition, hard-stop stale run vector once (`run(false)`).

Acceptance:
- [ ] Defensive-only WHM keeps following during party combat unless explicit movement lock requires hold.
- [ ] No straight-line drift when follow is suppressed/resumed.

---

## G3 - Target Selection Migration to Scheduler

Move target decision authority out of core:

Code:
- [x] Extract current target arbitration into provider proposal generation:
  - [x] prime/aggressive rules (parity slice via `core.select_target_for_scheduler` using `find_candidate_target`).
  - [x] partner-follow exclusions (inherited from core candidate logic).
  - [x] target-ignore list (inherited from core candidate logic).
  - [x] add-control/fight-leader preference (inherited from core candidate logic).
  - [x] path-hunter eligibility filters (inherited from core candidate logic).
- [x] Scheduler selects target intent as proposal family (initial `target.acquire.primary`).
- [x] Core no longer performs direct nearest scan/arbitration in main tick when scheduler combat dark-launch is enabled (core consumes current selected target; scheduler owns acquisition).

Files:
- `unified_combat_core.lua`
- `unified_scheduler.lua`
- `uc_targeting_common.lua`
- `uc_partner_list.lua`
- `uc_target_ignore.lua`

Acceptance:
- [ ] Partner-follow target separation remains correct after migration.
- [ ] No duplicate target fighting regressions.
- [ ] Switch-on-kill behavior remains stable.

---

## G4 - Movement Proposal Parity (Scheduler-Owned)

Code:
- [x] Port movement intents from core to scheduler movement provider:
  - [x] close range (via scheduler-owned `core_movement_tick` dispatch path)
  - [x] retreat/spacing (via scheduler-owned `core_movement_tick` dispatch path)
  - [x] face/stop (via scheduler-owned `core_movement_tick` dispatch path)
  - [x] follow-yield windows (preserved via core movement logic now invoked by scheduler path)
  - [x] puller-gate exceptions (preserved via core movement logic now invoked by scheduler path)
- [x] Move fight-follow hold logic to scheduler movement state (ownership path moved; hold semantics preserved through scheduler-dispatched core movement tick).
- [x] Convert core movement side-effects into proposal annotations instead of direct `run()` calls (scheduler now owns movement dispatch in dark-launch movement mode; core direct movement call suppressed in that mode).

Acceptance:
- [ ] Movement behavior parity with current stable build.
- [ ] Spacing/follow/combat no longer fight each other.
- [ ] Scheduler lock summary reflects movement ownership decisions.

---

## G5 - Pull/Tank Operational Migration

Code:
- [x] Pull action lifecycle moved to scheduler state machine:
  - [x] acquire target (scheduler `target_control` + `pull_control` proposal families)
  - [x] range approach (scheduler `pull_control` dispatch delegates to core pull state machine under scheduler ownership)
  - [x] settle (scheduler-owned pull dispatch invokes existing settle gates through scheduler path)
  - [x] cast/JA dispatch (scheduler `pull_control` dispatch path)
  - [x] timeout/ignore cooldown (preserved through existing pull/hunter lifecycle now invoked via scheduler path)
- [x] Tank enmity movement + action prep fully scheduler-owned.
- [x] Remove remaining core-only pull/tank movement overrides (core pull dispatch disabled when scheduler combat dark-launch is enabled; tank dispatch already scheduler-owned in that mode).

Acceptance:
- [ ] Pull spells no self-interrupt due to competing movement.
- [ ] Tank enmity recovery works without core fallback dispatch path.

---

## G6 - Core Tick Decomposition

Goal: reduce `run_unified_combat()` to orchestration shell.

Code:
- [x] Keep only:
  - [x] snapshot building
  - [x] scheduler tick call
  - [x] minimal compatibility telemetry
- [x] Remove direct command dispatch from core for migrated domains.
- [x] Remove duplicated locks/timers now owned by scheduler.

Acceptance:
- [ ] With dark-launch toggles enabled for all domains, behavior unchanged vs previous stable path.
- [ ] Core direct dispatch paths can be disabled with no loss of functionality.

---

## G7 - Cutover and Cleanup

Code:
- [ ] Flip scheduler domains from dark-launch to default-on.
- [ ] Remove legacy fallback branches for migrated behavior.
- [ ] Keep only explicit emergency guards (not silent behavioral fallback).
- [ ] Update UI wording:
  - [ ] replace “Run combat engine” with “Run UC engine” (or equivalent).
  - [ ] expose per-domain toggles clearly.

Docs:
- [ ] Update `docs/scheduler_work_tracking.md`.
- [ ] Update README architecture section to scheduler-owned model.

Acceptance:
- [ ] Engine OFF + Follow ON travel mode works.
- [ ] Engine ON scheduler domains behave deterministically.
- [ ] No mixed movement ownership code paths remain.

---

## High-Risk Areas (Track Closely)

1. Follow suppression transitions causing stale run vectors.
2. Partner-follow arbitration after target migration.
3. Pull spell settle and cast lock timing.
4. Tank enmity target/range handoff between movement and action dispatch.
5. BRD/COR maintenance jitter under acting lock.

---

## Test Matrix (Must Pass Before Final Cutover)

1. Travel mode:
- [ ] engine OFF, follow ON, all followers zone correctly and stay cohesive.

2. Defensive-only follower:
- [ ] engine ON, defensive ON, combat OFF, follow ON: unit follows while healing/buffing.

3. Full combat group:
- [ ] engine ON all domains: targeting, movement, WS, JA, buffs remain stable.

4. Tank scenario:
- [ ] enmity violations recovered without target churn/runaway movement.

5. Hunter/pathing scenario:
- [ ] path follow + hunter engage/return behavior stable with scheduler movement ownership.

---

## Notes

- This checklist intentionally sequences movement/follow/targeting migration before final core cutover.
- Do not remove core fallback slices until each corresponding scheduler domain has parity validation.
