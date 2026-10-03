local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(('uc_provider_target_control %s must be a table'):format(name))
	end
	return value
end

local function require_function(deps, name)
	local value = deps[name]
	if type(value) ~= 'function' then
		error(('uc_provider_target_control deps.%s must be a function'):format(name))
	end
	return value
end

local function require_number(deps, name)
	local value = tonumber(deps[name])
	if value == nil then
		error(('uc_provider_target_control deps.%s must be numeric'):format(name))
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'deps')
	local bool_setting = require_function(deps, 'bool_setting')
	local combat_autotarget = require_function(deps, 'combat_autotarget')
	local combat_domain_enabled = require_function(deps, 'combat_domain_enabled')
	local tank_enabled = require_function(deps, 'tank_enabled')
	local select_target = require_function(deps, 'select_target')
	local add_control_enabled = require_function(deps, 'add_control_enabled')
	local select_pull = require_function(deps, 'select_pull')
	local action_timeline_log = require_function(deps, 'action_timeline_log')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local tank_target_priority = require_number(deps, 'tank_target_priority')
	local tank_target_urgency = require_number(deps, 'tank_target_urgency')
	local death_switch_priority = require_number(deps, 'death_switch_priority')
	local death_switch_urgency = require_number(deps, 'death_switch_urgency')

	local provider = {}

	function provider.collect_target(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		if not bool_setting(combat_autotarget(ctx.config), false) then
			return
		end
		local player = ctx.player
		if ctx.player_present ~= true then
			return
		end
		local engaged = tonumber(player.status) == 1
		local add_control_retarget = engaged and add_control_enabled(ctx.settings, ctx.config)
		local pick = select_target(ctx.settings, ctx.config)
		if type(pick) ~= 'table' then
			return
		end
		local death_switch = pick.death_switch == true
		local death_switch_incumbent_id = tonumber(pick.death_switch_incumbent_id) or 0
		if death_switch and death_switch_incumbent_id <= 0 then
			error('uc_provider_target_control death-switch pick requires death_switch_incumbent_id')
		end
		-- While engaged, only explicit Add Control or the core's death-aware handoff may retarget.
		if engaged and not add_control_retarget and not death_switch then
			return
		end
		local tid = tonumber(pick.target_id) or 0
		if tid <= 0 then
			return
		end
		local tank_mode = bool_setting(tank_enabled(ctx.settings), false)
		local priority_band = death_switch and death_switch_priority or (tank_mode and tank_target_priority or 84)
		local urgency = death_switch and death_switch_urgency or (tank_mode and tank_target_urgency or 0.55)
		local cur = ctx.target_present == true and ctx.target or nil
		if cur and tonumber(cur.id) == tid then
			action_timeline_log('TARGET_SELECT_SKIPPED_ALREADY_TARGETED', {
				tid = tid,
				name = tostring(pick.target_name or ''),
			}, ('target_already:%d'):format(tid), 0.50)
			return
		end
		action_timeline_log(death_switch and 'TARGET_DEATH_SWITCH_CANDIDATE' or 'TARGET_ACQUIRE_CANDIDATE', {
			tid = tid,
			name = tostring(pick.target_name or ''),
			band = priority_band,
			urgency = ('%.2f'):format(clamp_urgency(urgency)),
		}, ('target_candidate:%d'):format(tid), 0.50)
		out[#out + 1] = {
			proposal_id = death_switch
				and ('target.death_switch.%d.%d.%d'):format(death_switch_incumbent_id, tid, math.floor(ctx.now * 1000))
				or ('target.acquire.%d.%d'):format(tid, math.floor(ctx.now * 1000)),
			family_id = 'target.acquire.primary',
			provider = 'target_control',
			action_type = 'target',
			action_name = death_switch and 'death_switch' or 'acquire_target',
			target_kind = 'mob',
			target_id = tid,
			target_name = tostring(pick.target_name or ''),
			priority_band = priority_band,
			urgency = clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.35,
			commit_deadline = ctx.now + 0.25,
			movement_policy = 'can_move',
			range_policy = { min = 0.0, max = 50.0, los_required = false },
			recast_key = ('target:%d'):format(tid),
			duplicate_suppression_key = death_switch
				and ('target.death_switch:%d:%d'):format(death_switch_incumbent_id, tid)
				or ('target.acquire:%d'):format(tid),
			lock_class = 'target_control',
			expected_ack = 'target_set',
			expected_effect = 'target_selected',
			sticky = true,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = death_switch and 'death_switch' or 'acquire_candidate',
			detail = {
				hpp = tonumber(pick.hpp) or 0,
				add_control_retarget = add_control_retarget and not death_switch,
				death_switch = death_switch,
				death_switch_incumbent_id = death_switch_incumbent_id,
			},
			required_setting = 'autotarget',
		}
	end

	function provider.collect_pull(ctx, out)
		require_table(ctx, 'ctx')
		require_table(out, 'out')
		if not bool_setting(rawget(_G, 'Start_Engine'), false) then
			return
		end
		if not bool_setting(combat_domain_enabled(), false) then
			return
		end
		if not bool_setting(combat_autotarget(ctx.config), false) then
			return
		end
		local pick = select_pull(ctx.settings)
		if type(pick) ~= 'table' then
			return
		end
		local tid = tonumber(pick.target_id) or 0
		local aname = tostring(pick.action_name or '')
		local atype = tostring(pick.action_type or '')
		if tid <= 0 or aname == '' or (atype ~= 'spell' and atype ~= 'ja') then
			return
		end
		local urgency = (pick.in_range == true) and 0.92 or 0.75
		out[#out + 1] = {
			proposal_id = ('pull.%s.%s.%d.%d'):format(atype, aname, tid, math.floor(ctx.now * 1000)),
			family_id = 'combat.pull.primary',
			provider = 'pull_control',
			action_type = 'pull',
			action_name = aname,
			target_kind = 'mob',
			target_id = tid,
			target_name = tostring(pick.target_name or ''),
			priority_band = 82,
			urgency = clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = ctx.now,
			expires_at = ctx.now + 0.30,
			commit_deadline = ctx.now + 0.20,
			movement_policy = 'requires_range',
			range_policy = { min = 0.0, max = tonumber(pick.range_max) or 20.0, los_required = false },
			recast_key = ('pull:%s:%s'):format(atype, aname),
			duplicate_suppression_key = ('pull:%s:%s:%d'):format(atype, aname, tid),
			lock_class = 'offense_action',
			expected_ack = 'action_start',
			expected_effect = 'pull_action',
			sticky = true,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = (pick.in_range == true) and 'pull_ready' or 'pull_move_into_range',
			detail = {
				action_type = atype,
				dist = tonumber(pick.dist) or 999,
				range_max = tonumber(pick.range_max) or 0,
				in_range = pick.in_range == true,
			},
			required_setting = 'autotarget',
		}
	end

	return provider
end

return M
