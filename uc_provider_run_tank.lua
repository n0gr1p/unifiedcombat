local res = require('resources')
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

        local enemy = current_enemy(ctx)
        if cfg.foil.enabled and (engaged or enemy ~= nil) then
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

        if #desired == 3 and enemy then
            local magic = cfg.magic_support or {}
            if (magic.gambit or magic.rayke) and not engaged then
                publish('waiting', 'RUN_MAGIC_SUPPORT_REQUIRES_ENGAGED', '', desired, observed)
                return
            end
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

        publish('satisfied', 'RUN_SATISFIED', '', desired, observed)
    end

    return provider
end

return M
