# T3.4h — Engage dispatch priority audit

## Observed field issue

After T3.4g, next-target acquisition became prompt again, but `/attack on` still lagged behind once the next target was already selected.

Observed examples:

- non-priority self-buffs delayed engage
- defensive/maintenance actions delayed engage
- confirmed completed spells could still leave a noticeable post-cast lockout before engage

## Target acquisition vs engage

T3.4g fixed target selection only.

- target acquisition = select the next valid mob
- engage dispatch = send `/attack on` against the already selected valid mob

This task covers only the second stage.

## Engage dispatch pipeline before patch

Before T3.4h:

1. target acquisition could complete in the pre-action lane
2. engage still re-entered normal ranked proposal selection
3. non-critical Cure, maintenance buffs, Sleep, and other routine proposals could still be chosen ahead of engage
4. even when engage was the intended next action, generic post-spell action-state and spell-wait tails could still delay dispatch

## Root cause

Two separate issues were still present:

1. **Engage was still subject to normal ranked action economy**
   - tank engage already had a high priority band from T3.4f
   - non-tank engage still had a lower default band
   - more importantly, engage still had to win the normal ranked lane instead of being explicitly preferred over non-critical actions once a valid target was already selected

2. **Confirmed spell completion was still over-blocking engage**
   - defensive spell success shortening existed already
   - generic local combat spell success/interruption did not get the same short release
   - tank spell wait also did not get an explicit local spell-completion clear

## New engage priority behavior

T3.4h adds a narrow engage preemption rule inside scheduler dry-run selection:

- if a valid engage proposal exists
- and the top-ranked proposal is **not** a critical Cure / emergency defensive exception
- then engage is selected ahead of non-critical actions

This makes engage outrank:

- non-critical Cure
- maintenance/self-buffs
- Sleep
- routine tank setup/enmity actions
- offensive setup that is not a true emergency

## Critical Cure exception

Critical Cure remains the explicit exception.

- if the top-ranked defensive Cure is at or below the existing critical HP threshold
- Cure still wins
- engage waits until that emergency action has been handled

No new HP thresholds were introduced.

## Post-spell lockout before/after

### Before

- generic spell sends entered the normal spell acting/cooldown state
- only defensive spell success/interruption had an explicit bounded post-cast release
- generic combat spell success could leave engage waiting on the broader spell tail
- tank spell wait did not have an explicit success/interruption clear on matching local spell completion

### After

- confirmed local spell success now shortens generic spell action-state to a bounded `0.2s` tail
- confirmed local spell interruption clears generic spell lockout immediately
- matching tank spell wait now clears on local spell success/interruption instead of waiting for the broader stale path
- in-progress spells still block engage until completion/failure/interruption

## What engage now outranks

- non-critical Cure
- weak / routine Cure traffic
- maintenance/self-buffs
- Sleep
- routine tank enmity/setup
- stale post-spell cooldown after confirmed spell completion

## What still outranks or blocks engage

- critical Cure / true defensive emergency
- an actually in-progress spell cast
- normal engage duplicate/throttle protection
- invalid/dead/recent-death/out-of-range/unrelated-claim target rejection
- existing ownership and dispatch validation seams

## Anti-spam / debounce behavior

Engage anti-spam remains intact:

- engage duplicate suppression key remains unchanged
- engage action-state still leaves a short bounded cooldown tail
- no multi-second engage debounce was added

## Relationship to T3.4f and T3.4g

- **T3.4f** kept the engage priority bands healthy, especially for tank mode
- **T3.4g** made next-target acquisition nonblocking
- **T3.4h** fixes the remaining gap between those two steps by making engage dispatch itself prompt once the valid target is already selected

## Risks

- engage can now preempt more routine setup actions than before
- that is intentional for parity with real gameplay expectations once a valid target is already selected
- the main guardrail is the preserved critical Cure exception plus unchanged target validity checks

## Field-test instructions

1. Select a normal next target and verify `/attack on` fires promptly without waiting for non-critical self-buffs or routine Cure traffic.
2. Confirm critical Cure still wins first when HP is at or below the existing critical threshold.
3. Cast a non-emergency spell that completes successfully, then verify engage follows after only a short bounded tail rather than a visible stale lockout.
4. Interrupt a spell and verify engage is not left waiting on stale spell state.
5. Verify engage does not spam repeatedly on the same target.

## Rollback note

Rollback is localized to:

- `unified_scheduler.lua`
- `uc_scheduler_action_state.lua`
- `tests/replay/harness/selftest_engage_dispatch_priority.lua`
- the updated related replay tests
- this audit note and tracker updates
