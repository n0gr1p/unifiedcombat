# UnifiedCombat Unified Scheduler Design (Phase 1)

Status: Draft  
Branch: `feature/unified-scheduler-design`  
Goal: Replace siloed action execution with one scheduler that arbitrates combat, support, and movement.

## 1. Problem Statement

Current behavior is spread across specialized flows (combat, defensive support, follow, provider-specific logic).  
This creates timing collisions:

- WS overlap (DPS actors firing at the same moment)
- spell/movement interference (run state during cast windows)
- cross-provider contention (e.g., defensive vs buff upkeep vs offense)

We need one action authority that:

- evaluates all candidate actions in one place
- selects a single next action (or explicit idle/move state)
- controls movement and casting locks consistently

## 2. Scope

In scope (Phase 1):

- scheduler core contract and runtime loop
- provider contract (how modules propose actions)
- lock and priority model
- movement/cast gating model
- minimal observability for QA

Out of scope (later phases):

- full feature parity for all providers in one pass
- advanced optimization (prediction/learning)
- UI redesign beyond required controls

## 3. Core Concepts

### 3.1 Action Proposal

Providers emit proposals; scheduler chooses one.

Suggested shape:

```lua
{
  id = "cor.rolls.refresh",
  provider = "cor",
  action_type = "spell|ja|ws|move|target|idle",
  target_id = 12345,
  target_name = "Apex Crab",
  command = 'input /ja "Chaos Roll" <me>',
  priority = 70,
  urgency = 0.0,         -- optional scalar
  expires_at = now + 0.5,
  movement_policy = "must_stop|can_move|requires_range",
  min_range = 0.0,
  max_range = 21.0,
  cast_lock_s = 2.0,
  recast_key = "ability:Chaos Roll",
  reason = "roll_missing",
}
```

### 3.2 Scheduler Decision

Per tick:

1. collect valid proposals from all enabled providers
2. discard expired/invalid/blocked proposals
3. apply lock constraints
4. rank by priority/urgency/tie-breakers
5. emit one action OR no-op (`idle`)

### 3.3 Locks

Global lock classes:

- `movement_lock` (don’t issue movement while cast-critical)
- `cast_lock` (don’t issue new cast until safe)
- `target_lock` (short hold to prevent target churn)
- `action_cooldown` (local anti-spam by proposal id/recast key)

### 3.4 Movement Arbitration

Movement should be scheduler-owned:

- movement is either chosen action (`move`) or explicit suppression
- cast-required proposals can preempt movement
- follow/spacing/close-in becomes proposal-based, not side-effects

## 4. Provider Interface

Each provider implements:

- `collect(ctx) -> { proposals }`
- `on_action_result(event)` (optional)
- `enabled(settings)` (optional helper)

Initial providers:

- `combat` (targeting, WS, JA offense)
- `defensive` (heals/na/buffs)
- `geo` (buff maintenance)
- `cor` (roll maintenance)
- `brd` (song maintenance)
- `puller` (camp pull logic)
- `follow/mobility` (travel + local spacing)

## 5. Priority Bands (Initial)

- 100: emergency defensive (death prevention, hard cleanse)
- 85: cast-window actions (short-lived high-impact buff/utility)
- 75: maintenance buffs (geo/cor/brd refresh)
- 70: offense core (WS/JA attack decisions)
- 60: target control / add management
- 50: movement maintenance (follow/spacing/camp position)
- 0: idle

## 6. Data/Context Contract (`ctx`)

Scheduler context should include:

- player state, status, HP/MP/TP, buffs/debuffs
- target state and party target map
- recasts and cooldown snapshots
- zone/state guards
- recent actions/events (`0x028`, `0x029`)
- current lock state
- settings/profile snapshot

## 7. Observability

Add scheduler diagnostics:

- selected proposal id/reason/provider
- blocked proposals with top rejection reason
- lock state summary
- tick sequence + duration

Expose to:

- remote state payload (`scheduler_action`, `scheduler_provider`, details)
- optional debug logs

## 8. Rollout Plan

Phase A:

- implement scheduler scaffold + provider interface
- move existing combat provider under scheduler (single provider mode)

Phase B:

- add defensive provider proposals
- add movement provider proposals (follow/spacing/close)

Phase C:

- integrate GEO/COR/BRD providers
- integrate puller provider

Phase D:

- remove legacy direct action paths
- finalize QA and cutover

## 9. Open Decisions

1. Should provider `collect()` be hard time-budgeted per tick?
2. Do we permit multiple actions in one tick (e.g., target + action), or one action max?
3. Should movement be entirely proposal-driven from Day 1, or phased behind feature flag?
4. How strict should anti-thrash target lock be under add-control?

