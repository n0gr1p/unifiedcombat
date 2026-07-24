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
    local proposals_source = read_file("uc_scheduler_proposals.lua")
    local ranker_source = read_file("uc_scheduler_ranker.lua")

    assert_contains(source, "scheduler.PRIORITY_BAND_AFTERMATH_WS = 108", "aftermath priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION = 131", "skillchain continuation priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SLEEP = 142", "Sleep priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_CRITICAL_CURE = 153", "critical Cure priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_BRD_MAINTENANCE = 200", "Bard maintenance priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_ENGAGE_BYPASS = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "engage bypass threshold must begin at skillchain continuation")

    assert_true(score(153, 0.70) > score(142, 1.00), "critical Cure must beat maximum Sleep urgency")
    assert_true(score(142, 0.55) > score(131, 1.00), "minimum Sleep urgency must beat maximum skillchain urgency")
    assert_true(score(200, 0.00) > score(153, 1.00), "minimum Bard maintenance urgency must beat maximum critical Cure urgency")
    assert_true(score(200, 0.00) > score(142, 1.00), "minimum Bard maintenance urgency must beat maximum Sleep urgency")
    assert_true(score(200, 0.00) > score(131, 1.00), "minimum Bard maintenance urgency must beat maximum skillchain urgency")

    assert_contains(source, "scheduler.PRIORITY_BAND_BRD_MAINTENANCE,", "Bard emitter must pass the global Bard band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_CRITICAL_CURE", "critical Cure emitters must use the global Cure band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_SLEEP", "Sleep emitter must use the global Sleep band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_AFTERMATH_WS", "aftermath emitter must use the global aftermath band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "skillchain emitter must use the global continuation band")

    local bypass = source:match("function scheduler%.p1_priority_bypasses_engage%(proposal%)(.-)\nend")
    assert_true(type(bypass) == "string", "failed to capture engage bypass helper")
    assert_contains(bypass, "scheduler.PRIORITY_BAND_ENGAGE_BYPASS", "engage bypass wrapper must pass the global band threshold")
    assert_not_contains(bypass, "main_job", "engage bypass must not inspect job identity")
    assert_not_contains(bypass, "provider", "engage bypass must not special-case providers")
    assert_contains(proposals_source, "proposal.priority_band >= engage_bypass_band", "proposal helper must apply the injected band threshold")

    assert_contains(ranker_source, "elseif not require_function(deps, 'priority_bypasses_engage')(proposal) then", "pending engage must admit globally high-priority bands")
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
    assert_contains(lane_policy, "return true", "BRD lane reservation must hold every competing proposal")
    assert_not_contains(lane_policy, "priority_band", "BRD lane reservation must not admit a competing action based on priority")
    assert_not_contains(lane_policy, "action_type", "BRD lane reservation must not exempt movement, targeting, or engage proposals")
	assert_contains(source, "local lane_reserved, lane_reason = require('uc_brd_maintenance').action_lane_status()",
		"scheduler collection must consult authoritative BRD sequence state")
	assert_contains(source, "local _, brd_action_event = require('uc_brd_maintenance').on_action(act, player_id, observed_at)",
		"scheduler action handling must receive Bard modifier confirmation events")
	assert_contains(source, "if brd_action_event == 'pianissimo_confirmed' then",
		"confirmed Pianissimo must enter the scheduler action-state completion path")
	assert_contains(source, "action_mark_packet_end({\n\t\t\t\tmessage_id = tonumber(act.category) or 0,",
		"confirmed Pianissimo must release the active JA lock while preserving normal cooldown")
	assert_contains(source, "scheduler.p1_pending_mark_complete(observed_at, 'brd_pianissimo_action')",
		"confirmed Pianissimo must complete its scheduler pending record before the reserved song")

	local process_tick = source:match("function scheduler%.process_tick%(cadence%)(.-)function scheduler%.on_ipc_message")
    assert_true(type(process_tick) == "string", "failed to capture scheduler process_tick")
    assert_contains(process_tick, "'config.ownership.scheduler_dark_launch_defensive'",
        "process_tick must enforce defensive scheduler ownership before legacy dispatch")
    assert_before(process_tick, "try_doom_water_emergency(s)", "scheduler.p1_try_dark_launch_dispatch(s)",
        "Doom must remain the sole hard prepass ahead of Bard scheduler arbitration")
    assert_contains(process_tick, "if not brd_lane_reserved then\n\t\tlocal target_ctx = nil",
        "Bard lane must hold nonblocking target acquisition")
    assert_contains(process_tick, "scheduler.p1_try_nonblocking_target_acquire(s, target_ctx)",
        "Bard lane target acquisition must use the tick-stable context")
    assert_contains(process_tick, "if not brd_lane_reserved then\n\t\tmove_acted, move_reason = run_movement_coordinator_tick()",
        "Bard lane must hold movement coordination")
    assert_before(process_tick, "if brd_lane_reserved then\n\t\t_G.UC_LAST_SCHED_ACTION = '[p1]brd_lane_hold'", "try_internal_defensive_action()",
        "Bard lane hold must prevent legacy defensive execution")
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
