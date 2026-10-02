local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
	end
end

local fixture = dofile("tests/replay/fixtures/maintenance/mixed_profile_v2_food_flat_brd.lua")
local normalizer = require("uc_config_normalizer")

local config = normalizer.normalize(fixture.input, {
	character = "Redrogue",
	main_job = "BRD",
	sub_job = "WHM",
	source = "phase0_characterization",
})

assert_equal(config.maintenance.food.enabled, fixture.current_characterization.food_enabled, "nested food enabled characterization")
assert_equal(config.maintenance.food.item, fixture.current_characterization.food_item, "nested food item characterization")
assert_equal(config.maintenance.brd.enabled, fixture.current_characterization.brd_enabled, "mixed-shape BRD enabled characterization")
assert_equal(#config.maintenance.brd.songs, fixture.current_characterization.brd_song_count, "mixed-shape BRD song characterization")

local fully_nested = {
	maintenance = {
		brd = {
			enabled = true,
			songs = { "Honor March", "Victory March" },
			use_nitro = true,
		},
		food = {
			enabled = true,
			item = "Grape Daifuku",
		},
	},
}
local nested_config = normalizer.normalize(fully_nested, {
	character = "Redrogue",
	main_job = "BRD",
	sub_job = "WHM",
	source = "phase0_nested_control",
})
assert_equal(nested_config.maintenance.brd.enabled, true, "fully nested BRD control must stay enabled")
assert_equal(#nested_config.maintenance.brd.songs, 2, "fully nested BRD control song count")
assert_equal(nested_config.maintenance.food.enabled, true, "fully nested food control must stay enabled")

io.stdout:write("selftest_profile_v2_mixed_shape_characterization: OK (KNOWN DEFECT: nested maintenance.food currently suppresses legacy flat BRD siblings)\n")
