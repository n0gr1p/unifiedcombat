local function assert_true(condition, message)
	if not condition then
		error(message or 'assertion failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values are not equal') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function make_helpers()
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
		action_ready = function()
			return true, nil, 'spell'
		end,
		get_spell_resource = function(action_name)
			local spell_ids = {
				['Honor March'] = { id = 1001, type = 'Songs', status = 101 },
				['Victory March'] = { id = 1002, type = 'Songs', status = 102 },
				['Protect'] = { id = 1003, type = 'WhiteMagic', status = 103 },
			}
			return spell_ids[action_name] or nil
		end,
		get_ja_resource = function()
			return nil
		end,
		is_bard_song = function(action_name)
			return action_name == 'Honor March' or action_name == 'Victory March'
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
			['Honor March'] = 1,
			['Victory March'] = 1,
			Protect = 2,
		},
		last_overwrite = {},
		log_debug = nil,
	}
end

local function set_active_profile(active_config, payload)
	local profile, err = active_config.build_active_profile_from_v2_payload(payload, {
		character = 'Audit',
		main_job = 'COR',
		sub_job = 'BRD',
		source = 'UC_PROFILE_V2',
	})
	if not profile then
		error('failed to build active profile: ' .. tostring(err))
	end
	local ok, stored = active_config.set_active_profile(profile)
	if ok ~= true then
		error('failed to set active profile: ' .. tostring(stored))
	end
	return stored
end

local function main()
	local previous_windower = rawget(_G, 'windower')
	local previous_socket = rawget(_G, 'socket')
	local previous_active_profile = rawget(_G, 'UC_ACTIVE_PROFILE')
	local previous_resources = package.loaded['resources']

	package.loaded['uc_active_config'] = nil
	package.loaded['uc_hb_buff_maint'] = nil
	package.loaded['uc_cor_maintenance'] = nil

	rawset(_G, 'socket', {
		gettime = function()
			return 100
		end,
	})

	rawset(_G, 'windower', {
		addon_path = './',
		ffxi = {
			get_player = function()
				return {
					id = 10,
					name = 'Audit',
					main_job = 'COR',
					sub_job = 'BRD',
					status = 0,
					buffs = {},
				}
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
			get_mob_by_id = function()
				return {
					id = 77,
					hpp = 100,
					distance = {
						sqrt = function()
							return 5
						end,
					},
				}
			end,
		},
	})

	package.loaded['resources'] = {
		buffs = {
			[101] = { en = 'Honor March' },
			[102] = { en = 'Victory March' },
			[103] = { en = 'Protect' },
		},
		spells = {},
		job_abilities = {},
	}

	local active_config = require('uc_active_config')
	local hb_buff_maint = require('uc_hb_buff_maint')
	local cor_maintenance = require('uc_cor_maintenance')

	local active_profile = set_active_profile(active_config, {
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Audit',
			main_job = 'COR',
			sub_job = 'BRD',
			source = 'ui',
		},
		config = {
			defensive = {
				enabled = true,
				buffs = {
					enabled = true,
					self_only = false,
					list = 'Honor March|Victory March',
					targeted = {
						{ character = 'Target', buff = 'Victory March' },
					},
					overwrite_enabled = false,
					overwrite_interval = 90,
				},
				thresholds = {
					critical_hpp = 40,
					medium_hpp = 60,
				},
			},
			maintenance = {
				cor = {
					roll_1 = 'Chaos Roll',
					roll_2 = 'Samurai Roll',
					crooked_roll_slot = 0,
					elevens = false,
					luzaf_range_override = false,
					range_require_ids = {},
				},
				brd = { 'Honor March', 'Victory March' },
				geo = { 'Geo-Frailty' },
			},
		},
	})

	assert_equal(active_config.get_path('config.defensive.thresholds.critical_hpp'), 40, 'active defensive critical threshold mismatch')
	assert_equal(active_config.get_path('config.defensive.thresholds.medium_hpp'), 60, 'active defensive medium threshold mismatch')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_1'), 'Chaos Roll', 'active COR roll 1 mismatch')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_2'), 'Samurai Roll', 'active COR roll 2 mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].character, 'Target', 'active targeted buff character mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].buff, 'Victory March', 'active targeted buff name mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd')[1], 'Honor March', 'active BRD maintenance list mismatch')
	assert_equal(active_config.get_path('config.maintenance.geo')[1], 'Geo-Frailty', 'active GEO maintenance list mismatch')

	local projected, project_err = active_config.project_flat_settings(active_profile, {})
	assert_true(projected ~= nil, 'project_flat_settings should succeed')
	assert_true(project_err == nil, 'project_flat_settings should not report an error')
	assert_equal(projected.defensive_critical_hpp, 40, 'projected defensive critical threshold mismatch')
	assert_equal(projected.defensive_medium_hpp, 60, 'projected defensive medium threshold mismatch')
	assert_equal(projected.cor_roll_1, 'Chaos Roll', 'projected COR roll 1 mismatch')
	assert_equal(projected.cor_roll_2, 'Samurai Roll', 'projected COR roll 2 mismatch')
	assert_equal(projected.defensive_targeted_buffs, 'Target:Victory March', 'projected targeted buff string mismatch')
	assert_equal(projected.maintenance_brd[1], 'Honor March', 'projected BRD maintenance list mismatch')
	assert_equal(projected.maintenance_geo[1], 'Geo-Frailty', 'projected GEO maintenance list mismatch')

	local cor_flat = {
		cor_roll_1 = 'Ninja Roll',
		cor_roll_2 = 'Evoker\'s Roll',
		cor_crooked_roll_slot = 0,
		cor_elevens = false,
		cor_luzaf_range_override = false,
		cor_roll_range_require_ids = {},
		abilities = {},
	}
	local cor_action = cor_maintenance.propose(cor_flat)
	assert_true(type(cor_action) == 'table', 'cor maintenance should propose a roll from active config')
	assert_equal(cor_action.action_name, 'Chaos Roll', 'cor maintenance must consume active config rolls')

	local helpers = make_helpers()
	local brd_general_flat = {
		defensive_buffs = 'Protect',
		defensive_targeted_buffs = '',
		defensive_buff_self_only = false,
		defensive_overwrite_enabled = false,
		defensive_overwrite_interval = 15,
	}
	local brd_members = {
		{
			name = 'Audit',
			is_self = true,
			buffs = {},
		},
	}
	local picked = hb_buff_maint.choose(brd_general_flat, brd_members, helpers)
	assert_true(type(picked) == 'table', 'BRD general maintenance should return a candidate')
	assert_equal(picked.spell, 'Honor March', 'BRD general maintenance must prefer the active config list')

	set_active_profile(active_config, {
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Audit',
			main_job = 'BRD',
			sub_job = 'WHM',
			source = 'ui',
		},
		config = {
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
		},
	})

	local targeted_active_flat = {
		defensive_buffs = '',
		defensive_targeted_buffs = 'Target:Honor March',
		defensive_buff_self_only = false,
		defensive_overwrite_enabled = false,
		defensive_overwrite_interval = 15,
	}
	local targeted_active_members = {
		{
			name = 'Target',
			is_self = false,
			buffs = {},
		},
	}
	picked = hb_buff_maint.choose(targeted_active_flat, targeted_active_members, helpers)
	assert_true(type(picked) == 'table', 'BRD structured targeted maintenance should return a candidate')
	assert_equal(picked.spell, 'Victory March', 'BRD structured targeted maintenance must prefer active config targeted entries over the flat compatibility string')

	set_active_profile(active_config, {
		version = 2,
		profile = {
			schema_version = 2,
			engine = 'UC',
			character = 'Audit',
			main_job = 'BRD',
			sub_job = 'WHM',
			source = 'ui',
		},
		config = {
			defensive = {
				buffs = {
					enabled = true,
					self_only = false,
					list = '',
					overwrite_enabled = false,
					overwrite_interval = 90,
				},
			},
		},
	})

	local targeted_flat = {
		defensive_buffs = '',
		defensive_targeted_buffs = 'Target:Victory March',
		defensive_buff_self_only = false,
		defensive_overwrite_enabled = false,
		defensive_overwrite_interval = 15,
	}
	local targeted_members = {
		{
			name = 'Target',
			is_self = false,
			buffs = {},
		},
	}
	local targeted_pick = hb_buff_maint.choose(targeted_flat, targeted_members, helpers)
	assert_true(type(targeted_pick) == 'table', 'BRD targeted maintenance should return a candidate')
	assert_equal(targeted_pick.target.name, 'Target', 'BRD targeted maintenance must honor the target name from the flat compatibility string')
	assert_equal(targeted_pick.spell, 'Victory March', 'BRD targeted maintenance must honor the flat targeted buff entry when no structured path exists')

	rawset(_G, 'windower', previous_windower)
	rawset(_G, 'socket', previous_socket)
	rawset(_G, 'UC_ACTIVE_PROFILE', previous_active_profile)
	package.loaded['resources'] = previous_resources
	package.loaded['uc_active_config'] = nil
	package.loaded['uc_hb_buff_maint'] = nil
	package.loaded['uc_cor_maintenance'] = nil

	io.stdout:write('selftest_profile_v2_runtime_consumers: OK\n')
end

main()
