local M = {}
local uc_smn_config = require('uc_smn_config')

local CURRENT_PROFILE_SCHEMA_VERSION = 1
local CURRENT_STATUS_SCHEMA_VERSION = 1

local OWNERSHIP_BY_FIELD = {
    -- command-owned runtime controls
    engine_enabled = "command_owned",
    start_engine = "command_owned",
    stop_engine = "command_owned",
    reload_profile = "command_owned",
    profile_switch = "command_owned",

    -- status output owned by addon
    active_profile_name = "status_output_owned_by_addon",
    current_active_profile_name = "status_output_owned_by_addon",
    current_profile_name = "status_output_owned_by_addon",
    profile_name = "status_output_owned_by_addon",
    profile_key = "status_output_owned_by_addon",
    character = "status_output_owned_by_addon",
    main_job = "status_output_owned_by_addon",
    sub_job = "status_output_owned_by_addon",
    job = "status_output_owned_by_addon",

    -- runtime owned by addon
    scheduler_action_state = "runtime_owned_by_addon",
    action_state = "runtime_owned_by_addon",
    pending_state = "runtime_owned_by_addon",
    pending_lock_state = "runtime_owned_by_addon",
    lock_state = "runtime_owned_by_addon",
    current_selected_action = "runtime_owned_by_addon",
    selected_action = "runtime_owned_by_addon",
    overlay_state = "runtime_owned_by_addon",
    current_intent = "runtime_owned_by_addon",
    intent = "runtime_owned_by_addon",
    runtime_state = "runtime_owned_by_addon",

    -- legacy / ambiguous
    local_ownership_flags = "legacy_or_ambiguous",
    local_ownership_flag = "legacy_or_ambiguous",
    ownership_flags = "legacy_or_ambiguous",
}

local PREFIX_CLASSIFICATION = {
    defensive_ = "profile_owned_by_ui",
    domain_ = "profile_owned_by_ui",
    encounter_ = "profile_owned_by_ui",
    cor_ = "profile_owned_by_ui",
    path_ = "profile_owned_by_ui",
    target_ = "profile_owned_by_ui",
    reaction_ = "profile_owned_by_ui",
    party_follow_ = "profile_owned_by_ui",
    fight_follow_ = "profile_owned_by_ui",
    spacing_ = "profile_owned_by_ui",
    add_ = "profile_owned_by_ui",
    log_ = "profile_owned_by_ui",
    sleep = "profile_owned_by_ui",
}

local DIRECT_PROFILE_FIELDS = {
    ability1 = "profile_owned_by_ui",
    ability2 = "profile_owned_by_ui",
    ability3 = "profile_owned_by_ui",
    ability4 = "profile_owned_by_ui",
    ability5 = "profile_owned_by_ui",
    ability6 = "profile_owned_by_ui",
    ability_active = "profile_owned_by_ui",
    abilities = "profile_owned_by_ui",
    wsabilities = "profile_owned_by_ui",
    ws1 = "profile_owned_by_ui",
    weaponskill = "profile_owned_by_ui",
    weaponskill_active = "profile_owned_by_ui",
    ws_mode = "profile_owned_by_ui",
    weaponskill_min_tp = "profile_owned_by_ui",
    aftermath_enabled = "profile_owned_by_ui",
    aftermath_ws = "profile_owned_by_ui",
    engine_mode = "profile_owned_by_ui",
    show_ingame_ui = "profile_owned_by_ui",
    defensive_enabled = "profile_owned_by_ui",
    defensive_provider = "profile_owned_by_ui",
    defensive_cure_enabled = "profile_owned_by_ui",
    defensive_doom_water = "profile_owned_by_ui",
    def_remove_enemy_buffs = "profile_owned_by_ui",
    defensive_na_enabled = "profile_owned_by_ui",
    defensive_buff_enabled = "profile_owned_by_ui",
    defensive_critical_hpp = "profile_owned_by_ui",
    defensive_medium_hpp = "profile_owned_by_ui",
    defensive_overwrite_enabled = "profile_owned_by_ui",
    defensive_overwrite_interval = "profile_owned_by_ui",
    defensive_buff_self_only = "profile_owned_by_ui",
    defensive_buffs = "profile_owned_by_ui",
    engine_enabled = "command_owned",
    domain_combat_enabled = "profile_owned_by_ui",
    domain_defensive_enabled = "profile_owned_by_ui",
    domain_movement_enabled = "profile_owned_by_ui",
    domain_maintenance_enabled = "profile_owned_by_ui",
    domain_follow_enabled = "profile_owned_by_ui",
    profile_v2_autoload = "profile_owned_by_ui",
    profile_v2_auto_reload_on_change = "profile_owned_by_ui",
    path_recording = "profile_owned_by_ui",
    path_follow_enabled = "profile_owned_by_ui",
    path_file_name = "profile_owned_by_ui",
    path_route_type = "profile_owned_by_ui",
    path_distance_to_start = "profile_owned_by_ui",
    path_points = "profile_owned_by_ui",
    path_party_gate_yalms = "profile_owned_by_ui",
    path_resume_index_window = "profile_owned_by_ui",
    path_hunter_targets = "profile_owned_by_ui",
    path_hunter_max_z_delta = "profile_owned_by_ui",
    path_hunter_max_target_range = "profile_owned_by_ui",
    path_hunter_claim_timeout_s = "profile_owned_by_ui",
    path_hunter_ignore_cooldown_s = "profile_owned_by_ui",
    path_pull_action_type = "profile_owned_by_ui",
    path_pull_action_name = "profile_owned_by_ui",
    autotarget = "profile_owned_by_ui",
    spam = "profile_owned_by_ui",
    closer = "profile_owned_by_ui",
    manual = "profile_owned_by_ui",
    prime = "profile_owned_by_ui",
    static = "profile_owned_by_ui",
    spacing = "profile_owned_by_ui",
    face = "profile_owned_by_ui",
    spacing_band_min = "profile_owned_by_ui",
    spacing_band_max = "profile_owned_by_ui",
    spacing_use_prediction = "profile_owned_by_ui",
    spacing_lookahead_s = "profile_owned_by_ui",
    spacing_model_size_floor = "profile_owned_by_ui",
    spacing_repel_hold_ticks = "profile_owned_by_ui",
    spacing_overlap_deadband = "profile_owned_by_ui",
    spacing_repel_weight = "profile_owned_by_ui",
    spacing_band_deadband = "profile_owned_by_ui",
    partner = "profile_owned_by_ui",
    partner2 = "profile_owned_by_ui",
    puller = "profile_owned_by_ui",
    puller_name = "profile_owned_by_ui",
	puller_leash_source = "profile_owned_by_ui",
    puller_engage_range = "profile_owned_by_ui",
    fight_leader_selected = "profile_owned_by_ui",
    puller_distance_only = "profile_owned_by_ui",
    partner_id = "profile_owned_by_ui",
    partner_id2 = "profile_owned_by_ui",
    partner_ids = "profile_owned_by_ui",
    puller_id = "runtime_owned_by_addon",
    fight_leader = "profile_owned_by_ui",
    fight_leader_name = "profile_owned_by_ui",
    fight_leader_id = "runtime_owned_by_addon",
    party_follow = "profile_owned_by_ui",
    party_follow_id = "profile_owned_by_ui",
    party_follow_leader_name = "profile_owned_by_ui",
    party_follow_min = "profile_owned_by_ui",
    party_follow_max = "profile_owned_by_ui",
    fight_follow_min = "profile_owned_by_ui",
    fight_follow_hold_s = "profile_owned_by_ui",
	nyzul_coordinator_name = "profile_owned_by_ui",
	nyzul_anchor_name = "profile_owned_by_ui",
	nyzul_parking_order = "profile_owned_by_ui",
    add_control = "profile_owned_by_ui",
    add_priority_names = "profile_owned_by_ui",
    sub = "profile_owned_by_ui",
    sub2 = "profile_owned_by_ui",
    move = "profile_owned_by_ui",
    formation_enabled = "profile_owned_by_ui",
    formation_encounter = "profile_owned_by_ui",
    formation_mock_enabled = "profile_owned_by_ui",
    formation_mock_mob_name = "profile_owned_by_ui",
    formation_role = "profile_owned_by_ui",
    formation_tank_name = "profile_owned_by_ui",
    formation_required_party_names = "profile_owned_by_ui",
    formation_capture_stable_s = "profile_owned_by_ui",
    formation_capture_tolerance = "profile_owned_by_ui",
    formation_safe_radius = "profile_owned_by_ui",
    formation_tank_accept_radius = "profile_owned_by_ui",
    formation_tank_return_radius = "profile_owned_by_ui",
    formation_dps_flank_angle_deg = "profile_owned_by_ui",
    formation_dps_melee_radius = "profile_owned_by_ui",
    formation_dps_position_tolerance = "profile_owned_by_ui",
    formation_healer_preferred_radius = "profile_owned_by_ui",
    formation_healer_minimum_boss_distance = "profile_owned_by_ui",
    formation_healer_maximum_party_range = "profile_owned_by_ui",
    formation_healer_cone_half_angle_deg = "profile_owned_by_ui",
    formation_healer_cone_safety_margin_deg = "profile_owned_by_ui",
    formation_healer_sample_step_deg = "profile_owned_by_ui",
    formation_placement_mode = "profile_owned_by_ui",
    formation_anchor = "profile_owned_by_ui",
    formation_anchor_member = "profile_owned_by_ui",
    formation_axis_type = "profile_owned_by_ui",
    formation_axis_member = "profile_owned_by_ui",
    formation_preferred_radius = "profile_owned_by_ui",
    formation_minimum_radius = "profile_owned_by_ui",
    formation_maximum_radius = "profile_owned_by_ui",
    formation_preferred_angle_deg = "profile_owned_by_ui",
    formation_allowed_angle_half_width_deg = "profile_owned_by_ui",
    formation_radius_step = "profile_owned_by_ui",
    formation_angle_step_deg = "profile_owned_by_ui",
    formation_hysteresis_start_distance = "profile_owned_by_ui",
    formation_hysteresis_stop_distance = "profile_owned_by_ui",
    formation_avoid_encounter_hazards = "profile_owned_by_ui",
    formation_hazard_margin = "profile_owned_by_ui",
    formation_safe_origin_radius = "profile_owned_by_ui",
    formation_minimum_boss_distance = "profile_owned_by_ui",
    formation_maximum_boss_distance = "profile_owned_by_ui",
    formation_maximum_party_range = "profile_owned_by_ui",
    named_formations_enabled = "profile_owned_by_ui",
    named_formation_entries = "profile_owned_by_ui",
    debug = "profile_owned_by_ui",
    log_combat_sched = "profile_owned_by_ui",
    log_ja_sched = "profile_owned_by_ui",
    log_ja_debug = "profile_owned_by_ui",
    log_def_sched = "profile_owned_by_ui",
    log_tank_sched = "profile_owned_by_ui",
    solo = "profile_owned_by_ui",
    aeonic = "profile_owned_by_ui",
    color = "profile_owned_by_ui",
    tank = "profile_owned_by_ui",
    sleep = "profile_owned_by_ui",
    command = "profile_owned_by_ui",
    hunter = "profile_owned_by_ui",
    tank_enmity_actions = "profile_owned_by_ui",
    target1 = "profile_owned_by_ui",
    target2 = "profile_owned_by_ui",
    target3 = "profile_owned_by_ui",
    targets = "profile_owned_by_ui",
    targetability = "profile_owned_by_ui",
    targetability_active = "profile_owned_by_ui",
    spell = "profile_owned_by_ui",
    spell_active = "profile_owned_by_ui",
    sleepspell = "profile_owned_by_ui",
    sleepspells = "profile_owned_by_ui",
    sleep_max_target_range = "profile_owned_by_ui",
    dd2_spell_slots = "profile_owned_by_ui",
    wait_ignore_names = "profile_owned_by_ui",
    ignore = "profile_owned_by_ui",
    target_ignore_names = "profile_owned_by_ui",
    reaction_enabled = "profile_owned_by_ui",
    reaction_rules = "profile_owned_by_ui",
}

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:match("^%s*(.-)%s*$") or "")
end

local function lower_key(field_name)
    return trim(field_name):lower()
end

local function add_error(errors, path, message)
    errors[#errors + 1] = {
        path = path or "",
        message = message or "invalid value",
    }
end

local function shallow_clone(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, inner_value in pairs(value) do
        out[key] = inner_value
    end
    return out
end

local function validate_structure(value, path, errors, seen)
    local value_type = type(value)
    if value_type ~= "table" then
        if value_type == "function" or value_type == "userdata" or value_type == "thread" then
            add_error(errors, path, "unsupported value type: " .. value_type)
            return false
        end
        return true
    end

    if seen[value] then
        add_error(errors, path, "cycle detected")
        return false
    end
    seen[value] = true

    local ok = true
    for key, inner_value in pairs(value) do
        local key_type = type(key)
        if key_type ~= "string" and key_type ~= "number" then
            add_error(errors, path, "unsupported key type: " .. key_type)
            ok = false
        end

        local inner_type = type(inner_value)
        local child_path = path .. "." .. tostring(key)
        if inner_type == "table" then
            if not validate_structure(inner_value, child_path, errors, seen) then
                ok = false
            end
        elseif inner_type == "function" or inner_type == "userdata" or inner_type == "thread" then
            add_error(errors, child_path, "unsupported value type: " .. inner_type)
            ok = false
        end
    end

    seen[value] = nil
    return ok
end

local function normalize_list(value)
    if type(value) ~= "table" then
        return {}
    end
    local out = {}
    for i, entry in ipairs(value) do
        out[i] = entry
    end
    return out
end

local function compose_profile_key(character, main_job, sub_job)
    local pieces = {}
    local character_name = trim(character)
    local main = trim(main_job):upper()
    local sub = trim(sub_job):upper()
    if character_name ~= "" then
        pieces[#pieces + 1] = character_name
    end
    if main ~= "" then
        pieces[#pieces + 1] = main
    end
    if sub ~= "" then
        pieces[#pieces + 1] = sub
    end
    return table.concat(pieces, "|")
end

function M.classify_profile_field(field_name)
    local key = lower_key(field_name)
    if key == "" then
        return "legacy_or_ambiguous"
    end

    local ownership = OWNERSHIP_BY_FIELD[key]
    if ownership then
        return ownership
    end

    local direct = DIRECT_PROFILE_FIELDS[key]
    if direct then
        return direct
    end

    for prefix, classification in pairs(PREFIX_CLASSIFICATION) do
        if key:sub(1, #prefix) == prefix then
            return classification
        end
    end

    if key:find("profile", 1, true) then
        return "status_output_owned_by_addon"
    end
    if key:find("state", 1, true) or key:find("lock", 1, true) or key:find("pending", 1, true) or key:find("overlay", 1, true) then
        return "runtime_owned_by_addon"
    end

    return "legacy_or_ambiguous"
end

function M.validate_uc_profile_table(profile_table)
    local errors = {}
    local warnings = {}

    if type(profile_table) ~= "table" then
        add_error(errors, "profile", "profile entry must be a table")
        return {
            ok = false,
            version = CURRENT_PROFILE_SCHEMA_VERSION,
            warnings = warnings,
            errors = errors,
        }
    end

    validate_structure(profile_table, "profile", errors, {})

    return {
        ok = #errors == 0,
        version = CURRENT_PROFILE_SCHEMA_VERSION,
        warnings = warnings,
        errors = errors,
    }
end

function M.validate_profile_tree(profile_tree)
    local errors = {}
    local warnings = {}

    if type(profile_tree) ~= "table" then
        add_error(errors, "profile_tree", "profile tree must be a table")
        return {
            ok = false,
            version = CURRENT_PROFILE_SCHEMA_VERSION,
            warnings = warnings,
            errors = errors,
        }
    end

    validate_structure(profile_tree, "profile_tree", errors, {})

    for branch_name, branch_value in pairs(profile_tree) do
        if type(branch_value) ~= "table" then
            add_error(errors, "profile_tree." .. tostring(branch_name), "profile branch must be a table")
        else
            for job_name, job_profile in pairs(branch_value) do
                local job_result = M.validate_uc_profile_table(job_profile)
                if not job_result.ok then
                    for _, entry in ipairs(job_result.errors) do
                        errors[#errors + 1] = {
                            path = "profile_tree." .. tostring(branch_name) .. "." .. tostring(job_name) .. "." .. entry.path,
                            message = entry.message,
                        }
                    end
                end
            end
        end
    end

    return {
        ok = #errors == 0,
        version = CURRENT_PROFILE_SCHEMA_VERSION,
        warnings = warnings,
        errors = errors,
    }
end

function M.validate_profile_payload(payload)
    local errors = {}
    local warnings = {}

    if type(payload) ~= "table" then
        add_error(errors, "payload", "payload must be a table")
        return {
            ok = false,
            version = CURRENT_PROFILE_SCHEMA_VERSION,
            warnings = warnings,
            errors = errors,
        }
    end

    local version = payload.version
    if version == nil then
        warnings[#warnings + 1] = "payload.version missing; defaulting to current version"
        version = CURRENT_PROFILE_SCHEMA_VERSION
    elseif type(version) ~= "number" or version % 1 ~= 0 then
        add_error(errors, "payload.version", "version must be an integer")
    elseif version > CURRENT_PROFILE_SCHEMA_VERSION then
        add_error(errors, "payload.version", "unsupported profile schema version: " .. tostring(version))
    elseif version < 1 then
        add_error(errors, "payload.version", "version must be positive")
    end

    local profiles = payload.profiles
    if type(profiles) ~= "table" then
        add_error(errors, "payload.profiles", "profiles must be a table")
        return {
            ok = false,
            version = version,
            warnings = warnings,
            errors = errors,
        }
    end

    local uc_profiles = profiles.UC
    if uc_profiles == nil then
        warnings[#warnings + 1] = "profiles.UC missing; current contract expects UC keyed job profiles"
    elseif type(uc_profiles) ~= "table" then
        add_error(errors, "payload.profiles.UC", "profiles.UC must be a table")
    else
        for job, job_profile in pairs(uc_profiles) do
            if type(job_profile) ~= "table" then
                add_error(errors, "payload.profiles.UC." .. tostring(job), "job profile entry must be a table")
            else
                local job_result = M.validate_uc_profile_table(job_profile)
                if not job_result.ok then
                    for _, entry in ipairs(job_result.errors) do
                        errors[#errors + 1] = {
                            path = "payload.profiles.UC." .. tostring(job) .. "." .. entry.path,
                            message = entry.message,
                        }
                    end
                end
            end
        end
    end

    return {
        ok = #errors == 0,
        version = version,
        warnings = warnings,
        errors = errors,
    }
end

function M.validate_structured_profile_config(payload)
    local errors = {}
    local warnings = {}

    if type(payload) ~= "table" then
        add_error(errors, "payload", "payload must be a table")
        return {
            ok = false,
            version = 2,
            warnings = warnings,
            errors = errors,
        }
    end

    validate_structure(payload, "payload", errors, {})

    local version = payload.version
    if version == nil then
        warnings[#warnings + 1] = "payload.version missing; treating as structured config candidate"
        version = 2
    elseif type(version) ~= "number" or version % 1 ~= 0 then
        add_error(errors, "payload.version", "version must be an integer")
    elseif version ~= 2 then
        add_error(errors, "payload.version", "structured profile config version must be 2")
    end

    local profile = payload.profile
    if type(profile) ~= "table" then
        add_error(errors, "payload.profile", "profile metadata must be a table")
    else
        if profile.schema_version ~= nil and (type(profile.schema_version) ~= "number" or profile.schema_version % 1 ~= 0) then
            add_error(errors, "payload.profile.schema_version", "schema_version must be an integer")
        end
        if profile.engine ~= nil and type(profile.engine) ~= "string" then
            add_error(errors, "payload.profile.engine", "engine must be a string")
        end
        if profile.character ~= nil and type(profile.character) ~= "string" then
            add_error(errors, "payload.profile.character", "character must be a string")
        end
        if profile.main_job ~= nil and type(profile.main_job) ~= "string" then
            add_error(errors, "payload.profile.main_job", "main_job must be a string")
        end
        if profile.sub_job ~= nil and type(profile.sub_job) ~= "string" then
            add_error(errors, "payload.profile.sub_job", "sub_job must be a string")
        end
    end

    local summoner_validation = uc_smn_config.validate(nil)
    if type(payload.config) ~= "table" then
        add_error(errors, "payload.config", "config must be a table")
    else
        summoner_validation = uc_smn_config.validate(payload.config.summoner)
        for _, issue in ipairs(summoner_validation.errors) do
            warnings[#warnings + 1] = issue.message
        end
        for _, issue in ipairs(summoner_validation.warnings) do
            warnings[#warnings + 1] = issue.message
        end
    end

    return {
        ok = #errors == 0,
        configuration_valid = #errors == 0 and summoner_validation.valid,
        summoner = summoner_validation,
        version = version,
        warnings = warnings,
        errors = errors,
    }
end

function M.build_status_contract_snapshot(input)
    input = type(input) == "table" and input or {}
    local character = input.character
    local main_job = input.main_job
    local sub_job = input.sub_job
    local profile_key = input.profile_key
    if profile_key == nil then
        profile_key = compose_profile_key(character, main_job, sub_job)
    end

    return {
        schema_version = CURRENT_STATUS_SCHEMA_VERSION,
        character = character,
        main_job = main_job,
        sub_job = sub_job,
        profile_key = profile_key,
        engine_state = shallow_clone(input.engine_state),
        zone_suspended = input.zone_suspended == true,
        scheduler_summary = shallow_clone(input.scheduler_summary),
        current_action = shallow_clone(input.current_action),
        warnings = normalize_list(input.warnings),
        errors = normalize_list(input.errors),
        updated_at = input.updated_at,
    }
end

return M
