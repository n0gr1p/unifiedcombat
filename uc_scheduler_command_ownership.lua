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

    if not status.dispatch_ok then
        error("uc_scheduler_command_ownership dispatcher failed: " .. status.dispatch_reason)
    end

    return status
end

return M
