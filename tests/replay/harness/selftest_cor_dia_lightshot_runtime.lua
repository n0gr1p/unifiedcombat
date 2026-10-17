local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
    end
end

local previous_cor = package.loaded['uc_cor_maintenance']
local previous_tracker = package.loaded['uc_enemy_effect_tracker']
local previous_reaction = package.loaded['uc_reaction_runtime']
local previous_ownership = package.loaded['uc_scheduler_command_ownership']

local target = { id = 17100979, name = 'Marsh Murre' }
local effects = {}
local dispatches = 0
local sends = {}

package.loaded['uc_cor_maintenance'] = {
    resolve_pending_light_shot_target = function()
        return target
    end,
}
package.loaded['uc_enemy_effect_tracker'] = {
    get_effects = function(target_id)
        if tonumber(target_id) ~= tonumber(target.id) then
            return {}
        end
        return effects
    end,
}
package.loaded['uc_reaction_runtime'] = {
    get_action_lock = function()
        return nil
    end,
}
package.loaded['uc_scheduler_command_ownership'] = nil
local ownership = require('uc_scheduler_command_ownership')

local dispatcher = {
    dispatch_intent = function(intent, deps)
        dispatches = dispatches + 1
        deps.send_command(intent.command)
        return { ok = true, executed = true, reason = 'executed' }
    end,
}
local send_command = function(command)
    sends[#sends + 1] = command
end

local function light_shot_intent()
    return {
        kind = 'send_command',
        command = 'input /ja "Light Shot" <me>',
        meta = {
            provider = 'maintenance_cor',
            action_type = 'ja',
            action_name = 'Light Shot',
            target_kind = 'enemy',
            target_id = target.id,
            target_name = target.name,
        },
    }
end

local function apply()
    local intent = light_shot_intent()
    return ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send_command,
        intent = intent,
        command = intent.command,
    })
end

-- Bind (or any non-Dia debuff) must never authorize Light Shot.
effects = { { effect_id = 11, seen_at = 10 } }
local status = apply()
assert_equal(status.dispatch_ok, true, 'Bind false positive should be a safe no-op')
assert_equal(status.dispatch_reason, 'cor_light_shot_dia_not_tracked', 'Bind must fail tracked-Dia gate')
assert_equal(dispatches, 0, 'Bind must not dispatch Light Shot')

-- A tracked Dia generation authorizes exactly one dispatch.
effects = { { effect_id = 134, seen_at = 20 } }
status = apply()
assert_equal(status.dispatch_ok, true, 'tracked Dia should dispatch')
assert_equal(status.dispatched, true, 'tracked Dia should reach dispatcher')
assert_equal(dispatches, 1, 'first Dia generation should dispatch once')
assert_equal(sends[1], 'input /ja "Light Shot" <t>', 'Light Shot must target current enemy')

-- Same Dia generation remains consumed even when Quick Draw becomes available again.
status = apply()
assert_equal(status.dispatch_ok, true, 'consumed Dia should be a safe no-op')
assert_equal(status.dispatch_reason, 'cor_light_shot_dia_already_handled', 'same Dia generation must remain consumed')
assert_equal(dispatches, 1, 'same Dia generation must not dispatch twice')

-- A fresh Dia application has a new tracker timestamp/generation and may fire once.
effects = { { effect_id = 134, seen_at = 30 } }
status = apply()
assert_equal(status.dispatch_ok, true, 'fresh Dia should dispatch')
assert_equal(status.dispatched, true, 'fresh Dia should reach dispatcher')
assert_equal(dispatches, 2, 'fresh Dia generation should permit one new shot')

package.loaded['uc_scheduler_command_ownership'] = previous_ownership
package.loaded['uc_cor_maintenance'] = previous_cor
package.loaded['uc_enemy_effect_tracker'] = previous_tracker
package.loaded['uc_reaction_runtime'] = previous_reaction

-- The real COR provider stages a target-scoped Dia proposal. The later
-- command-ownership resolution must reject a changed canonical setting,
-- preserving observed Dia so re-enabling can stage a fresh proposal.
do
    local old_resources = package.loaded.resources
    local old_time = package.loaded.uc_time
    local old_active = package.loaded.uc_active_config
    local old_cor_module = package.loaded.uc_cor_maintenance
    local old_windower = windower
    local old_string_unpack = string.unpack
    local old_flat = rawget(_G, 'UC_SETTINGS')
    local active_config = { maintenance = { cor = { light_shot_dia = true } } }
    local mob = {
        id = 555, name = 'Light Shot Target', spawn_type = 16,
        valid_target = true, hpp = 100,
        distance = { sqrt = function() return 4 end },
    }
    package.loaded.resources = { job_abilities = { [131] = { recast_id = 193 } } }
    package.loaded.uc_time = { now = function() return 10 end }
    package.loaded.uc_active_config = { get_config = function() return active_config end }
    package.loaded.uc_cor_maintenance = nil
    windower = {
        ffxi = {
            get_player = function() return { main_job = 'COR', sub_job = 'NIN', status = 1, buffs = {} } end,
            get_mob_by_target = function(slot)
                return slot == 'me' and { id = 100 } or mob
            end,
            get_ability_recasts = function() return { [193] = 0 } end,
        },
        packets = {
            parse_action = function()
                return {
                    actor_id = 200, category = 4, param = 23,
                    targets = { { id = mob.id, actions = { { message = 2 } } } },
                }
            end,
        },
    }
    -- Incoming test packet belongs to another caster; its Dia observation
    -- should still be tracked without triggering local COR busy state.
    string.unpack = function() return 200 end
    local live = require('uc_cor_maintenance')
    live.update_from_incoming_chunk(0x028, 'mock_packet')
    local proposed = live.propose(active_config)
    assert_equal(proposed.action_name, 'Light Shot',
        'observed Dia must produce configured COR Light Shot proposal')
    assert_equal(live.resolve_pending_light_shot_target(active_config).id, mob.id,
        'current valid Dia generation authorizes staged target')

    rawset(_G, 'UC_SETTINGS', { cor_light_shot_dia = true })
    active_config.maintenance.cor.light_shot_dia = false
    assert_equal(live.resolve_pending_light_shot_target(active_config), nil,
        'canonical COR OFF rejects stale flat ON at command ownership')
    active_config.maintenance.cor.light_shot_dia = true
    assert_equal(live.resolve_pending_light_shot_target(active_config), nil,
        'disabled policy retires the old cached target/generation')
    proposed = live.propose(active_config)
    assert_equal(proposed.action_name, 'Light Shot',
        'observed Dia remains available after policy-only cancellation')
    rawset(_G, 'UC_SETTINGS', { cor_light_shot_dia = false })
    assert_equal(live.resolve_pending_light_shot_target(active_config).id, mob.id,
        'canonical COR ON defeats stale flat OFF at dispatch')
    active_config = nil
    assert_equal(live.resolve_pending_light_shot_target(active_config).id, mob.id,
        'genuine no-profile compatibility retains pre-profile target resolution')
    string.unpack = old_string_unpack
    windower = old_windower
    rawset(_G, 'UC_SETTINGS', old_flat)
    package.loaded.resources = old_resources
    package.loaded.uc_time = old_time
    package.loaded.uc_active_config = old_active
    package.loaded.uc_cor_maintenance = old_cor_module
end

io.stdout:write('selftest_cor_dia_lightshot_runtime: OK\n')
