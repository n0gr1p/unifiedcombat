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

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local function format_fields(fields)
    local order = {
        "tid", "name", "role", "tank", "spell", "action", "provider", "band", "urgency", "critical", "reason",
        "status", "from", "to", "target", "target_id", "old_target_id", "message_id", "retry_in_s", "retry_count", "age_s", "remaining_s", "tail_s", "kind", "command", "dispatch_method", "pending_engage", "sent_for_target", "pull_owner", "target_valid", "range", "claim_check", "action_state", "top_family", "top_provider", "top_action"
    }
    local parts = {}
    local seen = {}
    for i = 1, #order do
        local key = order[i]
        local val = fields[key]
        if val ~= nil and val ~= "" then
            seen[key] = true
            parts[#parts + 1] = tostring(key) .. "=" .. tostring(val)
        end
    end
    local extra = {}
    for key, val in pairs(fields) do
        if not seen[key] and val ~= nil and val ~= "" then
            extra[#extra + 1] = tostring(key)
        end
    end
    table.sort(extra)
    for i = 1, #extra do
        local key = extra[i]
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(fields[key])
    end
    return table.concat(parts, " ")
end

local function format_line(elapsed, name, event_code, fields)
    local suffix = format_fields(fields or {})
    local line = ("%.3f | %s | %s"):format(elapsed, name, event_code)
    if suffix ~= "" then
        line = line .. " | " .. suffix
    end
    return line
end

local function mock_rate_limited()
    local st = { last_event_at = {} }
    local emitted = {}
    return function(now_value, event_code, dedupe_key, interval)
        local key = tostring(dedupe_key or event_code or "")
        local gap = tonumber(interval) or 0
        local last_at = tonumber(st.last_event_at[key]) or 0
        if key ~= "" and gap > 0 and last_at > 0 and (now_value - last_at) < gap then
            return false
        end
        st.last_event_at[key] = now_value
        emitted[#emitted + 1] = event_code
        return true, emitted
    end
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local action_state_source = read_file(action_state_path)

    assert_contains(scheduler_source, "return rawget(_G, 'UC_DEBUG_ACTION_TIMELINE') == true", "timeline logging must be default-off behind the global flag")
    assert_contains(scheduler_source, "data/logs/action_timeline_", "timeline logger must write under data/logs with per-character file names")
    assert_contains(scheduler_source, "SESSION_START", "timeline logger must emit a session/reload marker")

    local event_codes = {
        "TARGET_ACQUIRE_CANDIDATE",
        "TARGET_SELECTED",
        "TARGET_SELECT_SKIPPED_ALREADY_TARGETED",
        "TARGET_SELECT_BLOCKED",
        "TARGET_SELECT_DEBOUNCED",
        "ENGAGE_PROPOSED",
        "ENGAGE_PROPOSAL_CREATED",
        "ENGAGE_PROPOSAL_SKIPPED",
        "ENGAGE_PREEMPT_SELECTED",
        "ENGAGE_DISPATCH_ATTEMPT",
        "ENGAGE_DISPATCHED",
        "ENGAGE_DISPATCH_BLOCKED",
        "ENGAGE_DEBOUNCED",
        "ENGAGE_DUPLICATE_SUPPRESSED",
        "ENGAGE_DUPLICATE_ALLOWED_RETRY",
        "ENGAGE_DUPLICATE_RESET_TARGET_CHANGE",
        "ENGAGE_DUPLICATE_RESET_REJECTION",
        "ENGAGE_ACTION_STATE_BYPASS",
        "PENDING_ENGAGE_START",
        "PENDING_ENGAGE_CONFIRMED",
        "PENDING_ENGAGE_TIMEOUT",
        "PENDING_ENGAGE_REJECTED_WAIT_LONGER",
        "PENDING_ENGAGE_RETRY_READY",
        "PENDING_ENGAGE_RETRY_ATTEMPT",
        "PENDING_ENGAGE_CLEARED_INVALID_TARGET",
        "PENDING_ENGAGE_BLOCK_NONCRITICAL",
        "PENDING_ENGAGE_ALLOW_CRITICAL",
        "STALE_SPELL_LOCK_RELEASE",
        "STATUS_CHANGED",
        "CRITICAL_CURE_PROPOSED",
        "CRITICAL_CURE_DISPATCHED",
        "NONCRITICAL_CURE_PROPOSED",
        "NONCRITICAL_CURE_DISPATCHED",
        "MAINT_BUFF_PROPOSED",
        "MAINT_BUFF_DISPATCHED",
        "SLEEP_PROPOSED",
        "SLEEP_DISPATCHED",
        "SPELL_SENT",
        "SPELL_PACKET_START",
        "SPELL_SUCCESS",
        "SPELL_FAILURE",
        "SPELL_INTERRUPTED",
        "ACTION_STATE_BLOCK_ENGAGE",
        "ACTION_STATE_RELEASE",
        "POST_SPELL_TAIL_START",
        "POST_SPELL_TAIL_END",
    }
    for i = 1, #event_codes do
        assert_contains(scheduler_source .. action_state_source, event_codes[i], "missing expected timeline event code: " .. event_codes[i])
    end

    local blocker_codes = {
        "BLOCK_CRITICAL_CURE",
        "BLOCK_ACTION_STATE",
        "BLOCK_SPELL_CASTING",
        "BLOCK_POST_SPELL_TAIL",
        "BLOCK_DUPLICATE",
        "BLOCK_DEBOUNCE",
        "BLOCK_INVALID_TARGET",
        "BLOCK_ALREADY_ENGAGED",
        "BLOCK_PLAYER_DEAD",
        "BLOCK_UNKNOWN",
    }
    for i = 1, #blocker_codes do
        assert_contains(scheduler_source .. action_state_source, blocker_codes[i], "missing expected blocker reason code: " .. blocker_codes[i])
    end

    assert_contains(scheduler_source, "action_timeline_log('TARGET_SELECTED'", "enabled timeline logging must record target selected events")
    assert_contains(scheduler_source, "action_timeline_log('ENGAGE_PROPOSED'", "enabled timeline logging must record engage proposed events")
    assert_contains(scheduler_source, "p1_log_engage_proposal_probe('ENGAGE_PROPOSAL_CREATED'", "enabled timeline logging must record engage proposal creation probes")
    assert_contains(scheduler_source, "p1_log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED'", "enabled timeline logging must record engage proposal skip probes")
    assert_contains(scheduler_source, "action_timeline_log('ENGAGE_DISPATCHED'", "enabled timeline logging must record engage dispatched events")
    assert_contains(scheduler_source, "action_timeline_log('ENGAGE_DUPLICATE_SUPPRESSED'", "enabled timeline logging must record engage duplicate suppression events")
    assert_contains(action_state_source, "ENGAGE_ACTION_STATE_BYPASS", "enabled timeline logging must include explicit engage action-state bypass events")
    assert_contains(scheduler_source, "action_timeline_log('PENDING_ENGAGE_START'", "enabled timeline logging must record pending engage start events")
    assert_contains(scheduler_source, "action_timeline_log('PENDING_ENGAGE_REJECTED_WAIT_LONGER'", "enabled timeline logging must record engage rejection events")
    assert_contains(scheduler_source, "reason = 'pending_engage_retry_wait'", "enabled timeline logging must record retry-cadence engage holds")
    assert_contains(scheduler_source, "action_timeline_log('PENDING_ENGAGE_BLOCK_NONCRITICAL'", "enabled timeline logging must record pending engage block events")
    assert_contains(scheduler_source, "action_timeline_log('STALE_SPELL_LOCK_RELEASE'", "enabled timeline logging must record stale spell release events")
    assert_contains(scheduler_source, "'remaining_s'", "timeline field formatting must allow engage duplicate remaining debounce timing")
    assert_contains(scheduler_source, "'dispatch_method'", "timeline field formatting must allow engage dispatch-method annotations")
    assert_contains(scheduler_source, "'pending_engage'", "timeline field formatting must allow pending engage state annotations")
    assert_contains(scheduler_source, "'sent_for_target'", "timeline field formatting must allow sent-for-target engage annotations")
    assert_contains(scheduler_source, "'pull_owner'", "timeline field formatting must allow engage proposal pull-owner annotations")
    assert_contains(scheduler_source, "'claim_check'", "timeline field formatting must allow engage proposal claim annotations")
    assert_contains(scheduler_source, "'action_state'", "timeline field formatting must allow engage proposal action-state annotations")
    assert_contains(scheduler_source, "'top_family'", "timeline field formatting must allow engage proposal competing-top annotations")
    assert_contains(scheduler_source, "'immediate'", "timeline field formatting must allow immediate stale-release annotations")
    assert_contains(scheduler_source, "CRITICAL_CURE_DISPATCHED", "enabled timeline logging must classify critical Cure dispatch events")
    assert_contains(scheduler_source, "NONCRITICAL_CURE_DISPATCHED", "enabled timeline logging must classify non-critical Cure dispatch events")
    assert_contains(scheduler_source, "action_timeline_log('MAINT_BUFF_DISPATCHED'", "enabled timeline logging must record maintenance dispatch events")
    assert_contains(scheduler_source, "action_timeline_log('SLEEP_DISPATCHED'", "enabled timeline logging must record Sleep dispatch events")
    assert_contains(scheduler_source, "action_timeline_log('STATUS_CHANGED'", "enabled timeline logging must record status changes")

    assert_contains(scheduler_source, "local last_at = tonumber(scheduler.action_timeline_state.last_event_at[key]) or 0", "timeline logger must dedupe repeated identical events")
    assert_contains(action_state_source, "timeline_log('ACTION_STATE_BLOCK_ENGAGE'", "engage action-state blocker logging must be routed through the passive timeline callback")
    assert_contains(action_state_source, "timeline_log('ACTION_STATE_RELEASE'", "engage action-state release logging must be routed through the passive timeline callback")

    local helper_block = scheduler_source:match("function scheduler%.action_timeline_enabled%(%)" ..
        "(.-)\nlocal diag_init")
    assert_true(type(helper_block) == "string", "failed to capture timeline helper block")
    assert_not_contains(helper_block, "windower.send_command", "timeline helper must not introduce direct command side-effect calls")
    assert_not_contains(helper_block, "windower.ffxi.run", "timeline helper must not introduce direct run side-effect calls")

    local line = format_line(123.456, "Nyoourke", "ENGAGE_DISPATCHED", {
        tid = 123456,
        name = "Apex_Bat",
        command = "attack_on",
    })
    assert_equal(line, "123.456 | Nyoourke | ENGAGE_DISPATCHED | tid=123456 name=Apex_Bat command=attack_on", "timeline log output must stay compact and event-only")

    line = format_line(123.789, "Nyoourke", "ENGAGE_DUPLICATE_SUPPRESSED", {
        tid = 123456,
        name = "Apex_Bat",
        reason = "BLOCK_DUPLICATE",
        status = 0,
        age_s = "0.10",
        remaining_s = "0.20",
        dispatch_method = "attack_on",
        pending_engage = "active",
        sent_for_target = 1,
    })
    assert_equal(line, "123.789 | Nyoourke | ENGAGE_DUPLICATE_SUPPRESSED | tid=123456 name=Apex_Bat reason=BLOCK_DUPLICATE status=0 age_s=0.10 remaining_s=0.20 dispatch_method=attack_on pending_engage=active sent_for_target=1", "engage duplicate suppression lines must stay compact while carrying the new retry diagnostics")

    local emit = mock_rate_limited()
    local ok, emitted = emit(10.00, "ACTION_STATE_BLOCK_ENGAGE", "engage_block", 0.50)
    assert_equal(ok, true, "first blocker event should log")
    ok = emit(10.20, "ACTION_STATE_BLOCK_ENGAGE", "engage_block", 0.50)
    assert_equal(ok, false, "repeated identical blocker events should be rate-limited")
    ok, emitted = emit(10.55, "ACTION_STATE_BLOCK_ENGAGE", "engage_block", 0.50)
    assert_equal(ok, true, "rate-limited blocker events should log again after the interval")
    assert_equal(#emitted, 2, "rate-limited logging should keep output low-noise")

    io.stdout:write("selftest_action_economy_timeline_logging: OK\n")
end

main()
