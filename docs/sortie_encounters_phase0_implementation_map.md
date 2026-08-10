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

Implementation branch: `codex/encounters-rfc`.

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

- `unified_scheduler.lua::run_movement_coordinator_tick` observes Lilith formation,
  honors reaction and cast locks, then invokes
  `uc_lilith_easy_formation_runtime.run_tick`.
- `uc_lilith_easy_formation_runtime.lua` remains the dispatcher-backed runtime owner.
- `uc_combat_formation.lua` remains the existing pure Lilith-specific geometry owner.
- Phase 3 should introduce generic geometry beside these modules, then translate
  legacy Lilith configuration through a compatibility adapter after parity tests.
- Phase 1 does not change formation evaluation, movement priority, or dispatch.

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
  anchors and the RFC's initial `boss_to_member` axis.
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
  factory and a strict lazy Windower singleton, but is not yet selected by profile
  configuration or the scheduler movement coordinator.
- `uc_lilith_formation_adapter.lua` translates current Lilith tank and DPS settings
  into generic geometry while preserving existing proposal reasons and hysteresis.
  Lilith's healer threat-cone evaluator stays behind the compatibility adapter and
  is not imposed on the generic model.
- Existing Lilith runtime ownership and reaction/cast-lock ordering are unchanged.
  The existing `uc_combat_formation.evaluate` public wrapper remains stable.

Phase 3's pure solver and runtime ownership seam are replay-tested. Activating
per-client Sortie geometry still belongs to Phase 5's durable configuration work;
Dhartok hazard activation remains blocked on the field evidence required by Phase 4.

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
