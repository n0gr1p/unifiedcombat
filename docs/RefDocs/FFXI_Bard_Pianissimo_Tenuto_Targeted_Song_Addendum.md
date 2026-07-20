# Addendum A — Pianissimo, Tenuto, and Per-Recipient Bard Song Automation

**Companion to: FFXI Bard Enhancing-Song Capacity, Overwrite, and Maintenance Logic**  
**Version 1.0 — July 20, 2026**

## 1. Purpose and scope

This addendum defines how Bard automation should use **Pianissimo** and **Tenuto** when individual party members require different song sets or when one member must be rebuilt without altering the rest of the party.

The ability is correctly spelled **Tenuto**. “Tunuto” is treated as a spelling variant in user input only.

This document extends the parent specification. Unless explicitly overridden here, the parent rules remain normative:

1. exact-spell refresh;
2. add when the resolving cast has capacity;
3. otherwise replace the active song with the lowest remaining duration.

The main use cases are:

- giving a Paladin a single-target Ballad, Sirvente, Carol, or other specialized song;
- adding Daurdabla-enabled positions to one new, dispelled, or revived party member;
- rebuilding one recipient without applying dummy songs to everyone;
- maintaining a Bard-only Ballad or defensive song with Tenuto;
- preserving deterministic per-recipient state during targeted recovery.

## 2. Canonical distinction

> **Pianissimo changes the recipient set. Tenuto changes overwrite eligibility for the Bard’s own song effect. Neither ability creates an additional song position.**

| Ability | What it changes | What it does not change |
|---|---|---|
| Pianissimo | The next eligible enhancing song affects one selected party member instead of the normal area | Capacity, potency, duration, exact-spell identity, or overwrite victim selection |
| Tenuto | If the next song affects the Bard, the Bard’s copy becomes protected from ordinary subsequent songs | Targeting, area of effect, party-member capacity, or instrument requirements |

## 3. Pianissimo normative behavior

Pianissimo is obtained at Bard level 20. It lasts up to 60 seconds or until the next eligible song, and has a five-second recast [S1, S2].

While active:

- the next eligible enhancing song can be directed at one party member;
- only that selected recipient receives the song;
- the song uses the same capacity and overwrite rules it would use if delivered by an area cast;
- base song casting time is reduced to four seconds;
- Pianissimo Effect job points reduce casting time by 2% per rank, up to 40% at 20 ranks [S1, S3].

Community documentation reports a Pianissimo song-targeting range of approximately 20 yalms [S4]. Automation SHOULD use a safety margin and treat the server action result as authoritative.

### 3.1 Pianissimo does not create capacity

For the selected recipient:

```text
pianissimo_capacity =
    normal capacity of the instrument equipped when the song resolves
    + Clarion Call capacity, if active
```

Examples:

```text
Marsyas + no Clarion       -> capacity 2
Daurdabla 99 + no Clarion  -> capacity 4
Loughnashade III           -> capacity 4
Marsyas + Clarion          -> capacity 3
Daurdabla 99 + Clarion     -> capacity 5
```

Pianissimo only restricts the application to one recipient. It does not add a “Pianissimo slot.”

### 3.2 Pianissimo resolution algorithm

```text
function apply_pianissimo_song(target, incoming_song, instrument, clarion_active):
    assert target is an eligible current party member
    assert Pianissimo is confirmed active

    recipients = [target]                  # no area recipients
    result = apply_parent_song_algorithm(
        recipient = target,
        incoming_song = incoming_song,
        capacity = capacity(instrument, clarion_active)
    )

    return result
```

The selected recipient still follows the parent rules:

1. same exact spell already active -> refresh that exact spell;
2. exact spell absent and count below resolving capacity -> add;
3. otherwise -> replace the lowest-remaining eligible song.

### 3.3 One Pianissimo activation per song

Pianissimo modifies only the next eligible song. Every song in a targeted sequence requires a new Pianissimo activation.

Automation MUST NOT assume that one Pianissimo activation covers a multi-song queue.

Recommended transaction:

```text
acquire targeted-song lock
select recipient by stable server ID
verify recipient is in the current party
verify range
use Pianissimo
wait for confirmed Pianissimo status
cast one song at that recipient
hold the required instrument through resolution
wait for the song action result
update only that recipient’s state
release or continue the targeted-song lock
```

A fixed sleep is less reliable than observing the ability status or action packet. The five-second recast is normally short enough to be ready by the next song, but code MUST confirm recast readiness.

### 3.4 Failed or interrupted casts

Public documentation does not fully define whether every possible failed, interrupted, or invalid-target song attempt consumes Pianissimo.

After any abnormal cast result, automation MUST:

- stop the sequence;
- reread Pianissimo status;
- mark the recipient state unconfirmed;
- reissue Pianissimo if its status is absent or uncertain;
- never assume the intended song landed.

## 4. Giving one Paladin a Ballad

Assume the party has these area songs:

```text
Honor March
Valor Minuet V
```

The Paladin needs `Mage's Ballad III`.

### 4.1 Normal instrument or Marsyas

The Paladin already has two songs and the resolving instrument has capacity two.

```text
Pianissimo
Mage's Ballad III -> PLD
```

Ballad III is not added. It replaces whichever of the Paladin’s two active songs has the lowest remaining duration.

Pianissimo does not let code select Honor March or Minuet as the victim.

### 4.2 Daurdabla 99 or Loughnashade III

The Paladin has two songs and the resolving instrument has capacity four.

```text
Pianissimo
Mage's Ballad III -> PLD, resolving with Daurdabla 99
```

Ballad III is added as the Paladin’s third active effect. No other party member receives it.

If Daurdabla supplied the added position, the Ballad may have lower potency or duration than the final desired version. It can then be exact-refreshed only on the Paladin:

```text
Pianissimo
Mage's Ballad III -> PLD, resolving with final potency instrument
```

Because the exact same spell is already active, the second cast refreshes the Ballad III effect without selecting another victim.

With Loughnashade III, ordinary songs can usually be added at full `All Songs +4` potency in one targeted cast.

### 4.3 Adding two Ballads

Different Ballad tiers are different exact spells.

To give only the Paladin two Ballads while preserving two party songs:

```text
PLD starts with:
    Honor March
    Valor Minuet V

Pianissimo + Daurdabla/Loughnashade:
    Mage's Ballad III -> added as song 3

Pianissimo + Daurdabla/Loughnashade:
    Mage's Ballad II -> added as song 4
```

Recasting `Mage's Ballad III` does not add another Ballad. It exact-refreshes the existing Ballad III.

### 4.4 Full target with no available position

If the Paladin already has four songs and Daurdabla 99 or Loughnashade III resolves the cast, capacity equals the current count.

A new Ballad tier replaces the Paladin’s lowest-remaining song. The automation must either:

- accept that victim;
- deliberately make the intended disposable song uniquely shortest; or
- wait until a position is naturally available.

## 5. Per-recipient Daurdabla slot creation

Yes: **Pianissimo can be combined with Daurdabla to add Daurdabla-enabled songs to one party member without giving dummy songs to the whole party.** This is one of the most useful recovery patterns for automation [S5, S6].

### 5.1 Rebuilding one member from zero to four songs

Assume a party member died and now has zero songs, while the rest of the party still has four long-duration songs.

Desired exact set:

```text
Honor March
Valor Minuet V
Valor Minuet IV
Blade Madrigal
```

Safe targeted sequence:

```text
1. Pianissimo + Marsyas:
       Honor March -> member
   Current count: 1

2. Pianissimo + final instrument:
       Valor Minuet V -> member
   Current count: 2

3. Pianissimo + Daurdabla 99:
       Valor Minuet IV -> member
   Current count: 3

4. Pianissimo + Daurdabla 99:
       Blade Madrigal -> member
   Current count: 4

5. Pianissimo + final potency instrument:
       Valor Minuet IV -> exact refresh

6. Pianissimo + final potency instrument:
       Blade Madrigal -> exact refresh
```

Only the recovered member receives these casts. Existing songs on everyone else remain untouched.

Honor March is placed while the recipient has fewer than Marsyas’s capacity of two. Marsyas must remain equipped through Honor March resolution.

### 5.2 Dummy-based targeted rebuild

A generic target-only rebuild can use short disposable songs:

```text
for each required position:
    Pianissimo
    cast a unique short dummy on target with Daurdabla

for each final desired song:
    Pianissimo
    cast final song on target with its required instrument
```

The final different songs replace the shortest dummies in sequence.

The exact-seed method is preferred when possible because it avoids victim-selection ambiguity.

### 5.3 Recovering missing Honor March at count three

The recipient has three protected final songs and is missing Honor March.

Marsyas has capacity two, so Pianissimo plus Marsyas cannot add a fourth song directly.

Safe sequence:

```text
1. Pianissimo + Daurdabla:
       add a deliberately short placeholder as song 4

2. Pianissimo + Marsyas:
       Honor March replaces the uniquely shortest placeholder
```

The placeholder must be shorter than every protected final song on that recipient.

### 5.4 Recovering a fifth song

Pianissimo does not replace Clarion Call.

If a recipient falls from five songs to four after Clarion Call expires:

```text
current count = 4
Daurdabla 99 capacity = 4
Loughnashade III capacity = 4
```

No targeted cast can add a fifth song. Pianissimo can change or refresh the four effects, but the recipient remains in a degraded four-song state until Clarion Call is available.

While Clarion Call is active, Pianissimo and a two-additional-song instrument can build that individual recipient to five.

## 6. Pianissimo and instrument-exclusive songs

Pianissimo is compatible with the normal instrument requirement of the song being cast.

It does not allow one instrument to authorize a song while another instrument supplies capacity.

### 6.1 Honor March

```text
Pianissimo active
Honor March targeted at PLD
Marsyas remains equipped through resolution
```

The cast uses Marsyas capacity, not Daurdabla capacity.

To recover Honor March into a full four-song target, use a Daurdabla placeholder first, then replace it with Pianissimo Honor March.

### 6.2 Aria of Passion

Aria of Passion must resolve with a qualifying Loughnashade stage. Pianissimo can target Aria to one recipient, but the required Loughnashade must remain equipped.

## 7. Tenuto normative behavior

Tenuto is obtained at Bard level 83. It lasts up to 60 seconds or until the next appropriate song, and has a five-second recast [S7, S8].

Its official behavior is:

> If the next song affects the Bard, the Bard’s copy will not subsequently be overwritten by ordinary other songs.

Important consequences:

- Tenuto does **not** make the song single-target.
- The song remains a normal area song.
- Nearby party members can receive the song.
- Only the Bard’s own copy receives Tenuto overwrite protection.
- Tenuto-protected songs remain until natural loss or replacement by another Tenuto-modified song.
- It is possible to maintain up to five Tenuto-protected songs on the Bard, subject to normal capacity [S7].

Tenuto Effect job points add two seconds per rank, up to 40 seconds, to the Bard’s Tenuto song duration [S3, S9].

### 7.1 Tenuto does not stack with Pianissimo

Tenuto and Pianissimo are explicitly documented as not stacking [S7, S10].

Automation MUST treat them as mutually exclusive next-song modifiers:

```text
assert not (pianissimo_active and tenuto_active)
```

Do not attempt:

```text
Tenuto
Pianissimo
Ballad -> self
```

The result is not a supported way to create a Bard-only protected song.

### 7.2 Tenuto is not a targeting ability

To give only the Bard a Tenuto Ballad without also giving it to party members, the Bard must be positioned outside their song area before casting.

Recommended sequence:

```text
1. Move Bard outside party song range.
2. Activate Tenuto.
3. Cast Mage's Ballad III as a normal self-centered area song.
4. Confirm the Bard received the protected effect.
5. Return to group-song position.
6. Sing the party’s normal songs.
```

A wind instrument’s smaller predictable area is generally easier to isolate than a wide string-instrument area, but automation should verify recipient results rather than trusting position alone.

### 7.3 Protected-song model

Represent the Bard’s own song effects with an additional field:

```text
SongEffect {
    exact_spell_id
    estimated_expires_at
    tenuto_protected
}
```

For the Bard only:

```text
function apply_song_to_bard(incoming, tenuto_active):
    if tenuto_active:
        apply using normal exact/add/lowest-duration rules
        resulting Bard effect.tenuto_protected = true
        apply Tenuto JP duration to Bard copy
        return

    # ordinary song
    if exact matching Bard effect is Tenuto-protected:
        do not assume it refreshes
        require Tenuto before refreshing that protected effect

    eligible_victims = active Bard effects where tenuto_protected == false

    if capacity permits an add:
        add ordinary effect
    else if eligible_victims is not empty:
        replace the eligible victim with lowest remaining duration
    else:
        Bard’s active set remains unchanged
```

The last branch is an implementation consequence of the documented protection rule: when all full-capacity Bard songs are Tenuto-protected, an ordinary song has no eligible Bard effect to replace. The same area cast can still apply normally to nearby party members.

### 7.4 Refreshing a Tenuto-protected song

A protected song should be refreshed with Tenuto again:

```text
Tenuto
same exact protected song
```

Community testing specifically documents reapplying Tenuto songs by using Tenuto on the refresh [S11].

Automation MUST NOT issue an ordinary exact refresh and assume the protected Bard copy was updated. The party copies may refresh while the Bard’s protected copy remains unchanged, creating timer divergence.

### 7.5 Bard-only specialized song set

Example:

```text
Bard wants:
    Mage's Ballad III
    Mage's Ballad II

Party wants:
    Honor March
    Valor Minuet V
    Valor Minuet IV
    Blade Madrigal
```

Possible strategy:

```text
1. Separate Bard from party.
2. Tenuto + Ballad III.
3. Tenuto + Ballad II.
4. Return to party.
5. Cast party songs normally.
```

The Bard’s Ballads are protected from ordinary party-song overwrites. The Bard still has the same total song-capacity limit as everyone else; protected Ballads consume Bard song positions.

### 7.6 Never Tenuto a disposable dummy

A Tenuto-protected dummy resists ordinary replacement and defeats the purpose of a disposable song.

Automation MUST classify dummy songs as:

```text
tenuto_allowed = false
```

If a dummy is accidentally Tenuto-protected, replacement must be performed with another Tenuto-modified song or the dummy must expire/be removed.

### 7.7 Tenuto and fifth-song persistence

Tenuto adds protection, not capacity.

A Bard can Tenuto five songs only while the Bard has five available active positions. If one of five expires after Clarion Call ends, Tenuto cannot restore the fifth position without Clarion Call.

## 8. Per-recipient state implications

Pianissimo and Tenuto make party-wide state insufficient.

The same area song can produce different metadata:

```text
Bard copy:
    Mage's Ballad III
    tenuto_protected = true
    longer Tenuto-JP duration

PLD copy:
    Mage's Ballad III
    tenuto_protected = false
    normal duration

Other party members:
    may not have received the song due to range
```

Recommended state:

```text
RecipientSongState {
    recipient_server_id
    active_effects[]
    desired_effects[]
    desired_count
    recovery_mode
    last_targeted_cast_id
    confidence
}

SongEffect {
    exact_spell_id
    applied_at
    estimated_expires_at
    source_instrument
    source_modifiers {
        pianissimo
        tenuto
        clarion_call
        marcato
        troubadour
        soul_voice
    }
    tenuto_protected       # meaningful only for Bard self
}
```

## 9. Targeted-recovery state machine

```text
TARGET_STABLE
TARGET_MISSING_SONG
TARGET_REBUILDING_CAPACITY
TARGET_REPLACING_DUMMIES
TARGET_WAITING_FOR_CLARION
TARGET_UNKNOWN
```

Recommended transitions:

```text
TARGET_STABLE -> TARGET_MISSING_SONG
    dispel, expiration, K.O., zone, or missing confirmation

TARGET_MISSING_SONG -> TARGET_REBUILDING_CAPACITY
    current count is below desired count and instrument can add

TARGET_REBUILDING_CAPACITY -> TARGET_REPLACING_DUMMIES
    desired count reached with placeholders

TARGET_REPLACING_DUMMIES -> TARGET_STABLE
    exact desired set confirmed

ANY -> TARGET_WAITING_FOR_CLARION
    desired count is five, current count is four, Clarion inactive

ANY -> TARGET_UNKNOWN
    invalid target, interrupted cast, uncertain Pianissimo state,
    unexpected area cast, external Bard cast, or conflicting evidence
```

## 10. Scheduler and locking requirements

### 10.1 Serialize targeted transactions

A targeted rebuild MUST hold a song-operation lock. Do not allow an area-song maintenance cycle to interleave between:

```text
targeted dummy add
targeted final replacement
```

An interleaved area cast can alter the recipient’s timers and change the overwrite victim.

### 10.2 Use stable identity

Target party members by server ID or equivalent stable identity, not only by party-list index. Party ordering can change during the sequence.

### 10.3 Revalidate before every song

Before each Pianissimo cast:

- recipient still exists;
- recipient is still in the same party;
- recipient is alive;
- recipient is in range;
- the desired song is still missing or needs refresh;
- Pianissimo recast is ready;
- the required instrument is available.

### 10.4 Hold the instrument through resolution

Pianissimo shortens casting time. With Pianissimo job points, Fast Cast, Nightingale, or Quick Magic, the equipment-swap window can be very small.

Automation MUST preselect or equip the required resolving instrument early enough to guarantee:

- Daurdabla/Loughnashade capacity is present when adding a position;
- Marsyas remains equipped for Honor March;
- Loughnashade remains equipped for Aria of Passion;
- final potency and duration equipment is active at resolution.

### 10.5 Confirm action completion, not animation timing

Do not start the next target transaction based only on an animation delay. Wait for the action result or a reliable aftercast-equivalent event.

### 10.6 Targeted recovery action cost

A four-song Daurdabla recovery can require:

```text
4 Pianissimo activations
4 initial song casts
2 additional Pianissimo activations
2 final exact refreshes
```

That is twelve Bard actions for one recipient in the example sequence. A five-song rebuild can require more.

The planner should calculate whether the sequence can finish before Clarion Call, Nightingale, Troubadour, Soul Voice, or Marcato windows expire.

## 11. Other ability interactions worth modeling

### 11.1 Nightingale

Nightingale reduces song casting and recast times. It does not change Pianissimo targeting or create capacity.

Because Pianissimo already lowers base casting time, their combination increases the risk that midcast instrument selection occurs too late.

### 11.2 Troubadour

Troubadour doubles applicable song duration and does not change recipient selection.

Targeted and area recipients can develop dramatically different remaining durations when only some members are rebuilt under Troubadour. The overwrite planner must use per-recipient timers.

### 11.3 Soul Voice and Marcato

Pianissimo can direct a high-value Soul Voice or Marcato song to one recipient without affecting others. These abilities change song strength or duration, not capacity or victim selection.

A targeted Marcato song can become much longer than other songs and therefore difficult to replace intentionally. Store its source modifiers in the timer model.

### 11.4 Clarion Call

Clarion Call is global Bard state, but its capacity is evaluated independently for each recipient at each resolving cast.

Pianissimo can use the Clarion window to build one lagging member to five without disturbing the rest of the party. The planner must finish that member before Clarion expires.

### 11.5 Job-ability enmity

Pianissimo and Tenuto are documented with zero cumulative enmity and 80 volatile enmity [S1, S7].

Automation should avoid unnecessary ability spam while the Bard is on an active hate list, even though the amount is small.

## 12. Test vectors

### TV-A01: Pianissimo adds target-only third song

```json
{
  "target": "PLD",
  "target_active_count": 2,
  "other_members_active_count": 2,
  "incoming": "Mage's Ballad III",
  "pianissimo": true,
  "instrument": "Daurdabla 99",
  "clarion": false,
  "expected_target_result": "ADDED",
  "expected_target_count": 3,
  "expected_other_members_change": false
}
```

### TV-A02: Pianissimo with normal capacity replaces target’s shortest

```json
{
  "target_active": [
    {"spell": "Honor March", "remaining": 300},
    {"spell": "Valor Minuet V", "remaining": 260}
  ],
  "incoming": "Mage's Ballad III",
  "pianissimo": true,
  "instrument_capacity": 2,
  "expected_removed": "Valor Minuet V",
  "expected_count": 2
}
```

### TV-A03: Targeted exact refresh after Daurdabla seed

```json
{
  "target_active": [
    {"spell": "Mage's Ballad III", "source": "Daurdabla 99"}
  ],
  "incoming": "Mage's Ballad III",
  "pianissimo": true,
  "source_instrument": "final potency instrument",
  "expected_result": "EXACT_REFRESH",
  "expected_other_song_removed": false
}
```

### TV-A04: Missing Honor March at count three

```json
{
  "target_count": 3,
  "honor_march_active": false,
  "clarion": false,
  "steps": [
    "Pianissimo + Daurdabla short placeholder",
    "Pianissimo + Marsyas Honor March"
  ],
  "expected_final_count": 4,
  "expected_removed": "short placeholder"
}
```

### TV-A05: Fifth cannot be restored by Pianissimo

```json
{
  "desired_count": 5,
  "target_count": 4,
  "pianissimo": true,
  "instrument_additional_songs": 2,
  "clarion": false,
  "expected_result": "NO_CAPACITY_TO_ADD_FIFTH",
  "expected_state": "TARGET_WAITING_FOR_CLARION"
}
```

### TV-A06: Tenuto does not single-target

```json
{
  "tenuto": true,
  "pianissimo": false,
  "bard_in_party_song_range": true,
  "incoming": "Mage's Ballad III",
  "expected_bard_copy_protected": true,
  "expected_nearby_party_can_receive_song": true
}
```

### TV-A07: Protected refresh requires Tenuto

```json
{
  "bard_active": [
    {"spell": "Mage's Ballad III", "tenuto_protected": true}
  ],
  "incoming": "Mage's Ballad III",
  "tenuto": false,
  "expected_safe_automation_action": "DO_NOT_ASSUME_REFRESH",
  "required_action": "Activate Tenuto and recast"
}
```

### TV-A08: Tenuto and Pianissimo conflict

```json
{
  "pianissimo_active": true,
  "tenuto_active": true,
  "expected_planner_result": "INVALID_MODIFIER_COMBINATION",
  "expected_action": "Abort and normalize ability state"
}
```

### TV-A09: All Bard songs protected

```json
{
  "bard_count": 4,
  "bard_capacity": 4,
  "all_bard_songs_tenuto_protected": true,
  "incoming_tenuto": false,
  "incoming_exact_spell_is_protected": false,
  "expected_bard_set_change": false,
  "expected_party_area_application": "independent"
}
```

## 13. Implementation checklist

A compliant automation MUST:

- spell and identify Tenuto correctly;
- track songs per recipient;
- require one Pianissimo activation per targeted song;
- use the resolving instrument’s capacity;
- permit Pianissimo plus Daurdabla to add positions to only one member;
- never treat Pianissimo as capacity;
- never treat Tenuto as single-target;
- never combine Tenuto and Pianissimo;
- mark Tenuto protection only on the Bard’s copy;
- use Tenuto again to refresh protected songs;
- prohibit Tenuto on dummy songs;
- preserve Marsyas for Honor March resolution;
- degrade a lost five-song recipient to four when Clarion is unavailable;
- serialize targeted recovery against area maintenance;
- handle failed actions as uncertain state;
- confirm every recipient independently.

## 14. Sources

- **[S1]** BG Wiki, *Pianissimo*: single-target next song, 60-second status, five-second recast, four-second base cast time, and Pianissimo job-point effect.  
  https://www.bg-wiki.com/ffxi/Pianissimo
- **[S2]** Square Enix / BG Wiki, *June 9, 2008 Version Update*: introduction of Pianissimo as a single-target song modifier.  
  https://www.bg-wiki.com/ffxi/Version_Update_%2806/09/2008%29
- **[S3]** BG Wiki, *Bard*: Pianissimo and Tenuto job-point categories.  
  https://www.bg-wiki.com/ffxi/Bard
- **[S4]** FFXIclopedia, *Pianissimo*: party-member targeting, approximately 20-yalm range, and ordinary shortest-duration replacement.  
  https://ffxiclopedia.fandom.com/wiki/Pianissimo
- **[S5]** BG Wiki, *Obamiwannabuffya: A Bard Guide*: targeted recovery of a dispelled song using a multi-song instrument followed by a potency-instrument exact refresh.  
  https://www.bg-wiki.com/ffxi/Obamiwannabuffya%3A_A_Bard_Guide_by_Funkworkz
- **[S6]** FFXI community-tested recovery description: Pianissimo can rebuild dummy positions only on a member who died or lost songs.  
  https://www.reddit.com/r/ffxi/comments/yiejt9/bard_songs_vs_abilities/
- **[S7]** BG Wiki, *Tenuto*: self-copy protection, 60-second status, five-second recast, five protected songs, and incompatibility with Pianissimo.  
  https://www.bg-wiki.com/ffxi/Tenuto
- **[S8]** Square Enix / BG Wiki, *September 8, 2010 Version Update*: official Tenuto behavior.  
  https://www.bg-wiki.com/ffxi/Version_Update_%2809/08/2010%29
- **[S9]** Community testing, *Military Parade - A DD Bard Guide*: Tenuto job-point duration applies only to the Bard’s self-copy.  
  https://www.ffxiah.com/forum/topic/46553/military-parade-a-dd-bard-guide/
- **[S10]** Square Enix development response: Pianissimo and Tenuto cannot be combined without redesigning the abilities.  
  https://www.ffxiah.com/forum/topic/24473/bard-job-adjustments-answers-to-user-suggestions/1/
- **[S11]** Community testing, *You Spoony Guide*: Tenuto-protected songs can be reapplied by casting them again with Tenuto.  
  https://www.ffxiah.com/forum/topic/35597/you-spoony-guide-a-troubadours-libretto/24/
- **[S12]** Square Enix, *September 20, 2011 Version Update*: Pianissimo and Tenuto recasts reduced from 15 seconds to five seconds.  
  https://forum.square-enix.com/ffxi/threads/15044

## 15. Confidence and unresolved details

The targeting, recast, capacity neutrality, Tenuto protection, and non-stacking rules are directly documented.

Two implementation details should remain defensive:

1. the exact status-consumption result for every type of failed or interrupted Pianissimo/Tenuto song attempt;
2. the server’s behavior in a mathematically exact remaining-duration tie.

Automation should reread state after failures and should never intentionally depend on a tie.
