# UnifiedCombat Scheduler Refactor — Phase 4 Movement Ownership Decision

Status: **accepted for Phase 4 implementation**

Date: 2026-07-24

Canonical location: `RFC/UnifiedCombat_scheduler_refactor_phase4_movement_ownership_decision.md`

This file is the RFC-folder replacement for the RFC's originally proposed
`docs/movement_ownership_decision.md`.

## Decision

UnifiedCombat will keep domain-specific movement decision owners, but every
active UnifiedCombat movement owner will execute run, stop, turn, and mover
operations through one dispatcher-backed movement API.

Phase 4 does not convert movement into ranked scheduler proposals. Follow and
pathing remain independent decision systems because their high-frequency
position sampling and smooth movement cadence are separate from combat action
ranking. They must continue to yield through the existing movement owner,
movement lock, combat-intent, pull, cast, formation, and Nyzul gates.

The shared execution API is `uc_movement_dispatcher.lua`.

## Current and target ownership

| Domain | Decision owner | Phase 3 execution state | Phase 4 target |
| --- | --- | --- | --- |
| Scheduler combat movement | `run_movement_coordinator_tick` plus `core.apply_movement_for_scheduler` | Injected `uc_scheduler_movement_facade` | Preserve decisions and route the facade through the shared movement API |
| Cast freeze | Scheduler movement coordinator | Dispatcher-owned `run_stop`; publishes existing block reasons | Preserve exact stop and block-reason behavior |
| Lilith formation | `uc_lilith_easy_formation_runtime.lua` | Locally constructed dispatcher intents | Route through the shared movement API; retain formation decision ownership |
| Party follow | `uc_party_follow.lua` | Direct `windower.ffxi.run` | Route run/stop through the shared movement API; retain follow cadence, geometry, IPC, and zone replay |
| Path follow | `uc_pathing.lua` | Direct `windower.ffxi.run` | Route run/stop through the shared movement API; retain path cadence, geometry, and pause rules |
| Nyzul hold | `uc_nyzul_runtime.lua` | Direct `windower.ffxi.run(false)` | Route stop through the shared movement API; retain Nyzul IPC and hold ownership |
| Lifecycle reset | `UnifiedCombat.lua` | Direct `windower.ffxi.run(false)` | Route stop through the shared movement API |
| Legacy core execution | `unified_combat_core.lua` | Direct movement through `core.legacy_movement_executor` and legacy pull/tank paths | Remain explicitly allowlisted until Phase 5 domain cutover |

## Scheduler coordinator and core boundary

`run_movement_coordinator_tick` remains the scheduler-owned movement
coordinator. It is responsible for:

- `scheduler_dark_launch_movement` gating;
- movement-domain participation;
- Nyzul and formation priority;
- cast status, spell cooldown, and active-spell freeze;
- movement mode and block-reason diagnostics;
- calling `core.apply_movement_for_scheduler`.

`core.apply_movement_for_scheduler(settings, movement_executor)` remains a
movement decision compatibility helper. It must receive an executor and must
not select a direct executor internally. The scheduler injects an executor
whose effects are routed through the shared movement API.

The direct `core.legacy_movement_executor` and direct pull/tank movement sites
belong to the legacy core execution domain. Migrating or removing those paths
would change domain cutover rather than movement-adapter ownership, so that
work remains Phase 5.

## Arbitration contract

Phase 4 preserves the existing arbitration fields and their meanings:

- `_G.UC_MOVEMENT_OWNER`
- `_G.UC_MOVEMENT_LOCK_UNTIL`
- `_G.UC_COMBAT_INTENT_UNTIL`
- `_G.UC_PREENGAGE_APPROACH_ACTIVE`
- `_G.UC_PULL_APPROACH_UNTIL`
- `_G.UC_PULL_SPELL_WAITING`
- `_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL`
- `_G.UC_MOVEMENT_MODE`
- `_G.UC_MOVEMENT_BLOCK_REASON`

The shared movement API executes already-made movement decisions. It does not
silently override or reinterpret ownership. Conflicting owners continue to
yield through the existing gates, which keeps the ownership decision visible
at the domain boundary.

## Cast freeze

Casting status, the scheduler spell cooldown, and active spell action state
remain hard movement stops. These branches retain their established
`MOVE_COORD_*` block reasons, cancel any active scheduler or formation run
vector, and refresh bounded scheduler movement ownership. Follow and pathing
continue to observe the owner/lock gates and must not restart movement during
the cast hold.

## Follow and pathing decision

Party follow and pathing remain independent movement systems in Phase 4.

They are not promoted into ranked proposals because:

- their cadence is movement-driven rather than action-economy-driven;
- putting every position update into the ranked queue risks visible stutter;
- their current suppression rules already express priority against combat,
  formation, cast, pull, and Nyzul movement;
- proposal conversion would be a behavior change outside this phase.

Their temporary direct-run exceptions end in Phase 4. Their IPC, packet replay,
route selection, follow geometry, and pause logic remain locally owned and
explicitly inventoried.

## Nyzul, formation, and lifecycle decision

Nyzul retains its local role/IPC state and continues to assert an infinite
movement hold while a character is parked. Only its local stop effect moves
behind the shared API.

Formation retains its encounter-specific evaluation and scheduler ownership
label. Its existing dispatcher intent construction is consolidated behind the
same shared API without changing headings, goals, reasons, or run-active state.

Lifecycle reset retains its current global reset order and performs the final
movement stop through the shared API.

## Proposal-model decision

Movement remains coordinator-based for this phase. A later proposal-based
movement model is neither approved nor required by this decision. The dormant
vector proposal path documented in `docs/vector_run_reachability_decision.md`
must not be reconnected as a side effect of Phase 4.

## Phase 4 acceptance

Phase 4 is complete when:

- this decision is reflected in runtime wiring;
- scheduler, formation, follow, pathing, Nyzul, and lifecycle movement effects
  use `uc_movement_dispatcher.lua`;
- no direct `windower.ffxi.run(...)` calls remain in those owners;
- legacy core movement remains explicitly classified as Phase 5 scope;
- focused adapter and ownership tests pass;
- the repository runtime parse, side-effect inventory, and aggregate replay
  suite pass;
- a short live Windower smoke test confirms follow, pathing, combat movement,
  cast stop/lockout, Nyzul hold when available, and lifecycle stop behavior.

## Exit disposition

Field acceptance passed for addon reload, party follow, combat
approach/spacing/casting, and lifecycle `//uc stop`. The user explicitly
deferred live path-follow testing and accepted that residual risk; focused path
execution and arbitration coverage passes. Nyzul live testing was not reported
and remained conditional on the workflow being available; focused runtime/IPC
hold coverage passes. The Phase 4 exit audit records these limitations without
claiming unperformed field tests.
