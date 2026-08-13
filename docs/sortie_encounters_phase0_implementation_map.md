# Sortie Encounters Phase 0-3 Implementation Map

## Scope and baseline

This map covers Phase 0, the observation-only Phase 1 seam, the dormant-until-
configured Phase 2 policy path, and the pure/compatibility-first Phase 3 formation
model for
`RFC_Encounters/sortie_ae_encounter_rfc.md`.

Git baseline before implementation:

- branch: `master` tracking `origin/master`;
- pre-existing dirty path: untracked `RFC_Encounters/`;
- no tracked modifications were present.

Implementation branch: `codex/encounter-work`.

## Current integration points

### Action packets

- `UnifiedCombat.lua::uc_register_action_listener` is the single ActionPacket listener.
- It already forwards the original action to `UC_COMBAT_CORE.on_action` and
  `_G.UC_SCHED_OnAction`.
- Phase 1 adds `uc_encounter_runtime.on_action` at this listener for boss-ability
  observation only. It does not dispatch an action.
- `unified_combat_core.lua::core.on_action` already converts ActionPacket data into
  resource/action identity and computes success through
  `uc_skillchain_state.action_succeeded`. Phase 1 forwards only that normalized
  WS/BP result to the encounter observer, avoiding a second success classifier.

### Encounter identity and status observations

- `uc_encounter_registry.lua` owns the configured ID, family, actor name, and
  resource-derived Sortie zone name for Ghatjot and Dhartok.
- `uc_encounter_state.lua` owns transient identity, boss binding, origin capture,
  mechanic telemetry, Poison/Taint facts, recent successful WS/BP timestamps, and
  untrusted hazard candidates.
- `uc_encounter_runtime.lua` adapts Windower mob, party, buff, resource, and action
  data into the state-owner contract.
- Exact Ghatjot/Dhartok actions in the exact Sortie zone also emit explicitly
  untrusted `ENCOUNTER_RAW_ABILITY_CANDIDATE` and
  `ENCOUNTER_RAW_ACTION_RESULT_CANDIDATE` timeline records even while durable
  encounter activation is unavailable. These records do not bind state or drive
  policy, hazards, or movement.
- `unified_scheduler.lua::scheduler.process_tick` refreshes the observation snapshot
  before scheduler work. The returned state is not consulted by ranking or movement
  in Phase 1.

### Skillchain prediction

- `uc_skillchain_state.lua::State:get_snapshot` exposes the current target state.
- `uc_skillchain_state.lua::State:plan_continuation` owns WS continuation prediction.
- `uc_skillchain_state.lua::M.resolve_properties` owns property transitions.
- `unified_combat_core.lua::core.get_skillchain_snapshot` is the existing runtime
  snapshot facade.
- Combat WS proposals already carry the existing engine's
  `skillchain_plan.predicted_result`. Phase 2 consumes that field and adds one
  authoritative property-to-element membership table in `uc_skillchain_elements.lua`.
  It does not duplicate transition rules or create encounter-owned skillchain state.

### Scheduler validation

- `uc_scheduler_ranker.lua::M.validate_proposal` is the existing pre-rank proposal
  validation seam.
- `uc_scheduler_ranker.lua::M.rank` applies reaction blocking and hard-lock rejection
  before scoring valid proposals.
- Phase 2 calls `uc_encounter_runtime.validate_proposal` in this path before a
  proposal can win and calls it again from
  `unified_scheduler.lua::p1_revalidate_plan_commit` immediately before dispatch-plan
  commit. Proven violations use stable rejection reasons rather than score changes.

### Movement ownership and Lilith compatibility

- `unified_scheduler.lua::run_movement_coordinator_tick` observes the selected
  formation runtime, honors reaction and cast locks, then invokes
  `uc_formation_runtime.run_tick` in the existing formation priority slot.
- `uc_formation_runtime.lua` selects disabled, Lilith compatibility, or generic
  formation. Lilith still delegates unchanged to
  `uc_lilith_easy_formation_runtime.lua`; Sortie delegates to
  `uc_generic_formation_runtime.lua`.
- `uc_combat_formation.lua` remains the existing pure Lilith-specific geometry owner.
- `uc_lilith_formation_adapter.lua` continues to translate the durable Lilith role
  keys into the generic solver where parity has been established, while healer cone
  behavior remains in the compatibility evaluator.
- Generic formation uses the same dispatcher-backed movement intent path and does
  not bypass reaction holds, cast freezes, Doom handling, Nyzul holds, camp-puller
  reservation, or other higher-priority movement ownership.
- `uc_formation_mock_state.lua` provides an explicit formation-only test source for
  generic profiles. Each client explicitly binds its current target after verifying
  the configured exact name, then tracks that actor ID. It owns only transient mock
  boss/origin observations and never writes to
  `uc_encounter_state`, so the mock actor cannot activate encounter policies,
  mechanic telemetry, or hazards.

### Lifecycle and diagnostics

- Existing job-change, zone-change, unload, logout, engine-stop, and incoming zone
  packet reset paths now reset `uc_encounter_runtime` alongside Lilith state.
- `//uc encounter status` prints the observation snapshot, active policy modes,
  repeat-action tuning, last policy violation/rejection, and untrusted
  hazard-candidate wording.

## Configuration boundary

The Ghatjot-safe Phase 5 slice now provides the durable `config.encounter` domain,
strict normalizer validation, Profile V2 round-tripping, flat snapshot projection,
and WinForms controls for encounter identity, policy modes, and repeat-action tuning.
The UI defaults to disabled and makes `sortie_ghatjot` explicitly selectable. No
legacy formation key is reused as an encounter activation fallback.

The same contract can represent `sortie_dhartok`, but Dhartok spatial hazards remain
disabled and untrusted. Durable activation does not promote hazard candidates or
enable any hazard movement behavior.

`config.movement.formation` now selects `lilith_easy`, `sortie_ghatjot`, or
`sortie_dhartok`. Lilith retains its existing role/capture/tank/DPS/healer keys.
Sortie selections instead require the role-free solver-native contract:

- `placement`: `radial_band|polar_band`, `boss|encounter_origin|member` anchor,
  optional member anchor, `boss_to_member` or live `boss_heading` polar axis, radius/angle bands, and
  deterministic sample steps;
- `hysteresis`: correction start and stop distances;
- `constraints`: optional encounter-origin, boss-distance, and required-party range
  bounds plus the durable future hazard-avoidance preference and margin.
- optional `mock`: an explicit `enabled` flag and exact `mob_name` used only as the
  generic formation's boss-position/status source during field testing.

An enabled generic formation must match the enabled durable `config.encounter.id`.
WinForms exposes this contract without tank/DPS/healer semantics and writes the same
Profile V2 structure. Its formation tab labels mock mode as formation-only and tells
the user to target the exact named mob once on each client. No encounter strategy, party
composition, or world coordinate is supplied by code.

## Phase 2 policy boundary

- `uc_encounter_action_classifier.lua` resolves proposal names through Windower
  resources and classifies only verified Water-damage identities. Resource element
  alone is deliberately not accepted as damage proof for WS or Blood Pacts because
  physical Wasp Sting and Spinning Dive are both Water-tagged in current resources.
- Verified direct Water categories cover Elemental Magic, Suiton, damaging Water
  Blue Magic, Blade: Teki/Yu, Water Shot, and elemental Leviathan Blood Pacts.
  Water-tagged non-damage actions such as Poison, Awful Eye, and wards remain legal.
- `uc_encounter_policy.lua` scopes all policies to hostile proposals targeting the
  exact active boss actor. It enforces direct Water damage, predicted Water-bearing
  skillchains, and Dhartok repeated WS/BP actions within the configured guard.
- Policy modes are strict `enforce|warn|off`. Warn mode records and emits a violation
  without changing proposal eligibility. Enforce mode rejects with
  `encounter_water_damage`, `encounter_water_skillchain`, or
  `encounter_repeat_action_wall`.
- Registry defaults enforce both Water policies for Ghatjot and Dhartok. The
  unverified 10-second Dhartok repeat wall defaults to `warn`; Ghatjot's repeat wall
  is `off`.
- Successful local or externally observed WS/BP results use the existing action
  success classifier and resource action ID as the repeat key. Failed/interrupted
  actions do not create timestamps.
- Loss of the configured live actor, a wrong zone, multiple matching actors, or an
  incomplete actor clears the active binding; policy never runs against stale boss
  identity.

Phase 2 can now be activated explicitly through Profile V2 or the WinForms Encounter
Policy tab. Profiles remain disabled by default. Replay verification proves the
policy contract and scheduler seams; Ghatjot live evidence and residual limitations
are recorded in `docs/TestResults/sortie_ghatjot_acceptance_2026-08-10.md`.

## Phase 3 generic formation boundary

- `uc_generic_formation.lua` is a pure, role-free solver for `radial_band` and
  `polar_band` placement. It resolves `boss`, `encounter_origin`, or named-member
  anchors and the RFC's `boss_to_member` and live `boss_heading` axes.
- The solver applies strict radius/angle bands, encounter-origin and boss-distance
  limits, required-party range, and optional supplied hazard constraints. Phase 3
  does not promote encounter hazard candidates into those supplied constraints.
- Candidate enumeration is bounded and deterministic. Selection minimizes travel,
  then preferred-radius deviation, preferred-angle deviation, and stable generation
  order. Unsatisfied geometry returns `FORMATION_UNSATISFIED` without a goal.
- Hysteresis uses explicit start/stop distances from allowed geometry. Hard spatial
  constraints are never relaxed by hysteresis.
- `uc_generic_formation_runtime.lua` turns solver move/hold/error results into the
  existing dispatcher-backed run/stop intents. It exposes both an injectable test
  factory and a strict lazy Windower singleton and is selected for configured Sortie
  formation through `uc_formation_runtime.lua`.
- `uc_lilith_formation_adapter.lua` translates current Lilith tank and DPS settings
  into generic geometry while preserving existing proposal reasons and hysteresis.
  Lilith's healer threat-cone evaluator stays behind the compatibility adapter and
  is not imposed on the generic model.
- Existing Lilith runtime ownership and reaction/cast-lock ordering are unchanged.
  The existing `uc_combat_formation.evaluate` public wrapper remains stable.
- Generic formation can replace the live encounter snapshot with the isolated mock
  snapshot when `formation.mock.enabled` is true. Idle mock status exercises the
  normal `FORMATION_WAITING_FOR_ENGAGE` gate; after engagement, live actor movement
  feeds the same solver and scheduler coordinator used by the real encounter.
- Mock binding fails closed when the configured target is absent, name-mismatched,
  incomplete, or no longer visible. Encounter-origin geometry can be tested by
  targeting the mock mob while it is idle and stable for the normal 0.50-second
  origin capture before engaging it.

Phase 3's pure solver and runtime ownership seam and Phase 5's per-client activation
path are replay-tested. Coverage includes Profile V2 round-trip, disabled behavior,
unsatisfied geometry, scheduler ownership/precedence, Lilith compatibility, isolated
mock binding, idle/engaged transitions, origin capture, actor movement, same-name
actor stability, and explicit retargeting after actor loss.

## Remaining work blocked solely on Dhartok field evidence

Generic formation activation is complete for both Sortie encounter identities, but
the runtime passes an explicitly empty active-hazard list to the solver. The durable
`avoid_encounter_hazards` preference is stored for future use; it does not promote or
consume `hazard_candidates` today.

Only the following Phase 4 work remains blocked on the checklist in
`docs/sortie_encounters_field_validation.md`:

- prove the Cesspool/double-TP packet sequence across repeat observations;
- prove the authoritative cloud target and world position across clients;
- confirm in game that the cloud appears at that resolved position;
- define trusted hazard lifetime/radius from reviewed evidence;
- promote validated clouds from diagnostic `hazard_candidates` to a distinct active
  hazard list consumed by generic formation.

Until that evidence is recorded and reviewed, Dhartok candidates remain diagnostic
telemetry only. This gate does not block Ghatjot formation, Dhartok role-free static
geometry, encounter policy, or transient encounter-origin use.

## Phase 1 safety properties

- No encounter module calls `windower.send_command`, movement APIs, or a dispatcher.
- No scheduler proposal is rejected, rescored, or replaced.
- No hazard candidate is published as an active spatial constraint.
- Ambiguous actor identity and unresolved target coordinates produce explicit
  diagnostics; no actor or coordinate is guessed.
- Runtime state is module-owned and is not serialized into profile configuration.

## Remaining Phase 1 validation

- Field-confirm the resource zone name in a live Sortie instance.
- Field-capture named ability packets and confirm category/name mapping. This remains
  diagnostic-only for Ghatjot because no Ghatjot policy depends on a TP-move name.
- Field-confirm whether the completed Dhartok action carries exactly one authoritative
  target for cloud-location telemetry.
- Field-confirm the Cesspool double-TP sequence before promoting candidates to hazards.
- Field-confirm WS and Blood Pact success observations from local and remote actors.

Until the Dhartok checks are complete, Cesspool timing, pair interpretation, and
candidate hazard positions remain telemetry-only. They do not gate Ghatjot's actor-
scoped Water safeguards or Poison/Taint facts.

The capture procedure and acceptance checklist are in
`docs/sortie_encounters_field_validation.md`. The corresponding log summarizer is
`tests/replay/harness/audit_sortie_encounter_field_log.lua`.
