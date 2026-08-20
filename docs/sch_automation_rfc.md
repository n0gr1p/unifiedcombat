# RFC: Stateful Scholar Automation

**Status:** Phase 2 Scholar-aware group defense implemented (2026-08-20)

> **2026-08-20 live update:** The historical Phase 0/observe-only descriptions below
> document the development gates that preceded field capture. The production adapter now
> dispatches Light Arts, Sublimation activation/release, exact configured Storm II spells,
> an ordered list of exact Accession + Perpetuance maintenance spells, and Phase 2 Scholar-aware defense:
> Accession Cure I-IV, Accession Erase/-na, Rapture Cure I-IV, and Penury Cure I-IV.
> Production evidence is limited
> to the captured level-99, 2100-JP Scholar charge model, the captured Accession geometry,
> captured action-result messages, the captured 440-second Regen V duration, and the
> captured 332-MP Sublimation release-capacity threshold. Uncaptured progression and action
> identities remain fail-closed. Automatic Tabula Rasa use and all deferred Phase 3+ work
> remain disabled.
>
> Accession maintenance is admitted only when the exact charge model confirms the full
> charge budget. For the two-stratagem chain, both charges are reserved before Accession;
> Accession and Perpetuance are then dispatched from that reservation without treating the
> shared recast timer as a single-charge cooldown. The scheduler lane is atomic through the
> maintenance spell cast, so another scheduled spell cannot consume either prepared effect.

**Target:** UnifiedCombat Windower addon, scheduler, profile-v2 contract, and WinForms UI

**Initial eligibility:** Main-job Scholar only

**Primary implementation goal:** Reliable party support and Scholar-aware group defense through Phase 2

**Later goals:** Reactive magic bursts, Immanence skillchains, and runtime-armed encounter abilities

---

## Current implementation status (2026-08-02)

The following reviewable slices now exist:

- the focused static-resource and repository audit in `docs/sch_phase0_repository_audit.md`;
- exact Phase 1 configuration validation in `uc_sch_config.lua`;
- profile-v2, active-config, WinForms writer, and offline SCH-tab round trips;
- the shared state reducer, sequence invariants, lifecycle resets, lane state, ownership reconciliation, and deterministic replay tests in `uc_sch_runtime.lua`;
- deterministic roster generations plus engine, domain, job, player, party, and anchor revalidation before sequence advancement;
- an observe-only `maintenance_sch` adapter that emits no scheduler proposals and cannot dispatch actions;
- a selective Scholar lane filter that is dormant until a sequence exists, holds routine proposals/movement/targeting only for prepared support state, and aborts before established hard emergencies or critical cures preempt it;
- local spell/ability identity observation that invalidates prepared state after a manual or unrecognized local spell without claiming unproven action-result semantics;
- an exact evidence-keyed raw action-result classifier that validates every target/action, handles full and partial success, failures, interruption, missing and unexpected recipients, and aborts immediately without ownership when any result remains unclassified; the production catalog remains explicitly unvalidated and empty;
- an evidence-keyed charge-model boundary parameterized by exact level/job-point context, recast encoding, maximum charges, recharge interval, units, boundary tolerance, and Tabula Rasa policy; missing recast remains missing, contradictions invalidate confidence, and the production catalog remains explicitly unvalidated;
- status plus a bounded one-shot field trace that records changing buff/recast/party samples, raw local action targets, action messages, and a terminal reason;
- a durable automated capture session that continuously persists changing samples during long waits, associates completed raw traces with script-owned marks, and supports unattended solo and party-range Windower runners;
- comparison diagnostics that identify direct cures and single-target status removal as unchanged `defensive_internal`/`defensive_healbot` proposals;
- expanded `//uc sch status` output covering context, Arts, charge age, sequence/pending/lane state, support subsystems, ownership, retry, last result, and trace state;
- transition-only stable runtime logs for charge changes, sequence lifecycle, action failure, recipient reconciliation, and lane acquire/release without repeating unchanged idle observations;
- a pure deterministic Accession-area planner that evaluates every eligible party anchor, excludes anchors covering unowned existing Regen, fails closed on missing or stale coordinates, and applies maximum-coverage/stable-party-order/target-ID selection once explicit mechanics are confirmed;
- exact evidence-keyed Accession mechanics with an explicit production-unknown catalog and confirmed source requirements;
- a single Scholar party-snapshot boundary that timestamps complete numeric X/Y coordinate observations and supplies the same immutable snapshot to environment validation, ownership reconciliation, planning, and field traces;
- observe-only Regen evaluation that distinguishes confirmed owned presence from unowned existing Regen and exposes the geometry blocker without assuming a radius, distance metric, or coordinate-freshness window;
- a complete observe-only Regen ready path that, with injected confirmed charge and geometry evidence, selects the exact anchor and recipient set, builds the strict Accession + Perpetuance + Regen plan, exposes it in status, and still emits zero scheduler proposals;
- deterministic observe-only Storm II assignment planning that validates exact party identity and buff evidence, treats matching but unowned Storm II presence as blocked rather than satisfied, exposes the exact target/recipient plan, preserves Arts-before-storm priority, and still emits zero scheduler proposals;
- deterministic Sublimation activation planning that requires exact buff state, the configured minimum HP threshold, recast ID 234 readiness, learned JA readiness, and confirmed safety evidence derived from the scheduler's existing critical-cure, Doom, and charm signals; current MP is not an activation condition;
- deterministic observe-only Light Arts planning that blocks contradictory/unknown Arts state, requires exact recast ID 228 and scheduler JA ownership/readiness, exposes the expected buff and evidence source, preserves downstream diagnostics without admitting downstream candidates, and emits zero scheduler proposals;
- an evidence-keyed Sublimation release-capacity boundary that rejects invented thresholds and keeps production release explicitly blocked until a documented minimum-useful missing-MP rule is validated;
- an isolated evidence-keyed duration model that records the exact spell/modifier model key, rejects mismatched or invented evidence, and leaves production ownership explicitly unknown with no claimed end time until field validation exists;
- deterministic per-recipient ownership status lines exposing exact spell, presence, duration confidence/end time, evidence reason, model key, source, and last observation;
- atomic successful-recipient recording that validates the complete unique numeric recipient set before committing any ownership, preventing malformed or duplicate target evidence from leaving partial state;
- all 147 Lua replay suites, Lua 5.1 parsing for 116 runtime files, the WinForms build, and WinForms writer tests passing for the implemented slice.

Live Arts, Sublimation, storm, and multi-stratagem dispatch remain disabled. The lane and abort integration is safety infrastructure only; the observe-only provider cannot create an active sequence or emit an executable Scholar proposal. Phase 0 field gates for charge decoding, production action-result rules, area geometry/freshness, and exact duration still apply.

### Field trace runbook

The operator-facing field workflow is the unattended script process in `docs/sch_automated_capture_runbook.md`. The per-action commands below remain useful for focused engineering diagnosis; they are not the required operator workflow for the complete matrix.

With SCH as the current main job, the UnifiedCombat engine running, and the maintenance domain enabled:

1. Run `//uc sch trace once` immediately before one manual SCH action under test.
2. Perform the action within 30 seconds.
3. Wait at least two seconds after its completion.
4. Run `//uc sch trace show` to display the bounded evidence record.
5. Confirm the trace sample reports `jp_present=true` and the expected `jp_spent` value. A capture with missing job-point context is insufficient for charge-decoder evidence.
6. For area-geometry evidence, confirm each living candidate with X/Y coordinates also reports a numeric `coordinate_observed_at`. A member without a coordinate timestamp is not countable coverage evidence.

The trace auto-disarms after settlement, after 30 seconds without a terminal action, or at its 64-event bound. It is diagnostic-only and does not authorize or dispatch an action. Repeat it for every row in the Phase 0 live-capture matrix before implementing a decoder or result classifier.

---

## 1. Summary

UnifiedCombat should automate Scholar as a stateful, sequence-oriented job subsystem. Scholar must not be implemented as another generic list of buffs or independent job abilities.

A stratagem changes the meaning of the next eligible spell. After UnifiedCombat activates a stratagem, it must own the intended follow-up, observe whether the stratagem was consumed, and reconcile or abort when another action intervenes. The central architectural rule is therefore:

> One Scholar runtime owns all stratagem state and every stratagem-consuming sequence.

The subsystem will expose three scheduler-facing adapters over one shared runtime:

| Provider ID | Scheduler domain | Responsibility |
| --- | --- | --- |
| `maintenance_sch` | Maintenance | Arts, Addendum, Sublimation, Regen, storms, and later Embrava |
| `defensive_sch` | Defensive | Later Rapture/Penury cures, Accession cures, and Accession status removal |
| `combat_sch` | Combat | Later reactive magic bursts, Helix, and Immanence skillchains |

The adapters decide what Scholar action is required. The existing scheduler remains responsible for ranking, revalidation, movement settling, action locks, dispatch, pending actions, and global arbitration.

The first implementation is deliberately narrower than the complete architecture. It will support main-job Scholar in a Light Arts support role, reuse existing direct cures and status removal, and implement strict support sequences. It will not create autonomous Immanence chains, automatically spend Tabula Rasa, support alliances, or reposition the Scholar for area coverage.

---

## 2. Motivation

UnifiedCombat already handles ordinary healing and status removal through `build_defensive_candidates()` and the `defensive_internal` provider. That provider evaluates party HP, missing HP, cure tier, critical thresholds, removable statuses, spell readiness, target range, and observed party buffs.

The missing responsibility is not another cure selector. It is ownership of operations such as:

```text
Light Arts
-> Accession
-> Perpetuance
-> Regen V
-> confirm the successful recipients
-> reconcile owned duration for each recipient
```

Treating those operations as unrelated maintenance actions creates unsafe races:

- A cure can consume Accession before Regen is cast.
- A manual spell can consume Perpetuance.
- A provider can begin a two-charge plan with only one usable charge.
- A routine nuke can take the action lane during an Immanence closing window.
- A timer can advance a sequence even though the preceding action failed or was interrupted.
- A party buff can be present without proving its exact identity, remaining duration, or owner.

A single runtime and explicit state machine make these races observable and testable.

---

## 3. Governing decisions

### 3.1 One runtime owns Scholar state

`uc_sch_runtime.lua` will be the only mutable owner of:

- current Arts and Addendum intent;
- the active Scholar sequence;
- prepared stratagem reservations;
- the shared stratagem charge estimate and its confidence;
- Scholar-owned buff observations and duration estimates;
- Sublimation state;
- later Helix, burst, and skillchain intent;
- retry/backoff state;
- runtime arming for encounter abilities;
- the Scholar action-lane reservation.

No generic defensive, maintenance, combat, or ability provider may independently activate a stratagem.

### 3.2 Providers propose; the scheduler executes

Scholar modules must not run an independent timer loop or directly send `/ma` or `/ja` commands. Each adapter emits at most one revalidatable proposal for its domain. The existing scheduler owns command execution and pending-action behavior.

### 3.3 Runtime state is not durable configuration

Profile v2 stores intent and policy only. It must never store:

- current Arts or Addendum buffs;
- available stratagem charges or recast observations;
- an active sequence or sequence phase;
- pending action tokens;
- owned buff end times;
- current recipients;
- target IDs or target generations;
- Helix expiration;
- skillchain or burst generations;
- Sublimation charge state;
- an Embrava or Tabula Rasa armed flag;
- retry times or action-lane state.

All such state is cleared or reconstructed from live evidence after reload, zone change, engine stop, or job change.

### 3.4 No fallback behavior

Scholar automation must fail closed when a required fact or prerequisite is unavailable. It must not silently replace the configured plan with a weaker or different plan.

Examples:

- A configured Accession + Perpetuance + Regen sequence waits when two charges cannot be proven available. It does not silently cast Accession-only or single-target Regen.
- Unknown area geometry blocks the area sequence. It does not assume the whole party is covered.
- An unknown storm identity does not satisfy an exact storm assignment.
- An interrupted or manually contaminated sequence enters reconciliation. It does not advance by elapsed time.
- An unsupported config value is rejected. It is not replaced with a default spell or mode.

Any future alternative plan must be represented as a separately configured, validated policy with its own proposal and acceptance tests. It must not be an error-path substitution.

### 3.5 Evidence advances sequences

Sequence transitions require observed evidence whenever Windower exposes it. Elapsed time may define a bounded confirmation deadline, but a timer alone does not prove success.

Accepted evidence includes:

- the local action packet for a job ability or spell;
- classified per-target action results;
- local buff gain or loss;
- party buff presence from `0x076`;
- ability recast consumption, once its Scholar semantics are field-validated;
- an existing scheduler pending-action completion or failure;
- a target-specific skillchain snapshot from `uc_skillchain_state.lua`.

Contradictory or incomplete evidence invalidates confidence and blocks dependent actions.

### 3.6 Emergency support may preempt damage and prepared Scholar work

Critical defensive work must remain able to abort a Scholar support, burst, or skillchain sequence. A preemption is not transparent: the runtime assumes any prepared stratagem may have been consumed and reconciles before planning again.

Damage automation must never prevent life-saving support.

---

## 4. Verified repository baseline

This RFC relies on the following inspected behavior.

| Existing capability | Repository seam | Consequence for Scholar |
| --- | --- | --- |
| Scheduler runs every 0.20 seconds and advances ordinary maintenance at 1.00-second cadence | `unified_engine.lua` | Scholar can use 1 Hz while idle and every tick while a sequence or deadline is active. |
| Direct cure and status-removal selection already exists | `build_defensive_candidates()` in `unified_scheduler.lua`, exposed through `uc_provider_defensive.lua` | Phase 1 reuses existing single-target defense instead of creating another healing engine. |
| Scheduler has proposal ranking, action state, pending records, movement locks, rejection history, and dispatch helpers | `unified_scheduler.lua` and `uc_scheduler_*` modules | Scholar proposals integrate with existing execution ownership. |
| The core observes property-bearing spell/WS actions and maintains target-specific skillchain state | `unified_combat_core.lua`, `uc_skillchain_state.lua` | Later Scholar burst and Immanence logic consume the existing skillchain source of truth. |
| Skillchain snapshots include generation, earliest close, latest safe time, result, and magic-burst expiration | `uc_skillchain_state.lua` | Burst and closer proposals can carry generation and deadlines and revalidate them. |
| Party buff packet parsing records buff IDs for five remote party entries | `uc_party_buff_tracker.lua` | Combined with the local player buff list, initial Scholar coverage is the six-member party only. |
| Bard action observation classifies all raw `0x028` targets and successful recipients | `uc_brd_maintenance.lua` | Scholar can reuse the established raw multi-target observation pattern without inferring area recipients. |
| Bard and GEO already have provider-specific lane handling | `unified_scheduler.lua`, `uc_brd_maintenance.lua`, `uc_geo_maintenance.lua` | Initial Scholar integration should add a narrow Scholar lane filter instead of refactoring every lane owner. |
| A top-level job section already exists for Summoner and is validated across profile layers | `uc_smn_config.lua`, `uc_profile_contract.lua`, `uc_config_normalizer.lua`, `uc_active_config.lua`, `uc_profile_v2.lua`, structured writer code | `config.sch` should follow the established top-level job-section pattern. |

The baseline does **not** yet prove:

- how Windower ability recasts encode Scholar charge count at every main-job level;
- which evidence most reliably confirms Arts, Addendum, and stratagem activation;
- the complete success/failure message set for each proposed Scholar action;
- whether every required party member has fresh coordinates at planning time;
- exact duration after Perpetuance and equipment modifiers;
- whether current generic pending records contain every correlation field Scholar needs.

Those facts are implementation gates, not values to guess.

---

## 5. Scope

### 5.1 Phase 1 scope

The first useful Scholar implementation includes:

1. Main-job Scholar eligibility only.
2. One durable `support` mode.
3. Light Arts maintenance.
4. Addendum: White only for a validated upcoming requirement.
5. Existing `defensive_internal` direct cures and single-target status removal.
6. Sublimation activation and release policy.
7. Strict Accession + Perpetuance + configured Regen maintenance.
8. Exact single-target Storm II assignments.
9. Per-recipient successful-action evidence and conservative owned timers.
10. Sequence cancellation, reconciliation, retry, reset, status, and one-shot trace diagnostics.

### 5.2 Deferred scope

The following are part of the target architecture but not Phase 1:

- support-job Scholar;
- automatic repositioning for area coverage;
- alliance support;
- Accession storms;
- Rapture and Penury;
- Accession cures and area status removal;
- reactive magic bursting;
- Helix ownership;
- autonomous Immanence skillchains;
- cross-client Scholar skillchain reservations;
- automatic mode selection;
- Embrava execution;
- any automatic Tabula Rasa use;
- encounter-specific policy.

Deferred modes and configuration keys must either be omitted from the initial writer or rejected as unsupported when Scholar is enabled. They must not be accepted and ignored.

### 5.3 Explicit non-goals

- Scholar does not own equipment. UnifiedCombat continues to issue normal commands and GearSwap owns gear changes.
- Scholar does not replace `uc_skillchain_state.lua` with another skillchain model.
- Scholar does not replace the existing direct-healing engine.
- Scholar does not infer durable profile changes from manual actions.
- Scholar does not move initialization or packet hooks casually.
- Scholar does not broaden the party contract beyond `p0` through `p5`.

---

## 6. Proposed module boundaries

### 6.1 Required Phase 1 modules

| Module | Responsibility |
| --- | --- |
| `uc_sch_config.lua` | Exact Scholar schema, resource validation, eligibility, and cross-field validation. |
| `uc_sch_runtime.lua` | Shared mutable state, sequence reducer, observations, invalidation, lane status, and diagnostics snapshot. |
| `uc_sch_maintenance.lua` | Side-effect-free selection of the next maintenance action from config, context, and runtime snapshot. |
| `uc_provider_sch_maintenance.lua` | Scheduler adapter that converts the maintenance decision to provider ID `maintenance_sch`. |

The adapter boundary may be folded into the existing provider registry if that matches nearby code more closely, but the runtime must remain independently testable and must remain the only mutable Scholar state owner.

### 6.2 Later modules

| Module | Responsibility |
| --- | --- |
| `uc_provider_sch_defensive.lua` | Scholar-specific group defensive proposals; it delegates all stratagem transitions to the shared runtime. |
| `uc_provider_sch_combat.lua` | Burst and Immanence proposals using the shared runtime and existing skillchain snapshot. |

### 6.3 Required integration points

Implementation is expected to touch these existing surfaces incrementally:

- scheduler provider registration and collection;
- scheduler dispatch for the new provider ID;
- raw action and action-message observation;
- incoming chunk handling for party buffs if an additional observation is required;
- zone, job, death, engine-stop, unload, and reload cleanup;
- profile normalizer, validator, active config, v2 export/diff, and WinForms writer;
- command routing for `//uc sch status` and `//uc sch trace once`;
- replay harness registration.

No phase should combine these changes with an unrelated scheduler refactor.

---

## 7. Runtime model

The conceptual state is:

```lua
state = {
    eligibility = 'ineligible',
    mode = 'support',

    active_sequence = nil,
    pending = nil,
    lane = {
        reserved = false,
        class = 'none',
        reason = '',
    },

    arts = {
        observed = 'unknown',
        desired = 'light',
        commit_until = 0,
    },

    stratagem = {
        estimated_available = 0,
        observed_recast = 0,
        observed_at = 0,
        confidence = 'unknown',
        last_used_at = 0,
    },

    owned_buffs = {
        -- target_id -> exact family -> ownership record
    },

    sublimation = {
        observed = 'unknown',
        activated_at = 0,
    },

    helix_by_target = {},
    skillchain_intent = nil,
    burst_intent = nil,

    next_retry_at = 0,
    last_transition = 'init',
    last_blocker = '',
}
```

This shape is illustrative, not a requirement to expose globals or serialize the table.

### 7.1 Runtime invariants

The reducer must enforce:

1. At most one active Scholar sequence exists.
2. At most one Scholar action is pending.
3. A pending action belongs to the active sequence generation.
4. Only the runtime can reserve or release the Scholar lane.
5. Every stratagem proposal belongs to an active validated sequence.
6. Every prepared stratagem names its intended consuming spell.
7. A target ID, party roster generation, or skillchain generation change invalidates dependent work.
8. Unknown charge confidence cannot authorize a multi-stratagem sequence.
9. A successful cast records only classified successful recipients.
10. Buff presence without owned cast correlation never creates exact ownership or an exact end time.
11. Sequence completion requires its declared postconditions.
12. A terminal failure releases the lane and enters bounded backoff.

Invariant violations must surface a diagnostic blocker and cancel the sequence. They must not be repaired by guessing missing values.

### 7.2 Ownership record

Each confirmed Scholar-owned buff should resemble:

```lua
owned_buff = {
    target_id = 123456,
    target_name = 'Nyoourke',
    family = 'regen',
    exact_spell = 'Regen V',
    source_sequence_id = 'sch-regen-1842',
    cast_at = 9282.10,
    estimated_expires_at = 0,
    duration_confidence = 'unknown',
    duration_reason = 'phase0_duration_unvalidated',
    duration_source = '',
    duration_model_key = 'regen|Regen V|Accession,Perpetuance',
    applied_modifiers = { 'Accession', 'Perpetuance' },
    presence = 'present',
    last_observed_at = 9282.30,
}
```

An end time may be calculated only from a documented duration model and the exact sequence modifiers known to have succeeded. If equipment makes the duration unknowable, the runtime records unknown duration and uses presence-based reconciliation rather than inventing precision.

---

## 8. Sequence contract

Every multi-action Scholar operation is a validated plan, not an arbitrary list of commands.

```lua
sequence = {
    id = 'sch-regen-1842',
    generation = 12,
    purpose = 'party_regen',
    domain = 'maintenance',

    required_art = 'light',
    required_addendum = nil,
    stratagems = { 'Accession', 'Perpetuance' },
    spell = 'Regen V',

    anchor_id = 123456,
    anchor_name = 'Nyoourke',
    expected_recipients = { 123456, 234567, 345678, 456789 },
    party_generation = 14,

    created_at = 9280.00,
    deadline = 9295.00,
    phase = 'ensure_art',
    emergency_preemption = true,
}
```

### 8.1 Common phases

The Phase 1 group Regen sequence is:

```text
validate_plan
-> ensure_art
-> wait_for_art
-> use_accession
-> wait_for_accession
-> use_perpetuance
-> wait_for_perpetuance
-> cast_spell
-> wait_for_spell_result
-> reconcile_recipients
-> complete
```

Each `wait_for_*` phase has:

- expected evidence;
- a bounded deadline;
- an explicit success transition;
- an explicit contradiction transition;
- an explicit timeout result;
- no timer-only success transition.

### 8.2 Revalidation before every proposal

Before emitting the next step, the runtime or adapter must verify:

- engine and required domain remain enabled;
- player is still main-job Scholar;
- profile generation and relevant config are unchanged;
- sequence generation is current;
- party roster generation is current;
- target identity and eligibility are unchanged;
- required art/addendum state is compatible;
- charge confidence still satisfies all unspent steps;
- spell or ability remains learned, available, and legal;
- expected coverage still meets the configured minimum;
- sequence deadline has not expired;
- no contradictory manual action has occurred;
- existing scheduler action and pending locks permit a proposal.

### 8.3 Contamination by manual or unrelated actions

The runtime observes every local job ability and spell, including actions not dispatched by UnifiedCombat.

While a prepared stratagem is pending consumption:

- the intended spell advances the sequence when successful;
- an eligible unintended spell marks the sequence `contaminated`;
- an unrecognized local spell marks charge/buff confidence unknown;
- an unrelated job ability does not automatically consume a stratagem, but still passes through normal action locking;
- interruption keeps ownership unresolved until the observed buff/recast evidence proves whether the stratagem remains;
- death, zoning, job change, stop, or reload cancels and resets the sequence.

After contamination, the runtime clears all unproven reservations, releases the lane, and enters reconciliation. It does not resume at the next phase.

### 8.4 Failure results

At minimum, sequences distinguish:

- `prerequisite_unavailable`;
- `charge_confidence_unknown`;
- `insufficient_confirmed_charges`;
- `party_generation_changed`;
- `target_changed`;
- `coverage_unknown`;
- `coverage_below_minimum`;
- `action_rejected`;
- `action_interrupted`;
- `confirmation_timeout`;
- `manual_action_contamination`;
- `critical_defensive_preemption`;
- `target_unavailable`;
- `engine_stopped`;
- `zone_changed`;
- `job_changed`;
- `configuration_changed`;
- `invariant_violation`.

Each result has a bounded retry policy or is terminal until external state changes. Retries repeat plan validation from the beginning; they do not jump back into a partially prepared sequence.

---

## 9. Selective action-lane ownership

Scholar needs a selectively exclusive lane, not Bard's fully exclusive song lane.

### 9.1 Lane classes

| Lane class | Scholar state | Routine combat/maintenance | Critical cure | Doom | Charm sleeper | High-priority status removal | Movement/target changes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `none` | No active prepared sequence | Allow normal arbitration | Allow | Allow | Allow | Allow | Allow |
| `planning` | Ensuring Arts/Addendum; no stratagem prepared | Allow normal arbitration | Allow | Allow | Allow | Allow | Allow under normal scheduler rules |
| `prepared_support` | Stratagem active; intended support spell not dispatched | Block | Allow and abort Scholar sequence | Allow and abort | Allow and abort | Policy-gated and abort | Block unrelated movement and target changes |
| `timed_combat` | Later burst/Immanence timing reservation | Block | Allow and abort | Allow and abort | Allow and abort | Policy-gated and abort | Block unrelated movement and target changes |
| `dispatched` | Scholar spell/JA sent | Existing action/pending locks decide | Existing hard-emergency behavior only | Existing behavior | Existing behavior | Existing behavior | Existing cast movement lock |

Phase 1 may initially permit only the already established hard emergencies plus critical cures to preempt `prepared_support`. The exact status-removal preemption threshold must use existing defensive urgency data; it must not introduce a second status priority table.

### 9.2 Initial scheduler integration

The first implementation should add a dedicated Scholar filter beside current provider-specific lane logic. It must not simultaneously generalize all BRD, GEO, camp-pull, and Scholar lane ownership.

The filter consumes a side-effect-free runtime snapshot:

```lua
{
    reserved = true,
    class = 'prepared_support',
    reason = 'accession_waiting_for_regen',
    sequence_id = 'sch-regen-1842',
    sequence_generation = 12,
}
```

Proposal admission must be deterministic and fixture-tested. A blocked proposal remains blocked even when the Scholar adapter emits no proposal during a confirmation wait.

### 9.3 Preemption result

When an allowed emergency wins arbitration, the runtime records and reports the abort before the emergency dispatch proceeds:

```text
SCH_SEQUENCE_ABORT purpose=party_regen reason=critical_defensive_preemption
```

The runtime then treats prepared stratagems as uncertain until observations reconcile them.

---

## 10. Arts and Addendum

### 10.1 Target architecture

The complete system may support:

| Mode | Durable intent |
| --- | --- |
| `support` | Prefer Light Arts; use Addendum: White only when a required action needs it. |
| `burst` | Prefer Dark Arts; use Addendum: Black only when required. |
| `support_burst` | Prefer Light Arts; enter Dark Arts only for a valuable burst window and remain committed for a minimum interval. |
| `skillchain` | Prefer Dark Arts while a configured Scholar-owned skillchain intent exists. |
| `manual` | Never change Arts automatically. |

Phase 1 implements only `support`. Unsupported modes are rejected when Scholar automation is enabled.

The observe-only support planner now treats `light` and `addendum_white` as confirmed compatible states. `none`, `dark`, and `addendum_black` may produce one exact `ensure_light_arts` plan only when recast ID 228 is present and zero and the scheduler confirms the Light Arts JA is owned and usable. Contradictory `unknown` Arts state blocks with `arts_state_unknown`; it never authorizes Light Arts or a downstream Regen, storm, or Sublimation candidate. Downstream subsystem plans remain visible for diagnosis while Arts is actionable or blocked, but Light Arts retains admission priority. The provider remains diagnostic-only and emits no scheduler proposal.

### 10.2 Hysteresis

Later hybrid modes require commitment windows to prevent Arts thrashing. The runtime owns `commit_until`; an individual provider opportunity may not flip Arts by itself.

Critical support actions should cast off-art when legal and timely rather than spending an additional JA cycle to optimize them. Phase 1 direct cures remain under existing defensive behavior and do not wait for Scholar Arts preparation.

### 10.3 Addendum rule

Addendum may be proposed only when:

- the exact next configured spell requires it;
- the sequence is otherwise valid;
- the required art is confirmed;
- no critical action is waiting;
- the action can complete before the sequence deadline.

Phase 1 does not maintain Addendum merely because it may be useful later.

---

## 11. Stratagem charge model

All stratagems consume one shared charge pool. Independent `action_ready()` checks are insufficient for a plan requiring multiple stratagems.

### 11.1 Required provider output

The charge provider must expose:

```lua
{
    available = 2,
    maximum = 5,
    recast_present = true,
    observed_recast = 0,
    observed_at = 9280.25,
    confidence = 'confirmed',
    model_key = 'SCH|99|true|2100|231',
    decoder_source = 'field-capture:<validated-model-id>',
    reason = '',
    tabula_rasa_active = false,
}
```

Allowed confidence values are `confirmed` and `unknown` in Phase 1. The planner may not reinterpret `unknown` as zero or as enough.

### 11.2 Field-validation gate

Before live multi-stratagem execution is enabled, capture `windower.ffxi.get_ability_recasts()` and action evidence for:

- zero through maximum charges where practical;
- immediately before and after a stratagem;
- each main-job-level charge/recharge boundary used by supported profiles;
- zoning and job change;
- Tabula Rasa inactive and active;
- recast data temporarily unavailable;
- a manually used stratagem;
- an interrupted or rejected follow-up spell.

The resulting mapping, units, rounding behavior, and uncertainty rules must be documented in a focused repository note and pinned by fixtures. Until that gate passes, the Scholar provider may operate in observe/dry-run mode but must not dispatch a multi-stratagem sequence.

The implemented `uc_sch_charge_model.lua` supplies the strict decoder boundary without declaring production mechanics. A confirmed catalog is keyed by exact main-job level, job-point presence/value, and recast ID 231, and must explicitly declare `time_until_full` encoding, maximum charges, recharge interval, recast-unit scale, boundary tolerance, Tabula Rasa policy, and an evidence source. Missing recast is represented by `recast_present = false` and `observed_recast = nil`; a numeric zero sentinel is rejected. Values outside a confirmed model and unvalidated Tabula semantics return unknown confidence rather than a charge count. The production catalog currently reports `phase0_charge_mapping_unvalidated` and cannot authorize a sequence.

### 11.3 Reservation accounting

A validated sequence reserves its full remaining charge requirement at plan creation. The reservation is local planning state, not proof that charges exist.

- Two confirmed charges are required before Accession + Perpetuance begins.
- After Accession is confirmed, Perpetuance consumes the already reserved second charge; a nonzero shared recast timer does not force a recharge wait.
- The admitted Accession + Perpetuance maintenance transaction is non-preemptible through its exact spell cast, preventing scheduler contamination.
- Any recast contradiction invalidates the plan.
- Tabula Rasa does not imply permission to spend the ability or start an otherwise invalid sequence.

---

## 12. Support automation

### 12.1 Sublimation

Sublimation is an independent policy, not a generic buff-list entry.

```lua
sublimation = {
    enabled = true,
    release_when_mpp_at_most = 45,
    minimum_hpp_to_activate = 75,
    release_when_complete = false,
}
```

Activation requires:

- no observed Sublimation state;
- the configured minimum HP threshold satisfied;
- no critical party damage;
- no dangerous local pressure signal selected by the implementation audit;
- no active prepared Scholar sequence;
- the exact job ability learned and ready.

Release requires:

- a confirmed releasable Sublimation state;
- the configured MP condition or explicit `release_when_complete` condition;
- enough missing MP to receive a meaningful amount, using a documented rule;
- no critical action or prepared sequence conflict.

Unknown Sublimation state blocks activation and release until reconciled. Repeated release attempts without a state transition enter explicit backoff and diagnostics.

The planner produces an activation plan regardless of current MP only after a defensive proposal set refreshed on the same scheduler tick proves no established critical cure is pending, the existing Doom/charm signals prove no hard local emergency, recast ID 234 is exactly zero, and the scheduler confirms that the local player owns and can currently use the Sublimation JA. A fast trace tick without refreshed defensive evidence reports `scheduler_defensive_evidence_not_current`; an empty stale proposal set is never interpreted as safe. Activation remains lower priority than Light Arts. Release planning additionally passes current and maximum MP through `uc_sch_sublimation.lua`; the production mechanics require at least 332 missing MP before release.

### 12.2 Group Regen

Group Regen is the first multi-action Scholar feature.

The strict Phase 1 contract is:

```lua
regen = {
    enabled = true,
    spell = 'Regen V',
    recipients = { 'party' },
    stratagems = { 'Accession', 'Perpetuance' },
    minimum_coverage = 4,
    refresh_before_s = 25,
    unknown_existing_policy = 'wait_for_clear',
}
```

The planner:

1. Resolves the configured exact spell resource and buff family.
2. Builds the living, present, non-ignored six-member recipient set.
3. Determines which members lack confirmed Scholar-owned Regen or are inside a known refresh window.
4. Evaluates each eligible party member as an Accession anchor.
5. Uses fresh coordinates to calculate the expected area recipients around that anchor.
6. Requires `minimum_coverage` and fresh evidence for every counted member.
7. Rejects an anchor when its area would include a recipient whose existing Regen-family effect is unowned under `wait_for_clear`.
8. Requires confirmed Light Arts compatibility and two confirmed charges.
9. Creates and executes one strict sequence.
10. Classifies all action-packet targets and records only successful recipients.
11. Reconciles owned duration estimates against later buff presence.

The cast target is chosen by deterministic maximum coverage, then stable party order, then target ID. The Scholar is not assumed to be the best anchor.

Phase 1 does not reposition for coverage. When no eligible anchor meets the minimum, it reports `coverage_below_minimum` and waits for geometry or party state to change.

The implemented pure planner accepts radius, distance metric, and coordinate-age limits only as explicit confirmed mechanics keyed as `Accession|party` with a named source. Complete X/Y observations are timestamped at the Scholar party-snapshot boundary; incomplete coordinates remain untimestamped and cannot be counted. The production adapter currently passes mechanics confidence as `unknown`, so it reports `accession_geometry_unvalidated` and cannot select a live anchor. Synthetic confirmed fixtures prove that the observe-only provider selects the deterministic anchor and exact recipient set, constructs the Accession + Perpetuance + Regen plan, and emits zero proposals. No production radius, distance metric, or maximum coordinate age has been guessed.

#### Existing unknown Regen

Party buff presence can prove that a Regen-family effect exists but not its exact spell, caster, or remaining duration. With `unknown_existing_policy = 'wait_for_clear'`, an unowned existing Regen suppresses overwrite until it disappears. This is an explicit safety policy, not inferred ownership.

No other unknown-existing policy is supported in Phase 1.

### 12.3 Storm assignments

Storms are exact target assignments, not a single global buff name.

```lua
storms = {
    enabled = true,
    assignments = {
        {
            spell = 'Aurorastorm II',
            targets = { 'Redrogue', 'Terrasjr' },
        },
        {
            spell = 'Thunderstorm II',
            targets = { 'Nyoourke' },
        },
    },
    refresh_before_s = 30,
    unknown_existing_policy = 'wait_for_clear',
}
```

Phase 1 casts storms individually. Accession storm assignments are deferred.

The runtime tracks exact spell and recipient ownership. Generic storm-family presence does not prove the desired assignment. Duplicate assignments for one target are invalid even when the spells differ.

The observe-only planner now enforces that distinction. A desired Storm II is satisfied only when the current party buff observation agrees with an exact `owned_buffs[target_id].storm` record for the configured spell and status ID. Any observed Storm-family effect without that exact ownership is blocked by `unowned_storm_wait_for_clear`. When no Storm-family effect is present, the planner builds one deterministic single-target plan containing the exact spell, target, recipient set, party generation, refresh policy, and evidence-keyed duration model. Production duration remains explicitly unknown, so the refresh window cannot authorize a proactive recast yet. The provider exposes the plan diagnostically but emits no scheduler proposal.

### 12.4 Other enhancing magic

Aquaveil, Phalanx, Protect, Shell, Adloquium, Animus, and similar effects may later reuse the sequence contract. They are outside Phase 1 and must not be added to generic defensive buff maintenance when their configured behavior requires stratagems or group planning.

### 12.5 Embrava and Tabula Rasa

Embrava is deferred and will require a non-durable runtime arm:

```text
//uc sch arm embrava
//uc sch disarm embrava
```

The armed flag is cleared on reload, zone change, engine stop, job change, death, and successful use.

A durable profile may eventually permit Embrava automation, but UnifiedCombat must never automatically spend Tabula Rasa merely because Embrava is missing. Permission, runtime arm, validated encounter conditions, and a dedicated sequence are all separate prerequisites.

---

## 13. Scholar-aware defensive behavior

Direct cures and single-target status removal remain in `defensive_internal`. `defensive_sch` adds only strategic, stratagem-assisted behavior.

### 13.1 Rapture and Penury

Later Rapture policy must require that the target is expected to survive the additional JA delay, the cure value justifies a charge, and no more urgent cure is waiting. Penury is an MP-efficiency action and must never delay emergency healing.

Critical cures are cast immediately through existing defense.

### 13.2 Accession cures

Later group curing requires a real group condition, a valid coverage anchor, confirmed charge state, and enough time for JA preparation. One critically injured member always takes precedence over building an area-cure sequence.

### 13.3 Area status removal

Later Accession status removal keys a sequence by exact debuff, planned spell, party generation, anchor, and recipient set. If the debuff disappears or the set no longer satisfies policy while preparing, the sequence cancels.

The implementation must reuse existing debuff normalization and priority rather than define a conflicting Scholar table.

---

## 14. Reactive magic bursting

Reactive magic bursting is Phase 3 and precedes autonomous Immanence chains.

The combat adapter consumes the existing target-specific skillchain snapshot. A burst plan carries:

- skillchain generation;
- confirmed result property;
- target ID;
- magic-burst deadline;
- exact selected spell;
- learned/resource validation;
- MP and target-HP gates;
- required art/addendum;
- optional preparation steps;
- estimated dispatch completion time.

Every step revalidates target ID, skillchain generation, result property, and deadline.

### 14.1 Deadline-aware preparation

Preparation is selected only when its measured worst-case time fits before the guarded burst deadline:

```text
Long window:   required art -> Ebullience -> spell
Medium window: Ebullience -> spell
Narrow window: spell only
Too late:      no proposal
```

These are distinct validated plans selected before dispatch, not error-path fallbacks. Once a plan starts, missing prerequisites cancel it; they do not substitute a shorter plan mid-sequence.

Klimaform is considered only when the exact appropriate storm is already confirmed or when a separately validated pre-chain plan establishes it. The burst provider must not begin multi-action storm preparation after a skillchain result if doing so risks the deadline.

---

## 15. Immanence skillchains

Autonomous Immanence skillchains are Phase 4.

```text
Ensure Dark Arts
-> Immanence
-> opener spell
-> observe opener generation
-> wait for existing earliest-close timing
-> Immanence
-> closer spell
-> observe confirmed result
-> optionally create a separate burst plan
```

`uc_skillchain_state.lua` remains authoritative for resonance properties, generation, earliest close, latest safe time, confirmed result, and burst expiration. Scholar does not maintain a competing window approximation.

### 15.1 Cross-provider ownership

The current melee WS planner can observe the resonance created by an Immanence spell. Before Scholar-owned closers are enabled, UnifiedCombat requires a generalized target-and-generation reservation that can hold ordinary WS proposals.

The reservation includes:

- owner actor ID;
- target ID;
- resonance generation;
- planned closer identity;
- earliest and latest execution times;
- ownership expiration;
- whether a party closer is permitted.

Without that reservation, autonomous Scholar skillchains remain disabled.

### 15.2 Emergency abort

A critical cure or hard emergency may destroy a Scholar-owned skillchain plan. The runtime emits an explicit abort and releases all target/generation reservations.

---

## 16. Profile-v2 contract

Scholar should be a top-level job section, following the existing Summoner precedent.

### 16.1 Target schema

The complete target shape is:

```lua
sch = {
    enabled = true,
    mode = 'support',

    arts = {
        default = 'light',
        minimum_commit_s = 12,
        emergency_off_art_casts = true,
    },

    sublimation = {
        enabled = true,
        release_when_mpp_at_most = 45,
        release_when_complete = false,
        minimum_hpp_to_activate = 75,
    },

    support = {
        regen = {
            enabled = true,
            spells = {
                'Regen V',
                'Protect V',
                'Shell V',
                'Adloquium',
                'Phalanx',
            },
            recipients = { 'party' },
            stratagems = { 'Accession', 'Perpetuance' },
            minimum_coverage = 4,
            refresh_before_s = 25,
            unknown_existing_policy = 'wait_for_clear',
        },

        storms = {
            enabled = true,
            assignments = {},
            refresh_before_s = 30,
            unknown_existing_policy = 'wait_for_clear',
        },

        embrava = {
            enabled = false,
            manual_arm_required = true,
        },
    },

    defensive = {
        accession_cure = {
            enabled = false,
            minimum_members = 3,
            member_hpp_at_most = 75,
            minimum_total_missing_hp = 2500,
        },

        accession_status_removal = {
            enabled = false,
            minimum_members = 2,
        },

        rapture = {
            enabled = false,
            minimum_missing_hp = 1800,
        },

        penury = {
            enabled = false,
            maximum_mpp = 45,
        },
    },

    offense = {
        magic_burst = {
            enabled = false,
            minimum_mpp = 35,
            minimum_target_hpp = 10,
            spells = {},
        },

        skillchain = {
            enabled = false,
            allow_party_close = false,
            plans = {},
        },
    },
}
```

Phase 1 should serialize only implemented keys or require every deferred feature's `enabled` value to be exactly `false`. The validator must reject enabled deferred features.

### 16.2 Validation

When `sch.enabled == true`, validation rejects:

- a non-SCH main job;
- an unsupported mode;
- an unknown or unlearnable exact spell name;
- an enabled Regen policy without the exact required stratagem list;
- a Regen spell not eligible for the declared stratagems;
- a `minimum_coverage` outside the supported party range;
- an unsupported unknown-existing policy;
- duplicate or unknown storm targets;
- duplicate storm assignments for one target;
- an unknown Storm II spell;
- threshold values outside documented ranges;
- contradictory activation and release thresholds;
- an enabled deferred feature;
- Embrava without `manual_arm_required = true`;
- runtime-owned keys in durable config;
- unknown Scholar keys.

Validation must occur consistently in normalization, active-config loading, profile contract diagnostics, v2 writing, and UI save. Enabled invalid Scholar config prevents activation; it is not partially accepted.

### 16.3 UI

The first Scholar UI should expose only Phase 1 behavior. It should not show controls that serialize ignored future options.

Required controls:

- Scholar enabled;
- support mode display;
- Arts intent display;
- Sublimation minimum charging HP, MP release threshold, and complete-charge release policy;
- exact Regen spell;
- minimum coverage and refresh window;
- exact Storm II assignments by character;
- read-only note that direct cures/status removal use existing defensive settings;
- read-only note that Tabula Rasa and Immanence automation are unavailable in Phase 1.

---

## 17. Scheduler cadence and proposal contract

Routine Scholar maintenance participates at the existing 1 Hz maintenance cadence.

Scholar participates every 0.20-second scheduler tick while any of these are true:

- a sequence is active;
- a Scholar action is pending;
- a stratagem is prepared;
- a confirmation or follow-up has a deadline;
- later, a valid burst window is active;
- later, a skillchain sequence is active.

The runtime exposes `requires_fast_tick()` so cadence does not depend on scheduler inspection of private runtime fields.

Each Scholar proposal includes at least:

```lua
{
    provider = 'maintenance_sch',
    domain = 'maintenance',
    action_type = 'job_ability',
    action_name = 'Accession',
    target_id = 0,
    target_name = '<me>',
    sequence_id = 'sch-regen-1842',
    sequence_generation = 12,
    phase = 'use_accession',
    reason_code = 'sch_regen_prepare_accession',
    deadline = 9295.00,
    duplicate_suppression_key = 'sch:12:use_accession',
}
```

Proposal keys and rank relationships must be stable and fixture-tested. Exact numeric priority bands should be chosen only after auditing current rank bands. The required relative order is:

1. Existing hard emergencies.
2. Allowed critical defensive preemption.
3. Completion of an already prepared Scholar stratagem sequence.
4. Other urgent defensive work.
5. New routine Scholar maintenance.
6. Ordinary combat and maintenance according to current scheduler policy.

---

## 18. Observation and reconciliation

### 18.1 Action packets

Scholar action observation must inspect all raw action targets, not only the first target. For a pending area spell it records:

- actor ID and expected local ownership;
- category and exact action resource;
- pending token and sequence generation;
- each target ID;
- each target action message and parameter;
- classified success, failure, resist, no-effect, or unknown result;
- interruption state;
- successful-recipient set;
- unexpected-recipient set;
- observation timestamp.

Unknown message classification must fail the transaction closed and appear in one-shot trace output. It must not be treated as success.

The implemented `uc_sch_action_results.lua` boundary keys a catalog by exact action type and action name. Confirmed catalogs require a named evidence source and explicit message/parameter rules. It validates all raw target/action arrays before classification, rejects duplicate or coerced target IDs, reports missing and unexpected recipients, and withholds every successful recipient when any target remains unknown or mixed. The production catalog currently has `confidence = 'unknown'`, reason `phase0_action_results_unvalidated`, and no rules or source; observing such a result aborts the active transaction immediately and releases the lane.

### 18.2 Party buff presence

`0x076` and local player buffs are reconciliation evidence only:

- a confirmed owned recipient losing the buff invalidates ownership;
- a confirmed owned recipient retaining the buff supports presence but does not extend its end time;
- an unowned existing family remains unknown;
- missing or stale party state remains unknown, not absent;
- roster changes invalidate expected-recipient and geometry plans.

### 18.3 Duration

Phase 1 uses conservative locally owned duration estimates only after the exact spell and required stratagem outcomes are confirmed. The duration model must be isolated and fixture-tested.

If exact equipment-dependent duration cannot be observed reliably, refresh is gated by both the conservative estimate and current presence. The runtime never claims an authoritative remaining duration it cannot prove.

The implemented `uc_sch_duration.lua` boundary keys evidence by exact family, spell, and ordered applied modifiers. Confirmed evidence must provide that exact key, a positive finite duration, and a non-empty evidence source. Unknown evidence must provide a reason and is forbidden from carrying a duration, model key, or source. The production Phase 1 path currently records `phase0_duration_unvalidated`, `estimated_expires_at = 0`, and no source; therefore presence can be reconciled, but no proactive timer-based refresh is authorized yet.

### 18.4 Pending actions

Scholar may extend existing scheduler pending records with sequence token, generation, phase, and expected evidence. It must not create a second unrelated pending-action system that can disagree with the scheduler.

---

## 19. Lifecycle, cancellation, and recovery

The runtime resets or invalidates affected state on:

- addon unload/reload;
- engine stop;
- zone change;
- main-job or support-job change;
- player death or incapacitation;
- party membership or target identity change;
- profile generation change;
- manual cancellation command;
- action rejection, interruption, or timeout;
- contradictory buff or recast evidence;
- prepared stratagem consumed by another spell;
- loss of required Arts/Addendum state;
- target death;
- scheduler pending timeout.

Cleanup must release Scholar lane ownership and cross-provider reservations. It must not mutate durable configuration.

Recovery always returns to observation and complete plan validation. It never resumes from a guessed intermediate phase.

---

## 20. Diagnostics

Initial commands:

```text
//uc sch status
//uc sch trace once
//uc sch trace show
```

`//uc sch status` reports:

- eligibility and enabled state;
- active profile generation and mode;
- observed and desired Arts/Addendum;
- stratagem charge estimate, recast sample, confidence, and age;
- active sequence ID, purpose, generation, phase, and deadline;
- pending action and expected evidence;
- lane class and reason;
- Regen expected and confirmed recipients;
- per-recipient owned effect confidence and conservative deadline;
- storm assignments and first unsatisfied assignment;
- Sublimation observation and next eligible transition;
- retry time and first blocker.

`//uc sch trace once` arms one bounded transaction trace. It records proposal, dispatch, raw action targets, classified results, buff/recast observations, phase transitions, completion, or terminal failure, then disarms automatically.

Stable log events should include:

```text
SCH_SEQUENCE_START
SCH_SEQUENCE_TRANSITION
SCH_SEQUENCE_ABORT
SCH_SEQUENCE_COMPLETE
SCH_ACTION_REJECT
SCH_ACTION_TIMEOUT
SCH_CHARGE_OBSERVATION
SCH_RECIPIENT_RECONCILE
SCH_LANE_ACQUIRE
SCH_LANE_RELEASE
```

Routine idle blockers should be available in status without continuous chat spam.

---

## 21. Implementation plan

Each phase is a separately reviewable change set. Live dispatch remains disabled until that phase's evidence and replay gates pass.

### Phase 0: Repository and field evidence

Deliver:

- a focused Scholar repository audit;
- resource IDs and eligibility mapping for Phase 1 spells, abilities, and buffs;
- captured stratagem recast observations and a documented charge algorithm;
- classified action-message fixtures for Arts, Addendum, Sublimation, Accession, Perpetuance, Regen, and storms;
- raw multi-target Regen fixtures including partial success, failure, interruption, and unexpected recipients;
- party-coordinate freshness and area-radius decision;
- duration-model decision and documented unknown case;
- explicit scheduler priority and emergency-preemption mapping.

Gate: no live multi-stratagem dispatch before charge and action evidence are proven.

### Phase 1A: Config and pure runtime reducer

Deliver:

- `uc_sch_config.lua` exact Phase 1 schema and validation;
- `uc_sch_runtime.lua` state, invariants, reset, observations, and sequence reducer;
- profile-v2, active-config, writer, and UI round-trip support;
- status and one-shot trace snapshots;
- replay fixtures for every state transition and failure result;
- no live Scholar dispatch.

Gate: all invalid configs fail consistently and every reducer transition is deterministic.

### Phase 1B: Observe/dry-run provider

Deliver:

- `maintenance_sch` proposal selection without live execution;
- Arts, Sublimation, Regen, and storm plan diagnostics;
- fast-tick activation only during active/deadline state;
- lane decision diagnostics without blocking live proposals;
- comparison logs proving existing direct cures/status removal remain unchanged.

Gate: field traces select the expected anchor, recipients, sequence, and blockers without dispatch.

### Phase 1C: Arts and Sublimation live slice

Deliver:

- scheduler dispatch and observation for Light Arts and Sublimation only;
- pending correlation, interruption, reset, and retry behavior;
- no group Regen live dispatch yet;
- targeted field tests for manual actions and emergency interference.

Gate: no duplicate action, hidden substitution, stuck lane, or durable runtime state.

### Phase 1D: Strict group Regen live slice

Deliver:

- confirmed two-charge admission;
- deterministic anchor and coverage selection;
- Accession + Perpetuance + Regen sequence;
- selective lane and critical-defense abort;
- all-target success classification;
- per-recipient ownership and presence reconciliation;
- failure injection for every intermediate phase.

Gate: the sequence never advances without evidence and never silently changes plans.

### Phase 1E: Targeted storms and UI closure

Deliver:

- exact single-target storm assignments;
- duplicate-target validation;
- owned storm reconciliation;
- completed Phase 1 UI and profile tests;
- implementation/runbook documentation;
- field results for a full support session.

### Phase 2: Scholar-aware group defense

Add Rapture, Penury, Accession cures, Accession status removal, and finalized selective-preemption policy. Keep existing critical cure semantics unchanged.

Implemented 2026-08-20. The defensive planner shares the Phase 1 state machine and
charge reservation rather than introducing a second executor. It adds:

- Accession Cure I-IV after the configured member-count, HPP, total-missing-HP,
  geometry, charge, recast, learned-spell, and doubled-MP checks pass;
- Accession Erase and exact `-na` spells for two or more party members with the
  same removable status, with Addendum: White inserted when required;
- Rapture for a noncritical single-target cure meeting its missing-HP threshold;
- Penury for a noncritical single-target cure while player MPP is at or below its
  configured threshold, using the halved base MP requirement;
- priority below existing critical direct cures and prepared-sequence priority,
  so critical direct defense remains authoritative and can abort prepared work.

All four features remain explicit profile toggles. Phase 3 offense, Phase 4
skillchains, and Phase 5 encounter abilities remain rejected when enabled.

### Phase 3: Reactive magic bursts

Add target/generation burst snapshots, exact property-to-spell config, deadline-aware plan selection, optional Ebullience/Alacrity, and Helix ownership.

### Phase 4: Immanence skillchains

Add configured opener/closer plans, cross-provider target/generation reservations, WS holds, emergency abort, and optional party closer policy.

### Phase 5: Encounter abilities

Add runtime-armed Embrava, explicit Tabula Rasa permission and sequences, and separately designed encounter policies.

---

## 22. Required test contract

### 22.1 Configuration

- `config.sch` round-trips without runtime state.
- Missing `config.sch` leaves Scholar automation disabled without changing other job behavior.
- Enabled invalid Scholar config is rejected at every config boundary.
- Exact spell and ability names are resource-validated.
- Unknown keys are rejected.
- Deferred enabled features are rejected in Phase 1.
- Duplicate storm recipients are rejected.
- Runtime arm state never appears in profile output.
- Profile reload and diff remain stable.
- Loading a profile never starts the engine.

### 22.2 Runtime and sequences

- Only one Scholar sequence and one pending Scholar action can exist.
- Two confirmed charges are required before a two-stratagem plan starts.
- Unknown charges never authorize a plan.
- Each phase requires its declared evidence.
- Confirmation timeout never creates success or ownership.
- Manual eligible spells contaminate prepared sequences.
- Interrupted spells do not create recipients.
- A sequence restart revalidates from the beginning.
- Every terminal result releases the lane.
- Zone, stop, death, job change, and config change clear state.
- Runtime invariant failure is explicit and blocks action.

### 22.3 Regen and party evidence

- The planner considers every eligible anchor.
- Coverage selection is deterministic.
- Stale or missing coordinates block the area plan.
- Minimum coverage is enforced.
- No reposition command is emitted in Phase 1.
- All raw action targets are classified.
- Only successful per-target results create ownership.
- Partial success records only successful recipients.
- Malformed or duplicate successful-recipient sets abort without committing any partial ownership.
- Unexpected recipients are recorded without being treated as planned coverage.
- Missing/stale `0x076` state remains unknown.
- Existing unowned Regen follows `wait_for_clear`.
- Buff loss clears owned presence.
- Presence alone does not extend an estimated end time.
- Alliance members are not planned or claimed.

### 22.4 Scheduler and preemption

- `maintenance_sch` participates at 1 Hz while idle.
- Active sequences participate every scheduler tick.
- A prepared stratagem holds routine combat and maintenance even between proposals.
- Critical cure and hard-emergency paths can abort the lane.
- Abort occurs before the preempting action is dispatched.
- Preemption invalidates prepared stratagem confidence.
- Existing pending/action/movement locks remain authoritative.
- Existing BRD, GEO, camp-pull, and reaction behavior remains unchanged.
- Existing direct cure and status-removal selection remains unchanged.
- No proposal or command is dispatched twice.

### 22.5 Diagnostics

- Status reports the first blocker without mutating runtime.
- One-shot trace disarms after one transaction.
- Unknown message IDs and charge mappings are visible.
- Sequence ID and generation appear in proposal, pending, and completion records.
- Logs distinguish rejection, interruption, contamination, timeout, and preemption.

### 22.6 Later-phase timing

- Burst proposals require the current target and skillchain generation.
- Preparation fits inside the guarded burst deadline before it begins.
- A changed generation invalidates every remaining step.
- Immanence closer plans use existing earliest/latest timing.
- Scholar-owned skillchain reservations hold conflicting WS proposals.
- Critical defense releases skillchain reservations and reports an abort.

---

## 23. Acceptance criteria

Phase 1 is complete only when all of the following are true:

1. One shared runtime owns every Scholar stratagem and sequence.
2. Scholar support config is exact, validated, durable, and free of runtime state.
3. Main-job Scholar can maintain Light Arts and Sublimation under the declared policy.
4. Existing direct cures and status removal continue unchanged.
5. Accession + Perpetuance + Regen begins only with confirmed prerequisites and charge budget.
6. Each sequence phase advances from evidence, not sleep timing.
7. Area coverage is calculated around the selected target and never assumed.
8. Only classified successful action recipients gain Scholar ownership.
9. Unknown existing buffs remain unknown and follow the configured safety policy.
10. Manual actions, interruption, emergencies, and lifecycle changes cancel or reconcile safely.
11. A selective lane protects prepared stratagems while allowing declared emergencies.
12. No error path silently substitutes a different spell or sequence.
13. Idle Scholar work uses maintenance cadence; active sequences use scheduler cadence.
14. Status and one-shot trace explain the current state and first blocker.
15. Lua 5.1 parsing, focused replay tests, aggregate replay tests, config tests, and field evidence all pass.

The full target architecture is accepted when later phases additionally consume the existing skillchain runtime for reactive bursts and Immanence, coordinate target/generation ownership across providers, and keep Tabula Rasa behind explicit non-durable authorization.

---

## 24. Risks and required follow-up decisions

| Risk | Required treatment |
| --- | --- |
| Stratagem recast encoding is misunderstood | Block live multi-stratagem execution until Phase 0 field evidence and fixtures prove the mapping. |
| Area recipient geometry is stale | Require fresh coordinates for counted recipients; otherwise report `coverage_unknown`. |
| Equipment changes duration | Record conservative or unknown duration; never claim authoritative remaining time without evidence. |
| Manual spell consumes a prepared stratagem | Observe every local spell and contaminate/reconcile the sequence. |
| Emergency preemption consumes a stratagem | Abort first, then treat remaining stratagem state as uncertain. |
| Generic defense and Scholar group defense disagree | Keep direct defense authoritative; add Scholar group actions only in Phase 2 with explicit thresholds. |
| Existing WS planner races an Immanence closer | Keep Phase 4 disabled until target/generation reservation exists. |
| Another Scholar or external caster owns a buff | Treat presence as unowned; do not infer exact identity or remaining duration. |
| Scheduler special cases grow | Add only the narrow Phase 1 Scholar filter; consider a generalized lane contract in a separate RFC after behavior is proven. |

Two mechanics must be resolved by Phase 0 evidence rather than by design guesswork:

1. The authoritative conversion from Windower Scholar recast data to confirmed available charges.
2. The exact Accession radius and coordinate freshness contract used for deterministic coverage.

Neither uncertainty prevents config, reducer, observe-only, or fixture work. Both prevent live group-sequence dispatch.

---

## 25. Final architectural rule

The implementation must preserve this rule across every phase:

> Generic providers may request Scholar outcomes, but only the shared Scholar runtime may authorize and advance a stratagem-consuming sequence.

That rule is the boundary that makes support maintenance, group defense, reactive bursting, and Immanence automation coexist without consuming one another's prepared actions.
