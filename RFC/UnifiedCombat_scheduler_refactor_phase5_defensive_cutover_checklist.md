# UnifiedCombat Scheduler Refactor — Phase 5 Defensive Cutover Checklist

Status date: 2026-07-24

Implementation state: **DONE / FIELD VERIFIED**

## Runtime path

- [x] `uc_domain_ownership.is_enabled('defensive')` gates the Doom emergency
  prepass, defensive wait lifecycle, proposal collection, and dispatch.
- [x] Internal defense and HealBot proposal paths remain mutually selected by
  `config.defensive.provider`.
- [x] Internal spells execute through the scheduler dispatcher.
- [x] HealBot remains an explicit delegated provider call through
  `healer:take_action`; there is no second scheduler-local execution attempt.
- [x] Enemy-buff removal remains in the defensive collection cadence.

## Fallback closure

- [x] `scheduler.process_tick` no longer calls
  `try_internal_defensive_action()` after ranked dispatch.
- [x] `scheduler.process_tick` no longer calls `try_delegate_healbot()` after
  ranked dispatch.
- [x] Disabling the legacy defensive marker cannot reactivate either fallback.
- [x] Legacy helper bodies remain only as Phase 6 dead-code cleanup scope.

## Settings combinations

| `domain_defensive_enabled` | `defensive_enabled` | Legacy marker | Result |
| --- | --- | --- | --- |
| true | true | true or false | Selected scheduler defensive provider runs |
| true | false | true or false | No normal defensive proposals; Doom also requires its explicit feature setting |
| false | either | true or false | No defensive prepass, proposal, wait gate, or dispatch |

There is no setting combination that selects the former scheduler-local
defensive fallback.

## Evidence

- `tests/replay/harness/selftest_phase5_domain_cutover.lua`
- internal/HealBot provider shape and priority suites
- cure movement-lock, spell success/interruption, JA-to-cure, cure-weave,
  enemy-effect, and Doom dispatcher suites
- `_G.UC_LAST_SCHED_ACTION`, `_G.UC_SCHED_PROVIDER`, pending/lock overlay, and
  retained dispatcher validation globals

## Field acceptance record

| Item | Result | Evidence / disposition |
| --- | --- | --- |
| Defensive behavior during live party cycles | `PASS / NO REGRESSION OBSERVED` | The five-character party completed several full mob cycles without an observed regression or bug. |
| Defensive casting and movement coordination | `PASS / PRIOR FIELD BASELINE` | Phase 3 multibox defensive spell casting and Phase 4 combat/casting movement acceptance passed; the current session reported no regression. |
| False legacy-marker and disabled-domain cases | `AUTOMATED EVIDENCE ACCEPTED` | Focused domain-cutover tests prove the marker is non-authoritative and disabling the domain removes prepass, waits, collection, and dispatch. |
| HealBot, Doom/Holy Water, and isolated pending-Cure cases | `NOT ISOLATED` | These cases were not specifically reported in the current session. Their focused provider, action-state, Doom, and dispatcher tests remain green. |

The live no-regression result, prior defensive field baseline, and focused
cutover tests satisfy the Phase 5 defensive exit gate without claiming
unperformed isolated cases.
