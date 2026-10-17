-- One durable rule contract for both sequence-lock lifecycle and dispatch.
-- Packet-completed steps keep a copied rule; a changed Profile V2 rule must
-- neither reserve the action lane nor authorize further commands.
local M = {}

local function canonical(value)
    if type(value) ~= 'string' then return '' end
    return (value:match('^%s*(.-)%s*$') or ''):lower()
end

function M.matches(lock, rules)
    if type(lock) ~= 'table' or lock.response ~= 'use_sequence' then
        return false
    end
    local index = tonumber(lock.rule_index) or 0
    local rule = type(rules) == 'table' and index > 0 and rules[index] or nil
    if type(rule) ~= 'table'
        or rule.response ~= 'use_sequence'
        or canonical(rule.trigger) ~= canonical(lock.trigger)
        or canonical(rule.name) ~= canonical(lock.name) then
        return false
    end
    if lock.trigger == 'party_action_complete'
        and (canonical(rule.source_name) ~= canonical(lock.event_actor_name)
            or canonical(rule.action_type) ~= canonical(lock.completed_action_type)
            or canonical(rule.name) ~= canonical(lock.completed_action_name)) then
        return false
    end
    local configured, captured = rule.steps, lock.steps
    if type(configured) ~= 'table' or type(captured) ~= 'table'
        or #configured ~= #captured then
        return false
    end
    for i = 1, #captured do
        local original, current = captured[i], configured[i]
        if type(original) ~= 'table' or type(current) ~= 'table'
            or canonical(original.action_type) ~= canonical(current.action_type)
            or canonical(original.action_name) ~= canonical(current.action_name)
            or canonical(original.target) ~= canonical(current.target)
            or (original.optional == true) ~= (current.optional == true) then
            return false
        end
    end
    return true
end

function M.current(lock)
    -- This canonical-first reader falls back to flats only before a reactions
    -- domain exists. It deliberately does not consult cached sequence state.
    return M.matches(lock, require('uc_combat_extension_config').reaction_rules())
end

return M
