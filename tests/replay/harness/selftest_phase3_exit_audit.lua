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

local function count_plain(source, needle)
    local count = 0
    local start = 1
    while true do
        local at = source:find(needle, start, true)
        if at == nil then break end
        count = count + 1
        start = at + #needle
    end
    return count
end

local scheduler_config = require('uc_scheduler_config')

local function test_required_setting_authority()
    local config = {
        combat = {
            autotarget = true,
            prime = true,
            weaponskill = { enabled = true },
        },
        abilities = { enabled = true },
        sleep = { enabled = true },
        tank = { enabled = true },
    }

    assert_true(scheduler_config.combat_prime_from_config(config),
        'Prime must have an explicit canonical config accessor')
    assert_true(scheduler_config.sleep_enabled_from_config(config),
        'Sleep must have an explicit canonical config accessor')

    local expected = {
        autotarget = true,
        weaponskill_active = true,
        ability_active = true,
        sleep = true,
    }
    local seen = {}
    for _, path in ipairs({
        'uc_provider_target_control.lua',
        'uc_provider_combat.lua',
    }) do
        local source = read_all(path)
        for name in source:gmatch("required_setting%s*=%s*'([^']+)'") do
            assert_true(expected[name] == true,
                'production proposal uses an unmapped required_setting: ' .. tostring(name))
            assert_true(scheduler_config.required_setting_value_from_config(config, name) == true,
                'production required_setting must resolve through canonical config: ' .. tostring(name))
            seen[name] = true
        end
    end
    for name in pairs(expected) do
        assert_true(seen[name] == true, 'expected production required_setting missing: ' .. tostring(name))
    end

    config.combat.autotarget = false
    config.combat.weaponskill.enabled = false
    config.abilities.enabled = false
    config.sleep.enabled = false
    assert_false(scheduler_config.required_setting_value_from_config(config, 'autotarget'),
        'canonical autotarget OFF')
    assert_false(scheduler_config.required_setting_value_from_config(config, 'weaponskill_active'),
        'canonical weaponskill OFF')
    assert_false(scheduler_config.required_setting_value_from_config(config, 'ability_active'),
        'canonical abilities OFF')
    assert_false(scheduler_config.required_setting_value_from_config(config, 'sleep'),
        'canonical Sleep OFF')
    assert_equal(scheduler_config.required_setting_value_from_config(config, 'unknown_setting'), nil,
        'unknown required settings must remain unmapped so the ranker fails closed')
end

local function test_common_scheduler_core_wiring()
    local ranker = read_all('uc_scheduler_ranker.lua')
    local commitment = read_all('uc_combat_commitment.lua')
    local action_state = read_all('uc_scheduler_action_state.lua')
    local charm = read_all('uc_provider_charm_sleeper.lua')
    local wake = read_all('uc_provider_sleep_waker.lua')
    local combat_provider = read_all('uc_provider_combat.lua')
    local defensive_provider = read_all('uc_provider_defensive.lua')
    local core = read_all('unified_combat_core.lua')
    local scheduler = read_all('unified_scheduler.lua')

    assert_not_contains(ranker, 'ctx.settings[required_setting]',
        'ranker required-setting authority must never fall back to flat context')
    assert_contains(ranker, 'if required_value ~= true then',
        'ranker unknown required settings must fail closed')

    assert_contains(commitment, 'scheduler_config.combat_prime_from_config(config)',
        'combat commitment Prime policy must use the tick canonical config')
    assert_contains(commitment, 'local fight = follow_config.fight(config)',
        'combat commitment fight-leader policy must use canonical follow config')
    assert_not_contains(commitment, "require('uc_runtime_overrides')",
        'combat commitment must not route durable fight policy through flat-compatible runtime overrides')
    assert_not_contains(commitment, 'scheduler_config.combat_prime(settings)',
        'combat commitment must not read flat-compatible Prime policy')

    assert_not_contains(charm, 'ctx.settings',
        'charm sleeper gate must not consume flat scheduler context')
    assert_not_contains(charm, 'active_value_or_flat',
        'charm sleeper gate must be canonical-only')
    assert_contains(charm, 'ctx.config',
        'charm sleeper gate must consume canonical scheduler config')

    assert_not_contains(wake, 'ctx.settings',
        'sleep waker gate must not consume flat scheduler context')
    assert_not_contains(wake, 'active_value_or_flat',
        'sleep waker gate must be canonical-only')
    assert_contains(wake, 'ctx.config',
        'sleep waker gate must consume canonical scheduler config')

    assert_not_contains(action_state, 'UC_SETTINGS',
        'core action-state diagnostics must not read flat durable debug config')
    assert_contains(action_state, "uc_active_config.get_path('config.debug.combat_sched')",
        'core action-state diagnostics must use canonical debug config')

    assert_equal(count_plain(core, "rawget(_G, 'UC_SETTINGS')"), 1,
        'core may retain exactly one explicit no-config compatibility accessor')
    assert_contains(core, "require('uc_movement_config').controls(config)",
        'scheduler-facing movement must consume explicit canonical config')
    assert_contains(scheduler, 'ctx.config',
        'scheduler contexts must retain canonical config')
    assert_not_contains(scheduler, 'active_value_or_flat(',
        'unified scheduler must not retain canonical-first flat fallback authority')
    assert_not_contains(scheduler, "require('uc_runtime_overrides')",
        'unified scheduler common policy must not route through runtime override compatibility readers')
    assert_contains(scheduler, 'sleep_enabled = uc_scheduler_config.sleep_enabled_from_config',
        'scheduler Sleep enablement must be canonical')
    assert_contains(scheduler, 'sleep_spell_list = scheduler.sleep_spell_list_from_config',
        'scheduler Sleep order must be canonical')
    assert_contains(scheduler, 'uc_scheduler_config.defensive_from_config(config)',
        'common defensive selection must consume canonical config')
    assert_not_contains(defensive_provider, 'ctx.settings',
        'defensive provider must not consume flat scheduler settings')
    assert_not_contains(defensive_provider, 'active_value_or_flat',
        'defensive provider must not retain flat fallback authority')
    assert_contains(combat_provider, 'sleep_enabled(ctx.config)',
        'combat provider Sleep collection must use canonical config')
    assert_contains(combat_provider, 'fight_leader_enabled(ctx.config)',
        'combat provider fight-leader collection must use canonical config')
    assert_contains(combat_provider, 'combat_prime(ctx.config)',
        'combat provider Prime collection must use canonical config')
    assert_not_contains(combat_provider, 'sleep_enabled(ctx.settings)',
        'combat provider Sleep collection must not use flat settings')
    assert_not_contains(combat_provider, 'fight_leader_enabled(ctx.settings)',
        'combat provider fight-leader collection must not use flat settings')
    assert_not_contains(combat_provider, 'combat_prime(ctx.settings)',
        'combat provider Prime collection must not use flat settings')
end

local function test_tank_pet_enmity_canonical_authority()
    local active_config = require('uc_active_config')
    local previous = rawget(_G, 'UC_ACTIVE_PROFILE')
    local previous_flat = rawget(_G, 'UC_SETTINGS')
    local active = assert(active_config.build_default_active_profile({
        character = 'Terrasjr',
        main_job = 'PLD',
        sub_job = 'WAR',
        source = 'UC_DEFAULTS',
    }))
    assert_true(active_config.set_active_profile(active))
    rawset(_G, 'UC_SETTINGS', { tank_enmity_include_pets = true })
    local canonical = active_config.get_path('config.tank.enmity')
    assert_true(type(canonical) == 'table', 'tank enmity canonical domain must exist')
    canonical.include_pets = false
    assert_false(scheduler_config.tank_enmity_include_pets({ tank_enmity_include_pets = true }),
        'canonical false must defeat contradictory flat true')
    canonical.include_pets = true
    assert_true(scheduler_config.tank_enmity_include_pets({ tank_enmity_include_pets = false }),
        'canonical true must defeat contradictory flat false')
    canonical.include_pets = nil
    assert_true(scheduler_config.tank_enmity_include_pets({ tank_enmity_include_pets = true }),
        'pre-profile legacy compatibility may use flat setting only when canonical leaf is missing')
    rawset(_G, 'UC_ACTIVE_PROFILE', previous)
    rawset(_G, 'UC_SETTINGS', previous_flat)
end

test_required_setting_authority()
test_common_scheduler_core_wiring()
test_tank_pet_enmity_canonical_authority()

io.stdout:write('selftest_phase3_exit_audit: OK (common scheduler/core durable authority)\n')
