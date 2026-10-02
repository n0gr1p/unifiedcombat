local M = {}

local CHECK_INTERVAL_S = 0.50
local MISSING_LOG_INTERVAL_S = 15.0

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_provider_food requires function dependency: ' .. tostring(name))
	end
	return fn
end

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

function M.new(deps)
	deps = require_table(deps, 'uc_provider_food dependencies')
	local get_items = require_function(deps, 'get_items')
	local active_value_or_flat = require_function(deps, 'active_value_or_flat')
	local player_is_moving = require_function(deps, 'player_is_moving')
	local clamp_urgency = require_function(deps, 'clamp_urgency')
	local build_action_command = require_function(deps, 'build_action_command')
	local log = type(deps.log) == 'function' and deps.log or function() end
	local timeline_log = type(deps.action_timeline_log) == 'function' and deps.action_timeline_log or function() end
	local buff_resources = require_table(deps.buff_resources, 'uc_provider_food buff resources')
	local item_resources = require_table(deps.item_resources, 'uc_provider_food item resources')
	local priority_band = tonumber(deps.priority_band) or 50

	local state = {
		next_check_at = 0,
		next_missing_log_at = 0,
	}

	local function has_food_buff(player)
		if type(player) ~= 'table' or type(player.buffs) ~= 'table' then
			return false
		end
		for _, buff_id in ipairs(player.buffs) do
			local buff = buff_resources[tonumber(buff_id) or 0]
			if buff and tostring(buff.en or ''):lower() == 'food' then
				return true
			end
		end
		return false
	end

	local function inventory_has_item(item_name)
		local wanted = tostring(item_name or ''):lower()
		if wanted == '' then
			return false, 0
		end
		local inventory = get_items('Inventory')
		if type(inventory) ~= 'table' or inventory.enabled == false then
			return false, 0
		end
		local total = 0
		for _, row in ipairs(inventory) do
			local item_id = tonumber(row and row.id) or 0
			local count = tonumber(row and row.count) or 0
			local item = item_resources[item_id]
			if count > 0 and item and tostring(item.en or ''):lower() == wanted then
				total = total + count
			end
		end
		return total > 0, total
	end

	local provider = {}

	function provider.has_food_buff(player)
		return has_food_buff(player)
	end

	function provider.inventory_has_item(item_name)
		return inventory_has_item(item_name)
	end

	function provider.player_is_moving()
		return player_is_moving()
	end

	function provider.collect(ctx, out)
		ctx = require_table(ctx, 'food maintenance context')
		out = require_table(out, 'food maintenance proposal list')
		local now = tonumber(ctx.now) or 0
		if now < state.next_check_at then
			return
		end
		state.next_check_at = now + CHECK_INTERVAL_S

		local settings = type(ctx.settings) == 'table' and ctx.settings or {}
		local enabled = active_value_or_flat(
			'config.maintenance.food.enabled',
			settings.food_enabled
		)
		if enabled ~= true then
			return
		end
		local item_name = tostring(active_value_or_flat(
			'config.maintenance.food.item',
			settings.food_item
		) or ''):match('^%s*(.-)%s*
			return
		end
		local player = ctx.player
		if type(player) ~= 'table' or (tonumber(player.id) or 0) <= 0 then
			return
		end
		if has_food_buff(player) then
			return
		end
		if player_is_moving() then
			return
		end

		local available, count = inventory_has_item(item_name)
		if not available then
			if now >= state.next_missing_log_at then
				state.next_missing_log_at = now + MISSING_LOG_INTERVAL_S
				log(('FOOD_MAINT_REJECT item="%s" reason=ITEM_NOT_IN_INVENTORY'):format(item_name))
				timeline_log('FOOD_MAINT_MISSING_ITEM', {
					item = item_name,
					reason = 'ITEM_NOT_IN_INVENTORY',
				}, ('food_missing:%s'):format(item_name), MISSING_LOG_INTERVAL_S)
			end
			return
		end

		local player_id = tonumber(player.id) or 0
		local player_name = tostring(player.name or '')
		out[#out + 1] = {
			proposal_id = ('maint.food.%d'):format(math.floor(now * 1000)),
			family_id = 'maintenance.food',
			provider = 'maintenance_food',
			action_type = 'item',
			action_name = item_name,
			target_kind = 'self',
			target_id = player_id,
			target_name = player_name,
			priority_band = priority_band,
			urgency = clamp_urgency(0.10),
			starvation_eligible = true,
			created_at = now,
			expires_at = now + 0.40,
			commit_deadline = now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 0.0, los_required = false },
			recast_key = 'item:' .. item_name,
			duplicate_suppression_key = 'maint:food:' .. item_name,
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'food_buff',
			sticky = true,
			can_preempt_movement = false,
			can_preempt_same_band = false,
			reason_code = 'food_missing',
			detail = {
				food_item = item_name,
				inventory_count = count,
			},
			legacy_command = build_action_command(item_name, 'item', {
				id = player_id,
				name = player_name,
				is_self = true,
			}),
		}
		timeline_log('FOOD_MAINT_PROPOSED', {
			item = item_name,
			count = count,
			band = priority_band,
		}, ('food_proposed:%s'):format(item_name), 0.50)
	end

	return provider
end

return M
)
		if item_name == '' then
			return
		end
		local player = ctx.player
		if type(player) ~= 'table' or (tonumber(player.id) or 0) <= 0 then
			return
		end
		if has_food_buff(player) then
			return
		end
		if player_is_moving() then
			return
		end

		local available, count = inventory_has_item(item_name)
		if not available then
			if now >= state.next_missing_log_at then
				state.next_missing_log_at = now + MISSING_LOG_INTERVAL_S
				log(('FOOD_MAINT_REJECT item="%s" reason=ITEM_NOT_IN_INVENTORY'):format(item_name))
				timeline_log('FOOD_MAINT_MISSING_ITEM', {
					item = item_name,
					reason = 'ITEM_NOT_IN_INVENTORY',
				}, ('food_missing:%s'):format(item_name), MISSING_LOG_INTERVAL_S)
			end
			return
		end

		local player_id = tonumber(player.id) or 0
		local player_name = tostring(player.name or '')
		out[#out + 1] = {
			proposal_id = ('maint.food.%d'):format(math.floor(now * 1000)),
			family_id = 'maintenance.food',
			provider = 'maintenance_food',
			action_type = 'item',
			action_name = item_name,
			target_kind = 'self',
			target_id = player_id,
			target_name = player_name,
			priority_band = priority_band,
			urgency = clamp_urgency(0.10),
			starvation_eligible = true,
			created_at = now,
			expires_at = now + 0.40,
			commit_deadline = now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 0.0, los_required = false },
			recast_key = 'item:' .. item_name,
			duplicate_suppression_key = 'maint:food:' .. item_name,
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'food_buff',
			sticky = true,
			can_preempt_movement = false,
			can_preempt_same_band = false,
			reason_code = 'food_missing',
			detail = {
				food_item = item_name,
				inventory_count = count,
			},
			legacy_command = build_action_command(item_name, 'item', {
				id = player_id,
				name = player_name,
				is_self = true,
			}),
		}
		timeline_log('FOOD_MAINT_PROPOSED', {
			item = item_name,
			count = count,
			band = priority_band,
		}, ('food_proposed:%s'):format(item_name), 0.50)
	end

	return provider
end

return M
)
		if item_name == '' then
			return
		end
		local player = ctx.player
		if type(player) ~= 'table' or (tonumber(player.id) or 0) <= 0 then
			return
		end
		if has_food_buff(player) then
			return
		end
		if player_is_moving() then
			return
		end

		local available, count = inventory_has_item(item_name)
		if not available then
			if now >= state.next_missing_log_at then
				state.next_missing_log_at = now + MISSING_LOG_INTERVAL_S
				log(('FOOD_MAINT_REJECT item="%s" reason=ITEM_NOT_IN_INVENTORY'):format(item_name))
				timeline_log('FOOD_MAINT_MISSING_ITEM', {
					item = item_name,
					reason = 'ITEM_NOT_IN_INVENTORY',
				}, ('food_missing:%s'):format(item_name), MISSING_LOG_INTERVAL_S)
			end
			return
		end

		local player_id = tonumber(player.id) or 0
		local player_name = tostring(player.name or '')
		out[#out + 1] = {
			proposal_id = ('maint.food.%d'):format(math.floor(now * 1000)),
			family_id = 'maintenance.food',
			provider = 'maintenance_food',
			action_type = 'item',
			action_name = item_name,
			target_kind = 'self',
			target_id = player_id,
			target_name = player_name,
			priority_band = priority_band,
			urgency = clamp_urgency(0.10),
			starvation_eligible = true,
			created_at = now,
			expires_at = now + 0.40,
			commit_deadline = now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 0.0, los_required = false },
			recast_key = 'item:' .. item_name,
			duplicate_suppression_key = 'maint:food:' .. item_name,
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'food_buff',
			sticky = true,
			can_preempt_movement = false,
			can_preempt_same_band = false,
			reason_code = 'food_missing',
			detail = {
				food_item = item_name,
				inventory_count = count,
			},
			legacy_command = build_action_command(item_name, 'item', {
				id = player_id,
				name = player_name,
				is_self = true,
			}),
		}
		timeline_log('FOOD_MAINT_PROPOSED', {
			item = item_name,
			count = count,
			band = priority_band,
		}, ('food_proposed:%s'):format(item_name), 0.50)
	end

	return provider
end

return M
)
		if item_name == '' then
			return
		end
		local player = ctx.player
		if type(player) ~= 'table' or (tonumber(player.id) or 0) <= 0 then
			return
		end
		if has_food_buff(player) then
			return
		end
		if player_is_moving() then
			return
		end

		local available, count = inventory_has_item(item_name)
		if not available then
			if now >= state.next_missing_log_at then
				state.next_missing_log_at = now + MISSING_LOG_INTERVAL_S
				log(('FOOD_MAINT_REJECT item="%s" reason=ITEM_NOT_IN_INVENTORY'):format(item_name))
				timeline_log('FOOD_MAINT_MISSING_ITEM', {
					item = item_name,
					reason = 'ITEM_NOT_IN_INVENTORY',
				}, ('food_missing:%s'):format(item_name), MISSING_LOG_INTERVAL_S)
			end
			return
		end

		local player_id = tonumber(player.id) or 0
		local player_name = tostring(player.name or '')
		out[#out + 1] = {
			proposal_id = ('maint.food.%d'):format(math.floor(now * 1000)),
			family_id = 'maintenance.food',
			provider = 'maintenance_food',
			action_type = 'item',
			action_name = item_name,
			target_kind = 'self',
			target_id = player_id,
			target_name = player_name,
			priority_band = priority_band,
			urgency = clamp_urgency(0.10),
			starvation_eligible = true,
			created_at = now,
			expires_at = now + 0.40,
			commit_deadline = now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 0.0, los_required = false },
			recast_key = 'item:' .. item_name,
			duplicate_suppression_key = 'maint:food:' .. item_name,
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'food_buff',
			sticky = true,
			can_preempt_movement = false,
			can_preempt_same_band = false,
			reason_code = 'food_missing',
			detail = {
				food_item = item_name,
				inventory_count = count,
			},
			legacy_command = build_action_command(item_name, 'item', {
				id = player_id,
				name = player_name,
				is_self = true,
			}),
		}
		timeline_log('FOOD_MAINT_PROPOSED', {
			item = item_name,
			count = count,
			band = priority_band,
		}, ('food_proposed:%s'):format(item_name), 0.50)
	end

	return provider
end

return M
