local normalizer = require('uc_config_normalizer')

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
			fullers = { run_away_distance = 12.0, prearm_hpp_margin = 1.0 },
		},
	},
}
local config = normalizer.normalize(nested)
assert_equal(config.encounter.id, 'kei', 'nested Kei ID')
assert_equal(config.encounter.kei.elemental_damage.dealer_name, 'Nyoo', 'nested dealer')
assert_equal(config.encounter.kei.elemental_damage.water.damage_spell, 'Water III', 'nested Water damage spell')
assert_equal(config.encounter.kei.elemental_damage.ice.probe_spell, 'Blizzard', 'nested Ice probe')
assert_equal(config.encounter.kei.elemental_damage.sustain_interval_s, 2.5, 'nested sustain interval')
assert_equal(config.encounter.kei.fullers.run_away_distance, 12.0, 'nested Fullers distance')

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
	kei_fullers_run_away_distance = 12.0,
	kei_fullers_prearm_hpp_margin = 1.0,
})
assert_equal(flat.encounter.kei.elemental_damage.ice.damage_spell, 'Blizzard III', 'flat configuration round-trip')
assert_equal(flat.encounter.kei.fullers.prearm_hpp_margin, 1.0, 'flat Fullers margin round-trip')

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
