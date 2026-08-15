local audit = require('tests.replay.harness.uc_encounter_field_log_audit')

local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function ability(key, observed_at, target_summary)
	return ('1.000 | Tester | ENCOUNTER_RAW_ABILITY_CANDIDATE | actor_id=3001 actor_name=Dhartok category=11 action_param=900 targets_summary=%s actions_summary=t1[] ability_id=900 ability_key=%s observed_at=%s phase=completed target_count=1 zone_id=133 zone_name=Outer_RaKaznar_U2'):format(
		target_summary,
		key,
		tostring(observed_at)
	)
end

local lines = {
	ability('cesspool', 10, 't1,id=4001,x=1,y=2,z=3'),
	ability('auto_attack_1', 10.5, 't1,id=4001,x=100,y=100,z=3'),
	ability('fetid_eddies', 11, 't1,id=4001,x=1,y=2,z=3'),
	ability('noyade', 12, 't1,id=4002,x=4,y=5,z=6'),
	'2.000 | Tester | ENCOUNTER_RAW_ACTION_RESULT_CANDIDATE | actor_id=5001 target_id=3001 action_class=ws action_key=42 observed_at=13 success=true target_name=Dhartok',
}
local result = audit.analyze(lines)
assert_equal(#result.ability_events, 4, 'raw ability audit count mismatch')
assert_equal(#result.action_results, 1, 'raw action-result audit count mismatch')
assert_equal(#result.cesspool_sequences, 1, 'Cesspool sequence audit count mismatch')
assert_equal(result.cesspool_sequences[1].first_tp.ability_key, 'fetid_eddies', 'first TP audit mismatch')
assert_equal(result.cesspool_sequences[1].second_tp.ability_key, 'noyade', 'second TP audit mismatch')
assert_true(result.cesspool_sequences[1].second_target_authoritative, 'second TP target should be authoritative')
assert_true(#audit.summary_lines(result) >= 2, 'field audit summary missing')

io.stdout:write('selftest_encounter_field_log_audit: OK\n')
