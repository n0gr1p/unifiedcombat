local function assert_true(value, message)
    if value ~= true then
        error(message or 'expected true')
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
    end
end

local function reset_module(name)
    package.loaded[name] = nil
    package.preload[name] = nil
end

local MOCKED_MODULES = {
    'resources',
    'uc_active_config',
    'uc_combat_extension_config',
    'uc_reaction_runtime',
    'unified_combat_core',
    'uc_targeting_common',
    'uc_camp_pull_registry',
    'uc_combat_extensions',
    'uc_provider_combat',
}

local original_loaded = {}
local original_preload = {}
for i = 1, #MOCKED_MODULES do
    local name = MOCKED_MODULES[i]
    original_loaded[name] = package.loaded[name]
    original_preload[name] = package.preload[name]
end
local original_uc_settings = rawget(_G, 'UC_SETTINGS')
local original_start_engine = rawget(_G, 'Start_Engine')

local function restore_environment()
    for i = 1, #MOCKED_MODULES do
        local name = MOCKED_MODULES[i]
        package.loaded[name] = original_loaded[name]
        package.preload[name] = original_preload[name]
    end
    _G.UC_SETTINGS = original_uc_settings
    _G.Start_Engine = original_start_engine
end

local ok, err = xpcall(function()
    -- Extension config: active v2 values win, flat settings remain a compatibility fallback.
    local active_values = {}
    reset_module('uc_active_config')
    package.preload.uc_active_config = function()
        return {
            get_path = function(path, default_value)
                local value = active_values[path]
                if value == nil then return default_value end
                return value
            end,
        }
    end
    _G.UC_SETTINGS = {
        auto_engage = false,
        magic_burst_enabled = true,
        spell = 'Fire V',
        reaction_enabled = true,
        reaction_rules = {
            {
                trigger = 'ability_window',
                name = 'Just Desserts',
                response = 'use_action',
                action_type = 'spell',
                action_name = 'Stun',
            },
        },
    }
    reset_module('uc_combat_extension_config')
    local extension_config = require('uc_combat_extension_config')
    assert_true(extension_config.auto_engage_enabled({}) == false, 'flat auto_engage fallback must be honored')
    local burst = extension_config.magic_burst({})
    assert_true(burst.enabled, 'flat magic burst fallback must be honored')
    assert_equal(burst.spell, 'Fire V', 'flat magic burst spell mismatch')
    local fallback_rules = extension_config.reaction_rules()
    assert_equal(fallback_rules[1].action_name, 'Stun', 'flat action reaction fallback mismatch')
    local invalid_ok, invalid_error = extension_config.validate_action_rule({
        trigger = 'ability_window', response = 'use_action', action_type = 'ja', action_name = 'Weapon Bash',
    })
    assert_true(invalid_ok == false, 'unsupported reaction action type must fail validation')
    assert_true(tostring(invalid_error):find('currently supports only spell', 1, true) ~= nil,
        'unsupported action type must have an actionable error')
    active_values['config.combat.auto_engage'] = true
    active_values['config.spells'] = { magic_burst = false, configured = 'Blizzard V' }
    assert_true(extension_config.auto_engage_enabled({ auto_engage = false }), 'active auto_engage must override flat compatibility value')
    assert_true(extension_config.magic_burst({}).enabled == false, 'active magic burst disable must override flat compatibility value')
    active_values = {}

    -- Reaction runtime: use_action is a real authoritative ability-window lock.
    reset_module('resources')
    package.preload.resources = function()
        return {
            monster_abilities = {
                [777] = { id = 777, en = 'Just Desserts' },
            },
            buffs = {},
        }
    end
    local active_reaction_config = {
        enabled = true,
        rules = {
            {
                trigger = 'ability_window',
                name = 'Just Desserts',
                response = 'use_action',
                action_type = 'spell',
                action_name = 'Stun',
            },
        },
    }
    reset_module('uc_active_config')
    package.preload.uc_active_config = function()
        return {
            get_path = function(path)
                if path == 'config.reactions' then return active_reaction_config end
                return nil
            end,
        }
    end
    _G.UC_SETTINGS = nil
    reset_module('uc_combat_extension_config')
    reset_module('uc_reaction_runtime')
    local reactions = require('uc_reaction_runtime')
    local ready = reactions.on_action({
        actor_id = 900,
        category = 7,
        targets = { { actions = { { param = 777 } } } },
    }, 900, 10, true)
    assert_equal(ready.activated.response, 'use_action', 'Just Desserts must activate use_action')
    assert_equal(ready.activated.action_type, 'spell', 'reaction lock must carry action type')
    assert_equal(ready.activated.action_name, 'Stun', 'reaction lock must carry action name')
    assert_true(not reactions.blocks_movement(ready.activated), 'use_action must not claim movement ownership')
    assert_true(reactions.blocks_proposal(ready.activated, {
        provider = 'combat', family_id = 'combat.ws.primary', action_type = 'ws', target_kind = 'mob', target_id = 900,
    }), 'use_action lock must block ordinary enemy offense')
    assert_true(not reactions.blocks_proposal(ready.activated, {
        provider = 'combat', family_id = 'combat.reaction.action', action_type = 'spell', action_name = 'Stun',
        target_kind = 'mob', target_id = 900,
    }), 'use_action lock must permit its own configured reaction proposal')
    local action_lock = reactions.get_action_lock()
    assert_equal(action_lock.action_name, 'Stun', 'runtime must expose action reaction lock')
    reactions.on_action({ actor_id = 900, category = 11, param = 777 }, 900, 10.5, true)
    assert_true(reactions.get_action_lock() == nil, 'ability completion must clear action reaction lock')

    -- Combat provider: reaction action, magic burst, and independent auto-engage.
    reset_module('resources')
    package.preload.resources = function()
        local spells = {
            [1] = { id = 1, en = 'Stun', element = 'Lightning', range = 12 },
            [2] = { id = 2, en = 'Fire V', element = 'Fire', range = 12 },
        }
        function spells:with(key, value)
            if key ~= 'en' then return nil end
            for _, spell in pairs(self) do
                if type(spell) == 'table' and spell.en == value then return spell end
            end
            return nil
        end
        return { spells = spells, elements = {} }
    end
    local provider_reaction_config = {
        enabled = true,
        rules = {
            {
                trigger = 'ability_window',
                name = 'Just Desserts',
                response = 'use_action',
                action_type = 'spell',
                action_name = 'Stun',
            },
        },
    }
    local config_values = {
        ['config.combat.auto_engage'] = true,
        ['config.spells'] = { enabled = false, configured = 'Fire V', magic_burst = true },
        ['config.reactions'] = provider_reaction_config,
    }
    reset_module('uc_active_config')
    package.preload.uc_active_config = function()
        return {
            get_path = function(path, default_value)
                local value = config_values[path]
                if value == nil then return default_value end
                return value
            end,
        }
    end
    local current_action_lock = nil
    reset_module('uc_reaction_runtime')
    package.preload.uc_reaction_runtime = function()
        return { get_action_lock = function() return current_action_lock end }
    end
    local current_skillchain = nil
    reset_module('unified_combat_core')
    package.preload.unified_combat_core = function()
        return { get_skillchain_snapshot = function() return current_skillchain end }
    end
    reset_module('uc_targeting_common')
    package.preload.uc_targeting_common = function()
        return { build_friendly_claims = function() return { 123 }, { [123] = true } end }
    end
    reset_module('uc_camp_pull_registry')
    package.preload.uc_camp_pull_registry = function()
        return { combat_order = function() return nil end }
    end
    reset_module('uc_combat_extension_config')
    reset_module('uc_combat_extensions')
    reset_module('uc_provider_combat')
    local combat_provider = require('uc_provider_combat')

    local function bool_setting(value, default_value)
        if value == nil then return default_value end
        return value == true
    end
    local provider = combat_provider.new({
        bool_setting = bool_setting,
        clamp_urgency = function(v) return v end,
        build_partner_target_set = function() return {} end,
        select_ws_plan = function() return nil end,
        action_timeline_log = function() end,
        combat_domain_enabled = function() return true end,
        sleep_enabled = function() return false end,
        sleep_spell_list = function() return {} end,
        is_live_actionable_target = function() return true end,
        build_friendly_claims = function() return {}, { [123] = true } end,
        mob_targets_friendly_member = function() return false end,
        sleep_max_target_distance = function() return 20 end,
        target_sleep_suppressed = function() return false end,
        select_sleep_spell = function() return nil end,
        combat_autotarget = function() return true end,
        tank_enabled = function() return false end,
        debug_enabled = function() return false end,
        combat_prime = function() return false end,
        fight_leader_enabled = function() return false end,
        fight_leader_id = function() return 0 end,
        fight_leader_target_id = function() return 0 end,
        add_control_enabled = function() return false end,
        select_pull = function() return nil end,
        build_party_id_set = function() return {} end,
        prime_unclaimed_party_aggressive_ok = function() return false end,
        pending_engage_state = function() return nil end,
        pending_engage_live = function() return false end,
        collect_ordered_abilities = function() return {} end,
        get_ja_resource = function() return nil end,
        action_ready = function(name) return name == 'Stun' or name == 'Fire V', 'OK', 'spell' end,
        action_effective_range = function() return 20.9 end,
        log_ja_sched = function() end,
        phase1 = {}, action_state = {},
        skillchain_priority = 131, aftermath_priority = 130, sleep_priority = 142,
        tank_engage_priority = 120, default_engage_priority = 110,
        tank_engage_urgency = 1, default_engage_urgency = 0.5,
    })
    _G.Start_Engine = true
    local ctx = {
        now = 100,
        config = { combat = { autotarget = true, auto_engage = true } },
        settings = { weaponskill_active = false },
        player_present = true,
        player = { id = 1, name = 'Niightsiide', status = 0, vitals = { tp = 0 } },
        target_present = true,
        target = { id = 900, name = 'Zerde', hpp = 100, valid_target = true, spawn_type = 16, claim_id = 123, distance = 100 },
        party = {},
        mobs_by_id = {}, mob_array = {},
    }
    current_action_lock = {
        key = 'ability_window:900:just desserts', response = 'use_action', action_type = 'spell',
        action_name = 'Stun', actor_id = 900, name = 'Just Desserts',
    }
    local proposals = {}
    provider.collect_offense(ctx, proposals)
    assert_equal(#proposals, 1, 'reaction spell must propose while normal WS offense is disabled')
    assert_equal(proposals[1].action_name, 'Stun', 'reaction proposal must cast Stun')
    assert_equal(proposals[1].family_id, 'combat.reaction.action', 'reaction proposal family mismatch')
    current_action_lock = nil
    current_skillchain = { last_confirmed_result = 'Fusion', active_properties = { 'Fusion' }, magic_burst_expires_at = 110 }
    proposals = {}
    provider.collect_offense(ctx, proposals)
    assert_equal(#proposals, 1, 'Fusion must create configured Fire V burst proposal')
    assert_equal(proposals[1].action_name, 'Fire V', 'magic burst spell mismatch')
    assert_equal(proposals[1].family_id, 'combat.magic_burst', 'magic burst family mismatch')
    current_skillchain = { last_confirmed_result = 'Distortion', active_properties = { 'Distortion' }, magic_burst_expires_at = 110 }
    proposals = {}
    provider.collect_offense(ctx, proposals)
    assert_equal(#proposals, 0, 'element mismatch must not create a burst proposal')
    current_skillchain = { last_confirmed_result = 'Fusion', active_properties = { 'Fusion' }, magic_burst_expires_at = 104 }
    proposals = {}
    provider.collect_offense(ctx, proposals)
    assert_equal(#proposals, 0, 'short remaining burst window must not create a late proposal')
    config_values['config.combat.auto_engage'] = false
    ctx.config.combat.auto_engage = false
    proposals = {}
    provider.collect_engage(ctx, proposals)
    assert_equal(#proposals, 0, 'auto_engage=false must suppress engage proposals only')
end, debug.traceback)

restore_environment()
if not ok then
    error(err)
end

io.stdout:write('selftest_combat_extensions: OK\n')
