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

-- Canonical autonomous two-step Immanence recipes define only the skillchain
-- families. Profiles may override either exact spell independently without
-- duplicating the other side of the recipe.
local canonical_recipes = {
	Fusion = { opener = 'Fire', closer = 'Thunder' },
	Fragmentation = { opener = 'Blizzard', closer = 'Water' },
	Distortion = { opener = 'Luminohelix', closer = 'Stone' },
	Gravitation = { opener = 'Aero', closer = 'Noctohelix' },
}

local addendum_black_spells = {
	['Stone IV'] = true,
	['Stone V'] = true,
	['Water IV'] = true,
	['Water V'] = true,
	['Aero IV'] = true,
	['Aero V'] = true,
	['Fire IV'] = true,
	['Fire V'] = true,
	['Blizzard IV'] = true,
	['Blizzard V'] = true,
	['Thunder IV'] = true,
	['Thunder V'] = true,
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

function M.requires_addendum_black(spell_name)
	return addendum_black_spells[trimmed(spell_name)] == true
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
	local recipe = M.canonical_recipe(result)
	if recipe == nil then
		return nil, 'canonical_recipe_unavailable'
	end
	local opener = trimmed(plan.opener)
	local closer = trimmed(plan.closer)
	if opener == '' then
		opener = recipe.opener
	end
	if closer == '' then
		closer = recipe.closer
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
		requires_addendum_black = M.requires_addendum_black(opener)
			or M.requires_addendum_black(closer),
	}, ''
end

-- Return timing/generation evidence when the current target already carries a
-- skillchain property that the configured closer can extend into the configured
-- result. This lets SCH spend only the closer Immanence instead of recreating
-- an opener that the party has already supplied.
function M.compatible_existing_opener(plan, snapshot, now)
	if type(plan) ~= 'table' then
		return nil, 'plan_not_table'
	end
	if type(snapshot) ~= 'table' then
		return nil, 'skillchain_snapshot_missing'
	end
	if snapshot.terminal == true then
		return nil, 'skillchain_snapshot_terminal'
	end
	local generation = tonumber(snapshot.generation) or 0
	local properties = snapshot.active_properties
	if generation <= 0 or type(properties) ~= 'table' or #properties == 0 then
		return nil, 'skillchain_snapshot_no_properties'
	end
	local current_time = tonumber(now) or 0
	local latest_safe_at = tonumber(snapshot.latest_safe_at)
		or tonumber(snapshot.expires_at) or 0
	if latest_safe_at <= current_time then
		return nil, 'skillchain_close_window_expired'
	end
	local transition = skillchain_state.resolve_properties(
		properties,
		{ plan.closer_property },
		snapshot.chainbound_level
	)
	if type(transition) ~= 'table' or transition.property ~= plan.result then
		return nil, 'skillchain_snapshot_incompatible'
	end
	return {
		generation = generation,
		execute_at = tonumber(snapshot.preferred_execute_at)
			or tonumber(snapshot.earliest_close_at) or current_time,
		latest_safe_at = latest_safe_at,
		predicted_result = transition.property,
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