package.path = './?.lua;' .. package.path

local active_config = require('uc_active_config')
local profile_v2 = require('uc_profile_v2')

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message or 'expected false')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function deep_clone(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, inner in pairs(value) do
		out[deep_clone(key)] = deep_clone(inner)
	end
	return out
end

local meta = {
	character = 'Etamame',
	main_job = 'SAM',
	sub_job = 'DRG',
	source = 'legacy_food_apply_regression',
}

-- Reproduce the Activity Apply failure: the current live session has food
-- enabled, while the saved Profile V2 predates the maintenance.food leaf.
local live_settings = {
	domain_maintenance_enabled = true,
	food_enabled = true,
	food_item = 'Grape Daifuku',
}

local current_profile = active_config.build_active_profile_from_settings(live_settings, meta)
assert_true(current_profile.config.maintenance.food.enabled, 'test setup must start with live food enabled')
assert_equal(current_profile.config.maintenance.food.item, 'Grape Daifuku', 'test setup food item')

local legacy_payload = deep_clone(current_profile)
legacy_payload.config.maintenance.food = nil

local loaded_profile, load_error = active_config.build_active_profile_from_v2_payload(legacy_payload, meta)
assert_true(type(loaded_profile) == 'table', 'legacy Profile V2 should load: ' .. tostring(load_error))
assert_true(type(loaded_profile.config.maintenance.food) == 'table', 'legacy load must materialize maintenance.food')
assert_false(loaded_profile.config.maintenance.food.enabled, 'missing legacy food enabled must default false')
assert_equal(loaded_profile.config.maintenance.food.item, '', 'missing legacy food item must default empty')

local projected, projection_error = active_config.project_flat_settings(loaded_profile, live_settings)
assert_true(type(projected) == 'table', 'legacy Profile V2 should project: ' .. tostring(projection_error))
assert_false(projected.food_enabled, 'legacy apply must replace stale live food_enabled=true')
assert_equal(projected.food_item, '', 'legacy apply must replace stale live food item')

-- This is the same conversion invariant Activity Apply enforces: after
-- canonical Profile V2 -> flat compatibility projection -> durable rebuild,
-- there must be no config mismatch against the saved legacy profile.
local candidate_config = profile_v2.build_durable_config(projected, meta)
local round_trip = profile_v2.diff_durable_config(candidate_config, legacy_payload.config)
assert_equal(round_trip.count, 0, 'legacy food apply must not produce a structured profile conversion mismatch')

io.stdout:write('selftest_profile_v2_legacy_food_apply: OK\n')
