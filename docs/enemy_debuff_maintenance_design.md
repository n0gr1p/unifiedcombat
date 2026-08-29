# Enemy Debuff Maintenance V1

## Completed scope

Enemy debuff maintenance is a defensive scheduler provider for backline characters.
It does not require the character to be engaged or to have a current target.

The provider:

- reads an ordered spell list from `config.defensive.enemy_debuffs.list`;
- considers every alive, valid, party/alliance-claimed hostile mob in casting range;
- proposes the first configured debuff whose desired state is not satisfied;
- prefers the local current target when it is eligible, then nearest distance, then
  lowest target ID;
- otherwise selects party-claimed mobs without requiring a local target;
- records attempts per spell, target ID, and effect ID;
- uses the existing defensive spell dispatcher and movement/cast locks;
- runs below Cure/status-removal band 100 and above ordinary offensive band 70.

## State evidence

`uc_tb_effect_table.lua` supplies successful spell action identity, effect identity,
and known duration to the scheduler enemy-effect state. State is keyed by stable
target ID and effect ID.

A newly claimed mob with no matching observed effect is unsatisfied. Successful
effect evidence suppresses further casts until packet removal, known expiration,
death, invalidation, or zone cleanup removes that evidence.

For spell tiers sharing an effect ID:

- the exact configured spell satisfies maintenance;
- an observed spell whose resource overwrite list contains the configured spell
  satisfies maintenance as a stronger tier;
- a weaker observed spell remains eligible for replacement;
- an observed effect without exact spell identity blocks replacement because its
  relative strength is unknown.

The configuration fails fast when a spell is unknown, is not enemy-targeted, has
no status/action ID, duplicates another configured effect family, or conflicts
through explicit spell overwrite metadata. There is no inferred compatibility
or alternate-spell fallback.

## Durable configuration

Structured profile v2:

```lua
defensive = {
    enemy_debuffs = {
        enabled = true,
        list = 'Dia III|Distract III|Frazzle III',
    },
}
```

Flat UI/runtime compatibility keys:

- `def_maintain_enemy_debuffs`
- `defensive_enemy_debuffs`

The WinForms Defensive section exposes a `Maintain enemy debuffs` toggle and a
`Maintained Enemy Debuffs` ordered text field.

## Explicit V1 limits

- No speculative refresh lead time; known expiration is authoritative.
- No cross-host target-intent synchronization. Current target is only a preference,
  never an eligibility requirement.
- No movement toward an out-of-range mob. Only party-claimed mobs already within
  the scheduler's 20.9-yalm casting window are eligible.
- Spell effects must be represented in Windower resources and the TargetBar spell
  catalog to obtain exact landed-action evidence.
