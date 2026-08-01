local function read(path)
	local file = assert(io.open(path, 'r'))
	local text = file:read('*a')
	file:close()
	return text
end

local function assert_contains(text, needle, message)
	if not text:find(needle, 1, true) then
		error(message or ('missing expected text: ' .. needle))
	end
end

local function assert_not_contains(text, needle, message)
	if text:find(needle, 1, true) then
		error(message or ('unexpected text present: ' .. needle))
	end
end

local function main()
	local addon = read('UnifiedCombat.lua')
	local engine = read('unified_engine.lua')
	local scheduler = read('unified_scheduler.lua')
	local core = read('unified_combat_core.lua')
	local normalizer = read('uc_config_normalizer.lua')
	local active_config = read('uc_active_config.lua')
	local contract = read('uc_profile_contract.lua')
	local domain_ownership = read('uc_domain_ownership.lua')
	local scheduler_config = read('uc_scheduler_config.lua')
	local pending_record = read('uc_scheduler_pending_record.lua')
	local ui_constants = read('UnifiedCombatWinForms/HubUiConstants.cs')
	local ui = read('UnifiedCombatWinForms/MainForm.ParityUi.cs')
	local writer = read('UnifiedCombatWinForms/StructuredProfileV2Writer.cs')

	for _, source in ipairs({
		addon,
		engine,
		scheduler,
		core,
		normalizer,
		active_config,
		contract,
		domain_ownership,
		scheduler_config,
		ui_constants,
		ui,
		writer,
	}) do
		assert_not_contains(source, 'scheduler_dark_launch_',
			'Phase 6 runtime/UI/profile schema must not retain obsolete ownership markers')
	end

	assert_not_contains(addon, 'UC_CoreCombatTickOnce', 'legacy core tick global must be removed')
	assert_not_contains(addon, 'UC_ENABLE_LEGACY_JOB_ADAPTERS',
		'unused legacy job-adapter global must be removed')
	assert_not_contains(addon, "register_event('status change'",
		'empty legacy status-change event hook must be removed')
	assert_not_contains(core, 'combat_tick_once', 'legacy core tick entrypoint must be removed')
	assert_not_contains(core, 'run_unified_combat', 'legacy core combat loop must be removed')
	assert_not_contains(core, 'legacy_pull_executor', 'legacy pull executor must be removed')
	assert_not_contains(core, 'legacy_movement_executor', 'legacy movement executor must be removed')
	assert_not_contains(core, 'windower.send_command(', 'core must not directly execute commands')
	assert_not_contains(core, 'windower.ffxi.run(', 'core must not directly execute movement')
	assert_not_contains(core, 'windower.ffxi.turn(', 'core must not directly execute turns')
	assert_not_contains(core, 'uc_settarget.select_by_id(', 'core must not directly select targets')
	assert_not_contains(core, 'uc_attack.engage_target(', 'core must not directly engage')
	assert_not_contains(core, 'uc_attack.switch_target(', 'core must not directly switch targets')
	assert_not_contains(core, 'uc_attack.disengage(', 'core must not directly disengage')
	assert_not_contains(core, "require('uc_settarget')", 'core must not retain unused target-executor import')
	assert_not_contains(core, "require('uc_attack')", 'core must not retain unused attack-executor import')
	assert_not_contains(core, "require('uc_ws_gate')", 'core must not retain unused WS-gate import')
	assert_contains(scheduler,
		"require('lor/lor_packets') -- initializes _libs.lor.packets for lazy lor/lor_actor loading",
		'scheduler must retain the explicit require-time packet initialization contract')
	assert_not_contains(scheduler, "require('json')", 'scheduler must not retain unused JSON import')

	assert_not_contains(scheduler, 'local function try_internal_defensive_action()',
		'scheduler-local defensive fallback must be removed')
	assert_not_contains(scheduler, 'local function try_delegate_healbot()',
		'scheduler-local HealBot fallback must be removed')
	assert_not_contains(scheduler, 'p1_try_dark_launch_dispatch',
		'active scheduler dispatch must not retain dark-launch naming')
	assert_not_contains(scheduler, 'p1_try_dark_launch_combat_dispatch',
		'active combat dispatch must not retain dark-launch naming')
	assert_not_contains(scheduler, 'p1_record_legacy_dispatch',
		'active pending-ledger helper must not retain legacy-dispatch naming')
	assert_not_contains(pending_record, 'p1_record_legacy_dispatch',
		'pending-ledger module must not retain legacy-dispatch naming')
	assert_contains(scheduler, 'function scheduler.dispatch_selected_plan(settings)',
		'scheduler must expose the scheduler-only selected-plan dispatcher')
	assert_contains(scheduler, 'local function p1_dispatch_combat(selected, settings, phase)',
		'scheduler must retain the active combat dispatcher')
	assert_contains(scheduler, 'function scheduler.record_dispatch(ctx)',
		'scheduler must expose the active pending-ledger dispatch recorder')
	assert_contains(pending_record, 'function M.record_dispatch(scheduler, ctx, p1_number)',
		'pending-ledger module must expose the active dispatch recorder')

	-- Phase 6 RFC condition: validation/debug globals stay until a bridge or UI
	-- replacement exists. Their names are historical, but their live payloads
	-- remain part of the current diagnostic contract.
	assert_contains(scheduler, '_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE',
		'dispatcher validation diagnostics must remain until replaced')

	io.stdout:write('selftest_phase6_cleanup: OK\n')
end

main()
