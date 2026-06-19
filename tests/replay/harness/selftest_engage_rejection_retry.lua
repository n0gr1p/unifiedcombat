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

local PENDING_ENGAGE_TIMEOUT_S = 1.75
local PENDING_ENGAGE_RETRY_DELAY_S = 0.40
local WAIT_LONGER_MESSAGE_ID = 94

local function begin_pending_engage(state, now_value)
    state.pending_engage = {
        target_id = 2001,
        target_name = "Apex_Bat",
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

local function mark_rejected_wait_longer(state, now_value, message_id)
    local pending = assert(state.pending_engage, "pending engage required")
    pending.wait_longer_count = (tonumber(pending.wait_longer_count) or 0) + 1
    pending.retry_count = (tonumber(pending.retry_count) or 0) + 1
    pending.last_rejection_message_id = tonumber(message_id) or 0
    pending.retry_ready_at = math.min(tonumber(pending.timeout_at) or now_value, now_value + PENDING_ENGAGE_RETRY_DELAY_S)
end

local function engage_ready(state, now_value)
    local pending = state.pending_engage
    if type(pending) ~= "table" then
        return false
    end
    return now_value >= (tonumber(pending.retry_ready_at) or 0) and now_value < (tonumber(pending.timeout_at) or 0)
end

local function clear_if_invalid(state, target_valid)
    if target_valid ~= true then
        state.pending_engage = nil
        return true
    end
    return false
end

local function main()
    local scheduler_source = read_file(scheduler_path)

    assert_contains(scheduler_source, "scheduler.ENGAGE_REJECT_WAIT_LONGER_MESSAGE_ID = 94", "scheduler must pin the raw action-message id for wait-longer rejection")
    assert_contains(scheduler_source, "message_id == scheduler.ENGAGE_REJECT_WAIT_LONGER_MESSAGE_ID", "scheduler must detect wait-longer rejections by message id, not raw chat text")
    assert_contains(scheduler_source, "function scheduler.p1_mark_pending_engage_rejected_wait_longer", "scheduler must define engage rejection handling")
    assert_contains(scheduler_source, "PENDING_ENGAGE_REJECTED_WAIT_LONGER", "scheduler must log engage rejections")
    assert_contains(scheduler_source, "PENDING_ENGAGE_RETRY_READY", "scheduler must log bounded retry readiness")
    assert_contains(scheduler_source, "PENDING_ENGAGE_RETRY_ATTEMPT", "scheduler must log bounded retry attempts")
    assert_contains(scheduler_source, "ENGAGE_DUPLICATE_RESET_REJECTION", "wait-longer rejection must clear stale explicit attack-on duplicate suppression")
    assert_contains(scheduler_source, "scheduler.p1_clear_engage_duplicate_state(phase, 'ENGAGE_DUPLICATE_RESET_REJECTION'", "wait-longer rejection must reset explicit attack-on duplicate state directly")
    assert_contains(scheduler_source, "pending.timeout_at = now_value + scheduler.PENDING_ENGAGE_TIMEOUT_S", "retry attempts must refresh the pending timeout from the latest attempt")
    assert_contains(scheduler_source, "age_s = ('%.2f'):format(math.max(0, now_value - last_attempt_at))", "pending timeout logs must report age from the latest attempt")
    assert_contains(scheduler_source, "pending_engage_retry_wait", "scheduler must block engage retries until the short retry delay clears")

    local state = {}
    begin_pending_engage(state, 50.00)
    mark_rejected_wait_longer(state, 50.10, WAIT_LONGER_MESSAGE_ID)
    local pending = assert(state.pending_engage, "pending engage must survive wait-longer rejection")
    assert_equal(tonumber(pending.last_rejection_message_id) or 0, WAIT_LONGER_MESSAGE_ID, "wait-longer rejection must preserve the packet/message id")
    assert_equal(tonumber(pending.wait_longer_count) or 0, 1, "first wait-longer rejection must increment the rejection counter")
    assert_equal(tonumber(pending.retry_count) or 0, 1, "first wait-longer rejection must increment the retry counter")
    assert_close(tonumber(pending.retry_ready_at) or 0, 50.50, 0.0001, "retry readiness must use the bounded retry delay")

    assert_equal(engage_ready(state, 50.20), false, "retry must not be ready on every tick immediately after rejection")
    assert_equal(engage_ready(state, 50.49), false, "retry must remain blocked until the configured retry delay expires")
    assert_equal(engage_ready(state, 50.50), true, "retry must reopen once the short retry delay expires")
    note_pending_engage_attempt(state, 50.50)
    pending = assert(state.pending_engage, "retry attempt must keep pending engage live")
    assert_close(tonumber(pending.timeout_at) or 0, 52.25, 0.0001, "retry attempt must refresh the timeout window from the latest engage attempt")

    mark_rejected_wait_longer(state, 50.55, WAIT_LONGER_MESSAGE_ID)
    pending = assert(state.pending_engage, "pending engage must stay active through bounded repeated rejections")
    assert_equal(tonumber(pending.wait_longer_count) or 0, 2, "repeated wait-longer rejections must remain observable")
    assert_equal(tonumber(pending.retry_count) or 0, 2, "repeated wait-longer rejections must remain rate-limited through the retry counter")
    assert_close(tonumber(pending.retry_ready_at) or 0, 50.95, 0.0001, "each rejection must push the next retry to the bounded retry delay, not every tick")

    local invalid_cleared = clear_if_invalid(state, false)
    assert_equal(invalid_cleared, true, "retry must stop if the pending target becomes invalid")
    assert_equal(state.pending_engage, nil, "invalid pending target must clear the retry state")

    begin_pending_engage(state, 60.00)
    mark_rejected_wait_longer(state, 61.60, WAIT_LONGER_MESSAGE_ID)
    pending = assert(state.pending_engage, "pending engage must remain present until timeout")
    assert_close(tonumber(pending.retry_ready_at) or 0, 61.75, 0.0001, "retry readiness must clamp to the pending engage timeout ceiling")
    note_pending_engage_attempt(state, 61.75)
    pending = assert(state.pending_engage, "retry attempt must still be trackable after clamp scenarios")
    assert_close(tonumber(pending.timeout_at) or 0, 63.50, 0.0001, "latest retry attempt must extend the timeout from the retry send, not the first engage send")

    io.stdout:write("selftest_engage_rejection_retry: OK\n")
end

main()
