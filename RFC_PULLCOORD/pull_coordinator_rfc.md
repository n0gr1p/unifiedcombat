# RFC: Coordinated Multi-Character Camp Pulling

Status: Approved architecture; implementation not started

Date: 2026-08-01

Scope: UnifiedCombat camp pulling, pull registry, scheduler integration,
profile-v2 configuration, IPC, runtime diagnostics, and WinForms UI

## 1. Summary

UnifiedCombat will support more than one character assigned to camp pulling by
introducing one explicitly configured pull coordinator and multiple puller
workers.

The coordinator will be the sole runtime authority for:

- shared pull demand and quota;
- early-replenishment admission;
- worker selection and fairness;
- exclusive mob reservations;
- coordinated pull session identity;
- authoritative reacted-pull registration; and
- global pull order.

Each puller will continue to own its existing local responsibilities:

- local spell or job-ability configuration;
- local action readiness;
- target filtering and cooldowns;
- approach, settle, and action dispatch;
- reaction observation;
- movement recovery and return to camp; and
- scheduler and movement-domain interaction.

The pull registry will remain the shared record of mobs that actually reacted.
Pull reservations will be separate coordinator state and will not turn into
combat targets until reaction is confirmed.

Coordinated mode will fail closed. A puller will never start or continue to
dispatch a new pull action without a current grant from the configured
coordinator. There will be no automatic leader election and no degradation to
independent pulling when coordinated mode is unavailable.

## 2. Current-state problem

The current pull registry shares reacted mobs across addon instances and makes
those mobs occupy quota and retain FIFO combat priority across claim turnover.
It does not coordinate pull attempts before reaction.

If camp pulling is enabled on more than one character today:

- every puller calculates demand independently;
- every puller can select a candidate before another pull is announced;
- two pullers can select or act on the same mob;
- simultaneous journeys can overshoot the shared quota;
- each addon instance allocates pull order from a local counter; and
- a registration received during another puller's in-flight journey can
  collide with that journey's later local registration.

IPC convergence after reaction is not sufficient to make simultaneous pulling
safe. Coordination must occur before movement and action dispatch.

## 3. Goals

The subsystem will:

- allow two or more explicitly assigned characters to pull concurrently when
  shared demand contains multiple open slots;
- prevent two pullers from receiving permission for the same mob;
- count in-flight reservations against shared quota;
- preserve the current one-extra-mob early-replenishment behavior;
- allocate one global, collision-free FIFO order to reacted pulls;
- permit different pullers to use different actions, target policies, and
  local cooldowns;
- preserve the current camp-puller journey and movement behavior;
- preserve the current pull-registry foreign-claim and orphan behavior;
- recover deterministically from duplicate, delayed, or reordered IPC;
- fail closed on coordinator, identity, zone, camp, or configuration mismatch;
  and
- expose enough state to diagnose every grant, rejection, transition, and
  recovery decision.

## 4. Non-goals

This RFC will not:

- use FFXI claim ownership as a pull assignment or reservation;
- use puller identity to assign combat roles or partner targets;
- elect a replacement coordinator automatically;
- coordinate addon instances outside the existing Windower IPC domain;
- replace the scheduler or movement coordinator;
- merge route hunting with camp pulling;
- persist pull sessions, reservations, or registry state into profiles; or
- change ordinary single-puller behavior when coordinated mode is disabled.

Combat-role assignment remains a separate concern. A registry record may
retain which character pulled the mob for diagnostics, but that metadata will
not tell the party who should fight it.

## 5. Required invariants

The following invariants are normative:

1. Exactly one configured character is coordinator for a coordinated session.
2. Only configured pullers may receive grants.
3. A puller may hold at most one nonterminal reservation.
4. A mob may be associated with at most one nonterminal reservation.
5. No worker may enter outbound pull movement without a valid grant.
6. No worker may dispatch a pull action unless that grant is still present in
   a current coordinator snapshot.
7. Every nonterminal reservation consumes shared capacity.
8. An action-sent reservation is never canceled only because a timer expired.
9. Only the coordinator may commit a coordinated reacted pull to the registry.
10. Every committed pull receives one globally unique, monotonically
    increasing `pull_order` within the coordinator session and zone.
11. Messages from a stale session epoch cannot change current state.
12. Coordinated mode never falls back to uncoordinated pulling.

A violation of these invariants is an implementation error and must fail fast
or block coordinated pulling with a specific reason. It must not be hidden by
alternate behavior.

## 6. Configuration contract

`config.combat.pulling` will gain a structured coordination object:

```lua
coordination = {
    enabled = false,
    coordinator_name = nil,
    puller_names = {},
}
```

Validation rules:

- `enabled` is a strict boolean.
- `coordinator_name` is required and nonempty when enabled.
- `puller_names` is a nonempty ordered list when enabled.
- Names are unique case-insensitively.
- A coordinator that also pulls must appear in `puller_names`.
- A coordinator that is not listed acts only as coordinator.
- All names must be valid IPC fields and therefore cannot contain `|`.
- Coordination remains default-off.

Shared policy consists of:

- coordinator name;
- ordered puller names;
- `max_active_mobs`; and
- `replenish_below_hpp`.

The coordinator broadcasts a canonical signature of these normalized fields.
Assigned workers must have the same shared-policy signature. A mismatch blocks
that worker with `PULL_COORD_CONFIG_MISMATCH`.

The following remain local worker policy and may differ by character:

- pull action type and name;
- target list, matching mode, and target priorities;
- leash and Z limits;
- cast-range ratio and settle timing;
- retry and reaction timing;
- target cooldown; and
- local scheduler/domain availability.

Coordination runtime state is session-owned. It must not be written into
profile files or treated as UI-owned durable state.

## 7. Runtime roles and ownership

### 7.1 Coordinator

The coordinator owns a zone-scoped session containing:

- session epoch;
- authoritative revision;
- shared-policy signature;
- current camp-anchor identity;
- assigned-puller runtime identities and availability;
- round-robin cursor;
- active reservation table;
- next reservation sequence;
- next registry pull order;
- recovery state; and
- the authoritative coordinated registry writer.

The coordinator may run on a non-puller character. Its combat state must not be
required for it to coordinate.

### 7.2 Puller worker

Each configured puller owns:

- its existing camp-puller provider state;
- local action readiness and resource resolution;
- local candidate selection;
- local movement and retry state;
- one accepted reservation, if any;
- coordinator-heartbeat freshness; and
- outbound progress and reaction reports.

The worker proposes candidates. It does not reserve them locally and it does
not calculate authoritative shared demand.

### 7.3 Pull registry

In coordinated mode, the registry stores only reacted-pull lifecycle records.
Reservations remain coordinator-owned and are not registry records.

Coordinated registry records will additionally retain:

- coordinator epoch;
- reservation ID; and
- source puller name and runtime ID.

These fields are diagnostic provenance. Combat eligibility and priority remain
based on live mob state, registry lifecycle state, and global `pull_order`.

### 7.4 Scheduler and movement coordinator

The existing scheduler, dispatcher, action-state handling, camp-puller
movement reservation, breadcrumbs, and return recovery remain authoritative
for local execution. The pull coordinator grants permission; it does not issue
movement or combat commands on another character's behalf.

## 8. Coordinator and reservation states

### 8.1 Coordinator session states

- `DISABLED`: coordination is not enabled.
- `WAIT_IDENTITY`: configured identity cannot yet be resolved.
- `RECOVERING`: a new epoch is collecting and validating peer state.
- `READY`: the coordinator may grant reservations.
- `BLOCKED`: conflicting or invalid state prevents grants.
- `ENDING`: the session is shutting down or zoning.

Only `READY` may create grants.

### 8.2 Worker availability states

- `OFFLINE`: no current valid heartbeat.
- `INELIGIBLE`: identity, zone, anchor, configuration, engine, or domain check
  failed.
- `READY`: locally able to pull and has a current candidate proposal.
- `NO_CANDIDATE`: otherwise ready but no local candidate exists.
- `RESERVED`: owns a nonterminal reservation.
- `RETURNING`: committed or released and returning to camp.

### 8.3 Reservation states

- `GRANTED`: coordinator created the reservation.
- `ACKNOWLEDGED`: worker accepted and revalidated it.
- `APPROACH`: worker began outbound movement.
- `SETTLE`: worker is preparing to dispatch.
- `ACTION_SENT`: pull action was dispatched.
- `WAIT_REACTION`: action succeeded and reaction evidence is pending.
- `UNCERTAIN`: an action may have affected the mob but outcome is unresolved.
- `COMMITTED`: reaction was validated and registry ownership transferred.
- `CANCELLED`: no action may have affected the mob and the reservation ended.

`COMMITTED` and `CANCELLED` are terminal. Terminal reservations may remain in
diagnostic history for a bounded interval but do not consume capacity.

## 9. Shared demand and capacity

Only the coordinator calculates shared capacity.

Definitions:

- `active_count`: live mobs for which the pull registry reports
  `quota_eligible`.
- `pending_count`: reservations in any nonterminal state, including
  `UNCERTAIN`.
- `low_hpp_active`: at least one active mob has HPP less than or equal to
  `replenish_below_hpp`.

The permitted total is:

- `max_active_mobs` normally; or
- `max_active_mobs + 1` only when `active_count >= max_active_mobs` and
  `low_hpp_active` is true.

Available grants are:

`max(0, permitted_total - active_count - pending_count)`

Consequences:

- Multiple missing base slots may be granted to different pullers.
- At most one early-replenishment reservation may exist beyond a full stack.
- An uncertain action continues consuming capacity.
- A currently foreign-claimed registry mob follows existing quota semantics
  and does not occupy active quota while that foreign claim remains.
- No worker may independently reinterpret or expand coordinator demand.

## 10. Worker selection and candidate arbitration

Each eligible worker advertises its best locally eligible candidate without
starting a journey. Candidate selection retains the existing deterministic
worker-local order:

1. configured target priority;
2. camp distance; and
3. entity ID.

For each available grant, the coordinator:

1. walks the configured puller list from the round-robin cursor;
2. skips workers that are offline, ineligible, already reserved, or have no
   candidate;
3. validates the proposed mob against its own live snapshot;
4. rejects a mob that is tracked or reserved;
5. creates the reservation atomically in coordinator state;
6. advances the round-robin cursor only after a grant; and
7. broadcasts the authoritative reservation snapshot.

If two workers propose the same mob, only the selected worker receives it. The
other worker waits for the reservation broadcast, excludes that mob, and
proposes its next local candidate. The coordinator does not invent a target on
the worker's behalf.

Coordinator-side candidate checks must include live, valid monster, full HP,
idle status, zero claim, matching zone, and not tracked/reserved. The worker
repeats all local eligibility checks before accepting the grant and again
immediately before action dispatch.

## 11. IPC protocol

The protocol will use a new versioned namespace and will not overload the
current registry-v1 messages.

Canonical envelope:

`uc_pull_coord_v1|TYPE|ZONE|EPOCH|SEQUENCE|SENDER_ID|SENDER_NAME|PAYLOAD...`

Every message parser must strictly validate field count, numeric fields,
identity, zone, epoch, and delimiter safety.

Required operations:

- `SESSION`: coordinator identity, shared-policy signature, anchor identity,
  and heartbeat.
- `SNAPSHOT`: authoritative coordinator revision, reservations, puller states,
  and registry ordering metadata.
- `PULLER_STATUS`: worker identity, availability, local phase, and candidate.
- `GRANT`: exclusive reservation creation.
- `GRANT_ACK`: worker acceptance or explicit rejection.
- `PROGRESS`: worker reservation-phase transition.
- `REACTED`: worker-provided reaction evidence.
- `RELEASE`: pre-action cancellation request and evidence.
- `UNCERTAIN`: report that an action may have affected the mob.
- `SYNC_REQUEST`: new coordinator epoch requests retained state.
- `SYNC_RESPONSE`: peer registry and in-flight state for recovery.
- `SESSION_END`: graceful coordinator shutdown or zone transition.

Protocol rules:

- Coordinator operations carry a monotonically increasing authoritative
  revision.
- Worker messages carry a monotonically increasing worker sequence.
- Duplicate messages are idempotent.
- Older revisions or sequences cannot overwrite newer state.
- Messages from a different zone or stale epoch are consumed but rejected.
- A worker accepts grants only from its configured coordinator's current
  runtime identity.
- The coordinator accepts worker messages only from configured names resolved
  inside the current friendly party/alliance scope.
- A periodic full snapshot repairs missed incremental messages.

## 12. Grant and execution flow

1. The coordinator reaches `READY` and broadcasts `SESSION` plus `SNAPSHOT`.
2. A worker in local `IDLE` calculates its best candidate and sends
   `PULLER_STATUS`.
3. The coordinator calculates capacity and chooses the next worker.
4. The coordinator creates `GRANTED`, consumes capacity, and broadcasts it.
5. The worker verifies coordinator freshness, reservation identity, mob state,
   camp anchor, local action readiness, and local domains.
6. The worker sends `GRANT_ACK` and may enter its existing `APPROACH` state.
7. Existing approach, stop, settle, and action-dispatch behavior runs locally.
8. Each meaningful phase change sends `PROGRESS`.
9. Immediately before dispatch, the worker confirms that a current coordinator
   snapshot still contains its reservation.
10. After dispatch, the worker reports `ACTION_SENT`; this is the point after
    which timeout alone cannot cancel the reservation.
11. When live reaction evidence appears, the worker sends `REACTED`.
12. The coordinator validates the live mob and assigns the next global
    `pull_order`.
13. The coordinator commits and broadcasts the registry record, then marks the
    reservation `COMMITTED`.
14. The worker returns to camp and does not advertise availability until its
    local journey and movement reservation are complete.

## 13. Registry authority and ordering

Coordinated mode introduces a single-writer rule:

- only the coordinator may create, update, or remove authoritative coordinated
  registry records;
- workers and combat consumers install coordinator registry messages but do
  not rebroadcast derived transitions;
- workers may send observations to the coordinator; and
- the coordinator validates those observations against its live mob view.

The coordinator assigns `pull_order` when a reacted reservation is committed,
not when a candidate is proposed or granted. This preserves the existing
meaning that order belongs to a mob that actually reacted and avoids gaps from
canceled reservations.

If two reactions arrive in the same scheduler interval, coordinator processing
order defines the total order. The resulting values remain unique and
monotonic.

The existing registry lifecycle remains normative:

- `ACTIVE_PULL`
- `FOREIGN_CLAIMED`
- `ORPHANED_HOSTILE`
- `FORFEITED_IDLE`
- `ENDED`

Reservations do not add a `RESERVED` registry state.

## 14. Failure semantics

### 14.1 Before action dispatch

A grant may be canceled only when no pull action could have affected the mob.
Examples include:

- worker rejects the grant during validation;
- candidate becomes claimed, engaged, damaged, dead, invalid, or out of local
  policy before dispatch;
- worker loses coordinator heartbeat during approach or settle;
- worker engine or required domain is disabled;
- worker dies or zones before dispatch; or
- pre-action grant acknowledgement/progress expires.

Cancellation releases capacity and the worker stops and returns as needed.

### 14.2 After action dispatch

After `ACTION_SENT`, silence or timeout cannot prove that the mob was untouched.
The reservation becomes `UNCERTAIN` when confirmation is lost.

An uncertain reservation:

- continues consuming shared capacity;
- keeps its mob excluded from new candidate selection;
- cannot be assigned to another puller; and
- resolves only from authoritative live evidence.

Resolution rules:

- hostile, damaged, or friendly-claimed live mob: commit as a reacted pull;
- foreign-claimed live mob: commit into the existing foreign-claim lifecycle;
- full-HP, idle, unclaimed live mob with authoritative post-action evidence:
  cancel; and
- insufficient or conflicting evidence: remain uncertain and block capacity.

### 14.3 Coordinator loss

- Before dispatch, workers stop and cancel locally pending work after the
  coordinator session becomes stale.
- After dispatch, workers preserve and report uncertain state.
- No worker starts another pull.
- No alternate character promotes itself to coordinator.

### 14.4 Worker loss

- A pre-action reservation may be canceled after the coordinator validates
  that the mob remains untouched.
- An action-sent reservation becomes uncertain.
- The round-robin scheduler may use other available workers for remaining
  capacity, but uncertain capacity remains occupied.

## 15. Recovery and session epochs

The coordinator creates a new zone-scoped epoch on initial startup, reload, or
zone transition. A new epoch begins in `RECOVERING` and cannot grant pulls.

Recovery flow:

1. Broadcast `SYNC_REQUEST`.
2. Collect peer registry snapshots and nonterminal reservation reports.
3. Reject stale-zone and malformed records.
4. Reconcile records by mob ID, registry order, prior epoch, and live mob
   evidence.
5. Preserve committed registry entries that remain live.
6. Convert prior action-sent work to `UNCERTAIN` until resolved.
7. Cancel prior unacted grants only after verifying the mob is untouched.
8. Set the next pull order above every accepted retained order.
9. Enter `READY` only when the reconstructed state is internally consistent.

Conflicting registry order, incompatible live evidence, or incompatible peer
snapshots moves the session to `BLOCKED`. The coordinator exposes the exact
conflict and requires an explicit coordinator reset or state resolution.

An explicit reset is a runtime administrative action. It must not silently
discard a live, hostile, damaged, claimed, or uncertain mob. If such evidence
exists, reset is refused with a specific reason.

## 16. Lifecycle resets

Zone change, logout, unload, player death, engine stop, and feature disable must
have explicit coordinator and worker behavior.

- Zone change ends the old epoch and clears zone-scoped reservations.
- Logout and unload attempt a graceful `SESSION_END` or worker status update,
  but correctness must not depend on receiving it.
- Engine stop or feature disable prevents new grants immediately.
- A worker already returning to camp emits the required local stop before
  releasing movement ownership.
- Action-sent ambiguity remains uncertain until resolved; it is not erased by
  a local provider reset.
- Durable configuration remains unchanged by runtime resets.

## 17. Compatibility

Coordination is default-off.

When disabled:

- the existing single-puller state machine remains active;
- current registry-v1 behavior remains available;
- no coordinator heartbeat or grant is required; and
- existing profiles require no migration.

When enabled:

- direct independent pull admission is prohibited;
- direct worker allocation of registry order is prohibited;
- coordinated registry messages use their new protocol namespace; and
- coordinator unavailability blocks pulling instead of invoking legacy mode.

No public command or configuration key will be removed during the initial
implementation.

## 18. Observability and commands

`//uc camp pullstatus` will add local worker fields:

- coordination enabled;
- configured coordinator;
- coordinator epoch and heartbeat age;
- worker eligibility;
- proposed candidate;
- reservation ID, mob, and phase;
- grant revision;
- last worker sequence; and
- current coordination block reason.

A coordinator-focused status command will report:

- coordinator session state, epoch, zone, and revision;
- camp-anchor identity;
- shared-policy signature;
- active, pending, uncertain, and available capacity;
- configured pullers and their current availability;
- round-robin cursor and last granted puller;
- every reservation's puller, mob, phase, and age;
- next global pull order; and
- recovery conflicts.

Minimum reason families:

- `PULL_COORD_DISABLED`
- `PULL_COORD_WAIT_IDENTITY`
- `PULL_COORD_RECOVERING`
- `PULL_COORD_BLOCKED`
- `PULL_COORD_UNAVAILABLE`
- `PULL_COORD_STALE`
- `PULL_COORD_CONFIG_MISMATCH`
- `PULL_COORD_ZONE_MISMATCH`
- `PULL_COORD_ANCHOR_MISMATCH`
- `PULL_COORD_NOT_ASSIGNED`
- `PULL_COORD_NO_CAPACITY`
- `PULL_COORD_NO_CANDIDATE`
- `PULL_COORD_RESERVED`
- `PULL_COORD_GRANT_REJECTED`
- `PULL_COORD_RESERVATION_UNCERTAIN`
- `PULL_COORD_RECOVERY_CONFLICT`

Every coordinator state transition, reservation transition, grant decision,
and registry commit will be available to the existing action-timeline logging
surface with stable reason codes.

## 19. Module boundaries

Planned runtime ownership:

| Module | Responsibility |
| --- | --- |
| `uc_camp_pull_coordinator.lua` | Pure coordinator/worker protocol state, capacity, fairness, reservation lifecycle, recovery |
| `uc_camp_puller.lua` | Existing local journey plus worker proposal, grant gate, and progress reporting |
| `uc_camp_puller_policy.lua` | Existing local candidate and live demand helpers; shared demand gains a coordinator-owned pure calculation |
| `uc_camp_pull_registry.lua` | Reacted-pull lifecycle, coordinator-authored coordinated records, global order consumption |
| `UnifiedCombat.lua` | One IPC event route and operator commands |
| `unified_scheduler.lua` | Dependency wiring and existing local dispatch/movement integration only |
| `uc_config_normalizer.lua` | Strict coordination configuration contract |
| `uc_profile_v2.lua` | Durable coordination settings, excluding runtime session state |
| WinForms profile/UI files | Offline editing, validation, and runtime status display |

The scheduler must not absorb coordinator policy. The coordinator module must
not issue local movement or action commands.

## 20. Acceptance criteria

The architecture is complete only when all of the following are demonstrated:

- two pullers can fill two empty quota slots without selecting the same mob;
- two same-mob proposals result in one grant and no duplicate action;
- in-flight reservations prevent quota overshoot;
- a full stack with a low-HP mob admits exactly one replenishment pull;
- simultaneous reactions receive unique FIFO orders;
- coordinator loss before dispatch produces no pull action;
- coordinator or worker loss after dispatch preserves uncertain capacity;
- stale, duplicate, delayed, and reordered IPC cannot corrupt state;
- coordinator reload reconstructs consistent live state before granting;
- foreign-claim and orphaned-hostile registry behavior is unchanged;
- single-puller coordination-disabled behavior remains unchanged;
- partner target separation remains independent of puller provenance; and
- field testing confirms multiple physical journeys, reactions, and returns
  under live Windower/FFXI timing.

