# RFC: UnifiedCombat Encounter Policy and Configurable Formation for Sortie A/E

**Status:** Proposed  
**Target encounters:** Sortie Area A `Ghatjot`, Sortie Area E `Dhartok`  
**Primary architectural goal:** Add encounter-aware safety and mechanics without baking a preferred party composition, job assignment, weapon-skill rotation, or scripted fight strategy into UnifiedCombat.

---

## 1. Executive decision

UnifiedCombat should treat an encounter as a source of **facts, hard action-policy constraints, and dynamic spatial constraints**.

It should **not** treat an encounter as a script for how a party should win the fight.

The governing rule for this RFC is:

> **The encounter subsystem defines observed facts, mechanic-derived safety policy, and dynamic spatial constraints. It must not encode a preferred party composition, job assignment, weapon-skill rotation, or scripted fight strategy. Durable profile configuration determines how each client operates within those constraints.**

A second rule governs formation behavior:

> **Formation configuration expresses desired geometry. Encounter state may invalidate positions because of live hazards or other encounter constraints, but it must not replace the configured formation with an encounter-authored strategy.**

This means changing from one melee setup to another, moving support closer or farther away, changing who anchors boss facing, spreading melee, stacking melee, or changing a tank position must be possible through profile configuration without changing encounter code.

---

## 2. Why this RFC exists

UnifiedCombat already has several pieces needed for encounter automation, but they currently exist as separate specialized systems:

- `uc_lilith_easy_encounter.lua` owns transient Lilith encounter state and arena-center capture.
- `uc_lilith_easy_formation_runtime.lua` adapts live Windower state into formation evaluation and dispatches movement through the existing movement dispatcher.
- `uc_combat_formation.lua` contains pure formation geometry, but is currently hardcoded around `lilith_easy` and semantic roles `tank`, `dps`, and `healer`.
- `uc_reaction_runtime.lua` implements generic ability-window and enemy-buff reactions.
- `uc_skillchain_state.lua` already owns skillchain state and property resolution.
- `uc_scheduler_ranker.lua` already has a policy-like rejection seam through reaction proposal blocking.
- `uc_scheduler_defensive_utils.lua` already resolves common removable statuses such as Poison, Silence, and Plague to the appropriate -na spell.
- Scheduler movement side effects already cross dispatcher-backed ownership boundaries.

The A/E Sortie bosses need more than a Lilith-style movement special case. They require:

1. encounter identity and transient mechanic state;
2. action-policy enforcement;
3. access to existing skillchain prediction;
4. optional mechanic-aware provider context;
5. reusable configurable formation;
6. dynamic hazard constraints for Dhartok.

Adding `ghatjot` and `dhartok` branches directly to `uc_combat_formation.lua` would solve the immediate fights but create the wrong long-term architecture. This RFC instead uses A/E as the first consumer of a small generic encounter contract and a generalized formation solver while preserving existing scheduler ownership.

---

## 3. Goals

### 3.1 Required goals

- Recognize `Ghatjot` and `Dhartok` as distinct encounter identities sharing a Plovid mechanic family.
- Observe encounter state from authoritative live evidence where possible.
- Prevent UnifiedCombat from intentionally dispatching actions that violate enabled hard encounter policies.
- Reuse the existing skillchain engine rather than creating a second skillchain predictor.
- Represent Dhartok miasma/Poison Mist locations as dynamic encounter hazards when their locations can be resolved with sufficient confidence.
- Generalize formation from Lilith-specific semantic roles into profile-configurable geometry.
- Allow every participating client to define its own desired formation geometry.
- Allow encounter hazards to invalidate candidate positions without prescribing a boss-specific movement script.
- Preserve scheduler/dispatcher ownership of movement and combat side effects.
- Preserve existing Lilith behavior and configuration through a compatibility path.
- Expose enough diagnostics to field-validate uncertain mechanics before relying on them for automation.

### 3.2 Flexibility goals

The following must be changeable without encounter code changes:

- reference/anchor party member;
- melee position and spread;
- support position and spread;
- distance from boss;
- distance from encounter origin;
- allowed angular arc;
- formation tolerances;
- hazard safety margin;
- whether a policy is enforced, warning-only, or disabled for testing;
- mechanic tuning values that are not yet field-verified.

---

## 4. Non-goals

This RFC does **not** define:

- a required party composition;
- a required tank job;
- a required healer/support job;
- a Ghatjot weapon-skill rotation;
- a Dhartok weapon-skill rotation;
- a prescribed skillchain;
- a scripted sequence such as "tank moves, then DPS moves, then support moves";
- a rule that a specific job must cast Poisona/Silena/Viruna;
- a rule that a specific job must engage or disengage during an ability;
- a hardcoded strategy for where Dhartok clouds should intentionally be dropped;
- WinForms UI implementation in the first runtime phase;
- speculative recognition of mechanics that cannot yet be reliably observed.

Encounter code may state that a condition is dangerous or mechanically restricted. It must not choose a party strategy where multiple legal responses exist.

---

## 5. Architectural model

The proposed flow is:

```text
Windower observations
        |
        v
Encounter observation/state
        |
        +---------------------> Encounter diagnostics
        |
        +---------------------> Encounter action policy
        |                             |
        |                             v
        |                       Scheduler validation
        |
        +---------------------> Encounter spatial constraints
                                      |
Profile formation geometry ----------+
                                      |
                                      v
                              Generic formation solver
                                      |
                                      v
                              Movement proposal only
                                      |
                                      v
                         Existing scheduler/dispatcher
```

The encounter does not dispatch movement, spells, weapon skills, abilities, engage/disengage, or targeting commands.

---

## 6. Ownership model

### 6.1 Durable profile-owned configuration

Examples:

- enabled encounter ID;
- policy mode overrides;
- unverified mechanic tuning values;
- formation anchor/axis selection;
- formation geometry;
- formation tolerances;
- hazard avoidance enablement and margin;
- optional range/party coverage constraints.

### 6.2 Addon-owned transient runtime state

Examples:

- current boss actor ID;
- current boss position/status;
- captured encounter origin;
- last observed boss ability;
- Dhartok Cesspool/aura sequence state;
- observed successful WS/BP timestamps against Dhartok;
- inferred/observed hazard coordinates;
- currently active encounter policy reasons;
- last policy rejection;
- formation candidate/solver state.

Runtime state must never be serialized back into the durable profile.

### 6.3 Existing domain ownership remains authoritative

- combat provider proposes combat actions;
- defensive provider proposes cures/status removal;
- maintenance providers propose maintenance actions;
- formation proposes movement only;
- scheduler validates/ranks proposals;
- dispatcher-owned paths perform side effects.

No encounter module may introduce a direct `windower.send_command`, direct movement fallback, direct WS dispatch, direct spell dispatch, or separate execution lane.

---

## 7. Encounter registry/contract

The implementation may choose exact module names after repository inspection, but the logical contract should be equivalent to:

```lua
encounter = {
    id = "sortie_dhartok",
    family = "sortie_plovid",
    actor_name = "Dhartok",

    observe = function(event_or_snapshot) ... end,
    snapshot = function() ... end,
    validate_proposal = function(ctx, proposal, snapshot) ... end,
    spatial_constraints = function(ctx, snapshot) ... end,
    reset = function(reason) ... end,
}
```

Recommended encounter IDs:

```text
sortie_ghatjot
sortie_dhartok
```

Recommended shared family:

```text
sortie_plovid
```

The shared family owns only mechanics actually shared by both bosses.

---

## 8. Encounter identity

Encounter activation should require both:

1. the configured encounter ID; and
2. the expected live actor in Sortie.

Exact actor names:

```text
Ghatjot
Dhartok
```

Do not activate solely because a same-named actor is found in an unrelated environment. Prefer resolving/validating the Sortie zone through existing resources or zone helpers rather than introducing an undocumented numeric zone constant.

If multiple matching live actors exist, enter an explicit diagnostic error state rather than guessing.

If the boss actor ID changes, transient encounter state must reset before binding to the new actor.

---

## 9. Shared Plovid mechanics: Ghatjot and Dhartok

### 9.1 Water absorption / retaliation

Both bosses absorb Water damage. Community documentation also reports dangerous retaliation or increased TP-move damage after Water absorption.

This is a **hard mechanic policy**, not a preferred strategy.

UnifiedCombat should be able to prevent its own intentional Water damage to the active encounter boss.

Policy ID:

```text
plovid_water_damage
```

Possible modes:

```text
enforce  -> reject the proposal
warn     -> allow the proposal but publish/log a policy violation
off      -> no policy effect
```

Default for A/E profiles should be `enforce` once action-element classification is verified.

The policy applies only to hostile actions targeting the active boss. It must not globally disable Water actions against unrelated targets.

### 9.2 Water-bearing skillchain results

Water absorption includes skillchain damage. A policy based only on direct spell element is therefore incomplete.

UnifiedCombat already owns skillchain transition/property state in `uc_skillchain_state.lua`. Encounter policy must consume that existing prediction/state rather than independently recreating skillchain rules.

Before dispatching a WS that is predicted to close a skillchain, the encounter policy should determine whether the predicted resulting skillchain property contains Water in its possible elemental damage set.

If it does, the proposal is unsafe under `plovid_water_skillchain`.

Policy ID:

```text
plovid_water_skillchain
```

Examples of standard skillchain properties containing Water include Reverberation, Distortion, Darkness, Level-4 Darkness, and Umbra. The implementation should prefer one authoritative skillchain-property-to-element mapping rather than scattering encounter-specific name lists through policy code.

Important: the encounter does not choose a replacement WS. It only allows or rejects the proposed WS. Existing combat logic remains responsible for selecting another legal proposal.

### 9.3 Poison/Taint as encounter facts

The presence of Ra'Kaznar Metal changes the practical status behavior: removable Poison may be observed instead of Taint. The encounter should not need a separate brittle "do we have the Metal?" strategy branch if the actual status can be observed.

Authoritative runtime fact:

```text
member has Poison
member has Taint
```

The encounter should expose mechanic metadata describing why these statuses matter:

```text
stacking poison/taint increases dangerous boss damage
Taint is not normally removable by standard -na/status-removal paths
Poison is normally removable
```

The encounter module must not directly cast Poisona or choose which party member removes it.

Existing defensive logic may consume encounter severity/context, but any provider behavior change must remain inside normal scheduler proposal ownership.

### 9.4 Ability observation

Shared Plovid ability names relevant to diagnostics include:

```text
Nullifying Rain
Noyade
Cesspool
Clobbering Wave
Fetid Eddies
```

Ability names must be resolved from Windower resources/action packets, not persisted as numeric monster-ability IDs in profiles.

Do not assume every documented secondary effect is reliable enough to drive automation. Actual observed player/boss state remains authoritative where possible.

---

## 10. Ghatjot-specific mechanics

### 10.1 Encounter identity

```text
id: sortie_ghatjot
actor: Ghatjot
family: sortie_plovid
```

### 10.2 Required hard policies

Ghatjot inherits:

```text
plovid_water_damage
plovid_water_skillchain
```

### 10.3 Poison/Taint behavior

Documentation reports stacking Poison/Taint that increases Clobbering Wave danger. With Metal A, the removable version is normal Poison.

The encounter should publish observed Poison/Taint state and related mechanic severity, but should not encode a specific removal strategy.

### 10.4 Nullifying Rain documentation conflict

Current community documentation notes that Nullifying Rain no longer dispels, while older ability-table data still describes dispel/Max-HP-down behavior.

Therefore:

- do not hardcode a mass-rebuff reaction to Nullifying Rain in this RFC;
- observe actual effect loss/gain if future automation needs it;
- telemetry may record the ability for field confirmation.

### 10.5 Room lock

Ghatjot's room is documented to close/lock on engagement.

This is an encounter fact, but "wait for all party members before engage" is a configurable strategy decision.

If a future generic pre-engage gate is added, it must be profile-configurable rather than silently hardcoded into `sortie_ghatjot`.

### 10.6 Dynamic hazards

No dynamic spatial hazard is required for initial Ghatjot support.

Formation remains fully profile-configurable.

---

## 11. Dhartok-specific mechanics

### 11.1 Encounter identity

```text
id: sortie_dhartok
actor: Dhartok
family: sortie_plovid
```

### 11.2 Inherited hard policies

Dhartok inherits:

```text
plovid_water_damage
plovid_water_skillchain
```

### 11.3 Repeated WS/BP resistance wall

Dhartok has a cumulative resistance wall against repeated Weapon Skills and, according to secondary documentation, repeated Blood Pacts.

This mechanic should be represented as a **per-action recent-success guard**, not as a hardcoded WS rotation.

The runtime should observe successful relevant actions that land on the active Dhartok actor and maintain timestamps keyed by action identity.

Conceptually:

```lua
recent_repeat_actions = {
    [action_key] = last_success_at,
}
```

A local proposed action is rejected only when:

```text
proposal targets active Dhartok
AND proposal belongs to a guarded action class
AND same action key succeeded recently enough to still be inside the configured/verified wall window
```

Different actions are not prescribed. The combat provider remains free to choose anything else permitted by the profile.

Policy ID:

```text
dhartok_repeat_action_wall
```

Suggested policy modes:

```text
enforce
warn
off
```

The exact duration is not sufficiently authoritative for a permanent hardcoded constant in this RFC. Secondary documentation reports approximately 10 seconds. Treat the first implementation value as a **live-test tuning value** until verified.

Suggested initial profile tuning field:

```lua
repeat_action_guard_s = 10.0 -- initial test value; field verification required
```

Observation scope should include all visible successful WS/BP actions against Dhartok, not only actions dispatched by the local client. The wall is a boss mechanic, not a per-client mechanic.

If action success cannot be established, do not start/reset the guard from a guessed dispatch.

### 11.4 Cesspool double-TP aura

Current community documentation reports:

- Cesspool activates an aura;
- the aura lasts about three minutes;
- while active, Dhartok can use two TP moves in succession;
- a miasma/Poison Mist is created at the position of Dhartok's target when the second TP move completes;
- up to 16 persistent clouds may exist.

The encounter should track this as transient mechanic state, but **hazard-generating behavior must remain observation/telemetry-only until the packet sequence has been field-validated**.

Candidate state shape:

```lua
cesspool = {
    active = false,
    observed_at = 0,
    expires_at = 0,
    pair_index = 0,
    last_tp_name = "",
    last_tp_target_id = 0,
}
```

Do not assume that current `boss.target_index` at completion is the ability target. Prefer the actor/target IDs carried by the authoritative action event. Resolve the recorded target's world position at the authoritative completion point.

If the target or its coordinates cannot be resolved:

```text
publish HAZARD_LOCATION_UNRESOLVED
create no guessed coordinate
```

No speculative cloud should be invented from the boss position, current target, tank name, or party formation.

### 11.5 Miasma / Poison Mist hazards

Once cloud-generation observation is field-validated, publish hazards in a generic form:

```lua
hazards = {
    {
        id = "dhartok_miasma:<sequence>",
        kind = "miasma",
        x = 0.0,
        y = 0.0,
        created_at = 0.0,
        expires_at = nil,
        avoid_radius = 0.0,
        source = "second_tp_target_position",
    },
}
```

The exact avoidance radius is not sufficiently documented for a hardcoded factual value. It must be configurable/tunable until live testing establishes a reliable default.

Suggested tuning field:

```lua
hazard_avoid_radius = <live-test value>
```

A profile may additionally configure a safety margin:

```lua
hazard_margin = 0.5
```

Effective exclusion radius:

```text
hazard.avoid_radius + profile.hazard_margin
```

Clouds should remain in transient state until encounter reset unless field evidence proves a finite lifetime.

### 11.6 Hazard effects

Miasma clouds are documented to apply Drown and Magic Defense Down. Secondary community evidence also reports substantial Dhartok regeneration while Dhartok remains inside a cloud.

These should be exposed as encounter facts/diagnostics.

The encounter must **not** convert "boss is inside hazard" into a hardcoded scripted tank movement sequence.

Formation/configuration may react to the hazard because a player's allowed position is invalidated. The user remains responsible for configuring geometry that produces the desired boss positioning behavior.

### 11.7 Conflicting cloud descriptions

Secondary documentation contains a Noyade-specific description of Poison Mist spawning that conflicts with the more detailed Cesspool/double-TP description.

Initial implementation should therefore trust field-validated packet behavior, not encode the Noyade-specific claim as fact.

---

## 12. Policy classes

Not every mechanic should be treated the same way.

### 12.1 Hard veto

Used when UnifiedCombat can prove that its proposed action violates a mechanic policy.

Examples:

```text
Water offensive action -> Ghatjot/Dhartok
Water-bearing predicted skillchain -> Ghatjot/Dhartok
Repeated guarded WS/BP inside verified Dhartok wall window
```

Result:

```text
proposal rejected before dispatch
```

### 12.2 Context/severity fact

Used when the encounter knows a condition matters but multiple valid responses exist.

Examples:

```text
Poison present
Taint present
Dhartok inside known miasma
Cesspool aura active
hazard count increasing
```

Result:

```text
published in encounter snapshot/diagnostics
optionally consumed by existing providers
no direct side effect
```

### 12.3 Spatial constraint

Used when a world position is known to be unsafe.

Example:

```text
Dhartok miasma exclusion circle
```

Result:

```text
formation candidate invalid when hazard avoidance is enabled
```

The encounter does not author the replacement position.

---

## 13. Policy override model

For testing and field validation, a profile should be able to change policy mode without code edits.

Recommended shape:

```lua
encounter = {
    enabled = true,
    id = "sortie_dhartok",

    policy = {
        water_damage = "enforce",       -- enforce | warn | off
        water_skillchain = "enforce",   -- enforce | warn | off
        repeat_action_wall = "enforce", -- Dhartok only
    },

    tuning = {
        repeat_action_guard_s = 10.0,
        hazard_avoid_radius = 0.0,
    },
}
```

`warn` is important. It allows live testing to compare what policy would have blocked without changing actual combat execution.

An encounter may define sensible defaults, but profile override must remain available for unverified mechanics and intentional testing.

---

## 14. Generic formation v2

### 14.1 Architectural decision

Do not add Ghatjot- and Dhartok-specific branches to the current Lilith role evaluator.

Instead, extract/generalize the useful Lilith formation concepts into a pure configurable solver.

The solver should understand geometry and constraints, not jobs or encounter strategies.

### 14.2 No semantic combat roles in the generic solver

Generic formation must not require:

```text
tank
dps
healer
```

Those are useful human concepts but unnecessarily couple geometry to strategy.

A profile should describe where that client wants to stand.

### 14.3 Required formation inputs

A generic formation evaluation needs:

```lua
ctx = {
    me = { id, name, x, y },
    boss = { id, name, x, y },
    encounter_origin = { x, y } or nil,
    party_members = { ... },
    encounter_hazards = { ... },
    config = { ... },
    was_moving = true_or_false,
}
```

### 14.4 Anchor sources

Initial supported anchor sources should be intentionally small:

```text
boss
encounter_origin
member
```

`encounter_origin` means a transient captured reference point, not necessarily the geometric center of the room.

Do not call it `arena_center` for Sortie unless the code has proof it is actually the room center.

### 14.5 Axis sources

A polar formation may need a directional axis.

Initial supported axis source:

```text
boss_to_member
```

This covers the important "relative to the boss/reference-member line" geometry without the encounter declaring that the member is a tank.

The profile chooses the reference member.

Additional axes should be added only when a real encounter requires them.

### 14.6 Placement modes

Two generic modes cover the current Lilith use cases and the proposed Sortie use cases.

#### `radial_band`

Choose a valid point within a radius band around the anchor.

Useful for:

- holding near an encounter origin;
- selecting the nearest safe point after a hazard invalidates the current position;
- Lilith healer-style nearest-valid ring behavior.

Example:

```lua
placement = {
    mode = "radial_band",
    anchor = "encounter_origin",
    preferred_radius = 0.0,
    minimum_radius = 0.0,
    maximum_radius = 8.0,
    radius_step = 0.5,
    angle_step_deg = 10.0,
}
```

#### `polar_band`

Choose a valid point within a radius/angle band relative to a configured axis.

Useful for:

- front/rear/flank positions;
- melee spread;
- support arcs;
- Lilith DPS-style boss/reference axis positioning.

Example:

```lua
placement = {
    mode = "polar_band",
    anchor = "boss",
    axis = {
        type = "boss_to_member",
        member = "Terrasjr",
    },
    preferred_radius = 3.0,
    minimum_radius = 2.0,
    maximum_radius = 4.5,
    preferred_angle_deg = 180.0,
    allowed_angle_half_width_deg = 60.0,
    radius_step = 0.5,
    angle_step_deg = 10.0,
}
```

This example is illustrative configuration, not an endorsed Sortie strategy.

### 14.7 Candidate constraints

The generic solver should support profile constraints such as:

```text
stay inside configurable encounter-origin safe radius
minimum boss distance
maximum boss distance
maximum distance from required party members
avoid encounter hazards
optional hazard margin
```

Existing Lilith-specific cone constraints should either be represented generically or kept behind a Lilith compatibility adapter until a clean generic constraint is justified.

Do not force every encounter to carry Lilith's cone model.

### 14.8 Candidate selection

The solver should:

1. evaluate the current player position;
2. hold if the current position satisfies the configured allowed geometry and active hard constraints;
3. if invalid, enumerate configured candidate geometry;
4. reject candidates violating profile constraints;
5. reject candidates violating enabled encounter spatial constraints;
6. choose the nearest/best valid candidate using deterministic scoring;
7. emit a movement proposal only;
8. if no valid candidate exists, publish an explicit unsatisfied state and do not guess a position.

### 14.9 Hysteresis

The generic solver must preserve the anti-oscillation behavior already proven useful in Lilith.

Configuration should distinguish "start correcting" from "close enough to stop" where necessary.

Do not continuously issue movement because a client is a few tenths of a yalm away from an ideal point.

### 14.10 Dynamic hazard interaction

When `avoid_encounter_hazards = true`, a candidate is invalid when:

```text
distance(candidate, hazard.center) < hazard.avoid_radius + hazard_margin
```

The solver only answers:

```text
Is this player position valid?
If not, what valid point best satisfies this profile's geometry?
```

It does **not** answer:

```text
Where should the tank drag Dhartok?
Where should the party intentionally drop the next cloud?
Should the group rotate clockwise?
```

Those are strategy decisions.

---

## 15. Example per-client formation configurations

These examples demonstrate configurability only.

### 15.1 Boss-relative polar position

```lua
formation = {
    enabled = true,
    placement = {
        mode = "polar_band",
        anchor = "boss",
        axis = {
            type = "boss_to_member",
            member = "ReferenceName",
        },
        preferred_radius = 3.0,
        minimum_radius = 2.0,
        maximum_radius = 4.0,
        preferred_angle_deg = 180.0,
        allowed_angle_half_width_deg = 45.0,
        radius_step = 0.5,
        angle_step_deg = 10.0,
    },
    constraints = {
        avoid_encounter_hazards = true,
        hazard_margin = 0.5,
    },
}
```

### 15.2 Encounter-origin position with hazard fallback

```lua
formation = {
    enabled = true,
    placement = {
        mode = "radial_band",
        anchor = "encounter_origin",
        preferred_radius = 0.0,
        minimum_radius = 0.0,
        maximum_radius = 10.0,
        radius_step = 0.5,
        angle_step_deg = 10.0,
    },
    constraints = {
        avoid_encounter_hazards = true,
        safe_origin_radius = 16.0,
        hazard_margin = 0.5,
    },
}
```

Changing either configuration changes party geometry without changing encounter implementation.

---

## 16. Encounter origin capture

Lilith already demonstrates stable pre-engagement actor-position capture.

Generalize that concept as `encounter_origin` only when a formation configuration needs it.

Capture requirements should remain conservative:

- expected encounter actor exists;
- actor is alive;
- valid world coordinates exist;
- actor is idle/not yet engaged;
- coordinates remain within configured tolerance for configured stable duration.

After capture, origin is immutable for the current attempt.

If a configured formation requires `encounter_origin` and engagement occurs before capture succeeds, publish an explicit capture error. Do not capture the boss's later combat position and pretend it is the origin.

Runtime origin coordinates are never persisted to the profile.

---

## 17. Lilith compatibility and migration

Existing `lilith_easy` profiles and behavior must not break as a side effect of this RFC.

The current Lilith profile contains semantic fields such as:

```text
formation_role
formation_tank_name
formation_tank_accept_radius
formation_tank_return_radius
formation_dps_flank_angle_deg
formation_dps_melee_radius
formation_healer_*
```

Recommended migration approach:

1. implement/test the generic solver independently;
2. add a compatibility adapter that translates existing Lilith configuration into generic solver input;
3. run existing Lilith replay/self-tests unchanged where possible;
4. prove behavior parity before deleting or rewriting existing Lilith-specific wrappers;
5. retain old profile keys until an explicit profile migration is approved.

Do not combine this RFC with an unrelated broad profile cleanup.

---

## 18. Scheduler action-policy integration

### 18.1 Validation seam

Encounter hard-policy validation should occur before dispatch and before a proposal can win execution.

Conceptually:

```lua
local ok, reason = encounter_policy.validate_proposal(ctx, proposal)
if not ok then
    reject(proposal, reason)
end
```

Do not implement encounter policy by lowering scores and hoping another action wins. A proven hard violation is invalid, not merely low priority.

### 18.2 Suggested rejection reasons

```text
encounter_water_damage
encounter_water_skillchain
encounter_repeat_action_wall
encounter_state_unresolved
```

Keep reasons stable enough for replay tests and diagnostics.

### 18.3 Policy only blocks local dispatch

UnifiedCombat cannot prevent another player or non-UC client from using an unsafe action.

However, observed external actions should still update encounter state when relevant, such as Dhartok repeat-action timestamps.

### 18.4 Skillchain integration

Do not reconstruct skillchain state in the encounter module.

Use the current `uc_skillchain_state.lua` state/prediction path and add only the minimum interface needed for encounter validation if the current API is insufficient.

---

## 19. Defensive-provider integration

Initial encounter support does not require a second defensive subsystem.

The encounter snapshot may expose status severity/context, for example:

```lua
status_context = {
    poison = {
        present = true,
        mechanic = "stacking_damage_multiplier",
        severity = "high",
    },
    taint = {
        present = true,
        mechanic = "stacking_damage_multiplier",
        standard_removal = false,
    },
}
```

Any decision to prioritize a removal action must remain in the defensive provider/ranking path.

Do not place spell names or job-specific cure logic in `uc_sortie_plovid_*` encounter state.

---

## 20. Reaction runtime relationship

The existing reaction runtime remains useful for generic responses such as turn-away or stop-attacking rules.

Do not force every observed boss ability into `config.reactions` simply because an action packet is involved.

Rule of thumb:

- generic user-configurable response to an ability window -> reaction system;
- encounter-specific state needed to understand a mechanic -> encounter system;
- formation safety from a world-space hazard -> formation constraint;
- invalid offensive proposal -> encounter policy validation.

Avoid duplicate ownership of the same side effect.

---

## 21. Diagnostics

Add a generic command/snapshot equivalent to:

```text
//uc encounter status
```

Recommended output fields:

```text
enabled
configured encounter id
resolved encounter id
family
boss name/id/hpp/status
encounter origin / origin capture phase
last observed boss ability
active policy modes
last policy rejection
Poison/Taint observations available to this client
Dhartok Cesspool state
Dhartok repeat-action timestamps/remaining guard
hazard count
hazard coordinates/radii/source
unresolved hazard observations
last reset reason
```

Formation diagnostics should continue to expose:

```text
configured placement
resolved anchor
resolved axis
current-position validity
failed constraint
selected candidate
movement/hold/error reason
```

Diagnostics are required for field validation, not optional polish.

---

## 22. Lifecycle/reset requirements

Encounter transient state must reset on at least:

```text
zone change
job change where current UC lifecycle already resets encounter-sensitive state
addon unload
logout
configured encounter disabled/changed
boss actor replacement
boss defeated / encounter completed
manual profile switch where active encounter configuration changes
```

Reset must clear:

```text
boss actor binding
encounter origin
Cesspool sequence state
repeat-action timestamp map
hazards
policy transient diagnostics
formation runtime movement state where appropriate
```

---

## 23. Evidence and uncertainty register

The RFC intentionally distinguishes documented mechanics from implementation assumptions.

| Mechanic | Current confidence | Implementation rule |
| --- | --- | --- |
| Ghatjot absorbs Water | high | may enforce after action-element classification tests |
| Dhartok absorbs Water / dangerous retaliation | high | may enforce after action-element classification tests |
| Water skillchain damage is dangerous | high | use existing SC prediction + Water-element membership |
| Poison/Taint increases dangerous move damage | high | expose as mechanic context; do not hardcode job response |
| Metal changes practical removable status to Poison | high | observe actual status instead of branching on assumed KI |
| Dhartok repeat-action wall exists | high | observe successful repeated actions |
| Exact repeat-action window ~= 10s | medium | tuning value; field verify before treating as permanent fact |
| Cesspool enables double TP for ~3 min | high/medium | observe and telemetry first |
| Cloud appears at second TP target position | high/medium | field-validate action/target packet sequence before movement use |
| Maximum 16 clouds | high/medium | diagnostic limit; do not rely on it for core safety initially |
| Exact cloud radius | unknown | never invent; profile tuning until measured |
| Cloud persists for fight | medium | retain until reset initially; field verify |
| Dhartok regens inside cloud | medium | expose fact/diagnostic; no scripted movement |
| Noyade specifically spawns clouds | conflicting secondary source | do not encode until field evidence supports it |
| Ghatjot Nullifying Rain dispels | conflicting/stale documentation | do not encode automated rebuff behavior |

Primary community references reviewed for this RFC:

- BG-Wiki: Ghatjot
- BG-Wiki: Dhartok
- BG-Wiki: Taint
- BG-Wiki: Skillchain and Umbra/Level-4 Darkness elemental properties
- FFXIclopedia: Dhartok, used only as secondary evidence for the approximate repeat-action window and cloud behavior
- FFXIAH low-man Dhartok discussion, used only as operational corroboration and not as authoritative packet behavior

Repository references reviewed:

- `AGENTS.md`
- `docs/lilith_easy_formation_design.md`
- `docs/reaction_runtime_design.md`
- `docs/scheduler_responsibility_map.md`
- `uc_lilith_easy_encounter.lua`
- `uc_lilith_easy_formation_runtime.lua`
- `uc_combat_formation.lua`
- `uc_reaction_runtime.lua`
- `uc_skillchain_state.lua`
- `uc_scheduler_ranker.lua`
- `uc_scheduler_defensive_utils.lua`
- `uc_profile_contract.lua`

---

## 24. Implementation phases

### Phase 0 - Repository audit and contract freeze

No runtime behavior change.

- inspect current action packet entrypoints;
- inspect current skillchain prediction API;
- inspect profile-v2/config-normalizer formation paths;
- inspect movement coordinator ordering;
- identify exact reusable seams;
- write a short implementation plan tied to actual current functions/files;
- confirm pre-existing dirty files before edits.

Exit criteria:

- exact integration points documented;
- no speculative new execution path;
- compatibility plan for Lilith documented.

### Phase 1 - Encounter observation and diagnostics only

No combat or movement behavior change.

Implement:

- encounter identity;
- boss actor binding/lifecycle;
- encounter origin capture primitive;
- Ghatjot/Dhartok ability telemetry;
- Poison/Taint observation exposure where existing state permits;
- Dhartok successful WS/BP timestamp observation;
- Dhartok Cesspool/double-TP telemetry;
- candidate hazard-location telemetry without using it for movement;
- `//uc encounter status`.

Exit criteria:

- replay tests for state transitions;
- live logs sufficient to validate Cesspool pair/target behavior;
- no proposal is rejected and no movement changes yet.

### Phase 2 - Hard encounter policy

Implement:

- policy mode `enforce|warn|off`;
- direct Water proposal classification;
- skillchain Water-property veto using existing skillchain state;
- Dhartok repeat-action wall using observed success timestamps and tunable guard;
- stable reject diagnostics.

Exit criteria:

- non-encounter targets unaffected;
- safe actions unaffected;
- warning mode produces no behavior change;
- enforcement mode reliably prevents only proven policy violations;
- replay tests cover all policy cases.

### Phase 3 - Generic formation solver

Implement the pure generic formation model without Dhartok hazards first.

- anchor resolution;
- axis resolution;
- radial-band placement;
- polar-band placement;
- profile constraints;
- deterministic candidate selection;
- movement hysteresis;
- no-side-effect pure tests;
- dispatcher-backed runtime adapter.

Then add Lilith compatibility translation and prove replay parity.

Exit criteria:

- existing Lilith behavior remains accepted;
- Sortie can use generic profile geometry without boss-specific strategy code;
- disabling generic formation preserves existing movement behavior.

### Phase 4 - Dhartok dynamic spatial constraints

Only after Phase 1 field evidence validates cloud creation timing/location.

Implement:

- hazard creation from authoritative second-TP target position;
- transient persistent hazard list;
- configurable/tunable avoidance radius;
- formation candidate hazard rejection;
- unresolved-hazard diagnostics;
- optional distance telemetry to help tune radius.

Exit criteria:

- no guessed hazard coordinates;
- known hazards consistently invalidate candidate positions;
- unsatisfiable geometry reports an error rather than inventing a move;
- encounter still does not prescribe a tank/DPS/support movement sequence.

### Phase 5 - Profile/UI integration

Only after runtime contracts are field-accepted.

- add structured Profile V2 representation;
- add normalization/validation;
- add WinForms fields for encounter ID, policy modes/tuning, and generic formation geometry;
- preserve legacy Lilith keys and migration behavior;
- UI must block structurally invalid geometry but must not decide strategy.

---

## 25. Required tests

### 25.1 Encounter identity

- Ghatjot binds only to configured Ghatjot encounter.
- Dhartok binds only to configured Dhartok encounter.
- wrong actor -> explicit unresolved/error state.
- multiple matching actors -> explicit error.
- actor replacement resets transient state.

### 25.2 Water policy

- Water offensive proposal to active boss -> reject in enforce mode.
- same proposal -> allow + diagnostic in warn mode.
- same proposal -> unaffected in off mode.
- Water proposal to unrelated target -> unaffected.
- non-Water proposal -> unaffected.

### 25.3 Skillchain policy

- predicted skillchain whose elemental set contains Water -> reject in enforce mode.
- safe predicted skillchain -> unaffected.
- no active SC state -> ordinary WS remains eligible.
- encounter policy uses existing skillchain state, not duplicate transitions.

### 25.4 Dhartok repeat-action wall

- successful WS records timestamp by action key.
- dispatch attempt of same action inside guard -> rejected.
- different action -> not rejected merely because another action is guarded.
- same action after guard -> allowed.
- failed/interrupted action does not create success timestamp.
- externally observed successful WS updates the boss-wide guard.
- Ghatjot does not receive Dhartok wall behavior.

### 25.5 Hazard observation

- validated second-TP completion + resolvable target coordinates -> hazard candidate.
- unresolved target -> no guessed hazard; diagnostic emitted.
- boss death/reset clears hazards.
- new boss actor clears old hazards.

### 25.6 Generic formation

- valid current position -> hold.
- invalid current position -> deterministic nearest/best valid candidate.
- hazard-intersecting candidate -> rejected when avoidance enabled.
- same candidate allowed when hazard avoidance explicitly disabled.
- profile angular/radius bands are respected.
- missing required anchor/member -> explicit error.
- no valid candidate -> unsatisfied state, no guessed movement.
- movement dispatch uses existing dispatcher ownership only.

### 25.7 Lilith regression

- current Lilith encounter-center capture tests pass.
- current Lilith formation behavior remains equivalent through compatibility adapter.
- Fatal Allure/Dread Spikes reaction precedence remains unchanged.
- cast movement locks remain above formation correction.

---

## 26. Acceptance criteria

The RFC is successfully implemented when all of the following are true:

- [ ] Ghatjot and Dhartok can be enabled through durable encounter configuration.
- [ ] Encounter code contains no required party composition.
- [ ] Encounter code contains no hardcoded WS rotation.
- [ ] Encounter code contains no job-specific fight script.
- [ ] Water policy can prevent UC-generated unsafe Water actions.
- [ ] Water-bearing predicted skillchains can be prevented using the existing SC engine.
- [ ] Dhartok repeated-action protection is based on observed success and configurable/verified timing, not a prescribed rotation.
- [ ] Poison/Taint are exposed as encounter facts without bypassing the defensive provider.
- [ ] Dhartok hazard state can be observed and diagnosed before it is trusted for movement.
- [ ] Once validated, hazards become generic spatial constraints rather than scripted relocation instructions.
- [ ] Every client can configure its own formation geometry.
- [ ] Changing formation does not require encounter code changes.
- [ ] Formation solver is pure and side-effect free.
- [ ] Movement crosses the existing scheduler/dispatcher ownership path.
- [ ] Unsatisfied geometry never produces a guessed movement target.
- [ ] Existing Lilith configuration remains supported.
- [ ] Existing reaction precedence remains supported.
- [ ] Runtime encounter state is never persisted into profiles.
- [ ] Diagnostics expose enough state to field-debug policy and geometry failures.

---

## 27. Explicit anti-patterns for Codex

Do **not** implement any of the following:

```text
if encounter == "sortie_dhartok" then
    tank_move_to(...)
    dps_move_behind(...)
    healer_move_to(...)
end
```

```text
if last_ws == "Tachi: Fudo" then
    next_ws = "Tachi: Kasha"
end
```

```text
if poison then
    windower.send_command('input /ma "Poisona" ...')
end
```

```text
if cloud_spawned then
    move_party_clockwise()
end
```

```text
if boss_in_cloud then
    force_reference_member_to_fixed_boss_specific_coordinate()
end
```

Also do not add direct side effects from encounter observation code.

The correct pattern is:

```text
observe fact
    -> publish state/constraint/policy
    -> existing provider or configurable formation proposes behavior
    -> scheduler validates/ranks
    -> dispatcher executes
```

---

## 28. Codex task guidance

This is architecture-impacting and runtime-sensitive work. Follow `AGENTS.md`.

Before implementation:

1. inspect current git status;
2. identify pre-existing dirty files;
3. inspect the exact current scheduler/action/skillchain/formation entrypoints;
4. produce a brief Phase 0 implementation map tied to current symbols;
5. do not begin later phases until the prior phase has targeted replay verification.

Prefer separate commits/PR-sized changes by phase if commits are requested. Do not combine the encounter subsystem with unrelated scheduler refactors.

The first implementation task should be **Phase 0 + Phase 1 only**. Do not jump directly to policy enforcement and movement before the live-observation contract is proven.
