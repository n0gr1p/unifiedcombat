# Movement Coordinator Implementation Checklist

Purpose: replace movement-as-proposal arbitration with movement-as-coordinator behavior while preserving scheduler ownership of combat/defensive/maintenance dispatch.

Phase 4 update (2026-07-24): coordinator-based movement remains the selected
model. Scheduler, formation, party-follow, pathing, Nyzul hold, and lifecycle
movement execution now share `uc_movement_dispatcher.lua`. Follow and pathing
remain independent decision owners. See
`RFC/UnifiedCombat_scheduler_refactor_phase4_movement_ownership_decision.md`.
The Phase 4 implementation is field verified for reload, party follow, combat
movement/casting, and lifecycle stop. Live path-follow was deferred with risk
accepted; focused path execution/arbitration coverage passes.

## Scope
- Files expected:
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\unified_scheduler.lua`
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\unified_combat_core.lua`
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\uc_party_follow.lua`
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\uc_pathing.lua`
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\uc_nyzul_runtime.lua`
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\uc_lilith_easy_formation_runtime.lua`
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\uc_movement_dispatcher.lua`

## C1. Remove Movement Proposal Arbitration

Code
- [x] Remove/disable `p1_collect_movement(ctx, out)` movement proposal emission path.
- [x] Remove scheduler `provider == 'mobility'` dispatch path as the primary movement driver.
- [x] Keep movement dark-launch toggle as coordinator enable/disable gate (not proposal gate).
- [x] Ensure no movement duplicate suppression / pending-conflict path can block normal locomotion.

Validation
- [ ] Scheduler queue no longer shows movement intent rows competing with combat/defensive intents.
- [ ] Movement still runs each movement tick when enabled.

## C2. Add Movement Coordinator Tick

Code
- [x] Add dedicated movement coordinator call in scheduler tick flow (runs each tick, outside ranked selection).
- [x] Coordinator entrypoint calls core movement apply function directly.
- [x] Keep coordinator independent from action selection winner/no-winner state.

Validation
- [ ] Movement occurs even when queue top is non-movement.
- [ ] No movement starvation during high intent volume.

## C3. State Model + Role Gating

Code
- [x] Implement explicit movement mode computation:
  - `OUT_OF_COMBAT`
  - `IN_COMBAT_FIGHTER`
  - `IN_COMBAT_NON_FIGHTER`
  - `CAST_FREEZE` overlay
- [x] Reuse domain participant helpers (`UC_IsCombatParticipant`, `UC_IsMovementParticipant`, `UC_IsFollowParticipant`) consistently.
- [x] Use existing combat-follow hold (`UC_FIGHT_FOLLOW_ACTIVE_UNTIL`) only when actor is combat participant.

Validation
- [ ] Non-fighter with engine on keeps follow behavior and does not get combat-close movement.
- [ ] Fighter transitions cleanly between follow and combat movement.

## C4. Casting Freeze Coordination

Code
- [x] Add/confirm movement freeze state keyed from action-state lifecycle for spells.
- [x] Freeze prep: short settle period before spell dispatch (`run(false)` only).
- [x] Freeze active: hold `run(false)` until action-complete/fail/timeout.
- [x] Ensure JA/WS do not automatically use spell freeze unless explicitly required.
- [x] Ensure freeze timing uses `socket.gettime` consistently.

Validation
- [x] Spell casts are not self-interrupted by movement.
- [ ] JA/WS cadence is not unnecessarily frozen.

## C5. Facing Rules (Finalized Requirement)

Code
- [x] Enforce: facing applies only when there is a valid combat target.
- [x] If no valid combat target, do not issue turn command.
- [x] Preserve natural heading changes from run vectors when not facing combat target.

Validation
- [ ] No turning toward follow target or non-combat entities.
- [ ] In combat, face tracks valid combat target.

## C6. Follow + Movement Ownership Alignment

Code
- [x] Keep `uc_party_follow` suppression only for explicit combat/freeze guards.
- [x] Remove dependency on movement proposal ownership/locks for normal follow arbitration.
- [x] Maintain zone suspend/local request hard guards intact.
- [x] Route party-follow and pathing run/stop effects through the shared
  dispatcher-backed movement API without changing cadence or geometry.

Validation
- [x] Out-of-combat follow remains smooth with engine on.
- [ ] No yo-yo between follow and combat movement during fights.

## C7. Time Source Unification

Code
- [x] Replace remaining movement/follow gating uses of `os.clock` that participate in coordinator decisions with `socket.gettime` path.
- [x] Keep one fatal behavior: if `socket.gettime` unavailable, fail fast for coordinator timing.

Validation
- [ ] Hold windows (combat intent/follow hold/freeze) are stable and predictable.

## C8. Debug/Observability (In-Game Only)

Code
- [x] Add compact movement coordinator debug fields:
  - `movement_mode`
  - `movement_block_reason`
  - `freeze_remaining_s`
- [x] Ensure this is in in-game debug surfaces/logs only, not WinForms state spam.

Validation
- [ ] Debug shows clear reason when movement is suppressed.
- [ ] No UI redraw/perf regression from movement diagnostics.

## C9. Cleanup

Code
- [x] Remove dead code paths from old mobility proposal flow.
- [x] Remove unused lock members/summary tokens that only existed for movement proposal arbitration.
- [x] Keep comments updated to reflect coordinator model.

Validation
- [ ] No references to removed movement proposal family remain.

## Acceptance Suite

- [ ] A1: Engine OFF + follow ON => follow works.
- [ ] A2: Engine ON + non-fighter => follow works; no combat-close movement.
- [x] A3: Engine ON + fighter + valid target => close/fight movement + spacing/facing behavior correct.
- [x] A4: During spell cast => movement frozen, facing still allowed on valid combat target.
- [ ] A5: Post-combat => hold window respected, then return to normal follow.
- [ ] A6: Under intent load => no movement starvation/stutter from queue contention.

Field disposition:

- addon reload: pass, no Lua error;
- party follow: pass;
- combat approach/spacing/casting: pass with possible non-blocking settle-time
  fine tuning;
- lifecycle `//uc stop`: pass;
- live path-follow: deferred with risk accepted;
- Nyzul hold: no live result reported; focused runtime coverage passes.

## Rollout Notes

- Implement in order: C1 -> C2 -> C3 -> C4 -> C5 -> C6 -> C7 -> C8 -> C9.
- Run acceptance after C6, then again after C9 cleanup.
