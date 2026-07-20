# Addendum B — Soul Voice Effects, Persistence, and Clarion Call Interaction

**Companion to:**
- *FFXI Bard Enhancing-Song Capacity, Overwrite, and Maintenance Logic*
- *Addendum A — Pianissimo, Tenuto, and Per-Recipient Bard Song Automation*

**Version 1.0 — July 20, 2026**

---

## 1. Purpose and scope

This addendum defines how **Soul Voice** changes Bard songs and how automation should coordinate it with:

- Clarion Call;
- Daurdabla, Marsyas, and Loughnashade;
- Nightingale and Troubadour;
- Marcato;
- Pianissimo and Tenuto;
- Wild Card and other SP-ability resets;
- normal song-refresh and overwrite logic.

This is an implementation specification. The parent documents continue to define song capacity, exact-spell refresh, lowest-remaining-duration replacement, targeted songs, and per-recipient state.

The central rule is:

> **Soul Voice is evaluated when each song resolves. It enhances that newly applied song effect; it does not retroactively upgrade songs already active.**

---

## 2. Soul Voice ability state

Soul Voice is Bard's level-1 SP ability.

| Property | Value |
|---|---|
| Base status duration | 3 minutes |
| Enhanced status duration | 3 minutes 30 seconds with qualifying `Enhances "Soul Voice" effect` relic legs equipped for activation |
| Base recast | 60 minutes |
| Job Master recast | 45 minutes |
| Job Point effect | Song casting time -2% per rank, up to -40% |
| Capacity added | None |
| Target selection added | None |
| Volatile enmity | 80 |
| Cumulative enmity | 0 |

Qualifying Bard relic legs extend the **Soul Voice status window** by 30 seconds. They do not directly extend every song.

Automation MUST equip the Soul Voice-enhancing legs before activating Soul Voice and MUST confirm the resulting status duration rather than assuming the equipment swap succeeded.

```text
SoulVoiceState {
    active
    activated_at
    expires_at
    relic_duration_extension_applied
    recast_ready_at
}
```

---

## 3. Snapshot behavior

Soul Voice is a cast-resolution modifier.

For each song:

```text
if Soul Voice is active when the song resolves:
    apply that song's Soul Voice modifier
    mark the resulting effect as soul_voice_applied = true
else:
    apply the normal song
```

Consequences:

1. Activating Soul Voice does not alter songs already active.
2. Existing songs must be recast while Soul Voice is active to become enhanced.
3. A Soul Voice-enhanced song remains enhanced after Soul Voice itself expires.
4. The enhancement persists until that song effect:
   - expires;
   - is dispelled;
   - is removed by K.O. or zoning;
   - is overwritten;
   - is exact-refreshed by a later version.
5. Recasting the same exact song after Soul Voice expires replaces the Soul Voice version with a normal-potency version.
6. Casting a different song into a full song set can overwrite a Soul Voice song if that Soul Voice song has the lowest remaining duration.

Soul Voice does not create a protected song category. Potency is not considered by the normal song-overwrite algorithm.

---

## 4. Soul Voice effect classes

Automation MUST classify each song by how Soul Voice modifies it.

```text
SoulVoiceModifierType =
    POTENCY_X2
    MAGIC_ACCURACY_X2
    DURATION_X2
    UNKNOWN_OR_UNVERIFIED
```

### 4.1 Potency doubled

Soul Voice doubles the effect of the following beneficial-song families:

- Paeon;
- Ballad;
- Minne;
- Minuet;
- Madrigal;
- Prelude;
- Aubade;
- Pastoral;
- Fantasia;
- Operetta;
- Capriccio;
- Round;
- Gavotte;
- March, including Honor March;
- Etude;
- Carol;
- Sirvente;
- Dirge.

Soul Voice doubles the effect of the following enemy-targeted song families:

- Requiem;
- Elegy;
- Threnody;
- Nocturne, although some public documentation still marks portions of its testing incomplete.

For these songs:

```text
soul_voice_potency = normal_final_potency * 2
```

The multiplier applies to the final song effect, including applicable song-specific merit, Job Point, skill, and `Song +N` contributions.

#### Important cap behavior

Soul Voice doubles the calculated song effect, but the recipient remains subject to game-system caps.

Examples:

- A doubled March may provide more magic haste than the recipient can use.
- Additional Marches can be wasted when the magic-haste cap is already reached.
- Attack, accuracy, defensive, enmity, and resistance songs may have practical or system caps outside the Bard-song calculation.

The song planner SHOULD optimize for useful final effect, not blindly choose the songs with the largest doubled values.

### 4.2 Magic Accuracy doubled

Soul Voice doubles Magic Accuracy rather than effect potency or duration for:

- Lullaby;
- Finale;
- Virelai.

Consequences:

- Soul Voice does not double Lullaby sleep duration.
- Soul Voice does not make Finale remove additional effects.
- Soul Voice does not double Virelai duration.
- Troubadour, song-specific duration bonuses, and other duration systems remain responsible for effect duration where applicable.

The exact internal Magic Accuracy formula for songs is not fully exposed. Code SHOULD record a categorical `MAGIC_ACCURACY_X2` modifier rather than inventing a final land-rate percentage.

### 4.3 Duration doubled instead of potency

Soul Voice doubles duration for:

- Hymnus;
- Mazurka;
- Scherzo.

For these songs, Soul Voice does not double their ordinary functional effect.

Important examples:

- Soul Voice does not strengthen Scherzo's damage-mitigation threshold or reduction behavior; it makes Scherzo last longer.
- Soul Voice does not increase Mazurka movement speed; it makes Mazurka last longer.
- Soul Voice does not create an improved Reraise tier from Hymnus; it makes Hymnus last longer.

### 4.4 Aria of Passion

Publicly available central Soul Voice tables do not yet explicitly classify **Aria of Passion**, despite modern Bard guides recommending that Aria be reapplied during Soul Voice.

Until a controlled test or authoritative explicit source establishes the exact multiplier, automation SHOULD model Aria as:

```text
sv_modifier_type = UNKNOWN_OR_UNVERIFIED
requires_recast_during_soul_voice = true
```

Do not hardcode a specific `2.0` Aria potency multiplier solely by analogy with older song families.

---

## 5. Duration model under Soul Voice

### 5.1 Normal potency-class songs

Soul Voice does **not** ordinarily double the duration of Minuet, Ballad, March, Madrigal, Minne, and the other potency-class songs listed above.

For those songs:

```text
duration_before_troubadour =
    normal_song_duration_profile
    + applicable fixed duration additions

final_duration =
    duration_before_troubadour
    * (Troubadour active ? 2 : 1)
```

Soul Voice changes potency, not duration.

### 5.2 Soul Voice duration-class songs

For Hymnus, Mazurka, and Scherzo:

```text
duration_before_multipliers =
    normal_song_duration_profile
    + applicable fixed duration additions

final_duration =
    duration_before_multipliers
    * (Soul Voice active at resolution ? 2 : 1)
    * (Troubadour active at resolution ? 2 : 1)
```

Soul Voice and Troubadour are multiplicative for these duration-class songs.

Therefore, a qualifying song cast under both receives four times the pre-ability duration profile:

```text
Soul Voice duration multiplier = 2
Troubadour duration multiplier = 2
Combined multiplier = 4
```

### 5.3 Clarion Call Job Point duration

While Clarion Call is active, its Job Point category adds two seconds of song duration per rank, up to 40 seconds at 20 ranks.

This duration applies to songs cast while Clarion Call is active, including songs that are also enhanced by Soul Voice.

Troubadour doubles the total duration after the other duration bonuses are applied. An implementation may therefore model the fixed Clarion addition before the Troubadour multiplier.

### 5.4 Documentation conflict concerning March duration

Some individual March documentation currently says Soul Voice doubles both March potency and duration. The central Soul Voice documentation classifies March under potency-doubled songs and reserves duration doubling for Hymnus, Mazurka, and Scherzo.

This specification follows the central Soul Voice classification:

```text
March:
    potency_multiplier = 2
    duration_multiplier_from_soul_voice = 1
```

Automation SHOULD NOT double an ordinary March timer merely because Soul Voice was active.

---

## 6. Soul Voice and Clarion Call

## 6.1 No cooldown conflict

Soul Voice and Clarion Call do not share the same SP-ability cooldown.

- Soul Voice is a level-1 SP ability.
- Clarion Call is a level-96 SP ability.
- Level-1 SP abilities use one shared category timer.
- Level-96 SP abilities use a separate shared category timer.

Therefore:

```text
Soul Voice ready != Clarion Call ready
using Soul Voice does not place Clarion Call on cooldown
using Clarion Call does not place Soul Voice on cooldown
```

They can be activated normally during the same buff sequence.

## 6.2 No active-status conflict

Soul Voice and Clarion Call can be active simultaneously.

Their responsibilities are independent:

| Ability | Responsibility |
|---|---|
| Soul Voice | Enhances potency, Magic Accuracy, or duration of songs resolving while active |
| Clarion Call | Adds one song position while active |
| Clarion Call Job Points | Add song duration to songs resolving while Clarion is active |

When both are active, one song can simultaneously receive:

- Soul Voice's song-specific enhancement;
- Clarion Call's capacity permission;
- Clarion Call Job Point duration;
- Troubadour duration;
- Nightingale casting/recast reduction;
- normal instrument potency and duration.

## 6.3 Recommended activation order

Mechanically, activation order does not change a song if both statuses are active when that song resolves.

For automation, the preferred order is:

```text
1. Equip Soul Voice-enhancing relic legs.
2. Activate Soul Voice.
3. Activate Clarion Call.
4. Activate Nightingale and Troubadour as required.
5. Begin the song transaction.
```

Reason:

- Clarion Call's expiration is the hard deadline for adding a fifth position.
- Soul Voice songs already applied retain their potency after Soul Voice expires.
- A missed fifth position cannot be added after Clarion Call expires.
- Soul Voice can last 30 seconds longer than Clarion Call when enhanced by relic legs.

Activating Clarion Call after Soul Voice gives the slot-creation window the later expiration time.

Community sequences sometimes activate Clarion Call first. That is still valid when all songs complete safely inside both windows, but it is not the most conservative scheduler order.

## 6.4 Persisted fifth song

Once a fifth song is added under Clarion Call, it can be maintained after Clarion Call expires through exact refreshes.

Soul Voice does not affect this capacity persistence.

If the fifth song is lost:

- Soul Voice cannot restore the fifth position;
- Daurdabla or Loughnashade III alone cannot restore the fifth position;
- Clarion Call must be active again.

Soul Voice modifies the replacement song only if Soul Voice is also active when that replacement resolves.

---

## 7. Instrument interactions

## 7.1 Daurdabla

Daurdabla supplies additional-song capacity but lacks the full `All Songs +N` potency of a final potency instrument.

A song added with Daurdabla while Soul Voice is active receives Soul Voice's multiplier applied to the Daurdabla version of the song.

For maximum strength:

```text
1. Add or seed the song with Daurdabla.
2. Before Soul Voice expires, exact-refresh that same song with its final potency instrument.
```

If step 2 occurs after Soul Voice expires, the exact refresh downgrades the song to normal Soul Voice-independent potency.

### Daurdabla dummy songs

Disposable dummy songs do not need Soul Voice potency. However, every dummy cast consumes time inside the Soul Voice and Clarion windows.

The scheduler SHOULD minimize dummy count and SHOULD avoid exact-refreshing a dummy.

## 7.2 Marsyas and Honor March

Honor March must resolve with Marsyas.

Soul Voice enhances Honor March as a March-family song.

A valid Soul Voice Honor March cast requires:

```text
Soul Voice active at resolution
Marsyas equipped at resolution
```

Daurdabla cannot be swapped in during Honor March to borrow its capacity.

Because March potency may exceed useful magic-haste needs, the planner SHOULD account for the recipient's other haste sources before spending a song position on a second March.

## 7.3 Loughnashade

Loughnashade III can provide four-song capacity and `All Songs +4` for ordinary songs, reducing the need for low-potency Daurdabla seeding.

It cannot cast Honor March.

Aria of Passion requires a qualifying Loughnashade through resolution. Because Aria's exact Soul Voice multiplier is not explicitly established in the central public mechanics table, preserve its measured or observed value as separate runtime evidence.

---

## 8. Ability interactions

## 8.1 Marcato — hard conflict

Soul Voice and Marcato do not stack for effect or duration.

This includes Marcato's Job Point duration bonus.

When Soul Voice is active, Marcato provides no additional benefit beyond Soul Voice's 100% enhancement and may be consumed or suppressed.

Automation MUST treat this combination as invalid:

```text
if soul_voice_active:
    do_not_activate_marcato()
```

If Marcato is already active when a Soul Voice transaction begins, the planner SHOULD normalize the state rather than assume both modifiers will apply.

## 8.2 Troubadour — compatible and strongly synergistic

Troubadour stacks with Soul Voice.

For potency-class songs:

- Soul Voice doubles potency.
- Troubadour doubles duration.

For Soul Voice duration-class songs:

- Soul Voice doubles duration.
- Troubadour doubles duration again.

At five merit ranks, Troubadour also supplies its high-accuracy song behavior for enemy-targeted songs.

## 8.3 Nightingale — compatible

Nightingale is compatible with Soul Voice and reduces song casting and recast times.

Soul Voice Job Points can add up to 40% song casting-time reduction while Soul Voice is active. Combined with Nightingale, normal Fast Cast, and Pianissimo, the resolving-equipment window may become extremely short.

Automation MUST equip the final required instrument early enough to guarantee it remains equipped at song resolution.

## 8.4 Pianissimo — compatible

Pianissimo can deliver a Soul Voice song to one selected party member.

Each targeted song still requires:

- one Pianissimo activation;
- Soul Voice active at song resolution;
- the correct final instrument at song resolution.

A targeted recipient rebuilt during Soul Voice may end with stronger songs than other party members if their casts resolved under different ability windows. Track the Soul Voice flag per recipient and per exact song.

## 8.5 Tenuto — compatible

Tenuto can protect the Bard's own copy of a Soul Voice song.

The song must resolve while:

- Soul Voice is active;
- Tenuto is active;
- the Bard is included in the song's recipients.

The resulting self-copy is both:

- Soul Voice-enhanced;
- Tenuto-protected.

Refreshing that protected song later requires Tenuto again. Refreshing it after Soul Voice expires creates a protected but normal-potency copy.

## 8.6 Soul Voice does not add song capacity

Soul Voice never changes:

- the normal two-song base;
- Daurdabla or Loughnashade capacity;
- Clarion Call capacity;
- Pianissimo capacity;
- Tenuto capacity.

Do not use `soul_voice_active` in the capacity formula.

---

## 9. Building Soul Voice song sets

## 9.1 Two-song Soul Voice set

```text
1. Equip Soul Voice relic legs.
2. Activate Soul Voice.
3. Cast desired song 1 with final instrument.
4. Cast desired song 2 with final instrument.
5. Confirm each recipient independently.
```

No additional-song instrument is required.

## 9.2 Four songs with Daurdabla

Recommended exact-seed sequence:

```text
1. Equip Soul Voice relic legs.
2. Activate Soul Voice.
3. Activate Nightingale/Troubadour if using a one-pass long-duration build.
4. Cast S1 with final instrument.
5. Cast S2 with final instrument.
6. Cast exact S3 with Daurdabla to add position 3.
7. Cast exact S4 with Daurdabla to add position 4.
8. Exact-refresh S3 with final potency instrument.
9. Exact-refresh S4 with final potency instrument.
10. Confirm all recipients before Soul Voice expires.
```

If Honor March is desired, cast it with Marsyas while the recipient has capacity for it, or use a Daurdabla placeholder and replace that placeholder with Honor March before Soul Voice expires.

## 9.3 Five songs with Soul Voice and Clarion Call

Recommended Daurdabla sequence:

```text
1. Equip Soul Voice relic legs.
2. Activate Soul Voice.
3. Activate Clarion Call.
4. Activate Nightingale/Troubadour if using them.
5. Cast three final desired songs under their required instruments.
6. Equip Daurdabla.
7. Add exact S4.
8. Add exact S5.
9. Exact-refresh S4 with final potency instrument.
10. Exact-refresh S5 with final potency instrument.
11. Confirm every required recipient before Clarion expires.
```

Why three final songs first:

```text
normal base capacity = 2
Clarion capacity     = 3
Daurdabla adds       = positions 4 and 5
```

The three non-Daurdabla positions can be applied at full potency immediately.

With Loughnashade III, ordinary songs may be applied directly up to the combined five-song capacity. Honor March still requires Marsyas.

---

## 10. Extending Soul Voice coverage with a late refresh

Soul Voice status lasts only three to three and a half minutes, but songs enhanced by it retain their enhanced effect until those songs end or are replaced.

Automation may use a two-pass sequence:

### Pass 1 — immediate Soul Voice songs

```text
activate Soul Voice
apply the desired enhanced song set quickly
begin combat or event activity
```

### Pass 2 — late Soul Voice refresh

Shortly before Soul Voice expires:

```text
activate Nightingale and Troubadour
exact-refresh every desired song while Soul Voice is still active
```

The refreshed songs retain Soul Voice potency for their full new Troubadour-enhanced duration.

This can substantially extend total Soul Voice coverage beyond the Soul Voice status window.

### Scheduling constraints

The planner MUST calculate whether the complete late-refresh sequence fits before Soul Voice expires.

Required budget includes:

- job-ability animation and lock time;
- every song cast;
- Pianissimo activations;
- party-member range corrections;
- instrument swaps;
- network and action-result latency;
- recovery margin.

Do not begin a full five-song, multi-recipient late refresh that cannot safely complete.

---

## 11. SP reset behavior

## 11.1 Wild Card

Wild Card results interact differently with the two Bard SP categories:

- Wild Card 5 resets level-1 SP abilities, including Soul Voice.
- Wild Card 6 resets both SP categories, including Soul Voice and Clarion Call.

Automation implications:

### Wild Card 5

If the party still has five songs:

- Soul Voice can be activated again;
- all five exact songs can be refreshed under the new Soul Voice;
- Clarion Call is not required merely to exact-refresh existing fifth-position songs.

If a recipient has lost the fifth song:

- Soul Voice reset alone is insufficient;
- Clarion Call remains unavailable;
- that recipient stays degraded at four songs.

### Wild Card 6

Both Soul Voice and Clarion Call are restored.

The Bard can:

- rebuild missing fifth positions;
- reapply full Soul Voice potency;
- create a new five-song long-duration cycle.

## 11.2 Revitalizer

A Revitalizer resets both SP-ability cooldown categories. Treat it like a guaranteed opportunity to rebuild and re-enhance the complete song state.

## 11.3 Cutting Cards

Cutting Cards reduces remaining SP-ability recast time by a roll-dependent percentage. Track Soul Voice and Clarion Call cooldowns independently because they can have different remaining values.

---

## 12. Maintenance policy after Soul Voice expires

A generic maintenance loop can accidentally downgrade Soul Voice songs.

Example:

```text
Active:
    Soul Voice Valor Minuet V, 180 seconds remaining

Automation:
    sees refresh threshold
    casts normal Valor Minuet V after Soul Voice expired

Result:
    same exact spell is replaced
    new song is normal potency
```

Recommended policy:

```text
if effect.soul_voice_applied
and Soul Voice is no longer active
and effect.remaining > emergency_threshold:
    defer exact refresh
```

Refresh only when one of these is true:

- Soul Voice is active again;
- the effect is close enough to expiration that losing it is worse than downgrading it;
- the encounter policy explicitly authorizes a normal-potency refresh;
- a dispel or K.O. requires immediate recovery.

The policy must not allow a persisted fifth song to expire merely to preserve Soul Voice potency. Capacity preservation has higher priority than potency preservation.

Suggested priority:

```text
1. Prevent fifth-position loss.
2. Prevent any required song from expiring.
3. Preserve Soul Voice potency when feasible.
4. Avoid unplanned different-song overwrites.
5. Optimize nonessential potency.
```

---

## 13. Mixed-potency and partial-failure handling

Soul Voice is evaluated per song and per recipient.

A single party-wide sequence may produce:

```text
Player A:
    all five songs Soul Voice-enhanced

Player B:
    first four enhanced
    fifth resolved after Soul Voice expired

Player C:
    missed two casts due to range

Player D:
    lost one song to Dispel during the sequence
```

Automation MUST NOT mark the party as globally `SOUL_VOICE_BUFFED`.

Use:

```text
SongEffect {
    exact_spell_id
    recipient_id
    soul_voice_applied
    soul_voice_modifier_type
    potency_multiplier
    magic_accuracy_multiplier
    duration_multiplier
    source_instrument
    applied_at
    expires_at
    confidence
}
```

Recommended recipient-level status:

```text
SV_COMPLETE
SV_PARTIAL
SV_NOT_APPLIED
SV_DEGRADED_BY_REFRESH
SV_UNKNOWN
```

---

## 14. State machine additions

```text
SOUL_VOICE_READY
SOUL_VOICE_ACTIVE_BUILDING
SOUL_VOICE_ACTIVE_STABLE
SOUL_VOICE_LATE_REFRESH
SOUL_VOICE_PERSISTED
SOUL_VOICE_PARTIAL
SOUL_VOICE_EXPIRED_NORMAL_MAINTENANCE
WAITING_FOR_SOUL_VOICE_RESET
```

### Transition examples

```text
SOUL_VOICE_READY -> SOUL_VOICE_ACTIVE_BUILDING
    Soul Voice activation confirmed

SOUL_VOICE_ACTIVE_BUILDING -> SOUL_VOICE_ACTIVE_STABLE
    exact desired enhanced set confirmed for all required recipients

SOUL_VOICE_ACTIVE_STABLE -> SOUL_VOICE_LATE_REFRESH
    remaining Soul Voice window is sufficient for planned refresh

SOUL_VOICE_ACTIVE_STABLE -> SOUL_VOICE_PERSISTED
    Soul Voice expires after successful song application

SOUL_VOICE_PERSISTED -> SOUL_VOICE_PARTIAL
    one song is dispelled or exact-refreshed without Soul Voice

ANY -> SOUL_VOICE_PARTIAL
    Soul Voice expires during an incomplete transaction
```

---

## 15. Required scheduler safeguards

A compliant automation MUST:

- track Soul Voice and Clarion Call as separate cooldowns;
- allow both statuses to be active together;
- equip Soul Voice relic legs before activation;
- snapshot Soul Voice on every song effect independently;
- never retroactively mark preexisting songs as enhanced;
- prevent Marcato use during Soul Voice;
- track the Soul Voice expiration deadline;
- track the Clarion expiration deadline separately;
- prioritize the Clarion deadline when building five songs;
- exact-refresh Daurdabla-seeded final songs before Soul Voice expires;
- preserve Marsyas through Honor March resolution;
- avoid late normal refreshes that unnecessarily downgrade Soul Voice songs;
- never allow a persisted fifth song to expire solely to preserve potency;
- handle Wild Card 5 and Wild Card 6 differently;
- mark incomplete or mixed-recipient results explicitly;
- avoid assuming Aria of Passion's exact Soul Voice multiplier until verified.

---

## 16. Test vectors

### TV-B01 — Soul Voice is not retroactive

```json
{
  "active_song": {
    "spell": "Valor Minuet V",
    "soul_voice_applied": false
  },
  "action": "Activate Soul Voice",
  "expected_song_change": false,
  "required_next_action": "Recast Valor Minuet V while Soul Voice is active"
}
```

### TV-B02 — Soul Voice song persists after status expiration

```json
{
  "song_resolved_under_soul_voice": true,
  "soul_voice_status_now_active": false,
  "song_not_recast_or_removed": true,
  "expected_song_still_enhanced": true
}
```

### TV-B03 — Normal exact refresh downgrades Soul Voice song

```json
{
  "active": {
    "spell": "Valor Minuet V",
    "soul_voice_applied": true
  },
  "incoming": {
    "spell": "Valor Minuet V",
    "soul_voice_active_at_resolution": false
  },
  "expected_result": "EXACT_REFRESH",
  "expected_soul_voice_applied": false
}
```

### TV-B04 — Soul Voice and Clarion Call coexist

```json
{
  "soul_voice_active": true,
  "clarion_call_active": true,
  "incoming_song": "Valor Minuet V",
  "recipient_count_before": 2,
  "instrument_capacity": 2,
  "expected_capacity_with_clarion": 3,
  "expected_song_added": true,
  "expected_song_soul_voice_enhanced": true
}
```

### TV-B05 — Marcato conflict

```json
{
  "soul_voice_active": true,
  "marcato_requested": true,
  "expected_planner_result": "INVALID_REDUNDANT_MODIFIER",
  "expected_action": "Do not activate Marcato"
}
```

### TV-B06 — Scherzo receives duration, not potency

```json
{
  "spell": "Sentinel's Scherzo",
  "soul_voice_active_at_resolution": true,
  "expected_potency_multiplier": 1,
  "expected_duration_multiplier_from_soul_voice": 2
}
```

### TV-B07 — Lullaby receives Magic Accuracy, not duration

```json
{
  "spell": "Horde Lullaby II",
  "soul_voice_active_at_resolution": true,
  "expected_magic_accuracy_multiplier": 2,
  "expected_duration_multiplier_from_soul_voice": 1
}
```

### TV-B08 — Wild Card 5 with persisted fifth song

```json
{
  "wild_card_result": 5,
  "soul_voice_reset": true,
  "clarion_call_reset": false,
  "recipient_active_count": 5,
  "expected_can_exact_refresh_all_five_under_new_soul_voice": true,
  "expected_can_add_missing_fifth": false
}
```

### TV-B09 — Wild Card 6 after fifth-song loss

```json
{
  "wild_card_result": 6,
  "soul_voice_reset": true,
  "clarion_call_reset": true,
  "recipient_active_count": 4,
  "expected_can_rebuild_fifth": true,
  "expected_can_reapply_soul_voice": true
}
```

### TV-B10 — Soul Voice expires mid-sequence

```json
{
  "songs": [
    {"spell": "S1", "resolved_before_sv_expiry": true},
    {"spell": "S2", "resolved_before_sv_expiry": true},
    {"spell": "S3", "resolved_before_sv_expiry": false}
  ],
  "expected_recipient_state": "SV_PARTIAL",
  "expected_s1_enhanced": true,
  "expected_s2_enhanced": true,
  "expected_s3_enhanced": false
}
```

### TV-B11 — Fifth position has priority over potency preservation

```json
{
  "active_count": 5,
  "soul_voice_song_near_expiration": true,
  "soul_voice_active": false,
  "clarion_call_active": false,
  "expected_action": "Normal exact refresh before expiration",
  "expected_reason": "Preserve fifth-song capacity even though potency is downgraded"
}
```

### TV-B12 — Aria remains explicitly unverified

```json
{
  "spell": "Aria of Passion",
  "soul_voice_active_at_resolution": true,
  "expected_sv_modifier_type": "UNKNOWN_OR_UNVERIFIED",
  "expected_requires_recast_under_soul_voice": true,
  "expected_hardcoded_multiplier": null
}
```

---

## 17. Sources

- **[S1]** BG Wiki, *Soul Voice*: duration, recast, Job Point effect, song classifications, Marcato conflict, and relic-leg duration extension.  
  https://www.bg-wiki.com/ffxi/Soul_Voice

- **[S2]** BG Wiki, *Category: SP Ability*: separate level-1 and level-96 SP cooldown categories, Job Master cooldown reduction, Wild Card reset behavior, and SP summary.  
  https://www.bg-wiki.com/ffxi/Category%3ASP_Ability

- **[S3]** BG Wiki, *Clarion Call*: capacity, duration, Job Point duration, and persisted additional-song behavior.  
  https://www.bg-wiki.com/ffxi/Clarion_Call

- **[S4]** BG Wiki, *Marcato*: explicit non-stacking with Soul Voice and song-effect classification.  
  https://www.bg-wiki.com/ffxi/Marcato

- **[S5]** BG Wiki, *Troubadour*: duration doubling after other duration bonuses.  
  https://www.bg-wiki.com/ffxi/Troubadour

- **[S6]** BG Wiki, *Job Points*: Soul Voice casting-time reduction and Clarion Call duration bonus.  
  https://www.bg-wiki.com/ffxi/Job_Points

- **[S7]** BG Wiki, *Obamiwannabuffya: A Bard Guide*: modern Soul Voice use, relic extension, late reapplication, Clarion pairing, and instrument workflows.  
  https://www.bg-wiki.com/ffxi/Obamiwannabuffya%3A_A_Bard_Guide_by_Funkworkz

- **[S8]** BG Wiki, *Community Bard Guide*: modern summary of Soul Voice and Clarion Call usage.  
  https://www.bg-wiki.com/ffxi/Community_Bard_Guide

- **[S9]** BG Wiki, *Aria of Passion*: current documented Aria effect and Loughnashade requirement; does not explicitly document the Soul Voice multiplier.  
  https://www.bg-wiki.com/ffxi/Aria_of_Passion

- **[S10]** Current community explanation of exact-song overwrite behavior, including replacement of Soul Voice songs regardless of prior potency.  
  https://www.reddit.com/r/ffxi/comments/1pqiltk/bard_question/

- **[S11]** FFXIAH, *What is the order for Bard JA (Soul Voice, etc.)?*: community sequences pairing Soul Voice, Clarion Call, and late reapplication.  
  https://www.ffxiah.com/forum/topic/56406/what-is-the-order-for-bard-ja-soul-voice-etc/

---

## 18. Confidence and unresolved details

High confidence:

- Soul Voice and Clarion Call use separate SP cooldown categories.
- They can be active and useful simultaneously.
- Soul Voice is a per-song resolution modifier.
- Marcato does not stack with Soul Voice.
- Soul Voice potency persists after the status ends until the song is replaced or lost.
- Soul Voice does not create song capacity.
- Hymnus, Mazurka, and Scherzo receive duration rather than ordinary potency.
- Lullaby, Finale, and Virelai receive Magic Accuracy rather than ordinary potency.

Explicitly unresolved or conflicting:

1. **Aria of Passion's exact Soul Voice multiplier** is not explicitly documented in the central public Soul Voice table.
2. **Some March documentation says Soul Voice also doubles March duration**, conflicting with the central Soul Voice classification and practical duration model.
3. The internal numerical formula behind “Magic Accuracy doubled” is not fully exposed.
4. Exact packet-level timing tolerance near Soul Voice expiration must be measured in the automation environment.

Code should preserve these as explicit uncertainty rather than silently inventing mechanics.
