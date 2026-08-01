# UnifiedCombat Unified Scheduler Design - Phase 1 Amendment

## Purpose

This amendment tightens the Phase 1 design in five areas that need to be explicit before implementation:

- revised proposal schema
- pending action state model
- dispatch plan model
- lock semantics
- scoring and tie-break rules

The goal is to keep Phase 1 small enough to ship while avoiding the most common scheduler failure modes:

- repeated dispatch before state catches up
- movement/cast oscillation
- provider priority gaming
- target churn
- loss of debuggability

## 1. Design Principles

### 1.1 Providers propose intent, not raw execution strings

Providers should describe what they want done, not exactly how to emit it.

Phase 1 rule:

- providers may still include a prebuilt command as a temporary compatibility field
- scheduler/executor is the source of truth for dispatch validation and action bookkeeping

### 1.2 Scheduler decisions are stateful across ticks

Scheduler state tracks:

- current locks
- pending action state
- recent winners
- anti-thrash holds
- last dispatch outcomes

### 1.3 Scheduler emits one dispatch plan per tick

Allow one dispatch plan per tick, which may contain:

- zero or one prelude
- zero or one primary action

## 2. Revised Proposal Schema

### 2.1 Proposal shape

```lua
{
  proposal_id = "cor.rolls.chaos_refresh.self",
  family_id = "cor.rolls.refresh",
  provider = "cor",
  action_type = "spell|ja|ws|move|target|idle",
  action_name = "Chaos Roll",
  target_kind = "self|ally|mob|position|none",
  target_id = 12345,
  target_name = "Apex Crab",
  priority_band = 75,
  urgency = 0.42,
  starvation_eligible = true,
  created_at = now,
  expires_at = now + 0.40,
  commit_deadline = now + 0.25,
  movement_policy = "must_stop|can_move|requires_range|positioning_only",
  range_policy = { min = 0.0, max = 21.0, los_required = true },
  recast_key = "ability:Chaos Roll",
  duplicate_suppression_key = "cor:chaos_roll:self",
  lock_class = "support_action",
  expected_ack = "action_start",
  expected_effect = "buff_gain",
  sticky = true,
  can_preempt_movement = true,
  can_preempt_same_band = false,
  reason_code = "roll_missing",
  detail = { missing_buff = "Chaos Roll", seconds_remaining = 0.0 },
  legacy_command = 'input /ja "Chaos Roll" <me>',
}
```

### 2.2 Required identity fields

- `proposal_id`: unique instance id for logging and correlation
- `family_id`: stable logical family for anti-thrash and starvation handling
- `duplicate_suppression_key`: concrete anti-repeat key

### 2.3 Urgency contract

- urgency range is always `0.0` to `1.0`
- scheduler clamps invalid values

## 3. Pending Action State Model

### 3.1 Why this exists

Pending state prevents duplicate command spam while state propagation is still in flight.

### 3.2 Pending action record

```lua
{
  pending_id = "pend_00018422",
  proposal_id = "cor.rolls.chaos_refresh.self",
  family_id = "cor.rolls.refresh",
  duplicate_suppression_key = "cor:chaos_roll:self",
  provider = "cor",
  action_type = "ja",
  action_name = "Chaos Roll",
  target_id = nil,
  state = "selected|dispatching|sent|acknowledged|effect_seen|timed_out|failed|canceled|complete",
  selected_at = now,
  dispatched_at = nil,
  ack_deadline = now + 0.6,
  effect_deadline = now + 2.5,
  completion_deadline = now + 3.0,
  lock_impact = {
    movement_lock_until = nil,
    cast_lock_until = nil,
    target_lock_until = nil,
  },
  expected_ack = "action_start",
  expected_effect = "buff_gain",
  result = nil,
}
```

### 3.3 Pending lifecycle

- `selected`
- `dispatching`
- `sent`
- `acknowledged`
- `effect_seen`
- `complete`
- `timed_out`
- `failed`
- `canceled`

### 3.4 Pending ledger rules

- one critical pending action max in Phase 1
- duplicate suppression checks pending first
- pending may hold locks before visible effect lands

## 4. Dispatch Plan Model

### 4.1 Why a dispatch plan

Dispatch plans support legal prelude steps without allowing arbitrary multi-action ticks.

### 4.2 Dispatch plan shape

```lua
{
  plan_id = "plan_000812",
  selected_proposal_id = "combat.ws.savage_blade.mob_12345",
  prelude = {
    type = "none|stop|retarget|face",
    target_id = 12345,
    timeout_s = 0.20,
  },
  primary = {
    action_type = "ws",
    action_name = "Savage Blade",
    target_id = 12345,
  },
  commit_deadline = now + 0.25,
  created_at = now,
}
```

### 4.3 Allowed Phase 1 preludes

Allowed:

- `none`
- `stop`
- `retarget`
- `face`

### 4.4 Commit rule

Before primary dispatch, revalidate:

- proposal not expired
- commit deadline not passed
- target still valid
- no stronger lock emerged
- pending ledger still allows action

## 5. Lock Semantics

| Lock | Purpose | Acquired By | Blocks | Release |
| --- | --- | --- | --- | --- |
| movement_lock | prevent movement during cast/commit critical windows | pending spell/JA/WS or explicit stop-cast plan | movement dispatch | ack/effect/timeout or short fixed window |
| cast_lock | prevent issuing overlapping spell/JA/WS | pending spell/JA/WS | spell/JA/WS plans | effect/timeout/failure |
| target_lock | prevent target churn during sensitive windows | target prelude or target-sensitive pending action | conflicting retarget proposals | short TTL/effect/timeout |
| duplicate_lock | suppress immediate duplicates | pending/recent completion by duplicate key | matching duplicate key | TTL or pending resolution |
| movement_goal_hold | reduce movement oscillation | movement winner | low-priority contrary movement updates | hold expiry/hard preemption |
| zone_guard_lock | prevent unsafe dispatch while zoning/loading/menu states | system guard state | all active plans except idle | safe state restored |

### 5.2 Lock strengths

- hard lock: must block
- soft suppression: heavily disfavor unless no better valid action

### 5.3 Lock ownership

Locks are scheduler-owned only.

## 6. Scoring and Tie-Break Rules

### 6.1 Central scoring

All providers go through one scoring function.

### 6.2 Priority bands

- `100` emergency defensive
- `85` cast-window utility
- `75` maintenance buffs
- `70` offense core
- `60` target control/add management
- `50` movement maintenance
- `0` idle

### 6.3 Score formula

```text
effective_score =
  priority_band
  + urgency_bonus
  + starvation_bonus
  + sticky_bonus
  - risk_penalty
```

Where:

- `urgency_bonus = urgency * 9.9` (0.0 to 9.9)
- `starvation_bonus`: 0.0 to 3.0
- `sticky_bonus`: 0.0 to 1.5
- `risk_penalty`: 0.0 to 8.0

### 6.4 Tie-break order

1. lower risk penalty
2. shorter time-to-expiry
3. same family as recent winner if valid
4. same provider as current pending family if stabilizing
5. provider lexical order
6. proposal id lexical order

## 7. Proposal Evaluation Pipeline

Per tick:

1. snapshot (`ctx`)
2. collect (all enabled providers)
3. validate
4. viability classification
5. score
6. select
7. build dispatch plan
8. dispatch + pending/lock updates

Viability classes:

- `ready`
- `ready_with_prelude`
- `needs_reposition`
- `blocked_soft`
- `invalid`

## 8. Provider Contract

Required:

```lua
collect(ctx) -> proposals
```

Optional:

```lua
on_pending_update(event)
on_scheduler_reset(reason)
enabled(settings) -> bool
```

Provider rules:

- no direct dispatch
- no direct lock acquisition
- no direct movement state mutation

## 9. Movement Model (Phase 1)

Movement families:

- `movement.follow`
- `movement.spacing`
- `movement.close_range`
- `movement.return_camp`

Movement proposal fields should include:

- goal type
- desired target or position
- tolerance radius
- urgency
- preemption allowance by cast-critical actions

Example:

```lua
{
  proposal_id = "movement.close_range.mob_12345",
  family_id = "movement.close_range",
  provider = "mobility",
  action_type = "move",
  target_kind = "mob",
  target_id = 12345,
  priority_band = 50,
  urgency = 0.55,
  movement_policy = "positioning_only",
  range_policy = { min = 3.0, max = 20.0, los_required = false },
  sticky = true,
  reason_code = "ws_out_of_range",
}
```

Movement hysteresis:

- use `movement_goal_hold` on movement wins
- prefer same movement family briefly unless stronger non-movement preempts

## 10. Observability Requirements

Per tick record:

- tick sequence
- snapshot timestamp
- provider counts
- valid candidate count
- top 3 ranked with score breakdown
- selected proposal and plan
- no-op reason
- current locks
- pending summary
- tick duration

Rejection reason categories:

- `expired`
- `malformed`
- `hard_locked`
- `duplicate_suppressed`
- `pending_conflict`
- `invalid_target`
- `out_of_range`
- `stale_snapshot`
- `settings_disabled`
- `zone_guard`
- `commit_invalidated`
- `lower_score`

Remote state additions:

- `scheduler_tick`
- `scheduler_selected_proposal`
- `scheduler_selected_provider`
- `scheduler_selected_family`
- `scheduler_plan_prelude`
- `scheduler_pending_state`
- `scheduler_lock_summary`
- `scheduler_reject_top`
- `scheduler_noop_reason`

## 11. Phase 1 Invariants

1. no provider dispatches commands directly once scheduler-controlled
2. at most one critical pending action at a time
3. proposal must be valid at commit time
4. movement is blocked under hard `movement_lock`
5. duplicate suppression checks pending plus recent history
6. decisions are deterministic for same `ctx` + scheduler state

## 12. Recommended Answers to Open Decisions

- provider collect should be soft time-budgeted with overrun logging
- one dispatch plan max per tick, optional one-step prelude
- movement should be proposal-driven for scheduler-owned paths from Phase 1
- target lock under add-control should be short-lived and plan-integrity focused

## 13. Suggested Implementation Order

1. scheduler shell (`ctx`, collect, ranking trace, no dispatch)
2. dispatch plan + executor bridge for one provider
3. pending ledger + duplicate suppression
4. lock acquisition/release
5. migrate combat provider
6. add defensive provider
7. add movement proposals + hysteresis
8. migrate maintenance providers (GEO/COR/BRD)

## 14. Compact Pseudocode

```lua
function scheduler_tick(raw_state)
  local ctx = build_tick_snapshot(raw_state, scheduler_state)

  local proposals = {}
  for _, provider in ipairs(enabled_providers(ctx)) do
    local ok, provider_proposals = safe_collect(provider, ctx)
    if ok then
      extend(proposals, provider_proposals)
    else
      log_provider_error(provider)
    end
  end

  local evaluated = {}
  for _, proposal in ipairs(proposals) do
    local eval = evaluate_proposal(ctx, proposal, scheduler_state)
    if eval.status == "ready" or eval.status == "ready_with_prelude" then
      eval.score = score_proposal(eval, scheduler_state)
      table.insert(evaluated, eval)
    else
      log_rejection(proposal, eval.status, eval.reason)
    end
  end

  sort_by_score_and_tiebreakers(evaluated)

  local winner = evaluated[1]
  if not winner then
    log_noop(ctx, scheduler_state)
    return
  end

  local plan = build_dispatch_plan(ctx, winner, scheduler_state)
  if not revalidate_plan_commit(ctx, plan, scheduler_state) then
    log_commit_invalidated(plan)
    return
  end

  local pending = create_pending_record(plan, winner, ctx)
  acquire_locks_for_pending(pending, scheduler_state)

  local result = executor_dispatch(plan, ctx)
  update_pending_from_dispatch_result(pending, result, scheduler_state)
  log_selection(ctx, winner, plan, pending)
end
```

## 15. Bottom Line

This amendment formalizes the core parts needed to ship a robust Phase 1 scheduler:

- proposal intent contracts
- pending in-flight state
- one-plan dispatch model
- explicit lock semantics
- centralized scoring
- proposal-driven movement
- deterministic, debuggable decisions
