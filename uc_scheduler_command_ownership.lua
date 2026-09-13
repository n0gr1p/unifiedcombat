local M = {}
local recovery_hold = require('uc_recovery_hold')

local function require_table(value, name)
    if type(value) ~= "table" then
        error(name .. " must be a table")
    end
    return value
end

local function require_function(value, name)
    if type(value) ~= "function" then
        error(name .. " must be a function")
    end
    return value
end

local function timeline_log(event_code, fields, dedupe_key, interval)
    local fn = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
    if type(fn) == 'function' then
        pcall(fn, event_code, fields, dedupe_key, interval)
    end
end

local function local_player_id()
    local windower_ref = rawget(_G, 'windower')
    local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil
    local get_player = type(ffxi) == 'table' and ffxi.get_player or nil
    if type(get_player) ~= 'function' then
        return 0
    end
    local ok, player = pcall(get_player)
    if not ok or type(player) ~= 'table' then
        return 0
    end
    return tonumber(player.id) or 0
end

local function consume_dispatched_reaction_action(intent)
    local meta = type(intent.meta) == 'table' and intent.meta or nil
    if meta == nil then
        return nil
    end

    local action_type = tostring(meta.action_type or ''):lower()
    local action_name = tostring(meta.action_name or '')
    local target_kind = tostring(meta.target_kind or '')
    local target_id = tonumber(meta.target_id) or 0
    if (action_type ~= 'spell' and action_type ~= 'ja') or action_name == '' then
        return nil
    end

    local reaction_runtime = require('uc_reaction_runtime')
    local lock = reaction_runtime.get_action_lock()
    if type(lock) ~= 'table' then
        return nil
    end

    if tostring(lock.response or '') == 'use_sequence' then
        local player_id = local_player_id()
        if target_kind == 'self' and target_id <= 0 then
            target_id = player_id
        end
        local marked, reason = reaction_runtime.note_sequence_action_dispatched(
            lock.key,
            action_type,
            action_name,
            target_kind,
            target_id,
            player_id,
            require('uc_time').now()
        )
        if marked ~= true then
            return nil
        end
        timeline_log('REACTION_SEQUENCE_STEP_DISPATCHED', {
            ability = tostring(lock.name or ''),
            response = 'use_sequence',
            action_type = action_type,
            action = action_name,
            target_kind = target_kind,
            target_id = target_id,
            actor_id = tonumber(lock.actor_id) or 0,
            step_index = tonumber(lock.step_index) or 1,
            step_count = tonumber(lock.step_count) or 0,
            optional = lock.action_optional == true and '1' or '0',
            reason = tostring(reason or 'dispatched'),
        }, ('reaction_sequence_step_dispatched:%s:%d:%d'):format(
            tostring(lock.name or ''),
            tonumber(lock.actor_id) or 0,
            tonumber(lock.step_index) or 1
        ), 0)
        return {
            sequence_step_dispatched = true,
            key = tostring(lock.key or ''),
        }
    end

    if tostring(lock.response or '') ~= 'use_action'
        or target_kind ~= 'mob'
        or tostring(lock.action_type or ''):lower() ~= action_type
        or tostring(lock.action_name or '') ~= action_name
        or (tonumber(lock.actor_id) or 0) ~= target_id then
        return nil
    end

    local released = reaction_runtime.cancel(lock.key, 'action_dispatched')
    if type(released) ~= 'table' then
        return nil
    end

    timeline_log('REACTION_ACTION_RELEASED', {
        ability = tostring(released.name or ''),
        response = 'use_action',
        action_type = action_type,
        action = action_name,
        actor_id = target_id,
        reason = 'action_dispatched',
    }, ('reaction_action_released:%s:%d'):format(
        tostring(released.name or ''),
        target_id
    ), 0)
    return released
end

local function prepare_cor_targeted_utility(intent)
    local meta = type(intent.meta) == 'table' and intent.meta or nil
    if meta == nil
        or tostring(meta.provider or '') ~= 'maintenance_cor'
        or tostring(meta.action_type or '') ~= 'ja'
        or tostring(meta.action_name or '') ~= 'Light Shot' then
        return true, ''
    end
    local cor = require('uc_cor_maintenance')
    if type(cor.resolve_pending_light_shot_target) ~= 'function' then
        return false, 'cor_light_shot_target_resolver_missing'
    end
    local target = cor.resolve_pending_light_shot_target()
    if type(target) ~= 'table' or (tonumber(target.id) or 0) <= 0 then
        return false, 'cor_light_shot_target_stale'
    end
    intent.command = 'input /ja "Light Shot" <t>'
    meta.target_kind = 'mob'
    meta.target_id = tonumber(target.id) or 0
    meta.target_name = tostring(target.name or '')
    return true, ''
end

local function consume_dispatched_cor_targeted_utility(intent)
    local meta = type(intent.meta) == 'table' and intent.meta or nil
    if meta == nil
        or tostring(meta.provider or '') ~= 'maintenance_cor'
        or tostring(meta.action_type or '') ~= 'ja'
        or tostring(meta.action_name or '') ~= 'Light Shot' then
        return false
    end
    local cor = require('uc_cor_maintenance')
    if type(cor.note_light_shot_dispatched) ~= 'function' then
        return false
    end
    return cor.note_light_shot_dispatched(tonumber(meta.target_id) or 0) == true
end

function M.apply_command_ownership(opts)
    opts = require_table(opts, "opts")
    local intent = require_table(opts.intent, "opts.intent")
    local dispatcher = require_table(opts.dispatcher, "opts.dispatcher")
    require_function(dispatcher.dispatch_intent, "opts.dispatcher.dispatch_intent")
    local send_command = require_function(opts.send_command, "opts.send_command")

    local command = opts.command
    local command_present = (command ~= nil and tostring(command) ~= "")
    local status = {
        ownership_enabled = true,
        dispatched = false,
        dispatch_ok = false,
        dispatch_reason = "",
        fallback_used = false,
        command_present = command_present,
        reaction_released = false,
        reaction_key = "",
        reaction_sequence_step_dispatched = false,
    }

    if not command_present then
        status.dispatch_reason = "missing_command"
        return status
    end

    local prepared, prepare_reason = prepare_cor_targeted_utility(intent)
    if not prepared then
        -- Treat a stale current-target/Dia generation as a safe no-op. Because
        -- nothing was dispatched, the generation remains eligible for a later
        -- maintenance tick if it becomes valid again.
        status.dispatch_ok = true
        status.dispatch_reason = prepare_reason
        return status
    end

    status.dispatched = true
    local dispatch_result = dispatcher.dispatch_intent(intent, {
        execute = true,
        send_command = send_command,
    })
    status.dispatch_ok = (type(dispatch_result) == "table" and dispatch_result.ok == true and dispatch_result.executed == true)
    status.dispatch_reason = type(dispatch_result) == "table" and tostring(dispatch_result.reason or "") or "missing_dispatch_result"

    if status.dispatch_ok then
        consume_dispatched_cor_targeted_utility(intent)
        local consumed = consume_dispatched_reaction_action(intent)
        if type(consumed) == 'table' and consumed.sequence_step_dispatched == true then
            status.reaction_sequence_step_dispatched = true
            status.reaction_key = tostring(consumed.key or '')
        elseif type(consumed) == 'table' then
            status.reaction_released = true
            status.reaction_key = tostring(consumed.key or '')
        end
    end

    if not status.dispatch_ok and status.dispatch_reason ~= recovery_hold.BLOCK_REASON then
        error("uc_scheduler_command_ownership dispatcher failed: " .. status.dispatch_reason)
    end

    return status
end

return M
