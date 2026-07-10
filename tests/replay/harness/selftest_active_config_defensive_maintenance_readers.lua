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

local function set_active_profile(active_config, config)
    local ok, err = active_config.set_active_profile({
        version = 2,
        profile = {
            schema_version = 2,
            engine = 'UC',
            source = 'selftest',
        },
        config = config or {},
    })
    if ok ~= true then
        error('failed to set active profile: ' .. tostring(err))
    end
end

local function make_hb_helpers()
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
        action_ready = function(action_name)
            if action_name == 'Majesty' then
                return true, nil, 'ja'
            end
            return true, nil, 'spell'
        end,
        get_spell_resource = function(action_name)
            if action_name == 'Protect' then
                return { id = 1, type = 'WhiteMagic', status = 101 }
            end
            return nil
        end,
        get_ja_resource = function(action_name)
            if action_name == 'Majesty' then
                return { id = 621, type = 'JobAbility', status = 102 }
            end
            return nil
        end,
        is_bard_song = function()
            return false
        end,
        attempt_allowed = function()
            return true
        end,
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

local function main()
    local previous_windower = rawget(_G, 'windower')
    local previous_socket = rawget(_G, 'socket')
    local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
    local previous_resources = package.loaded['resources']

    package.loaded['uc_active_config'] = nil
    package.loaded['uc_config_normalizer'] = nil
    package.loaded['uc_hb_buff_maint'] = nil
    package.loaded['uc_cor_maintenance'] = nil

    rawset(_G, 'socket', {
        gettime = function()
            return 100
        end,
    })

    local fake_player = {
        id = 10,
        name = 'Tester',
        main_job = 'COR',
        sub_job = 'WAR',
        status = 0,
        buffs = {},
    }
    local fake_members_by_id = {
        [77] = {
            id = 77,
            hpp = 100,
            distance = {
                sqrt = function()
                    return 5
                end,
            },
        },
    }

    rawset(_G, 'windower', {
        addon_path = './',
        ffxi = {
            get_player = function()
                return fake_player
            end,
            get_ability_recasts = function()
                return {
                    [96] = 0,
                    [193] = 0,
                    [194] = 0,
                    [197] = 0,
                    [198] = 0,
                }
            end,
            get_items = function()
                return { enabled = false }
            end,
            get_mob_by_id = function(id)
                return fake_members_by_id[tonumber(id) or 0]
            end,
        },
    })

    package.loaded['resources'] = {
        buffs = {
            [101] = { en = 'Protect' },
            [102] = { en = 'Majesty' },
        },
        spells = {},
        job_abilities = {},
    }

    local active_config = require('uc_active_config')
    local hb_buff_maint = dofile('uc_hb_buff_maint.lua')
    local cor_maintenance = dofile('uc_cor_maintenance.lua')

    local hb_flat = {
        defensive_buffs = 'Protect',
        defensive_targeted_buffs = '',
        defensive_buff_self_only = false,
        defensive_overwrite_enabled = false,
        defensive_overwrite_interval = 15,
    }

    set_active_profile(active_config, {
        defensive = {
            buffs = {
                enabled = true,
                self_only = false,
                list = 'Majesty',
                overwrite_enabled = true,
                overwrite_interval = 90,
            },
        },
    })
    local picked = hb_buff_maint.choose(hb_flat, {
        {
            name = 'Tester',
            is_self = true,
            buffs = {},
        },
    }, make_hb_helpers())
    assert_true(type(picked) == 'table', 'hb buff maintenance should pick a candidate from active config')
    assert_equal(picked.spell, 'Majesty', 'hb buff maintenance must honor active config buff list when flat settings differ')

    set_active_profile(active_config, {
            defensive = {
                buffs = {
                    enabled = true,
                    self_only = false,
                    list = '',
                    targeted = {
                        { character = 'Target', buff = 'Victory March' },
                    },
                    overwrite_enabled = false,
                overwrite_interval = 90,
            },
        },
    })
    picked = hb_buff_maint.choose(hb_flat, {
        {
            name = 'Target',
            is_self = false,
            buffs = {},
        },
    }, make_hb_helpers())
    assert_true(type(picked) == 'table', 'hb buff maintenance should pick a targeted candidate from active config')
    assert_equal(picked.spell, 'Victory March', 'hb buff maintenance must honor active config targeted buff entries')

    set_active_profile(active_config, {
        defensive = {
            buffs = {},
        },
    })
    picked = hb_buff_maint.choose(hb_flat, {
        {
            name = 'Tester',
            is_self = true,
            buffs = {},
        },
    }, make_hb_helpers())
    assert_true(type(picked) == 'table', 'hb buff maintenance should still pick a fallback candidate when active list path is missing')
    assert_equal(picked.spell, 'Protect', 'hb buff maintenance must preserve flat fallback when the active buff list path is missing')

    local hb_targeted_flat = {
        defensive_buffs = '',
        defensive_targeted_buffs = 'Target:Victory March',
        defensive_buff_self_only = false,
        defensive_overwrite_enabled = false,
        defensive_overwrite_interval = 15,
    }
    set_active_profile(active_config, {
        defensive = {
            buffs = {
                enabled = true,
                self_only = false,
                list = '',
                overwrite_enabled = false,
                overwrite_interval = 90,
            },
        },
    })
    picked = hb_buff_maint.choose(hb_targeted_flat, {
        {
            name = 'Target',
            is_self = false,
            buffs = {},
        },
    }, make_hb_helpers())
    assert_true(type(picked) == 'table', 'hb buff maintenance should still pick a fallback targeted candidate when structured path is missing')
    assert_equal(picked.spell, 'Victory March', 'hb buff maintenance must preserve flat fallback when the active targeted path is missing')

    local hb_self_only_flat = {
        defensive_buffs = 'Protect',
        defensive_targeted_buffs = '',
        defensive_buff_self_only = true,
        defensive_overwrite_enabled = false,
        defensive_overwrite_interval = 15,
    }
    set_active_profile(active_config, {
        defensive = {
            buffs = {
                enabled = true,
                self_only = false,
                list = 'Protect',
            },
        },
    })
    picked = hb_buff_maint.choose(hb_self_only_flat, {
        {
            name = 'Ally',
            is_self = false,
            buffs = {},
        },
    }, make_hb_helpers())
    assert_true(type(picked) == 'table', 'hb buff maintenance should evaluate non-self targets when active self_only differs from flat')
    assert_equal(picked.target.name, 'Ally', 'hb buff maintenance must honor active config self_only gating when flat settings differ')

    local cor_flat = {
        cor_roll_1 = 'Ninja Roll',
        cor_roll_2 = 'Evoker\'s Roll',
        cor_crooked_roll_slot = 0,
        cor_elevens = false,
        cor_luzaf_range_override = false,
        cor_roll_range_require_ids = {},
        abilities = {},
    }

    set_active_profile(active_config, {
        maintenance = {
            cor = {
                roll_1 = 'Chaos Roll',
                roll_2 = 'Samurai Roll',
                crooked_roll_slot = 0,
                elevens = false,
                luzaf_range_override = false,
                range_require_ids = {},
            },
        },
    })
    local action = cor_maintenance.propose(cor_flat)
    assert_true(type(action) == 'table', 'cor maintenance should propose a roll when active config is populated')
    assert_equal(action.action_name, 'Chaos Roll', 'cor maintenance must honor active config roll selection when flat settings differ')

    set_active_profile(active_config, {
        maintenance = {
            cor = {},
        },
    })
    action = cor_maintenance.propose(cor_flat)
    assert_true(type(action) == 'table', 'cor maintenance should still propose a roll when active roll paths are missing')
    assert_equal(action.action_name, 'Ninja Roll', 'cor maintenance must preserve flat fallback when the active roll path is missing')

    set_active_profile(active_config, {
        maintenance = {
            cor = {
                roll_1 = 'Chaos Roll',
                roll_2 = 'Samurai Roll',
                crooked_roll_slot = 1,
                elevens = false,
                luzaf_range_override = false,
                range_require_ids = {},
            },
        },
    })
    action = cor_maintenance.propose(cor_flat)
    assert_true(type(action) == 'table', 'cor maintenance should propose a crooked-roll prep action when configured in active config')
    assert_equal(action.action_name, 'Crooked Cards', 'cor maintenance must honor active config crooked roll slot when flat settings differ')

    rawset(_G, 'windower', previous_windower)
    rawset(_G, 'socket', previous_socket)
    rawset(_G, 'UC_ACTIVE_PROFILE', previous_active_profile)
    package.loaded['resources'] = previous_resources
    package.loaded['uc_hb_buff_maint'] = nil
    package.loaded['uc_cor_maintenance'] = nil
    package.loaded['uc_active_config'] = nil
    package.loaded['uc_config_normalizer'] = nil

    io.stdout:write('selftest_active_config_defensive_maintenance_readers: OK\n')
end

main()
