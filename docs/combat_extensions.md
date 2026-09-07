# Generic magic burst, action reactions, and auto-engage

This feature branch adds three generic combat controls without encounter-specific Zerde code.

## Auto-engage

`config.combat.auto_engage` defaults to `true`. When false, normal target selection/autotarget remains available but the combat provider does not propose `/attack on`.

```lua
combat = {
    enabled = true,
    autotarget = true,
    auto_engage = false,
}
```

## Magic burst

Magic bursting reuses the existing generic configured spell and the authoritative skillchain snapshot. Set the desired burst spell in `config.spells.configured` and arm burst use with `magic_burst = true`. The spell is proposed only when its element is valid for the confirmed skillchain and at least six seconds remain in the tracked burst window.

```lua
spells = {
    enabled = false,
    configured = 'Fire V',
    magic_burst = true,
}
```

`spells.enabled` remains independent; magic bursting does not require ordinary configured-spell spam to be enabled.

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

The reaction action is submitted through the normal scheduler proposal path at priority band 180. It does not bypass readiness, recast, target, movement, duplicate-suppression, or action-state ownership.
