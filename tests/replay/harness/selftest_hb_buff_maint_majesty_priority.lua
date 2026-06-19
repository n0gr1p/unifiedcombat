package.loaded['uc_hb_buff_maint'] = nil

windower = windower or {}
windower.addon_path = './'

package.loaded['resources'] = {
    buffs = {
        [101] = { en = 'Protect' },
        [102] = { en = 'Majesty' },
    },
}

local hb_buff_maint = dofile('uc_hb_buff_maint.lua')

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    if not value then
        error(message or 'assert_true failed')
    end
end

local function make_helpers(overrides)
    overrides = overrides or {}
    local ready_map = overrides.ready_map or {}
    local attempt_map = overrides.attempt_map or {}
    local present_buffs = overrides.present_buffs or {}
    local function action_ready(action_name)
        local cfg = ready_map[action_name]
        if cfg == nil then
            return true, nil, action_name == 'Majesty' and 'ja' or 'spell'
        end
        return cfg[1], cfg[2], cfg[3]
    end
    local function attempt_allowed(kind, member_name, action_name)
        local key = tostring(kind) .. '|' .. tostring(member_name) .. '|' .. tostring(action_name)
        if attempt_map[key] == nil then
            return true
        end
        return attempt_map[key]
    end
    local function get_spell_resource(action_name)
        if action_name == 'Protect' then
            return { id = 1, type = 'WhiteMagic', status = 101 }
        end
        return nil
    end
    local function get_ja_resource(action_name)
        if action_name == 'Majesty' then
            return { id = 621, type = 'JobAbility', status = 102 }
        end
        return nil
    end
    return {
        bool_setting = function(value, default)
            if value == nil then
                return default
            end
            return value == true
        end,
        in_party_cast_range = function()
            return true
        end,
        action_ready = action_ready,
        get_spell_resource = get_spell_resource,
        get_ja_resource = get_ja_resource,
        is_bard_song = function()
            return false
        end,
        attempt_allowed = attempt_allowed,
        member_priority = function(member)
            return member.is_self and 1 or 5
        end,
        pri_default = function(member_prio, buff_prio)
            return tonumber(member_prio) + (tonumber(buff_prio) or 0) / 10
        end,
        buff_priority = {
            Protect = 2,
            Majesty = 0,
        },
        last_overwrite = {},
        log_debug = nil,
    }
end

local function make_members(buff_ids)
    return {
        {
            name = 'Terrasjr',
            is_self = true,
            buffs = buff_ids or {},
        },
    }
end

local function main()
    local settings = {
        defensive_buffs = 'Protect|Majesty',
        defensive_targeted_buffs = '',
        defensive_buff_self_only = true,
        defensive_overwrite_enabled = false,
    }

    local picked = hb_buff_maint.choose(settings, make_members({}), make_helpers())
    assert_true(type(picked) == 'table', 'expected a picked buff candidate')
    assert_equal(picked.spell, 'Majesty', 'Majesty must beat an earlier eligible non-Majesty buff')
    assert_equal(picked.action_kind, 'ja', 'Majesty candidate must keep JA action kind')

    picked = hb_buff_maint.choose(settings, make_members({}), make_helpers({
        ready_map = {
            Majesty = { false, 'RECAST', 'ja' },
        },
    }))
    assert_true(type(picked) == 'table', 'expected fallback non-Majesty buff when Majesty is not ready')
    assert_equal(picked.spell, 'Protect', 'non-Majesty first eligible buff must win when Majesty is not ready')

    picked = hb_buff_maint.choose(settings, make_members({ 102 }), make_helpers())
    assert_true(type(picked) == 'table', 'expected fallback non-Majesty buff when Majesty is already active')
    assert_equal(picked.spell, 'Protect', 'non-Majesty first eligible buff must win when Majesty is already present')

    picked = hb_buff_maint.choose(settings, make_members({}), make_helpers({
        attempt_map = {
            ['buff|Terrasjr|Majesty'] = false,
        },
    }))
    assert_true(type(picked) == 'table', 'expected fallback non-Majesty buff when Majesty is attempt-gated')
    assert_equal(picked.spell, 'Protect', 'Majesty must not bypass attempt gate')

    picked = hb_buff_maint.choose(settings, make_members({ 101, 102 }), make_helpers())
    assert_equal(picked, nil, 'no candidate expected when all listed buffs are already present')

    local scheduler_source = io.open('unified_scheduler.lua', 'r')
    local scheduler_text = scheduler_source:read('*a')
    scheduler_source:close()
    assert_true(scheduler_text:find("if majesty_action then", 1, true) ~= nil,
        'defensive chooser must still allow Majesty to beat Cure')
    assert_true(scheduler_text:find("elseif c.buff and ((c.buff.prio + 2) < c.cure.prio) then", 1, true) == nil,
        'ordinary self-buffs must still not beat valid Cure candidates')

    io.stdout:write('selftest_hb_buff_maint_majesty_priority: OK\n')
end

main()
