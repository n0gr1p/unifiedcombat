# Summoner automation Phase 1 — repository audit

**RFC:** `SMN_RFC.md`

**Audit date:** 2026-07-28

**Repository baseline:** `561c54b9236f` on `scheduler-refactor`

## Scope

This document completes Phase 1 of the Summoner RFC implementation plan. It records the current repository and installed Windower resource facts needed before the configuration contract and runtime implementation begin.

No Summoner runtime behavior, profile fields, UI controls, provider registration, scheduler action kinds, or dispatch paths are added in Phase 1.

## Executive findings

1. The active runtime is `UnifiedCombat.lua` -> `unified_engine.lua` -> `unified_scheduler.lua` plus `unified_combat_core.lua`. The older `dd2_engine.lua`, `dd2_module.lua`, and `melee_engine.lua` contain pet-related code but are not required by the active engine path (`UnifiedCombat.lua:366-367`, `unified_engine.lua:1-2`).
2. Maintenance has one registered scheduler provider with the interface `provider.collect(ctx, out)`. Bard and Corsair are subordinate proposer modules called by that provider; they are not separately registered scheduler providers (`uc_provider_maintenance.lua:18-44`, `uc_provider_maintenance.lua:187-269`, `unified_scheduler.lua:6043-6070`).
3. Combat uses one registered provider exposing separate collection methods for offense, sleep, engagement, and job abilities (`uc_provider_combat.lua:71`, `uc_provider_combat.lua:225`, `uc_provider_combat.lua:334`, `uc_provider_combat.lua:538`, `unified_scheduler.lua:5997-6041`).
4. The practical scheduler proposal contract is a Lua table. Only `proposal_id` and `provider` are required by identity validation. Other behavior depends on conventional fields such as `action_type`, `action_name`, target identity, priority, expiry, duplicate key, lock class, and expected lifecycle (`uc_scheduler_proposals.lua:5-31`).
5. Proposals have no explicit `domain` field. Domain ownership is currently expressed by which gated collection group calls a provider and which provider-specific dispatch branch receives the selected proposal (`unified_scheduler.lua:3408-3440`, `unified_scheduler.lua:5237-5288`).
6. The active scheduler supports player `spell`, `ja`, `ws`, and `engage` execution paths. It has no active `/pet` dispatcher or pet action kind. Dormant legacy engines do issue `/pet` commands, including numeric target IDs (`dd2_engine.lua:1734-1743`, `dd2_engine.lua:2208-2224`).
7. Installed Windower resources classify Summoner commands more precisely than the current scheduler:
   - `Assault`: resource ID 88, prefix `/pet`, type `PetCommand`, recast 170.
   - `Release`: resource ID 90, prefix `/pet`, type `PetCommand`, recast 172.
   - `Avatar's Favor`: resource ID 250, prefix `/pet`, type `PetCommand`, recast 176.
   - `Crimson Howl`: resource ID 548, prefix `/pet`, type `BloodPactWard`, recast 174, status 68.
   - `Flaming Crush`: resource ID 550, prefix `/pet`, type `BloodPactRage`, recast 173.
   - `Ifrit`: spell resource ID 298, type `SummonerPact`.
8. Current action readiness resolves names against `res.job_abilities` and classifies any owned result as `ja`, but current command builders convert every such result to `/ja`. Pet resources therefore cannot reuse the current JA dispatch unchanged (`unified_scheduler.lua:2590-2634`, `unified_scheduler.lua:2981-2992`, `uc_scheduler_command_builder.lua:16-19`, `unified_scheduler.lua:4747-4882`).
9. Scheduler context contains player, self, current target, party, and the mob array indexed by server ID. It does not observe the `pet` target or expose a pet identity (`uc_scheduler_context.lua:11-64`).
10. The scheduler has one generic pending record, but its acknowledgement and action-message completion are player-actor-centric. Pet action packets are not safely correlated with pending completion, failure, or retry (`uc_scheduler_pending_record.lua:3-31`, `unified_scheduler.lua:5659-5728`, `unified_scheduler.lua:5795-5846`).
11. Profile v2 currently has maintenance configuration for COR, BRD, and GEO but no Summoner configuration. The normalizer supplies defaults and legacy projection; the WinForms writer constructs the structured v2 tree from its flat working profile (`uc_config_normalizer.lua:566-591`, `uc_config_normalizer.lua:1052-1099`, `UnifiedCombatWinForms/StructuredProfileV2Writer.cs:595-646`).
12. The UI's normal job-action option-list convention is runtime hydration from `remote_bridge.lua`. COR has a static C# list used when live roll options are absent; no cross-language static capability catalog is established (`remote_bridge.lua:718-759`, `remote_bridge.lua:995-1015`, `UnifiedCombatWinForms/MainForm.ParityLogic.cs:800-905`, `UnifiedCombatWinForms/MainForm.ParityLogic.cs:1486-1500`, `UnifiedCombatWinForms/HubUiConstants.cs:163-195`).

## 1. Active runtime boundary

`UnifiedCombat.lua` requires `unified_combat_core` and `unified_engine`. `unified_engine` requires `unified_scheduler` and the same core (`UnifiedCombat.lua:366-367`, `unified_engine.lua:1-2`).

The repository's older engines contain existing pet helpers:

- `dd2_engine.lua` reads pet name, status, and HPP through `windower.ffxi.get_mob_by_target('pet')` (`dd2_engine.lua:1259-1281`).
- Its generic ability caster uses the resource `prefix`, so a `PetCommand` becomes `/pet`; enemy actions are sent with a numeric target ID (`dd2_engine.lua:1734-1743`).
- It directly sends numeric-target `/pet deploy` and `/pet fight` commands (`dd2_engine.lua:2208-2218`).

Those files are useful evidence that Windower accepts numeric target IDs for some `/pet` commands, but they are not reusable scheduler infrastructure and are not on the active engine's require path.

## 2. Provider interfaces and registration

### 2.1 Maintenance provider

The registered maintenance provider contract is:

```lua
local provider = require('uc_provider_maintenance').new(deps)
provider.collect(ctx, out)
```

`new(deps)` validates its dependencies immediately. `collect(ctx, out)` appends zero or more proposal tables to the caller-owned output array (`uc_provider_maintenance.lua:18-44`, `uc_provider_maintenance.lua:96-184`).

Collection is gated by:

- global engine enabled state;
- a present player and main job;
- city-zone suppression;
- the maintenance domain;
- a 1 Hz maintenance cadence, except active BRD sequencing is collected every scheduler tick (`uc_provider_maintenance.lua:47-77`, `unified_scheduler.lua:3428-3440`).

The provider currently selects exactly one job branch per collection:

- COR main job calls `uc_cor_maintenance.propose(settings)`;
- BRD main or subjob calls `uc_brd_maintenance.propose(config, ctx)`;
- GEO main job runs inline count-based logic (`uc_provider_maintenance.lua:187-287`).

`uc_cor_maintenance.propose` returns either `nil` or a compact action description with `action_name`, `action_type = "ja"`, target information, reason, urgency, and detail (`uc_cor_maintenance.lua:152-163`, `uc_cor_maintenance.lua:285-447`).

`uc_brd_maintenance.propose` returns either `nil` or a compact action description with action type/name, reason, urgency, and detail. Bard also owns an internal sequencing lane and its own pending song-confirmation state (`uc_brd_maintenance.lua:605-624`, `uc_brd_maintenance.lua:1896-1980`).

The outer maintenance provider expands those compact descriptions into full scheduler proposals. COR is assigned provider `maintenance_cor`, band 75, and action type `ja`. BRD is assigned provider `maintenance_brd` and the configured BRD maintenance band (`uc_provider_maintenance.lua:187-238`, `uc_provider_maintenance.lua:246-283`).

### 2.2 Combat/offensive provider

The registered combat provider contract is:

```lua
local provider = require('uc_provider_combat').new(deps)
provider.collect_engage(ctx, out)
provider.collect_sleep(ctx, out)
provider.collect_offense(ctx, out)
provider.collect_ja(ctx, out)
```

Each method validates `ctx` and `out` and appends proposals directly. Current action types are:

- offense: `ws`;
- sleep: `spell`;
- engagement: `engage`;
- configured abilities: `ja` (`uc_provider_combat.lua:71-185`, `uc_provider_combat.lua:225-331`, `uc_provider_combat.lua:334-535`, `uc_provider_combat.lua:538-625`).

Combat-domain collection order is target acquisition, engagement, pull, tank enmity, sleep, offense, and job abilities (`unified_scheduler.lua:3411-3420`). That order is not the normal priority rule; all collected proposals are ranked afterward. It can still matter to special logic such as the BRD lane removing non-BRD proposals and diagnostic code looking at the first proposal before ranking (`unified_scheduler.lua:3428-3457`, `uc_provider_combat.lua:381-386`).

### 2.3 Registration facts

Provider instances are constructed once at module load in `unified_scheduler.lua:5944-6070`. There is no dynamic registry API. Adding Summoner maintenance or reusable pet combat will require an explicit construction dependency and explicit collection call, or a deliberate refactor of the registry.

Dispatch is also provider-name-based. Only these provider strings are routed:

- `target_control`;
- `pull_control`;
- `combat`;
- `defensive_internal`;
- `defensive_healbot`;
- `maintenance_cor`;
- `maintenance_brd` (`unified_scheduler.lua:5237-5288`).

An unrecognized provider is not dispatched.

## 3. Scheduler candidate and priority behavior

### 3.1 Proposal fields

Only `proposal_id` and `provider` are mandatory in `validate_identity`. The live normalizer enforces expiry, commit deadline, integer priority band, and clamped urgency (`uc_scheduler_proposals.lua:5-31`).

Existing providers consistently include:

- `proposal_id`;
- `family_id`;
- `provider`;
- `action_type`;
- `action_name`;
- `target_kind`;
- `target_id`;
- `target_name`;
- `priority_band`;
- `urgency`;
- `starvation_eligible`;
- `created_at`;
- `expires_at`;
- `commit_deadline`;
- `movement_policy`;
- `range_policy`;
- `recast_key`;
- `duplicate_suppression_key`;
- `lock_class`;
- `expected_ack`;
- `expected_effect`;
- `sticky`;
- movement-preemption flags;
- `reason_code`;
- `detail`;
- sometimes `legacy_command` and `required_setting`.

These are conventions, not a centrally validated schema.

### 3.2 Ranking

The score is:

```text
priority_band + urgency * 9.9
```

Starvation, sticky, and risk terms are present but all currently evaluate to zero (`uc_scheduler_ranker.lua:103-118`).

Ties are broken by:

1. earlier expiry;
2. lexically smaller provider name;
3. lexically smaller proposal ID (`uc_scheduler_ranker.lua:149-165`).

Provider registration order is therefore not the ordinary rank rule. Special post-ranking behavior still exists:

- an eligible engage proposal can be selected by the preemptive-engage policy;
- a noncritical cure can be replaced by a ready combat JA/WS weave;
- an active Bard action lane removes every non-BRD proposal before ranking (`unified_scheduler.lua:3673-3713`, `unified_scheduler.lua:3428-3457`).

Current named priority bands include:

| Candidate | Band |
| --- | ---: |
| BRD maintenance | 200 |
| Critical cure | 153 |
| Sleep | 142 |
| Skillchain continuation | 131 |
| Aftermath WS | 108 |
| Tank engage | 107 |
| Default engage | 72 |

These constants are defined in `unified_scheduler.lua:1610-1619`. COR maintenance uses 75 (`uc_provider_maintenance.lua:199-225`); ordinary combat WS/JA behavior commonly uses 70, with tank JAs using 99 (`uc_provider_combat.lua:116-123`, `uc_provider_combat.lua:591-617`).

### 3.3 Validation and locks

Validation rejects:

- a disabled `required_setting`;
- proposals older than 0.8 seconds;
- expired proposals;
- duplicates;
- reaction-held actions;
- pending-engage conflicts;
- certain conflicting lock classes;
- hard locks (`uc_scheduler_ranker.lua:22-100`, `uc_scheduler_ranker.lua:224-257`).

The current pending-conflict and hard-lock checks enumerate `spell`, `ja`, `ws`, and `move`. A newly invented action type such as `pet` would not automatically receive those protections (`uc_scheduler_ranker.lua:70-81`, `uc_scheduler_locks.lua:45-66`).

## 4. Existing execution infrastructure

### 4.1 Spell readiness and dispatch

`action_ready(name, target_id)` searches spell resources first, then job-ability resources (`unified_scheduler.lua:2981-2992`).

Spell readiness checks:

- resource presence;
- learned state;
- current main/subjob usability;
- spell recast;
- player presence and MP (`unified_scheduler.lua:2538-2587`, `unified_scheduler.lua:2644-2664`).

Spell dispatch is not one generic executor. Provider-specific dispatch branches build commands, apply movement handling, mark action state, record pending state, and emit diagnostics.

Combat spells can be sent to an immutable numeric target ID:

```lua
input /ma "<spell>" <numeric-server-id>
```

The commit plan and combat dispatcher both revalidate the target ID before sending (`uc_scheduler_dispatch_plan.lua:31-77`, `unified_scheduler.lua:5032-5133`).

Self spells use `<me>` (`unified_scheduler.lua:5166-5222`). Bard targeted songs use a captured target name after validating the proposal target ID/name (`unified_scheduler.lua:4341-4352`).

### 4.2 Job-ability readiness and dispatch

JA readiness checks:

- job-ability resource presence;
- ownership in `windower.ffxi.get_abilities().job_abilities`;
- limited player status rules;
- enemy target validity/range when the resource targets an enemy;
- ability recast (`unified_scheduler.lua:2914-2978`).

The current command builder assumes every `action_kind == "ja"` uses `/ja` (`uc_scheduler_command_builder.lua:3-20`). Combat dispatch repeats that assumption directly for both enemy-targeted and self-targeted abilities (`unified_scheduler.lua:4747-4882`).

This is incompatible with Summoner pet resources because they are stored in `res.job_abilities` but declare `prefix = "/pet"` and pet-specific `type` values. `Avatar's Favor` is also a `/pet` `PetCommand` in the installed resources, not a `/ja` command.

### 4.3 Command dispatcher

`uc_scheduler_dispatcher` is a generic intent dispatcher, not a game-action executor. For a `send_command` intent it validates that a command string exists and calls the injected `send_command` function (`uc_scheduler_dispatcher.lua:137-145`, `uc_scheduler_dispatcher.lua:275-289`).

It does not:

- classify spells, JAs, or pet commands;
- check recasts;
- capture pet or target identity;
- create pending state;
- interpret action packets.

Those responsibilities remain in provider-specific code and scheduler helpers.

## 5. Current pet-command support

The active scheduler has no `/pet` command construction or dispatch branch. Searches of the active path find no pet context, pet proposal, pet pending channel, or pet action-state handler.

The repository does contain legacy pet behavior:

- `Cast_Ability` honors `res.job_abilities[*].prefix`, allowing `/pet` (`dd2_engine.lua:1734-1743`);
- PUP `Deploy` and BST `Fight` use numeric target IDs (`dd2_engine.lua:2208-2218`);
- BST `Jettatura` uses `<me>` (`dd2_engine.lua:2220-2225`);
- legacy pet helpers observe name, status, and HPP (`dd2_engine.lua:1259-1281`).

This code directly dispatches commands and does not use current scheduler proposals, priorities, pending state, or movement ownership. It should be treated as evidence only, not as shared infrastructure.

## 6. Action completion, failure, and interruption

### 6.1 Event ingress

`UnifiedCombat.lua` opens one `ActionPacket` listener and forwards each action to both the combat core and scheduler (`UnifiedCombat.lua:1927-1940`).

Incoming `0x029` action-message packets are decoded into actor ID, target ID, effect/parameter, and message ID and forwarded to both components (`UnifiedCombat.lua:1953-1979`). The scheduler also observes raw `0x028`, `0x029`, `0x037`, and `0x063` packets for its current features (`unified_scheduler.lua:5440-5517`).

### 6.2 Player action lifecycle

The generic scheduler pending record starts with:

- `state = "sent"`;
- 0.6-second acknowledgement deadline;
- 2.5-second effect deadline;
- 3.0-second completion deadline (`uc_scheduler_pending_record.lua:3-31`).

On a local-player action packet, pending becomes acknowledged. A pending action is marked complete when an action packet contains the expected target ID (`unified_scheduler.lua:5659-5728`).

On action-message packets:

- non-spell local actions end the actor-centric action lock;
- local spell messages use spell-specific start/success/interruption classification;
- the generic pending record is completed only after rejecting messages whose actor is not the local player and whose target conflicts with the pending target (`unified_scheduler.lua:5795-5846`, `unified_scheduler.lua:1868-1958`).

The action-state layer has an 8-second default lag timeout and a 1-second JA timeout (`unified_scheduler.lua:77-86`, `uc_scheduler_action_state.lua:681-742`).

### 6.3 Pet lifecycle gap

Pet action packets use the pet as actor. Current pending acknowledgement and action-message completion compare the actor against the player ID, so they do not provide a pet completion/failure lifecycle.

The combat core can already parse property-bearing actions from `job_abilities` and `monster_abilities`, including pet Rage actions, for skillchain observation (`unified_combat_core.lua:2563-2586`, `unified_combat_core.lua:2671-2743`, `tests/replay/harness/selftest_skillchain_state.lua:108-109`). That observation is not connected to scheduler pending state.

The current generic action-packet completion check is target-based and does not verify the actor or action identity before completing pending (`unified_scheduler.lua:5720-5727`). It is therefore not sufficient for a pet-command coordinator without stricter pet ID, target ID, action ID, and category matching.

No current code classifies pet-action success, rejection, interruption, or range failure for scheduler retry.

## 7. Pet and target server-ID handling

### 7.1 Targets

Scheduler context stores mob objects by `mob.id`; proposals capture `target_id`, and commit validation re-queries `windower.ffxi.get_mob_by_id(target_id)` (`uc_scheduler_context.lua:21-43`, `uc_scheduler_dispatch_plan.lua:53-77`).

Combat JA and spell commands can use the captured numeric ID rather than mutable `<t>` (`unified_scheduler.lua:4775-4794`, `unified_scheduler.lua:5068-5087`). The legacy pet code also demonstrates numeric IDs for `/pet` enemy commands (`dd2_engine.lua:1734-1743`, `dd2_engine.lua:2208-2218`).

Therefore numeric target dispatch is established for the repository, but active scheduler commit validation for `/pet` has not been implemented or tested.

### 7.2 Pets and avatars

Scheduler context never calls `get_mob_by_target('pet')` and has no `pet`, `pet_id`, `pet_instance`, or avatar-identity field (`uc_scheduler_context.lua:11-64`).

The legacy helpers represent avatar identity as the observed pet mob's `name`; they also read `status` and `hpp` (`dd2_engine.lua:1259-1281`). They do not establish a scheduler contract for pet server ID or current target.

No active code tracks:

- combat generations;
- pet-instance generations;
- a pet's current combat target;
- pet disappearance as a state transition;
- pet server-ID changes during one combat target.

The current player engagement duplicate key is only target-based (`engage:<target-id>`), and pending engagement is a separate target-based structure (`uc_provider_combat.lua:507-535`, `unified_scheduler.lua:881-918`).

## 8. Pending timeout, retry, and serialization

### 8.1 Generic pending watchdog

`p1_update_pending_state` is the generic pending watchdog:

- a live pending record becomes `timed_out` after `effect_deadline`;
- its duplicate key is held for another 0.75 seconds;
- failed, canceled, timed-out, and complete records are removed after their completion deadline (`uc_scheduler_pending.lua:3-27`).

This update runs before proposal collection and ranking (`unified_scheduler.lua:3647-3653`).

### 8.2 Retry behavior

`p1_pending_mark_failed(now, result_code, retry_delay)` stores the caller-provided delay and applies it to both the completion deadline and duplicate suppression (`uc_scheduler_pending.lua:52-68`).

There is no centralized per-action retry history or exponential backoff. Current retry/throttle behavior is split among:

- generic duplicate suppression;
- provider cadence gates;
- Bard's internal pending/failure state;
- engagement's dedicated retry state;
- action-state cooldown/timeout;
- feature-specific attempt maps.

This does not yet meet the RFC's requirement for a shared pet-command retry/backoff lifecycle.

### 8.3 Serialization

A live generic pending record creates a cast lock and movement lock. The cast lock rejects new `spell`, `ja`, and `ws` proposals; the movement lock rejects movement proposals (`uc_scheduler_locks.lua:23-66`).

Pending lock-class conflict logic also enumerates `spell`, `ja`, `ws`, and `move` (`uc_scheduler_ranker.lua:70-81`).

There is no pet-specific serialization. A Phase 3 pet action kind must be added to both pending-conflict and hard-lock rules; otherwise a novel `pet` action type would bypass existing protections.

## 9. Movement behavior by current action path

Proposal `movement_policy = "must_stop"` is converted into a dispatch-plan prelude of type `stop`, but the dispatch plan module only describes and revalidates the plan; it does not execute the prelude (`uc_scheduler_dispatch_plan.lua:3-29`).

Actual movement handling is provider/action-path-specific:

- Bard maintenance applies a movement stop before both its spells and JAs (`unified_scheduler.lua:4317-4328`).
- Defensive internal spells apply an explicit movement lock/stop (`unified_scheduler.lua:4482-4499`).
- Combat spells use a movement-freeze preparation sequence before dispatch (`unified_scheduler.lua:4894-4971`).
- Tank JAs and tank spells add explicit stop/settle behavior (`unified_scheduler.lua:4640-4693`, `unified_scheduler.lua:4813-4844`, `unified_scheduler.lua:4982-5031`).
- Ordinary combat JAs do not issue a run stop in their non-tank path (`unified_scheduler.lua:4747-4882`).
- COR maintenance JAs do not issue a run stop (`unified_scheduler.lua:4237-4305`).
- Player engagement proposals use `movement_policy = "can_move"` (`uc_provider_combat.lua:507-535`).

A live pending action also blocks scheduler movement proposals regardless of the proposal's original movement policy (`uc_scheduler_locks.lua:23-44`).

There is no current pet movement behavior. To satisfy the RFC, Release, Assault, Ward, and Rage need a dispatch path that does not call the explicit run-stop helpers and does not independently restore movement. Summon spells can use the normal spell movement path.

## 10. Profile-v2 conventions

### 10.1 Canonical normalization

`uc_config_normalizer.default_config(meta)` owns canonical defaults. Current maintenance defaults are:

```lua
maintenance = {
    enabled = true,
    cor = { ... },
    brd = {
        enabled = false,
        songs = {},
        dummy_songs = {},
        ...
    },
    geo = {},
}
```

(`uc_config_normalizer.lua:362-375`, `uc_config_normalizer.lua:566-591`)

`normalize_maintenance` accepts either the nested v2 shape or legacy flat fields and writes into this canonical structure (`uc_config_normalizer.lua:1052-1099`).

The structured profile builder normalizes settings, selects durable domains, and returns `{ version = 2, profile = ..., config = ... }` (`uc_profile_v2.lua:593-625`).

Job-specific durable maintenance is currently pruned:

- COR maintenance is kept only for main COR;
- BRD maintenance is kept for main or sub BRD (`uc_profile_v2.lua:166-176`, `uc_profile_v2.lua:224-230`, `uc_profile_v2.lua:300-367`).

There is no Summoner applicability rule.

### 10.2 Validation

`validate_structured_profile_config` currently validates:

- payload table shape;
- recursively supported Lua key/value types and cycles;
- version 2;
- profile metadata primitive types;
- presence of a config table (`uc_profile_contract.lua:250-278`, `uc_profile_contract.lua:475-531`).

It does not semantically validate domain fields such as a desired avatar or pact compatibility. Phase 2 must add explicit Summoner validation rather than relying on the current structural validator.

### 10.3 WinForms writer

The WinForms app keeps a flat JSON working profile and `StructuredProfileV2Writer` converts it to the nested v2 tree. Maintenance is always enabled in output; COR is included for main COR or configured nondefault COR values; BRD is included for main/sub BRD (`UnifiedCombatWinForms/StructuredProfileV2Writer.cs:585-646`).

Summoner fields will require coordinated changes to:

- UI controls and working-profile capture/apply;
- default flat profile creation;
- structured v2 writer;
- writer tests;
- addon normalization and legacy projection, if any legacy flat mirror is intentionally added.

## 11. WinForms option-list conventions

The bridge currently derives most options from live state:

- owned job abilities from `windower.ffxi.get_abilities()`;
- learned/current-job spells from `windower.ffxi.get_spells()` plus resources;
- Bard songs through `uc_brd_song_options.collect(...)`;
- party members from live party state (`remote_bridge.lua:718-806`, `remote_bridge.lua:995-1015`).

The UI accepts an `options` snapshot, splits pipe-delimited strings, updates in-memory lists, and repopulates combo boxes (`UnifiedCombatWinForms/MainForm.ParityLogic.cs:800-905`).

COR has one offline exception: `EnsureCorRollOptions` uses `HubUiConstants.CorRollOptions` when the live list is empty (`UnifiedCombatWinForms/MainForm.ParityLogic.cs:1486-1500`, `UnifiedCombatWinForms/HubUiConstants.cs:163-195`).

No existing mechanism gives both Lua and C# a shared generated capability file. Current alternatives are:

- addon-side Windower resources;
- C# constants;
- live bridge option hydration.

The RFC requires offline authoring and avatar-based filtering, so Summoner cannot depend solely on the current live `request_options` pattern.

## 12. Installed Windower resource facts

The following facts come from the installed Windower resource files on the audited machine, not repository-controlled files:

| Resource | Stable ID | Prefix/type | Recast/status facts |
| --- | ---: | --- | --- |
| Assault | 88 | `/pet`, `PetCommand` | recast 170, enemy target |
| Release | 90 | `/pet`, `PetCommand` | recast 172, self target |
| Blood Pact: Rage | 91 | `/pet`, `PetCommand` | recast 173 |
| Blood Pact: Ward | 172 | `/pet`, `PetCommand` | recast 174 |
| Avatar's Favor | 250 | `/pet`, `PetCommand` | recast 176 |
| Crimson Howl | 548 | `/pet`, `BloodPactWard` | recast 174, status 68 |
| Flaming Crush | 550 | `/pet`, `BloodPactRage` | recast 173 |
| Hastega II | 602 | `/pet`, `BloodPactWard` | recast 174, status 33 |
| Ifrit | spell 298 | `/magic`, `SummonerPact` | recast 298 |
| Avatar's Favor buff | buff 431 | localized buff row | observable by buff ID |

Evidence:

- `C:/Program Files (x86)/Windower/res/job_abilities.lua:76-79`
- `C:/Program Files (x86)/Windower/res/job_abilities.lua:159`
- `C:/Program Files (x86)/Windower/res/job_abilities.lua:236`
- `C:/Program Files (x86)/Windower/res/job_abilities.lua:403-405`
- `C:/Program Files (x86)/Windower/res/job_abilities.lua:442`
- `C:/Program Files (x86)/Windower/res/spells.lua:301`
- `C:/Program Files (x86)/Windower/res/buffs.lua:426`
- `C:/Program Files (x86)/Windower/res/ability_recasts.lua:164-165`

These rows provide stable action IDs, English/Japanese names, prefix, action type, recast group, MP cost, target mask, range, and sometimes resulting status/duration.

They do **not** encode which avatar may use each Ward or Rage. A curated or generated avatar-to-pact compatibility catalog remains necessary.

The repository generally persists English action names and resolves resources by English name, with lowercase/normalization helpers (`unified_scheduler.lua:2525-2531`, `unified_scheduler.lua:2590-2634`). Stable IDs are not the current profile convention.

## 13. Direct answers to RFC section 85

### 1. What are the exact maintenance provider interfaces?

`require('uc_provider_maintenance').new(deps)` returns an object with `collect(ctx, out)`. It appends full proposals to `out`. COR implements `propose(settings)` and BRD implements `propose(config, ctx)` as subordinate compact-proposal interfaces.

### 2. How are Bard and Corsair providers registered?

They are not independent scheduler registrations. The one registered maintenance provider calls `uc_cor_maintenance.propose` or `uc_brd_maintenance.propose` based on the current job and emits providers named `maintenance_cor` and `maintenance_brd`.

### 3. Which existing domain should own pet engagement and offense?

The repository has a `combat` ownership gate containing target acquisition, player engagement, sleep, WS offense, and combat JAs (`unified_scheduler.lua:3411-3420`). No separate offense domain exists. Under the current architecture, combat is the only existing domain matching target-relative pet engagement and offense. A new provider name and dispatch route are still required.

### 4. Does UnifiedCombat already track combat generations?

No. It tracks skillchain resonance generations, but no player-combat generation exists. Engagement duplicate state is target-based, not combat-generation-based.

### 5. Does runtime expose pet server IDs reliably?

The audited scheduler does not request or store a pet mob. Legacy code reads the pet mob through `get_mob_by_target('pet')`, which should contain the normal mob `id`, but no active code or replay test establishes a reliable pet-ID contract. This remains an implementation prerequisite requiring runtime validation.

### 6. Does runtime expose the pet's current target?

No current repository code reads a current-target field from the pet mob or reconstructs it from pet actions. The active context has no pet object. This is not established.

### 7. How is avatar identity represented?

It is not represented in the active scheduler. Legacy helpers use the pet mob's English `name`.

### 8. Are pet commands already supported by a generic executor?

No. The generic intent dispatcher can send any prebuilt string, but the active action classifiers and command builders do not build `/pet` commands. Legacy direct dispatch honors the resource prefix outside the active scheduler.

### 9. How are Ward and Rage actions distinguished?

Installed `res.job_abilities` rows use `type = "BloodPactWard"` and `type = "BloodPactRage"` and separate recast IDs 174 and 173. The active scheduler does not currently inspect those type values.

### 10. How are pet-action completion, failure, and interruption detected?

They are not detected for scheduler lifecycle purposes. Action packets reach the core and scheduler, and property-bearing pet actions can affect skillchain observation, but pet actor/action identity is not matched to pending state.

### 11. Can target IDs be executed without mutable `<t>`?

Yes for current combat `/ma` and `/ja` paths, and legacy `/pet` enemy commands demonstrate numeric target IDs. Active scheduler `/pet` dispatch and its commit-time stale-target test do not yet exist.

### 12. Does the scheduler already serialize pet actions?

No. The generic pending record serializes current enumerated action types, but `pet` is not an action type in conflict, hard-lock, or dispatch logic.

### 13. Is retry backoff centralized?

No. Generic failure accepts a caller-supplied delay, while duplicate suppression, Bard, engagement, action state, and feature-specific attempts maintain separate timing.

### 14. Is there a pending-action watchdog?

Yes. Generic pending times out at its effect deadline and is later removed. Separate action-state, Bard, spell-wait, and engagement timeouts also exist.

### 15. Which action kinds acquire movement locks?

There is no single action-kind rule. A live generic pending action blocks scheduler movement proposals. Explicit run stops are provider/path-specific: BRD spell/JA, defensive spells, combat spells, and tank JA/spells stop; ordinary combat JA, COR JA, WS/engage paths shown here do not use those same stop helpers. Pet kinds do not exist.

### 16. Can Avatar's Favor state be observed reliably?

The player snapshot exposes `player.buffs`, and installed resources identify Avatar's Favor as buff ID 431, so presence can be checked by stable buff ID each scheduler tick. The repository has no current Summoner tracker or tests, so packet/timing reliability is not yet demonstrated.

### 17. What authoritative avatar/pact resource data is available?

Installed Windower spells and job abilities provide action IDs, names, prefixes, types, recasts, ranges, costs, targets, and some statuses/durations. They do not provide avatar-to-pact compatibility.

### 18. Can the UI and addon share generated capability data?

No established shared artifact exists. The addon reads Windower resources; WinForms uses bridge-fed live options and some independent constants. A shared generated catalog would be a new contract.

### 19. How are localized display names and stable IDs handled?

Windower resources expose stable numeric IDs and localized name fields. Current UnifiedCombat profile/UI conventions persist English names and resolve resources by normalized English name. Stable IDs are used internally for recast/buff/resource lookup but not generally persisted.

### 20. Which replay events cover pet lifecycle changes?

None. Existing pet-related replay coverage is limited to skillchain eligibility for property-bearing `job_abilities` and `monster_abilities`. There are no summon, appearance, disappearance, Assault, Release, Ward, Rage, pet-target, or pet-instance fixtures.

### 21. How should pet-instance identity be reset across summon/release events?

Current code provides no contract to inherit. The RFC-required key must be introduced. The strongest available runtime identity candidate is the observed pet server ID; absence or a changed ID must invalidate pet-bound state. That rule is a design requirement, not existing behavior.

### 22. Can a pet action in progress be distinguished from a merely pending command?

Not by current state. The scheduler records only its own sent pending action, and pet actor packets are not correlated with it. Action packets provide enough raw ingress to build a distinction, but the correlation logic does not exist.

### 23. Which global emergency actions may preempt avatar correction?

No answer exists until avatar-correction priority is assigned. Current ranking would allow any higher score to win, pending engagement blocks non-bypass proposals below band 131, reaction locks can reject proposals, and an active BRD action lane removes all non-BRD proposals. Current high bands are listed in section 3.2. Phase 4 must explicitly select and test the avatar-correction band against those policies.

## 14. Required prerequisites for later phases

These are gaps proven by the audit, not Phase 1 implementation work:

1. Define the canonical Summoner profile location and job-applicability rule.
2. Add strict semantic validation for enabled Summoner configuration and pact/avatar compatibility.
3. Create one authoritative avatar/pact catalog usable offline by WinForms and at runtime by Lua.
4. Extend scheduler context with an authoritative observed pet record including server ID, name, alive state, and any confirmed target evidence.
5. Add combat-generation and pet-instance identity explicitly; do not reuse target-only engagement duplicate state.
6. Add a pet action classification based on resource `prefix` and `type`; do not route pet resources through `/ja`.
7. Add an explicit pet-command dispatch route with numeric captured targets and commit-time pet/target revalidation.
8. Extend pending/conflict/duplicate rules to serialize pet commands.
9. Correlate completion and failure using captured pet ID, action ID/type, and target ID; do not use the current target-only completion test.
10. Establish one retry/backoff owner for pet commands and test timeout behavior.
11. Keep Release, Assault, Ward, and Rage out of explicit run-stop helpers. Keep summon spells on the normal spell path.
12. Add replay fixtures for all RFC pet lifecycle transitions before claiming runtime reliability.

## 15. Phase 1 completion statement

Phase 1 is complete as a repository audit. No runtime or profile behavior has been changed. The major blockers for Phase 2 and Phase 3 are now explicit:

- no shared static capability catalog;
- no Summoner profile contract;
- no pet in scheduler context;
- no pet action kind or dispatcher;
- no pet-aware pending lifecycle;
- no combat/pet generation tracking;
- no pet replay coverage.
