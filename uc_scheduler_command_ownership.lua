local M = {}
local recovery_hold = require('uc_recovery_hold')

local function require_table(value, name)
    if type(value) ~= "table" then
        error(name .. " must be a table")
    end
    return value
end

local function require_function(value, name)
    if type(value) ~= "function" then
        error(name .. " must be a function")
    end
    return value
end

local function timeline_log(event_code, fields, dedupe_key, interval)
    local fn = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
    if type(fn) == 'function' then
        pcall(fn, event_code, fields, dedupe_key, interval)
    end
end

local function consume_dispatched_reaction_action(intent)
    local meta = type(intent.meta) == 'table' and intent.meta or nil
    if meta == nil or tostring(meta.target_kind or '') ~= 'mob' then
        return nil
    end

    local action_type = tostring(meta.action_type or ''):lower()
    local action_name = tostring(meta.action_name or '')
    local target_id = tonumber(meta.target_id) or 0
    if (action_type ~= 'spell' and action_type ~= 'ja')
        or action_name == ''
        or target_id <= 0 then
        return nil
    end

    local reaction_runtime = require('uc_reaction_runtime')
    local lock = reaction_runtime.get_action_lock()
    if type(lock) ~= 'table'
        or tostring(lock.action_type or ''):lower() ~= action_type
        or tostring(lock.action_name or '') ~= action_name
        or (tonumber(lock.actor_id) or 0) ~= target_id then
        return nil
    end

    local released = reaction_runtime.cancel(lock.key, 'action_dispatched')
    if type(released) ~= 'table' then
        return nil
    end

    timeline_log('REACTION_ACTION_RELEASED', {
        ability = tostring(released.name or ''),
        response = 'use_action',
        action_type = action_type,
        action = action_name,
        actor_id = target_id,
        reason = 'action_dispatched',
    }, ('reaction_action_released:%s:%d'):format(
        tostring(released.name or ''),
        target_id
    ), 0)
    return released
end

function M.apply_command_ownership(opts)
    opts = require_table(opts, "opts")
    local intent = require_table(opts.intent, "opts.intent")
    local dispatcher = require_table(opts.dispatcher, "opts.dispatcher")
    require_function(dispatcher.dispatch_intent, "opts.dispatcher.dispatch_intent")
    local send_command = require_function(opts.send_command, "opts.send_command")

    local command = opts.command
    local command_present = (command ~= nil and tostring(command) ~= "")
    local status = {
        ownership_enabled = true,
        dispatched = false,
        dispatch_ok = false,
        dispatch_reason = "",
        fallback_used = false,
        command_present = command_present,
        reaction_released = false,
        reaction_key = "",
    }

    if not command_present then
        status.dispatch_reason = "missing_command"
        return status
    end

    status.dispatched = true
    local dispatch_result = dispatcher.dispatch_intent(intent, {
        execute = true,
        send_command = send_command,
    })
    status.dispatch_ok = (type(dispatch_result) == "table" and dispatch_result.ok == true and dispatch_result.executed == true)
    status.dispatch_reason = type(dispatch_result) == "table" and tostring(dispatch_result.reason or "") or "missing_dispatch_result"

    if status.dispatch_ok then
        local released = consume_dispatched_reaction_action(intent)
        if type(released) == 'table' then
            status.reaction_released = true
            status.reaction_key = tostring(released.key or '')
        end
    end

    if not status.dispatch_ok and status.dispatch_reason ~= recovery_hold.BLOCK_REASON then
        error("uc_scheduler_command_ownership dispatcher failed: " .. status.dispatch_reason)
    end

    return status
end

return M