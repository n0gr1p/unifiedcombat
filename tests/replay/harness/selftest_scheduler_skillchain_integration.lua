local function read_file(path)
	local handle, err = io.open(path, 'r')
	if not handle then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local text = handle:read('*a')
	handle:close()
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

local function assert_before(text, first, second, message)
	local first_at = text:find(first, 1, true)
	local second_at = text:find(second, 1, true)
	if not first_at or not second_at or first_at >= second_at then
		error(message or ('expected ordering: ' .. first .. ' before ' .. second))
	end
end

local function main()
	local state = read_file('uc_skillchain_state.lua')
	local core = read_file('unified_combat_core.lua')
	local scheduler = read_file('unified_scheduler.lua')
	local combat_provider = read_file('uc_provider_combat.lua')
	local dispatch_plan = read_file('uc_scheduler_dispatch_plan.lua')
	local entrypoint = read_file('UnifiedCombat.lua')
	local bridge = read_file('remote_bridge.lua')

	assert_contains(core, "local uc_skillchain_state = require('uc_skillchain_state')", 'core must use cohesive skillchain owner')
	assert_contains(core, "now = os.clock", 'core skillchain runtime must use the approved monotonic clock')
	assert_not_contains(core, 'ws_timer', 'global WS timer must not remain in scheduler-owned selection')
	assert_not_contains(core, 'step > 5', 'speculative chain-length cap must be removed')
	assert_contains(core, 'skillchain_runtime:observe_action_result({', 'packet results must feed target state')
	assert_contains(core, 'uc_skillchain_state.action_succeeded({', 'packet success mapping must use the tested state-owner contract')
	assert_contains(core, 'uc_skillchain_state.should_observe_action({', 'packet action-family mapping must use the tested state-owner contract')
	assert_contains(state, '[209] = 3.0', 'Wild Flourish must have an explicit source lifetime')
	assert_contains(state, '[320] = 60.0', 'Konzen-ittai must have an explicit source lifetime')
	assert_contains(state, "SC_CHAINBOUND_SOURCE_UNSUPPORTED", 'unknown Chainbound lifetimes must fail closed without a fallback window')
	assert_contains(core, 'uc_skillchain_state.chainbound_expires_at(action_id, skillchain_observed_at)', 'runtime must apply source-specific Chainbound expiry')
	assert_contains(core, 'local resource_action = res[resource] and res[resource][action_id]', 'propertyless and Chainbound actions must resolve resource names without skills metadata')
	assert_contains(core, 'function core.select_ws_plan_for_scheduler', 'structured scheduler wrapper must exist')
	assert_contains(core, "or ws_reason == 'SC_READY'", 'skillchain continuations must use the configured minimum TP')
	assert_contains(core, "elseif ws_reason == 'AM_READY' then", 'aftermath must retain an explicit TP policy')
	assert_contains(core, "or plan_reason == 'SC_NOT_READY'", 'not-yet-ready continuation plans must reserve the scheduler action lane')
	assert_contains(core, "or plan_reason == 'SC_DISPATCH_PENDING_RESULT'", 'dispatched continuations must reserve the action lane until their result')
	assert_contains(core, 'function core.revalidate_skillchain_plan', 'core atomic validator must exist')
	assert_contains(core, 'function core.reset_skillchain_state', 'state reset owner must exist')
	assert_contains(core, 'actor_has_diamond_aspis = actor_context.diamond_aspis', 'Diamond Aspis evidence must be actor-specific')
	assert_contains(core, 'aeonic_weapon_names_by_id', 'Aeonic equipment must be resolved for the acting player')
	assert_contains(core, 'or ws_actor_has_incapacitating_buff(player.buffs)', 'final commit must reject incapacitating WS-blocking buffs')
	assert_contains(core, "skillchain_runtime:clear_target(target_id, 'despawn_or_invalid')", 'runtime tick must prune dead, invalid, and despawned targets')
	assert_contains(core, "return 'CHIVALRY_READY'", 'ready Chivalry must reserve TP from competing WS proposals')
	assert_before(core, 'local chivalry_reason = chivalry_ws_reservation_reason(settings, player)', 'if resonance_active then', 'Chivalry maintenance must precede continuation planning')
	assert_before(core, 'local aftermath_ws, aftermath_reason = select_aftermath_maintenance_ws(settings, player)', 'if resonance_active then', 'aftermath maintenance must precede continuation planning')

	assert_contains(scheduler, 'combat_core.select_ws_plan_for_scheduler', 'scheduler must consume structured WS selection')
	assert_contains(combat_provider, 'skillchain_plan = skillchain_plan', 'proposal must carry skillchain plan')
	assert_contains(combat_provider, 'required_tp = required_tp', 'proposal must carry its explicit TP requirement')
	assert_contains(scheduler, 'if tp < required_tp then', 'dispatch must revalidate the proposal TP requirement')
	assert_contains(scheduler, 'scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION = 131', 'continuation band must be explicit')
	assert_contains(combat_provider, "or 'skillchain_continuation'", 'ready continuation reason must be explicit')
	assert_contains(combat_provider, "and 'skillchain_continuation_pending'", 'pending continuation reason must be explicit')
	assert_contains(combat_provider, "and 'skillchain_continuation_awaiting_result'", 'awaiting-result continuation reason must be explicit')
	assert_contains(combat_provider, "action_timeline_log('SC_CONTINUATION_PROPOSED'", 'proposal telemetry must include scheduler band')
	assert_contains(scheduler, "scheduler.action_timeline_log('SC_WS_DISPATCHED'", 'dispatch telemetry must exist')
	assert_contains(scheduler, 'selected.skillchain_plan)', 'atomic dispatch must carry the selected plan')
	assert_not_contains(scheduler, "source = 'unified_scheduler:T2.3d_darklaunch'", 'direct WS fallback dispatch must be removed')

	assert_contains(dispatch_plan, 'skillchain_plan = selected.skillchain_plan', 'dispatch plan must preserve structured continuation')
	assert_contains(dispatch_plan, 'combat_core.revalidate_skillchain_plan(', 'ranking commit must validate through core')
	assert_contains(dispatch_plan, "'rank_commit'", 'ranking validation telemetry stage must be explicit')
	assert_contains(core, "'dispatch_commit'", 'immediate pre-send validation telemetry stage must be explicit')
	assert_contains(core, "hooks.revalidate = function()", 'skillchain commit validation must be a dispatcher hook')
	assert_contains(core, "hooks.on_executed = function()", 'skillchain generation marking must be a dispatcher execution hook')
	assert_contains(core, "require('uc_scheduler_dispatcher').dispatch_intent({", 'skillchain WS must execute through the scheduler dispatcher')
	assert_not_contains(core, "windower.send_command('input /ws", 'skillchain WS must not retain direct command execution')
	assert_contains(state, 'commit_stage = type(context)', 'commit telemetry must distinguish rank and dispatch validation')
	assert_contains(core, 'skillchain_runtime:mark_plan_dispatched(skillchain_plan, os.clock())', 'successful send must reserve the dispatched resonance generation')
	assert_contains(state, "'SC_DISPATCH_PENDING_RESULT'", 'same resonance generation must not be dispatched twice')
	assert_contains(state, "return reject('SC_RESONANCE_CHANGED')", 'generation cancellation code must be stable')
	assert_contains(state, "return reject('SC_PROPERTIES_CHANGED')", 'property cancellation code must be stable')
	assert_contains(state, "return reject('SC_LATEST_SAFE_PASSED')", 'deadline cancellation code must be stable')
	assert_contains(state, 'now < (tonumber(plan.preferred_execute_at)', 'commit must preserve the conservative preferred dispatch buffer')
	assert_contains(state, "self:_emit('SC_PREDICTION_DISAGREEMENT'", 'server disagreement telemetry must exist')

	assert_contains(entrypoint, "UC_COMBAT_CORE.reset_skillchain_state('zone_change')", 'zone reset must be explicit')
	assert_contains(entrypoint, "_G.UC_StopUnifiedEngine('unload')", 'unload reset must be explicit')
	assert_contains(entrypoint, "_G.UC_StopUnifiedEngine('logout')", 'logout reset must be explicit')
	assert_contains(entrypoint, "_G.UC_StopUnifiedEngine('engine_stop')", 'command stop reset must be explicit')
	assert_contains(bridge, "_G.UC_StopUnifiedEngine('engine_stop')", 'remote stop reset must be explicit')

	io.stdout:write('selftest_scheduler_skillchain_integration: OK\n')
end

main()
