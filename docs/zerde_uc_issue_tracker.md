# Zerde UC Reliability Issue Tracker

This document tracks the UnifiedCombat issues exposed by the current Zerde SMN burn workflow. The intent is to keep the work durable in-repo and close the items one at a time with code, tests, and commit references.

## Scope

Encounter setup currently uses RUN / 2x SMN / GEO / BRD / COR with player Auto Engage disabled and Summoner pet engagement enabled. The SMN Rage model-edge range bug has already been fixed and is not part of this tracker.

## Status

| # | Issue | Status | Notes |
| --- | --- | --- | --- |
| 1 | Optional pet-aware tank enmity recovery | COMPLETE | Opt-in party/alliance-pet victim detection shipped and passed in-game Zerde validation. |
| 2 | GEO Indi ownership/reconciliation | NOT A BUG | The pre-pull Indi was legitimately stripped when Geas Fete Confrontation began; the combat-start recast was required. |
| 3 | RUN Foil dispatch + no-TP RUN mode | READY FOR REVIEW | Fixes Foil self-spell dispatch, corrects Gambit/Rayke engagement semantics, and adds optional engaged-facing-away no-TP mode. |
| 4 | Tank enmity priority inversion | OPEN | Reactive tank enmity recovery is priority 96 while generic configured tank JAs are priority 99. |
| 5 | Phantom spell-action / spell ownership stall | OPEN | UC believed Cure III had been sent, no cast started, and spell-action ownership remained occupied long enough to delay Geo-Frailty until nearly the second Just Desserts. |

---

## 1. Optional pet-aware tank enmity recovery

### Status

**COMPLETE**

Implemented and merged on `master` through commit `bd1a35f` (`Complete pet-aware tank enmity #1`). In-game pet-enmity breach testing passed on 2026-09-14.

### Problem

The tank enmity workflow only reacted when an enemy was targeting a recognized friendly player. Summoned pets were not included in that friendly-victim set. In the Zerde burn this allowed Zerde to turn onto an Ifrit without triggering Flash/Provoke recovery.

### Result

An opt-in tank-enmity setting now treats pets owned by friendly party/alliance members as valid enmity-violation victims without globally redefining friendly combat members. Existing player-only behavior remains unchanged when the option is disabled.

---

## 2. GEO Indi ownership/reconciliation

### Status

**NOT A BUG / CLOSED WITHOUT CODE CHANGE**

### Original observation

A pre-pull Indi-Malaise was active and UC cast Indi-Malaise again shortly after the Zerde fight began. This initially looked like lost GEO ownership.

### Corrected root cause

The log sequence shows the first Indi-Malaise was cast before the Geas Fete confrontation began. Starting the confrontation strips active Geomancy effects. The later Indi-Malaise was therefore a legitimate restoration after the real Indi-Colure effect disappeared, not a redundant automation recast.

PR #44, which attempted to preserve GEO ownership across soft transitions, was closed unmerged after this was established. No GEO ownership change from that PR belongs on `master`.

---

## 3. RUN Foil dispatch + no-TP RUN mode

### Status

**READY FOR REVIEW**

Implementation commit: `84a9993` (`Fix RUN Foil self spell dispatch`).

### Observed failure

The RUN provider correctly proposed Foil as a self-targeted spell. The Zerde run then showed `structured_spell_invalid_target_id`, Foil being represented as sent, no corresponding Foil cast start, and repeated retries that prevented the provider from reaching Gambit/Rayke.

### Root cause

The provider was not the problem: its self-target proposal already carried the RUN player's valid id and used `/ma "Foil" <me>`.

The combat self-spell dispatch branch rebuilt that proposal into a structured `send_command` intent but omitted `meta.target_id`. `uc_scheduler_dispatcher` intentionally rejects every structured spell whose target id is zero, producing exactly the `structured_spell_invalid_target_id` error seen in the run.

The same self-spell branch also proceeded to mark spell ownership after command ownership returned, instead of explicitly requiring successful command dispatch first. This made the historical failure appear downstream as a sent/no-cast Foil lifecycle.

### Fix

- Resolve the local player id once for every combat self-spell and fail closed if it is unavailable.
- Carry that player id into the structured spell intent as `meta.target_id`.
- Preserve provider metadata on the intent.
- Require successful command dispatch before `action_mark_sent`, `SPELL_SENT`, and phase-1 pending ownership are recorded.
- Reuse the same validated player id for action-state and timeline target metadata.

This is a general combat self-spell fix; it is not hard-coded to Foil.

### Verification

Focused coverage now verifies:

- Foil proposals are `target_kind='self'` and carry the RUN player's id.
- Unengaged RUN automation with a valid enemy selected still proposes Foil to the RUN, never the enemy.
- A valid structured Foil intent passes dispatcher validation and executes `/ma "Foil" <me>`.
- A structured self-spell missing its player target id fails closed and executes no command.
- Spell ownership is marked only after the self-spell dispatch-success guard.
- If Foil is unavailable at readiness time, the RUN provider falls through to Gambit rather than starving later support actions.

Focused Lua tests passed together:

- `selftest_run_tank.lua`
- `selftest_run_foil_dispatch.lua`
- `selftest_scheduler_dispatcher_phase2.lua`
- `selftest_command_ownership_static.lua`
- `selftest_command_ownership_runtime.lua`

### Scope boundary with issue #5

Investigation showed this Foil incident was a **pre-dispatch structured-intent validation failure**, not evidence of a successfully dispatched Foil command that later failed to produce a cast-start acknowledgement. Therefore issue #3 does not change the generic 8-second spell action-state timeout or invent a new global no-start timeout.

Issue #5 remains responsible for the separate, evidenced case where a spell command is considered dispatched but no real cast begins and ownership remains occupied too long.

### Corrected RUN engagement/facing mechanics

Follow-up in-game verification established that Gambit and Rayke cannot be used while the RUN is disengaged. The earlier RUN design and documentation incorrectly allowed those enemy-targeted Effusions whenever a valid enemy was selected. They **can**, however, be used while the RUN is engaged and facing away from the enemy.

Issue #3 therefore also includes the smallest general correction:

- Gambit and Rayke require true player engagement before readiness/proposal.
- Their engagement requirement is separate from front-arc requirements; facing away must not block them.
- Optional `tank.run.no_tp_mode` keeps an engaged RUN persistently facing away from the current live enemy, suppressing normal melee swings/TP feed.
- No-TP mode does not own engagement; Auto Engage or manual control still enters combat.
- No-TP mode is default-off and must not alter normal facing when disabled.
- While facing away, the RUN cannot parry; no-TP mode intentionally trades that defensive benefit for reduced melee TP feed.

### In-game acceptance

A small RUN validation against any normal target is sufficient; another full Zerde attempt is not required. Expected results:

1. missing/ready Foil produces one real self-targeted cast with a normal lifecycle;
2. Gambit/Rayke are not proposed while Niightsiide is disengaged;
3. with no-TP mode enabled and Niightsiide engaged, UC keeps him facing away;
4. Gambit/Rayke still execute while that away-facing is held;
5. disabling no-TP mode restores ordinary facing behavior.

---

## 4. Tank enmity priority inversion

### Problem

Reactive tank enmity recovery currently runs at priority band 96 while generic configured JAs in tank mode run at priority band 99. This lets routine configured JAs outrank a detected hate-loss recovery.

### Required behavior

Define a scheduler ordering where reactive tank enmity recovery outranks routine configured tank JAs while preserving higher-priority emergency sustain/defensive work.

### Acceptance criteria

- A ready Flash/Provoke-style recovery wins over a routine configured tank JA when both are eligible.
- Non-tank configured JA behavior is unchanged.
- Existing starvation protection remains intact.
- Update tests that currently encode tank configured JA priority 99 as being above recovery.

---

## 5. Phantom spell-action / spell ownership stall

### Problem

During the Zerde opening UC recorded Cure III on Redrogue as sent, but no cast began. Spell-action ownership remained occupied for roughly ten seconds, delaying Geo-Frailty until almost the second Just Desserts.

### Investigation targets

- Exact path that marks a structured spell as sent before a real cast start.
- Ack timeout/release behavior for spells with no outgoing cast packet.
- Whether the failure is in dispatcher result handling, action ownership, pending spell state, or provider revalidation.
- Whether the same failure class can affect other successfully dispatched spells.

### Acceptance criteria

- A spell that does not actually begin casting cannot hold spell-action ownership for an extended window.
- Failed/no-ack spell attempts release ownership promptly and enter bounded retry/backoff.
- Valid casts retain normal duplicate suppression and ack behavior.
- Regression coverage includes a dispatch-success/no-cast-start scenario.

---

## Encounter tuning tracked separately

These are relevant to Zerde but are not currently classified as UC core bugs in this tracker:

- Fire Threnody II landed too late in the burn window and may need reaction-sequence optimization.
- Light Shot missed; treat as accuracy/RNG unless automation evidence shows otherwise.
- Avatar pre-positioning remains an encounter setup requirement.

## Work order

Work the issues in numerical order unless investigation proves that one item is a prerequisite for another. For each item: reproduce or inspect the responsible path, implement the smallest general fix, add focused tests, update this tracker with the resulting commit(s), then move to the next issue.
