package.path = './?.lua;./?/?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then error(message or 'expected true') end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function resources(entries)
    local out = {}
    for id, entry in pairs(entries) do out[id] = entry end
    function out:with(field, value)
        for key, entry in pairs(self) do
            if type(key) == 'number' and type(entry) == 'table' and entry[field] == value then return entry end
        end
        return nil
    end
    return out
end

local rune_ids = {
    Ignis = 7001, Gelus = 7002, Flabra = 7003, Tellus = 7004,
    Sulpor = 7005, Unda = 7006, Lux = 7007, Tenebrae = 7008,
}
local job_entries = {}
local buff_entries = {}
local next_ja = 100
for name, status in pairs(rune_ids) do
    job_entries[next_ja] = { id = next_ja, en = name, status = status, range = 0 }
    buff_entries[status] = { id = status, en = name }
    next_ja = next_ja + 1
end
for _, spec in ipairs({
    { 'Vallation', 7101 }, { 'Valiance', 7102 }, { 'Liement', 7103 }, { 'Pflug', 7104 },
    { 'Battuta', 7105 }, { 'Swordplay', 7106 }, { 'One for All', 7107 },
    { 'Gambit', 0 }, { 'Rayke', 0 },
}) do
    job_entries[next_ja] = { id = next_ja, en = spec[1], status = spec[2], range = spec[1] == 'Gambit' and 4 or (spec[1] == 'Rayke' and 4 or 0) }
    if spec[2] > 0 then buff_entries[spec[2]] = { id = spec[2], en = spec[1] } end
    next_ja = next_ja + 1
end
local spell_entries = resources({ [200] = { id = 200, en = 'Foil', status = 7201, range = 0 } })
buff_entries[7201] = { id = 7201, en = 'Foil' }

package.loaded.resources = {
    job_abilities = resources(job_entries),
    spells = spell_entries,
    buffs = resources(buff_entries),
}
package.loaded.uc_scheduler_config = {
    tank_enabled = function(settings) return settings and settings.tank end,
}
package.loaded.uc_active_config = {
    get_path = function() return nil end,
}

_G.Start_Engine = true

local run_config = require('uc_run_config')
local ownership = require('uc_run_ownership')
local provider_module = require('uc_provider_run_tank')

local normalized = run_config.normalize({
    enabled = true,
    runes = { maintain = true, desired = { 'ignis', 'Ignis', 'IGNIS' } },
    foil = { enabled = true },
    wards = { vallation = true },
    magic_support = { gambit = true, rayke = true },
})
assert_equal(normalized.runes.desired[1], 'Ignis', 'rune canonicalization')
assert_equal(#normalized.runes.desired, 3, 'rune count')

local bad_ok = pcall(function()
    run_config.normalize({ enabled = true, runes = { desired = { 'Ignis', 'Ignis' } } })
end)
assert_true(not bad_ok, 'partial rune stacks must be rejected')

local ward_bad_ok = pcall(function()
    run_config.normalize({ enabled = true, wards = { vallation = true, valiance = true } })
end)
assert_true(not ward_bad_ok, 'Vallation and Valiance cannot both be automated')

local settings = {
    tank = true,
    ability_allow_unengaged = false,
    tank_run = normalized,
}
local filtered = ownership.filter_generic_abilities(settings, { 'Ignis', 'Battuta', 'Liement', 'Rayke', 'Sentinel' })
assert_equal(table.concat(filtered, '|'), 'Battuta|Liement|Sentinel', 'RUN ownership filter mismatch')

local ready = {}
local function action_ready(name)
    if ready[name] == false then return false, 'RECAST', 'ja' end
    if name == 'Foil' then return true, 'READY', 'spell' end
    return true, 'READY', 'ja'
end
local provider = provider_module.new({
    action_ready = action_ready,
    action_effective_range = function(raw) return tonumber(raw) or 0 end,
    clamp_urgency = function(value) return value end,
    log_tank_sched = function() end,
})
local player = {
    id = 1, name = 'Tank', main_job = 'RUN', status = 1, buffs = {},
}
local target = { id = 99, name = 'Target', valid_target = true, spawn_type = 16, hpp = 100 }
local function collect()
    local out = {}
    provider.collect({
        now = 10.0,
        settings = settings,
        player = player,
        player_present = true,
        target = target,
        target_present = true,
    }, out)
    return out
end

local out = collect()
assert_equal(#out, 1, 'missing runes should emit one proposal')
assert_equal(out[1].action_name, 'Ignis', 'first missing rune action')
assert_equal(out[1].target_kind, 'self', 'rune target')
assert_equal(out[1].priority_band, 94, 'RUN priority band')

player.buffs = { rune_ids.Ignis, rune_ids.Ignis, rune_ids.Ignis }
out = collect()
assert_equal(out[1].action_name, 'Vallation', 'ward should follow rune convergence')

player.buffs[#player.buffs + 1] = 7101
out = collect()
assert_equal(out[1].action_name, 'Foil', 'Foil should follow core ward')
assert_equal(out[1].action_type, 'spell', 'Foil action kind')

player.buffs[#player.buffs + 1] = 7201
out = collect()
assert_equal(out[1].action_name, 'Gambit', 'Gambit should precede Rayke')
assert_equal(out[1].target_kind, 'mob', 'Gambit target')

ready.Gambit = false
player.buffs = { 7101, 7201 }
out = collect()
assert_equal(out[1].action_name, 'Ignis', 'runes must rebuild before Rayke')

player.buffs = { rune_ids.Ignis, rune_ids.Ignis, rune_ids.Ignis, 7101, 7201 }
out = collect()
assert_equal(out[1].action_name, 'Rayke', 'Rayke should run after rebuilt runes when Gambit unavailable')

player.buffs[#player.buffs + 1] = 7103
player.buffs = { rune_ids.Ignis, rune_ids.Ignis, rune_ids.Ignis, 7103, 7201 }
ready.Gambit = false
ready.Rayke = false
out = collect()
assert_equal(#out, 0, 'Liement should suppress Vallation restore while active')

print('RUN tank self-test: ok')
