# Zerde UC Reliability Issue Tracker

This document tracks the UnifiedCombat issues exposed by the current Zerde SMN burn workflow. The intent is to keep the work durable in-repo and close the items one at a time with code, tests, and commit references.

## Scope

Encounter setup currently uses RUN / 2x SMN / GEO / BRD / COR with player Auto Engage disabled and Summoner pet engagement enabled. The SMN Rage model-edge range bug has already been fixed and is not part of this tracker.

## Status

| # | Issue | Status | Notes |
| --- | --- | --- | --- |
| 1 | Optional pet-aware tank enmity recovery | OPEN | Tank recovery currently recognizes player victims but not party/alliance pets. |
| 2 | GEO Indi ownership/reconciliation | OPEN | A pre-existing Indi-Malaise was not retained as owned during the Zerde opening and UC attempted to recast it. |
| 3 | RUN Foil dispatch/ack failure | OPEN | Foil is proposed as a self-targeted spell, but the observed run repeatedly treated it as sent without a corresponding cast; the loop also starved Gambit/Rayke. |
| 4 | Tank enmity priority inversion | OPEN | Reactive tank enmity recovery is priority 96 while generic configured tank JAs are priority 99. |
| 5 | Phantom spell-action / spell ownership stall | OPEN | UC believed Cure III had been sent, no cast started, and spell-action ownership remained occupied long enough to delay Geo-Frailty until nearly the second Just Desserts. |

---

## 1. Optional pet-aware tank enmity recovery

### Problem

The tank enmity workflow only reacts when an enemy is targeting a recognized friendly player. Summoned pets are not included in that friendly-victim set. In the Zerde burn this allows Zerde to turn onto an Ifrit without triggering Flash/Provoke recovery. Once Zerde turns, an avatar that was deliberately positioned behind the mob can become frontal and receive Amnesia, stopping Rage pacts.

### Required behavior

Add an opt-in tank-enmity setting that treats pets owned by friendly party/alliance members as valid enmity-violation victims. This must be scoped to tank enmity detection; do not globally redefine friendly combat members or claim ownership to include pets.

### Acceptance criteria

- Default behavior remains unchanged when the option is disabled.
- When enabled, an enemy targeting a friendly party pet can trigger the same tank enmity recovery path used for a non-tank party member.
- Pet victim diagnostics include pet identity and, when resolvable, owner identity.
- Existing player-only tank enmity behavior is unchanged.
- Add focused regression coverage for enabled and disabled pet-victim behavior.

---

## 2. GEO Indi ownership/reconciliation

### Problem

A pre-pull Indi-Malaise was active, but the GEO maintenance runtime later lost ownership and attempted to cast Indi-Malaise again during the burn window.

### Investigation targets

- How `owned_indi_spell` is established after an observed successful Indi cast.
- How ownership is reconciled from the generic Indi-Colure buff.
- Whether an engine/config/activity transition clears identity while the actual buff remains active.
- Whether a pending token timeout or unrelated sequence transition can clear ownership incorrectly.

### Acceptance criteria

- A successfully observed owned Indi remains owned while the corresponding Indi-Colure effect is still active.
- Legitimate loss/replacement of the Indi effect still clears/replaces ownership.
- Pre-pull Indi maintenance does not issue a redundant recast during the Zerde opening.
- Regression coverage reproduces the pre-pull-to-combat transition.

---

## 3. RUN Foil dispatch/ack failure

### Problem

The RUN provider correctly proposes Foil as a self-targeted spell, but the observed Zerde run repeatedly treated Foil as sent without an actual cast packet. Because the RUN provider returns after proposing Foil, repeated Foil failure also prevents Gambit/Rayke from being reached.

### Investigation targets

- Structured self-target spell construction for RUN Foil.
- The `structured_spell_invalid_target_id` errors seen in the same run and whether they are related to Foil.
- Spell dispatch ownership/ack lifecycle for self-targeted combat-provider spells.
- Failure/backoff behavior so one broken Foil attempt cannot indefinitely starve later RUN support actions.

### Acceptance criteria

- Foil dispatches to the RUN and produces a real cast/action lifecycle.
- Self-targeted Foil never uses the enemy as its spell target.
- A failed Foil attempt enters bounded retry/backoff and does not permanently starve Gambit/Rayke.
- Add focused regression coverage for unengaged RUN usage with a valid enemy selected.

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
- Whether the same failure class can affect Foil.

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
