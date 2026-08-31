local selector = require('uc_ws_selector')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function candidate(id, name, level, path_rank, score)
	return {
		ws_id = id,
		ws_name = name,
		path_rank = path_rank,
		skillchain_level = level,
		progression_score = score,
	}
end

local function winner_name(candidates, configured_primary)
	local winner = selector.select(candidates, configured_primary)
	return winner and winner.ws_name or nil
end

local function test_impulse_drive_regression()
	local vorpal = candidate(117, 'Vorpal Thrust', 2, 0, selector.progression_score(117))
	local camlann = candidate(124, "Camlann's Torment", 2, 0, selector.progression_score(124))
	assert_equal(winner_name({ vorpal, camlann }), "Camlann's Torment", 'later-progression closer must win')
	assert_equal(winner_name({ camlann, vorpal }), "Camlann's Torment", 'closer choice must ignore input order')
end

local function test_skillchain_level_wins()
	local level_three = candidate(117, 'Lower Progression Lv.3', 3, 0, 175)
	local level_two = candidate(126, 'Prime Lv.2', 2, 0, 450)
	assert_equal(winner_name({ level_two, level_three }), 'Lower Progression Lv.3', 'skillchain level must outrank progression')
end

local function test_configured_primary_tie()
	local first = candidate(117, 'First', 2, 0, 175)
	local primary = candidate(118, 'Configured Primary', 2, 0, 175)
	assert_equal(winner_name({ first, primary }, 'Configured Primary'), 'Configured Primary', 'configured primary must break an exact ranking tie')
end

local function test_stable_resource_id_fallback()
	local lower = candidate(117, 'Lower ID', 2, 0, 175)
	local higher = candidate(118, 'Higher ID', 2, 0, 175)
	assert_equal(winner_name({ lower, higher }), 'Lower ID', 'lower resource ID must win the stable fallback')
	assert_equal(winner_name({ higher, lower }), 'Lower ID', 'stable fallback must ignore input order')
end

local function test_selected_target_path_wins()
	local advances_target = candidate(117, 'Advances Target', 2, -1, 175)
	local wrong_path = candidate(126, 'Wrong Path Prime', 4, -2, 450)
	assert_equal(winner_name({ wrong_path, advances_target }), 'Advances Target', 'target-path rank must outrank level and progression')
end

local function test_progression_dataset()
	assert_equal(selector.progression_score('Vorpal Thrust'), 175, 'Vorpal Thrust progression')
	assert_equal(selector.progression_score('Impulse Drive'), 240, 'Impulse Drive progression')
	assert_equal(selector.progression_score('Stardiver'), 357, 'Stardiver progression')
	assert_equal(selector.progression_score("Camlann's Torment"), 400, "Camlann's Torment progression")
	assert_equal(selector.progression_score('Diarmuid'), 450, 'Diarmuid progression')
	assert_equal(selector.progression_score('Unknown Weapon Skill'), 0, 'unknown WS progression')
	assert_equal(selector.progression_score(9999), 0, 'unknown WS ID progression')
end

local function main()
	test_impulse_drive_regression()
	test_skillchain_level_wins()
	test_configured_primary_tie()
	test_stable_resource_id_fallback()
	test_selected_target_path_wins()
	test_progression_dataset()
	io.stdout:write('selftest_ws_selector: OK\n')
end

main()
