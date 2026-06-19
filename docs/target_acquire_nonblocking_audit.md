# Target Acquire Nonblocking Audit

## Observed Field Issue

- Tank target acquisition lagged a non-tank DPS by roughly `2–5` seconds when both had the same valid next target available.
- The difference was specifically about setting/selecting the next target, not `/attack on` timing.

## Tank vs MNK Comparison

- MNK with little or no defensive proposal traffic selected the next target quickly.
- PLD with defensive Cure, maintenance, and Sleep proposal traffic selected the next target more slowly.
- That pointed to scheduler action-economy coupling rather than target-validity differences.

## Target Acquisition Pipeline Before Patch

1. `p1_collect_target_control(...)` built a normal ranked proposal.
2. That proposal competed in the same queue as Cure, maintenance, Sleep, engage, and other actions.
3. Even though `target_control` dispatch itself bypassed `action_dispatch_blocked(...)`, it first had to win ranking.
4. When it finally dispatched, the target-control branch still used normal pending/duplicate bookkeeping through `p1_record_legacy_dispatch(...)`.
5. That pending state could behave like ordinary action economy, creating avoidable follow-on delay.

## Root Cause

- Next-target acquisition was still modeled as part of ranked action economy.
- Tanks generated more defensive/support proposals than low-maintenance DPS jobs, so target acquisition lost or arrived later more often.
- Defensive spell wait also blocked the whole scheduler dispatch phase before target-control could run.

## New Nonblocking Target Acquisition Behavior

- The scheduler now runs a dedicated pre-action target-acquire lane before ranked action dispatch.
- That lane:
  - reuses the existing `p1_collect_target_control(...)` candidate logic,
  - preserves the existing target ownership helper seam,
  - validates the candidate normally,
  - dispatches target selection without creating a normal pending action lock.

## What Target Acquisition Can Now Bypass

- non-critical Cure ranking,
- maintenance buff ranking,
- Sleep ranking,
- ordinary spell/JA/WS action-state blocking,
- defensive spell wait blocking for target-selection latency purposes.

This keeps target selection nonblocking relative to action economy.

## What Safety Gates Still Apply

- dead targets are rejected,
- recent-death targets are rejected,
- unrelated claimed targets are rejected,
- invalid/stale mobs are rejected,
- out-of-range targets are rejected,
- existing scope/claim validity rules are preserved,
- zone-guard style scheduler safety locks still apply.

## Target Debounce Behavior

- Target acquisition now uses a short role-neutral debounce of `0.20` seconds.
- This is only anti-spam protection.
- It is intentionally too short to explain tank-only multi-second lag.

## Relationship to T3.4f

- T3.4f kept tank engage above non-critical defensive actions.
- T3.4g moves the earlier step — target acquisition itself — out of ranked action economy.
- Engage priority remains intact.
- This patch makes target acquisition fast and role-neutral before engage/action ranking even matters.

## Risks

- A dedicated pre-action target lane is broader than a pure ranking tweak, so field checks should confirm it does not feel too aggressive in rapid target churn situations.
- Because target acquisition no longer creates a normal pending action lock, the short debounce is the main anti-spam guard and should be watched in live use.

## Field-Test Instructions

1. Enable scheduler combat dark-launch with `autotarget`.
2. Compare a tank with defensive settings against a low-maintenance DPS on the same pull flow.
3. Verify both characters set the next valid target promptly after the current one dies or becomes stale.
4. Verify the tank no longer waits on Cure/maintenance/Sleep proposal ranking before selecting the next target.
5. Verify critical Cure can still win action dispatch, while the next target is still selected promptly.
6. Verify no visible target-selection spam occurs.

## Rollback Note

- Rollback is localized to `unified_scheduler.lua`, `tests/replay/harness/selftest_target_acquire_nonblocking.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, and the related docs.
- Ownership promotion/default-off policy remains unchanged.
