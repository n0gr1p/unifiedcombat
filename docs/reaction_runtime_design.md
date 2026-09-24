# UnifiedCombat Reaction Runtime Design

## Scope

UnifiedCombat supports profile-configured safety reactions without delegating execution to a second addon or bypassing scheduler ownership.

The first live acceptance rule is `Cold Stare`: when a valid live enemy actor readies Cold Stare, UnifiedCombat turns away from that actor and holds enemy-facing work until that same actor completes Cold Stare.

## Ownership

- The UI owns durable reaction configuration in `config.reactions`.
- `_G.UC_ACTIVE_PROFILE` is the active durable source read by the reaction runtime.
- `_G.UC_SETTINGS` may contain `reaction_enabled` and `reaction_rules` compatibility projections.
- Actor IDs, effect IDs selected from resources, active locks, transition timestamps, and turn-applied state are addon-owned runtime state.
- UI edits remain local until Save. Save writes the exact Profile V2 file, and the unconditional stable-file watcher consumes valid changes automatically.
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
        {
            trigger = "ability_window",
            name = "Range Pulse",
            response = "move_to_range",
            distance = 12.0,
        },
    },
}
```

The disabled, empty domain is optional so profiles created before reactions existed remain valid. A configured rule is durable and participates in profilev2 status and diff.

## Rule Types

### Ability Window

- `trigger = "ability_window"`
- `response = "turn_away"`, `response = "run_away"`, or `response = "move_to_range"`
- `run_away` and `move_to_range` require a positive numeric `distance` in raw coordinate yalms.
- Windower action category `7` is authoritative ready evidence.
- The ready ability is resolved from the first target action parameter through `resources.monster_abilities`.
- Windower action category `11` is authoritative completion evidence.
- Completion is correlated by actor ID and canonical ability name.
- The rule activates for any valid live enemy actor observed readying the configured ability; target selection does not determine whether the ability can affect the player.
- `run_away` recalculates the vector from the enemy's current X/Y position toward the player's current X/Y position every movement tick.
- Its distance is raw center-coordinate distance. Player and enemy model sizes are not added or subtracted.
- It stops at `distance - 0.15` yalms or farther, then remains stopped for the rest of that ability window so a moving enemy cannot drive overshoot after satisfaction.
- `move_to_range` continuously reevaluates the same raw 2D distance throughout the Ability Window. Below `distance - 0.15` it moves outward; above `distance + 0.15` it moves inward; inside that tolerance it stops once and holds reaction ownership without repeated stop commands.
- If either actor moves after `move_to_range` reaches its band, the next movement evaluation resumes the required inward or outward correction.

### Enemy Buff

- `trigger = "enemy_buff"`
- `response = "stop_attacking"`
- The configured name is resolved through `resources.buffs`.
- The existing enemy-effect tracker supplies gain and removal evidence.
- Enemy-buff reactions are scoped to the current combat target because they suppress attacks against that affected target.
- Unresolved names fail closed and are reported by reaction status; IDs are never guessed or persisted.

### Event Window

- `trigger = "event_window"`
- `response` is `stop_attacking` or `turn_away`; separate rules may use both responses for the same lifecycle.
- `activate_event` is one of `spell_start`, `ability_start`, or `buff_gained`.
- `release_event` is one of `spell_end`, `ability_end`, or `buff_lost`; `release_name` may differ from the activation name.
- Spell/ability starts are observed directly from Windower action categories 8/7, so safety work can begin before a resulting buff is applied.
- Category-8 spell starts resolve the spell resource id from `act.targets[1].actions[1].param`; `act.param` is not treated as the spell id for begin-cast packets.
- For `buff_lost` releases, the runtime holds continuously across action completion while waiting for the expected buff. Once seen, actual buff loss is authoritative.
- If the expected buff never appears, `confirmation_timeout_seconds` releases the hold after action completion rather than leaving combat suspended indefinitely.
- An authoritative cast-interrupted action message releases a `spell_start` lifecycle immediately; the confirmation timeout remains the fallback for normally completed casts whose expected buff never appears.
- Event-window stop-attacking rules are scoped to the current combat target.
- Legacy `enemy_buff` and `ability_window` rules remain valid and retain their existing behavior.

## Scheduler Behavior

- Reaction turns use the existing scheduler turn dispatcher and turn-ownership module.
- Both distance-bearing responses use the existing scheduler movement facade and dispatcher under `scheduler_reaction` ownership.
- The scheduler holds movement and suppresses ordinary face-to-target while a reaction is active.
- Enemy-targeted, combat, pull, target-control, movement, engage, disengage, target-switch, and weapon-skill proposals are rejected with `reaction_hold`.
- Party/self support proposals remain eligible, including cures, defensive buffs, songs, and rolls that do not target the enemy.
- UnifiedCombat does not disengage or change targets. Facing away stops melee while preserving combat state.
- When the final lock for the actor clears, scheduler-owned facing is restored toward the still-valid current target.
- Reaction-movement completion, cancellation, invalid actors, and lifecycle resets issue an explicit dispatcher-owned movement stop before releasing ownership.
- Party Follow, formation, and routine combat positioning yield while either reaction movement response owns the lane. `move_to_range` retains ownership even while physically holding inside its target band; normal positioning resumes only after the ability-window lock releases.
- Doom emergency handling remains above reaction handling.

## Runtime Lifecycle

- Locks are keyed by trigger, actor ID, and canonical action/effect name.
- Multiple locks may coexist; facing is restored only after the final lock for the actor clears.
- A new ability-ready event from the same actor supersedes an older incomplete ability-window lock.
- Target changes clear target-scoped enemy-buff locks but do not clear an ability-window lock owned by another actor. Zone changes, job changes, scheduler lock resets, and addon unload clear all runtime reaction state.
- No speculative completion timeout is used. Missing completion evidence remains visible through diagnostics rather than being hidden by a guessed timer.

## Diagnostics

`//uc reactions status` reports:

- enabled state and configured rule count
- active runtime locks
- last transition
- unresolved enemy-buff resource names
