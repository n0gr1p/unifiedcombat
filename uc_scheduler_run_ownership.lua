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

function M.apply_run_ownership(opts)
    opts = require_table(opts, "opts")
    local intent = require_table(opts.intent, "opts.intent")
    local dispatcher = require_table(opts.dispatcher, "opts.dispatcher")
    require_function(dispatcher.dispatch_intent, "opts.dispatcher.dispatch_intent")
    local run = require_function(opts.run, "opts.run")
    local heading = tonumber(opts.heading)

    local normalized_run_x = tonumber(intent.run_x) or 0
    local normalized_run_y = tonumber(intent.run_y) or 0
    local status = {
        ownership_enabled = true,
        dispatched = false,
        dispatch_ok = false,
        dispatch_reason = "",
        fallback_used = false,
        run_x = normalized_run_x,
        run_y = normalized_run_y,
        heading = heading,
    }

    status.dispatched = true
    local dispatch_result = dispatcher.dispatch_intent(intent, {
        execute = true,
        run = run,
    })
    status.dispatch_ok = (type(dispatch_result) == "table" and dispatch_result.ok == true and dispatch_result.executed == true)
    status.dispatch_reason = type(dispatch_result) == "table" and tostring(dispatch_result.reason or "") or "missing_dispatch_result"

    if not status.dispatch_ok and status.dispatch_reason ~= recovery_hold.BLOCK_REASON then
        error("uc_scheduler_run_ownership dispatcher failed: " .. status.dispatch_reason)
    end

    return status
end

return M
