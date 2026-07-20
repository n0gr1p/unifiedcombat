# Scheduler-owned WS skillchain implementation plan

Date: 2026-07-20
Status: **COMPLETE — IMPLEMENTED / REPLAY VERIFIED / FIELD VERIFIED**
Workstream: `WS-SC`
Rules authority: `docs/RefDocs/FFXI_Skillchain_Rules_Specification_2026-07-20.md`
Source audit: `docs/scheduler_owned_ws_skillchain_compliance_audit.md`

Implementation evidence: `docs/TestResults/scheduler_owned_ws_skillchain_replay_results_2026-07-20.md`

Field procedure: `docs/TestResults/scheduler_owned_ws_skillchain_field_test_packet.md`

## Implementation checkpoint

`WS-SC-0` through `WS-SC-4` are complete. Deadline-aware priority, urgency, commit cancellation, generation-scoped pending-result reservation, and telemetry are active. Initial live Cases A and B proved window timing and both multi-actor replacement variants while exposing overly broad Aeonic prediction and repeated sends for one pending generation. Both findings were corrected, replay-verified, and then field-verified after addon reload. The accepted post-reload evidence is documented in `docs/TestResults/scheduler_owned_ws_skillchain_field_results_2026-07-20.md`.

The approved monotonic runtime clock is `os.clock`. It is sampled at the beginning of incoming action processing and used only for process-local skillchain comparisons. Existing cross-process intent coordination continues to use its existing LuaSocket time domain; the two clocks are never compared directly.

## Objective

Make scheduler-owned Weapon Skill selection and dispatch conform to the supplied skillchain rules specification while preserving current public settings, command names, scheduler ownership boundaries, and Lua 5.1 compatibility.

The first delivery target is the Nyoourke SAM case:

- Aftermath is already satisfied.
- Nyoourke has sufficient TP.
- A currently available WS can continue the target's active chain.
- The continuation is dispatched inside a conservative valid window unless a higher-priority emergency or a newly observed server action invalidates it.

## Non-goals

- No scheduler rewrite.
- No profile schema or UI change solely to implement correctness rules.
- No external dependency.
- No change to the FFXI transition table unless packet evidence contradicts the reference.
- No speculative universal maximum chain length.
- No attempt to calculate skillchain damage in the first timing/dispatch phases.
- No replacement of server add-effect authority with local prediction.
- No fallback dispatch of the configured primary WS when a planned continuation fails revalidation.

## Non-negotiable invariants

1. State is maintained independently per target ID.
2. Timing starts from the received successful action result, not command send or animation start.
3. An ordinary closer must not be dispatched as eligible before the configured ordinary minimum window.
4. A miss, interruption, invalid target, or propertyless WS does not replace resonance or restart its earliest-close time.
5. A successful property-bearing action that does not chain becomes the new opener.
6. A server skillchain add-effect is authoritative over prediction.
7. A successful chain result becomes the only active resonance property.
8. Terminal Level 4 results cannot be continued.
9. A planned continuation must be revalidated against the same resonance generation immediately before dispatch.
10. Failed revalidation cancels the plan with an explicit reason. It never silently sends another WS.
11. Once dispatched, the same resonance generation cannot dispatch again while its action result is pending; its non-dispatchable continuation proposal continues reserving the action lane from routine work.
12. Doom and critical Cure retain emergency preemption.
13. All changes remain Lua 5.1 compatible and preserve existing public wrapper signatures.

## Required runtime state contract

The skillchain owner must maintain this target-keyed state shape:

```lua
target_state = {
    target_id = 0,
    generation = 0,
    source_action_id = 0,
    source_action_name = '',
    source_actor_id = 0,
    source_resource = '',
    active_properties = {},
    landed_at = 0,
    earliest_close_at = 0,
    preferred_execute_at = 0,
    expires_at = 0,
    latest_safe_at = 0,
    action_count = 1,
    skillchain_stage = 0,
    result_level = 0,
    terminal = false,
    chainbound_level = 0,
    actor_expiry_overrides = {},
    magic_burst_expires_at = 0,
    last_confirmed_result = '',
}
```

Required semantics:

- `generation` increments on every successful property-bearing state replacement, including a successful chain result and a non-chain overwrite.
- `active_properties` preserves source order. After a successful chain it contains only the server-confirmed result.
- `earliest_close_at` uses the source action's delay metadata.
- `preferred_execute_at` is the normal scheduler admission time. Resonance can be technically valid at `earliest_close_at`, but the scheduler-owned path waits for the conservative preferred buffer unless the planner has explicitly moved the preferred time earlier for a high-risk window.
- `latest_safe_at` is earlier than raw expiry by the configured guard.
- `actor_expiry_overrides` is empty unless an actor-specific rule such as Diamond Aspis applies.
- Magic-burst timing is stored separately from resonance timing.

## Timing constants

Initial defaults are taken from the approved rules specification:

| Constant | Initial value | Treatment |
| --- | --- | --- |
| `ORDINARY_WS_MIN_DELAY_S` | `3.0` | Operational minimum for ordinary WS sources. |
| `ORDINARY_WS_DISPATCH_BUFFER_S` | `0.3` | Conservative preferred execution buffer. |
| `LATEST_WINDOW_GUARD_S` | `0.6` | Conservative guard before predicted expiry. |
| `CHAINBOUND_DELAY_S` | `2.0` | Operational Chainbound delay unless source metadata is more specific. |
| `MAGIC_BURST_DURATION_S` | `10.0` | Separate confirmed MB window. |

These constants belong with the skillchain state/planner, not in profiles. Correctness must not depend on UI configuration.

`WS-SC-0` must identify and prove one approved monotonic runtime clock before `WS-SC-1` begins. `socket.gettime` is the current high-resolution wall-clock source and does not by itself satisfy the monotonic-clock requirement. Do not add a second clock or silently switch clocks when the approved source is unavailable; fail fast under the project's runtime rules.

For an accepted source action:

```text
earliest_close_at    = landed_at + action_delay
preferred_execute_at = earliest_close_at + dispatch_buffer
expires_at           = landed_at + action_delay + 8 - step
latest_safe_at        = expires_at - latest_window_guard
```

If `preferred_execute_at > latest_safe_at`, mark the plan high risk. The executor may use `earliest_close_at + a small positive buffer`, but must not dispatch after `latest_safe_at` as a planned continuation.

## Event transition contract

| Incoming event | Required transition |
| --- | --- |
| Successful property action, no active eligible transition | Install ordered action properties as a new opener; increment generation. |
| Successful compatible action in window | Install server-confirmed chain result as sole property; increment action count, stage, and generation. |
| Successful property action too early/late/incompatible | Install ordered action properties as a new opener; increment generation. |
| Property-bearing miss | Preserve prior resonance and timing; record telemetry only. |
| Interrupted/failed action | Preserve prior resonance and timing; record telemetry only. |
| Propertyless WS | Preserve resonance and MB state. |
| Terminal result | Store terminal result and MB deadline; prohibit continuation planning. |
| Target death/despawn | Clear target resonance and MB state. |
| Zone/logout/unload/engine stop | Clear all resonance, pending continuation, and IPC coordination state. |

## Module boundary

Create one cohesive helper module, recommended as `uc_skillchain_state.lua`, with no direct command side effects.

Responsibilities:

- target-state ownership;
- directional property resolution;
- effective-property calculation;
- event-driven state transitions;
- earliest/latest timing calculation;
- terminal and actor-specific expiry checks;
- structured continuation planning;
- commit-time plan revalidation;
- reset and diagnostic snapshot helpers.

Keep command dispatch and scheduler ranking in `unified_scheduler.lua`. Keep compatibility wrappers in `unified_combat_core.lua` so existing callers remain stable.

The module should accept injected time, resource, equipment, and buff readers in tests. Runtime construction may bind Windower dependencies explicitly. Missing required runtime dependencies must fail fast rather than selecting an alternate behavior.

## Structured continuation plan contract

Add a structured scheduler-facing plan while preserving `select_smart_ws_for_scheduler(settings, target_id)` for compatibility:

```lua
ws_plan = {
    kind = 'skillchain_continuation',
    target_id = 0,
    resonance_generation = 0,
    source_action_id = 0,
    source_actor_id = 0,
    ws_id = 0,
    ws_name = '',
    effective_properties = {},
    predicted_result = '',
    predicted_level = 0,
    earliest_execute_at = 0,
    preferred_execute_at = 0,
    latest_safe_at = 0,
    high_risk = false,
    selection_reason = '',
}
```

Compatibility policy:

- The existing string/reason wrapper remains callable.
- Scheduler-owned combat consumes the structured plan.
- Legacy/direct callers are not silently redirected to a different selection policy during the first scheduler-owned implementation phases.
- Once the scheduler-owned path is verified, dead global-timer logic is removed rather than retained as a fallback.

## Commit-time revalidation contract

Immediately before `/ws` dispatch, all of the following must still be true:

- engine and WS settings are enabled;
- target ID is unchanged, alive, valid, and current;
- current resonance generation matches the proposal;
- resonance is nonterminal;
- current time is within `[earliest_execute_at, latest_safe_at]` and has reached the plan's conservative `preferred_execute_at` admission time;
- ordered effective properties still produce the planned result;
- selected WS remains learned/available for current equipment;
- actor still has sufficient TP;
- required weapon, aftermath, job ability, or pet context is unchanged;
- actor is engaged and not incapacitated or action-locked;
- target remains inside enforced WS range and any required LOS rule;
- no higher-priority emergency or reaction lock blocks dispatch.

Any failed condition cancels the continuation proposal. The next scheduler tick may create a new plan from the current state. It must not reuse a stale WS name or send the profile primary WS as a fallback.

## Standard rejection and cancellation codes

Use stable reason codes for diagnostics and replay assertions:

- `SC_NO_TARGET`
- `SC_NO_RESONANCE`
- `SC_TERMINAL`
- `SC_NOT_READY`
- `SC_WINDOW_HIGH_RISK`
- `SC_WINDOW_EXPIRED`
- `SC_CHAINBOUND_SOURCE_UNSUPPORTED`
- `SC_LATEST_SAFE_PASSED`
- `SC_NO_CONTINUATION`
- `SC_RESONANCE_CHANGED`
- `SC_PROPERTIES_CHANGED`
- `SC_WS_UNAVAILABLE`
- `SC_TP_LOST`
- `SC_ACTOR_BLOCKED`
- `SC_TARGET_CHANGED`
- `SC_TARGET_INVALID`
- `SC_OUT_OF_RANGE`
- `SC_ENGINE_DISABLED`
- `SC_REACTION_HOLD`
- `SC_INTENT_LOST`
- `SC_DISPATCH_PENDING_RESULT`
- `SC_DISPATCHED`

Existing general scheduler rejection codes remain valid for non-skillchain proposals.

## Scheduler priority contract

Priority ordering for ready actions must be explicit:

```text
Doom / critical Cure / agreed emergency control
    > valid time-bounded skillchain continuation
    > aftermath refresh and routine defensive/maintenance work
    > ordinary TP-ready opener and configured JA work
```

Sleep/add-control emergency ordering must remain explicit and covered by tests. Do not assign a continuation band until the resulting numeric order is verified against every existing priority constant, including maintenance sequencing.

Continuation urgency increases as `latest_safe_at` approaches. Urgency does not extend the underlying validity window.

An action already dispatched or genuinely in progress is not preempted. This priority governs proposal selection, not cancellation of a server-accepted action.

## Special-rule requirements

### Chainbound

- Use observed Chainbound source time and source-specific delay/lifetime.
- Fail closed with `SC_CHAINBOUND_SOURCE_UNSUPPORTED` when a qualifying source has no evidenced lifetime; do not substitute the ordinary/default expiry formula.
- Apply the documented Level 1 first-property restriction.
- Preserve Level 2/3 Chainbound opener priority.
- Consume/replace state only from the observed qualifying result.

### Aeonic

- Restore effective Level 3 property handling using `skills.lua` metadata.
- Determine eligibility for the acting character from current weapon and aftermath level.
- Do not infer party-wide eligibility from one character's buff.
- Preserve server Radiance/Umbra result as authoritative.

### Diamond Aspis

- Calculate expiry for the candidate actor.
- Preserve normal target expiry for nonwearers and pets.
- Do not replace the target-wide default expiry with the wearer's override.

### Terminal results and magic burst

- Remove `step > 5` as a terminal rule.
- Terminality comes from the result property/level or server evidence.
- In smart non-spam mode, do not automatically send a new property-bearing WS during a terminal MB window.
- Existing explicit spam/solo modes may intentionally ignore chain/MB coordination, but that behavior must remain visible in diagnostics.

## Telemetry contract

For each property action and continuation decision, record:

- monotonic observation timestamp;
- actor ID, target ID, action ID/name, resource, and success state;
- prior and resulting resonance generation;
- ordered source and closer properties;
- predicted result and server-confirmed result;
- action count, stage, and terminal state;
- landed time, earliest, preferred, latest-safe, and expiry times;
- selected WS and selection reason;
- scheduler band/urgency;
- commit-time result and stable rejection code;
- command dispatch time;
- observed result time and whether the chain succeeded.

Prediction/server disagreement must log full context and retain the server result.

## Work packages

### `WS-SC-0` — Characterization and replay foundation

Status: **DONE**

- [x] Add a testable skillchain-state seam without changing live selection behavior.
- [x] Inventory Windower/Lua 5.1 clock sources and approve one monotonic runtime clock; treat this as an exit-gate dependency for `WS-SC-1`.
- [x] Add action-result fixtures for success, miss, interruption, propertyless WS, Chainbound, and server add-effects.
- [x] Pin current transition ordering and operational expiry calculations.
- [x] Add all new suites to the aggregate replay runner and runtime parse checks.

Exit gate: fixtures reproduce current behavior and expose the known global-timer, Chainbound, Aeonic, hard-cap, and commit-revalidation gaps.

### `WS-SC-1` — Target-scoped state and timing

Status: **DONE**

- [x] Introduce the required target-state contract and generation semantics.
- [x] Update state only from successful action results.
- [x] Enforce action-specific earliest, preferred, expiry, and latest-safe timing.
- [x] Preserve resonance on miss/interruption/propertyless WS.
- [x] Add explicit death/despawn/zone/logout/unload/engine-stop reset paths.
- [x] Remove `core.ws_timer` from scheduler-owned eligibility after parity tests pass.

Exit gate: all timing/state fixtures pass and scheduler-owned selection has no read dependency on the global timer.

### `WS-SC-2` — Structured plans and atomic dispatch validation

Status: **DONE**

- [x] Emit structured continuation plans.
- [x] Carry resonance generation and timing into scheduler proposals.
- [x] Add commit-time resonance/property/equipment/status/range validation.
- [x] Cancel and replan on every intervening state change.
- [x] Add stable rejection codes and action-timeline events.
- [x] Preserve the existing wrapper signature for external callers.

Exit gate: an intervening property action, equipment change, TP loss, range change, or target change reliably cancels the stale plan without another WS dispatch.

### `WS-SC-3` — Special rules and terminal cleanup

Status: **DONE**

- [x] Enforce Chainbound timing and priority.
- [x] Restore actor-specific Aeonic effective properties.
- [x] Add Diamond Aspis actor-specific expiry.
- [x] Remove the fixed `step > 5` closure.
- [x] Add terminal MB state and smart-mode hold policy.

Exit gate: all special-rule scenarios in the reference specification pass focused replay tests.

### `WS-SC-4` — Deadline-aware arbitration and field validation

Status: **DONE**

- [x] Insert continuation priority into the complete scheduler band ordering.
- [x] Scale urgency from remaining safe window.
- [x] Preserve Doom, critical Cure, and agreed emergency precedence.
- [x] Enable complete timing/result telemetry for a bounded field test.
- [x] Run the Nyoourke SAM field case and at least one multi-actor race case.
- [x] Record initial field results under `docs/TestResults/`.
- [x] Correct and replay-test the Aeonic-prediction and duplicate-generation findings exposed by the initial capture.
- [x] Run the focused post-reload acceptance capture against the corrected runtime.

Exit gate: repeated live runs show valid continuations dispatched inside the safe window, stale plans canceled, and emergency preemption preserved.

## Required replay scenarios

- [x] Basic directional success at preferred timing.
- [x] Compatible closer too early becomes a new opener.
- [x] Compatible closer after expiry becomes a new opener.
- [x] Miss preserves resonance and original timing.
- [x] Interruption preserves resonance and original timing.
- [x] Propertyless WS preserves resonance and MB state.
- [x] Two targets maintain independent overlapping state.
- [x] Multi-property first-valid-pair priority.
- [x] Every Level 2 loop and promotion.
- [x] Normal terminal Double Light/Double Darkness.
- [x] Radiance/Umbra and aftermath consumption evidence.
- [x] Chainbound Level 1 secondary-property restriction.
- [x] Chainbound two-second earliest timing.
- [x] Diamond Aspis wearer/nonwearer split.
- [x] More than five nonterminal linked actions without local hard closure.
- [x] Another actor changes resonance between proposal and dispatch.
- [x] WS/equipment/aftermath/TP/status/range invalidation at commit.
- [x] AoE selected-target-only state installation at the state-owner seam; packet ordering remains a field observation item.
- [x] Death/despawn/zone/logout/unload/engine-stop cleanup.
- [x] Doom and critical Cure preempt a continuation.
- [x] Routine defensive/maintenance proposal does not consume a ready continuation's safe window.

## Verification commands expected for implementation phases

Use the best available Lua executable in the environment:

```text
luac -p <each changed Lua file>
lua tests/replay/harness/<focused WS-SC selftest>.lua
lua tests/replay/harness/selftest_runtime_parse.lua
lua tests/replay/harness/selftest_side_effect_inventory.lua
lua tests/replay/harness/selftest_all_replay_fixtures.lua
```

Each phase must review `git diff --check`, inspect the final diff, and record exactly which live behavior changed.

## Rollout rules

- Implement one work package per reviewable change set.
- Do not mix profile/config migration, unrelated scheduler cleanup, or formatting changes into this workstream.
- Keep existing public globals and wrappers until all known callers are proven migrated.
- Do not keep the old global-timer eligibility path as a runtime fallback after the target-scoped path is promoted.
- Fail closed with an explicit rejection when required skillchain state is invalid or unavailable.
- Require focused replay success before live field testing.
- Require field evidence before declaring `WS-SC-4` complete.

## Completion definition

This workstream is complete only when:

- every required replay scenario passes;
- the scheduler revalidates the same resonance at commit;
- ordinary, Chainbound, Aeonic, Diamond Aspis, and terminal timing rules are represented explicitly;
- no speculative chain-length cap remains;
- state lifecycle cleanup is explicit;
- continuation priority preserves documented emergency precedence;
- live field results confirm the Nyoourke scenario;
- the compliance audit is updated from partial to compliant or lists any consciously accepted residual deviations.
