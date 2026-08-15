# Sortie Dhartok Hazard Acceptance — 2026-08-14

## Decision

Dhartok cloud placement is accepted for opt-in generic formation avoidance. The
active hazard contract uses the second exact tracked TP move after completed
`Cesspool`, requires one resolved packet target, centers the cloud on that target's
observed world position, uses a `3.0`-yalm radius, and retains the cloud until the
encounter resets.

## Reviewed evidence

The participating clients were `Niightsiide`, `Nyoourke`, `Ponponponponpon`,
`Redrogue`, and `Terrasjr`. Their action timelines identified exact actor ID
`21000815` as `Dhartok` in Windower zone ID `133` (`Outer Ra'Kaznar [U2]`).

The capture contains two completed Cesspool sequences:

- At approximately `1786746265.5`, the next two tracked completed moves were
  `Nullifying Rain` and `Nullifying Rain`. The second packet had three targets, so it
  does not provide one authoritative cloud position and must not activate a hazard.
- At approximately `1786746826.6`, the next two tracked completed moves were
  `Fetid Eddies` and `Noyade`. The second packet had one target (`558393`) at
  approximately `(741.255, -618.265, 100)`, with matching coordinates across the
  observing clients.

Independent in-game observation confirmed that the cloud appears at the target of
the second TP move after Cesspool. The observed cloud radius is `3.0` yalms and the
cloud does not expire during the fight.

The raw stream also identifies Dhartok auto attacks as resource abilities. Those
packets are not TP moves and must not advance Cesspool pairing. The field-log audit
and runtime therefore use the exact tracked Dhartok TP-move set.

## Runtime contract

- Only completed `Clobbering Wave`, `Fetid Eddies`, `Noyade`, and `Nullifying Rain`
  advance an active Cesspool pair.
- The pair closes after its second tracked move, whether or not target resolution
  succeeds.
- Multi-target or unresolved second moves create no active hazard.
- A resolved second move creates one active hazard with radius `3.0` yalms.
- Active hazards have no timer and clear through existing encounter reset paths.
- Generic formation consumes active hazards only when
  `constraints.avoid_encounter_hazards == true`; `hazard_margin` is additive.
- Ghatjot, named-mob, and formation-mock behavior remains unchanged.

## Verification

Focused and full-suite verification results are recorded in the implementing task's
final report.
