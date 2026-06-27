# Scheduler Ownership Promotion Plan

## Current Closure State

- `unified_scheduler.lua` has zero direct textual scheduler side-effect call expressions for `windower.send_command(`, `windower.ffxi.run(`, `windower.ffxi.turn(`, and `uc_settarget.select_by_id(`.
- 11 low-risk, field-tested scheduler ownership paths are now accepted as default-on after T3.0b field testing.
- Promoted paths can still be rolled back temporarily through `_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP == true` or disabled individually by setting their flag to `false`.
- Deferred/default-off paths still require explicit `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP == true` checks.
- This T3.0c update is documentation-only and does not change runtime behavior.

## Ownership Families

- Command ownership
- Target ownership
- Turn ownership
- Run-stop ownership
- Vector run ownership

## Flag Inventory

### Command Ownership

| Flag | Family | Routed Behavior | Existing Fallback Behavior | Recommended Smoke-Test Scenario | Rollback |
| --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP` | Command ownership | Shared internal defensive dispatch command send routes through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct internal dispatch send. | Trigger a safe internal defensive action while idle and confirm a single command send. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP` | Command ownership | `defensive_internal` command path routes through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct defensive send. | Exercise a defensive-internal branch and confirm no duplicate command. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP` | Command ownership | Doom Holy Water item command routes through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct Holy Water command send. | Simulate Doom handling and confirm the item command fires once with preserved stop/cooldown ordering. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP` | Command ownership | Maintenance COR self-JA command routes through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct maintenance command send. | Run a maintenance COR self-action and confirm one JA command. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP` | Command ownership | Combat WS command send routes through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct WS command send. | Perform a WS-ready combat send and confirm exactly one WS command with normal gating. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP` | Command ownership | Combat JA target/self command sends route through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct JA target/self command send. | Test one JA target send and one JA self send under normal combat readiness. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP` | Command ownership | Combat spell target/self command sends route through `uc_scheduler_command_ownership`. | Dispatcher failure falls back to one direct spell target/self command send. | Test one spell target send and one spell self send with normal settle/prep ordering. | Unset/remove the flag or set it to `false`/`nil`. |

### Target Ownership

| Flag | Family | Routed Behavior | Existing Fallback Behavior | Recommended Smoke-Test Scenario | Rollback |
| --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP` | Target ownership | Scheduler target prep routes through `uc_scheduler_target_ownership` and preserves boolean select result semantics. | Dispatcher failure falls back to one direct target select by id. | Acquire a new target and confirm correct selection plus unchanged scheduler gating. | Unset/remove the flag or set it to `false`/`nil`. |

### Turn Ownership

| Flag | Family | Routed Behavior | Existing Fallback Behavior | Recommended Smoke-Test Scenario | Rollback |
| --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP` | Turn ownership | Face-to-target turn routes through `uc_scheduler_turn_ownership`. | Dispatcher failure falls back to one direct turn call. | Face a target from idle and confirm a single turn with no oscillation or duplicate rotation. | Unset/remove the flag or set it to `false`/`nil`. |

### Run-Stop Ownership

| Flag | Family | Routed Behavior | Existing Fallback Behavior | Recommended Smoke-Test Scenario | Rollback |
| --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP` | Run-stop ownership | Doom emergency stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Trigger Doom handling and confirm one emergency stop before Holy Water path. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP` | Run-stop ownership | Movement coordinator cast-freeze prep stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise cast-freeze prep and confirm movement freeze happens once. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP` | Run-stop ownership | Movement coordinator pull-cast-hold stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise pull cast-hold flow and confirm movement stop/hold parity. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP` | Run-stop ownership | Movement coordinator pull-spell-wait stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise pull spell wait and confirm movement stop occurs once. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | Run-stop ownership | Generic combat spell-settle stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise spell-settle blocking and confirm stop/return timing parity. | Unset/remove the flag or set it to `false`/`nil`. Shared promoted kill switch still disables the path, and explicit `false` remains the local rollback. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` | Run-stop ownership | Generic combat spell prep-wait stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise spell prep-wait blocking and confirm one stop plus unchanged prep timing. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP` | Run-stop ownership | Tank action settle stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise tank action settle and confirm one stop before JA/spell dispatch. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP` | Run-stop ownership | Tank-enmity JA self send-adjacent stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise tank-enmity JA self send and confirm one adjacent stop before send. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP` | Run-stop ownership | Tank spell settle stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise tank spell settle and confirm stop/wait parity. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP` | Run-stop ownership | Tank-enmity spell target send-adjacent stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise tank-enmity spell target send and confirm one adjacent stop before send. | Unset/remove the flag or set it to `false`/`nil`. |
| `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP` | Run-stop ownership | Tank-enmity spell self send-adjacent stop routes through `uc_scheduler_run_stop_ownership`. | Dispatcher failure falls back to one direct `run(false)`. | Exercise tank-enmity spell self send and confirm one adjacent stop before send. | Unset/remove the flag or set it to `false`/`nil`. |

### Vector Run Ownership

| Flag | Family | Routed Behavior | Existing Fallback Behavior | Recommended Smoke-Test Scenario | Rollback |
| --- | --- | --- | --- | --- | --- |
| `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP` | Vector run ownership | Final vector run path routes through `uc_scheduler_run_ownership` using a heading-preserving dispatcher adapter. | Dispatcher failure falls back to one direct heading run call. | Deferred for current live field testing: audit whether `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` fires at all, because the scheduler helper path is currently not confirmed reachable from live runtime flow. | Unset/remove the flag or set it to `false`/`nil`. |

## Suggested Staged Promotion Order

1. Target/turn
2. Command isolated paths
3. Command combat families
4. Run-stop isolated paths
5. Run-stop movement/tank paths
6. Vector run last

This staged plan began as default-off only, but T3.0b has now promoted the approved 11-path set to default-on.

## Field Smoke-Test Checklist

- Idle/no action: confirm no unexpected side effects with flags unset, then with one test flag manually enabled.
- Target acquire: confirm target prep still selects the correct target and preserves boolean success/failure behavior.
- Face target: confirm scheduler turns once toward target without oscillation or duplicate turn.
- WS send: confirm one WS command under normal TP/readiness gating.
- JA target/self send: confirm one JA target send and one JA self send with unchanged combat gating.
- Spell target/self send: confirm one spell target send and one spell self send with unchanged settle/prep logic.
- Doom Holy Water: confirm stop-before-item ordering and one Holy Water command.
- Movement freeze/pull stops: confirm cast-freeze and pull-related stops still happen once at the expected timing.
- Tank settle/send-adjacent stops: confirm tank settle and send-adjacent stop branches preserve one-stop behavior and send ordering.
- Vector run movement: currently deferred in live field testing unless `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` can first be shown to fire from a real runtime path.

Record each manual smoke result before enabling the next family.

## Promotion Gates

A flag may only be promoted for field testing when all of the following are true:

- Full replay suite passes.
- Static closure test passes.
- Side-effect inventory passes.
- Before promotion, the flag is enabled manually and remains default-off in code.
- The manual smoke-test result is recorded.
- The rollback path is clear: unset/remove the flag or set it to `false`/`nil`.

## T3.0a Readiness Summary

The readiness audit in `docs/scheduler_ownership_promotion_readiness_audit.md` recommends splitting promotion into three buckets:

- **Promote default-on first**
  - target
  - turn
  - isolated internal/maintenance command paths
  - combat command families
  - Stage 5 movement-coordinator run-stop trio
- **Keep default-off for now**
  - Doom command / Doom run_stop
  - generic combat-spell run-stop paths
  - all partially or unconfirmed tank run-stop paths
- **Retire or park as unreachable**
  - vector run ownership, unless live runtime wiring is intentionally restored later

## Recommended Staged Promotion Update

### T3.0b

Promote low-risk, field-tested scheduler ownership flags to default-on while retaining a temporary kill switch for rollback:

- `UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP`

### T3.0c

Keep these behind manual kill-switch flags:

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`

### T3.0d

Do not promote:

- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP`

Treat it as unreachable/dormant until a future explicit runtime reconnection decision is made.

### T3.0e

After promotion:

- rerun closure/static/replay validation,
- confirm rollback/kill-switch behavior still exists,
- and update the tracker to distinguish promoted vs permanently default-off vs retired ownership flags.

## T3.0b Applied Promotion

Promoted default-on paths now behave as scheduler ownership enabled when their flag is unset, while preserving:

- a global temporary kill switch
- and a per-flag explicit opt-out

### Temporary Kill Switch

Use:

```lua
_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP = true
```

When that global is literally `true`, all promoted ownership paths fall back to legacy/direct behavior.

### Per-Flag Opt-Out

For any promoted flag, setting the flag to `false` in `local_ownership_flags.lua` disables the promoted behavior for that path only.

Example:

```lua
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP = false
```

### Promoted Default-On List

- `UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP`

### Keep Default-Off List

These still require explicit `== true`:

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`

### Not Promoted

- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP`

Vector run ownership remains dormant/unreachable and still requires explicit `== true` if used for future audit/debug work.

## T3.0c Field-Test Closure

T3.0b field testing is now closed as PASS:

- the 11 promoted paths were exercised as default-on,
- the global kill switch was not required,
- no per-flag `false` opt-out was required,
- and no observable regression was reported during the promotion field-test window.

These promoted paths are now accepted as the near-term default-on scheduler ownership set.

## Remaining Default-Off Policy

### Doom Holy Water command ownership

- Status: keep default-off.
- Policy: keep indefinitely default-off due to unsafe/impractical live test.
- Rationale: emergency item usage remains high-risk and did not receive a safe practical field scenario.

### Doom run_stop ownership

- Status: keep default-off.
- Policy: keep indefinitely default-off due to unsafe/impractical live test.
- Rationale: emergency stop-before-item behavior is safety-critical and still lacks safe practical live confirmation.

### Combat spell settle/prep-wait run_stop ownership

- Status: keep default-off.
- Policy: create replay/mock coverage before promotion.
- Rationale: likely reachable, but practical live confirmation remains incomplete and the remaining risk is timing/order parity rather than ownership reachability.

### Tank action/tank spell/tank enmity run_stop ownership

- Status: keep default-off.
- Policy: create targeted field-test packet.
- Rationale: Stage 6 remained partial, `TANK_ACTION_SETTLE` is live but the full family was not practically covered, and promotion should be based on explicit tank-path evidence rather than partial inference.

### Vector run ownership

- Status: dormant/unreachable.
- Policy: retire/unwire because not live-reachable, or leave documented as dormant until an explicit runtime reconnection decision is made.
- Rationale: current scheduler runtime flow does not prove the vector ownership path executes in live play, so promotion remains out of scope.

## Near-Term Ownership Policy

- Keep the temporary global kill switch while the promoted default-on set continues through normal regression windows.
- Keep per-flag `false` opt-outs available for promoted paths during that same period.
- Treat the remaining default-off set as intentionally deferred rather than silently pending promotion.
- Do not promote vector run ownership without an explicit reachability/reconnection decision first.

## T3.1a Coverage Plan

The remaining default-off branches are now governed by `docs/scheduler_remaining_run_stop_coverage_plan.md`.

Near-term policy from that plan:

- Doom Holy Water command and Doom run_stop move to replay/mock-first coverage rather than live-testing-first.
- Combat spell settle/prep-wait run_stop move to replay/mock-first coverage before any new promotion decision.
- Tank action/tank spell/tank enmity run_stop paths move to a narrower targeted field-test packet, with replay/mock fallback if realistic live scenarios are unavailable.
- Vector run stays parked as dormant/unreachable and is not part of run_stop promotion planning.

## T3.1b Coverage Summary

T3.1b adds focused static+mock coverage for:

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`

This task does **not** promote any additional ownership flags.

Post-T3.1b policy remains:

- promoted default-on set stays unchanged,
- these four paths remain explicit default-off `== true` branches,
- and future promotion consideration must come from a separate follow-up task rather than from coverage alone.

## T3.1c Combat-Spell Run-Stop Promotion Policy

Decision:

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP` is now promoted default-on with explicit false opt-out and shared kill-switch rollback.
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP` is not promoted yet.

Reason:

- T3.1b gives strong static+mock confidence for routing, fallback preservation, and default-off gating.
- Live reachability still looks likely, but live branch timing has not been directly confirmed in field results.
- Promotion should therefore wait for a targeted field-test packet rather than relying on replay/mock evidence alone.

Recommended next step:

- yes, a `T3.1d` combat-spell field-test packet is recommended
- scope it only to the settle/prep-wait run_stop pair
- keep Doom command/run_stop outside that packet and default-off

Current policy:

- Doom Holy Water command ownership remains default-off
- Doom run_stop ownership remains default-off
- combat-spell settle/prep-wait run_stop ownership remain default-off pending targeted live confirmation

## T3.1d Packet Status

- `docs/scheduler_combat_spell_run_stop_field_test_packet.md` now exists
- it is the recommended live-test vehicle for the settle/prep-wait pair
- no promotion occurred in T3.1d

## T3.1e Tank-Spell Movement-Lock Note

- T3.1e fixes a scheduler runtime bug in the tank-spell path where movement could resume after the existing pre-send `run_stop` but before the spell cast window had safely cleared.
- The fix is scheduler-local movement-lock bookkeeping after tank spell send; it does not promote any tank run-stop ownership flag and does not change default-off/default-on ownership policy.
- Promotion policy for the tank run-stop family remains unchanged after this bugfix.

## T3.1f Defensive Cure Movement-Lock Note

- T3.1f fixes a separate scheduler runtime bug in the defensive Cure/spell path where Cure could be sent while approach movement continued because no spell-cast stop/lock lifecycle existed.
- The fix uses the existing scheduler-safe run-stop seam plus scheduler-local bounded spell wait bookkeeping.
- No ownership promotion policy changed.
- No promoted/default-off flag set changed.

## Field-Test Instructions After Promotion

- Start with no per-flag opt-outs and no kill switch set.
- Re-run the previously passing Stage 1 / Stage 2 / Stage 3 / Stage 5 practical scenarios.
- If any promoted path regresses, first set:

```lua
_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP = true
```

- If the issue is isolated to one promoted path, clear the global kill switch and set only that path’s flag to `false` in `local_ownership_flags.lua`.
