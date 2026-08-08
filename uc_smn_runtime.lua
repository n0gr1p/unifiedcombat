local smn_config = require('uc_smn_config')

local M = {
	RECAST_ASSAULT = 170,
	RECAST_RELEASE = 172,
	RECAST_RAGE = 173,
	RECAST_WARD = 174,
	RECAST_FAVOR = 176,
	BUFF_FAVOR = 431,
	PRIORITY_RELEASE = 149,
	PRIORITY_FAVOR = 149,
	PRIORITY_WARD = 148,
	PRIORITY_ASSAULT = 147,
	PRIORITY_RAGE = 146,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_boolean(value, name)
	if type(value) ~= 'boolean' then
		error(name .. ' must be boolean')
	end
	return value
end

local function optional_string(value, name)
	if value ~= nil and type(value) ~= 'string' then
		error(name .. ' must be a string or nil')
	end
	if value == '' then
		return nil
	end
	return value
end

local function parse_ward_actions(settings)
	local actions_value = settings.summoner_ward_actions
	local legacy_value = settings.summoner_ward_action
	if actions_value ~= nil and type(actions_value) ~= 'string' then
		error('summoner_ward_actions must be a pipe-delimited string')
	end
	if legacy_value ~= nil and type(legacy_value) ~= 'string' then
		error('summoner_ward_action must be a string or nil')
	end
	local actions = {}
	local seen = {}
	local raw = actions_value or ''
	if raw ~= '' then
		if raw:sub(1, 1) == '|' or raw:sub(-1) == '|' or raw:find('||', 1, true) then
			error('summoner_ward_actions contains an empty action')
		end
		for name in raw:gmatch('[^|]+') do
			if name == '' or name:match('^%s*$') then
				error('summoner_ward_actions contains an empty action')
			end
			name = name:match('^%s*(.-)%s*$')
			if seen[name] then
				error(('summoner_ward_actions duplicates %q'):format(name))
			end
			seen[name] = true
			actions[#actions + 1] = name
		end
	end
	local legacy = optional_string(legacy_value, 'summoner_ward_action')
	if legacy ~= nil then
		if #actions == 0 then
			actions[1] = legacy
		elseif actions[1] ~= legacy then
			error('summoner_ward_action must match the first summoner_ward_actions entry')
		end
	end
	return actions
end

local function optional_gate(settings, enabled_name, value_name, default_value, maximum)
	local enabled = settings[enabled_name]
	local value = settings[value_name]
	if enabled == nil and value == nil then
		return {
			enabled = false,
			value = default_value,
		}
	end
	require_boolean(enabled, enabled_name)
	if type(value) ~= 'number'
		or value % 1 ~= 0
		or value < 0
		or value > maximum then
		error(('%s must be an integer from 0 to %d'):format(value_name, maximum))
	end
	return {
		enabled = enabled,
		value = value,
	}
end

function M.config_from_settings(settings)
	settings = require_table(settings, 'Summoner runtime settings')
	require_boolean(settings.summoner_enabled, 'summoner_enabled')
	if settings.summoner_enabled == false then
		local disabled = {
			enabled = false,
			avatar = nil,
			maintenance = {
				avatar_favor = false,
				ward = {
					enabled = false,
					actions = {},
				},
			},
			pet_combat = {
				engage_on_combat_start = false,
				offensive_action = {
					enabled = false,
					action = nil,
					usage = 'on_cooldown',
					target_hpp_above_enabled = false,
					target_hpp_above = 50,
					pet_tp_above_enabled = false,
					pet_tp_above = 2000,
				},
			},
		}
		return disabled, smn_config.validate(disabled)
	end
	local target_hpp_gate = optional_gate(
		settings,
		'summoner_rage_target_hpp_above_enabled',
		'summoner_rage_target_hpp_above',
		50,
		99
	)
	local pet_tp_gate = optional_gate(
		settings,
		'summoner_rage_pet_tp_above_enabled',
		'summoner_rage_pet_tp_above',
		2000,
		2999
	)
	local config = {
		enabled = true,
		avatar = optional_string(settings.summoner_avatar, 'summoner_avatar'),
		maintenance = {
			avatar_favor = require_boolean(
				settings.summoner_avatar_favor,
				'summoner_avatar_favor'
			),
			ward = {
				enabled = require_boolean(settings.summoner_ward_enabled, 'summoner_ward_enabled'),
				actions = parse_ward_actions(settings),
			},
		},
		pet_combat = {
			engage_on_combat_start = require_boolean(
				settings.summoner_engage_on_combat_start,
				'summoner_engage_on_combat_start'
			),
			offensive_action = {
				enabled = require_boolean(settings.summoner_rage_enabled, 'summoner_rage_enabled'),
				action = optional_string(settings.summoner_rage_action, 'summoner_rage_action'),
				usage = optional_string(settings.summoner_rage_usage, 'summoner_rage_usage'),
				target_hpp_above_enabled = target_hpp_gate.enabled,
				target_hpp_above = target_hpp_gate.value,
				pet_tp_above_enabled = pet_tp_gate.enabled,
				pet_tp_above = pet_tp_gate.value,
			},
		},
	}
	local validation = smn_config.validate(config)
	return config, validation
end

function M.has_buff(player, effect_id)
	player = require_table(player, 'Summoner player state')
	local buffs = player.buffs
	if type(buffs) ~= 'table' then
		error('Summoner player state buffs must be a table')
	end
	for i = 1, #buffs do
		if tonumber(buffs[i]) == effect_id then
			return true
		end
	end
	return false
end

function M.player_mp(player)
	player = require_table(player, 'Summoner player state')
	local vitals = require_table(player.vitals, 'Summoner player vitals')
	local mp = tonumber(vitals.mp)
	if mp == nil then
		error('Summoner player MP must be numeric')
	end
	return mp
end

function M.recast_ready(ctx, recast_id)
	ctx = require_table(ctx, 'Summoner scheduler context')
	if ctx.ability_recasts_present ~= true then
		return false, 'ability_recasts_unavailable'
	end
	local recasts = require_table(ctx.ability_recasts, 'Summoner ability recasts')
	local value = tonumber(recasts[recast_id])
	if value == nil then
		error(('Summoner ability recasts missing id %d'):format(recast_id))
	end
	if value > 0 then
		return false, 'recast_unavailable'
	end
	return true, ''
end

function M.pet_distance(pet, target)
	pet = require_table(pet, 'Summoner pet state')
	target = require_table(target, 'Summoner target state')
	local pet_x = tonumber(pet.x)
	local pet_y = tonumber(pet.y)
	local target_x = tonumber(target.x)
	local target_y = tonumber(target.y)
	if pet_x == nil or pet_y == nil or target_x == nil or target_y == nil then
		return nil
	end
	local dx = target_x - pet_x
	local dy = target_y - pet_y
	return math.sqrt((dx * dx) + (dy * dy))
end

return M
