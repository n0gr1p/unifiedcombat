# Named Mob and Boss Formations

Profile V2 can store multiple role-free generic formations keyed by an enemy's exact
name. A configured entry activates automatically when all of these conditions are
true on that client:

- the movement domain and automatic named formations are enabled;
- the current target is a valid enemy actor with the configured exact name
  (comparison is case-insensitive);
- the target is alive and engaged;
- the UnifiedCombat engine is running; and
- no higher-priority movement or action lock currently owns movement.

Each client selects its own entry and geometry. Named formations do not assign tank,
DPS, or healer roles and do not enable encounter policies or boss-specific mechanics.
They use the existing generic formation solver and scheduler movement coordinator, so
reaction movement, Doom handling, cast locks, and other higher-priority ownership keep
their existing precedence.

## WinForms setup

1. Select the character and job profile to edit.
2. Open **Encounter Formation** and enable **Automatic named mob / boss formations**.
3. Enable the movement domain if the validation row requests it.
4. Enter the enemy name exactly as it appears in game.
5. Configure the generic geometry fields: radial or polar band, anchor, optional polar
   axis, radius and angle bands, hysteresis, and constraints.
6. Click **Add / Update**. Repeat for other named enemies, then save the profile.
7. Rebuild/restart the UI only when its executable changed, and reload the saved
   Profile V2 in the addon.

To change an existing entry, select it in **Configured named formations**, click
**Load geometry**, edit the fields, and click **Add / Update** again.

At runtime, target and engage the configured enemy. The live target position and
heading drive boss-relative geometry. An `encounter_origin` anchor is transient: it is
captured from that actor's position when the named formation first activates and is
cleared when named-formation ownership ends. No runtime actor ID, origin, or hazard is
written into the profile.

## Durable shape

The WinForms UI writes the following role-free structure under `config.movement`:

```lua
named_formations = {
    enabled = true,
    entries = {
        {
            mob_name = "Kei",
            placement = {
                mode = "polar_band",
                anchor = "boss",
                axis = { type = "boss_heading" },
                preferred_radius = 12,
                minimum_radius = 10,
                maximum_radius = 14,
                preferred_angle_deg = 180,
                allowed_angle_half_width_deg = 45,
                radius_step = 0.5,
                angle_step_deg = 10,
            },
            hysteresis = {
                start_distance = 1,
                stop_distance = 0.5,
            },
            constraints = {
                avoid_encounter_hazards = false,
                hazard_margin = 0,
                minimum_boss_distance = 10,
                maximum_boss_distance = 14,
            },
        },
    },
}
```

Names must be unique within a profile. Empty enabled lists, duplicate names, invalid
geometry, or an enabled named formation without the movement domain fail profile
validation.

`avoid_encounter_hazards` remains durable future-facing configuration. Dhartok
`hazard_candidates` are still telemetry-only and are not supplied to named or Sortie
formation solving until the documented field-validation gate is complete.
