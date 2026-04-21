# Unified Scheduler Work Tracking

Last updated: 2026-04-21
Branch: feature/unified-scheduler-design-clean
Owner: Codex + Peter

## Goal
Build the unified scheduler in incremental, testable slices without destabilizing combat.

## Progress Rules
- This file is the source of truth for scheduler implementation status.
- Every code change that advances scheduler work must update this file in the same commit.
- Status values: `TODO`, `IN_PROGRESS`, `DONE`, `BLOCKED`.

## Phase 1 - Foundation

### S1. Tick-stable snapshot + collect-only shell
- Status: DONE
- Code:
  - [x] Added Phase 1 scheduler state container (`scheduler.phase1`) in `unified_scheduler.lua`.
  - [x] Added tick context builder (`p1_make_ctx`).
  - [x] Added provider collect pass (`p1_collect_proposals`) with defensive-internal proposal adapter.
  - [x] Added proposal validation (`p1_validate_proposal`).
  - [x] Added centralized scoring (`p1_score`) and deterministic selection (`p1_rank_and_select`).
  - [x] Wired dry-run pass into `scheduler.process_tick()` via `p1_run_dry_tick(s)`.
- Notes:
  - Dry-run path is non-dispatch and does not change live action execution flow.
  - New globals exposed for observability: `UC_SCHED_P1_*`.

### S2. Dispatch-plan model (single plan with optional prelude)
- Status: TODO
- Code:
  - [ ] Add dispatch plan object (`plan_id`, `selected_proposal_id`, optional prelude, primary).
  - [ ] Add commit-time revalidation function.
  - [ ] Add no-op path with explicit `commit_invalidated` reason.

### S3. Pending ledger + duplicate suppression
- Status: TODO
- Code:
  - [ ] Add pending action ledger structure and lifecycle states.
  - [ ] Enforce duplicate suppression checks against pending + recent history.
  - [ ] Add timeout handling (`ack_deadline`, `effect_deadline`).

### S4. Lock semantics
- Status: TODO
- Code:
  - [ ] Implement lock state (`movement_lock`, `cast_lock`, `target_lock`, `duplicate_lock`).
  - [ ] Add hard vs soft lock behavior.
  - [ ] Add lock ownership/release rules tied to pending lifecycle.

### S5. Provider migration order
- Status: IN_PROGRESS
- Code:
  - [x] Defensive/internal provider has proposal adapter (dry-run only).
  - [ ] Move defensive dispatch under plan+pending path.
  - [ ] Add combat provider proposals.
  - [ ] Add movement proposals.
  - [ ] Add maintenance providers (GEO/COR/BRD).

## Observability
- Status: IN_PROGRESS
- Code:
  - [x] Added selected/no-op/top summary globals for dry-run scheduler output.
  - [ ] Emit structured rejection reasons list.
  - [ ] Surface additional scheduler fields to remote bridge/UI.

## Testing Checklist (Code Perspective)
- [ ] Confirm no combat behavior regression with dry-run shell enabled.
- [ ] Confirm defensive behavior unchanged from pre-shell baseline.
- [ ] Confirm `UC_SCHED_P1_*` values update per tick and stay stable under idle/no-proposal cases.

## Current Risks
- Defensive proposal adapter currently models only internal provider candidate shape.
- No pending/lock semantics yet; selection is informational only in this pass.

## Next Implementation Slice
1. Add dispatch plan object + commit revalidation (S2).
2. Keep old execution as fallback while plan path is dark-launched.
3. Update this tracker in the same commit.
