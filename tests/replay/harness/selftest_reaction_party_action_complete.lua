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
        spells = {
            [501] = { id = 501, en = 'Indi-Malaise' },
            [502] = { id = 502, en = 'Indi-Frailty' },
        },
        job_abilities = {
            [601] = { id = 601, en = 'Entrust' },
            [701] = { id = 701, en = 'Astral Flow' },
            [702] = { id = 702, en = 'Astral Conduit' },
        },
        monster_abilities = {},
    }
end

local enemy_valid = true
_G.windower = {
    ffxi = {
        get_party = function()
            return {
                p0 = { mob = { id = 100, name = 'Terrasjr' } },
                p1 = { mob = { id = 200, name = 'Etamame' } },
                p2 = { mob = { id = 201, name = 'Othergeo' } },
            }
        end,
        get_mob_by_id = function(id)
            if tonumber(id) == 900 and enemy_valid then
                return { id = 900, name = 'Zerde', hpp = 100, valid_target = true }
            end
            return nil
        end,
    },
}

local rule_enabled = true
local rule = {
    trigger = 'party_action_complete',
    source_name = 'Etamame',
    action_type = 'spell',
    name = 'Indi-Malaise',
    response = 'use_sequence',
    once_per_instance = true,
    steps = {
        { action_type = 'ja', action_name = 'Astral Flow', target = 'self', optional = false },
        { action_type = 'ja', action_name = 'Astral Conduit', target = 'self', optional = false },
    },
}

local ja_rule = {
    trigger = 'party_action_complete',
    source_name = 'Etamame',
    action_type = 'ja',
    name = 'Entrust',
    response = 'use_sequence',
    steps = {
        { action_type = 'ja', action_name = 'Astral Flow', target = 'self', optional = false },
    },
}

package.loaded.uc_combat_extension_config = nil
package.preload.uc_combat_extension_config = function()
    return {
        reaction_rules = function() return rule_enabled and { rule, ja_rule } or {} end,
        validate_action_rule = function(candidate)
            local valid = candidate == rule or candidate == ja_rule
            return valid, valid and nil or 'unexpected rule'
        end,
    }
end

local fake_base = {}
function fake_base.on_action() return {} end
function fake_base.evaluate() return nil, nil end
function fake_base.prune_invalid_ability_windows() return nil end
function fake_base.get_action_lock() return nil end
function fake_base.skip_optional_step() return nil, 'sequence_not_active' end
function fake_base.note_sequence_action_dispatched() return false, 'sequence_not_active' end
function fake_base.note_sequence_pet_command_completed() return nil, 'sequence_not_active' end
function fake_base.note_sequence_pet_command_failed() return nil, 'sequence_not_active' end
function fake_base.blocks_proposal() return false end
function fake_base.blocks_movement() return false end
function fake_base.owns_movement() return false end
function fake_base.requires_disengage() return false end
function fake_base.cancel() return nil, nil end
function fake_base.reset() return nil end
function fake_base.status() return { active = {} } end

package.loaded.uc_party_action_event = nil
package.loaded.uc_reaction_party_sequence_runtime = nil
package.loaded.uc_reaction_once_runtime = nil
local party = require('uc_reaction_party_sequence_runtime').extend(fake_base)
local reactions = require('uc_reaction_once_runtime').extend(party)

local wrong_source = reactions.on_action({ actor_id = 201, category = 4, param = 501 }, 900, 1.0, false)
assert_true(wrong_source.activated == nil, 'same spell from wrong party member must not activate')

local wrong_action = reactions.on_action({ actor_id = 200, category = 4, param = 502 }, 900, 1.1, false)
assert_true(wrong_action.activated == nil, 'different completed spell must not activate')

local no_enemy = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 0, 1.2, false)
assert_true(no_enemy.activated == nil, 'matching party action without current enemy must not activate')

local ja_ready = reactions.on_action({ actor_id = 200, category = 6, param = 601 }, 900, 1.3, false)
assert_true(type(ja_ready.activated) == 'table', 'matching party job ability completion must activate sequence')
assert_equal(ja_ready.activated.completed_action_type, 'ja', 'job ability trigger type')
assert_equal(ja_ready.activated.completed_action_name, 'Entrust', 'job ability trigger name')
assert_equal(ja_ready.activated.event_actor_id, 200, 'job ability event actor')
local ja_released = reactions.cancel(ja_ready.activated.key, 'selftest')
assert_true(type(ja_released) == 'table', 'job ability reaction must use ordinary cancellable sequence lock')

local ready = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 900, 2.0, false)
assert_true(type(ready.activated) == 'table', 'matching party action completion must activate sequence')
assert_equal(ready.activated.trigger, 'party_action_complete', 'trigger type')
assert_equal(ready.activated.actor_id, 900, 'enemy instance must own reaction lock')
assert_equal(ready.activated.event_actor_id, 200, 'party member must be recorded separately')
assert_equal(ready.activated.event_actor_name, 'Etamame', 'party member name')
assert_equal(ready.activated.completed_action_type, 'spell', 'completed spell type')
assert_equal(ready.activated.completed_action_name, 'Indi-Malaise', 'completed action name')

local duplicate_pending = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 900, 2.1, false)
assert_true(duplicate_pending.once_per_instance_suppressed == true,
    'duplicate completion must be suppressed while one-shot sequence is pending')

local dispatched = reactions.note_sequence_action_dispatched(
    ready.activated.key, 'ja', 'Astral Flow', 'self', 100, 100, 2.2
)
assert_true(dispatched == true, 'first reaction step must dispatch')
assert_equal(reactions.status().once_per_instance.consumed_count, 1,
    'enemy instance must be consumed after first successful sequence dispatch')

local flow_complete = reactions.on_action({ actor_id = 100, category = 6, param = 701 }, 900, 2.3, false)
assert_true(type(flow_complete.activated) == 'table', 'Astral Flow completion must advance sequence')
assert_equal(flow_complete.activated.action_name, 'Astral Conduit', 'second step must be Astral Conduit')

local conduit_dispatched = reactions.note_sequence_action_dispatched(
    flow_complete.activated.key, 'ja', 'Astral Conduit', 'self', 100, 100, 2.4
)
assert_true(conduit_dispatched == true, 'second reaction step must dispatch')
local conduit_complete = reactions.on_action({ actor_id = 100, category = 6, param = 702 }, 900, 2.5, false)
assert_true(type(conduit_complete.released) == 'table', 'terminal completion must release sequence lock')

local duplicate_consumed = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 900, 2.6, false)
assert_true(duplicate_consumed.once_per_instance_suppressed == true,
    'same enemy instance must remain consumed after sequence completes')

enemy_valid = false
reactions.prune_invalid_ability_windows(function(actor_id)
    return tonumber(actor_id) ~= 900
end)
assert_equal(reactions.status().once_per_instance.consumed_count, 0,
    'despawned enemy must clear party-trigger one-shot state')

enemy_valid = true
local reused_enemy = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 900, 3.0, false)
assert_true(type(reused_enemy.activated) == 'table',
    'new enemy instance reusing actor id must be eligible after invalidation cleanup')

-- A disabled rule must release a still-pending one-shot sequence and its
-- pending reservation. A dispatched/consumed instance must retain history
-- even when its sequence is later cancelled by a profile edit.
assert_equal(reactions.status().once_per_instance.pending_count, 1,
    'new enemy instance starts with one pending one-shot sequence')
rule_enabled = false
local policy_released = reactions.prune_invalid_ability_windows(function() return true end)
assert_equal(policy_released.key, reused_enemy.activated.key, 'disabled party rule releases lock')
assert_true(reactions.get_action_lock() == nil, 'disabled party rule frees action lane')
assert_equal(reactions.status().once_per_instance.pending_count, 0,
    'disabled rule frees orphaned pending once-per-instance reservation')
assert_equal(reactions.status().once_per_instance.consumed_count, 0,
    'pending cancellation does not fabricate consumed one-shot history')
rule_enabled = true

local resumed = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 900, 4.0, false)
assert_true(type(resumed.activated) == 'table', 're-enabled rule can re-arm before first dispatch')
local marked_after_rearm = reactions.note_sequence_action_dispatched(
    resumed.activated.key, 'ja', 'Astral Flow', 'self', 100, 100, 4.1
)
assert_true(marked_after_rearm, 're-armed sequence dispatches')
assert_equal(reactions.status().once_per_instance.consumed_count, 1,
    'dispatched step consumes the enemy instance')
local next_step = reactions.on_action({ actor_id = 100, category = 6, param = 701 }, 900, 4.2, false)
assert_equal(next_step.activated.action_name, 'Astral Conduit',
    'packet completion advances to pending second step')
rule.source_name = 'Redrogue'
local source_released = reactions.prune_invalid_ability_windows(function() return true end)
assert_equal(source_released.key, resumed.activated.key,
    'party source edit releases stale sequence immediately')
assert_true(reactions.get_action_lock() == nil, 'party source edit frees action lane')
assert_equal(reactions.status().once_per_instance.pending_count, 0,
    'party source edit cannot leave orphaned pending reservation')
assert_equal(reactions.status().once_per_instance.consumed_count, 1,
    'already consumed one-shot instance survives profile edit')
rule.source_name = 'Etamame'
local again = reactions.on_action({ actor_id = 200, category = 4, param = 501 }, 900, 4.3, false)
assert_true(again.once_per_instance_suppressed == true,
    'profile edit must not let consumed enemy trigger a second one-shot sequence')

print('selftest_reaction_party_action_complete: OK')
