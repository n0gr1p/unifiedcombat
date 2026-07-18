# UnifiedCombat Reaction Runtime Design

## Scope

UnifiedCombat supports profile-configured safety reactions without delegating execution to a second addon or bypassing scheduler ownership.

The first live acceptance rule is `Cold Stare`: when the current combat target readies Cold Stare, UnifiedCombat turns away and holds enemy-facing work until that same actor completes Cold Stare.

## Ownership

- The UI owns durable reaction configuration in `config.reactions`.
- `_G.UC_ACTIVE_PROFILE` is the active durable source read by the reaction runtime.
- `_G.UC_SETTINGS` may contain `reaction_enabled` and `reaction_rules` compatibility projections.
- Actor IDs, effect IDs selected from resources, active locks, transition timestamps, and turn-applied state are addon-owned runtime state.
- UI edits remain local until Save. The addon consumes changes through normal profilev2 reload, autoload, or opt-in file-change reload.
- Reaction handling never starts or stops the engine and never writes a profile file.

## Durable Shape

```lua
config.reactions = {
    enabled = true,
    rules = {
        {
            trigger = "ability_window",
            name = "Cold Stare",
            response = "turn_away",
        },
        {
            trigger = "enemy_buff",
            name = "Dread Spikes",
            response = "stop_attacking",
        },
    },
}
```

The disabled, empty domain is optional so profiles created before reactions existed remain valid. A configured rule is durable and participates in profilev2 status and diff.

## Rule Types

### Ability Window

- `trigger = "ability_window"`
- `response = "turn_away"`
- Windower action category `7` is authoritative ready evidence.
- The ready ability is resolved from the first target action parameter through `resources.monster_abilities`.
- Windower action category `11` is authoritative completion evidence.
- Completion is correlated by actor ID and canonical ability name.
- The rule activates only when the actor is the current combat target.

### Enemy Buff

- `trigger = "enemy_buff"`
- `response = "stop_attacking"`
- The configured name is resolved through `resources.buffs`.
- The existing enemy-effect tracker supplies gain and removal evidence.
- Unresolved names fail closed and are reported by reaction status; IDs are never guessed or persisted.

## Scheduler Behavior

- Reaction turns use the existing scheduler turn dispatcher and turn-ownership module.
- The scheduler holds movement and suppresses ordinary face-to-target while a reaction is active.
- Enemy-targeted, combat, pull, target-control, movement, engage, disengage, target-switch, and weapon-skill proposals are rejected with `reaction_hold`.
- Party/self support proposals remain eligible, including cures, defensive buffs, songs, and rolls that do not target the enemy.
- UnifiedCombat does not disengage or change targets. Facing away stops melee while preserving combat state.
- When the final lock for the actor clears, scheduler-owned facing is restored toward the still-valid current target.
- Doom emergency handling remains above reaction handling.

## Runtime Lifecycle

- Locks are keyed by trigger, actor ID, and canonical action/effect name.
- Multiple locks may coexist; facing is restored only after the final lock for the actor clears.
- A new ability-ready event from the same actor supersedes an older incomplete ability-window lock.
- Target changes, zone changes, job changes, scheduler lock resets, and addon unload clear runtime reaction state.
- No speculative completion timeout is used. Missing completion evidence remains visible through diagnostics rather than being hidden by a guessed timer.

## Diagnostics

`//uc reactions status` reports:

- enabled state and configured rule count
- active runtime locks
- last transition
- unresolved enemy-buff resource names

