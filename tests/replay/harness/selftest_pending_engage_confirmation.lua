local scheduler_path = "unified_scheduler.lua"
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

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local PENDING_ENGAGE_TIMEOUT_S = 1.75
local PENDING_ENGAGE_RETRY_DELAY_S = 0.40
local PRIORITY_BAND_ENGAGE_BYPASS = 113

local function begin_pending_engage(state, target_id, target_name, now_value)
    state.pending_engage = {
        target_id = tonumber(target_id) or 0,
        target_name = tostring(target_name or ""),
        started_at = now_value,
        timeout_at = now_value + PENDING_ENGAGE_TIMEOUT_S,
        retry_ready_at = now_value,
        last_attempt_at = now_value,
        retry_count = 0,
        wait_longer_count = 0,
    }
end

local function note_pending_engage_attempt(state, now_value)
    local pending = assert(state.pending_engage, "pending engage required")
    pending.last_attempt_at = now_value
    pending.timeout_at = now_value + PENDING_ENGAGE_TIMEOUT_S
    pending.retry_ready_at = now_value
end

local function pending_gate(settings, state, now_value, proposal)
    local pending = state.pending_engage
    if type(pending) ~= "table" or now_value >= (tonumber(pending.timeout_at) or 0) then
        return true, "inactive"
    end
    if tostring(proposal.provider or "") == "target_control" then
        return true, "target_control"
    end
    if tostring(proposal.action_type or "") == "engage" then
        if now_value < (tonumber(pending.retry_ready_at) or 0) then
            return false, "pending_engage_retry_wait"
        end
        return true, "engage_ready"
    end
    if type(proposal.priority_band) == "number" and proposal.priority_band >= PRIORITY_BAND_ENGAGE_BYPASS then
        return true, "priority_override"
    end
    return false, "pending_engage_block_noncritical"
end

local function refresh_pending_engage(state, now_value, player_status, target_valid)
    local pending = state.pending_engage
    if type(pending) ~= "table" then
        return false, "inactive"
    end
    if tonumber(player_status) == 1 then
        state.pending_engage = nil
        return false, "confirmed"
    end
    if target_valid ~= true then
        state.pending_engage = nil
        return false, "invalid_target"
    end
    if now_value >= (tonumber(pending.timeout_at) or 0) then
        state.pending_engage = nil
        return false, "timeout"
    end
    return true, "active"
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local action_state_source = read_file(action_state_path)

    assert_contains(scheduler_source, "scheduler.PENDING_ENGAGE_TIMEOUT_S = 1.75", "scheduler must pin the bounded pending engage timeout")
    assert_contains(scheduler_source, "scheduler.PENDING_ENGAGE_RETRY_DELAY_S = 0.40", "scheduler must pin the bounded engage retry delay")
    assert_contains(scheduler_source, "function scheduler.p1_note_pending_engage_attempt", "scheduler must define pending engage start/retry bookkeeping")
    assert_contains(scheduler_source, "function scheduler.p1_refresh_pending_engage", "scheduler must define pending engage refresh/confirmation bookkeeping")
    assert_contains(scheduler_source, "PENDING_ENGAGE_ALLOW_CRITICAL", "scheduler must log critical pending engage overrides")
    assert_contains(scheduler_source, "PENDING_ENGAGE_CONFIRMED", "scheduler must log confirmed engage state")
    assert_contains(scheduler_source, "PENDING_ENGAGE_CLEARED_INVALID_TARGET", "scheduler must clear pending engage on invalid targets")
    assert_contains(scheduler_source, "scheduler.p1_clear_engage_duplicate_state(phase, '', now_value)", "pending engage cleanup must clear explicit attack-on duplicate retry state on confirmation/timeout/invalid-target exit")
    assert_contains(action_state_source, "tail_s", "action-state release path must publish bounded post-spell tail timing")

    local settings = { defensive_critical_hpp = 35 }
    local state = {}
    begin_pending_engage(state, 1001, "Apex_Bat", 10.00)
    assert_true(type(state.pending_engage) == "table", "engage dispatch must start pending engage state")

    local allowed, reason = pending_gate(settings, state, 10.05, {
        provider = "defensive_internal",
        action_type = "spell",
        action_name = "Cure IV",
        priority_band = 100,
        detail = { def_action_type = "cure", target_hpp = 80 },
    })
    assert_equal(allowed, false, "pending engage must block non-critical Cure")
    assert_equal(reason, "pending_engage_block_noncritical", "non-critical Cure block reason mismatch")

    allowed, reason = pending_gate(settings, state, 10.05, {
        provider = "maintenance",
        action_type = "spell",
        action_name = "Protect V",
        priority_band = 75,
    })
    assert_equal(allowed, false, "pending engage must block maintenance buffs")
    assert_equal(reason, "pending_engage_block_noncritical", "maintenance block reason mismatch")

    allowed, reason = pending_gate(settings, state, 10.05, {
        provider = "combat",
        family_id = "combat.sleep.primary",
        action_type = "spell",
        action_name = "Sleep II",
        priority_band = 113,
    })
    assert_equal(allowed, true, "pending engage must allow globally high-priority Sleep")
    assert_equal(reason, "priority_override", "Sleep priority override reason mismatch")

    allowed, reason = pending_gate(settings, state, 10.05, {
        provider = "defensive_internal",
        action_type = "spell",
        action_name = "Cure IV",
        priority_band = 117,
        detail = { def_action_type = "cure", target_hpp = 25 },
    })
    assert_equal(allowed, true, "pending engage must allow critical Cure overrides")
    assert_equal(reason, "priority_override", "critical Cure priority override reason mismatch")

    allowed, reason = pending_gate(settings, state, 10.05, {
        provider = "target_control",
        action_type = "select_target",
        action_name = "select_target",
    })
    assert_equal(allowed, true, "target acquisition must remain nonblocking during pending engage")
    assert_equal(reason, "target_control", "target-control reason mismatch")

    local live, refresh_reason = refresh_pending_engage(state, 10.20, 1, true)
    assert_equal(live, false, "status=1 must confirm and clear pending engage")
    assert_equal(refresh_reason, "confirmed", "confirmed engage reason mismatch")
    assert_equal(state.pending_engage, nil, "confirmed engage must clear pending state")

    begin_pending_engage(state, 1002, "Apex_Bat", 20.00)
    live, refresh_reason = refresh_pending_engage(state, 20.10, 0, false)
    assert_equal(live, false, "invalid targets must clear pending engage")
    assert_equal(refresh_reason, "invalid_target", "invalid target clear reason mismatch")
    assert_equal(state.pending_engage, nil, "invalid target must clear pending state")

    begin_pending_engage(state, 1003, "Apex_Bat", 30.00)
    note_pending_engage_attempt(state, 31.00)
    live, refresh_reason = refresh_pending_engage(state, 31.80, 0, true)
    assert_equal(live, true, "latest engage attempt must refresh the pending timeout window")
    assert_equal(refresh_reason, "active", "refreshed pending engage should remain active before the latest timeout")
    live, refresh_reason = refresh_pending_engage(state, 32.76, 0, true)
    assert_equal(live, false, "pending engage must still expire after the latest attempt window")
    assert_equal(refresh_reason, "timeout", "latest-attempt timeout reason mismatch")
    assert_equal(state.pending_engage, nil, "latest-attempt timeout must still clear pending state")

    begin_pending_engage(state, 1004, "Apex_Bat", 40.00)
    live, refresh_reason = refresh_pending_engage(state, 40.50, 0, true)
    assert_equal(live, true, "separate fresh pending engage must not inherit the previous timeout")
    assert_equal(refresh_reason, "active", "fresh pending engage should still be active")
    live, refresh_reason = refresh_pending_engage(state, 41.76, 0, true)
    assert_equal(live, false, "pending engage must time out after the bounded timeout")
    assert_equal(refresh_reason, "timeout", "timeout reason mismatch")
    assert_equal(state.pending_engage, nil, "timed out pending engage must clear pending state")

    io.stdout:write("selftest_pending_engage_confirmation: OK\n")
end

main()
