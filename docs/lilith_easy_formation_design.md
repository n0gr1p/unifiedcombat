# Maiden of the Dusk (Easy) Formation Automation

## Scope

This design covers the High-Tier Battlefield version of **Maiden of the Dusk** on **Easy** difficulty.

The objective is to keep Lady Lilith near the middle of the arena while reducing exposure to her conal attacks and preserving cure and buff coverage. This work does not add Normal-difficulty Gyve, Warden, Doom-aura, or Lilith Ascendant orchestration.

## Encounter observations

- Lady Lilith initially stands at the arena center.
- She remains there until a player passes inside the outer Gyve ring and triggers engagement.
- Her stationary pre-engagement coordinates are therefore the authoritative arena center.
- The center must be captured before she begins moving. Formation automation must not guess a center after engagement.
- The outer Gyve ring bounds the usable arena. Formation positions must stay inside a configured safe radius from center.

## Formation model

### Tank

The tank uses a hard arena-relative tether to the captured center.

- Movement begins only after the tank exceeds the configured return radius.
- Movement stops after the tank enters the smaller accept radius.
- The two radii provide hysteresis and prevent center-point oscillation.
- Knockback recovery returns the tank to center.

### DPS

DPS uses an arena-center-anchored flank whose direction follows the live boss-to-tank axis.

- The desired direction is calculated from the Lady-Lilith-to-tank vector.
- The vector is rotated by the configured flank angle, initially 90 degrees toward Lilith's right flank.
- The rotated melee offset is projected from the captured arena center, not from Lilith's current position.
- Knockback cannot make an unsafe outer-ring position acceptable merely because Lilith followed the displaced party.
- A broad position tolerance lets melee continue fighting without unnecessary correction.

### Healer

The healer remains stationary while the current position satisfies all constraints.

Hard safety constraints:

- Stay inside the configured safe arena radius.
- Stay at least the configured minimum distance from Lady Lilith.
- Stay outside the configured cone around the tank direction.
- Stay outside the configured cone around the expected DPS flank direction.
- Stay outside the cone around Lady Lilith's current target when that target can be resolved.

Coverage constraints:

- Stay within the configured party coverage range of every required, visible party member.
- When `required_party_names` is empty, every visible party member is required.
- A configured required member that cannot be resolved is an explicit error.

When the current position is invalid, the solver selects the nearest valid sampled point. If no valid point exists, it reports an unsatisfied state and emits no guessed movement.

## Arena-center capture

The Lilith encounter runtime observes the exact actor name `Lady Lilith`.

Capture requirements:

- The actor is alive.
- The actor has valid world coordinates.
- The actor is idle (`status == 0`).
- Its coordinates remain within the capture tolerance for the configured stable interval.

After capture, the center is immutable for the attempt. If Lilith enters combat before capture completes, the encounter enters an explicit `CENTER_CAPTURE_MISSED` error state.

Encounter state resets on zone change, job change, unload, or logout. Runtime center coordinates are never written to a profile.

## Scheduler ownership

The formation runtime only proposes movement. The existing scheduler movement coordinator owns validation and dispatch.

Priority order:

1. Doom emergency handling
2. Reaction holds such as `Fatal Allure -> turn_away`
3. Casting and action movement locks
4. Formation correction
5. Existing combat spacing and target-close movement
6. Follow/path behavior outside the scheduler coordinator

Formation dispatch uses scheduler `run` and `run_stop` intents. Dispatch validation failures are surfaced through diagnostics; no direct movement fallback is used.

The movement domain and scheduler movement dispatch must both be enabled. Runtime state can be inspected with `//uc formation status`.

Required ownership configuration:

```lua
ownership = {
    domain_movement_enabled = true,
}
```

## Durable configuration

Formation configuration belongs under `config.movement.formation`:

```lua
formation = {
    enabled = true,
    encounter = "lilith_easy",
    role = "tank", -- tank, dps, healer, disabled
    tank_name = "TankName",
    required_party_names = {},
    capture_stable_s = 0.50,
    capture_tolerance = 0.10,
    safe_radius = 16.0,
    tank = {
        accept_radius = 1.5,
        return_radius = 3.0,
    },
    dps = {
        flank_angle_deg = 90.0,
        melee_radius = 3.0,
        position_tolerance = 1.5,
    },
    healer = {
        preferred_radius = 12.0,
        minimum_boss_distance = 8.0,
        maximum_party_range = 18.0,
        cone_half_angle_deg = 50.0,
        cone_safety_margin_deg = 15.0,
        sample_step_deg = 10.0,
    },
}
```

The initial numeric values are test defaults, not claims about exact encounter geometry. Live testing must establish the final safe radius and cone margin.

The WinForms profile editor exposes these settings on the **Encounter Formation** tab. Formation edits are profile-scoped and remain local until **Save (XML)** writes the UI profile and structured Profile V2 file. Enabling a formation requires a non-disabled role, a tank character name, and scheduler movement ownership; the UI blocks an invalid save and offers an explicit **Enable required movement ownership** action. Disabled formation configuration is omitted from the structured profile for compatibility with older Profile V2 files.

## Existing safety reactions

The formation feature is intended to run with existing reaction rules:

```lua
reactions = {
    enabled = true,
    rules = {
        {
            trigger = "ability_window",
            name = "Fatal Allure",
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

Enemy-buff removal must be enabled on a capable support profile if automatic removal of Dread Spikes is desired. Dread Spikes observation is shared by the reaction and removal paths. The `stop_attacking` response disengages melee without suspending formation correction, and it permits the dedicated Magic Finale or Dispel proposal. Formation ownership suppresses party-follow and path-return movement while the character is disengaged. Because removal spells can remove a different enhancement, removal retries after the attempt gate until effect 173 itself is confirmed removed. Only that confirmation releases the melee hold; `turn_away` reactions such as Fatal Allure continue to suspend formation movement and own facing.

## Acceptance checklist

- [ ] Every participating client captures the same stationary center.
- [ ] Capture never occurs after Lady Lilith begins moving.
- [ ] The tank returns to center after knockback without oscillation.
- [ ] DPS corrects toward the configured flank without continuous movement.
- [ ] The healer remains still while all safety and range constraints are satisfied.
- [ ] The healer selects the nearest valid sampled point after a constraint violation.
- [ ] Missing required party members and unsatisfiable geometry are visible errors.
- [ ] Fatal Allure reaction holds override formation movement and facing.
- [ ] Dread Spikes disengages melee while tank and DPS formation correction remains active.
- [ ] Dread Spikes permits Magic Finale or Dispel and retries when another enhancement is removed.
- [ ] Confirmed removal of effect 173 releases the melee hold and permits re-engagement.
- [ ] Casting locks override formation movement.
- [ ] Formation movement prevents the existing combat movement path from competing on the same tick.
- [ ] Disabling formation preserves existing behavior.
- [ ] Zone, job, unload, and logout lifecycle events clear runtime encounter state.
