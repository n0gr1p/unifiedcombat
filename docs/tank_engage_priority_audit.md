# Tank Engage Priority Audit

## Observed Field Issue

- Tanks could remain unengaged while a valid next enemy was available.
- While unengaged, tanks did not build TP, which delayed Chivalry windows and worsened MP starvation.
- The scheduler then spent action economy on repeated non-critical Cure and routine support actions instead of promptly acquiring and engaging the next mob.

## Action-Economy Loop

1. Tank is out of engagement.
2. No TP is generated, so Chivalry recovery stays unavailable.
3. MP remains stressed.
4. Scheduler keeps finding non-critical Cure or support actions.
5. Those actions consume dispatch opportunities and delay next-target acquire/engage.
6. The tank remains out of TP generation longer, reinforcing the loop.

## Existing Ranking Before Patch

- Critical Cure already ranked at `priority_band = 110`.
- Non-critical defensive Cure/support actions ranked at `priority_band = 100`.
- Sleep ranked at `priority_band = 94`.
- Tank enmity recovery ranked at `priority_band = 96`.
- Target acquisition ranked at `priority_band = 84`.
- Engage was intended to be tank-boosted, but the engage collector referenced undefined `engage_priority` / `engage_urgency` locals, so the effective engage score could collapse to the default numeric fallback instead of the intended tank band.

## Root Cause

- `p1_collect_combat_engage(...)` emitted engage proposals with undefined priority locals instead of explicit scoped tank/non-tank values.
- Pre-engage `target_control` also remained below non-critical defensive actions for tanks, so a tank without the right current target could still be starved before engage was even available.

## New Tank Engage Priority Rule

When all of these are true:

- `tank` setting is active,
- a valid next target exists,
- the target is live and in scope,
- the target is within valid acquire/engage range,
- no critical Cure is pending,

then:

- tank target acquisition now ranks at `priority_band = 106`,
- tank engage now ranks at `priority_band = 107`.

This keeps both steps above:

- non-critical Cure,
- low-value Cure spam,
- maintenance buffs,
- Sleep,
- routine offense/setup,
- tank enmity actions that only make sense after engagement.

## Critical Cure Exception

- Critical Cure remains unchanged at `priority_band = 110`.
- Critical emergency defensive actions still beat tank target acquire and tank engage.
- No new health threshold was introduced; the existing `defensive_critical_hpp` threshold remains the gate.

## What Tank Engage Now Outranks

- non-critical defensive Cure,
- low-MP weak Cure spam,
- maintenance buff actions,
- Sleep,
- ordinary offense setup,
- routine tank enmity recovery actions below the critical Cure band.

## What Still Outranks Tank Engage

- critical Cure / emergency defensive actions,
- any existing hard validity/duplicate/lock rejection that blocks engage safely,
- pull-owner suppression when the configured pull action owns that same target.

## Chivalry / Resource Notes

- The scheduler does not implement a broad resource-risk model for “tank not engaged”.
- It also does not explicitly model Chivalry opportunity cost as a ranked resource state.
- This patch stays narrow: it treats prompt tank target acquire/engage as a higher scheduler action-economy priority than non-critical defensive/support actions.

## Risks

- Tank-specific target acquire/engage now wins more aggressively while out of engagement, so field checks should confirm this does not feel too eager in edge cases with benign yellow HP.
- Non-tank behavior is intentionally unchanged, so mixed-role expectations should not be inferred from this patch.
- This patch does not alter movement arbitration, ownership policy, or generic action-state behavior.

## Field-Test Instructions

1. Enable scheduler combat dark-launch with `autotarget` and `tank`.
2. Present a valid next target while the tank is unengaged and a party member has non-critical missing HP.
3. Verify the tank acquires and engages the next target before spending another non-critical Cure/support action.
4. Verify the same tank still prioritizes a truly critical Cure when HP is at or below the configured `defensive_critical_hpp` threshold.
5. Verify Sleep and maintenance buffs do not beat tank next-target acquire/engage when the tank is unengaged and the defensive state is non-critical.
6. Verify duplicate engage protection still prevents `/attack on` spam.

## Rollback Note

- Rollback is localized to `unified_scheduler.lua`, `tests/replay/harness/selftest_tank_engage_priority.lua`, `tests/replay/harness/selftest_all_replay_fixtures.lua`, and the related docs.
- Ownership promotion/default-off policy remains unchanged, so reverting this slice only restores the prior ranking behavior.
