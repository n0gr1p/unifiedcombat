# Scheduler-owned WS skillchain field results

Date: 2026-07-20
Workstream: `WS-SC-4`
Status: **PASS — FIELD ACCEPTANCE COMPLETE**

## Evidence scope

The following live action timelines were inspected:

- `data/logs/action_timeline_nyoourke.log`
- `data/logs/action_timeline_ponponponponpon.log`
- `data/logs/action_timeline_terrasjr.log`

The initial files were still being appended during review. Initial statistics below are intentionally bounded to these captured lines:

- Nyoourke through elapsed `849.549` / monotonic observation `33617.559`.
- Ponponponponpon through elapsed `797.153` / monotonic observation `33588.561`.
- Terrasjr supplied independent incoming-action observations but did not dispatch scheduler-owned continuations in the bounded capture.

A second `SESSION_START` was captured after all participating addons were reloaded with the corrected runtime. The deterministic field validator analyzes only that newest session.

## Case A — Nyoourke continuation timing

**Timing result: PASS for the captured build.**

| Actor | Dispatch commits | Unique target/generation/WS keys | Before preferred | After latest-safe | Earliest after preferred | Average after preferred | Latest after preferred | Smallest remaining safe margin |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Nyoourke | 73 | 72 | 0 | 0 | 0.119s | 1.139s | 4.725s | 1.375s |
| Ponponponponpon | 59 | 41 | 0 | 0 | 0.238s | 1.359s | 6.013s | 0.087s |

Every `dispatch_commit` in the bounded sample occurred at or after its plan's `preferred_execute_at` and at or before `latest_safe_at`. This confirms the former global incoming-WS three-second gate has been replaced by target/generation timing and that ready proposals can dispatch inside the guarded window.

The logs also show routine maintenance yielding while a continuation is pending. For example, Ponponponponpon records `MAINT_BUFF_CANDIDATE_SKIPPED` while the band-131 plan is `SC_NOT_READY` or awaiting dispatch.

## Case B — multi-actor replacement before dispatch

**Result: PASS for both required variants.**

The bounded logs contain plans replaced by a new server-observed generation before any `dispatch_commit` for the old target/generation key:

| Observer | Total replacements before dispatch | Successful intervening chain result | Successful non-chain overwrite |
| --- | ---: | ---: | ---: |
| Nyoourke | 34 | 4 | 30 |
| Ponponponponpon | 8 | 3 | 5 |

Representative successful-chain race:

- Nyoourke elapsed `306.38`: generation 9 planned `Tachi: Shoha`.
- Nyoourke elapsed `306.78`: another actor's `Savage Blade` produced server-confirmed `Light`, replacing generation 9 with generation 10 before the planned WS dispatched.

Representative non-chain overwrite race:

- Nyoourke elapsed `56.10`: generation 2 planned `Tachi: Fudo`.
- Nyoourke elapsed `56.40`: another actor's successful `Savage Blade` installed a new opener as generation 3 before generation 2 dispatched.

No configured-primary fallback dispatch was found for these superseded generation keys.

## Cases C and D disposition

- Case C was not artificially forced in game because the emergency combinations are impractical to reproduce safely in the current setup. The user accepted replay coverage for this case. The aggregate suite proves critical Cure and Sleep/emergency priority above continuation and continuation above routine maintenance/aftermath work. Natural field evidence confirms routine maintenance yielding.
- Case D is not applicable to the current party/setup and is recorded as a no-op rather than fabricated evidence. AoE packet ordering, LOS rejection, and optional Chainbound-source calibration remain observational follow-ups, not blockers for the Nyoourke timing objective.

## Findings discovered by the field capture

### F1 — non-Aeonic AM3 incorrectly predicted Radiance

Nyoourke recorded three `predicted_result=Radiance server_result=Light` disagreements. Nyoourke was using Masamune AM3, not an Aeonic weapon. The server result remained authoritative, so resonance state was safe, but local Ultimate prediction was too broad because buff ID 272 alone was treated as sufficient.

Correction:

- Ultimate prediction now requires a nonempty equipped Aeonic weapon identity in addition to the actor's Aftermath level and action-count threshold.
- A focused replay case proves Masamune/non-Aeonic AM3 predicts terminal `Light`, while an Aeonic actor context can still predict Radiance/Umbra at AM1/AM2/AM3 thresholds.

### F2 — one resonance generation could issue repeated `/ws` sends

The captured build produced one duplicated Nyoourke generation and eight duplicated Ponponponponpon generations. Nyoourke's duplicate issued two `dispatch_commit` events for the same target/generation/WS; Ponponponponpon accumulated 18 excess commits across eight duplicated generations. The general scheduler action lock could release before the skillchain action result replaced resonance.

Correction:

- A successful `/ws` send now reserves its exact target/resonance generation in the skillchain owner.
- Further planning for that generation emits a non-dispatchable band-131 reservation proposal. Commit fails closed with `SC_DISPATCH_PENDING_RESULT`, preventing both another WS and lower routine work while the result is pending; emergency bands remain able to preempt.
- Any successful property-bearing replacement, target clear, or lifecycle reset releases the reservation through generation/state replacement.
- Focused replay proves the same generation cannot dispatch twice and that an intervening new generation becomes plannable normally.

## Corrective verification

```text
luac -p uc_skillchain_state.lua unified_combat_core.lua
PASS

lua tests/replay/harness/selftest_skillchain_state.lua
selftest_skillchain_state: OK

lua tests/replay/harness/selftest_scheduler_skillchain_integration.lua
selftest_scheduler_skillchain_integration: OK

lua tests/replay/harness/selftest_side_effect_inventory.lua
selftest_side_effect_inventory: OK (files=13, patterns=39)

lua tests/replay/harness/selftest_all_replay_fixtures.lua
selftest_all_replay_fixtures: OK (95 suites)

git diff --check
PASS (line-ending conversion warnings only; no whitespace errors)
```

## Focused post-reload acceptance result

**Result: PASS.** The corrected worktree was reloaded on the participating addons and more than five ordinary continuation attempts were captured. No artificial Case C or Case D setup was required.

| Actor | Newest-session dispatches | Ultimate predictions | Earliest after preferred | Smallest remaining safe margin | Validator |
| --- | ---: | ---: | ---: | ---: | --- |
| Nyoourke | 35 | 0 | 0.220s | 1.175s | PASS (`non_aeonic`) |
| Ponponponponpon | 13 | 0 | 0.246s | 2.699s | PASS |

The validator proved all of the final acceptance conditions:

1. Every `dispatch_commit` was inside `[preferred_execute_at, latest_safe_at]`.
2. Each target/resonance generation had at most one `dispatch_commit`, with `SC_DISPATCH_PENDING_RESULT` observed after send while its result was pending.
3. The Nyoourke Masamune/non-Aeonic session produced zero Radiance/Umbra predictions. Ordinary Double Light remained `Light`; the server result remained authoritative.
4. The already-captured Case B evidence remains the accepted live multi-actor race evidence.

Run the deterministic validator after the new session:

```text
lua tests/replay/harness/audit_scheduler_owned_ws_skillchain_field_log.lua data/logs/action_timeline_nyoourke.log 5 non_aeonic
field_log=data/logs/action_timeline_nyoourke.log sessions=2 dispatches=35 ultimate_predictions=0 after_preferred_min=0.220 before_latest_min=1.175
audit_scheduler_owned_ws_skillchain_field_log: PASS

lua tests/replay/harness/audit_scheduler_owned_ws_skillchain_field_log.lua data/logs/action_timeline_ponponponponpon.log 5
field_log=data/logs/action_timeline_ponponponponpon.log sessions=2 dispatches=13 ultimate_predictions=0 after_preferred_min=0.246 before_latest_min=2.699
audit_scheduler_owned_ws_skillchain_field_log: PASS
```

The validator analyzes only the newest `SESSION_START`, so the initial pre-correction evidence may remain in the same log. It fails on early/late timing, duplicate generation dispatch, missing `SC_DISPATCH_PENDING_RESULT`, insufficient dispatch count, or Radiance/Umbra prediction in the declared non-Aeonic session.

The post-correction capture closes the `WS-SC-4` field gate. Cases A and B are field-verified, Case C is replay-verified by user-approved disposition, and Case D remains not applicable to the current setup.
