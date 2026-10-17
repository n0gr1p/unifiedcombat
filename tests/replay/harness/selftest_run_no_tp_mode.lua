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
    tank_enabled_from_config = function(config)
        return type(config) == 'table' and type(config.tank) == 'table' and config.tank.enabled == true
    end,
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

-- Canonical RUN no-TP follows the supplied Profile V2 snapshot, not the
-- previous flat mirror. Preserve no-config compatibility separately.
local run_on = { tank = { enabled = true, run = { enabled = true, no_tp_mode = true } } }
local run_off = { tank = { enabled = true, run = { enabled = false, no_tp_mode = false } } }
settings.tank_run.enabled = true
settings.tank_run.no_tp_mode = true
assert_false(no_tp.enabled(settings, player, run_off), 'canonical RUN OFF overrides stale flat ON')
assert_equal(no_tp.target_id(settings, player, enemy, run_off), 0,
    'canonical no-TP OFF must not return a facing target')
settings.tank_run.enabled = false
settings.tank_run.no_tp_mode = false
assert_true(no_tp.enabled(settings, player, run_on), 'canonical RUN ON overrides stale flat OFF')
assert_equal(no_tp.target_id(settings, player, enemy, run_on), 99,
    'canonical no-TP ON must preserve target id')
assert_false(no_tp.enabled(settings, player, { tank = { enabled = true } }),
    'missing RUN subtree must fail closed rather than inherit flat settings')

assert_true(predicates.ja_requires_engaged('Gambit', {}), 'Gambit requires engagement')
assert_true(predicates.ja_requires_engaged('Rayke', {}), 'Rayke requires engagement')
assert_false(predicates.ja_requires_engaged_front('Gambit', {}), 'Gambit does not require front arc')
assert_false(predicates.ja_requires_engaged_front('Rayke', {}), 'Rayke does not require front arc')
assert_true(predicates.ja_requires_engaged('Shield Bash', { id = 46 }), 'front-required JA also requires engagement')
assert_true(predicates.ja_requires_engaged_front('Shield Bash', { id = 46 }), 'Shield Bash retains front requirement')

-- Face preference is canonical policy; forced defensive turns are not.
local face_policy = require('uc_scheduler_context_utils').face_turn_allowed
local canonical_off = { combat = { face = false } }
local canonical_on = { combat = { face = true } }
assert_false(face_policy({ face = true }, canonical_off, false, false),
    'canonical face OFF must block routine turning despite stale flat ON')
assert_true(face_policy({ face = false }, canonical_on, false, false),
    'canonical face ON must allow routine turning despite stale flat OFF')
assert_false(face_policy({ face = true }, { combat = {} }, false, false),
    'missing canonical face leaf must not resurrect flat ON')
assert_false(face_policy({ face = true }, {}, false, false),
    'missing canonical combat domain must not resurrect flat ON')
assert_true(face_policy({ face = true }, nil, false, false),
    'genuine no-profile flat ON must remain compatible')
assert_true(face_policy({ face = 'on' }, nil, false, false),
    'genuine no-profile string toggle remains compatible')
assert_false(face_policy({ face = false }, nil, false, false),
    'genuine no-profile flat OFF must remain disabled')
assert_true(face_policy({ face = true }, canonical_off, true, true),
    'reaction turn-away must bypass canonical face OFF')
assert_true(face_policy({ face = true }, canonical_off, false, true),
    'post-reaction restoration must bypass canonical face OFF')
assert_true(face_policy({ face = false }, canonical_off, true, true),
    'RUN no-TP emergency turn must bypass both canonical and flat face OFF')
assert_true(face_policy({ face = false }, canonical_off, true, false),
    'explicit turn-away semantics must not be governed by routine face')
assert_true(face_policy({ face = false }, canonical_off, false, true),
    'explicit forced-facing semantics must not be governed by routine face')

local scheduler_source = assert(io.open('unified_scheduler.lua', 'r')):read('*a')
assert_contains(scheduler_source, "local requires_engaged = ja_requires_engaged(name, ja)", 'scheduler must enforce engaged-only JA predicate')
assert_contains(scheduler_source, "require('uc_run_no_tp').target_id(s, p, t, config)", 'movement coordinator must apply persistent no-TP facing with canonical tank config')
assert_contains(scheduler_source, "p1_apply_face_to_target(s, no_tp_tid, true, true, 'unified_scheduler:run_no_tp', config)", 'movement coordinator must turn RUN away')
assert_contains(scheduler_source, "require('uc_run_no_tp').target_id(settings, player, current_target, config)", 'combat dispatch must honor no-TP facing with canonical tank config')

assert_contains(scheduler_source, "face_turn_allowed(settings, config, turn_away, force_face)",
    'scheduler facing path must consume shared canonical/forced policy')
assert_contains(scheduler_source, "p1_apply_face_to_target(s, tid, false, false, nil, config)",
    'normal facing must pass the canonical tick config without forcing')
assert_contains(scheduler_source, "p1_apply_face_to_target(settings, tonumber(selected.target_id) or 0, false, false, nil, config)",
    'combat dispatch normal facing must pass canonical config without forcing')
assert_contains(scheduler_source, "scheduler.apply_reaction_turn({ actor_id = current_target_id }, false)",
    'reaction completion must still restore facing after an emergency turn')
assert_contains(scheduler_source, "tonumber(lock.actor_id) or 0,",
    'reaction facing must retain its explicit actor target')
assert_contains(scheduler_source, "turn_away == true,",
    'reaction facing must retain turn-away direction and force flag')


print('RUN no-TP mode self-test: ok')
