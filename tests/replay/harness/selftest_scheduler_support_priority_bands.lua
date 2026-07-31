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
    local combat_provider = read_file("uc_provider_combat.lua")
    local defensive_provider = read_file("uc_provider_defensive.lua")
    local maintenance_provider = read_file("uc_provider_maintenance.lua")
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

    assert_contains(source, "brd_maintenance_priority = scheduler.PRIORITY_BAND_BRD_MAINTENANCE", "scheduler must inject the global Bard band")
    assert_contains(source, "critical_cure_priority = scheduler.PRIORITY_BAND_CRITICAL_CURE", "scheduler must inject the global Cure band")
    assert_contains(source, "sleep_priority = scheduler.PRIORITY_BAND_SLEEP", "scheduler must inject the global Sleep band")
    assert_contains(source, "aftermath_priority = scheduler.PRIORITY_BAND_AFTERMATH_WS", "scheduler must inject the global aftermath band")
    assert_contains(source, "skillchain_priority = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "scheduler must inject the global continuation band")
    assert_contains(maintenance_provider, "brd_maintenance_priority,", "Bard emitter must pass the injected global Bard band")
    assert_contains(defensive_provider, "priority_band = critical_cure_priority", "critical Cure emitters must use the injected global Cure band")
    assert_contains(combat_provider, "priority_band = sleep_priority", "Sleep emitter must use the injected global Sleep band")
    assert_contains(combat_provider, "priority_band = aftermath_priority", "aftermath emitter must use the injected global aftermath band")
    assert_contains(combat_provider, "priority_band = skillchain_priority", "skillchain emitter must use the injected global continuation band")

    local bypass = source:match("function scheduler%.p1_priority_bypasses_engage%(proposal%)(.-)\nend")
    assert_true(type(bypass) == "string", "failed to capture engage bypass helper")
    assert_contains(bypass, "scheduler.PRIORITY_BAND_ENGAGE_BYPASS", "engage bypass wrapper must pass the global band threshold")
    assert_not_contains(bypass, "main_job", "engage bypass must not inspect job identity")
    assert_not_contains(bypass, "provider", "engage bypass must not special-case providers")
    assert_contains(proposals_source, "proposal.priority_band >= engage_bypass_band", "proposal helper must apply the injected band threshold")

    assert_contains(ranker_source, "elseif not require_function(deps, 'priority_bypasses_engage')(proposal) then", "pending engage must admit globally high-priority bands")
    assert_contains(source, "if scheduler.p1_priority_bypasses_engage(top) then", "engage preemption must preserve globally high-priority bands")

    assert_contains(source, "and main_job ~= 'COR'",
        "BRD provider cadence must use the same job eligibility as maintenance collection")
    assert_contains(source, "and (brd_provider_active or ctx.now >= (tonumber(s._sched_next_maintenance_at) or 0)) then",
        "BRD provider must be collected every scheduler tick")
    assert_contains(maintenance_provider, "brd_maintenance_priority,\n\t\t\t\t\t0,",
        "BRD proposal emission must not consume a speculative throttle")

    local lane_policy = source:match("function scheduler%.p1_brd_lane_blocks_proposal%(proposal, lane_reserved%)(.-)\nend")
    assert_true(type(lane_policy) == "string", "failed to capture BRD action-lane policy")
    assert_contains(lane_policy, "provider or '') == 'maintenance_brd'", "BRD proposals must remain eligible during lane reservation")
    assert_contains(lane_policy, "return true", "BRD lane reservation must hold every competing proposal")
    assert_not_contains(lane_policy, "priority_band", "BRD lane reservation must not admit a competing action based on priority")
    assert_not_contains(lane_policy, "action_type", "BRD lane reservation must not exempt movement, targeting, or engage proposals")
	local camp_lane_policy = source:match("function scheduler%.p1_camp_lane_blocks_proposal%(proposal, lane_reserved%)(.-)\nend")
	assert_true(type(camp_lane_policy) == "string", "failed to capture camp-puller action-lane policy")
	assert_contains(camp_lane_policy, "provider or '') ~= 'camp_puller'",
		"camp-puller proposals must be the only proposals eligible during an active journey")
	assert_not_contains(camp_lane_policy, "priority_band",
		"camp-puller action-lane ownership must not admit competing actions based on priority")
	assert_not_contains(camp_lane_policy, "action_type",
		"camp-puller action-lane ownership must cover actions, targeting, engage, and movement")
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
    assert_contains(process_tick, "local defensive_domain_enabled = domain_ownership.is_enabled('defensive')",
        "process_tick must enforce defensive domain enablement")
    assert_before(process_tick, "try_doom_water_emergency(s)", "scheduler.dispatch_selected_plan(s)",
        "Doom must remain the sole hard prepass ahead of Bard scheduler arbitration")
    assert_contains(process_tick, "if not brd_lane_reserved and not camp_lane_reserved then\n\t\tlocal target_ctx = nil",
        "Bard and camp-puller lanes must hold nonblocking target acquisition")
    assert_contains(process_tick, "scheduler.p1_try_nonblocking_target_acquire(s, target_ctx)",
        "Bard lane target acquisition must use the tick-stable context")
    assert_contains(process_tick, "if camp_lane_reserved or not brd_lane_reserved then\n\t\tmove_acted, move_reason = run_movement_coordinator_tick()",
        "Bard must hold movement coordination while camp-puller ownership retains its movement path")
    assert_not_contains(process_tick, "try_internal_defensive_action()",
        "process_tick must not retain legacy internal defensive fallback execution")
    assert_not_contains(process_tick, "try_delegate_healbot()",
        "process_tick must not retain legacy HealBot fallback execution")
    assert_not_contains(process_tick, "scheduler_dark_launch_defensive",
        "process_tick must not branch on the compatibility-only defensive marker")

    io.stdout:write("selftest_scheduler_support_priority_bands: OK\n")
end

main()
