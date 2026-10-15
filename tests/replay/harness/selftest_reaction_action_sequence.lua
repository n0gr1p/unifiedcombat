local function reset(name)
    package.loaded[name] = nil
    package.preload[name] = nil
end

local function assert_true(value, message)
    if value ~= true then
        error(message or 'expected true')
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message or 'assertion failed', tostring(expected), tostring(actual)))
    end
end

local rule_enabled = true
local sequence_rule = {
    trigger = 'ability_window',
    name = 'Just Desserts',
    response = 'use_sequence',
    steps = {
        { action_type = 'ja', action_name = 'Elemental Seal', target = 'self', optional = true },
        { action_type = 'spell', action_name = 'Stun', target = 'actor', optional = false },
    },
}

local function resource_set(rows)
    local out = rows or {}
    function out:with(field, value)
        for _, row in pairs(self) do
            if type(row) == 'table' and row[field] == value then
                return row
            end
        end
        return nil
    end
    return out
end

reset('resources')
package.preload.resources = function()
    return {
        monster_abilities = resource_set({ [100] = { id = 100, en = 'Just Desserts' } }),
        job_abilities = resource_set({ [200] = { id = 200, en = 'Elemental Seal', range = 0 } }),
        spells = resource_set({ [300] = { id = 300, en = 'Stun', range = 12 } }),
    }
end

reset('uc_combat_extension_config')
package.preload.uc_combat_extension_config = function()
    return {
        reaction_rules = function() return rule_enabled and { sequence_rule } or {} end,
        validate_action_rule = function() return true end,
    }
end

local defensive_lock = nil
local base = {
    on_action = function() return {} end,
    evaluate = function() return defensive_lock, nil end,
    prune_invalid_ability_windows = function() return nil end,
    get_action_lock = function() return nil end,
    blocks_proposal = function() return false end,
    blocks_movement = function() return false end,
    owns_movement = function() return false end,
    requires_disengage = function() return false end,
    cancel = function() return nil, nil end,
    reset = function() return nil end,
    status = function() return { enabled = true, rule_count = 1, active = defensive_lock and { defensive_lock } or {}, last_transition = 'base' } end,
}

reset('uc_reaction_sequence_runtime')
local reactions = require('uc_reaction_sequence_runtime').extend(base)
local ready = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 10.0, true)
assert_equal(ready.activated.response, 'use_sequence', 'sequence activation response')
assert_equal(ready.activated.action_name, 'Elemental Seal', 'first sequence action')
assert_true(ready.activated.action_optional, 'Elemental Seal must be optional')
assert_equal(ready.activated.step_index, 1, 'first sequence step index')
assert_true(reactions.blocks_movement(ready.activated), 'atomic sequence must freeze normal movement immediately')

assert_true(reactions.blocks_proposal(ready.activated, {
    provider = 'defensive_internal',
    family_id = 'defensive.cure',
    action_type = 'spell',
    action_name = 'Cure V',
    target_kind = 'party',
}), 'atomic sequence must block ordinary support work')

local skipped, skip_reason = reactions.skip_optional_step(ready.activated.key, 'recast')
assert_equal(skip_reason, 'skipped', 'optional step skip reason')
assert_equal(skipped.action_name, 'Stun', 'optional setup skip must advance to Stun')
assert_equal(skipped.step_index, 2, 'optional setup skip step index')
assert_true(skipped.action_optional == false, 'Stun must be required')

reactions.reset('restart')
ready = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 20.0, true)
local marked, mark_reason = reactions.note_sequence_action_dispatched(
    ready.activated.key, 'ja', 'Elemental Seal', 'self', 1, 1, 20.1
)
assert_true(marked, 'Elemental Seal dispatch must be accepted')
assert_equal(mark_reason, 'dispatched', 'Elemental Seal dispatch reason')
assert_equal(reactions.get_action_lock().step_state, 'dispatched', 'sequence must hold while JA is in flight')

local ja_complete = reactions.on_action({ actor_id = 1, category = 6, param = 200 }, 900, 20.5, false)
assert_true(ja_complete.sequence_step_completed, 'Elemental Seal completion must advance sequence')
assert_equal(ja_complete.activated.action_name, 'Stun', 'JA completion must expose Stun')
assert_equal(ja_complete.activated.step_index, 2, 'JA completion step index')

marked = reactions.note_sequence_action_dispatched(
    ja_complete.activated.key, 'spell', 'Stun', 'mob', 900, 1, 20.6
)
assert_true(marked, 'Stun dispatch must be accepted')
assert_equal(reactions.get_action_lock().step_state, 'dispatched', 'sequence must hold while Stun is in flight')

local stun_complete = reactions.on_action({ actor_id = 1, category = 4, param = 300 }, 900, 21.0, false)
assert_true(stun_complete.sequence_step_completed, 'Stun completion must complete sequence')
assert_true(type(stun_complete.released) == 'table', 'terminal Stun completion must release sequence')
assert_true(reactions.get_action_lock() == nil, 'terminal completion must clear action lock')

ready = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 30.0, true)
local window_complete = reactions.on_action({ actor_id = 900, category = 11, param = 100 }, 900, 30.4, true)
assert_true(type(window_complete.released) == 'table', 'enemy ability completion must abort/release active sequence')
assert_true(reactions.get_action_lock() == nil, 'ability-window completion must clear sequence lock')

-- Pet-command sequence steps are dispatched by the shared pet coordinator and
-- advance only when that coordinator confirms the pet is on the requested actor.
sequence_rule.steps = {
    { action_type = 'pet', action_name = 'Assault', target = 'actor', optional = false },
}
reactions.reset('pet_test')
ready = reactions.on_action({
    actor_id = 900,
    category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 35.0, true)
assert_equal(ready.activated.action_type, 'pet', 'pet sequence action type')
assert_equal(ready.activated.action_name, 'Assault', 'pet sequence action name')
assert_true(not reactions.blocks_proposal(ready.activated, {
    provider = 'pet_combat',
    family_id = 'combat.reaction.sequence',
    action_type = 'pet',
    action_name = 'Assault',
    target_kind = 'mob',
    target_id = 900,
}), 'reaction lock must admit its exact pet proposal')
marked = reactions.note_sequence_action_dispatched(
    ready.activated.key, 'pet', 'Assault', 'mob', 900, 200, 35.1
)
assert_true(marked, 'Assault dispatch must be accepted')
assert_equal(reactions.get_action_lock().step_state, 'dispatched', 'pet sequence holds while Assault is pending')
local pet_complete, pet_complete_reason = reactions.note_sequence_pet_command_completed(
    ready.activated.key, 'Assault', 900, 200, 'pet_engaged_observed'
)
assert_equal(pet_complete_reason, 'sequence_complete', 'terminal Assault completes reaction sequence')
assert_true(type(pet_complete) == 'table', 'pet completion returns released sequence')
assert_true(reactions.get_action_lock() == nil, 'pet completion clears terminal sequence lock')

sequence_rule.steps = {
    { action_type = 'ja', action_name = 'Elemental Seal', target = 'self', optional = true },
    { action_type = 'spell', action_name = 'Stun', target = 'actor', optional = false },
}

-- Mid-sequence Profile V2 edits must release stale locks, not just block
-- follow-up dispatch. No unrelated defensive reaction state is reset.
reactions.reset('policy_pruning')
ready = reactions.on_action({
    actor_id = 900, category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 40.0, true)
assert_true(type(ready.activated) == 'table', 'policy test sequence activates')
marked = reactions.note_sequence_action_dispatched(
    ready.activated.key, 'ja', 'Elemental Seal', 'self', 1, 1, 40.1
)
assert_true(marked, 'policy test opener dispatched')
local completed = reactions.on_action({ actor_id = 1, category = 6, param = 200 }, 900, 40.2, false)
assert_equal(completed.activated.action_name, 'Stun', 'packet completion must advance before policy change')
rule_enabled = false
local released = reactions.prune_invalid_ability_windows(function() return true end)
assert_equal(released.key, ready.activated.key, 'canonical disable releases copied sequence lock')
assert_true(reactions.get_action_lock() == nil, 'disabled sequence cannot reserve action lane')
assert_equal(#reactions.status().active, 0, 'disabled rule clears sequence status')
rule_enabled = true

ready = reactions.on_action({
    actor_id = 900, category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 41.0, true)
sequence_rule.steps[2].action_name = 'Sleep II'
local dropped = reactions.evaluate(900, {}, 41.1)
assert_true(dropped == nil, 'edited second step invalidates copied active sequence on evaluate')
assert_true(reactions.get_action_lock() == nil, 'edited rule releases action lane immediately')
sequence_rule.steps[2].action_name = 'Stun'

ready = reactions.on_action({
    actor_id = 900, category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 42.0, true)
sequence_rule.steps[1].optional = false
assert_true(reactions.get_action_lock() == nil, 'optional-step policy edit releases cached sequence')
sequence_rule.steps[1].optional = true

-- A reconfigured sequence must not clear an unrelated defensive turn-away
-- reaction. Only sequence-owned state is released by policy pruning.
defensive_lock = {
    key = 'ability_window:901:cold stare', trigger = 'ability_window',
    response = 'turn_away', name = 'Cold Stare', actor_id = 901,
}
ready = reactions.on_action({
    actor_id = 900, category = 7,
    targets = { { actions = { { param = 100 } } } },
}, 900, 43.0, true)
rule_enabled = false
local defense_continues = reactions.evaluate(900, {}, 43.1)
assert_equal(defense_continues.key, defensive_lock.key,
    'disabling sequence leaves active unrelated defensive reaction intact')
assert_true(reactions.get_action_lock() == nil,
    'defensive turn-away is not misclassified as a stale sequence action')
assert_equal(#reactions.status().active, 1, 'defensive lock remains in status after sequence cleanup')
rule_enabled = true
defensive_lock = nil

-- Provider wrapper: unavailable optional Elemental Seal must be skipped immediately
-- and required Stun must still be emitted in the same collection pass.
local provider_lock = {
    key = 'sequence:test', response = 'use_sequence', name = 'Just Desserts', actor_id = 900,
    step_index = 1, step_count = 2, step_state = 'pending',
    action_type = 'ja', action_name = 'Elemental Seal', action_target = 'self', action_optional = true,
}
local skip_calls = 0
reset('uc_reaction_runtime')
package.preload.uc_reaction_runtime = function()
    return {
        get_action_lock = function() return provider_lock end,
        skip_optional_step = function()
            skip_calls = skip_calls + 1
            provider_lock = {
                key = 'sequence:test', response = 'use_sequence', name = 'Just Desserts', actor_id = 900,
                step_index = 2, step_count = 2, step_state = 'pending',
                action_type = 'spell', action_name = 'Stun', action_target = 'actor', action_optional = false,
            }
            return provider_lock, 'skipped'
        end,
    }
end

local fake_base_extensions = {
    new = function()
        return { collect_priority_offense = function() return false end }
    end,
}
reset('uc_combat_extensions_sequence')
local sequence_extensions = require('uc_combat_extensions_sequence').wrap(fake_base_extensions)
local api = sequence_extensions.new({
    action_ready = function(name)
        if name == 'Elemental Seal' then
            return false, 'recast', 'ja'
        end
        if name == 'Stun' then
            return true, '', 'spell'
        end
        return false, 'unknown', 'none'
    end,
    action_effective_range = function() return 20 end,
})
local old_windower = rawget(_G, 'windower')
_G.windower = {
    ffxi = {
        get_mob_by_id = function(id)
            if tonumber(id) == 900 then
                return { id = 900, name = 'Zerde' }
            end
            return nil
        end,
    },
}
local out = {}
local claimed = api.collect_priority_offense({
    now = 40.0,
    player = { id = 1, name = 'Etamame' },
}, out)
assert_true(claimed, 'sequence provider must reserve priority offense path')
assert_equal(skip_calls, 1, 'unavailable optional setup must be skipped exactly once')
assert_equal(#out, 1, 'required Stun must still be proposed')
assert_equal(out[1].action_name, 'Stun', 'required terminal action after optional skip')
assert_equal(out[1].target_name, 'Zerde', 'actor-targeted sequence proposal must name the actor, not the triggering ability')
assert_equal(out[1].family_id, 'combat.reaction.sequence', 'sequence proposal family')

provider_lock = {
    key = 'sequence:pet', response = 'use_sequence', name = 'Just Desserts', actor_id = 900,
    step_index = 1, step_count = 1, step_state = 'pending',
    action_type = 'pet', action_name = 'Assault', action_target = 'actor', action_optional = false,
}
out = {}
claimed = api.collect_priority_offense({
    now = 41.0,
    player = { id = 1, name = 'Terrasjr' },
    pet_present = true,
    pet_id = 200,
    combat_generation = 4,
}, out)
assert_true(claimed, 'pet sequence provider must reserve priority offense path')
assert_equal(#out, 1, 'pet sequence proposal count')
assert_equal(out[1].provider, 'pet_combat', 'pet sequence must use shared pet provider')
assert_equal(out[1].action_type, 'pet', 'pet sequence proposal action type')
assert_equal(out[1].action_name, 'Assault', 'pet sequence proposal action name')
assert_equal(out[1].target_id, 900, 'pet sequence proposal target')
assert_equal(out[1].detail.pet_command.kind, 'assault', 'pet sequence command kind')
assert_equal(out[1].detail.pet_command.pet_id, 200, 'pet sequence command pet id')
assert_equal(out[1].detail.pet_command.combat_generation, 4, 'pet sequence command combat generation')
assert_equal(out[1].detail.pet_command.reaction_key, 'sequence:pet', 'pet sequence command reaction correlation')
_G.windower = old_windower

local scheduler_source = assert(io.open('unified_scheduler.lua', 'rb')):read('*a')
assert_true(
    scheduler_source:find("if response == 'use_action' or response == 'use_sequence' then", 1, true) ~= nil,
    'scheduler activation handler must accept action-bearing reaction responses'
)

-- Normalizer wrapper must preserve durable sequence shape while allowing the
-- legacy normalizer to process the rest of the profile unchanged.
reset('uc_config_normalizer_sequence')
local saw_placeholder = false
local fake_normalizer = {
    normalize = function(settings)
        local rules = settings.config.reactions.rules
        saw_placeholder = rules[1].response == 'turn_away'
        return {
            reactions = {
                enabled = true,
                rules = {
                    { trigger = 'ability_window', name = 'Just Desserts', response = 'turn_away' },
                },
            },
        }
    end,
    version = function() return 2 end,
}
local normalizer = require('uc_config_normalizer_sequence').wrap(fake_normalizer)
local normalized = normalizer.normalize({
    config = { reactions = { enabled = true, rules = { sequence_rule } } },
})
assert_true(saw_placeholder, 'base normalizer must receive a compatible placeholder')
assert_equal(normalized.reactions.rules[1].response, 'use_sequence', 'sequence response must be restored')
assert_equal(normalized.reactions.rules[1].steps[1].action_name, 'Elemental Seal', 'sequence setup step persistence')
assert_equal(normalized.reactions.rules[1].steps[2].action_name, 'Stun', 'sequence terminal step persistence')
assert_true(normalized.reactions.rules[1].steps[1].optional, 'sequence optional flag persistence')

local normalized_pet = normalizer.normalize({
    config = { reactions = { enabled = true, rules = {
        {
            trigger = 'ability_window', name = 'Just Desserts', response = 'use_sequence',
            steps = { { action_type = 'pet', action_name = 'Assault', target = 'actor', optional = false } },
        },
    } } },
})
assert_equal(normalized_pet.reactions.rules[1].steps[1].action_type, 'pet', 'pet sequence action type persistence')
assert_equal(normalized_pet.reactions.rules[1].steps[1].action_name, 'Assault', 'pet sequence action persistence')

print('selftest_reaction_action_sequence: PASS')
