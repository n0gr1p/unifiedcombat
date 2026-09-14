# Rune Fencer tank automation

Rune Fencer tank automation extends the existing `combat` tank lane; it does not create a new scheduler domain.

## Ownership

- Existing `tank.enmity.actions` owns reactive enemy-target hate recovery such as `Flash`.
- `tank.run` owns Rune Enchantments, proactive `Foil`, enabled RUN wards, and Gambit/Rayke sequencing.
- Generic defensive buff maintenance continues to own ordinary enhancing magic such as Crusade and Phalanx.
- Reactions continue to own encounter-triggered Liement, Elemental Sforzo, and similar emergency actions.
- When RUN automation owns a JA, the generic configured-JA lane filters that JA so only one policy source can propose it.

## Configuration

```lua
tank = {
    enabled = true,
    enmity = {
        actions = { 'Flash' },
    },
    run = {
        enabled = true,
        runes = {
            maintain = true,
            desired = { 'Ignis', 'Ignis', 'Ignis' },
        },
        foil = { enabled = true },
        wards = {
            vallation = true,
            valiance = false,
            pflug = true,
            swordplay = false,
            battuta = true,
            one_for_all = false,
        },
        magic_support = {
            gambit = true,
            rayke = true,
        },
    },
}
```

The desired rune list must be empty or contain exactly three runes. Vallation and Valiance cannot both be enabled.

When `ability_allow_unengaged` is enabled, RUN automation may operate while the player remains disengaged. This is intentional for encounters where melee TP feed is undesirable. Foil may be maintained once a valid enemy target exists even if the RUN is not engaged, and Gambit/Rayke may be used against that valid current enemy without requiring player melee engagement.

## Ordering

The provider emits at most one RUN proposal per scheduler tick. Routine RUN work is priority band 94, immediately below existing tank-enmity recovery at band 96.

The policy order is:

1. converge the configured rune stack;
2. establish Vallation/Valiance and configured wards;
3. maintain Foil once combat has a valid enemy target (or while already engaged);
4. use Gambit, then rebuild consumed runes;
5. use Rayke, then rebuild consumed runes.

Liement suppresses Vallation/Valiance restoration while Liement is active.

## Deliberate v1 exclusions

Lunge and Swipe are not automated. Exact mixed-rune consumption ordering is therefore not part of the v1 contract. Rune convergence is based on observed player buff slots and fails closed if a configured rune status cannot be resolved.

Runtime diagnostics are published at `_G.UC_RUN_TANK_STATUS`.
