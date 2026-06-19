local scheduler_path = "unified_scheduler.lua"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text present: " .. needle))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local function count_plain(text, needle)
    local count = 0
    local index = 1
    while true do
        local found = text:find(needle, index, true)
        if not found then
            return count
        end
        count = count + 1
        index = found + #needle
    end
end

local function main()
    local source = read_file(scheduler_path)

    assert_contains(source, "defensive_spell_waiting = false,", "scheduler must define defensive spell wait flag")
    assert_contains(source, "defensive_spell_wait_until = 0,", "scheduler must define defensive spell wait timeout")
    assert_contains(source, "defensive_pending_action = '',", "scheduler must define defensive pending action")
    assert_contains(source, "defensive_pending_target_id = 0,", "scheduler must define defensive pending target id")
    assert_contains(source, "defensive_pending_sent_at = 0,", "scheduler must define defensive pending sent timestamp")

    assert_contains(source, "function scheduler.clear_defensive_spell_wait_state()", "scheduler must define defensive spell wait clear helper")
    assert_contains(source, "function scheduler.begin_defensive_spell_wait(action_name, target_id, at)", "scheduler must define defensive spell wait start helper")
    assert_contains(source, "function scheduler.refresh_defensive_spell_wait_lock(at)", "scheduler must define defensive spell movement-lock refresh helper")
    assert_contains(source, "function scheduler.apply_defensive_spell_movement_lock(action_name, target_id, at)", "scheduler must define defensive spell stop/lock helper")

    assert_contains(source, "phase.tank_spell_wait_until = now_value + 8.0", "tank spell helper baseline must remain bounded")
    assert_contains(source, "scheduler.defensive_spell_wait_until = now_value + 8.0", "defensive spell wait must be bounded")
    assert_contains(source, "ownership_enabled = false,", "defensive spell stop helper must not change ownership promotion policy")
    assert_contains(source, "require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({", "defensive spell stop helper must use existing run_stop seam")
    assert_contains(source, "_G.UC_MOVEMENT_OWNER = 'scheduler'", "defensive spell helper must set scheduler movement owner")
    assert_contains(source, "_G.UC_MOVEMENT_LOCK_UNTIL = now_value + 0.6", "defensive spell send helper must create a bounded initial lock")
    assert_contains(source, "_G.UC_MOVEMENT_LOCK_UNTIL = math.min(wait_until, now_value + 0.6)", "defensive spell wait refresh must keep the lock bounded")
    assert_contains(source, "if (not acting) and now_value >= cooldown_until then", "defensive spell wait must release after spell completion/cooldown")

    assert_contains(source, "local defensive_spell_wait_locked = scheduler.refresh_defensive_spell_wait_lock(now_s())", "process tick must refresh defensive spell lock before movement coordinator")
    assert_contains(source, "return true, 'BLOCK_DEFENSIVE_SPELL_WAITING'", "active defensive spell wait must block scheduler movement/action dispatch")

    local target_lane_pos = assert(source:find("local target_acted, target_reason = scheduler.p1_try_nonblocking_target_acquire(s)", 1, true))
    local refresh_pos = assert(source:find("local defensive_spell_wait_locked = scheduler.refresh_defensive_spell_wait_lock(now_s())", 1, true))
    local p1_pos = assert(source:find("local p1_acted, p1_reason = p1_try_dark_launch_dispatch(s)", 1, true))
    local move_pos = assert(source:find("local move_acted, move_reason = run_movement_coordinator_tick()", refresh_pos + 1, true))
    assert_true(target_lane_pos < refresh_pos, "nonblocking target acquire may run before defensive spell wait refresh")
    assert_true(refresh_pos < p1_pos, "defensive spell wait refresh must run before p1 dispatch")
    assert_true(refresh_pos < move_pos, "defensive spell wait refresh must run before movement coordinator")

    assert_contains(source, "local can_apply_defensive_spell_lock = (", "defensive spell send paths must guard lock creation")
    assert_contains(source, "scheduler.apply_defensive_spell_movement_lock(tostring(action.spell or ''), tonumber(action.target and action.target.id) or 0, now)", "direct defensive sender must apply spell movement lock at send point")
    assert_contains(source, "scheduler.begin_defensive_spell_wait(tostring(action.spell or ''), tonumber(action.target and action.target.id) or 0, now)", "direct defensive sender must begin defensive spell wait")
    assert_contains(source, "scheduler.apply_defensive_spell_movement_lock(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0, now_gate)", "ranked defensive sender must apply spell movement lock at send point")
    assert_contains(source, "scheduler.begin_defensive_spell_wait(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0, now_gate)", "ranked defensive sender must begin defensive spell wait")

    assert_contains(source, "(tostring(action.type or '') ~= 'cure' or target_hpp > 0)", "direct defensive sender must avoid stale cure lock on dead/invalid targets")
    assert_contains(source, "(tostring(type(detail) == 'table' and detail.def_action_type or '') ~= 'cure' or target_hpp > 0)", "ranked defensive sender must avoid stale cure lock on dead/invalid targets")

    local direct_side_effect_patterns = {
        "windower.send_command(",
        "windower.ffxi.run(",
        "windower.ffxi.turn(",
        "uc_settarget.select_by_id(",
    }
    for _, pattern in ipairs(direct_side_effect_patterns) do
        if count_plain(source, pattern) ~= 0 then
            error("scheduler direct side-effect invariant broken for pattern: " .. pattern)
        end
    end

    assert_not_contains(source, "UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_CURE", "no new defensive cure ownership promotion flag should be introduced")
    assert_not_contains(source, "UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_SPELL", "no new defensive spell ownership promotion flag should be introduced")

    io.stdout:write("selftest_scheduler_defensive_cure_movement_lock: OK\n")
end

main()
