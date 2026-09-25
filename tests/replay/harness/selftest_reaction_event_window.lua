local function assert_true(value, message)
    if value ~= true then
        error(message or 'expected true')
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected=%s actual=%s'):format(
            message or 'values differ',
            tostring(expected),
            tostring(actual)
        ))
    end
end

package.loaded.resources = nil
package.preload.resources = function()
    return {
        monster_abilities = {},
        buffs = {
            [173] = { id = 173, en = 'Dread Spikes' },
        },
        spells = {
            [901] = { id = 901, en = 'Dread Spikes' },
        },
    }
end

local normalizer = require('uc_config_normalizer')
local active_config = require('uc_active_config')

local rules = {
    -- Keep the legacy rule present to prove backward compatibility/coexistence.
    { trigger = 'enemy_buff', name = 'Dread Spikes', response = 'stop_attacking' },
    {
        trigger = 'event_window',
        name = 'Dread Spikes',
        response = 'stop_attacking',
        activate_event = 'spell_start',
        release_event = 'buff_lost',
        release_name = 'Dread Spikes',
        confirmation_timeout_seconds = 1.5,
    },
    {
        trigger = 'event_window',
        name = 'Dread Spikes',
        response = 'turn_away',
        activate_event = 'spell_start',
        release_event = 'buff_lost',
        release_name = 'Dread Spikes',
        confirmation_timeout_seconds = 1.5,
    },
}

local meta = { character = 'Testchar', main_job = 'MNK', sub_job = 'WAR' }
local normalized = normalizer.normalize({
    reactions = {
        enabled = true,
        rules = rules,
    },
}, meta)

assert_equal(#normalized.reactions.rules, 3, 'reaction lifecycle rules must normalize')
assert_equal(normalized.reactions.rules[2].activate_event, 'spell_start', 'activation event must normalize')
assert_equal(normalized.reactions.rules[2].release_event, 'buff_lost', 'release event must normalize')
assert_equal(normalized.reactions.rules[2].release_name, 'Dread Spikes', 'release name must normalize')
assert_equal(normalized.reactions.rules[2].confirmation_timeout_seconds, 1.5, 'confirmation timeout must normalize')
assert_equal(normalized.reactions.rules[3].response, 'turn_away', 'turn-away event-window response must normalize')

local payload = {
    version = 2,
    profile = {
        schema_version = 2,
        engine = 'UC',
        character = 'Testchar',
        main_job = 'MNK',
        sub_job = 'WAR',
        source = 'ui',
    },
    config = {
        reactions = {
            enabled = true,
            rules = normalized.reactions.rules,
        },
    },
}
local active, active_error = active_config.build_active_profile_from_v2_payload(payload, meta)
assert_true(type(active) == 'table', active_error or 'active profile must build')
assert_true(active_config.set_active_profile(active), 'active profile must install')

package.loaded.uc_reaction_runtime = nil
local reactions = require('uc_reaction_runtime')
local watch = reactions.effect_watch_set()
assert_true(watch[173] == true, 'release buff must be included in the observed effect set')

local start = reactions.on_action({
    actor_id = 900,
    category = 8,
    param = 24931,
    targets = {
        { id = 900, actions = { { param = 901 } } },
    },
}, 900, 10.0, true)
assert_true(type(start.activated) == 'table', 'spell start must activate the lifecycle')
assert_true(type(start.activated_all) == 'table', 'spell start must expose all matching event-window reactions')
assert_equal(#start.activated_all, 2, 'spell start must activate both stop-attacking and turn-away rules')
assert_equal(start.activated_all[1].response, 'stop_attacking', 'first Dread Spikes response must stop attacks')
assert_equal(start.activated_all[2].response, 'turn_away', 'second Dread Spikes response must turn away')
assert_equal(start.activated.trigger, 'event_window', 'spell start must create an event-window lock')
assert_equal(start.activated.phase, 'active', 'new lifecycle must begin active')
assert_true(reactions.requires_disengage(start.activated_all[1], 1), 'spell-start stop reaction must request immediate disengage')
local turn_lock = reactions.active_response_lock(900, 'turn_away')
assert_true(type(turn_lock) == 'table', 'spell start must expose a concurrent turn-away lock')
assert_true(reactions.blocks_movement(turn_lock), 'turn-away lifecycle must hold normal facing/movement')

reactions.reset('off_target')
local off_target = reactions.on_action({
    actor_id = 901,
    category = 8,
    param = 24931,
    targets = {
        { id = 901, actions = { { param = 901 } } },
    },
}, 900, 11.0, true)
assert_true(off_target.activated == nil, 'stop-attacking spell-start lifecycle must be current-target scoped')

reactions.reset('confirmation')
start = reactions.on_action({
    actor_id = 900,
    category = 8,
    param = 24931,
    targets = {
        { id = 900, actions = { { param = 901 } } },
    },
}, 900, 20.0, true)
assert_true(type(start.activated) == 'table', 'confirmation test cast must activate')
local complete = reactions.on_action({
    actor_id = 900,
    category = 4,
    param = 901,
}, 900, 20.5, true)
assert_true(complete.released == nil, 'spell completion must not create a release gap before buff confirmation')
local waiting = reactions.evaluate(900, {}, 20.6)
assert_equal(waiting.phase, 'awaiting_confirmation', 'completed spell must wait for expected buff')

local selected = reactions.evaluate(900, { { effect_id = 173 } }, 20.7)
assert_true(type(selected) == 'table', 'buff gain must leave a stop-attacking lock selected')
local lifecycle = nil
local legacy = nil
for _, lock in ipairs(reactions.status().active or {}) do
    if lock.trigger == 'event_window' then
        lifecycle = lock
    elseif lock.trigger == 'enemy_buff' then
        legacy = lock
    end
end
assert_true(type(lifecycle) == 'table', 'event-window lock must remain active after buff gain')
assert_equal(lifecycle.phase, 'confirmed', 'buff gain must confirm event-window lifecycle')
local confirmed_turn = reactions.active_response_lock(900, 'turn_away')
assert_true(type(confirmed_turn) == 'table', 'turn-away lifecycle must remain active after buff confirmation')
assert_equal(confirmed_turn.phase, 'confirmed', 'turn-away lifecycle must confirm on the same buff')
assert_true(type(legacy) == 'table', 'legacy enemy-buff rule must coexist with event-window lifecycle')

local after_timeout = reactions.evaluate(900, { { effect_id = 173 } }, 23.0)
assert_true(type(after_timeout) == 'table', 'confirmed buff must ignore the no-buff timeout')
local released, released_target = reactions.evaluate(900, {}, 23.1)
assert_true(released == nil, 'buff loss must clear all Dread Spikes stop locks')
assert_equal(released_target, 900, 'buff loss must request normal reaction release handling')

reactions.reset('interruption')
start = reactions.on_action({
    actor_id = 900,
    category = 8,
    param = 24931,
    targets = {
        { id = 900, actions = { { param = 901 } } },
    },
}, 900, 30.0, true)
assert_true(type(start.activated) == 'table', 'interruption test cast must activate')
local interrupted = reactions.on_action_message({
    actor_id = 900,
    target_id = 900,
    message_id = 16,
}, 900, 30.2)
assert_true(type(interrupted.released) == 'table', 'cast interruption must immediately release lifecycle')
assert_equal(interrupted.released_target_id, 900, 'interruption release must restore normal reaction ownership')
assert_true(reactions.evaluate(900, {}, 30.3) == nil, 'interrupted cast must leave no stale stop lock')

reactions.reset('missing_buff')
start = reactions.on_action({
    actor_id = 900,
    category = 8,
    param = 24931,
    targets = {
        { id = 900, actions = { { param = 901 } } },
    },
}, 900, 40.0, true)
assert_true(type(start.activated) == 'table', 'missing-buff test cast must activate')
reactions.on_action({
    actor_id = 900,
    category = 4,
    param = 901,
}, 900, 40.5, true)
local before_confirmation_timeout = reactions.evaluate(900, {}, 41.9)
assert_true(type(before_confirmation_timeout) == 'table', 'missing buff must remain held before confirmation timeout')
local after_confirmation_timeout, timeout_target = reactions.evaluate(900, {}, 42.01)
assert_true(after_confirmation_timeout == nil, 'missing buff must release after confirmation timeout')
assert_equal(timeout_target, 900, 'confirmation timeout must restore normal reaction ownership')

print('selftest_reaction_event_window: OK')


local function read_file(path)
    local fh = assert(io.open(path, 'r'))
    local content = fh:read('*a')
    fh:close()
    return content
end

local function assert_before(source, first_text, second_text, message)
    local first = assert(source:find(first_text, 1, true), 'missing source text: ' .. first_text)
    local second = assert(source:find(second_text, 1, true), 'missing source text: ' .. second_text)
    assert_true(first < second, message)
end

local unified_source = read_file('UnifiedCombat.lua')
assert_before(
    unified_source,
    "_G.UC_SCHED_OnReactionAction(act, observed_at)",
    "uc_encounter_runtime.observe(observed_at)",
    'reaction prepass must run before encounter bookkeeping'
)
assert_before(
    unified_source,
    "_G.UC_SCHED_OnReactionAction(act, observed_at)",
    "UC_COMBAT_CORE.on_action(act)",
    'reaction prepass must run before combat-core action observation'
)
assert_before(
    unified_source,
    "_G.UC_SCHED_OnReactionAction(act, observed_at)",
    "_G.UC_SCHED_OnAction(act)",
    'reaction prepass must run before normal scheduler action observation'
)

local scheduler_source = read_file('unified_scheduler.lua')
local prepass_start = assert(scheduler_source:find('function scheduler.on_reaction_action(act, packet_received_at)', 1, true))
local normal_action_start = assert(scheduler_source:find('function scheduler.on_action(act)', 1, true))
assert_true(prepass_start < normal_action_start, 'reaction prepass must be defined independently of normal action processing')
local normal_action_body = scheduler_source:sub(normal_action_start)
assert_true(
    normal_action_body:find("require('uc_reaction_runtime').on_action(", 1, true) == nil,
    'normal scheduler action path must not process reactions a second time'
)
assert_true(
    scheduler_source:find("scheduler.action_timeline_log('REACTION_FASTPATH'", 1, true) ~= nil,
    'reaction prepass must emit fast-path timing telemetry'
)
assert_true(
    scheduler_source:find('_G.UC_LAST_REACTION_TIMINGS = timing_records', 1, true) ~= nil,
    'reaction prepass must retain the latest timing snapshot in memory'
)
