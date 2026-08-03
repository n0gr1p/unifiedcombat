# Scholar Automation Phase 0 Repository Audit

**Status:** Initial repository audit complete; live field evidence remains required

**RFC:** `docs/sch_automation_rfc.md`

**Inspected:** 2026-08-02

## 1. Purpose

This audit records the repository and installed-resource evidence required before Scholar automation is implemented. It separates confirmed local facts from observations that require a live Scholar session.

No live Scholar action is authorized by this document. The strict Accession + Perpetuance + Regen sequence remains gated on confirmed charge decoding, action-message classification, and area-coverage evidence.

## 2. Installed resource evidence

The installed Windower resource files are:

- `C:\Program Files (x86)\Windower\res\jobs.lua`;
- `C:\Program Files (x86)\Windower\res\job_abilities.lua`;
- `C:\Program Files (x86)\Windower\res\spells.lua`;
- `C:\Program Files (x86)\Windower\res\buffs.lua`.

These files establish identities and static metadata. They do not prove runtime packet messages, charge-count encoding, area radius, or equipment-modified duration.

### 2.1 Job identity

| Field | Confirmed value |
| --- | --- |
| Job ID | `20` |
| English name | `Scholar` |
| Short name | `SCH` |

### 2.2 Phase 1 job abilities

| Ability | Action ID | Recast ID | Buff ID | Resource duration | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| Light Arts | 211 | 228 | 358 | 7200 | Phase 1 desired Art. |
| Dark Arts | 212 | 232 | 359 | 7200 | Deferred mode, but contradictory state must be observed. |
| Sublimation | 233 | 234 | 187 | 7200 | Buff 187 is activated; installed buffs also define complete state 188. |
| Addendum: White | 234 | 231 | 401 | not declared | Shares recast 231 and must be included in charge planning until field evidence proves its exact semantics. |
| Addendum: Black | 235 | 231 | 402 | not declared | Deferred, but shares the same charge/recast seam. |
| Accession | 218 | 231 | 366 | not declared | Phase 1 prepared stratagem. |
| Perpetuance | 316 | 231 | 469 | not declared | Phase 1 prepared stratagem. |
| Immanence | 317 | 231 | 470 | not declared | Deferred; current core already observes the buff for skillchain behavior. |
| Tabula Rasa | 210 | 0 | 377 | 180 | Never authorized automatically by Phase 1 config. |

The following deferred stratagems also use recast ID 231 in the installed resources: Penury, Celerity, Rapture, Parsimony, Alacrity, Ebullience, Manifestation, Altruism, Focalization, Tranquility, and Equanimity.

### 2.3 Phase 1 spells

| Spell | Spell ID | SCH resource level | Status ID | Base duration | Cast time | Recast | Range |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Regen V | 504 | 99 | 42 | 60 | 2.5 | 28 | 12 |
| Sandstorm II | 857 | 100 | 592 | 180 | 2.0 | 18 | 12 |
| Rainstorm II | 858 | 100 | 594 | 180 | 2.0 | 18 | 12 |
| Windstorm II | 859 | 100 | 591 | 180 | 2.0 | 18 | 12 |
| Firestorm II | 860 | 100 | 589 | 180 | 2.0 | 18 | 12 |
| Hailstorm II | 861 | 100 | 590 | 180 | 2.0 | 18 | 12 |
| Thunderstorm II | 862 | 100 | 593 | 180 | 2.0 | 18 | 12 |
| Voidstorm II | 863 | 100 | 596 | 180 | 2.0 | 18 | 12 |
| Aurorastorm II | 864 | 100 | 595 | 180 | 2.0 | 18 | 12 |

All eight Storm II resources declare the same overwrite family, spell IDs 857 through 864. A target therefore cannot have two exact Phase 1 storm assignments.

The installed `levels[20] = 100` value for Storm II is a resource convention and must not be interpreted as ordinary level-100 job eligibility. Learned-spell state must be checked at runtime before dispatch.

### 2.4 Deferred encounter spell

| Spell | Spell ID | Status ID | Base duration | Requirement metadata |
| --- | ---: | ---: | ---: | ---: |
| Embrava | 478 | 228 | 90 | `requirements = 9` |

Static requirements metadata does not grant Tabula Rasa authorization. Runtime arming and encounter policy remain separate future gates.

## 3. Existing scheduler and runtime seams

### 3.1 Cadence

`unified_engine.lua` defines a 0.20-second engine tick and a 1.00-second maintenance cadence. This supports the RFC contract:

- idle Scholar selection at 1 Hz;
- active sequence and deadline reconciliation every engine tick.

Scholar should expose a single `requires_fast_tick()` result. The scheduler should not inspect private reducer fields.

### 3.2 Direct defense

`build_defensive_candidates()` in `unified_scheduler.lua` remains the current direct cure and status-removal selector. `uc_provider_defensive.lua` converts the chosen result to `defensive_internal` proposals.

Phase 1 Scholar must not duplicate or replace this behavior. Critical preemption should consume existing defensive urgency rather than introduce a Scholar-specific cure engine.

### 3.3 Proposal and pending infrastructure

The scheduler already owns:

- proposal collection and stable provider IDs;
- ranking and proposal keys;
- action-state locks;
- pending records and completion/failure transitions;
- movement stop/settle and cast locks;
- duplicate suppression and reject history;
- action and action-message observation entry points.

Scholar should extend the existing pending correlation with sequence identity and expected evidence. It should not create a second command dispatcher or an unrelated pending-action owner.

### 3.4 Existing special lanes

`unified_scheduler.lua` contains explicit Bard and GEO maintenance handling. Bard publishes action-lane state through `uc_brd_maintenance.lua`; GEO exposes lane status through `uc_geo_maintenance.lua`.

The initial Scholar implementation should add one narrow Scholar lane filter. A general lane-ownership refactor is outside this implementation slice.

### 3.5 Lifecycle hooks

`UnifiedCombat.lua` already resets runtime modules on job change, zone change, unload, logout, and engine stop. `unified_scheduler.lua` also handles zone-change packet cleanup and scheduler lock reset.

Scholar runtime integration must be added to all applicable paths. Cleanup must be idempotent because a zone transition may be observed through more than one hook.

### 3.6 Party state and geometry

`get_party_members()` in `unified_scheduler.lua` reads `p0` through `p5`, preserves party member coordinates, uses local player vitals/buffs for self, prefers packet `0x076` buffs for remote members, and uses UnifiedCombat IPC when packet buffs are unavailable.

`uc_party_buff_tracker.lua` parses five remote entries with 32 buff slots each. Missing packet and IPC data remains missing; Scholar must not convert it to an empty buff list.

`uc_sch_party.lua` now stamps complete numeric X/Y observations with the scheduler time at which the Scholar party snapshot was taken. Incomplete coordinates remain untimestamped, malformed coordinate types fail fast, and the same immutable snapshot feeds environment validation, buff reconciliation, observe-only planning, and the one-shot trace. This proves when UnifiedCombat sampled the Windower party object; it does not by itself prove an Accession radius, distance metric, maximum acceptable observation age, or a server-update timestamp. Live area planning remains gated until those mechanics are decided from evidence.

`uc_sch_area_planner.lua` now provides the offline deterministic selection boundary: it evaluates every eligible party anchor, rejects coverage of unowned existing Regen, fails closed for missing or stale relevant coordinates, and resolves safe candidates by maximum coverage, stable party order, then target ID. Mechanics are keyed as `Accession|party`; confirmed parameters require a named evidence source. The production path deliberately supplies `mechanics.confidence = 'unknown'`; therefore the planner reports `accession_geometry_unvalidated` until radius, distance metric, and coordinate freshness are proven and configured explicitly. Synthetic confirmed fixtures exercise the complete observe-only ready path through exact plan construction while proving zero scheduler proposals are emitted.

### 3.7 Raw multi-target action evidence

`uc_brd_maintenance.lua` already iterates every raw `act.targets` entry and classifies successful recipients for area songs. Scholar should follow or extract that proven pattern.

`unified_combat_core.lua` uses the first parsed target for its general skillchain observation. That core behavior is not sufficient by itself for party-wide Regen ownership.

### 3.8 Skillchain state

`unified_combat_core.lua` and `uc_skillchain_state.lua` already observe property-bearing actions, including Immanence-style spell behavior, and maintain target-specific:

- generation;
- active properties;
- earliest close;
- preferred execute time;
- latest safe time;
- confirmed result;
- magic-burst expiration.

Later Scholar combat automation must consume this state. It must not create a separate skillchain clock.

## 4. Profile and UI seams

Summoner establishes the current top-level job-config pattern across:

- `uc_config_normalizer.lua`;
- `uc_active_config.lua`;
- `uc_profile_contract.lua`;
- `uc_profile_v2.lua`;
- `UnifiedCombatWinForms/StructuredProfileV2Writer.cs`;
- focused Lua and C# tests.

Scholar should follow this durable-section pattern while remaining stricter about enabled invalid data:

- missing `config.sch` means disabled for backward compatibility;
- once `sch.enabled` is true, Phase 1 requires an exact supported shape;
- deferred enabled features are rejected, not ignored;
- runtime fields and unknown keys are rejected;
- profile loading never arms encounter abilities and never starts the engine.

## 5. Recast evidence and unresolved charge decoding

The scheduler context already captures `windower.ffxi.get_ability_recasts()` and exposes both `ability_recasts_present` and the recast table. Ordinary providers treat `0` as ready and a positive value as unavailable.

That binary interpretation is not enough for Scholar. The installed resources prove that the relevant abilities share recast ID 231, but they do not prove how values at ID 231 map to:

- zero charges;
- one through maximum charges;
- the next recharge interval;
- job-level maximum charge count;
- Tabula Rasa behavior;
- rounding and temporary unavailability.

No production multi-charge mapping is declared from static resources alone. `uc_sch_charge_model.lua` now provides a parameterized evidence boundary for an exact level/job-point/recast model. It supports only explicitly confirmed `time_until_full` encoding with declared maximum charges, recharge interval, unit scale, rounding tolerance, Tabula policy, and evidence source. Missing recast stays `nil`, and model contradictions return unknown confidence. The production catalog remains `phase0_charge_mapping_unvalidated` until the live matrix proves those parameters.

### Required live capture matrix

Capture the raw recast value and local action evidence:

1. At each observable charge count from zero through maximum.
2. Immediately before and after Accession.
3. Immediately before and after Perpetuance.
4. Immediately before and after Addendum: White.
5. During and after Tabula Rasa.
6. After zone and job changes.
7. When recast data is absent.
8. When a prepared stratagem is followed by the intended spell.
9. When a prepared stratagem is followed by a manual eligible spell.
10. When the follow-up spell is interrupted or rejected.

The capture must record main job level/job points relevant to maximum charges. The derived algorithm must be fixture-tested before strict group Regen dispatch is enabled.

## 6. Action-message evidence still required

Static resources do not classify live `0x028` message results. Required captures include:

- Light Arts and Addendum success/rejection;
- Sublimation activation, completion, release, and no-capacity behavior;
- Accession and Perpetuance success/rejection;
- Regen V single-recipient success;
- Accession Regen V full success;
- Accession Regen V partial success;
- interruption before and after stratagem preparation;
- out-of-range and invalid-target rejection;
- target death during preparation;
- manual action contamination;
- storm success, overwrite, no-effect, and failure.

Unknown message IDs must remain transaction failures until classified.

## 7. Duration evidence still required

Installed resources declare base Regen V duration 60 seconds and Storm II duration 180 seconds. These are not authoritative Scholar-owned end times because Arts, Perpetuance, job gifts, and equipment can change duration.

`uc_sch_duration.lua` now implements the strict duration-model interface. Evidence is keyed by exact family, spell, and ordered applied modifiers. Mismatched confirmed evidence and unknown evidence carrying an invented duration fail fast. The production runtime records `phase0_duration_unvalidated`, no source, and `estimated_expires_at = 0`; party buff presence may reconcile loss but cannot create or extend a timer. A claimed duration remains prohibited until captured evidence supports that exact model key.

## 8. Initial implementation decisions

The following decisions are supported now:

1. Add `config.sch` as a top-level durable domain.
2. Use main-job SCH eligibility only.
3. Implement only `support` mode initially.
4. Keep direct cures and single-target status removal in `defensive_internal`.
5. Create one `uc_sch_runtime.lua` mutable owner.
6. Treat recast ID 231 as an observed shared pool, not as independently ready abilities.
7. Count Addendum: White as a charge-consuming prerequisite until field evidence establishes otherwise.
8. Reject all enabled deferred features in Phase 1.
9. Implement config, reducer, diagnostics snapshots, and observe-only planning before live sequences.
10. Fail closed on missing recasts, buffs, coordinates, messages, learned spells, or duration evidence.

## 9. Gate status

| Gate | Status | Evidence |
| --- | --- | --- |
| Static SCH action/spell/buff identities | PASS | Installed Windower resources inspected. |
| Existing scheduler/profile/lifecycle seams | PASS | Repository source inspected. |
| Shared recast ID identification | PASS | All relevant stratagem resources use ID 231. |
| Charge-count decoding | BLOCKED FOR LIVE DISPATCH | Requires live recast capture. |
| Charge-model decoder boundary | PASS OFFLINE | Synthetic fixtures cover full through empty boundaries, rounding, missing recast, missing job points, model contradiction, and explicit Tabula policies. The production catalog remains unvalidated. |
| Addendum charge semantics | BLOCKED FOR LIVE DISPATCH | Shared resource metadata is suggestive but not sufficient. |
| Action-message classification | BLOCKED FOR LIVE DISPATCH | Requires live packet capture. |
| Action-result classifier boundary | PASS OFFLINE | Exact action catalogs, full/partial/failure/interruption results, unknown messages, missing/unexpected recipients, and fail-closed transaction aborts are fixture-tested. The production rule catalog remains empty. |
| Accession radius and coordinate freshness | BLOCKED FOR LIVE DISPATCH | Requires mechanics decision and live validation. |
| Coordinate observation timestamp plumbing | PASS OFFLINE | The Scholar party boundary timestamps complete X/Y samples; planning and trace capture consume the same snapshot, while incomplete coordinates remain uncountable. |
| Deterministic Accession area planner | PASS OFFLINE | Pure fixtures cover all eligible anchors, maximum coverage, stable ties, unsafe recipients, minimum coverage, and missing/stale coordinates. Production mechanics remain unconfirmed. |
| Complete observe-only group Regen plan | PASS OFFLINE | Confirmed synthetic charge and geometry evidence produces the deterministic anchor, exact recipient set, strict stratagem plan, Accession candidate, and zero emitted proposals. |
| Exact observe-only targeted Storm II plan | PASS OFFLINE | Strict party evidence, exact owned/unowned identity, deterministic target selection, Arts priority, plan diagnostics, and zero provider emissions are fixture-tested. |
| Equipment-modified duration | BLOCKED FOR EXACT TIMER CLAIMS | Explicit unknown-duration behavior is implemented; exact timers still require field evidence. |
| Duration-model interface and unknown case | PASS OFFLINE | Exact model keys and evidence sources are fixture-tested; production ownership remains explicitly unknown with no end time. |
| Exact config and profile-v2 round trip | PASS | Lua validation, active projection, C# writer, and offline SCH UI tests pass. |
| Shared reducer and invariants | PASS | Deterministic sequence, lifecycle, contamination, timeout, unclassified-result abort, atomic recipient commit, and reconciliation fixtures pass; all 146 aggregate Lua replay suites pass and all 115 runtime Lua files parse under Lua 5.1. |
| Deterministic party generation and environment revalidation | PASS | Roster identity is slot-order independent; engine, domain, job, incapacitation, membership, and anchor changes abort active state. |
| Observe-only maintenance adapter | PASS | Registered at idle/trace cadence; blocker and fully ready planning paths are fixture-proven to emit zero proposals. |
| Selective scheduler lane safety | PASS FOR DORMANT INFRASTRUCTURE | Prepared support state holds routine work and movement/target changes; Doom, charm sleeper, and existing critical cures abort Scholar state before preemption. No Scholar sequence can be started by the provider yet. |
| Local action identity/contamination observation | PASS FOR IDENTITY ONLY | Local spell and JA identities are resource-resolved; manual or unknown spells abort prepared state. Success, rejection, interruption, and recipient classification remain field-gated. |
| Existing direct cure/status-removal ownership | PASS | Scheduler comparison diagnostics retain `defensive_internal`/`defensive_healbot` as the source; no Scholar cure selector was added. |
| Bounded field trace | PASS | Captures main-job level/job-point context, changing recast/buff/party samples, raw local action targets, action messages, and terminal reason without dispatch. |
| Live Arts/Sublimation/storm dispatch | NOT AUTHORIZED | Action-message field classification remains incomplete. |
| Live group Regen dispatch | NOT AUTHORIZED | Charge, geometry, action-result, and duration gates remain unresolved. |

This audit authorizes the implemented Phase 1A and observe-only Phase 1B work. It does not authorize live Scholar dispatch.
