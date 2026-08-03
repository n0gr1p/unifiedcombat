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

local function main()
	package.loaded.uc_sch_action_observer = nil
	local observer = require('uc_sch_action_observer')
	local function spell_name(id)
		if id == 504 then
			return 'Regen V'
		end
		if id == 4 then
			return 'Cure IV'
		end
		return nil
	end
	local function ability_name(id)
		if id == 218 then
			return 'Accession'
		end
		return nil
	end
	local cast = observer.classify({ actor_id = 1001, category = 8, param = 504 }, 1001, spell_name, ability_name)
	assert_equal(cast.action_type, 'spell', 'spell classification mismatch')
	assert_equal(cast.action_name, 'Regen V', 'spell name mismatch')
	assert_equal(cast.phase, 'cast_start', 'spell phase mismatch')
	local ability = observer.classify({ actor_id = 1001, category = 6, param = 218 }, 1001, spell_name, ability_name)
	assert_equal(ability.action_type, 'job_ability', 'ability classification mismatch')
	assert_equal(ability.action_name, 'Accession', 'ability name mismatch')
	local unknown = observer.classify({ actor_id = 1001, category = 4, param = 9999 }, 1001, spell_name, ability_name)
	assert_true(not unknown.recognized and unknown.action_name == '', 'unknown spell must remain explicit')
	assert_true(observer.classify({ actor_id = 2000, category = 4, param = 504 }, 1001, spell_name, ability_name) == nil,
		'other actors must not produce local observations')
	assert_true(observer.classify({ actor_id = 1001, category = 1, param = 0 }, 1001, spell_name, ability_name) == nil,
		'non-action categories must be ignored')

	local invalid_ok = pcall(observer.classify,
		{ actor_id = 1001, category = 4, param = '504' },
		1001,
		spell_name,
		ability_name)
	assert_true(not invalid_ok, 'coerced action ids must fail fast')
	print('selftest_sch_action_observer: OK')
end

main()
