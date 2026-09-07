local res = require('resources')
local uc_active_config = require('uc_active_config')

local M = {}

local locks = {}
local last_active_target_id = 0
local watch_cache_signature = nil
local watch_cache_set = {}
local watch_cache_names = {}
local watch_cache_unresolved = {}
local last_transition = 'none'
local RUN_AWAY_STOP_TOLERANCE = 0.15
local MOVE_TO_RANGE_TOLERANCE = 0.15
local POSITION_EPSILON = 0.000001

local function response_owns_movement(response)
	return response == 'run_away' or response == 'move_to_range'
end

local function trim(value)
	if type(value) ~= 'string' then
		return ''
	end
	return value:match('^%s*(.-)%s*$') or ''
end

local function canonical(value)
	return trim(value):lower()
end

local function configured()
	local configured_rules = {}
	local config = uc_active_config.get_path('config.reactions')
	if type(config) == 'table' and config.enabled == true then
		if type(config.rules) ~= 'table' then
			error('enabled config.reactions requires rules')
		end
		for i = 1, #config.rules do
			configured_rules[#configured_rules + 1] = config.rules[i]
		end
	end
	local encounter = uc_active_config.get_path('config.encounter')
	if type(encounter) == 'table' and encounter.enabled == true and encounter.id == 'kei' then
		if type(encounter.kei) ~= 'table' or type(encounter.kei.fullers) ~= 'table' then
			error('enabled Kei encounter requires Fullers reaction configuration')
		end
		local distance = encounter.kei.fullers.target_distance
		if type(distance) ~= 'number' or distance <= 0 then
			error('Kei Fullers target distance must be positive')
		end
		configured_rules[#configured_rules + 1] = {
			trigger = 'ability_window',
			name = 'Dancing Fullers',
			response = 'move_to_range',
			distance = distance,
		}
	end
	return #configured_rules > 0, configured_rules
end

local function rule_signature(rules)
	local parts = {}
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == 'table' then
			parts[#parts + 1] = table.concat({
				tostring(rule.trigger or ''),
				tostring(rule.name or ''),
				tostring(rule.response or ''),
				tostring(rule.distance or ''),
			}, '\031')
		end
	end
	return table.concat(parts, '\030')
end

local function refresh_effect_watch_cache(rules)
	local signature = rule_signature(rules)
	if signature == watch_cache_signature then
		return
	end
	watch_cache_signature = signature
	watch_cache_set = {}
	watch_cache_names = {}
	watch_cache_unresolved = {}

	local requested = {}
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == 'table' and rule.trigger == 'enemy_buff' then
			local name = trim(rule.name)
			if name ~= '' then
				requested[canonical(name)] = name
			end
		end
	end
	local resolved = {}
	for id, buff in pairs(res.buffs or {}) do
		local name = trim(buff and buff.en)
		local key = canonical(name)
		if requested[key] ~= nil then
			local effect_id = tonumber(id) or 0
			if effect_id > 0 then
				watch_cache_set[effect_id] = true
				watch_cache_names[effect_id] = requested[key]
				resolved[key] = true
			end
		end
	end
	for key, name in pairs(requested) do
		if resolved[key] ~= true then
			watch_cache_unresolved[#watch_cache_unresolved + 1] = name
		end
	end
	table.sort(watch_cache_unresolved)
end

local function lock_key(trigger, actor_id, name)
	return table.concat({ tostring(trigger), tostring(actor_id), canonical(name) }, ':')
end

local function copy_lock(lock)
	if type(lock) ~= 'table' then
		return nil
	end
	local out = {}
	for key, value in pairs(lock) do
		out[key] = value
	end
	return out
end

local function actor_has_lock(actor_id)
	local id = tonumber(actor_id) or 0
	for _, lock in pairs(locks) do
		if tonumber(lock.actor_id) == id then
			return true
		end
	end
	return false
end

local function first_lock_for_actor(actor_id)
	local id = tonumber(actor_id) or 0
	local best = nil
	for _, lock in pairs(locks) do
		if tonumber(lock.actor_id) == id then
			local lock_rule = tonumber(lock.rule_index) or 9999
			local best_rule = best and (tonumber(best.rule_index) or 9999) or 9999
			if best == nil or lock_rule < best_rule or (lock_rule == best_rule and tostring(lock.key) < tostring(best.key)) then
				best = lock
			end
		end
	end
	return best
end

local function select_active_lock()
	local active = first_lock_for_actor(last_active_target_id)
	if active then
		return active
	end
	local best = nil
	for _, lock in pairs(locks) do
		local lock_rule = tonumber(lock.rule_index) or 9999
		local best_rule = best and (tonumber(best.rule_index) or 9999) or 9999
		local lock_started = tonumber(lock.started_at) or 0
		local best_started = best and (tonumber(best.started_at) or 0) or 0
		if best == nil
			or lock_rule < best_rule
			or (lock_rule == best_rule and lock_started > best_started)
			or (lock_rule == best_rule and lock_started == best_started and tostring(lock.key) < tostring(best.key)) then
			best = lock
		end
	end
	if best then
		last_active_target_id = tonumber(best.actor_id) or 0
	end
	return best
end

local function matching_rule(rules, trigger, name)
	local wanted = canonical(name)
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == 'table' and rule.trigger == trigger and canonical(rule.name) == wanted then
			return rule, i
		end
	end
	return nil, nil
end

local function prune_unconfigured_locks(rules)
	for key, lock in pairs(locks) do
		local rule = matching_rule(rules, lock.trigger, lock.name)
		local configured_distance = rule and tonumber(rule.distance) or nil
		local active_distance = tonumber(lock.distance)
		if rule == nil
			or rule.response ~= lock.response
			or (response_owns_movement(lock.response) and configured_distance ~= active_distance) then
			locks[key] = nil
		end
	end
end

local function ability_name_from_action(act, category)
	local ability_id = 0
	if category == 7 then
		local target = type(act.targets) == 'table' and act.targets[1] or nil
		local action = target and type(target.actions) == 'table' and target.actions[1] or nil
		ability_id = tonumber(action and action.param) or 0
	elseif category == 11 then
		ability_id = tonumber(act.param) or 0
	end
	local ability = ability_id > 0 and res.monster_abilities and res.monster_abilities[ability_id] or nil
	return trim(ability and ability.en), ability_id
end

local function clear_other_ability_windows(actor_id, keep_key)
	local id = tonumber(actor_id) or 0
	local released = nil
	for key, lock in pairs(locks) do
		if key ~= keep_key and lock.trigger == 'ability_window' and tonumber(lock.actor_id) == id then
			if released == nil then
				released = copy_lock(lock)
			end
			locks[key] = nil
		end
	end
	return released
end

function M.effect_watch_set()
	local enabled, rules = configured()
	if not enabled then
		return {}
	end
	refresh_effect_watch_cache(rules)
	local out = {}
	for effect_id in pairs(watch_cache_set) do
		out[effect_id] = true
	end
	return out
end

function M.on_action(act, current_target_id, now, actor_is_valid_enemy)
	local result = {}
	local enabled, rules = configured()
	if not enabled then
		local released = M.reset('config_disabled')
		result.released_target_id = released
		return result
	end
	if type(act) ~= 'table' then
		return result
	end
	local category = tonumber(act.category) or 0
	if category ~= 7 and category ~= 11 then
		return result
	end
	local actor_id = tonumber(act.actor_id) or 0
	local ability_name, ability_id = ability_name_from_action(act, category)
	if actor_id <= 0 or ability_name == '' then
		return result
	end
	local key = lock_key('ability_window', actor_id, ability_name)
	if category == 7 then
		if actor_is_valid_enemy ~= true then
			return result
		end
		local rule, rule_index = matching_rule(rules, 'ability_window', ability_name)
		if not rule then
			return result
		end
		result.released = clear_other_ability_windows(actor_id, key)
		locks[key] = {
			key = key,
			trigger = 'ability_window',
			name = trim(rule.name),
			response = rule.response,
			actor_id = actor_id,
			ability_id = ability_id,
			started_at = tonumber(now) or 0,
			rule_index = rule_index,
			turn_applied = false,
		}
		if response_owns_movement(rule.response) then
			locks[key].distance = rule.distance
			if rule.response == 'run_away' then
				locks[key].run_away_phase = 'pending'
			else
				locks[key].move_to_range_phase = 'pending'
			end
			locks[key].current_distance = nil
		end
		last_active_target_id = actor_id
		last_transition = 'ready:' .. ability_name
		result.activated = copy_lock(locks[key])
		return result
	end

	if locks[key] ~= nil then
		result.released = copy_lock(locks[key])
		locks[key] = nil
		last_transition = 'complete:' .. ability_name
		if last_active_target_id == actor_id then
			last_active_target_id = 0
			local replacement = select_active_lock()
			if replacement then
				replacement.turn_applied = false
				result.activated = copy_lock(replacement)
			else
				result.released_target_id = actor_id
			end
		end
	end
	return result
end

function M.evaluate(current_target_id, effects, now)
	local target_id = tonumber(current_target_id) or 0
	local enabled, rules = configured()
	if not enabled then
		local released = M.reset('config_disabled')
		return nil, released
	end
	refresh_effect_watch_cache(rules)

	local previously_active_actor_id = last_active_target_id
	prune_unconfigured_locks(rules)
	for key, lock in pairs(locks) do
		if lock.trigger == 'enemy_buff' and tonumber(lock.actor_id) ~= target_id then
			locks[key] = nil
		end
	end

	local active_effects = {}
	for i = 1, #(effects or {}) do
		local effect_id = tonumber(effects[i] and effects[i].effect_id) or 0
		if watch_cache_set[effect_id] == true then
			active_effects[effect_id] = true
		end
	end
	for key, lock in pairs(locks) do
		if lock.trigger == 'enemy_buff' and active_effects[tonumber(lock.effect_id) or 0] ~= true then
			locks[key] = nil
		end
	end
	for effect_id in pairs(active_effects) do
		local name = watch_cache_names[effect_id]
		local rule, rule_index = matching_rule(rules, 'enemy_buff', name)
		if rule and target_id > 0 then
			local key = lock_key('enemy_buff', target_id, name)
			if locks[key] == nil then
				locks[key] = {
					key = key,
					trigger = 'enemy_buff',
					name = trim(rule.name),
					response = rule.response,
					actor_id = target_id,
					effect_id = effect_id,
					started_at = tonumber(now) or 0,
					rule_index = rule_index,
					turn_applied = false,
				}
				last_transition = 'effect_gain:' .. name
			end
		end
	end

	if not actor_has_lock(last_active_target_id) then
		last_active_target_id = 0
	end
	local active = select_active_lock()
	local released_target_id = nil
	if active then
		local active_actor_id = tonumber(active.actor_id) or 0
		if previously_active_actor_id > 0 and active_actor_id ~= previously_active_actor_id then
			active.turn_applied = false
		end
	elseif previously_active_actor_id > 0 then
		released_target_id = previously_active_actor_id
		last_transition = 'released'
	end
	return copy_lock(active), released_target_id
end

function M.mark_turn_applied(key)
	local lock = locks[tostring(key or '')]
	if type(lock) == 'table' then
		lock.turn_applied = true
		return true
	end
	return false
end

local function lock_response(lock)
	if type(lock) ~= 'table' then
		return ''
	end
	local response = tostring(lock.response or '')
	if response ~= 'turn_away'
		and response ~= 'stop_attacking'
		and response ~= 'run_away'
		and response ~= 'move_to_range' then
		error('uc_reaction_runtime received unsupported reaction response: ' .. response)
	end
	return response
end

function M.blocks_movement(lock)
	local response = lock_response(lock)
	return response == 'turn_away' or response_owns_movement(response)
end

function M.owns_movement(lock)
	if type(lock) ~= 'table' then
		return false
	end
	return response_owns_movement(lock_response(lock))
end

local function finite_coordinate(value)
	local number = tonumber(value)
	if number == nil or number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	return number
end

local function set_run_away_phase(lock, phase, current_distance)
	local changed = lock.run_away_phase ~= phase
	lock.run_away_phase = phase
	lock.current_distance = current_distance
	if changed then
		last_transition = ('run_away:%s:%s'):format(phase, lock.name)
	end
	return changed
end

function M.run_away_request(lock_value, me_value, enemy_value)
	if lock_response(lock_value) ~= 'run_away' then
		error('run-away movement requires a run_away reaction lock')
	end
	local key = tostring(lock_value.key or '')
	local lock = locks[key]
	if type(lock) ~= 'table' then
		error('run-away movement requires an active authoritative reaction lock')
	end
	local target_distance = tonumber(lock.distance)
	if target_distance == nil or target_distance <= 0 then
		error('active run-away reaction requires a positive target distance')
	end
	if lock.run_away_phase == 'reached' then
		return {
			kind = 'hold',
			reason = 'REACTION_RUN_AWAY_REACHED',
			target_distance = target_distance,
			current_distance = lock.current_distance,
			phase_changed = false,
		}
	end
	local me_x = type(me_value) == 'table' and finite_coordinate(me_value.x) or nil
	local me_y = type(me_value) == 'table' and finite_coordinate(me_value.y) or nil
	local enemy_x = type(enemy_value) == 'table' and finite_coordinate(enemy_value.x) or nil
	local enemy_y = type(enemy_value) == 'table' and finite_coordinate(enemy_value.y) or nil
	if me_x == nil or me_y == nil or enemy_x == nil or enemy_y == nil then
		local phase_changed = set_run_away_phase(lock, 'position_unavailable', nil)
		return {
			kind = phase_changed and 'stop' or 'hold',
			reason = 'REACTION_RUN_AWAY_POSITION_UNAVAILABLE',
			target_distance = target_distance,
			current_distance = nil,
			phase_changed = phase_changed,
		}
	end
	local dx = me_x - enemy_x
	local dy = me_y - enemy_y
	local current_distance = math.sqrt(dx * dx + dy * dy)
	if current_distance >= target_distance - RUN_AWAY_STOP_TOLERANCE then
		return {
			kind = 'stop',
			reason = 'REACTION_RUN_AWAY_REACHED',
			target_distance = target_distance,
			current_distance = current_distance,
			phase_changed = set_run_away_phase(lock, 'reached', current_distance),
		}
	end
	if current_distance <= POSITION_EPSILON then
		local phase_changed = set_run_away_phase(lock, 'zero_vector', current_distance)
		return {
			kind = phase_changed and 'stop' or 'hold',
			reason = 'REACTION_RUN_AWAY_ZERO_VECTOR',
			target_distance = target_distance,
			current_distance = current_distance,
			phase_changed = phase_changed,
		}
	end
	return {
		kind = 'run',
		reason = 'REACTION_RUN_AWAY_MOVING',
		run_x = dx / current_distance,
		run_y = dy / current_distance,
		target_distance = target_distance,
		current_distance = current_distance,
		phase_changed = set_run_away_phase(lock, 'moving', current_distance),
	}
end

local function set_move_to_range_phase(lock, phase, current_distance)
	local changed = lock.move_to_range_phase ~= phase
	lock.move_to_range_phase = phase
	lock.current_distance = current_distance
	if changed then
		last_transition = ('move_to_range:%s:%s'):format(phase, lock.name)
	end
	return changed
end

function M.move_to_range_request(lock_value, me_value, enemy_value)
	if lock_response(lock_value) ~= 'move_to_range' then
		error('move-to-range movement requires a move_to_range reaction lock')
	end
	local key = tostring(lock_value.key or '')
	local lock = locks[key]
	if type(lock) ~= 'table' then
		error('move-to-range movement requires an active authoritative reaction lock')
	end
	local target_distance = tonumber(lock.distance)
	if target_distance == nil or target_distance <= 0 then
		error('active move-to-range reaction requires a positive target distance')
	end
	local me_x = type(me_value) == 'table' and finite_coordinate(me_value.x) or nil
	local me_y = type(me_value) == 'table' and finite_coordinate(me_value.y) or nil
	local enemy_x = type(enemy_value) == 'table' and finite_coordinate(enemy_value.x) or nil
	local enemy_y = type(enemy_value) == 'table' and finite_coordinate(enemy_value.y) or nil
	if me_x == nil or me_y == nil or enemy_x == nil or enemy_y == nil then
		local phase_changed = set_move_to_range_phase(lock, 'position_unavailable', nil)
		return {
			kind = phase_changed and 'stop' or 'hold',
			reason = 'REACTION_MOVE_TO_RANGE_POSITION_UNAVAILABLE',
			target_distance = target_distance,
			current_distance = nil,
			phase_changed = phase_changed,
		}
	end
	local dx = me_x - enemy_x
	local dy = me_y - enemy_y
	local current_distance = math.sqrt(dx * dx + dy * dy)
	if math.abs(current_distance - target_distance) <= MOVE_TO_RANGE_TOLERANCE then
		local phase_changed = set_move_to_range_phase(lock, 'holding', current_distance)
		return {
			kind = phase_changed and 'stop' or 'hold',
			reason = 'REACTION_MOVE_TO_RANGE_REACHED',
			target_distance = target_distance,
			current_distance = current_distance,
			phase_changed = phase_changed,
		}
	end
	if current_distance <= POSITION_EPSILON then
		local phase_changed = set_move_to_range_phase(lock, 'zero_vector', current_distance)
		return {
			kind = phase_changed and 'stop' or 'hold',
			reason = 'REACTION_MOVE_TO_RANGE_ZERO_VECTOR',
			target_distance = target_distance,
			current_distance = current_distance,
			phase_changed = phase_changed,
		}
	end
	if current_distance < target_distance then
		return {
			kind = 'run',
			reason = 'REACTION_MOVE_TO_RANGE_MOVING_OUTWARD',
			run_x = dx / current_distance,
			run_y = dy / current_distance,
			target_distance = target_distance,
			current_distance = current_distance,
			phase_changed = set_move_to_range_phase(lock, 'moving_outward', current_distance),
		}
	end
	return {
		kind = 'run',
		reason = 'REACTION_MOVE_TO_RANGE_MOVING_INWARD',
		run_x = -dx / current_distance,
		run_y = -dy / current_distance,
		target_distance = target_distance,
		current_distance = current_distance,
		phase_changed = set_move_to_range_phase(lock, 'moving_inward', current_distance),
	}
end

function M.cancel(key_value, reason)
	local key = tostring(key_value or '')
	local released = locks[key]
	if type(released) ~= 'table' then
		return nil, copy_lock(select_active_lock())
	end
	locks[key] = nil
	if tonumber(released.actor_id) == last_active_target_id then
		last_active_target_id = 0
	end
	last_transition = 'cancel:' .. tostring(reason or 'manual') .. ':' .. released.name
	return copy_lock(released), copy_lock(select_active_lock())
end

function M.requires_disengage(lock, player_status)
	return lock_response(lock) == 'stop_attacking' and tonumber(player_status) == 1
end

function M.blocks_proposal(lock, proposal)
	if type(lock) ~= 'table' or type(proposal) ~= 'table' then
		return false
	end
	local response = lock_response(lock)
	local provider = tostring(proposal.provider or '')
	local action_type = tostring(proposal.action_type or '')
	local target_kind = tostring(proposal.target_kind or '')
	local family_id = tostring(proposal.family_id or '')
	local reason_code = tostring(proposal.reason_code or '')
	if response == 'stop_attacking' then
		if reason_code == 'enemy_buff_remove'
			and provider == 'defensive_internal'
			and action_type == 'spell'
			and target_kind == 'mob' then
			return false
		end
		if family_id == 'combat.tank_enmity.primary' then
			return false
		end
		if action_type == 'move' or action_type == 'disengage' then
			return false
		end
		if action_type == 'engage' or action_type == 'target_switch' or action_type == 'ws' then
			return true
		end
		if target_kind == 'mob' then
			return true
		end
		return provider == 'combat' or provider == 'pull_control' or provider == 'target_control'
	end
	if action_type == 'move' or action_type == 'engage' or action_type == 'disengage' or action_type == 'target_switch' or action_type == 'ws' then
		return true
	end
	if target_kind == 'mob' then
		return true
	end
	return provider == 'combat' or provider == 'pull_control' or provider == 'target_control'
end

function M.reset(reason)
	local released = last_active_target_id > 0 and last_active_target_id or nil
	locks = {}
	last_active_target_id = 0
	last_transition = 'reset:' .. tostring(reason or 'manual')
	return released
end

function M.status()
	local enabled, rules = configured()
	refresh_effect_watch_cache(rules)
	local active = {}
	for _, lock in pairs(locks) do
		active[#active + 1] = copy_lock(lock)
	end
	table.sort(active, function(left, right)
		return tostring(left.key or '') < tostring(right.key or '')
	end)
	return {
		enabled = enabled,
		rule_count = #rules,
		active = active,
		unresolved_enemy_buffs = watch_cache_unresolved,
		last_transition = last_transition,
	}
end

return M
