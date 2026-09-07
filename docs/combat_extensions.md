# Generic magic burst, action reactions, and auto-engage

This feature branch adds three generic combat controls without encounter-specific Zerde code.

## Architecture

The runtime behavior is integrated through the canonical `uc_provider_combat.lua` and `uc_reaction_runtime.lua` modules. There are no shadow `_base` copies or compatibility wrappers. Small focused helpers own only the new combat-extension configuration reads and priority-offense proposal construction.

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

Magic bursting reuses the existing configured spell and the authoritative skillchain snapshot. Set the desired burst spell in `config.spells.configured` and arm burst use with `magic_burst = true`. The spell is proposed only when its element is valid for the confirmed skillchain and at least six seconds remain in the tracked burst window.

```lua
spells = {
    enabled = false,
    configured = 'Fire V',
    magic_burst = true,
}
```

`spells.enabled` remains independent; magic bursting does not require ordinary configured-spell spam to be enabled. The flat compatibility toggle is `magic_burst_enabled` and uses the existing flat `spell` setting for the spell name.

## Ability-window action reactions

Existing movement/facing reactions are unchanged. A new `use_action` response is accepted for `ability_window` rules. The first implementation intentionally supports spells only and fails closed for other action types.

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

The `use_action` rule becomes a normal authoritative reaction lock. While that lock is active, normal enemy-facing offense remains suppressed, but the matching configured reaction proposal is explicitly allowed through the same reaction gate. The reaction spell is submitted through the normal scheduler proposal path at priority band 240; it does not bypass readiness, recast, target, movement, duplicate-suppression, or action-state ownership.

## Initial burst priority

Magic-burst proposals use priority band 170. This puts an armed, time-limited burst above normal WS continuation while keeping critical defensive actions above it. The six-second minimum remaining window is intentionally conservative for this first implementation and is isolated in `uc_combat_extensions.lua` for future tuning without changing the skillchain state contract.
