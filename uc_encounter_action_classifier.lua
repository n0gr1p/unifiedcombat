local res = require('resources')

local M = {}

local resource_cache = {}

local WATER_DAMAGE_WEAPON_SKILLS = {
	[130] = 'Blade: Teki',
	[139] = 'Blade: Yu',
}

local WATER_DAMAGE_NINJUTSU = {
	[335] = 'Suiton: Ichi',
	[336] = 'Suiton: Ni',
	[337] = 'Suiton: San',
}

local WATER_DAMAGE_BLUE_MAGIC = {
	[513] = 'Venom Shell',
	[515] = 'Maelstrom',
	[536] = 'Poison Breath',
	[544] = 'Cursed Sphere',
	[648] = 'Regurgitation',
	[651] = 'Corrosive Ooze',
	[656] = 'Acrid Stream',
	[687] = 'Water Bomb',
	[694] = 'Vapor Spray',
	[702] = 'Rending Deluge',
	[705] = 'Foul Waters',
	[716] = 'Nectarous Deluge',
	[726] = 'Scouring Spate',
	[752] = 'Cesspool',
}

local WATER_DAMAGE_JOB_ABILITIES = {
	[130] = 'Water Shot',
}

local WATER_DAMAGE_BLOOD_PACTS = {
	[577] = 'Water II',
	[581] = 'Water IV',
	[583] = 'Grand Fall',
	[584] = 'Tidal Wave',
}

local function action_resource_table(action_type, deps)
	if action_type == 'spell' then
		return deps.spells
	end
	if action_type == 'ws' then
		return deps.weapon_skills
	end
	if action_type == 'ja' or action_type == 'pet' then
		return deps.job_abilities
	end
	return nil
end

local function build_name_cache(resource_table)
	local cached = resource_cache[resource_table]
	if cached ~= nil then
		return cached
	end
	local by_name = {}
	for id, resource in pairs(resource_table) do
		local name = type(resource) == 'table' and tostring(resource.en or '') or ''
		if name ~= '' then
			local numeric_id = tonumber(resource.id) or tonumber(id)
			if numeric_id == nil or numeric_id <= 0 then
				error('encounter action resource has an invalid id for ' .. name)
			end
			if by_name[name] ~= nil and by_name[name].id ~= numeric_id then
				error('encounter action resource name is ambiguous: ' .. name)
			end
			by_name[name] = resource
		end
	end
	resource_cache[resource_table] = by_name
	return by_name
end

local function resource_by_name(resource_table, action_name)
	if type(resource_table) ~= 'table' then
		return nil
	end
	return build_name_cache(resource_table)[action_name]
end

local function element_name(resource, elements)
	if type(resource) ~= 'table' then
		return ''
	end
	local element_id = tonumber(resource.element)
	if element_id ~= nil then
		local element = type(elements) == 'table' and elements[element_id] or nil
		if type(element) ~= 'table' or type(element.en) ~= 'string' or element.en == '' then
			error('encounter action resource element is unresolved: ' .. tostring(element_id))
		end
		return element.en
	end
	if type(resource.element) == 'string' then
		return resource.element
	end
	return ''
end

local function listed_resource(resource, expected_names, label)
	local id = tonumber(resource.id)
	local expected_name = id and expected_names[id] or nil
	if expected_name == nil then
		return false
	end
	local actual_name = tostring(resource.en or '')
	if actual_name ~= expected_name then
		error(('%s resource identity mismatch id=%s expected=%s actual=%s'):format(
			label,
			tostring(id),
			expected_name,
			actual_name
		))
	end
	return true
end

local function spell_is_water_damage(resource)
	local spell_type = tostring(resource.type or '')
	local skill_id = tonumber(resource.skill)
	if skill_id == 36 then
		return true
	end
	if spell_type == 'Ninjutsu' then
		return listed_resource(resource, WATER_DAMAGE_NINJUTSU, 'Water Ninjutsu')
	end
	if spell_type == 'BlueMagic' then
		return listed_resource(resource, WATER_DAMAGE_BLUE_MAGIC, 'Water Blue Magic')
	end
	return false
end

function M.classify(proposal, deps)
	if type(proposal) ~= 'table' then
		error('uc_encounter_action_classifier.classify requires proposal')
	end
	local sources = deps
	if sources == nil then
		sources = {
			spells = res.spells,
			weapon_skills = res.weapon_skills,
			job_abilities = res.job_abilities,
			elements = res.elements,
		}
	end
	if type(sources) ~= 'table' then
		error('encounter action classifier deps must be a table')
	end
	local action_type = tostring(proposal.action_type or '')
	local action_name = tostring(proposal.action_name or '')
	local resource_table = action_resource_table(action_type, sources)
	local resource = resource_by_name(resource_table, action_name)
	local result = {
		action_type = action_type,
		action_name = action_name,
		resource_id = resource and tonumber(resource.id) or nil,
		element = element_name(resource, sources.elements),
		direct_damage = false,
		action_class = '',
		action_key = '',
		proof = '',
	}
	if resource == nil then
		return result
	end
	if action_type == 'ws' then
		result.action_class = 'ws'
		result.action_key = tostring(resource.id)
		if result.element == 'Water'
			and listed_resource(resource, WATER_DAMAGE_WEAPON_SKILLS, 'Water weapon skill') then
			result.direct_damage = true
			result.proof = 'verified_water_weapon_skill_resource'
		end
		return result
	end
	if action_type == 'spell' then
		if result.element == 'Water' and spell_is_water_damage(resource) then
			result.direct_damage = true
			result.proof = 'verified_water_spell_resource'
		end
		return result
	end
	if action_type == 'ja' then
		if result.element == 'Water'
			and listed_resource(resource, WATER_DAMAGE_JOB_ABILITIES, 'Water job ability') then
			result.direct_damage = true
			result.proof = 'verified_water_job_ability_resource'
		end
		return result
	end
	if action_type == 'pet' then
		local detail = proposal.detail
		local command = type(detail) == 'table' and detail.pet_command or nil
		if type(command) == 'table' and tostring(command.kind or '') == 'rage' then
			result.action_class = 'bp'
			result.action_key = tostring(resource.id)
			if result.element == 'Water'
				and listed_resource(resource, WATER_DAMAGE_BLOOD_PACTS, 'Water Blood Pact') then
				result.direct_damage = true
				result.proof = 'verified_water_blood_pact_resource'
			end
		end
	end
	return result
end

function M.reset_cache()
	resource_cache = {}
end

return M
