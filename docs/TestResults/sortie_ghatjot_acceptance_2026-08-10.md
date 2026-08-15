# Sortie Ghatjot Acceptance — 2026-08-10

## Decision

The Ghatjot encounter implementation is ready for opt-in use through durable
Profile V2 configuration. Dhartok dynamic hazards remain separately blocked on live
field evidence.

## Implemented contract

- exact configured identity `sortie_ghatjot`;
- exact actor name `Ghatjot` in Windower zone ID `133` (`Outer Ra'Kaznar [U2]`);
- ambiguous, missing, replaced, or defeated actor lifecycle handling;
- actor-scoped direct Water damage policy;
- actor-scoped predicted Water-bearing skillchain policy;
- strict `enforce|warn|off` policy modes;
- Poison/Taint encounter facts without direct status-removal dispatch;
- Profile V2, config normalizer, active-config projection, and WinForms encounter
  policy controls;
- `//uc encounter status` diagnostics.

Ghatjot does not use Dhartok's repeat-action wall and has no initial dynamic spatial
hazard. Its UI-authored repeat-action mode is therefore required to remain `off`.

## Available live evidence

Local action-timeline logs from the 2026-08-10 Sortie run show:

- `Nyoourke` and `Terrasjr` independently selected and engaged the same actor ID
  `21000566` with exact name `Ghatjot`;
- the observed fight window spans approximately timeline timestamps `17632` through
  `17771` on both clients;
- during that window, `Niightsiide` proposed and dispatched `Poisona` through the
  existing `defensive_internal` provider for `Nyoourke` at timestamp `17715`;
- the defensive action followed the normal scheduler/action-state path; encounter
  observation did not dispatch status removal directly.

The raw encounter candidate logger was added after this captured run, so these logs
do not contain Ghatjot category-7/category-11 named-ability records. No implemented
Ghatjot policy keys off a TP-move name, target coordinate, or ability packet phase.
That missing capture is retained as a diagnostic follow-up rather than a safety gate.

## Verification criteria

- [x] Exact configured Ghatjot identity is tested.
- [x] Wrong zone, wrong actor, ambiguous actor, actor replacement, and defeat reset
  behavior are tested.
- [x] Direct Water proposals to the active boss are rejected in enforce mode.
- [x] Water proposals to unrelated targets remain unaffected.
- [x] Predicted Water-bearing skillchains are rejected in enforce mode.
- [x] Ghatjot does not receive Dhartok repeat-action behavior.
- [x] Poison/Taint remain encounter facts and use the existing defensive provider.
- [x] Durable configuration is disabled by default and validated before save/load.
- [x] Runtime encounter state is excluded from durable profiles.
- [ ] Capture Ghatjot named-ability category telemetry on a future run for additional
  diagnostics.

## Residual boundary

Generic formation remains shared optional infrastructure. Ghatjot has no required
dynamic spatial constraint, so its safety-policy completion does not activate new
movement behavior. Dhartok Cesspool pairing, cloud coordinates, trusted hazard
promotion, and hazard-radius tuning remain blocked and out of this acceptance.
