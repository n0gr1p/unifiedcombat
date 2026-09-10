local res = require('resources')
local extension_config = require('uc_combat_extension_config')

local M = {}

local sequence_locks = {}
local active_sequence_key = nil
local last_transition = 'none'

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function canonical(value)
    return trim(value):lower()
end

local function deep_copy(value, seen)
    if type(value) ~= 'table' then
        return value
    end
    local visited = seen or {}
    if visited[value] then
        return nil
    end
    visited[value] = true
    local out = {}
    for key, inner in pairs(value) do
        out[deep_copy(key, visited)] = deep_copy(inner, visited)
    end
    visited[value] = nil
    return out
end

local function lock_key(actor_id, name)
    return table.concat({ 'ability_window', tostring(actor_id), canonical(name) }, ':')
end

local function sequence_rule(name)
    local wanted = canonical(name)
    local rules = extension_config.reaction_rules()
    for i = 1, #(rules or {}) do
        local rule = rules[i]
        if type(rule) == 'table'
            and rule.trigger == 'ability_window'
            and rule.response == 'use_sequence'
            and canonical(rule.name) == wanted then
            return rule, i
        end
    end
    return nil, nil
end

local function monster_ability_name(act, category)
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

local function local_action_name(act, action_type)
    local category = tonumber(act and act.category) or 0
    local id = tonumber(act and act.param) or 0
    if action_type == 'spell' and category == 4 then
        local spell = id > 0 and res.spells and res.spells[id] or nil
        return trim(spell and spell.en)
    end
    if action_type == 'ja' and (category == 6 or category == 13 or category == 14 or category == 15) then
        local ability = id > 0 and res.job_abilities and res.job_abilities[id] or nil
        return trim(ability and ability.en)
    end
    return ''
end

local function current_sequence()
    if active_sequence_key ~= nil and type(sequence_locks[active_sequence_key]) == 'table' then
        return sequence_locks[active_sequence_key]
    end
    local best = nil
    for _, lock in pairs(sequence_locks) do
        if best == nil
            or (tonumber(lock.started_at) or 0) > (tonumber(best.started_at) or 0)
            or ((tonumber(lock.started_at) or 0) == (tonumber(best.started_at) or 0)
                and tostring(lock.key) < tostring(best.key)) then
            best = lock
        end
    end
    active_sequence_key = best and best.key or nil
    return best
end

local function current_step(lock)
    if type(lock) ~= 'table' or type(lock.steps) ~= 'table' then
        return nil
    end
    return lock.steps[tonumber(lock.step_index) or 1]
end

local function public_lock(lock)
    if type(lock) ~= 'table' then
        return nil
    end
    local out = deep_copy(lock)
    local step = current_step(lock)
    if type(step) == 'table' then
        out.action_type = trim(step.action_type):lower()
        out.action_name = trim(step.action_name)
        out.action_target = trim(step.target):lower()
        out.action_optional = step.optional == true
        out.target_kind = out.action_target == 'self' and 'self' or 'mob'
    else
        out.action_type = nil
        out.action_name = nil
        out.action_target = nil
        out.action_optional = nil
        out.target_kind = nil
    end
    out.step_count = type(lock.steps) == 'table' and #lock.steps or 0
    return out
end

local function release_sequence(lock, reason)
    if type(lock) ~= 'table' then
        return nil
    end
    sequence_locks[lock.key] = nil
    if active_sequence_key == lock.key then
        active_sequence_key = nil
    end
    last_transition = ('release:%s:%s'):format(tostring(reason or 'complete'), tostring(lock.name or ''))
    return public_lock(lock)
end

local function clear_sequence_windows_for_actor(actor_id, keep_key)
    local released = nil
    local id = tonumber(actor_id) or 0
    for key, lock in pairs(sequence_locks) do
        if key ~= keep_key and tonumber(lock.actor_id) == id then
            released = released or release_sequence(lock, 'superseded')
        end
    end
    return released
end

local function clear_base_windows_for_actor(base, actor_id)
    local status = base.status()
    for _, lock in ipairs(type(status) == 'table' and type(status.active) == 'table' and status.active or {}) do
        if lock.trigger == 'ability_window' and tonumber(lock.actor_id) == tonumber(actor_id) then
            base.cancel(lock.key, 'sequence_superseded')
        end
    end
end

local function advance_step(lock, reason)
    lock.step_index = (tonumber(lock.step_index) or 1) + 1
    lock.step_state = 'pending'
    lock.dispatched_actor_id = 0
    lock.dispatched_at = 0
    lock.dispatched_action_type = ''
    lock.dispatched_action_name = ''
    lock.last_step_reason = tostring(reason or 'complete')
    if lock.step_index > #lock.steps then
        return nil, release_sequence(lock, reason or 'sequence_complete')
    end
    last_transition = ('step:%d:%s'):format(lock.step_index, tostring(lock.name or ''))
    return public_lock(lock), nil
end

local function local_sequence_completion(act)
    local lock = current_sequence()
    if type(lock) ~= 'table' or lock.step_state ~= 'dispatched' then
        return nil
    end
    local actor_id = tonumber(act and act.actor_id) or 0
    if actor_id <= 0 or actor_id ~= (tonumber(lock.dispatched_actor_id) or 0) then
        return nil
    end
    local step = current_step(lock)
    if type(step) ~= 'table' then
        return nil
    end
    local action_type = trim(step.action_type):lower()
    local observed_name = local_action_name(act, action_type)
    if observed_name == '' or canonical(observed_name) ~= canonical(step.action_name) then
        return nil
    end
    local activated, released = advance_step(lock, 'step_complete')
    return {
        activated = activated,
        released = released,
        released_target_id = released and (tonumber(released.actor_id) or 0) or nil,
        sequence_step_completed = true,
        completed_action_type = action_type,
        completed_action_name = observed_name,
    }
end

function M.extend(base)
    if type(base) ~= 'table' then
        error('uc_reaction_sequence_runtime requires base reaction runtime')
    end
    if base._sequence_extension_installed == true then
        return base
    end

    local base_on_action = base.on_action
    local base_evaluate = base.evaluate
    local base_prune = base.prune_invalid_ability_windows
    local base_get_action_lock = base.get_action_lock
    local base_blocks_proposal = base.blocks_proposal
    local base_blocks_movement = base.blocks_movement
    local base_owns_movement = base.owns_movement
    local base_requires_disengage = base.requires_disengage
    local base_cancel = base.cancel
    local base_reset = base.reset
    local base_status = base.status

    function base.on_action(act, current_target_id, now, actor_is_valid_enemy)
        local completed = local_sequence_completion(act)
        if completed ~= nil then
            return completed
        end

        local category = tonumber(act and act.category) or 0
        if category == 7 or category == 11 then
            local actor_id = tonumber(act and act.actor_id) or 0
            local ability_name, ability_id = monster_ability_name(act, category)
            if actor_id > 0 and ability_name ~= '' then
                local rule, rule_index = sequence_rule(ability_name)
                local key = lock_key(actor_id, ability_name)
                if category == 7 and rule ~= nil then
                    if actor_is_valid_enemy ~= true then
                        return {}
                    end
                    local ok, err = extension_config.validate_action_rule(rule)
                    if ok ~= true then
                        error(('invalid reaction sequence rule %d: %s'):format(rule_index, tostring(err or 'invalid')))
                    end
                    local released = clear_sequence_windows_for_actor(actor_id, key)
                    clear_base_windows_for_actor(base, actor_id)
                    local lock = {
                        key = key,
                        trigger = 'ability_window',
                        name = trim(rule.name),
                        response = 'use_sequence',
                        actor_id = actor_id,
                        ability_id = ability_id,
                        started_at = tonumber(now) or 0,
                        rule_index = rule_index,
                        steps = deep_copy(rule.steps),
                        step_index = 1,
                        step_state = 'pending',
                        dispatched_actor_id = 0,
                        dispatched_at = 0,
                        dispatched_action_type = '',
                        dispatched_action_name = '',
                    }
                    sequence_locks[key] = lock
                    active_sequence_key = key
                    last_transition = 'ready:' .. ability_name
                    return {
                        activated = public_lock(lock),
                        released = released,
                    }
                end
                if category == 11 and type(sequence_locks[key]) == 'table' then
                    local released = release_sequence(sequence_locks[key], 'ability_window_complete')
                    return {
                        released = released,
                        released_target_id = actor_id,
                    }
                end
            end
        end
        return base_on_action(act, current_target_id, now, actor_is_valid_enemy)
    end

    function base.evaluate(current_target_id, effects, now)
        local lock = current_sequence()
        if type(lock) == 'table' then
            return public_lock(lock), nil
        end
        return base_evaluate(current_target_id, effects, now)
    end

    function base.prune_invalid_ability_windows(actor_is_valid_enemy)
        local released_sequence = nil
        for _, lock in pairs(sequence_locks) do
            if actor_is_valid_enemy(tonumber(lock.actor_id) or 0) ~= true then
                released_sequence = released_sequence or release_sequence(lock, 'actor_unavailable')
            end
        end
        local released_base = base_prune(actor_is_valid_enemy)
        return released_sequence or released_base
    end

    function base.get_action_lock()
        local lock = current_sequence()
        if type(lock) == 'table' then
            return public_lock(lock)
        end
        return base_get_action_lock()
    end

    function base.skip_optional_step(key_value, reason)
        local lock = sequence_locks[tostring(key_value or '')]
        if type(lock) ~= 'table' then
            return nil, 'sequence_not_active'
        end
        if lock.step_state ~= 'pending' then
            return public_lock(lock), 'step_already_dispatched'
        end
        local step = current_step(lock)
        if type(step) ~= 'table' or step.optional ~= true then
            return public_lock(lock), 'step_required'
        end
        local activated, released = advance_step(lock, reason or 'optional_unavailable')
        return activated, released and 'sequence_complete' or 'skipped'
    end

    function base.note_sequence_action_dispatched(key_value, action_type, action_name, target_kind, target_id, player_id, now)
        local lock = sequence_locks[tostring(key_value or '')]
        if type(lock) ~= 'table' then
            return false, 'sequence_not_active'
        end
        if lock.step_state ~= 'pending' then
            return false, 'step_not_pending'
        end
        local step = current_step(lock)
        if type(step) ~= 'table' then
            return false, 'step_missing'
        end
        local expected_type = trim(step.action_type):lower()
        local expected_name = trim(step.action_name)
        local expected_target = trim(step.target):lower()
        local actual_kind = tostring(target_kind or '')
        if tostring(action_type or ''):lower() ~= expected_type
            or canonical(action_name) ~= canonical(expected_name)
            or (expected_target == 'self' and actual_kind ~= 'self')
            or (expected_target == 'actor' and actual_kind ~= 'mob')
            or (expected_target == 'actor' and (tonumber(target_id) or 0) ~= (tonumber(lock.actor_id) or 0)) then
            return false, 'dispatch_does_not_match_current_step'
        end
        local local_id = tonumber(player_id) or 0
        if local_id <= 0 then
            return false, 'player_id_unavailable'
        end
        lock.step_state = 'dispatched'
        lock.dispatched_actor_id = local_id
        lock.dispatched_at = tonumber(now) or 0
        lock.dispatched_action_type = expected_type
        lock.dispatched_action_name = expected_name
        last_transition = ('dispatched:%d:%s'):format(tonumber(lock.step_index) or 1, tostring(lock.name or ''))
        return true, 'dispatched'
    end

    function base.blocks_proposal(lock, proposal)
        if type(lock) == 'table' and tostring(lock.response or '') == 'use_sequence' then
            if type(proposal) ~= 'table' then
                return false
            end
            local authoritative = sequence_locks[tostring(lock.key or '')]
            local step = current_step(authoritative)
            if type(step) ~= 'table' or authoritative.step_state ~= 'pending' then
                return true
            end
            local expected_target = trim(step.target):lower()
            local target_matches = expected_target == 'self'
                and tostring(proposal.target_kind or '') == 'self'
                or expected_target == 'actor'
                    and tostring(proposal.target_kind or '') == 'mob'
                    and (tonumber(proposal.target_id) or 0) == (tonumber(authoritative.actor_id) or 0)
            if tostring(proposal.provider or '') == 'combat'
                and tostring(proposal.family_id or '') == 'combat.reaction.sequence'
                and tostring(proposal.action_type or '') == trim(step.action_type):lower()
                and canonical(proposal.action_name) == canonical(step.action_name)
                and target_matches then
                return false
            end
            -- Atomic sequence ownership: no ordinary support/offense/maintenance
            -- action may enter the lane between setup and the required terminal step.
            return true
        end
        return base_blocks_proposal(lock, proposal)
    end

    function base.blocks_movement(lock)
        if type(lock) == 'table' and tostring(lock.response or '') == 'use_sequence' then
            -- Freeze ordinary movement as soon as an atomic action sequence
            -- activates.  A setup JA such as Elemental Seal can execute while
            -- moving, but its required spell must not lose the ability window
            -- waiting for formation/follow movement to settle afterwards.
            return true
        end
        return base_blocks_movement(lock)
    end

    function base.owns_movement(lock)
        if type(lock) == 'table' and tostring(lock.response or '') == 'use_sequence' then
            return false
        end
        return base_owns_movement(lock)
    end

    function base.requires_disengage(lock, player_status)
        if type(lock) == 'table' and tostring(lock.response or '') == 'use_sequence' then
            return false
        end
        return base_requires_disengage(lock, player_status)
    end

    function base.cancel(key_value, reason)
        local key = tostring(key_value or '')
        local lock = sequence_locks[key]
        if type(lock) == 'table' then
            local released = release_sequence(lock, reason or 'manual')
            return released, public_lock(current_sequence())
        end
        return base_cancel(key_value, reason)
    end

    function base.reset(reason)
        local released_sequence = current_sequence()
        sequence_locks = {}
        active_sequence_key = nil
        last_transition = 'reset:' .. tostring(reason or 'manual')
        local released_base = base_reset(reason)
        return released_sequence and (tonumber(released_sequence.actor_id) or nil) or released_base
    end

    function base.status()
        local status = base_status()
        local active = type(status.active) == 'table' and status.active or {}
        for _, lock in pairs(sequence_locks) do
            active[#active + 1] = public_lock(lock)
        end
        table.sort(active, function(left, right)
            return tostring(left.key or '') < tostring(right.key or '')
        end)
        status.active = active
        if current_sequence() ~= nil then
            status.last_transition = last_transition
        end
        return status
    end

    base._sequence_extension_installed = true
    return base
end

return M
