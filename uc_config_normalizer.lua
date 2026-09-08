local M = {}
local uc_sch_config = require('uc_sch_config')
local uc_pup_config = require('uc_pup_config')

local CURRENT_CANONICAL_CONFIG_VERSION = 1

local DEFAULT_SLEEP_ORDER = { 'Horde Lullaby II' }

local DEFAULT_GEO_MAINTENANCE = {
    enabled = false,
    geo_spell = nil,
    geo_target = {
        kind = 'current_enemy',
        name = nil,
    },
    indi_spell = nil,
    ordering = 'geo_first',
    require_camp = true,
    camp_tolerance_yalms = 1.0,
    enemy_geo_requires_camp_radius = false,
    unknown_existing_policy = 'wait_for_clear',
    entrust = {
        enabled = false,
        spell = nil,
        target_name = nil,
    },
    luopan = {
        placement = 'target',
        use_blaze_of_glory = false,
        use_ecliptic_attrition = false,
        use_life_cycle = false,
        life_cycle_hpp = 50,
        replace_out_of_position = false,
        max_camp_distance_yalms = 6.0,
    },
}

local DEFAULT_CAMP_PULLING = {
    enabled = false,
    mode = 'camp',
    action = {
        type = 'spell',
        name = nil,
    },
    targets = {},
    match_mode = 'exact',
    max_active_mobs = 1,
    replenish_below_hpp = 20,
    leash_yalms = 35.0,
    max_z_delta = 2.0,
    cast_range_ratio = 0.90,
    settle_seconds = 0.40,
    reaction_timeout_seconds = 4.0,
    retry_limit = 2,
    retry_window_seconds = 2.5,
    target_cooldown_seconds = 20.0,
    camp_arrival_yalms = 0.75,
}

local function path(...)
    return { ... }
end

local function is_table(value)
    return type(value) == 'table'
end

local function trim_string(value)
    if type(value) ~= 'string' then
        return ''
    end
    return (value:match('^%s*(.-)%s*$') or '')
end

local function normalize_optional_string(value)
    local trimmed = trim_string(value)
    if trimmed == '' then
        return nil
    end
    return trimmed
end

local function normalize_string(value, default_value)
    local trimmed = trim_string(value)
    if trimmed == '' then
        return default_value
    end
    return trimmed
end

local function normalize_boolean(value, default_value)
    if value == true or value == false then
        return value
    end
    if type(value) == 'number' then
        if value == 0 then
            return false
        elseif value == 1 then
            return true
        end
        return default_value
    end
    if type(value) == 'string' then
        local lowered = trim_string(value):lower()
        if lowered == 'true' or lowered == 'on' or lowered == 'yes' or lowered == '1' then
            return true
        elseif lowered == 'false' or lowered == 'off' or lowered == 'no' or lowered == '0' then
            return false
        end
    end
    return default_value
end

local function normalize_number(value, default_value, options)
    local n = nil
    if type(value) == 'number' then
        n = value
    elseif type(value) == 'string' then
        n = tonumber(trim_string(value))
    end
    if n == nil then
        return default_value
    end
    local opts = options or {}
    if opts.integer == true then
        n = math.floor(n + 0.5)
    end
    if opts.min ~= nil and n < opts.min then
        n = opts.min
    end
    if opts.max ~= nil and n > opts.max then
        n = opts.max
    end
    return n
end

local function clone_value(value, seen)
    local value_type = type(value)
    if value_type ~= 'table' then
        return value
    end

    local visited = seen or {}
    if visited[value] then
        return {}
    end

    visited[value] = true
    local out = {}
    for key, inner_value in pairs(value) do
        local key_type = type(key)
        local cloned_key = key
        if key_type ~= 'string' and key_type ~= 'number' and key_type ~= 'boolean' then
            cloned_key = tostring(key)
        end
        out[cloned_key] = clone_value(inner_value, visited)
    end
    visited[value] = nil
    return out
end

local function normalize_list(value, default_value)
    if type(value) == 'table' then
        return clone_value(value)
    end
    if type(value) == 'string' then
        local trimmed = trim_string(value)
        if trimmed ~= '' then
            return { trimmed }
        end
    end
    return clone_value(default_value)
end

local function normalize_leash_source(value, default_value)
	local normalized = normalize_string(value, default_value):lower()
	if normalized ~= 'player' and normalized ~= 'camp' then
		error('follow.partner.leash_source must be player or camp')
	end
	return normalized
end

local function normalize_pipe_string_list(value, default_value)
    if type(value) == 'table' then
        local out = {}
        for i = 1, #value do
            local item = type(value[i]) == 'string' and trim_string(value[i]) or ''
            if item ~= '' then
                out[#out + 1] = item
            end
        end
        return out
    end
    if type(value) == 'string' then
        local out = {}
        for item in value:gmatch('[^|]+') do
            item = trim_string(item)
            if item ~= '' then
                out[#out + 1] = item
            end
        end
        return out
    end
    return clone_value(default_value or {})
end

local function normalize_summoner_ward_actions(value, path_name)
	if value == nil then
		return {}
	end
	local raw_actions = {}
	if type(value) == 'table' then
		local count = 0
		for key in pairs(value) do
			count = count + 1
			if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then
				error(path_name .. ' must be a contiguous array of strings')
			end
		end
		if count ~= #value then
			error(path_name .. ' must be a contiguous array of strings')
		end
		for i = 1, #value do
			raw_actions[#raw_actions + 1] = value[i]
		end
	elseif type(value) == 'string' then
		if value == '' then
			return {}
		end
		if value:sub(1, 1) == '|' or value:sub(-1) == '|' or value:find('||', 1, true) then
			error(path_name .. ' contains an empty action')
		end
		for action in value:gmatch('[^|]+') do
			raw_actions[#raw_actions + 1] = action
		end
	else
		error(path_name .. ' must be an array or pipe-delimited string')
	end
	local actions = {}
	local seen = {}
	for i = 1, #raw_actions do
		if type(raw_actions[i]) ~= 'string' then
			error(path_name .. ' entries must be strings')
		end
		local action = trim_string(raw_actions[i])
		if action == '' then
			error(path_name .. ' entries must be non-empty strings')
		end
		if seen[action] then
			error(('%s duplicates %q'):format(path_name, action))
		end
		seen[action] = true
		actions[#actions + 1] = action
	end
	return actions
end

local function normalize_targeted_buffs(value, default_value)
    if value == nil then
        return clone_value(default_value)
    end

    local out = {}
    local function append_entry(character, buff)
        local target_name = normalize_optional_string(character)
        local buff_name = normalize_optional_string(buff)
        if target_name ~= nil and buff_name ~= nil then
            out[#out + 1] = {
                character = target_name,
                buff = buff_name,
            }
        end
    end

    if type(value) == 'table' then
        for i = 1, #value do
            local entry = value[i]
            if type(entry) == 'table' then
                append_entry(entry.character or entry.target or entry.name, entry.buff or entry.action)
            end
        end
        return out
    end

    if type(value) == 'string' then
        for token in tostring(value):gmatch('[^|]+') do
            local entry = trim_string(token)
            if entry ~= '' then
                local separator = entry:find(':', 1, true)
                if separator and separator > 1 and separator < #entry then
                    append_entry(entry:sub(1, separator - 1), entry:sub(separator + 1))
                end
            end
        end
    end

    return out
end

local function normalize_brd_targeted_songs(value, default_value)
    if value == nil then
        return clone_value(default_value or {})
    end

    local out = {}
    local function append_invalid_entry()
        out[#out + 1] = {
            recipients = {},
            priority_songs = {},
        }
    end
    local function split_csv(text)
        local values = {}
        for token in tostring(text or ''):gmatch('[^,]+') do
            local item = trim_string(token)
            if item ~= '' then
                values[#values + 1] = item
            end
        end
        return values
    end
    local function append_entry(recipients, priority_songs)
        local normalized_recipients = type(recipients) == 'table'
            and normalize_pipe_string_list(recipients, {}) or split_csv(recipients)
        local normalized_songs = type(priority_songs) == 'table'
            and normalize_pipe_string_list(priority_songs, {}) or split_csv(priority_songs)
        if #normalized_recipients > 0 and #normalized_songs > 0 then
            out[#out + 1] = {
                recipients = normalized_recipients,
                priority_songs = normalized_songs,
            }
        else
            append_invalid_entry()
        end
    end

    if type(value) == 'table' then
		if #value == 0 and next(value) ~= nil then
			append_invalid_entry()
			return out
		end
        for i = 1, #value do
            local entry = value[i]
            if type(entry) == 'table' then
                append_entry(entry.recipients, entry.priority_songs or entry.songs)
            else
                append_invalid_entry()
            end
        end
        return out
    end

    if type(value) == 'string' then
        for token in value:gmatch('[^|]+') do
            local entry = trim_string(token)
            local separator = entry:find(':', 1, true)
            if separator and separator > 1 and separator < #entry then
                append_entry(entry:sub(1, separator - 1), entry:sub(separator + 1))
            else
                append_invalid_entry()
            end
        end
		if trim_string(value) ~= '' and #out == 0 then
			append_invalid_entry()
		end
        return out
    end

    append_invalid_entry()
    return out
end

local function normalize_reaction_rules(value)
    local out = {}
    local seen = {}
    if type(value) ~= 'table' then
        return out
    end
    for i = 1, #value do
        local entry = value[i]
        if type(entry) == 'table' then
            local trigger = normalize_optional_string(entry.trigger)
            local name = normalize_optional_string(entry.name)
            local response = normalize_optional_string(entry.response)
            local valid = (trigger == 'ability_window'
                    and (response == 'turn_away' or response == 'run_away' or response == 'move_to_range' or response == 'use_action'))
                or (trigger == 'enemy_buff' and response == 'stop_attacking')
            local key = trigger and name and (trigger .. ':' .. name:lower()) or nil
            if valid and name ~= nil and key ~= nil and not seen[key] then
                seen[key] = true
                local normalized = {
                    trigger = trigger,
                    name = name,
                    response = response,
                }
                if response == 'run_away' or response == 'move_to_range' then
                    if type(entry.distance) ~= 'number'
                        or entry.distance ~= entry.distance
                        or entry.distance == math.huge
                        or entry.distance == -math.huge
                        or entry.distance <= 0 then
                        error(('reactions.rules[%d].distance must be a finite number greater than zero for %s'):format(i, response))
                    end
                    normalized.distance = entry.distance
                elseif response == 'use_action' then
                    local action_type = normalize_optional_string(entry.action_type)
                    local action_name = normalize_optional_string(entry.action_name)
                    if action_type ~= 'spell' then
                        error(('reactions.rules[%d].action_type must be spell for use_action'):format(i))
                    end
                    if action_name == nil then
                        error(('reactions.rules[%d].action_name is required for use_action'):format(i))
                    end
                    normalized.action_type = action_type
                    normalized.action_name = action_name
                end
                out[#out + 1] = normalized
            end
        end
    end
    return out
end

local function get_path(root, segments)
    local current = root
    for i = 1, #segments do
        if type(current) ~= 'table' then
            return nil
        end
        current = rawget(current, segments[i])
        if current == nil then
            return nil
        end
    end
    return current
end

local function first_path(root, candidates)
    for i = 1, #candidates do
        local value = get_path(root, candidates[i])
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function canonical_alias_value(canonical_value, legacy_value, canonical_path, legacy_path)
    if canonical_value ~= nil and legacy_value ~= nil and canonical_value ~= legacy_value then
        error(('%s conflicts with legacy alias %s'):format(canonical_path, legacy_path))
    end
    if canonical_value ~= nil then
        return canonical_value
    end
    return legacy_value
end

local function table_has_any(value, keys)
    if type(value) ~= 'table' then
        return false
    end
    for i = 1, #keys do
        if rawget(value, keys[i]) ~= nil then
            return true
        end
    end
    return false
end

local function strict_boolean(value, default_value, field_name)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'boolean' then
        error(field_name .. ' must be boolean')
    end
    return value
end

local function strict_optional_string(value, default_value, field_name)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'string' then
        error(field_name .. ' must be a string or nil')
    end
    local normalized = trim_string(value)
    if normalized == '' then
        return nil
    end
    return normalized
end

local function strict_number(value, default_value, field_name, min_value, max_value)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
        error(field_name .. ' must be a finite number')
    end
    if value < min_value or value > max_value then
        error(string.format('%s must be between %.1f and %.1f', field_name, min_value, max_value))
    end
    return value
end

local function strict_enum(value, default_value, field_name, allowed)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'string' or allowed[value] ~= true then
        error(field_name .. ' has an unsupported value')
    end
    return value
end

local function migrate_geo_maintenance_list(value)
    local entries = {}
    if type(value) == 'string' then
        entries[1] = value
    elseif type(value) == 'table' then
        for key in pairs(value) do
            if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then
                error('maintenance.geo legacy configuration must be a list of spell names')
            end
        end
        for i = 1, #value do
            entries[i] = value[i]
        end
    else
        error('maintenance.geo must be a structured table or legacy spell list')
    end

    local migrated = clone_value(DEFAULT_GEO_MAINTENANCE)
    for i = 1, #entries do
        local spell_name = entries[i]
        if type(spell_name) ~= 'string' or trim_string(spell_name) == '' then
            error('maintenance.geo legacy entries must be non-empty strings')
        end
        spell_name = trim_string(spell_name)
        if spell_name:match('^Geo%-') then
            if migrated.geo_spell ~= nil then
                error('maintenance.geo legacy list contains more than one Geo- spell')
            end
            migrated.geo_spell = spell_name
        elseif spell_name:match('^Indi%-') then
            if migrated.indi_spell ~= nil then
                error('maintenance.geo legacy list contains more than one Indi- spell')
            end
            migrated.indi_spell = spell_name
        else
            error('maintenance.geo legacy list contains an unrecognized spell: ' .. spell_name)
        end
    end

    -- The legacy list was observational only. Migration must not silently make
    -- GEO maintenance executable.
    migrated.enabled = false
    return migrated
end

local function normalize_geo_maintenance(value)
    if value == nil then
        return clone_value(DEFAULT_GEO_MAINTENANCE)
    end
    if type(value) == 'string' then
        return migrate_geo_maintenance_list(value)
    end
    if type(value) ~= 'table' then
        error('maintenance.geo must be a structured table or legacy spell list')
    end

    local structured_keys = {
        'enabled',
        'geo_spell',
        'geo_target',
        'indi_spell',
        'ordering',
        'require_camp',
        'camp_tolerance_yalms',
        'enemy_geo_requires_camp_radius',
        'unknown_existing_policy',
        'entrust',
        'luopan',
    }
    if not table_has_any(value, structured_keys) then
        if next(value) == nil then
            return clone_value(DEFAULT_GEO_MAINTENANCE)
        end
        return migrate_geo_maintenance_list(value)
    end

    local out = clone_value(DEFAULT_GEO_MAINTENANCE)
    out.enabled = strict_boolean(value.enabled, out.enabled, 'maintenance.geo.enabled')
    out.geo_spell = strict_optional_string(value.geo_spell, out.geo_spell, 'maintenance.geo.geo_spell')
    out.indi_spell = strict_optional_string(value.indi_spell, out.indi_spell, 'maintenance.geo.indi_spell')
    out.ordering = strict_enum(value.ordering, out.ordering, 'maintenance.geo.ordering', {
        geo_first = true,
        indi_first = true,
    })
    out.require_camp = strict_boolean(value.require_camp, out.require_camp, 'maintenance.geo.require_camp')
    out.camp_tolerance_yalms = strict_number(
        value.camp_tolerance_yalms,
        out.camp_tolerance_yalms,
        'maintenance.geo.camp_tolerance_yalms',
        0.0,
        50.0
    )
    out.enemy_geo_requires_camp_radius = strict_boolean(
        value.enemy_geo_requires_camp_radius,
        out.enemy_geo_requires_camp_radius,
        'maintenance.geo.enemy_geo_requires_camp_radius'
    )
    out.unknown_existing_policy = strict_enum(
        value.unknown_existing_policy,
        out.unknown_existing_policy,
        'maintenance.geo.unknown_existing_policy',
        { wait_for_clear = true }
    )

    if value.geo_target ~= nil and type(value.geo_target) ~= 'table' then
        error('maintenance.geo.geo_target must be a table')
    end
    local geo_target = value.geo_target or {}
    out.geo_target.kind = strict_enum(
        geo_target.kind,
        out.geo_target.kind,
        'maintenance.geo.geo_target.kind',
        {
            current_enemy = true,
            self = true,
            party_member = true,
        }
    )
    out.geo_target.name = strict_optional_string(
        geo_target.name,
        out.geo_target.name,
        'maintenance.geo.geo_target.name'
    )
    if out.geo_target.kind == 'party_member' and out.geo_target.name == nil then
        error('maintenance.geo.geo_target.name is required for party_member')
    end
    if out.geo_target.kind ~= 'party_member' and out.geo_target.name ~= nil then
        error('maintenance.geo.geo_target.name is only valid for party_member')
    end

    if value.entrust ~= nil and type(value.entrust) ~= 'table' then
        error('maintenance.geo.entrust must be a table')
    end
    local entrust = value.entrust or {}
    out.entrust.enabled = strict_boolean(entrust.enabled, out.entrust.enabled, 'maintenance.geo.entrust.enabled')
    out.entrust.spell = strict_optional_string(entrust.spell, out.entrust.spell, 'maintenance.geo.entrust.spell')
    out.entrust.target_name = strict_optional_string(
        entrust.target_name,
        out.entrust.target_name,
        'maintenance.geo.entrust.target_name'
    )
    if out.entrust.enabled and (out.entrust.spell == nil or out.entrust.target_name == nil) then
        error('maintenance.geo.entrust requires spell and target_name when enabled')
    end
    if out.entrust.spell ~= nil and not out.entrust.spell:match('^Indi%-') then
        error('maintenance.geo.entrust.spell must be an exact Indi- spell name')
    end

    if value.luopan ~= nil and type(value.luopan) ~= 'table' then
        error('maintenance.geo.luopan must be a table')
    end
    local luopan = value.luopan or {}
    out.luopan.placement = strict_enum(
        luopan.placement,
        out.luopan.placement,
        'maintenance.geo.luopan.placement',
        {
            target = true,
            camp = true,
        }
    )
    out.luopan.use_blaze_of_glory = strict_boolean(
        luopan.use_blaze_of_glory,
        out.luopan.use_blaze_of_glory,
        'maintenance.geo.luopan.use_blaze_of_glory'
    )
    out.luopan.use_ecliptic_attrition = strict_boolean(
        luopan.use_ecliptic_attrition,
        out.luopan.use_ecliptic_attrition,
        'maintenance.geo.luopan.use_ecliptic_attrition'
    )
    out.luopan.use_life_cycle = strict_boolean(
        luopan.use_life_cycle,
        out.luopan.use_life_cycle,
        'maintenance.geo.luopan.use_life_cycle'
    )
    out.luopan.life_cycle_hpp = strict_number(
        luopan.life_cycle_hpp,
        out.luopan.life_cycle_hpp,
        'maintenance.geo.luopan.life_cycle_hpp',
        1.0,
        99.0
    )
    out.luopan.replace_out_of_position = strict_boolean(
        luopan.replace_out_of_position,
        out.luopan.replace_out_of_position,
        'maintenance.geo.luopan.replace_out_of_position'
    )
    out.luopan.max_camp_distance_yalms = strict_number(
        luopan.max_camp_distance_yalms,
        out.luopan.max_camp_distance_yalms,
        'maintenance.geo.luopan.max_camp_distance_yalms',
        0.1,
        50.0
    )
    if out.enabled then
        if out.geo_spell == nil or not out.geo_spell:match('^Geo%-') then
            error('maintenance.geo.geo_spell must be an exact Geo- spell name when enabled')
        end
        if out.indi_spell == nil or not out.indi_spell:match('^Indi%-') then
            error('maintenance.geo.indi_spell must be an exact Indi- spell name when enabled')
        end
    elseif out.geo_spell ~= nil and not out.geo_spell:match('^Geo%-') then
        error('maintenance.geo.geo_spell must be an exact Geo- spell name')
    elseif out.indi_spell ~= nil and not out.indi_spell:match('^Indi%-') then
        error('maintenance.geo.indi_spell must be an exact Indi- spell name')
    end

    return out
end

local function strict_integer(value, default_value, field_name, min_value, max_value)
    local number = strict_number(value, default_value, field_name, min_value, max_value)
    if number ~= math.floor(number) then
        error(field_name .. ' must be an integer')
    end
    return number
end

local function normalize_pull_targets(value)
    if value == nil then
        return {}
    end
    if type(value) ~= 'table' then
        error('combat.pulling.targets must be a list')
    end
    local out = {}
    local seen = {}
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then
            error('combat.pulling.targets must be a list')
        end
    end
    for i = 1, #value do
        local entry = value[i]
        if type(entry) ~= 'table' then
            error(('combat.pulling.targets[%d] must be a table'):format(i))
        end
        local name = strict_optional_string(entry.name, nil, ('combat.pulling.targets[%d].name'):format(i))
        if name == nil then
            error(('combat.pulling.targets[%d].name is required'):format(i))
        end
        local key = name:lower()
        if seen[key] then
            error('combat.pulling.targets contains duplicate name: ' .. name)
        end
        seen[key] = true
        out[#out + 1] = {
            name = name,
            priority = strict_integer(
                entry.priority,
                0,
                ('combat.pulling.targets[%d].priority'):format(i),
                -1000,
                1000
            ),
        }
    end
    return out
end

local function normalize_camp_pulling(value)
    if value == nil then
        return clone_value(DEFAULT_CAMP_PULLING)
    end
    if type(value) ~= 'table' then
        error('combat.pulling must be a table')
    end
    local out = clone_value(DEFAULT_CAMP_PULLING)
    out.enabled = strict_boolean(value.enabled, out.enabled, 'combat.pulling.enabled')
    out.mode = strict_enum(value.mode, out.mode, 'combat.pulling.mode', { camp = true })
    if value.action ~= nil and type(value.action) ~= 'table' then
        error('combat.pulling.action must be a table')
    end
    local action = value.action or {}
    out.action.type = strict_enum(action.type, out.action.type, 'combat.pulling.action.type', {
        spell = true,
        ja = true,
    })
    out.action.name = strict_optional_string(action.name, out.action.name, 'combat.pulling.action.name')
    out.targets = normalize_pull_targets(value.targets)
    out.match_mode = strict_enum(value.match_mode, out.match_mode, 'combat.pulling.match_mode', {
        exact = true,
        substring = true,
    })
    out.max_active_mobs = strict_integer(
        value.max_active_mobs,
        out.max_active_mobs,
        'combat.pulling.max_active_mobs',
        1,
        20
    )
    out.replenish_below_hpp = strict_integer(
        value.replenish_below_hpp,
        out.replenish_below_hpp,
        'combat.pulling.replenish_below_hpp',
        0,
        100
    )
    out.leash_yalms = strict_number(value.leash_yalms, out.leash_yalms, 'combat.pulling.leash_yalms', 1.0, 100.0)
    out.max_z_delta = strict_number(value.max_z_delta, out.max_z_delta, 'combat.pulling.max_z_delta', 0.0, 20.0)
    out.cast_range_ratio = strict_number(
        value.cast_range_ratio,
        out.cast_range_ratio,
        'combat.pulling.cast_range_ratio',
        0.1,
        1.0
    )
    out.settle_seconds = strict_number(
        value.settle_seconds,
        out.settle_seconds,
        'combat.pulling.settle_seconds',
        0.0,
        3.0
    )
    out.reaction_timeout_seconds = strict_number(
        value.reaction_timeout_seconds,
        out.reaction_timeout_seconds,
        'combat.pulling.reaction_timeout_seconds',
        0.5,
        30.0
    )
    out.retry_limit = strict_integer(value.retry_limit, out.retry_limit, 'combat.pulling.retry_limit', 0, 10)
    out.retry_window_seconds = strict_number(
        value.retry_window_seconds,
        out.retry_window_seconds,
        'combat.pulling.retry_window_seconds',
        0.1,
        30.0
    )
    out.target_cooldown_seconds = strict_number(
        value.target_cooldown_seconds,
        out.target_cooldown_seconds,
        'combat.pulling.target_cooldown_seconds',
        0.0,
        300.0
    )
    out.camp_arrival_yalms = strict_number(
        value.camp_arrival_yalms,
        out.camp_arrival_yalms,
        'combat.pulling.camp_arrival_yalms',
        0.1,
        10.0
    )
    if out.enabled then
        if out.action.name == nil then
            error('combat.pulling.action.name is required when enabled')
        end
        if #out.targets == 0 then
            error('combat.pulling.targets must not be empty when enabled')
        end
    end
    return out
end

local function normalize_source(settings)
    if not is_table(settings) then
        return {}, {}
    end
    if is_table(settings.config) then
        return settings.config, settings
    end
    return settings, settings
end

local function default_profile(meta)
    local meta_table = is_table(meta) and meta or {}
    return {
        schema_version = CURRENT_CANONICAL_CONFIG_VERSION,
        engine = 'UC',
        character = normalize_optional_string(first_path(meta_table, { path('character'), path('char') })),
        main_job = normalize_optional_string(first_path(meta_table, { path('main_job'), path('job') })),
        sub_job = normalize_optional_string(first_path(meta_table, { path('sub_job') })),
        source = normalize_string(first_path(meta_table, { path('source') }), 'UC_SETTINGS'),
    }
end

local function default_config(meta)
    return {
        profile = default_profile(meta),
        ui = {
            show_ingame_ui = false,
        },
        command = {
            engine_enabled_default = false,
        },
        combat = {
            enabled = true,
            autotarget = false,
            auto_engage = true,
            spam = false,
            closer = false,
            manual = false,
            prime = false,
            static = false,
            face = false,
            weaponskill = {
                enabled = false,
                primary = '',
                mode = 'smart',
                minimum_tp = 1000,
                allow_aoe = true,
                fast_skillchain = false,
                skillchain_target = 'auto',
                wait_ignore_names = {},
                aftermath_enabled = false,
                aftermath_ws = '',
            },
            pulling = clone_value(DEFAULT_CAMP_PULLING),
        },
        abilities = {
            enabled = false,
            configured = {},
            legacy_slots = {},
            wsabilities = {},
        },
        defensive = {
            enabled = false,
            provider = 'internal',
            cure = {
                enabled = false,
                min_tier = 3,
                max_tier = 4,
                min_missing_hp = 250,
                ignore_trusts = true,
                curaga = {
                    enabled = false,
                    min_targets = 3,
                },
            },
            waltz = {
                enabled = false,
                tp_reserve = 0,
                divine_min_targets = 3,
            },
            doom = {
                holy_water_enabled = false,
            },
            charm_sleeper = {
                enabled = false,
            },
            sleep_waker = {
                enabled = false,
            },
            na = {
                enabled = false,
                limit_enabled = false,
                priority = '',
            },
            enemy_buffs = {
                remove = false,
            },
            enemy_debuffs = {
                enabled = false,
                list = '',
            },
            buffs = {
                enabled = false,
                self_only = true,
                list = '',
                targeted = {},
                overwrite_enabled = false,
                overwrite_interval = 150,
            },
            thresholds = {
                critical_hpp = 35,
                medium_hpp = 55,
            },
        },
        encounter = {
            enabled = false,
            id = '',
            policy = {},
            tuning = {},
        },
        movement = {
            enabled = true,
            move = false,
            formation = {
                enabled = false,
                encounter = 'lilith_easy',
                mock = {
                    enabled = false,
                    mob_name = '',
                },
                role = 'disabled',
                tank_name = '',
                required_party_names = {},
                capture_stable_s = 0.50,
                capture_tolerance = 0.10,
                safe_radius = 16.0,
                tank = {
                    accept_radius = 1.5,
                    return_radius = 3.0,
                },
                dps = {
                    flank_angle_deg = 90.0,
                    melee_radius = 3.0,
                    position_tolerance = 1.5,
                },
                healer = {
                    preferred_radius = 12.0,
                    minimum_boss_distance = 8.0,
                    maximum_party_range = 18.0,
                    cone_half_angle_deg = 50.0,
                    cone_safety_margin_deg = 15.0,
                    sample_step_deg = 10.0,
                },
            },
            named_formations = {
                enabled = false,
                entries = {},
            },
            spacing = {
                enabled = false,
                band_min = -0.9,
                band_max = 0.4,
                model_size_floor = 0.9,
                use_prediction = true,
                lookahead_s = 0.25,
                repel_hold_ticks = 5,
                overlap_deadband = 0.10,
                repel_weight = 0.35,
                band_deadband = 0.20,
            },
            path = {
                recording = false,
                follow_enabled = false,
                file_name = '',
                route_type = 'unknown',
                distance_to_start = 0,
                points = {},
                party_gate_yalms = 3.0,
                resume_index_window = 12,
                hunter_targets = {},
                hunter_max_z_delta = 2.0,
                hunter_max_target_range = 20.0,
                hunter_claim_timeout_s = 4.0,
                hunter_ignore_cooldown_s = 20.0,
                pull_action_type = 'ja',
                pull_action_name = '',
            },
        },
        follow = {
            enabled = true,
            party = {
                enabled = false,
                leader_id = 0,
                leader_name = '',
                min = 0.5,
                max = 50,
            },
            fight = {
                leader = false,
                leader_id = 0,
                leader_name = '',
                min = 3.0,
                hold_s = 8.0,
            },
            partner = {
                enabled = false,
                secondary_enabled = false,
                names = {},
                ids = {},
                puller = false,
                puller_name = '',
                puller_id = 0,
				leash_source = 'player',
                engage_range = 6.0,
                puller_distance_only = false,
            },
			nyzul = {
				coordinator_name = '',
				anchor_name = '',
				parking_order = {},
			},
        },
        targeting = {
            add_control = false,
            add_priority_names = {},
            legacy_slots = {},
            targets = {},
            targetability = {
                enabled = false,
                action = '',
            },
            ignore = {},
            target_ignore_names = {},
        },
        reactions = {
            enabled = false,
            rules = {},
        },
        tank = {
            enabled = false,
            enmity = {
                actions = {},
            },
        },
        sleep = {
            enabled = false,
            order = clone_value(DEFAULT_SLEEP_ORDER),
            legacy_primary = DEFAULT_SLEEP_ORDER[1],
            max_target_range = 6.0,
        },
        spells = {
            enabled = false,
            configured = '',
            magic_burst = false,
            dd2_slots = {},
        },
        maintenance = {
            enabled = true,
            cor = {
                roll_1 = '',
                roll_2 = '',
                crooked_roll_slot = 0,
                elevens = false,
                luzaf_range_override = false,
                range_selected = '',
                range_require_ids = {},
            },
            brd = {
                enabled = false,
                songs = {},
                dummy_songs = {},
                use_nitro = false,
                use_soul_voice = false,
                use_clarion_call = false,
                use_marcato = false,
                marcato_song = '',
				targeted_songs = {},
				recovery_range_yalms = 9.9,
				recovery_ignore_names = {},
				reposition_for_party_songs = false,
            },
            geo = clone_value(DEFAULT_GEO_MAINTENANCE),
        },
        puppetmaster = uc_pup_config.default_config(),
        summoner = {
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
        },
        sch = uc_sch_config.default_config(),
        debug = {
            enabled = false,
            combat_sched = false,
            ja_sched = false,
            ja_debug = false,
            def_sched = false,
            tank_sched = false,
        },
        ownership = {
            domain_combat_enabled = true,
            domain_defensive_enabled = true,
            domain_movement_enabled = true,
            domain_maintenance_enabled = true,
            domain_follow_enabled = true,
            pause_automation_while_weakened = false,
        },
        legacy = {
            sub = false,
            sub2 = false,
            solo = false,
            aeonic = false,
            color = false,
            command = false,
            hunter = false,
            profiles = {},
        },
    }
end

local ENCOUNTER_IDS = {
    sortie_ghatjot = true,
    sortie_dhartok = true,
    kei = true,
}

local GENERIC_FORMATION_ENCOUNTER_IDS = {
    sortie_ghatjot = true,
    sortie_dhartok = true,
}

local ENCOUNTER_POLICY_MODES = {
    enforce = true,
    warn = true,
    off = true,
}

local function normalize_encounter_boolean(value, path_name, default_value)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'boolean' then
        error(path_name .. ' must be a boolean')
    end
    return value
end

local function normalize_encounter_id(value, enabled)
    if value == nil then
        if enabled then
            error('enabled encounter requires config.encounter.id')
        end
        return ''
    end
    if type(value) ~= 'string' then
        error('config.encounter.id must be a string')
    end
    local encounter_id = value:match('^%s*(.-)%s*$')
    if encounter_id == '' then
        if enabled then
            error('enabled encounter requires config.encounter.id')
        end
        return ''
    end
    if ENCOUNTER_IDS[encounter_id] ~= true then
        error('config.encounter.id must be sortie_ghatjot, sortie_dhartok, or kei')
    end
    return encounter_id
end

local function normalize_encounter_policy_mode(value, path_name)
    if value == nil then
        return nil
    end
    if type(value) ~= 'string' or ENCOUNTER_POLICY_MODES[value] ~= true then
        error(path_name .. ' must be enforce, warn, or off')
    end
    return value
end

local function normalize_encounter(source, config)
    local nested = get_path(source, { 'encounter' })
    local enabled_value
    local id_value
    local policy_value
    local tuning_value
    local kei_value
    if nested ~= nil then
        if type(nested) ~= 'table' then
            error('config.encounter must be a table')
        end
        enabled_value = nested.enabled
        id_value = nested.id
        policy_value = nested.policy
        tuning_value = nested.tuning
        kei_value = nested.kei
    else
        enabled_value = first_path(source, { path('encounter_enabled') })
        id_value = first_path(source, { path('encounter_id') })
        policy_value = {
            water_damage = first_path(source, { path('encounter_water_damage') }),
            water_skillchain = first_path(source, { path('encounter_water_skillchain') }),
            repeat_action_wall = first_path(source, { path('encounter_repeat_action_wall') }),
        }
        tuning_value = {
            repeat_action_guard_s = first_path(source, { path('encounter_repeat_action_guard_s') }),
        }
        kei_value = {
            elemental_damage = {
                dealer_name = first_path(source, { path('kei_elemental_dealer_name') }),
                water = {
                    probe_spell = first_path(source, { path('kei_water_probe_spell') }),
                    damage_spell = first_path(source, { path('kei_water_damage_spell') }),
                },
                ice = {
                    probe_spell = first_path(source, { path('kei_ice_probe_spell') }),
                    damage_spell = first_path(source, { path('kei_ice_damage_spell') }),
                },
                sustain_interval_s = first_path(source, { path('kei_sustain_interval_s') }),
                probe_timeout_s = first_path(source, { path('kei_probe_timeout_s') }),
            },
            fullers = {
                target_distance = first_path(source, { path('kei_fullers_target_distance') }),
                run_away_distance = first_path(source, { path('kei_fullers_run_away_distance') }),
                prearm_hpp_margin = first_path(source, { path('kei_fullers_prearm_hpp_margin') }),
            },
        }
    end

    local encounter = config.encounter
    encounter.enabled = normalize_encounter_boolean(enabled_value, 'config.encounter.enabled', encounter.enabled)
    encounter.id = normalize_encounter_id(id_value, encounter.enabled)

    if policy_value ~= nil and type(policy_value) ~= 'table' then
        error('config.encounter.policy must be a table')
    end
    local policy = policy_value or {}
    encounter.policy.water_damage = normalize_encounter_policy_mode(
        policy.water_damage,
        'config.encounter.policy.water_damage'
    )
    encounter.policy.water_skillchain = normalize_encounter_policy_mode(
        policy.water_skillchain,
        'config.encounter.policy.water_skillchain'
    )
    encounter.policy.repeat_action_wall = normalize_encounter_policy_mode(
        policy.repeat_action_wall,
        'config.encounter.policy.repeat_action_wall'
    )

    if tuning_value ~= nil and type(tuning_value) ~= 'table' then
        error('config.encounter.tuning must be a table')
    end
    local repeat_guard = tuning_value and tuning_value.repeat_action_guard_s or nil
    if repeat_guard ~= nil then
        if type(repeat_guard) ~= 'number' or repeat_guard <= 0 then
            error('config.encounter.tuning.repeat_action_guard_s must be a positive number')
        end
        encounter.tuning.repeat_action_guard_s = repeat_guard
    end

    if encounter.id == 'kei' and encounter.enabled == true then
        if type(kei_value) ~= 'table' then
            error('enabled Kei encounter requires config.encounter.kei')
        end
        local elemental = kei_value.elemental_damage
        if type(elemental) ~= 'table' or type(elemental.water) ~= 'table' or type(elemental.ice) ~= 'table' then
            error('enabled Kei encounter requires elemental_damage water and ice spell tables')
        end
        local dealer_name = normalize_optional_string(elemental.dealer_name)
        local water_probe = normalize_optional_string(elemental.water.probe_spell)
        local water_damage = normalize_optional_string(elemental.water.damage_spell)
        local ice_probe = normalize_optional_string(elemental.ice.probe_spell)
        local ice_damage = normalize_optional_string(elemental.ice.damage_spell)
        if dealer_name == nil then
            error('config.encounter.kei.elemental_damage.dealer_name must not be empty')
        end
        if water_probe == nil or water_damage == nil or ice_probe == nil or ice_damage == nil then
            error('config.encounter.kei requires all four configured elemental spells')
        end
        local sustain_interval = elemental.sustain_interval_s
        if type(sustain_interval) ~= 'number' or sustain_interval < 0.5 or sustain_interval > 30 then
            error('config.encounter.kei.elemental_damage.sustain_interval_s must be 0.5..30')
        end
        local probe_timeout = elemental.probe_timeout_s
        if type(probe_timeout) ~= 'number' or probe_timeout < 0.5 or probe_timeout > 30 then
            error('config.encounter.kei.elemental_damage.probe_timeout_s must be 0.5..30')
        end
        if type(kei_value.fullers) ~= 'table' then
            error('config.encounter.kei.fullers must be a table')
        end
        local target_distance = canonical_alias_value(
            kei_value.fullers.target_distance,
            kei_value.fullers.run_away_distance,
            'config.encounter.kei.fullers.target_distance',
            'config.encounter.kei.fullers.run_away_distance'
        )
        if type(target_distance) ~= 'number' or target_distance <= 0 or target_distance > 50 then
            error('config.encounter.kei.fullers.target_distance must be > 0 and <= 50')
        end
        local prearm_margin = kei_value.fullers.prearm_hpp_margin
        if type(prearm_margin) ~= 'number' or prearm_margin < 0 or prearm_margin > 10 then
            error('config.encounter.kei.fullers_prearm_hpp_margin must be 0..10')
        end
        encounter.kei = {
            elemental_damage = {
                dealer_name = dealer_name,
                water = {
                    probe_spell = water_probe,
                    damage_spell = water_damage,
                },
                ice = {
                    probe_spell = ice_probe,
                    damage_spell = ice_damage,
                },
                sustain_interval_s = sustain_interval,
                probe_timeout_s = probe_timeout,
            },
            fullers = {
                target_distance = target_distance,
                prearm_hpp_margin = prearm_margin,
            },
        }
    else
        encounter.kei = nil
    end
end

local function normalize_profile(source, meta, config)
    local profile_source = is_table(source) and source or {}
    local profile = config.profile
    local nested_profile = get_path(profile_source, { 'profile' })
    if is_table(nested_profile) then
        profile.schema_version = normalize_number(nested_profile.schema_version, profile.schema_version, { integer = true })
        profile.engine = normalize_string(nested_profile.engine, profile.engine)
        profile.character = normalize_optional_string(nested_profile.character) or profile.character
        profile.main_job = normalize_optional_string(nested_profile.main_job) or profile.main_job
        profile.sub_job = normalize_optional_string(nested_profile.sub_job) or profile.sub_job
        profile.source = normalize_string(nested_profile.source, profile.source)
    end

    profile.engine = normalize_string(first_path(profile_source, { path('engine_mode'), path('profile', 'engine') }), profile.engine)
    profile.character = normalize_optional_string(first_path(profile_source, { path('character'), path('profile', 'character') })) or profile.character
    profile.main_job = normalize_optional_string(first_path(profile_source, { path('main_job'), path('profile', 'main_job'), path('job'), path('profile', 'job') })) or profile.main_job
    profile.sub_job = normalize_optional_string(first_path(profile_source, { path('sub_job'), path('profile', 'sub_job') })) or profile.sub_job
    profile.source = normalize_string(first_path(profile_source, { path('source'), path('profile', 'source') }), profile.source)

    local meta_profile = is_table(meta) and meta or {}
    profile.character = profile.character or normalize_optional_string(first_path(meta_profile, { path('character'), path('char') }))
    profile.main_job = profile.main_job or normalize_optional_string(first_path(meta_profile, { path('main_job'), path('job') }))
    profile.sub_job = profile.sub_job or normalize_optional_string(first_path(meta_profile, { path('sub_job') }))
    profile.source = normalize_string(first_path(meta_profile, { path('source') }), profile.source)
end

local function normalize_list_domain(source, config)
    local abilities = config.abilities
    local nested_abilities = get_path(source, { 'abilities' })
    if is_table(nested_abilities) and table_has_any(nested_abilities, { 'configured', 'legacy_slots', 'wsabilities', 'enabled' }) then
        abilities.enabled = normalize_boolean(nested_abilities.enabled, abilities.enabled)
        abilities.configured = normalize_list(nested_abilities.configured, abilities.configured)
        abilities.legacy_slots = normalize_list(nested_abilities.legacy_slots, abilities.legacy_slots)
        abilities.wsabilities = normalize_list(nested_abilities.wsabilities, abilities.wsabilities)
    else
        abilities.enabled = normalize_boolean(first_path(source, { path('ability_active') }), abilities.enabled)
        abilities.configured = normalize_list(first_path(source, { path('abilities') }), abilities.configured)
        abilities.legacy_slots = normalize_list({
            first_path(source, { path('ability1') }),
            first_path(source, { path('ability2') }),
            first_path(source, { path('ability3') }),
            first_path(source, { path('ability4') }),
            first_path(source, { path('ability5') }),
            first_path(source, { path('ability6') }),
        }, abilities.legacy_slots)
        abilities.wsabilities = normalize_list(first_path(source, { path('wsabilities') }), abilities.wsabilities)
    end
end

local function normalize_weaponskill_minimum_tp(value, default_value)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'number'
        or value % 1 ~= 0
        or value < 1000
        or value > 3000 then
        error('combat.weaponskill.minimum_tp must be an integer from 1000 to 3000')
    end
    return value
end

local SKILLCHAIN_TARGETS = {
    auto = true,
    compression = true,
    liquefaction = true,
    induration = true,
    reverberation = true,
    transfixion = true,
    scission = true,
    detonation = true,
    impaction = true,
    gravitation = true,
    fragmentation = true,
    distortion = true,
    fusion = true,
    light = true,
    darkness = true,
    radiance = true,
    umbra = true,
}

local function normalize_skillchain_target(value, default_value)
    local normalized = normalize_string(value, default_value or 'auto'):lower()
    if SKILLCHAIN_TARGETS[normalized] ~= true then
        error('combat.weaponskill.skillchain_target has unsupported value: ' .. tostring(value))
    end
    return normalized
end

local function normalize_combat(source, config)
    local combat = config.combat
    local nested = get_path(source, { 'combat' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'autotarget', 'auto_engage', 'spam', 'closer', 'manual', 'prime', 'static', 'face', 'weaponskill', 'pulling' }) then
            combat.enabled = normalize_boolean(nested.enabled, combat.enabled)
            combat.autotarget = normalize_boolean(nested.autotarget, combat.autotarget)
        combat.auto_engage = normalize_boolean(nested.auto_engage, combat.auto_engage)
        combat.spam = normalize_boolean(nested.spam, combat.spam)
        combat.closer = normalize_boolean(nested.closer, combat.closer)
        combat.manual = normalize_boolean(nested.manual, combat.manual)
        combat.prime = normalize_boolean(nested.prime, combat.prime)
        combat.static = normalize_boolean(nested.static, combat.static)
        combat.face = normalize_boolean(nested.face, combat.face)
        local nested_ws = is_table(nested.weaponskill) and nested.weaponskill or {}
        combat.weaponskill.enabled = normalize_boolean(nested_ws.enabled, combat.weaponskill.enabled)
        combat.weaponskill.primary = normalize_string(nested_ws.primary or nested_ws.ws1 or nested_ws.weaponskill, combat.weaponskill.primary)
        combat.weaponskill.mode = normalize_string(nested_ws.mode, combat.weaponskill.mode)
        combat.weaponskill.minimum_tp = normalize_weaponskill_minimum_tp(nested_ws.minimum_tp, combat.weaponskill.minimum_tp)
        combat.weaponskill.allow_aoe = normalize_boolean(nested_ws.allow_aoe, combat.weaponskill.allow_aoe)
        combat.weaponskill.fast_skillchain = normalize_boolean(nested_ws.fast_skillchain, combat.weaponskill.fast_skillchain)
        combat.weaponskill.skillchain_target = normalize_skillchain_target(nested_ws.skillchain_target, combat.weaponskill.skillchain_target)
        combat.weaponskill.wait_ignore_names = normalize_list(nested_ws.wait_ignore_names, combat.weaponskill.wait_ignore_names)
        combat.weaponskill.aftermath_enabled = normalize_boolean(nested_ws.aftermath_enabled, combat.weaponskill.aftermath_enabled)
        combat.weaponskill.aftermath_ws = normalize_string(nested_ws.aftermath_ws, combat.weaponskill.aftermath_ws)
        combat.pulling = normalize_camp_pulling(nested.pulling)
    else
            combat.enabled = normalize_boolean(first_path(source, { path('domain_combat_enabled') }), combat.enabled)
            combat.autotarget = normalize_boolean(first_path(source, { path('autotarget') }), combat.autotarget)
        combat.auto_engage = normalize_boolean(first_path(source, { path('auto_engage') }), combat.auto_engage)
        combat.spam = normalize_boolean(first_path(source, { path('spam') }), combat.spam)
        combat.closer = normalize_boolean(first_path(source, { path('closer') }), combat.closer)
        combat.manual = normalize_boolean(first_path(source, { path('manual') }), combat.manual)
        combat.prime = normalize_boolean(first_path(source, { path('prime') }), combat.prime)
        combat.static = normalize_boolean(first_path(source, { path('static') }), combat.static)
        combat.face = normalize_boolean(first_path(source, { path('face') }), combat.face)
        combat.weaponskill.enabled = normalize_boolean(first_path(source, { path('weaponskill_active') }), combat.weaponskill.enabled)
        combat.weaponskill.primary = normalize_string(first_path(source, { path('weaponskill'), path('ws1') }), combat.weaponskill.primary)
        combat.weaponskill.mode = normalize_string(first_path(source, { path('ws_mode') }), combat.weaponskill.mode)
        combat.weaponskill.minimum_tp = normalize_weaponskill_minimum_tp(first_path(source, { path('weaponskill_min_tp') }), combat.weaponskill.minimum_tp)
        combat.weaponskill.allow_aoe = normalize_boolean(first_path(source, { path('weaponskill_allow_aoe') }), combat.weaponskill.allow_aoe)
        combat.weaponskill.fast_skillchain = normalize_boolean(first_path(source, { path('fast_skillchain') }), combat.weaponskill.fast_skillchain)
        combat.weaponskill.skillchain_target = normalize_skillchain_target(first_path(source, { path('skillchain_target') }), combat.weaponskill.skillchain_target)
        combat.weaponskill.wait_ignore_names = normalize_list(first_path(source, { path('wait_ignore_names') }), combat.weaponskill.wait_ignore_names)
        combat.weaponskill.aftermath_enabled = normalize_boolean(first_path(source, { path('aftermath_enabled') }), combat.weaponskill.aftermath_enabled)
        combat.weaponskill.aftermath_ws = normalize_string(first_path(source, { path('aftermath_ws') }), combat.weaponskill.aftermath_ws)
        combat.pulling = normalize_camp_pulling(first_path(source, { path('camp_pulling') }))
    end
end

local function normalize_defensive(source, config)
    local defensive = config.defensive
    local nested = get_path(source, { 'defensive' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'provider', 'cure', 'waltz', 'doom', 'charm_sleeper', 'sleep_waker', 'na', 'enemy_buffs', 'enemy_debuffs', 'buffs', 'thresholds' }) then
        defensive.enabled = normalize_boolean(nested.enabled, defensive.enabled)
        defensive.provider = normalize_string(nested.provider, defensive.provider)
        local cure = is_table(nested.cure) and nested.cure or {}
        defensive.cure.enabled = normalize_boolean(cure.enabled, defensive.cure.enabled)
        defensive.cure.min_tier = normalize_number(cure.min_tier, defensive.cure.min_tier, { integer = true })
        defensive.cure.max_tier = normalize_number(cure.max_tier, defensive.cure.max_tier, { integer = true })
        defensive.cure.min_missing_hp = normalize_number(cure.min_missing_hp, defensive.cure.min_missing_hp, { integer = true })
        defensive.cure.ignore_trusts = normalize_boolean(cure.ignore_trusts, defensive.cure.ignore_trusts)
        local curaga = is_table(cure.curaga) and cure.curaga or {}
        defensive.cure.curaga.enabled = normalize_boolean(curaga.enabled, defensive.cure.curaga.enabled)
        defensive.cure.curaga.min_targets = normalize_number(curaga.min_targets, defensive.cure.curaga.min_targets, { integer = true, min = 2, max = 6 })
        local waltz = is_table(nested.waltz) and nested.waltz or {}
        defensive.waltz.enabled = normalize_boolean(waltz.enabled, defensive.waltz.enabled)
        defensive.waltz.tp_reserve = normalize_number(waltz.tp_reserve, defensive.waltz.tp_reserve, { integer = true, min = 0, max = 3000 })
        defensive.waltz.divine_min_targets = normalize_number(waltz.divine_min_targets, defensive.waltz.divine_min_targets, { integer = true, min = 2, max = 6 })
        local doom = is_table(nested.doom) and nested.doom or {}
        defensive.doom.holy_water_enabled = normalize_boolean(doom.holy_water_enabled, defensive.doom.holy_water_enabled)
        local charm_sleeper = is_table(nested.charm_sleeper) and nested.charm_sleeper or {}
        defensive.charm_sleeper.enabled = normalize_boolean(charm_sleeper.enabled, defensive.charm_sleeper.enabled)
        local sleep_waker = is_table(nested.sleep_waker) and nested.sleep_waker or {}
        defensive.sleep_waker.enabled = normalize_boolean(sleep_waker.enabled, defensive.sleep_waker.enabled)
        local na = is_table(nested.na) and nested.na or {}
        defensive.na.enabled = normalize_boolean(na.enabled, defensive.na.enabled)
        defensive.na.limit_enabled = normalize_boolean(na.limit_enabled, defensive.na.limit_enabled)
        defensive.na.priority = normalize_string(na.priority, defensive.na.priority)
        local enemy_buffs = is_table(nested.enemy_buffs) and nested.enemy_buffs or {}
        defensive.enemy_buffs.remove = normalize_boolean(enemy_buffs.remove, defensive.enemy_buffs.remove)
        local enemy_debuffs = is_table(nested.enemy_debuffs) and nested.enemy_debuffs or {}
        defensive.enemy_debuffs.enabled = normalize_boolean(enemy_debuffs.enabled, defensive.enemy_debuffs.enabled)
        defensive.enemy_debuffs.list = normalize_string(enemy_debuffs.list, defensive.enemy_debuffs.list)
        local buffs = is_table(nested.buffs) and nested.buffs or {}
        defensive.buffs.enabled = normalize_boolean(buffs.enabled, defensive.buffs.enabled)
        defensive.buffs.self_only = normalize_boolean(buffs.self_only, defensive.buffs.self_only)
        defensive.buffs.list = normalize_string(buffs.list, defensive.buffs.list)
        defensive.buffs.targeted = normalize_targeted_buffs(buffs.targeted, defensive.buffs.targeted)
        defensive.buffs.overwrite_enabled = normalize_boolean(buffs.overwrite_enabled, defensive.buffs.overwrite_enabled)
        defensive.buffs.overwrite_interval = normalize_number(buffs.overwrite_interval, defensive.buffs.overwrite_interval, { integer = true })
        local thresholds = is_table(nested.thresholds) and nested.thresholds or {}
        defensive.thresholds.critical_hpp = normalize_number(thresholds.critical_hpp, defensive.thresholds.critical_hpp, { integer = true })
        defensive.thresholds.medium_hpp = normalize_number(thresholds.medium_hpp, defensive.thresholds.medium_hpp, { integer = true })
    else
        defensive.enabled = normalize_boolean(first_path(source, { path('defensive_enabled') }), defensive.enabled)
        defensive.provider = normalize_string(first_path(source, { path('defensive_provider') }), defensive.provider)
        defensive.cure.enabled = normalize_boolean(first_path(source, { path('defensive_cure_enabled') }), defensive.cure.enabled)
        defensive.cure.min_tier = normalize_number(first_path(source, { path('def_heal_min_tier_cure') }), defensive.cure.min_tier, { integer = true })
        defensive.cure.max_tier = normalize_number(first_path(source, { path('def_heal_max_tier_cure') }), defensive.cure.max_tier, { integer = true })
        defensive.cure.min_missing_hp = normalize_number(first_path(source, { path('def_heal_min_missing_hp') }), defensive.cure.min_missing_hp, { integer = true })
        defensive.cure.ignore_trusts = normalize_boolean(first_path(source, { path('def_heal_ignore_trusts') }), defensive.cure.ignore_trusts)
        defensive.cure.curaga.enabled = normalize_boolean(first_path(source, { path('defensive_curaga_enabled') }), defensive.cure.curaga.enabled)
        defensive.cure.curaga.min_targets = normalize_number(first_path(source, { path('defensive_curaga_min_targets') }), defensive.cure.curaga.min_targets, { integer = true, min = 2, max = 6 })
        defensive.waltz.enabled = normalize_boolean(first_path(source, { path('defensive_waltz_enabled') }), defensive.waltz.enabled)
        defensive.waltz.tp_reserve = normalize_number(first_path(source, { path('defensive_waltz_tp_reserve') }), defensive.waltz.tp_reserve, { integer = true, min = 0, max = 3000 })
        defensive.waltz.divine_min_targets = normalize_number(first_path(source, { path('defensive_divine_waltz_min_targets') }), defensive.waltz.divine_min_targets, { integer = true, min = 2, max = 6 })
        defensive.doom.holy_water_enabled = normalize_boolean(first_path(source, { path('defensive_doom_water') }), defensive.doom.holy_water_enabled)
        defensive.charm_sleeper.enabled = normalize_boolean(first_path(source, { path('def_charm_sleeper_enabled') }), defensive.charm_sleeper.enabled)
        defensive.sleep_waker.enabled = normalize_boolean(first_path(source, { path('def_sleep_waker_enabled') }), defensive.sleep_waker.enabled)
        defensive.na.enabled = normalize_boolean(first_path(source, { path('defensive_na_enabled') }), defensive.na.enabled)
        defensive.na.limit_enabled = normalize_boolean(first_path(source, { path('defensive_na_limit_enabled') }), defensive.na.limit_enabled)
        defensive.na.priority = normalize_string(first_path(source, { path('defensive_na_priority') }), defensive.na.priority)
        defensive.enemy_buffs.remove = normalize_boolean(first_path(source, { path('def_remove_enemy_buffs') }), defensive.enemy_buffs.remove)
        defensive.enemy_debuffs.enabled = normalize_boolean(first_path(source, { path('def_maintain_enemy_debuffs') }), defensive.enemy_debuffs.enabled)
        defensive.enemy_debuffs.list = normalize_string(first_path(source, { path('defensive_enemy_debuffs') }), defensive.enemy_debuffs.list)
        defensive.buffs.enabled = normalize_boolean(first_path(source, { path('defensive_buff_enabled') }), defensive.buffs.enabled)
        defensive.buffs.self_only = normalize_boolean(first_path(source, { path('defensive_buff_self_only') }), defensive.buffs.self_only)
        defensive.buffs.list = normalize_string(first_path(source, { path('defensive_buffs') }), defensive.buffs.list)
        defensive.buffs.targeted = normalize_targeted_buffs(first_path(source, { path('defensive_targeted_buffs') }), defensive.buffs.targeted)
        defensive.buffs.overwrite_enabled = normalize_boolean(first_path(source, { path('defensive_overwrite_enabled') }), defensive.buffs.overwrite_enabled)
        defensive.buffs.overwrite_interval = normalize_number(first_path(source, { path('defensive_overwrite_interval') }), defensive.buffs.overwrite_interval, { integer = true })
        defensive.thresholds.critical_hpp = normalize_number(first_path(source, { path('defensive_critical_hpp') }), defensive.thresholds.critical_hpp, { integer = true })
        defensive.thresholds.medium_hpp = normalize_number(first_path(source, { path('defensive_medium_hpp') }), defensive.thresholds.medium_hpp, { integer = true })
    end
end

local function require_formation_table(value, path_name)
    if type(value) ~= 'table' then
        error(path_name .. ' must be a table')
    end
    return value
end

local function require_formation_string(value, path_name)
    if type(value) ~= 'string' then
        error(path_name .. ' must be a string')
    end
    local normalized = value:match('^%s*(.-)%s*$')
    if normalized == '' then
        error(path_name .. ' must be a non-empty string')
    end
    return normalized
end

local function require_formation_number(value, path_name, minimum, maximum, positive)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
        error(path_name .. ' must be a finite number')
    end
    if positive and value <= 0 then
        error(path_name .. ' must be a positive number')
    end
    if minimum ~= nil and value < minimum then
        error(path_name .. ' must be >= ' .. tostring(minimum))
    end
    if maximum ~= nil and value > maximum then
        error(path_name .. ' must be <= ' .. tostring(maximum))
    end
    return value
end

local function optional_formation_number(value, path_name, minimum, maximum, positive)
    if value == nil then
        return nil
    end
    return require_formation_number(value, path_name, minimum, maximum, positive)
end

local function optional_generic_formation_flat_number(source, key)
    local value = first_path(source, { path(key) })
    if value == 0 then
        return nil
    end
    return value
end

local function generic_formation_flat_source(source)
    return {
        placement = {
            mode = first_path(source, { path('formation_placement_mode') }),
            anchor = first_path(source, { path('formation_anchor') }),
            anchor_member = first_path(source, { path('formation_anchor_member') }),
            axis = {
                type = first_path(source, { path('formation_axis_type') }),
                member = first_path(source, { path('formation_axis_member') }),
            },
            preferred_radius = first_path(source, { path('formation_preferred_radius') }),
            minimum_radius = first_path(source, { path('formation_minimum_radius') }),
            maximum_radius = first_path(source, { path('formation_maximum_radius') }),
            preferred_angle_deg = first_path(source, { path('formation_preferred_angle_deg') }),
            allowed_angle_half_width_deg = first_path(source, { path('formation_allowed_angle_half_width_deg') }),
            radius_step = first_path(source, { path('formation_radius_step') }),
            angle_step_deg = first_path(source, { path('formation_angle_step_deg') }),
        },
        hysteresis = {
            start_distance = first_path(source, { path('formation_hysteresis_start_distance') }),
            stop_distance = first_path(source, { path('formation_hysteresis_stop_distance') }),
        },
        constraints = {
            avoid_encounter_hazards = first_path(source, { path('formation_avoid_encounter_hazards') }),
            hazard_margin = first_path(source, { path('formation_hazard_margin') }),
            safe_origin_radius = optional_generic_formation_flat_number(source, 'formation_safe_origin_radius'),
            minimum_boss_distance = optional_generic_formation_flat_number(source, 'formation_minimum_boss_distance'),
            maximum_boss_distance = optional_generic_formation_flat_number(source, 'formation_maximum_boss_distance'),
            maximum_party_range = optional_generic_formation_flat_number(source, 'formation_maximum_party_range'),
            required_party_names = first_path(source, { path('formation_required_party_names') }),
        },
    }
end

local function normalize_formation_mock(source, target)
    if source == nil then
        return
    end
    if type(source) ~= 'table' then
        error('config.movement.formation.mock must be a table')
    end
    if source.enabled ~= nil and type(source.enabled) ~= 'boolean' then
        error('config.movement.formation.mock.enabled must be boolean')
    end
    if source.mob_name ~= nil and type(source.mob_name) ~= 'string' then
        error('config.movement.formation.mock.mob_name must be a string')
    end
    target.enabled = source.enabled == true
    target.mob_name = source.mob_name == nil and '' or (source.mob_name:match('^%s*(.-)%s*$'))
    if target.enabled and target.mob_name == '' then
        error('enabled config.movement.formation.mock requires mob_name')
    end
end

local function normalize_generic_formation(source, target)
    local placement = require_formation_table(source.placement, 'config.movement.formation.placement')
    local mode = require_formation_string(placement.mode, 'config.movement.formation.placement.mode')
    if mode ~= 'radial_band' and mode ~= 'polar_band' then
        error('config.movement.formation.placement.mode must be radial_band or polar_band')
    end
    local anchor = require_formation_string(placement.anchor, 'config.movement.formation.placement.anchor')
    if anchor ~= 'boss' and anchor ~= 'encounter_origin' and anchor ~= 'member' then
        error('config.movement.formation.placement.anchor must be boss, encounter_origin, or member')
    end
    local normalized_placement = {
        mode = mode,
        anchor = anchor,
        preferred_radius = require_formation_number(
            placement.preferred_radius,
            'config.movement.formation.placement.preferred_radius',
            0,
            nil,
            false
        ),
        minimum_radius = require_formation_number(
            placement.minimum_radius,
            'config.movement.formation.placement.minimum_radius',
            0,
            nil,
            false
        ),
        maximum_radius = require_formation_number(
            placement.maximum_radius,
            'config.movement.formation.placement.maximum_radius',
            0,
            nil,
            false
        ),
        radius_step = require_formation_number(
            placement.radius_step,
            'config.movement.formation.placement.radius_step',
            nil,
            nil,
            true
        ),
        angle_step_deg = require_formation_number(
            placement.angle_step_deg,
            'config.movement.formation.placement.angle_step_deg',
            nil,
            360,
            true
        ),
    }
    if normalized_placement.maximum_radius < normalized_placement.minimum_radius then
        error('config.movement.formation.placement.maximum_radius must be >= minimum_radius')
    end
    if normalized_placement.preferred_radius < normalized_placement.minimum_radius
        or normalized_placement.preferred_radius > normalized_placement.maximum_radius then
        error('config.movement.formation.placement.preferred_radius must be inside the radius band')
    end
    if anchor == 'member' then
        normalized_placement.anchor_member = require_formation_string(
            placement.anchor_member,
            'config.movement.formation.placement.anchor_member'
        )
    end
    if mode == 'polar_band' then
        local axis = require_formation_table(placement.axis, 'config.movement.formation.placement.axis')
        if axis.type ~= 'boss_to_member' and axis.type ~= 'boss_heading' then
            error('config.movement.formation.placement.axis.type must be boss_to_member or boss_heading')
        end
        normalized_placement.axis = {
            type = axis.type,
        }
        if axis.type == 'boss_to_member' then
            normalized_placement.axis.member = require_formation_string(
                axis.member,
                'config.movement.formation.placement.axis.member'
            )
        end
        normalized_placement.preferred_angle_deg = require_formation_number(
            placement.preferred_angle_deg,
            'config.movement.formation.placement.preferred_angle_deg',
            nil,
            nil,
            false
        )
        normalized_placement.allowed_angle_half_width_deg = require_formation_number(
            placement.allowed_angle_half_width_deg,
            'config.movement.formation.placement.allowed_angle_half_width_deg',
            0,
            180,
            false
        )
    end

    local hysteresis = require_formation_table(source.hysteresis, 'config.movement.formation.hysteresis')
    local normalized_hysteresis = {
        start_distance = require_formation_number(
            hysteresis.start_distance,
            'config.movement.formation.hysteresis.start_distance',
            0,
            nil,
            false
        ),
        stop_distance = require_formation_number(
            hysteresis.stop_distance,
            'config.movement.formation.hysteresis.stop_distance',
            0,
            nil,
            false
        ),
    }
    if normalized_hysteresis.start_distance < normalized_hysteresis.stop_distance then
        error('config.movement.formation.hysteresis.start_distance must be >= stop_distance')
    end

    local constraints = require_formation_table(source.constraints, 'config.movement.formation.constraints')
    if type(constraints.avoid_encounter_hazards) ~= 'boolean' then
        error('config.movement.formation.constraints.avoid_encounter_hazards must be a boolean')
    end
    local normalized_constraints = {
        avoid_encounter_hazards = constraints.avoid_encounter_hazards,
        hazard_margin = require_formation_number(
            constraints.hazard_margin,
            'config.movement.formation.constraints.hazard_margin',
            0,
            nil,
            false
        ),
    }
    normalized_constraints.safe_origin_radius = optional_formation_number(
        constraints.safe_origin_radius,
        'config.movement.formation.constraints.safe_origin_radius',
        nil,
        nil,
        true
    )
    normalized_constraints.minimum_boss_distance = optional_formation_number(
        constraints.minimum_boss_distance,
        'config.movement.formation.constraints.minimum_boss_distance',
        0,
        nil,
        false
    )
    normalized_constraints.maximum_boss_distance = optional_formation_number(
        constraints.maximum_boss_distance,
        'config.movement.formation.constraints.maximum_boss_distance',
        nil,
        nil,
        true
    )
    if normalized_constraints.minimum_boss_distance ~= nil
        and normalized_constraints.maximum_boss_distance ~= nil
        and normalized_constraints.maximum_boss_distance < normalized_constraints.minimum_boss_distance then
        error('config.movement.formation.constraints.maximum_boss_distance must be >= minimum_boss_distance')
    end
    normalized_constraints.maximum_party_range = optional_formation_number(
        constraints.maximum_party_range,
        'config.movement.formation.constraints.maximum_party_range',
        nil,
        nil,
        true
    )
    if normalized_constraints.maximum_party_range ~= nil then
        normalized_constraints.required_party_names = normalize_list(constraints.required_party_names, {})
        if #normalized_constraints.required_party_names == 0 then
            error('config.movement.formation.constraints.required_party_names must not be empty when maximum_party_range is set')
        end
        for i = 1, #normalized_constraints.required_party_names do
            normalized_constraints.required_party_names[i] = require_formation_string(
                normalized_constraints.required_party_names[i],
                ('config.movement.formation.constraints.required_party_names[%d]'):format(i)
            )
        end
    elseif constraints.required_party_names ~= nil then
        local names = normalize_list(constraints.required_party_names, {})
        if #names > 0 then
            error('config.movement.formation.constraints.maximum_party_range is required with required_party_names')
        end
    end

    target.placement = normalized_placement
    target.hysteresis = normalized_hysteresis
    target.constraints = normalized_constraints
    target.role = nil
    target.tank_name = nil
    target.required_party_names = nil
    target.capture_stable_s = nil
    target.capture_tolerance = nil
    target.safe_radius = nil
    target.tank = nil
    target.dps = nil
    target.healer = nil
end

local function normalize_named_formations(source, target)
    if source == nil then
        return
    end
    if type(source) ~= 'table' then
        error('config.movement.named_formations must be a table')
    end
    target.enabled = normalize_boolean(source.enabled, target.enabled)
    local entries = source.entries
    if entries == nil then
        entries = {}
    end
    if type(entries) ~= 'table' then
        error('config.movement.named_formations.entries must be a table')
    end
    local count = #entries
    for key in pairs(entries) do
        if type(key) ~= 'number' or key < 1 or key > count or key % 1 ~= 0 then
            error('config.movement.named_formations.entries must be a contiguous array')
        end
    end
    local normalized_entries = {}
    local seen_names = {}
    for i = 1, count do
        local entry = require_formation_table(
            entries[i],
            ('config.movement.named_formations.entries[%d]'):format(i)
        )
        local mob_name = require_formation_string(
            entry.mob_name,
            ('config.movement.named_formations.entries[%d].mob_name'):format(i)
        )
        local name_key = mob_name:lower()
        if seen_names[name_key] then
            error('config.movement.named_formations contains duplicate mob name: ' .. mob_name)
        end
        seen_names[name_key] = true
        local normalized = { mob_name = mob_name }
        local geometry = type(entry.placement) == 'table' and entry or generic_formation_flat_source(entry)
        normalize_generic_formation(geometry, normalized)
        normalized_entries[#normalized_entries + 1] = normalized
    end
    if target.enabled and #normalized_entries == 0 then
        error('enabled config.movement.named_formations requires at least one entry')
    end
    target.entries = normalized_entries
end

local function normalize_movement(source, config)
    local movement = config.movement
    local nested = get_path(source, { 'movement' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'move', 'formation', 'named_formations', 'spacing', 'path' }) then
        movement.enabled = normalize_boolean(nested.enabled, movement.enabled)
        movement.move = normalize_boolean(nested.move, movement.move)
        local formation = is_table(nested.formation) and nested.formation or {}
        movement.formation.enabled = normalize_boolean(formation.enabled, movement.formation.enabled)
        movement.formation.encounter = normalize_string(formation.encounter, movement.formation.encounter)
        normalize_formation_mock(formation.mock, movement.formation.mock)
        movement.formation.role = normalize_string(formation.role, movement.formation.role):lower()
        movement.formation.tank_name = normalize_string(formation.tank_name, movement.formation.tank_name)
        movement.formation.required_party_names = normalize_list(formation.required_party_names, movement.formation.required_party_names)
        movement.formation.capture_stable_s = normalize_number(formation.capture_stable_s, movement.formation.capture_stable_s, { min = 0.1, max = 5.0 })
        movement.formation.capture_tolerance = normalize_number(formation.capture_tolerance, movement.formation.capture_tolerance, { min = 0.01, max = 1.0 })
        movement.formation.safe_radius = normalize_number(formation.safe_radius, movement.formation.safe_radius, { min = 5.0, max = 30.0 })
        local formation_tank = is_table(formation.tank) and formation.tank or {}
        movement.formation.tank.accept_radius = normalize_number(formation_tank.accept_radius, movement.formation.tank.accept_radius, { min = 0.1, max = 10.0 })
        movement.formation.tank.return_radius = normalize_number(formation_tank.return_radius, movement.formation.tank.return_radius, { min = 0.2, max = 15.0 })
        local formation_dps = is_table(formation.dps) and formation.dps or {}
        movement.formation.dps.flank_angle_deg = normalize_number(formation_dps.flank_angle_deg, movement.formation.dps.flank_angle_deg, { min = 1.0, max = 179.0 })
        movement.formation.dps.melee_radius = normalize_number(formation_dps.melee_radius, movement.formation.dps.melee_radius, { min = 0.5, max = 8.0 })
        movement.formation.dps.position_tolerance = normalize_number(formation_dps.position_tolerance, movement.formation.dps.position_tolerance, { min = 0.1, max = 5.0 })
        local formation_healer = is_table(formation.healer) and formation.healer or {}
        movement.formation.healer.preferred_radius = normalize_number(formation_healer.preferred_radius, movement.formation.healer.preferred_radius, { min = 2.0, max = 25.0 })
        movement.formation.healer.minimum_boss_distance = normalize_number(formation_healer.minimum_boss_distance, movement.formation.healer.minimum_boss_distance, { min = 1.0, max = 20.0 })
        movement.formation.healer.maximum_party_range = normalize_number(formation_healer.maximum_party_range, movement.formation.healer.maximum_party_range, { min = 2.0, max = 25.0 })
        movement.formation.healer.cone_half_angle_deg = normalize_number(formation_healer.cone_half_angle_deg, movement.formation.healer.cone_half_angle_deg, { min = 1.0, max = 89.0 })
        movement.formation.healer.cone_safety_margin_deg = normalize_number(formation_healer.cone_safety_margin_deg, movement.formation.healer.cone_safety_margin_deg, { min = 1.0, max = 45.0 })
        movement.formation.healer.sample_step_deg = normalize_number(formation_healer.sample_step_deg, movement.formation.healer.sample_step_deg, { min = 1.0, max = 45.0 })
        if movement.formation.enabled and movement.formation.encounter ~= 'lilith_easy' then
            normalize_generic_formation(formation, movement.formation)
        end
        normalize_named_formations(nested.named_formations, movement.named_formations)
        local spacing = is_table(nested.spacing) and nested.spacing or {}
        movement.spacing.enabled = normalize_boolean(spacing.enabled, movement.spacing.enabled)
        movement.spacing.band_min = normalize_number(spacing.band_min, movement.spacing.band_min)
        movement.spacing.band_max = normalize_number(spacing.band_max, movement.spacing.band_max)
        movement.spacing.model_size_floor = normalize_number(spacing.model_size_floor, movement.spacing.model_size_floor)
        movement.spacing.use_prediction = normalize_boolean(spacing.use_prediction, movement.spacing.use_prediction)
        movement.spacing.lookahead_s = normalize_number(spacing.lookahead_s, movement.spacing.lookahead_s)
        movement.spacing.repel_hold_ticks = normalize_number(spacing.repel_hold_ticks, movement.spacing.repel_hold_ticks, { integer = true })
        movement.spacing.overlap_deadband = normalize_number(spacing.overlap_deadband, movement.spacing.overlap_deadband)
        movement.spacing.repel_weight = normalize_number(spacing.repel_weight, movement.spacing.repel_weight)
        movement.spacing.band_deadband = normalize_number(spacing.band_deadband, movement.spacing.band_deadband)
        local path_cfg = is_table(nested.path) and nested.path or {}
        movement.path.recording = normalize_boolean(path_cfg.recording, movement.path.recording)
        movement.path.follow_enabled = normalize_boolean(path_cfg.follow_enabled, movement.path.follow_enabled)
        movement.path.file_name = normalize_string(path_cfg.file_name, movement.path.file_name)
        movement.path.route_type = normalize_string(path_cfg.route_type, movement.path.route_type)
        movement.path.distance_to_start = normalize_number(path_cfg.distance_to_start, movement.path.distance_to_start)
        movement.path.points = normalize_list(path_cfg.points, movement.path.points)
        movement.path.party_gate_yalms = normalize_number(path_cfg.party_gate_yalms, movement.path.party_gate_yalms)
        movement.path.resume_index_window = normalize_number(path_cfg.resume_index_window, movement.path.resume_index_window, { integer = true })
        movement.path.hunter_targets = normalize_list(path_cfg.hunter_targets, movement.path.hunter_targets)
        movement.path.hunter_max_z_delta = normalize_number(path_cfg.hunter_max_z_delta, movement.path.hunter_max_z_delta)
        movement.path.hunter_max_target_range = normalize_number(path_cfg.hunter_max_target_range, movement.path.hunter_max_target_range)
        movement.path.hunter_claim_timeout_s = normalize_number(path_cfg.hunter_claim_timeout_s, movement.path.hunter_claim_timeout_s)
        movement.path.hunter_ignore_cooldown_s = normalize_number(path_cfg.hunter_ignore_cooldown_s, movement.path.hunter_ignore_cooldown_s)
        movement.path.pull_action_type = normalize_string(path_cfg.pull_action_type, movement.path.pull_action_type)
        movement.path.pull_action_name = normalize_string(path_cfg.pull_action_name, movement.path.pull_action_name)
    else
        movement.enabled = normalize_boolean(first_path(source, { path('domain_movement_enabled') }), movement.enabled)
        movement.move = normalize_boolean(first_path(source, { path('move') }), movement.move)
        movement.formation.enabled = normalize_boolean(first_path(source, { path('formation_enabled') }), movement.formation.enabled)
        movement.formation.encounter = normalize_string(first_path(source, { path('formation_encounter') }), movement.formation.encounter)
        normalize_formation_mock({
            enabled = first_path(source, { path('formation_mock_enabled') }),
            mob_name = first_path(source, { path('formation_mock_mob_name') }),
        }, movement.formation.mock)
        movement.formation.role = normalize_string(first_path(source, { path('formation_role') }), movement.formation.role):lower()
        movement.formation.tank_name = normalize_string(first_path(source, { path('formation_tank_name') }), movement.formation.tank_name)
        movement.formation.required_party_names = normalize_list(first_path(source, { path('formation_required_party_names') }), movement.formation.required_party_names)
        movement.formation.capture_stable_s = normalize_number(first_path(source, { path('formation_capture_stable_s') }), movement.formation.capture_stable_s, { min = 0.1, max = 5.0 })
        movement.formation.capture_tolerance = normalize_number(first_path(source, { path('formation_capture_tolerance') }), movement.formation.capture_tolerance, { min = 0.01, max = 1.0 })
        movement.formation.safe_radius = normalize_number(first_path(source, { path('formation_safe_radius') }), movement.formation.safe_radius, { min = 5.0, max = 30.0 })
        movement.formation.tank.accept_radius = normalize_number(first_path(source, { path('formation_tank_accept_radius') }), movement.formation.tank.accept_radius, { min = 0.1, max = 10.0 })
        movement.formation.tank.return_radius = normalize_number(first_path(source, { path('formation_tank_return_radius') }), movement.formation.tank.return_radius, { min = 0.2, max = 15.0 })
        movement.formation.dps.flank_angle_deg = normalize_number(first_path(source, { path('formation_dps_flank_angle_deg') }), movement.formation.dps.flank_angle_deg, { min = 1.0, max = 179.0 })
        movement.formation.dps.melee_radius = normalize_number(first_path(source, { path('formation_dps_melee_radius') }), movement.formation.dps.melee_radius, { min = 0.5, max = 8.0 })
        movement.formation.dps.position_tolerance = normalize_number(first_path(source, { path('formation_dps_position_tolerance') }), movement.formation.dps.position_tolerance, { min = 0.1, max = 5.0 })
        movement.formation.healer.preferred_radius = normalize_number(first_path(source, { path('formation_healer_preferred_radius') }), movement.formation.healer.preferred_radius, { min = 2.0, max = 25.0 })
        movement.formation.healer.minimum_boss_distance = normalize_number(first_path(source, { path('formation_healer_minimum_boss_distance') }), movement.formation.healer.minimum_boss_distance, { min = 1.0, max = 20.0 })
        movement.formation.healer.maximum_party_range = normalize_number(first_path(source, { path('formation_healer_maximum_party_range') }), movement.formation.healer.maximum_party_range, { min = 2.0, max = 25.0 })
        movement.formation.healer.cone_half_angle_deg = normalize_number(first_path(source, { path('formation_healer_cone_half_angle_deg') }), movement.formation.healer.cone_half_angle_deg, { min = 1.0, max = 89.0 })
        movement.formation.healer.cone_safety_margin_deg = normalize_number(first_path(source, { path('formation_healer_cone_safety_margin_deg') }), movement.formation.healer.cone_safety_margin_deg, { min = 1.0, max = 45.0 })
        movement.formation.healer.sample_step_deg = normalize_number(first_path(source, { path('formation_healer_sample_step_deg') }), movement.formation.healer.sample_step_deg, { min = 1.0, max = 45.0 })
        if movement.formation.enabled and movement.formation.encounter ~= 'lilith_easy' then
            normalize_generic_formation(generic_formation_flat_source(source), movement.formation)
        end
        normalize_named_formations({
            enabled = first_path(source, { path('named_formations_enabled') }),
            entries = first_path(source, { path('named_formation_entries') }),
        }, movement.named_formations)
        movement.spacing.enabled = normalize_boolean(first_path(source, { path('spacing') }), movement.spacing.enabled)
        movement.spacing.band_min = normalize_number(first_path(source, { path('spacing_band_min') }), movement.spacing.band_min)
        movement.spacing.band_max = normalize_number(first_path(source, { path('spacing_band_max') }), movement.spacing.band_max)
        movement.spacing.model_size_floor = normalize_number(first_path(source, { path('spacing_model_size_floor') }), movement.spacing.model_size_floor)
        movement.spacing.use_prediction = normalize_boolean(first_path(source, { path('spacing_use_prediction') }), movement.spacing.use_prediction)
        movement.spacing.lookahead_s = normalize_number(first_path(source, { path('spacing_lookahead_s') }), movement.spacing.lookahead_s)
        movement.spacing.repel_hold_ticks = normalize_number(first_path(source, { path('spacing_repel_hold_ticks') }), movement.spacing.repel_hold_ticks, { integer = true })
        movement.spacing.overlap_deadband = normalize_number(first_path(source, { path('spacing_overlap_deadband') }), movement.spacing.overlap_deadband)
        movement.spacing.repel_weight = normalize_number(first_path(source, { path('spacing_repel_weight') }), movement.spacing.repel_weight)
        movement.spacing.band_deadband = normalize_number(first_path(source, { path('spacing_band_deadband') }), movement.spacing.band_deadband)
        movement.path.recording = normalize_boolean(first_path(source, { path('path_recording') }), movement.path.recording)
        movement.path.follow_enabled = normalize_boolean(first_path(source, { path('path_follow_enabled') }), movement.path.follow_enabled)
        movement.path.file_name = normalize_string(first_path(source, { path('path_file_name') }), movement.path.file_name)
        movement.path.route_type = normalize_string(first_path(source, { path('path_route_type') }), movement.path.route_type)
        movement.path.distance_to_start = normalize_number(first_path(source, { path('path_distance_to_start') }), movement.path.distance_to_start)
        movement.path.points = normalize_list(first_path(source, { path('path_points') }), movement.path.points)
        movement.path.party_gate_yalms = normalize_number(first_path(source, { path('path_party_gate_yalms') }), movement.path.party_gate_yalms)
        movement.path.resume_index_window = normalize_number(first_path(source, { path('path_resume_index_window') }), movement.path.resume_index_window, { integer = true })
        movement.path.hunter_targets = normalize_list(first_path(source, { path('path_hunter_targets') }), movement.path.hunter_targets)
        movement.path.hunter_max_z_delta = normalize_number(first_path(source, { path('path_hunter_max_z_delta') }), movement.path.hunter_max_z_delta)
        movement.path.hunter_max_target_range = normalize_number(first_path(source, { path('path_hunter_max_target_range') }), movement.path.hunter_max_target_range)
        movement.path.hunter_claim_timeout_s = normalize_number(first_path(source, { path('path_hunter_claim_timeout_s') }), movement.path.hunter_claim_timeout_s)
        movement.path.hunter_ignore_cooldown_s = normalize_number(first_path(source, { path('path_hunter_ignore_cooldown_s') }), movement.path.hunter_ignore_cooldown_s)
        movement.path.pull_action_type = normalize_string(first_path(source, { path('path_pull_action_type') }), movement.path.pull_action_type)
        movement.path.pull_action_name = normalize_string(first_path(source, { path('path_pull_action_name') }), movement.path.pull_action_name)
    end
end

local function validate_formation_activation(config)
    local formation = config.movement.formation
    local named = config.movement.named_formations
    if named.enabled == true and config.movement.enabled ~= true then
        error('enabled named formations require config.movement.enabled')
    end
    if formation.mock.enabled == true and formation.enabled ~= true then
        error('enabled formation mock requires config.movement.formation.enabled')
    end
    if formation.enabled ~= true then
        return
    end
    if formation.encounter == 'lilith_easy' then
        if formation.mock.enabled == true then
            error('formation mock is supported only for generic formation')
        end
        return
    end
    if GENERIC_FORMATION_ENCOUNTER_IDS[formation.encounter] ~= true then
        error('enabled config.movement.formation.encounter must be lilith_easy, sortie_ghatjot, or sortie_dhartok')
    end
    if config.movement.enabled ~= true then
        error('enabled generic formation requires config.movement.enabled')
    end
    if config.encounter.enabled ~= true then
        error('enabled generic formation requires config.encounter.enabled')
    end
    if config.encounter.id ~= formation.encounter then
        error('generic formation encounter must match config.encounter.id')
    end
end

local function normalize_follow(source, config)
    local follow = config.follow
    local nested = get_path(source, { 'follow' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'party', 'fight', 'partner', 'nyzul' }) then
        follow.enabled = normalize_boolean(nested.enabled, follow.enabled)
        local party = is_table(nested.party) and nested.party or {}
        follow.party.enabled = normalize_boolean(party.enabled, follow.party.enabled)
        follow.party.leader_id = normalize_number(party.leader_id, follow.party.leader_id, { integer = true })
        follow.party.leader_name = normalize_string(party.leader_name, follow.party.leader_name)
        follow.party.min = normalize_number(party.min, follow.party.min)
        follow.party.max = normalize_number(party.max, follow.party.max)
        local fight = is_table(nested.fight) and nested.fight or {}
        follow.fight.leader = normalize_boolean(fight.leader, follow.fight.leader)
        follow.fight.leader_id = normalize_number(fight.leader_id, follow.fight.leader_id, { integer = true })
        follow.fight.leader_name = normalize_string(fight.leader_name, follow.fight.leader_name)
        follow.fight.min = normalize_number(fight.min, follow.fight.min)
        follow.fight.hold_s = normalize_number(fight.hold_s, follow.fight.hold_s)
        local partner = is_table(nested.partner) and nested.partner or {}
        follow.partner.enabled = normalize_boolean(partner.enabled, follow.partner.enabled)
        follow.partner.secondary_enabled = normalize_boolean(partner.secondary_enabled, follow.partner.secondary_enabled)
		follow.partner.names = normalize_pipe_string_list(partner.names, follow.partner.names)
        follow.partner.ids = normalize_list(partner.ids, follow.partner.ids)
        follow.partner.puller = normalize_boolean(partner.puller, follow.partner.puller)
        follow.partner.puller_name = normalize_string(partner.puller_name, follow.partner.puller_name)
        follow.partner.puller_id = normalize_number(partner.puller_id, follow.partner.puller_id, { integer = true })
		follow.partner.leash_source = normalize_leash_source(partner.leash_source, follow.partner.leash_source)
        follow.partner.engage_range = normalize_number(partner.engage_range, follow.partner.engage_range, { min = 0.1, max = 50.0 })
        follow.partner.puller_distance_only = normalize_boolean(partner.puller_distance_only, follow.partner.puller_distance_only)
		local nyzul = is_table(nested.nyzul) and nested.nyzul or {}
		follow.nyzul.coordinator_name = normalize_string(nyzul.coordinator_name, follow.nyzul.coordinator_name)
		follow.nyzul.anchor_name = normalize_string(nyzul.anchor_name, follow.nyzul.anchor_name)
		follow.nyzul.parking_order = normalize_pipe_string_list(nyzul.parking_order, follow.nyzul.parking_order)
    else
        follow.enabled = normalize_boolean(first_path(source, { path('domain_follow_enabled') }), follow.enabled)
        follow.party.enabled = normalize_boolean(first_path(source, { path('party_follow') }), follow.party.enabled)
        follow.party.leader_id = normalize_number(first_path(source, { path('party_follow_id') }), follow.party.leader_id, { integer = true })
        follow.party.leader_name = normalize_string(first_path(source, { path('party_follow_leader_name') }), follow.party.leader_name)
        follow.party.min = normalize_number(first_path(source, { path('party_follow_min') }), follow.party.min)
        follow.party.max = normalize_number(first_path(source, { path('party_follow_max') }), follow.party.max)
        follow.fight.leader = normalize_boolean(first_path(source, { path('fight_leader') }), follow.fight.leader)
        follow.fight.leader_id = normalize_number(first_path(source, { path('fight_leader_id') }), follow.fight.leader_id, { integer = true })
        follow.fight.leader_name = normalize_string(first_path(source, { path('fight_leader_name'), path('fight_leader_selected') }), follow.fight.leader_name)
        follow.fight.min = normalize_number(first_path(source, { path('fight_follow_min') }), follow.fight.min)
        follow.fight.hold_s = normalize_number(first_path(source, { path('fight_follow_hold_s') }), follow.fight.hold_s)
        follow.partner.enabled = normalize_boolean(first_path(source, { path('partner') }), follow.partner.enabled)
        follow.partner.secondary_enabled = normalize_boolean(first_path(source, { path('partner2') }), follow.partner.secondary_enabled)
		follow.partner.names = normalize_pipe_string_list(first_path(source, { path('partner_names') }), follow.partner.names)
        follow.partner.ids = normalize_list(first_path(source, { path('partner_ids') }), follow.partner.ids)
        follow.partner.puller = normalize_boolean(first_path(source, { path('puller') }), follow.partner.puller)
        follow.partner.puller_name = normalize_string(first_path(source, { path('puller_name'), path('puller_selected') }), follow.partner.puller_name)
        follow.partner.puller_id = normalize_number(first_path(source, { path('puller_id') }), follow.partner.puller_id, { integer = true })
		follow.partner.leash_source = normalize_leash_source(first_path(source, { path('puller_leash_source') }), follow.partner.leash_source)
        follow.partner.engage_range = normalize_number(first_path(source, { path('puller_engage_range') }), follow.partner.engage_range, { min = 0.1, max = 50.0 })
        follow.partner.puller_distance_only = normalize_boolean(first_path(source, { path('puller_distance_only') }), follow.partner.puller_distance_only)
		follow.nyzul.coordinator_name = normalize_string(first_path(source, { path('nyzul_coordinator_name') }), follow.nyzul.coordinator_name)
		follow.nyzul.anchor_name = normalize_string(first_path(source, { path('nyzul_anchor_name') }), follow.nyzul.anchor_name)
		follow.nyzul.parking_order = normalize_pipe_string_list(first_path(source, { path('nyzul_parking_order') }), follow.nyzul.parking_order)
    end
end

local function normalize_targeting(source, config)
    local targeting = config.targeting
    local nested = get_path(source, { 'targeting' })
    if is_table(nested) and table_has_any(nested, { 'add_control', 'add_priority_names', 'legacy_slots', 'targets', 'targetability', 'ignore', 'target_ignore_names' }) then
        targeting.add_control = normalize_boolean(nested.add_control, targeting.add_control)
        local nested_target_names = nested.targets
        if type(nested_target_names) == 'table' and #nested_target_names == 0 then
            nested_target_names = nil
        end
        if nested_target_names == nil then
            nested_target_names = nested.add_priority_names
        end
        local nested_add_priority_names = nested.add_priority_names
        if type(nested_add_priority_names) == 'table' and #nested_add_priority_names == 0 then
            nested_add_priority_names = nil
        end
        if nested_add_priority_names == nil then
            nested_add_priority_names = nested.targets
        end
        targeting.add_priority_names = normalize_list(nested_add_priority_names, targeting.add_priority_names)
        targeting.legacy_slots = normalize_list(nested.legacy_slots, targeting.legacy_slots)
        targeting.targets = normalize_list(nested_target_names, targeting.targets)
        local nested_targetability = is_table(nested.targetability) and nested.targetability or {}
        targeting.targetability.enabled = normalize_boolean(nested_targetability.enabled, targeting.targetability.enabled)
        targeting.targetability.action = normalize_string(nested_targetability.action, targeting.targetability.action)
        targeting.ignore = normalize_list(nested.ignore, targeting.ignore)
        targeting.target_ignore_names = normalize_list(nested.target_ignore_names, targeting.target_ignore_names)
    else
        targeting.add_control = normalize_boolean(first_path(source, { path('add_control') }), targeting.add_control)
        local flat_target_names = first_path(source, { path('targets') })
        if type(flat_target_names) == 'table' and #flat_target_names == 0 then
            flat_target_names = nil
        end
        if flat_target_names == nil then
            flat_target_names = first_path(source, { path('add_priority_names') })
        end
        local flat_add_priority_names = first_path(source, { path('add_priority_names') })
        if type(flat_add_priority_names) == 'table' and #flat_add_priority_names == 0 then
            flat_add_priority_names = nil
        end
        if flat_add_priority_names == nil then
            flat_add_priority_names = first_path(source, { path('targets') })
        end
        targeting.add_priority_names = normalize_list(flat_add_priority_names, targeting.add_priority_names)
        targeting.legacy_slots = normalize_list({
            first_path(source, { path('target1') }),
            first_path(source, { path('target2') }),
            first_path(source, { path('target3') }),
        }, targeting.legacy_slots)
        targeting.targets = normalize_list(flat_target_names, targeting.targets)
        targeting.targetability.enabled = normalize_boolean(first_path(source, { path('targetability_active') }), targeting.targetability.enabled)
        targeting.targetability.action = normalize_string(first_path(source, { path('targetability') }), targeting.targetability.action)
        targeting.ignore = normalize_list(first_path(source, { path('ignore') }), targeting.ignore)
        targeting.target_ignore_names = normalize_list(first_path(source, { path('target_ignore_names') }), targeting.target_ignore_names)
    end
end

local function normalize_tank(source, config)
    local tank = config.tank
    local nested = get_path(source, { 'tank' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'enmity' }) then
        tank.enabled = normalize_boolean(nested.enabled, tank.enabled)
        local enmity = is_table(nested.enmity) and nested.enmity or {}
        tank.enmity.actions = normalize_list(enmity.actions, tank.enmity.actions)
    else
        tank.enabled = normalize_boolean(first_path(source, { path('tank') }), tank.enabled)
        tank.enmity.actions = normalize_list(first_path(source, { path('tank_enmity_actions') }), tank.enmity.actions)
    end
end

local function normalize_sleep(source, config)
    local sleep = config.sleep
    local nested = get_path(source, { 'sleep' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'order', 'legacy_primary', 'max_target_range' }) then
        sleep.enabled = normalize_boolean(nested.enabled, sleep.enabled)
        sleep.max_target_range = normalize_number(nested.max_target_range, sleep.max_target_range, { min = 0.1, max = 50.0 })
        local order = nested.order
        local order_was_provided = order ~= nil
        if order == nil and nested.legacy_primary ~= nil then
            order = { nested.legacy_primary }
            order_was_provided = true
        end
        sleep.order = normalize_list(order, sleep.order)
        local legacy_primary = normalize_optional_string(nested.legacy_primary)
        if legacy_primary ~= nil then
            sleep.legacy_primary = legacy_primary
        elseif #sleep.order > 0 then
            sleep.legacy_primary = normalize_string(sleep.order[1], sleep.legacy_primary)
        elseif order_was_provided then
            sleep.legacy_primary = ''
        end
    else
        sleep.enabled = normalize_boolean(first_path(source, { path('sleep') }), sleep.enabled)
        sleep.max_target_range = normalize_number(first_path(source, { path('sleep_max_target_range') }), sleep.max_target_range, { min = 0.1, max = 50.0 })
        local order = first_path(source, { path('sleepspells') })
        local order_was_provided = order ~= nil
        if order == nil then
            local legacy_primary = normalize_optional_string(first_path(source, { path('sleepspell') }))
            if legacy_primary ~= nil then
                order = { legacy_primary }
                order_was_provided = true
            end
        end
        sleep.order = normalize_list(order, sleep.order)
        local legacy_primary = normalize_optional_string(first_path(source, { path('sleepspell') }))
        if legacy_primary ~= nil then
            sleep.legacy_primary = legacy_primary
        elseif #sleep.order > 0 then
            sleep.legacy_primary = normalize_string(sleep.order[1], sleep.legacy_primary)
        elseif order_was_provided then
            sleep.legacy_primary = ''
        end
    end
end

local function normalize_spells(source, config)
    local spells = config.spells
    local nested = get_path(source, { 'spells' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'configured', 'magic_burst', 'dd2_slots', 'spell' }) then
            spells.enabled = normalize_boolean(nested.enabled, spells.enabled)
            spells.configured = normalize_string(nested.configured or nested.spell, spells.configured)
        spells.magic_burst = normalize_boolean(nested.magic_burst, spells.magic_burst)
        spells.dd2_slots = normalize_list(nested.dd2_slots, spells.dd2_slots)
    else
            spells.enabled = normalize_boolean(first_path(source, { path('spell_active') }), spells.enabled)
            spells.configured = normalize_string(first_path(source, { path('spell') }), spells.configured)
        spells.magic_burst = normalize_boolean(first_path(source, { path('magic_burst_enabled') }), spells.magic_burst)
        spells.dd2_slots = normalize_list(first_path(source, { path('dd2_spell_slots') }), spells.dd2_slots)
    end
end

local function normalize_maintenance(source, config)
    local maintenance = config.maintenance
    local nested = get_path(source, { 'maintenance' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'cor', 'brd', 'geo' }) then
        maintenance.enabled = normalize_boolean(nested.enabled, maintenance.enabled)
        local cor = is_table(nested.cor) and nested.cor or {}
        maintenance.cor.roll_1 = normalize_string(cor.roll_1, maintenance.cor.roll_1)
        maintenance.cor.roll_2 = normalize_string(cor.roll_2, maintenance.cor.roll_2)
        maintenance.cor.crooked_roll_slot = normalize_number(cor.crooked_roll_slot, maintenance.cor.crooked_roll_slot, { integer = true })
        maintenance.cor.elevens = normalize_boolean(cor.elevens, maintenance.cor.elevens)
        maintenance.cor.luzaf_range_override = normalize_boolean(cor.luzaf_range_override, maintenance.cor.luzaf_range_override)
        maintenance.cor.range_selected = normalize_string(cor.range_selected, maintenance.cor.range_selected)
        maintenance.cor.range_require_ids = normalize_list(cor.range_require_ids, maintenance.cor.range_require_ids)
        local brd = is_table(nested.brd) and nested.brd or {}
        maintenance.brd.enabled = normalize_boolean(brd.enabled, maintenance.brd.enabled)
        maintenance.brd.songs = normalize_pipe_string_list(brd.songs, maintenance.brd.songs)
        maintenance.brd.dummy_songs = normalize_pipe_string_list(brd.dummy_songs, maintenance.brd.dummy_songs)
        maintenance.brd.use_nitro = normalize_boolean(brd.use_nitro, maintenance.brd.use_nitro)
        maintenance.brd.use_soul_voice = normalize_boolean(brd.use_soul_voice, maintenance.brd.use_soul_voice)
        maintenance.brd.use_clarion_call = normalize_boolean(brd.use_clarion_call, maintenance.brd.use_clarion_call)
        maintenance.brd.use_marcato = normalize_boolean(brd.use_marcato, maintenance.brd.use_marcato)
        maintenance.brd.marcato_song = normalize_string(brd.marcato_song, maintenance.brd.marcato_song)
		maintenance.brd.targeted_songs = normalize_brd_targeted_songs(brd.targeted_songs, maintenance.brd.targeted_songs)
		maintenance.brd.recovery_range_yalms = normalize_number(brd.recovery_range_yalms, maintenance.brd.recovery_range_yalms, { min = 1.0, max = 20.0 })
		maintenance.brd.recovery_ignore_names = normalize_pipe_string_list(brd.recovery_ignore_names, maintenance.brd.recovery_ignore_names)
		maintenance.brd.reposition_for_party_songs = normalize_boolean(brd.reposition_for_party_songs, maintenance.brd.reposition_for_party_songs)
        maintenance.geo = normalize_geo_maintenance(nested.geo)
    else
        maintenance.enabled = normalize_boolean(first_path(source, { path('domain_maintenance_enabled') }), maintenance.enabled)
        maintenance.cor.roll_1 = normalize_string(first_path(source, { path('cor_roll_1') }), maintenance.cor.roll_1)
        maintenance.cor.roll_2 = normalize_string(first_path(source, { path('cor_roll_2') }), maintenance.cor.roll_2)
        maintenance.cor.crooked_roll_slot = normalize_number(first_path(source, { path('cor_crooked_roll_slot') }), maintenance.cor.crooked_roll_slot, { integer = true })
        maintenance.cor.elevens = normalize_boolean(first_path(source, { path('cor_elevens') }), maintenance.cor.elevens)
        maintenance.cor.luzaf_range_override = normalize_boolean(first_path(source, { path('cor_luzaf_range_override') }), maintenance.cor.luzaf_range_override)
        maintenance.cor.range_selected = normalize_string(first_path(source, { path('cor_roll_range_selected') }), maintenance.cor.range_selected)
        maintenance.cor.range_require_ids = normalize_list(first_path(source, { path('cor_roll_range_require_ids') }), maintenance.cor.range_require_ids)
        maintenance.brd.enabled = normalize_boolean(first_path(source, { path('brd_maintenance_enabled') }), maintenance.brd.enabled)
        maintenance.brd.songs = normalize_pipe_string_list(first_path(source, { path('brd_songs') }), maintenance.brd.songs)
        maintenance.brd.dummy_songs = normalize_pipe_string_list(first_path(source, { path('brd_dummy_songs') }), maintenance.brd.dummy_songs)
        maintenance.brd.use_nitro = normalize_boolean(first_path(source, { path('brd_use_nitro') }), maintenance.brd.use_nitro)
        maintenance.brd.use_soul_voice = normalize_boolean(first_path(source, { path('brd_use_soul_voice') }), maintenance.brd.use_soul_voice)
        maintenance.brd.use_clarion_call = normalize_boolean(first_path(source, { path('brd_use_clarion_call') }), maintenance.brd.use_clarion_call)
        maintenance.brd.use_marcato = normalize_boolean(first_path(source, { path('brd_use_marcato') }), maintenance.brd.use_marcato)
        maintenance.brd.marcato_song = normalize_string(first_path(source, { path('brd_marcato_song') }), maintenance.brd.marcato_song)
		maintenance.brd.targeted_songs = normalize_brd_targeted_songs(first_path(source, { path('brd_targeted_songs') }), maintenance.brd.targeted_songs)
		maintenance.brd.recovery_range_yalms = normalize_number(first_path(source, { path('brd_recovery_range_yalms') }), maintenance.brd.recovery_range_yalms, { min = 1.0, max = 20.0 })
		maintenance.brd.recovery_ignore_names = normalize_pipe_string_list(first_path(source, { path('brd_recovery_ignore_names') }), maintenance.brd.recovery_ignore_names)
		maintenance.brd.reposition_for_party_songs = normalize_boolean(first_path(source, { path('brd_reposition_for_party_songs') }), maintenance.brd.reposition_for_party_songs)
        maintenance.geo = normalize_geo_maintenance(first_path(source, { path('maintenance_geo') }))
    end
end

local function normalize_debug(source, config)
    local debug = config.debug
    local nested = get_path(source, { 'debug' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'combat_sched', 'ja_sched', 'ja_debug', 'def_sched', 'tank_sched' }) then
        debug.enabled = normalize_boolean(nested.enabled, debug.enabled)
        debug.combat_sched = normalize_boolean(nested.combat_sched, debug.combat_sched)
        debug.ja_sched = normalize_boolean(nested.ja_sched, debug.ja_sched)
        debug.ja_debug = normalize_boolean(nested.ja_debug, debug.ja_debug)
        debug.def_sched = normalize_boolean(nested.def_sched, debug.def_sched)
        debug.tank_sched = normalize_boolean(nested.tank_sched, debug.tank_sched)
    else
        debug.enabled = normalize_boolean(first_path(source, { path('debug') }), debug.enabled)
        debug.combat_sched = normalize_boolean(first_path(source, { path('log_combat_sched') }), debug.combat_sched)
        debug.ja_sched = normalize_boolean(first_path(source, { path('log_ja_sched') }), debug.ja_sched)
        debug.ja_debug = normalize_boolean(first_path(source, { path('log_ja_debug') }), debug.ja_debug)
        debug.def_sched = normalize_boolean(first_path(source, { path('log_def_sched') }), debug.def_sched)
        debug.tank_sched = normalize_boolean(first_path(source, { path('log_tank_sched') }), debug.tank_sched)
    end
end

local function normalize_ownership(source, config)
    local ownership = config.ownership
    local nested = get_path(source, { 'ownership' })
    if is_table(nested) and table_has_any(nested, { 'domain_combat_enabled', 'domain_defensive_enabled', 'domain_movement_enabled', 'domain_maintenance_enabled', 'domain_follow_enabled', 'pause_automation_while_weakened' }) then
        ownership.domain_combat_enabled = normalize_boolean(nested.domain_combat_enabled, ownership.domain_combat_enabled)
        ownership.domain_defensive_enabled = normalize_boolean(nested.domain_defensive_enabled, ownership.domain_defensive_enabled)
        ownership.domain_movement_enabled = normalize_boolean(nested.domain_movement_enabled, ownership.domain_movement_enabled)
        ownership.domain_maintenance_enabled = normalize_boolean(nested.domain_maintenance_enabled, ownership.domain_maintenance_enabled)
        ownership.domain_follow_enabled = normalize_boolean(nested.domain_follow_enabled, ownership.domain_follow_enabled)
        ownership.pause_automation_while_weakened = normalize_boolean(nested.pause_automation_while_weakened, ownership.pause_automation_while_weakened)
    else
        ownership.domain_combat_enabled = normalize_boolean(first_path(source, { path('domain_combat_enabled') }), ownership.domain_combat_enabled)
        ownership.domain_defensive_enabled = normalize_boolean(first_path(source, { path('domain_defensive_enabled') }), ownership.domain_defensive_enabled)
        ownership.domain_movement_enabled = normalize_boolean(first_path(source, { path('domain_movement_enabled') }), ownership.domain_movement_enabled)
        ownership.domain_maintenance_enabled = normalize_boolean(first_path(source, { path('domain_maintenance_enabled') }), ownership.domain_maintenance_enabled)
        ownership.domain_follow_enabled = normalize_boolean(first_path(source, { path('domain_follow_enabled') }), ownership.domain_follow_enabled)
        ownership.pause_automation_while_weakened = normalize_boolean(first_path(source, { path('pause_automation_while_weakened') }), ownership.pause_automation_while_weakened)
    end
end

local function normalize_summoner(source, config)
    local summoner = config.summoner
    local nested = get_path(source, { 'summoner' })
    if is_table(nested) then
        if type(nested.enabled) ~= 'boolean' then
            error('summoner.enabled must be boolean')
        end
        summoner.enabled = nested.enabled
        if nested.avatar ~= nil and type(nested.avatar) ~= 'string' then
            error('summoner.avatar must be a string or nil')
        end
        summoner.avatar = normalize_optional_string(nested.avatar)
        if nested.maintenance == nil or not is_table(nested.maintenance) then
            error('summoner.maintenance must be a table')
        end
        local maintenance = nested.maintenance
        if type(maintenance.avatar_favor) ~= 'boolean' then
            error('summoner.maintenance.avatar_favor must be boolean')
        end
        summoner.maintenance.avatar_favor = maintenance.avatar_favor
        if maintenance.ward == nil or not is_table(maintenance.ward) then
            error('summoner.maintenance.ward must be a table')
        end
        local ward = maintenance.ward
        if type(ward.enabled) ~= 'boolean' then
            error('summoner.maintenance.ward.enabled must be boolean')
        end
		if ward.actions ~= nil and ward.action ~= nil then
			error('summoner.maintenance.ward must define actions or legacy action, not both')
		end
		if ward.actions == nil and ward.action ~= nil and type(ward.action) ~= 'string' then
			error('summoner.maintenance.ward.action must be a string or nil')
		end
        summoner.maintenance.ward.enabled = ward.enabled
		if ward.actions ~= nil then
			summoner.maintenance.ward.actions = normalize_summoner_ward_actions(
				ward.actions,
				'summoner.maintenance.ward.actions'
			)
		else
			local legacy_action = normalize_optional_string(ward.action)
			summoner.maintenance.ward.actions = legacy_action and { legacy_action } or {}
		end
        if nested.pet_combat == nil or not is_table(nested.pet_combat) then
            error('summoner.pet_combat must be a table')
        end
        local pet_combat = nested.pet_combat
        if type(pet_combat.engage_on_combat_start) ~= 'boolean' then
            error('summoner.pet_combat.engage_on_combat_start must be boolean')
        end
        summoner.pet_combat.engage_on_combat_start = pet_combat.engage_on_combat_start
        if pet_combat.offensive_action == nil or not is_table(pet_combat.offensive_action) then
            error('summoner.pet_combat.offensive_action must be a table')
        end
        local offensive = pet_combat.offensive_action
        if type(offensive.enabled) ~= 'boolean' then
            error('summoner.pet_combat.offensive_action.enabled must be boolean')
        end
        if offensive.action ~= nil and type(offensive.action) ~= 'string' then
            error('summoner.pet_combat.offensive_action.action must be a string or nil')
        end
        if type(offensive.usage) ~= 'string' or trim_string(offensive.usage) == '' then
            error('summoner.pet_combat.offensive_action.usage must be a non-empty string')
        end
        local target_hpp_gate_present = offensive.target_hpp_above_enabled ~= nil
            or offensive.target_hpp_above ~= nil
        if target_hpp_gate_present then
            if type(offensive.target_hpp_above_enabled) ~= 'boolean' then
                error('summoner.pet_combat.offensive_action.target_hpp_above_enabled must be boolean')
            end
            if type(offensive.target_hpp_above) ~= 'number'
                or offensive.target_hpp_above % 1 ~= 0
                or offensive.target_hpp_above < 0
                or offensive.target_hpp_above > 99 then
                error('summoner.pet_combat.offensive_action.target_hpp_above must be an integer from 0 to 99')
            end
        end
        local pet_tp_gate_present = offensive.pet_tp_above_enabled ~= nil
            or offensive.pet_tp_above ~= nil
        if pet_tp_gate_present then
            if type(offensive.pet_tp_above_enabled) ~= 'boolean' then
                error('summoner.pet_combat.offensive_action.pet_tp_above_enabled must be boolean')
            end
            if type(offensive.pet_tp_above) ~= 'number'
                or offensive.pet_tp_above % 1 ~= 0
                or offensive.pet_tp_above < 0
                or offensive.pet_tp_above > 2999 then
                error('summoner.pet_combat.offensive_action.pet_tp_above must be an integer from 0 to 2999')
            end
        end
        summoner.pet_combat.offensive_action.enabled = offensive.enabled
        summoner.pet_combat.offensive_action.action = normalize_optional_string(offensive.action)
        summoner.pet_combat.offensive_action.usage = trim_string(offensive.usage)
        if target_hpp_gate_present then
            summoner.pet_combat.offensive_action.target_hpp_above_enabled =
                offensive.target_hpp_above_enabled
            summoner.pet_combat.offensive_action.target_hpp_above =
                offensive.target_hpp_above
        end
        if pet_tp_gate_present then
            summoner.pet_combat.offensive_action.pet_tp_above_enabled =
                offensive.pet_tp_above_enabled
            summoner.pet_combat.offensive_action.pet_tp_above =
                offensive.pet_tp_above
        end
    else
        summoner.enabled = normalize_boolean(
            first_path(source, { path('summoner_enabled') }),
            summoner.enabled
        )
        summoner.avatar = normalize_optional_string(first_path(source, { path('summoner_avatar') }))
        summoner.maintenance.avatar_favor = normalize_boolean(
            first_path(source, { path('summoner_avatar_favor') }),
            summoner.maintenance.avatar_favor
        )
        summoner.maintenance.ward.enabled = normalize_boolean(
            first_path(source, { path('summoner_ward_enabled') }),
            summoner.maintenance.ward.enabled
        )
		local flat_ward_actions = first_path(source, { path('summoner_ward_actions') })
		local legacy_ward_action = normalize_optional_string(
			first_path(source, { path('summoner_ward_action') })
		)
		summoner.maintenance.ward.actions = normalize_summoner_ward_actions(
			flat_ward_actions,
			'summoner_ward_actions'
		)
		if legacy_ward_action ~= nil then
			if #summoner.maintenance.ward.actions == 0 then
				summoner.maintenance.ward.actions[1] = legacy_ward_action
			elseif summoner.maintenance.ward.actions[1] ~= legacy_ward_action then
				error('summoner_ward_action must match the first summoner_ward_actions entry')
			end
		end
        summoner.pet_combat.engage_on_combat_start = normalize_boolean(
            first_path(source, { path('summoner_engage_on_combat_start') }),
            summoner.pet_combat.engage_on_combat_start
        )
        summoner.pet_combat.offensive_action.enabled = normalize_boolean(
            first_path(source, { path('summoner_rage_enabled') }),
            summoner.pet_combat.offensive_action.enabled
        )
        summoner.pet_combat.offensive_action.action = normalize_optional_string(
            first_path(source, { path('summoner_rage_action') })
        )
        summoner.pet_combat.offensive_action.usage = normalize_string(
            first_path(source, { path('summoner_rage_usage') }),
            summoner.pet_combat.offensive_action.usage
        )
        local flat_target_hpp_enabled = first_path(source, {
            path('summoner_rage_target_hpp_above_enabled'),
        })
        local flat_target_hpp_above = first_path(source, {
            path('summoner_rage_target_hpp_above'),
        })
        if flat_target_hpp_enabled ~= nil or flat_target_hpp_above ~= nil then
            if type(flat_target_hpp_enabled) ~= 'boolean' then
                error('summoner_rage_target_hpp_above_enabled must be boolean')
            end
            if type(flat_target_hpp_above) ~= 'number'
                or flat_target_hpp_above % 1 ~= 0
                or flat_target_hpp_above < 0
                or flat_target_hpp_above > 99 then
                error('summoner_rage_target_hpp_above must be an integer from 0 to 99')
            end
            summoner.pet_combat.offensive_action.target_hpp_above_enabled =
                flat_target_hpp_enabled
            summoner.pet_combat.offensive_action.target_hpp_above =
                flat_target_hpp_above
        end
        local flat_pet_tp_enabled = first_path(source, {
            path('summoner_rage_pet_tp_above_enabled'),
        })
        local flat_pet_tp_above = first_path(source, {
            path('summoner_rage_pet_tp_above'),
        })
        if flat_pet_tp_enabled ~= nil or flat_pet_tp_above ~= nil then
            if type(flat_pet_tp_enabled) ~= 'boolean' then
                error('summoner_rage_pet_tp_above_enabled must be boolean')
            end
            if type(flat_pet_tp_above) ~= 'number'
                or flat_pet_tp_above % 1 ~= 0
                or flat_pet_tp_above < 0
                or flat_pet_tp_above > 2999 then
                error('summoner_rage_pet_tp_above must be an integer from 0 to 2999')
            end
            summoner.pet_combat.offensive_action.pet_tp_above_enabled =
                flat_pet_tp_enabled
            summoner.pet_combat.offensive_action.pet_tp_above =
                flat_pet_tp_above
        end
    end
end

local function normalize_puppetmaster(source, config)
    local nested = get_path(source, { 'puppetmaster' })
    local candidate = nil
    if nested ~= nil then
        candidate = nested
    else
        local enabled = first_path(source, { path('puppetmaster_enabled') })
        local activate_if_missing = first_path(source, { path('puppetmaster_activate_if_missing') })
        local deploy_on_combat_start = first_path(source, { path('puppetmaster_deploy_on_combat_start') })
        local maneuvers_enabled = first_path(source, { path('puppetmaster_maneuvers_enabled') })
        local maneuver_pattern = first_path(source, { path('puppetmaster_maneuver_pattern') })
        local quiet = first_path(source, { path('puppetmaster_post_activate_quiet_seconds') })
        local ceiling = first_path(source, { path('puppetmaster_safe_burden_ceiling') })
        if enabled ~= nil or activate_if_missing ~= nil or deploy_on_combat_start ~= nil
            or maneuvers_enabled ~= nil or maneuver_pattern ~= nil or quiet ~= nil or ceiling ~= nil then
            local defaults = uc_pup_config.default_config()
            local pattern = maneuver_pattern
            if type(pattern) == 'string' then
                pattern = normalize_pipe_string_list(pattern, defaults.maneuvers.pattern)
            elseif pattern == nil then
                pattern = clone_value(defaults.maneuvers.pattern)
            end
            candidate = {
                enabled = normalize_boolean(enabled, defaults.enabled),
                activate_if_missing = normalize_boolean(activate_if_missing, defaults.activate_if_missing),
                deploy_on_combat_start = normalize_boolean(deploy_on_combat_start, defaults.deploy_on_combat_start),
                maneuvers = {
                    enabled = normalize_boolean(maneuvers_enabled, defaults.maneuvers.enabled),
                    pattern = pattern,
                    post_activate_quiet_seconds = normalize_number(quiet, defaults.maneuvers.post_activate_quiet_seconds, { integer = true }),
                    safe_burden_ceiling = normalize_number(ceiling, defaults.maneuvers.safe_burden_ceiling, { integer = true }),
                },
            }
        end
    end
    if candidate == nil then
        return
    end
    local copied, validation = uc_pup_config.copy_validated(candidate, config.profile)
    if copied == nil or validation.valid ~= true then
        local first = validation and validation.errors and validation.errors[1]
        error(first and first.message or 'Puppetmaster configuration validation failed')
    end
    config.puppetmaster = copied
end

local function normalize_sch(source, config)
    local nested = get_path(source, { 'sch' })
    if nested == nil then
        return
    end
    local copied, validation = uc_sch_config.copy_validated(nested, config.profile)
    if validation.valid ~= true then
        error('Scholar configuration validation failed')
    end
    config.sch = copied
end

local function normalize_reactions(source, config)
    local reactions = config.reactions
    local nested = get_path(source, { 'reactions' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'rules' }) then
        reactions.enabled = normalize_boolean(nested.enabled, reactions.enabled)
        reactions.rules = normalize_reaction_rules(nested.rules)
    else
        reactions.enabled = normalize_boolean(first_path(source, { path('reaction_enabled') }), reactions.enabled)
        reactions.rules = normalize_reaction_rules(first_path(source, { path('reaction_rules') }))
    end
end

local function validate_kei_reaction_configuration(config)
    if config.encounter.enabled ~= true or config.encounter.id ~= 'kei'
        or config.reactions.enabled ~= true then
        return
    end
    for i = 1, #config.reactions.rules do
        local rule = config.reactions.rules[i]
        if rule.trigger == 'ability_window'
            and type(rule.name) == 'string'
            and rule.name:lower() == 'dancing fullers' then
            error('Kei Fullers reaction is owned by config.encounter.kei.fullers; remove the duplicate reaction rule')
        end
    end
end

local function normalize_legacy(source, config)
    local legacy = config.legacy
    local nested = get_path(source, { 'legacy' })
    if is_table(nested) and table_has_any(nested, { 'sub', 'sub2', 'solo', 'aeonic', 'color', 'command', 'hunter', 'profiles' }) then
        legacy.sub = normalize_boolean(nested.sub, legacy.sub)
        legacy.sub2 = normalize_boolean(nested.sub2, legacy.sub2)
        legacy.solo = normalize_boolean(nested.solo, legacy.solo)
        legacy.aeonic = normalize_boolean(nested.aeonic, legacy.aeonic)
        legacy.color = normalize_boolean(nested.color, legacy.color)
        legacy.command = normalize_boolean(nested.command, legacy.command)
        legacy.hunter = normalize_boolean(nested.hunter, legacy.hunter)
        legacy.profiles = normalize_list(nested.profiles or first_path(source, { path('profiles') }), legacy.profiles)
    else
        legacy.sub = normalize_boolean(first_path(source, { path('sub') }), legacy.sub)
        legacy.sub2 = normalize_boolean(first_path(source, { path('sub2') }), legacy.sub2)
        legacy.solo = normalize_boolean(first_path(source, { path('solo') }), legacy.solo)
        legacy.aeonic = normalize_boolean(first_path(source, { path('aeonic') }), legacy.aeonic)
        legacy.color = normalize_boolean(first_path(source, { path('color') }), legacy.color)
        legacy.command = normalize_boolean(first_path(source, { path('command') }), legacy.command)
        legacy.hunter = normalize_boolean(first_path(source, { path('hunter') }), legacy.hunter)
        legacy.profiles = normalize_list(first_path(source, { path('profiles') }), legacy.profiles)
    end
end

function M.default_config(meta)
    return default_config(meta)
end

function M.normalize(settings, meta)
    local source, profile_source = normalize_source(settings)
    local config = default_config(meta)

    normalize_profile(profile_source, meta, config)
    config.ui.show_ingame_ui = normalize_boolean(first_path(source, { path('show_ingame_ui'), path('ui', 'show_ingame_ui') }), config.ui.show_ingame_ui)
    config.command.engine_enabled_default = normalize_boolean(first_path(source, { path('engine_enabled'), path('command', 'engine_enabled_default') }), config.command.engine_enabled_default)
    normalize_combat(source, config)
    normalize_list_domain(source, config)
    normalize_defensive(source, config)
    normalize_encounter(source, config)
    normalize_movement(source, config)
    validate_formation_activation(config)
    normalize_follow(source, config)
    normalize_targeting(source, config)
    normalize_reactions(source, config)
    validate_kei_reaction_configuration(config)
    normalize_tank(source, config)
    normalize_sleep(source, config)
    normalize_spells(source, config)
    normalize_maintenance(source, config)
    normalize_summoner(source, config)
    normalize_puppetmaster(source, config)
    normalize_sch(source, config)
    normalize_debug(source, config)
    normalize_ownership(source, config)
    normalize_legacy(source, config)

    return config
end

function M.version()
    return CURRENT_CANONICAL_CONFIG_VERSION
end

return M
