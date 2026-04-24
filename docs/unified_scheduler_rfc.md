# RFC: UnifiedCombat Unified Scheduler (Phase 1)

Status: Draft  
Owner: UnifiedCombat  
Branch: `feature/unified-scheduler-design`  
Related:

- [unified_scheduler_design.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_design.md)
- [unified_scheduler_phase1_amendment.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_phase1_amendment.md) (Normative Appendix)

## Problem

UnifiedCombat currently executes behavior across multiple independent paths (combat/offense, defensive, movement/follow, maintenance providers).  
That fragmentation causes avoidable runtime conflicts:

- duplicated or overlapping dispatch before state catches up
- movement and cast contention
- target churn during active engagements
- difficult debugging because decision authority is distributed

The system needs one runtime authority that makes deterministic, stateful decisions from a single tick snapshot.

## Goals

- Establish one scheduler authority for all scheduler-managed action dispatch.
- Convert providers to proposal-only behavior (`collect(ctx)`), with no direct command execution.
- Guarantee one dispatch plan max per tick, with optional single prelude.
- Add pending action ledger + duplicate suppression keyed by exact action identity.
- Add explicit lock semantics (`movement_lock`, `cast_lock`, `target_lock`, etc.).
- Centralize scoring and tie-break rules.
- Improve observability with ranked candidates, rejection reasons, locks, and pending state.
- Keep Phase 1 small enough to ship and iterate.

## Non-goals

- Full parity migration of every provider in one cut.
- Advanced pathfinding or predictive optimization.
- Multi-step macro choreography in one tick.
- New UI paradigm outside required scheduler visibility fields.

## Contracts

### Scheduler contract

- Build one tick-stable `ctx` snapshot per tick.
- Collect proposals from enabled providers.
- Validate, classify viability, score, and select deterministically.
- Emit at most one dispatch plan per tick.
- Revalidate commit-time viability before primary dispatch.
- Own and enforce lock lifecycle.
- Own and enforce pending action lifecycle.

### Provider contract

Required:

```lua
collect(ctx) -> proposals
```

Optional:

```lua
enabled(settings) -> bool
on_pending_update(event)
on_scheduler_reset(reason)
```

Rules:

- Providers do not dispatch commands directly once under scheduler control.
- Providers do not acquire/release locks directly.
- Providers may emit multiple candidates or none.

### Proposal and plan contracts

Normative schema and lifecycle definitions are in:

- [unified_scheduler_phase1_amendment.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_phase1_amendment.md)

This includes:

- proposal identity (`proposal_id`, `family_id`, `duplicate_suppression_key`)
- urgency normalization (`0.0..1.0`)
- pending record shape and states
- dispatch plan model (`prelude` + `primary`)
- lock semantics and strengths
- score formula and tie-break order

## Algorithms

### Per-tick pipeline

1. Snapshot: build tick-stable `ctx`.
2. Collect: call each enabled provider `collect(ctx)`.
3. Validate: drop malformed/expired/hard-locked/duplicate-suppressed proposals.
4. Classify: `ready`, `ready_with_prelude`, `needs_reposition`, `blocked_soft`, `invalid`.
5. Score: apply central effective score.
6. Select: choose winner deterministically (or explicit no-op).
7. Plan: build dispatch plan (0..1 prelude + 0..1 primary).
8. Commit revalidation: ensure still valid at dispatch edge.
9. Dispatch: execute plan; create/update pending; acquire/release locks.
10. Observe: emit decision and rejection diagnostics.

### Determinism requirements

- Given the same `ctx` + scheduler state, winner selection must match.
- Tie-break order is fixed and stable.
- Rejection reason taxonomy is standardized.

## Rollout

### Phase A

- Implement scheduler shell and ctx snapshot.
- Provider collect path + ranking diagnostics only (no dispatch).
- Wire one provider through dispatch-plan bridge in controlled mode.

### Phase B

- Add pending ledger and duplicate suppression.
- Add lock acquisition/release enforcement.
- Migrate combat provider under scheduler authority.

### Phase C

- Migrate defensive and movement providers (proposal-driven movement + hysteresis).
- Add maintenance providers (GEO/COR/BRD).

### Phase D

- Remove legacy direct dispatch paths.
- Finalize QA, performance checks, and cutover.

## Risks

- Provider migration drift: old side-effects may survive unless aggressively removed.
- Over-tight locks: can create starvation or sluggish behavior.
- Under-tight locks: can reintroduce churn and repeated dispatch.
- Snapshot staleness: commit invalidation rates can spike under load.
- Observability gaps: hard to QA without rejection and score trace data.

## Acceptance criteria

- Scheduler-controlled providers never dispatch commands directly.
- At most one critical pending action exists at a time.
- Duplicate suppression blocks in-flight and too-recent re-dispatch.
- Commit-time revalidation prevents stale/invalid primary dispatch.
- Movement dispatch is blocked by hard `movement_lock`.
- Decision traces include top candidates and rejection reasons.
- Remote state exposes selected proposal/provider/family, pending summary, locks, and no-op reason.
- Behavior remains stable across multi-session combat scenarios without target churn regressions.

## Normative appendix

Phase 1 implementation details are normative in:

- [unified_scheduler_phase1_amendment.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_phase1_amendment.md)
