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

local function require_executed(result, operation)
    if type(result) ~= "table" or result.ok ~= true or result.executed ~= true then
        local reason = type(result) == "table" and result.reason or "missing_dispatch_result"
        error("uc_scheduler_movement_facade " .. operation .. " failed: " .. tostring(reason))
    end
end

function M.build(opts)
    opts = require_table(opts, "opts")
    local dispatcher = require_table(opts.dispatcher, "opts.dispatcher")
    require_function(dispatcher.dispatch_intent, "opts.dispatcher.dispatch_intent")
    local run = require_function(opts.run, "opts.run")
    local turn = require_function(opts.turn, "opts.turn")

    return {
        stop = function()
            require_executed(dispatcher.dispatch_intent({
                kind = "run_stop",
                source = "scheduler_movement_facade:stop",
            }, {
                execute = true,
                run = run,
            }), "stop")
        end,
        run_heading = function(heading)
            local numeric_heading = tonumber(heading)
            if numeric_heading == nil then
                error("uc_scheduler_movement_facade heading must be numeric")
            end
            require_executed(dispatcher.dispatch_intent({
                kind = "run",
                source = "scheduler_movement_facade:run_heading",
                run_x = math.cos(numeric_heading),
                run_y = math.sin(numeric_heading),
                meta = { heading = numeric_heading },
            }, {
                execute = true,
                run = function()
                    run(numeric_heading)
                end,
            }), "run_heading")
        end,
        run_forward = function()
            require_executed(dispatcher.dispatch_intent({
                kind = "run_forward",
                source = "scheduler_movement_facade:run_forward",
            }, {
                execute = true,
                run_forward = function()
                    run()
                end,
            }), "run_forward")
        end,
        turn = function(heading)
            require_executed(dispatcher.dispatch_intent({
                kind = "turn",
                source = "scheduler_movement_facade:turn",
                heading = heading,
            }, {
                execute = true,
                turn = turn,
            }), "turn")
        end,
        move_towards = function(mover, target_id)
            require_table(mover, "mover")
            require_function(mover.move_towards, "mover.move_towards")
            require_executed(dispatcher.dispatch_intent({
                kind = "move_towards",
                source = "scheduler_movement_facade:move_towards",
                target_id = target_id,
            }, {
                execute = true,
                move_towards = function(id)
                    mover:move_towards(id)
                end,
            }), "move_towards")
        end,
        move_away_from = function(mover, target_id)
            require_table(mover, "mover")
            require_function(mover.move_away_from, "mover.move_away_from")
            require_executed(dispatcher.dispatch_intent({
                kind = "move_away_from",
                source = "scheduler_movement_facade:move_away_from",
                target_id = target_id,
            }, {
                execute = true,
                move_away_from = function(id)
                    mover:move_away_from(id)
                end,
            }), "move_away_from")
        end,
    }
end

return M
