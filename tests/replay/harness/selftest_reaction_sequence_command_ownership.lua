local function reset(name)
    package.loaded[name] = nil
    package.preload[name] = nil
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message or 'assertion failed', tostring(expected), tostring(actual)))
    end
end

local now_value = 123.5
reset('uc_time')
package.preload.uc_time = function()
    return { now = function() return now_value end }
end

local lock = {
    key = 'ability_window:900:just desserts',
    trigger = 'ability_window',
    name = 'Just Desserts',
    response = 'use_sequence',
    actor_id = 900,
    action_type = 'ja',
    action_name = 'Elemental Seal',
    action_target = 'self',
    action_optional = true,
    step_index = 1,
    step_count = 2,
}
local marked = {}
reset('uc_reaction_runtime')
package.preload.uc_reaction_runtime = function()
    return {
        get_action_lock = function() return lock end,
        note_sequence_action_dispatched = function(key, action_type, action_name, target_kind, target_id, player_id, at)
            marked[#marked + 1] = {
                key = key,
                action_type = action_type,
                action_name = action_name,
                target_kind = target_kind,
                target_id = target_id,
                player_id = player_id,
                at = at,
            }
            return true, 'dispatched'
        end,
        cancel = function() error('sequence dispatch must not cancel reaction lock') end,
    }
end

local old_windower = rawget(_G, 'windower')
_G.windower = {
    ffxi = {
        get_player = function() return { id = 1, name = 'Etamame' } end,
    },
}

reset('uc_scheduler_command_ownership')
local ownership = require('uc_scheduler_command_ownership')
local sends = {}
local dispatcher = {
    dispatch_intent = function(intent, deps)
        deps.send_command(intent.command)
        return { ok = true, executed = true, reason = 'executed' }
    end,
}
local status = ownership.apply_command_ownership({
    dispatcher = dispatcher,
    send_command = function(command) sends[#sends + 1] = command end,
    intent = {
        kind = 'send_command',
        command = 'input /ja "Elemental Seal" <me>',
        meta = {
            action_type = 'ja',
            action_name = 'Elemental Seal',
            target_kind = 'self',
        },
    },
    command = 'input /ja "Elemental Seal" <me>',
})
assert_equal(status.dispatch_ok, true, 'sequence setup dispatch status')
assert_equal(status.reaction_released, false, 'sequence setup dispatch must retain reaction lock')
assert_equal(status.reaction_sequence_step_dispatched, true, 'sequence setup dispatch marker')
assert_equal(#marked, 1, 'sequence dispatch mark count')
assert_equal(marked[1].target_id, 1, 'self target id must resolve to player id')
assert_equal(marked[1].player_id, 1, 'local actor id must be captured')
assert_equal(marked[1].at, now_value, 'sequence dispatch must use canonical UC clock')

lock = {
    key = 'ability_window:900:just desserts',
    trigger = 'ability_window',
    name = 'Just Desserts',
    response = 'use_sequence',
    actor_id = 900,
    action_type = 'spell',
    action_name = 'Stun',
    action_target = 'actor',
    action_optional = false,
    step_index = 2,
    step_count = 2,
}
status = ownership.apply_command_ownership({
    dispatcher = dispatcher,
    send_command = function(command) sends[#sends + 1] = command end,
    intent = {
        kind = 'send_command',
        command = 'input /ma "Stun" 900',
        meta = {
            action_type = 'spell',
            action_name = 'Stun',
            target_kind = 'mob',
            target_id = 900,
        },
    },
    command = 'input /ma "Stun" 900',
})
assert_equal(status.dispatch_ok, true, 'sequence terminal dispatch status')
assert_equal(status.reaction_released, false, 'terminal dispatch must wait for action completion before release')
assert_equal(status.reaction_sequence_step_dispatched, true, 'terminal dispatch marker')
assert_equal(#marked, 2, 'terminal dispatch mark count')
assert_equal(marked[2].target_id, 900, 'Stun target id')

_G.windower = old_windower
print('selftest_reaction_sequence_command_ownership: PASS')
