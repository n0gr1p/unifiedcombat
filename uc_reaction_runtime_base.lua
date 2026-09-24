local res = require('resources')
local uc_active_config = require('uc_active_config')
local extension_config = require('uc_combat_extension_config')

local M = {}

local locks = {}
local last_active_target_id = 0
local watch_cache_signature = nil
local watch_cache_set = {}
local watch_cache_names = {}
local watch_cache_ids = {}
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
	local rules = extension_config.reaction_rules()
	if type(rules) == 'table' then
		for i = 1, #rules do
			local rule = rules[i]
			local ok, err = extension_config.validate_action_rule(rule)
			if ok ~= true then
				error(('invalid reaction rule %d: %s'):format(i, tostring(err or 'invalid')))
			end
			configured_rules[#configured_rules + 1] = rule
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
				tostring(rule.action_type or ''),
				tostring(rule.action_name or ''),
				tostring(rule.activate_event or ''),
				tostring(rule.release_event or ''),
				tostring(rule.release_name or ''),
				tostring(rule.confirmation_timeout_seconds or ''),
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
	watch_cache_ids = {}
	watch_cache_unresolved = {}

	local requested = {}
	local function request_buff(name)
		local display = trim(name)
		if display ~= '' then
			requested[canonical(display)] = display
		end
	end
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == 'table' then
			if rule.trigger == 'enemy_buff' then
				request_buff(rule.name)
			elseif rule.trigger == 'event_window' then
				if rule.activate_event == 'buff_gained' then
					request_buff(rule.name)
				end
				if rule.release_event == 'buff_lost' then
					request_buff(rule.release_name)
				end
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
				watch_cache_ids[key] = effect_id
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

local function matching_event_window_rule(rules, activate_event, name)
	local wanted = canonical(name)
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == 'table'
			and rule.trigger == 'event_window'
			and tostring(rule.activate_event or '') == tostring(activate_event or '')
			and canonical(rule.name) == wanted then
			return rule, i
		end
	end
	return nil, nil
end

local function prune_unconfigured_locks(rules)
	for key, lock in pairs(locks) do
		local rule
		if lock.trigger == 'event_window' then
			rule = matching_event_window_rule(rules, lock.activate_event, lock.name)
		else
			rule = matching_rule(rules, lock.trigger, lock.name)
		end
		local configured_distance = rule and tonumber(rule.distance) or nil
		local active_distance = tonumber(lock.distance)
		local action_changed = lock.response == 'use_action' and (
			tostring(rule and rule.action_type or '') ~= tostring(lock.action_type or '')
			or tostring(rule and rule.action_name or '') ~= tostring(lock.action_name or '')
			)
		local lifecycle_changed = lock.trigger == 'event_window' and (
			tostring(rule and rule.release_event or '') ~= tostring(lock.release_event or '')
			or canonical(rule and rule.release_name or '') ~= canonical(lock.release_name or '')
			or tonumber(rule and rule.confirmation_timeout_seconds) ~= tonumber(lock.confirmation_timeout_seconds)
			)
		if rule == nil
			or rule.response ~= lock.response
			or action_changed
			or lifecycle_changed
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

local function spell_name_from_action(act)
	local spell_id = tonumber(type(act) == 'table' and act.param) or 0
	local spell = spell_id > 0 and res.spells and res.spells[spell_id] or nil
	return trim(spell and spell.en), spell_id
end

local function event_from_action(act, category)
	if category == 8 then
		local name, id = spell_name_from_action(act)
		return 'spell_start', name, id
	elseif category == 4 then
		local name, id = spell_name_from_action(act)
		return 'spell_end', name, id
	elseif category == 7 then
		local name, id = ability_name_from_action(act, category)
		return 'ability_start', name, id
	elseif category == 11 then
		local name, id = ability_name_from_action(act, category)
		return 'ability_end', name, id
	end
	return '', '', 0
end

local function event_window_key(rule, actor_id)
	return lock_key(
		'event_window:' .. tostring(rule.activate_event or ''),
		actor_id,
		rule.name
	)
end

local function activate_event_window(rule, rule_index, actor_id, action_id, now)
	local key = event_window_key(rule, actor_id)
	local lock = {
		key = key,
		trigger = 'event_window',
		name = trim(rule.name),
		response = rule.response,
		actor_id = actor_id,
		action_id = tonumber(action_id) or 0,
		started_at = tonumber(now) or 0,
		rule_index = rule_index,
		turn_applied = false,
		activate_event = tostring(rule.activate_event or ''),
		release_event = tostring(rule.release_event or ''),
		release_name = trim(rule.release_name),
		confirmation_timeout_seconds = tonumber(rule.confirmation_timeout_seconds),
		release_armed = false,
		phase = 'active',
	}
	if lock.release_event == 'buff_lost' then
		lock.release_effect_id = tonumber(watch_cache_ids[canonical(lock.release_name)]) or 0
	end
	locks[key] = lock
	last_active_target_id = actor_id
	last_transition = ('activated:%s:%s'):format(lock.activate_event, lock.name)
	return copy_lock(lock)
end

local function release_lock(key, transition)
	local released = copy_lock(locks[key])
	if released == nil then
		return nil, nil, nil
	end
	locks[key] = nil
	last_transition = transition
	if tonumber(released.actor_id) == last_active_target_id then
		last_active_target_id = 0
		local replacement = select_active_lock()
		if replacement then
			replacement.turn_applied = false
			return released, copy_lock(replacement), nil
		end
		return released, nil, tonumber(released.actor_id) or 0
	end
	return released, nil, nil
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
	refresh_effect_watch_cache(rules)
	local category = tonumber(act.category) or 0
	if category ~= 4 and category ~= 7 and category ~= 8 and category ~= 11 then
		return result
	end
	local actor_id = tonumber(act.actor_id) or 0
	local event_name, action_name, action_id = event_from_action(act, category)
	if actor_id <= 0 or event_name == '' or action_name == '' then
		return result
	end

	-- Generic lifecycle reactions are intentionally target-scoped for
	-- stop_attacking: an unrelated enemy casting the same spell must not
	-- disengage the character from the mob they are actually fighting.
	if event_name == 'spell_start' or event_name == 'ability_start' then
		local rule, rule_index = matching_event_window_rule(rules, event_name, action_name)
		if rule ~= nil
			and actor_is_valid_enemy == true
			and tonumber(current_target_id) == actor_id then
			result.activated = activate_event_window(rule, rule_index, actor_id, action_id, now)
			return result
		end
	end

	-- Action completion can either be the configured release itself or the
	-- point where a start->buff lifecycle begins waiting for confirmation.
	if event_name == 'spell_end' or event_name == 'ability_end' then
		for key, lock in pairs(locks) do
			if lock.trigger == 'event_window' and tonumber(lock.actor_id) == actor_id then
				if tostring(lock.release_event or '') == event_name
					and canonical(lock.release_name) == canonical(action_name) then
					local released, replacement, released_target_id = release_lock(
						key,
						('released:%s:%s'):format(event_name, action_name)
					)
					result.released = released
					result.activated = replacement
					result.released_target_id = released_target_id
					return result
				end
				local activation_completed =
					(lock.activate_event == 'spell_start' and event_name == 'spell_end')
					or (lock.activate_event == 'ability_start' and event_name == 'ability_end')
				if activation_completed and canonical(lock.name) == canonical(action_name)
					and lock.release_event == 'buff_lost'
					and lock.release_armed ~= true then
					local timeout = tonumber(lock.confirmation_timeout_seconds) or 1.5
					lock.confirmation_deadline = (tonumber(now) or 0) + timeout
					lock.phase = 'awaiting_confirmation'
					last_transition = 'awaiting_confirmation:' .. lock.name
				end
			end
		end
	end

	-- Preserve legacy ability_window behavior unchanged.
	if category ~= 7 and category ~= 11 then
		return result
	end
	local ability_name, ability_id = ability_name_from_action(act, category)
	if ability_name == '' then
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
		if rule.response == 'use_action' then
			locks[key].action_type = trim(rule.action_type):lower()
			locks[key].action_name = trim(rule.action_name)
		end
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
		local released, replacement, released_target_id = release_lock(key, 'complete:' .. ability_name)
		result.released = released
		result.activated = replacement
		result.released_target_id = released_target_id
	end
	return result
end

function M.prune_invalid_ability_windows(actor_is_valid_enemy)
	if type(actor_is_valid_enemy) ~= 'function' then
		error('reaction ability-window pruning requires an enemy-validity function')
	end
	local active_before = copy_lock(select_active_lock())
	for key, lock in pairs(locks) do
		if (lock.trigger == 'ability_window' or lock.trigger == 'event_window')
			and actor_is_valid_enemy(tonumber(lock.actor_id) or 0) ~= true then
			locks[key] = nil
		end
	end
	if not actor_has_lock(last_active_target_id) then
		last_active_target_id = 0
	end
	if active_before and locks[tostring(active_before.key or '')] == nil then
		last_transition = 'actor_unavailable:' .. tostring(active_before.name or '')
		return active_before
	end
	return nil
end

function M.evaluate(current_target_id, effects, now)
	local target_id = tonumber(current_target_id) or 0
	local now_value = tonumber(now) or 0
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
		elseif lock.trigger == 'event_window'
			and lock.response == 'stop_attacking'
			and tonumber(lock.actor_id) ~= target_id then
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

	-- Existing enemy_buff rules retain their original gain/loss lifecycle.
	for key, lock in pairs(locks) do
		if lock.trigger == 'enemy_buff' and active_effects[tonumber(lock.effect_id) or 0] ~= true then
			locks[key] = nil
		end
	end

	-- A generic lifecycle may activate before its eventual buff exists.  Once
	-- the release buff is observed, buff loss is authoritative.  Until then,
	-- a post-completion confirmation deadline prevents an interrupted/failed
	-- spell from holding attacks indefinitely.
	for key, lock in pairs(locks) do
		if lock.trigger == 'event_window' and lock.release_event == 'buff_lost' then
			local effect_id = tonumber(lock.release_effect_id) or 0
			local buff_active = effect_id > 0 and active_effects[effect_id] == true
			if buff_active then
				if lock.release_armed ~= true then
					lock.release_armed = true
					lock.confirmation_deadline = nil
					lock.phase = 'confirmed'
					last_transition = 'confirmed:buff_gained:' .. lock.release_name
				end
			elseif lock.release_armed == true then
				locks[key] = nil
				last_transition = 'released:buff_lost:' .. lock.release_name
			elseif (tonumber(lock.confirmation_deadline) or 0) > 0
				and now_value >= tonumber(lock.confirmation_deadline) then
				locks[key] = nil
				last_transition = 'released:confirmation_timeout:' .. lock.release_name
			end
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
					started_at = now_value,
					rule_index = rule_index,
					turn_applied = false,
				}
				last_transition = 'effect_gain:' .. name
			end
		end
		local lifecycle_rule, lifecycle_index = matching_event_window_rule(rules, 'buff_gained', name)
		if lifecycle_rule and target_id > 0 then
			local key = event_window_key(lifecycle_rule, target_id)
			if locks[key] == nil then
				activate_event_window(lifecycle_rule, lifecycle_index, target_id, effect_id, now_value)
				local lock = locks[key]
				if lock and lock.release_event == 'buff_lost'
					and tonumber(lock.release_effect_id) == effect_id then
					lock.release_armed = true
					lock.phase = 'confirmed'
				end
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
		if not tostring(last_transition):find('released:', 1, true) then
			last_transition = 'released'
		end
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
		and response ~= 'move_to_range'
		and response ~= 'use_action' then
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

function M.get_action_lock()
	local active = select_active_lock()
	if type(active) == 'table' and lock_response(active) == 'use_action' then
		return copy_lock(active)
	end
	return nil
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
	if response == 'use_action' then
		if provider == 'combat'
			and family_id == 'combat.reaction.action'
			and action_type == tostring(lock.action_type or '')
			and tostring(proposal.action_name or '') == tostring(lock.action_name or '')
			and target_kind == 'mob'
			and (tonumber(proposal.target_id) or 0) == (tonumber(lock.actor_id) or 0) then
			return false
		end
	end
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
