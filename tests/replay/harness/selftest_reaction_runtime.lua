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

package.loaded.resources = nil
package.preload.resources = function()
    return {
        monster_abilities = {
            [284] = { id = 284, en = 'Cold Stare' },
            [1563] = { id = 1563, en = 'Cold Stare' },
        },
        buffs = {
            [300] = { id = 300, en = 'Dread Spikes' },
        },
    }
end

local normalizer = require('uc_config_normalizer')
local active_config = require('uc_active_config')
local profile_v2 = require('uc_profile_v2')
package.loaded.uc_reaction_runtime = nil
local reactions = require('uc_reaction_runtime')

local rules = {
    { trigger = 'ability_window', name = 'Cold Stare', response = 'turn_away' },
    { trigger = 'enemy_buff', name = 'Dread Spikes', response = 'stop_attacking' },
}
local meta = { character = 'Redrogue', main_job = 'BRD', sub_job = 'WHM' }
local normalized = normalizer.normalize({
    reactions = {
        enabled = true,
        rules = rules,
    },
}, meta)
assert_true(normalized.reactions.enabled, 'structured reaction enabled flag must normalize')
assert_equal(#normalized.reactions.rules, 2, 'structured reaction rules must normalize')
assert_equal(normalized.reactions.rules[1].name, 'Cold Stare', 'ability rule name must survive normalize')

local payload = {
    version = 2,
    profile = {
        schema_version = 2,
        engine = 'UC',
        character = 'Redrogue',
        main_job = 'BRD',
        sub_job = 'WHM',
        source = 'ui',
    },
    config = {
        reactions = {
            enabled = true,
            rules = rules,
        },
    },
}
local active, active_error = active_config.build_active_profile_from_v2_payload(payload, meta)
assert_true(type(active) == 'table', active_error or 'reaction active profile must build')
assert_true(active_config.set_active_profile(active), 'reaction active profile must install')
assert_equal(active_config.get_path({ 'config', 'reactions', 'rules', 1, 'name' }), 'Cold Stare', 'active config must preserve reaction name')
local projected, projection_error = active_config.project_flat_settings(active, {})
assert_true(type(projected) == 'table', projection_error or 'reaction compatibility projection must build')
assert_true(projected.reaction_enabled, 'reaction enabled flag must project')
assert_equal(projected.reaction_rules[2].name, 'Dread Spikes', 'reaction rule list must project')
local durable = profile_v2.build_durable_config(projected, meta)
local diff = profile_v2.diff_durable_config(durable.reactions, payload.config.reactions)
assert_equal(diff.count, 0, 'reaction config must round-trip without durable diffs')

local old_payload = {
    version = 2,
    profile = payload.profile,
    config = {},
}
local old_active = assert(active_config.build_active_profile_from_v2_payload(old_payload, meta))
local cleared_projection = assert(active_config.project_flat_settings(old_active, projected))
assert_true(cleared_projection.reaction_enabled == false, 'omitted optional reaction domain must clear stale compatibility enable flag')
assert_equal(#cleared_projection.reaction_rules, 0, 'omitted optional reaction domain must clear stale compatibility rules')
assert_true(profile_v2.build_durable_config(cleared_projection, meta).reactions == nil, 'disabled empty reaction projection must remain equivalent to omission')
assert_true(active_config.set_active_profile(active), 'reaction active profile must reinstall after omission projection test')

local wrong_actor = reactions.on_action({
    actor_id = 901,
    category = 7,
    targets = { { actions = { { param = 284 } } } },
}, 900, 1, true)
assert_equal(wrong_actor.activated.actor_id, 901, 'valid non-current enemy actor must activate a reaction')
local off_target_lock = reactions.evaluate(900, {}, 1.1)
assert_equal(off_target_lock.actor_id, 901, 'non-current actor ability lock must survive target-scoped refresh')
local wrong_actor_complete = reactions.on_action({ actor_id = 901, category = 11, param = 284 }, 900, 1.2, false)
assert_equal(wrong_actor_complete.released_target_id, 901, 'non-current actor completion must release its reaction')

local invalid_actor = reactions.on_action({
    actor_id = 902,
    category = 7,
    targets = { { actions = { { param = 284 } } } },
}, 900, 1.3, false)
assert_true(invalid_actor.activated == nil, 'invalid or non-enemy action actor must not activate a reaction')

local ready = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 284 } } } },
}, 900, 2, true)
assert_equal(ready.activated.name, 'Cold Stare', 'Cold Stare ready must activate configured rule')
assert_equal(ready.activated.response, 'turn_away', 'Cold Stare response mismatch')
local active_lock = reactions.evaluate(900, {}, 2.1)
assert_equal(active_lock.name, 'Cold Stare', 'ability lock must remain active before completion')
assert_true(reactions.blocks_proposal(active_lock, {
    provider = 'combat', action_type = 'ws', target_kind = 'mob',
}), 'reaction must block enemy-facing offense')
assert_true(not reactions.blocks_proposal(active_lock, {
    provider = 'defensive_internal', action_type = 'spell', target_kind = 'party',
}), 'reaction must allow party support proposals')
assert_true(not reactions.blocks_proposal(active_lock, {
    provider = 'maintenance_brd', action_type = 'spell', target_kind = 'self',
}), 'reaction must allow self maintenance proposals')

local complete = reactions.on_action({ actor_id = 900, category = 11, param = 284 }, 900, 3)
assert_equal(complete.released_target_id, 900, 'matching completion must release Cold Stare lock')
local after_complete = reactions.evaluate(900, {}, 3.1)
assert_true(after_complete == nil, 'Cold Stare lock must be gone after completion')

local watch = reactions.effect_watch_set()
assert_true(watch[300] == true, 'configured enemy buff must be added to observed effect set')
local buff_lock = reactions.evaluate(900, { { effect_id = 300 } }, 4)
assert_equal(buff_lock.name, 'Dread Spikes', 'tracked enemy buff must activate stop-attacking lock')
assert_equal(buff_lock.response, 'stop_attacking', 'enemy buff response mismatch')
local no_buff, released_target = reactions.evaluate(901, {}, 5)
assert_true(no_buff == nil, 'enemy buff stop-attacking lock must clear when its actor is no longer the current target')
assert_equal(released_target, 900, 'target-scoped enemy buff lock removal must request facing restoration')

local source = assert(io.open('unified_scheduler.lua', 'rb')):read('*a')
assert_true(source:find("reject_reason = 'reaction_hold'", 1, true) ~= nil, 'scheduler must reject blocked proposals through reaction hold')
assert_true(source:find("UC_MOVEMENT_MODE = 'REACTION_HOLD'", 1, true) ~= nil, 'movement coordinator must hold while turned away')
assert_true(source:find("if rawget(_G, 'Start_Engine') == true then", 1, true) ~= nil, 'ability reactions must not activate while the engine is stopped')
assert_true(source:find('scheduler.apply_reaction_turn(reaction_event.activated, true)', 1, true) ~= nil, 'ready event must use scheduler turn ownership')
assert_true(source:find('scheduler.apply_reaction_turn({ actor_id = current_target_id }, false)', 1, true) ~= nil, 'completion must restore scheduler facing toward the current target')

local before_reset_config = active_config.get_path({ 'config', 'reactions', 'rules', 1, 'name' })
reactions.reset('test')
assert_equal(active_config.get_path({ 'config', 'reactions', 'rules', 1, 'name' }), before_reset_config, 'runtime reset must not mutate durable reaction config')

io.stdout:write('selftest_reaction_runtime: OK\n')
