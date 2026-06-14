local M = {}

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

local function effective_ownership_enabled(opts)
    local explicit_enabled = (opts.ownership_enabled == true)
    local promoted_default_on = (opts.promoted_default_on == true)
    local ownership_disabled = (opts.ownership_disabled == true)
    local promoted_kill_switch = (opts.promoted_kill_switch == true)

    if explicit_enabled then
        return not promoted_kill_switch
    end
    if not promoted_default_on then
        return false
    end
    if ownership_disabled then
        return false
    end
    if promoted_kill_switch then
        return false
    end
    return true
end

function M.apply_command_ownership(opts)
    opts = require_table(opts, "opts")
    local intent = require_table(opts.intent, "opts.intent")
    local direct_send_command = require_function(opts.direct_send_command, "opts.direct_send_command")
    local dispatcher = require_table(opts.dispatcher, "opts.dispatcher")
    require_function(dispatcher.dispatch_intent, "opts.dispatcher.dispatch_intent")
    local send_command = require_function(opts.send_command, "opts.send_command")

    local command = opts.command
    local ownership_enabled = effective_ownership_enabled(opts)
    local command_present = (command ~= nil and tostring(command) ~= "")
    local status = {
        ownership_enabled = ownership_enabled,
        dispatched = false,
        dispatch_ok = false,
        dispatch_reason = "",
        fallback_used = false,
        command_present = command_present,
    }

    if not command_present then
        status.dispatch_reason = "missing_command"
        return status
    end

    if not ownership_enabled then
        direct_send_command(command)
        return status
    end

    status.dispatched = true
    local dispatch_result = dispatcher.dispatch_intent(intent, {
        execute = true,
        send_command = send_command,
    })
    status.dispatch_ok = (type(dispatch_result) == "table" and dispatch_result.ok == true and dispatch_result.executed == true)
    status.dispatch_reason = type(dispatch_result) == "table" and tostring(dispatch_result.reason or "") or "missing_dispatch_result"

    if not status.dispatch_ok then
        status.fallback_used = true
        direct_send_command(command)
    end

    return status
end

return M
