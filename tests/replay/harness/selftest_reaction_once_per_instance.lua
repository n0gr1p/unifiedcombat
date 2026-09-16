local function assert_true(value, message)
    if value ~= true then error(message or 'expected true') end
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
            [777] = { id = 777, en = 'Just Desserts' },
        },
    }
end

local rule = {
    trigger = 'ability_window',
    name = 'Just Desserts',
    response = 'use_sequence',
    once_per_instance = true,
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

local active_lock = nil
local fake_base = {}

function fake_base.on_action(act)
    if tonumber(act.category) == 7 then
        active_lock = {
            key = 'ability_window:' .. tostring(act.actor_id) .. ':just desserts',
            response = 'use_sequence',
            name = 'Just Desserts',
            actor_id = act.actor_id,
            step_index = 1,
            step_state = 'pending',
        }
        return { activated = active_lock }
    end
    return {}
end

function fake_base.note_sequence_action_dispatched()
    if active_lock == nil then return false, 'missing' end
    active_lock.step_state = 'dispatched'
    return true, 'dispatched'
end

function fake_base.cancel(key)
    local released = active_lock
    active_lock = nil
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
    return { active = active_lock and { active_lock } or {} }
end

package.loaded.uc_reaction_once_runtime = nil
local reactions = require('uc_reaction_once_runtime').extend(fake_base)

local ready = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 777 } } } },
}, 900, 1.0, true)
assert_true(type(ready.activated) == 'table', 'first ability must activate one-shot sequence')

local duplicate_pending = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 777 } } } },
}, 900, 1.1, true)
assert_true(duplicate_pending.once_per_instance_suppressed == true,
    'same one-shot reaction must not reactivate while first activation is pending')

local marked = reactions.note_sequence_action_dispatched(
    ready.activated.key, 'ja', 'Astral Flow', 'self', 1, 1, 1.2
)
assert_true(marked == true, 'first sequence dispatch must succeed')
assert_equal(reactions.status().once_per_instance.consumed_count, 1,
    'first successful dispatch must consume one-shot reaction for actor instance')

local duplicate_consumed = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 777 } } } },
}, 900, 1.3, true)
assert_true(duplicate_consumed.once_per_instance_suppressed == true,
    'same actor instance must suppress later matching abilities after consumption')

reactions.prune_invalid_ability_windows(function(actor_id)
    return actor_id ~= 900
end)
assert_equal(reactions.status().once_per_instance.consumed_count, 0,
    'despawned actor must release one-shot consumption state')

local reused_actor = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 777 } } } },
}, 900, 2.0, true)
assert_true(type(reused_actor.activated) == 'table',
    'new mob instance reusing actor id must be able to trigger after invalidation cleanup')

reactions.cancel(reused_actor.activated.key, 'required_opener_unavailable')
assert_equal(reactions.status().once_per_instance.consumed_count, 0,
    'cancelled sequence before first dispatch must not consume its one-shot')

local retry_after_cancel = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 777 } } } },
}, 900, 2.1, true)
assert_true(type(retry_after_cancel.activated) == 'table',
    'failed opener must leave one-shot eligible for a later matching ability')

reactions.reset('test')
assert_equal(reactions.status().once_per_instance.consumed_count, 0, 'reset must clear consumed state')
assert_equal(reactions.status().once_per_instance.pending_count, 0, 'reset must clear pending state')

print('selftest_reaction_once_per_instance: OK')
