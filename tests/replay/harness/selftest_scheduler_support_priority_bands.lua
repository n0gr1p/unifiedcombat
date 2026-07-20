local scheduler_path = "unified_scheduler.lua"

local function read_file(path)
    local fh, err = io.open(path, "r")
    if not fh then
        error("failed to open " .. tostring(path) .. ": " .. tostring(err))
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

local function assert_before(text, first, second, message)
    local first_pos = text:find(first, 1, true)
    local second_pos = text:find(second, 1, true)
    if not first_pos or not second_pos or first_pos >= second_pos then
        error(message or ("expected " .. first .. " before " .. second))
    end
end

local function score(priority_band, urgency)
    return priority_band + urgency * 9.9
end

local function main()
    local source = read_file(scheduler_path)

    assert_contains(source, "scheduler.PRIORITY_BAND_AFTERMATH_WS = 108", "aftermath priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION = 131", "skillchain continuation priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SLEEP = 142", "Sleep priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_CRITICAL_CURE = 153", "critical Cure priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_BRD_MAINTENANCE = 120", "Bard maintenance priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_ENGAGE_BYPASS = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "engage bypass threshold must begin at skillchain continuation")

    assert_true(score(153, 0.70) > score(142, 1.00), "critical Cure must beat maximum Sleep urgency")
    assert_true(score(142, 0.55) > score(131, 1.00), "minimum Sleep urgency must beat maximum skillchain urgency")
    assert_true(score(131, 0.00) > score(120, 1.00), "minimum skillchain urgency must beat maximum Bard maintenance urgency")
    assert_true(score(120, 0.00) > score(108, 1.00), "minimum Bard maintenance urgency must beat maximum aftermath WS urgency")

    assert_contains(source, "scheduler.PRIORITY_BAND_BRD_MAINTENANCE,", "Bard emitter must pass the global Bard band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_CRITICAL_CURE", "critical Cure emitters must use the global Cure band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_SLEEP", "Sleep emitter must use the global Sleep band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_AFTERMATH_WS", "aftermath emitter must use the global aftermath band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "skillchain emitter must use the global continuation band")

    local bypass = source:match("function scheduler%.p1_priority_bypasses_engage%(proposal%)(.-)\nend")
    assert_true(type(bypass) == "string", "failed to capture engage bypass helper")
    assert_contains(bypass, "proposal.priority_band >= scheduler.PRIORITY_BAND_ENGAGE_BYPASS", "engage bypass must use the global band threshold")
    assert_not_contains(bypass, "main_job", "engage bypass must not inspect job identity")
    assert_not_contains(bypass, "provider", "engage bypass must not special-case providers")

    assert_contains(source, "elseif not scheduler.p1_priority_bypasses_engage(p) then", "pending engage must admit globally high-priority bands")
    assert_contains(source, "if scheduler.p1_priority_bypasses_engage(top) then", "engage preemption must preserve globally high-priority bands")

    assert_contains(source, "local brd_provider_active = main_job ~= 'COR' and (main_job == 'BRD' or sub_job == 'BRD')",
        "BRD provider cadence must use the same job eligibility as maintenance collection")
    assert_contains(source, "if brd_provider_active or ctx.now >= (tonumber(s._sched_next_maintenance_at) or 0) then",
        "BRD provider must be collected every scheduler tick")
    assert_contains(source, "scheduler.PRIORITY_BAND_BRD_MAINTENANCE,\n\t\t\t\t0,",
        "BRD proposal emission must not consume a speculative throttle")

    local lane_policy = source:match("function scheduler%.p1_brd_lane_blocks_proposal%(proposal, lane_reserved%)(.-)\nend")
    assert_true(type(lane_policy) == "string", "failed to capture BRD action-lane policy")
    assert_contains(lane_policy, "provider or '') == 'maintenance_brd'", "BRD proposals must remain eligible during lane reservation")
    assert_contains(lane_policy, "action_type == 'spell' or action_type == 'ja' or action_type == 'ws'",
        "BRD lane reservation must hold lower-priority action proposals")
    assert_not_contains(lane_policy, "action_type == 'move'", "BRD lane reservation must not block movement")
    assert_not_contains(lane_policy, "action_type == 'target'", "BRD lane reservation must not block targeting")
    assert_contains(source, "local lane_reserved, lane_reason = require('uc_brd_maintenance').action_lane_status()",
        "scheduler collection must consult authoritative BRD sequence state")

    local process_tick = source:match("function scheduler%.process_tick%(cadence%)(.-)function scheduler%.on_ipc_message")
    assert_true(type(process_tick) == "string", "failed to capture scheduler process_tick")
    assert_contains(process_tick, "'config.ownership.scheduler_dark_launch_defensive'",
        "process_tick must enforce defensive scheduler ownership before legacy dispatch")
    assert_contains(process_tick, "if scheduler_owns_defensive then",
        "scheduler-owned defensive work must not fall through to the legacy direct executor")
    assert_contains(process_tick, "DEF_SKIP reason=SCHEDULER_OWNS_DEFENSIVE",
        "defensive ownership skip must remain observable in defensive diagnostics")
    assert_before(process_tick, "if scheduler_owns_defensive then", "acted, reason = try_internal_defensive_action()",
        "defensive ownership guard must precede the direct internal defensive executor")
    assert_before(process_tick, "if scheduler_owns_defensive then", "acted, reason = try_delegate_healbot()",
        "defensive ownership guard must precede the direct Healbot executor")

    io.stdout:write("selftest_scheduler_support_priority_bands: OK\n")
end

main()
