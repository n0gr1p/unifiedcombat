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

local function main()
    local source = read_file(scheduler_path)

    assert_contains(source, "tank_spell_waiting = false,", "phase state must define tank spell waiting flag")
    assert_contains(source, "tank_spell_wait_until = 0,", "phase state must define tank spell wait timeout")
    assert_contains(source, "tank_pending_action = '',", "phase state must define tank pending action")
    assert_contains(source, "tank_pending_target_id = 0,", "phase state must define tank pending target id")
    assert_contains(source, "tank_pending_sent_at = 0,", "phase state must define tank pending sent timestamp")

    assert_contains(source, "function scheduler.p1_clear_tank_spell_wait_state(phase)", "scheduler must define a tank spell wait clear helper")
    assert_contains(source, "function scheduler.p1_begin_tank_spell_wait(phase, action_name, target_id, at)", "scheduler must define a tank spell wait start helper")
    assert_contains(source, "function scheduler.p1_refresh_tank_spell_wait_lock(phase, at)", "scheduler must define a tank spell movement-lock refresh helper")

    assert_contains(source, "phase.tank_spell_wait_until = now_value + 8.0", "tank spell wait helper must keep the lock bounded")
    assert_contains(source, "if now_value >= wait_until then", "tank spell wait helper must expire")
    assert_contains(source, "if send_kind ~= 'spell' then", "tank spell wait helper must fail closed when the last sent kind is not spell")
    assert_contains(source, "if (not acting) and now_value >= cooldown_until then", "tank spell wait helper must release after spell action/cooldown completion")
    assert_contains(source, "_G.UC_MOVEMENT_OWNER = 'scheduler'", "tank spell wait helper must claim scheduler movement ownership")
    assert_contains(source, "_G.UC_MOVEMENT_LOCK_UNTIL = math.min(wait_until, now_value + 0.6)", "tank spell wait helper must refresh only a short bounded movement lock window")

    assert_contains(source, "local tank_spell_wait_locked = scheduler.p1_refresh_tank_spell_wait_lock(phase, now_s())", "dispatch path must refresh tank spell movement lock before provider dispatch")
    assert_contains(source, "return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_TANK_SPELL_WAIT'", "active tank spell wait must block scheduler dispatch during cast wait")

    local refresh_pos = assert(source:find("local tank_spell_wait_locked = scheduler.p1_refresh_tank_spell_wait_lock(phase, now_s())", 1, true))
    local provider_pos = assert(source:find("local provider = tostring(selected.provider or '')", 1, true))
    assert_true(refresh_pos < provider_pos, "tank spell wait refresh must run before provider dispatch selection")

    local target_send_anchor = assert(source:find("action_mark_sent('spell', {", 1, true))
    local target_wait_anchor = assert(source:find("scheduler.p1_begin_tank_spell_wait(phase, spell, expected_tid, now_s())", target_send_anchor, true))
    assert_true(target_wait_anchor > target_send_anchor, "tank target spell send must start wait only after spell send is marked")

    local self_send_anchor = assert(source:find("action_mark_sent('spell', {", target_wait_anchor + 1, true))
    local self_wait_anchor = assert(source:find("scheduler.p1_begin_tank_spell_wait(phase, spell, 0, now_s())", self_send_anchor, true))
    assert_true(self_wait_anchor > self_send_anchor, "tank self spell send must start wait only after spell send is marked")

    assert_not_contains(source, "_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_WAIT", "tank spell movement lock bugfix must not introduce a new ownership promotion flag")

    io.stdout:write("selftest_scheduler_tank_spell_movement_lock: OK\n")
end

main()
