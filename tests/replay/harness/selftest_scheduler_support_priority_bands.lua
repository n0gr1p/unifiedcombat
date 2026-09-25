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
    local sleep_waker_provider = read_file("uc_provider_sleep_waker.lua")
    local maintenance_provider = read_file("uc_provider_maintenance.lua")
    local proposals_source = read_file("uc_scheduler_proposals.lua")
    local ranker_source = read_file("uc_scheduler_ranker.lua")

    assert_contains(source, "scheduler.PRIORITY_BAND_AFTERMATH_WS = 108", "aftermath priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION = 131", "skillchain continuation priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SLEEP = 142", "Sleep priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_GEO_MAINTENANCE = 210", "GEO maintenance priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_SLEEP_WAKE = 149", "Sleep waker priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_GEO_CREATION = 240", "GEO creation priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_CRITICAL_CURE = 250", "critical Cure priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_BRD_MAINTENANCE = 200", "Bard maintenance priority band mismatch")
	assert_contains(source, "scheduler.PRIORITY_BAND_SCH_ROUTINE = 75", "Scholar routine priority band mismatch")
	assert_contains(source, "scheduler.PRIORITY_BAND_SCH_PREPARED = 150", "Scholar prepared priority band mismatch")
    assert_contains(source, "scheduler.PRIORITY_BAND_ENGAGE_BYPASS = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "engage bypass threshold must begin at skillchain continuation")

    assert_true(score(250, 0.00) > score(240, 1.00), "critical Cure must beat maximum GEO creation urgency")
    assert_true(score(240, 1.00) > score(210, 1.00),
        "missing-Luopan creation must beat maximum routine GEO maintenance urgency")
    assert_true(score(240, 0.00) > score(225, 1.00), "GEO creation must beat maximum camp-pull recovery urgency")
    assert_true(score(210, 0.00) > score(200, 1.00), "GEO maintenance must beat maximum Bard maintenance urgency")
    assert_true(score(210, 0.00) > score(150, 1.00), "GEO maintenance must beat maximum prepared Scholar urgency")
    assert_true(score(210, 0.00) > score(149, 1.00), "GEO maintenance must beat maximum Sleep-wake urgency")
    assert_true(score(210, 0.00) > score(142, 1.00), "GEO maintenance must beat maximum Sleep urgency")
    assert_true(score(142, 0.55) > score(131, 1.00), "minimum Sleep urgency must beat maximum skillchain urgency")
    assert_true(score(250, 0.00) > score(200, 1.00), "critical Cure must beat maximum Bard maintenance urgency")
    assert_true(score(200, 0.00) > score(142, 1.00), "minimum Bard maintenance urgency must beat maximum Sleep urgency")
    assert_true(score(200, 0.00) > score(131, 1.00), "minimum Bard maintenance urgency must beat maximum skillchain urgency")
	assert_true(score(250, 0.70) > score(150, 0.95),
		"critical Cure must beat prepared Scholar completion")
	assert_true(score(150, 0.95) > score(149, 1.00),
		"prepared Scholar completion must beat other urgent support")
	assert_true(score(75, 0.70) < score(108, 0.00),
		"new routine Scholar maintenance must remain below ordinary offense bands")

    assert_contains(source, "brd_maintenance_priority = scheduler.PRIORITY_BAND_BRD_MAINTENANCE", "scheduler must inject the global Bard band")
    assert_contains(source, "geo_maintenance_priority = scheduler.PRIORITY_BAND_GEO_MAINTENANCE", "scheduler must inject the global GEO maintenance band")
    assert_contains(source, "geo_creation_priority = scheduler.PRIORITY_BAND_GEO_CREATION", "scheduler must inject the GEO creation band")
	assert_contains(source, "routine_priority = scheduler.PRIORITY_BAND_SCH_ROUTINE",
		"scheduler must inject the Scholar routine band")
	assert_contains(source, "prepared_priority = scheduler.PRIORITY_BAND_SCH_PREPARED",
		"scheduler must inject the Scholar prepared band")
	assert_contains(source, "function scheduler.p1_dispatch_maintenance_sch(selected, settings)",
		"scheduler must own Scholar live dispatch")
	assert_contains(source, "scheduler.providers.sch_maintenance.note_dispatched(",
		"Scholar dispatch must enter the runtime pending transaction")
	assert_contains(source, "if main_job == 'SCH' then\n\t\t\tctx.sch_defensive_evidence_current",
		"Scholar provider collection must be gated before charge decoding on non-SCH jobs")
	assert_contains(source, "if provider == 'maintenance_sch' or provider == 'defensive_sch' then",
		"scheduler arbitration must route Scholar proposals")
    assert_contains(source, "critical_cure_priority = scheduler.PRIORITY_BAND_CRITICAL_CURE", "scheduler must inject the global Cure band")
    assert_contains(source, "priority_band = scheduler.PRIORITY_BAND_SLEEP_WAKE", "scheduler must inject the global Sleep-wake band")
    assert_contains(source, "sleep_priority = scheduler.PRIORITY_BAND_SLEEP", "scheduler must inject the global Sleep band")
    assert_contains(source, "aftermath_priority = scheduler.PRIORITY_BAND_AFTERMATH_WS", "scheduler must inject the global aftermath band")
    assert_contains(source, "skillchain_priority = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION", "scheduler must inject the global continuation band")
    assert_contains(maintenance_provider, "brd_maintenance_priority,", "Bard emitter must pass the injected global Bard band")
    assert_contains(defensive_provider, "priority_band = critical_cure_priority", "critical Cure emitters must use the injected global Cure band")
    assert_contains(sleep_waker_provider, "priority_band = priority_band", "Sleep-wake emitter must use the injected global Sleep-wake band")
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
    assert_contains(source, "and (brd_provider_active or sch_fast_tick_active",
        "BRD provider must be collected every scheduler tick")
    assert_contains(source, "local geo_fast_tick_active = maintenance_enabled",
        "missing-Luopan recovery must have a dedicated scheduler fast-tick gate")
    assert_contains(source, "scheduler.providers.geo_maintenance.requires_fast_tick(ctx)",
        "scheduler must ask the GEO provider whether missing-Luopan recovery needs 5 Hz collection")
    assert_contains(source, "if not geo_provider_collected",
        "scheduler must avoid duplicate GEO collection on ordinary maintenance ticks")
    local geo_fast_block = source:match(
        "if not geo_provider_collected(.-)if not sch_provider_collected"
    )
    assert_true(type(geo_fast_block) == "string",
        "failed to capture GEO fast-tick collection block")
    assert_contains(geo_fast_block, "and geo_fast_tick_active then",
        "GEO fast pass must be conditional on missing-Luopan recovery")
    assert_contains(geo_fast_block, "scheduler.providers.geo_maintenance.collect(ctx, out)",
        "GEO fast pass must recollect the missing-Luopan proposal every scheduler tick")
    assert_not_contains(geo_fast_block, "scheduler.providers.maintenance.collect(ctx, out)",
        "GEO recovery fast pass must not accelerate generic maintenance")
    assert_not_contains(geo_fast_block, "scheduler.providers.summoner_maintenance.collect(ctx, out)",
        "GEO recovery fast pass must not accelerate Summoner maintenance")
    assert_contains(source, "and (require('uc_sch_runtime').requires_fast_tick()",
        "active Scholar sequences must be collected every scheduler tick")
    assert_contains(source, "or scheduler.providers.sch_maintenance.trace_active())",
        "armed Scholar evidence capture must be collected every scheduler tick")
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
	assert_contains(source, "local sch_lane = require('uc_sch_runtime').lane_status()",
		"scheduler collection must consult authoritative Scholar sequence state")
	assert_contains(source, "local decision = sch_lane_policy.decide(",
		"scheduler collection must apply selective Scholar lane policy")
	assert_contains(source, "proposal._sch_lane_preempt_reason = decision.reason",
		"eligible emergency proposals must carry Scholar preemption intent to dispatch")
	assert_contains(source, "SCH_DEFENSIVE_PARITY provider=%s type=%s action=\"%s\"",
		"Scholar diagnostics must identify unchanged existing cure and status-removal proposals")
	assert_contains(source, "source=existing_defensive",
		"Scholar defensive comparison diagnostics must name the existing defensive source")
	assert_contains(source, "function scheduler.sch_sublimation_safety(ctx, proposals)",
		"Scholar Sublimation must derive safety from the current scheduler proposal set")
	assert_contains(source, "ctx.sch_defensive_evidence_current = defensive_evidence_current",
		"Scholar Sublimation safety must know whether defensive proposals were refreshed this tick")
	assert_contains(source, "defensive_evidence_current = ctx.sch_defensive_evidence_current",
		"Scholar Sublimation safety must fail closed on stale defensive proposal evidence")
	assert_contains(source, "player_doom_present = player_has_doom(ctx.player)",
		"Scholar Sublimation safety must reuse the existing Doom observation")
	assert_contains(source, "return scheduler.p1_is_critical_defensive_proposal(ctx.settings, proposal)",
		"Scholar Sublimation safety must reuse the established critical-cure classifier")
	assert_contains(source, "get_sublimation_safety = scheduler.sch_sublimation_safety",
		"Scholar provider must receive the scheduler-owned safety evidence boundary")
	assert_contains(source, "get_sublimation_release_mechanics = require('uc_sch_sublimation').production_release_mechanics",
		"Scholar provider must retain the explicit production-unknown release-capacity gate")
	assert_before(source, "local function p1_collect_proposals(ctx)", "SCH_DEFENSIVE_PARITY provider=%s",
		"Scholar defensive comparison diagnostics must remain inside scheduler proposal collection")
	assert_before(source, "SCH_DEFENSIVE_PARITY provider=%s", "local sch_lane_policy = require('uc_sch_lane_policy')",
		"Scholar defensive comparison diagnostics must observe the existing proposal before lane filtering")
	assert_contains(source, "require('uc_sch_runtime').preempt(\n\t\t\t\tsch_preempt_reason,",
		"selected emergency dispatch must abort Scholar state before provider dispatch")
	assert_before(source, "'doom_emergency_preemption'", "local doom_holy_water_command",
		"Doom must abort Scholar state before Holy Water command construction and dispatch")
	assert_contains(source, "local _, brd_action_event = require('uc_brd_maintenance').on_action(act, player_id, observed_at)",
		"scheduler action handling must receive Bard modifier confirmation events")
	assert_contains(source, "if brd_action_event == 'pianissimo_confirmed' then",
		"confirmed Pianissimo must enter the scheduler action-state completion path")
	assert_contains(source, "action_mark_packet_end({\n\t\t\t\tmessage_id = tonumber(act.category) or 0,",
		"confirmed Pianissimo must release the active JA lock while preserving normal cooldown")
	assert_contains(source, "scheduler.p1_pending_mark_complete(observed_at, 'brd_pianissimo_action')",
		"confirmed Pianissimo must complete its scheduler pending record before the reserved song")
	assert_contains(source, "local critical_cure = scheduler.p1_is_critical_defensive_proposal(",
		"an atomic GEO sequence must continue admitting scheduler-classified critical cures")
	assert_contains(source, "local allowed = critical_cure",
		"the GEO atomic lane must preserve critical-Cure proposals")

	local process_tick = source:match("function scheduler%.process_tick%(cadence%)(.-)function scheduler%.on_ipc_message")
    assert_true(type(process_tick) == "string", "failed to capture scheduler process_tick")
    assert_contains(process_tick, "local defensive_domain_enabled = domain_ownership.is_enabled('defensive')",
        "process_tick must enforce defensive domain enablement")
	assert_contains(process_tick, "require('uc_sch_runtime').cancel('maintenance_domain_disabled', now_s(), 0)",
		"maintenance domain disablement must abort an active Scholar sequence")
	assert_contains(process_tick, "scheduler.providers.geo_maintenance.creation_preempts_pull(geo_creation_ctx)",
		"ready Luopan recovery must be checked before camp-pull lane acquisition")
	assert_contains(process_tick, "scheduler.providers.camp_puller.reset('PULL_PREEMPTED_FOR_GEO_CREATION')",
		"ready Luopan recovery must abort an active pull journey")
	assert_contains(process_tick, "and not geo_creation_preempts_pull then",
		"ready Luopan recovery must prevent a new pull journey")
	assert_contains(source, "if ctx.geo_creation_preempts_pull ~= true then\n\t\t\tscheduler.providers.camp_puller.collect(ctx, out)",
		"ready Luopan recovery must suppress collection-time pull acquisition")
    assert_before(process_tick, "try_doom_water_emergency(s)", "scheduler.dispatch_selected_plan(s)",
        "Doom must remain the sole hard prepass ahead of Bard scheduler arbitration")
    assert_contains(process_tick, "if not brd_lane_reserved and not camp_lane_reserved and not sch_lane_holds then\n\t\tlocal target_ctx = nil",
        "Bard, Scholar, and camp-puller lanes must hold nonblocking target acquisition")
    assert_contains(process_tick, "scheduler.p1_try_nonblocking_target_acquire(s, target_ctx)",
        "Bard lane target acquisition must use the tick-stable context")
    assert_contains(process_tick, "if camp_lane_reserved or (not brd_lane_reserved and not sch_lane_holds) then\n\t\tmove_acted, move_reason = run_movement_coordinator_tick()",
        "Bard and Scholar must hold movement coordination while camp-puller ownership retains its movement path")
	assert_contains(process_tick, "scheduler.apply_sch_lane_movement(sch_lane.reason, now_s())",
		"Scholar lane reservation must actively stop movement")
	assert_contains(process_tick, "return true, 'BLOCK_SCH_ACTION_LANE:' .. sch_lane.reason",
		"Scholar lane reservation must report an explicit scheduler hold")
    assert_not_contains(process_tick, "try_internal_defensive_action()",
        "process_tick must not retain legacy internal defensive fallback execution")
    assert_not_contains(process_tick, "try_delegate_healbot()",
        "process_tick must not retain legacy HealBot fallback execution")
    assert_not_contains(process_tick, "scheduler_dark_launch_defensive",
        "process_tick must not branch on the compatibility-only defensive marker")

    io.stdout:write("selftest_scheduler_support_priority_bands: OK\n")
end

main()
