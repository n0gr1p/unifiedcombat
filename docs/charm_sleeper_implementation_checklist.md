# Charmed Player Sleeper Implementation Checklist

## Status

Architecture validation and Phase 1 implementation completed on 2026-08-01.

Manual in-game validation remains required because the replay harness cannot create a real Windower charmed-player entity or prove that every supported spell is accepted by the FFXI client against that entity.

## Goal

Add a highest-priority defensive emergency feature that detects charmed party members and keeps them slept until charm clears.

## Validated Architecture

- Durable configuration is structured at `config.defensive.charm_sleeper.enabled`.
- `def_charm_sleeper_enabled` is the flat runtime/UI compatibility mirror. It is not the durable profile shape.
- The WinForms boolean registry in `HubUiConstants` owns toggle creation, hydration, persistence, and generic remote `set` forwarding. No feature-specific remote bridge operation is needed.
- Party member collection is owned by `unified_scheduler.lua`. Charm comes directly from the current party mob object as `entry.mob.charmed`; it is revalidated from `get_mob_by_id(target_id).charmed` before proposal creation.
- Party Sleep state comes from the existing local/IPC/0x076 buff snapshots. Sleep effect ids come from the checked-in policy data.
- Proposal creation is owned by `uc_provider_charm_sleeper.lua`; normal casting uses the existing `defensive_internal` dispatch, action lock, movement-freeze, and target-id command path.
- Doom Holy Water is still a legacy prepass rather than a ranked proposal. A narrow charm-sleeper emergency arbitration step therefore runs before that Doom prepass. The same charm proposal also participates in normal defensive collection.
- The checked-in JSON policy is loaded by `uc_charm_sleeper_policy.lua` with fail-fast schema/field validation and no runtime fallback list.

## Phase 1 Behavior

- The feature requires the defensive domain, Defensive master toggle, and `Charm sleeper` toggle to be enabled.
- It works with either normal defensive provider selection (`internal` or `healbot`) because the emergency is provider-independent.
- Local-player charm is observed but never dispatched because a charmed local player cannot act reliably.
- Trusts/NPCs, dead members, cleared charm state, missing mobs, and out-of-range targets are rejected.
- Safe spells are evaluated in `selector_policy.default_sort_order` from `docs/ffxi_charmed_player_sleep_spells.json`.
- Spells listed in `exclude_by_default` are never selected. This excludes damage-bearing emergency actions such as Pinecone Bomb.
- Yawn is excluded because its gaze/facing requirement cannot be verified by the current provider.
- Blue Magic sleeps must be present in the active main-job or support-job BLU spell set.
- Each spell must be learned, usable by the current main/sub job, recast-ready, affordable, targetable, and in range.
- A live Sleep buff suppresses recasting. If the buff snapshot is present and Sleep disappears early, the provider retries after the one-second per-target/action attempt gate.
- A successful local 0x028 spell result records the policy duration, projected end, and two-second pre-clear time. Projection suppresses only when live party buff data is unavailable; live buff state remains authoritative.
- Charm clear removes attempt and projection state on the next scheduler scan.

## Priority and Arbitration

- Proposal family: `emergency.charm_sleep.primary`.
- Priority band: `1000`.
- This is higher than critical cure (`153`) and all other ranked actions.
- The emergency arbitration step runs before Doom Holy Water, target acquisition, partner arbitration, and BRD/camp lane handling.
- Existing global scheduler/action locks and commit revalidation still block dispatch.

## Observability

Defensive scheduler logging includes:

- charmed candidates;
- selected spell, distance, and range;
- `NO_CHARMED_TARGET`, `TARGET_ALREADY_SLEPT`, `NOT_READY`, `BLU_SPELL_NOT_SET`, `OUT_OF_RANGE`, `ATTEMPT_GATE`, invalid-target, and self-charm rejection states;
- successful spell confirmation, projected end, pre-clear, dispatch, and stale-state cleanup.

The in-game diagnostic overlay includes a `CharmSleeper:` line backed by `UC_CHARM_SLEEPER_STATUS`.

## Implementation Checklist

- [x] Add `config.defensive.charm_sleeper.enabled` with default `false`.
- [x] Add `def_charm_sleeper_enabled` to addon defaults and flat profile/runtime keys.
- [x] Project structured config back to the flat runtime mirror.
- [x] Add the WinForms `Charm sleeper` toggle to shared boolean keys, labels, and Defensive card keys.
- [x] Cover UI hydrate/apply/save and generic remote bridge forwarding through the shared boolean registry.
- [x] Add fail-fast policy loading from `docs/ffxi_charmed_player_sleep_spells.json`.
- [x] Exclude policy actions marked unsafe by default.
- [x] Copy and revalidate the authoritative mob `charmed` flag.
- [x] Detect Sleep from existing party buff snapshots.
- [x] Add the charm-sleeper proposal provider and `emergency.charm_sleep.primary` family.
- [x] Add priority band `1000` and arbitration ahead of Doom.
- [x] Use the existing defensive spell dispatch, entity-id targeting, and movement/cast coordination.
- [x] Add one-second per-target/action dispatch throttling.
- [x] Track confirmed projections and two-second pre-clear events.
- [x] Retry early breaks when live buff state shows Sleep removed.
- [x] Clear state when charm clears, the feature is disabled, or zoning occurs.
- [x] Add defensive logs and the overlay status line.
- [x] Add focused provider tests and config/UI persistence coverage.

## Automated Acceptance

- [x] Toggle defaults off and OFF emits no charm-sleeper proposal.
- [x] Charmed, alive, non-self target emits an immediate proposal when a safe spell is available.
- [x] Stronger unavailable spell advances to the next ready policy spell.
- [x] Proposal priority is above critical cure and normal ranked actions.
- [x] Live Sleep buff suppresses recasting.
- [x] Confirmed projection suppresses while live buff data is unavailable.
- [x] Projected pre-clear releases projection suppression.
- [x] Early observed Sleep break retries after the minimal gate.
- [x] Charm clear stops proposals and clears state.
- [x] Self charm never dispatches.
- [x] Structured and flat configuration round-trip through Lua and WinForms paths.

## Manual In-Game Acceptance

- [ ] Enable `Debug`, `Log: defensive scheduler`, Defensive, and `Charm sleeper`.
- [ ] Reproduce charm on a party member.
- [ ] Confirm the client accepts the target-id sleep command against the charmed player.
- [ ] Confirm the first learned/usable policy spell is selected for the current job.
- [ ] Confirm the charm sleeper preempts Doom Holy Water and a simultaneous critical cure.
- [ ] Confirm no second cast while the target has Sleep in the party buff snapshot.
- [ ] Break Sleep early while charm remains and confirm retry after the minimal gate.
- [ ] Let Sleep approach projected wear-off and confirm the pre-clear log without recasting while the live Sleep buff remains.
- [ ] Clear charm and confirm immediate stop/cleanup.
- [ ] Repeat once with `defensive_provider=internal` and once with `defensive_provider=healbot`.

## Out of Scope

- Tier-1 then tier-2 overwrite ladders.
- Per-job sleep policy editing.
- Zone-specific behavior.
- General non-charm crowd control.
- Damage-bearing emergency sleep actions.
- Summoner Blood Pact sleeps.
