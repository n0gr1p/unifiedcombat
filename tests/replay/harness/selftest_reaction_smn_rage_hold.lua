local function assert_true(value, message)
    if value ~= true then error(message or 'expected true') end
end

local function assert_false(value, message)
    if value ~= false then error(message or 'expected false') end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
    end
end

local source_available = true
local rule = {
    trigger = 'party_action_complete',
    source_name = 'Etamame',
    action_type = 'spell',
    name = 'Indi-Malaise',
    response = 'use_sequence',
    once_per_instance = true,
    hold_smn_rage_until_sequence_complete = true,
    steps = {
        { action_type = 'ja', action_name = 'Astral Flow', target = 'self', optional = false },
        { action_type = 'ja', action_name = 'Astral Conduit', target = 'self', optional = false },
    },
}

package.loaded.uc_combat_extension_config = nil
package.preload.uc_combat_extension_config = function()
    return {
        reaction_rules = function() return { rule } end,
    }
end

package.loaded.uc_party_action_event = nil
package.preload.uc_party_action_event = function()
    return {
        party_member_actor_id = function(name)
            if source_available and name == 'Etamame' then return 200 end
            return 0
        end,
    }
end

local mode = 'idle'
local active_lock = nil
local fake_base = {}

function fake_base.on_action()
    if mode == 'activate' then
        active_lock = {
            key = 'party_action_complete:900:etamame:spell:indi-malaise',
            trigger = 'party_action_complete',
            name = 'Indi-Malaise',
            response = 'use_sequence',
            actor_id = 900,
            event_actor_id = 200,
            event_actor_name = 'Etamame',
            completed_action_type = 'spell',
            completed_action_name = 'Indi-Malaise',
            rule_index = 1,
        }
        return { activated = active_lock }
    end
    if mode == 'complete' then
        local released = active_lock
        active_lock = nil
        return { released = released, sequence_step_completed = true }
    end
    return {}
end

function fake_base.cancel(_, reason)
    local released = active_lock
    active_lock = nil
    if released then released.cancel_reason = reason end
    return released, nil
end

function fake_base.prune_invalid_ability_windows()
    return nil
end

function fake_base.reset()
    active_lock = nil
    return nil
end

function fake_base.status()
    return { active = {} }
end

package.loaded.uc_reaction_smn_rage_gate = nil
local gate = require('uc_reaction_smn_rage_gate')
local reactions = gate.extend(fake_base)

local held, reason, detail = gate.should_hold(900)
assert_true(held, 'configured party reaction must hold Rage before trigger')
assert_equal(reason, 'reaction_pretrigger_hold', 'pre-trigger hold reason')
assert_equal(detail.source_name, 'Etamame', 'hold source name')

source_available = false
held, reason = gate.should_hold(900)
assert_false(held, 'missing trigger source must fail open')
assert_equal(reason, 'reaction_source_unavailable', 'missing source reason')
source_available = true

mode = 'activate'
local activated = reactions.on_action({}, 900, 1.0, false)
assert_true(type(activated.activated) == 'table', 'trigger must activate sequence')
held, reason = gate.should_hold(900)
assert_true(held, 'Rage must remain held while AFAC sequence is active')
assert_equal(reason, 'reaction_pretrigger_hold', 'active sequence remains held')

mode = 'complete'
local completed = reactions.on_action({}, 900, 2.0, false)
assert_true(type(completed.released) == 'table', 'terminal completion must release sequence')
held, reason = gate.should_hold(900)
assert_false(held, 'terminal sequence completion must release Rage')
assert_equal(reason, 'reaction_sequence_released', 'completed release reason')
assert_equal(reactions.status().smn_rage_gate.released_count, 1, 'released gate count')

mode = 'activate'
reactions.on_action({}, 901, 3.0, false)
-- The fake lock always uses actor 900; reset so cancellation can exercise a fresh instance cleanly.
reactions.reset('test-reset')
held = gate.should_hold(901)
assert_true(held, 'new enemy instance must begin held')

mode = 'activate'
local second = reactions.on_action({}, 901, 4.0, false)
second.activated.actor_id = 901
active_lock.actor_id = 901
-- Re-feed the corrected activation shape so the gate owns actor 901.
mode = 'idle'
reactions.reset('actor-correction')
active_lock = second.activated
mode = 'activate'
fake_base.on_action = function()
    return { activated = active_lock }
end
reactions.on_action({}, 901, 4.1, false)
local released = reactions.cancel(active_lock.key, 'required_opener_unavailable')
assert_true(type(released) == 'table', 'cancel must return released lock')
held, reason = gate.should_hold(901)
assert_false(held, 'sequence cancellation must fail open Rage')
assert_equal(reason, 'reaction_sequence_released', 'cancel release reason')

reactions.prune_invalid_ability_windows(function(actor_id)
    return tonumber(actor_id) ~= 900 and tonumber(actor_id) ~= 901
end)
assert_equal(reactions.status().smn_rage_gate.released_count, 0, 'invalid enemy cleanup must clear released state')
held = gate.should_hold(900)
assert_true(held, 'cleared/reused enemy instance must re-arm hold')

print('selftest_reaction_smn_rage_hold: OK')
