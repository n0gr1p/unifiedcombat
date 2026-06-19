local scheduler_path = "unified_scheduler.lua"
local command_ownership_path = "uc_scheduler_command_ownership.lua"
local dispatcher_path = "uc_scheduler_dispatcher.lua"

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

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local ENGAGE_DUPLICATE_RETRY_DEBOUNCE_S = 0.30
local PENDING_ENGAGE_TIMEOUT_S = 1.75
local PENDING_ENGAGE_RETRY_DELAY_S = 0.40

local function note_engage_attempt(state, target_id, now_value, player_status)
    state.engage_duplicate = {
        target_id = tonumber(target_id) or 0,
        target_name = "Apex_Bat",
        last_attempt_at = now_value,
        suppressed_until = now_value + ENGAGE_DUPLICATE_RETRY_DEBOUNCE_S,
        player_status = tonumber(player_status) or 0,
        dispatch_method = "attack_on",
    }
end

local function reset_target_change(state, new_target_id)
    local old = state.engage_duplicate
    if type(old) == "table" and (tonumber(old.target_id) or 0) ~= (tonumber(new_target_id) or 0) then
        state.engage_duplicate = nil
        return true
    end
    return false
end

local function begin_pending_engage(state, target_id, now_value)
    state.pending_engage = {
        target_id = tonumber(target_id) or 0,
        target_name = "Apex_Bat",
        started_at = now_value,
        timeout_at = now_value + PENDING_ENGAGE_TIMEOUT_S,
        retry_ready_at = now_value,
        last_attempt_at = now_value,
        retry_count = 0,
        wait_longer_count = 0,
    }
end

local function mark_wait_longer_rejection(state, now_value)
    local pending = assert(state.pending_engage, "pending engage required")
    pending.wait_longer_count = (tonumber(pending.wait_longer_count) or 0) + 1
    pending.retry_count = (tonumber(pending.retry_count) or 0) + 1
    pending.retry_ready_at = math.min(tonumber(pending.timeout_at) or now_value, now_value + PENDING_ENGAGE_RETRY_DELAY_S)
    state.engage_duplicate = nil
end

local function refresh_pending_timeout(state, now_value, player_status)
    local pending = state.pending_engage
    if type(pending) ~= "table" then
        return false, "inactive"
    end
    if tonumber(player_status) == 1 then
        state.pending_engage = nil
        state.engage_duplicate = nil
        return false, "confirmed"
    end
    if now_value >= (tonumber(pending.timeout_at) or 0) then
        state.pending_engage = nil
        state.engage_duplicate = nil
        return false, "timeout"
    end
    return true, "active"
end

local function engage_duplicate_gate(state, target_id, now_value, player_status)
    if tonumber(player_status) == 1 then
        state.engage_duplicate = nil
        return true, "engaged"
    end
    if reset_target_change(state, target_id) then
        return true, "target_change"
    end
    local pending = state.pending_engage
    local dup = state.engage_duplicate
    if type(dup) == "table"
        and type(pending) == "table"
        and (tonumber(pending.target_id) or 0) == (tonumber(target_id) or 0)
        and now_value >= (tonumber(pending.retry_ready_at) or 0)
        and now_value < (tonumber(dup.suppressed_until) or 0) then
        state.engage_duplicate = nil
        return true, "retry_ready"
    end
    if type(dup) ~= "table" then
        return true, "ready"
    end
    if now_value < (tonumber(dup.suppressed_until) or 0) then
        return false, "duplicate_suppressed"
    end
    return true, "ready"
end

local function strict_toggle_guard(last_sent_at, now_value)
    if tonumber(last_sent_at) and now_value < (last_sent_at + 2.0) then
        return false
    end
    return true
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
    local detail = type(proposal.detail) == "table" and proposal.detail or {}
    local target_hpp = tonumber(detail.target_hpp) or -1
    local critical_hpp = tonumber(settings.defensive_critical_hpp) or 35
    local is_critical_cure =
        (tostring(proposal.provider or "") == "defensive_internal" or tostring(proposal.provider or "") == "defensive_healbot")
        and tostring(proposal.action_type or "") == "spell"
        and tostring(detail.def_action_type or "") == "cure"
        and target_hpp > 0
        and target_hpp <= critical_hpp
    if is_critical_cure then
        return true, "critical_override"
    end
    return false, "pending_engage_block_noncritical"
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local command_ownership_source = read_file(command_ownership_path)
    local dispatcher_source = read_file(dispatcher_path)

    assert_contains(scheduler_source, "scheduler.ENGAGE_DUPLICATE_RETRY_DEBOUNCE_S = 0.30", "scheduler must pin the explicit attack-on retry debounce")
    assert_contains(scheduler_source, "scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON = 'attack_on'", "scheduler must pin the explicit attack-on dispatch label")
    assert_contains(scheduler_source, "function scheduler.p1_validate_engage_duplicate_retry", "scheduler must define engage-specific duplicate retry validation")
    assert_contains(scheduler_source, "ENGAGE_DUPLICATE_ALLOWED_RETRY", "scheduler must log when pending engage retry bypasses stale duplicate suppression")
    assert_contains(scheduler_source, "ENGAGE_DUPLICATE_RESET_TARGET_CHANGE", "scheduler must log duplicate reset on target change")
    assert_contains(scheduler_source, "ENGAGE_DUPLICATE_RESET_REJECTION", "scheduler must log duplicate reset on wait-longer rejection")
    assert_contains(scheduler_source, "dispatch_method = dispatch_method", "engage duplicate logging must include dispatch method")
    assert_contains(scheduler_source, "pending_engage = pending_live and 'active' or 'inactive'", "engage duplicate logging must include pending engage state")
    assert_contains(scheduler_source, "sent_for_target = 1", "engage duplicate logging must report whether an engage was already sent for the target")
    assert_contains(scheduler_source, "uc_attack.engage_target(expected_tid)", "scheduler engage dispatch must still use the explicit attack-on helper")
    assert_not_contains(command_ownership_source, "engage_target", "command ownership seam must not own engage dispatch")
    assert_not_contains(dispatcher_source, "engage_target", "dispatcher seam must not own engage dispatch")
    assert_not_contains(scheduler_source, "windower.send_command('/attack", "scheduler engage path must not introduce console attack toggles")
    assert_not_contains(scheduler_source, "input /attack", "scheduler engage path must not introduce input attack toggles")

    local state = {}

    local allowed, reason = engage_duplicate_gate(state, 2001, 10.00, 0)
    assert_equal(allowed, true, "first explicit attack-on engage should be allowed")
    assert_equal(reason, "ready", "first engage should be immediately ready")
    note_engage_attempt(state, 2001, 10.00, 0)
    assert_close(tonumber(state.engage_duplicate.suppressed_until) or 0, 10.30, 0.0001, "explicit attack-on engage should only debounce for the short configured cadence")

    allowed, reason = engage_duplicate_gate(state, 2001, 10.10, 0)
    assert_equal(allowed, false, "explicit attack-on retry must still be rate-limited inside the short debounce")
    assert_equal(reason, "duplicate_suppressed", "short debounce must surface as duplicate suppression")
    allowed, reason = engage_duplicate_gate(state, 2001, 10.31, 0)
    assert_equal(allowed, true, "explicit attack-on retry must be allowed promptly after the short debounce")
    assert_equal(reason, "ready", "retry should reopen once the short debounce expires")

    begin_pending_engage(state, 2001, 20.00)
    note_engage_attempt(state, 2001, 20.00, 0)
    mark_wait_longer_rejection(state, 20.10)
    assert_equal(state.engage_duplicate, nil, "wait-longer rejection must clear stale engage duplicate suppression immediately")
    allowed, reason = pending_gate({ defensive_critical_hpp = 35 }, state, 20.20, {
        provider = "combat",
        action_type = "engage",
        action_name = "engage_target",
    })
    assert_equal(allowed, false, "pending engage retry must still respect the bounded retry-ready window")
    assert_equal(reason, "pending_engage_retry_wait", "pending engage retry gate mismatch")
    allowed, reason = engage_duplicate_gate(state, 2001, 20.50, 0)
    assert_equal(allowed, true, "retry-ready engage must not inherit stale duplicate suppression after wait-longer rejection")
    assert_equal(reason, "ready", "retry-ready engage should reopen cleanly after rejection reset")

    begin_pending_engage(state, 2001, 30.00)
    note_engage_attempt(state, 2001, 30.00, 0)
    local live, refresh_reason = refresh_pending_timeout(state, 31.80, 0)
    assert_equal(live, false, "pending engage timeout must end the retry window")
    assert_equal(refresh_reason, "timeout", "pending engage timeout reason mismatch")
    assert_equal(state.engage_duplicate, nil, "timeout must clear stale engage duplicate suppression")
    allowed, reason = engage_duplicate_gate(state, 2001, 31.81, 0)
    assert_equal(allowed, true, "post-timeout engage should not stay locked out by stale duplicate suppression")
    assert_equal(reason, "ready", "post-timeout engage should reopen cleanly")

    note_engage_attempt(state, 2001, 40.00, 0)
    allowed, reason = engage_duplicate_gate(state, 2002, 40.05, 0)
    assert_equal(allowed, true, "target changes must bypass stale engage duplicate suppression")
    assert_equal(reason, "target_change", "target-change reset reason mismatch")
    assert_equal(state.engage_duplicate, nil, "target change must clear the old target's duplicate state")

    note_engage_attempt(state, 2003, 50.00, 0)
    allowed, reason = engage_duplicate_gate(state, 2003, 50.10, 1)
    assert_equal(allowed, true, "status=1 should clear engage duplicate suppression")
    assert_equal(reason, "engaged", "status=1 should be treated as confirmed engage")
    assert_equal(state.engage_duplicate, nil, "status=1 must clear the engage duplicate state")

    assert_equal(strict_toggle_guard(60.00, 60.50), false, "toggle-risk fallback should remain under strict suppression if it ever exists")
    assert_equal(strict_toggle_guard(60.00, 62.10), true, "strict toggle guard should eventually reopen after a long cooloff")

    begin_pending_engage(state, 3001, 70.00)
    local pending_allowed, pending_reason = pending_gate({ defensive_critical_hpp = 35 }, state, 70.05, {
        provider = "combat",
        family_id = "combat.sleep.primary",
        action_type = "spell",
        action_name = "Sleep II",
    })
    assert_equal(pending_allowed, false, "pending engage must still block non-critical Sleep during engage confirmation")
    assert_equal(pending_reason, "pending_engage_block_noncritical", "non-critical pending engage block reason mismatch")
    pending_allowed, pending_reason = pending_gate({ defensive_critical_hpp = 35 }, state, 70.05, {
        provider = "defensive_internal",
        action_type = "spell",
        action_name = "Cure IV",
        detail = { def_action_type = "cure", target_hpp = 20 },
    })
    assert_equal(pending_allowed, true, "critical Cure override must survive the duplicate suppression hotfix")
    assert_equal(pending_reason, "critical_override", "critical Cure override reason mismatch")

    io.stdout:write("selftest_engage_duplicate_suppression: OK\n")
end

main()
