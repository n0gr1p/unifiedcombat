# Unified Scheduler Work Tracking

Last updated: 2026-04-21
Branch: feature/unified-scheduler-design-clean
Status owner: Codex + Peter

## Rules
- This file is updated in every scheduler implementation commit.
- Status values: `TODO`, `IN_PROGRESS`, `DONE`, `BLOCKED`.
- Scope is code implementation progress (not gameplay QA outcomes).

## Phase 1 Workboard

### S1 - Scheduler shell (ctx -> collect -> validate/classify -> score -> select), dry-run only
- Status: DONE
- Deliverables:
  - [x] Tick-stable context builder in scheduler.
  - [x] Proposal collect path (initial provider adapter: defensive/internal).
  - [x] Proposal validation and rejection accounting (`malformed`, `expired`).
  - [x] Central score calculation (priority band + urgency bonus shape).
  - [x] Deterministic rank/select ordering.
  - [x] Dry-run execution wired into `process_tick()` with no behavior change to live dispatch.
  - [x] Remote state observability keys added for selected proposal/provider/family + no-op/reject summary.
- Files:
  - `unified_scheduler.lua`
  - `remote_bridge.lua`

### S2 - Dispatch plan model (`prelude + primary`) with commit-time revalidation
- Status: DONE
- Deliverables:
  - [x] Plan model object + builder.
  - [x] Commit revalidation function.
  - [x] `commit_invalidated` no-op reason path.
- Notes:
  - Implemented in dry-run path (non-dispatch) to preserve behavioral safety while we stand up pending/locks.

### S3 - Pending action ledger + duplicate suppression
- Status: DONE
- Deliverables:
  - [x] Pending record model + lifecycle states.
  - [x] Duplicate suppression against pending + recent history.
  - [x] Ack/effect timeout transitions.
- Notes:
  - Pending lifecycle is currently wired via legacy-dispatch observation while scheduler dispatch remains dark-launched.
  - Timeout path currently uses `effect_deadline` transition to `timed_out`; ack/event-driven transitions come with packet-integrated pending updates.

### S4 - Lock semantics and enforcement
- Status: DONE
- Deliverables:
  - [x] `movement_lock`, `cast_lock`, `target_lock`, `zone_guard_lock` base objects.
  - [x] `duplicate_lock` object and `movement_goal_hold` object formalization.
  - [x] Hard-lock behavior in evaluation (`hard_locked`, `zone_guard` rejection paths).
  - [x] Soft suppression behavior in evaluation (`blocked_soft` path with fallback when no hard-valid proposals exist).
  - [x] Lock acquire/release tied to pending lifecycle (current model derives cast/move lock from pending live states).
- Notes:
  - Current lock model is implemented in dry-run scheduler path and mirrors pending-derived lock lifecycle while legacy dispatch remains active.

### S5 - Provider migration under scheduler authority
- Status: IN_PROGRESS
- Deliverables:
  - [x] Defensive/internal adapter emits scheduler proposal (dry-run).
  - [x] Defensive dispatch dark-launch scaffold via scheduler-selected proposal path (opt-in setting: `scheduler_dark_launch_defensive`).
  - [x] Combat provider proposal path (WS + JA offense proposal adapters, dry-run).
  - [x] Combat dispatch dark-launch executes scheduler-selected WS/JA proposals (opt-in setting: `scheduler_dark_launch_combat`).
  - [x] Movement provider proposal path (initial close/retreat proposal adapters, dry-run).
  - [x] Maintenance providers (GEO/COR/BRD) proposal path (state-driven buff presence scaffolding, dry-run).
- Notes:
  - Combat proposal adapter now seeds both WS (TP-ready) and JA (ordered, recast-ready) proposals for ranking/diagnostics.
  - Combat dark-launch path now dispatches scheduler-selected combat WS/JA proposals; still opt-in and not full-cutover for all combat subsystems.
  - Maintenance adapters now use buff-state intent (COR roll count, BRD song count, GEO indi/geo presence) with throttled proposal emission.
  - Dark-launch dispatch remains opt-in and limited to defensive-internal selection path.

## Observability Checklist
- [x] `scheduler_selected_proposal`
- [x] `scheduler_selected_provider`
- [x] `scheduler_selected_family`
- [x] `scheduler_noop_reason`
- [x] `scheduler_reject_top`
- [x] `scheduler_tick`
- [x] `scheduler_pending_state`
- [x] `scheduler_lock_summary`
- [x] ranked top candidates with full score part details in UI/debug (`scheduler_top3_verbose`)

## Current Risk Notes
- Existing live scheduler execution remains legacy defensive path; dry-run path is advisory only.
- Proposal collection now includes combat/defensive/movement/maintenance lanes; cutover risk is in per-lane dark-launch parity validation.

## Next Slice (immediately next code task)
1. Expand dark launch beyond defensive-internal to one additional provider path (likely movement prelude/plan). - DONE
2. Keep legacy path operational until scheduler-owned dispatch path is fully validated.
3. Add pending lifecycle event hooks (ack/effect updates) from packet callbacks instead of timeout-only progression. - DONE

## Recently Completed
- Added maintenance COR scheduler cut-in (S5 extension):
  - New module: `uc_cor_maintenance.lua` ports AutoCOR-style roll upkeep decisions into UC runtime.
  - Scheduler now emits `maintenance_cor` proposals with concrete JA actions (`<Roll>`, `Snake Eye`, `Double-Up`, `Fold`) instead of generic placeholder intents.
  - Scheduler dark-launch dispatch now executes `maintenance_cor` proposals behind new opt-in setting: `scheduler_dark_launch_maintenance`.
  - Added packet-fed COR roll-state hook path via `UC_COR_MAINT_OnIncomingChunk` callback wiring from `UnifiedCombat.lua` incoming chunk event.
  - Added persistence/snapshot/UI parity for new setting:
    - `UnifiedCombat.lua` defaults/profile keys include `scheduler_dark_launch_maintenance`.
    - `remote_bridge.lua` includes setting in session snapshot.
    - WinForms Scheduler tab includes `Scheduler: maintenance dispatch (dark launch)` toggle.
  - Added WinForms COR maintenance selectors:
    - Scheduler tab now includes `COR Roll 1` and `COR Roll 2` dropdowns bound to `cor_roll_1` / `cor_roll_2`.
    - Roll selectors are session-backed and persisted through normal save/profile paths.
- Result:
  - COR maintenance can now be tested as a scheduler-owned dispatch lane independently from movement/defensive/combat toggles.

- Added defensive HealBot scheduler path (S5 extension):
  - `p1_collect_defensive_healbot(ctx, out)` proposal adapter now emits scheduler defensive proposals when provider is `healbot`.
  - `p1_try_dark_launch_dispatch` now executes selected `defensive_healbot` proposals behind `scheduler_dark_launch_defensive`.
  - Defensive overlay filtering treats both `defensive_internal` and `defensive_healbot` as defensive opt-in lane.
- Result:
  - Defensive provider behavior can route through scheduler selection for both internal and HealBot modes while remaining opt-in.

- Added packet-driven pending lifecycle updates:
  - `scheduler.on_action(act)` and `scheduler.on_action_message(msg)` in `unified_scheduler.lua`
  - Hooked from `UnifiedCombat.lua` action listener + incoming 0x029 parser via global callbacks.
- Result:
  - pending state can progress by observed action events (ack/effect) instead of timeout-only transitions.
- Expanded dark launch path:
  - Added opt-in movement dark launch (`scheduler_dark_launch_movement`) for scheduler-selected mobility proposals.
  - Defensive dark launch remains opt-in via `scheduler_dark_launch_defensive`.
  - Added explicit defaults/profile persistence keys for both dark-launch settings in `UnifiedCombat.lua`.
- Dark launch priority correction:
  - Added combat-first dark launch (`scheduler_dark_launch_combat`) and moved dark-launch execution before defensive-provider gating.
  - This ensures combat dark launch can run even when defensive automation is disabled.
  - Clarification: scheduler score/priority ordering remains unchanged; combat-first applies to implementation/testing sequence, not priority-band overrides.
