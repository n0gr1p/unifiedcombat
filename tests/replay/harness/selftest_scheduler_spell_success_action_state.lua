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

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text present: " .. needle))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function assert_close(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error((message or "assert_close failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
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

    assert_contains(action_state_source, "function M.clear_local_defensive_spell_success", "action-state helper for defensive spell success must exist")
    assert_contains(action_state_source, "function M.clear_local_spell_success", "generic action-state helper for local spell success must exist")
    assert_contains(action_state_source, "local SPELL_SUCCESS_TAIL_S = 0.2", "spell success helpers must keep the bounded post-cast tail constant explicit")
    assert_contains(action_state_source, "st.cooldown_until = now + SPELL_SUCCESS_TAIL_S", "defensive spell success helper must shorten cooldown to a bounded tail")
    assert_contains(action_state_source, "st.action_delay = SPELL_SUCCESS_TAIL_S", "defensive spell success helper must set a bounded post-cast tail")
    assert_contains(action_state_source, "st.post_spell_tail_started_at = now", "spell success helper must record the tail start time")
    assert_contains(action_state_source, "st.post_spell_tail_until = now + SPELL_SUCCESS_TAIL_S", "spell success helper must record the bounded tail deadline")
    assert_contains(action_state_source, "if last_send_kind ~= 'spell' then", "success clear must not clear JA/WS state")
    assert_contains(action_state_source, "if last_provider ~= 'defensive_internal' and last_provider ~= 'defensive_healbot' then", "success clear must stay scoped to defensive spell providers")

    assert_contains(scheduler_source, "function scheduler.clear_local_defensive_spell_success()", "scheduler must expose defensive spell success helper")
    assert_contains(scheduler_source, "function scheduler.clear_local_spell_success()", "scheduler must expose generic local spell success helper")
    assert_contains(scheduler_source, "local handled_local_spell_success = false", "scheduler success branch must track handled spell success")
    assert_contains(scheduler_source, "scheduler.is_spell_success_message_id(message_id)", "scheduler success branch must use known spell-success ids")
    assert_contains(scheduler_source, "scheduler.clear_local_spell_success()", "scheduler success branch must clear local spell success state")
    assert_contains(scheduler_source, "p1_pending_mark_complete(now, ('spell_success_%d'):format(message_id))", "scheduler success branch must mark pending complete with explicit success code")
    assert_contains(scheduler_source, "_G.UC_MOVEMENT_LOCK_UNTIL = math.min(current_lock_until, now + 0.2)", "scheduler success branch must only shorten scheduler-owned movement lock")
    assert_not_contains(scheduler_source, "\t\tspell_finish = true,", "scheduler start markers must no longer treat spell_finish as a start signal")

    local scheduler = {}

    now_value = 10
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Cure IV",
        provider = "defensive_internal",
        def_action_type = "cure",
    })
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "defensive spell must start as acting")

    local cleared = action_state.clear_local_defensive_spell_success(scheduler, now_s)
    assert_equal(cleared, true, "local defensive spell success must clear defensive spell action state")
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "defensive spell success must end acting state immediately")
    local st = action_state.action_state(scheduler)
    assert_close(tonumber(st.cooldown_until) or 0, 10.2, 0.0001, "defensive spell success must leave only a bounded cooldown tail")
    assert_close(tonumber(st.action_delay) or 0, 0.2, 0.0001, "defensive spell success must leave only a bounded action delay tail")

    now_value = 20
    local init_scheduler = {}
    action_state.action_mark_sent_with_meta(init_scheduler, "spell", now_s, {
        action_name = "Cure III",
        provider = "defensive_internal",
        def_action_type = "cure",
    })
    assert_equal(action_state.action_is_acting(init_scheduler, now_s), true, "initiating defensive spell must remain acting before success")

    now_value = 30
    local ja_scheduler = {}
    action_state.action_mark_sent_with_meta(ja_scheduler, "ja", now_s, {
        action_name = "Majesty",
        provider = "defensive_internal",
        def_action_type = "buff",
    })
    cleared = action_state.clear_local_defensive_spell_success(ja_scheduler, now_s)
    assert_equal(cleared, false, "spell success must not clear JA state")

    now_value = 40
    local ws_scheduler = {}
    action_state.action_mark_sent_with_meta(ws_scheduler, "ws", now_s, {
        action_name = "Savage Blade",
        provider = "combat",
        def_action_type = "",
    })
    cleared = action_state.clear_local_defensive_spell_success(ws_scheduler, now_s)
    assert_equal(cleared, false, "spell success must not clear WS state")

    now_value = 50
    local other_scheduler = {}
    action_state.action_mark_sent_with_meta(other_scheduler, "spell", now_s, {
        action_name = "Dia",
        provider = "combat",
        def_action_type = "",
    })
    cleared = action_state.clear_local_defensive_spell_success(other_scheduler, now_s)
    assert_equal(cleared, false, "unrelated combat spell must not be cleared by defensive spell success helper")
    cleared = action_state.clear_local_spell_success(other_scheduler, now_s)
    assert_equal(cleared, true, "generic spell success helper must clear unrelated local combat spell state after confirmed success")
    st = action_state.action_state(other_scheduler)
    assert_close(tonumber(st.cooldown_until) or 0, 50.2, 0.0001, "generic spell success helper must leave only a bounded cooldown tail for local combat spells")
    assert_close(tonumber(st.action_delay) or 0, 0.2, 0.0001, "generic spell success helper must leave only a bounded action delay tail for local combat spells")

    now_value = 60
    local timeout_scheduler = {}
    action_state.action_mark_sent_with_meta(timeout_scheduler, "spell", now_s, {
        action_name = "Cure IV",
        provider = "defensive_internal",
        def_action_type = "cure",
    })
    assert_equal(action_state.action_is_acting(timeout_scheduler, now_s), true, "timeout fallback scenario must begin as acting")
    now_value = 69
    assert_equal(action_state.action_is_acting(timeout_scheduler, now_s), false, "timeout fallback must remain available when no success/interruption packet arrives")

    io.stdout:write("selftest_scheduler_spell_success_action_state: OK\n")
end

main()
