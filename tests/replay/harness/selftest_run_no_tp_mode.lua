package.path = './?.lua;./?/?.lua;' .. package.path

local function assert_true(value, message) if value ~= true then error(message or 'expected true') end end
local function assert_false(value, message) if value ~= false then error(message or 'expected false') end end
local function assert_equal(actual, expected, message)
    if actual ~= expected then error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual)) end
end
local function assert_contains(haystack, needle, message)
    if not tostring(haystack):find(tostring(needle), 1, true) then error((message or 'missing text') .. ': ' .. tostring(needle)) end
end

package.loaded.uc_scheduler_config = {
    tank_enabled = function(settings) return settings and settings.tank end,
}

local no_tp = require('uc_run_no_tp')
local predicates = require('uc_scheduler_action_predicates')
local settings = {
    tank = true,
    tank_run = {
        enabled = true,
        no_tp_mode = true,
        runes = { maintain = true, desired = {} },
        foil = { enabled = true },
        wards = {},
        magic_support = {},
    },
}
local player = { main_job = 'RUN', status = 1 }
local enemy = { id = 99, valid_target = true, spawn_type = 16, hpp = 100 }

assert_true(no_tp.enabled(settings, player), 'engaged RUN no-TP mode must activate')
assert_equal(no_tp.target_id(settings, player, enemy), 99, 'no-TP target id')
player.status = 0
assert_false(no_tp.enabled(settings, player), 'disengaged RUN must not own no-TP facing')
assert_equal(no_tp.target_id(settings, player, enemy), 0, 'disengaged no-TP target')
player.status = 1
player.main_job = 'PLD'
assert_false(no_tp.enabled(settings, player), 'non-RUN must not own no-TP facing')
player.main_job = 'RUN'
settings.tank = false
assert_false(no_tp.enabled(settings, player), 'disabled tank automation must disable no-TP facing')
settings.tank = true
settings.tank_run.no_tp_mode = false
assert_false(no_tp.enabled(settings, player), 'no-TP option defaults/acts off')
settings.tank_run.no_tp_mode = true
assert_equal(no_tp.target_id(settings, player, { id = 99, valid_target = true, spawn_type = 16, hpp = 0 }), 0, 'dead target must not own facing')

assert_true(predicates.ja_requires_engaged('Gambit', {}), 'Gambit requires engagement')
assert_true(predicates.ja_requires_engaged('Rayke', {}), 'Rayke requires engagement')
assert_false(predicates.ja_requires_engaged_front('Gambit', {}), 'Gambit does not require front arc')
assert_false(predicates.ja_requires_engaged_front('Rayke', {}), 'Rayke does not require front arc')
assert_true(predicates.ja_requires_engaged('Shield Bash', { id = 46 }), 'front-required JA also requires engagement')
assert_true(predicates.ja_requires_engaged_front('Shield Bash', { id = 46 }), 'Shield Bash retains front requirement')

local scheduler_source = assert(io.open('unified_scheduler.lua', 'r')):read('*a')
assert_contains(scheduler_source, "local requires_engaged = ja_requires_engaged(name, ja)", 'scheduler must enforce engaged-only JA predicate')
assert_contains(scheduler_source, "require('uc_run_no_tp').target_id(s, p, t)", 'movement coordinator must apply persistent no-TP facing')
assert_contains(scheduler_source, "p1_apply_face_to_target(s, no_tp_tid, true, true, 'unified_scheduler:run_no_tp')", 'movement coordinator must turn RUN away')
assert_contains(scheduler_source, "require('uc_run_no_tp').target_id(settings, player, current_target)", 'combat dispatch must honor no-TP facing')

print('RUN no-TP mode self-test: ok')
