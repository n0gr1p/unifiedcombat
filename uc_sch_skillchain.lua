local skillchain_state = require('uc_skillchain_state')

local M = {}

local spell_families = {
	{ prefix = 'Fire', property = 'Liquefaction' },
	{ prefix = 'Blizzard', property = 'Induration' },
	{ prefix = 'Aero', property = 'Detonation' },
	{ prefix = 'Stone', property = 'Scission' },
	{ prefix = 'Thunder', property = 'Impaction' },
	{ prefix = 'Water', property = 'Reverberation' },
	{ prefix = 'Luminohelix', property = 'Transfixion' },
	{ prefix = 'Noctohelix', property = 'Compression' },
	{ prefix = 'Pyrohelix', property = 'Liquefaction' },
	{ prefix = 'Cryohelix', property = 'Induration' },
	{ prefix = 'Anemohelix', property = 'Detonation' },
	{ prefix = 'Geohelix', property = 'Scission' },
	{ prefix = 'Ionohelix', property = 'Impaction' },
	{ prefix = 'Hydrohelix', property = 'Reverberation' },
}

-- Canonical autonomous two-step Immanence recipes. UI/profile consumers select
-- the desired result; spell ordering remains owned here so recipe knowledge is
-- not duplicated across the WinForms editor and runtime.
local canonical_recipes = {
	Fusion = { opener = 'Fire', closer = 'Thunder' },
	Fragmentation = { opener = 'Blizzard', closer = 'Water' },
	Distortion = { opener = 'Luminohelix', closer = 'Stone' },
	Gravitation = { opener = 'Aero', closer = 'Noctohelix' },
}

local function trimmed(value)
	return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function family_matches(name, prefix)
	if name == prefix then
		return true
	end
	local suffix = name:match('^' .. prefix .. '%s+([IVX]+)$')
	return suffix ~= nil
end

function M.spell_property(spell_name)
	local name = trimmed(spell_name)
	if name == '' then
		return nil
	end
	for i = 1, #spell_families do
		local family = spell_families[i]
		if family_matches(name, family.prefix) then
			return family.property
		end
	end
	return nil
end

local function normalized_result(value)
	local ok, _key, property = pcall(skillchain_state.normalize_skillchain_target, value)
	if not ok or property == nil then
		return nil
	end
	return property
end

function M.canonical_recipe(result)
	local normalized = normalized_result(result)
	local recipe = normalized and canonical_recipes[normalized] or nil
	if recipe == nil then
		return nil
	end
	return {
		result = normalized,
		opener = recipe.opener,
		closer = recipe.closer,
	}
end

function M.supported_results()
	return { 'Fusion', 'Fragmentation', 'Distortion', 'Gravitation' }
end

function M.validate_plan(plan)
	if type(plan) ~= 'table' then
		return nil, 'plan_not_table'
	end
	local result = normalized_result(plan.result)
	if result == nil then
		return nil, 'result_unsupported'
	end
	local opener = trimmed(plan.opener)
	local closer = trimmed(plan.closer)
	if opener == '' and closer == '' then
		local recipe = M.canonical_recipe(result)
		if recipe == nil then
			return nil, 'canonical_recipe_unavailable'
		end
		opener = recipe.opener
		closer = recipe.closer
	elseif opener == '' or closer == '' then
		return nil, 'opener_and_closer_must_be_paired'
	end
	local opener_property = M.spell_property(opener)
	if opener_property == nil then
		return nil, 'opener_spell_unsupported'
	end
	local closer_property = M.spell_property(closer)
	if closer_property == nil then
		return nil, 'closer_spell_unsupported'
	end
	local transition = skillchain_state.resolve_properties({ opener_property }, { closer_property })
	if type(transition) ~= 'table' or transition.property ~= result then
		return nil, 'recipe_does_not_create_result'
	end
	return {
		result = result,
		opener = opener,
		closer = closer,
		opener_property = opener_property,
		closer_property = closer_property,
	}, ''
end

function M.default_plan()
	return { result = 'Fusion' }
end

function M.plans(config)
	local skillchain = type(config) == 'table'
		and type(config.offense) == 'table'
		and type(config.offense.skillchain) == 'table'
		and config.offense.skillchain or nil
	if skillchain == nil then
		return {}
	end
	local configured = skillchain.plans
	if type(configured) ~= 'table' or #configured == 0 then
		configured = { M.default_plan() }
	end
	local out = {}
	for i = 1, #configured do
		local plan = M.validate_plan(configured[i])
		if plan ~= nil then
			out[#out + 1] = plan
		end
	end
	return out
end

return M
