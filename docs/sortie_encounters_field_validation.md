# Sortie Encounters Field Validation

## Purpose

This procedure records the live evidence used to promote validated Dhartok clouds
into movement constraints. It also validates the Phase 1
zone, ability, target, and WS/BP observation contracts. Dhartok's gate is independent
of Ghatjot's completed durable policy path.

The raw capture path is intentionally independent of `config.encounter`. It only
recognizes exact `Ghatjot` or `Dhartok` actors in Windower zone ID `133`
(`Outer Ra'Kaznar [U2]`). Raw candidates never activate encounter state, reject an
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

- [x] The live zone resolves to Windower zone ID `133` (`Outer Ra'Kaznar [U2]`).
- [x] Ghatjot and Dhartok actor IDs/names resolve without ambiguity.
- [x] Category 7 consistently represents the expected readied packet shape.
- [x] Category 11 consistently represents the expected completed packet shape.
- [x] Resource IDs resolve to the observed ability names on every client.
- [x] Cesspool pairing is repeatable across multiple sequences.
- [x] The second completed TP move has exactly one authoritative target, or the
      implementation is revised to represent the actual packet shape without
      guessing.
- [x] Target coordinates agree across clients closely enough to represent one world
      position.
- [x] Independent in-game observation confirms the cloud appears at that position;
      packet structure alone is insufficient.
- [x] Successful WS/BP observations are recorded, while failed/interrupted actions
      are not accepted as repeat-wall timestamps.
- [x] No raw candidate changed policy, movement, or durable configuration.

The reviewed evidence and Phase 4 activation decision are recorded in
`docs/TestResults/sortie_dhartok_hazard_acceptance_2026-08-14.md`.
