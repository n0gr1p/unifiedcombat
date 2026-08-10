# Sortie Encounters Field Validation

## Purpose

This procedure gathers the live evidence required before Phase 4 may promote
Dhartok hazard candidates into movement constraints. It also validates the Phase 1
zone, ability, target, and WS/BP observation contracts. Dhartok's gate is independent
of Ghatjot's completed durable policy path.

The raw capture path is intentionally independent of `config.encounter`. It only
recognizes exact `Ghatjot` or `Dhartok` actors in the exact resource-derived zone
`Outer Ra'Kaznar [U3]`. Raw candidates never activate encounter state, reject an
action, create a trusted hazard, or dispatch movement.

## Capture preparation

1. Run the branch build on at least one participating client.
2. Set `_G.UC_DEBUG_ACTION_TIMELINE = true` before the run, using the same local
   debug bootstrap used for existing action-economy timeline captures.
3. Reload UnifiedCombat so the timeline starts a new session.
4. Note the character and session start time. Do not delete older logs.

Timeline output is written to:

```text
data/logs/action_timeline_<character>.log
```

## Required live actions

- Observe at least one readied and one completed named ability from Ghatjot.
- Observe at least one readied and one completed named ability from Dhartok.
- For Dhartok, capture Cesspool followed by both completed TP moves in the reported
  pair.
- Capture more than one Cesspool sequence if practical; one packet sequence is not
  sufficient to establish a stable rule.
- Include successful and failed/interrupted WS or Blood Pact attempts against
  Dhartok when practical.
- If multiple clients capture the same sequence, retain all logs for coordinate and
  target-count comparison.

After the run, set `_G.UC_DEBUG_ACTION_TIMELINE = false` if continuous timeline
logging is not otherwise wanted.

## Raw evidence fields

`ENCOUNTER_RAW_ABILITY_CANDIDATE` records:

- exact actor ID/name and zone;
- action category and interpreted `readied|completed` phase;
- resource ability ID, normalized ability key, and name;
- raw action parameter;
- exact packet target count;
- every target ID and target coordinates available at observation time;
- per-target action message, parameter, reaction, animation, effect, stagger, and
  add-effect fields.

`ENCOUNTER_RAW_ACTION_RESULT_CANDIDATE` records normalized WS/BP result evidence,
including the resource action key, actor, boss target, observation time, and the
existing success classifier result.

## Summarize a capture

From the addon directory:

```powershell
lua tests\replay\harness\audit_sortie_encounter_field_log.lua data\logs\action_timeline_<character>.log
```

The summarizer reports ability/category counts and each observed Cesspool sequence's
first and second completed TP moves. `authoritative_second_target=true` means only
that the packet had exactly one target and that target had resolved coordinates. It
does not by itself prove the cloud was created there.

For direct inspection:

```powershell
rg -n "ENCOUNTER_RAW_(ABILITY|ACTION_RESULT)_CANDIDATE" data\logs\action_timeline_<character>.log
```

## Acceptance checklist

- [ ] The live zone resolves exactly to `Outer Ra'Kaznar [U3]`.
- [ ] Ghatjot and Dhartok actor IDs/names resolve without ambiguity.
- [ ] Category 7 consistently represents the expected readied packet shape.
- [ ] Category 11 consistently represents the expected completed packet shape.
- [ ] Resource IDs resolve to the observed ability names on every client.
- [ ] Cesspool pairing is repeatable across multiple sequences.
- [ ] The second completed TP move has exactly one authoritative target, or the
      implementation is revised to represent the actual packet shape without
      guessing.
- [ ] Target coordinates agree across clients closely enough to represent one world
      position.
- [ ] Independent in-game observation confirms the cloud appears at that position;
      packet structure alone is insufficient.
- [ ] Successful WS/BP observations are recorded, while failed/interrupted actions
      are not accepted as repeat-wall timestamps.
- [ ] No raw candidate changed policy, movement, or durable configuration.

Phase 4 remains gated for Dhartok until these items are reviewed and recorded under
`docs/TestResults/`. Ghatjot does not create a dynamic spatial hazard, and its hard
policies do not depend on a named boss ability, so this gate does not prevent
Ghatjot from being enabled through durable configuration.
