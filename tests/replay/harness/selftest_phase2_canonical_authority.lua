package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message or ('expected true, got ' .. tostring(value)))
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message or ('expected false, got ' .. tostring(value)))
	end
end

local function distance(value)
	return setmetatable({ value = value }, {
		__index = {
			sqrt = function(self)
				return self.value
			end,
		},
	})
end

local function bool_setting(value, default)
	if value == nil then
		return default
	end
	return value == true
end

local function run_food(canonical_enabled, flat_enabled)
	local provider = require('uc_provider_food').new({
		get_items = function()
			return { enabled = true, [1] = { id = 1001, count = 2 } }
		end,
		player_is_moving = function() return false end,
		clamp_urgency = function(v) return v end,
		build_action_command = function(name) return 'item:' .. tostring(name) end,
		buff_resources = {},
		item_resources = { [1001] = { en = 'Grape Daifuku' } },
		priority_band = 50,
	})
	local out = {}
	provider.collect({
		now = 10,
		player = { id = 1, name = 'Tester', buffs = {} },
		config = {
			maintenance = {
				food = { enabled = canonical_enabled, item = 'Grape Daifuku' },
			},
		},
		settings = {
			food_enabled = flat_enabled,
			food_item = flat_enabled and 'Grape Daifuku' or 'Marine Stewpot',
		},
	}, out)
	return out
end

local function run_recurring(canonical_enabled, flat_enabled)
	local previous_engine = rawget(_G, 'Start_Engine')
	rawset(_G, 'Start_Engine', true)
	local provider = require('uc_provider_recurring_spells').new({
		bool_setting = bool_setting,
		get_spell_resource = function(name)
			if name == 'Absorb-TP' then
				return { id = 275, en = 'Absorb-TP', targets = 32, range = 4 }
			end
			return nil
		end,
		action_ready = function() return true, '', 'spell' end,
		action_effective_range = function() return 20 end,
		build_friendly_claims = function() return {}, { [1001] = true } end,
		clamp_urgency = function(v) return v end,
		combat_domain_enabled = function() return true end,
		action_timeline_log = function() end,
		priority_band = 70,
	})
	local out = {}
	provider.collect({
		now = 10,
		config = {
			combat = {
				recurring_spells = {
					enabled = canonical_enabled,
					list = { 'Absorb-TP' },
				},
			},
		},
		settings = {
			recurring_spells_enabled = flat_enabled,
			recurring_spells = flat_enabled and 'Absorb-TP' or 'Cure',
		},
		player_present = true,
		player = { id = 1, status = 1 },
		target_present = true,
		target = {
			id = 900,
			name = 'Colibri',
			valid_target = true,
			spawn_type = 16,
			hpp = 100,
			claim_id = 1001,
		},
	}, out)
	rawset(_G, 'Start_Engine', previous_engine)
	return out
end

local function defensive_provider()
	local members = {
		{ id = 100, name = 'Downed', is_self = false, is_npc = false, spawn_type = 13, hpp = 0 },
	}
	local provider = require('uc_provider_defensive').new({
		bool_setting = bool_setting,
		build_defensive_candidates = function()
			return {
				{
					type = 'cure',
					action_name = 'Cure IV',
					target = { id = 200, name = 'Hurt', hpp = 20, is_self = false },
				},
			}
		end,
		choose_defensive_action = function(candidates)
			return candidates[1], 'canonical_test'
		end,
		action_ready = function(name)
			if name == 'Raise III' or name == 'Cure IV' then
				return true, '', 'spell'
			end
			return false, 'NOT_READY', 'spell'
		end,
		action_range = function() return 20.9 end,
		build_action_command = function(name) return 'cast:' .. tostring(name) end,
		cure_target_allowed = function() return true end,
		clamp_urgency = function(v) return v end,
		get_party_members = function() return members end,
		in_party_cast_range = function() return true end,
		log = function() end,
		critical_cure_priority = 150,
	})
	return provider
end

local function run_defensive_internal(config, settings)
	local provider = defensive_provider()
	local out = {}
	provider.collect_internal({
		now = 10,
		config = config,
		settings = settings,
	}, out)
	return out
end

local function run_resurrection(canonical_enabled, flat_enabled)
	local provider = defensive_provider()
	local function collect(at)
		local out = {}
		provider.collect_resurrection({
			now = at,
			config = {
				defensive = {
					enabled = true,
					resurrection = {
						enabled = canonical_enabled,
						priority = { 'Raise III' },
					},
				},
			},
			settings = {
				defensive_enabled = true,
				defensive_resurrection_enabled = flat_enabled,
				defensive_resurrection_priority = 'Raise',
			},
		}, out)
		return out
	end
	collect(1.0)
	return collect(1.5)
end

local function run_enemy_buff_remove(canonical_remove, flat_remove)
	local provider = require('uc_provider_enemy_buff_removal').new({
		bool_setting = bool_setting,
		log = function() end,
		build_friendly_claims = function() return {}, { [1001] = true } end,
		list_targets = function() return { { target_id = 900 } } end,
		get_effects = function() return { { effect_id = 55 } } end,
		claim_valid = function(id, set) return set[id] == true end,
		is_dispellable = function(id) return id == 55 end,
		dispel_priority = function() return 10 end,
		diag = function() end,
		choose_action = function() return 'Dispel' end,
		effect_label = function() return 'Test Buff' end,
		can_attempt = function() return true, 'attempt-key' end,
		action_ready = function() return true, '', 'spell' end,
		build_action_command = function() return 'dispel' end,
		clamp_urgency = function(v) return v end,
	})
	local out = {}
	provider.collect({
		now = 10,
		config = {
			defensive = {
				enabled = true,
				provider = 'internal',
				enemy_buffs = { remove = canonical_remove },
			},
		},
		settings = {
			defensive_enabled = true,
			defensive_provider = 'internal',
			def_remove_enemy_buffs = flat_remove,
		},
		mobs_by_id = {
			[900] = {
				id = 900,
				name = 'Target',
				spawn_type = 16,
				hpp = 100,
				claim_id = 1001,
				distance = distance(5),
			},
		},
	}, out)
	return out
end

local function run_enemy_debuff(canonical_enabled, flat_enabled)
	local spell = {
		id = 25,
		en = 'Dia III',
		targets = 32,
		status = 134,
		overwrites = {},
	}
	local provider = require('uc_provider_enemy_debuff_maintenance').new({
		bool_setting = bool_setting,
		get_spell_resource = function(name) return name == 'Dia III' and spell or nil end,
		get_spell_by_id = function(id) return id == 25 and spell or nil end,
		build_friendly_claims = function() return {}, { [1001] = true } end,
		claim_valid = function(id, set) return set[id] == true end,
		effect_map = function() return {} end,
		prune_expired = function() end,
		can_attempt = function() return true, 'attempt-key' end,
		action_ready = function() return true, '', 'spell' end,
		build_action_command = function() return 'dia' end,
		clamp_urgency = function(v) return v end,
		log = function() end,
	})
	local out = {}
	provider.collect({
		now = 10,
		config = {
			defensive = {
				enabled = true,
				enemy_debuffs = {
					enabled = canonical_enabled,
					list = 'Dia III',
				},
			},
		},
		settings = {
			defensive_enabled = true,
			def_maintain_enemy_debuffs = flat_enabled,
			defensive_enemy_debuffs = flat_enabled and 'Dia III' or 'Bio III',
		},
		target_id_snapshot = 900,
		mobs_by_id = {
			[900] = {
				id = 900,
				name = 'Target',
				valid_target = true,
				spawn_type = 16,
				hpp = 100,
				claim_id = 1001,
				distance = distance(5),
			},
		},
	}, out)
	return out
end

local function run_cor_maintenance_router()
	local previous_engine = rawget(_G, 'Start_Engine')
	rawset(_G, 'Start_Engine', true)
	local received = nil
	local provider = require('uc_provider_maintenance').new({
		bool_setting = bool_setting,
		log_def_sched = function() end,
		is_city_zone = function() return false end,
		ensure_buff_cache = function() end,
		number = function(v, default) return tonumber(v) or default end,
		clamp_urgency = function(v) return v end,
		action_timeline_action_state_summary = function() return 'idle' end,
		action_timeline_log = function() end,
		cor_propose = function(config)
			received = config
			local cor = config and config.maintenance and config.maintenance.cor or {}
			return {
				action_name = tostring(cor.roll_1 or ''),
				action_type = 'ja',
				target_kind = 'self',
				target_name = 'Corsair',
				target_id = 1,
				urgency = 0.7,
			}
		end,
		get_party_members = function() return {} end,
		action_ready = function() return false, '', 'none' end,
		clear_local_brd_spell_failure = function() end,
		pending_mark_failed = function() end,
		count_matching_buffs = function() return 0 end,
		phase1 = {},
		maintenance_buff_cache = {},
		action_timeline_state = {},
		brd_maintenance_priority = 200,
	})
	local canonical = {
		maintenance = {
			cor = { roll_1 = 'Chaos Roll' },
		},
	}
	local out = {}
	provider.collect({
		now = 10,
		player_present = true,
		player = { id = 1, name = 'Corsair', main_job = 'COR', sub_job = 'DNC', status = 1, buffs = {} },
		config = canonical,
		settings = { cor_roll_1 = 'Ninja Roll' },
	}, out)
	rawset(_G, 'Start_Engine', previous_engine)
	return received, canonical, out
end

local function run_hb_buff()
	local previous_resources = package.loaded.resources
	local previous_metadata = package.loaded.uc_scheduler_action_metadata
	local previous_time = package.loaded.uc_time
	local previous_module = package.loaded.uc_hb_buff_maint
	local previous_windower = rawget(_G, 'windower')
	package.loaded.resources = { buffs = {} }
	package.loaded.uc_scheduler_action_metadata = {
		action_target_mode = function() return 'ally' end,
	}
	package.loaded.uc_time = { gettime = function() return 100 end }
	rawset(_G, 'windower', { addon_path = './' })
	package.loaded.uc_hb_buff_maint = nil
	local hb = require('uc_hb_buff_maint')
	hb._reset_test_state()
	local config = {
		defensive = {
			buffs = {
				list = 'Protect',
				targeted = {},
				self_only = true,
				overwrite_enabled = false,
				overwrite_interval = 150,
			},
		},
		maintenance = { brd = { enabled = false } },
		defensive_buffs = 'Shell',
		defensive_buff_self_only = false,
	}
	local picked = hb.choose(config, {
		{ id = 1, name = 'Tester', is_self = true, buffs = {} },
	}, {
		bool_setting = bool_setting,
		in_party_cast_range = function() return true end,
		is_bard_song = function() return false end,
		action_ready = function() return true, '', 'spell' end,
		get_spell_resource = function(name)
			if name == 'Protect' then return { id = 43, en = 'Protect', status = 40, type = 'WhiteMagic' } end
			if name == 'Shell' then return { id = 48, en = 'Shell', status = 41, type = 'WhiteMagic' } end
			return nil
		end,
		get_ja_resource = function() return nil end,
		attempt_allowed = function() return true end,
		last_overwrite = {},
		pri_default = function(_, b) return b end,
		member_priority = function() return 1 end,
		buff_priority = {},
	})
	package.loaded.resources = previous_resources
	package.loaded.uc_scheduler_action_metadata = previous_metadata
	package.loaded.uc_time = previous_time
	package.loaded.uc_hb_buff_maint = previous_module
	rawset(_G, 'windower', previous_windower)
	return picked
end

local function run_cor_roll()
	local previous_resources = package.loaded.resources
	local previous_time = package.loaded.uc_time
	local previous_module = package.loaded.uc_cor_maintenance
	local previous_windower = rawget(_G, 'windower')
	package.loaded.resources = { job_abilities = {} }
	package.loaded.uc_time = { now = function() return 100 end }
	rawset(_G, 'windower', {
		ffxi = {
			get_player = function()
				return { id = 1, name = 'Corsair', main_job = 'COR', sub_job = 'DNC', status = 0, buffs = {} }
			end,
			get_ability_recasts = function()
				return { [96] = 0, [193] = 0, [194] = 0, [197] = 0, [198] = 0 }
			end,
			get_items = function() return { enabled = false } end,
			get_mob_by_target = function() return nil end,
			get_mob_by_id = function() return nil end,
			get_mob_by_name = function() return nil end,
			get_party = function() return {} end,
		},
	})
	package.loaded.uc_cor_maintenance = nil
	local cor = require('uc_cor_maintenance')
	local action = cor.propose({
		maintenance = {
			cor = {
				roll_1 = 'Chaos Roll',
				roll_2 = 'Samurai Roll',
				crooked_roll_slot = 0,
				elevens = false,
				luzaf_range_override = false,
				range_require_ids = {},
				light_shot_dia = false,
			},
		},
		abilities = { configured = {} },
		cor_roll_1 = 'Ninja Roll',
		cor_roll_2 = "Puppet Roll",
	})
	package.loaded.resources = previous_resources
	package.loaded.uc_time = previous_time
	package.loaded.uc_cor_maintenance = previous_module
	rawset(_G, 'windower', previous_windower)
	return action
end

local function run_geo_authority(canonical_placement, flat_placement)
	local previous_packets = package.loaded.packets
	local previous_resources = package.loaded.resources
	local previous_anchor = package.loaded.uc_camp_anchor
	local previous_active = package.loaded.uc_active_config
	local previous_module = package.loaded.uc_geo_camp_placement
	local previous_windower = rawget(_G, 'windower')
	local previous_settings = rawget(_G, 'UC_SETTINGS')
	local previous_geo_status = rawget(_G, 'UC_GEO_MAINTENANCE_STATUS')
	local previous_place_status = rawget(_G, 'UC_GEO_CAMP_PLACEMENT_STATUS')

	local active_geo = { luopan = { placement = canonical_placement } }
	package.loaded.packets = {
		parse = function()
			return {
				['Target'] = 900,
				['Target Index'] = 50,
				['Category'] = 0x03,
				['Param'] = 818,
				['X Offset'] = 0,
				['Y Offset'] = 0,
				['Z Offset'] = 0,
			}
		end,
		build = function() return 'rewritten' end,
	}
	package.loaded.resources = { spells = { [818] = { id = 818, en = 'Geo-Frailty' } } }
	package.loaded.uc_camp_anchor = {
		resolve_current_anchor = function() return { x = 10, y = 20, z = 5 }, 'CAMP_READY' end,
	}
	package.loaded.uc_active_config = {
		get_path = function(path)
			if path == 'config.maintenance.geo' then return active_geo end
			return nil
		end,
	}
	rawset(_G, 'windower', {
		ffxi = {
			get_mob_by_id = function()
				return { id = 900, index = 50, name = 'Mob', x = 12, y = 23, z = 7 }
			end,
		},
		register_event = function() return 1 end,
	})
	rawset(_G, 'UC_SETTINGS', { maintenance_geo = { luopan = { placement = flat_placement } } })
	rawset(_G, 'UC_GEO_MAINTENANCE_STATUS', {
		state = 'dispatched',
		pending_kind = 'geo',
		pending_spell = 'Geo-Frailty',
	})
	package.loaded.uc_geo_camp_placement = nil
	local placement = require('uc_geo_camp_placement')
	local rewritten = placement.rewrite_outgoing(0x01A, 'raw', false, true)
	local reason = type(rawget(_G, 'UC_GEO_CAMP_PLACEMENT_STATUS')) == 'table'
		and _G.UC_GEO_CAMP_PLACEMENT_STATUS.reason or ''

	package.loaded.packets = previous_packets
	package.loaded.resources = previous_resources
	package.loaded.uc_camp_anchor = previous_anchor
	package.loaded.uc_active_config = previous_active
	package.loaded.uc_geo_camp_placement = previous_module
	rawset(_G, 'windower', previous_windower)
	rawset(_G, 'UC_SETTINGS', previous_settings)
	rawset(_G, 'UC_GEO_MAINTENANCE_STATUS', previous_geo_status)
	rawset(_G, 'UC_GEO_CAMP_PLACEMENT_STATUS', previous_place_status)
	return rewritten, reason
end

local function run_raise_authority(canonical_enabled, flat_enabled)
	local previous_active = package.loaded.uc_active_config
	local previous_time = package.loaded.uc_time
	local previous_packets = package.loaded.packets
	local previous_module = package.loaded.uc_raise_accept
	local previous_windower = rawget(_G, 'windower')
	local previous_settings = rawget(_G, 'UC_SETTINGS')
	local injected = 0
	package.loaded.uc_active_config = {
		get_path = function(path)
			assert_equal(path, 'config.ownership.auto_accept_raise', 'raise canonical path')
			return canonical_enabled
		end,
	}
	package.loaded.uc_time = { now = function() return 100 end }
	package.loaded.packets = {
		parse = function() return { ['Category'] = 0x01 } end,
		new = function(_, _, values) return values end,
		inject = function() injected = injected + 1 end,
	}
	rawset(_G, 'windower', {
		ffxi = {
			get_mob_by_target = function()
				return { id = 1, index = 1, name = 'Dead', status = 2 }
			end,
		},
		add_to_chat = function() end,
	})
	rawset(_G, 'UC_SETTINGS', { auto_accept_raise = flat_enabled })
	package.loaded.uc_raise_accept = nil
	local raise = require('uc_raise_accept')
	raise.reset_runtime()
	local accepted, reason = raise.on_incoming_chunk(0x0F9, 'raw', 100)

	package.loaded.uc_active_config = previous_active
	package.loaded.uc_time = previous_time
	package.loaded.packets = previous_packets
	package.loaded.uc_raise_accept = previous_module
	rawset(_G, 'windower', previous_windower)
	rawset(_G, 'UC_SETTINGS', previous_settings)
	return accepted, reason, injected
end

local function run_recovery_authority(canonical_enabled, flat_enabled)
	local previous_active = package.loaded.uc_active_config
	local previous_module = package.loaded.uc_recovery_hold
	local previous_settings = rawget(_G, 'UC_SETTINGS')
	package.loaded.uc_active_config = {
		get_path = function(path)
			assert_equal(path, 'config.ownership.pause_automation_while_weakened', 'recovery canonical path')
			return canonical_enabled
		end,
	}
	rawset(_G, 'UC_SETTINGS', { pause_automation_while_weakened = flat_enabled })
	package.loaded.uc_recovery_hold = nil
	local recovery = require('uc_recovery_hold')
	local active = recovery.active(nil, { buffs = { 1 } })
	package.loaded.uc_active_config = previous_active
	package.loaded.uc_recovery_hold = previous_module
	rawset(_G, 'UC_SETTINGS', previous_settings)
	return active
end

local cases = {
	{
		name = 'food canonical enabled beats flat disabled',
		run = function()
			local out = run_food(true, false)
			assert_equal(#out, 1, 'food proposal count')
			assert_equal(out[1].action_name, 'Grape Daifuku', 'food action')
		end,
	},
	{
		name = 'food canonical disabled beats flat enabled',
		run = function()
			assert_equal(#run_food(false, true), 0, 'food disabled proposal count')
		end,
	},
	{
		name = 'recurring spell canonical enabled beats flat disabled',
		run = function()
			local out = run_recurring(true, false)
			assert_equal(#out, 1, 'recurring proposal count')
			assert_equal(out[1].action_name, 'Absorb-TP', 'recurring action')
		end,
	},
	{
		name = 'recurring spell canonical disabled beats flat enabled',
		run = function()
			assert_equal(#run_recurring(false, true), 0, 'recurring disabled proposal count')
		end,
	},
	{
		name = 'defensive internal provider and threshold come from canonical config',
		run = function()
			local out = run_defensive_internal({
				defensive = {
					enabled = true,
					provider = 'internal',
					thresholds = { critical_hpp = 35 },
				},
			}, {
				defensive_enabled = false,
				defensive_provider = 'healbot',
				defensive_critical_hpp = 1,
			})
			assert_equal(#out, 1, 'internal defensive proposal count')
			assert_equal(out[1].provider, 'defensive_internal', 'internal defensive provider')
			assert_equal(out[1].priority_band, 150, 'canonical critical threshold')
		end,
	},
	{
		name = 'defensive canonical provider blocks stale flat internal provider',
		run = function()
			local out = run_defensive_internal({
				defensive = {
					enabled = true,
					provider = 'healbot',
					thresholds = { critical_hpp = 35 },
				},
			}, {
				defensive_enabled = true,
				defensive_provider = 'internal',
				defensive_critical_hpp = 99,
			})
			assert_equal(#out, 0, 'canonical healbot selection must block internal provider')
		end,
	},
	{
		name = 'resurrection canonical enabled beats flat disabled',
		run = function()
			local out = run_resurrection(true, false)
			assert_equal(#out, 1, 'resurrection proposal count')
			assert_equal(out[1].action_name, 'Raise III', 'resurrection action')
		end,
	},
	{
		name = 'resurrection canonical disabled beats flat enabled',
		run = function()
			assert_equal(#run_resurrection(false, true), 0, 'resurrection disabled proposal count')
		end,
	},
	{
		name = 'enemy buff removal canonical enabled beats flat disabled',
		run = function()
			local out = run_enemy_buff_remove(true, false)
			assert_equal(#out, 1, 'enemy buff removal proposal count')
			assert_equal(out[1].action_name, 'Dispel', 'enemy buff removal action')
		end,
	},
	{
		name = 'enemy buff removal canonical disabled beats flat enabled',
		run = function()
			assert_equal(#run_enemy_buff_remove(false, true), 0, 'enemy buff removal disabled proposal count')
		end,
	},
	{
		name = 'enemy debuff canonical enabled beats flat disabled',
		run = function()
			local out = run_enemy_debuff(true, false)
			assert_equal(#out, 1, 'enemy debuff proposal count')
			assert_equal(out[1].action_name, 'Dia III', 'enemy debuff action')
		end,
	},
	{
		name = 'enemy debuff canonical disabled beats flat enabled',
		run = function()
			assert_equal(#run_enemy_debuff(false, true), 0, 'enemy debuff disabled proposal count')
		end,
	},
	{
		name = 'maintenance provider routes canonical config to COR',
		run = function()
			local received, canonical, out = run_cor_maintenance_router()
			assert_true(received == canonical, 'COR maintenance must receive ctx.config by identity')
			assert_equal(#out, 1, 'COR routed proposal count')
			assert_equal(out[1].action_name, 'Chaos Roll', 'COR routed canonical action')
		end,
	},
	{
		name = 'defensive buff maintenance ignores flat buff fields',
		run = function()
			local picked = run_hb_buff()
			assert_true(type(picked) == 'table', 'HB buff candidate')
			assert_equal(picked.spell, 'Protect', 'HB canonical buff selection')
		end,
	},
	{
		name = 'COR maintenance ignores flat roll fields',
		run = function()
			local action = run_cor_roll()
			assert_true(type(action) == 'table', 'COR canonical roll action')
			assert_equal(action.action_name, 'Chaos Roll', 'COR canonical roll selection')
		end,
	},
	{
		name = 'GEO camp placement canonical camp beats flat target',
		run = function()
			local rewritten, reason = run_geo_authority('camp', 'target')
			assert_equal(rewritten, 'rewritten', 'GEO canonical camp rewrite')
			assert_equal(reason, 'GEO_CAMP_PACKET_REWRITTEN', 'GEO canonical camp reason')
		end,
	},
	{
		name = 'GEO camp placement canonical target beats flat camp',
		run = function()
			local rewritten, reason = run_geo_authority('target', 'camp')
			assert_equal(rewritten, nil, 'GEO canonical target must not rewrite')
			assert_equal(reason, 'GEO_CAMP_PLACEMENT_DISABLED', 'GEO canonical target reason')
		end,
	},
	{
		name = 'raise acceptance canonical enabled beats flat disabled',
		run = function()
			local accepted, reason, injected = run_raise_authority(true, false)
			assert_true(accepted, 'raise should accept from canonical config')
			assert_equal(reason, 'ACCEPTED', 'raise accepted reason')
			assert_equal(injected, 1, 'raise packet injection count')
		end,
	},
	{
		name = 'raise acceptance canonical disabled beats flat enabled',
		run = function()
			local accepted, reason, injected = run_raise_authority(false, true)
			assert_false(accepted, 'raise should remain disabled from canonical config')
			assert_equal(reason, 'DISABLED', 'raise disabled reason')
			assert_equal(injected, 0, 'raise disabled injection count')
		end,
	},
	{
		name = 'recovery hold canonical enabled beats flat disabled',
		run = function()
			assert_true(run_recovery_authority(true, false), 'canonical recovery hold should activate')
		end,
	},
	{
		name = 'recovery hold canonical disabled beats flat enabled',
		run = function()
			assert_false(run_recovery_authority(false, true), 'canonical recovery hold should remain disabled')
		end,
	},
}

local failures = {}
for index, case in ipairs(cases) do
	local ok, err = pcall(case.run)
	if ok then
		io.stdout:write(('[%02d/%02d] PASS %s\n'):format(index, #cases, case.name))
	else
		failures[#failures + 1] = case.name .. ': ' .. tostring(err)
		io.stdout:write(('[%02d/%02d] FAIL %s\n'):format(index, #cases, case.name))
	end
end

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stdout:write('- ' .. failure .. '\n')
	end
	error(('Phase 2 canonical-authority regression failed: %d/%d case(s)'):format(#failures, #cases))
end

io.stdout:write(('selftest_phase2_canonical_authority: OK (%d contradictory canonical-vs-flat cases)\n'):format(#cases))
