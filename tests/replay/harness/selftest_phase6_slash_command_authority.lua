package.path = './?.lua;' .. package.path

local active = require('uc_active_config')
local edit = require('uc_profile_v2_command_edits')
local overrides = require('uc_runtime_overrides')

local function eq(actual, expected, label)
    if actual ~= expected then error(('%s: expected=%s actual=%s'):format(label, tostring(expected), tostring(actual))) end
end
local function yes(value, label) eq(value, true, label) end

local prior_settings = rawget(_G, 'UC_SETTINGS')
local prior_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
local legacy = {
    fight_leader = false, fight_leader_id = 77, fight_leader_name = 'Old Leader',
    add_priority_names = { 'Old Mob' }, sleep = true,
    sleepspells = { 'Legacy Sleep' }, sleepspell = 'Legacy Sleep',
}
_G.UC_SETTINGS = legacy
local ok = active.set_active_profile({
    version = 2,
    profile = { character = 'Test', main_job = 'RDM', sub_job = 'WHM' },
    config = {
        follow = { fight = { leader = false, leader_name = '' } },
        targeting = { targets = {} },
        sleep = { enabled = false, order = {}, legacy_primary = '' },
    },
})
yes(ok, 'setup canonical Profile V2')

local success, why = edit.fight_leader('set', 'Ponpon', function(name)
    return name == 'Ponpon' and 12345 or 0
end)
yes(success, 'configured fight leader')
yes(active.get_path('config.follow.fight.leader'), 'fight leader enabled in canonical config')
eq(active.get_path('config.follow.fight.leader_name'), 'Ponpon', 'durable leader identity is name')
eq(active.get_path('config.follow.fight.leader_id'), 0, 'live party id must not become durable')
eq(legacy.fight_leader, false, 'flat fight leader must remain unchanged')
success, why = edit.fight_leader('off')
yes(success, 'fight leader off')
eq(active.get_path('config.follow.fight.leader'), false, 'canonical fight leader off')
success, why = edit.fight_leader('set', 'Outsider', function() return 0 end)
eq(success, false, 'invalid party member rejected')
eq(why, 'NOT_IN_PARTY', 'party identity rejection reason')
success, why = edit.fight_leader('clear')
yes(success, 'clear configured fight leader name')
eq(active.get_path('config.follow.fight.leader_id'), 0, 'cleared id stays runtime-only')
eq(overrides.fight_leader_enabled(legacy), false, 'runtime fight policy canonical')

success = edit.add_priority('add', 'Apex Bat')
yes(success, 'append canonical target')
success, why = edit.add_priority('add', 'apex bat')
eq(success, false, 'case-insensitive duplicate rejected')
eq(why, 'ALREADY', 'duplicate result')
success, why = edit.add_priority('add', 'Apex Crab')
yes(success, 'append second target')
success, why = edit.add_priority('list')
yes(success, 'list canonical priority')
eq(why[1], 'Apex Bat', 'first canonical target')
eq(why[2], 'Apex Crab', 'second canonical target')
eq(overrides.add_priority_names(legacy)[1], 'Apex Bat', 'runtime target priority canonical')
eq(legacy.add_priority_names[1], 'Old Mob', 'flat target list unchanged')
success, why = edit.add_priority('remove', 1)
yes(success, 'remove canonical target by index')
eq(active.get_path('config.targeting.targets')[1], 'Apex Crab', 'remove commits to canonical list')
success = edit.add_priority('clear')
yes(success, 'clear canonical target priority')
eq(#active.get_path('config.targeting.targets'), 0, 'priority list cleared')
eq(#overrides.add_priority_names(legacy), 0, 'flat cannot revive cleared target list')

local function spell(name)
    if name == 'Sleep II' or name == 'Sleep' then return name end
    return nil
end
success = edit.sleep('on')
yes(success, 'canonical sleep enabled')
eq(active.get_path('config.sleep.enabled'), true, 'canonical sleep gate')
success, why = edit.sleep('add', 'Sleep II', nil, spell)
yes(success, 'canonical Sleep II added')
eq(active.get_path('config.sleep.legacy_primary'), 'Sleep II', 'canonical primary mirror kept in sync')
success = edit.sleep('add', 'Sleep', nil, spell)
yes(success, 'canonical Sleep added')
success, why = edit.sleep('move', 2, 'up')
yes(success, 'sleep order moved')
eq(overrides.sleep_spell_names(legacy)[1], 'Sleep', 'runtime Sleep order canonical')
eq(active.get_path('config.sleep.legacy_primary'), 'Sleep', 'primary changed with order')
success, why = edit.sleep('add', 'Sleep')
eq(success, false, 'missing spell resource validation cannot silently edit')
success, why = edit.sleep('add', 'Not a Spell', nil, spell)
eq(success, false, 'unknown sleep spell rejected')
eq(why, 'SLEEP_SPELL_UNKNOWN', 'unknown spell rejection reason')
success = edit.sleep('remove', 2)
yes(success, 'canonical Sleep list remove')
success = edit.sleep('clear')
yes(success, 'canonical Sleep list clear')
eq(#overrides.sleep_spell_names(legacy), 0, 'flat Sleep cannot revive cleared order')
success = edit.sleep('off')
yes(success, 'canonical Sleep off')
eq(overrides.sleep_enabled(legacy), false, 'runtime Sleep gate canonical')
eq(legacy.sleep, true, 'flat Sleep gate untouched')
eq(legacy.sleepspells[1], 'Legacy Sleep', 'flat Sleep list untouched')

local file = assert(io.open('UnifiedCombat.lua', 'r'))
local source = file:read('*a'); file:close()
for _, marker in ipairs({
    "uc_profile_v2_command_edits.fight_leader(",
    "uc_profile_v2_command_edits.add_priority(",
    "uc_profile_v2_command_edits.sleep(",
}) do
    yes(source:find(marker, 1, true) ~= nil, 'addon command wire: ' .. marker)
end

_G.UC_SETTINGS = prior_settings
_G.UC_ACTIVE_PROFILE = prior_profile
print('selftest_phase6_slash_command_authority: OK')
