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
            [999] = { id = 999, en = 'Dancing Fullers' },
        },
        buffs = {
            [33] = { id = 33, en = 'Haste' },
            [173] = { id = 173, en = 'Dread Spikes' },
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
    { trigger = 'ability_window', name = 'Dancing Fullers', response = 'run_away', distance = 12.0 },
}
local meta = { character = 'Redrogue', main_job = 'BRD', sub_job = 'WHM' }
local normalized = normalizer.normalize({
    reactions = {
        enabled = true,
        rules = rules,
    },
}, meta)
assert_true(normalized.reactions.enabled, 'structured reaction enabled flag must normalize')
assert_equal(#normalized.reactions.rules, 3, 'structured reaction rules must normalize')
assert_equal(normalized.reactions.rules[1].name, 'Cold Stare', 'ability rule name must survive normalize')
assert_equal(normalized.reactions.rules[3].distance, 12.0, 'run-away target distance must survive normalize')

local invalid_distance_ok, invalid_distance_error = pcall(normalizer.normalize, {
    reactions = {
        enabled = true,
        rules = {
            { trigger = 'ability_window', name = 'Dancing Fullers', response = 'run_away', distance = 0 },
        },
    },
}, meta)
assert_true(not invalid_distance_ok, 'run-away distance zero must fail configuration normalization')
assert_true(tostring(invalid_distance_error):find('distance must be a finite number greater than zero', 1, true) ~= nil,
    'invalid run-away distance must produce an actionable validation error')

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
assert_equal(projected.reaction_rules[3].distance, 12.0, 'run-away distance must project through compatibility settings')
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

local run_ready = reactions.on_action({
    actor_id = 910,
    category = 7,
    targets = { { actions = { { param = 999 } } } },
}, 900, 3.2, true)
assert_equal(run_ready.activated.response, 'run_away', 'Dancing Fullers must activate run-away response')
assert_equal(run_ready.activated.distance, 12.0, 'active run-away lock must carry configured raw distance')
assert_true(reactions.blocks_movement(run_ready.activated), 'run-away must own movement above normal positioning')

local run_request = reactions.run_away_request(run_ready.activated, { x = 4, y = 0 }, { x = 0, y = 0 })
assert_equal(run_request.kind, 'run', 'inside run-away distance must begin outward movement')
assert_equal(run_request.run_x, 1, 'outward vector must point from enemy toward player')
assert_equal(run_request.run_y, 0, 'outward vector y component mismatch')
assert_equal(run_request.current_distance, 4, 'run-away must report raw coordinate distance')
run_request = reactions.run_away_request(run_ready.activated, { x = 8, y = 0 }, { x = 0, y = 0 })
assert_equal(run_request.kind, 'run', 'outward movement must continue below target distance')

run_request = reactions.run_away_request(run_ready.activated, { x = 8, y = 0 }, { x = 8, y = 4 })
assert_equal(run_request.kind, 'run', 'moving enemy must retain active escape movement below target')
assert_equal(run_request.run_x, 0, 'moving enemy must recalculate the escape x component')
assert_equal(run_request.run_y, -1, 'moving enemy must recalculate the escape y component')

run_request = reactions.run_away_request(run_ready.activated, nil, { x = 8, y = 4 })
assert_equal(run_request.kind, 'stop', 'missing player position must stop an active outward vector')
assert_equal(run_request.reason, 'REACTION_RUN_AWAY_POSITION_UNAVAILABLE', 'missing-position reason mismatch')
run_request = reactions.run_away_request(run_ready.activated, nil, { x = 8, y = 4 })
assert_equal(run_request.kind, 'hold', 'repeated missing positions must remain stopped without movement spam')
run_request = reactions.run_away_request(run_ready.activated, { x = 8, y = 0 }, { x = 0, y = 0 })
assert_equal(run_request.kind, 'run', 'run-away must resume when position data returns')

local superseded_run = reactions.on_action({
    actor_id = 910,
    category = 7,
    targets = { { actions = { { param = 284 } } } },
}, 900, 3.25, true)
assert_equal(superseded_run.released.response, 'run_away', 'a superseding ability must expose prior run-away ownership for cleanup')
assert_equal(superseded_run.activated.response, 'turn_away', 'superseding ability must activate its configured response')
reactions.on_action({ actor_id = 910, category = 11, param = 284 }, 900, 3.26)

run_ready = reactions.on_action({
    actor_id = 910,
    category = 7,
    targets = { { actions = { { param = 999 } } } },
}, 900, 3.27, true)
run_request = reactions.run_away_request(run_ready.activated, { x = 8, y = 0 }, { x = 0, y = 0 })
assert_equal(run_request.kind, 'run', 'early-completion setup must own outward movement')

local run_complete_early = reactions.on_action({ actor_id = 910, category = 11, param = 999 }, 900, 3.3)
assert_equal(run_complete_early.released.response, 'run_away', 'early completion must expose released movement ownership')
assert_true(reactions.evaluate(900, {}, 3.4) == nil, 'early completion must clear run-away state immediately')

run_ready = reactions.on_action({
    actor_id = 910,
    category = 7,
    targets = { { actions = { { param = 999 } } } },
}, 900, 3.5, true)
run_request = reactions.run_away_request(run_ready.activated, { x = 13, y = 0 }, { x = 0, y = 0 })
assert_equal(run_request.kind, 'stop', 'player starting beyond target must not move farther outward')
assert_equal(run_request.reason, 'REACTION_RUN_AWAY_REACHED', 'beyond-target stop reason mismatch')
run_request = reactions.run_away_request(run_ready.activated, { x = 4, y = 0 }, { x = 3, y = 0 })
assert_equal(run_request.kind, 'hold', 'satisfied run-away distance must remain sticky for the ability window')
local run_complete_reached = reactions.on_action({ actor_id = 910, category = 11, param = 999 }, 900, 3.6)
assert_equal(run_complete_reached.released.run_away_phase, 'reached', 'completion after target must clean reached state')

run_ready = reactions.on_action({
    actor_id = 910,
    category = 7,
    targets = { { actions = { { param = 999 } } } },
}, 900, 3.7, true)
run_request = reactions.run_away_request(run_ready.activated, { x = 11.9, y = 0 }, { x = 0, y = 0 })
assert_equal(run_request.kind, 'stop', 'small stop tolerance must avoid overshooting the configured distance')
assert_equal(run_request.reason, 'REACTION_RUN_AWAY_REACHED', 'near-target tolerance reason mismatch')
local cancelled_run, replacement_run = reactions.cancel(run_ready.activated.key, 'enemy_despawn')
assert_equal(cancelled_run.response, 'run_away', 'enemy despawn cancellation must release run-away ownership')
assert_true(replacement_run == nil, 'enemy despawn cancellation must not leave stale reaction state')

run_ready = reactions.on_action({
    actor_id = 910,
    category = 7,
    targets = { { actions = { { param = 999 } } } },
}, 900, 3.8, true)
local reduced_payload = {
    version = 2,
    profile = payload.profile,
    config = {
        reactions = {
            enabled = true,
            rules = { rules[1], rules[2] },
        },
    },
}
local reduced_active = assert(active_config.build_active_profile_from_v2_payload(reduced_payload, meta))
assert_true(active_config.set_active_profile(reduced_active), 'reduced reaction profile must install')
local after_rule_reload, reload_released_target = reactions.evaluate(900, {}, 3.9)
assert_true(after_rule_reload == nil, 'profile reload must remove a reaction lock whose rule is no longer configured')
assert_equal(reload_released_target, 910, 'profile reload must expose the released movement actor to scheduler cleanup')
assert_true(active_config.set_active_profile(active), 'full reaction profile must reinstall after reload cleanup test')

local watch = reactions.effect_watch_set()
assert_true(watch[173] == true, 'configured enemy buff must resolve to the live Dread Spikes effect id')
local buff_lock = reactions.evaluate(900, { { effect_id = 173 } }, 4)
assert_equal(buff_lock.name, 'Dread Spikes', 'tracked enemy buff must activate stop-attacking lock')
assert_equal(buff_lock.response, 'stop_attacking', 'enemy buff response mismatch')
assert_true(reactions.requires_disengage(buff_lock, 1), 'stop-attacking must disengage an engaged player')
assert_true(not reactions.requires_disengage(buff_lock, 0), 'stop-attacking must not resend disengage after leaving combat')
assert_true(not reactions.blocks_movement(buff_lock), 'stop-attacking must preserve formation movement')
assert_true(reactions.blocks_movement(active_lock), 'turn-away must continue holding movement and facing')
assert_true(reactions.blocks_proposal(buff_lock, {
    provider = 'combat', action_type = 'ws', target_kind = 'mob', family_id = 'combat.ws.primary',
}), 'stop-attacking must reject melee offense')
assert_true(not reactions.blocks_proposal(buff_lock, {
    provider = 'defensive_internal', action_type = 'spell', target_kind = 'mob',
    family_id = 'def.enemy_dispel.primary', reason_code = 'enemy_buff_remove',
}), 'stop-attacking must allow the dedicated enemy-buff removal spell')
assert_true(not reactions.blocks_proposal(buff_lock, {
    provider = 'combat', action_type = 'spell', target_kind = 'mob', family_id = 'combat.tank_enmity.primary',
}), 'stop-attacking must allow configured tank enmity actions while disengaged')
local no_buff, released_target = reactions.evaluate(901, {}, 5)
assert_true(no_buff == nil, 'enemy buff stop-attacking lock must clear when its actor is no longer the current target')
assert_equal(released_target, 900, 'target-scoped enemy buff lock removal must request facing restoration')

local original_windower = rawget(_G, 'windower')
local tracked_mob = { id = 900, spawn_type = 16, hpp = 100 }
_G.windower = {
    addon_path = '',
    ffxi = {
        get_mob_by_id = function(id)
            if tonumber(id) == 900 then
                return tracked_mob
            end
            return nil
        end,
    },
}
package.loaded.uc_enemy_effect_tracker = nil
local tracker = require('uc_enemy_effect_tracker')
local tracked_set = { [33] = true, [173] = true }
package.loaded.uc_tb_effect_table = nil
local tb_effect_table = require('uc_tb_effect_table')
local function observe_catalog_action(action)
    local events = {}
    tb_effect_table.apply_from_action(action, 800, function(target_id, effect_id, source)
        local event = tracker.observe_effect(target_id, effect_id, source, tracked_set)
        if event then
            events[#events + 1] = event
        end
    end, function(target_id, effect_id)
        tracker.clear_effect(target_id, effect_id)
    end, 1)
    return events
end
for _, skill_id in ipairs({ 2675, 3342, 4188 }) do
    local catalog_events = observe_catalog_action({
        actor_id = 900,
        category = 11,
        param = skill_id,
        targets = { { id = 900, actions = { { message = 194, param = 0 } } } },
    })
    assert_equal(catalog_events[1].effect_id, 173, ('Dark Thorn skill %d must resolve to Dread Spikes'):format(skill_id))
    assert_equal(tracker.get_effects(900)[1].effect_id, 173, 'Dark Thorn catalog observation must enter the authoritative tracker')
    tracker.clear_all()
end
local dia_events = observe_catalog_action({
    actor_id = 900,
    category = 4,
    param = 23,
    targets = { { id = 900, actions = { { message = 2, param = 0 } } } },
})
assert_equal(#dia_events, 0, 'Dia catalog effects must not enter the authoritative dispellable-buff tracker')
assert_equal(#tracker.get_effects(900), 0, 'Dia must not create an enemy buff removal candidate')
local non_gain_events = tracker.on_action({
    actor_id = 900,
    targets = { { id = 900, actions = { { message = 2, param = 33 } } } },
}, tracked_set)
assert_equal(#non_gain_events, 0, 'non-gain action params must not be tracked as enemy buffs')
assert_equal(#tracker.get_effects(900), 0, 'non-gain action params must leave enemy buff state empty')
local non_gain_message_events = tracker.on_action_message({
    actor_id = 900, target_id = 900, message_id = 2, param_1 = 33,
}, tracked_set)
assert_equal(#non_gain_message_events, 0, 'enemy self-target messages must still require a gain-effect message')
assert_equal(#tracker.get_effects(900), 0, 'enemy self-target non-gain messages must leave enemy buff state empty')
local gain_events = tracker.on_action({
    actor_id = 900,
    targets = { { id = 900, actions = { { message = 194, param = 173 } } } },
}, tracked_set)
assert_equal(gain_events[1].effect_id, 173, 'Dark Thorn packet effect must enter the authoritative tracker')
tracker.on_action({
    actor_id = 900,
    targets = { { id = 900, actions = { { message = 194, param = 33 } } } },
}, tracked_set)
tracker.on_action_message({ actor_id = 900, target_id = 900, message_id = 341, param_1 = 33 }, tracked_set)
local after_other_dispel = tracker.get_effects(900)
assert_equal(#after_other_dispel, 1, 'removing another random enhancement must leave Dread Spikes tracked for retry')
assert_equal(after_other_dispel[1].effect_id, 173, 'Dread Spikes must remain tracked when Dispel removes another enhancement')
tracker.on_action_message({ actor_id = 900, target_id = 900, message_id = 341, param_1 = 173 }, tracked_set)
assert_equal(#tracker.get_effects(900), 0, 'confirmed Dread Spikes removal must clear the authoritative tracker')
tracker.on_action({
    actor_id = 900,
    targets = { { id = 900, actions = { { message = 194, param = 173 } } } },
}, tracked_set)
tracker.on_action_message({ actor_id = 900, target_id = 900, message_id = 6, param_1 = 0 }, tracked_set)
assert_equal(#tracker.get_effects(900), 0, 'death message 6 must clear all tracked effects for the mob')
tracker.on_action({
    actor_id = 900,
    targets = { { id = 900, actions = { { message = 194, param = 173 } } } },
}, tracked_set)
tracker.on_action({
    actor_id = 800,
    targets = { { id = 900, actions = { { message = 6, param = 0 } } } },
}, tracked_set)
assert_equal(#tracker.get_effects(900), 0, 'death results in action packets must clear all tracked effects for the mob')
tracker.on_action({
    actor_id = 900,
    targets = { { id = 900, actions = { { message = 194, param = 173 } } } },
}, tracked_set)
tracker.sweep_invalid()
assert_equal(#tracker.get_effects(900), 1, 'invalid-target sweep must preserve effects on a living enemy')
tracked_mob = { id = 900, spawn_type = 16, hpp = 0 }
tracker.sweep_invalid()
assert_equal(#tracker.get_effects(900), 0, 'invalid-target sweep must clear effects while the mob is dead')
tracked_mob = { id = 900, spawn_type = 16, hpp = 100 }
assert_equal(#tracker.get_effects(900), 0, 'a same-id respawn must start without stale tracked effects')
package.loaded.uc_enemy_effect_tracker = nil
package.loaded.uc_tb_effect_table = nil
_G.windower = original_windower

local source = assert(io.open('unified_scheduler.lua', 'rb')):read('*a')
local enemy_buff_provider_source = assert(io.open('uc_provider_enemy_buff_removal.lua', 'rb')):read('*a')
local enemy_effect_state_source = assert(io.open('uc_scheduler_enemy_effect_state.lua', 'rb')):read('*a')
local ranker_source = assert(io.open('uc_scheduler_ranker.lua', 'rb')):read('*a')
assert_true(enemy_effect_state_source:find('local dispellable_priority = {}', 1, true) ~= nil, 'enemy-effect state must own JSON dispel priorities')
assert_true(enemy_effect_state_source:find('local dispellable_set = {}', 1, true) ~= nil, 'enemy-effect state must own JSON dispel membership')
assert_true(enemy_effect_state_source:find('buff_ids record at byte %d has no danger_weight', 1, true) ~= nil, 'the JSON dispel catalog must reject records without a danger weight')
assert_true(source:find("is_dispellable = require('uc_scheduler_enemy_effect_state').is_dispellable", 1, true) ~= nil, 'scheduler must inject explicit JSON catalog membership into enemy dispel collection')
assert_true(enemy_buff_provider_source:find('if is_dispellable(eid) then', 1, true) ~= nil, 'enemy dispel collection must require explicit JSON catalog membership')
assert_true(ranker_source:find("reject_reason = 'reaction_hold'", 1, true) ~= nil, 'ranker must reject blocked proposals through reaction hold')
assert_true(source:find("UC_MOVEMENT_MODE = 'REACTION_HOLD'", 1, true) ~= nil, 'movement coordinator must hold while turned away')
assert_true(source:find("UC_MOVEMENT_MODE = 'REACTION_RUN_AWAY'", 1, true) ~= nil, 'movement coordinator must publish run-away ownership')
assert_true(source:find("UC_MOVEMENT_OWNER = 'scheduler_reaction'", 1, true) ~= nil, 'run-away must use scheduler movement ownership')
assert_true(source:find('reaction_movement_executor().stop({', 1, true) ~= nil, 'run-away completion must dispatch an explicit movement stop')
assert_true(source:find("if rawget(_G, 'Start_Engine') == true then", 1, true) ~= nil, 'ability reactions must not activate while the engine is stopped')
assert_true(source:find('scheduler.apply_reaction_response(reaction_event.activated)', 1, true) ~= nil, 'ready event must use response-specific scheduler ownership')
assert_true(source:find('scheduler.apply_reaction_turn({ actor_id = current_target_id }, false)', 1, true) ~= nil, 'completion must restore scheduler facing toward the current target')
assert_true(source:find('mark_enemy_dispel_attempt(tostring(dispel_detail.enemy_dispel_attempt_key), dispatch_now)', 1, true) ~= nil, 'enemy dispel retry cooldown must begin only after dispatch')
assert_true(enemy_buff_provider_source:find('for _, tracked_target in ipairs(tracked_targets) do', 1, true) ~= nil, 'enemy dispel collection must use the authoritative effect tracker')
assert_true(source:find('enemy_effect_tracker.sweep_invalid()', 1, true) ~= nil, 'every scheduler tick must sweep dead or despawned enemy effect targets')
assert_true(source:find('enemy_effect_tracker.observe_effect(target_id, effect_id, source, observed_effect_set)', 1, true) ~= nil, 'TargetBar catalog observations must feed the authoritative enemy effect tracker')

local before_reset_config = active_config.get_path({ 'config', 'reactions', 'rules', 1, 'name' })
reactions.reset('test')
assert_equal(active_config.get_path({ 'config', 'reactions', 'rules', 1, 'name' }), before_reset_config, 'runtime reset must not mutate durable reaction config')

io.stdout:write('selftest_reaction_runtime: OK\n')
