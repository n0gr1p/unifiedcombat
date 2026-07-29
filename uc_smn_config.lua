local capabilities = require('uc_smn_capabilities')

local M = {}

local function add_issue(list, code, message)
	list[#list + 1] = {
		code = code,
		message = message,
	}
end

local function require_table(result, parent, key, path)
	local value = parent[key]
	if value == nil then
		result.valid = false
		add_issue(result.errors, 'summoner_shape_invalid', path .. ' must be a table.')
		return nil
	end
	if type(value) ~= 'table' then
		result.valid = false
		add_issue(result.errors, 'summoner_shape_invalid', path .. ' must be a table.')
		return nil
	end
	return value
end

local function require_boolean(result, parent, key, path)
	if type(parent[key]) ~= 'boolean' then
		result.valid = false
		add_issue(result.errors, 'summoner_shape_invalid', path .. ' must be boolean.')
		return false
	end
	return true
end

local function require_optional_string(result, parent, key, path)
	local value = parent[key]
	if value ~= nil and type(value) ~= 'string' then
		result.valid = false
		add_issue(result.errors, 'summoner_shape_invalid', path .. ' must be a string or nil.')
		return false
	end
	return true
end

function M.validate(config)
	local result = {
		enabled = false,
		valid = true,
		avatar_valid = true,
		ward_valid = true,
		rage_valid = true,
		errors = {},
		warnings = {},
	}

	if config == nil then
		return result
	end
	if type(config) ~= 'table' then
		result.valid = false
		result.avatar_valid = false
		add_issue(result.errors, 'summoner_not_table', 'Summoner configuration must be a table.')
		return result
	end

	if not require_boolean(result, config, 'enabled', 'summoner.enabled') then
		result.avatar_valid = false
	end
	local maintenance = require_table(result, config, 'maintenance', 'summoner.maintenance')
	local pet_combat = require_table(result, config, 'pet_combat', 'summoner.pet_combat')
	if maintenance == nil or pet_combat == nil then
		return result
	end

	local ward = require_table(result, maintenance, 'ward', 'summoner.maintenance.ward')
	local offensive = require_table(
		result,
		pet_combat,
		'offensive_action',
		'summoner.pet_combat.offensive_action'
	)
	if ward == nil or offensive == nil then
		return result
	end
	require_optional_string(result, config, 'avatar', 'summoner.avatar')
	require_boolean(result, maintenance, 'avatar_favor', 'summoner.maintenance.avatar_favor')
	require_boolean(result, ward, 'enabled', 'summoner.maintenance.ward.enabled')
	require_optional_string(result, ward, 'action', 'summoner.maintenance.ward.action')
	require_boolean(
		result,
		pet_combat,
		'engage_on_combat_start',
		'summoner.pet_combat.engage_on_combat_start'
	)
	require_boolean(result, offensive, 'enabled', 'summoner.pet_combat.offensive_action.enabled')
	require_optional_string(
		result,
		offensive,
		'action',
		'summoner.pet_combat.offensive_action.action'
	)
	if type(offensive.usage) ~= 'string' then
		result.valid = false
		add_issue(
			result.errors,
			'summoner_shape_invalid',
			'summoner.pet_combat.offensive_action.usage must be a string.'
		)
	end
	result.enabled = config.enabled == true
	if not result.valid or not result.enabled then
		return result
	end

	local avatar = capabilities.avatar(config.avatar)
	if avatar == nil then
		result.valid = false
		result.avatar_valid = false
		if config.avatar == nil or config.avatar == '' then
			add_issue(result.errors, 'avatar_required', 'Summoner automation requires a desired avatar.')
		else
			add_issue(
				result.errors,
				'avatar_unsupported',
				('Summoner avatar %q is not supported.'):format(tostring(config.avatar))
			)
		end
		return result
	end
	result.avatar = avatar

	if ward.enabled == true then
		local action = capabilities.action(avatar.name, 'ward', ward.action)
		if action == nil then
			result.ward_valid = false
			if ward.action == nil or ward.action == '' then
				add_issue(result.warnings, 'ward_action_required', 'Enabled Summoner Ward maintenance requires an action.')
			else
				add_issue(
					result.warnings,
					'ward_incompatible',
					('Ward %q is not compatible with desired avatar %s.'):format(tostring(ward.action), avatar.name)
				)
			end
		else
			result.ward = action
		end
	end

	if offensive.enabled == true then
		local action = capabilities.action(avatar.name, 'rage', offensive.action)
		if action == nil then
			result.rage_valid = false
			if offensive.action == nil or offensive.action == '' then
				add_issue(result.warnings, 'rage_action_required', 'Enabled Summoner Rage automation requires an action.')
			else
				add_issue(
					result.warnings,
					'rage_incompatible',
					('Rage %q is not compatible with desired avatar %s.'):format(tostring(offensive.action), avatar.name)
				)
			end
		else
			result.rage = action
		end
		if offensive.usage ~= 'on_cooldown' then
			result.rage_valid = false
			add_issue(
				result.warnings,
				'rage_usage_unsupported',
				('Rage usage policy %q is not supported.'):format(tostring(offensive.usage))
			)
		end
	end

	return result
end

return M
