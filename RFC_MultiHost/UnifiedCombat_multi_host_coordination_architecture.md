# UnifiedCombat Single-Coordinator Multi-Host Coordination and Shared Configuration Architecture

**Status:** Refined proposed architecture  
**Decision:** One authoritative coordinator per coordinated session  
**Applies to:** UnifiedCombat checkout inspected from `UnifiedCombat(3).zip`  
**Repository HEAD:** `4011e81`  
**Implementation status:** The approved local pull-coordinator RFC exists, but coordinated pulling and multi-host transport have not been implemented.

---

## 1. Decision and scope

UnifiedCombat will support coordinated pulling across multiple physical computers through **one authoritative coordinator** and multiple worker characters.

The selected architecture is:

- one explicitly configured **UnifiedCombat Lua coordinator instance** per coordinated session;
- one normal local UnifiedCombat scheduler in every character instance;
- one lightweight **UnifiedCombat node gateway** on each physical computer;
- authenticated persistent connections between node gateways through a relay/API service; and
- a relational database for durable configuration, identity, permissions, revisions, and audit history only.

The coordinator is the only component allowed to grant shared pull capacity, reserve mobs, assign global pull order, or commit coordinated pull-registry records.

Every worker remains responsible for local game execution:

- selecting a locally valid candidate;
- checking its own action readiness;
- approaching the target;
- dispatching the pull action through its local scheduler;
- observing reaction evidence;
- returning to camp; and
- recovering local movement and action ownership.

The remote infrastructure authorizes and coordinates a local pull journey. It does not remotely drive movement or combat execution.

### 1.1 Explicitly out of scope

This architecture does not include:

- active-active coordinators;
- coordinator consensus or quorum;
- automatic leader election;
- automatic coordinator promotion;
- synchronously replicated runtime coordinator state;
- direct database polling by Windower clients; or
- independent pulling as a fallback when coordinator connectivity is lost.

If the coordinator is unavailable, coordinated pulling stops. Starting a replacement coordinator is a deliberate recovery operation that creates a new coordinator epoch.

---

## 2. Why one coordinator is practical

A remote worker pays network latency only during the pull-authorization handshake:

1. the worker proposes a candidate;
2. the coordinator grants or rejects the proposal; and
3. the worker acknowledges and locally revalidates the grant.

After that handshake, the entire journey remains local.

UnifiedCombat's scheduler runs on a roughly 0.20-second tick, but a pull journey takes seconds. A network round trip of approximately 100–400 ms may delay the start of a remote pull by several tenths of a second. That is acceptable for capacity coordination and mob reservation.

It would not be acceptable for:

- movement vectors;
- action dispatch;
- reaction detection;
- spell interruption handling;
- defensive actions;
- cures;
- weapon skills; or
- scheduler arbitration.

Those paths remain local and do not wait on a remote response.

### 2.1 Local-latency advantage must not determine fairness

The coordinator's local workers will naturally submit and receive messages faster than remote workers. The coordinator must therefore use explicit fairness state, such as configured round-robin worker rotation, rather than granting whichever proposal arrives first.

The design accepts unequal transport latency but must not allow that latency to become a permanent worker priority.

---

## 3. Existing UnifiedCombat boundaries to preserve

### 3.1 Scheduler ownership

UnifiedCombat already has one scheduler-owned action path:

- `unified_engine.lua` drives the engine tick;
- `unified_scheduler.lua` owns proposal collection, ranking, dispatch, pending-action state, and provider arbitration;
- scheduler movement and run-ownership modules control local movement authority; and
- providers submit proposals instead of executing uncontrolled parallel actions.

The multi-host implementation must preserve this model. No remote component may bypass the scheduler and directly issue movement, spell, ability, weapon-skill, ranged, or pet commands.

### 3.2 Camp-puller ownership

The existing camp-puller boundary is appropriate for coordination:

- `uc_camp_puller.lua` owns the local pull journey;
- `uc_camp_puller_policy.lua` owns local candidate and demand policy helpers;
- `uc_camp_pull_registry.lua` tracks reacted pulls and their lifecycle; and
- `uc_camp_anchor.lua` owns the camp anchor consumed by movement and pulling.

The coordinator grants permission before the journey begins. The existing camp-puller continues to own the journey itself.

### 3.3 Existing same-machine communication

Cross-character runtime communication currently uses Windower IPC. `UnifiedCombat.lua` routes IPC messages to the camp anchor, pull registry, combat core, and scheduler listeners.

Windower IPC is local to one physical machine. It cannot be the transport for a multi-host session.

### 3.4 Existing bridge boundary

`remote_bridge.lua` is a nonblocking LuaSocket TCP client using newline-delimited JSON. It currently connects to the configured host and port, defaulting to `127.0.0.1:27182`.

`UnifiedCombatWinForms/MirrorDuplex.cs` currently:

- listens only on loopback;
- accepts multiple local addon sessions;
- receives `hello`, `state`, and `options` messages;
- forwards a limited command set; and
- exists inside the WinForms process lifecycle.

This is a useful local process boundary, but it is not a production internet transport. It currently lacks:

- TLS;
- node authentication;
- remote authorization;
- a grant-specific acknowledged protocol;
- bounded priority queues;
- durable process lifetime independent of WinForms; and
- reconnect/resynchronization semantics suitable for coordinator authority.

The current bridge port must not be exposed directly to the internet.

### 3.5 Existing configuration ownership

UnifiedCombat already separates durable configuration from runtime state:

- WinForms authors profile-v2 files;
- the addon validates and consumes them;
- `_G.UC_ACTIVE_PROFILE` is the applied canonical profile;
- `_G.UC_SETTINGS` is a compatibility projection; and
- active targets, journeys, reservations, locks, pending actions, and path progress are runtime state rather than profile data.

Shared configuration must preserve that contract. A remote service may distribute and revision profile data, but local nodes must materialize normal profile-v2 files and use the existing validation/reload path.

---

## 4. Authoritative ownership model

The implementation must distinguish local observation from global authority.

| Concern | Authority |
|---|---|
| Local entity visibility and candidate validity | Worker |
| Local action readiness and cooldowns | Worker |
| Local movement and scheduler ownership | Worker scheduler |
| Shared pull demand and available capacity | Coordinator |
| Worker fairness and selection | Coordinator |
| Exclusive mob reservation | Coordinator |
| Reservation lifecycle | Coordinator, based on worker evidence |
| Global reacted-pull order | Coordinator |
| Coordinated registry commits | Coordinator |
| Durable character configuration | Profile-v2/configuration system |
| Shared session manifest | Coordination service |
| User, site, and command permissions | Coordination service |

### 4.1 Worker authority over local world state

A coordinator on another character may not have the worker's proposed mob loaded. FFXI clients can differ in:

- loaded entities;
- claim-state timing;
- HP updates;
- distance and coordinates;
- despawn timing; and
- alliance or party observations.

Therefore, the coordinator must not reject a proposal solely because the coordinator cannot see the mob locally.

The worker is authoritative for local eligibility and must revalidate immediately before dispatch:

- same zone;
- entity still present;
- expected mob identity and name;
- alive and actionable;
- compatible claim state;
- within configured geometry and leash rules;
- not represented by a locally installed reservation or registry record; and
- local scheduler, action, and movement domains still available.

### 4.2 Coordinator authority over shared decisions

The coordinator decides whether the worker may act at all. It validates:

- coordination session and epoch;
- configured worker identity;
- zone, alliance/party, camp-anchor, and policy compatibility;
- worker heartbeat freshness;
- available shared quota;
- existing reservations;
- fairness order;
- duplicate or conflicting candidate reports; and
- whether the session is currently allowed to grant.

A worker may have a valid local candidate and still receive no grant because shared capacity or session state blocks it.

---

## 5. Recommended deployment topology

```text
                         Shared durable/control plane
                 ┌────────────────────────────────────┐
                 │ Coordination API and relay         │
                 │                                    │
                 │ - authenticated WSS connections    │
                 │ - node/session routing             │
                 │ - shared configuration revisions   │
                 │ - command authorization            │
                 │ - audit records                    │
                 └──────────────────┬─────────────────┘
                                    │
                                    ▼
                           ┌─────────────────┐
                           │ PostgreSQL      │
                           │ durable data    │
                           └─────────────────┘

         persistent outbound WSS                 persistent outbound WSS
                    │                                      │
                    ▼                                      ▼
┌──────────────────────────────────┐   ┌──────────────────────────────────┐
│ Coordinator host                 │   │ Remote worker host               │
│                                  │   │                                  │
│ UnifiedCombat node gateway       │   │ UnifiedCombat node gateway       │
│ - loopback addon hub             │   │ - loopback addon hub             │
│ - stable node identity           │   │ - stable node identity           │
│ - WSS connection and reconnect   │   │ - WSS connection and reconnect   │
│ - routing and local permissions  │   │ - routing and local permissions  │
│ - profile cache/materialization  │   │ - profile cache/materialization  │
│          │                       │   │          │                       │
│          │ local NDJSON          │   │          │ local NDJSON          │
│          ▼                       │   │          ▼                       │
│ Windower addon instances         │   │ Windower addon instances         │
│ - designated Lua coordinator     │   │ - remote puller workers          │
│ - optional local puller workers  │   │ - other local characters         │
│ - local schedulers               │   │ - local schedulers               │
└──────────────────────────────────┘   └──────────────────────────────────┘
```

### 5.1 The relay is not the pull coordinator

For the initial architecture, the relay routes authenticated messages between nodes and stores durable management data. It does not select mobs or allocate pull capacity.

The authoritative pull state machine remains in the configured Lua coordinator instance described by `RFC_PULLCOORD/pull_coordinator_rfc.md`.

This avoids maintaining the pull policy twice—once in Lua and once in a server implementation—and keeps local-only and multi-host sessions on the same coordinator logic.

### 5.2 The node gateway is not another scheduler

The node gateway owns transport and machine-level concerns:

- local addon connections;
- stable site/node identity;
- TLS/WSS connectivity;
- reconnection and resynchronization;
- configuration caching and file materialization;
- local command allowlists; and
- health reporting.

It does not:

- select targets;
- rank proposals;
- grant pull capacity;
- move characters;
- issue combat actions; or
- interpret ordinary scheduler behavior.

---

## 6. Coordinator transport contract

The coordinator state machine should be transport-neutral.

Recommended Lua boundary:

```lua
coord_transport.send(message)
coord_transport.on_message(message)
coord_transport.status()
coord_transport.request_snapshot()
```

Potential implementations:

- `ipc` for local-only coordinated sessions; and
- `bridge` for multi-host coordinated sessions.

### 6.1 One transport per session

A multi-host coordinated session should route all pull-coordinator protocol messages through the bridge path, including messages between characters on the coordinator's own machine.

This avoids:

- duplicate delivery through IPC and bridge;
- different ordering rules for local and remote workers;
- separate local and remote acknowledgement behavior;
- complex cross-transport deduplication; and
- local-only state that remote workers cannot reconstruct.

Existing unrelated Windower IPC features may remain unchanged.

### 6.2 Required identity

Messages require stable and runtime identity fields:

- `user_id` — authenticated human account;
- `site_id` — stable deployment or household identity;
- `node_id` — stable node-gateway installation identity;
- `character_key` — world/server plus character name;
- `instance_id` — one addon load lifetime;
- `coordination_session_id` — one shared operation; and
- `coordinator_epoch` — one authoritative coordinator lifetime.

Character name alone is not sufficient.

### 6.3 Required message envelope

Every coordination message should include:

```json
{
  "protocol": "uc.pullcoord.v1",
  "message_id": "playa-node:Bahamut:Puller:1842",
  "session_id": "shared-camp-01",
  "coordinator_epoch": "Bahamut:Redrogue:77",
  "sender": {
    "site_id": "playa-home",
    "node_id": "playa-node",
    "character_key": "Bahamut:Puller",
    "instance_id": "Puller:981223:1722547401"
  },
  "sequence": 1842,
  "type": "CANDIDATE",
  "payload": {}
}
```

The protocol must provide:

- unique message IDs;
- monotonically increasing sender sequences;
- explicit session and coordinator epoch;
- schema versioning;
- idempotent processing;
- duplicate suppression;
- stale-epoch rejection;
- bounded payload size;
- acknowledgements for grant-critical transitions; and
- a full snapshot/resync operation.

### 6.4 Clock handling

Do not compare process-relative or monotonic clocks between hosts.

Use:

- coordinator revisions for authoritative ordering;
- sender sequences for per-sender ordering;
- locally measured heartbeat age after receipt;
- duration-based local lease checks; and
- UTC timestamps only for audit and diagnostics.

A worker must never trust a remote wall-clock timestamp by itself as proof that a grant remains valid.

---

## 7. Coordinated pull flow

### 7.1 Candidate to grant

1. `uc_camp_puller` determines that local demand and action readiness allow a possible pull.
2. The worker selects a locally valid candidate using existing local policy.
3. Before acquiring outbound movement ownership, the worker sends `CANDIDATE`.
4. The coordinator validates session compatibility, worker eligibility, shared capacity, uniqueness, and fairness.
5. The coordinator creates an exclusive reservation.
6. The coordinator sends an authoritative `GRANT` containing the reservation and current snapshot revision.
7. The worker accepts only a grant addressed to its current character instance and candidate observation.
8. The worker revalidates the candidate locally.
9. The worker acknowledges the grant and enters the existing camp-puller journey.

A worker awaiting a grant has no dispatchable camp-puller proposal. The scheduler never blocks waiting for the network.

### 7.2 Journey progress

The worker reports typed transitions such as:

- `GRANT_ACKNOWLEDGED`;
- `APPROACH_STARTED`;
- `SETTLE_STARTED`;
- `ACTION_SENT`;
- `REACTION_OBSERVED`;
- `RETURNING`;
- `COMPLETED`;
- `FAILED_PRE_ACTION`; and
- `UNCERTAIN_POST_ACTION`.

The coordinator uses these reports to advance reservation state and publish authoritative snapshots.

### 7.3 Registry commit

`uc_camp_pull_registry.lua` currently allows each client to allocate its own next order, register a reacted mob locally, and broadcast the record over IPC.

That behavior cannot remain authoritative in coordinated mode.

In coordinated mode:

1. the worker reports reaction evidence;
2. the coordinator validates the active reservation;
3. the coordinator assigns the next global `pull_order`;
4. the coordinator creates the authoritative reacted-pull record; and
5. every worker installs that coordinator-authored record as replicated read-only state.

Legacy uncoordinated pulling retains the current behavior when coordination is disabled.

### 7.4 Reservation uncertainty

Once a pull action may have affected the mob, the slot cannot be released merely because a timer or connection expired.

Required rule:

- before action dispatch, an abandoned grant can normally be canceled safely;
- after `ACTION_SENT`, loss of evidence creates `UNCERTAIN` capacity;
- uncertain capacity remains counted until reaction, registry, authoritative recovery evidence, or explicit operator resolution determines the outcome; and
- reconnect does not silently recreate or discard post-action state.

---

## 8. Session compatibility requirements

A coordinated session should not enter `READY` until the coordinator has compatible reports for:

- FFXI world/server;
- zone;
- configured coordinator and puller membership;
- current addon instance identity;
- camp-anchor revision;
- shared-policy revision or signature;
- required profile revision/signature;
- party/alliance roster or stable roster signature; and
- coordinator transport health.

### 8.1 Party and alliance limitation

A shared pull queue is generally valid only when participating characters operate in the same friendly claim domain and are expected to fight the same mobs.

Two unrelated parties should not join one ordinary pull-coordination session. One party's claim may be foreign to the other, and UnifiedCombat's combat target ownership rules may correctly exclude it.

Separate parties require separate sessions, separate camps, or explicitly partitioned target populations.

### 8.2 Camp anchor as revisioned session state

For a multi-host session, the camp anchor should include:

- session ID;
- zone ID;
- X/Y/Z coordinates;
- setter identity;
- anchor revision;
- coordinator epoch; and
- optional camp label or reason.

A shared camp change flows through the coordinator/session state and is then consumed locally through the existing camp-anchor and movement logic.

---

## 9. Shared configuration model

### 9.1 Keep durable and runtime data separate

| Data class | Owner | Durable |
|---|---|---:|
| Character profile | Profile-v2 system | Yes |
| Shared session manifest | Coordination service | Yes |
| Runtime coordinator state | Lua coordinator | No |
| Temporary operational commands | Runtime, with durable audit only | No |

### 9.2 Character profile responsibilities

The existing profile-v2 file should contain durable local enrollment and permissions, for example:

```lua
config.combat.pulling.coordination = {
    enabled = true,
    session_id = 'shared-camp-01',
    transport = 'bridge',
    coordinator = false,
    puller = true,
    fail_closed = true,
    allow_remote_start_stop = true,
    allow_remote_reload = true,
    allow_remote_camp_change = true,
}
```

Exact field names should be finalized through `uc_config_normalizer.lua`, `uc_profile_contract.lua`, profile-v2 writer changes, replay tests, and UI updates.

### 9.3 Shared session manifest responsibilities

The shared manifest should contain facts that must have one durable revision:

- session ID and name;
- world/server;
- configured coordinator character key;
- allowed puller character keys;
- shared quota and early-replenishment policy;
- camp-anchor policy;
- shared target-policy requirements or canonical signature;
- party/alliance compatibility requirements;
- command permissions; and
- current manifest revision.

### 9.4 Applying a remote configuration revision

A safe application flow is:

1. an authorized operator submits a change;
2. the service validates schema, permission, and expected base revision;
3. the new revision is stored with author, reason, and prior revision;
4. the target node receives the revision;
5. the node writes a temporary profile-v2 file;
6. the node performs structural validation;
7. the node atomically replaces the normal local profile file;
8. the node invokes the existing profile-v2 reload path;
9. the addon reports the applied profile identity/signature; and
10. the service records success or failure.

The node retains the last known good file and supports rollback.

### 9.5 Outage fallback rules

Configuration and coordination have different fallback behavior:

- **Remote configuration unavailable:** continue using the last validated local profile.
- **Coordinator or coordination transport unavailable:** stop creating new coordinated pulls.

A coordinated puller must never silently degrade into independent pulling.

### 9.6 Conflict handling

Configuration updates use optimistic concurrency. Every update includes the expected base revision. If another operator has already changed the same record, the update is rejected or explicitly merged.

Silent last-write-wins behavior is not acceptable for shared coordinator, quota, roster, target-policy, or camp settings.

---

## 10. Node gateway and relay responsibilities

### 10.1 Headless node gateway

The current loopback hub lives inside WinForms. Production multi-host operation needs a process that can remain running when the configuration UI is closed, such as:

```text
UnifiedCombatNode.exe
```

Responsibilities:

- listen on loopback for addon sessions;
- maintain stable node identity and credentials;
- connect outbound to the relay over WSS;
- route coordination messages by session and character instance;
- enforce local command permissions;
- cache configuration revisions;
- atomically materialize profile files;
- expose node and addon health to WinForms;
- maintain bounded priority queues; and
- perform reconnect snapshot exchange before re-entering `READY`.

### 10.2 Relay/API service

The service owns:

- authentication;
- user, site, node, and character registration;
- active connection routing;
- session membership;
- authorization;
- durable manifests and profile revisions;
- command submission and result tracking;
- audit history; and
- optional web administration.

It does not allocate pull capacity in the first implementation.

### 10.3 Database

The database stores durable management state:

- users and trust relationships;
- node registrations and revocations;
- character identities;
- session manifests;
- profile/configuration revisions;
- command history and results; and
- audit records.

Runtime heartbeats, grants, and reservations stay in active coordinator/relay memory and are not synchronously persisted before every pull.

The database must not be placed on the pull-grant latency path.

### 10.4 Message priority and backpressure

The current unbounded outbound channel is unsuitable for grant-critical traffic.

Recommended priority order:

1. emergency stop, session end, and epoch changes;
2. grant, cancellation, action-sent, and reaction evidence;
3. heartbeat and worker state;
4. ordinary state snapshots and diagnostics.

Low-priority diagnostics may be coalesced or dropped. Grant-critical messages must either be delivered/acknowledged or force the session to fail closed.

---

## 11. Remote operational commands

Remote operations are useful but must remain typed, scheduler-safe, and explicitly authorized.

### 11.1 Safe initial command set

- request state;
- request diagnostics;
- stop engine;
- start engine;
- addon reload;
- profile-v2 reload;
- pause or resume coordinated pulling;
- set or clear the shared camp anchor; and
- cancel a pre-action reservation when the coordinator proves cancellation is safe.

### 11.2 Later commands

- request return to camp;
- change session enrollment;
- initiate a scheduler-owned relocation task;
- request a bounded diagnostic capture; and
- perform a reviewed stalled-worker recovery operation.

### 11.3 Command constraints

Every command must be:

- typed and allowlisted;
- authorized for the user and target site;
- targeted to an explicit node, character instance, or group;
- assigned a unique ID;
- expiring;
- idempotent where possible;
- acknowledged with result state;
- recorded in an audit log; and
- locally disableable.

No arbitrary shell, Lua, Windower console, or remote code-execution command should exist.

Commands that cause movement or actions must enter normal scheduler/provider ownership. The gateway must not directly call movement functions.

---

## 12. Failure and recovery behavior

### 12.1 Network or relay loss

- no new grants are valid;
- workers do not switch to independent pulling;
- pre-action grants are canceled when locally safe;
- post-action reservations remain uncertain;
- unrelated local scheduler providers may continue according to local configuration;
- cached durable configuration remains available; and
- a full snapshot/resync is required before new grants resume.

### 12.2 Coordinator addon loss or reload

- all workers fail closed for new pulls;
- no worker promotes itself;
- active post-action reservations remain uncertain;
- the old coordinator epoch becomes permanently stale;
- a restarted or replacement coordinator creates a new epoch; and
- the new epoch performs recovery from worker and registry snapshots before entering `READY`.

This is session recovery, not automatic failover.

### 12.3 Node gateway loss

- local addons detect bridge heartbeat loss;
- current multi-host grants become unusable according to reservation phase;
- remote commands and configuration delivery stop;
- the local engine may continue unrelated behavior if configured; and
- reconnect requires identity and session resynchronization.

### 12.4 WinForms loss

After the node gateway is extracted, closing WinForms has no runtime effect. Before extraction, multi-host support is only a proof of concept because the UI process owns the loopback hub.

### 12.5 Database loss

- existing relay connections may continue for a bounded period if authorization state is already loaded;
- no durable configuration or permission changes are accepted;
- coordinator authority does not change;
- no second coordinator is created; and
- service restart requires transport/session resynchronization.

---

## 13. Key implementation challenges and exceptions

### 13.1 Different world snapshots

Remote workers and the coordinator will not share identical entity state. Protocol messages must describe observations and authority, not pretend all clients possess one synchronized game snapshot.

### 13.2 Mob ID reuse

Mob IDs are zone-local and may be reused after despawn/respawn. A delayed grant must not authorize a newly spawned mob that happens to use the same numeric ID.

Reservations should include:

- zone ID;
- mob ID/index used by the action path;
- expected name;
- worker observation sequence;
- worker instance ID;
- reservation ID;
- coordinator epoch; and
- enough candidate metadata to identify the original observation.

Final local revalidation is still mandatory.

### 13.3 Message duplication and reordering

The transport must tolerate duplicate, delayed, and reordered messages. State changes must be idempotent and guarded by session, epoch, sender sequence, reservation state, and authoritative snapshot revision.

### 13.4 Bridge cadence

`remote_bridge.lua` currently emits ordinary state snapshots on an approximately 1.5-second cadence and reconnect attempts are separated by roughly two seconds. That is appropriate for UI monitoring but too slow and too implicit for pull grants.

Coordination requires event-driven messages and a dedicated lightweight heartbeat, while periodic full snapshots remain useful for recovery.

### 13.5 Config or session mismatch

A worker may reconnect with:

- a different main/sub-job profile;
- a stale profile revision;
- a different target-policy signature;
- a different zone;
- a different alliance roster;
- a different camp revision; or
- a new addon instance ID.

Any mismatch affecting shared pulling blocks grants with a specific diagnostic reason.

### 13.6 Runtime edits

Changes to coordinator identity, puller roster, quota, target policy, camp anchor, or session membership may invalidate active reservations.

Each setting requires an explicit application rule:

- reject while reservations are active;
- apply at the next idle boundary; or
- end the current epoch and restart the session.

Settings must not silently change the meaning of an existing grant.

### 13.7 Restarting stalled workers

A remote restart can worsen an uncertain pull if an action may already have been sent. Recovery should first inspect:

- current camp-puller phase;
- reservation state;
- last action evidence;
- current target and claim state;
- movement ownership;
- pending scheduler action; and
- heartbeat age.

The first implementation should prefer stop and diagnostic capture over automatic restart.

### 13.8 Security and trust

This system permits one operator to affect another person's game clients and configuration. Required controls include:

- TLS/WSS;
- unique revocable node credentials;
- authenticated users;
- explicit site-to-site trust grants;
- least-privilege command scopes;
- command expiration and replay protection;
- immutable audit records;
- local emergency stop;
- visible remote-control status; and
- no arbitrary code execution.

No other user receives authority over a site until that site owner explicitly grants it.

---

## 14. Proposed codebase boundaries

The following modules are a concrete implementation direction rather than existing files unless already present.

| Module/component | Responsibility |
|---|---|
| `uc_camp_pull_coordinator.lua` | Single coordinator/worker state machine from the approved RFC |
| `uc_coord_transport.lua` | Transport-neutral Lua facade |
| `uc_coord_transport_ipc.lua` | Local-only coordinator protocol transport |
| `uc_coord_transport_bridge.lua` | Multi-host coordinator protocol through the node gateway |
| `uc_camp_puller.lua` | Candidate proposal, grant gate, progress reports, reaction evidence, existing local journey |
| `uc_camp_pull_registry.lua` | Legacy independent mode plus coordinator-authored coordinated records |
| `uc_camp_anchor.lua` | Revisioned shared anchor consumption while retaining local-only mode |
| `uc_config_normalizer.lua` | Durable coordination enrollment and permission normalization |
| `uc_profile_contract.lua` | Profile-v2 coordination validation |
| `remote_bridge.lua` | Nonblocking local-node protocol transport and dispatch |
| Shared .NET transport library | Extract loopback session-hub behavior from WinForms |
| `UnifiedCombatNode` | Headless node gateway, WSS, identity, cache, commands, health |
| `UnifiedCombatWinForms` | Configuration and monitoring client, not required to remain open |
| Coordination API/relay | Authentication, routing, durable configuration, commands, audit |

The implementation should avoid duplicating coordinator policy in .NET or the API service.

---

## 15. Implementation sequence

### Phase 1 — Implement the approved coordinator locally

1. Implement the existing `RFC_PULLCOORD` state machine and invariants.
2. Preserve current single-puller behavior when coordination is disabled.
3. Add exclusive pre-action reservations.
4. Make coordinated registry writes single-authority.
5. Add deterministic recovery and uncertain-capacity behavior.
6. Build pure tests for capacity, fairness, ordering, duplicates, and stale epochs.

This phase should work entirely on one machine before any shared infrastructure is introduced.

### Phase 2 — Make coordinator transport neutral

1. Introduce the coordinator transport facade.
2. Implement the existing IPC transport through that facade.
3. Add message IDs, sequences, acknowledgements, and snapshot resync.
4. Prove that transport mechanics do not alter coordinator policy.

### Phase 3 — Route a local session through the bridge

1. Add coordination message types to `remote_bridge.lua` and the .NET hub.
2. Route all workers, including local workers, through the bridge transport.
3. Validate ordering, deduplication, reconnect, and backpressure on one machine.
4. Confirm WinForms lifecycle remains a known proof-of-concept limitation.

### Phase 4 — Add node gateways and one remote relay

1. Add stable node identity and authenticated WSS connections.
2. Keep one designated Lua coordinator.
3. Connect two physical hosts to one session.
4. Test with artificial latency, jitter, loss, duplication, and reconnect.
5. Prove that no duplicate grant or duplicate pull begins.

### Phase 5 — Extract the headless node process

1. Move the loopback hub and WSS client out of the WinForms lifecycle.
2. Preserve UI functionality through a shared interface.
3. Add node health, service/tray operation, and a local emergency stop.

### Phase 6 — Add shared configuration

1. Add versioned session manifests and profile revisions.
2. Add atomic local profile materialization.
3. Report applied profile signatures.
4. Add optimistic concurrency, rollback, and audit history.

### Phase 7 — Add remote operational commands

1. Start with read-only diagnostics and stop.
2. Add start, reload, and shared camp changes.
3. Add scheduler-owned relocation or recovery workflows only after field evidence supports them.
4. Require explicit per-site permissions for every command category.

---

## 16. Verification and acceptance

### 16.1 Coordinator tests

- two workers propose the same mob and only one receives a grant;
- two workers propose different mobs with one available slot;
- multiple open slots preserve quota and fairness;
- lower local latency does not defeat round-robin policy;
- stale epoch and stale instance messages are rejected;
- duplicate messages are idempotent;
- coordinator loss before action dispatch prevents the action;
- coordinator loss after action dispatch preserves uncertain capacity;
- mob ID reuse cannot revive an old grant;
- registry order is globally monotonic within the coordinator epoch and zone; and
- config, anchor, zone, or alliance mismatch blocks grants.

### 16.2 Transport chaos tests

Run the same scenarios with:

- 0, 100, 400, and 1,000 ms latency;
- jitter;
- dropped acknowledgements;
- duplicated and reordered messages;
- temporary disconnects;
- gateway restart;
- relay restart; and
- coordinator addon reload.

### 16.3 Configuration tests

- base-revision conflict rejection;
- invalid profile rejection;
- atomic replacement and rollback;
- applied-signature confirmation;
- last-known-good local operation during service outage;
- command permission denial; and
- complete audit records.

### 16.4 Initial field acceptance

The first live test should contain only:

- two physical hosts;
- one FFXI world;
- one zone;
- one party/alliance claim domain;
- one shared camp;
- one designated coordinator;
- one puller on each host;
- one shared capacity policy;
- visible coordinator and node logs;
- a controlled disconnect before action dispatch;
- a controlled disconnect immediately after action dispatch; and
- proof that no duplicate pull begins.

Remote configuration editing and movement operations should remain disabled until this test succeeds.

---

## 17. Success criteria

The architecture is successful when:

1. characters on multiple computers can join one authenticated coordination session;
2. exactly one configured Lua coordinator owns all grants;
3. every character retains its local scheduler and movement/action ownership;
4. a mob and capacity slot cannot be granted to two workers;
5. coordinator loss stops new pulling without causing independent fallback;
6. delayed or duplicated messages cannot revive stale authority;
7. remote latency does not materially interfere with normal pull throughput;
8. registry order remains globally consistent;
9. durable configuration can be safely shared, cached, revised, and rolled back;
10. remote commands are typed, authorized, audited, and locally disableable; and
11. coordination-disabled users retain current behavior.

---

## 18. Final architecture statement

UnifiedCombat multi-host support should be implemented as **multiple local execution nodes under one authoritative Lua coordinator**.

The coordinator owns shared decisions. Workers own local truth and local execution. Node gateways provide secure transport, identity, configuration caching, and command enforcement. The relay connects the nodes and stores durable management data, but it does not become a second combat engine.

This model is practical because remote latency is paid only when authorizing a new pull. It is safe because one component owns every grant and registry order. It aligns with the existing scheduler, camp-puller, pull-registry, bridge, and profile-v2 boundaries instead of replacing them.

The immediate milestone is:

> Implement the approved local single-coordinator state machine with a transport-neutral protocol, then prove that same authority model across two physical hosts through authenticated node gateways.
