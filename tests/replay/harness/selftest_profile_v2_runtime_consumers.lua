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
			get_mob_by_target = function()
				return nil
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
			get_mob_by_name = function(name)
				if name == 'Niightsiide' then
					return {
						id = 77,
					}
				end
				return nil
			end,
			get_party = function()
				return {
					p1 = {
						mob = {
							id = 77,
							name = 'Niightsiide',
						},
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
	local uc_ignore = require('uc_ignore')
	local hb_buff_maint = require('uc_hb_buff_maint')
	local cor_maintenance = require('uc_cor_maintenance')
	local runtime_overrides = require('uc_runtime_overrides')

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
			combat = {
				weaponskill = {
					enabled = true,
					primary = 'Savage Blade',
					mode = 'smart',
					minimum_tp = 2000,
					wait_ignore_names = { 'Niightsiide' },
					aftermath_enabled = true,
					aftermath_ws = 'Energy Steal',
				},
			},
			defensive = {
				enabled = true,
				cure = {
					enabled = true,
					min_tier = 3,
					max_tier = 4,
					min_missing_hp = 250,
					ignore_trusts = true,
				},
				buffs = {
					enabled = true,
					self_only = false,
					list = 'Honor March|Victory March',
					targeted = {
						{ character = 'Target', buff = 'Victory March' },
					},
					overwrite_enabled = false,
					overwrite_interval = 150,
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
				brd = {
					enabled = true,
					songs = { 'Honor March', 'Victory March' },
					dummy_songs = {},
					recovery_range_yalms = 14.5,
					recovery_ignore_names = { 'Niightsiide' },
					reposition_for_party_songs = true,
					use_nitro = true,
					use_soul_voice = true,
					use_clarion_call = false,
					use_marcato = false,
					marcato_song = '',
					targeted_songs = {
						{ recipients = { 'Target' }, priority_songs = { 'Victory March' } },
					},
				},
				geo = { 'Geo-Frailty' },
			},
			follow = {
				nyzul = {
					coordinator_name = 'Audit',
					anchor_name = 'Terrasjr',
					parking_order = { 'Niightsiide', 'Nyoourke' },
				},
				fight = {
					leader = true,
					leader_name = 'Niightsiide',
					leader_id = 0,
					min = 3,
					hold_s = 8,
				},
				partner = {
					enabled = false,
					secondary_enabled = false,
					ids = {},
					puller = true,
					puller_name = 'Niightsiide',
					engage_range = 9.5,
					puller_distance_only = false,
				},
			},
			sleep = {
				enabled = true,
				order = { 'Horde Lullaby II' },
				legacy_primary = 'Horde Lullaby II',
				max_target_range = 14.0,
			},
		},
	})

	assert_equal(active_config.get_path('config.defensive.thresholds.critical_hpp'), 40, 'active defensive critical threshold mismatch')
	assert_equal(active_config.get_path('config.defensive.thresholds.medium_hpp'), 60, 'active defensive medium threshold mismatch')
	assert_equal(active_config.get_path('config.combat.weaponskill.aftermath_ws'), 'Energy Steal', 'active aftermath ws mismatch')
	assert_equal(active_config.get_path('config.combat.weaponskill.minimum_tp'), 2000, 'active WS minimum TP mismatch')
	assert_equal(active_config.get_path('config.defensive.cure.max_tier'), 4, 'active defensive cure max tier mismatch')
	assert_equal(active_config.get_path('config.defensive.cure.min_missing_hp'), 250, 'active defensive cure missing hp mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.overwrite_interval'), 150, 'active defensive overwrite interval mismatch')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_1'), 'Chaos Roll', 'active COR roll 1 mismatch')
	assert_equal(active_config.get_path('config.maintenance.cor.roll_2'), 'Samurai Roll', 'active COR roll 2 mismatch')
	assert_equal(active_config.get_path('config.combat.weaponskill.wait_ignore_names')[1], 'Niightsiide', 'active wait ignore name mismatch')
	assert_equal(active_config.get_path('config.follow.fight.leader_name'), 'Niightsiide', 'active fight leader name mismatch')
	assert_equal(active_config.get_path('config.follow.partner.puller_name'), 'Niightsiide', 'active puller name mismatch')
	assert_equal(active_config.get_path('config.follow.partner.engage_range'), 9.5, 'active puller engage range mismatch')
	assert_equal(active_config.get_path('config.follow.nyzul.coordinator_name'), 'Audit', 'active Nyzul coordinator mismatch')
	assert_equal(active_config.get_path('config.follow.nyzul.anchor_name'), 'Terrasjr', 'active Nyzul anchor mismatch')
	assert_equal(active_config.get_path('config.follow.nyzul.parking_order')[2], 'Nyoourke', 'active Nyzul parking order mismatch')
	assert_equal(active_config.get_path('config.sleep.max_target_range'), 14.0, 'active sleep target range mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].character, 'Target', 'active targeted buff character mismatch')
	assert_equal(active_config.get_path('config.defensive.buffs.targeted')[1].buff, 'Victory March', 'active targeted buff name mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd.songs')[1], 'Honor March', 'active BRD maintenance list mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd.recovery_range_yalms'), 14.5, 'active BRD recovery range mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd.recovery_ignore_names')[1], 'Niightsiide', 'active BRD recovery ignore list mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd.reposition_for_party_songs'), true, 'active BRD reposition policy mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd.use_soul_voice'), true, 'active BRD Soul Voice mismatch')
	assert_equal(active_config.get_path('config.maintenance.brd.targeted_songs')[1].recipients[1], 'Target', 'active BRD targeted recipient mismatch')
	assert_equal(active_config.get_path('config.maintenance.geo.geo_spell'), 'Geo-Frailty', 'active GEO maintenance migration mismatch')
	assert_equal(active_config.get_path('config.maintenance.geo.luopan.placement'), 'target', 'active GEO placement migration mismatch')

	local projected, project_err = active_config.project_flat_settings(active_profile, {})
	assert_true(projected ~= nil, 'project_flat_settings should succeed')
	assert_true(project_err == nil, 'project_flat_settings should not report an error')
	assert_equal(projected.aftermath_ws, 'Energy Steal', 'projected aftermath ws mismatch')
	assert_equal(projected.weaponskill_min_tp, 2000, 'projected WS minimum TP mismatch')
	assert_equal(projected.def_heal_max_tier_cure, 4, 'projected defensive cure max tier mismatch')
	assert_equal(projected.def_heal_min_missing_hp, 250, 'projected defensive cure missing hp mismatch')
	assert_equal(projected.defensive_overwrite_interval, 150, 'projected defensive overwrite interval mismatch')
	assert_equal(projected.defensive_critical_hpp, 40, 'projected defensive critical threshold mismatch')
	assert_equal(projected.defensive_medium_hpp, 60, 'projected defensive medium threshold mismatch')
	assert_equal(projected.cor_roll_1, 'Chaos Roll', 'projected COR roll 1 mismatch')
	assert_equal(projected.cor_roll_2, 'Samurai Roll', 'projected COR roll 2 mismatch')
	assert_equal(projected.wait_ignore_names[1], 'Niightsiide', 'projected wait ignore name mismatch')
	assert_equal(projected.ignore[1], 77, 'projected legacy ignore id mismatch')
	assert_equal(projected.fight_leader_name, 'Niightsiide', 'projected fight leader name mismatch')
	assert_equal(projected.fight_leader_id, 77, 'projected fight leader id mismatch')
	assert_equal(projected.fight_leader_selected, 'Niightsiide', 'projected fight leader selected mismatch')
	assert_equal(projected.follow.fight.leader_name, 'Niightsiide', 'projected nested fight leader name mismatch')
	assert_equal(projected.follow.fight.leader_id, 77, 'projected nested fight leader id mismatch')
	assert_equal(projected.puller_name, 'Niightsiide', 'projected puller name mismatch')
	assert_equal(projected.puller_id, 77, 'projected puller id mismatch')
	assert_equal(projected.puller_engage_range, 9.5, 'projected puller engage range mismatch')
	assert_equal(projected.nyzul_coordinator_name, 'Audit', 'projected Nyzul coordinator mismatch')
	assert_equal(projected.nyzul_anchor_name, 'Terrasjr', 'projected Nyzul anchor mismatch')
	assert_equal(projected.nyzul_parking_order[1], 'Niightsiide', 'projected Nyzul parking order mismatch')
	assert_equal(projected.sleep_max_target_range, 14.0, 'projected sleep target range mismatch')
	assert_equal(projected.defensive_targeted_buffs, 'Target:Victory March', 'projected targeted buff string mismatch')
	assert_equal(projected.maintenance_brd.songs[1], 'Honor March', 'projected BRD maintenance list mismatch')
	assert_equal(projected.brd_songs[2], 'Victory March', 'projected BRD flat song list mismatch')
	assert_equal(projected.brd_recovery_range_yalms, 14.5, 'projected BRD recovery range mismatch')
	assert_equal(projected.brd_recovery_ignore_names[1], 'Niightsiide', 'projected BRD recovery ignore list mismatch')
	assert_equal(projected.brd_reposition_for_party_songs, true, 'projected BRD reposition policy mismatch')
	assert_equal(projected.brd_use_soul_voice, true, 'projected BRD Soul Voice mismatch')
	assert_equal(projected.brd_targeted_songs, 'Target:Victory March', 'projected BRD targeted songs mismatch')
	assert_equal(projected.maintenance_geo.geo_spell, 'Geo-Frailty', 'projected GEO maintenance migration mismatch')
	assert_equal(projected.maintenance_geo.luopan.placement, 'target', 'projected GEO placement migration mismatch')
	assert_equal(runtime_overrides.fight_leader_id(projected), 77, 'fight leader helper must resolve the leader name before the id')
	assert_true(uc_ignore.is_name_blocked({ wait_ignore_names = { 'Niightsiide' } }, 'Niightsiide') == true, 'wait ignore helper must block by name')
	assert_true(uc_ignore.is_name_blocked({ wait_ignore_names = { 'Niightsiide' } }, 'Other Ally') == false, 'wait ignore helper must not block unrelated names')

	local cor_flat = {
		cor_roll_1 = 'Ninja Roll',
		cor_roll_2 = 'Evoker\'s Roll',
		cor_crooked_roll_slot = 0,
		cor_elevens = false,
		cor_luzaf_range_override = false,
		cor_roll_range_require_ids = {},
		abilities = {},
	}
	local cor_action = cor_maintenance.propose(active_config.get_config())
	assert_true(type(cor_action) == 'table', 'cor maintenance should propose a roll from active config')
	assert_equal(cor_action.action_name, 'Chaos Roll', 'cor maintenance must consume active config rolls')

	local exact_profile = set_active_profile(active_config, {
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
			combat = {
				weaponskill = {
					enabled = true,
					primary = 'Savage Blade',
					mode = 'smart',
					minimum_tp = 2000,
					aftermath_enabled = true,
					aftermath_ws = 'Energy Steal',
				},
			},
			defensive = {
				enabled = true,
				cure = {
					enabled = true,
					min_tier = 3,
					max_tier = 4,
					min_missing_hp = 250,
					ignore_trusts = true,
				},
				buffs = {
					enabled = true,
					self_only = false,
					list = 'Honor March|Victory March',
					targeted = {
						{ character = 'Target', buff = 'Mage’s Ballad III' },
					},
					overwrite_enabled = false,
					overwrite_interval = 150,
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
				brd = {
					enabled = true,
					songs = { 'Honor March', 'Victory March' },
					dummy_songs = {},
					use_nitro = false,
					use_clarion_call = false,
					use_marcato = false,
					marcato_song = '',
				},
				geo = { 'Geo-Frailty' },
			},
		},
	})
	local exact_projected, exact_project_err = active_config.project_flat_settings(exact_profile, {})
	assert_true(exact_projected ~= nil, 'exact roundtrip project_flat_settings should succeed')
	assert_true(exact_project_err == nil, 'exact roundtrip project_flat_settings should not report an error')
	assert_equal(exact_projected.aftermath_ws, 'Energy Steal', 'exact roundtrip aftermath ws mismatch')
	assert_equal(exact_projected.weaponskill_min_tp, 2000, 'exact roundtrip WS minimum TP mismatch')
	assert_equal(exact_projected.def_heal_max_tier_cure, 4, 'exact roundtrip cure max tier mismatch')
	assert_equal(exact_projected.def_heal_min_missing_hp, 250, 'exact roundtrip cure missing hp mismatch')
	assert_equal(exact_projected.defensive_overwrite_interval, 150, 'exact roundtrip overwrite interval mismatch')
	assert_equal(exact_projected.defensive_targeted_buffs, 'Target:Mage’s Ballad III', 'exact roundtrip targeted buff mismatch')
	local exact_normalized = require('uc_config_normalizer').normalize(exact_projected, {
		character = 'Audit',
		main_job = 'COR',
		sub_job = 'BRD',
	})
	assert_equal(exact_normalized.combat.weaponskill.aftermath_ws, 'Energy Steal', 'exact normalized aftermath ws mismatch')
	assert_equal(exact_normalized.combat.weaponskill.minimum_tp, 2000, 'exact normalized WS minimum TP mismatch')
	assert_equal(exact_normalized.defensive.cure.max_tier, 4, 'exact normalized cure max tier mismatch')
	assert_equal(exact_normalized.defensive.cure.min_missing_hp, 250, 'exact normalized cure missing hp mismatch')
	assert_equal(exact_normalized.defensive.buffs.overwrite_interval, 150, 'exact normalized overwrite interval mismatch')
	assert_equal(exact_normalized.defensive.buffs.targeted[1].buff, 'Mage’s Ballad III', 'exact normalized targeted buff mismatch')

	local normalized = require('uc_config_normalizer').normalize(projected, {
		character = 'Audit',
		main_job = 'COR',
		sub_job = 'BRD',
	})
	assert_equal(normalized.combat.weaponskill.aftermath_ws, 'Energy Steal', 'normalized aftermath ws mismatch')
	assert_equal(normalized.combat.weaponskill.minimum_tp, 2000, 'normalized WS minimum TP mismatch')
	assert_equal(normalized.defensive.cure.max_tier, 4, 'normalized cure max tier mismatch')
	assert_equal(normalized.defensive.cure.min_missing_hp, 250, 'normalized cure missing hp mismatch')
	assert_equal(normalized.defensive.buffs.overwrite_interval, 150, 'normalized overwrite interval mismatch')
	assert_equal(normalized.defensive.buffs.targeted[1].buff, 'Victory March', 'normalized targeted buff mismatch')

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
	local picked = hb_buff_maint.choose(active_config.get_config(), brd_members, helpers)
	assert_true(picked == nil, 'dedicated BRD maintenance must own songs instead of defensive_internal')

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
	picked = hb_buff_maint.choose(active_config.get_config(), targeted_active_members, helpers)
	assert_true(type(picked) == 'table', 'legacy targeted maintenance should remain available when dedicated BRD maintenance is absent')
	assert_equal(picked.spell, 'Victory March', 'structured targeted maintenance must prefer active config targeted entries over the flat compatibility string')

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
	local targeted_pick = hb_buff_maint.choose(active_config.get_config(), targeted_members, helpers)
	assert_equal(targeted_pick, nil, 'BRD targeted maintenance must not consult flat compatibility when canonical targeted config is absent')

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
