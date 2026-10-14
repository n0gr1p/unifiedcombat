local uc_active_config = require('uc_active_config')
local uc_follow_config = require('uc_follow_config')

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
    local config = uc_active_config.get_config()
    if type(config) == 'table' then
        local fight = uc_follow_config.fight(config)
        if type(fight) == 'table' then
            return fight.leader == true
        end
    end
    local s = settings_or_default(settings)
    return truthy(s.fight_leader)
end

function M.fight_leader_id(settings)
    local config = uc_active_config.get_config()
    if type(config) == 'table' and type(uc_follow_config.fight(config)) == 'table' then
        return uc_follow_config.fight_leader_id(config)
    end
    local s = settings_or_default(settings)
    local name = trim_string(s.fight_leader_name)
    if name ~= '' then
        local id = resolve_party_member_id_by_name(name)
        if id > 0 then return id end
    end
    return tonumber(s.fight_leader_id) or 0
end

function M.fight_leader_name(settings)
    local config = uc_active_config.get_config()
    if type(config) == 'table' and type(uc_follow_config.fight(config)) == 'table' then
        local name = uc_follow_config.fight_leader_name(config)
        if name ~= '' then return name end
        return resolve_party_member_name_by_id(uc_follow_config.fight_leader_id(config))
    end
    local s = settings_or_default(settings)
    local name = trim_string(s.fight_leader_name)
    if name ~= '' then return name end
    return resolve_party_member_name_by_id(s.fight_leader_id)
end

function M.add_priority_names(settings)
    local targeting = uc_active_config.get_path('config.targeting')
    if type(targeting) == 'table' then
        local names = targeting.targets
        if type(names) ~= 'table' then
            names = targeting.add_priority_names
        end
        -- An explicit empty canonical list is authoritative.
        return normalize_name_list(clone_array(names), nil)
    end
    local s = settings_or_default(settings)
    return normalize_name_list(rawget(s, 'add_priority_names'), nil)
end

function M.sleep_enabled(settings)
    local active_value = uc_active_config.get_path('config.sleep.enabled')
    if active_value ~= nil then
        return active_value == true
    end
    return truthy(settings_or_default(settings).sleep)
end

function M.sleep_spell_names(settings)
    local sleep = uc_active_config.get_path('config.sleep')
    if type(sleep) == 'table' then
        return normalize_name_list(clone_array(sleep.order), sleep.legacy_primary)
    end
    local s = settings_or_default(settings)
    return normalize_name_list(rawget(s, 'sleepspells'), rawget(s, 'sleepspell'))
end

return M
