# Local Ownership Flags Audit

## Scope

- Path inspected: `C:\Program Files (x86)\Windower\addons\UnifiedCombat\local_ownership_flags.lua`
- File status: tracked in git, not gitignored, and intended to remain local-only
- Audit date: `2026-06-28`

## How the file is loaded

- `UnifiedCombat.lua` loads the file with `pcall(require, 'local_ownership_flags')`.
- The load happens during addon bootstrap, after `unified_engine.lua` has already required `unified_scheduler.lua`, but before the runtime loop starts using scheduler globals.
- The loader mutates `_G` through the module body.
- Missing-file errors are ignored.
- Other load failures are reported through `windower.add_to_chat(...)`.
- The module is cached by `require`, so the overrides persist until Windower reloads the addon or the file is reloaded by a fresh session.

## Current local flag inventory

| Line | Setting | Current value | Category | Recommended action | Reason |
| --- | --- | --- | --- | --- | --- |
| 4 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Target ownership is promoted default-on; explicit `false` is an active opt-out and can disable expected routing. |
| 5 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Turn ownership is promoted default-on; explicit `false` is an active opt-out. |
| 10 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Maintenance COR command ownership is promoted default-on. |
| 11 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Defensive internal command ownership is promoted default-on. |
| 12 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Internal dispatch command ownership is promoted default-on. |
| 16 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Combat WS command ownership is promoted default-on. |
| 17 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Combat JA command ownership is promoted default-on. |
| 18 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Combat spell command ownership is promoted default-on. |
| 22 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Movement-coordinator cast-freeze stop ownership is promoted default-on. |
| 23 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Movement-coordinator pull cast-hold stop ownership is promoted default-on. |
| 24 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Movement-coordinator pull spell-wait stop ownership is promoted default-on. |
| 58 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Tank action-settle is promoted default-on; explicit `false` can suppress it. |
| 59 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Tank spell-settle is promoted default-on as of `T3.6j`; explicit `false` can suppress it. |
| 60 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` | `false` | `promoted_default_on` | remove/comment out | Tank enmity JA self is promoted default-on as of `T3.6i`; explicit `false` can suppress it. |
| 61 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` | `false` | `still_default_off` | remove/comment out | This seam is still default-off; explicit `false` is redundant and can be removed. |
| 62 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | `false` | `still_default_off` | remove/comment out | This seam is still default-off; explicit `false` is redundant and can be removed. |
| 97 | `_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` | `false` | `deferred_or_parked` | remove/comment out | Vector run is still parked/dormant; explicit `false` is redundant unless you want a local note. |
| 130 | `_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION` | `true` | `unrelated` | keep only if you are intentionally testing movement arbitration | Not part of ownership auditing; unrelated to the tank starvation report. |
| 134 | `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE` | `true` | `unrelated` | keep only if you are intentionally testing alliance scope | Not part of ownership auditing; unrelated to the tank starvation report. |
| 136 | `_G.UC_DEBUG_ACTION_TIMELINE` | `false` | `debug_logging` | remove/comment out | Debug logging should stay off unless you are actively collecting traces. |
| 138 | `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP = true` | `true` | `promoted_default_on` but malformed | remove/comment out | This is a bare global assignment with no `_G.` prefix; it is redundant now that the seam is promoted default-on and should not stay as a stray local override. |
| 140 | `_G.UC_SPELL_LIFECYCLE_PROBE` | `false` | `debug_logging` | remove/comment out | Probe should stay off unless you are actively debugging spell lifecycle behavior. |

## Suspicious or stale settings

- The file contains many explicit `false` overrides for promoted default-on ownership flags.
- The most suspicious lines are the promoted tank/target/turn/command/movement-stop overrides at lines 4-24 and 58-60.
- The bare assignment at line 138 is stale and malformed relative to the rest of the file.
- `UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP` is not present, which is good; a global kill switch should not be a normal local config value.
- No `true` overrides were found for the still-default-off tank enmity spell target/self seams, Doom ownership, or vector ownership.

## Recommended normal config

Normal clean config should be close to empty:

```lua
-- Local-only ownership field-test flags.
-- Leave ownership unset unless you are deliberately bisecting.
```

If you want to keep only diagnostics:

```lua
_G.UC_DEBUG_ACTION_TIMELINE = true
_G.UC_SPELL_LIFECYCLE_PROBE = true
```

## Recommended temporary tank bisect config

Use this only if you are actively bisecting tank behavior after cleaning out stale opt-outs:

```lua
-- Start from a clean file.
-- Do not set any promoted default-on ownership flags to false.
-- Do not set the promoted ownership kill switch.

-- If you need a one-at-a-time experiment, enable exactly one default-off seam.
-- Example:
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP = true
-- or
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP = true
```

## Could the current local flags explain the tank behavior?

Yes, plausibly.

- The file explicitly disables several promoted default-on ownership paths that tank behavior depends on, including target/turn, combat spell command, movement-stop, tank action-settle, tank spell-settle, and tank enmity JA self.
- That can suppress the promoted routing path and leave the scheduler on older fallback behavior.
- The file does **not** directly change Cure runtime logic, so it cannot by itself prove why Cure is being chosen too often; it can, however, explain why tank JAs and spell-settle ownership routes are not behaving as expected.

## Next recommended step

1. Clear the stale explicit `false` overrides for promoted default-on flags.
2. Remove the redundant bare line at 138.
3. Leave default-off seams unset unless you are deliberately testing them one at a time.
4. If the tank starvation persists after that cleanup, bisect with one default-off tank seam enabled at a time.
