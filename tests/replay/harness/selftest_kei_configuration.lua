local normalizer = require('uc_config_normalizer')
local active_config = require('uc_active_config')
local profile_v2 = require('uc_profile_v2')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local function assert_error(fn, expected)
	local ok, err = pcall(fn)
	assert_equal(ok, false, 'expected normalization failure')
	assert_true(tostring(err):find(expected, 1, true) ~= nil, 'unexpected error: ' .. tostring(err))
end

local nested = {
	encounter = {
		enabled = true,
		id = 'kei',
		kei = {
			elemental_damage = {
				dealer_name = 'Nyoo',
				water = { probe_spell = 'Water', damage_spell = 'Water III' },
				ice = { probe_spell = 'Blizzard', damage_spell = 'Blizzard III' },
				sustain_interval_s = 2.5,
				probe_timeout_s = 3.0,
			},
			fullers = { target_distance = 12.0, prearm_hpp_margin = 1.0 },
		},
	},
}
local config = normalizer.normalize(nested)
assert_equal(config.encounter.id, 'kei', 'nested Kei ID')
assert_equal(config.encounter.kei.elemental_damage.dealer_name, 'Nyoo', 'nested dealer')
assert_equal(config.encounter.kei.elemental_damage.water.damage_spell, 'Water III', 'nested Water damage spell')
assert_equal(config.encounter.kei.elemental_damage.ice.probe_spell, 'Blizzard', 'nested Ice probe')
assert_equal(config.encounter.kei.elemental_damage.sustain_interval_s, 2.5, 'nested sustain interval')
assert_equal(config.encounter.kei.fullers.target_distance, 12.0, 'nested Fullers target distance')
assert_equal(config.encounter.kei.fullers.run_away_distance, nil, 'canonical nested config must not retain legacy distance alias')

local projected = assert(active_config.project_flat_settings({
	version = 2,
	profile = {
		schema_version = 2,
		engine = 'UC',
		character = 'Nyoo',
		main_job = 'BLM',
		sub_job = 'RDM',
		source = 'selftest',
	},
	config = config,
}, {}))
assert_equal(projected.kei_fullers_target_distance, 12.0, 'active config must project canonical Fullers target distance')
assert_equal(projected.kei_fullers_run_away_distance, nil, 'active config must not project legacy Fullers distance')
local stale_sortie_projected = assert(active_config.project_flat_settings({
	version = 2,
	profile = {
		schema_version = 2,
		engine = 'UC',
		character = 'Nyoo',
		main_job = 'BLM',
		sub_job = 'RDM',
		source = 'selftest',
	},
	config = config,
}, {
	encounter_water_damage = 'enforce',
	encounter_water_skillchain = 'warn',
	encounter_repeat_action_wall = 'off',
	encounter_repeat_action_guard_s = 10.0,
}))
assert_equal(stale_sortie_projected.encounter_water_damage, nil, 'Kei projection must clear stale Sortie damage policy')
assert_equal(stale_sortie_projected.encounter_water_skillchain, nil, 'Kei projection must clear stale Sortie skillchain policy')
assert_equal(stale_sortie_projected.encounter_repeat_action_wall, nil, 'Kei projection must clear stale Sortie repeat policy')
assert_equal(stale_sortie_projected.encounter_repeat_action_guard_s, nil, 'Kei projection must clear stale Sortie tuning')
local durable = profile_v2.build_durable_config(projected, {
	character = 'Nyoo', main_job = 'BLM', sub_job = 'RDM', source = 'selftest',
})
assert_equal(durable.encounter.policy, nil, 'Kei Profile V2 config must omit inapplicable Sortie policy')
assert_equal(durable.encounter.tuning, nil, 'Kei Profile V2 config must omit inapplicable Sortie tuning')
assert_equal(durable.encounter.kei.fullers.target_distance, 12.0, 'Profile V2 must persist canonical Fullers target distance')
assert_equal(durable.encounter.kei.fullers.run_away_distance, nil, 'Profile V2 must not persist legacy Fullers distance')

local flat = normalizer.normalize({
	encounter_enabled = true,
	encounter_id = 'kei',
	kei_elemental_dealer_name = 'Nyoo',
	kei_water_probe_spell = 'Water',
	kei_water_damage_spell = 'Water III',
	kei_ice_probe_spell = 'Blizzard',
	kei_ice_damage_spell = 'Blizzard III',
	kei_sustain_interval_s = 2.5,
	kei_probe_timeout_s = 3.0,
	kei_fullers_target_distance = 12.0,
	kei_fullers_prearm_hpp_margin = 1.0,
})
assert_equal(flat.encounter.kei.elemental_damage.ice.damage_spell, 'Blizzard III', 'flat configuration round-trip')
assert_equal(flat.encounter.kei.fullers.prearm_hpp_margin, 1.0, 'flat Fullers margin round-trip')
assert_equal(flat.encounter.kei.fullers.target_distance, 12.0, 'flat Fullers target distance round-trip')

local legacy_nested = normalizer.normalize({
	encounter = {
		enabled = true,
		id = 'kei',
		kei = {
			elemental_damage = nested.encounter.kei.elemental_damage,
			fullers = { run_away_distance = 12.0, prearm_hpp_margin = 1.0 },
		},
	},
})
assert_equal(legacy_nested.encounter.kei.fullers.target_distance, 12.0, 'legacy nested Fullers distance must migrate')
assert_equal(legacy_nested.encounter.kei.fullers.run_away_distance, nil, 'legacy nested alias must not survive normalization')

local legacy_flat = normalizer.normalize({
	encounter_enabled = true,
	encounter_id = 'kei',
	kei_elemental_dealer_name = 'Nyoo',
	kei_water_probe_spell = 'Water',
	kei_water_damage_spell = 'Water III',
	kei_ice_probe_spell = 'Blizzard',
	kei_ice_damage_spell = 'Blizzard III',
	kei_sustain_interval_s = 2.5,
	kei_probe_timeout_s = 3.0,
	kei_fullers_run_away_distance = 12.0,
	kei_fullers_prearm_hpp_margin = 1.0,
})
assert_equal(legacy_flat.encounter.kei.fullers.target_distance, 12.0, 'legacy flat Fullers distance must migrate')
assert_equal(legacy_flat.encounter.kei.fullers.run_away_distance, nil, 'legacy flat alias must not survive normalization')

assert_error(function()
	local conflict = {
		encounter = {
			enabled = true,
			id = 'kei',
			kei = {
				elemental_damage = nested.encounter.kei.elemental_damage,
				fullers = {
					target_distance = 12.0,
					run_away_distance = 15.0,
					prearm_hpp_margin = 1.0,
				},
			},
		},
	}
	normalizer.normalize(conflict)
end, 'conflicts with legacy alias')

assert_error(function()
	local conflict = {
		encounter_enabled = true,
		encounter_id = 'kei',
		kei_elemental_dealer_name = 'Nyoo',
		kei_water_probe_spell = 'Water',
		kei_water_damage_spell = 'Water III',
		kei_ice_probe_spell = 'Blizzard',
		kei_ice_damage_spell = 'Blizzard III',
		kei_sustain_interval_s = 2.5,
		kei_probe_timeout_s = 3.0,
		kei_fullers_target_distance = 12.0,
		kei_fullers_run_away_distance = 15.0,
		kei_fullers_prearm_hpp_margin = 1.0,
	}
	normalizer.normalize(conflict)
end, 'conflicts with legacy alias')

local old = normalizer.normalize({
	encounter = {
		enabled = true,
		id = 'sortie_ghatjot',
		policy = { water_damage = 'enforce', water_skillchain = 'enforce', repeat_action_wall = 'off' },
		tuning = { repeat_action_guard_s = 10.0 },
	},
})
assert_equal(old.encounter.id, 'sortie_ghatjot', 'older encounter ID')
assert_equal(old.encounter.kei, nil, 'older profile must not gain Kei configuration')

assert_error(function()
	local invalid = nested
	local saved = invalid.encounter.kei.elemental_damage.ice.damage_spell
	invalid.encounter.kei.elemental_damage.ice.damage_spell = ''
	normalizer.normalize(invalid)
	invalid.encounter.kei.elemental_damage.ice.damage_spell = saved
end, 'all four configured elemental spells')
nested.encounter.kei.elemental_damage.ice.damage_spell = 'Blizzard III'

assert_error(function()
	local duplicate = {
		encounter = nested.encounter,
		reactions = {
			enabled = true,
			rules = {
				{ trigger = 'ability_window', name = 'Dancing Fullers', response = 'run_away', distance = 15.0 },
			},
		},
	}
	normalizer.normalize(duplicate)
end, 'remove the duplicate reaction rule')

io.stdout:write('selftest_kei_configuration: OK\n')
