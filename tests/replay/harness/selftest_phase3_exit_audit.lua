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

    local engine_source = read_all('unified_engine.lua')
    assert_contains(engine_source, "require('uc_scheduler_config').debug_enabled(s)",
        'engine scheduler overlay visibility must use the canonical debug facade')
    assert_not_contains(engine_source, 'bool_setting(s.debug, false)',
        'flat debug may not control the scheduler overlay')
    assert_contains(engine_source, "domain_enabled_fn(s, name)",
        'engine overlay must still pass transient runtime state to domain diagnostics')
    assert_contains(core, "return require('uc_scheduler_config').debug_enabled()",
        'core debug gate must use canonical debug facade')
    assert_equal(count_plain(core, 'if not core_debug_enabled() then'), 2,
        'core JA and tank diagnostic file writers must share canonical debug gate')
    assert_not_contains(core, 'setting_enabled(s and s.debug)',
        'flat debug may not control core diagnostic file writes')

    assert_equal(count_plain(core, "rawget(_G, 'UC_SETTINGS')"), 1,
        'core may retain exactly one explicit no-config compatibility accessor')
    assert_contains(core, "require('uc_movement_config').controls(config)",
        'scheduler-facing movement must consume explicit canonical config')
    assert_contains(core, 'view.prime = scheduler_config.combat_prime_from_config(config)',
        'core scheduler view must use supplied canonical Prime rather than global/flat')
    assert_not_contains(core, 'view.prime = scheduler_config.combat_prime(base)\n\tif type(config)',
        'core must not defer canonical Prime until after compatibility lookup')
    local facade = read_all('uc_scheduler_config.lua')
    assert_not_contains(facade, 'active_value_or_flat(',
        'generic flat fallback adapter must remain retired')

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
    assert_false(scheduler_config.tank_enmity_include_pets({ tank_enmity_include_pets = true }),
        'missing canonical tank leaf must not fall back to stale flat true')
    rawset(_G, 'UC_ACTIVE_PROFILE', previous)
    rawset(_G, 'UC_SETTINGS', previous_flat)
end

local function test_scheduler_domain_compatibility_authority()
    local active = require('uc_active_config')
    local old_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
    local old_flat = rawget(_G, 'UC_SETTINGS')
    local old_timeline = rawget(_G, 'UC_DEBUG_ACTION_TIMELINE')
    local profile = assert(active.build_default_active_profile({
        character = 'Terrasjr', main_job = 'PLD', sub_job = 'WAR',
        source = 'UC_DEFAULTS',
    }))
    assert_true(active.set_active_profile(profile))
    local config = active.get_config()
    config.debug = {}
    config.combat = {}
    config.tank = { enmity = {} }
    config.defensive = { enemy_buffs = {} }
    local stale = {
        debug = true, log_combat_sched = true, log_ja_sched = true,
        log_ja_debug = true, log_def_sched = true, log_tank_sched = true,
        log_action_timeline = true, autotarget = true, prime = true,
        tank = true, tank_enmity_actions = { 'Flash' },
        tank_enmity_include_pets = true, def_remove_enemy_buffs = true,
    }
    rawset(_G, 'UC_SETTINGS', stale)
    rawset(_G, 'UC_DEBUG_ACTION_TIMELINE', true)

    for _, test in ipairs({
        { 'debug enabled', function() return scheduler_config.debug_enabled(stale) end },
        { 'debug combat', function() return scheduler_config.debug_log_combat_sched(stale) end },
        { 'debug JA', function() return scheduler_config.debug_log_ja_sched(stale) end },
        { 'debug JA detail', function() return scheduler_config.debug_log_ja_debug(stale) end },
        { 'debug defensive', function() return scheduler_config.debug_log_def_sched(stale) end },
        { 'debug tank', function() return scheduler_config.debug_log_tank_sched(stale) end },
        { 'debug action timeline', function() return scheduler_config.debug_action_timeline(stale) end },
        { 'combat autotarget', function() return scheduler_config.combat_autotarget(stale) end },
        { 'combat prime', function() return scheduler_config.combat_prime(stale) end },
        { 'tank enabled', function() return scheduler_config.tank_enabled(stale) end },
        { 'tank include pets', function() return scheduler_config.tank_enmity_include_pets(stale) end },
        { 'enemy buff removal', function() return scheduler_config.defensive_enemy_buffs_remove(stale) end },
    }) do
        assert_false(test[2](), 'canonical missing leaf must beat stale flat: ' .. test[1])
    end
    assert_equal(#scheduler_config.tank_enmity_actions(stale), 0,
        'canonical missing enmity actions must not restore stale flat Flash')

    config.debug.enabled = true
    config.debug.combat_sched = true
    config.debug.action_timeline = true
    config.combat.prime = true
    config.tank.enabled = true
    config.tank.enmity.include_pets = true
    config.defensive.enemy_buffs.remove = true
    local opposed = {
        debug = false, log_combat_sched = false, log_action_timeline = false,
        prime = false, tank = false, tank_enmity_include_pets = false,
        def_remove_enemy_buffs = false,
    }
    assert_true(scheduler_config.debug_enabled(opposed), 'canonical debug true beats flat false')
    assert_true(scheduler_config.debug_log_combat_sched(opposed), 'canonical log true beats flat false')
    assert_true(scheduler_config.debug_action_timeline(opposed), 'canonical timeline true beats flat false')
    assert_true(scheduler_config.combat_prime(opposed), 'canonical Prime true beats flat false')
    assert_true(scheduler_config.tank_enabled(opposed), 'canonical tank true beats flat false')
    assert_true(scheduler_config.tank_enmity_include_pets(opposed), 'canonical pet true beats flat false')
    assert_true(scheduler_config.defensive_enemy_buffs_remove(opposed),
        'canonical buff-removal true beats flat false')

    -- No-profile compatibility remains available to genuine legacy callers.
    rawset(_G, 'UC_ACTIVE_PROFILE', nil)
    assert_true(scheduler_config.combat_prime(stale), 'no-profile Prime compatibility')
    assert_true(scheduler_config.debug_enabled(), 'no-profile global debug compatibility')
    assert_true(scheduler_config.debug_action_timeline(stale), 'no-profile timeline compatibility')
    assert_true(scheduler_config.tank_enabled(stale), 'no-profile tank compatibility')
    assert_true(scheduler_config.tank_enmity_include_pets(stale), 'no-profile pets compatibility')
    assert_equal(scheduler_config.tank_enmity_actions(stale)[1], 'Flash',
        'no-profile tank-actions compatibility')
    rawset(_G, 'UC_ACTIVE_PROFILE', old_profile)
    rawset(_G, 'UC_SETTINGS', old_flat)
    rawset(_G, 'UC_DEBUG_ACTION_TIMELINE', old_timeline)
end

-- Execute the actual engine overlay render path with a stub scheduler/text
-- implementation. Static source guards above also freeze the core log gates.
local function test_engine_overlay_canonical_debug_authority()
    local active = require('uc_active_config')
    local old_active = rawget(_G, 'UC_ACTIVE_PROFILE')
    local old_flat = rawget(_G, 'UC_SETTINGS')
    local old_engine = rawget(_G, 'Start_Engine')
    local old_domain_enabled = rawget(_G, 'UC_DomainEnabled')
    local old_schedule = coroutine.schedule
    local modules = { 'unified_engine', 'unified_scheduler', 'unified_combat_core', 'texts', 'uc_time' }
    local saved_modules = {}
    for _, name in ipairs(modules) do saved_modules[name] = package.loaded[name] end

    local calls = { created = 0, shown = 0, hidden = 0, domain = 0 }
    local now = 100
    local scheduled
    local function text_box()
        calls.created = calls.created + 1
        return {
            show = function() calls.shown = calls.shown + 1 end,
            hide = function() calls.hidden = calls.hidden + 1 end,
            text = function() end,
            pos = function() end,
            pos_x = function() return 100 end,
            pos_y = function() return 100 end,
        }
    end
    package.loaded.unified_engine = nil
    package.loaded.unified_scheduler = {
        process_tick = function() return false, nil end,
        get_debug_overlay = function() return { queued = {}, rejected = {} } end,
        get_action_state = function() return {} end,
        get_enemy_effect_table_overlay = function() return { lines = {} } end,
    }
    package.loaded.unified_combat_core = { assert_no_job_branch = function() return true end }
    package.loaded.texts = { new = text_box }
    package.loaded.uc_time = { gettime = function() return now end }
    coroutine.schedule = function(fn) scheduled = fn end
    rawset(_G, 'UC_DomainEnabled', function(settings)
        calls.domain = calls.domain + 1
        assert_true(type(settings) == 'table', 'domain diagnostics still need runtime settings')
        return false
    end)

    local ok, err = xpcall(function()
        local profile = assert(active.build_default_active_profile({
            character = 'Terrasjr', main_job = 'PLD', sub_job = 'WAR',
            source = 'UC_DEFAULTS',
        }))
        assert_true(active.set_active_profile(profile))
        local config = active.get_config()
        config.debug.enabled = false
        rawset(_G, 'UC_SETTINGS', { debug = true })
        rawset(_G, 'Start_Engine', true)
        local engine = require('unified_engine')
        engine.start()
        assert_equal(calls.created, 0, 'stale flat debug=true must not create overlay')
        assert_true(type(scheduled) == 'function', 'engine must schedule next tick')

        config.debug.enabled = true
        rawset(_G, 'UC_SETTINGS', { debug = false })
        now = 101
        scheduled()
        assert_equal(calls.created, 3, 'canonical debug=true must create all three overlay panels')
        assert_true(calls.shown >= 3, 'canonical debug=true must display the panels')
        assert_true(calls.domain > 0, 'domain diagnostics must retain transient settings')

        config.debug.enabled = false
        rawset(_G, 'UC_SETTINGS', { debug = true })
        now = 102
        scheduled()
        assert_true(calls.hidden >= 3, 'canonical debug=false must hide previously visible panels')

        rawset(_G, 'UC_ACTIVE_PROFILE', nil)
        local before = calls.shown
        now = 103
        scheduled()
        assert_true(calls.shown > before, 'no-profile flat debug fallback must still show overlay')
        engine.stop()
    end, debug.traceback)

    for _, name in ipairs(modules) do package.loaded[name] = saved_modules[name] end
    coroutine.schedule = old_schedule
    rawset(_G, 'UC_ACTIVE_PROFILE', old_active)
    rawset(_G, 'UC_SETTINGS', old_flat)
    rawset(_G, 'Start_Engine', old_engine)
    rawset(_G, 'UC_DomainEnabled', old_domain_enabled)
    if not ok then error(err) end
end

test_required_setting_authority()
test_common_scheduler_core_wiring()
test_tank_pet_enmity_canonical_authority()
test_scheduler_domain_compatibility_authority()
test_engine_overlay_canonical_debug_authority()

io.stdout:write('selftest_phase3_exit_audit: OK (common scheduler/core durable authority)\n')
