local enemy_state = require('uc_scheduler_enemy_effect_state')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local imported = enemy_state.load_dispel_map('')
if imported <= 0 then
	error('dispel map must import at least one effect')
end
assert_equal(enemy_state.is_dispellable(33), true, 'Haste is dispellable')
assert_equal(enemy_state.dispel_priority(33), 94, 'Haste danger priority')
assert_equal(enemy_state.is_dispellable(99999), false, 'unknown effect is not dispellable')
assert_equal(enemy_state.copy_dispellable_set()[33], true, 'dispellable set copy')

local phase1 = {}
local now_value = 10
local function now()
	return now_value
end

enemy_state.set(phase1, 100, 33, 'fixture', 10, 5, now)
assert_equal(phase1.effectiveTargets[100][33].source, 'fixture', 'effect source')
assert_equal(phase1.effectiveTargets[100][33].expires_at, 15, 'effect expiry')
enemy_state.prune_expired(phase1, 14.9, now)
assert_equal(phase1.effectiveTargets[100][33] ~= nil, true, 'effect retained before expiry')
enemy_state.prune_expired(phase1, 15, now)
assert_equal(phase1.effectiveTargets[100], nil, 'expired target removed')

enemy_state.set(phase1, 101, 33, 'old', 1, 0, now)
enemy_state.set(phase1, 102, 33, 'live', 9, 0, now)
enemy_state.sweep(phase1, 5, now, function(target_id)
	if target_id == 102 then
		return { id = 102, spawn_type = 16, hpp = 100 }
	end
	return nil
end)
assert_equal(phase1.effectiveTargets[101], nil, 'invalid target swept')
assert_equal(phase1.effectiveTargets[102][33] ~= nil, true, 'live target retained')
assert_equal(enemy_state.clear(phase1, 102, 33), true, 'effect clear reports change')
assert_equal(enemy_state.clear(phase1, 102, 33), false, 'repeat clear reports no change')

local allowed, key = enemy_state.can_attempt(phase1, 'Dispel', 200, 33, 20, 3)
assert_equal(allowed, true, 'first dispel attempt allowed')
enemy_state.mark_attempt(phase1, key, 20, now)
allowed = enemy_state.can_attempt(phase1, 'Dispel', 200, 33, 22.9, 3)
assert_equal(allowed, false, 'dispel attempt held during cooldown')
allowed = enemy_state.can_attempt(phase1, 'Dispel', 200, 33, 23, 3)
assert_equal(allowed, true, 'dispel attempt released at cooldown')

assert_equal(enemy_state.observe_unknown_once('fixture:1'), true, 'first unknown observed')
assert_equal(enemy_state.observe_unknown_once('fixture:1'), false, 'unknown deduplicated')
assert_equal(enemy_state.is_raw_death_message(6), true, 'death message classified')
assert_equal(enemy_state.is_raw_remove_message(204), true, 'remove message classified')

enemy_state.ingest_raw_action(phase1, {
	actor_id = 500,
	category = 1,
	targets = {
		{
			id = 600,
			actions = {
				{
					message = 1,
					param = 0,
					has_add_effect = true,
					add_effect_message = 160,
					add_effect_param = 33,
				},
			},
		},
	},
}, {
	addon_path = '',
	parse_action = function()
		error('table action must not invoke packet parser')
	end,
	get_player = function()
		return { id = 1 }
	end,
	now = function()
		return 30
	end,
	spell_effect_gain_messages = { [2] = true },
})
assert_equal(
	phase1.effectiveTargets[600][33].source,
	'raw_028_add_effect_msg_160',
	'raw action add effect ingested'
)

io.stdout:write('selftest_scheduler_enemy_effect_state: OK\n')
