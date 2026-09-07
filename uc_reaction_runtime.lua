local base = require('uc_reaction_runtime_base')
local res = require('resources')

local M = {}
for key, value in pairs(base) do M[key] = value end

local action_lock = nil

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function canonical(value)
    return trim(value):lower()
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end

local function configured_action_rules()
    local profile = rawget(_G, 'UC_ACTIVE_PROFILE')
    local reactions = type(profile) == 'table' and type(profile.config) == 'table'
        and type(profile.config.reactions) == 'table' and profile.config.reactions or nil
    if type(reactions) ~= 'table' or reactions.enabled ~= true or type(reactions.rules) ~= 'table' then
        return {}
    end
    local out = {}
    for index = 1, #reactions.rules do
        local rule = reactions.rules[index]
        if type(rule) == 'table' and rule.trigger == 'ability_window' and rule.response == 'use_action' then
            out[#out + 1] = {
                rule_index = index,
                name = trim(rule.name),
                action_type = trim(rule.action_type):lower(),
                action_name = trim(rule.action_name),
            }
        end
    end
    return out
end

local function ability_name_from_action(act, category)
    local ability_id = 0
    if category == 7 then
        local target = type(act.targets) == 'table' and act.targets[1] or nil
        local action = target and type(target.actions) == 'table' and target.actions[1] or nil
        ability_id = tonumber(action and action.param) or 0
    elseif category == 11 then
        ability_id = tonumber(act.param) or 0
    end
    local ability = ability_id > 0 and res.monster_abilities and res.monster_abilities[ability_id] or nil
    return trim(ability and ability.en), ability_id
end

local function with_base_rules(fn)
    local profile = rawget(_G, 'UC_ACTIVE_PROFILE')
    local reactions = type(profile) == 'table' and type(profile.config) == 'table'
        and type(profile.config.reactions) == 'table' and profile.config.reactions or nil
    if type(reactions) ~= 'table' or type(reactions.rules) ~= 'table' then return fn() end
    local original = reactions.rules
    local filtered = {}
    for index = 1, #original do
        local rule = original[index]
        if not (type(rule) == 'table' and rule.response == 'use_action') then
            filtered[#filtered + 1] = rule
        end
    end
    reactions.rules = filtered
    local ok, a, b, c = pcall(fn)
    reactions.rules = original
    if not ok then error(a) end
    return a, b, c
end

function M.on_action(act, current_target_id, now, actor_is_valid_enemy)
    local category = type(act) == 'table' and tonumber(act.category) or 0
    if category == 7 or category == 11 then
        local actor_id = tonumber(act.actor_id) or 0
        local ability_name, ability_id = ability_name_from_action(act, category)
        if actor_id > 0 and ability_name ~= '' then
            if category == 7 and action_lock and tonumber(action_lock.actor_id) == actor_id
                and canonical(action_lock.name) ~= canonical(ability_name) then
                action_lock = nil
            end
            if category == 7 and actor_is_valid_enemy == true then
                local rules = configured_action_rules()
                for index = 1, #rules do
                    local rule = rules[index]
                    if canonical(rule.name) == canonical(ability_name) then
                        action_lock = {
                            key = ('ability_window:%d:%s'):format(actor_id, canonical(ability_name)),
                            trigger = 'ability_window',
                            actor_id = actor_id,
                            ability_id = ability_id,
                            name = ability_name,
                            response = 'use_action',
                            action_type = rule.action_type,
                            action_name = rule.action_name,
                            rule_index = rule.rule_index,
                            started_at = tonumber(now) or 0,
                        }
                        break
                    end
                end
            elseif category == 11 and action_lock
                and tonumber(action_lock.actor_id) == actor_id
                and canonical(action_lock.name) == canonical(ability_name) then
                action_lock = nil
            end
        end
    end
    return with_base_rules(function()
        return base.on_action(act, current_target_id, now, actor_is_valid_enemy)
    end)
end

function M.get_action_lock()
    if action_lock then
        local found = false
        local rules = configured_action_rules()
        for index = 1, #rules do
            local rule = rules[index]
            if canonical(rule.name) == canonical(action_lock.name)
                and rule.action_type == action_lock.action_type
                and rule.action_name == action_lock.action_name then
                found = true
                break
            end
        end
        if not found then action_lock = nil end
    end
    return copy(action_lock)
end

function M.reset(reason)
    action_lock = nil
    return with_base_rules(function() return base.reset(reason) end)
end

function M.evaluate(current_target_id, effects, now)
    return with_base_rules(function() return base.evaluate(current_target_id, effects, now) end)
end

function M.effect_watch_set()
    return with_base_rules(function() return base.effect_watch_set() end)
end

function M.status()
    local status = with_base_rules(function() return base.status() end)
    if type(status) == 'table' then status.action_lock = copy(action_lock) end
    return status
end

return M
