-- Legacy slash commands must edit the active canonical Profile V2, never
-- the legacy global settings mirror. These are active-profile edits; saving is explicit.
local active = require('uc_active_config')
local M = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$') or ''
end

local function require_domain(path)
    if type(active.get_path(path)) ~= 'table' then
        return false, 'CANONICAL_CONFIG_UNAVAILABLE'
    end
    return true
end

function M.fight_leader(op, name, party_id_for_name)
    local ready, reason = require_domain('config.follow.fight')
    if not ready then return false, reason end
    local fight = active.get_path('config.follow.fight')
    if op == 'on' or op == 'off' then
        fight.leader = op == 'on'
        return true, op
    end
    if op == 'clear' then
        return active.replace_name('config.follow.fight.leader_name', '')
    end
    local wanted = trim(name)
    if wanted == '' then return false, 'NAME_REQUIRED' end
    if type(party_id_for_name) ~= 'function' or (tonumber(party_id_for_name(wanted)) or 0) <= 0 then
        return false, 'NOT_IN_PARTY'
    end
    local ok, why = active.replace_name('config.follow.fight.leader_name', wanted)
    if not ok then return false, why end
    fight.leader = true
    return true, wanted
end

function M.add_priority(op, value)
    local path = 'config.targeting.targets'
    local ready, reason = require_domain(path)
    if not ready then return false, reason end
    if op == 'list' then
        local names = active.get_path(path)
        local out = {}
        for i = 1, #names do out[i] = names[i] end
        return true, out
    end
    if op == 'clear' then return active.replace_string_list(path, {}) end
    if op == 'add' then
        local name = trim(value)
        if name == '' then return false, 'NAME_REQUIRED' end
        local ok, result = active.append_string_list(path, name)
        if ok and result == 'ALREADY' then return false, 'ALREADY' end
        return ok, result
    end
    if op == 'remove' then return active.remove_string_list_index(path, value) end
    return false, 'UNKNOWN_OPERATION'
end

function M.sleep(op, value, direction, spell_resource)
    local ready, reason = require_domain('config.sleep')
    if not ready then return false, reason end
    local sleep = active.get_path('config.sleep')
    local path = 'config.sleep.order'
    if op == 'on' or op == 'off' then
        sleep.enabled = op == 'on'
        return true, op
    end
    if op == 'list' then
        local out = {}
        for i = 1, #(sleep.order or {}) do out[i] = sleep.order[i] end
        return true, { enabled = sleep.enabled == true, order = out }
    end
    if type(sleep.order) ~= 'table' then return false, 'CANONICAL_ORDER_UNAVAILABLE' end
    if op == 'clear' then return active.replace_string_list(path, {}) end
    if op == 'remove' then return active.remove_string_list_index(path, value) end
    if op == 'move' then
        local delta = direction == 'up' and -1 or direction == 'down' and 1 or nil
        if delta == nil then return false, 'DIRECTION_REQUIRED' end
        return active.move_string_list_index(path, value, delta)
    end
    if op == 'add' or op == 'set' or op == 'spell' then
        local name = trim(value)
        if name == '' then return false, 'SLEEP_SPELL_EMPTY' end
        if type(spell_resource) ~= 'function' then return false, 'SPELL_RESOURCE_REQUIRED' end
        local canonical = spell_resource(name)
        if type(canonical) ~= 'string' or canonical == '' then
            return false, 'SLEEP_SPELL_UNKNOWN'
        end
        if op == 'add' then
            local ok, result = active.append_string_list(path, canonical)
            if ok and result == 'ALREADY' then return false, 'SLEEP_SPELL_ALREADY' end
            return ok, result
        end
        return active.replace_string_list(path, { canonical })
    end
    return false, 'UNKNOWN_OPERATION'
end

return M
