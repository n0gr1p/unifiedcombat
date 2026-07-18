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
	local config = uc_active_config.get_path('config.reactions')
	if type(config) ~= 'table' or config.enabled ~= true or type(config.rules) ~= 'table' then
		return false, {}
	end
	return true, config.rules
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
	for key, lock in pairs(locks) do
		if key ~= keep_key and lock.trigger == 'ability_window' and tonumber(lock.actor_id) == id then
			locks[key] = nil
		end
	end
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
		clear_other_ability_windows(actor_id, key)
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
		last_active_target_id = actor_id
		last_transition = 'ready:' .. ability_name
		result.activated = copy_lock(locks[key])
		return result
	end

	if locks[key] ~= nil then
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

function M.blocks_proposal(lock, proposal)
	if type(lock) ~= 'table' or type(proposal) ~= 'table' then
		return false
	end
	local provider = tostring(proposal.provider or '')
	local action_type = tostring(proposal.action_type or '')
	local target_kind = tostring(proposal.target_kind or '')
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
