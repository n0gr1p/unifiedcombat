# T3.1n — Delayed Target Acquisition and Engage Audit

## Scope

This audit traces the path from current-target death to next-target select/engage under scheduler-owned combat flow.

T3.1o updated runtime behavior narrowly for scheduler engage action-state release.
No diagnostics were added.

## T3.1o fix summary

T3.1o patched the scheduler engage send path so a successful `/attack on` send no longer enters the generic “acting until timeout” action-state path.

Before T3.1o:

- scheduler engage dispatch called `action_mark_sent('engage')`
- that created a generic acting state
- if no usable local self action-message end arrived, engage stayed blocked until the generic `lag_timeout = 8.0`

After T3.1o:

- scheduler engage dispatch calls a dedicated engage action-state helper
- engage does **not** enter the generic acting state
- engage now leaves only a bounded cooldown/debounce tail of about `0.35` seconds
- duplicate suppression and pending duplicate windows still remain in place to prevent attack-on spam

Why the generic 8-second timeout was inappropriate for engage:

- `/attack on` is not a spell/JA/WS action with a reliable completion bridge in the current scheduler hooks
- leaving it in the generic acting path made the scheduler wait on a completion signal that might never arrive
- the field symptom of `5–10` seconds matched that timeout almost exactly

## Observed behavior under audit

Field report:

- a valid next target can already exist,
- the target is party/alliance-valid, in range, and otherwise eligible,
- but scheduler-owned reacquire / attack-on can lag by roughly 5–10 seconds,
- and the issue appears during extended play rather than only immediately after reload.

## Timeline model

Most likely timeline in the current implementation:

1. **T0 — current target dies**
   - core death / zero-HP checks recognize the current target as dead.
2. **T1 — player status / sticky state settles**
   - core may briefly preserve current-target context while engaged-state jitter settles.
3. **T2 — scheduler next-target proposal becomes eligible**
   - target-control and/or engage proposal is created on a later scheduler tick.
4. **T3 — proposal wins rank**
   - target-control proposal usually wins first, then engage proposal on a later tick.
5. **T4 — attack-on send is attempted**
   - current code can still block here if scheduler action-state thinks a prior engage is still in flight.

The interval most likely to expand into the reported 5–10 seconds is **T3 → T4**, caused by the global scheduler `action_dispatch_blocked()` gate treating a previous `engage` send as still acting until the generic `lag_timeout` expires.

## Full target/engage pipeline map

### 1) Current-target death / invalidation

**Core death / recent-death validity**

- `unified_combat_core.lua:543` — `death_event_active_for_id(id, now)`
- `unified_combat_core.lua:553` — `is_live_actionable_combat_target(mob_or_target, now, include_recent_death)`

Current current-target death handling:

- `unified_combat_core.lua:1046`
  - when the current engaged target is dead, core explicitly clears sticky target and allows immediate rescan.

Pass meaning:

- dead / recent-death current target should stop being treated as actionable.

Potential delay contribution:

- low by itself; this path is explicitly designed to unblock immediate rescan.

### 2) Core next-target scan / selection

**Primary target pick**

- `unified_combat_core.lua:3701` — `core.select_target_for_scheduler(settings)`
- depends on `find_candidate_target(s)` from core target selection flow.

Important core stickiness / hold state in that flow:

- `unified_combat_core.lua:1019` onward — sticky target reuse while engaged or within sticky hold
- `unified_combat_core.lua:3233` — `core.sticky_hold_until = now + 1.2`

Pass meaning:

- returns `{ target_id, target_name, hpp }` for a live valid combat mob.

Fail meaning:

- returns `nil`, so scheduler emits no target-control proposal.

Timeout / hold durations:

- `sticky_hold_until`: about `1.2` seconds after engagement drops.

Can it accumulate over long play?

- not obviously; this is short and resets around engagement transitions.

### 3) Friendly claim / party-alliance validity

**Friendly claims helper**

- `uc_targeting_common.lua:81` — `build_friendly_claims(opts)`
- `uc_targeting_common.lua:85` — `is_friendly_party_or_alliance_member_id(id, opts)`
- `uc_targeting_common.lua:98` — `pick_primary_and_prime(...)`

Scheduler engage claim gate:

- `unified_scheduler.lua:2948` onward
  - `party_claimed_ok`
  - `prime_unclaimed_ok`
  - `force_leader_engage`

Pass meaning:

- claimed-by-friendly, allowed prime/unclaimed aggressive, or explicit fight-leader forced engage.

Fail meaning:

- no engage proposal emitted.

Can it accumulate over long play?

- not by itself; claim validity is snapshot-based.

### 4) Scheduler target proposal creation

**Target-control proposal**

- `unified_scheduler.lua:3003` — `p1_collect_target_control(ctx, out)`
- `unified_scheduler.lua:3037` onward — emits `provider='target_control'`, `action_type='target'`

Important engage relationship:

- `unified_scheduler.lua:3017`
  - target acquisition proposals are explicitly “for pre-engage control only”.
- `unified_scheduler.lua:3018` / `3022`
  - only runs when player is **not engaged**.

Timeout / throttle details:

- `expires_at = ctx.now + 0.35`
- `commit_deadline = ctx.now + 0.25`
- `recast_key = ('target:%d')`
- `duplicate_suppression_key = ('target.acquire:%d')`

Delay contribution:

- normal one-step serialization: target acquisition and engage are split into separate proposals.
- by design this costs at least another scheduler cycle, but not 5–10 seconds by itself.

### 5) Scheduler engage proposal creation

**Engage proposal**

- `unified_scheduler.lua:2887` — `p1_collect_combat_engage(ctx, out)`

Key gate:

- `unified_scheduler.lua:2908`
  - if `engaged` and no forced fight-leader target, scheduler does **not** collect engage proposals.

Proposal metadata:

- `unified_scheduler.lua:2973` onward
  - `family_id = 'combat.engage.primary'`
  - `action_type = 'engage'`
  - `priority_band = 72`
  - `recast_key = 'engage:attack_on'`
  - `duplicate_suppression_key = ('engage:%d')`
  - `expires_at = ctx.now + 0.30`
  - `commit_deadline = ctx.now + 0.20`

Pass meaning:

- a valid engage proposal enters ranking.

Fail meaning:

- no engage proposal exists that tick.

Delay contribution:

- **moderate secondary candidate**: scheduler engage collection is suppressed while player status still says engaged after a kill.
- likely short-lived, but it serializes reacquire behind status drop.

### 6) Proposal validation / duplicate suppression / pending conflicts

**Validation path**

- `unified_scheduler.lua:3580` — `p1_validate_proposal(ctx, p)`
- `unified_scheduler.lua:3637` — `p1_rank(ctx, proposals)`

Validation gates:

- malformed proposal rejection
- required setting disabled
- stale snapshot: older than `0.8` seconds
- pending conflict
- expired proposal
- duplicate suppression

Important detail:

- `unified_scheduler.lua:3595` onward
  - pending conflict only hard-rejects when lock classes differ **and** action type is `spell`, `ja`, `ws`, or `move`
  - `engage` is **not** part of that list

Implication:

- pending state is not the strongest direct blocker for engage here.
- duplicate suppression can suppress repeated same-target engage proposals, but that alone is not evidenced as an hours-long accumulator from the visible code.

### 7) Ranking / outranking

**Rank behavior**

- `unified_scheduler.lua:3637` — `p1_rank(ctx, proposals)`
- `unified_scheduler.lua:3687` onward — debug reporting when engage loses or wins

Observed ranking structure:

- target-control proposal has `priority_band = 84`
- engage proposal has `priority_band = 72`

Implication:

- when both exist, target acquisition beats engage first.
- that is expected and usually healthy, but it means engage is inherently a second-stage action.

Could defensive / maintenance actions outrank engage?

- yes, depending on their priority bands and current conditions.
- however, the strongest code-evidenced multi-second blocker is still the global action-state gate, because it blocks dispatch after ranking even when engage has already won.

### 8) Ownership dispatch / fallback

**Target ownership helper**

- `uc_scheduler_target_ownership.lua:38` — `apply_target_ownership(opts)`
- if dispatcher execution fails, `fallback_used = true` and direct target select happens immediately in the same call.

**Turn ownership helper**

- `uc_scheduler_turn_ownership.lua:38` — `apply_turn_ownership(opts)`
- dispatcher failure falls back immediately to direct turn.

**Command ownership helper**

- `uc_scheduler_command_ownership.lua:38` — `apply_command_ownership(opts)`
- dispatcher failure falls back immediately to direct send.

Promoted ownership controls:

- `unified_scheduler.lua:170` — promoted ownership kill switch
- helpers honor explicit per-flag false and global kill switch

Delay contribution:

- **low** for target/turn ownership in this symptom.
- helper decline/fallback is immediate and does not create a multi-second wait window by itself.
- engage attack-on itself is not routed through `uc_scheduler_command_ownership`; it is a direct `uc_attack.engage_target(expected_tid)` call in scheduler combat dispatch.

### 9) Engage commit path

**Target prep before engage**

- `unified_scheduler.lua:3841` — `p1_try_target_prep(target_id)`
- uses promoted default-on target ownership helper with immediate direct fallback if dispatcher fails.

**Target-control dispatch branch**

- `unified_scheduler.lua:4022`
- after successful target prep, scheduler records dispatch/pending globals and returns `BLOCK_SCHED_P1_DARKLAUNCH_TARGET`
- comment at `unified_scheduler.lua:4035` explicitly says target prep must not enter the global acting lock path.

**Engage dispatch branch**

- `unified_scheduler.lua:4191` onward
- target must match expected target, must be live actionable, must not already be engaged on same target
- then `uc_attack.engage_target(expected_tid)` is called
- before T3.1o: success called `action_mark_sent('engage')`
- after T3.1o: success calls an engage-specific action-state helper that leaves only a short cooldown tail

This is the most important handoff point in the delay.

## Gate inventory summary

### High-confidence gates

1. **Current target death / recent-death invalidation**
   - owner: core
   - likely short and healthy
2. **Engaged-state suppression of target-control / engage collection**
   - owner: scheduler/core mixed
   - secondary short blocker candidate
3. **Target-control outranks engage**
   - owner: scheduler
   - expected one-cycle serialization
4. **Action-state global block after engage send**
   - owner: scheduler action-state
   - **primary blocker candidate**
5. **Defensive spell wait movement lock**
   - owner: scheduler defensive state
   - possible blocker for movement/follow, but less directly tied to several-second attack-on delay after recent T3.1m fixes
6. **Ownership fallback path**
   - owner: scheduler ownership helpers
   - immediate fallback; unlikely long blocker

## Long-lived state inventory

### 1) Generic scheduler action-state

**Definition / defaults**

- `unified_scheduler.lua:83`–`89`
  - `cooldown_until = 0`
  - `lag_timeout = 8.0`
  - `ja_lag_timeout = 1.0`

**Send marker**

- `uc_scheduler_action_state.lua:8` — `action_mark_sent(...)`
  - sets `action_start = now`
  - sets `action_end = now - 0.001`
  - sets initial `cooldown_until = now + 0.6`

**Acting evaluation**

- `uc_scheduler_action_state.lua:103` — `action_is_acting(...)`
- `uc_scheduler_action_state.lua:109` — generic timeout defaults to `8.0`
- `uc_scheduler_action_state.lua:122` — once acting ends, generic cooldown tail becomes `0.5`

**Dispatch gate**

- `uc_scheduler_action_state.lua:130` — `action_dispatch_blocked(...)`
- blocks first on `action_is_acting()`
- then blocks on `cooldown_until`

### 2) Defensive spell wait state

- `unified_scheduler.lua:451` — `scheduler.refresh_defensive_spell_wait_lock(at)`
- wait duration can be up to `8.0` seconds from send, but T3.1k/T3.1m already added explicit interruption/success clears.

This still matters for movement lock, but is not the strongest code-evidenced explanation for engage-specific 5–10 second delay growth.

### 3) Core sticky target hold

- `unified_combat_core.lua:3233` — `sticky_hold_until = now + 1.2`

Short-lived only; useful to absorb jitter, but too small to explain the full symptom by itself.

### 4) Hunter acquire timeout / ignore cooldown

- `unified_combat_core.lua:3346` — `claim_timeout` default `4.0` seconds
- `unified_combat_core.lua:3347` — `ignore_cooldown` default `20.0` seconds

This can produce large delays for hunter/path-claim acquisition flows, but the field report says the next target is already valid, claimed, and in range, so this is a weaker fit unless the live scenario is actually staying in hunter-claim gating more than expected.

## Most likely blocker candidates with evidence

### Candidate 1 — stale scheduler `engage` action-state blocked new engage for up to 8 seconds

**Evidence chain**

1. Successful scheduler engage calls:
   - `unified_scheduler.lua:4235` — `action_mark_sent('engage')`
2. `action_mark_sent(...)` creates an in-flight acting state:
   - `uc_scheduler_action_state.lua:8`
3. Generic acting timeout for non-JA actions is:
   - `uc_scheduler_action_state.lua:109` — `lag_timeout = 8.0`
4. Engage dispatch is blocked by the global action gate before the engage branch runs:
   - `unified_scheduler.lua:4099` — `action_dispatch_blocked()` in combat provider path
   - `uc_scheduler_action_state.lua:130` — `action_dispatch_blocked(...)`
5. The generic end signal path is only:
   - `unified_scheduler.lua:5283` / `5353`–`5356`
   - `scheduler.on_action_message(msg)` → `action_mark_packet_end()` for non-zero local-player action messages

**Why this matters**

- `engage` is not a spell/JA/WS packet with a dedicated completion bridge.
- If `/attack on` does not generate a useful local non-zero action message for the scheduler, the prior `engage` send can remain “acting” until the **8 second timeout**.
- During that time, `action_dispatch_blocked()` can reject the next engage attempt even when the new target is already valid and ready.

**Why it matches the field symptom**

- observed delay is about `5–10` seconds
- code timeout is `8.0` seconds plus scheduler tick / target reacquire / ranking overhead
- the delay would be intermittent depending on whether unrelated local action messages happen to clear action-state sooner

This is the strongest evidence-backed blocker candidate in the current audit.

T3.1o directly addressed this candidate.

### Candidate 2 — scheduler engage/target collection is suppressed while player still reads as engaged after kill

**Evidence**

- `unified_scheduler.lua:2908` — engage proposals return early while `player.status == 1` unless fight-leader force target is active
- `unified_scheduler.lua:3017` — target-control proposals are pre-engage only and also return if engaged

**Impact**

- after kill, scheduler waits for engaged-state to drop before it will emit normal target-control/engage proposals
- probably contributes a short initial delay window

**Why it is secondary**

- visible code suggests this should be short, not 8–10 seconds by itself
- it likely compounds with Candidate 1 rather than replacing it

### Candidate 3 — two-stage target-control then engage sequencing adds normal extra latency

**Evidence**

- target-control priority band `84`: `unified_scheduler.lua:3041`
- engage priority band `72`: `unified_scheduler.lua:2981`
- target-control dispatch returns its own block reason and records pending separately: `unified_scheduler.lua:4022`–`4040`

**Impact**

- a target acquire tick usually happens before an engage tick
- this is expected serialization, not a root cause for 5–10 seconds alone

### Candidate 4 — hunter acquire timeout / ignore cooldown can create large delays in some claim-transition flows

**Evidence**

- `unified_combat_core.lua:3346`–`3356`, `3425`–`3434`

**Why it is weaker here**

- report says next target is already valid, claimed, and in range
- if that observation is fully accurate, hunter timeout should not be the primary gate

## Ownership dispatch findings

- promoted default-on target/turn ownership helpers can decline dispatcher execution and immediately fall back to direct side effects in the same function call.
- no evidence in the helper code suggests multi-second delay accumulation from target or turn ownership fallback.
- global promoted kill switch and per-flag false opt-outs can change which path executes, but they do not introduce long waits themselves.
- engage attack-on does not use command ownership helper at all; scheduler calls `uc_attack.engage_target(expected_tid)` directly.

## Recommended field log capture procedure

No diagnostics were added in this task.

Recommended immediate field capture using existing signals:

1. enable scheduler debug logging already used for combat scheduling if available in your current setup,
2. watch `_G.UC_LAST_SCHED_ACTION`, `_G.UC_LAST_BLOCK_REASON`, and any combat scheduler debug output,
3. specifically capture a sequence where:
   - target A dies,
   - target B is already valid and visible,
   - engage does not happen for several seconds,
4. during that window, note whether:
   - player status still reads engaged,
   - `_G.UC_LAST_SCHED_ACTION` shows target acquire / engage rank activity,
   - repeated blocks map to action-state cooldown/acting,
   - a new local spell/JA/WS action suddenly “unsticks” engage before the long delay would otherwise end.

Most useful discriminator:

- if a delayed engage releases immediately after some unrelated self action message, that strongly supports the stale `engage` action-state hypothesis.

## Field-test instructions

Field-test with:

1. let target A die while target B is already valid and eligible,
2. confirm scheduler reacquire still follows the existing target-control then engage sequence,
3. confirm the next engage no longer lingers for several seconds,
4. confirm repeated `/attack on` spam does not appear,
5. confirm normal spell/JA/WS behavior remains unchanged,
6. if any delay remains, capture whether it is now in:
   - engaged-state drop after kill,
   - target-control rank/selection,
   - or some other non-engage gate.

## Rollback note

Rollback is narrow:

- revert the engage-specific action-state helper and restore `action_mark_sent('engage')`
- this would restore the old generic behavior, including the stale 8-second engage block risk

## Recommended next fix task

If field testing still shows meaningful delay after T3.1o, the next likely slice is:

**T3.1p — Audit and tighten post-kill engaged-state / target-control serialization after death, now that stale engage action-state no longer dominates the delay.**

## Rollback risk

For T3.1o itself, rollback risk is moderate:

- engage is central combat behavior,
- under-releasing would preserve the current delay,
- over-releasing could permit duplicate attack-on churn.

The current patch keeps duplicate/pending suppression intact specifically to reduce that spam risk.
