# Bard Soul Voice and Pianissimo Implementation Plan

## Status

This document records the agreed design and implementation plan for completing UnifiedCombat's beneficial-song Bard implementation with:

- automatic, user-toggleable Soul Voice use;
- Soul Voice integration with NITRO, Clarion Call, and Marcato policy;
- per-recipient custom song overlays delivered through Pianissimo;
- duration-safe overlay decisions based on the actual song effect being refreshed or displaced;
- serialized, packet-confirmed Bard transactions under the existing scheduler provider.

The base implementation described here is now codified in the Bard provider, profile pipeline, scheduler dispatch, WinForms UI, and replay tests. When remote timer evidence cannot safely support more than one overlay, the implementation selects the highest-priority safe song and stops instead of estimating a second overwrite. Live packet timing validation, richer authoritative multi-song subset selection, and the explicitly deferred late-window Soul Voice optimization remain follow-up work.

The existing runtime entry point remains `uc_brd_maintenance.lua`, owned by scheduler provider `maintenance_brd`. The existing initial design remains in `docs/bard_song_maintenance_design.md`. This plan extends that design and supersedes its initial deferral of targeted beneficial songs once the work described here is implemented.

Mechanics references:

- `docs/RefDocs/FFXI_Bard_Pianissimo_Tenuto_Targeted_Song_Addendum.md`
- `docs/RefDocs/FFXI_Bard_Soul_Voice_and_Clarion_Call_Addendum.md`

## Goals

The completed subsystem will:

- allow the user to enable or disable automatic Soul Voice use;
- never intentionally spend Soul Voice without confirmed Nightingale and Troubadour support;
- avoid Marcato actions during a Soul Voice transaction because Marcato adds no value over Soul Voice;
- allow exact custom songs to be assigned to one or more named party members;
- deliver custom songs through one Pianissimo activation per targeted song;
- allow normal Pianissimo overlays during a normal, non-NITRO song cycle;
- require Troubadour only when a targeted cast could shorten an existing Troubadour-enhanced effect;
- verify required Troubadour coverage through song resolution, not merely at song start;
- preserve group-song and capacity safety ahead of optional potency optimization;
- keep all Bard operations serialized through the existing Bard action lane;
- fail explicitly when recipient identity, overwrite outcome, modifier state, or action confirmation is unsafe or unknown.

## Non-goals

This plan does not:

- add a second scheduler provider for targeted songs or Soul Voice;
- make live recipient IDs, timers, ability state, or transaction progress durable;
- treat Pianissimo as additional song capacity;
- assume Pianissimo can select which full-capacity song the server replaces;
- estimate an unknown overwrite victim merely to continue a sequence;
- use Tenuto as a targeting ability;
- combine Tenuto with Pianissimo;
- implement enemy-targeted Bard songs;
- introduce a new equipment bridge or external dependency;
- guarantee uninterrupted custom overlays after unrelated area refreshes, dispels, K.O., zoning, or other invalidating events;
- implement late-window Soul Voice refresh optimization in the first phase.

## Architecture Decision

Soul Voice, Pianissimo, normal area songs, NITRO, Clarion Call, and Marcato remain under one scheduler provider:

```text
maintenance_brd
```

They share one action lane because each operation can change the assumptions used by the next operation. A separate provider would permit unsafe interleaving.

Scheduler priority is absolute for this provider: Doom is the only operation allowed ahead of actionable or reserved Bard maintenance. `maintenance_brd` uses the highest non-Doom proposal band, and an active Bard lane blocks every competing proposal plus nonblocking target acquisition and movement coordination. Modifier confirmation gaps such as Nightingale-to-Troubadour and Pianissimo-to-song retain the lane until the expected status is confirmed. A dispatched instant job ability that lacks confirmation becomes eligible to retry the same reserved step after 0.5 seconds; missing confirmation does not abandon or advance the sequence.

The runtime concerns should be separated internally without changing the scheduler-facing wrapper:

1. **Group-song planner**
   Maintains the normal area-song set, dummy songs, additional-song capacity, and ordinary party recovery.
2. **Targeted-overlay planner**
   Evaluates per-recipient custom-song requirements and creates safe Pianissimo transactions.
3. **Sequence controller**
   Owns multi-action generations and reservations involving NITRO, Soul Voice, Clarion Call, Marcato exclusion, Pianissimo, and their associated songs.

`uc_brd_maintenance.lua` remains the stable public wrapper called by `unified_scheduler.lua`. Cohesive helper extraction is acceptable, but existing public functions and scheduler call signatures must remain stable unless an implementation phase explicitly extends them.

## Durable Configuration

The proposed durable shape is:

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

    use_soul_voice = true,
    use_nitro = true,
    use_clarion_call = true,
    use_marcato = false,
    marcato_song = "",

    targeted_songs = {
        {
            recipients = { "Tankone", "Tanktwo" },
            priority_songs = {
                "Mage's Ballad III",
                "Mage's Ballad II",
            },
        },
    },

    recovery_range_yalms = 9.9,
    recovery_ignore_names = {},
}
```

### Configuration meaning

`use_soul_voice` means UnifiedCombat may automatically use Soul Voice when the Soul Voice and NITRO preconditions in this document are satisfied.

`targeted_songs` defines recipient-specific high-priority songs layered over the normal group-song set. The first entry in `priority_songs` is the highest priority.

Pianissimo does not create capacity. At full capacity, adding a targeted song necessarily displaces a song selected by the server's normal overwrite rules. Therefore, a targeted recipient's effective policy is constraint-based:

```text
required:
    configured targeted priority songs

acceptable fillers:
    configured normal group songs

required count:
    the recipient's currently supported configured song capacity
```

The planner does not require a particular normal group song to be the victim when the user has accepted that any safe normal group song may be displaced.

### Durable validation

Configuration validation must fail with a specific reason when:

- a recipient name is empty;
- the same recipient appears in more than one targeted assignment;
- a targeted song is not an exact canonical beneficial Bard song;
- the same targeted song appears more than once for one assignment;
- Pianissimo is unavailable at the configured Bard level;
- targeted assignments are configured for an unsupported job combination;
- Soul Voice is enabled for a job combination that cannot use it;
- the targeted configuration cannot be normalized without ambiguous ownership.

Recipient names are durable policy. Runtime server IDs are resolved from the current party roster and are never serialized.

## Runtime State Ownership

All live state remains addon-owned. It must not be written to the profile.

Required additions include conceptually:

```lua
state.soul_voice_generation = {
    phase = "awaiting_nightingale",
    started_at = 0,
    soul_voice_expires_at = 0,
    troubadour_expires_at = 0,
    clarion_expires_at = 0,
    group_complete = {},
    overlay_complete = {},
}

state.targeted_transaction = {
    recipient_id = 0,
    recipient_name = "",
    assignment_index = 0,
    song_name = "",
    song_priority = 0,
    phase = "awaiting_pianissimo",
    expected_victim_names = {},
    requires_troubadour = false,
    troubadour_required_through = 0,
    action_token = "",
}
```

Exact field names may follow nearby code style, but the state distinctions must be preserved.

Per-recipient effects require at least:

```lua
SongEffect = {
    song_name = "",
    status_id = 0,
    endtime = 0,
    endtime_confidence = "confirmed",
    confirmed_at = 0,
    is_dummy = false,
    troubadour_active = false,
    soul_voice_applied = false,
    pianissimo_applied = false,
    source_generation = 0,
}
```

`troubadour_active` and `soul_voice_applied` describe the modifiers present when that exact song resolved. They do not describe current Bard buff state.

## Soul Voice Policy

### NITRO is mandatory

Soul Voice is too valuable to use without NITRO. UnifiedCombat must never intentionally activate Soul Voice unless both Nightingale and Troubadour are confirmed active.

The sequence is:

```text
confirm Nightingale ready
confirm Troubadour ready
activate Nightingale
confirm Nightingale active
activate Troubadour
confirm Troubadour active and capture its endtime
activate Soul Voice
confirm Soul Voice active and capture its endtime
activate Clarion Call if required for capacity
build or refresh the normal group set
apply safe targeted overlays in the remaining modifier window
complete the generation
```

Activating NITRO before Soul Voice intentionally spends a small amount of the NITRO window. This is preferable to consuming Soul Voice and then discovering that Nightingale or Troubadour failed.

Before arming the generation, the planner must verify:

- Bard maintenance is enabled;
- `use_soul_voice` is true;
- Soul Voice is ready;
- Nightingale and Troubadour are ready or already confirmed active with sufficient remaining duration;
- no incompatible Bard transaction is pending;
- the minimum useful group refresh can fit within the expected NITRO window;
- required recipients and current group-song state are sufficiently known to plan safely.

If NITRO is unavailable, Soul Voice waits. Normal NITRO use does not have to wait for Soul Voice when Soul Voice is unavailable.

### Per-effect Soul Voice state

Soul Voice is evaluated at song resolution. It is not a party-global property.

Every successful song delivery records `soul_voice_applied` independently for each recipient and exact song. A partial sequence may therefore produce a mix of Soul Voice-enhanced, normal, and unknown effects.

After Soul Voice expires:

- avoid an unnecessary normal exact refresh that would downgrade a safely lasting Soul Voice effect;
- refresh when capacity preservation or imminent expiration makes refresh necessary;
- never sacrifice a persisted fifth position solely to preserve Soul Voice potency;
- report partial or downgraded Soul Voice coverage explicitly.

### Marcato exclusion

Marcato adds no value over Soul Voice and consumes an action with no benefit. Marcato is therefore prohibited for the entire Soul Voice transaction, not only while the Soul Voice status is visibly active.

The exclusion begins when a Soul Voice generation is armed and ends only when that generation completes or aborts.

Required behavior:

- do not propose Marcato while `state.soul_voice_generation` exists;
- clear any addon-owned Marcato reservation when a Soul Voice generation starts;
- do not insert Marcato if Soul Voice expires or fails midway through the generation;
- if Marcato was activated manually before the generation, do not delay Soul Voice to preserve it;
- if an already-active Marcato is consumed by a Soul Voice song, attribute only the Soul Voice modifier to the resulting effect;
- resume ordinary configured Marcato behavior only after the generation has ended and Soul Voice is inactive.

## Targeted Overlay Policy

### One Pianissimo per song

Every targeted song is its own serialized transaction:

```text
resolve configured recipient name to current server ID
verify current party membership
verify recipient is alive and in range
verify targeted song is still required
verify overwrite and modifier safety
activate Pianissimo
confirm Pianissimo active
revalidate recipient and safety
cast exactly one song on that recipient
confirm the intended recipient and successful result from 0x028
reconcile recipient count from 0x076 when a count transition is expected
update only that recipient's song state
complete or advance the targeted transaction
```

One Pianissimo activation must never be assumed to cover multiple songs.

The entire targeted transaction uses the existing Bard action lane. Area-song maintenance may not interleave between Pianissimo and its reserved song.

### Target identity

Durable configuration uses player names. At runtime:

- resolve the configured name to a current party member;
- store the resolved server ID in the active transaction;
- revalidate the same ID and name before every action;
- never rely solely on a party-list index;
- abort if the roster entry changes or becomes ambiguous.

### Conditional Troubadour rule

Troubadour is not globally required for Pianissimo.

A normal, non-NITRO group cycle may be overlaid with normal Pianissimo songs. Troubadour is required only when a targeted cast could shorten a Troubadour-enhanced effect.

The decision matrix is:

| Target operation | Troubadour requirement |
|---|---|
| Add into unused resolving capacity | Not required |
| Exact-refresh an existing normal song | Not required |
| Exact-refresh an existing Troubadour song | Required through resolution |
| Replace a uniquely shortest normal song | Not required |
| Replace a uniquely shortest Troubadour song | Required through resolution |
| Possible tied victims include a Troubadour song | Required through resolution |
| Victim or modifier state is unknown, without Troubadour | Block the transaction |
| Victim or modifier state is unknown, with Troubadour proven safe through resolution | Allow a best-effort replacement and retain unknown victim identity |

The invariant is:

```text
incoming_song_duration_class must not intentionally downgrade
the Troubadour duration class of the effect it refreshes or may displace
```

### Overwrite candidate evaluation

For a full-capacity target:

1. If the exact incoming song is already active, treat the operation as an exact refresh.
2. Otherwise, determine the unique shortest effect or the complete tied candidate set within the established timer tolerance.
3. Reject unknown endtimes or unknown active effects unless confirmed Troubadour will remain active through resolution. With that proof, the incoming enhanced song cannot shorten either a normal or enhanced unknown victim, so a best-effort replacement is duration-safe even though victim identity remains unknown.
4. Reject candidates containing a targeted song that policy does not permit this action to sacrifice.
5. Set `requires_troubadour` when any possible candidate has `troubadour_active == true`.
6. If all acceptable candidates are normal-duration effects, allow a normal Pianissimo overlay.
7. If any acceptable candidate is Troubadour-enhanced, wait for or use confirmed Troubadour.

The server selects the actual victim. The addon uses candidate evaluation to prove that every possible outcome allowed by its current evidence is safe.

### Troubadour must survive through resolution

When `requires_troubadour` is true, checking the buff at song start is insufficient.

Before Pianissimo, require:

```text
now
+ Pianissimo action allowance
+ song cast allowance
+ packet confirmation allowance
+ safety margin
< Troubadour endtime
```

Immediately before dispatching the song, repeat the deadline check using the current time and known Troubadour endtime.

When the song resolves, record the result as Troubadour-enhanced only when the `0x028` success time is earlier than the authoritative Troubadour expiration time. If this cannot be proven, stop the overlay and mark the recipient state uncertain.

### Resolution-time modifier evidence

The existing implementation carries `troubadour_active` from proposal detail into pending delivery. That is dispatch-time intent, not sufficient proof of resolution-time state.

Implementation must distinguish:

```lua
requires_troubadour = true
troubadour_active_at_dispatch = true
troubadour_active_at_resolution = true
```

Only resolution-time evidence is persisted on the resulting song effect.

Apply the same resolution-time principle to `soul_voice_applied`.

### Targeted priority and best effort

Targeted songs are ordered from highest to lowest user priority. When only part of an overlay can be completed safely, select the highest-priority subset that fits.

Within the selected subset, cast from lowest selected priority to highest selected priority. This ensures that if a later cast unexpectedly displaces an earlier targeted effect, the most important song is the final survivor.

Each successfully delivered targeted song is marked complete per recipient for the current group-song generation. An unconfirmed Pianissimo activation is not a song attempt and retries the same reserved recipient after 0.5 seconds. A confirmed song delivery is not repeated within that generation unless new authoritative evidence proves the overlay was displaced.

An unsafe remaining song is deferred with a specific blocker. The provider does not estimate or guess merely to finish the list.

## Group and Overlay Interaction

Normal group songs define the baseline. Targeted songs define recipient-specific high-priority requirements layered over that baseline.

An area-song refresh can affect every in-range recipient, including recipients with custom overlays. Pianissimo does not protect a targeted song from later area casts.

A Pianissimo exact refresh affects only its selected recipient. It must not move the group refresh deadline. Ordinary area-song maintenance uses the earliest confirmed endtime for each group song across all currently eligible recipients, including recipients whose timer remains earlier than the Bard's locally refreshed timer. An unknown recipient endtime is an explicit blocker rather than permission to fall back to the Bard's later local timer.

Required behavior:

- complete the normal group build or refresh before applying the generation's targeted overlays;
- after any area-song delivery, reevaluate affected targeted recipients;
- mark an overlay pending when an area cast, dispel, K.O., zone, roster change, or uncertain result may have invalidated it;
- permit normal overlay repair when the possible displaced effects are all normal-duration effects;
- require Troubadour for repair when any possible displaced effect is Troubadour-enhanced;
- preserve required song capacity ahead of optional overlay or potency preservation;
- expose pending and blocked overlay state in Bard status output.

Custom overlays cannot be guaranteed continuously when the game provides insufficient evidence or the necessary Troubadour window is unavailable. The addon must report that state rather than silently applying a duration downgrade.

## Action Confirmation and Evidence

### Local area songs

The existing local `0x063` timer-delta path remains authoritative for the Bard's local effects. A confirmed local endtime from the same serialized area cast may continue to be associated with confirmed area recipients under the existing ownership contract.

### Remote Pianissimo songs

A Pianissimo song delivered only to a remote recipient does not create a local Bard `0x063` song timer delta.

Targeted confirmation therefore uses:

- `0x028` to confirm the Bard, exact spell, successful result, and intended recipient ID;
- `0x076` to confirm remote recipient song-count transitions when the operation should add capacity;
- the pre-cast per-recipient ownership model to classify exact refresh or possible overwrite candidates;
- recorded ability endtimes to prove Troubadour and Soul Voice state at resolution.

For a full-capacity exact refresh or replacement, `0x076` may show no count change. The successful targeted `0x028` result confirms that the incoming song landed, but it does not directly identify which different song was removed. The planner must establish a safe candidate set before dispatch.

If post-cast evidence conflicts with the plan:

- stop the transaction;
- release reservations through the normal terminal path;
- mark the recipient unknown or partial as appropriate;
- do not continue to the next targeted song.

## Sequence Priority

The intended safety order is:

```text
1. Complete or terminate the currently pending Bard action.
2. Preserve a persisted fifth song position.
3. Prevent required group songs from expiring.
4. Complete an already-started atomic Pianissimo-plus-song pair.
5. Complete an active Soul Voice/NITRO group generation safely.
6. Apply or repair safe targeted overlays.
7. Preserve Soul Voice potency when feasible.
8. Perform optional Marcato optimization outside Soul Voice generations.
```

Before starting a multi-action targeted sequence, the planner must ensure that it will not cause known group-song safety deadlines to be missed. Once Pianissimo has been activated for a reserved song, the pair must complete or terminate before unrelated Bard work resumes.

## Failure Handling

The implementation must fail fast with a specific blocker for at least:

- configured recipient not in party;
- recipient server ID changed;
- recipient dead or outside configured range;
- missing remote buff evidence;
- unknown recipient song count when the operation requires count knowledge;
- unknown overwrite victim without a Troubadour window proven safe through resolution;
- ambiguous candidate set containing an unacceptable victim;
- unknown candidate modifier state;
- insufficient Troubadour time through predicted resolution;
- Troubadour expired before required song resolution;
- Pianissimo confirmation pending or retrying for the same reserved recipient;
- Pianissimo or song rejected or interrupted;
- successful song result names an unexpected recipient;
- expected `0x076` count transition not observed;
- Soul Voice requested without confirmed NITRO;
- Marcato requested during a Soul Voice generation.

No failure path may fabricate delivery, silently downgrade modifier metadata, or continue a multi-song overlay from uncertain state.

## Status and Diagnostics

Bard status output should include:

- Soul Voice enabled/disabled policy;
- current Soul Voice generation phase;
- Soul Voice, Troubadour, and Clarion remaining windows when known;
- Marcato exclusion reason while a Soul Voice generation exists;
- active targeted recipient and transaction phase;
- targeted song priority and expected overwrite candidates;
- whether the current targeted action requires Troubadour;
- overlay state per configured recipient: satisfied, pending, partial, blocked, or unknown;
- the exact blocker preventing the next action;
- per-effect `troubadour_active`, `soul_voice_applied`, and `pianissimo_applied` flags.

Diagnostics must distinguish dispatch-time modifier intent from resolution-time modifier confirmation.

## Implementation Phases

### Phase 1 — Configuration and contracts

- add `use_soul_voice` to canonical defaults and normalization;
- add `targeted_songs` structured validation and normalization;
- update profile-v2 omission and durability rules;
- add WinForms controls for Soul Voice and targeted recipient/song assignments;
- update structured profile writer and parity tests;
- update ownership documentation.

No runtime behavior should be enabled until canonical configuration tests pass.

### Phase 2 — Resolution-time modifier tracking

- add Soul Voice to the Bard ability metadata;
- expose authoritative local ability endtimes needed by the Bard provider;
- change Troubadour delivery metadata from proposal-time state to resolution-time evidence;
- record `soul_voice_applied` per exact song and recipient;
- add tests for expiration between dispatch, cast start, and resolution.

This phase is required before conditional overlay enforcement.

### Phase 3 — Soul Voice generation

- add explicit Soul Voice generation state;
- require confirmed Nightingale and Troubadour before Soul Voice activation;
- integrate Clarion Call when capacity creation requires it;
- force the configured group refresh under the generation;
- exclude and clear Marcato reservations for the full generation;
- preserve per-effect Soul Voice state after Soul Voice expires;
- defer nonessential normal refreshes that would downgrade safely lasting Soul Voice effects;
- add state-machine and partial-failure tests.

The first implementation should perform one complete Soul Voice generation. Late-window Soul Voice refresh optimization remains deferred.

### Phase 4 — Target-aware Bard dispatch

- extend Bard proposals and scheduler candidates with recipient ID and name;
- construct and dispatch a verified party-member-targeted song command;
- retain `<me>` behavior for area songs and self-target job abilities;
- pass target identity through action-state and diagnostic metadata;
- confirm the recipient from `0x028`;
- add dispatch tests before enabling multi-action overlays.

### Phase 5 — Single targeted transaction

- implement one Pianissimo activation followed by one reserved song;
- revalidate recipient identity, life state, range, readiness, and modifier deadline before each action;
- confirm Pianissimo before dispatching the song;
- update only the confirmed recipient;
- terminate safely on every abnormal result;
- verify add, exact-refresh, and replacement cases independently.

### Phase 6 — Conditional Troubadour planner

- expose overwrite candidate analysis from per-recipient party-song state;
- calculate `requires_troubadour` from the exact refresh target or possible victim set;
- allow normal overlays over normal effects;
- require Troubadour through resolution when a possible displaced effect is Troubadour-enhanced;
- block unknown or unacceptable outcomes;
- add boundary tests at Troubadour expiration.

### Phase 7 — Multi-song priority overlays

- implement per-recipient priority selection;
- choose the highest-priority subset that fits known action and modifier deadlines;
- cast the selected subset from lower to higher priority;
- prevent retry loops within one generation;
- reconcile overlays after area deliveries and recipient state changes;
- expose satisfied, pending, partial, blocked, and unknown status.

### Phase 8 — Live validation and optional optimization

- capture Pianissimo activation, consumption, interruption, invalid-target, and successful target packets;
- validate targeted command construction and range behavior;
- measure the required safety margin near Troubadour expiration;
- validate `0x076` count-transition timing after targeted additions;
- validate behavior when possible overwrite endtimes are tied;
- consider late-window Soul Voice refresh only after the base transaction model is proven live.

## Verification Matrix

At minimum, replay/self-tests must cover:

### Soul Voice

- Soul Voice disabled;
- Soul Voice ready while NITRO is unavailable;
- NITRO confirmed before Soul Voice activation;
- Nightingale succeeds and Troubadour fails;
- Soul Voice succeeds with Clarion separately active;
- Soul Voice applies per recipient and per exact song;
- Soul Voice expires mid-generation;
- normal refresh would downgrade a safely lasting Soul Voice effect;
- capacity preservation overrides Soul Voice potency preservation;
- Marcato ready when a Soul Voice generation starts;
- an existing Marcato reservation is cleared;
- manually active Marcato does not delay Soul Voice;
- Marcato is not inserted after mid-generation Soul Voice expiration;
- ordinary Marcato behavior resumes after the generation ends.

### Pianissimo and overlays

- one Pianissimo activation applies to exactly one song;
- normal song added into unused capacity without Troubadour;
- normal exact refresh without Troubadour;
- normal overlay replaces a normal victim without Troubadour;
- Troubadour exact refresh waits for Troubadour;
- possible Troubadour victim waits for Troubadour;
- Troubadour active at cast start but expired at resolution;
- tied candidates are all normal and acceptable;
- tied candidates include a Troubadour effect;
- candidate set contains a protected higher-priority targeted song;
- unknown endtime or unknown active song blocks;
- unexpected target ID aborts;
- missing `0x076` count transition invalidates an add;
- higher-priority subset selection under a short modifier window;
- lower-priority-to-higher-priority execution order;
- no retry loop after a targeted song may have overwritten another targeted song;
- area refresh marks the affected overlay for reconciliation.

### Compatibility

- current area-song maintenance behavior remains unchanged when new settings are disabled;
- current NITRO, Clarion, dummy, recovery, and Marcato tests continue to pass;
- Bard scheduler proposals still use provider `maintenance_brd`;
- public Bard module functions and scheduler call surfaces remain compatible;
- all changed Lua files parse under Lua 5.1.

## Known Constraints and Follow-up Questions

1. Remote `0x076` buff data does not provide exact expiration times. Targeted casts require conservative pre-cast ownership and modifier evidence.
2. A successful targeted `0x028` action result confirms the incoming song and recipient but not the identity of a different overwritten song.
3. Pianissimo consumption behavior for every abnormal failure needs live confirmation.
4. The safe action-time allowance near Troubadour expiration must be measured in Windower.
5. Exact server behavior for mathematically tied overwrite candidates must not be assumed.
6. GearSwap must equip the Soul Voice relic legs and required resolving instruments through the normal precast/midcast lifecycle. UnifiedCombat should confirm results rather than create a new equipment-control path.
7. Tenuto may be modeled later for Bard-self specialized sets, but it is independent of the requested Pianissimo overlay feature and must never be treated as targeting.

## Completion Criteria

The feature is complete only when:

- the new durable configuration round-trips through the UI and structured profile;
- Soul Voice never dispatches without confirmed NITRO;
- Marcato never dispatches during a Soul Voice generation;
- every targeted song uses a separately confirmed Pianissimo activation;
- conditional Troubadour enforcement is based on the effect being refreshed or possibly displaced;
- required Troubadour is proven active at song resolution;
- recipient identity and delivery are confirmed from authoritative action evidence;
- unsafe or unknown overwrite outcomes block explicitly;
- existing Bard behavior remains unchanged when Soul Voice and targeted songs are disabled;
- Lua 5.1 parsing and the complete replay self-test suite pass;
- focused live packet validation confirms the remaining Pianissimo and timing assumptions.
