package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    assert_equal(value, true, message)
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then
        error(message or ('missing text: ' .. needle))
    end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then
        error(message or ('unexpected text: ' .. needle))
    end
end

local function read_all(path)
    local fh = assert(io.open(path, 'rb'))
    local source = fh:read('*a')
    fh:close()
    return source
end

local previous_windower = rawget(_G, 'windower')
local previous_settings = rawget(_G, 'UC_SETTINGS')
local previous_engine = rawget(_G, 'Start_Engine')
local previous_resources = package.loaded.resources
local previous_time = package.loaded.uc_time
local previous_active = package.loaded.uc_active_config
local previous_cor = package.loaded.uc_cor_maintenance
local previous_provider = package.loaded.uc_provider_maintenance

local range_member = {
    id = 77,
    hpp = 100,
    distance = {
        sqrt = function()
            return 9
        end,
    },
}

rawset(_G, 'UC_SETTINGS', {
    cor_roll_1 = 'Ninja Roll',
    cor_roll_2 = "Evoker's Roll",
    cor_crooked_roll_slot = 0,
    cor_elevens = false,
    cor_luzaf_range_override = false,
    cor_roll_range_require_ids = {},
    cor_light_shot_dia = true,
})

rawset(_G, 'windower', {
    ffxi = {
        get_player = function()
            return {
                id = 100,
                name = 'Corsair',
                main_job = 'COR',
                sub_job = 'DNC',
                status = 0,
                buffs = {},
            }
        end,
        get_ability_recasts = function()
            return {
                [96] = 0,
                [193] = 0,
                [194] = 0,
                [197] = 0,
                [198] = 0,
            }
        end,
        get_items = function()
            return { enabled = false }
        end,
        get_mob_by_id = function(id)
            if tonumber(id) == 77 then
                return range_member
            end
            return nil
        end,
        get_mob_by_target = function()
            return nil
        end,
    },
})

package.loaded.resources = {
    job_abilities = {
        [131] = { id = 131, en = 'Light Shot', recast_id = 195 },
    },
}
package.loaded.uc_time = {
    now = function()
        return 100
    end,
}
package.loaded.uc_active_config = {
    get_path = function(path)
        error('COR runtime must not consult global active config: ' .. tostring(path))
    end,
}
package.loaded.uc_cor_maintenance = nil
local cor = require('uc_cor_maintenance')

local function canonical_cor(overrides)
    local cfg = {
        roll_1 = 'Chaos Roll',
        roll_2 = 'Samurai Roll',
        crooked_roll_slot = 0,
        elevens = false,
        luzaf_range_override = false,
        range_selected = '',
        range_require_ids = {},
        light_shot_dia = false,
    }
    for key, value in pairs(overrides or {}) do
        cfg[key] = value
    end
    return cfg
end

local function root(cor_config, abilities)
    return {
        maintenance = {
            cor = cor_config,
        },
        abilities = {
            configured = abilities or {},
        },
    }
end

local function test_direct_runtime_authority()
    local action = cor.propose(root(canonical_cor({
        crooked_roll_slot = 1,
        elevens = true,
        luzaf_range_override = true,
    })))
    assert_true(type(action) == 'table', 'canonical COR policy should produce an action')
    assert_equal(action.action_name, 'Crooked Cards', 'canonical crooked-roll slot must win')
    assert_equal(action.detail.roll, 'Chaos Roll', 'canonical roll 1 must win over flat roll 1')
    assert_equal(action.detail.max_range, 16, 'canonical Luzaf range override must win')

    action = cor.propose(root(canonical_cor({
        roll_1 = 'Ninja Roll',
        roll_2 = "Evoker's Roll",
        crooked_roll_slot = 0,
        luzaf_range_override = false,
    })))
    assert_true(type(action) == 'table', 'canonical explicit roll pair should produce an action')
    assert_equal(action.action_name, 'Ninja Roll', 'canonical explicit roll pair must beat flat globals')

    action = cor.propose(root(canonical_cor({
        roll_1 = '',
        roll_2 = '',
        crooked_roll_slot = 0,
    }), { "Wizard's Roll", "Evoker's Roll" }))
    assert_true(type(action) == 'table', 'canonical configured abilities fallback should produce an action')
    assert_equal(action.action_name, "Wizard's Roll", 'canonical abilities fallback must select the first configured roll')

    action = cor.propose(root(canonical_cor({
        range_require_ids = { 77 },
        luzaf_range_override = false,
    })))
    assert_equal(action, nil, 'canonical roll-range requirements must block an out-of-range member')
end

local function test_provider_root_identity()
    local provider_module = require('uc_provider_maintenance')
    local received = nil
    local provider = provider_module.new({
        bool_setting = function(value, default)
            if value == nil then return default end
            return value == true
        end,
        log_def_sched = function() end,
        is_city_zone = function() return false end,
        ensure_buff_cache = function() end,
        number = function(value, default)
            local number = tonumber(value)
            return number == nil and default or number
        end,
        clamp_urgency = function(value) return tonumber(value) or 0 end,
        action_timeline_action_state_summary = function() return '' end,
        action_timeline_log = function() end,
        cor_propose = function(config)
            received = config
            return {
                action_type = 'ja',
                action_name = 'Chaos Roll',
                target_kind = 'self',
                target_name = 'Corsair',
                target_id = 100,
                reason_code = 'cor_authority_test',
                urgency = 0.75,
                detail = {},
            }
        end,
        get_party_members = function() return {} end,
        action_ready = function() return true, '', 'ja' end,
        clear_local_brd_spell_failure = function() end,
        pending_mark_failed = function() end,
        count_matching_buffs = function() return 0 end,
        phase1 = { maintenance_next_at = {} },
        maintenance_buff_cache = {},
        action_timeline_state = {},
        brd_maintenance_priority = 200,
    })

    local canonical = root(canonical_cor())
    local out = {}
    provider.collect({
        now = 10,
        config = canonical,
        settings = {
            cor_roll_1 = 'Ninja Roll',
            cor_roll_2 = "Evoker's Roll",
        },
        player_present = true,
        player = {
            id = 100,
            name = 'Corsair',
            main_job = 'COR',
            sub_job = 'DNC',
            status = 0,
            buffs = {},
        },
    }, out)

    assert_equal(received, canonical, 'maintenance provider must pass ctx.config to COR by identity')
    assert_equal(#out, 1, 'canonical COR proposal must route through maintenance provider')
    assert_equal(out[1].action_name, 'Chaos Roll', 'routed COR action')
end

local function test_static_boundary()
    local cor_source = read_all('uc_cor_maintenance.lua')
    local provider_source = read_all('uc_provider_maintenance.lua')
    local normalizer_source = read_all('uc_config_normalizer_cor.lua')

    assert_not_contains(cor_source, 'UC_SETTINGS', 'COR runtime must not read flat global settings')
    assert_not_contains(cor_source, 'ctx.settings', 'COR runtime must not read scheduler compatibility settings')
    assert_not_contains(cor_source, 'uc_active_config', 'COR runtime must not resample active config')
    assert_not_contains(cor_source, 'active_value_or_flat', 'COR runtime must not retain active/flat fallback helpers')
    assert_contains(cor_source, 'local cor = cor_config(config)', 'COR runtime must derive policy from explicit config')
    assert_contains(cor_source, 'for _, a in ipairs(configured_abilities(config)) do',
        'COR ability-derived roll fallback must use explicit canonical config')
    assert_contains(cor_source, 'local elevens = cor.elevens == true', 'COR elevens mode must use canonical COR subtree')
    assert_contains(provider_source, 'local action = cor_propose(ctx.config)',
        'maintenance provider must route the canonical root to COR')
    assert_not_contains(provider_source, 'cor_propose(ctx.settings)',
        'maintenance provider must not route compatibility settings to COR')
    assert_contains(normalizer_source, 'function wrapped.normalize(settings, meta)',
        'COR settings reader belongs to the input normalizer compatibility boundary')
    assert_not_contains(cor_source, "require('uc_config_normalizer_cor')",
        'COR action runtime must not invoke the compatibility normalizer')
end

rawset(_G, 'Start_Engine', true)
local ok, err = pcall(function()
    test_direct_runtime_authority()
    test_provider_root_identity()
    test_static_boundary()
end)

rawset(_G, 'windower', previous_windower)
rawset(_G, 'UC_SETTINGS', previous_settings)
rawset(_G, 'Start_Engine', previous_engine)
package.loaded.resources = previous_resources
package.loaded.uc_time = previous_time
package.loaded.uc_active_config = previous_active
package.loaded.uc_cor_maintenance = previous_cor
package.loaded.uc_provider_maintenance = previous_provider

if not ok then
    error(err, 0)
end

print('selftest_phase4_cor_authority: OK (canonical COR runtime authority)')
