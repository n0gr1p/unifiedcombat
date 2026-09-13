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

io.stdout:write('selftest_cor_dia_lightshot_runtime: OK\n')
