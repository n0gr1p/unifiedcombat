local function assert_true(value, message)
    if value ~= true then error(message or 'expected true') end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
    end
end

local lock = {
    key = 'ability_window:900:just desserts',
    response = 'use_sequence',
    name = 'Just Desserts',
    actor_id = 900,
    step_index = 1,
    step_state = 'pending',
    action_optional = false,
}
local cancel_reason = nil

package.loaded.uc_reaction_runtime = nil
package.preload.uc_reaction_runtime = function()
    return {
        get_action_lock = function() return lock end,
        cancel = function(_, reason)
            cancel_reason = reason
            lock = nil
            return true
        end,
    }
end

local fake_base = {}
function fake_base.new()
    return {
        collect_priority_offense = function(_, out)
            if lock ~= nil then
                -- Simulate the existing sequence collector finding a required
                -- first step unavailable and reserving the lane without a proposal.
                return true
            end
            out[#out + 1] = { family_id = 'combat.normal' }
            return true
        end,
    }
end

package.loaded.uc_combat_extensions_once = nil
local wrapped = require('uc_combat_extensions_once').wrap(fake_base)
local api = wrapped.new({})
local out = {}
api.collect_priority_offense({}, out)
assert_equal(cancel_reason, 'required_opener_unavailable',
    'required unavailable sequence opener must cancel instead of holding the lane')
assert_equal(#out, 1, 'collector must retry ordinary combat in same tick after opener cancellation')
assert_equal(out[1].family_id, 'combat.normal', 'fail-open retry must expose ordinary combat proposal')

lock = {
    key = 'ability_window:900:test',
    response = 'use_sequence',
    actor_id = 900,
    step_index = 2,
    step_state = 'pending',
    action_optional = false,
}
cancel_reason = nil
out = {}
api.collect_priority_offense({}, out)
assert_true(cancel_reason == nil, 'later required sequence steps must retain existing reserved-lane retry behavior')
assert_equal(#out, 0, 'later unavailable required step must remain atomic')

lock = {
    key = 'ability_window:900:test-optional',
    response = 'use_sequence',
    actor_id = 900,
    step_index = 1,
    step_state = 'pending',
    action_optional = true,
}
cancel_reason = nil
out = {}
api.collect_priority_offense({}, out)
assert_true(cancel_reason == nil, 'optional first step must remain owned by normal sequence optional-step handling')

print('selftest_reaction_sequence_fail_open: OK')
