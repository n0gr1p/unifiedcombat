local M = {}

local REACTION_PET_ACTIONS = {
    assault = true,
    deploy = true,
}

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return value:match('^%s*(.-)%s*$') or ''
end

local function active_config()
    return require('uc_active_config')
end

local function global_settings()
    local settings = rawget(_G, 'UC_SETTINGS')
    return type(settings) == 'table' and settings or {}
end

local function flat_value(settings, key)
    if type(settings) == 'table' and settings[key] ~= nil then
        return settings[key]
    end
    return global_settings()[key]
end

local function has_action_rule(rules)
    if type(rules) ~= 'table' then
        return false
    end
    for i = 1, #rules do
        if type(rules[i]) == 'table'
            and (rules[i].response == 'use_action' or rules[i].response == 'use_sequence') then
            return true
        end
    end
    return false
end

local function reaction_identity(rule)
    if type(rule) ~= 'table' then
        return ''
    end
    return table.concat({
        trim(rule.trigger):lower(),
        trim(rule.source_name):lower(),
        trim(rule.action_type):lower(),
        trim(rule.name):lower(),
        trim(rule.response):lower(),
    }, '\031')
end

local function merge_party_action_rules(active_rules, flat_rules)
    local merged = {}
    local seen = {}
    for i = 1, #(active_rules or {}) do
        local rule = active_rules[i]
        merged[#merged + 1] = rule
        local identity = reaction_identity(rule)
        if identity ~= '' then
            seen[identity] = true
        end
    end
    for i = 1, #(flat_rules or {}) do
        local rule = flat_rules[i]
        if type(rule) == 'table' and rule.trigger == 'party_action_complete' then
            local identity = reaction_identity(rule)
            if identity ~= '' and seen[identity] ~= true then
                merged[#merged + 1] = rule
                seen[identity] = true
            end
        end
    end
    return merged
end

local function validate_sequence_step(step, index, count)
    if type(step) ~= 'table' then
        return false, ('use_sequence step %d must be a table'):format(index)
    end
    local action_type = trim(step.action_type):lower()
    if action_type ~= 'spell' and action_type ~= 'ja' and action_type ~= 'pet' then
        return false, ('use_sequence step %d action_type must be spell, ja, or pet'):format(index)
    end
    local action_name = trim(step.action_name)
    if action_name == '' then
        return false, ('use_sequence step %d requires action_name'):format(index)
    end
    local target = trim(step.target):lower()
    if target ~= 'self' and target ~= 'actor' then
        return false, ('use_sequence step %d target must be self or actor'):format(index)
    end
    if action_type == 'pet' then
        if target ~= 'actor' then
            return false, ('use_sequence step %d pet actions currently require actor target'):format(index)
        end
        if REACTION_PET_ACTIONS[action_name:lower()] ~= true then
            return false, ('use_sequence step %d unsupported pet action: %s'):format(index, action_name)
        end
    end
    if step.optional ~= nil and type(step.optional) ~= 'boolean' then
        return false, ('use_sequence step %d optional must be boolean'):format(index)
    end
    if index == count and step.optional == true then
        return false, 'use_sequence final step must be required'
    end
    return true
end

function M.auto_engage_enabled_from_config(config)
    local combat = type(config) == 'table' and config.combat or nil
    local value = type(combat) == 'table' and combat.auto_engage or nil
    if value == nil then
        return true
    end
    return value ~= false
end

function M.auto_engage_enabled(settings)
    local active_value = active_config().get_path('config.combat.auto_engage')
    if active_value ~= nil then
        return active_value ~= false
    end
    local flat = flat_value(settings, 'auto_engage')
    if flat ~= nil then
        return flat ~= false
    end
    return true
end

function M.magic_burst(settings)
    local spells = active_config().get_path('config.spells')
    local enabled
    local spell
    local mode
    local family
    local max_tier
    if type(spells) == 'table' and spells.magic_burst ~= nil then
        enabled = spells.magic_burst == true
        spell = trim(spells.configured)
        mode = trim(spells.magic_burst_mode):lower()
        family = trim(spells.magic_burst_family):lower()
        max_tier = tonumber(spells.magic_burst_max_tier)
    else
        enabled = flat_value(settings, 'magic_burst_enabled') == true
        spell = trim(flat_value(settings, 'spell'))
        mode = trim(flat_value(settings, 'magic_burst_mode')):lower()
        family = trim(flat_value(settings, 'magic_burst_family')):lower()
        max_tier = tonumber(flat_value(settings, 'magic_burst_max_tier'))
    end
    if mode == '' then mode = 'exact' end
    if family == '' then family = 'spell' end
    if mode ~= 'exact' and mode ~= 'auto' then mode = 'exact' end
    if family ~= 'spell' and family ~= 'ra' and family ~= 'helix' then family = 'spell' end
    max_tier = math.floor(max_tier or 0)
    if max_tier < 0 then max_tier = 0 end
    if max_tier > 5 then max_tier = 5 end
    return {
        enabled = enabled,
        spell = spell,
        mode = mode,
        family = family,
        max_tier = max_tier,
    }
end

function M.reaction_rules()
    local active = active_config().get_path('config.reactions')
    local active_rules = type(active) == 'table' and active.enabled == true and type(active.rules) == 'table'
        and active.rules or nil
    local flat = global_settings()
    local flat_rules = flat.reaction_enabled == true and type(flat.reaction_rules) == 'table'
        and flat.reaction_rules or nil

    -- Structured v2 remains authoritative for existing reactions. Party-action
    -- rules are also merged from the flat UI projection so mixed profiles cannot
    -- lose a newly configured party trigger during the structured-profile
    -- compatibility window.
    if has_action_rule(active_rules) then
        return merge_party_action_rules(active_rules, flat_rules)
    end
    if has_action_rule(flat_rules) then
        return flat_rules
    end
    return active_rules or flat_rules
end

function M.validate_action_rule(rule)
    if type(rule) ~= 'table' then
        return true
    end
    if rule.once_per_instance ~= nil and type(rule.once_per_instance) ~= 'boolean' then
        return false, 'once_per_instance must be boolean'
    end
    if rule.once_per_instance == true
        and rule.trigger ~= 'ability_window'
        and rule.trigger ~= 'party_action_complete' then
        return false, 'once_per_instance reactions require ability_window or party_action_complete trigger'
    end
    if rule.trigger == 'event_window' then
        if rule.response ~= 'stop_attacking' and rule.response ~= 'turn_away' then
            return false, 'event_window supports only stop_attacking or turn_away'
        end
        local activate_event = trim(rule.activate_event):lower()
        if activate_event ~= 'spell_start'
            and activate_event ~= 'ability_start'
            and activate_event ~= 'buff_gained' then
            return false, 'event_window activate_event must be spell_start, ability_start, or buff_gained'
        end
        local release_event = trim(rule.release_event):lower()
        if release_event ~= 'spell_end'
            and release_event ~= 'ability_end'
            and release_event ~= 'buff_lost' then
            return false, 'event_window release_event must be spell_end, ability_end, or buff_lost'
        end
        if trim(rule.name) == '' or trim(rule.release_name) == '' then
            return false, 'event_window requires activation and release names'
        end
        if release_event == 'buff_lost' then
            local timeout = tonumber(rule.confirmation_timeout_seconds)
            if timeout == nil or timeout <= 0 or timeout > 10 then
                return false, 'event_window buff_lost release requires confirmation_timeout_seconds > 0 and <= 10'
            end
        elseif rule.confirmation_timeout_seconds ~= nil then
            return false, 'event_window confirmation timeout is only valid for buff_lost release'
        end
    end
    if rule.hold_smn_rage_until_sequence_complete ~= nil
        and type(rule.hold_smn_rage_until_sequence_complete) ~= 'boolean' then
        return false, 'hold_smn_rage_until_sequence_complete must be boolean'
    end
    if rule.hold_smn_rage_until_sequence_complete == true then
        if rule.trigger ~= 'party_action_complete' or rule.response ~= 'use_sequence' then
            return false, 'SMN Rage hold requires party_action_complete/use_sequence'
        end
        if rule.once_per_instance ~= true then
            return false, 'SMN Rage hold requires once_per_instance=true'
        end
    end
    if rule.trigger == 'party_action_complete' then
        if trim(rule.source_name) == '' then
            return false, 'party_action_complete reactions require source_name'
        end
        local trigger_action_type = trim(rule.action_type):lower()
        if trigger_action_type ~= 'spell' and trigger_action_type ~= 'ja' then
            return false, 'party_action_complete action_type must be spell or ja'
        end
        if trim(rule.name) == '' then
            return false, 'party_action_complete reactions require action name'
        end
    end
    if rule.response == 'use_action' then
        if rule.trigger ~= 'ability_window' then
            return false, 'use_action reactions require ability_window trigger'
        end
        if trim(rule.action_type):lower() ~= 'spell' then
            return false, 'use_action currently supports only spell actions'
        end
        if trim(rule.action_name) == '' then
            return false, 'use_action reactions require action_name'
        end
        return true
    end
    if rule.response ~= 'use_sequence' then
        return true
    end
    if rule.trigger ~= 'ability_window' and rule.trigger ~= 'party_action_complete' then
        return false, 'use_sequence reactions require ability_window or party_action_complete trigger'
    end
    if type(rule.steps) ~= 'table' or #rule.steps == 0 then
        return false, 'use_sequence reactions require at least one step'
    end
    for i = 1, #rule.steps do
        local ok, err = validate_sequence_step(rule.steps[i], i, #rule.steps)
        if not ok then
            return false, err
        end
    end
    return true
end

return M
