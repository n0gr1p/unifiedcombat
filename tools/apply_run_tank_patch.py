from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(rel, old, new):
    path = ROOT / rel
    text = path.read_text(encoding='utf-8')
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{rel}: expected one anchor, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def write(rel, content):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


RUN_CONFIG = r'''local M = {}

local RUNE_NAMES = {
    Ignis = true,
    Gelus = true,
    Flabra = true,
    Tellus = true,
    Sulpor = true,
    Unda = true,
    Lux = true,
    Tenebrae = true,
}

local RUNE_CANONICAL = {}
for name in pairs(RUNE_NAMES) do
    RUNE_CANONICAL[name:lower()] = name
end

local function clone(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for key, inner in pairs(value) do
        out[key] = clone(inner)
    end
    return out
end

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function bool(value, default_value, path)
    if value == nil then
        return default_value
    end
    if type(value) ~= 'boolean' then
        error(path .. ' must be boolean')
    end
    return value
end

local function split_pipe(value)
    if type(value) ~= 'string' then
        return value
    end
    local out = {}
    for token in value:gmatch('[^|]+') do
        local entry = trim(token)
        if entry ~= '' then
            out[#out + 1] = entry
        end
    end
    return out
end

local function normalize_runes(value)
    value = split_pipe(value or {})
    if type(value) ~= 'table' then
        error('config.tank.run.runes.desired must be an array or pipe-delimited string')
    end
    local out = {}
    for i = 1, #value do
        local raw = trim(value[i])
        local canonical = RUNE_CANONICAL[raw:lower()]
        if canonical == nil then
            error(('config.tank.run.runes.desired[%d] is not a Rune Enchantment'):format(i))
        end
        out[#out + 1] = canonical
    end
    if #out ~= 0 and #out ~= 3 then
        error('config.tank.run.runes.desired must be empty or contain exactly three runes')
    end
    return out
end

function M.default_config()
    return {
        enabled = false,
        runes = {
            maintain = true,
            desired = {},
        },
        foil = {
            enabled = true,
        },
        wards = {
            vallation = false,
            valiance = false,
            pflug = false,
            swordplay = false,
            battuta = false,
            one_for_all = false,
        },
        magic_support = {
            gambit = false,
            rayke = false,
        },
    }
end

local function flat_value(source, key)
    if type(source) ~= 'table' then
        return nil
    end
    return source[key]
end

function M.normalize(value, flat_source)
    local out = M.default_config()
    local structured = type(value) == 'table' and value or nil
    if structured ~= nil then
        out.enabled = bool(structured.enabled, out.enabled, 'config.tank.run.enabled')
        local runes = type(structured.runes) == 'table' and structured.runes or {}
        out.runes.maintain = bool(runes.maintain, out.runes.maintain, 'config.tank.run.runes.maintain')
        out.runes.desired = normalize_runes(runes.desired)
        local foil = type(structured.foil) == 'table' and structured.foil or {}
        out.foil.enabled = bool(foil.enabled, out.foil.enabled, 'config.tank.run.foil.enabled')
        local wards = type(structured.wards) == 'table' and structured.wards or {}
        out.wards.vallation = bool(wards.vallation, out.wards.vallation, 'config.tank.run.wards.vallation')
        out.wards.valiance = bool(wards.valiance, out.wards.valiance, 'config.tank.run.wards.valiance')
        out.wards.pflug = bool(wards.pflug, out.wards.pflug, 'config.tank.run.wards.pflug')
        out.wards.swordplay = bool(wards.swordplay, out.wards.swordplay, 'config.tank.run.wards.swordplay')
        out.wards.battuta = bool(wards.battuta, out.wards.battuta, 'config.tank.run.wards.battuta')
        out.wards.one_for_all = bool(wards.one_for_all, out.wards.one_for_all, 'config.tank.run.wards.one_for_all')
        local magic = type(structured.magic_support) == 'table' and structured.magic_support or {}
        out.magic_support.gambit = bool(magic.gambit, out.magic_support.gambit, 'config.tank.run.magic_support.gambit')
        out.magic_support.rayke = bool(magic.rayke, out.magic_support.rayke, 'config.tank.run.magic_support.rayke')
    else
        out.enabled = bool(flat_value(flat_source, 'run_tank_enabled'), out.enabled, 'run_tank_enabled')
        out.runes.maintain = bool(flat_value(flat_source, 'run_tank_runes_maintain'), out.runes.maintain, 'run_tank_runes_maintain')
        out.runes.desired = normalize_runes(flat_value(flat_source, 'run_tank_runes') or {})
        out.foil.enabled = bool(flat_value(flat_source, 'run_tank_foil'), out.foil.enabled, 'run_tank_foil')
        out.wards.vallation = bool(flat_value(flat_source, 'run_tank_vallation'), out.wards.vallation, 'run_tank_vallation')
        out.wards.valiance = bool(flat_value(flat_source, 'run_tank_valiance'), out.wards.valiance, 'run_tank_valiance')
        out.wards.pflug = bool(flat_value(flat_source, 'run_tank_pflug'), out.wards.pflug, 'run_tank_pflug')
        out.wards.swordplay = bool(flat_value(flat_source, 'run_tank_swordplay'), out.wards.swordplay, 'run_tank_swordplay')
        out.wards.battuta = bool(flat_value(flat_source, 'run_tank_battuta'), out.wards.battuta, 'run_tank_battuta')
        out.wards.one_for_all = bool(flat_value(flat_source, 'run_tank_one_for_all'), out.wards.one_for_all, 'run_tank_one_for_all')
        out.magic_support.gambit = bool(flat_value(flat_source, 'run_tank_gambit'), out.magic_support.gambit, 'run_tank_gambit')
        out.magic_support.rayke = bool(flat_value(flat_source, 'run_tank_rayke'), out.magic_support.rayke, 'run_tank_rayke')
    end
    if out.wards.vallation and out.wards.valiance then
        error('config.tank.run.wards cannot enable both Vallation and Valiance')
    end
    return out
end

function M.active(settings)
    if type(settings) == 'table' and type(settings.tank_run) == 'table' then
        return M.normalize(settings.tank_run)
    end
    local ok, active_config = pcall(require, 'uc_active_config')
    if ok and type(active_config) == 'table' and type(active_config.get_path) == 'function' then
        local active = active_config.get_path('config.tank.run')
        if type(active) == 'table' then
            return M.normalize(active)
        end
    end
    return M.normalize(nil, settings)
end

function M.is_rune_name(name)
    return RUNE_CANONICAL[trim(name):lower()] ~= nil
end

function M.rune_names()
    local out = {}
    for _, name in ipairs({ 'Ignis', 'Gelus', 'Flabra', 'Tellus', 'Sulpor', 'Unda', 'Lux', 'Tenebrae' }) do
        out[#out + 1] = name
    end
    return out
end

function M.copy(config)
    return clone(config)
end

return M
'''

RUN_OWNERSHIP = r'''local run_config = require('uc_run_config')

local M = {}

local RUNE_NAMES = {}
for _, name in ipairs(run_config.rune_names()) do
    RUNE_NAMES[name:lower()] = true
end

local function owned_set(settings)
    local cfg = run_config.active(settings)
    if cfg.enabled ~= true then
        return {}
    end
    local out = {}
    for name in pairs(RUNE_NAMES) do
        out[name] = true
    end
    local wards = cfg.wards or {}
    if wards.vallation then out.vallation = true end
    if wards.valiance then out.valiance = true end
    if wards.pflug then out.pflug = true end
    if wards.swordplay then out.swordplay = true end
    if wards.battuta then out.battuta = true end
    if wards.one_for_all then out['one for all'] = true end
    local magic = cfg.magic_support or {}
    if magic.gambit then out.gambit = true end
    if magic.rayke then out.rayke = true end
    return out
end

function M.owns_ja(settings, name)
    local key = tostring(name or ''):lower()
    return owned_set(settings)[key] == true
end

function M.filter_generic_abilities(settings, abilities)
    if type(abilities) ~= 'table' then
        return {}
    end
    local owned = owned_set(settings)
    if next(owned) == nil then
        local copy = {}
        for i = 1, #abilities do copy[i] = abilities[i] end
        return copy
    end
    local out = {}
    for i = 1, #abilities do
        local name = abilities[i]
        if owned[tostring(name or ''):lower()] ~= true then
            out[#out + 1] = name
        end
    end
    return out
end

return M
'''

RUN_PROVIDER = r'''local res = require('resources')
local run_config = require('uc_run_config')
local scheduler_config = require('uc_scheduler_config')

local M = {}
local RUN_PRIORITY = 94

local RUNE_NAMES = run_config.rune_names()
local RUNE_SET = {}
for _, name in ipairs(RUNE_NAMES) do RUNE_SET[name] = true end

local function require_table(value, name)
    if type(value) ~= 'table' then error(name .. ' must be a table') end
    return value
end

local function require_function(deps, name)
    local value = deps[name]
    if type(value) ~= 'function' then error(('uc_provider_run_tank deps.%s must be a function'):format(name)) end
    return value
end

local function bool_setting(value)
    if value == true or value == 1 then return true end
    if type(value) == 'string' then
        local lowered = value:lower()
        return lowered == 'true' or lowered == 'on' or lowered == '1' or lowered == 'yes'
    end
    return false
end

local function resource_by_name(collection, name)
    if type(collection) ~= 'table' then return nil end
    if type(collection.with) == 'function' then
        local ok, value = pcall(collection.with, collection, 'en', name)
        if ok and type(value) == 'table' then return value end
    end
    for _, value in pairs(collection) do
        if type(value) == 'table' and tostring(value.en or '') == name then return value end
    end
    return nil
end

local function status_id_for_action(name, kind)
    local resource = kind == 'spell' and resource_by_name(res.spells, name) or resource_by_name(res.job_abilities, name)
    local direct = tonumber(resource and resource.status) or 0
    if direct > 0 then return direct end
    for id, buff in pairs(res.buffs or {}) do
        if type(buff) == 'table' and tostring(buff.en or '') == name then
            local numeric = tonumber(id) or tonumber(buff.id) or 0
            if numeric > 0 then return numeric end
        end
    end
    return 0
end

local function buff_count(player, status_id)
    local count = 0
    for _, id in ipairs(type(player) == 'table' and player.buffs or {}) do
        if tonumber(id) == tonumber(status_id) then count = count + 1 end
    end
    return count
end

local function has_buff(player, status_id)
    return status_id > 0 and buff_count(player, status_id) > 0
end

local function current_enemy(ctx)
    local target = type(ctx) == 'table' and ctx.target or nil
    if type(target) ~= 'table' or ctx.target_present ~= true then return nil end
    if target.valid_target ~= true or tonumber(target.spawn_type) ~= 16 or (tonumber(target.hpp) or 0) <= 0 then return nil end
    if (tonumber(target.id) or 0) <= 0 then return nil end
    return target
end

local function publish(state, reason, action_name, desired, observed)
    _G.UC_RUN_TANK_STATUS = {
        state = tostring(state or ''),
        reason = tostring(reason or ''),
        action = tostring(action_name or ''),
        desired_runes = desired or {},
        observed_runes = observed or {},
    }
end

function M.new(deps)
    deps = require_table(deps, 'deps')
    local action_ready = require_function(deps, 'action_ready')
    local action_effective_range = require_function(deps, 'action_effective_range')
    local clamp_urgency = require_function(deps, 'clamp_urgency')
    local log_tank_sched = type(deps.log_tank_sched) == 'function' and deps.log_tank_sched or function() end

    local provider = {}

    local function ready(name, target_id, expected_kind)
        local ok, reason, kind = action_ready(name, target_id)
        if ok == true and tostring(kind or '') == expected_kind then return true end
        log_tank_sched(('run_skip action="%s" reason=%s kind=%s'):format(name, tostring(reason or 'NOT_READY'), tostring(kind or '')))
        return false
    end

    local function add_proposal(ctx, out, spec)
        local player = ctx.player
        local target_id = spec.target_kind == 'self' and (tonumber(player.id) or 0) or tonumber(spec.target_id) or 0
        if target_id <= 0 then return false end
        local target_name = spec.target_kind == 'self' and tostring(player.name or '') or tostring(spec.target_name or '')
        local max_range = 0.1
        if spec.target_kind == 'mob' then
            max_range = tonumber(spec.max_range) or 0
            if max_range <= 0 then max_range = 20.0 end
        end
        out[#out + 1] = {
            proposal_id = ('combat.run.%s.%s.%d.%d'):format(spec.kind, spec.name, target_id, math.floor(ctx.now * 1000)),
            family_id = 'combat.run_tank.primary',
            provider = 'combat',
            action_type = spec.kind,
            action_name = spec.name,
            target_kind = spec.target_kind,
            target_id = target_id,
            target_name = target_name,
            priority_band = RUN_PRIORITY,
            urgency = clamp_urgency(tonumber(spec.urgency) or 0.70),
            starvation_eligible = true,
            created_at = ctx.now,
            expires_at = ctx.now + 0.35,
            commit_deadline = ctx.now + 0.25,
            movement_policy = spec.kind == 'spell' and 'must_stop' or (spec.target_kind == 'mob' and 'requires_range' or 'none'),
            range_policy = { min = 0.0, max = max_range, los_required = spec.target_kind == 'mob' },
            recast_key = ('run:%s:%s'):format(spec.kind, spec.name),
            duplicate_suppression_key = ('run:%s:%s:%d'):format(spec.kind, spec.name, target_id),
            lock_class = spec.target_kind == 'mob' and 'offense_action' or 'support_action',
            expected_ack = 'action_start',
            expected_effect = spec.kind == 'spell' and 'spell_effect' or 'ja_effect',
            sticky = spec.target_kind == 'mob',
            can_preempt_movement = true,
            can_preempt_same_band = false,
            reason_code = spec.reason,
            detail = {
                run_tank = true,
                category = spec.category,
            },
            legacy_command = spec.kind == 'spell'
                and ('input /ma "%s" %s'):format(spec.name, spec.target_kind == 'self' and '<me>' or tostring(target_id))
                or ('input /ja "%s" %s'):format(spec.name, spec.target_kind == 'self' and '<me>' or tostring(target_id)),
        }
        publish('proposed', spec.reason, spec.name, spec.desired_runes, spec.observed_runes)
        return true
    end

    local function rune_state(player, desired)
        local wanted = {}
        local observed = {}
        local status_by_name = {}
        for _, name in ipairs(RUNE_NAMES) do
            local sid = status_id_for_action(name, 'ja')
            if sid <= 0 then
                return nil, nil, nil, 'RUN_RUNE_STATUS_UNKNOWN:' .. name
            end
            status_by_name[name] = sid
            observed[name] = buff_count(player, sid)
        end
        for _, name in ipairs(desired) do wanted[name] = (wanted[name] or 0) + 1 end
        return wanted, observed, status_by_name, nil
    end

    local function missing_rune(player, desired)
        local wanted, observed, _, err = rune_state(player, desired)
        if err then return nil, observed or {}, err end
        local consumed = {}
        for _, name in ipairs(desired) do
            consumed[name] = (consumed[name] or 0) + 1
            if (observed[name] or 0) < consumed[name] then
                return name, observed, nil
            end
        end
        return nil, observed, nil
    end

    local function ward_missing(player, cfg)
        local liement_sid = status_id_for_action('Liement', 'ja')
        local ward_family_blocked = liement_sid > 0 and has_buff(player, liement_sid)
        local vallation_sid = status_id_for_action('Vallation', 'ja')
        local valiance_sid = status_id_for_action('Valiance', 'ja')
        local family_active = has_buff(player, vallation_sid) or has_buff(player, valiance_sid)
        if not ward_family_blocked and not family_active then
            if cfg.wards.vallation then return 'Vallation' end
            if cfg.wards.valiance then return 'Valiance' end
        end
        local ordered = {
            { key = 'pflug', name = 'Pflug' },
            { key = 'battuta', name = 'Battuta' },
            { key = 'swordplay', name = 'Swordplay' },
            { key = 'one_for_all', name = 'One for All' },
        }
        for _, entry in ipairs(ordered) do
            if cfg.wards[entry.key] then
                local sid = status_id_for_action(entry.name, 'ja')
                if sid <= 0 or not has_buff(player, sid) then return entry.name end
            end
        end
        return nil
    end

    function provider.collect(ctx, out)
        require_table(ctx, 'ctx')
        require_table(out, 'out')
        if not bool_setting(rawget(_G, 'Start_Engine')) then return end
        if ctx.player_present ~= true or type(ctx.player) ~= 'table' then return end
        local player = ctx.player
        if tostring(player.main_job or '') ~= 'RUN' then
            publish('inactive', 'RUN_JOB_REQUIRED', '', {}, {})
            return
        end
        if not bool_setting(scheduler_config.tank_enabled(ctx.settings)) then return end
        local cfg = run_config.active(ctx.settings)
        if cfg.enabled ~= true then
            publish('disabled', 'RUN_AUTOMATION_DISABLED', '', cfg.runes.desired, {})
            return
        end
        local engaged = tonumber(player.status) == 1
        if not engaged and not bool_setting(ctx.settings.ability_allow_unengaged) then return end
        local desired = cfg.runes.desired or {}
        local observed = {}

        if cfg.runes.maintain and #desired > 0 then
            local rune, snapshot, rune_err = missing_rune(player, desired)
            observed = snapshot or {}
            if rune_err then
                publish('blocked', rune_err, '', desired, observed)
                log_tank_sched('run_blocked reason=' .. rune_err)
                return
            end
            if rune and ready(rune, tonumber(player.id) or 0, 'ja') then
                add_proposal(ctx, out, {
                    kind = 'ja', name = rune, target_kind = 'self', reason = 'RUN_RUNE_MISSING',
                    category = 'rune', urgency = 0.92, desired_runes = desired, observed_runes = observed,
                })
                return
            elseif rune then
                publish('waiting', 'RUN_RUNE_NOT_READY', rune, desired, observed)
                return
            end
        end

        local ward = ward_missing(player, cfg)
        if ward and ready(ward, tonumber(player.id) or 0, 'ja') then
            add_proposal(ctx, out, {
                kind = 'ja', name = ward, target_kind = 'self', reason = 'RUN_WARD_MISSING',
                category = 'ward', urgency = 0.84, desired_runes = desired, observed_runes = observed,
            })
            return
        end

        if engaged and cfg.foil.enabled then
            local foil_sid = status_id_for_action('Foil', 'spell')
            if foil_sid <= 0 or not has_buff(player, foil_sid) then
                if ready('Foil', tonumber(player.id) or 0, 'spell') then
                    add_proposal(ctx, out, {
                        kind = 'spell', name = 'Foil', target_kind = 'self', reason = 'RUN_FOIL_MISSING',
                        category = 'enmity', urgency = 0.82, desired_runes = desired, observed_runes = observed,
                    })
                    return
                end
            end
        end

        if engaged and #desired == 3 then
            local enemy = current_enemy(ctx)
            if enemy then
                local magic = cfg.magic_support or {}
                for _, entry in ipairs({
                    { key = 'gambit', name = 'Gambit', reason = 'RUN_GAMBIT_READY' },
                    { key = 'rayke', name = 'Rayke', reason = 'RUN_RAYKE_READY' },
                }) do
                    if magic[entry.key] and ready(entry.name, tonumber(enemy.id) or 0, 'ja') then
                        local resource = resource_by_name(res.job_abilities, entry.name)
                        local range = action_effective_range(resource and resource.range or 0)
                        add_proposal(ctx, out, {
                            kind = 'ja', name = entry.name, target_kind = 'mob', target_id = enemy.id,
                            target_name = enemy.name, max_range = range, reason = entry.reason,
                            category = 'magic_support', urgency = 0.72, desired_runes = desired, observed_runes = observed,
                        })
                        return
                    end
                end
            end
        end

        publish('satisfied', 'RUN_SATISFIED', '', desired, observed)
    end

    return provider
end

return M
'''

RUN_TEST = r'''package.path = './?.lua;./?/?.lua;' .. package.path

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
'''

RUN_DOC = r'''# Rune Fencer tank automation

Rune Fencer tank automation extends the existing `combat` tank lane; it does not create a new scheduler domain.

## Ownership

- Existing `tank.enmity.actions` owns reactive enemy-target hate recovery such as `Flash`.
- `tank.run` owns Rune Enchantments, proactive `Foil`, enabled RUN wards, and Gambit/Rayke sequencing.
- Generic defensive buff maintenance continues to own ordinary enhancing magic such as Crusade and Phalanx.
- Reactions continue to own encounter-triggered Liement, Elemental Sforzo, and similar emergency actions.
- When RUN automation owns a JA, the generic configured-JA lane filters that JA so only one policy source can propose it.

## Configuration

```lua
tank = {
    enabled = true,
    enmity = {
        actions = { 'Flash' },
    },
    run = {
        enabled = true,
        runes = {
            maintain = true,
            desired = { 'Ignis', 'Ignis', 'Ignis' },
        },
        foil = { enabled = true },
        wards = {
            vallation = true,
            valiance = false,
            pflug = true,
            swordplay = false,
            battuta = true,
            one_for_all = false,
        },
        magic_support = {
            gambit = true,
            rayke = true,
        },
    },
}
```

The desired rune list must be empty or contain exactly three runes. Vallation and Valiance cannot both be enabled.

## Ordering

The provider emits at most one RUN proposal per scheduler tick. Routine RUN work is priority band 94, immediately below existing tank-enmity recovery at band 96.

The policy order is:

1. converge the configured rune stack;
2. establish Vallation/Valiance and configured wards;
3. maintain Foil while engaged;
4. use Gambit, then rebuild consumed runes;
5. use Rayke, then rebuild consumed runes.

Liement suppresses Vallation/Valiance restoration while Liement is active.

## Deliberate v1 exclusions

Lunge and Swipe are not automated. Exact mixed-rune consumption ordering is therefore not part of the v1 contract. Rune convergence is based on observed player buff slots and fails closed if a configured rune status cannot be resolved.

Runtime diagnostics are published at `_G.UC_RUN_TANK_STATUS`.
'''

RUN_WORKFLOW = r'''name: RUN tank verification

on:
  push:
    branches:
      - feature/run-tank-automation
  pull_request:
    branches:
      - master

jobs:
  lua:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Lua 5.1
        run: sudo apt-get update && sudo apt-get install -y lua5.1
      - name: RUN tank self-test
        run: lua5.1 tests/replay/harness/selftest_run_tank.lua
      - name: Config normalizer self-test
        run: lua5.1 tests/replay/harness/selftest_config_normalizer.lua
      - name: All replay self-tests
        run: lua5.1 tests/replay/harness/selftest_all_replay_fixtures.lua

  winforms:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'
      - name: Build WinForms
        run: dotnet build UnifiedCombatWinForms/UnifiedCombatWinForms.csproj -c Release
      - name: Profile v2 self-test
        run: dotnet run --project UnifiedCombatWinForms/UnifiedCombatWinForms.csproj -c Release --no-build -- --selftest-profile-v2
'''

write('uc_run_config.lua', RUN_CONFIG)
write('uc_run_ownership.lua', RUN_OWNERSHIP)
write('uc_provider_run_tank.lua', RUN_PROVIDER)
write('tests/replay/harness/selftest_run_tank.lua', RUN_TEST)
write('docs/run_tank_automation.md', RUN_DOC)
write('.github/workflows/run-tank-verify.yml', RUN_WORKFLOW)

replace_once(
    'uc_config_normalizer_base.lua',
    "local uc_pup_config = require('uc_pup_config')\n",
    "local uc_pup_config = require('uc_pup_config')\nlocal uc_run_config = require('uc_run_config')\n",
)
replace_once(
    'uc_config_normalizer_base.lua',
    """        tank = {\n            enabled = false,\n            enmity = {\n                actions = {},\n            },\n        },\n""",
    """        tank = {\n            enabled = false,\n            enmity = {\n                actions = {},\n            },\n            run = uc_run_config.default_config(),\n        },\n""",
)
replace_once(
    'uc_config_normalizer_base.lua',
    """local function normalize_tank(source, config)\n    local tank = config.tank\n    local nested = get_path(source, { 'tank' })\n    if is_table(nested) and table_has_any(nested, { 'enabled', 'enmity' }) then\n        tank.enabled = normalize_boolean(nested.enabled, tank.enabled)\n        local enmity = is_table(nested.enmity) and nested.enmity or {}\n        tank.enmity.actions = normalize_list(enmity.actions, tank.enmity.actions)\n    else\n        tank.enabled = normalize_boolean(first_path(source, { path('tank') }), tank.enabled)\n        tank.enmity.actions = normalize_list(first_path(source, { path('tank_enmity_actions') }), tank.enmity.actions)\n    end\nend\n""",
    """local function normalize_tank(source, config)\n    local tank = config.tank\n    local nested = get_path(source, { 'tank' })\n    if is_table(nested) and table_has_any(nested, { 'enabled', 'enmity', 'run' }) then\n        tank.enabled = normalize_boolean(nested.enabled, tank.enabled)\n        local enmity = is_table(nested.enmity) and nested.enmity or {}\n        tank.enmity.actions = normalize_list(enmity.actions, tank.enmity.actions)\n        tank.run = uc_run_config.normalize(nested.run)\n    else\n        tank.enabled = normalize_boolean(first_path(source, { path('tank') }), tank.enabled)\n        tank.enmity.actions = normalize_list(first_path(source, { path('tank_enmity_actions') }), tank.enmity.actions)\n        tank.run = uc_run_config.normalize(nil, source)\n    end\nend\n""",
)

replace_once(
    'uc_active_config.lua',
    """\tif type(config.tank) == 'table' then\n\t\tcandidate.tank = config.tank.enabled\n\t\tif type(config.tank.enmity) == 'table' then\n\t\t\tcandidate.tank_enmity_actions = clone_value(config.tank.enmity.actions)\n\t\tend\n\tend\n""",
    """\tif type(config.tank) == 'table' then\n\t\tcandidate.tank = config.tank.enabled\n\t\tif type(config.tank.enmity) == 'table' then\n\t\t\tcandidate.tank_enmity_actions = clone_value(config.tank.enmity.actions)\n\t\tend\n\t\tif type(config.tank.run) == 'table' then\n\t\t\tcandidate.tank_run = clone_value(config.tank.run)\n\t\tend\n\tend\n""",
)

replace_once(
    'uc_provider_tank_enmity.lua',
    """\tlocal action_ready = require_function(deps, 'action_ready')\n\tlocal log_tank_sched = require_function(deps, 'log_tank_sched')\n\tlocal clamp_urgency = require_function(deps, 'clamp_urgency')\n\n\tlocal provider = {}\n""",
    """\tlocal action_ready = require_function(deps, 'action_ready')\n\tlocal action_effective_range = require_function(deps, 'action_effective_range')\n\tlocal log_tank_sched = require_function(deps, 'log_tank_sched')\n\tlocal clamp_urgency = require_function(deps, 'clamp_urgency')\n\tlocal run_provider = require('uc_provider_run_tank').new({\n\t\taction_ready = action_ready,\n\t\taction_effective_range = action_effective_range,\n\t\tlog_tank_sched = log_tank_sched,\n\t\tclamp_urgency = clamp_urgency,\n\t})\n\n\tlocal provider = {}\n""",
)
replace_once(
    'uc_provider_tank_enmity.lua',
    """\t\tlocal player = ctx.player\n\t\tif ctx.player_present ~= true then\n\t\t\treturn\n\t\tend\n\t\tlocal engaged = tonumber(player.status) == 1\n""",
    """\t\tlocal player = ctx.player\n\t\tif ctx.player_present ~= true then\n\t\t\treturn\n\t\tend\n\t\trun_provider.collect(ctx, out)\n\t\tlocal engaged = tonumber(player.status) == 1\n""",
)

replace_once(
    'unified_scheduler.lua',
    """scheduler.providers.tank_enmity = require('uc_provider_tank_enmity').new({\n\tbool_setting = bool_setting,\n\tselect_tank_enmity = combat_core.select_tank_enmity_for_scheduler,\n\taction_ready = action_ready,\n\tlog_tank_sched = log_tank_sched,\n\tclamp_urgency = p1_clamp_urgency,\n})\n""",
    """scheduler.providers.tank_enmity = require('uc_provider_tank_enmity').new({\n\tbool_setting = bool_setting,\n\tselect_tank_enmity = combat_core.select_tank_enmity_for_scheduler,\n\taction_ready = action_ready,\n\taction_effective_range = action_effective_range,\n\tlog_tank_sched = log_tank_sched,\n\tclamp_urgency = p1_clamp_urgency,\n})\n""",
)

replace_once(
    'uc_provider_combat.lua',
    "\t\tlocal ordered = collect_ordered_abilities(ctx.settings, 6)\n",
    """\t\tlocal ordered = require('uc_run_ownership').filter_generic_abilities(\n\t\t\tctx.settings,\n\t\t\tcollect_ordered_abilities(ctx.settings, 6)\n\t\t)\n""",
)

replace_once(
    'uc_profile_contract.lua',
    "    reaction_ = \"profile_owned_by_ui\",\n",
    "    reaction_ = \"profile_owned_by_ui\",\n    run_tank_ = \"profile_owned_by_ui\",\n",
)

replace_once(
    'tests/replay/harness/selftest_all_replay_fixtures.lua',
    '    "tests/replay/harness/selftest_tank_configured_ja_starvation.lua",\n',
    '    "tests/replay/harness/selftest_tank_configured_ja_starvation.lua",\n    "tests/replay/harness/selftest_run_tank.lua",\n',
)

replace_once(
    'UnifiedCombatWinForms/StructuredProfileV2Writer.cs',
    '''    private static StructuredProfileNode BuildTank(JsonObject flatProfile)\n    {\n        return new StructuredProfileNode()\n            .Add("enabled", ReadBool(flatProfile, "tank", false))\n            .Add("enmity", new StructuredProfileNode().Add("actions", SplitPipeList(ReadString(flatProfile, "tank_enmity_actions", ""))));\n    }\n''',
    '''    private static StructuredProfileNode BuildTank(JsonObject flatProfile)\n    {\n        return new StructuredProfileNode()\n            .Add("enabled", ReadBool(flatProfile, "tank", false))\n            .Add("enmity", new StructuredProfileNode().Add("actions", SplitPipeList(ReadString(flatProfile, "tank_enmity_actions", ""))))\n            .Add("run", BuildRunTank(flatProfile));\n    }\n\n    private static StructuredProfileNode BuildRunTank(JsonObject flatProfile)\n    {\n        var runes = SplitPipeList(ReadString(flatProfile, "run_tank_runes", ""));\n        var canonicalRunes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)\n        {\n            ["Ignis"] = "Ignis", ["Gelus"] = "Gelus", ["Flabra"] = "Flabra", ["Tellus"] = "Tellus",\n            ["Sulpor"] = "Sulpor", ["Unda"] = "Unda", ["Lux"] = "Lux", ["Tenebrae"] = "Tenebrae",\n        };\n        for (var i = 0; i < runes.Count; i++)\n        {\n            var raw = runes[i].Trim();\n            if (!canonicalRunes.TryGetValue(raw, out var canonical))\n            {\n                throw new InvalidDataException($"RUN rune '{raw}' is not a Rune Enchantment.");\n            }\n            runes[i] = canonical;\n        }\n        if (runes.Count != 0 && runes.Count != 3)\n        {\n            throw new InvalidDataException("RUN rune list must be empty or contain exactly three runes.");\n        }\n        var vallation = ReadBool(flatProfile, "run_tank_vallation", false);\n        var valiance = ReadBool(flatProfile, "run_tank_valiance", false);\n        if (vallation && valiance)\n        {\n            throw new InvalidDataException("RUN automation cannot enable both Vallation and Valiance.");\n        }\n        return new StructuredProfileNode()\n            .Add("enabled", ReadBool(flatProfile, "run_tank_enabled", false))\n            .Add("runes", new StructuredProfileNode()\n                .Add("maintain", ReadBool(flatProfile, "run_tank_runes_maintain", true))\n                .Add("desired", runes))\n            .Add("foil", new StructuredProfileNode().Add("enabled", ReadBool(flatProfile, "run_tank_foil", true)))\n            .Add("wards", new StructuredProfileNode()\n                .Add("vallation", vallation)\n                .Add("valiance", valiance)\n                .Add("pflug", ReadBool(flatProfile, "run_tank_pflug", false))\n                .Add("swordplay", ReadBool(flatProfile, "run_tank_swordplay", false))\n                .Add("battuta", ReadBool(flatProfile, "run_tank_battuta", false))\n                .Add("one_for_all", ReadBool(flatProfile, "run_tank_one_for_all", false)))\n            .Add("magic_support", new StructuredProfileNode()\n                .Add("gambit", ReadBool(flatProfile, "run_tank_gambit", false))\n                .Add("rayke", ReadBool(flatProfile, "run_tank_rayke", false)));\n    }\n''',
)

replace_once(
    'UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs',
    '        CopyStringArrayAsPipe(profile, "tank_enmity_actions", "tank_enmity_actions");\n',
    '        CopyStringArrayAsPipe(profile, "tank_enmity_actions", "tank_enmity_actions");\n        FlattenRunTank(profile);\n',
)
replace_once(
    'UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs',
    '''    private static void FlattenCampPulling(JsonObject profile)\n''',
    '''    private static void FlattenRunTank(JsonObject profile)\n    {\n        if (!profile.TryGetPropertyValue("tank_run", out var source) || source is null)\n        {\n            return;\n        }\n        var run = source as JsonObject\n            ?? throw new InvalidDataException("Runtime active config 'tank_run' must be an object.");\n        var runes = RequiredObject(run, "runes", "tank_run.runes");\n        var foil = RequiredObject(run, "foil", "tank_run.foil");\n        var wards = RequiredObject(run, "wards", "tank_run.wards");\n        var magic = RequiredObject(run, "magic_support", "tank_run.magic_support");\n        profile["run_tank_enabled"] = RequiredValue(run, "enabled", "tank_run.enabled");\n        profile["run_tank_runes_maintain"] = RequiredValue(runes, "maintain", "tank_run.runes.maintain");\n        profile["run_tank_runes"] = JoinStringArray(RequiredArray(runes, "desired", "tank_run.runes.desired"), "tank_run.runes.desired");\n        profile["run_tank_foil"] = RequiredValue(foil, "enabled", "tank_run.foil.enabled");\n        foreach (var key in new[] { "vallation", "valiance", "pflug", "swordplay", "battuta", "one_for_all" })\n        {\n            profile[$"run_tank_{key}"] = RequiredValue(wards, key, $"tank_run.wards.{key}");\n        }\n        profile["run_tank_gambit"] = RequiredValue(magic, "gambit", "tank_run.magic_support.gambit");\n        profile["run_tank_rayke"] = RequiredValue(magic, "rayke", "tank_run.magic_support.rayke");\n    }\n\n    private static void FlattenCampPulling(JsonObject profile)\n''',
)

replace_once(
    'UnifiedCombatWinForms/MainForm.ProfileStore.cs',
    '            ["tank_enmity_actions"] = string.Join("|", _tankEnmityRows),\n',
    '''            ["tank_enmity_actions"] = string.Join("|", _tankEnmityRows),\n            ["run_tank_enabled"] = _runTankEnabled.Checked,\n            ["run_tank_runes_maintain"] = _runRunesMaintain.Checked,\n            ["run_tank_runes"] = _runRunes.Text.Trim(),\n            ["run_tank_foil"] = _runFoil.Checked,\n            ["run_tank_vallation"] = _runVallation.Checked,\n            ["run_tank_valiance"] = _runValiance.Checked,\n            ["run_tank_pflug"] = _runPflug.Checked,\n            ["run_tank_swordplay"] = _runSwordplay.Checked,\n            ["run_tank_battuta"] = _runBattuta.Checked,\n            ["run_tank_one_for_all"] = _runOneForAll.Checked,\n            ["run_tank_gambit"] = _runGambit.Checked,\n            ["run_tank_rayke"] = _runRayke.Checked,\n''',
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ProfileStore.cs',
    '            ["tank_enmity_actions"] = "",\n',
    '''            ["tank_enmity_actions"] = "",\n            ["run_tank_enabled"] = false,\n            ["run_tank_runes_maintain"] = true,\n            ["run_tank_runes"] = "",\n            ["run_tank_foil"] = true,\n            ["run_tank_vallation"] = false,\n            ["run_tank_valiance"] = false,\n            ["run_tank_pflug"] = false,\n            ["run_tank_swordplay"] = false,\n            ["run_tank_battuta"] = false,\n            ["run_tank_one_for_all"] = false,\n            ["run_tank_gambit"] = false,\n            ["run_tank_rayke"] = false,\n''',
)

replace_once(
    'UnifiedCombatWinForms/MainForm.ParityUi.cs',
    '''    private Button _tankEnmityDown = null!;\n''',
    '''    private Button _tankEnmityDown = null!;\n    private CheckBox _runTankEnabled = null!;\n    private CheckBox _runRunesMaintain = null!;\n    private TextBox _runRunes = null!;\n    private CheckBox _runFoil = null!;\n    private CheckBox _runVallation = null!;\n    private CheckBox _runValiance = null!;\n    private CheckBox _runPflug = null!;\n    private CheckBox _runSwordplay = null!;\n    private CheckBox _runBattuta = null!;\n    private CheckBox _runOneForAll = null!;\n    private CheckBox _runGambit = null!;\n    private CheckBox _runRayke = null!;\n''',
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ParityUi.cs',
    '''        tankFlow.Controls.Add(tankBtnRow);\n        tankGroup.SetContent(tankFlow);\n''',
    '''        tankFlow.Controls.Add(tankBtnRow);\n\n        tankFlow.Controls.Add(new Label { Text = "Rune Fencer automation", AutoSize = true, Padding = new Padding(0, 10, 0, 2) });\n        _runTankEnabled = new CheckBox { Text = "Enable RUN automation", AutoSize = true };\n        tankFlow.Controls.Add(_runTankEnabled);\n        var runeRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };\n        runeRow.Controls.Add(new Label { Text = "Runes", AutoSize = true, Padding = new Padding(0, 6, 4, 0) });\n        _runRunes = new TextBox { Width = 250, PlaceholderText = "Ignis|Ignis|Ignis" };\n        runeRow.Controls.Add(_runRunes);\n        _runRunesMaintain = new CheckBox { Text = "Maintain", AutoSize = true, Checked = true };\n        runeRow.Controls.Add(_runRunesMaintain);\n        tankFlow.Controls.Add(runeRow);\n        _runFoil = new CheckBox { Text = "Maintain Foil", AutoSize = true, Checked = true };\n        tankFlow.Controls.Add(_runFoil);\n        var wardRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = true };\n        _runVallation = new CheckBox { Text = "Vallation", AutoSize = true };\n        _runValiance = new CheckBox { Text = "Valiance", AutoSize = true };\n        _runPflug = new CheckBox { Text = "Pflug", AutoSize = true };\n        _runBattuta = new CheckBox { Text = "Battuta", AutoSize = true };\n        _runSwordplay = new CheckBox { Text = "Swordplay", AutoSize = true };\n        _runOneForAll = new CheckBox { Text = "One for All", AutoSize = true };\n        wardRow.Controls.Add(_runVallation);\n        wardRow.Controls.Add(_runValiance);\n        wardRow.Controls.Add(_runPflug);\n        wardRow.Controls.Add(_runBattuta);\n        wardRow.Controls.Add(_runSwordplay);\n        wardRow.Controls.Add(_runOneForAll);\n        tankFlow.Controls.Add(wardRow);\n        var magicRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };\n        _runGambit = new CheckBox { Text = "Gambit", AutoSize = true };\n        _runRayke = new CheckBox { Text = "Rayke", AutoSize = true };\n        magicRow.Controls.Add(_runGambit);\n        magicRow.Controls.Add(_runRayke);\n        tankFlow.Controls.Add(magicRow);\n\n        tankGroup.SetContent(tankFlow);\n''',
)

replace_once(
    'UnifiedCombatWinForms/MainForm.ParityLogic.cs',
    '''            _tankEnmityNameCombo.Items.Clear();\n            _tankEnmityNameCombo.Text = "";\n''',
    '''            _tankEnmityNameCombo.Items.Clear();\n            _tankEnmityNameCombo.Text = "";\n            _runTankEnabled.Checked = false;\n            _runRunesMaintain.Checked = true;\n            _runRunes.Text = "";\n            _runFoil.Checked = true;\n            _runVallation.Checked = false;\n            _runValiance.Checked = false;\n            _runPflug.Checked = false;\n            _runSwordplay.Checked = false;\n            _runBattuta.Checked = false;\n            _runOneForAll.Checked = false;\n            _runGambit.Checked = false;\n            _runRayke.Checked = false;\n''',
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ParityLogic.cs',
    '''            if (!SequenceEqualOrdinal(_tankEnmityRows, tankEnmityActions))\n            {\n                _tankEnmityRows = tankEnmityActions.Where(x => !string.IsNullOrWhiteSpace(x)).ToList();\n                RebindTankEnmityListUi();\n            }\n            var pullTypeIncoming = SessionStateHelper.GetString(s, "path_pull_action_type", "ja");\n''',
    '''            if (!SequenceEqualOrdinal(_tankEnmityRows, tankEnmityActions))\n            {\n                _tankEnmityRows = tankEnmityActions.Where(x => !string.IsNullOrWhiteSpace(x)).ToList();\n                RebindTankEnmityListUi();\n            }\n            _runTankEnabled.Checked = SessionStateHelper.GetBool(s, "run_tank_enabled", false);\n            _runRunesMaintain.Checked = SessionStateHelper.GetBool(s, "run_tank_runes_maintain", true);\n            _runRunes.Text = SessionStateHelper.GetString(s, "run_tank_runes");\n            _runFoil.Checked = SessionStateHelper.GetBool(s, "run_tank_foil", true);\n            _runVallation.Checked = SessionStateHelper.GetBool(s, "run_tank_vallation", false);\n            _runValiance.Checked = SessionStateHelper.GetBool(s, "run_tank_valiance", false);\n            _runPflug.Checked = SessionStateHelper.GetBool(s, "run_tank_pflug", false);\n            _runSwordplay.Checked = SessionStateHelper.GetBool(s, "run_tank_swordplay", false);\n            _runBattuta.Checked = SessionStateHelper.GetBool(s, "run_tank_battuta", false);\n            _runOneForAll.Checked = SessionStateHelper.GetBool(s, "run_tank_one_for_all", false);\n            _runGambit.Checked = SessionStateHelper.GetBool(s, "run_tank_gambit", false);\n            _runRayke.Checked = SessionStateHelper.GetBool(s, "run_tank_rayke", false);\n            var pullTypeIncoming = SessionStateHelper.GetString(s, "path_pull_action_type", "ja");\n''',
)

print('RUN tank patch staged')
