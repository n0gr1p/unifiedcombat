# Nyoourke SAM weaponskill timing audit

Date: 2026-07-20
Scope: read-only audit of Nyoourke's UC/SAM profile, smart-WS selection, scheduler-owned combat dispatch, and skillchain coordination. No runtime behavior was changed.

## Profile facts

`data/profiles/nyoourke.lua` configures the UC/SAM profile with:

- Scheduler-owned combat enabled (`scheduler_dark_launch_combat = true`).
- Weaponskills enabled and `ws_mode = "smart"`.
- Normal WS set to `Tachi: Kasha` (`weaponskill` and `ws1`).
- Aftermath enabled with `aftermath_ws = "Tachi: Fudo"`.
- `spam = false` and `solo = false`; party WS coordination is therefore active.

`Tachi: Fudo` is mapped to Masamune in `docs/aftermath_table.lua`. Its table has no per-weapon minimum override, so the selector uses the default stage 3. For Masamune this means only buff ID 272 (`Aftermath: Lv.3`) satisfies the aftermath check. IDs 270 and 271 do not.

## Selection path when aftermath is satisfied

With buff 272 present, `select_smart_ws` does not hold for aftermath and continues into party coordination and skillchain selection. A chain-continuing usable WS is selected from the character's currently available WS list. It is not limited to the configured `Tachi: Kasha` in smart mode.

Therefore, a valid chain continuation with AM3 present can still be withheld by the gates below.

## Confirmed withholding gates

| Gate | Condition | Timing / effect | Relevance |
| --- | --- | --- | --- |
| Local observed party WS hold | Another party member starts a WS on Nyoourke's current target. | Blocks selection for up to 1.6 seconds; cleared early only by that actor's `weaponskill_finish` event. | Can block even when Nyoourke has the most TP and a continuation exists. It runs before candidate selection. |
| Remote chain hold | Another client announces that it is holding the target's active chain. | Blocks Nyoourke while the received chain deadline remains active. | Intended coordination; no local TP comparison is involved. |
| TP-lead wait | A non-ignored ally is engaged on the same target, has at least 1,000 TP, and is at least 300 TP ahead of Nyoourke. | Returns `ALLY_WAIT`. | Not consistent with the reported case if Nyoourke is truly at least 300 TP ahead of every eligible ally. A smaller lead than 300 does not prevent this hold. |
| No continuation candidate | An active chain exists but none of Nyoourke's currently available WS properties continues it. | Emits a remote hold through the chain expiry and returns `SC_HOLD_NO_CONTINUE`. | Expected, but must be distinguished from a stale/incorrect candidate list in live telemetry. |
| Incoming-WS timer lock | Any WS event on the current target sets `core.ws_timer` to now + 3 seconds. | A chain continuation is suppressed until that 3-second timer expires, unless spam is on or the chain has already expired. | **Primary timing concern.** The skillchain state remains valid for `delay + 8 - step`; the selector can know a valid continuation exists yet return `TIMER_LOCK` for approximately three seconds after the initiating WS. This leaves little or no practical time to dispatch and land a continuation. |
| WS intent arbitration | Scheduler dispatch calls the cross-client intent gate. | Initial attempt broadcasts then waits 0.12 seconds; an equal-WS remote intent holds for 0.9 seconds; the lower actor ID wins identical simultaneous intents and the loser cools down for 1.0 second. | Can suppress a selected WS after it has won scheduler ranking. Scheduler reports this as `BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_WS_INTENT`. |
| Scheduler action state | The unified scheduler has a pending action, detects the character as acting, or is inside cooldown/tail state. | WS dispatch is blocked before the WS-specific dispatch branch. | Common general contention path. A spell's completion tail is specifically capable of blocking combat actions. |
| Scheduler arbitration | Normal WS proposals have priority band 70. | Any higher-ranked proposal wins the tick. Defensive actions use 100, dispel uses 106, sleep 113, and critical cures 117. | AM3 does not elevate normal Kasha/chain-continuation proposals. Only the special `AM_READY` Fudo proposal receives band 108, which occurs while AM3 is absent at 3,000 TP. |
| Proposal / target revalidation | The WS proposal has a 0.30-second expiry and 0.20-second commit deadline. | Target invalidation, 0 HP, or a missed commit window drops the proposal. | Less likely as persistent behavior, but can make a narrow chain window appear missed. |

## Main finding

The implementation contains a direct contradiction with the desired behavior: after an incoming WS creates an active chain, `rebuild_ws_candidates` may identify a valid continuation, but the final selector refuses to return it until `core.ws_timer` (set to three seconds by that same incoming WS) expires. This is independent of aftermath state and party TP leadership.

Because Nyoourke is scheduler-owned, that delay is compounded by the scheduler's 5 Hz collection cadence, proposal expiry/commit windows, intent handshake, and any action-state lock. It is a credible explanation for repeatedly seeing TP available and a continuation candidate without an immediate WS.

## Secondary finding

The one scheduling boost for WS is narrowly applied to `AM_READY` (Fudo at 3,000 TP while AM3 is missing). Once AM3 is satisfied, Nyoourke's chain-continuing WS returns `READY` at ordinary band 70. This can lose to routine defensive work (band 100) and other high-priority work even when it would extend an active chain.

## Recommended next change (not implemented)

Treat a valid active-chain continuation as an explicit high-priority, short-deadline intent and bypass or replace the generic three-second `ws_timer` lock for that case. Keep the existing lock for non-chain WS to avoid duplicate/animation spam. The change should be accompanied by replay coverage for:

1. AM3 present, Nyoourke highest TP, valid continuation: dispatch before the active chain expires.
2. Same setup with no continuation: preserve `SC_HOLD_NO_CONTINUE`.
3. Simultaneous party WS/intent traffic: preserve the selected coordination winner without duplicate WS commands.
4. Critical cure and doom handling: retain their existing preemption rules.

## Live evidence needed before implementation

Enable Nyoourke's combat scheduler log and capture the WS diagnostics around a missed window. The decisive values are:

- `UC_WS_LAST_DIAG`, especially `TIMER_LOCK`, `ALLY_WS_READY_HOLD`, `ALLY_WAIT`, or `SC_HOLD_NO_CONTINUE`.
- `UC_LAST_SCHED_ACTION`, especially `ws_hold` intent reasons.
- Scheduler reject history / combat log for `hard_locked`, `pending_conflict`, `reaction_hold`, and dispatch blocks.

No Nyoourke action-timeline or combat-scheduler log was present in `data/logs` during this audit, so the finding is source-backed but not yet matched to a captured live event.
