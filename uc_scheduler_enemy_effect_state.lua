local enemy_effect_utils = require('uc_scheduler_enemy_effect_utils')

local M = {}

local dispellable_priority = {}
local dispellable_set = {}
local observed_unknown = {}
local targetbar_spells = nil
local targetbar_abilities = nil
local targetbar_skills = nil

local RAW_REMOVE_MESSAGES = {
	[204] = true,
	[206] = true,
}

local RAW_DEATH_MESSAGES = {
	[6] = true,
	[20] = true,
	[113] = true,
	[406] = true,
	[605] = true,
	[646] = true,
}

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_scheduler_enemy_effect_state requires function dependency: ' .. tostring(name))
	end
	return fn
end

local function require_phase1(phase1)
	if type(phase1) ~= 'table' then
		error('uc_scheduler_enemy_effect_state requires phase1 state')
	end
	return phase1
end

function M.load_dispel_map(addon_path)
	dispellable_priority = {}
	dispellable_set = {}
	local path = tostring(addon_path or '') .. 'docs/ffxi_enemy_dispellable_buffs.json'
	local file = io.open(path, 'r')
	if not file then
		error(('uc_scheduler_enemy_effect_state: unable to open dispel map JSON at %s'):format(path))
	end
	local raw = file:read('*a')
	file:close()
	if type(raw) ~= 'string' or raw == '' then
		error(('uc_scheduler_enemy_effect_state: dispel map JSON is empty at %s'):format(path))
	end
	if not raw:find('"schema_name"%s*:%s*"ffxi_enemy_dispellable_buffs"') then
		error(('uc_scheduler_enemy_effect_state: invalid dispel map schema at %s'):format(path))
	end

	local imported_count = 0
	local cursor = 1
	local guard = 0
	local guard_max = 250000
	while true do
		guard = guard + 1
		if guard > guard_max then
			error('uc_scheduler_enemy_effect_state: dispel map parse exceeded safety limit')
		end
		local start_at, end_at, ids_blob =
			raw:find('"buff_ids"%s*:%s*%[(.-)%]', cursor)
		if not start_at then
			break
		end
		local tail = raw:sub(end_at + 1, math.min(#raw, end_at + 1200))
		local danger_weight = tonumber(tail:match('"danger_weight"%s*:%s*(%d+)'))
		if not danger_weight then
			error(
				('uc_scheduler_enemy_effect_state: buff_ids record at byte %d has no danger_weight')
					:format(start_at)
			)
		end
		local priority = enemy_effect_utils.danger_weight_to_priority(danger_weight)
		for number_text in tostring(ids_blob or ''):gmatch('%d+') do
			local effect_id = tonumber(number_text) or 0
			if effect_id > 0 then
				if dispellable_set[effect_id] == true then
					error(
						('uc_scheduler_enemy_effect_state: duplicate dispel map buff id %d')
							:format(effect_id)
					)
				end
				dispellable_priority[effect_id] = priority
				dispellable_set[effect_id] = true
				imported_count = imported_count + 1
			end
		end
		cursor = end_at + 1
	end
	if imported_count <= 0 then
		error(
			('uc_scheduler_enemy_effect_state: imported zero buff ids from %s'):format(path)
		)
	end
	return imported_count
end

function M.is_dispellable(effect_id)
	return dispellable_set[tonumber(effect_id) or 0] == true
end

function M.dispel_priority(effect_id)
	return dispellable_priority[tonumber(effect_id) or 0]
end

function M.copy_dispellable_set()
	local copy = {}
	for effect_id in pairs(dispellable_set) do
		copy[effect_id] = true
	end
	return copy
end

function M.observe_unknown_once(key)
	local normalized = tostring(key or '')
	if normalized == '' then
		error('uc_scheduler_enemy_effect_state requires a non-blank observation key')
	end
	if observed_unknown[normalized] == true then
		return false
	end
	observed_unknown[normalized] = true
	return true
end

local function load_targetbar_catalogs(addon_path)
	if targetbar_spells ~= nil and targetbar_abilities ~= nil and targetbar_skills ~= nil then
		return
	end
	local base = tostring(addon_path or '') .. 'TargetBar\\'
	local ok_spells, spells = pcall(dofile, base .. 'spells.lua')
	if not ok_spells or type(spells) ~= 'table' then
		error(
			('uc_scheduler_enemy_effect_state: failed loading %s (%s)')
				:format(base .. 'spells.lua', tostring(spells))
		)
	end
	local ok_abilities, abilities = pcall(dofile, base .. 'abilities.lua')
	if not ok_abilities or type(abilities) ~= 'table' then
		error(
			('uc_scheduler_enemy_effect_state: failed loading %s (%s)')
				:format(base .. 'abilities.lua', tostring(abilities))
		)
	end
	local ok_skills, skills = pcall(dofile, base .. 'skills.lua')
	if not ok_skills or type(skills) ~= 'table' then
		error(
			('uc_scheduler_enemy_effect_state: failed loading %s (%s)')
				:format(base .. 'skills.lua', tostring(skills))
		)
	end
	targetbar_spells = spells
	targetbar_abilities = abilities
	targetbar_skills = skills
end

function M.spell_effect_id(addon_path, spell_id)
	load_targetbar_catalogs(addon_path)
	local entry = targetbar_spells[tonumber(spell_id) or 0]
	return type(entry) == 'table' and tonumber(entry[1]) or 0
end

function M.attempt_map(phase1)
	local phase = require_phase1(phase1)
	phase.enemy_dispel_attempts = phase.enemy_dispel_attempts or {}
	return phase.enemy_dispel_attempts
end

function M.effect_map(phase1)
	local phase = require_phase1(phase1)
	phase.effectiveTargets = phase.effectiveTargets or {}
	return phase.effectiveTargets
end

function M.set(phase1, target_id, effect_id, source, at, duration_s, now, action_id)
	local tid = tonumber(target_id) or 0
	local eid = tonumber(effect_id) or 0
	if tid <= 0 or eid <= 0 then
		return
	end
	local timestamp = tonumber(at)
	if timestamp == nil then
		timestamp = require_function({ now = now }, 'now')()
	end
	local duration = tonumber(duration_s) or 0
	local expires_at = 0
	if duration > 0 then
		expires_at = timestamp + duration
	end
	local state = M.effect_map(phase1)
	state[tid] = state[tid] or {}
	state[tid][eid] = {
		seen_at = timestamp,
		source = tostring(source or ''),
		expires_at = expires_at,
		action_id = tonumber(action_id) or 0,
	}
end

function M.clear(phase1, target_id, effect_id)
	local tid = tonumber(target_id) or 0
	local eid = tonumber(effect_id) or 0
	if tid <= 0 or eid <= 0 then
		return false
	end
	local state = M.effect_map(phase1)
	if type(state[tid]) == 'table' and state[tid][eid] ~= nil then
		state[tid][eid] = nil
		return true
	end
	return false
end

function M.clear_target(phase1, target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return
	end
	M.effect_map(phase1)[tid] = nil
end

function M.prune_expired(phase1, at, now)
	local timestamp = tonumber(at)
	if timestamp == nil then
		timestamp = require_function({ now = now }, 'now')()
	end
	local state = M.effect_map(phase1)
	for target_id, effects in pairs(state) do
		if type(effects) == 'table' then
			for effect_id, row in pairs(effects) do
				local expires_at = tonumber(row and row.expires_at) or 0
				if expires_at > 0 and expires_at <= timestamp then
					effects[effect_id] = nil
				end
			end
			if next(effects) == nil then
				state[target_id] = nil
			end
		else
			state[target_id] = nil
		end
	end
end

function M.sweep(phase1, max_age_s, now, get_mob_by_id)
	local timestamp = require_function({ now = now }, 'now')()
	local cutoff = timestamp - (tonumber(max_age_s) or 120)
	local state = M.effect_map(phase1)
	for target_id, effects in pairs(state) do
		local remove_target = false
		local mob = require_function(
			{ get_mob_by_id = get_mob_by_id },
			'get_mob_by_id'
		)(tonumber(target_id) or 0)
		if not mob or tonumber(mob.spawn_type) ~= 16 or (tonumber(mob.hpp) or 0) <= 0 then
			remove_target = true
		elseif type(effects) ~= 'table' then
			remove_target = true
		else
			for effect_id, row in pairs(effects) do
				local seen_at = tonumber(row and row.seen_at) or 0
				if seen_at > 0 and seen_at < cutoff then
					effects[effect_id] = nil
				end
			end
			if next(effects) == nil then
				remove_target = true
			end
		end
		if remove_target then
			state[target_id] = nil
		end
	end
end

function M.can_attempt(phase1, action_name, target_id, effect_id, now, cooldown_s)
	local key = table.concat({
		tostring(action_name or ''),
		tostring(tonumber(target_id) or 0),
		tostring(tonumber(effect_id) or 0),
	}, ':')
	local last = tonumber(M.attempt_map(phase1)[key]) or 0
	if last > 0 and (now - last) < cooldown_s then
		return false, key
	end
	return true, key
end

function M.mark_attempt(phase1, key, at, now)
	if tostring(key or '') == '' then
		return
	end
	local timestamp = tonumber(at)
	if timestamp == nil then
		timestamp = require_function({ now = now }, 'now')()
	end
	M.attempt_map(phase1)[tostring(key)] = timestamp
end

local function apply_effect_list(phase1, target_id, effect_list, source, at, now)
	if type(effect_list) ~= 'table' then
		return
	end
	for i = 1, #effect_list do
		local row = effect_list[i]
		if type(row) == 'table' then
			local effect_id = tonumber(row[1]) or 0
			if effect_id > 0 then
				M.set(phase1, target_id, effect_id, source, at, nil, now)
			end
		end
	end
end

local function apply_catalog_effects(
	phase1,
	catalog,
	action_id,
	actor_id,
	target_id,
	source,
	at,
	now
)
	local id = tonumber(action_id) or 0
	if id <= 0 or type(catalog) ~= 'table' then
		return
	end
	local entry = catalog[id]
	if type(entry) ~= 'table' or #entry == 0 then
		return
	end
	if type(entry[1]) == 'number' then
		local effect_id = tonumber(entry[1]) or 0
		if effect_id > 0 then
			M.set(phase1, target_id, effect_id, source, at, nil, now)
		end
		return
	end
	if type(entry[1]) == 'table' and type(entry[1][1]) == 'number' then
		apply_effect_list(phase1, target_id, entry, source, at, now)
		return
	end
	if type(entry[1]) == 'table' and type(entry[1][1]) == 'table' then
		apply_effect_list(phase1, target_id, entry[1], source, at, now)
		apply_effect_list(phase1, actor_id, entry[2], source .. '_actor', at, now)
	end
end

function M.ingest_raw_action(phase1, data_or_action, deps)
	load_targetbar_catalogs(deps.addon_path)
	local action
	if type(data_or_action) == 'table' then
		action = data_or_action
	else
		local parse_action = require_function(deps, 'parse_action')
		local ok, parsed = pcall(function()
			return parse_action(data_or_action)
		end)
		if not ok or type(parsed) ~= 'table' then
			error(
				('uc_scheduler_enemy_effect_state: failed to parse 0x028 action packet (%s)')
					:format(tostring(parsed))
			)
		end
		action = parsed
	end
	local player = require_function(deps, 'get_player')()
	local player_id = tonumber(player and player.id) or 0
	local actor_id = tonumber(action.actor_id) or 0
	if actor_id <= 0 or (player_id > 0 and actor_id == player_id)
		or type(action.targets) ~= 'table' then
		return
	end
	local category = tonumber(action.category) or 0
	local timestamp = require_function(deps, 'now')()
	local spell_gain_messages = deps.spell_effect_gain_messages
	if type(spell_gain_messages) ~= 'table' then
		error('uc_scheduler_enemy_effect_state requires spell_effect_gain_messages')
	end

	local aa_hit = { [1]=true,[67]=true,[157]=true,[353]=true,[577]=true }
	local aa_ignore = { [15]=true,[31]=true,[70]=true,[354]=true,[355]=true }
	local spell_remove = { [83]=true,[341]=true,[342]=true,[343]=true,[344]=true }
	local spell_ignore = { [0]=true,[31]=true,[75]=true,[78]=true,[85]=true,[106]=true,[114]=true,[283]=true,[284]=true }
	local ja_add = { [100]=true,[102]=true,[110]=true,[115]=true,[116]=true,[117]=true,[118]=true,[119]=true,[120]=true,[121]=true,[126]=true,[131]=true,[134]=true,[143]=true,[148]=true,[149]=true,[266]=true,[285]=true,[286]=true,[287]=true,[304]=true,[317]=true,[319]=true,[452]=true,[519]=true,[529]=true,[667]=true,[668]=true,[669]=true }
	local ws_add = { [1]=true,[101]=true,[110]=true,[185]=true,[187]=true,[194]=true,[224]=true,[225]=true,[226]=true,[238]=true,[242]=true,[243]=true,[264]=true,[276]=true,[277]=true,[278]=true,[280]=true,[281]=true,[299]=true,[317]=true,[367]=true,[763]=true }
	local ws_ignore = { [15]=true,[31]=true,[188]=true,[189]=true,[282]=true,[283]=true }

	for _, target in ipairs(action.targets) do
		local target_id = tonumber(target and target.id) or 0
		if target_id > 0 and type(target.actions) == 'table' then
			for index = 1, #target.actions do
				local action_row = target.actions[index] or {}
				local message = tonumber(action_row.message)
					or tonumber(action_row.message_id)
					or 0
				local effect_id = tonumber(action_row.param) or 0
				if index == 1 and actor_id ~= 0 and (message == 29 or message == 84)
					and M.is_dispellable(4) then
					M.set(
						phase1,
						actor_id,
						4,
						'raw_028_actor_para',
						timestamp,
						nil,
						deps.now
					)
				end
				if category == 1 or category == 2 then
					if aa_hit[message] == true then
						M.clear(phase1, target_id, 36)
						M.clear(phase1, target_id, 66)
						M.clear(phase1, target_id, 444)
						M.clear(phase1, target_id, 445)
						M.clear(phase1, target_id, 446)
						if effect_id > 0 then
							M.clear(phase1, target_id, 37)
						end
					elseif message == 30 then
						M.clear(phase1, target_id, 67)
					elseif aa_ignore[message] ~= true then
						-- Unknown melee branches intentionally do not infer effects.
					end
					if action_row.has_add_effect then
						local add_message = tonumber(action_row.add_effect_message) or 0
						local add_effect = tonumber(action_row.add_effect_param) or 0
						if (add_message == 160 or add_message == 164)
							and add_effect > 0 and M.is_dispellable(add_effect) then
							M.set(
								phase1,
								target_id,
								add_effect,
								('raw_028_add_effect_msg_%d'):format(add_message),
								timestamp,
								nil,
								deps.now
							)
						end
					end
				elseif category == 4 then
					if spell_gain_messages[message] == true then
						apply_catalog_effects(
							phase1,
							targetbar_spells,
							tonumber(action.param) or 0,
							actor_id,
							target_id,
							('raw_028_spell_msg_%d'):format(message),
							timestamp,
							deps.now
						)
					elseif spell_remove[message] == true then
						if effect_id > 0 then
							M.clear(phase1, target_id, effect_id)
						end
					elseif message == 84 and M.is_dispellable(4) then
						M.set(
							phase1,
							target_id,
							4,
							'raw_028_spell_para',
							timestamp,
							nil,
							deps.now
						)
					elseif spell_ignore[message] ~= true then
						-- Unknown spell branches intentionally do not infer effects.
					end
				elseif category == 6 or category == 13 or category == 14 or category == 15 then
					if ja_add[message] == true then
						apply_catalog_effects(
							phase1,
							targetbar_abilities,
							tonumber(action.param) or 0,
							actor_id,
							target_id,
							('raw_028_ja_msg_%d'):format(message),
							timestamp,
							deps.now
						)
					end
				elseif category == 3 or category == 11 then
					if ws_add[message] == true then
						apply_catalog_effects(
							phase1,
							targetbar_skills,
							tonumber(action.param) or 0,
							actor_id,
							target_id,
							('raw_028_ws_msg_%d'):format(message),
							timestamp,
							deps.now
						)
					elseif ws_ignore[message] ~= true then
						-- Unknown WS branches intentionally do not infer effects.
					end
				end
			end
		end
	end
	if actor_id > 0 and (player_id <= 0 or actor_id ~= player_id) then
		M.clear(phase1, actor_id, 10)
		M.clear(phase1, actor_id, 2)
		M.clear(phase1, actor_id, 7)
	end
end

function M.is_raw_remove_message(message_id)
	return RAW_REMOVE_MESSAGES[tonumber(message_id) or 0] == true
end

function M.is_raw_death_message(message_id)
	return RAW_DEATH_MESSAGES[tonumber(message_id) or 0] == true
end

return M
