# RFC: UnifiedCombat Summoner Automation v1 and Reusable Pet-Combat Architecture

**Status:** Draft
**Supersedes:** Earlier Summoner automation RFC drafts
**Target:** UnifiedCombat addon, scheduler, profile-v2 contract, and WinForms UI
**Initial job:** Summoner
**Future consumers:** Beastmaster and Puppetmaster

---

## 1. Summary

UnifiedCombat should add Summoner automation through two separate provider responsibilities:

### Summoner maintenance

A job-specific `SummonerMaintenanceProvider` in the existing maintenance domain should drive persistent Summoner state toward the durable profile configuration:

* Maintain one configured avatar.
* Maintain Avatar’s Favor when enabled.
* Maintain one configured Blood Pact: Ward effect.

### Pet combat

A reusable `PetCombatProvider` should manage target-relative pet behavior:

* Send the job-specific pet engagement command when required.
* Use one configured offensive pet action when available.

For Summoner v1:

* Engagement command: `Assault`
* Offensive action: one configured Blood Pact: Rage

The common pet-combat provider should delegate job-specific mechanics to an adapter or strategy so that Beastmaster and Puppetmaster can reuse the same combat lifecycle later.

Both providers submit candidates to the existing scheduler. Neither provider directly executes commands or owns an independent action loop.

---

# Part I: Governing Automation Principles

## 2. Durable configuration is authoritative

The profile defines the desired Summoner state.

The addon observes live state and continuously attempts to make it match the profile.

```text
Durable desired configuration
        ↓
Addon observes runtime state
        ↓
Provider identifies configuration drift
        ↓
Provider proposes corrective action
        ↓
Scheduler authorizes execution
        ↓
Runtime state is observed again
```

Example:

```text
Desired avatar: Ifrit
Observed avatar: Garuda
Result: runtime is misaligned and must be corrected
```

Combat, manual intervention, or the presence of a usable but incorrect avatar does not change the configured goal.

---

## 3. Runtime convergence invariant

When Summoner automation is enabled and its configuration is valid:

> UnifiedCombat must always work toward aligning runtime state with the durable Summoner configuration.

A mismatch may remain temporarily only because a required corrective action is not currently legal or has been delayed by a higher-priority scheduler action.

Valid temporary blockers include:

* A pet command is already pending.
* The pet is executing an action that cannot be interrupted safely.
* The player is casting.
* The player is stunned, asleep, silenced, or otherwise unable to perform the required action.
* The summon spell is unavailable.
* Required MP is unavailable.
* The action is in retry backoff.
* A higher-priority recovery or emergency action is selected.

The following are not valid reasons to preserve a mismatch:

* The character is currently in combat.
* The incorrect avatar is already attacking.
* The incorrect avatar is still usable.
* The user manually summoned the incorrect avatar.
* The incorrect avatar supports a different useful pact.
* Replacing the avatar would temporarily reduce damage.

---

## 4. No implicit manual override

Summoner automation v1 does not infer user intent from manual runtime actions.

If the profile says:

```text
Desired avatar: Ifrit
```

and the user manually summons Garuda, UnifiedCombat observes configuration drift.

It does not interpret the manual summon as:

* A temporary override.
* A profile update.
* Permission to use Garuda indefinitely.
* Permission to substitute Garuda-compatible actions.

UnifiedCombat should restore Ifrit as soon as scheduler and action legality allow.

A future explicit manual-override feature may be designed separately. No implicit override exists in v1.

---

## 5. Configured avatar is foundational

A valid desired avatar is required for Summoner automation v1.

The configured avatar is not an optional convenience added alongside Ward and Rage behavior. It is the foundation that makes all other Summoner configuration deterministic.

The desired avatar determines:

* Which avatar should exist.
* Which Ward actions are compatible.
* Which Rage actions are compatible.
* Which pet must receive Assault.
* Which avatar should carry Avatar’s Favor.

No Summoner maintenance or pet-combat action should use an unintended avatar.

---

## 6. Domain describes why; action kind describes how

An action’s scheduler domain should be determined by why the action is needed, not by the command syntax used to execute it.

| Action                  | Domain            | Execution kind     |
| ----------------------- | ----------------- | ------------------ |
| Summon Ifrit            | Maintenance       | Player spell       |
| Release Garuda          | Maintenance       | Pet command        |
| Activate Avatar’s Favor | Maintenance       | Player job ability |
| Use Hastega II          | Maintenance       | Blood Pact: Ward   |
| Assault target          | Combat engagement | Pet command        |
| Use Flaming Crush       | Combat offense    | Blood Pact: Rage   |

This prevents all `/pet` actions from being incorrectly grouped into a single pet domain.

---

## 7. Providers decide; shared executors perform

Providers determine:

* Whether an action is required.
* Why it is required.
* Which pet and target identities it applies to.
* Which domain and priority it should receive.

Shared execution infrastructure determines:

* Whether the action can be dispatched now.
* How the command is sent.
* How pending state is represented.
* How completion is detected.
* How interruption, failure, and timeout are handled.
* When retry is permitted.

---

# Part II: Goals and Scope

## 8. Functional goals

Summoner automation v1 must allow a profile to configure:

* Whether Summoner automation is enabled.
* One required desired avatar.
* Whether Avatar’s Favor should be maintained.
* Zero or one Blood Pact: Ward effect to maintain.
* Whether the configured avatar should engage each combat target.
* Zero or one Blood Pact: Rage to use when available.

---

## 9. Architectural goals

The implementation must:

* Keep durable configuration owned by the UI and profile.
* Keep live state owned by the addon.
* Continuously drive runtime toward durable configuration.
* Use the existing scheduler and candidate model.
* Place Summoner buffing beside Bard and Corsair maintenance providers.
* Introduce reusable pet-combat behavior for future BST and PUP support.
* Reuse existing spell, job-ability, and action lifecycle infrastructure.
* Avoid fixed waits.
* Avoid independent provider action loops.
* Serialize conflicting pet commands.
* Preserve existing behavior for profiles without Summoner automation.

---

## 10. Safety goals

The implementation must not:

* Use a different avatar than the configured avatar.
* Preserve an avatar mismatch merely because combat is active.
* Maintain Avatar’s Favor on an unintended avatar.
* Use a configured Ward through an unintended avatar.
* Use a configured Rage through an unintended avatar.
* Send Assault with an unintended avatar.
* Dynamically substitute an avatar or pact.
* Depend on live avatar state to author the profile.
* Mutate durable configuration in response to runtime state.
* Send duplicate commands while an action is pending.
* Redirect a queued pet action to a newly selected target.
* Introduce pet-specific fixed sleeps.
* Introduce unnecessary player movement locks for pet commands.

---

# Part III: Proposed Architecture

## 11. Provider and execution structure

```text
Maintenance domain
└── SummonerMaintenanceProvider
    ├── Configured avatar convergence
    ├── Avatar’s Favor maintenance
    └── Blood Pact: Ward maintenance

Combat/offense domain
└── PetCombatProvider
    ├── Common combat-target lifecycle
    ├── Common pet-target validation
    ├── Common engagement behavior
    ├── Common offensive-action scheduling
    └── Job-specific adapter
        ├── SummonerPetCombatAdapter
        ├── BeastmasterPetCombatAdapter       [future]
        └── PuppetmasterPetCombatAdapter      [future]

Shared execution infrastructure
├── Existing spell executor
│   └── Avatar summon spells
├── Existing job-ability executor
│   └── Avatar’s Favor
└── PetCommandCoordinator or equivalent scheduler channel
    ├── Release
    ├── Assault
    ├── Blood Pact: Ward
    ├── Blood Pact: Rage
    ├── Fight / Ready / Sic                  [future]
    └── Deploy / Retrieve                    [future]
```

The exact class and module names may follow repository conventions, but the responsibility boundaries should remain.

---

## 12. Summoner configuration shape

A conceptual profile-v2 shape is:

```lua
summoner = {
    enabled = true,

    avatar = "Ifrit",

    maintenance = {
        avatar_favor = true,

        ward = {
            enabled = true,
            action = "Crimson Howl",
        },
    },

    pet_combat = {
        engage_on_combat_start = true,

        offensive_action = {
            enabled = true,
            action = "Flaming Crush",
            usage = "on_cooldown",
        },
    },
}
```

A disabled configuration is:

```lua
summoner = {
    enabled = false,

    avatar = nil,

    maintenance = {
        avatar_favor = false,

        ward = {
            enabled = false,
            action = nil,
        },
    },

    pet_combat = {
        engage_on_combat_start = false,

        offensive_action = {
            enabled = false,
            action = nil,
            usage = "on_cooldown",
        },
    },
}
```

The exact field names should follow existing profile-v2 conventions.

---

## 13. Avatar configuration requirement

When `summoner.enabled` is true, `summoner.avatar` must identify a valid supported avatar.

If the desired avatar is missing or invalid:

* Summoner automation is configuration-invalid.
* No Summoner actions are executed.
* Existing pets are not destructively released.
* A clear diagnostic is emitted.
* Unrelated profile sections remain active.

This is a configuration failure, not normal runtime drift.

---

## 14. Configuration ownership

### 14.1 Profile-owned state

The profile owns:

* Summoner automation enabled state.
* Desired avatar.
* Avatar’s Favor maintenance setting.
* Ward maintenance enabled state.
* Selected Ward.
* Pet engagement enabled state.
* Offensive pet-action enabled state.
* Selected Rage.
* Offensive usage policy.

### 14.2 Addon-owned runtime state

The addon owns:

* Observed pet presence.
* Pet server ID.
* Observed avatar identity.
* Pet alive/dead state.
* Pet busy state.
* Pet combat target.
* Player combat target.
* Combat-generation identity.
* Pet-instance identity.
* Buff state.
* Recast state.
* Pending actions.
* Retry backoff.
* Action completion and failure state.
* Engagement satisfaction.

No live runtime state should be persisted as profile configuration.

---

# Part IV: Static Capability Data and UI Ownership

## 15. Summoner capability catalog

The UI and addon need authoritative static or generated knowledge describing:

* Supported avatars.
* Avatar summon spell identities.
* Ward actions per avatar.
* Rage actions per avatar.
* Ward resulting effects.
* Action categories.
* Resource IDs and display names.

Conceptually:

```lua
summoner_capabilities = {
    Ifrit = {
        summon_spell = "Ifrit",

        wards = {
            "Crimson Howl",
            "Inferno Howl",
        },

        rages = {
            "Punch",
            "Burning Strike",
            "Double Punch",
            "Flaming Crush",
            "Meteor Strike",
            "Conflag Strike",
        },
    },

    Garuda = {
        summon_spell = "Garuda",

        wards = {
            "Aerial Armor",
            "Hastega II",
        },

        rages = {
            -- Garuda-compatible Rage actions
        },
    },
}
```

Stable game-resource IDs should be preferred internally where practical.

---

## 16. UI behavior

The UI must support profile authoring when:

* No avatar is summoned.
* The character is not on Summoner.
* UnifiedCombat is disabled.
* The addon is not currently connected.
* The character is not in combat.
* Runtime recast and buff state are unavailable.

The UI may filter Ward and Rage selections based on:

* The profile’s desired avatar.
* The static Summoner capability catalog.

The UI must not filter based on:

* The currently observed avatar.
* Current pet presence.
* Current runtime state.

---

## 17. Invalidated action configuration

If the desired avatar changes and a configured Ward or Rage is no longer compatible:

* The incompatible value should not be silently deleted.
* The UI should mark it invalid.
* Runtime should suppress the invalid behavior.
* Diagnostics should explain the incompatibility.
* The avatar itself should still be maintained correctly.
* Other valid Summoner behavior may continue.

Example:

```text
Desired avatar changed:
Ifrit → Garuda

Configured Rage:
Flaming Crush

Result:
- Garuda is maintained.
- Flaming Crush is configuration-invalid.
- Rage automation is suppressed.
- No replacement Rage is chosen automatically.
```

---

# Part V: Summoner Maintenance Provider

## 18. Provider responsibility

`SummonerMaintenanceProvider` answers:

```text
Which configured persistent Summoner states are currently unsatisfied?
```

Its initial responsibilities are:

1. Desired avatar convergence.
2. Avatar’s Favor maintenance.
3. One Blood Pact: Ward effect.

It does not own:

* Enemy target selection.
* Assault.
* Rage.
* Offensive rotations.
* Dynamic avatar selection.
* Pet positioning.

---

## 19. Desired avatar convergence

### 19.1 No pet active

When no pet is active, the provider should propose the desired avatar’s summon spell when:

* Summoner automation is enabled.
* The main job is Summoner.
* The desired avatar is valid.
* The summon spell is known.
* Normal spell requirements permit an attempt.
* No conflicting action is pending.
* Retry backoff has expired.

Conceptual candidate:

```lua
{
    domain = "maintenance",
    provider = "summoner",
    action_kind = "spell",
    action_name = "Ifrit",
    target = "self",
    reason = "configured avatar missing",
}
```

Summoning must use existing spell execution and completion handling.

---

### 19.2 Correct avatar active

When the observed avatar matches the desired avatar:

* Avatar convergence is satisfied.
* No summon or Release candidate is generated.
* Dependent Summoner behaviors may be evaluated.

---

### 19.3 Wrong avatar active

When the observed avatar does not match the desired avatar, runtime is misaligned.

This is true regardless of combat state.

The provider should work toward:

```text
Wrong avatar observed
    ↓
Release wrong avatar
    ↓
Observe pet disappearance
    ↓
Summon desired avatar
    ↓
Observe desired avatar
```

Combat does not suspend this goal.

---

### 19.4 Correction during combat

When the wrong avatar is active during combat:

* The mismatch remains an active maintenance requirement.
* The provider proposes Release as soon as the pet-action channel and scheduler permit it.
* After pet disappearance is observed, the provider proposes the desired summon spell.
* Existing target and combat state remain runtime inputs.
* Once the desired avatar appears, pet-combat behavior reevaluates against the current target.

There is no special “defer until combat ends” rule.

---

### 19.5 Correction blockers

Avatar correction may wait only for explicit action legality or scheduler constraints.

Examples:

* A pet action is currently pending.
* The pet is executing a command that has not completed.
* Release is temporarily unavailable.
* A higher-priority action is selected.
* Release is in retry backoff.
* After Release, summoning is blocked by silence, stun, sleep, MP, recast, movement, or an existing cast.

These states should be observable and diagnostically distinguishable.

---

### 19.6 No use of the wrong avatar

While the wrong avatar remains active:

* Avatar’s Favor is not maintained.
* Ward is not used.
* Assault is not sent.
* Rage is not used.
* No compatible substitute pact is selected.
* The wrong avatar is not treated as a temporary valid automation state.

The only normal Summoner candidate associated with the wrong avatar is the action required to remove it.

Higher-priority global emergency or recovery actions may still occur.

---

### 19.7 Manual avatar changes

A manual summon of an unintended avatar creates runtime drift.

UnifiedCombat should:

1. Detect the mismatch.
2. Wait for any currently pending action to resolve.
3. Release the unintended avatar.
4. Summon the configured avatar.
5. Resume configured Summoner behavior.

The durable profile is not changed.

---

### 19.8 Desired avatar lost

If the desired avatar dies, is manually released, or disappears:

* Avatar convergence becomes unsatisfied immediately.
* Pet-bound queued candidates become stale.
* Pending pet actions resolve or cancel through the central action lifecycle.
* The provider proposes resummoning the desired avatar when legal.
* Other Summoner providers remain blocked until the desired avatar is observed.

---

### 19.9 Release and summon are state-driven

The transition must not be implemented with a fixed wait.

Prohibited:

```lua
send_command('/pet "Release" <me>')
wait(1)
send_command('/ma "Ifrit" <me>')
```

Required:

```text
Release dispatch
    ↓
Pet disappearance event or authoritative observation
    ↓
Provider reevaluation
    ↓
Summon candidate
```

---

## 20. Avatar’s Favor maintenance

### 20.1 Dependency

Avatar’s Favor may be maintained only when the observed avatar matches the configured desired avatar.

```text
Desired avatar active + Favor missing
    → Favor candidate may be generated

Wrong avatar active
    → Favor blocked by avatar mismatch
```

UnifiedCombat must not maintain Favor on an unintended avatar.

---

### 20.2 Eligibility

Avatar’s Favor is eligible when:

* Summoner automation is enabled.
* Favor maintenance is enabled.
* The desired avatar is currently active.
* Favor is not active.
* The job ability is available.
* No conflicting action is pending.
* Retry backoff has expired.
* Scheduler rules permit a maintenance action.

---

### 20.3 Completion and failure

Avatar’s Favor should reuse existing job-ability lifecycle handling.

It must not be marked complete solely because the command was sent.

A failed Favor attempt:

* Clears pending state through central handling.
* Leaves the Favor goal unsatisfied.
* Retries through standard backoff.

---

## 21. Blood Pact: Ward maintenance

### 21.1 Dependency

Ward maintenance requires the desired avatar to be currently active.

The provider must not use:

* The wrong active avatar.
* A substitute Ward.
* A Ward compatible with runtime but incompatible with configuration.

---

### 21.2 Desired-state contract

For v1:

```text
Configured Ward effect present on Summoner
    → Ward satisfied

Configured Ward effect absent
    → Ward unsatisfied
```

---

### 21.3 Ward metadata

Supported Wards require metadata describing their maintained effects.

Conceptually:

```lua
ward_metadata = {
    ["Hastega II"] = {
        avatar = "Garuda",
        resulting_buffs = { "Haste" },
        satisfaction = "all",
        target_policy = "self",
    },

    ["Crimson Howl"] = {
        avatar = "Ifrit",
        resulting_buffs = { "Warcry" },
        satisfaction = "all",
        target_policy = "self",
    },
}
```

Stable buff and action IDs should be used internally where available.

---

### 21.4 Buff-observation scope

V1 evaluates the Summoner’s own buff state.

* If the Summoner has the expected effect, Ward is satisfied.
* If another party member loses the effect but the Summoner retains it, no recast occurs solely for that member.
* If the Summoner loses the effect, Ward becomes eligible again.

Per-party-member maintenance remains outside v1.

---

### 21.5 No pre-refresh

V1 does not pre-refresh a Ward.

The provider waits until the maintained condition is unsatisfied.

---

### 21.6 Ward eligibility

A Ward candidate is eligible when:

* Summoner automation is enabled.
* Ward maintenance is enabled.
* The configured Ward is valid for the desired avatar.
* The desired avatar is currently active.
* The maintained effect is absent.
* Blood Pact: Ward recast permits execution.
* The pet can legally act.
* No conflicting pet action is pending.
* Retry backoff has expired.

---

### 21.7 Targeting

V1 supports self-targeted Ward invocation only.

```text
Blood Pact: Ward target = Summoner
```

Arbitrary party-member targeting is outside v1.

---

### 21.8 Completion and failure

Ward completion must use authoritative runtime evidence such as:

* Pet-action completion.
* Result event.
* Recast consumption.
* Expected effect appearing.
* Existing scheduler completion rules.

If Ward fails:

* Pending state clears centrally.
* The maintained state remains unsatisfied.
* Retry uses standard backoff.
* Other valid actions may proceed while Ward is in backoff.

---

## 22. Summoner maintenance dependency order

Within Summoner maintenance:

```text
1. Desired avatar convergence
2. Avatar’s Favor
3. Ward maintenance
```

The desired avatar is a hard prerequisite.

If the desired avatar is absent or mismatched:

* Favor is not eligible.
* Ward is not eligible.
* Pet-combat actions are not eligible.

The scheduler may still select unrelated higher-priority global actions.

---

# Part VI: Reusable Pet Combat Provider

## 23. Provider responsibility

`PetCombatProvider` answers:

```text
What should the correctly configured active pet do against the current combat target?
```

It owns:

* Per-target engagement.
* Pet and target identity validation.
* One configured offensive pet action.
* Offensive readiness.
* Job-specific pet mechanics through an adapter.

It does not own:

* Summoning.
* Releasing mismatched pets as configuration maintenance.
* Avatar selection.
* Avatar’s Favor.
* Blood Pact: Ward.
* Persistent buff maintenance.

---

## 24. Correct pet prerequisite

For Summoner, the pet-combat provider is eligible only when:

```text
Observed avatar == configured desired avatar
```

If the avatar is:

* Missing.
* Incorrect.
* Dying.
* Being released.
* Being summoned.
* Not yet authoritatively observed.

Then all Summoner pet-combat candidates are suppressed.

The maintenance provider owns convergence.

---

## 25. Reusable adapter model

Avoid a provider implemented as one large job conditional.

Prefer:

```text
PetCombatProvider
    └── IPetCombatAdapter
        ├── SummonerPetCombatAdapter
        ├── BeastmasterPetCombatAdapter
        └── PuppetmasterPetCombatAdapter
```

Conceptual adapter responsibilities:

```lua
PetCombatAdapter = {
    supports_current_job = function(context) end,

    get_required_pet_identity = function(profile) end,

    get_active_pet = function(context) end,

    get_pet_target_id = function(context) end,

    build_engage_candidate = function(context, target) end,

    get_configured_offensive_action = function(profile) end,

    validate_offensive_action = function(context, action) end,

    evaluate_offensive_readiness = function(context, action) end,

    build_offensive_candidate = function(context, target, action) end,
}
```

The exact interface should follow repository conventions.

---

## 26. Future job mapping

| Job | Engagement command | Offensive behavior         |
| --- | ------------------ | -------------------------- |
| SMN | Assault            | Blood Pact: Rage           |
| BST | Fight              | Ready or Sic               |
| PUP | Deploy             | Primarily automaton-driven |
| DRG | Mostly automatic   | Limited applicability      |

Common lifecycle responsibilities include:

* Combat-target identity.
* Pet identity.
* Engagement satisfaction.
* Pending-action suppression.
* Stale-target rejection.
* Pet-action serialization.
* Failure backoff.
* Diagnostics.

Job adapters own:

* Command names.
* Recast or charge interpretation.
* Action compatibility.
* Resource checks.
* Job-specific target rules.

---

# Part VII: Combat and Pet-Engagement Identity

## 27. Combat generation

A new combat generation begins when UnifiedCombat establishes a valid hostile target and:

* No previous combat target existed.
* The target’s unique server ID changes.
* A previous engagement ended and combat begins again.

Example:

```text
No target
    → Goblin A
    → Combat generation 41

Remain on Goblin A
    → Generation 41

Switch to Goblin B
    → Generation 42

Disengage
    → Generation 42 ends

Re-engage Goblin B
    → Generation 43
```

Target names are insufficient. Unique runtime/server identity is required.

---

## 28. Pet engagement key

Engagement satisfaction must be associated with both:

* Combat-generation identity.
* Pet-instance identity.

Conceptually:

```text
engagement_key = combat_generation_id + pet_server_id
```

This is required because a new avatar may appear during the same combat generation.

Example:

```text
Combat generation 41
Pet instance A assaults target
Pet instance A dies
Pet instance B is summoned
```

Pet instance B must receive Assault even though the combat target and combat generation did not change.

---

## 29. Summoner Assault behavior

### 29.1 Profile meaning

```lua
engage_on_combat_start = true
```

means:

```text
Ensure each correctly configured pet instance receives Assault
for the current combat target when needed.
```

The UI may display:

> Send Assault when engaging an enemy

---

### 29.2 Eligibility

An Assault candidate is eligible when:

* Summoner automation is enabled.
* Pet engagement is enabled.
* The desired avatar is currently active.
* A valid hostile combat target exists.
* The engagement key is not satisfied.
* The pet is not already attacking the correct target.
* No Assault is pending.
* No conflicting pet command is pending.
* Retry backoff has expired.
* Pet, target, and combat identities remain valid.

---

### 29.3 Already attacking correct target

If the configured avatar is already attacking the correct target:

* Engagement is considered satisfied for the current engagement key.
* No redundant Assault is sent.

This accommodates manual Assault without treating manual avatar selection as an override.

---

### 29.4 New avatar during the same fight

When the configured avatar disappears and a new instance is summoned:

* The pet server ID changes.
* The engagement key changes.
* Assault becomes eligible again for the current combat target.

---

### 29.5 Pet attacking another target

If the configured avatar is attacking a different enemy:

* The current engagement key is unsatisfied.
* Assault may be proposed against the configured combat target.
* Target identity must be revalidated before dispatch.

---

### 29.6 No continuous engagement maintenance

V1 does not continuously resend Assault after engagement was satisfied for the same pet instance and combat generation.

If the same pet instance later disengages unexpectedly during the same combat generation, v1 does not automatically resend Assault.

A future `maintain_engagement` policy may extend this behavior.

---

### 29.7 Disabled engagement

When engagement automation is disabled:

* No Assault is generated.
* Rage does not implicitly enable Assault.
* The configured avatar is still maintained.
* Other enabled Summoner behavior remains independently evaluated.

---

# Part VIII: Offensive Pet Action

## 30. Configured Rage behavior

When enabled, the configured Blood Pact: Rage should be used against the active combat target whenever legally executable.

```text
Use configured Rage when:
- desired avatar is active,
- target is valid,
- Rage recast is ready,
- pet can act,
- scheduler permits it.
```

“On cooldown” does not mean repeatedly sending the command while unavailable.

---

## 31. Rage eligibility

A Rage candidate is eligible when:

* Summoner automation is enabled.
* Offensive pet-action automation is enabled.
* The configured Rage is valid for the desired avatar.
* The desired avatar is currently active.
* A valid hostile combat target exists.
* The target is alive.
* The target belongs to the captured combat generation.
* Blood Pact: Rage recast permits execution.
* The pet can legally act.
* No Rage is pending.
* No conflicting pet action is pending.
* Retry backoff has expired.
* Existing scheduler rules permit an offensive action.

---

## 32. Target and pet capture

The candidate must capture:

* Target server ID.
* Combat-generation ID.
* Pet server ID.
* Desired avatar identity.
* Configured action identity.

Immediately before dispatch, the system must revalidate:

* The target still exists.
* The target is alive.
* The target remains hostile.
* The combat generation is unchanged.
* The same configured pet instance remains active.
* The action remains valid and available.

Stale candidates must be discarded or regenerated.

The executor must not depend exclusively on mutable `<t>` resolution.

---

## 33. Avatar mismatch during queued Rage

If the pet changes after a Rage candidate is created:

* The queued candidate becomes stale.
* It must not execute through the new pet.
* It must not be redirected.
* Maintenance resolves the avatar state.
* Pet combat later generates a new candidate if appropriate.

---

## 34. Range and positioning

When the runtime can authoritatively determine that the pet or target is out of range:

* Rage should not be proposed or dispatched.

When exact range cannot be known before execution:

* The command may be attempted.
* Explicit range failure clears pending state.
* Retry uses centralized backoff.
* Commands must not be sent every frame.
* V1 does not move the player or pet automatically.

---

## 35. Target death during execution

If the target dies after Rage is accepted:

* Central lifecycle handling resolves the pending action.
* The action does not redirect.
* A new target requires a newly generated candidate.

---

## 36. Rage completion

Successful Rage execution should naturally update recast state and suppress further candidates until available.

No separate hard-coded Rage delay should be added.

---

# Part IX: Shared Pet-Action Infrastructure

## 37. Shared pet-command coordination

Maintenance and combat providers may propose commands involving the same pet.

A shared coordinator or scheduler channel must serialize them.

Conceptually:

```text
PetCommandCoordinator
- Current pet identity
- Current pet busy state
- Pending pet command
- Captured target identity
- Command dispatch
- Completion recognition
- Failure recognition
- Timeout/watchdog
- Retry backoff
```

This may be implemented as an extension of existing scheduler infrastructure.

---

## 38. Commands requiring serialization

Initial commands:

* Release.
* Assault.
* Blood Pact: Ward.
* Blood Pact: Rage.

Future commands:

* Fight.
* Ready.
* Sic.
* Deploy.
* Retrieve.
* Other pet-specific actions.

---

## 39. Shared channel does not imply shared priority

Pet actions retain their original scheduler reason and domain.

Examples:

* Release wrong avatar: configuration convergence maintenance.
* Restore Ward: buff maintenance.
* Assault: combat engagement.
* Rage: offense.

The shared channel prevents simultaneous pet commands. It does not flatten domain priority.

---

## 40. Wrong-avatar correction priority

Within Summoner automation, avatar convergence is a hard prerequisite.

When the wrong avatar is active:

```text
Release wrong avatar
    takes precedence over
Favor, Ward, Assault, and Rage
```

Those dependent actions should not be generated.

This is stronger than merely giving Release a higher numeric priority. The other actions are ineligible until the desired avatar is observed.

---

# Part X: Action Lifecycle

## 41. Required repository audit

Implementation must identify existing authoritative handling for:

* Pet command acceptance.
* Pet action start.
* Pet action completion.
* Pet action failure.
* Pet action interruption.
* Summon spell completion.
* Avatar appearance.
* Avatar disappearance.
* Blood Pact recast consumption.
* Target death during pending actions.
* Pet disappearance during pending actions.
* Pending-action timeout.

Existing lifecycle paths should be extended rather than duplicated.

---

## 42. No fixed waits

Prohibited:

```lua
send_command('/pet "Release" <me>')
wait(1)
send_command('/ma "Ifrit" <me>')
```

Prohibited:

```lua
send_command('/pet "Assault" <t>')
wait(1)
send_command('/pet "Crimson Howl" <me>')
wait(2)
send_command('/pet "Flaming Crush" <t>')
```

Required:

```text
Dispatch
    ↓
Authoritative completion, failure, or timeout
    ↓
Observe runtime state again
    ↓
Generate newly valid candidates
```

---

## 43. Pending-action watchdog

Pet actions should use the existing centralized action watchdog if one exists.

If no suitable watchdog exists, timeout behavior should be added centrally rather than as separate constants for:

* Release.
* Assault.
* Ward.
* Rage.

---

# Part XI: Movement

## 44. Summoning

Summon spells follow normal spell movement and interruption rules.

The Summoner provider must not create a separate movement system.

---

## 45. Pet commands

Pet commands should not independently lock player movement:

* Release.
* Assault.
* Ward.
* Rage.

If the current scheduler applies movement locks to every action type, implementation must explicitly audit and correct pet-command behavior where appropriate.

Neither provider independently stops or restores player movement.

---

# Part XII: Priority and Starvation

## 46. Summoner dependency ordering

```text
1. Valid desired avatar configuration
2. Desired avatar present
3. Avatar’s Favor
4. Ward
5. Pet engagement
6. Rage
```

This list combines hard dependencies and typical functional progression. It is not intended to override higher-priority global recovery or emergency actions.

Hard requirements:

* Favor requires the desired avatar.
* Ward requires the desired avatar.
* Assault requires the desired avatar.
* Rage requires the desired avatar.
* Summoning requires no active pet.
* Summoning after Release requires observed pet disappearance.

---

## 47. Cross-domain scheduling

After the desired avatar is present, the scheduler may choose among:

* Avatar’s Favor.
* Ward.
* Assault.
* Rage.
* Recovery.
* Emergency actions.
* Other job actions.

Provider registration order must not implicitly define priority.

---

## 48. Failure must not cause starvation

Examples:

* Ward in backoff does not permanently block Rage.
* Assault in backoff does not permanently block Ward.
* Favor in backoff does not block valid pet combat.
* Summoning blocked by MP does not create per-frame command spam.
* Release failure does not permit automation to start using the wrong avatar.

The avatar mismatch remains unsatisfied and continues retrying through normal policy.

---

# Part XIII: Failure Handling

## 49. Summon interrupted

When summoning is interrupted:

* Resolve pending state through normal spell handling.
* Desired-avatar state remains unsatisfied.
* Retry uses standard backoff.
* MP, recast, status, and casting legality are revalidated.

---

## 50. Summon blocked

When summoning is blocked by:

* MP.
* Silence.
* Stun.
* Sleep.
* Movement.
* Recast.
* Another cast.

The provider reports the explicit blocker and reevaluates when state changes.

It must not send impossible summon commands repeatedly.

---

## 51. Release failure

When Release fails:

* Pending state clears centrally.
* The avatar mismatch remains active.
* Retry uses standard backoff.
* Dependent Summoner actions remain ineligible.
* The wrong avatar is not adopted as a fallback.

---

## 52. Avatar disappears during an action

When the pet disappears or its server identity changes:

* Pet-bound queued candidates become stale.
* Pending actions resolve or cancel centrally.
* Engagement satisfaction tied to the old pet becomes invalid.
* Desired-avatar maintenance reevaluates.
* Dependent providers remain blocked until the desired avatar is observed.

---

## 53. Assault failure

When Assault fails:

* The engagement key remains unsatisfied.
* Retry uses standard backoff.
* Pet and target identities are revalidated.
* No per-frame retry loop is allowed.

---

## 54. Ward failure

When Ward fails:

* The maintained effect remains unsatisfied.
* Retry uses normal backoff.
* Ward does not permanently starve other eligible actions.

---

## 55. Rage failure

When Rage fails:

* Pending state clears centrally.
* Target, pet, recast, and legality are revalidated.
* Retry uses standard backoff.
* The action does not redirect.

---

# Part XIV: Observability

## 56. Avatar convergence states

Recommended diagnostic reasons:

```text
Summoner automation disabled
no desired avatar configured
invalid desired avatar
no pet active
desired avatar active
wrong avatar active
Release pending
Release blocked
Release retry backoff
summon pending
summon recast unavailable
insufficient MP
summon blocked by status
summon retry backoff
ready to Release
ready to summon
```

There should be no:

```text
correction deferred during combat
```

state.

---

## 57. Avatar’s Favor states

```text
disabled
desired avatar missing
avatar mismatch
already active
job ability unavailable
action pending
retry backoff
ready
```

---

## 58. Ward states

```text
disabled
no Ward configured
invalid Ward
Ward incompatible with desired avatar
desired avatar missing
avatar mismatch
maintained effect present
maintained effect absent
Ward recast unavailable
pet busy
action pending
retry backoff
ready
```

---

## 59. Pet engagement states

```text
disabled
desired avatar missing
avatar mismatch
no combat target
engagement already satisfied
pet already attacking correct target
pet attacking another target
action pending
retry backoff
ready
```

---

## 60. Rage states

```text
disabled
no action configured
invalid action
action incompatible with desired avatar
desired avatar missing
avatar mismatch
no combat target
target dead
stale target
recast unavailable
resource unavailable
pet busy
action pending
retry backoff
ready
```

---

## 61. Dispatch logging

Debug logs should include where applicable:

* Domain.
* Provider.
* Adapter.
* Action kind.
* Action resource ID.
* Desired avatar.
* Observed avatar.
* Pet server ID.
* Target server ID.
* Combat-generation ID.
* Engagement key.
* Candidate reason.
* Scheduler decision.

Normal recast waiting should not generate warning-level noise.

---

# Part XV: Explicit V1 Decisions

## 62. Decision table

| Question                                               | V1 decision                |
| ------------------------------------------------------ | -------------------------- |
| Is Summoner automation optional?                       | Yes                        |
| Is a desired avatar required when enabled?             | Yes                        |
| How many desired avatars?                              | One                        |
| Can the addon summon it?                               | Yes                        |
| Can the addon replace the wrong avatar outside combat? | Yes                        |
| Can the addon replace the wrong avatar during combat?  | Yes                        |
| Does combat suspend avatar convergence?                | No                         |
| Does manual summoning override the profile?            | No                         |
| Can the wrong avatar be used temporarily?              | No                         |
| Is Favor maintained on the wrong avatar?               | No                         |
| Can Ward use the wrong avatar?                         | No                         |
| Can Rage use the wrong avatar?                         | No                         |
| Can Assault use the wrong avatar?                      | No                         |
| Is UI configuration based on live avatar state?        | No                         |
| Is Avatar’s Favor maintained?                          | Optionally                 |
| How many maintained Wards?                             | One                        |
| Is Ward checked per party member?                      | No                         |
| Does Ward pre-refresh?                                 | No                         |
| Can Ward target arbitrary party members?               | No                         |
| How many recurring Rage actions?                       | One                        |
| Is Rage target-aware?                                  | Current combat target only |
| Is Assault configurable?                               | Yes                        |
| Is Assault engagement keyed to pet instance?           | Yes                        |
| Does Rage implicitly enable Assault?                   | No                         |
| Does pet combat summon or replace avatars?             | No                         |
| Are pet commands serialized?                           | Yes                        |
| Are fixed waits used?                                  | No                         |
| Do pet commands lock movement?                         | No by default              |

---

# Part XVI: Non-goals

## 63. Outside v1

* Dynamic avatar selection.
* Enemy-element avatar selection.
* Day or weather avatar selection.
* Temporary avatar switching for individual pacts.
* Manual override inference.
* Timed manual override.
* Multiple maintained Wards.
* Per-party-member Ward tracking.
* Arbitrary party-member Ward targeting.
* Ward duration prediction.
* Ward pre-refresh.
* Multiple Rage priorities.
* Rage rotations.
* Skillchain-aware Rage selection.
* Magic-burst-aware Rage selection.
* Astral Conduit automation.
* Apogee automation.
* Astral Flow automation.
* Mana strategy beyond action legality.
* Elemental spirit automation.
* Pet positioning.
* Player repositioning for pet actions.
* Continuous Assault maintenance.
* Automatic Retreat tactics.
* Substitute pacts for avatar mismatch.
* BST implementation.
* PUP implementation.

---

# Part XVII: Acceptance Criteria

## 64. Configuration ownership

1. The profile can configure a desired avatar while no avatar is present.
2. The UI can configure Summoner behavior without live addon state.
3. The UI uses static capability data and the desired-avatar field.
4. The UI does not use the observed avatar to control authoring.
5. Runtime avatar changes do not mutate the profile.
6. Existing profiles default Summoner automation to disabled.
7. Enabling Summoner automation without a valid avatar produces a configuration error.

---

## 65. Avatar convergence

1. No active pet causes the desired avatar to be summoned when legal.
2. The desired avatar satisfies convergence.
3. A wrong avatar is released outside combat.
4. A wrong avatar is released during combat.
5. Combat alone never suppresses correction.
6. Manual summoning of the wrong avatar triggers correction.
7. Release and summon are separated by observed pet disappearance.
8. An interrupted summon retries through normal backoff.
9. Insufficient MP does not create command spam.
10. A wrong avatar never becomes a fallback automation state.
11. Dependent SMN actions remain blocked during mismatch.
12. Disabling Summoner automation stops new convergence actions.

---

## 66. Avatar’s Favor

1. Favor is proposed only when the desired avatar is active.
2. Favor is not proposed on the wrong avatar.
3. Favor is not proposed when already active.
4. Favor is not proposed with no avatar.
5. Favor uses existing job-ability lifecycle handling.

---

## 67. Ward maintenance

1. Ward is validated against the desired avatar.
2. Ward executes only through the desired avatar.
3. Ward is blocked during avatar mismatch.
4. Ward is not proposed while its maintained effect is present.
5. Ward becomes eligible after effect removal.
6. Ward checks the Summoner’s effect state.
7. Ward is not pre-refreshed.
8. Duplicate Ward commands are suppressed.
9. Ward failure uses normal backoff.
10. Ward failure does not permanently starve Rage.

---

## 68. Pet engagement

1. Assault requires the desired avatar.
2. The wrong avatar never receives automatic Assault.
3. Engagement is keyed by combat generation and pet instance.
4. A newly summoned avatar can receive Assault during an existing fight.
5. Repeated scheduler ticks do not duplicate Assault.
6. A pet already attacking the correct target satisfies engagement.
7. Disabling engagement prevents automatic Assault.
8. Rage does not implicitly enable Assault.
9. Assault never executes against a stale target.
10. Assault failure retries only through normal backoff.

---

## 69. Offensive pet action

1. Rage requires the desired avatar.
2. The wrong avatar never executes automatic Rage.
3. A valid Rage is proposed when recast and target conditions permit.
4. Recast suppresses duplicate use after success.
5. Pending Rage suppresses duplicate commands.
6. Target death invalidates the candidate.
7. Target changes invalidate stale candidates.
8. Pet identity changes invalidate stale candidates.
9. Rage never redirects.
10. Recoverable failure retries through normal backoff.

---

## 70. Scheduler behavior

1. Maintenance and combat providers can both propose pet actions.
2. Shared serialization prevents conflicting pet commands.
3. Candidates retain their original domains.
4. Provider registration order does not define priority.
5. Avatar mismatch makes dependent SMN candidates ineligible.
6. Retry backoff does not starve unrelated valid actions.
7. No pet action sequence uses fixed sleeps.
8. Pet disappearance invalidates pet-bound candidates.
9. Existing non-Summoner behavior remains unchanged.

---

## 71. Movement

1. Summon spells use normal spell movement rules.
2. Release does not independently lock player movement.
3. Assault does not independently lock player movement.
4. Ward does not independently lock player movement.
5. Rage does not independently lock player movement.
6. Neither provider independently restores movement.

---

# Part XVIII: Required Tests

## 72. Profile and UI tests

* Missing Summoner section.
* Disabled Summoner automation.
* Enabled with no desired avatar.
* Invalid desired avatar.
* Valid desired avatar.
* Valid Ward for desired avatar.
* Ward incompatible with desired avatar.
* Valid Rage for desired avatar.
* Rage incompatible with desired avatar.
* Desired-avatar change invalidating Ward.
* Desired-avatar change invalidating Rage.
* Profile round trip.
* Existing profile compatibility.
* UI operation without live avatar.
* UI operation without addon runtime connection.

---

## 73. Avatar convergence tests

* No pet and summon legal.
* No pet and insufficient MP.
* No pet and summon recast unavailable.
* No pet and blocked by status.
* Desired avatar active.
* Wrong avatar outside combat.
* Wrong avatar during combat.
* Wrong avatar currently attacking.
* Wrong avatar manually summoned.
* Release pending.
* Release failure.
* Pet disappearance after Release.
* Summon only after observed disappearance.
* Summon interrupted.
* Desired avatar dies during combat.
* Desired avatar manually released.
* Summoner automation disabled during convergence.
* Dependent actions blocked during mismatch.

---

## 74. Favor tests

* Favor disabled.
* Desired avatar missing.
* Wrong avatar active.
* Desired avatar active with Favor missing.
* Desired avatar active with Favor already present.
* Favor pending.
* Favor failure and backoff.

---

## 75. Ward tests

* Ward disabled.
* Ward invalid for desired avatar.
* Desired avatar missing.
* Wrong avatar active.
* Buff present.
* Buff absent.
* Ward recast unavailable.
* Ward pending.
* Ward failure and backoff.
* Ward effect removed.
* Ward does not pre-refresh.

---

## 76. Pet-combat tests

* Engagement disabled.
* Desired avatar missing.
* Wrong avatar active.
* First target engagement.
* Repeated evaluation of same engagement key.
* Target switch.
* Combat end and re-engage.
* Pet already attacking correct target.
* Pet attacking different target.
* Desired avatar dies and is resummoned during same combat generation.
* New pet instance receives Assault.
* Assault pending.
* Assault failure and backoff.
* Rage with no target.
* Rage with dead target.
* Rage with stale target.
* Rage with stale pet identity.
* Rage recast unavailable.
* Rage pending.
* Rage range failure.
* Target dies while Rage is pending.
* Rage enabled with Assault disabled.

---

## 77. Scheduler and serialization tests

* Release and Assault otherwise simultaneously eligible.
* Only Release remains eligible during mismatch.
* Release and Ward conflict.
* Release and Rage conflict.
* Favor and Assault simultaneously eligible after convergence.
* Ward and Rage simultaneously eligible.
* Ward in backoff while Rage is ready.
* Assault in backoff while Ward is ready.
* Summon blocked while any pet remains observed.
* Existing higher-priority recovery action versus Release.
* Pet-action pending watchdog.
* Stale target at dispatch.
* Stale pet identity at dispatch.
* No movement lock for pet commands.

---

## 78. Replay fixtures

Replay coverage should include:

* Summon started.
* Summon completed.
* Summon interrupted.
* Avatar appears.
* Avatar disappears.
* Wrong avatar appears.
* Release succeeds.
* Release fails.
* Wrong avatar released during combat.
* Desired avatar appears during ongoing combat.
* Avatar’s Favor succeeds.
* Avatar’s Favor fails.
* Ward starts.
* Ward completes.
* Ward fails.
* Ward effect applied.
* Ward effect removed.
* Assault succeeds.
* Assault fails.
* Pet begins attacking.
* Rage starts.
* Rage completes.
* Rage fails.
* Blood Pact recast changes.
* Target dies.
* Target changes.
* Combat generation begins and ends.
* Pet server ID changes during the same combat generation.

Tests should assert both generated actions and the absence of prohibited actions.

---

# Part XIX: Implementation Plan

## 79. Phase 1 — Repository audit

* Inspect Bard and Corsair maintenance providers.
* Identify maintenance provider interfaces.
* Identify combat/offensive provider interfaces.
* Identify scheduler candidate and priority behavior.
* Identify spell and job-ability executors.
* Identify current pet-command support.
* Identify pet-action completion and failure events.
* Identify pet and target server-ID handling.
* Identify pending-action timeout and retry behavior.
* Identify movement locks by action kind.
* Identify profile-v2 and WinForms option-list conventions.

The audit must return code facts rather than assumptions.

---

## 80. Phase 2 — Configuration contract

* Add the Summoner profile-v2 shape.
* Require a valid desired avatar when enabled.
* Add normalization and validation.
* Create or expose the capability catalog.
* Add UI controls.
* Add profile round-trip tests.
* Preserve backward compatibility.

---

## 81. Phase 3 — Shared pet-command infrastructure

* Add or extend pet action classification.
* Add shared pet-command serialization.
* Capture pet and target identities.
* Integrate completion, failure, interruption, and timeout.
* Add centralized retry/backoff.
* Verify movement behavior.

---

## 82. Phase 4 — Summoner maintenance

* Implement desired-avatar convergence.
* Implement correction during and outside combat.
* Implement strict mismatch blocking.
* Implement Avatar’s Favor maintenance.
* Implement one Ward maintenance rule.
* Add diagnostics and tests.

---

## 83. Phase 5 — Reusable pet combat

* Implement common `PetCombatProvider`.
* Implement `SummonerPetCombatAdapter`.
* Add combat-generation and pet-instance engagement keys.
* Add Assault.
* Add one Rage-on-availability behavior.
* Add stale target and stale pet validation.
* Add diagnostics and tests.

---

## 84. Phase 6 — Integration

* Test cross-provider serialization.
* Test mismatch hard dependencies.
* Test scheduler priorities.
* Test starvation prevention.
* Add replay fixtures.
* Run the full regression suite.
* Update architecture and user documentation.

---

# Part XX: Open Code-Fact Questions

## 85. Questions requiring repository inspection

1. What are the exact maintenance provider interfaces?
2. How are Bard and Corsair providers registered?
3. Which existing domain should own pet engagement and offense?
4. Does UnifiedCombat already track combat generations?
5. Does runtime expose pet server IDs reliably?
6. Does runtime expose the pet’s current target?
7. How is avatar identity represented?
8. Are pet commands already supported by a generic executor?
9. How are Ward and Rage actions distinguished?
10. How are pet-action completion, failure, and interruption detected?
11. Can target IDs be executed without mutable `<t>`?
12. Does the scheduler already serialize pet actions?
13. Is retry backoff centralized?
14. Is there a pending-action watchdog?
15. Which action kinds acquire movement locks?
16. Can Avatar’s Favor state be observed reliably?
17. What authoritative avatar/pact resource data is available?
18. Can the UI and addon share generated capability data?
19. How are localized display names and stable IDs handled?
20. Which replay events cover pet lifecycle changes?
21. How should pet-instance identity be reset across summon/release events?
22. Can a pet action in progress be distinguished from a merely pending command?
23. Which global emergency actions may preempt avatar correction?

---

# Part XXI: Representative Runtime Behavior

## 86. Normal startup

Given:

```lua
summoner = {
    enabled = true,
    avatar = "Ifrit",

    maintenance = {
        avatar_favor = true,

        ward = {
            enabled = true,
            action = "Crimson Howl",
        },
    },

    pet_combat = {
        engage_on_combat_start = true,

        offensive_action = {
            enabled = true,
            action = "Flaming Crush",
            usage = "on_cooldown",
        },
    },
}
```

Expected behavior:

```text
No avatar exists
    ↓
Summon Ifrit
    ↓
Observe Ifrit
    ↓
Maintain Avatar’s Favor
    ↓
Maintain Crimson Howl
    ↓
Engage current combat target with Assault
    ↓
Use Flaming Crush when legal
```

---

## 87. Wrong avatar during combat

```text
Desired avatar: Ifrit
Observed avatar: Garuda
Current state: fighting an enemy
    ↓
Favor, Ward, Assault, and Rage are blocked
    ↓
Release Garuda when scheduler and pet channel permit
    ↓
Observe no pet
    ↓
Summon Ifrit when spell execution permits
    ↓
Observe new Ifrit pet instance
    ↓
Maintain Favor and Ward
    ↓
Assault current target for the new engagement key
    ↓
Resume Flaming Crush automation
```

Combat never converts Garuda into an acceptable runtime state.

---

## 88. Manual avatar replacement

```text
Desired avatar: Ifrit
Observed avatar: Ifrit
User manually summons Garuda
    ↓
Observed state no longer matches profile
    ↓
UnifiedCombat treats Garuda as configuration drift
    ↓
Release Garuda
    ↓
Restore Ifrit
```

No profile mutation and no implicit manual override occur.

---

## 89. Desired avatar dies mid-fight

```text
Ifrit is fighting target A
    ↓
Ifrit disappears
    ↓
Pending pet-bound actions become stale
    ↓
Summon Ifrit when legal
    ↓
New Ifrit pet instance appears
    ↓
Engagement key changes because pet server ID changed
    ↓
Assault target A again
    ↓
Resume Favor, Ward, and Rage behavior
```

---

# Part XXII: Final Architectural Contract

## 90. Final contract

```text
UI and profile
    own durable desired Summoner configuration

SummonerMaintenanceProvider
    continuously converges runtime toward the desired avatar
    and maintains Favor and Ward only after convergence

PetCombatProvider
    controls target-relative behavior only for the configured pet

Job-specific pet adapter
    supplies Summoner, Beastmaster, or Puppetmaster mechanics

Scheduler
    selects actions and enforces domain priorities

Shared executors
    dispatch spells, job abilities, and pet commands

Addon runtime
    observes results and triggers the next convergence evaluation
```

The central rule is:

> UnifiedCombat does not accept a usable approximation of the configured Summoner state. It continuously drives runtime toward the exact durable configuration and blocks dependent automation until that configuration is satisfied.
