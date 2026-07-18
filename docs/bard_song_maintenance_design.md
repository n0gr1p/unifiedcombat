# UnifiedCombat Bard Song Maintenance Design

## Status

This document records the design contract implemented by the dedicated Bard enhancing-song maintenance subsystem.

The initial implementation is in `uc_brd_maintenance.lua`, with scheduler ownership under provider `maintenance_brd` and UI-owned durable policy under `config.maintenance.brd`.

The game-mechanics reference is `docs/RefDocs/FFXI_Bard_Song_Overwrite_Logic_Specification.md`. This document defines how UnifiedCombat will apply those mechanics while preserving the addon's scheduler and profile ownership boundaries.

## Goals

The subsystem will:

- maintain configured beneficial Bard songs for their intended recipients;
- prevent maintained songs from expiring whenever execution conditions permit;
- preserve exact song identity when multiple songs share one status-effect family;
- use server-observed song expiration state instead of durable duration estimates;
- refresh every configured song after UnifiedCombat activates Nightingale and Troubadour;
- support assigning Marcato to one exact configured song;
- operate as a scheduler maintenance provider without direct action loops;
- expose Bard-specific durable choices in a dedicated UI tab;
- preserve non-song defensive maintenance behavior.

## Non-goals

The initial implementation will not:

- make song duration, expiration, active slots, confidence, or target IDs durable profile data;
- estimate durable song duration from equipment configuration;
- support targeted beneficial songs in the initial implementation;
- control enemy-targeted Bard debuffs;
- model uncontrolled multi-Bard song interaction as deterministic;
- bypass scheduler locks, pending-action handling, cooldown checks, or action arbitration;
- start the engine automatically;
- replace `defensive_internal` for cures, status removal, or non-song defensive buffs;
- write runtime song state to the v2 profile or `_G.UC_ACTIVE_PROFILE`.

## Architectural Decision

Beneficial Bard songs will have one runtime owner: a dedicated Bard maintenance module, proposed as `uc_brd_maintenance.lua`.

The scheduler provider will be distinct from `defensive_internal`, proposed as `maintenance_brd`.

The provider will:

1. Read durable Bard intent from `_G.UC_ACTIVE_PROFILE` through the active-config API.
2. Read addon-owned party, recast, buff, packet, pending-action, and lock state.
3. Return at most one side-effect-free proposal per scheduler evaluation.
4. Let the existing scheduler rank, dispatch, confirm, reject, and retry the action.
5. Update Bard runtime ownership only after confirmed action and packet evidence.

The provider must not send commands directly, sleep, poll in a blocking loop, or maintain a second action dispatcher.

### Existing-system replacement boundary

The current Bard-specific song logic is insufficient as the final implementation because it:

- routes configured songs through generic defensive buff maintenance;
- collapses exact songs into shared status families;
- estimates expiration from a configured overwrite interval;
- records exact identity with a bounded recent-success heuristic;
- contains a scheduler `maintenance_songs` placeholder without a complete Bard dispatch path.

Implementation may remove or replace those Bard-specific portions after equivalent dedicated-provider coverage exists.

It must not remove or bypass required `defensive_internal` initialization or non-song behavior. The migration boundary is Bard enhancing songs only.

## UI Design

The WinForms UI will have a dedicated Bard maintenance tab.

The tab will be visible when either:

- the profile main job is `BRD`; or
- the profile support job is `BRD`.

Controls that require unavailable job abilities must be disabled or omitted according to the selected profile's actual job capability. The tab itself remains available for main-job and support-job Bard song selection.

The tab will own durable user intent such as:

- whether Bard song maintenance is enabled;
- the ordered list of exact beneficial songs to maintain;
- the ordered list of exact dummy songs used to build additional-song capacity;
- whether UnifiedCombat should use Nightingale and Troubadour as NITRO;
- whether UnifiedCombat should use Clarion Call where the configured song count requires it;
- whether Marcato is enabled;
- the exact configured song assigned to Marcato.

The UI will not expose or serialize expected duration, current duration, expiration timestamps, active song slots, current JA buffs, recast timers, packet confidence, or runtime entity IDs.

As with all durable controls, editing the Bard tab remains local until Save. Save writes files only. The addon consumes the saved profile through manual reload, startup autoload, or opt-in file-change auto-reload.

## Durable Profile Ownership

The v2 profile owns desired policy, not observed game state.

A conceptual durable shape is:

```lua
config.maintenance.brd = {
    enabled = true,
    songs = {
        "Honor March",
        "Victory March",
        "Valor Minuet V",
        "Valor Minuet IV",
    },
    dummy_songs = {
        "Army's Paeon",
        "Army's Paeon II",
    },
    use_nitro = true,
    use_clarion_call = true,
    use_marcato = true,
    marcato_song = "Honor March",
}
```

This shape is illustrative. The initial dedicated subsystem supports one general area-song list and one dummy-song list. Targeted song assignments are deferred and must not complicate the initial schema or runtime model.

Durable song identity must use exact canonical spell names or IDs. A family name such as `March`, `Minuet`, or `Ballad` is not sufficient durable identity.

Dummy songs are durable user intent because the user and GearSwap coordinate which exact songs equip the required capacity instrument. Dummy-song durations, active state, and resulting capacity remain runtime-owned.

## Runtime Ownership

The addon owns all live song state.

Runtime state includes:

- exact active song ownership per recipient;
- status-effect family and status ID;
- observed server expiration time;
- remaining duration derived from server time;
- application timestamp and source cast sequence;
- active song count and inferred capacity state;
- whether Clarion Call capacity is currently active or persisted;
- NITRO readiness and active state;
- current NITRO refresh generation;
- Marcato readiness, active state, and exact-song reservation;
- runtime recipient IDs;
- packet confidence and invalidation reason;
- pending, attempted, confirmed, failed, and rejected actions.

None of this state belongs in `_G.UC_ACTIVE_PROFILE` or durable profile diff/status.

## Authoritative Duration Source

Song duration is game state and is addon-owned.

UnifiedCombat already receives local-player status packet `0x063`. Its type-9 payload contains up to 32 buff IDs and corresponding server expiration times. `uc_scheduler_status_snapshot_parser.lua` currently parses these expiration times into per-status-ID `endtimes` arrays.

The expiration value is an absolute server endtime. Remaining duration is derived at runtime:

```text
remaining = observed_server_endtime - current_server_time
```

The observed endtime automatically incorporates the actual result of:

- the song used;
- the equipment and instrument present when the effect resolved;
- song-duration equipment;
- Troubadour;
- Marcato-related modifiers;
- Clarion Call-related modifiers;
- any other server-applied duration effect.

The durable profile must not contain an expected duration or duration formula. The provider must not overwrite authoritative packet state with a configured default duration.

### Party packet limitation

Party status packet `0x076` exposes party-member buff IDs but does not expose their expiration times.

Therefore:

- the local Bard's `0x063` endtimes are authoritative for the Bard;
- recipient ownership is established from confirmed targets of serialized outgoing casts;
- a recipient must not be marked as receiving a song without successful target evidence;
- a locally observed endtime from the same successful area cast may be associated with confirmed recipients because it represents that serialized cast;
- unknown or contradictory recipient timing must lower confidence rather than invent a duration.

The initial implementation supports general area songs only. Targeted songs that do not affect the Bard are deferred to a possible future enhancement, so they do not require a timing solution in this design.

## Exact Song Identity Mapping

Several exact songs share one game status-effect family. For example, multiple Marches may appear as duplicate instances of one March status ID.

UnifiedCombat will recover exact ownership by correlating one serialized song cast with before/after status snapshots.

### Mapping sequence

For every dispatched enhancing song:

1. Capture the pre-cast multiset of endtimes for the incoming song's status family.
2. Record the exact pending spell, intended recipients, and a unique cast sequence.
3. Wait for confirmed action success.
4. Wait for the next applicable `0x063` status snapshot.
5. Compare the family's before/after endtime multisets.
6. Assign the newly added or changed endtime to the exact song just cast.
7. If one prior endtime disappeared, remove or replace its previous exact-song owner.

Packet snapshots can shift an unchanged raw endtime by a few ticks as the remaining duration is encoded again. Identity correlation therefore pairs before/after observations within one server-second before classifying unmatched values as a real addition or replacement. A paired owner adopts the newest observed raw endtime; exact numeric equality across snapshots is not an identity requirement.

The raw `0x063` endtime uses the FFXI server timeline at 60 ticks per second. The provider begins with Windower's established epoch-derived offset, then calibrates its runtime offset from `Timestamp` and `Time offset?` in incoming `0x037` packets. Song identity correlation remains in raw packet units; remaining duration is `(endtime - (unix_time - server_offset) * 60) / 60`. The calibrated offset and its source are runtime state and are never durable configuration.
8. Update only recipients with confirmed successful target evidence.

Because the scheduler serializes actions, only one UnifiedCombat song can be responsible for the expected status change.

### Area-cast recipient evidence

UnifiedCombat already receives the complete parsed `0x028` action structure through `ActionPacket.open_listener(...)` in `UnifiedCombat.lua` and forwards it to `scheduler.on_action(act)`.

For an area song, that structure contains:

- the local Bard as `act.actor_id`;
- the action category and exact spell ID in `act.param`;
- every affected candidate in `act.targets[]`;
- one or more per-target result records in `target.actions[]`;
- the message and parameter associated with each target result.

The dedicated Bard provider will use the local actor ID, pending exact spell ID, action category, and each target's result message to construct the canonical successful-recipient set. Presence in `act.targets[]` alone is not success; the per-target action result must be classified as a successful song-effect application.

The exact accepted success-message set must be locked down with captured song fixtures. Windower's installed action-message catalog identifies gain-effect messages such as `205`, `230`, `266`, and `280`, while message `17` means `Unable to cast spells at this time`.

The current Bard heuristic in `scheduler.handle_local_spell_effect_observation(...)` treats `message_id == 17` and `message_param == 0` as success and then prefers one expected target ID. That path is not a valid recipient or success contract and must not be reused by the dedicated provider.

Individual `0x029` messages may supplement diagnostics, but `0x028` is the canonical per-cast recipient transaction so one area cast is not reconstructed from loosely related chat events.

### Cast-to-status confirmation transaction

The screenshot and live behavior show cast completion and recipient buff gains in the same displayed second. The implementation therefore does not need an arbitrary multi-second song delay.

Packet ordering can still place the local `0x063` snapshot immediately before or after the cast-complete observation. Correlation will be transaction-based:

1. Capture the local pre-cast family snapshot at dispatch.
2. Open one pending song transaction keyed by scheduler action token and exact spell ID.
3. Retain applicable `0x063` snapshots received after dispatch, even if one arrives before cast-complete handling.
4. On successful `0x028` completion, consume an already-observed matching delta or wait for the next matching `0x063` delta.
5. Do not dispatch another Bard song until the transaction is resolved or explicitly timed out.
6. On timeout without a relevant delta, record no timer ownership and expose the failure diagnostically.

Confirmation timeout is phase-aware. A dispatched command has two seconds to produce its category-8/message-327 song-start evidence. An observed cast waits for successful completion or interruption, with a twenty-second exceptional watchdog for a lost terminal packet. A successful category-4 result then starts a fresh two-second window for the corresponding `0x063` timer change. Cast time must never consume the snapshot-confirmation window.

Local action-message `17` or `18` (`Unable to cast spells at this time.`) is a terminal pre-start rejection when the current scheduler token belongs to `maintenance_brd` and no cast-start packet has arrived. The scheduler immediately releases action state as `server_reject_unable_cast`, marks its pending record failed, preserves the existing maintenance throttle with a minimum 0.75-second retry backoff, and tells the provider to discard the unstarted transaction without creating ownership.

The silent two-second start timeout and exceptional casting watchdog publish the same scheduler-owned failure transition with outcomes `start_timeout` and `cast_terminal_timeout`. This releases stale action state, marks scheduler pending failed, and preserves retry backoff rather than merely clearing provider-local pending state.

The bounded scheduler pending/confirmation transaction is the safe window. The implementation should measure actual high-resolution packet deltas with the one-shot trace diagnostic before assigning its timeout constant; it must not infer correctness from chat's one-second timestamp resolution alone.

### Expected transitions

- Adding a song introduces one new family endtime.
- Exact-refreshing a song replaces that exact song's old endtime with a new endtime.
- Casting a different song at full capacity removes the uniquely shortest prior endtime and introduces the incoming song's endtime.
- Casting a different song when capacity is available adds the incoming song without removing an existing owner.

### No-evidence and ambiguity rules

- If a confirmed cast produces no relevant timer change, the runtime must not claim a new expiration or ownership transition.
- If multiple unrelated family changes occur in one observation window, the state becomes ambiguous.
- If two possible overwrite victims cannot be distinguished, the provider must not guess.
- General-song ownership and completion are anchored to the Bard's own successful recipient result and local `0x063` timer transition. Other area-cast recipients are retained as runtime evidence, but party roster members are not mandatory completion targets because they may be dead, out of zone, or out of song range.
- External Bard casts, dispels, K.O., zoning, party changes, missed range, and conflicting packet evidence invalidate or downgrade affected ownership.
- Ambiguous state transitions to an explicit unknown/reconstruction state; it does not silently fall back to generic-family assumptions.

## Never-Expire Invariant

The primary steady-state invariant is:

> A maintained desired song should be exact-refreshed before its observed server expiration whenever action eligibility and game conditions permit.

The provider will calculate a runtime refresh deadline from observed state:

```text
refresh_deadline =
    observed_endtime
    - current_cast_requirement
    - scheduler_and_action_delay
    - packet_confirmation_allowance
    - retry_allowance
```

The safety allowance is addon execution policy, not durable song duration. It should be derived or centrally defined by the provider rather than exposed as an expected-duration profile setting.

Normal maintenance refreshes as late as safely possible. An imminent expiration outranks optional efficiency work.

The provider must continue respecting movement, action, recast, range, target, pending-action, zoning, and scheduler locks. "Never expire" is a planning invariant, not permission to bypass action safety.

## NITRO Design

Nightingale and Troubadour are one UI and durable-policy option named NITRO.

```lua
use_nitro = true
```

They are not independent automatic options.

### Readiness

NITRO is ready only when both job abilities are off cooldown:

```text
nitro_ready =
    nightingale_recast == 0
    and troubadour_recast == 0
```

The provider must not automatically use only whichever half is ready.

NITRO is active only when both resulting buffs are observed:

```text
nitro_active =
    nightingale_buff_present
    and troubadour_buff_present
```

Cooldown state must not be treated as proof that the buffs are active.

### Activation sequence

The scheduler sequence is:

1. Propose Nightingale.
2. Confirm Nightingale activation.
3. Propose Troubadour.
4. Confirm Troubadour activation.
5. Confirm both NITRO buffs are active.
6. Start a runtime forced-refresh generation.

If one activation fails, the provider does not claim active NITRO. It may retry the missing activation while the first buff remains valid, subject to normal scheduler rules.

### Forced full refresh

Once UnifiedCombat activates NITRO, it must re-sing every configured desired song even if that song is not approaching expiration.

This deliberately trades a small amount of immediate casting efficiency for the much larger benefit of applying Troubadour-enhanced duration to the full maintained set.

The forced-refresh generation records every desired exact song as pending for each intended recipient. During the generation:

- current long remaining duration does not suppress the forced proposal;
- every configured desired song remains incomplete until it receives one confirmed refresh for its required recipient set;
- a successfully completed song is not redundantly refreshed again during the same generation;
- successful casts receive newly observed runtime endtimes;
- failed or rejected casts remain incomplete while the NITRO window permits retry;
- configured song order is the default batch order, but expiration safety and documented capacity recovery may promote a song without changing its durable order;
- the generation completes when all required songs are confirmed or the NITRO window ends.

After the generation, the provider returns to ordinary observed-deadline maintenance.

### NITRO safety precedence

The provider must not allow a song to expire merely to wait for NITRO readiness. If a song reaches its safety deadline before both abilities are ready, normal exact refresh proceeds without NITRO.

## Marcato Design

Marcato is assignable to one exact configured song, analogous to assigning Crooked Cards to a configured COR roll.

The durable identity is the exact song name, not a list index:

```lua
use_marcato = true
marcato_song = "Honor March"
```

An exact name is stable when the user reorders the song list. Validation must require the selected Marcato song to exist in the configured desired-song set.

### Marcato with NITRO enabled

When both Marcato and NITRO are enabled:

- Marcato may be activated only while both NITRO buffs are active;
- the provider must not use Marcato merely because NITRO is off cooldown;
- Marcato may be activated only when its configured song is dispatch-ready and the reservation can be completed safely;
- Marcato must not be activated when doing so would force another maintained song across its safety deadline;
- Marcato is proposed immediately before its configured song in the NITRO refresh generation;
- a runtime reservation prevents any other Bard song from consuming Marcato;
- the reservation clears on confirmed target-song success, observed Marcato loss, cancellation, timeout, zone, death, job change, or engine stop.

NITRO readiness remains contingent on Nightingale and Troubadour, not Marcato. If Marcato is unexpectedly unavailable when NITRO begins, the provider performs the full NITRO refresh without Marcato rather than wasting the NITRO window or risking song expiration.

Marcato and NITRO have similar nominal recast cycles, so normal addon-controlled use should keep them aligned. Runtime checks remain authoritative because manual use, failed actions, death, zoning, and recast modifiers can cause drift.

### Song ordering

The configured desired-song order remains the default batch order. Expiration safety may promote a song, and deterministic capacity recovery may require a documented order, but neither changes the durable list. When the Marcato song is reached, the provider inserts the Marcato action immediately before it.

The provider must not silently move the Marcato song to another durable slot or let an unrelated enhancing or enemy-targeted song consume the reservation.

Enemy-targeted Bard songs are outside the initial subsystem. No separate enemy-song Marcato exclusion lock will be added in the initial implementation. If an external or manual song consumes Marcato, observed Marcato loss invalidates the reservation rather than being modeled as provider success.

### Startup snapshot ownership

On addon load, the scheduler first attempts to seed Bard runtime ownership from Windower's cached type-9 `0x063` status snapshot. Other `0x063` variants are rejected by the existing parser. If no authoritative cached snapshot is available, starting maintenance enters an explicit ownership-rebuild state instead of blocking: the provider casts the effective configured sequence and learns exact song timers from the resulting action and type-9 `0x063` packets. This bootstrap state is runtime-only and never changes durable configuration.

For live packet validation, `//uc brd capture once` passively records the next local general-song `0x028` target results and the matching status family from the next type-9 `0x063`. The command does not dispatch an action; stop the engine before arming it when capturing a manual cast, then inspect the evidence with `//uc brd status`.

For multi-cast lifecycle diagnosis, `//uc brd log start` clears and enables `data/logs/<character>_brd_maintenance.log`. The runtime records proposals, dispatch baselines, raw `0x028` results, parsed `0x063` family timers, multiset deltas, owner confirmation/pruning, pending timeout/cancellation, and scheduler rejection. `//uc brd log stop` closes the diagnostic session; logging is runtime-only and never durable profile configuration.

## Clarion Call and Capacity

Clarion Call is runtime capacity state controlled by durable user policy.

The dedicated provider must use the capacity and recovery rules in `docs/RefDocs/FFXI_Bard_Song_Overwrite_Logic_Specification.md`, including:

- exact refresh before capacity replacement;
- normal main-job and support-job song limits;
- additional-song instrument capacity at effect resolution;
- persisted four- or five-song states after the capacity ability or instrument is no longer active;
- degraded state after a persisted fifth song is lost and Clarion Call is unavailable;
- no guessed overwrite when shortest-duration victim identity is ambiguous.

Clarion active state, remaining window, current song count, and degraded state are runtime-owned.

The ordered final-song list may contain five songs while Clarion policy is disabled. In that case, the provider treats only the first four entries as the effective maintenance set and requires capacity dummy songs for those four slots only. Enabling Clarion activates the fifth entry and its additional dummy-song requirement. The durable five-song order is preserved when Clarion is toggled; the provider does not reject the profile or attempt to maintain the inactive fifth song.

### Dummy-song and GearSwap contract

The UI and v2 profile will contain an ordered list of exact dummy songs used to establish the required active-song count before final songs replace them.

The contract is:

- dummy songs are general beneficial songs, not targeted or enemy songs;
- dummy songs must be exact canonical spells that the character can cast;
- dummy songs must not duplicate each other or overlap the final maintained song list;
- the configured list must contain enough entries for the requested capacity build;
- GearSwap is responsible for equipping the required additional-song instrument when a configured dummy song resolves;
- UnifiedCombat does not persist an instrument name or infer capacity from a configured duration;
- UnifiedCombat verifies the result by observing that each successful dummy cast actually increased or deterministically changed the active song state;
- if a dummy cast does not produce the required capacity transition, the build enters an explicit failed or unknown state and reports the blocker instead of assuming GearSwap equipped the intended instrument.

After the base count is established, the provider replaces the dummy songs with configured final songs according to the deterministic shortest-remaining and exact-refresh rules in the mechanics reference. Dummy-song endtimes are observed runtime state and help make replacement order deterministic.

## Per-recipient State

Song state is maintained per recipient, not as one party-wide count.

A conceptual runtime record is:

```lua
recipient_song_state = {
    recipient_name = "Example",
    recipient_id = 0,
    confidence = "confirmed",
    active = {
        {
            exact_song = "Honor March",
            status_id = 0,
            observed_endtime = 0,
            source_cast_sequence = 0,
        },
    },
    loss_reason = nil,
}
```

This is runtime state only. It is not a proposed v2 serialization shape.

An area cast must not be assumed to affect every intended member. Each recipient requires successful action evidence or must remain unknown.

## Provider Priorities

Within Bard maintenance, proposal priority is:

1. Complete an active Marcato-to-song reservation so no other Bard song can consume it.
2. Prevent an imminent desired-song expiration, especially a persisted fifth song.
3. Complete an already active NITRO forced-refresh generation.
4. Activate NITRO when both abilities are ready and conditions permit the full cycle.
5. Exact-refresh a desired song at its normal safety deadline.
6. Restore a missing song when current capacity permits.
7. Rebuild Clarion-dependent capacity when Clarion is available.
8. Perform a unique-song overwrite only when the victim is uniquely predictable.
9. Refuse or defer ambiguous replacement.

Every dedicated `maintenance_brd` proposal uses global scheduler priority band 120. This is provider-scoped rather than job-scoped: only the Bard maintenance provider emits these actions. Doom remains the hard emergency prepass. Below Doom, the global support ordering is Bard maintenance, critical Cure, Sleep, aftermath weapon skill, then existing weighted actions. Critical Cure uses band 117, Sleep uses band 113, and aftermath uses band 108. Band 113 is also the global pending-engage and engage-preemption bypass threshold, so engage setup cannot suppress Bard maintenance, critical Cure, or Sleep. Existing action, cooldown, movement, zoning, and pending-action safety locks remain authoritative; priority never interrupts an action already underway.

An actionable Bard proposal starts a runtime-only action-lane reservation for the current song sequence. The reservation remains active while the provider waits for cast start, cast completion or interruption, the applicable `0x063` ownership confirmation, and the next required song transition. During that interval, lower-band spell, job ability, and weapon-skill proposals are held so their action lock cannot split the sequence merely because the Bard provider is temporarily between proposals. Movement and targeting remain available. The reservation releases when the effective configured song set is satisfied or when the provider reaches a terminal unavailable state. An initially unavailable Bard action does not reserve the lane. Doom remains unaffected because it is processed by the hard emergency prepass before scheduler proposal arbitration.

## State Invalidation and Cleanup

The Bard runtime module must explicitly invalidate or reset affected state on:

- addon unload or reload;
- engine stop;
- zone change;
- character, main-job, or support-job change;
- K.O. or recipient disappearance;
- party membership change;
- observed dispel or song-count loss;
- interrupted, failed, or rejected song actions;
- external song changes that conflict with owned state;
- loss of Nightingale, Troubadour, Marcato, or Clarion state;
- pending-action timeout.

Cleanup must not mutate durable config.

## Diagnostics

Focused diagnostics should expose why Bard maintenance did or did not propose an action without producing continuous chat spam.

The initial diagnostic surface will be:

```text
//uc brd status
//uc brd trace once
```

`//uc brd status` prints a concise current snapshot: provider eligibility, configured final and dummy songs, recipient ownership/confidence, next deadline, NITRO/Marcato/Clarion state, active generation, and first blocker.

`//uc brd trace once` arms a one-action trace for the next Bard maintenance action. It records the pending action token, exact spell, `0x028` per-target messages and parameters, successful-recipient set, cast-complete time, relevant `0x063` arrival time, family before/after endtimes, resolved ownership transition, and rejection or timeout reason. It automatically disarms after that transaction so it cannot create continuous chat spam.

At minimum, diagnostics should report:

- provider enabled and job eligibility;
- configured exact song set;
- per-recipient exact ownership and confidence;
- observed endtimes and calculated safety deadlines;
- current song count and capacity state;
- NITRO ready, active, and forced-generation progress;
- Marcato ready, reserved song, and reservation status;
- Clarion ready, active, persisted, or degraded state;
- the first proposal blocker or scheduler rejection reason.

## Implementation Phases

### Phase 1: Pure runtime model and packet fixtures

- Extract or extend status snapshot parsing without changing current dispatch.
- Capture and classify real `0x028` per-target song success results.
- Implement exact-song ownership transitions from serialized cast plus snapshot deltas.
- Implement per-recipient confidence and invalidation.
- Cover duplicate-family songs, exact refresh, add, unique overwrite, no-change, and ambiguous observations.

### Phase 2: Dedicated provider in observe/dry-run mode

- Add `uc_brd_maintenance.lua` as a side-effect-free chooser.
- Read active v2 intent and existing scheduler runtime facades.
- Produce diagnostics and dry-run proposals without dispatching live songs.
- Compare proposals with current defensive song behavior.

### Phase 3: Scheduler dispatch and confirmation

- Add the dedicated `maintenance_brd` dispatch path.
- Route song success and failure observations to the Bard runtime model.
- Preserve all global scheduler locks and pending-action behavior.
- Field-test two-song exact refresh before enabling capacity rebuilds.

### Phase 4: NITRO and Marcato orchestration

- Add combined NITRO readiness and activation state.
- Add the forced full-refresh generation.
- Add Marcato exact-song reservation and consumption rules.
- Verify urgent-expiration precedence and interrupted-cycle cleanup.

### Phase 5: Clarion and expanded-capacity recovery

- Implement deterministic four- and five-song construction.
- Add durable dummy-song intent and verified GearSwap capacity transitions.
- Implement persisted fifth-song protection and degraded recovery.
- Add Daurdabla, Marsyas, Loughnashade, and ambiguous-victim fixtures from the mechanics reference.

### Phase 6: UI and v2 migration

- Add the job-visible Bard tab and durable controls.
- Finalize the structured `config.maintenance.brd` shape.
- Preserve or migrate existing general Bard song selections; do not add targeted-song schema.
- Add writer, normalizer, active-config, reload, autoload, diff, and runtime-consumer tests.

### Phase 7: Remove superseded Bard-specific logic

- Move beneficial Bard songs out of generic defensive buff maintenance.
- Remove the incomplete `maintenance_songs` placeholder path.
- Remove synthetic Bard expiration estimates and recent-success identity heuristics only after replacement coverage passes.
- Confirm `defensive_internal` still initializes and maintains non-song defensive behavior.

## Required Test Contract

The completed subsystem must prove:

- the Bard tab is visible for main-job and support-job Bard profiles only;
- durable config stores exact final-song intent, exact dummy-song intent, NITRO policy, Clarion policy, and Marcato assignment;
- durable config stores no duration, endtime, active slot, confidence, recast, buff, or runtime ID state;
- targeted beneficial and enemy-targeted songs remain outside the initial provider;
- `0x028` per-target results produce the successful area-cast recipient set;
- target presence without a successful per-target result does not create recipient ownership;
- the current message-17 Bard success heuristic is not reused;
- cast completion and `0x063` deltas correlate through one action-token transaction without another Bard song racing it;
- a timed-out confirmation transaction creates no false ownership;
- configured dummy songs round-trip durably without duration or instrument state;
- each dummy capacity cast must produce a verified runtime capacity transition;
- duplicate same-family songs map to distinct exact ownership after serialized casts;
- exact refresh updates only the exact song's observed endtime;
- a unique full-capacity overwrite removes the observed shortest owner;
- no timer change does not create false ownership;
- ambiguous packet changes invalidate instead of guessing;
- per-recipient success is not inferred from an area cast without target evidence;
- a maintained song is proposed before its safety deadline;
- NITRO is ready only when both abilities are off cooldown;
- the provider never intentionally activates only one half of NITRO;
- activating NITRO forces all configured songs to be re-sung regardless of remaining duration;
- forced NITRO casts receive newly observed runtime endtimes;
- Marcato is used only during active NITRO when both policies are enabled;
- Marcato can be consumed only by its exact configured song;
- Marcato unavailability does not delay a NITRO refresh cycle;
- urgent expiration does not wait for NITRO;
- Clarion-dependent persisted capacity is maintained without expiration;
- zone, death, job change, engine stop, and contradictory observations clean runtime state;
- no Bard migration breaks COR maintenance or non-song `defensive_internal` behavior;
- profilev2 reload, autoload, status, and diff remain clean;
- the engine is never started automatically by profile or Bard maintenance initialization.

## Resolved Scope Questions

- General area songs are the only initial song-assignment model. Targeted songs are deferred.
- Enemy-targeted songs and a separate enemy-song Marcato lock are deferred.
- Dummy songs are ordered durable config; GearSwap owns their capacity equipment behavior.
- Runtime packet evidence verifies that dummy casts produced the required capacity transition.
- Parsed `0x028` target/action records are the canonical successful-recipient source.
- Cast-to-`0x063` timing is bounded by one serialized action-token transaction, not chat timestamps or an arbitrary sleep.
- `//uc brd status` is the concise state/blocker diagnostic.
- `//uc brd trace once` is the bounded packet-correlation field diagnostic.

Any later targeted-song or enemy-song feature requires a separate design update. It must not be smuggled into the initial implementation through generic defaults or assumed behavior.

## Acceptance Summary

The design is accepted when implementation preserves these central rules:

1. UI configuration owns song intent; the addon owns live song state.
2. Song duration is observed runtime state and is never durable profile config.
3. Beneficial Bard songs have one dedicated scheduler provider.
4. Exact song ownership is reconstructed from serialized casts and packet endtime deltas.
5. Maintained songs are refreshed before expiration.
6. Nightingale and Troubadour are one NITRO option and must be ready together.
7. Activating NITRO forces a complete refresh of all configured songs.
8. Marcato is reserved for one exact configured song and, when NITRO is enabled, is used only while NITRO is active.
9. Ambiguous runtime evidence invalidates state instead of being guessed.
10. Replacing Bard song logic must not break COR or non-song `defensive_internal` maintenance.
11. Initial scope includes general area songs and durable dummy songs, not targeted or enemy songs.
12. Successful area recipients come from classified `0x028` per-target results.
