local M = {}

local defaults = {
    recording = false,
    follow_enabled = false,
    party_gate_yalms = 3.0,
    resume_index_window = 12,
    hunter_targets = {},
    hunter_max_z_delta = 2.0,
    hunter_max_target_range = 20.0,
    hunter_claim_timeout_s = 4.0,
    hunter_ignore_cooldown_s = 20.0,
    pull_action_type = 'ja',
    pull_action_name = '',
    pull_attack_fallback_enabled = false,
}

local function clone_list(values)
    local out = {}
    if type(values) ~= 'table' then return out end
    for i = 1, #values do out[i] = values[i] end
    return out
end

local function path_config(config)
    local movement = type(config) == 'table' and config.movement or nil
    local path = type(movement) == 'table' and movement.path or nil
    return type(path) == 'table' and path or nil
end

local function value(config, key)
    local path = path_config(config)
    local current = type(path) == 'table' and path[key] or nil
    if current == nil then return defaults[key] end
    return current
end

function M.from_config(config)
    return path_config(config)
end

function M.recording_enabled(config)
    return value(config, 'recording') == true
end

function M.follow_enabled(config)
    return value(config, 'follow_enabled') == true
end

function M.party_gate_yalms(config)
    return tonumber(value(config, 'party_gate_yalms')) or defaults.party_gate_yalms
end

function M.resume_index_window(config)
    return tonumber(value(config, 'resume_index_window')) or defaults.resume_index_window
end

function M.hunter_enabled(config)
    local legacy = type(config) == 'table' and config.legacy or nil
    if type(legacy) ~= 'table' or legacy.hunter == nil then return false end
    return legacy.hunter == true
end

function M.hunter_targets(config)
    return clone_list(value(config, 'hunter_targets'))
end

function M.hunter_max_z_delta(config)
    return tonumber(value(config, 'hunter_max_z_delta')) or defaults.hunter_max_z_delta
end

function M.hunter_max_target_range(config)
    return tonumber(value(config, 'hunter_max_target_range')) or defaults.hunter_max_target_range
end

function M.hunter_claim_timeout_s(config)
    return tonumber(value(config, 'hunter_claim_timeout_s')) or defaults.hunter_claim_timeout_s
end

function M.hunter_ignore_cooldown_s(config)
    return tonumber(value(config, 'hunter_ignore_cooldown_s')) or defaults.hunter_ignore_cooldown_s
end

function M.pull_action_type(config)
    local action_type = tostring(value(config, 'pull_action_type') or 'ja'):lower()
    if action_type ~= 'spell' then return 'ja' end
    return 'spell'
end

function M.pull_action_name(config)
    return tostring(value(config, 'pull_action_name') or '')
end

function M.pull_attack_fallback_enabled(config)
    return value(config, 'pull_attack_fallback_enabled') == true
end

function M.apply_runtime_view(view, config)
    if type(view) ~= 'table' then error('path runtime view requires a table') end
    if type(config) ~= 'table' then return view end

    view.hunter = M.hunter_enabled(config)
    view.path_recording = M.recording_enabled(config)
    view.path_follow_enabled = M.follow_enabled(config)
    view.path_party_gate_yalms = M.party_gate_yalms(config)
    view.path_resume_index_window = M.resume_index_window(config)
    view.path_hunter_targets = M.hunter_targets(config)
    view.path_hunter_max_z_delta = M.hunter_max_z_delta(config)
    view.path_hunter_max_target_range = M.hunter_max_target_range(config)
    view.path_hunter_claim_timeout_s = M.hunter_claim_timeout_s(config)
    view.path_hunter_ignore_cooldown_s = M.hunter_ignore_cooldown_s(config)
    view.path_pull_action_type = M.pull_action_type(config)
    view.path_pull_action_name = M.pull_action_name(config)
    view.path_pull_attack_fallback_enabled = M.pull_attack_fallback_enabled(config)

    -- Route identity/progress stays in live runtime state:
    -- path_file_name, path_route_type, path_distance_to_start, path_points.
    return view
end

return M
