package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    assert_equal(value, true, message)
end

local function assert_false(value, message)
    assert_equal(value, false, message)
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then
        error(message or ('missing expected text: ' .. tostring(needle)))
    end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then
        error(message or ('unexpected text: ' .. tostring(needle)))
    end
end

local function read_all(path)
    local fh = assert(io.open(path, 'rb'))
    local source = fh:read('*a')
    fh:close()
    return source
end

local path_config = require('uc_path_config')
local profile_v2 = require('uc_profile_v2')

local canonical = {
    legacy = { hunter = true },
    movement = {
        path = {
            recording = true,
            follow_enabled = true,
            party_gate_yalms = 4.5,
            resume_index_window = 9,
            hunter_targets = { 'Canon Mob', 'Canon Add' },
            hunter_max_z_delta = 3.5,
            hunter_max_target_range = 27.0,
            hunter_claim_timeout_s = 6.0,
            hunter_ignore_cooldown_s = 31.0,
            pull_action_type = 'spell',
            pull_action_name = 'Dia II',
            pull_attack_fallback_enabled = true,
        },
    },
}

local function contradictory_flat()
    return {
        hunter = false,
        path_recording = false,
        path_follow_enabled = false,
        path_file_name = 'runtime_route.lua',
        path_route_type = 'patrol',
        path_distance_to_start = 12.5,
        path_points = { { x = 1, y = 2, z = 3 } },
        path_party_gate_yalms = 99,
        path_resume_index_window = 99,
        path_hunter_targets = { 'Flat Mob' },
        path_hunter_max_z_delta = 19,
        path_hunter_max_target_range = 79,
        path_hunter_claim_timeout_s = 99,
        path_hunter_ignore_cooldown_s = 99,
        path_pull_action_type = 'ja',
        path_pull_action_name = 'Provoke',
        path_pull_attack_fallback_enabled = false,
    }
end

local function test_canonical_on_beats_flat_off()
    local view = contradictory_flat()
    local runtime_points = view.path_points
    path_config.apply_runtime_view(view, canonical)

    assert_true(view.hunter, 'canonical hunter ON must beat flat OFF')
    assert_true(view.path_recording, 'canonical recording ON must beat flat OFF')
    assert_true(view.path_follow_enabled, 'canonical path follow ON must beat flat OFF')
    assert_equal(view.path_party_gate_yalms, 4.5, 'canonical party gate')
    assert_equal(view.path_resume_index_window, 9, 'canonical resume window')
    assert_equal(view.path_hunter_targets[1], 'Canon Mob', 'canonical hunter targets')
    assert_equal(view.path_hunter_targets[2], 'Canon Add', 'canonical hunter target order')
    assert_true(view.path_hunter_targets ~= canonical.movement.path.hunter_targets,
        'runtime hunter target projection must clone canonical list')
    assert_equal(view.path_hunter_max_z_delta, 3.5, 'canonical hunter max z')
    assert_equal(view.path_hunter_max_target_range, 27.0, 'canonical hunter max range')
    assert_equal(view.path_hunter_claim_timeout_s, 6.0, 'canonical hunter claim timeout')
    assert_equal(view.path_hunter_ignore_cooldown_s, 31.0, 'canonical hunter ignore cooldown')
    assert_equal(view.path_pull_action_type, 'spell', 'canonical pull action type')
    assert_equal(view.path_pull_action_name, 'Dia II', 'canonical pull action name')
    assert_true(view.path_pull_attack_fallback_enabled, 'canonical pull attack fallback')

    assert_equal(view.path_file_name, 'runtime_route.lua', 'runtime filename must survive canonical projection')
    assert_equal(view.path_route_type, 'patrol', 'runtime route classification must survive canonical projection')
    assert_equal(view.path_distance_to_start, 12.5, 'runtime distance must survive canonical projection')
    assert_true(view.path_points == runtime_points, 'runtime route points must remain runtime-owned')
end

local function test_canonical_off_beats_flat_on()
    local view = contradictory_flat()
    view.hunter = true
    view.path_recording = true
    view.path_follow_enabled = true
    view.path_pull_attack_fallback_enabled = true

    canonical.legacy.hunter = false
    canonical.movement.path.recording = false
    canonical.movement.path.follow_enabled = false
    canonical.movement.path.pull_attack_fallback_enabled = false

    path_config.apply_runtime_view(view, canonical)
    assert_false(view.hunter, 'canonical hunter OFF must beat flat ON')
    assert_false(view.path_recording, 'canonical recording OFF must beat flat ON')
    assert_false(view.path_follow_enabled, 'canonical path follow OFF must beat flat ON')
    assert_false(view.path_pull_attack_fallback_enabled, 'canonical pull fallback OFF must beat flat ON')

    canonical.legacy.hunter = true
    canonical.movement.path.recording = true
    canonical.movement.path.follow_enabled = true
    canonical.movement.path.pull_attack_fallback_enabled = true
end

local function test_missing_path_uses_canonical_defaults()
    local view = contradictory_flat()
    view.hunter = true
    view.path_recording = true
    view.path_follow_enabled = true
    view.path_pull_attack_fallback_enabled = true

    path_config.apply_runtime_view(view, { movement = {}, legacy = {} })

    assert_false(view.hunter, 'missing canonical hunter must default OFF rather than flat fallback')
    assert_false(view.path_recording, 'missing canonical recording must default OFF rather than flat fallback')
    assert_false(view.path_follow_enabled, 'missing canonical follow must default OFF rather than flat fallback')
    assert_equal(view.path_party_gate_yalms, 3.0, 'missing canonical gate default')
    assert_equal(view.path_resume_index_window, 12, 'missing canonical resume default')
    assert_equal(#view.path_hunter_targets, 0, 'missing canonical hunter list default')
    assert_equal(view.path_pull_action_type, 'ja', 'missing canonical pull type default')
    assert_equal(view.path_pull_action_name, '', 'missing canonical pull name default')
    assert_false(view.path_pull_attack_fallback_enabled, 'missing canonical pull fallback default')
    assert_equal(view.path_file_name, 'runtime_route.lua', 'canonical defaults must not erase runtime filename')
end

local function test_route_session_state_is_not_durable_authority()
    local current = {
        movement = {
            path = {
                follow_enabled = true,
                file_name = 'runtime-a.lua',
                route_type = 'patrol',
                distance_to_start = 12,
                points = { 'runtime-a' },
                party_gate_yalms = 3,
            },
        },
    }
    local target = {
        movement = {
            path = {
                follow_enabled = true,
                file_name = 'profile-b.lua',
                route_type = 'loop',
                distance_to_start = 99,
                points = { 'profile-b' },
                party_gate_yalms = 3,
            },
        },
    }

    local runtime_only_diff = profile_v2.diff_durable_config(current, target)
    assert_equal(runtime_only_diff.count, 0,
        'route filename/type/distance/points must not participate in durable authority diff')

    target.movement.path.party_gate_yalms = 4
    local policy_diff = profile_v2.diff_durable_config(current, target)
    assert_true(policy_diff.count > 0,
        'durable path policy must still participate in Profile V2 diff')
end

local function test_static_wiring()
    local pathing = read_all('uc_pathing.lua')
    local core = read_all('unified_combat_core.lua')
    local target_provider = read_all('uc_provider_target_control.lua')
    local combat_provider = read_all('uc_provider_combat.lua')
    local active_config = read_all('uc_active_config.lua')
    local profile_v2 = read_all('uc_profile_v2.lua')

    assert_contains(pathing, "local uc_path_config = require('uc_path_config')",
        'pathing must require canonical path adapter')
    assert_not_contains(pathing, 'active_value_or_flat(',
        'pathing must burn down all active-value-or-flat readers')
    assert_contains(pathing, 'uc_path_config.recording_enabled(active_path_config())',
        'recording gate must be canonical')
    assert_contains(pathing, 'uc_path_config.follow_enabled(active_path_config())',
        'path follow gate must be canonical')
    assert_contains(pathing, 'settings and settings.path_file_name',
        'path filename must remain live runtime state')
    assert_contains(pathing, 'settings and settings.path_route_type',
        'route classification must remain live runtime state')

    assert_contains(core, "require('uc_path_config').apply_runtime_view(view, config)",
        'scheduler target view must overlay canonical path/hunter policy')
    assert_contains(core, 'function core.select_pull_for_scheduler(settings, config)',
        'scheduler pull selector must accept canonical config')
    assert_contains(target_provider, 'select_pull(ctx.settings, ctx.config)',
        'target-control pull provider must pass canonical config')
    assert_contains(combat_provider, 'select_pull(ctx.settings, ctx.config)',
        'combat engage provider must pass canonical config')

    assert_not_contains(active_config, 'candidate.path_file_name = config.movement.path.file_name',
        'canonical projection must not overwrite runtime path filename')
    assert_not_contains(active_config, 'candidate.path_points = clone_value(config.movement.path.points)',
        'canonical projection must not overwrite runtime path points')
    assert_contains(profile_v2, 'config.movement.path.route_type = nil',
        'durable Profile V2 comparison must ignore runtime route type')
    assert_contains(profile_v2, 'config.movement.path.points = nil',
        'durable Profile V2 comparison must ignore runtime route points')
end

test_canonical_on_beats_flat_off()
test_canonical_off_beats_flat_on()
test_missing_path_uses_canonical_defaults()
test_route_session_state_is_not_durable_authority()
test_static_wiring()

io.stdout:write('selftest_phase3_pathing_authority: OK (route + hunter + pull policy)\n')
