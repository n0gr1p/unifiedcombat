local scheduler_source_path = "unified_scheduler.lua"
local action_state_path = "uc_scheduler_action_state.lua"

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

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

package.loaded["uc_scheduler_action_state"] = nil
local action_state = dofile(action_state_path)

local now_value = 0

local function now_s()
    return now_value
end

local function main()
    local scheduler_source = read_file(scheduler_source_path)
    local action_state_source = read_file(action_state_path)

    assert_contains(action_state_source, "function M.clear_local_defensive_spell_interruption", "action-state helper for defensive spell interruption must exist")
    assert_contains(action_state_source, "if last_send_kind ~= 'spell' then", "interruption clear must not clear JA/WS state")
    assert_contains(action_state_source, "if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then", "interruption clear must stay scoped to defensive spell providers")

    assert_contains(scheduler_source, "function scheduler.is_spell_cast_complete_message_id(message_id)", "scheduler must classify spell cast-complete message ids")
    assert_contains(scheduler_source, "function scheduler.is_spell_cast_interrupted_message_id(message_id)", "scheduler must classify spell interruption message ids")
    assert_contains(scheduler_source, "scheduler.defensive_spell_waiting == true", "scheduler interruption branch must require defensive spell wait to be active")
    assert_contains(scheduler_source, "scheduler.is_spell_cast_interrupted_message_id(message_id)", "scheduler interruption branch must require an explicit cast-interrupted message")
    assert_contains(scheduler_source, "scheduler.clear_defensive_spell_wait_state()", "scheduler interruption branch must clear defensive spell wait")
    assert_contains(scheduler_source, "_G.UC_MOVEMENT_LOCK_UNTIL = math.min(current_lock_until, now + 0.2)", "scheduler interruption branch must only shorten scheduler-owned movement lock")
    assert_contains(scheduler_source, "p1_pending_mark_complete(now, ('spell_cast_interrupted_%d'):format(message_id))", "scheduler interruption branch must complete pending state with explicit interruption code")

    local scheduler = {}

    now_value = 10
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Cure IV",
        provider = "defensive_internal",
        def_action_type = "cure",
    })
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "defensive spell must start as acting")

    local cleared = action_state.clear_local_defensive_spell_interruption(scheduler, now_s)
    assert_equal(cleared, true, "local defensive spell interruption must clear defensive spell action state")
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "defensive spell interruption must end acting state immediately")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_interrupted", "interruption helper must record cast_interrupted terminal outcome")

    now_value = 20
    local ja_scheduler = {}
    action_state.action_mark_sent_with_meta(ja_scheduler, "ja", now_s, {
        action_name = "Majesty",
        provider = "defensive_internal",
        def_action_type = "buff",
    })
    cleared = action_state.clear_local_defensive_spell_interruption(ja_scheduler, now_s)
    assert_equal(cleared, false, "spell interruption must not clear JA state")

    now_value = 30
    local ws_scheduler = {}
    action_state.action_mark_sent_with_meta(ws_scheduler, "ws", now_s, {
        action_name = "Savage Blade",
        provider = "combat",
        def_action_type = "",
    })
    cleared = action_state.clear_local_defensive_spell_interruption(ws_scheduler, now_s)
    assert_equal(cleared, false, "spell interruption must not clear WS state")

    now_value = 40
    local other_scheduler = {}
    action_state.action_mark_sent_with_meta(other_scheduler, "spell", now_s, {
        action_name = "Dia",
        provider = "combat",
        def_action_type = "",
    })
    cleared = action_state.clear_local_defensive_spell_interruption(other_scheduler, now_s)
    assert_equal(cleared, false, "unrelated combat spell must not be cleared by defensive spell interruption helper")

    io.stdout:write("selftest_scheduler_spell_interruption_action_state: OK\n")
end

main()
