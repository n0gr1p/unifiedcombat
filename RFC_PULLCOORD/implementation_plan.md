# Coordinated Multi-Puller Implementation Plan

This file tracks the planned implementation of
`RFC_PULLCOORD/pull_coordinator_rfc.md`.

No implementation work has started. All runtime behavior remains unchanged.

## Current status

| Phase | Code status | Automated verification | Field verification |
| --- | --- | --- | --- |
| 0 — Contract and test model | Not started | Not started | Not applicable |
| 1 — Coordinator state machine | Not started | Not started | Not applicable |
| 2 — IPC session and snapshots | Not started | Not started | Not started |
| 3 — Worker grants and reservations | Not started | Not started | Not started |
| 4 — Registry single-writer integration | Not started | Not started | Not started |
| 5 — Failure and recovery | Not started | Not started | Not started |
| 6 — Configuration, profile, and UI | Not started | Not started | Not started |
| 7 — Observability and compatibility | Not started | Not started | Not started |
| 8 — Integrated and field acceptance | Not started | Not started | Not started |

## Implementation constraints

- Preserve Lua 5.1 and Windower compatibility.
- Introduce no external dependency.
- Keep coordinated mode default-off.
- Preserve existing single-puller behavior when coordination is disabled.
- Do not use claim ownership as a reservation.
- Do not add automatic coordinator election.
- Do not let coordinator failure invoke uncoordinated pulling.
- Keep runtime session state out of durable profiles.
- Preserve scheduler proposal ranking, action-state, pending, movement, and
  dispatch semantics except for the explicit coordinated pull-admission gate.
- Prefer pure state transitions and injected time/IPC dependencies for replay
  tests.
- Fail fast on invalid contracts and block on ambiguous runtime state.

## Phase 0 — Contract and deterministic test model

### Deliverables

- [ ] Freeze the normalized `combat.pulling.coordination` schema.
- [ ] Freeze the shared-policy signature fields.
- [ ] Freeze coordinator, worker, and reservation state enums.
- [ ] Freeze the IPC envelope and operation field contracts.
- [ ] Freeze reason-code families.
- [ ] Define a pure coordinator input snapshot for tests.
- [ ] Define deterministic fake clock, mob, party/alliance, camp, and IPC
  fixtures.
- [ ] Add the new suites to the aggregate replay runner.

### Verification gate

- Invalid names, duplicate pullers, missing coordinator, malformed lists, and
  wrong types fail normalization.
- Every protocol operation rejects malformed, stale-zone, stale-epoch, and
  unauthorized input deterministically.
- Documentation and test contracts agree before runtime integration begins.

## Phase 1 — Coordinator state machine

### Deliverables

- [ ] Add `uc_camp_pull_coordinator.lua` as a pure state owner.
- [ ] Implement explicit coordinator identity and zone-scoped epochs.
- [ ] Implement coordinator session states.
- [ ] Implement assigned-puller runtime records and heartbeat freshness.
- [ ] Implement canonical shared-policy signature comparison.
- [ ] Implement capacity calculation using active plus pending counts.
- [ ] Preserve exactly one early-replenishment slot.
- [ ] Implement configured-order round-robin selection.
- [ ] Implement one-reservation-per-worker and one-reservation-per-mob
  invariants.
- [ ] Implement strict reservation transitions and terminal history pruning.
- [ ] Expose a side-effect-free coordinator snapshot.

### Focused tests

- [ ] No capacity produces no grant.
- [ ] Two empty base slots can grant two different workers.
- [ ] A worker cannot receive a second reservation.
- [ ] A mob cannot receive a second reservation.
- [ ] Round-robin advances only on successful grants.
- [ ] Offline and ineligible workers are skipped deterministically.
- [ ] Two same-mob proposals result in one reservation.
- [ ] Low-HP full-stack demand creates exactly one extra reservation.
- [ ] `UNCERTAIN` consumes capacity.
- [ ] Invalid transitions fail fast.

### Verification gate

All coordinator logic passes without loading Windower, scheduler, movement, or
command-dispatch code.

## Phase 2 — IPC session and authoritative snapshots

### Deliverables

- [ ] Add strict encoding and parsing for `uc_pull_coord_v1`.
- [ ] Add coordinator `SESSION` heartbeat emission.
- [ ] Add periodic authoritative `SNAPSHOT` emission.
- [ ] Add worker `PULLER_STATUS` emission.
- [ ] Track sender sequence and coordinator revision.
- [ ] Make duplicate messages idempotent.
- [ ] Reject delayed revisions and stale worker sequences.
- [ ] Validate configured name against current runtime entity ID.
- [ ] Validate current party/alliance scope and zone.
- [ ] Bind the session to current camp-anchor identity.
- [ ] Route IPC once through the existing UnifiedCombat IPC event.
- [ ] Reset protocol state explicitly on zone, logout, and unload.

### Focused tests

- [ ] Round-trip every message type.
- [ ] Reject wrong field count and invalid numerics.
- [ ] Reject delimiter injection in names and identifiers.
- [ ] Reject wrong coordinator, unassigned worker, wrong zone, and stale epoch.
- [ ] Reordered incrementals cannot overwrite a newer snapshot.
- [ ] Duplicate grants and acknowledgements have one side effect.
- [ ] A full snapshot repairs a deliberately dropped incremental message.

### Verification gate

Two mocked addon instances converge on the same coordinator snapshot despite
duplicate and reordered message delivery.

## Phase 3 — Worker grants and local journey integration

### Deliverables

- [ ] Extend the camp-puller provider with coordinated worker status.
- [ ] Keep local candidate selection read-only while awaiting a grant.
- [ ] Advertise only the best currently eligible local candidate.
- [ ] Prevent `begin_journey` without a valid local reservation.
- [ ] Revalidate grant identity, mob, camp, action, engine, and domains before
  acknowledgement.
- [ ] Send progress for approach, settle, action sent, reaction wait, and
  return.
- [ ] Revalidate current coordinator snapshot immediately before dispatch.
- [ ] Stop and return on pre-action grant loss.
- [ ] Preserve existing breadcrumbs, movement recovery, retry, cooldown, and
  direct entity-ID action behavior.
- [ ] Make the coordinator itself use the same worker path when listed as a
  puller.

### Focused tests

- [ ] A ready worker without a grant emits no movement or action.
- [ ] A grant for another worker or mob is ignored.
- [ ] An accepted grant starts exactly one journey.
- [ ] Candidate invalidation before dispatch cancels safely.
- [ ] A stale coordinator heartbeat before dispatch emits stop and no pull
  action.
- [ ] Duplicate grants cannot restart or duplicate a journey.
- [ ] Existing coordination-disabled camp-puller tests remain unchanged.
- [ ] Scheduler and movement side-effect counts remain bounded and explicit.

### Verification gate

No coordinated pull action can be observed without a matching current grant in
the captured coordinator snapshot.

## Phase 4 — Registry single-writer integration

### Deliverables

- [ ] Add coordinator-authored coordinated registry records.
- [ ] Add coordinator epoch, reservation ID, and puller provenance.
- [ ] Allocate global `pull_order` only at validated reaction commit.
- [ ] Prevent workers from allocating coordinated pull order.
- [ ] Prevent non-coordinator clients from broadcasting coordinated registry
  transitions.
- [ ] Accept peer observations without surrendering coordinator authority.
- [ ] Preserve `ACTIVE_PULL`, `FOREIGN_CLAIMED`, `ORPHANED_HOSTILE`,
  `FORFEITED_IDLE`, and `ENDED` behavior.
- [ ] Keep reservations outside the combat registry.
- [ ] Preserve FIFO combat targeting and tracked-candidate exclusion.
- [ ] Preserve zone and fresh-spawn reset behavior.

### Focused tests

- [ ] Two concurrent reactions receive unique increasing orders.
- [ ] Canceled grants consume no pull order.
- [ ] A reservation is not combat eligible before reaction.
- [ ] Commit makes the reacted mob visible on every consumer.
- [ ] Worker provenance does not change combat eligibility or partner logic.
- [ ] Friendly claim turnover preserves order.
- [ ] Foreign claim, yellow-hostile return, forfeiture, death, and fresh respawn
  retain existing semantics.
- [ ] Unauthorized coordinated registry writes are rejected.

### Verification gate

All clients converge on the same records and pull orders with one authoritative
writer and no duplicate registration path.

## Phase 5 — Failure, uncertainty, and recovery

### Deliverables

- [ ] Implement pre-action grant expiry with live untouched-mob validation.
- [ ] Implement action-sent `UNCERTAIN` state.
- [ ] Prevent timer-only cancellation after action dispatch.
- [ ] Resolve uncertainty from authoritative live mob evidence.
- [ ] Handle worker death, zone, logout, unload, and heartbeat loss by phase.
- [ ] Handle coordinator loss without election or independent fallback.
- [ ] Start new coordinator epochs in `RECOVERING`.
- [ ] Implement `SYNC_REQUEST` and `SYNC_RESPONSE`.
- [ ] Reconcile retained registry records and prior in-flight actions.
- [ ] Set next pull order above all accepted retained records.
- [ ] Enter `BLOCKED` on conflicting recovery evidence.
- [ ] Add an explicit coordinator reset that refuses to discard ambiguous live
  work.

### Focused tests

- [ ] Worker disappears during grant, approach, settle, action-sent, and
  reaction-wait phases.
- [ ] Coordinator disappears in the same phases.
- [ ] Pre-action untouched reservations cancel and release capacity.
- [ ] Action-sent loss remains uncertain and occupies capacity.
- [ ] Damaged, hostile, friendly-claimed, foreign-claimed, and untouched mobs
  resolve correctly.
- [ ] New epoch invalidates old grants before dispatch.
- [ ] Recovery union preserves live registry order.
- [ ] Conflicting peer snapshots block instead of choosing one silently.
- [ ] Reset refuses live or ambiguous state.

### Verification gate

No tested loss or restart scenario permits an ungranted action, duplicate mob
reservation, quota overshoot, or silent loss of an action-sent mob.

## Phase 6 — Configuration, profile-v2, and WinForms UI

### Deliverables

- [ ] Add strict normalizer defaults and validation.
- [ ] Add active-config projection.
- [ ] Add profile-v2 export and diff ownership.
- [ ] Keep epochs, identities, reservations, heartbeats, and registry records
  out of durable settings.
- [ ] Add offline UI fields for coordinated mode, coordinator, and ordered
  pullers.
- [ ] Validate duplicate names and required fields before save.
- [ ] Clearly label shared coordinator-owned quota policy versus local worker
  action policy.
- [ ] Preserve existing profiles with coordination default-off.
- [ ] Add structured writer and UI parity tests.

### Verification gate

Profile save/load round-trips the durable coordination policy exactly, rejects
invalid configurations, and never serializes runtime coordination state.

## Phase 7 — Observability and compatibility

### Deliverables

- [ ] Extend `//uc camp pullstatus` with local worker coordination state.
- [ ] Add coordinator status output.
- [ ] Add stable reason codes from RFC section 18.
- [ ] Add action-timeline events for sessions, grants, progress, uncertainty,
  commits, cancellations, and recovery.
- [ ] Add coordinator and worker status to the WinForms runtime surface.
- [ ] Document operator setup and common blocked states.
- [ ] Preserve route-hunter and party-follow behavior.
- [ ] Preserve scheduler rank, lock, pending, and action-state behavior.
- [ ] Preserve partner arbitration and combat-role independence.

### Verification gate

Every non-action outcome in integration tests exposes one stable reason, and a
captured status snapshot identifies coordinator, worker, mob, reservation,
capacity, and recovery state without inspecting internal Lua tables.

## Phase 8 — Integrated and field acceptance

### Automated scenarios

- [ ] Two pullers fill a two-mob empty stack concurrently.
- [ ] Two pullers propose the same nearest mob.
- [ ] Three pullers compete for two open slots.
- [ ] One puller has no ready action while another is ready.
- [ ] Pullers use different action types and target lists.
- [ ] Full two-mob stack at threshold admits one refresh pull.
- [ ] One reserved mob reacts while another reservation cancels.
- [ ] Foreign actor claims a reserved or newly reacted mob.
- [ ] Coordinator reload occurs with active registry entries.
- [ ] Coordinator reload occurs with an action-sent reservation.
- [ ] Zone change occurs with pullers in different local phases.
- [ ] SAM-versus-rest partner separation works regardless of source puller.
- [ ] Aggregate replay suite and runtime parse suite pass.
- [ ] Every changed Lua file passes `luac -p` when available.

### Field scenarios

- [ ] Two spell pullers, two empty quota slots.
- [ ] Spell puller plus JA puller.
- [ ] Same-candidate contention under live latency.
- [ ] Early replenishment at the configured HPP threshold.
- [ ] One puller temporarily loses MP, readiness, or movement eligibility.
- [ ] Puller death before action and after action.
- [ ] Coordinator addon reload with live pulled mobs.
- [ ] Coordinator loss before dispatch produces no action.
- [ ] Coordinator loss after dispatch blocks capacity until resolved.
- [ ] Foreign claim and later yellow-hostile return.
- [ ] Long outbound journeys and simultaneous returns.
- [ ] Coordinator status and action-timeline evidence captured for every case.

### Final acceptance gate

The feature may be described as supported only after automated verification is
complete and live field evidence proves:

- no duplicate pull actions for one mob;
- no shared quota overshoot;
- no colliding pull orders;
- no action without a grant;
- no silent coordinator fallback;
- correct uncertainty retention; and
- unchanged single-puller and combat-target behavior.

## Planned file impact

Expected new files:

- `uc_camp_pull_coordinator.lua`
- focused coordinator/protocol replay self-tests

Expected existing files to change during implementation:

- `uc_camp_puller.lua`
- `uc_camp_puller_policy.lua`
- `uc_camp_pull_registry.lua`
- `uc_config_normalizer.lua`
- `uc_active_config.lua`
- `uc_profile_v2.lua`
- `unified_scheduler.lua`
- `UnifiedCombat.lua`
- relevant aggregate/runtime-parse tests
- WinForms camp-pulling, profile, parity, and structured-writer files
- `README.md`

This list is an implementation forecast, not authorization for unrelated
refactoring. Each phase should remain independently reviewable and preserve
existing public surfaces.

