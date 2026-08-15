local function assert_true(condition, message)
	if condition ~= true then
		error(message)
	end
end

local function assert_false(condition, message)
	if condition ~= false then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local resources = {
	elements = {
		[3] = { en = 'Earth' },
		[5] = { en = 'Water' },
	},
	spells = {
		[169] = { id = 169, en = 'Water', element = 5, skill = 36, type = 'BlackMagic' },
		[220] = { id = 220, en = 'Poison', element = 5, skill = 35, type = 'BlackMagic' },
		[335] = { id = 335, en = 'Suiton: Ichi', element = 5, skill = 39, type = 'Ninjutsu' },
		[515] = { id = 515, en = 'Maelstrom', element = 5, skill = 43, type = 'BlueMagic' },
		[606] = { id = 606, en = 'Awful Eye', element = 5, skill = 43, type = 'BlueMagic' },
	},
	weapon_skills = {
		[16] = { id = 16, en = 'Wasp Sting', element = 5, skillchain_a = 'Scission' },
		[130] = { id = 130, en = 'Blade: Teki', element = 5, skillchain_a = 'Reverberation' },
		[11] = { id = 11, en = 'Safe Test WS' },
		[12] = { id = 12, en = 'Different Test WS' },
	},
	job_abilities = {
		[130] = { id = 130, en = 'Water Shot', element = 5, type = 'CorsairShot' },
		[582] = { id = 582, en = 'Spinning Dive', element = 5, type = 'BloodPactRage' },
		[583] = { id = 583, en = 'Grand Fall', element = 5, type = 'BloodPactRage' },
		[21] = { id = 21, en = 'Earth Test BP', element = 3, type = 'BloodPactRage' },
		[22] = { id = 22, en = 'Water Test Ward', element = 5, type = 'BloodPactWard' },
	},
}

local saved_resources = package.loaded.resources
package.loaded.resources = resources

local classifier = require('uc_encounter_action_classifier')
local policy = require('uc_encounter_policy')
local skillchain_elements = require('uc_skillchain_elements')

local function classify(proposal)
	return classifier.classify(proposal, resources)
end

local function snapshot(encounter_id, modes, recent)
	return {
		enabled = true,
		resolved_id = encounter_id or 'sortie_dhartok',
		boss = { id = 3001 },
		policy_modes = modes or {
			water_damage = 'enforce',
			water_skillchain = 'enforce',
			repeat_action_wall = 'enforce',
		},
		tuning = { repeat_action_guard_s = 10.0 },
		recent_repeat_actions = recent or {},
	}
end

local function proposal(action_type, action_name, target_id)
	return {
		proposal_id = 'fixture:' .. action_name,
		provider = 'combat',
		action_type = action_type,
		action_name = action_name,
		target_kind = 'mob',
		target_id = target_id or 3001,
	}
end

local deps = { classify = classify }
local ctx = { now = 100.0 }

local water_spell = proposal('spell', 'Water')
local ok, reason, decision = policy.validate(ctx, water_spell, snapshot(), deps)
assert_false(ok, 'Water damage spell must be rejected in enforce mode')
assert_equal(reason, 'encounter_water_damage', 'Water spell rejection reason mismatch')
assert_equal(decision.policy_id, 'plovid_water_damage', 'Water spell policy id mismatch')
assert_equal(decision.classification_proof, 'verified_water_spell_resource', 'Water spell proof mismatch')

ok, reason, decision = policy.validate(ctx, proposal('spell', 'Poison'), snapshot(), deps)
assert_true(ok, 'Water-element non-damage enfeeble must remain eligible')
assert_equal(decision, nil, 'safe enfeeble must not publish a violation')

ok = policy.validate(ctx, proposal('spell', 'Suiton: Ichi'), snapshot(), deps)
assert_false(ok, 'Water Ninjutsu damage must be rejected')
ok = policy.validate(ctx, proposal('spell', 'Maelstrom'), snapshot(), deps)
assert_false(ok, 'Water Blue Magic damage must be rejected')
ok = policy.validate(ctx, proposal('spell', 'Awful Eye'), snapshot(), deps)
assert_true(ok, 'Water-tagged non-damage Blue Magic must remain eligible')

local unrelated = proposal('spell', 'Water', 9999)
ok, reason, decision = policy.validate(ctx, unrelated, snapshot(), deps)
assert_true(ok, 'Water action against unrelated target must remain eligible')
assert_equal(decision, nil, 'unrelated target must not publish a violation')

local ally = proposal('spell', 'Water')
ally.target_kind = 'ally'
ok = policy.validate(ctx, ally, snapshot(), deps)
assert_true(ok, 'non-hostile Water action must remain eligible')

local warn_modes = {
	water_damage = 'warn',
	water_skillchain = 'enforce',
	repeat_action_wall = 'enforce',
}
ok, reason, decision = policy.validate(ctx, water_spell, snapshot(nil, warn_modes), deps)
assert_true(ok, 'warn mode must not reject Water damage')
assert_equal(reason, '', 'warn mode must not return a rejection reason')
assert_equal(decision.mode, 'warn', 'warn diagnostic mode mismatch')

local off_modes = {
	water_damage = 'off',
	water_skillchain = 'enforce',
	repeat_action_wall = 'enforce',
}
ok, reason, decision = policy.validate(ctx, water_spell, snapshot(nil, off_modes), deps)
assert_true(ok, 'off mode must not reject Water damage')
assert_equal(decision, nil, 'off mode must not publish a violation')

local safe_ws = proposal('ws', 'Safe Test WS')
safe_ws.skillchain_plan = {
	predicted_result = 'Distortion',
	resonance_generation = 7,
}
ok, reason, decision = policy.validate(ctx, safe_ws, snapshot(), deps)
assert_false(ok, 'Water-bearing predicted skillchain must be rejected')
assert_equal(reason, 'encounter_water_skillchain', 'skillchain rejection reason mismatch')
assert_equal(decision.predicted_result, 'Distortion', 'predicted skillchain diagnostic mismatch')

safe_ws.skillchain_plan.predicted_result = 'Fragmentation'
ok = policy.validate(ctx, safe_ws, snapshot(), deps)
assert_true(ok, 'Water-free predicted skillchain must remain eligible')
safe_ws.skillchain_plan = nil
ok = policy.validate(ctx, safe_ws, snapshot(), deps)
assert_true(ok, 'ordinary WS without active skillchain must remain eligible')

ok, reason = policy.validate(ctx, proposal('ws', 'Blade: Teki'), snapshot(), deps)
assert_false(ok, 'direct Water WS damage must be rejected')
assert_equal(reason, 'encounter_water_damage', 'direct Water WS reason mismatch')

ok = policy.validate(ctx, proposal('ws', 'Wasp Sting'), snapshot(), deps)
assert_true(ok, 'Water-tagged physical WS must remain eligible')

ok = policy.validate(ctx, proposal('ja', 'Water Shot'), snapshot(), deps)
assert_false(ok, 'Water Shot must be rejected')

local recent = {
	['ws:11'] = {
		action_class = 'ws',
		action_key = '11',
		observed_at = 95.0,
	},
}
ok, reason, decision = policy.validate(ctx, proposal('ws', 'Safe Test WS'), snapshot(nil, nil, recent), deps)
assert_false(ok, 'same WS inside Dhartok guard must be rejected')
assert_equal(reason, 'encounter_repeat_action_wall', 'repeat WS reason mismatch')
assert_equal(decision.remaining_s, 5.0, 'repeat WS remaining guard mismatch')

ok = policy.validate(ctx, proposal('ws', 'Different Test WS'), snapshot(nil, nil, recent), deps)
assert_true(ok, 'different WS must not be rejected by another action guard')

recent['ws:11'].observed_at = 90.0
ok = policy.validate(ctx, proposal('ws', 'Safe Test WS'), snapshot(nil, nil, recent), deps)
assert_true(ok, 'same WS at guard boundary must be eligible')

recent['ws:11'].observed_at = 95.0
ok = policy.validate(ctx, proposal('ws', 'Safe Test WS'), snapshot('sortie_ghatjot', nil, recent), deps)
assert_true(ok, 'Ghatjot must not receive Dhartok repeat policy')

local bp = proposal('pet', 'Earth Test BP')
bp.provider = 'pet_combat'
bp.detail = { pet_command = { kind = 'rage' } }
local bp_recent = {
	['bp:21'] = { action_class = 'bp', action_key = '21', observed_at = 96.0 },
}
ok, reason = policy.validate(ctx, bp, snapshot(nil, nil, bp_recent), deps)
assert_false(ok, 'same Blood Pact inside Dhartok guard must be rejected')
assert_equal(reason, 'encounter_repeat_action_wall', 'repeat BP reason mismatch')

local water_bp = proposal('pet', 'Grand Fall')
water_bp.detail = { pet_command = { kind = 'rage' } }
ok, reason = policy.validate(ctx, water_bp, snapshot(), deps)
assert_false(ok, 'Water-element offensive Blood Pact must be rejected')
assert_equal(reason, 'encounter_water_damage', 'Water BP reason mismatch')

local physical_water_bp = proposal('pet', 'Spinning Dive')
physical_water_bp.detail = { pet_command = { kind = 'rage' } }
ok = policy.validate(ctx, physical_water_bp, snapshot(), deps)
assert_true(ok, 'Water-avatar physical Blood Pact must remain eligible')

local water_ward = proposal('pet', 'Water Test Ward')
water_ward.detail = { pet_command = { kind = 'ward' } }
ok = policy.validate(ctx, water_ward, snapshot(), deps)
assert_true(ok, 'Water-element Ward must remain eligible')

assert_true(skillchain_elements.contains('Reverberation', 'Water'), 'Reverberation Water mapping missing')
assert_true(skillchain_elements.contains('Darkness', 'Water'), 'Darkness Water mapping missing')
assert_true(skillchain_elements.contains('Umbra', 'Water'), 'Umbra Water mapping missing')
assert_false(skillchain_elements.contains('Fragmentation', 'Water'), 'Fragmentation must not contain Water')

package.loaded.resources = saved_resources

io.stdout:write('selftest_encounter_policy: OK\n')
