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

function M.apply_target_ownership(opts)
    opts = require_table(opts, "opts")
    local intent = require_table(opts.intent, "opts.intent")
    local dispatcher = require_table(opts.dispatcher, "opts.dispatcher")
    require_function(dispatcher.dispatch_intent, "opts.dispatcher.dispatch_intent")
    local set_target = require_function(opts.set_target, "opts.set_target")

    local target_id = tonumber(opts.target_id) or 0
    local status = {
        ownership_enabled = true,
        dispatched = false,
        dispatch_ok = false,
        dispatch_reason = "",
        fallback_used = false,
        selected = false,
    }

    status.dispatched = true
    local dispatch_result = dispatcher.dispatch_intent(intent, {
        execute = true,
        set_target = set_target,
    })
    status.dispatch_ok = (type(dispatch_result) == "table" and dispatch_result.ok == true and dispatch_result.executed == true)
    status.dispatch_reason = type(dispatch_result) == "table" and tostring(dispatch_result.reason or "") or "missing_dispatch_result"
    status.selected = (type(dispatch_result) == "table" and dispatch_result.dep_result == true)

    if not status.dispatch_ok and status.dispatch_reason:match("^missing_dep:") then
        error("uc_scheduler_target_ownership dispatcher failed: " .. status.dispatch_reason)
    end

    return status
end

return M
