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
                min = 3.0,
                hold_s = 8.0,
            },
            partner = {
                enabled = false,
                secondary_enabled = false,
                ids = {},
                puller = false,
                puller_id = 0,
                puller_distance_only = false,
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
            brd = {},
            geo = {},
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
            scheduler_dark_launch_combat = false,
            scheduler_dark_launch_defensive = false,
            scheduler_dark_launch_movement = false,
            scheduler_dark_launch_maintenance = false,
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
        defensive.buffs.overwrite_enabled = normalize_boolean(first_path(source, { path('defensive_overwrite_enabled') }), defensive.buffs.overwrite_enabled)
        defensive.buffs.overwrite_interval = normalize_number(first_path(source, { path('defensive_overwrite_interval') }), defensive.buffs.overwrite_interval, { integer = true })
        defensive.thresholds.critical_hpp = normalize_number(first_path(source, { path('defensive_critical_hpp') }), defensive.thresholds.critical_hpp, { integer = true })
        defensive.thresholds.medium_hpp = normalize_number(first_path(source, { path('defensive_medium_hpp') }), defensive.thresholds.medium_hpp, { integer = true })
    end
end

local function normalize_movement(source, config)
    local movement = config.movement
    local nested = get_path(source, { 'movement' })
    if is_table(nested) and table_has_any(nested, { 'enabled', 'move', 'spacing', 'path' }) then
        movement.enabled = normalize_boolean(nested.enabled, movement.enabled)
        movement.move = normalize_boolean(nested.move, movement.move)
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
    if is_table(nested) and table_has_any(nested, { 'enabled', 'party', 'fight', 'partner' }) then
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
        follow.fight.min = normalize_number(fight.min, follow.fight.min)
        follow.fight.hold_s = normalize_number(fight.hold_s, follow.fight.hold_s)
        local partner = is_table(nested.partner) and nested.partner or {}
        follow.partner.enabled = normalize_boolean(partner.enabled, follow.partner.enabled)
        follow.partner.secondary_enabled = normalize_boolean(partner.secondary_enabled, follow.partner.secondary_enabled)
        follow.partner.ids = normalize_list(partner.ids, follow.partner.ids)
        follow.partner.puller = normalize_boolean(partner.puller, follow.partner.puller)
        follow.partner.puller_id = normalize_number(partner.puller_id, follow.partner.puller_id, { integer = true })
        follow.partner.puller_distance_only = normalize_boolean(partner.puller_distance_only, follow.partner.puller_distance_only)
    else
        follow.enabled = normalize_boolean(first_path(source, { path('domain_follow_enabled') }), follow.enabled)
        follow.party.enabled = normalize_boolean(first_path(source, { path('party_follow') }), follow.party.enabled)
        follow.party.leader_id = normalize_number(first_path(source, { path('party_follow_id') }), follow.party.leader_id, { integer = true })
        follow.party.leader_name = normalize_string(first_path(source, { path('party_follow_leader_name') }), follow.party.leader_name)
        follow.party.min = normalize_number(first_path(source, { path('party_follow_min') }), follow.party.min)
        follow.party.max = normalize_number(first_path(source, { path('party_follow_max') }), follow.party.max)
        follow.fight.leader = normalize_boolean(first_path(source, { path('fight_leader') }), follow.fight.leader)
        follow.fight.leader_id = normalize_number(first_path(source, { path('fight_leader_id') }), follow.fight.leader_id, { integer = true })
        follow.fight.min = normalize_number(first_path(source, { path('fight_follow_min') }), follow.fight.min)
        follow.fight.hold_s = normalize_number(first_path(source, { path('fight_follow_hold_s') }), follow.fight.hold_s)
        follow.partner.enabled = normalize_boolean(first_path(source, { path('partner') }), follow.partner.enabled)
        follow.partner.secondary_enabled = normalize_boolean(first_path(source, { path('partner2') }), follow.partner.secondary_enabled)
        follow.partner.ids = normalize_list(first_path(source, { path('partner_ids') }), follow.partner.ids)
        follow.partner.puller = normalize_boolean(first_path(source, { path('puller') }), follow.partner.puller)
        follow.partner.puller_id = normalize_number(first_path(source, { path('puller_id') }), follow.partner.puller_id, { integer = true })
        follow.partner.puller_distance_only = normalize_boolean(first_path(source, { path('puller_distance_only') }), follow.partner.puller_distance_only)
    end
end

local function normalize_targeting(source, config)
    local targeting = config.targeting
    local nested = get_path(source, { 'targeting' })
    if is_table(nested) and table_has_any(nested, { 'add_control', 'add_priority_names', 'legacy_slots', 'targets', 'targetability', 'ignore', 'target_ignore_names' }) then
        targeting.add_control = normalize_boolean(nested.add_control, targeting.add_control)
        targeting.add_priority_names = normalize_list(nested.add_priority_names, targeting.add_priority_names)
        targeting.legacy_slots = normalize_list(nested.legacy_slots, targeting.legacy_slots)
        targeting.targets = normalize_list(nested.targets, targeting.targets)
        local nested_targetability = is_table(nested.targetability) and nested.targetability or {}
        targeting.targetability.enabled = normalize_boolean(nested_targetability.enabled, targeting.targetability.enabled)
        targeting.targetability.action = normalize_string(nested_targetability.action, targeting.targetability.action)
        targeting.ignore = normalize_list(nested.ignore, targeting.ignore)
        targeting.target_ignore_names = normalize_list(nested.target_ignore_names, targeting.target_ignore_names)
    else
        targeting.add_control = normalize_boolean(first_path(source, { path('add_control') }), targeting.add_control)
        targeting.add_priority_names = normalize_list(first_path(source, { path('add_priority_names') }), targeting.add_priority_names)
        targeting.legacy_slots = normalize_list({
            first_path(source, { path('target1') }),
            first_path(source, { path('target2') }),
            first_path(source, { path('target3') }),
        }, targeting.legacy_slots)
        targeting.targets = normalize_list(first_path(source, { path('targets') }), targeting.targets)
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
    if is_table(nested) and table_has_any(nested, { 'enabled', 'order', 'legacy_primary' }) then
        sleep.enabled = normalize_boolean(nested.enabled, sleep.enabled)
        local order = nested.order
        if order == nil and nested.legacy_primary ~= nil then
            order = { nested.legacy_primary }
        end
        sleep.order = normalize_list(order, sleep.order)
        local legacy_primary = normalize_optional_string(nested.legacy_primary)
        if legacy_primary ~= nil then
            sleep.legacy_primary = legacy_primary
        elseif #sleep.order > 0 then
            sleep.legacy_primary = normalize_string(sleep.order[1], sleep.legacy_primary)
        end
    else
        sleep.enabled = normalize_boolean(first_path(source, { path('sleep') }), sleep.enabled)
        local order = first_path(source, { path('sleepspells') })
        if order == nil then
            local legacy_primary = normalize_optional_string(first_path(source, { path('sleepspell') }))
            if legacy_primary ~= nil then
                order = { legacy_primary }
            end
        end
        sleep.order = normalize_list(order, sleep.order)
        local legacy_primary = normalize_optional_string(first_path(source, { path('sleepspell') }))
        if legacy_primary ~= nil then
            sleep.legacy_primary = legacy_primary
        elseif #sleep.order > 0 then
            sleep.legacy_primary = normalize_string(sleep.order[1], sleep.legacy_primary)
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
        maintenance.brd = normalize_list(nested.brd, maintenance.brd)
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
        maintenance.brd = normalize_list(first_path(source, { path('maintenance_brd') }), maintenance.brd)
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
    if is_table(nested) and table_has_any(nested, { 'domain_combat_enabled', 'domain_defensive_enabled', 'domain_movement_enabled', 'domain_maintenance_enabled', 'domain_follow_enabled', 'scheduler_dark_launch_combat', 'scheduler_dark_launch_defensive', 'scheduler_dark_launch_movement', 'scheduler_dark_launch_maintenance' }) then
        ownership.domain_combat_enabled = normalize_boolean(nested.domain_combat_enabled, ownership.domain_combat_enabled)
        ownership.domain_defensive_enabled = normalize_boolean(nested.domain_defensive_enabled, ownership.domain_defensive_enabled)
        ownership.domain_movement_enabled = normalize_boolean(nested.domain_movement_enabled, ownership.domain_movement_enabled)
        ownership.domain_maintenance_enabled = normalize_boolean(nested.domain_maintenance_enabled, ownership.domain_maintenance_enabled)
        ownership.domain_follow_enabled = normalize_boolean(nested.domain_follow_enabled, ownership.domain_follow_enabled)
        ownership.scheduler_dark_launch_combat = normalize_boolean(nested.scheduler_dark_launch_combat, ownership.scheduler_dark_launch_combat)
        ownership.scheduler_dark_launch_defensive = normalize_boolean(nested.scheduler_dark_launch_defensive, ownership.scheduler_dark_launch_defensive)
        ownership.scheduler_dark_launch_movement = normalize_boolean(nested.scheduler_dark_launch_movement, ownership.scheduler_dark_launch_movement)
        ownership.scheduler_dark_launch_maintenance = normalize_boolean(nested.scheduler_dark_launch_maintenance, ownership.scheduler_dark_launch_maintenance)
    else
        ownership.domain_combat_enabled = normalize_boolean(first_path(source, { path('domain_combat_enabled') }), ownership.domain_combat_enabled)
        ownership.domain_defensive_enabled = normalize_boolean(first_path(source, { path('domain_defensive_enabled') }), ownership.domain_defensive_enabled)
        ownership.domain_movement_enabled = normalize_boolean(first_path(source, { path('domain_movement_enabled') }), ownership.domain_movement_enabled)
        ownership.domain_maintenance_enabled = normalize_boolean(first_path(source, { path('domain_maintenance_enabled') }), ownership.domain_maintenance_enabled)
        ownership.domain_follow_enabled = normalize_boolean(first_path(source, { path('domain_follow_enabled') }), ownership.domain_follow_enabled)
        ownership.scheduler_dark_launch_combat = normalize_boolean(first_path(source, { path('scheduler_dark_launch_combat') }), ownership.scheduler_dark_launch_combat)
        ownership.scheduler_dark_launch_defensive = normalize_boolean(first_path(source, { path('scheduler_dark_launch_defensive') }), ownership.scheduler_dark_launch_defensive)
        ownership.scheduler_dark_launch_movement = normalize_boolean(first_path(source, { path('scheduler_dark_launch_movement') }), ownership.scheduler_dark_launch_movement)
        ownership.scheduler_dark_launch_maintenance = normalize_boolean(first_path(source, { path('scheduler_dark_launch_maintenance') }), ownership.scheduler_dark_launch_maintenance)
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
    normalize_tank(source, config)
    normalize_sleep(source, config)
    normalize_spells(source, config)
    normalize_maintenance(source, config)
    normalize_debug(source, config)
    normalize_ownership(source, config)
    normalize_legacy(source, config)

    return config
end

function M.version()
    return CURRENT_CANONICAL_CONFIG_VERSION
end

return M
