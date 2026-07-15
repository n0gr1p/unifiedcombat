local uc_active_config = require('uc_active_config')

local M = {}

local function settings_or_default(settings)
    if type(settings) == 'table' then
        return settings
    end
    return rawget(_G, 'UC_SETTINGS') or {}
end

local function truthy(value)
    if value == true or value == 1 then
        return true
    end
    if type(value) == 'string' then
        local lowered = value:lower()
        return lowered == 'true' or lowered == 'on' or lowered == '1' or lowered == 'yes'
    end
    return false
end

local function trim_string(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function clone_array(source)
    local out = {}
    if type(source) ~= 'table' then
        return out
    end
    for i = 1, #source do
        out[i] = source[i]
    end
    return out
end

local function normalize_name_list(values, legacy_single)
    local out = {}
    local seen = {}

    local function append_name(raw)
        local name = trim_string(raw)
        if name == '' then
            return
        end
        local key = name:lower()
        if seen[key] then
            return
        end
        seen[key] = true
        out[#out + 1] = name
    end

    if type(values) == 'table' then
        for i = 1, #values do
            append_name(values[i])
        end
    elseif type(values) == 'string' then
        append_name(values)
    end

    if #out == 0 then
        append_name(legacy_single)
    end

	return out
end

local function resolve_party_member_id_by_name(name)
	local trimmed = trim_string(name)
	if trimmed == '' then
		return 0
	end

	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	if type(ffxi) ~= 'table' then
		return 0
	end

	local get_party = ffxi.get_party
	if type(get_party) == 'function' then
		local ok_party, party = pcall(get_party)
		if ok_party and type(party) == 'table' then
			for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
				local entry = party[key]
				local mob = entry and entry.mob
				if mob and type(mob.name) == 'string' and mob.name == trimmed then
					local mob_id = tonumber(mob.id) or 0
					if mob_id > 0 then
						return mob_id
					end
				end
			end
		end
	end

	local get_mob_by_name = ffxi.get_mob_by_name
	if type(get_mob_by_name) == 'function' then
		local ok_mob, mob = pcall(get_mob_by_name, trimmed)
		if ok_mob and mob then
			local mob_id = tonumber(mob.id) or 0
			if mob_id > 0 then
				return mob_id
			end
		end
	end

	return 0
end

local function resolve_party_member_name_by_id(id)
	local member_id = tonumber(id) or 0
	if member_id <= 0 then
		return nil
	end

	local windower_ref = rawget(_G, 'windower')
	local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
	if type(ffxi) ~= 'table' then
		return nil
	end

	local get_party = ffxi.get_party
	if type(get_party) == 'function' then
		local ok_party, party = pcall(get_party)
		if ok_party and type(party) == 'table' then
			for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
				local entry = party[key]
				local mob = entry and entry.mob
				if mob and tonumber(mob.id) == member_id then
					local name = trim_string(mob.name)
					if name ~= '' then
						return name
					end
				end
			end
		end
	end

	return nil
end

function M.fight_leader_enabled(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'fight_leader')
    if flat_value ~= nil then
        return truthy(flat_value)
    end
    local active_value = uc_active_config.get_path('config.follow.fight.leader')
    if active_value ~= nil then
        return active_value == true
    end
    return truthy(s.fight_leader)
end

function M.fight_leader_id(settings)
	local s = settings_or_default(settings)
	local flat_name = rawget(s, 'fight_leader_name')
	if type(flat_name) == 'string' and trim_string(flat_name) ~= '' then
		local flat_name_id = resolve_party_member_id_by_name(flat_name)
		if flat_name_id > 0 then
			return flat_name_id
		end
	end
	local flat_value = rawget(s, 'fight_leader_id')
	if flat_value ~= nil then
		return tonumber(flat_value) or 0
	end
	local active_name = uc_active_config.get_path('config.follow.fight.leader_name')
	if type(active_name) == 'string' and trim_string(active_name) ~= '' then
		local active_name_id = resolve_party_member_id_by_name(active_name)
		if active_name_id > 0 then
			return active_name_id
		end
	end
	local active_value = uc_active_config.get_path('config.follow.fight.leader_id')
	if active_value ~= nil then
		return tonumber(active_value) or 0
	end
	return tonumber(s.fight_leader_id) or 0
end

function M.fight_leader_name(settings)
	local s = settings_or_default(settings)
	local flat_name = rawget(s, 'fight_leader_name')
	if type(flat_name) == 'string' and trim_string(flat_name) ~= '' then
		return trim_string(flat_name)
	end
	local flat_id_name = resolve_party_member_name_by_id(rawget(s, 'fight_leader_id'))
	if type(flat_id_name) == 'string' and flat_id_name ~= '' then
		return flat_id_name
	end
	local active_name = uc_active_config.get_path('config.follow.fight.leader_name')
	if type(active_name) == 'string' and trim_string(active_name) ~= '' then
		return trim_string(active_name)
	end
	local active_id = uc_active_config.get_path('config.follow.fight.leader_id')
	local active_name_from_id = resolve_party_member_name_by_id(active_id)
	if type(active_name_from_id) == 'string' and active_name_from_id ~= '' then
		return active_name_from_id
	end
	return nil
end

function M.add_priority_names(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'add_priority_names')
    if flat_value ~= nil then
        return normalize_name_list(flat_value, nil)
    end
    local active_value = uc_active_config.get_path('config.targeting.add_priority_names')
    if active_value ~= nil then
        return normalize_name_list(clone_array(active_value), nil)
    end
    return normalize_name_list(s.add_priority_names, nil)
end

function M.sleep_enabled(settings)
    local s = settings_or_default(settings)
    local flat_value = rawget(s, 'sleep')
    if flat_value ~= nil then
        return truthy(flat_value)
    end
    local active_value = uc_active_config.get_path('config.sleep.enabled')
    if active_value ~= nil then
        return active_value == true
    end
    return truthy(s.sleep)
end

function M.sleep_spell_names(settings)
    local s = settings_or_default(settings)
    if rawget(s, 'sleepspells') ~= nil or rawget(s, 'sleepspell') ~= nil then
        return normalize_name_list(rawget(s, 'sleepspells'), rawget(s, 'sleepspell'))
    end

    local active_order = uc_active_config.get_path('config.sleep.order')
    local active_primary = uc_active_config.get_path('config.sleep.legacy_primary')
    if active_order ~= nil or active_primary ~= nil then
        return normalize_name_list(clone_array(active_order), active_primary)
    end

    return normalize_name_list(s.sleepspells, s.sleepspell)
end

return M
