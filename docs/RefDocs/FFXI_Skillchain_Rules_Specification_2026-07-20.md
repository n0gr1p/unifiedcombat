**FINAL FANTASY XI**

# Skillchain Rules Specification

*Formation, timing, property resolution, chain progression, damage, magic-burst interaction, and automation logic*

**Revision 1.0  |  20 July 2026**

> **Purpose**
>
> This document is written as a standalone behavioral specification suitable for player reference and for implementing a packet-driven skillchain planner or executor. It distinguishes confirmed game rules from community-derived timing models and conservative automation recommendations.

**Scope note**  
The game does not publish a complete server-side skillchain algorithm. Where the exact boundary is not officially documented, this specification states the strongest current community evidence and labels the uncertainty instead of presenting an estimate as a fact.

## Evidence labels used in this document

| **Label** | **Meaning** | **Implementation treatment** |
| --- | --- | --- |
| **CONFIRMED** | Consistent in current community reference material and/or directly visible in action results. | May be coded as a rule. |
| **OPERATIONAL** | Derived from packet-tracking addons or repeatable community testing, but not an official server contract. | Code with instrumentation and a fallback. |
| **CONSERVATIVE** | Recommended buffer intended to avoid boundary failures caused by latency, frame timing, or packet order. | Use for scheduling, not for rule validation. |
| **UNRESOLVED** | Current public sources conflict or do not define the behavior precisely. | Do not hardcode as truth; log and verify in game. |

## Contents

- 1. Executive rules and direct timing answer
- 2. Terminology and state model
- 3. Formation prerequisites and eligible actions
- 4. Timing rules
- 5. Skillchain properties, levels, and elements
- 6. Property transition rules
- 7. Multiple-property priority
- 8. State replacement, misses, interruption, and reset
- 9. Multi-step progression and terminal chains
- 10. Chainbound, Aeonic, and special exceptions
- 11. Magic burst interaction
- 12. Skillchain damage rules
- 13. Automation implementation specification
- 14. Validation scenarios and regression tests
- 15. Known uncertainties and required telemetry
- Appendix A. Compact reference tables
- Appendix B. Sources

## 1. Executive rules and direct timing answer

> **Direct answer: how soon may the next Weapon Skill be used?**
>
> For an ordinary Weapon Skill opener, the next qualifying action must LAND on the same target approximately 3 seconds or more after the previous action completed, and before the current skillchain window expires. The first continuation window is documented broadly as 3–10 seconds. Measure from the server-observed action result, not from the instant the command was issued. For automation, a normal close should usually be targeted around 3.3–4.0 seconds after the prior landed action, rather than exactly at 3.0 or near the late cutoff. [S1][S7]

**The non-negotiable rules are:**

- Both actions must affect the same target. Skillchain state is maintained independently per target.
- The first action must successfully apply one or more skillchain properties. A missed or interrupted action does not establish a new opener.
- The closing action must successfully connect or land, have a compatible property, arrive in the valid time window, and be evaluated in a valid property order.
- Order matters. Many property pairs are directional rather than reciprocal.
- After a successful skillchain, the target resonates only with the single resulting skillchain property, not with every property of the closing action.
- A property-bearing action that lands but fails to chain normally replaces the old resonance and becomes a new opener.
- A propertyless Weapon Skill does not replace the old resonance and is explicitly documented not to interrupt an active magic-burst window.
- Level 4 chains are terminal. No further skillchain may continue from Double Light, Double Darkness, Radiance, or Umbra.
- The skillchain animation is not the scheduling anchor. Use the received action-result/conclusion event and the action’s known delay behavior. [S1][S5][S7]

> **Automation safety rule**
>
> Do not issue a closer merely because TP is available. First require: target identity match, active nonterminal resonance, compatible properties, actor able to act, and current time inside a conservative execution window. Revalidate immediately before issuing the action because another party member may have changed the target’s resonance.

## 2. Terminology and state model

| **Term** | **Definition** |
| --- | --- |
| **Action** | Any successful property-bearing Weapon Skill, Blood Pact, physical Blue Magic action under the required job ability, Immanence spell, automaton/pet move, or Chainbound opener. |
| **Opener** | The action whose properties are currently resonating on the target before a closing action is evaluated. |
| **Closer** | The new action evaluated against the target’s active resonance. |
| **Property** | A named skillchain attribute such as Liquefaction, Fragmentation, Light, or Darkness. |
| **Result** | The skillchain property produced by a valid opener-property → closer-property pair. |
| **Step / action count** | The count of property-bearing actions in the current linked sequence. Two actions create the first skillchain result. |
| **Skillchain stage** | The number of successful skillchain results in the current sequence. Stage 1 is created by action 2. |
| **Resonance** | The target-specific active ordered properties and their timing eligibility. |
| **Terminal** | A resonance that may be magic bursted but cannot be extended into another skillchain. |
| **Magic-burst window** | The separate 10-second opportunity created after each successful skillchain result. |

### 2.1 Minimum state maintained per target

```text
target_state = {
    target_id,
    active_properties_ordered,
    source_action_id,
    source_actor_id,
    action_count,
    skillchain_stage,
    result_level,
    landed_at,
    earliest_close_at,
    default_expires_at,
    actor_specific_expiry,   -- needed for Diamond Aspis
    terminal,
    magic_burst_expires_at,
    last_confirmed_skillchain_result
}
```

**Critical distinction:** resonance state and magic-burst state overlap but are not the same timer. A successful new link replaces the resonance with the new result and starts a new magic-burst window. The additional property-bearing Weapon Skill also ends the prior burst opportunity early. [S6]

## 3. Formation prerequisites and eligible actions

### 3.1 Required conditions

- Same target: opener and closer must resolve against the same target ID.
- Successful action: the action must land/connect and be recognized as property-bearing.
- Valid property level: properties only interact within their own level. Level 1 combines with Level 1; Level 2 with Level 2; Level 3 with the matching Level 3 property.
- Valid directional pair: the transition table must define opener → closer.
- Valid time: the closer must land after the minimum delay and before the relevant expiry.
- Nonterminal state: no continuation is possible after a Level 4 result. [S1]

### 3.2 Actions that can carry skillchain properties

| **Action family** | **Requirement** | **Important behavior** |
| --- | --- | --- |
| **Weapon Skills** | Property is defined by the WS and current equipment/buff state. | AoE WS applies skillchain properties only to the selected target; secondary targets do not receive opener state. |
| **Rage Blood Pacts** | The Blood Pact has one or more skillchain properties. | Pet action completion is the timing anchor. |
| **Physical Blue Magic** | Chain Affinity or Azure Lore is active. | Without the required ability, the spell does not participate as a skillchain action. |
| **Elemental magic** | Immanence is active and the spell is eligible. | Use spell-specific action delay; do not assume every spell uses the ordinary 3-second WS minimum. |
| **Automaton / other pet moves** | The move has defined properties. | Treat pet actor and master separately for readiness and actor-specific effects. |
| **Konzen-ittai / Wild Flourish / qualifying Weapon Bash** | Inflicts Chainbound. | Opener only; Chainbound has special property-priority behavior. |

[S1][S4][S5]

### 3.3 Server ordering and simultaneous actions

When multiple actions arrive close together, the server-observed action-result order controls. There is no reservation of the opener for a planned participant. The first property-bearing action processed may close, overwrite, or terminate the state before the planned closer executes. Automation must treat an intent as provisional until the closer is actually issued and then confirmed.

## 4. Timing rules

### 4.1 Timing anchor: action result, not button press

> **Correct t0**
>
> Set t0 when the incoming action packet reports the property-bearing action’s successful conclusion/result on the target. Do not start the skillchain timer when the macro is pressed, when the outgoing action packet is sent, or when the animation begins locally. [S7]

### 4.2 Ordinary Weapon Skill window

**CONFIRMED broad rule:** the valid ordinary window is approximately 3–10 seconds after the preceding action. The closer must land inside the window. The earliest boundary prevents a new action from chaining before the target is ready; the late boundary is the resonance expiry. [S1]

| **0 s** | **~3 s** | **Preferred** | **Late boundary** | **Expired** |
| --- | --- | --- | --- | --- |
| Prior action lands | Earliest ordinary close | ~3.3–4.0 s automation target | Initially near 10 s; shorter later | New property action becomes opener |

### 4.3 Window contraction during a linked chain

**CONFIRMED behavior:** the continuation window becomes shorter as the linked sequence grows. Current community guides disagree on the exact shorthand, so the late boundary must not be treated as an official fixed formula. [S8]

**OPERATIONAL packet-addon model:** Ivaar’s widely used SkillChains addon records the action conclusion, waits an action-specific delay (normally 3 seconds), and computes the display expiry as delay + 8 − step. That produces a one-second reduction in the displayed late boundary per step. The same addon marks long chains closed after a fixed step count, which is implementation behavior rather than proof of the current server maximum. [S7]

| **State after action** | **Earliest ordinary close** | **Nominal addon late cutoff** | **Usable width** | **Implementation guidance** |
| --- | --- | --- | --- | --- |
| 1 (opener) | 3.0 s | 10.0 s | 7.0 s | Target 3.3–4.0 s |
| 2 (SC stage 1) | 3.0 s | 9.0 s | 6.0 s | Target 3.3–4.0 s |
| 3 (SC stage 2) | 3.0 s | 8.0 s | 5.0 s | Target 3.3–3.8 s |
| 4 (SC stage 3) | 3.0 s | 7.0 s | 4.0 s | Target 3.2–3.7 s |
| 5 (SC stage 4) | 3.0 s | 6.0 s | 3.0 s | Target 3.2–3.6 s |
| 6 (if continuing) | 3.0 s | 5.0 s | 2.0 s | Treat as high-risk boundary |

> **Do not code “minus two seconds per step” as a server law**
>
> A current Samurai guide summarizes the window as shrinking by about two seconds until roughly three seconds remain. That is useful player advice, but it conflicts with the one-second-per-step timer used by a common packet addon. For UnifiedCombat, prefer an early conservative close and confirm success from the skillchain add-effect rather than depending on the late edge. [S7][S8]

### 4.4 Action-specific timing exceptions

| **Action type** | **Timing treatment** |
| --- | --- |
| **Normal Weapon Skills** | Default operational minimum is about 3 seconds after action conclusion. |
| **Chainbound event** | Common packet addon uses a 2-second delay before displaying the close window. The status source may also have a short lifetime; use the observed Chainbound event and source-specific duration. |
| **Immanence spells** | Some actions have longer defined delays. Helix-family actions are commonly modeled with a 5-second delay. The engine should use action metadata rather than a universal 3-second constant. |
| **Long-animation pet/monster actions** | May have per-action delays greater than 3 seconds in addon data. Use the property source’s delay record or learned telemetry. |

[S4][S7]

### 4.5 Diamond Aspis: actor-specific 10-second continuation

**CONFIRMED exception:** when the Diamond Aspis wearer closes a skillchain, the continuation window available to that wearer is held at a constant 10 seconds. Other players without the shield and pets retain the normal skillchain-window duration. [S3]

> **Data-model consequence**
>
> A single target-wide expires_at value is insufficient if Diamond Aspis is supported precisely. Maintain a default target expiry plus actor-specific expiry overrides, or calculate can_close(actor, target, now) with actor equipment context.

### 4.6 Latency, frame, and command scheduling

- Use a monotonic clock for local comparisons; never use wall-clock time for subsecond scheduling.
- Timestamp the received server result as closely as possible before downstream processing.
- Avoid scheduling at exactly 3.000 seconds. A 0.2–0.4 second buffer is normally safer.
- Avoid the final 0.5–1.0 second of the predicted late window unless no alternative exists.
- Revalidate target and resonance immediately before command dispatch.
- Do not “sleep” the entire combat engine. Create a pending intent with earliest and latest execution times so other events can cancel or replace it.

## 5. Skillchain properties, levels, and elements

| **Level** | **Property** | **Elements** | **Progression behavior** |
| --- | --- | --- | --- |
| 1 | **Compression** | Dark | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Liquefaction** | Fire | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Induration** | Ice | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Reverberation** | Water | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Transfixion** | Light | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Scission** | Earth | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Detonation** | Wind | Combines with Level 1 to produce Level 1 or 2. |
| 1 | **Impaction** | Thunder | Combines with Level 1 to produce Level 1 or 2. |
| 2 | **Gravitation** | Earth, Dark | Combines with Level 2 to produce Level 2 or Darkness. |
| 2 | **Distortion** | Ice, Water | Combines with Level 2 to produce Level 2 or Darkness. |
| 2 | **Fusion** | Fire, Light | Combines with Level 2 to produce Level 2 or Light. |
| 2 | **Fragmentation** | Wind, Thunder | Combines with Level 2 to produce Level 2 or Light. |
| 3 | **Darkness** | Dark, Earth, Water, Ice | Darkness → Darkness produces terminal Level 4 Darkness or Umbra. |
| 3 | **Light** | Light, Fire, Wind, Thunder | Light → Light produces terminal Level 4 Light or Radiance. |
| 4 | **Level 4 Darkness / Umbra** | Dark, Earth, Water, Ice | Terminal. |
| 4 | **Level 4 Light / Radiance** | Light, Fire, Wind, Thunder | Terminal. |

[S1][S7]

## 6. Property transition rules

**Table orientation:** left side is the active opener/resonance; right side is the new closing property. Only listed pairs produce a skillchain. Any unlisted same-level pair does not chain.

### 6.1 Level 1 transitions

| **Active opener** | **New closer** | **Result** |
| --- | --- | --- |
| Compression | Transfixion | **Transfixion (L1)** |
| Compression | Detonation | **Detonation (L1)** |
| Liquefaction | Impaction | **Fusion (L2)** |
| Liquefaction | Scission | **Scission (L1)** |
| Induration | Reverberation | **Fragmentation (L2)** |
| Induration | Compression | **Compression (L1)** |
| Induration | Impaction | **Impaction (L1)** |
| Reverberation | Induration | **Induration (L1)** |
| Reverberation | Impaction | **Impaction (L1)** |
| Transfixion | Scission | **Distortion (L2)** |
| Transfixion | Reverberation | **Reverberation (L1)** |
| Transfixion | Compression | **Compression (L1)** |
| Scission | Liquefaction | **Liquefaction (L1)** |
| Scission | Reverberation | **Reverberation (L1)** |
| Scission | Detonation | **Detonation (L1)** |
| Detonation | Compression | **Gravitation (L2)** |
| Detonation | Scission | **Scission (L1)** |
| Impaction | Liquefaction | **Liquefaction (L1)** |
| Impaction | Detonation | **Detonation (L1)** |

### 6.2 Level 2 transitions

| **Active opener** | **New closer** | **Result** |
| --- | --- | --- |
| Gravitation | Distortion | **Darkness (L3)** |
| Gravitation | Fragmentation | **Fragmentation (L2)** |
| Distortion | Gravitation | **Darkness (L3)** |
| Distortion | Fusion | **Fusion (L2)** |
| Fusion | Fragmentation | **Light (L3)** |
| Fusion | Gravitation | **Gravitation (L2)** |
| Fragmentation | Fusion | **Light (L3)** |
| Fragmentation | Distortion | **Distortion (L2)** |

### 6.3 Level 3 and Level 4 transitions

| **Active opener** | **New closer** | **Normal result** | **Aeonic-eligible result** |
| --- | --- | --- | --- |
| Light | Light | **Level 4 Light (“Double Light”)** | **Radiance** |
| Darkness | Darkness | **Level 4 Darkness (“Double Darkness”)** | **Umbra** |
| Light | Darkness | **No skillchain** | **No skillchain** |
| Darkness | Light | **No skillchain** | **No skillchain** |

[S1][S2][S7]

## 7. Multiple-property priority

**CONFIRMED:** Weapon Skills may have primary, secondary, and tertiary properties. Properties are tested in priority order, and the first valid pair wins. If no chain is active, all properties are installed as the new opener in their listed order. If a skillchain forms, the result becomes the only active property. [S1][S5]

### 7.1 Normal priority algorithm

```text
function resolve_normal(active_props, closing_props):
    # Operational ordering used by common packet addons:
    for opener_prop in active_props:          # opener primary -> secondary -> tertiary
        for closer_prop in closing_props:     # closer primary -> secondary -> tertiary
            result = transition[opener_prop][closer_prop]
            if result exists:
                return result                 # first valid pair wins
    return NONE

if result exists:
    active_properties = [result.property]
else:
    active_properties = closing_props         # closing action becomes a new opener
    action_count = 1
    skillchain_stage = 0
```

> **Why priority matters**
>
> A later property that could create a higher-level or strategically preferred chain is ignored if an earlier property pair is valid. A planner must simulate priority, not merely search for any compatible property combination.

### 7.2 Chainbound priority is not identical

- Level 2 and 3 Chainbound prioritizes the Chainbound opener’s properties, like a normal skillchain. Eligible Level 2 or 3 closer properties may be used even when not first in the closer’s overall property list.
- Level 1 Chainbound prioritizes the closing Weapon Skill and considers only that Weapon Skill’s first Level 1 property. Secondary or tertiary Level 1 properties cannot close Level 1 Chainbound.
- Because of property priority, Chainbound cannot produce Reverberation, Impaction, Gravitation, or Distortion as the result of the Chainbound opener. [S4]

## 8. State replacement, misses, interruption, and reset

| **Event** | **Effect on active resonance** | **Effect on magic-burst window** |
| --- | --- | --- |
| **Compatible property action lands in window** | Creates skillchain; replace active properties with the single result; increment stage. | Old burst window ends; new 10-second burst window begins. |
| **Property-bearing action lands too early, too late, or with no valid transition** | No skillchain; replace resonance with the action’s ordered properties and reset sequence count. | A property-bearing WS used during the MB window ends the current opportunity. |
| **Propertyless WS lands** | Does not replace the prior resonance. | Documented examples do not interrupt the MB window. |
| **Property-bearing action misses** | Does not establish its properties; previous resonance continues until it expires. | Current public material is less explicit on miss-based MB interruption; log actual behavior. |
| **Action is interrupted / target invalid / out of range** | No new property state. | No new burst state. |
| **Target dies, despawns, or zone changes** | Clear target state. | Clear target state. |
| **Level 4 result** | Store terminal result only for burst display/telemetry. | Start final 10-second MB window. |

[S5][S6]

### 8.1 “Too early” is an overwrite, not a queued closer

A property-bearing closer that lands before the skillchain-ready boundary should be treated as a failed chain attempt and a new opener. Do not keep the older opener alive merely because the properties would have chained later. The server evaluates actions as they arrive; it does not queue compatibility for a later time.

### 8.2 Per-target isolation

A Weapon Skill on target B does not close or overwrite target A’s resonance. Maintain state by stable target ID, not by the player’s current target selection. Retargeting in the UI must not move or duplicate resonance state.

## 9. Multi-step progression and terminal chains

- Level 1 results can continue through additional Level 1 property combinations and may promote into Level 2.
- Level 2 results may loop among Gravitation → Fragmentation → Distortion → Fusion → Gravitation, or promote into Light/Darkness through the valid reciprocal pair.
- A Level 3 result cannot cycle through other Level 3 properties. It may only be continued once by the same Level 3 property to produce a terminal Level 4 result.
- A normal Light → Light or Darkness → Darkness displays a Light/Darkness-type result but is terminal even if the chat label does not explicitly say “Double.”
- Radiance and Umbra are Aeonic versions of the terminal Level 4 result and also cannot be continued. [S1][S2]

### 9.1 Sequence-length maximum: do not assume a universal hard cap

**UNRESOLVED:** current public references do not agree on the hard maximum number of linked actions. The BG damage table defines scaling through “7+” actions, while the current Ivaar addon marks a sequence closed after its own fixed step threshold. Historical and community claims vary. Therefore, the core engine should not reject a continuation solely because a presumed action-count cap was reached. It should rely on terminal-property rules, time expiry, and the server’s actual add-effect result. The damage multiplier index may safely clamp to the published 7+ bucket. [S1][S7]

## 10. Chainbound, Aeonic, and special exceptions

### 10.1 Chainbound

| **Source** | **Level(s)** | **Lifetime / consumption** | **Rules** |
| --- | --- | --- | --- |
| **Wild Flourish** | 1 | Short Chainbound; BG notes up to ~3 seconds. | Opener only; requires a closer with at least one Level 1 property. |
| **Konzen-ittai** | 1, 2, and 3 | Listed as 60 seconds or until the next WS; Chainbound is consumed by qualifying use. | Broad ordered opener properties; some nominal results are impossible because of priority. |
| **Weapon Bash + specific Ignominy Gauntlets** | 1 | Until consumed/expired. | Uses Level 1 Chainbound rules. |

[S4][S9][S10]

### 10.2 Aeonic Aftermath and Ultimate Skillchains

While Aeonic Aftermath is active, the Aeonic Weapon Skill used to activate it gains a Level 3 property. Any Weapon Skill available to that player with the necessary Level 3 property may close the Ultimate Skillchain; it does not have to be the Aeonic Weapon Skill. [S2]

| **Aftermath** | **Trigger TP** | **SC/MB bonus** | **Minimum path** | **Outcome** |
| --- | --- | --- | --- | --- |
| **AM1** | 1000–1499 | 3% | Any SC → any SC → L3 SC + matching L3-property WS | Radiance/Umbra |
| **AM1** | 1500–1999 | 4% | Same four-action minimum | Radiance/Umbra |
| **AM2** | 2000–2199 | 5% | Any SC → L3 SC + matching L3-property WS | Radiance/Umbra |
| **AM2** | 2200–2399 | 6% | Same three-action minimum | Radiance/Umbra |
| **AM2** | 2400–2599 | 7% | Same three-action minimum | Radiance/Umbra |
| **AM2** | 2600–2799 | 8% | Same three-action minimum | Radiance/Umbra |
| **AM2** | 2800–2999 | 9% | Same three-action minimum | Radiance/Umbra |
| **AM3** | 3000 | 10% | Matching L3-property WS → matching L3-property WS | Radiance/Umbra |

- All Aeonic Aftermath levels last 180 seconds.
- The Ultimate Skillchain consumes the relevant Aeonic Aftermath.
- Any level can overwrite AM1; only AM3 overwrites AM2; nothing overwrites AM3. Maintaining AM3 may require waiting for expiration or consumption.
- Ultimate eligibility belongs to the actor under Aftermath. Do not infer party-wide eligibility from one member’s buff. [S2]

### 10.3 Inundation

Inundation modifies skillchain damage rather than formation. Its design rewards multiple players using different weapon types. Self-skillchains do not receive the bonus even if the player changes weapon types between actions. Formation, timing, and property transitions remain unchanged. [S11]

## 11. Magic burst interaction

- Each successful skillchain opens a 10-second magic-burst window beginning as the skillchain result appears.
- The spell or ability must LAND during the window; cast start time is irrelevant.
- A new property-bearing Weapon Skill on the target ends the current burst opportunity early. If it creates another skillchain, a new 10-second burst window begins for the new result.
- Propertyless Weapon Skills such as Sanguine Blade, Mystic Boon, Spirit Taker, and Spirits Within are documented exceptions and do not interrupt the burst window.
- During the burst window, resistance ranks for every element composing the skillchain are lowered by one stage. The effect resets with each successive skillchain. [S1][S6]

### 11.1 Element-to-skillchain burst alignment

| **Spell element** | **Skillchain results that permit the burst** |
| --- | --- |
| **Light** | Transfixion, Fusion, Light, Radiance |
| **Fire** | Liquefaction, Fusion, Light, Radiance |
| **Wind** | Detonation, Fragmentation, Light, Radiance |
| **Thunder** | Impaction, Fragmentation, Light, Radiance |
| **Dark** | Compression, Gravitation, Darkness, Umbra |
| **Earth** | Scission, Gravitation, Darkness, Umbra |
| **Ice** | Induration, Distortion, Darkness, Umbra |
| **Water** | Reverberation, Distortion, Darkness, Umbra |

### 11.2 Base burst scaling by chain length

A two-action skillchain grants a base +35% magic-burst damage increase. Each additional linked action adds another +10 percentage points: 45% for three actions, 55% for four, and so on, before the separate resistance-rank and Magic Burst Bonus terms. [S6]

## 12. Skillchain damage rules

Skillchain damage is based primarily on the closing action’s damage, the result level, and the number of actions in the linked sequence. It is magical elemental damage and is then modified by bonuses, affinity, weather/day, resistance rank, and target magic-damage reductions. [S1]

### 12.1 Published base multiplier table

| **Result level** | **2 actions** | **3** | **4** | **5** | **6** | **7+** |
| --- | --- | --- | --- | --- | --- | --- |
| **Level 1** | 0.50 | 0.60 | 0.70 | 0.80 | 0.90 | 1.00 |
| **Level 2** | 0.60 | 0.75 | 1.00 | 1.25 | 1.50 | 1.75 |
| **Level 3** | 1.00 | 1.50 | 1.75 | 2.00 | 2.25 | 2.50 |
| **Radiance / Umbra** | 1.50 | 1.80 | 2.10 | 2.40 | 2.70 | 3.00 |

### 12.2 Formula structure

```text
SC damage = floor(
    (
        closing_damage * base_multiplier * (1 + SkillchainBonus / 100)
        + MagicDamage
    )
    * (1 + SkillchainDamagePercent / 100)
    * day_weather_term
    * staff_affinity_term
    * elemental_affinity_term
    * resistance_rank_term
    * target_magic_damage_reduction_term
)
```

- Gear, traits, gifts, and Aeonic Aftermath contribute to Skillchain Bonus, generally capped at 50%. Certain Job Point effects are added separately and can exceed that cap.
- Level 1 results have one damage element. Multi-element results choose the element for which the target has the lowest resistance rank.
- If multiple eligible elements tie for lowest resistance, the priority is Fire → Ice → Wind → Earth → Thunder → Water → Light → Dark.
- Because the closing action’s damage is the base, maximizing the closer can be more valuable than adding weak intermediate actions solely to increase the step multiplier. [S1]

## 13. Automation implementation specification

### 13.1 Required event inputs

- Incoming action result/conclusion: actor ID, target ID, action category, action ID, success/miss/interruption, damage, add-effect skillchain result, and message ID.
- Resource metadata: ordered skillchain properties, property levels, action-specific delay, and whether Aeonic equipment/buff changes the property list.
- Actor status: TP, ability lock, animation/action lock, incapacitating status, current weapon, Diamond Aspis, Aeonic Aftermath level, and pet availability.
- Target status: alive/valid, distance, current resonance, terminal flag, and actor-specific expiry overrides.

### 13.2 Core state-transition algorithm

```text
on_property_action_result(event):
    if not event.success or event.interrupted:
        return

    state = target_states[event.target_id]
    now = monotonic_now()
    closing_props = effective_properties(event.actor_id, event.action_id)

    if closing_props is empty:
        # No resonance replacement. MB exception handled separately.
        return

    eligible = state exists
               and not state.terminal
               and now >= state.earliest_close_at
               and now <= expiry_for(event.actor_id, state)

    result = NONE
    if eligible:
        result = resolve_properties(state.active_properties_ordered,
                                    closing_props,
                                    state.chainbound_level)

    if event.server_skillchain_add_effect exists:
        # Server result is authoritative; use prediction only as diagnostics.
        result = event.server_skillchain_add_effect

    if result exists:
        next = new_state_from_skillchain_result(event, state, result)
        next.active_properties_ordered = [result.property]
        next.action_count = state.action_count + 1
        next.skillchain_stage = state.skillchain_stage + 1
        next.terminal = (result.level == 4)
        next.magic_burst_expires_at = now + 10.0
        apply_action_timing(next, event.action_id)
        apply_actor_expiry_overrides(next, event.actor_id)
        target_states[event.target_id] = next
    else:
        target_states[event.target_id] = new_opener_state(event, closing_props)
```

### 13.3 Planner / executor separation

| **Planner responsibility** | **Executor responsibility** |
| --- | --- |
| Enumerate actions whose effective ordered properties produce the desired next result. | Verify actor can act, TP/cost is available, target is valid, and time is within the execution window. |
| Score routes by desired terminal result, action damage, reliability, actor assignment, and chain length. | Create a cancellable pending intent; never block the main scheduler. |
| Account for property priority and actor-specific special effects. | Revalidate state immediately before dispatch and cancel on any intervening property-bearing action. |
| Treat predicted skillchain result as provisional. | Use the incoming server add-effect as authoritative confirmation. |

### 13.4 Recommended scheduling policy

- normal_earliest = landed_at + max(action_delay, 3.0 seconds for ordinary WS)
- preferred_execute = normal_earliest + 0.2 to 0.8 seconds
- latest_safe = predicted_expiry − 0.6 seconds
- If preferred_execute > latest_safe, mark the continuation high risk and either issue at earliest+small buffer or abandon/replan.
- For Chainbound, use the Chainbound-specific event time and source duration rather than waiting the ordinary WS minimum blindly.
- For Diamond Aspis, calculate expiry per actor. The shield wearer may still be eligible when another actor is not.

> **Never trust prediction over the server result**
>
> The transition table predicts what should happen. The incoming skillchain add-effect determines what did happen. If prediction and result differ, preserve the server result, log the full action context, and update telemetry rather than forcing local state to the prediction.

### 13.5 Cancellation conditions for a pending closer

- Target ID changes, dies, despawns, or becomes invalid.
- Another property-bearing action lands on the target.
- A successful skillchain result changes active property or terminal state.
- The actor loses TP/cost, weapon, buff, or job-ability requirement needed for the planned action.
- The actor becomes unable to act or leaves range.
- The latest safe time passes.
- The user disables the combat engine or overrides the action.

## 14. Validation scenarios and regression tests

| **Scenario** | **Input** | **Expected result** |
| --- | --- | --- |
| **Basic directional success** | Compression opener; Transfixion closer lands at t0+3.5s. | Transfixion skillchain; active property becomes only Transfixion; MB timer starts. |
| **Directional failure** | Scission opener; Transfixion closer lands in time. | No skillchain; closer properties become new opener. |
| **Too early overwrite** | Compression opener; compatible closer lands at t0+2.0s. | No skillchain; closer becomes new opener. |
| **Too late overwrite** | Compression opener; compatible closer lands after expiry. | No skillchain; closer becomes new opener. |
| **Miss preserves resonance** | Compression opener; property-bearing closer misses at t0+4.0s. | Compression resonance remains until original expiry. |
| **Propertyless WS** | Active resonance and MB window; Spirits Within lands. | Resonance remains; MB window remains. |
| **AoE selected target only** | AoE WS damages targets A/B/C with B selected. | Only B receives WS properties. |
| **Level 2 promotion** | Fusion opener; Fragmentation closer. | Light (L3). |
| **Level 2 loop** | Gravitation opener; Fragmentation closer. | Fragmentation (L2), chain can continue. |
| **Terminal normal** | Light opener; Light closer without eligible Aeonic aftermath. | Terminal Level 4 Light; no continuation. |
| **Aeonic AM3** | Eligible actor under AM3 uses matching L3-property WS twice. | Radiance or Umbra; aftermath consumed; terminal. |
| **Diamond Aspis actor split** | Shield wearer closes; wait beyond another actor’s normal expiry but within 10s. | Wearer can continue; nonwearer cannot. |
| **Chainbound L1 secondary property** | Closer’s first L1 property cannot make desired result, second L1 property could. | Second L1 property is ignored; use Chainbound L1 priority result or no desired result. |
| **Race between actors** | Planned closer queued; another actor lands a property WS first. | Queued intent cancels/replans from new server-confirmed state. |

### 14.1 Timing calibration test

1. Use two low-damage, known-compatible Weapon Skills on a durable target.
1. Record server action-result timestamps at 0.1-second resolution or better.
1. Test closer offsets around 2.7–3.4 seconds to locate the practical early threshold.
1. Test the late boundary separately for each stage; do not infer it from animation timing.
1. Repeat under low and high network latency and with different action types.
1. Store raw packet-order telemetry so a timing failure can be distinguished from property priority or target mismatch.

## 15. Known uncertainties and required telemetry

| **Uncertainty** | **Current conclusion** | **Required implementation response** |
| --- | --- | --- |
| **Exact server late-window formula** | Current sources agree the window shortens, but common public descriptions disagree on the exact decrement. | Log action-result-to-closer deltas and success for every stage. |
| **Maximum linked action count** | Public current sources do not provide one consistent server maximum. | Do not enforce a speculative cap; record whether the server returns an add-effect. |
| **Miss and current MB interruption** | Resonance preservation is documented; MB interruption on a property-bearing miss is less explicit. | Record MB success attempts after misses. |
| **Action-specific minimum delays** | Common addon data contains per-action delays, but this is not an official complete table. | Maintain configurable action delay metadata and learn from observed successes. |
| **Chainbound source duration detail** | Wild Flourish documentation contains both a displayed duration and notes describing a much shorter effective Chainbound period. | Treat Chainbound as an observed status/event and close promptly; log exact expiry behavior. |
| **New or adjusted Weapon Skills** | Version updates can add or alter properties. | Load properties from maintained resources and compare unknown action results against telemetry. |

> **Definition of “known true today”**
>
> This specification treats directly observed server add-effects and stable property tables as authoritative. Timing boundaries derived from community code are intentionally labeled operational. UnifiedCombat should make those boundaries configurable and self-auditing so future evidence can change a timing constant without rewriting property logic.

## Appendix A. Compact reference tables

### A.1 Level 2 route summary

| **Goal** | **Valid opener** | **Valid closer** | **Result** |
| --- | --- | --- | --- |
| Light | Fusion | Fragmentation | **Light** |
| Light | Fragmentation | Fusion | **Light** |
| Darkness | Gravitation | Distortion | **Darkness** |
| Darkness | Distortion | Gravitation | **Darkness** |
| Loop | Gravitation | Fragmentation | **Fragmentation** |
| Loop | Fragmentation | Distortion | **Distortion** |
| Loop | Distortion | Fusion | **Fusion** |
| Loop | Fusion | Gravitation | **Gravitation** |

### A.2 Automation decision checklist

- Is the target ID the same as the active resonance target?
- Is the target alive and valid?
- Is the resonance nonterminal and unexpired for this actor?
- Has the action-specific earliest-close time passed?
- Does the planned action’s effective ordered property list produce the desired result after priority resolution?
- Is the actor able to act and equipped/buffed as assumed?
- Has any intervening property-bearing action changed the state?
- Is current time before latest_safe?
- After execution, did the server add-effect confirm the predicted result?

### A.3 Recommended default constants

| **Constant** | **Recommended default** | **Status** |
| --- | --- | --- |
| **ordinary_ws_min_delay** | 3.0 s | OPERATIONAL / broad rule |
| **ordinary_ws_dispatch_buffer** | +0.3 s | CONSERVATIVE |
| **latest_window_guard** | 0.6 s | CONSERVATIVE |
| **magic_burst_duration** | 10.0 s | CONFIRMED |
| **chainbound_packet_delay** | 2.0 s | OPERATIONAL addon model |
| **diamond_aspis_actor_window** | 10.0 s | CONFIRMED |
| **skillchain_damage_action_bucket** | clamp at 7+ | CONFIRMED damage table |

## Appendix B. Sources

Sources were reviewed for the state of the retail game as of 20 July 2026. BG Wiki is a community-maintained reference, not an official Square Enix specification. The Ivaar addon is used as operational evidence of packet-derived community behavior, not as proof of the server implementation.

**[S1] BG Wiki — Category: Skillchain.** [https://www.bg-wiki.com/ffxi/Category:Skillchain](https://www.bg-wiki.com/ffxi/Category:Skillchain) — Core formation rules, 3–10 second broad window, property levels, transitions, damage multipliers, element selection, and terminal chains.

**[S2] BG Wiki — Aeonic Aftermath.** [https://www.bg-wiki.com/ffxi/Aeonic_Aftermath](https://www.bg-wiki.com/ffxi/Aeonic_Aftermath) — Aftermath levels, duration, Ultimate Skillchain prerequisites, bonuses, and property behavior.

**[S3] BG Wiki — Diamond Aspis.** [https://www.bg-wiki.com/ffxi/Diamond_Aspis](https://www.bg-wiki.com/ffxi/Diamond_Aspis) — Constant 10-second skillchain-duration effect for the wearer and normal timing for other actors.

**[S4] BG Wiki — Chainbound (Status).** [https://www.bg-wiki.com/ffxi/Chainbound_(Status)](https://www.bg-wiki.com/ffxi/Chainbound_(Status)) — Chainbound sources, property levels, consumption, and special priority behavior.

**[S5] FFXIclopedia — Skillchains.** [https://ffxiclopedia.fandom.com/wiki/Category:Skillchains](https://ffxiclopedia.fandom.com/wiki/Category:Skillchains) — Resonance replacement, propertyless WS and miss behavior, and multiple-property priority corroboration.

**[S6] BG Wiki — Magic Burst.** [https://www.bg-wiki.com/ffxi/Magic_Burst](https://www.bg-wiki.com/ffxi/Magic_Burst) — Ten-second burst window, interruption exceptions, elemental alignments, and base burst scaling.

**[S7] Ivaar/Skillchains — Skillchains.lua.** [https://github.com/Ivaar/Skillchains/blob/master/Skillchains.lua](https://github.com/Ivaar/Skillchains/blob/master/Skillchains.lua) — Packet-event model, transition table, property priority, per-action delay, step-based timer, Chainbound delay, and server-result parsing.

**[S8] BG Wiki — Community Samurai Guide.** [https://www.bg-wiki.com/ffxi/Community_Samurai_Guide](https://www.bg-wiki.com/ffxi/Community_Samurai_Guide) — Current player-facing description of a shrinking multi-step window; retained as a conflicting approximation rather than an exact contract.

**[S9] BG Wiki — Wild Flourish.** [https://www.bg-wiki.com/ffxi/Wild_Flourish](https://www.bg-wiki.com/ffxi/Wild_Flourish) — Level 1 Chainbound opener and short effective timing notes.

**[S10] BG Wiki — Konzen-ittai.** [https://www.bg-wiki.com/ffxi/Konzen-ittai](https://www.bg-wiki.com/ffxi/Konzen-ittai) — Chainbound duration, ordered properties, and impossible results caused by priority.

**[S11] BG Wiki — Inundation.** [https://www.bg-wiki.com/ffxi/Inundation](https://www.bg-wiki.com/ffxi/Inundation) — Skillchain damage bonus design for multiple players and different weapon types; self-skillchain exclusion.

### Revision notes

**Revision 1.0 (20 July 2026): Initial standalone rules specification.**

- Explicitly separates confirmed rules, operational addon behavior, conservative scheduling, and unresolved boundaries.
- Includes Diamond Aspis actor-specific expiry, Chainbound priority, Aeonic Ultimate paths, and automation regression scenarios.
