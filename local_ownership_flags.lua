-- Local-only ownership field-test flags.
-- Do not commit this file.

_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP = false

-- Stage 2 live-testable isolated command ownership flags.
-- Doom Holy Water intentionally omitted from live field testing.

_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP = false

-- Stage 3: combat command ownership only.

_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP = false

--Stage 5 flags will be the movement-coordinator stop flags:

_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP = false

--[[local function dump_run_stop_status(label, status)
    if type(status) ~= 'table' then
        return
    end

    windower.add_to_chat(207, string.format(
        '[UC Stage5] %s kind=%s source=%s ownership=%s dispatched=%s ok=%s fallback=%s reason=%s',
        label,
        tostring(status.kind),
        tostring(status.source),
        tostring(status.ownership_enabled),
        tostring(status.dispatched),
        tostring(status.dispatch_ok),
        tostring(status.fallback_used),
        tostring(status.reason or status.dispatch_reason)
    ))
end

windower.register_event('prerender', function()
    local now = os.clock()
    if _G.UC_STAGE5_LAST_DUMP and now - _G.UC_STAGE5_LAST_DUMP < 1.0 then
        return
    end
    _G.UC_STAGE5_LAST_DUMP = now

    dump_run_stop_status('CAST_FREEZE_PREP', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE)
    dump_run_stop_status('PULL_CAST_HOLD', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE)
    dump_run_stop_status('PULL_SPELL_WAIT', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE)
end) ]]

--stage 6 flags

_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP = false
_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP = false

--[[local function dump_run_stop_status(label, status)
    if type(status) ~= 'table' then
        return
    end

    windower.add_to_chat(207, string.format(
        '[UC Stage6] %s kind=%s source=%s ownership=%s dispatched=%s ok=%s fallback=%s reason=%s',
        label,
        tostring(status.kind),
        tostring(status.source),
        tostring(status.ownership_enabled),
        tostring(status.dispatched),
        tostring(status.dispatch_ok),
        tostring(status.fallback_used),
        tostring(status.reason or status.dispatch_reason)
    ))
end

windower.register_event('prerender', function()
    local now = os.clock()
    if _G.UC_STAGE6_LAST_DUMP and now - _G.UC_STAGE6_LAST_DUMP < 1.0 then
        return
    end
    _G.UC_STAGE6_LAST_DUMP = now

    dump_run_stop_status('TANK_ACTION_SETTLE', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE)
    dump_run_stop_status('TANK_SPELL_SETTLE', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE)
    dump_run_stop_status('TANK_JA_SELF_SEND', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE)
    dump_run_stop_status('TANK_SPELL_TARGET_SEND', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE)
    dump_run_stop_status('TANK_SPELL_SELF_SEND', _G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE)
end) ]]

-- stage 7 flags
_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP = false
--[[
local dumped_stage7_once = false

windower.register_event('prerender', function()
    if dumped_stage7_once then
        return
    end

    local status = _G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE
    if type(status) ~= 'table' then
        return
    end

    if status.ownership_enabled == true or status.dispatched == true then
        dumped_stage7_once = true
        windower.add_to_chat(207, string.format(
            '[UC Stage7] RUN_VECTOR kind=%s source=%s ownership=%s dispatched=%s ok=%s fallback=%s heading=%s run_x=%s run_y=%s reason=%s',
            tostring(status.kind),
            tostring(status.source),
            tostring(status.ownership_enabled),
            tostring(status.dispatched),
            tostring(status.dispatch_ok),
            tostring(status.fallback_used),
            tostring(status.heading),
            tostring(status.run_x),
            tostring(status.run_y),
            tostring(status.reason or status.dispatch_reason)
        ))
    end
end) ]]

-- T2.8b movement priority arbitration test.
_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = true
-- T3.2b alliance target-scope field test.
_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
_G.UC_DEBUG_ACTION_TIMELINE = true