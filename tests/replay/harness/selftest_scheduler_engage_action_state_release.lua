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

    assert_contains(action_state_source, "function M.action_mark_engage_sent", "engage action-state helper must exist")
    assert_contains(action_state_source, "local ENGAGE_ACTION_TAIL_S = 0.35", "engage helper must keep the short bounded tail constant explicit")
    assert_contains(action_state_source, "st.action_delay = ENGAGE_ACTION_TAIL_S", "engage helper must leave a short bounded action tail")
    assert_contains(action_state_source, "st.cooldown_until = math.max(tonumber(st.cooldown_until) or 0, now + ENGAGE_ACTION_TAIL_S)", "engage helper must leave a short bounded cooldown tail")
    assert_contains(action_state_source, "st.last_send_kind = 'engage'", "engage helper must classify engage sends distinctly")
    assert_contains(scheduler_source, "require('uc_scheduler_action_state').action_mark_engage_sent(scheduler, now_s)", "scheduler engage dispatch must use engage-specific action-state release")

    local engage_scheduler = {}
    now_value = 10
    action_state.action_mark_engage_sent(engage_scheduler, now_s)
    assert_equal(action_state.action_is_acting(engage_scheduler, now_s), false, "engage send must not enter the generic acting state")
    local st = action_state.action_state(engage_scheduler)
    assert_close(tonumber(st.cooldown_until) or 0, 10.35, 0.0001, "engage send must leave only a short bounded cooldown tail")
    assert_close(tonumber(st.action_delay) or 0, 0.35, 0.0001, "engage send must leave only a short bounded action delay tail")

    local blocked, reason = action_state.action_dispatch_blocked(engage_scheduler, now_s, {})
    assert_equal(blocked, true, "engage send must still debounce immediate repeat dispatch")
    assert_equal(reason, "BLOCK_ACTION_COOLDOWN", "engage debounce should be cooldown-based, not acting-based")

    now_value = 10.36
    blocked, reason = action_state.action_dispatch_blocked(engage_scheduler, now_s, {})
    assert_equal(blocked, false, "engage send must release after the short bounded timeout")
    assert_equal(reason, nil, "released engage debounce should not return a block reason")

    local spell_scheduler = {}
    now_value = 20
    action_state.action_mark_sent(spell_scheduler, "spell", now_s)
    assert_equal(action_state.action_is_acting(spell_scheduler, now_s), true, "spell send must still enter acting state")

    now_value = 27.9
    assert_equal(action_state.action_is_acting(spell_scheduler, now_s), true, "spell send must still use the normal long timeout before expiry")
    now_value = 28.1
    assert_equal(action_state.action_is_acting(spell_scheduler, now_s), false, "spell send timeout fallback must still work")

    local ja_scheduler = {}
    now_value = 30
    action_state.action_mark_sent(ja_scheduler, "ja", now_s)
    assert_equal(action_state.action_is_acting(ja_scheduler, now_s), true, "JA send must still enter acting state")
    now_value = 30.9
    assert_equal(action_state.action_is_acting(ja_scheduler, now_s), true, "JA send must still use the normal JA timeout before expiry")
    now_value = 31.1
    assert_equal(action_state.action_is_acting(ja_scheduler, now_s), false, "JA send timeout fallback must still work")

    local ws_scheduler = {}
    now_value = 40
    action_state.action_mark_sent(ws_scheduler, "ws", now_s)
    assert_equal(action_state.action_is_acting(ws_scheduler, now_s), true, "WS send must still enter acting state")
    now_value = 47.9
    assert_equal(action_state.action_is_acting(ws_scheduler, now_s), true, "WS send must still use the normal long timeout before expiry")
    now_value = 48.1
    assert_equal(action_state.action_is_acting(ws_scheduler, now_s), false, "WS send timeout fallback must still work")

    io.stdout:write("selftest_scheduler_engage_action_state_release: OK\n")
end

main()
