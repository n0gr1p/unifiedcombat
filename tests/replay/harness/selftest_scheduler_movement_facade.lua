local dispatcher = require("uc_scheduler_dispatcher")
local movement_facade = require("uc_scheduler_movement_facade")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function main()
    local run_calls, turn_calls = {}, {}
    local executor = movement_facade.build({
        dispatcher = dispatcher,
        run = function(...)
            run_calls[#run_calls + 1] = { count = select("#", ...), ... }
        end,
        turn = function(heading)
            turn_calls[#turn_calls + 1] = heading
        end,
    })

    executor.run_heading(1.25)
    executor.stop()
    executor.run_forward()
    executor.turn(2.5)
    assert_equal(#run_calls, 3, "movement run call count")
    assert_equal(run_calls[1].count, 1, "heading run arity")
    assert_equal(run_calls[1][1], 1.25, "heading run value")
    assert_equal(run_calls[2].count, 1, "stop run arity")
    assert_equal(run_calls[2][1], false, "stop run value")
    assert_equal(run_calls[3].count, 0, "forward run arity")
    assert_equal(turn_calls[1], 2.5, "turn value")

    local mover_calls = {}
    local mover = {
        move_towards = function(_, target_id)
            mover_calls[#mover_calls + 1] = "towards:" .. tostring(target_id)
        end,
        move_away_from = function(_, target_id)
            mover_calls[#mover_calls + 1] = "away:" .. tostring(target_id)
        end,
    }
    executor.move_towards(mover, 1001)
    executor.move_away_from(mover, 1002)
    assert_equal(mover_calls[1], "towards:1001", "move-towards dispatch")
    assert_equal(mover_calls[2], "away:1002", "move-away dispatch")

    local core = read("unified_combat_core.lua")
    local scheduler = read("unified_scheduler.lua")
    assert(core:find("function core.apply_movement_for_scheduler(settings, movement_executor, config)", 1, true), "core scheduler movement must accept canonical config")
    assert(core:find("apply_movement(s, current, movement_executor, config)", 1, true), "core scheduler movement must use the injected executor and canonical config")
    assert(scheduler:find("require('uc_scheduler_movement_facade').build({", 1, true), "scheduler must build the dispatcher movement facade")
    assert(scheduler:find("combat_core.apply_movement_for_scheduler(s, movement_executor, config)", 1, true), "scheduler movement coordinator must inject its explicit canonical tick config")

    io.stdout:write("selftest_scheduler_movement_facade: OK\n")
end

main()
