# Scheduler Ownership Field-Test Packet

## Preconditions

- Full replay suite passes.
- Static closure test passes.
- Side-effect inventory passes.
- Promotion plan static guard passes.
- All ownership flags remain default-off before starting.

## Global Rollback Rule

- This rollback rule applies to every field-test stage.
- unset/remove the tested `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP` flag or set it to `false`/`nil`.
- reload the addon if needed.
- rerun the same scenario with the flag off.

## Warnings

- Do not enable all 21 flags at once until every prior stage has passed.
- Do not make any flag default-on during field testing.
- Do not remove fallback paths during field testing.

## Optional Local Flag File

- Create `C:\Program Files (x86)\Windower\addons\UnifiedCombat\local_ownership_flags.lua` only for local manual testing.
- `local_ownership_flags.lua` is optional; if it does not exist, addon behavior is unchanged.
- `UnifiedCombat.lua` loads it through a protected `pcall(require, 'local_ownership_flags')` path after addon-local package-path setup, so scheduler ownership checks can see any `_G.UC_SCHED_P1_ENABLE_DISPATCHER_*_OWNERSHIP` globals it sets.
- Do not commit `local_ownership_flags.lua`.

### Stage 1 Example

```lua
-- Local-only ownership field-test flags.
-- Copy this into local_ownership_flags.lua for manual testing.
-- Do not commit local_ownership_flags.lua.

_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP = true
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP = true
```

## Stage 1 - Target and Turn Ownership

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP`

### Minimum Manual Scenario

- Acquire a new target that requires scheduler target prep.
- Face a target from idle and confirm scheduler turn behavior.

### Expected Visible Behavior

- Correct target is selected once.
- Facing change happens once with no oscillation or duplicate rotation.

### Failure Signs

- Wrong target selected.
- No target selection.
- Repeated target selection attempts.
- Oscillation, stutter-turning, or duplicate turn behavior.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same target/turn scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Target used and whether selection succeeded.
- Visible turn result.
- Any duplicate or missing action symptom.

## Stage 2 - Isolated Command Ownership Paths

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP`

### Minimum Manual Scenario

- Trigger Doom Holy Water handling once.
- Trigger one maintenance COR self action.
- Trigger one safe internal defensive dispatch action.
- Trigger one `defensive_internal` branch action.

### Expected Visible Behavior

- Each command path fires once.
- Doom preserves stop/cooldown ordering before item use.
- No duplicate internal or defensive sends.

### Failure Signs

- Duplicate command execution.
- Missing command execution.
- Doom item path firing without expected ordering.
- Wrong internal or defensive command.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same command scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Command family exercised.
- Whether exactly one visible command effect occurred.
- Any duplicate, missing, or misordered action symptom.

## Stage 3 - Combat Command Families

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP`

### Minimum Manual Scenario

- Perform one WS-ready combat send.
- Perform one combat JA target send and one combat JA self send.
- Perform one combat spell target send and one combat spell self send.

### Expected Visible Behavior

- Each combat command fires once.
- Existing TP, readiness, target, settle, and prep gating remains unchanged.
- No duplicate WS, JA, or spell sends.

### Failure Signs

- Duplicate combat command execution.
- Missing combat command execution.
- Command fires despite normal gating not being satisfied.
- Target/self branch mismatch.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same combat command scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Action type exercised: WS, JA target, JA self, spell target, spell self.
- Whether combat gating looked unchanged.
- Any duplicate, missing, or mistimed send symptom.

## Stage 4 - Isolated Run-Stop Paths

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP`

### Minimum Manual Scenario

- Trigger Doom handling that requires the emergency stop before Holy Water behavior.

### Expected Visible Behavior

- One stop occurs before the item path.
- Doom handling order remains unchanged.

### Failure Signs

- No stop.
- Duplicate stop.
- Stop occurs after item behavior or with obvious ordering drift.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same Doom stop scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Whether the stop happened exactly once.
- Whether stop-before-item ordering was preserved.

## Stage 5 - Movement-Coordinator Run-Stop Paths

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP`

### Minimum Manual Scenario

- Exercise cast-freeze prep.
- Exercise pull cast-hold flow.
- Exercise pull spell-wait flow.

### Expected Visible Behavior

- Each movement stop happens once at the expected timing.
- Movement freeze/hold/wait behavior remains unchanged.

### Failure Signs

- No stop.
- Duplicate stop.
- Movement release or freeze timing visibly changes.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same movement-coordinator scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Movement scenario exercised.
- Whether stop timing looked unchanged.
- Any duplicate, missing, or mistimed stop symptom.

## Stage 6 - Tank and Combat-Spell Run-Stop Paths

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP`
- `UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP`

### Minimum Manual Scenario

- Exercise generic combat spell settle and prep-wait flows.
- Exercise tank action settle.
- Exercise tank-enmity JA self send-adjacent stop.
- Exercise tank spell settle.
- Exercise tank-enmity spell target and self send-adjacent stops.

### Expected Visible Behavior

- Each stop occurs once.
- Adjacent send ordering remains unchanged.
- Tank and combat-spell timing remains unchanged.

### Failure Signs

- No stop.
- Duplicate stop.
- Send happens before the visible stop when it should be adjacent.
- Tank or combat-spell timing visibly drifts.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same tank/combat-spell stop scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Specific stop branch exercised.
- Whether stop and adjacent send order looked unchanged.
- Any duplicate, missing, or mistimed stop symptom.

## Stage 7 - Vector Run Ownership

### Flags to Enable

- `UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP`

### Minimum Manual Scenario

- No confirmed live field scenario is available in the current scheduler runtime flow.
- Enable the flag only for audit confirmation while observing whether `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` ever fires.

### Expected Visible Behavior

- Current live hunter/pathing/combat movement may still occur, but it is not expected to prove scheduler vector ownership reachability.
- If `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` does not fire, treat Stage 7 as deferred/not live-reachable rather than failed.

### Failure Signs

- Ownership-specific failure is only confirmed if `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` fires and shows bad ownership status.
- Yoyo or movement-priority conflicts without `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` should be recorded as baseline scheduler movement behavior, not as proven vector ownership failure.

### Rollback Instruction

- Unset/remove the tested flag or set it to `false`/`nil`, reload if needed, then rerun the same vector-run scenario with the flag off.

### Evidence to Capture

- Enabled flag names.
- Whether `_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE` fired at all.
- Movement scenario exercised.
- Any yoyo, duplicate, missing, or drift symptom.
- Whether the same behavior reproduces with vector ownership disabled.

## Final Notes

- Record evidence for every stage before enabling the next stage.
- Keep field testing manual and default-off throughout the entire packet.
