# Nyoourke SAM weaponskill timing audit

Date: 2026-07-20
Scope: original read-only audit of Nyoourke's UC/SAM profile, smart-WS selection, scheduler-owned combat dispatch, and skillchain coordination, followed by the 2026-07-20 implementation disposition.

Approved follow-up work: `docs/scheduler_owned_ws_skillchain_implementation_plan.md`

## Implementation disposition

The source-backed causes identified below have been codified and corrected in the scheduler-owned WS path:

- The incoming-WS `core.ws_timer` gate is removed. Ordinary WS still observes the documented three-second action-result minimum, now per target/resonance with a 0.3-second preferred buffer and 0.6-second late guard.
- Ready Chivalry and missing-aftermath TP reservations are evaluated before compatible continuation planning. Chivalry suppresses competing WS proposals below and at its 2,000-TP ready boundary; missing aftermath reserves TP through the 3,000-TP `AM_READY` dispatch.
- When neither TP-maintenance reservation applies, continuations use explicit scheduler band 131. Bard maintenance (200), Critical Cure (153), and Sleep/agreed emergency control (142) remain above it. Aftermath retains band 108 because the planner does not emit a competing continuation while aftermath maintenance is active.
- The selected continuation carries its target, resonance generation, effective properties, earliest time, and latest-safe deadline through scheduler commit and into the core intent owner.
- A not-yet-ready continuation reserves the scheduler action lane from routine work only after Chivalry and aftermath TP maintenance are satisfied, then becomes dispatch-admissible at the conservative preferred time (normally action result + 3.3 seconds). Emergency bands can still preempt it.
- The core revalidates the same resonance, target, WS, TP, equipment/Aftermath, status, range, reaction state, and deadline immediately before send. Failure cancels with an `SC_*` code and sends no fallback WS.
- Action-result, plan, rank, commit, dispatch, and server-confirmation telemetry is available through the action timeline.

All 99 aggregate replay suites pass. Initial Nyoourke and multi-actor evidence is recorded in `docs/TestResults/scheduler_owned_ws_skillchain_field_results_2026-07-20.md`: timing and race behavior passed, and two field-only findings were corrected. The focused post-reload acceptance also passed with 35 Nyoourke and 13 Ponponponponpon dispatches, closing `WS-SC-4`.

## Profile facts

`data/profiles/nyoourke.lua` configures the UC/SAM profile with:

- Scheduler-owned combat enabled (`domain_combat_enabled = true`).
- Weaponskills enabled and `ws_mode = "smart"`.
- Normal WS set to `Tachi: Kasha` (`weaponskill` and `ws1`).
- Aftermath enabled with `aftermath_ws = "Tachi: Fudo"`.
- `spam = false` and `solo = false`; party WS coordination is therefore active.

`Tachi: Fudo` is mapped to Masamune in `docs/aftermath_table.lua`. Its table has no per-weapon minimum override, so the selector uses the default stage 3. For Masamune this means only buff ID 272 (`Aftermath: Lv.3`) satisfies the aftermath check. IDs 270 and 271 do not.

## Selection path when aftermath is satisfied

With buff 272 present, `select_smart_ws` does not hold for aftermath and continues into party coordination and skillchain selection. A chain-continuing usable WS is selected from the character's currently available WS list. It is not limited to the configured `Tachi: Kasha` in smart mode.

Therefore, a valid chain continuation with AM3 present can still be withheld by the gates below.

## Confirmed withholding gates in the pre-implementation path

This table describes the audited before-state. The implementation disposition above and compliance audit record which paths were removed, reordered, or replaced.

| Gate | Condition | Timing / effect | Relevance |
| --- | --- | --- | --- |
| Local observed party WS hold | Another party member starts a WS on Nyoourke's current target. | Blocks selection for up to 1.6 seconds; cleared early only by that actor's `weaponskill_finish` event. | Can block even when Nyoourke has the most TP and a continuation exists. It runs before candidate selection. |
| Remote chain hold | Another client announces that it is holding the target's active chain. | Blocks Nyoourke while the received chain deadline remains active. | Intended coordination; no local TP comparison is involved. |
| TP-lead wait | A non-ignored ally is engaged on the same target, has at least 1,000 TP, and is at least 300 TP ahead of Nyoourke. | Returns `ALLY_WAIT`. | Not consistent with the reported case if Nyoourke is truly at least 300 TP ahead of every eligible ally. A smaller lead than 300 does not prevent this hold. |
| No continuation candidate | An active chain exists but none of Nyoourke's currently available WS properties continues it. | Emits a remote hold through the chain expiry and returns `SC_HOLD_NO_CONTINUE`. | Expected, but must be distinguished from a stale/incorrect candidate list in live telemetry. |
| Incoming-WS timer lock | Any WS event on the current target sets the global `core.ws_timer` to now + 3 seconds. | A chain continuation is suppressed until that timer expires, unless spam is on or the chain is no longer active. | **Primary timing concern, refined by the 2026-07-20 rules specification.** An ordinary closer should land about three seconds or more after the preceding result, so the delay itself is valid. The defect is that the timer is global, begins on WS begin as well as finish, also moves on misses/failures, and replaces the target-specific `reson.delay` instead of scheduling a buffered close within that resonance's safe window. |
| WS intent arbitration | Scheduler dispatch calls the cross-client intent gate. | Initial attempt broadcasts then waits 0.12 seconds; an equal-WS remote intent holds for 0.9 seconds; the lower actor ID wins identical simultaneous intents and the loser cools down for 1.0 second. | Can suppress a selected WS after it has won scheduler ranking. Scheduler reports this as `BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_WS_INTENT`. |
| Scheduler action state | The unified scheduler has a pending action, detects the character as acting, or is inside cooldown/tail state. | WS dispatch is blocked before the WS-specific dispatch branch. | Common general contention path. A spell's completion tail is specifically capable of blocking combat actions. |
| Scheduler arbitration | Normal WS proposals have priority band 70. | Any higher-ranked proposal wins the tick. Defensive actions use 100, dispel uses 106, sleep 113, and critical cures 117. | AM3 does not elevate normal Kasha/chain-continuation proposals. Only the special `AM_READY` Fudo proposal receives band 108, which occurs while AM3 is absent at 3,000 TP. |
| Proposal / target revalidation | The WS proposal has a 0.30-second expiry and 0.20-second commit deadline. | Target invalidation, 0 HP, or a missed commit window drops the proposal. | Less likely as persistent behavior, but can make a narrow chain window appear missed. |

## Main finding (refined against the rules specification)

The three-second minimum is not itself a contradiction: the supplied rules specification says an ordinary closing action must land approximately three seconds or more after the preceding action result. Immediate dispatch is therefore not generally correct.

The implementation problem is how that rule is represented. `core.ws_timer` is global rather than target/resonance-specific, is updated before success filtering for WS begin and finish traffic, and is used instead of the stored action-specific `reson.delay`. It has no preferred execution buffer, latest-safe guard, or resonance version for commit-time revalidation. This can delay valid continuations after misses/failures, allow Chainbound or retargeted continuations too early, and lose shortening windows through scheduler/intent contention.

## Secondary finding

The one scheduling boost for WS is narrowly applied to `AM_READY` (Fudo at 3,000 TP while AM3 is missing). Once AM3 is satisfied, Nyoourke's chain-continuing WS returns `READY` at ordinary band 70. This can lose to routine defensive work (band 100) and other high-priority work even when it would extend an active chain.

## Recommended change from the original audit (implemented)

Treat a valid active-chain continuation as an explicit target-scoped, high-priority, short-deadline intent. Replace the global `ws_timer` eligibility source with the resonance's action-result timestamp, action-specific earliest-close time, buffered preferred execution time, and guarded latest-safe time. Revalidate the same resonance immediately before dispatch; do not bypass the ordinary minimum-close rule. The change should be accompanied by replay coverage for:

1. AM3 present, Nyoourke highest TP, valid continuation: dispatch before the active chain expires.
2. Same setup with no continuation: preserve `SC_HOLD_NO_CONTINUE`.
3. Simultaneous party WS/intent traffic: preserve the selected coordination winner without duplicate WS commands.
4. Critical cure and doom handling: retain their existing preemption rules.

## Focused live evidence completion

Initial Nyoourke and multi-actor timing logs proved timing and race behavior and exposed two corrected field-only findings. After reloading the corrected runtime, the required capture exceeded five ordinary continuation attempts for both active WS actors. The decisive values were:

- `SC_OPENER_INSTALLED`, `SC_RESULT_CONFIRMED`, and any `SC_PREDICTION_DISAGREEMENT`.
- `SC_CONTINUATION_PLANNED`, `SC_CONTINUATION_PROPOSED`, and their target/generation/timing fields.
- `SC_COMMIT_RESULT` and `SC_WS_DISPATCHED`, including cancellation codes for stale plans.
- `SC_DISPATCH_PENDING_RESULT` after each send, with no second `dispatch_commit` for the same target/generation.
- Masamune AM3 Double Light predicted as `Light`, not `Radiance`.

The deterministic audit passed: Nyoourke recorded 35 dispatches with a 0.220-second minimum offset after preferred time and 1.175-second minimum safe margin; Ponponponponpon recorded 13 dispatches with a 0.246-second minimum offset and 2.699-second minimum safe margin. No duplicate target/generation dispatch or non-Aeonic Ultimate prediction was found. See `docs/TestResults/scheduler_owned_ws_skillchain_field_results_2026-07-20.md` for the full bounded evidence.
