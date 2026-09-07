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

-- Canonical config normalization coverage.
package.loaded.uc_config_normalizer = nil
local normalizer = require('uc_config_normalizer')
local defaults = normalizer.default_config({ character = 'Niightsiide', main_job = 'GEO', sub_job = 'RDM' })
assert_true(defaults.combat.auto_engage == true, 'auto_engage must default on to preserve existing behavior')
assert_true(defaults.spells.magic_burst == false, 'magic burst must default off')

local normalized = normalizer.normalize({
    auto_engage = false,
    magic_burst_enabled = true,
    spell = 'Fire V',
    reactions = {
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
    },
}, { character = 'Niightsiide', main_job = 'GEO', sub_job = 'RDM' })
assert_true(normalized.combat.auto_engage == false, 'flat auto_engage alias must normalize')
assert_true(normalized.spells.magic_burst == true, 'flat magic_burst_enabled alias must normalize')
assert_equal(normalized.spells.configured, 'Fire V', 'configured burst spell must normalize')
assert_equal(normalized.reactions.rules[1].response, 'use_action', 'use_action reaction response must survive normalize')
assert_equal(normalized.reactions.rules[1].action_type, 'spell', 'use_action action type must survive normalize')
assert_equal(normalized.reactions.rules[1].action_name, 'Stun', 'use_action action name must survive normalize')

local invalid_action_ok, invalid_action_error = pcall(normalizer.normalize, {
    reactions = {
        enabled = true,
        rules = {
            {
                trigger = 'ability_window',
                name = 'Just Desserts',
                response = 'use_action',
                action_type = 'ja',
                action_name = 'Weapon Bash',
            },
        },
    },
}, {})
assert_true(not invalid_action_ok, 'unsupported reaction action type must fail normalization')
assert_true(tostring(invalid_action_error):find('currently supports only spell', 1, true) ~= nil,
    'unsupported use_action type must return an actionable error')

-- Reaction runtime coverage: use_action is an authoritative ability-window lock,
-- blocks normal enemy offense, but permits its own configured proposal.
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
            if path == 'config.reactions' then
                return active_reaction_config
            end
            if path == 'config.encounter' then
                return nil
            end
            return nil
        end,
    }
end
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
    provider = 'combat',
    family_id = 'combat.ws.primary',
    action_type = 'ws',
    target_kind = 'mob',
    target_id = 900,
}), 'use_action lock must block normal enemy offense')
assert_true(not reactions.blocks_proposal(ready.activated, {
    provider = 'combat',
    family_id = 'combat.reaction.action',
    action_type = 'spell',
    action_name = 'Stun',
    target_kind = 'mob',
    target_id = 900,
}), 'use_action lock must permit its own reaction action')
local action_lock = reactions.get_action_lock()
assert_equal(action_lock.action_name, 'Stun', 'runtime must expose the active action reaction to the combat provider')
reactions.on_action({ actor_id = 900, category = 11, param = 777 }, 900, 10.5, true)
assert_true(reactions.get_action_lock() == nil, 'ability completion must clear the reaction action lock')

-- Combat provider coverage with isolated dependencies.
reset_module('resources')
package.preload.resources = function()
    local spells = {
        [1] = { id = 1, en = 'Stun', element = 'Lightning', range = 12 },
        [2] = { id = 2, en = 'Fire V', element = 'Fire', range = 12 },
    }
    function spells:with(key, value)
        if key ~= 'en' then return nil end
        for _, spell in pairs(self) do
            if type(spell) == 'table' and spell.en == value then
                return spell
            end
        end
        return nil
    end
    return {
        spells = spells,
        elements = {},
    }
end

local config_values = {
    ['config.combat.auto_engage'] = true,
    ['config.spells'] = {
        enabled = false,
        configured = 'Fire V',
        magic_burst = true,
    },
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
    return {
        get_action_lock = function()
            return current_action_lock
        end,
    }
end

local current_skillchain = nil
reset_module('unified_combat_core')
package.preload.unified_combat_core = function()
    return {
        get_skillchain_snapshot = function()
            return current_skillchain
        end,
    }
end
reset_module('uc_camp_pull_registry')
package.preload.uc_camp_pull_registry = function()
    return {
        combat_order = function() return nil end,
    }
end
reset_module('uc_provider_combat')
local combat_provider = require('uc_provider_combat')

local function bool_setting(value, default_value)
    if value == nil then return default_value end
    return value == true
end

local function new_provider()
    return combat_provider.new({
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
        action_ready = function(name)
            return name == 'Stun' or name == 'Fire V', 'OK', 'spell'
        end,
        action_effective_range = function() return 20.9 end,
        log_ja_sched = function() end,
        phase1 = {},
        action_state = {},
        skillchain_priority = 131,
        aftermath_priority = 130,
        sleep_priority = 142,
        tank_engage_priority = 120,
        default_engage_priority = 110,
        tank_engage_urgency = 1,
        default_engage_urgency = 0.5,
    })
end

local provider = new_provider()
_G.Start_Engine = true
local ctx = {
    now = 100,
    settings = { weaponskill_active = false },
    player_present = true,
    player = { id = 1, name = 'Niightsiide', status = 0, vitals = { tp = 0 } },
    target_present = true,
    target = { id = 900, name = 'Zerde', hpp = 100, valid_target = true, spawn_type = 16, claim_id = 123 },
    mobs_by_id = {},
    mob_array = {},
}

current_action_lock = {
    response = 'use_action',
    action_type = 'spell',
    action_name = 'Stun',
    actor_id = 900,
    name = 'Just Desserts',
}
local proposals = {}
provider.collect_offense(ctx, proposals)
assert_equal(#proposals, 1, 'reaction spell must propose even when normal WS offense is disabled')
assert_equal(proposals[1].action_name, 'Stun', 'reaction proposal must cast configured Stun')
assert_equal(proposals[1].family_id, 'combat.reaction.action', 'reaction proposal family mismatch')
assert_equal(proposals[1].target_id, 900, 'reaction proposal must target the reacting enemy actor')

current_action_lock = nil
current_skillchain = {
    active_properties = { 'Fusion' },
    magic_burst_expires_at = 110,
}
proposals = {}
provider.collect_offense(ctx, proposals)
assert_equal(#proposals, 1, 'matching active skillchain must produce one magic burst proposal')
assert_equal(proposals[1].action_name, 'Fire V', 'Fusion must permit configured Fire V burst')
assert_equal(proposals[1].family_id, 'combat.magic_burst', 'magic burst proposal family mismatch')

current_skillchain = {
    active_properties = { 'Distortion' },
    magic_burst_expires_at = 110,
}
proposals = {}
provider.collect_offense(ctx, proposals)
assert_equal(#proposals, 0, 'element mismatch must not emit a magic burst')

current_skillchain = {
    active_properties = { 'Fusion' },
    magic_burst_expires_at = 104,
}
proposals = {}
provider.collect_offense(ctx, proposals)
assert_equal(#proposals, 0, 'insufficient remaining burst window must not emit a late spell')

config_values['config.combat.auto_engage'] = false
proposals = {}
provider.collect_engage(ctx, proposals)
assert_equal(#proposals, 0, 'auto_engage=false must suppress engage proposals without disabling combat targeting')

_G.Start_Engine = nil
io.stdout:write('selftest_combat_extensions: OK\n')
