local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    if not value then
        error(message or 'assert_true failed')
    end
end

local function deep_clone(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for key, inner in pairs(value) do
        out[key] = deep_clone(inner)
    end
    return out
end

local function deep_equal(actual, expected, seen)
    if actual == expected then
        return true
    end
    if type(actual) ~= type(expected) then
        return false
    end
    if type(actual) ~= 'table' then
        return actual == expected
    end

    seen = seen or {}
    seen[actual] = seen[actual] or {}
    if seen[actual][expected] then
        return true
    end
    seen[actual][expected] = true

    for key, value in pairs(actual) do
        if not deep_equal(value, expected[key], seen) then
            return false
        end
    end
    for key in pairs(expected) do
        if actual[key] == nil then
            return false
        end
    end
    return true
end

local function assert_deep_equal(actual, expected, message)
    if not deep_equal(actual, expected) then
        error(message or 'assert_deep_equal failed')
    end
end

local function set_active_profile(active_config, config)
    local ok, err = active_config.set_active_profile({
        version = 2,
        profile = {
            schema_version = 2,
            engine = 'UC',
            source = 'selftest',
        },
        config = config or {},
    })
    if ok ~= true then
        error('failed to set active profile: ' .. tostring(err))
    end
end

local function main()
    local previous_windower = rawget(_G, 'windower')
    local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
    local previous_settings = rawget(_G, 'UC_SETTINGS')

    package.loaded['uc_active_config'] = nil
    package.loaded['uc_config_normalizer'] = nil
    package.loaded['uc_runtime_overrides'] = nil

    rawset(_G, 'windower', {
        addon_path = './',
        ffxi = {
            get_player = function()
                return {
                    name = 'Tester',
                    main_job = 'BRD',
                    sub_job = 'WHM',
                }
            end,
        },
    })

    local active_config = require('uc_active_config')
    local runtime_overrides = require('uc_runtime_overrides')

    set_active_profile(active_config, {
        follow = {
            fight = {
                leader = false,
                leader_id = 22,
            },
        },
        targeting = {
            targets = { 'Active Bat', 'Active Beetle' },
        },
        sleep = {
            enabled = false,
            order = { 'Sleep II', 'Sleep' },
            legacy_primary = 'Sleep II',
        },
    })

    local active_snapshot = deep_clone(active_config.get_active_profile())
    local flat_override = {
        fight_leader = true,
        fight_leader_id = 77,
        add_priority_names = { 'Override A', 'Override B', 'Override A' },
        sleep = true,
        sleepspells = { 'Horde Lullaby II', 'Sleep II', 'Horde Lullaby II' },
        sleepspell = 'Repose',
    }

    assert_equal(runtime_overrides.fight_leader_enabled(flat_override), false, 'fight leader canonical durable value must beat conflicting flat override')
    assert_equal(runtime_overrides.fight_leader_id(flat_override), 22, 'fight leader canonical identity must beat conflicting flat override')
    assert_equal(runtime_overrides.add_priority_names(flat_override)[1], 'Active Bat', 'canonical priority must override stale flat list')
    assert_equal(runtime_overrides.add_priority_names(flat_override)[2], 'Active Beetle', 'canonical priority must preserve order')
    assert_equal(#runtime_overrides.add_priority_names(flat_override), 2, 'canonical priority count')
    assert_equal(runtime_overrides.sleep_enabled(flat_override), false, 'canonical disabled Sleep must override flat enabled')
    assert_equal(runtime_overrides.sleep_spell_names(flat_override)[1], 'Sleep II', 'canonical Sleep order must override flat list')
    assert_equal(runtime_overrides.sleep_spell_names(flat_override)[2], 'Sleep', 'canonical Sleep order preserved')
    assert_equal(#runtime_overrides.sleep_spell_names(flat_override), 2, 'canonical Sleep list count')

    local active_only = {}
    assert_equal(runtime_overrides.fight_leader_enabled(active_only), false, 'fight leader should fall back to active durable value when flat key missing')
    assert_equal(runtime_overrides.fight_leader_id(active_only), 22, 'fight leader id should fall back to active durable value when flat key missing')
    assert_equal(runtime_overrides.add_priority_names(active_only)[1], 'Active Bat', 'add priority should fall back to active durable list when flat key missing')
    assert_equal(runtime_overrides.sleep_enabled(active_only), false, 'sleep should fall back to active durable value when flat key missing')
    assert_equal(runtime_overrides.sleep_spell_names(active_only)[1], 'Sleep II', 'sleep spell list should fall back to active durable order when flat key missing')

    rawset(_G, 'UC_SETTINGS', {
        fight_leader = true,
        fight_leader_id = 101,
        add_priority_names = { 'Global Value' },
        sleep = true,
        sleepspell = 'Repose',
    })
    assert_equal(runtime_overrides.fight_leader_id(), 22, 'active canonical fight leader identity must beat global flat settings')
    assert_equal(runtime_overrides.add_priority_names()[1], 'Active Bat', 'canonical priority must beat global flat state')
    assert_equal(runtime_overrides.sleep_spell_names()[1], 'Sleep II', 'canonical Sleep must beat global flat state')

    -- Explicit canonical empty lists must not resurrect stale flat entries.
    local config = active_config.get_config()
    config.targeting.targets = {}
    config.sleep.order = {}
    config.sleep.legacy_primary = ''
    assert_equal(#runtime_overrides.add_priority_names(flat_override), 0, 'empty canonical target list must stay empty')
    assert_equal(#runtime_overrides.sleep_spell_names(flat_override), 0, 'empty canonical Sleep list must stay empty')
    config.targeting.targets = { 'Active Bat', 'Active Beetle' }
    config.sleep.order = { 'Sleep II', 'Sleep' }
    config.sleep.legacy_primary = 'Sleep II'
    -- Legacy fallback remains only when the corresponding canonical domain is absent.
    config.targeting = nil
    config.sleep = nil
    assert_equal(runtime_overrides.add_priority_names(flat_override)[1], 'Override A', 'pre-profile targeting fallback')
    assert_equal(runtime_overrides.sleep_spell_names(flat_override)[1], 'Horde Lullaby II', 'pre-profile Sleep fallback')
    assert_equal(runtime_overrides.sleep_enabled(flat_override), true, 'pre-profile Sleep enabled fallback')
    config.targeting = { targets = { 'Active Bat', 'Active Beetle' } }
    config.sleep = { enabled = false, order = { 'Sleep II', 'Sleep' }, legacy_primary = 'Sleep II' }

    assert_deep_equal(active_config.get_active_profile(), active_snapshot, 'runtime override reads must not mutate UC_ACTIVE_PROFILE')

    rawset(_G, 'windower', previous_windower)
    rawset(_G, 'UC_ACTIVE_PROFILE', previous_active_profile)
    rawset(_G, 'UC_SETTINGS', previous_settings)
    package.loaded['uc_runtime_overrides'] = nil
    package.loaded['uc_active_config'] = nil
    package.loaded['uc_config_normalizer'] = nil

    io.stdout:write('selftest_runtime_overrides: OK\n')
end

main()
