# Generic magic burst, action reactions, and auto-engage

This feature set adds generic combat controls without encounter-specific Zerde code.

## Architecture

Runtime behavior remains on the existing combat-provider and reaction-runtime call paths. Reaction sequences are layered through thin compatibility wrappers so the legacy single-action reaction behavior remains unchanged while the sequence state machine stays isolated and reviewable. The durable profile remains the source of truth; sequence progress is runtime-only state.

## Auto-engage

`config.combat.auto_engage` defaults behaviorally to `true`. When false, normal target selection/autotarget remains available but the combat provider does not propose `/attack on`.

```lua
combat = {
    enabled = true,
    autotarget = true,
    auto_engage = false,
}
```

The flat compatibility setting is `auto_engage`.

## Magic burst

Magic bursting reuses the existing configured spell and the authoritative skillchain snapshot. Set the desired burst spell in `config.spells.configured` and arm burst use with `magic_burst = true`.

```lua
spells = {
    enabled = false,
    configured = 'Fire V',
    magic_burst = true,
}
```

`spells.enabled` remains independent; magic bursting does not require ordinary configured-spell spam to be enabled. The flat compatibility toggle is `magic_burst_enabled` and uses the existing flat `spell` setting for the spell name.

General-purpose bursting can instead set `magic_burst_mode = 'auto'` with one of three families: `spell`, `ra`, or `helix`. `magic_burst_max_tier = 0` means Auto/highest available; positive values are a tier ceiling. Auto selection reads the target's confirmed skillchain property and chooses the strongest compatible ready spell in that family. Direct nukes use tiers I-V, GEO `-ra` uses I-III, and Helix uses I-II. Auto Helix never crosses into direct nukes and does not cast a weaker/alternate Helix merely because the preferred Helix is on recast. Legacy profiles default to `magic_burst_mode = 'exact'` and preserve their configured spell behavior.

## Ability-window action reactions

Existing movement/facing reactions are unchanged. `use_action` remains the backward-compatible one-shot spell response for `ability_window` rules.

```lua
reactions = {
    enabled = true,
    rules = {
        {
            trigger = 'ability_window',
            name = 'Just Desserts',
            response = 'use_action',
            action_type = 'spell',
            action_name = 'Stun',
        },
    },
}
```

The `use_action` rule becomes a normal authoritative reaction lock while its response is armed. The exact matching reaction proposal is submitted through the normal scheduler proposal path at priority band 240. It does not bypass readiness, recast, target, movement, duplicate-suppression, or action-state ownership. Once the matching action is successfully dispatched, legacy `use_action` consumes its lock immediately.

### Atomic action sequences

`use_sequence` adds a generic ordered action sequence to an `ability_window` reaction. Each step declares an action type, action name, target, and whether the step is optional.

```lua
reactions = {
    enabled = true,
    rules = {
        {
            trigger = 'ability_window',
            name = 'Just Desserts',
            response = 'use_sequence',
            steps = {
                {
                    action_type = 'ja',
                    action_name = 'Elemental Seal',
                    target = 'self',
                    optional = true,
                },
                {
                    action_type = 'spell',
                    action_name = 'Stun',
                    target = 'actor',
                    optional = false,
                },
            },
        },
    },
}
```

Sequence rules are deliberately generic: supported step action types are `ja`, `spell`, and `pet`; supported targets are `self` and `actor`. Pet steps currently support target-directed `Assault` and `Deploy`, and therefore require `target = 'actor'`. The final step must be required. The runtime does not contain Zerde-, Elemental-Seal-, Stun-, or encounter-specific pet policy.

A Summoner can therefore stage an avatar onto the triggering enemy immediately when its ability window opens:

```lua
{
    trigger = 'ability_window',
    name = 'Just Desserts',
    response = 'use_sequence',
    steps = {
        {
            action_type = 'pet',
            action_name = 'Assault',
            target = 'actor',
            optional = false,
        },
    },
}
```

Pet steps use the existing shared pet-command coordinator instead of sending `/pet` commands through a second path. Dispatch captures the exact pet ID, triggering actor ID, and combat generation. The reaction step remains dispatched until the coordinator observes that pet on the requested actor (or another authoritative Assault/Deploy completion signal). A failed or timed-out pet command returns the step to pending and respects the coordinator's retry backoff while the enemy ability window remains active.

An unavailable optional step is skipped immediately. Therefore a sequence such as optional Elemental Seal followed by required Stun still attempts Stun when Elemental Seal is on recast, unavailable, or otherwise fails readiness. A required step is never skipped; the sequence keeps ownership and retries while the triggering enemy ability window remains active.

Once a sequence activates, it owns the scheduler action lane atomically. All ordinary proposals, including support actions, are rejected while the sequence is active; only the exact current sequence step is admitted. Doom emergency handling remains outside this ordinary proposal gate as before.

Dispatch does not advance or release a sequence. Spell and job-ability steps advance from their matching local action-result packet. Pet steps advance from shared pet-command completion evidence. Completion of the required terminal step releases the sequence. If the triggering enemy ability completes first, or the actor becomes invalid, the active sequence is aborted and its lock is released.

This completion-driven behavior avoids the stale-lock problem that would result from waiting only for the enemy ability completion packet: a successful interrupt can prevent that packet from ever occurring.

Sequence progress (`step_index`, dispatch state, action/pet correlation, and timestamps) is runtime-only. Durable configuration contains only the configured steps.

Movement/facing reactions such as `turn_away`, `stop_attacking`, `run_away`, and `move_to_range` retain their full hazard lifecycle and continue to release when the triggering condition resolves or the actor becomes invalid.

## Initial burst priority

Magic-burst proposals use priority band 170. Reaction actions and reaction-sequence steps use priority band 240. This keeps time-critical reactions above normal WS and burst work while still using the normal scheduler dispatch/readiness/action-state pipeline.
