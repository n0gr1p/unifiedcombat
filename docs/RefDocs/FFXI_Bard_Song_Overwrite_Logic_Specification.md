# FFXI Bard Enhancing-Song Capacity, Overwrite, and Maintenance Logic

**Standalone specification for deterministic 2-, 4-, and 5-song automation**  
**Version 1.0 — July 10, 2026**

## 1. Purpose and scope

This document defines a deterministic model for applying, overwriting, refreshing, losing, and recovering beneficial Bard songs on party members in Final Fantasy XI. It is written as an implementation specification rather than a play guide.

The normative logic covers:

- normal two-song operation;
- four-song operation using a two-additional-song instrument;
- five-song operation using Clarion Call plus a two-additional-song instrument;
- Daurdabla, Marsyas, and Loughnashade behavior;
- exact-song refreshes, unique-song replacement, dummy songs, dispel/death recovery, and degraded operation.

This specification applies to **party-targeted beneficial songs** from one controlled Bard. Enemy-targeted debuff songs are outside the song-capacity algorithm. Multi-Bard interaction is not defined here because it introduces ownership questions that should be tested separately.

Normative terms:

- **MUST**: required for deterministic correctness.
- **SHOULD**: strongly recommended to avoid uncertain outcomes.
- **MAY**: optional behavior.

## 2. Canonical rule summary

A successful beneficial-song application to one recipient is resolved in this order:

1. **Exact spell already active:** replace that exact spell effect.
2. **Exact spell not active and a song position is available for this cast:** add the new effect.
3. **Exact spell not active and no position is available:** replace the active song with the **lowest remaining duration**.

The duration or potency of the incoming song is not compared with the outgoing song. The incoming song can be much shorter or weaker and still replace the current lowest-duration song.

“Same song” means the **same exact spell**, not merely the same family:

- `Valor Minuet II` and `Valor Minuet III` are different spells.
- `Mage's Ballad II` and `Mage's Ballad III` are different spells.
- Recasting `Valor Minuet II` targets the existing `Valor Minuet II`.
- Casting `Valor Minuet III` while `Valor Minuet II` is active follows the unique-song rules.

### 2.1 Correction of an obsolete rule

Before April 8, 2014, a song could be blocked from overwriting based on remaining duration. Square Enix changed Bard so that song effects may be overwritten regardless of remaining duration [S1]. A current BG Wiki overview still contains one sentence saying the same song cannot be reapplied until it falls below base duration; that sentence conflicts with the official 2014 change and with modern tested Bard behavior [S1, S8]. Code MUST use the post-2014 rule in this document.

## 3. Per-recipient state model

Song state is independent for every recipient. An area cast can therefore produce different results for different party members because each person may have:

- a different active-song count;
- different remaining durations;
- a dispelled or expired song;
- been outside range for an earlier cast;
- died, zoned, or joined the party later.

A correct automation MUST maintain state per recipient, not only one party-wide song state.

Represent each active effect as:

```text
SongEffect {
    exact_spell_id
    exact_spell_name
    applied_at
    estimated_expires_at
    estimated_remaining
    potency_profile
    duration_profile
    source_cast_id
}
```

Recommended recipient state:

```text
RecipientSongState {
    recipient_id
    active_effects[]
    active_count
    desired_exact_spell_ids[]
    confidence
    last_confirmed_at
    loss_reason
}
```

“Slot number” is useful planning language, but the game should be modeled primarily as an **active effect count plus replacement rules**. A song does not permanently own a numbered slot after subsequent overwrites.

## 4. Capacity at the instant a song resolves

For a main-job Bard:

```text
cast_capacity =
    2
    + additional_songs_from_equipped_instrument
    + (clarion_call_active ? 1 : 0)
```

Without an instrument, or when Bard is the support job, the normal base is one song [S2].

The instrument used for capacity is the instrument equipped when the song effect resolves. Precast equipment does not define the final capacity or song properties.

### 4.1 Instrument capacity table

| Instrument/state | Additional songs | Main-Bard capacity without Clarion | Capacity with Clarion |
|---|---:|---:|---:|
| Normal instrument, Marsyas, Gjallarhorn | 0 | 2 | 3 |
| Daurdabla level 90/95 | 1 | 3 | 4 |
| Daurdabla level 99/99 II | 2 | 4 | 5 |
| Loughnashade level 119 | 0 | 2 | 3 |
| Loughnashade level 119 II | 1 | 3 | 4 |
| Loughnashade level 119 III | 2 | 4 | 5 |

Additional-song properties from instruments do **not** stack with one another. Only the instrument resolving the current cast contributes its additional-song allowance. Daurdabla explicitly does not stack with other additional-song instruments [S4].

### 4.2 Capacity is permission to add, not a permanent equipment requirement

After a recipient has four or five active songs, replacing or refreshing an existing effect does not reduce the count merely because the Bard switches to an instrument with lower capacity.

Examples:

- Four active songs may be refreshed with Gjallarhorn, Marsyas, or another normal instrument.
- Five active songs may remain after Clarion Call expires.
- A new, different song cast while five songs remain active replaces one effect and leaves five active.
- If one of five songs is lost and the count falls to four, a two-additional-song instrument alone cannot restore the fifth. Clarion Call is required again.

## 5. Normative cast-resolution algorithm

```text
function apply_song(recipient, incoming_song, instrument, clarion_active, now):
    A = recipient.active_effects

    # Rule 1: exact-spell refresh
    existing = find effect in A where effect.exact_spell_id == incoming_song.spell_id
    if existing exists:
        remove existing
        add newly calculated incoming effect
        return EXACT_REFRESH

    # Rule 2: add when current cast has capacity
    K = capacity(instrument, clarion_active)
    if count(A) < K:
        add newly calculated incoming effect
        return ADDED

    # Rule 3: unique-song overwrite
    victim_set = effects in A having the minimum remaining duration at resolution
    if count(victim_set) != 1:
        return AMBIGUOUS_TIE_REQUIRES_SAFE_POLICY

    remove victim_set[0]
    add newly calculated incoming effect
    return REPLACED_LOWEST_REMAINING
```

### 5.1 Important consequences

- Exact refresh is evaluated before capacity.
- Exact refresh is safe even when the current active count exceeds the capacity of the equipped instrument.
- A different tier in the same family does not exact-refresh another tier.
- When no capacity is available, only the outgoing songs' remaining durations determine the victim.
- The new song's duration, potency, family, cast order, and instrument do not give it replacement priority.
- “Oldest song is removed” is only a useful shortcut when all active songs began with the same duration modifiers. It is not the rule.

## 6. Remaining-duration selection

The overwrite victim is the active song with the least server-side time remaining [S2, S8].

Beneficial songs normally have a 120-second base duration. `Song +N` adds 10% of base duration per point, general song-duration bonuses are additive with those bonuses, and Troubadour doubles the result after those duration bonuses [S2].

A simplified estimator is:

```text
estimated_duration =
    120 seconds
    * (1 + song_plus * 0.10 + additive_duration_percent)
    * troubadour_multiplier
    + applicable_fixed_seconds
```

The estimator MUST include all material duration differences used by the casting set. In particular:

- song-specific `Song +N` equipment;
- Daurdabla's instrument duration;
- Marsyas's +50% song duration;
- generic song-effect-duration gear;
- Troubadour;
- Marcato-related duration differences;
- Clarion Call Effect job-point duration;
- any special duration behavior used by the build.

### 6.1 Tie policy

The game's exact tie-break for genuinely equal remaining durations is not sufficiently documented for deterministic automation. Code MUST NOT intentionally depend on it.

If two candidate victims are within the implementation's timing uncertainty:

- mark the victim as ambiguous;
- avoid casting a different song;
- exact-refresh existing desired songs instead; or
- first create a clearly shorter disposable song.

A practical safety margin should exceed packet latency, action-processing delay, and timer-estimation error.

## 7. Instrument-specific behavior

## 7.1 Daurdabla

Daurdabla is primarily a capacity instrument:

- level 90/95: one additional song;
- level 99/99 II: two additional songs;
- level 99 provides +30% song duration;
- it does not provide `All Songs +N` potency [S4].

Therefore, songs initially applied through Daurdabla are often placeholders or lower-potency versions that are later replaced.

Two valid replacement patterns exist:

### Different-spell dummy pattern

1. Use Daurdabla to add disposable songs until the target reaches the intended count.
2. Make those disposable songs clearly shorter than protected songs.
3. Cast the desired different songs with their final instruments.
4. Each desired song replaces the current shortest dummy.

### Exact-spell seed pattern

1. Use Daurdabla to add the exact desired spell in an added position.
2. Recast that exact spell with the final potency instrument.
3. The exact-spell branch replaces its own Daurdabla version, regardless of duration.

The exact-spell pattern is safer because it does not depend on shortest-duration victim selection. It cannot seed songs that require a different instrument to be cast, such as Honor March.

## 7.2 Marsyas

Marsyas:

- grants **no additional song positions**;
- has `Song effect duration +50%`;
- is required to cast Honor March [S5].

Marsyas therefore has normal two-song capacity, or three while Clarion Call is active.

Honor March maintenance rules:

- If Honor March is already active, recasting Honor March with Marsyas exact-refreshes it without disturbing another song.
- If Honor March is missing and the recipient is below the required total count, Marsyas can add it only when its cast capacity exceeds the current count.
- If Honor March is missing from a full four- or five-song arrangement and Marsyas has no add capacity, it replaces the current lowest-duration song.
- To recover a missing Honor March safely in a four-song setup, first restore the fourth count with the additional-song instrument, then cast Honor March with Marsyas to replace a deliberately short placeholder.
- To recover a fifth Honor March after the count has fallen from five to four, Clarion Call must be available again.

## 7.3 Loughnashade

Loughnashade stages are materially different [S6, S7]:

- level 119: `All Songs +2`, no additional song;
- level 119 II: one additional song, `All Songs +3`;
- level 119 III: two additional songs, `All Songs +4`.

Loughnashade level 119 III combines four-song capacity and full `All Songs +4` potency for ordinary songs. Unlike Daurdabla, it does not require low-potency dummy songs merely to obtain four ordinary full-strength songs.

It also enables Aria of Passion at the appropriate Prime stages [S6, S9].

Limitations:

- It does not cast Honor March; Marsyas remains required.
- A specialized song instrument may provide different or superior song-specific bonuses. Such a song MAY be initially cast through Loughnashade to add it, then exact-refreshed with the specialized instrument.
- Additional-song capacity from Loughnashade does not combine with Daurdabla capacity.

## 8. Clarion Call

Clarion Call:

- lasts three minutes;
- adds one song position while active;
- conceptually supplies the third position;
- shifts the positions supplied by a two-additional-song instrument to the fourth and fifth [S3, S8].

For planning:

```text
No Clarion + two-additional-song instrument:
    positions 1-2 = normal
    positions 3-4 = instrument-enabled

Clarion + two-additional-song instrument:
    positions 1-2 = normal
    position 3 = Clarion-enabled
    positions 4-5 = instrument-enabled
```

These labels describe how capacity is opened. They are not reliable permanent identities after songs are overwritten.

### 8.1 Persistence after Clarion expires

Once five effects are active, they can be maintained indefinitely after Clarion Call expires, provided the count never falls below five [S3].

Safe maintenance:

- exact-refresh each desired spell before expiration;
- do not allow any effect to wear off;
- treat dispel, K.O., zoning, range failure, and missed casts as possible count-loss events.

A different song may replace one of the five while preserving a count of five, but that operation depends on shortest-duration selection and is less safe than exact refresh.

### 8.2 Loss of the Clarion-enabled count

If any one of five songs is lost after Clarion expires:

```text
active_count = 4
maximum add capacity with Daurdabla 99 or Loughnashade III = 4
```

A fifth song cannot be added. Casting additional different songs only replaces one of the four. The automation MUST enter a degraded four-song state until Clarion Call is available and used again.

### 8.3 Clarion Call Effect job points

Clarion Call Effect job points add two seconds of song duration per rank, up to 40 seconds at 20 ranks, for applicable songs sung under Clarion Call [S3]. This changes remaining-duration comparisons and must be included in duration estimates.

## 9. Deterministic operating procedures

## 9.1 Two-song initialization

Desired set: `S1, S2`.

1. Cast `S1` with its final instrument and duration set.
2. Cast `S2` with its final instrument and duration set.
3. Confirm both recipients and effects.

No dummy songs are required.

### Two-song maintenance

For each desired exact spell:

1. Refresh before its safe expiration threshold.
2. Recast the same exact spell.
3. Do not substitute a different tier unless replacement of the lowest-duration song is intended.

### Two-song recovery

If one song is missing, cast the missing song with any instrument that permits normal two-song capacity. It adds while count is one.

## 9.2 Four songs with Daurdabla 99

Desired set: `S1, S2, S3, S4`.

### Recommended exact-seed sequence

1. Cast two desired songs with their final instruments.
2. Equip Daurdabla.
3. Cast the exact desired `S3`; it adds as the third effect.
4. Cast the exact desired `S4`; it adds as the fourth effect.
5. Recast `S3` with its final instrument; it exact-refreshes itself.
6. Recast `S4` with its final instrument; it exact-refreshes itself.
7. Confirm the final exact set.

If `S3` or `S4` is Honor March, it cannot be seeded with Daurdabla. Use the dummy sequence instead or place Honor March among the first two.

### Honor-March-aware sequence

1. Cast Honor March with Marsyas as one of the first two songs.
2. Cast another final desired song.
3. Use Daurdabla to add the exact remaining two desired spells.
4. Recast those two exact spells with final potency instruments.

### Different-dummy sequence

1. Cast two final desired songs.
2. Use Daurdabla and a deliberately low-duration set to add two disposable songs.
3. Cast the remaining two desired songs in the intended victim order.
4. Confirm that each cast replaced a dummy, not a protected song.

### Four-song maintenance

Exact-refresh every desired song with its final instrument. Daurdabla is not required while all four remain active.

### Four-song recovery after one loss

If active count is three:

- **Missing song castable with Loughnashade III:** cast it directly with Loughnashade to add it.
- **Using Daurdabla and missing song is normally castable:** cast the missing exact spell with Daurdabla to add it, then exact-refresh it with the final instrument.
- **Missing song requires Marsyas:** add a short placeholder with Daurdabla, then cast Honor March with Marsyas. The placeholder MUST be the uniquely shortest song.

## 9.3 Four songs with Loughnashade III

For four ordinary songs:

1. Cast all four desired songs with Loughnashade III.
2. Exact-refresh any song that requires a specialized final instrument.

No capacity dummies are required.

If Honor March is desired:

1. Cast Honor March with Marsyas early, while the current count is below Marsyas's capacity.
2. Cast the other three desired songs with Loughnashade III.
3. Exact-refresh specialized songs as required.

A robust order from zero is:

```text
Honor March with Marsyas
S2 with Loughnashade III
S3 with Loughnashade III
S4 with Loughnashade III
```

## 9.4 Five songs with Daurdabla 99 and Clarion Call

Desired set: `S1, S2, S3, S4, S5`.

### Recommended sequence

1. Cast two desired songs normally.
2. Activate Clarion Call.
3. Cast a third desired song with its required final instrument. Marsyas/Honor March is a good candidate.
4. Equip Daurdabla.
5. Cast the exact desired `S4`; it adds as the fourth effect.
6. Cast the exact desired `S5`; it adds as the fifth effect.
7. Recast `S4` and `S5` with their final instruments.
8. Finish this process for every recipient before Clarion Call expires.
9. Thereafter, maintain all five only through exact refreshes whenever possible.

Alternative: use three Daurdabla dummies after the initial two, then replace all three with final desired songs. This is more dependent on duration ordering.

## 9.5 Five songs with Loughnashade III and Clarion Call

Loughnashade III permits direct full-potency application of ordinary songs.

Recommended sequence:

1. Activate Clarion Call.
2. Cast Honor March with Marsyas first if it is desired.
3. Cast the remaining desired songs with Loughnashade III until count reaches five.
4. Exact-refresh any specialized songs with their final instruments.
5. Complete all recipients before Clarion expires.
6. Maintain through exact refreshes.

From zero, with Honor March plus four ordinary songs:

```text
Clarion Call
Honor March with Marsyas
S2 with Loughnashade III
S3 with Loughnashade III
S4 with Loughnashade III
S5 with Loughnashade III
```

## 10. Recovery matrix

| Intended state | Current count | Clarion active? | Additional-song instrument needed? | Correct action |
|---|---:|---:|---:|---|
| 2 songs | 1 | No | No | Cast missing exact song; it adds |
| 4 songs | 3 | No | Yes, +2 instrument | Add missing exact song through capacity, or add dummy then replace |
| 4 songs | 4 | No | No for refresh | Exact-refresh existing songs |
| 5 songs | 5 | No | No for refresh | Exact-refresh; never permit count loss |
| 5 songs | 4 | No | Insufficient | Enter degraded four-song state; wait for Clarion |
| 5 songs | 4 | Yes | Yes, +2 instrument | Add fifth exact song or dummy, then apply final instrument |
| 5 songs | 3 or less | Yes | Yes | Rebuild to five while Clarion remains active |

## 11. Automation state machine

Recommended high-level states:

```text
EMPTY
BUILDING_2
STABLE_2
BUILDING_4
STABLE_4
BUILDING_5_CLARION
STABLE_5_PERSISTED
DEGRADED_4_WAITING_FOR_CLARION
UNKNOWN_OR_DIVERGED
```

### 11.1 Transition examples

```text
EMPTY -> BUILDING_4
    requested plan has four songs

BUILDING_4 -> STABLE_4
    every intended recipient has the exact desired set

STABLE_5_PERSISTED -> DEGRADED_4_WAITING_FOR_CLARION
    confirmed song loss reduces any required recipient to four after Clarion expires

DEGRADED_4_WAITING_FOR_CLARION -> BUILDING_5_CLARION
    Clarion becomes available and rebuild begins

ANY -> UNKNOWN_OR_DIVERGED
    state evidence conflicts, target range is uncertain, untracked Bard casts occur,
    or victim selection cannot be determined
```

### 11.2 Planner priorities

The planner SHOULD choose actions in this order:

1. Prevent expiration of a persisted fifth song.
2. Exact-refresh a desired song.
3. Add a missing song when current cast capacity permits.
4. Add a disposable short placeholder to restore count.
5. Perform a unique-song overwrite only when the victim is uniquely predictable.
6. Refuse or defer a unique overwrite when the victim is ambiguous.

## 12. Required implementation safeguards

### 12.1 Per-target confirmation

An AoE cast MUST NOT be assumed to affect every intended member. Track confirmations or conservatively mark unconfirmed recipients unknown.

### 12.2 Exact spell identity

Do not collapse all Minuets, Ballads, Marches, Madrigals, or other tiers into one desired-state key. The exact spell ID is required.

### 12.3 Duration confidence

A client-side timer is an estimate. The implementation SHOULD retain:

- expected duration;
- packet/action timestamp;
- gear/instrument profile used;
- confidence and error margin.

When duration confidence is low, exact refresh is safe; unique-song replacement is not.

### 12.4 Loss invalidation

K.O., zoning, dispel, natural expiration, party change, missed range, and external song casts MUST invalidate or downgrade confidence for the affected recipient.

### 12.5 Clarion deadline

A five-song builder MUST track the Clarion expiration deadline and stop starting recipients it cannot finish. Partial five-song coverage creates asymmetric states that require per-target recovery.

## 13. Edge cases

### 13.1 Original example

Active:

```text
Valor Minuet II: 180 seconds remaining
Dragonfoe Mambo: 205 seconds remaining
```

Incoming:

```text
Valor Minuet III
```

`Valor Minuet III` is not the exact same spell as `Valor Minuet II`. At two-song capacity, it replaces the lowest remaining effect: `Valor Minuet II`.

If Mambo had 170 seconds remaining instead, Mambo would be replaced.

### 13.2 Exact refresh ignores shortest-song selection

Active:

```text
Valor Minuet II: 300 seconds remaining
Mambo: 40 seconds remaining
```

Incoming:

```text
Valor Minuet II
```

The existing `Valor Minuet II` is replaced. Mambo remains, even though it has less time remaining.

### 13.3 Four active, normal instrument, different song

Active count is four from Daurdabla. The Bard casts a different song using Gjallarhorn, whose current cast capacity is two.

Because the target already has at least the current capacity, the cast does not collapse the target to two songs. It replaces the lowest-duration active song and leaves four active.

### 13.4 Five persisted after Clarion expires

Five exact desired songs are active. Clarion expires. Recasting any one of the same exact songs refreshes that song and preserves five.

### 13.5 One of five is dispelled after Clarion expires

Count falls to four. Daurdabla 99 or Loughnashade III supplies capacity four, not five. The fifth cannot be restored until Clarion Call is active again.

### 13.6 Recovering missing Honor March in a four-song state

Count is three and Honor March is missing.

1. Add a short disposable song with Daurdabla 99 or Loughnashade III.
2. Cast Honor March with Marsyas.
3. Honor March replaces the disposable song because it is uniquely shortest.

Casting Honor March with Marsyas immediately at count three would not add a fourth under Marsyas's normal capacity of two; it would replace the shortest existing song and leave count three.

### 13.7 Ambiguous equal timers

Two songs are estimated at 240.0 seconds remaining with ±1.0 second confidence. A different incoming song has no deterministic victim. The planner must not claim which song will be removed.

## 14. External shared song/roll limit

There is also a 12-effect shared limit between Bard songs and Corsair Phantom Rolls. At that separate limit, newly applied effects can remove older shared-slot effects in application order [S2].

This is not the same as the Bard capacity algorithm:

- Bard capacity replacement uses lowest remaining song duration.
- The shared song/roll ceiling is an external effect-cap constraint.

Automation SHOULD detect unexpected song loss even when its Bard-slot calculations were correct.

## 15. Test vectors for code

### TV-01: unique tier replaces shortest

```json
{
  "active": [
    {"spell": "Valor Minuet II", "remaining": 180},
    {"spell": "Dragonfoe Mambo", "remaining": 205}
  ],
  "incoming": "Valor Minuet III",
  "capacity": 2,
  "expected_removed": "Valor Minuet II",
  "expected_count": 2
}
```

### TV-02: exact spell refresh

```json
{
  "active": [
    {"spell": "Valor Minuet II", "remaining": 300},
    {"spell": "Dragonfoe Mambo", "remaining": 40}
  ],
  "incoming": "Valor Minuet II",
  "capacity": 2,
  "expected_removed": "Valor Minuet II",
  "expected_preserved": "Dragonfoe Mambo",
  "expected_result": "EXACT_REFRESH"
}
```

### TV-03: lower-capacity instrument preserves four by replacement

```json
{
  "active_count": 4,
  "cast_capacity": 2,
  "incoming_exact_spell_already_active": false,
  "expected_result": "REPLACE_LOWEST_REMAINING",
  "expected_count": 4
}
```

### TV-04: persisted five exact refresh

```json
{
  "active_count": 5,
  "clarion_active": false,
  "cast_capacity": 2,
  "incoming_exact_spell_already_active": true,
  "expected_result": "EXACT_REFRESH",
  "expected_count": 5
}
```

### TV-05: fifth lost after Clarion

```json
{
  "desired_count": 5,
  "active_count": 4,
  "clarion_active": false,
  "instrument_additional_songs": 2,
  "expected_max_add_capacity": 4,
  "expected_state": "DEGRADED_4_WAITING_FOR_CLARION"
}
```

### TV-06: ambiguous victim

```json
{
  "active": [
    {"spell": "S1", "remaining_estimate": 200, "error": 1},
    {"spell": "S2", "remaining_estimate": 200.5, "error": 1}
  ],
  "incoming_exact_spell_already_active": false,
  "expected_result": "AMBIGUOUS_TIE_REQUIRES_SAFE_POLICY"
}
```

## 16. Sources

- **[S1]** Square Enix, *Apr 8, 2014 (JST) Version Update*: “Song effects may now be overwritten regardless of their remaining duration.”
  https://forum.square-enix.com/ffxi/threads/41117
- **[S2]** BG Wiki, *Category: Song*: baseline capacity, lowest-remaining-duration overwrite, duration model, and shared song/roll limit.
  https://www.bg-wiki.com/ffxi/Category%3ASong
- **[S3]** BG Wiki, *Clarion Call*: +1 capacity, conceptual third position, persistence, and loss behavior.
  https://www.bg-wiki.com/ffxi/Clarion_Call
- **[S4]** BG Wiki, *Daurdabla (Level 99)*: +2 songs, +30% duration, position interaction, dummy technique, and non-stacking.
  https://www.bg-wiki.com/ffxi/Daurdabla_%28Level_99%29
- **[S5]** BG Wiki, *Marsyas*: +50% duration and Honor March requirement.
  https://www.bg-wiki.com/ffxi/Marsyas
- **[S6]** BG Wiki, *Loughnashade (Level 119 III)*: +2 songs, All Songs +4, and Aria of Passion.
  https://www.bg-wiki.com/ffxi/Loughnashade_%28Level_119_III%29
- **[S7]** BG Wiki, *May 2023 Version Update Changes*: Loughnashade stage-by-stage properties.
  https://www.bg-wiki.com/ffxi/May_2023_Version_Update_Changes
- **[S8]** BG Wiki, *Obamiwannabuffya: A Bard Guide*: modern same-song, lowest-duration, dummy, and Clarion maintenance behavior.
  https://www.bg-wiki.com/ffxi/Obamiwannabuffya%3A_A_Bard_Guide_by_Funkworkz
- **[S9]** BG Wiki, *Aria of Passion*: Loughnashade casting requirement.
  https://www.bg-wiki.com/ffxi/Aria_of_Passion

## 17. Confidence and unresolved detail

The three-branch cast-resolution model is strongly supported by the official 2014 adjustment and modern Bard documentation. Instrument and Clarion capacities are directly documented.

One detail is intentionally not asserted: the server's tie-break when multiple songs have exactly equal remaining duration. Deterministic code should avoid creating that condition rather than inventing a tie rule.
