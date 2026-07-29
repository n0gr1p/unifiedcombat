local M = {}

local CURRENT_CANONICAL_CONFIG_VERSION = 1

local DEFAULT_SLEEP_ORDER = { 'Horde Lullaby II' }

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

local function normalize_optional_true_boolean(value)
    if value == true then
        return true
    end
    if type(value) == 'number' then
        if value == 1 then
            return true
        end
        return nil
    end
    if type(value) == 'string' then
        local lowered = trim_string(value):lower()
        if lowered == 'true' or lowered == 'on' or lowered == 'yes' or lowered == '1' then
            return true
        end
    end
    return nil
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
            local valid = (trigger == 'ability_window' and response == 'turn_away')
                or (trigger == 'enemy_buff' and response == 'stop_attacking')
            local key = trigger and name and (trigger .. ':' .. name:lower()) or nil
            if valid and name ~= nil and key ~= nil and not seen[key] then
                seen[key] = true
                out[#out + 1] = {
                    trigger = trigger,
                    name = name,
                    response = response,
                }
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
                wait_ignore_names = {},
                aftermath_enabled = false,
                aftermath_ws = '',
            },
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
            },
            doom = {
                holy_water_enabled = false,
            },
            na = {
                enabled = false,
            },
            enemy_buffs = {
                remove = false,
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
        movement = {
            enabled = true,
            move = false,
            formation = {
                enabled = false,
                encounter = 'lilith_easy',
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
            },
            geo = {},
        },
        summoner = {
            enabled = false,
            avatar = nil,
            maintenance = {
                avatar_favor = false,
                ward = {
                    enabled = false,
                    action = nil,
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
            profile_v2_auto_reload_on_change = false,
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

local function normalize_combat(source, config)
    local combat = config.combat
    local nested = get_path(source, { 'combat' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'autotarget', 'spam', 'closer', 'manual', 'prime', 'static', 'face', 'weaponskill' }) then
        combat.enabled = normalize_boolean(nested.enabled, combat.enabled)
        combat.autotarget = normalize_boolean(nested.autotarget, combat.autotarget)
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
        combat.weaponskill.wait_ignore_names = normalize_list(nested_ws.wait_ignore_names, combat.weaponskill.wait_ignore_names)
        combat.weaponskill.aftermath_enabled = normalize_boolean(nested_ws.aftermath_enabled, combat.weaponskill.aftermath_enabled)
        combat.weaponskill.aftermath_ws = normalize_string(nested_ws.aftermath_ws, combat.weaponskill.aftermath_ws)
    else
        combat.enabled = normalize_boolean(first_path(source, { path('domain_combat_enabled') }), combat.enabled)
        combat.autotarget = normalize_boolean(first_path(source, { path('autotarget') }), combat.autotarget)
        combat.spam = normalize_boolean(first_path(source, { path('spam') }), combat.spam)
        combat.closer = normalize_boolean(first_path(source, { path('closer') }), combat.closer)
        combat.manual = normalize_boolean(first_path(source, { path('manual') }), combat.manual)
        combat.prime = normalize_boolean(first_path(source, { path('prime') }), combat.prime)
        combat.static = normalize_boolean(first_path(source, { path('static') }), combat.static)
        combat.face = normalize_boolean(first_path(source, { path('face') }), combat.face)
        combat.weaponskill.enabled = normalize_boolean(first_path(source, { path('weaponskill_active') }), combat.weaponskill.enabled)
        combat.weaponskill.primary = normalize_string(first_path(source, { path('weaponskill'), path('ws1') }), combat.weaponskill.primary)
        combat.weaponskill.mode = normalize_string(first_path(source, { path('ws_mode') }), combat.weaponskill.mode)
        combat.weaponskill.wait_ignore_names = normalize_list(first_path(source, { path('wait_ignore_names') }), combat.weaponskill.wait_ignore_names)
        combat.weaponskill.aftermath_enabled = normalize_boolean(first_path(source, { path('aftermath_enabled') }), combat.weaponskill.aftermath_enabled)
        combat.weaponskill.aftermath_ws = normalize_string(first_path(source, { path('aftermath_ws') }), combat.weaponskill.aftermath_ws)
    end
end

local function normalize_defensive(source, config)
    local defensive = config.defensive
    local nested = get_path(source, { 'defensive' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'provider', 'cure', 'doom', 'na', 'enemy_buffs', 'buffs', 'thresholds' }) then
        defensive.enabled = normalize_boolean(nested.enabled, defensive.enabled)
        defensive.provider = normalize_string(nested.provider, defensive.provider)
        local cure = is_table(nested.cure) and nested.cure or {}
        defensive.cure.enabled = normalize_boolean(cure.enabled, defensive.cure.enabled)
        defensive.cure.min_tier = normalize_number(cure.min_tier, defensive.cure.min_tier, { integer = true })
        defensive.cure.max_tier = normalize_number(cure.max_tier, defensive.cure.max_tier, { integer = true })
        defensive.cure.min_missing_hp = normalize_number(cure.min_missing_hp, defensive.cure.min_missing_hp, { integer = true })
        defensive.cure.ignore_trusts = normalize_boolean(cure.ignore_trusts, defensive.cure.ignore_trusts)
        local doom = is_table(nested.doom) and nested.doom or {}
        defensive.doom.holy_water_enabled = normalize_boolean(doom.holy_water_enabled, defensive.doom.holy_water_enabled)
        local na = is_table(nested.na) and nested.na or {}
        defensive.na.enabled = normalize_boolean(na.enabled, defensive.na.enabled)
        local enemy_buffs = is_table(nested.enemy_buffs) and nested.enemy_buffs or {}
        defensive.enemy_buffs.remove = normalize_boolean(enemy_buffs.remove, defensive.enemy_buffs.remove)
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
        defensive.doom.holy_water_enabled = normalize_boolean(first_path(source, { path('defensive_doom_water') }), defensive.doom.holy_water_enabled)
        defensive.na.enabled = normalize_boolean(first_path(source, { path('defensive_na_enabled') }), defensive.na.enabled)
        defensive.enemy_buffs.remove = normalize_boolean(first_path(source, { path('def_remove_enemy_buffs') }), defensive.enemy_buffs.remove)
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

local function normalize_movement(source, config)
    local movement = config.movement
    local nested = get_path(source, { 'movement' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'move', 'formation', 'spacing', 'path' }) then
        movement.enabled = normalize_boolean(nested.enabled, movement.enabled)
        movement.move = normalize_boolean(nested.move, movement.move)
        local formation = is_table(nested.formation) and nested.formation or {}
        movement.formation.enabled = normalize_boolean(formation.enabled, movement.formation.enabled)
        movement.formation.encounter = normalize_string(formation.encounter, movement.formation.encounter)
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
    if is_table(nested) and table_has_any(nested, { 'enabled', 'configured', 'dd2_slots', 'spell' }) then
        spells.enabled = normalize_boolean(nested.enabled, spells.enabled)
        spells.configured = normalize_string(nested.configured or nested.spell, spells.configured)
        spells.dd2_slots = normalize_list(nested.dd2_slots, spells.dd2_slots)
    else
        spells.enabled = normalize_boolean(first_path(source, { path('spell_active') }), spells.enabled)
        spells.configured = normalize_string(first_path(source, { path('spell') }), spells.configured)
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
        maintenance.geo = normalize_list(nested.geo, maintenance.geo)
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
        maintenance.geo = normalize_list(first_path(source, { path('maintenance_geo') }), maintenance.geo)
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
    if is_table(nested) and table_has_any(nested, { 'domain_combat_enabled', 'domain_defensive_enabled', 'domain_movement_enabled', 'domain_maintenance_enabled', 'domain_follow_enabled', 'profile_v2_autoload', 'profile_v2_auto_reload_on_change' }) then
        ownership.domain_combat_enabled = normalize_boolean(nested.domain_combat_enabled, ownership.domain_combat_enabled)
        ownership.domain_defensive_enabled = normalize_boolean(nested.domain_defensive_enabled, ownership.domain_defensive_enabled)
        ownership.domain_movement_enabled = normalize_boolean(nested.domain_movement_enabled, ownership.domain_movement_enabled)
        ownership.domain_maintenance_enabled = normalize_boolean(nested.domain_maintenance_enabled, ownership.domain_maintenance_enabled)
        ownership.domain_follow_enabled = normalize_boolean(nested.domain_follow_enabled, ownership.domain_follow_enabled)
        ownership.profile_v2_autoload = normalize_optional_true_boolean(nested.profile_v2_autoload)
        local auto_reload = normalize_optional_true_boolean(nested.profile_v2_auto_reload_on_change)
        if auto_reload ~= nil then
            ownership.profile_v2_auto_reload_on_change = auto_reload
        end
    else
        ownership.domain_combat_enabled = normalize_boolean(first_path(source, { path('domain_combat_enabled') }), ownership.domain_combat_enabled)
        ownership.domain_defensive_enabled = normalize_boolean(first_path(source, { path('domain_defensive_enabled') }), ownership.domain_defensive_enabled)
        ownership.domain_movement_enabled = normalize_boolean(first_path(source, { path('domain_movement_enabled') }), ownership.domain_movement_enabled)
        ownership.domain_maintenance_enabled = normalize_boolean(first_path(source, { path('domain_maintenance_enabled') }), ownership.domain_maintenance_enabled)
        ownership.domain_follow_enabled = normalize_boolean(first_path(source, { path('domain_follow_enabled') }), ownership.domain_follow_enabled)
        ownership.profile_v2_autoload = normalize_optional_true_boolean(first_path(source, { path('profile_v2_autoload') }))
        local auto_reload = normalize_optional_true_boolean(first_path(source, { path('profile_v2_auto_reload_on_change') }))
        if auto_reload ~= nil then
            ownership.profile_v2_auto_reload_on_change = auto_reload
        end
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
        if ward.action ~= nil and type(ward.action) ~= 'string' then
            error('summoner.maintenance.ward.action must be a string or nil')
        end
        summoner.maintenance.ward.enabled = ward.enabled
        summoner.maintenance.ward.action = normalize_optional_string(ward.action)
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
        summoner.maintenance.ward.action = normalize_optional_string(
            first_path(source, { path('summoner_ward_action') })
        )
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
    normalize_movement(source, config)
    normalize_follow(source, config)
    normalize_targeting(source, config)
    normalize_reactions(source, config)
    normalize_tank(source, config)
    normalize_sleep(source, config)
    normalize_spells(source, config)
    normalize_maintenance(source, config)
    normalize_summoner(source, config)
    normalize_debug(source, config)
    normalize_ownership(source, config)
    normalize_legacy(source, config)

    return config
end

function M.version()
    return CURRENT_CANONICAL_CONFIG_VERSION
end

return M
