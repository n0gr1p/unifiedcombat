package.path = './?.lua;' .. package.path

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local normalizer = require('uc_config_normalizer_base')

local defaults = normalizer.default_config()
assert_equal(defaults.tank.enmity.include_pets, false, 'default include_pets')

local flat = normalizer.normalize({
	tank = true,
	tank_enmity_actions = { 'Flash' },
	tank_enmity_include_pets = true,
})
assert_equal(flat.tank.enmity.include_pets, true, 'flat include_pets')

local nested = normalizer.normalize({
	tank = {
		enabled = true,
		enmity = {
			actions = { 'Flash' },
			include_pets = true,
		},
	},
})
assert_equal(nested.tank.enmity.include_pets, true, 'nested include_pets')

package.loaded.uc_scheduler_config = nil
local active_value = false
package.loaded.uc_active_config = {
	get_path = function(path)
		if path == 'config.tank.enmity.include_pets' then
			return active_value
		end
		return nil
	end,
}

local scheduler_config = require('uc_scheduler_config')

assert_equal(
	scheduler_config.tank_enmity_include_pets({}),
	false,
	'active false fallback'
)

active_value = true
assert_equal(
	scheduler_config.tank_enmity_include_pets({}),
	true,
	'active true fallback'
)

active_value = false
assert_equal(
	scheduler_config.tank_enmity_include_pets({ tank_enmity_include_pets = true }),
	false,
	'canonical false overrides stale flat on'
)

active_value = true
assert_equal(
	scheduler_config.tank_enmity_include_pets({ tank_enmity_include_pets = false }),
	true,
	'canonical true overrides stale flat off'
)

print('selftest_tank_pet_enmity_config: OK')
