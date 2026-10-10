local function read_file(path)
    local fh, err = io.open(path, 'r')
    if not fh then
        error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
    end
    local text = fh:read('*a')
    fh:close()
    return text
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or 'assert_true failed')
    end
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ('missing expected text: ' .. needle))
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ('unexpected text: ' .. needle))
    end
end

local function puller_gate_mock(input)
    local max_range = tonumber(input.max_range) or 6.0
    local dist = tonumber(input.mob_to_puller_distance) or 999
    if dist <= max_range then
        return true, 'PULLER_IN_RANGE'
    end
    if input.distance_only ~= true and (tonumber(input.mob_hpp) or 0) < 99 then
        return true, 'PULLER_HPP_BYPASS'
    end
    return false, 'PULLER_OUT_OF_RANGE'
end

local function main()
    package.loaded['uc_config_normalizer'] = nil
    package.loaded['uc_active_config'] = nil
    package.loaded['uc_profile_v2'] = nil
    local normalizer = require('uc_config_normalizer')
    local active_config = require('uc_active_config')
    local profile_v2 = require('uc_profile_v2')

    local normalized = normalizer.normalize({
        follow = {
            partner = {
                puller = true,
                engage_range = 9.5,
                puller_distance_only = true,
            },
        },
        sleep = {
            max_target_range = 14.0,
        },
    }, {
        character = 'RangeTest',
        main_job = 'BRD',
        sub_job = 'WHM',
        source = 'ui',
    })
    assert_equal(normalized.follow.partner.engage_range, 9.5, 'structured puller engage range must normalize')
    assert_equal(normalized.sleep.max_target_range, 14.0, 'structured sleep range must normalize')

    assert_equal(normalized.follow.partner.engage_range, 9.5, 'canonical puller engage range must remain durable')
    assert_equal(normalized.sleep.max_target_range, 14.0, 'canonical sleep range must remain durable')

    local disabled_sleep_meta = {
        character = 'Nyoourke',
        main_job = 'SAM',
        sub_job = 'DRG',
        source = 'ui',
    }
    local disabled_sleep_config = profile_v2.build_durable_config({
        sleep = {
            enabled = false,
            order = {},
            legacy_primary = '',
            max_target_range = 6.0,
        },
    }, disabled_sleep_meta)
    assert_equal(disabled_sleep_config.sleep.legacy_primary, '', 'explicit empty Sleep order must clear the compatibility primary')
    local disabled_sleep_profile = {
        version = 2,
        profile = {
            schema_version = 2,
            engine = 'UC',
            character = 'Nyoourke',
            main_job = 'SAM',
            sub_job = 'DRG',
            source = 'ui',
        },
        config = disabled_sleep_config,
    }
    local disabled_active, disabled_active_err = active_config.build_active_profile_from_v2_payload(disabled_sleep_profile, disabled_sleep_meta)
    assert_true(type(disabled_active) == 'table', 'disabled Sleep v2 profile must build active config: ' .. tostring(disabled_active_err))
    assert_equal(disabled_active.config.sleep.legacy_primary, '', 'disabled Sleep active config must preserve an empty compatibility primary')
    local disabled_diff = profile_v2.diff_durable_config(disabled_active.config.sleep, disabled_sleep_config.sleep)
    assert_equal(disabled_diff.count, 0, 'disabled empty Sleep profile must survive canonical Profile V2 conversion without durable diffs')

    local allowed, reason = puller_gate_mock({
        max_range = 9.5,
        mob_to_puller_distance = 9.4,
        mob_hpp = 100,
        distance_only = true,
    })
    assert_true(allowed, 'mob inside configured puller range must allow combat-close movement')
    assert_equal(reason, 'PULLER_IN_RANGE', 'in-range puller reason mismatch')

    allowed, reason = puller_gate_mock({
        max_range = 9.5,
        mob_to_puller_distance = 10.0,
        mob_hpp = 100,
        distance_only = true,
    })
    assert_equal(allowed, false, 'mob outside distance-only puller range must block combat-close movement')
    assert_equal(reason, 'PULLER_OUT_OF_RANGE', 'out-of-range puller reason mismatch')

    allowed, reason = puller_gate_mock({
        max_range = 9.5,
        mob_to_puller_distance = 10.0,
        mob_hpp = 98,
        distance_only = false,
    })
    assert_true(allowed, 'damaged-mob bypass must remain available when distance-only is disabled')
    assert_equal(reason, 'PULLER_HPP_BYPASS', 'puller HP bypass reason mismatch')

    local core_source = read_file('unified_combat_core.lua')
    local scheduler_source = read_file('unified_scheduler.lua')
    assert_contains(core_source, 'local function puller_engage_range(settings)', 'core must read the configured puller engage range')
    assert_contains(core_source, 'if dist <= range then', 'core puller gate must compare mob-to-puller distance with configured range')
    assert_contains(core_source, 'local puller_allowed = puller_engage_allowed(puller_settings, target)', 'combat-close movement must use the canonical follow runtime view for the shared puller gate')
    assert_contains(core_source, "return false, 'PULLER_UNRESOLVED'", 'configured unresolved puller must fail closed')
    assert_contains(core_source, "return false, 'PULLER_UNAVAILABLE'", 'configured unavailable puller must fail closed')
    assert_not_contains(scheduler_source, 'combat_core.puller_engage_allowed_for_scheduler', 'puller range must not block targeting or attack engagement')
    assert_contains(scheduler_source, "'config.sleep.max_target_range'", 'scheduler must read the active sleep target range')
    assert_contains(scheduler_source, 'if effective_max_range <= 0 or effective_max_range > configured_max_range then', 'native sleep spell range must be capped by configured range')

    io.stdout:write('selftest_configurable_control_ranges: OK\n')
end

main()
