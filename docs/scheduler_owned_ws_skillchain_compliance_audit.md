# Scheduler-owned WS skillchain compliance audit

Date: 2026-07-20
Reference: `docs/RefDocs/FFXI_Skillchain_Rules_Specification_2026-07-20.md` revision 1.0
Scope: scheduler-owned Weapon Skill selection and dispatch, plus the shared skillchain state that feeds it. The original read-only audit is retained below; this document now also records the post-implementation compliance re-audit.

Approved implementation contract: `docs/scheduler_owned_ws_skillchain_implementation_plan.md`

## Executive conclusion

The scheduler-owned WS path is **implementation-compliant, replay-verified, and field-verified**.

The former global `core.ws_timer` eligibility path is removed. `uc_skillchain_state.lua` now owns target-scoped, generation-versioned resonance and separate magic-burst state using `os.clock`. Incoming successful action results establish earliest, preferred, raw-expiry, and latest-safe times. Misses, interruptions, and propertyless WS preserve the prior state.

Scheduler proposals now carry a structured continuation plan. The scheduler and the core intent owner both revalidate the target, resonance generation, deadline, ordered effective properties, learned WS, TP, engaged/status state, range, weapon/equipment signature, Aftermath, Diamond Aspis context, reaction hold, and intent identity before the one WS send. Telemetry labels those checks as `rank_commit` and `dispatch_commit`. A successful send reserves that resonance generation until an action result replaces it, preventing repeated `/ws` sends while a non-dispatchable band-131 proposal continues holding routine work out of the result gap. Failed validation is explicit and never falls back to the configured primary WS.

Replay coverage passes for ordinary timing through the buffered preferred dispatch boundary, action-specific delays, propertyless and non-player property-action classification, server authority, directional priority, all Level 2 loops/promotions, terminal Double Light/Double Darkness, Radiance/Umbra thresholds, Chainbound, Diamond Aspis, more than five nonterminal actions, lifecycle cleanup, pending-lane reservation, priority, and commit-time invalidation. Full results are in `docs/TestResults/scheduler_owned_ws_skillchain_replay_results_2026-07-20.md`.

Initial field logs proved Nyoourke timing and both multi-actor replacement variants. They also exposed and drove correction of non-Aeonic AM3 Ultimate prediction and repeated sends for one pending resonance generation. After addon reload, deterministic audits passed for Nyoourke (35 dispatches) and Ponponponponpon (13 dispatches): every dispatch was within its preferred/latest-safe window, no target/generation dispatched twice, every send established a pending-result reservation, and the declared non-Aeonic Nyoourke session produced zero Ultimate predictions. Three nonblocking environment/evidence limits remain explicit:

- Windower exposes no project-used pre-dispatch line-of-sight query. The implementation enforces target validity and 5.5-yalm range; server/game rejection remains authoritative for obstruction.
- AoE processing retains the action parser's first-target/first-subaction selected-target assumption. The target-scoped seam is covered, but live packet ordering must be confirmed.
- Exact qualifying Weapon Bash Chainbound lifetime and remote party-member Aeonic equipment/Aftermath cannot be derived from available local APIs. Wild Flourish and Konzen-ittai have explicit source lifetimes; an unmapped qualifying Weapon Bash fails closed with `SC_CHAINBOUND_SOURCE_UNSUPPORTED` instead of receiving a fallback lifetime. Server add-effects remain authoritative in every case.

## Post-implementation disposition

| Work package | Status | Evidence |
| --- | --- | --- |
| `WS-SC-0` | Done | Pure state owner, fixtures, approved monotonic clock, aggregate/runtime registration. |
| `WS-SC-1` | Done | Target-scoped state/timing, success-only replacement, preservation rules, lifecycle reset, no global timer dependency. |
| `WS-SC-2` | Done | Structured plans, generation/property transport, two-stage commit validation, stable cancellation codes, no fallback WS. |
| `WS-SC-3` | Done | Chainbound, local actor Aeonic effective properties, Diamond Aspis override, terminal/MB state, no step cap. |
| `WS-SC-4` runtime | Done | Continuation band/urgency, emergency precedence, proposal/commit/result telemetry. |
| `WS-SC-4` field | Done | Initial Cases A/B reviewed; post-reload Nyoourke and Ponponponponpon validator runs passed. Case C is replay-only by accepted test disposition; Case D is not applicable to the current setup. |

## Inspected paths

- `unified_combat_core.lua`
  - packet-driven resonance state
  - transition/property resolution
  - WS candidate enumeration and selection
  - party hold and WS-intent arbitration
- `unified_scheduler.lua`
  - scheduler WS proposal collection, ranking, and dispatch
- `uc_scheduler_dispatch_plan.lua`
  - commit-time proposal validation
- `uc_scheduler_action_state.lua` and `uc_scheduler_locks.lua`
  - shared action/lock suppression
- `uc_ws_memory.lua` and `uc_ws_gate.lua`
  - local WS availability and legacy direct-path gating
- `skills.lua`
  - ordered properties, action-specific delays, and Aeonic metadata
- `addons/libs/actions.lua`
  - action-result parsing semantics used by the core
- replay/self-test tree
  - coverage for scheduler-owned WS skillchain behavior

## Pre-implementation compliance matrix (historical baseline)

The following matrix records the code state that motivated this work. It is intentionally retained as the before-state and must not be read as the current implementation status.

| Specification area | Status | Evidence and assessment |
| --- | --- | --- |
| State maintained independently per target | Compliant | `core.resonating[target_id]` and `core.ws_candidates[target_id]` are target-keyed. |
| Timing anchored from received action result | Partial | `apply_properties` timestamps during incoming action processing, but `core.ws_timer` is set for both WS begin and finish events and is not conditioned on a successful landed property action. |
| Monotonic local timing | Noncompliant | `uc_now_s` uses LuaSocket `socket.gettime`, which is high-resolution wall-clock time rather than a guaranteed monotonic clock. |
| Ordinary ~3-second minimum | Partial | A three-second gate exists, but it is global rather than target/resonance-specific and has no explicit conservative dispatch buffer. |
| Action-specific earliest close | Noncompliant | `reson.delay` records `ability.delay`, but no WS selection or scheduler dispatch path reads it. |
| Contracting late window | Compliant for the operational model | `times = landed + delay + 8 - step` matches the specification's operational Ivaar model. |
| Conservative late guard | Noncompliant | There is no `latest_safe = expiry - guard`; a continuation remains selectable until raw expiry. |
| Directional transition table | Compliant | The Level 1/2/3 transitions in `sc_info` match the reference table used for WS selection. |
| Ordered multiple-property priority | Compliant for normal properties | `check_props` iterates opener properties first and closer properties second, returning the first valid pair. |
| Successful chain result becomes sole resonance | Compliant | A server skillchain add-effect replaces active properties with `{ skillchain }`. |
| Successful non-chain property action becomes new opener | Compliant | Recognized successful property-bearing actions call `apply_properties` with the action's ordered properties and reset `step` to 1. |
| Miss/interruption preserves resonance | Partial | Miss/failure messages do not replace resonance, but their WS begin/finish traffic can still reset the global three-second timer and suppress a valid existing continuation. |
| Propertyless WS preserves resonance | Compliant for current data path | Propertyless WS entries are absent from `skills.weapon_skills`, so they do not call `apply_properties`. This behavior is implicit and lacks regression coverage. |
| Same-target validation | Compliant at basic level | Selection is target-ID based and dispatch requires the current target ID to equal the proposal target ID. |
| Revalidate resonance immediately before dispatch | Noncompliant | Commit validation checks proposal deadlines and target validity only. It does not re-run property resolution, compare a resonance generation/version, or verify earliest/latest chain timing. |
| Revalidate actor/equipment/property eligibility | Noncompliant | Dispatch rechecks engaged status and TP, but not current weapon, WS availability, effective properties, aftermath state, incapacitating buffs, or Chain Affinity/Immanence-style requirements. |
| Revalidate range/LOS | Noncompliant for WS | The proposal declares a 5.5-yalm range policy, but the WS dispatch branch does not enforce distance or LOS before sending. |
| Cancellable pending closer intent | Noncompliant | The system polls until selection returns a WS. The IPC intent handshake arbitrates simultaneous commands, but it does not carry opener identity, earliest time, latest-safe time, or a resonance generation to cancel/replan. |
| Intervening action cancels/replans | Partial | A later scheduler tick rebuilds candidates from current state, but there is no atomic state check inside WS dispatch after selection. |
| Chainbound timing | Noncompliant | Chainbound stores a two-second `reson.delay`, but the selector ignores it and the global WS timer is not set by the Chainbound JA event. An immediate closer may be dispatched. |
| Chainbound property priority | Substantially compliant | The long Chainbound property arrays plus the `#old_props > 3` same-level break implement the special first-eligible-property behavior inherited from the Ivaar model. This has no targeted tests. |
| Aeonic effective properties | Noncompliant | `skills.lua` carries `aeonic` and `weapon` metadata, but unified-core `rebuild_ws_candidates` and action-state installation use only `skillchain.skillchain`. The legacy `aeonic_prop`/`aeonic_am` handling was not migrated. |
| Aeonic actor-specific eligibility | Noncompliant | The unified core does not associate Aeonic AM/equipment with the acting character when predicting or installing effective properties. |
| Diamond Aspis actor-specific expiry | Noncompliant | Resonance has one target-wide `times` value and no actor-specific expiry override. |
| Terminal Level 4 handling | Compliant | Radiance/Umbra are Level 4, and normal Light→Light/Darkness→Darkness is promoted to level 4 for closure when prediction context exists. |
| No speculative maximum chain length | Noncompliant | `closed = step > 5 or level == 4` imposes a fixed nonterminal chain cutoff contrary to the specification's unresolved/no-hard-cap requirement. |
| Target death/despawn/zone reset | Partial | Expiry and live-target checks prevent most use, but resonance is not explicitly cleared on death, despawn, zone change, or logout. Zone suspension only delays execution. |
| Selected-target-only AoE behavior | Unverified | `core.on_action` reads only the first packet target and first subaction. This is likely inherited packet ordering behavior, but no assertion proves that this is always the selected target or contains the authoritative add-effect. |
| Server add-effect is authoritative | Compliant | A recognized incoming skillchain add-effect supplies the installed result property; prediction is used primarily to infer terminal level for ordinary Double Light/Darkness. |
| Magic-burst window interaction | Noncompliant / not modeled | Scheduler-owned WS logic keeps no separate MB state. In particular, a terminal chain appears as `sc_step == 0`, allowing an ordinary property-bearing WS without preserving the final burst opportunity. |
| Required telemetry | Noncompliant | The runtime does not record opener identity, predicted vs. server result, landed-to-dispatch/landed-to-result deltas, earliest/latest windows, stage-specific expiry outcomes, or miss/overwrite distinctions. |
| Required regression scenarios | Noncompliant | No replay tests directly exercise unified-core resonance transitions, timing boundaries, Chainbound, Aeonic, Diamond Aspis, terminal chains, misses, propertyless WS, or intervening-action cancellation. |

## Findings that required cleanup (historical baseline)

### F1 — Global WS timer is not a compliant resonance clock (high)

`core.ws_timer` is one process-wide timestamp. Any recognized WS on the currently selected target sets it to `now + 3`, before success/conclusion filtering. The final selector uses it instead of the target-specific `reson.delay`.

Consequences:

- A WS begin packet starts a timer before the result lands; the finish packet starts it again.
- A miss, interruption, or failed WS can postpone a valid continuation even though the prior resonance should remain unchanged.
- A resonance established while a different target is selected can lack the required early gate after retargeting.
- Action-specific delays and Chainbound's two-second delay are stored but ignored.
- The scheduler cannot distinguish “not yet eligible” from generic `TIMER_LOCK`, nor schedule a preferred buffered execution time.

The three-second value itself is supported by the specification for ordinary WS timing. Its current global placement and event semantics are not.

### F2 — Commit-time validation does not validate the skillchain plan (high)

`p1_revalidate_plan_commit` validates expiry/commit timestamps and that a mob is still alive/valid. The WS dispatch branch additionally checks engaged status, TP, and current target identity. Neither path verifies:

- that the same opener/result is still resonating;
- that the action is still the first valid ordered-property continuation;
- that current time is after actor/action-specific earliest close and before latest-safe;
- that no intervening property-bearing action changed the resonance;
- that the actor still has the selected WS/equipment/buff eligibility;
- that distance/LOS satisfies the proposal's declared range policy.

The 0.12-second IPC intent handshake causes later polling in ordinary operation, which reduces some races, but it is not a resonance-version revalidation contract.

### F3 — Aeonic property handling was lost in the unified path (high)

The checked-in `skills.lua` identifies Aeonic WS entries and their gained Level 3 property. Legacy `melee_engine.lua` contains `aeonic_prop` and `aeonic_am`, applies effective properties to incoming actions, and exposes eligible Aeonic continuations.

`unified_combat_core.lua` does neither. It uses base `skillchain` arrays for both incoming state and candidate resolution. Therefore scheduler-owned combat cannot reliably plan Ultimate Skillchains or model actor-specific Aeonic eligibility even though the metadata exists.

The general aftermath keeper is not a substitute: it decides when to use a configured aftermath WS, but it does not alter effective skillchain properties or model AM1/AM2/AM3 Ultimate eligibility.

### F4 — Chainbound earliest timing is not enforced (high)

Message 529 creates Chainbound resonance with a two-second delay. Because selection never reads `reson.delay` and Chainbound does not set the WS-only global timer, a compatible WS may be selected immediately. This directly conflicts with the specification's source-specific Chainbound timing rule.

### F5 — Fixed `step > 5` closure encodes an unresolved rule as truth (medium-high)

The core closes a sequence when `step > 5`, even if the result is nonterminal and unexpired. The specification explicitly says not to reject solely because of a presumed action-count maximum. Only terminal-property rules, expiry, and actual server results should close the chain.

### F6 — Special actor/state rules are absent (medium-high)

- Diamond Aspis cannot be represented because expiry is target-wide.
- Aeonic eligibility is not actor-specific.
- Current weapon/equipment is not included in the selected intent.
- Incapacitating buffs are not explicitly revalidated at WS commit.

These omissions mean the scheduler cannot implement `can_close(actor, target, now)` as specified.

### F7 — Continuations have no deadline-aware scheduler priority (medium)

A valid chain continuation receives the same band-70 proposal as a normal TP-ready opener. Only `AM_READY` aftermath refresh receives band 108. Routine defensive work at band 100 and other higher bands can consume enough of a shortening chain window to lose it.

The reference calls for an earliest/latest pending intent and high-risk handling when the usable interval is narrow. The current proposal has only a generic 0.30-second lifetime measured from proposal creation, not the resonance's latest-safe deadline.

### F8 — Terminal chains and magic-burst preservation are not modeled (medium)

There is no separate magic-burst state. A terminal resonance is hidden by `get_resonating_step` returning 0, and that same `sc_step == 0` condition bypasses `core.ws_timer`. A newly TP-ready primary WS can therefore be issued during the final burst window. This may be acceptable under an explicit “always WS” policy, but it is not compliant with the reference planner/executor model and is not documented as a deliberate policy.

### F9 — State lifecycle cleanup is incomplete (medium)

The core does not expose or invoke a resonance reset on target death, despawn, zone change, logout, or engine stop. Expiry and a 15-second zone suspension usually prevent an actual stale close, but the required state transition is implicit rather than guaranteed.

### F10 — Packet target/subaction assumptions are unverified (medium)

`core.on_action` processes only the first target and first action returned by the action library. This may correctly correspond to the selected target/add-effect for all relevant WS packets, but the contract is not asserted and the AoE selected-target rule has no replay fixture.

### F11 — Candidate ranking is valid-pair aware but strategically under-specified (low-medium)

Each candidate correctly resolves its first valid ordered pair. Selection then chooses the highest resulting level, with later ability-list entries winning equal-level ties. It does not score desired terminal route, WS damage, reliability, actor assignment, remaining window, or whether an equal-level result is a strategically better loop. This is a planner-quality gap rather than a basic transition correctness bug.

### F12 — Compliance-critical telemetry and tests are absent (high for safe cleanup)

No targeted replay coverage was found for this runtime path. Without packet-order fixtures and timing telemetry, changes to F1–F5 would be difficult to validate safely.

Minimum new telemetry should include target ID, actor ID, action ID/name, action result timestamp, prior resonance generation, ordered properties, predicted result, server result, step, earliest close, predicted expiry, latest-safe, selection reason, dispatch time, and cancellation/rejection reason.

## Confirmed strengths to preserve

- Target-keyed resonance and candidate storage.
- Directional transition data matching the reference.
- Opener-first, closer-second normal property ordering.
- Server skillchain add-effect as the installed result.
- Operational one-second-per-step late-window contraction.
- Successful non-chain action replacing prior resonance.
- Miss/failure messages not replacing the stored properties.
- Terminal Level 4 recognition.
- Scheduler rechecks engine enablement, TP, engaged state, current target identity, and live target state before sending.
- Cross-client intent arbitration reduces duplicate simultaneous WS commands and does not itself mutate resonance.

## Implemented cleanup sequence

1. Added replay fixtures and a pure target-scoped state seam.
2. Replaced `core.ws_timer` eligibility with landed, earliest, preferred, expiry, latest-safe, action, actor, and generation fields.
3. Carried generation/timing into scheduler proposals and revalidated at rank commit and immediately before send.
4. Restored local actor Aeonic effective-property handling and Diamond Aspis actor-specific expiry.
5. Added Chainbound-specific delay, property priority, and known source lifetimes.
6. Removed the speculative `step > 5` closure.
7. Added separate terminal magic-burst state and smart-mode hold behavior.
8. Added explicit lifecycle cleanup.
9. Added timing/result telemetry and completed the `WS-SC-4` live field gate.
10. Closed final flow-audit gaps: successful propertyless WS preservation when `skills.lua` has no entry, property-bearing pet/job/monster action observation, source-specific Wild Flourish/Konzen-ittai expiry, fail-closed unmapped Chainbound handling, explicit incapacitation checks, stale-target pruning, pending-window lane reservation, and end-to-end preferred-buffer admission.

## Required regression coverage

- Ordinary opener plus compatible closer at too-early, preferred, latest-safe, and expired offsets.
- Target A and target B with independent overlapping resonance.
- Compatible WS miss preserving the prior opener without restarting earliest-close timing.
- Propertyless WS preserving resonance and MB state.
- Non-chain property WS replacing the opener.
- Multi-property first-valid-pair priority.
- Each Level 2 loop/promotion and Level 3 terminal transition.
- Chainbound Level 1 priority and two-second timing.
- Aeonic AM1/AM2/AM3 effective properties and terminal result.
- Diamond Aspis wearer versus nonwearer expiry.
- More than five nonterminal linked actions, accepting server result rather than local hard closure.
- Another actor changing resonance after proposal creation but before dispatch.
- Equipment/WS availability, TP, incapacitation, range, and target invalidation at commit.
- AoE WS selected-target-only state installation.
- Zone/death/despawn/logout state clearing.

## Verification limits

Static inspection and 95 aggregate replay suites pass, including the scheduler-owned skillchain state and integration suites. Live Nyoourke and multi-actor traces prove preferred/latest-safe timing and generation replacement before dispatch. The initial capture's two corrective findings are implemented, replay-verified, and post-reload field-verified as described in `docs/TestResults/scheduler_owned_ws_skillchain_field_results_2026-07-20.md`. Line-of-sight rejection, AoE selected-target packet ordering, exact Weapon Bash Chainbound expiry, and remote actor Aeonic opener inference remain nonblocking observational items.
