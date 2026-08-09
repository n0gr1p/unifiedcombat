package.path = './?.lua;' .. package.path

local maintenance = require('uc_smn_maintenance')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local function settings()
	return {
		summoner_enabled = true,
		summoner_avatar = 'Ifrit',
		summoner_avatar_favor = true,
		summoner_ward_enabled = true,
		summoner_ward_action = 'Crimson Howl',
		summoner_ward_actions = 'Crimson Howl',
		summoner_engage_on_combat_start = true,
		summoner_rage_enabled = true,
		summoner_rage_action = 'Flaming Crush',
		summoner_rage_usage = 'on_cooldown',
	}
end

local function context()
	return {
		now = 10,
		settings = settings(),
		player_present = true,
		player = {
			id = 100,
			name = 'Tester',
			main_job = 'SMN',
			vitals = {
				mp = 1000,
			},
			buffs = {},
		},
		player_id = 100,
		player_name = 'Tester',
		pet_present = false,
		pet_id = 0,
		pet_name = '',
		ability_recasts_present = true,
		ability_recasts = {
			[172] = 0,
			[174] = 0,
		},
	}
end

local coordinator_blocked = false
local moving = false
local provider = maintenance.new({
	action_ready = function(name)
		if name == 'Ifrit' or name == 'Garuda' or name == 'Fenrir' then
			return true, '', 'spell'
		end
		if name == 'Avatar\'s Favor' then
			return true, '', 'ja'
		end
		return false, 'unknown', 'none'
	end,
	coordinator_can_attempt = function()
		if coordinator_blocked then
			return false, 'retry_backoff', 1
		end
		return true, '', 0
	end,
	player_is_moving = function()
		return moving
	end,
	get_ja_resource = function(name)
		if name == 'Crimson Howl' then
			return { mp_cost = 84 }
		end
		if name == 'Hastega II' then
			return { mp_cost = 248 }
		end
		if name == 'Ecliptic Growl' then
			return { mp_cost = 46 }
		end
		return nil
	end,
	log = function()
	end,
})

local function collect(ctx)
	local out = {}
	provider.collect(ctx, out)
	return out
end

local function find(actions, name)
	for _, action in ipairs(actions) do
		if action.action_name == name then
			return action
		end
	end
	return nil
end

local function test_avatar_convergence()
	_G.Start_Engine = true
	local no_pet = context()
	local actions = collect(no_pet)
	assert_equal(#actions, 1, 'no pet must produce exactly one convergence action')
	assert_equal(actions[1].action_name, 'Ifrit', 'desired avatar summon')
	assert_equal(actions[1].action_type, 'spell', 'summon action type')
	assert_equal(actions[1].priority_band, 120, 'summon retains spell priority')

	moving = true
	assert_equal(#collect(context()), 0, 'summon must be suppressed while moving')
	moving = false

	local wrong = context()
	wrong.pet_present = true
	wrong.pet_id = 201
	wrong.pet_name = 'Garuda'
	actions = collect(wrong)
	assert_equal(#actions, 1, 'wrong avatar must allow only Release')
	assert_equal(actions[1].action_name, 'Release', 'wrong avatar correction')
	assert_equal(actions[1].action_type, 'pet', 'Release action type')
	assert_equal(actions[1].priority_band, 149, 'Release instant-action priority')
	assert_equal(actions[1].detail.pet_command.pet_id, 201, 'Release captured pet id')

	coordinator_blocked = true
	assert_equal(#collect(wrong), 0, 'Release retry backoff')
	coordinator_blocked = false

	local correct = context()
	correct.pet_present = true
	correct.pet_id = 202
	correct.pet_name = 'Ifrit'
	actions = collect(correct)
	assert_true(find(actions, 'Avatar\'s Favor') ~= nil, 'Favor candidate after convergence')
	assert_true(find(actions, 'Crimson Howl') ~= nil, 'Ward candidate after convergence')
	assert_equal(find(actions, 'Avatar\'s Favor').priority_band, 149, 'Favor instant-action priority')
	assert_equal(find(actions, 'Crimson Howl').priority_band, 148, 'Ward instant-action priority')
end

local function test_favor_and_ward_satisfaction()
	local ctx = context()
	ctx.pet_present = true
	ctx.pet_id = 202
	ctx.pet_name = 'Ifrit'
	ctx.player.buffs = { 431, 68 }
	assert_equal(#collect(ctx), 0, 'satisfied Favor and Ward must not be proposed')

	ctx.player.buffs = { 431 }
	local actions = collect(ctx)
	assert_equal(#actions, 1, 'missing Ward only')
	assert_equal(actions[1].action_name, 'Crimson Howl', 'Ward after effect removal')
	assert_equal(actions[1].movement_policy, 'none', 'Ward must not lock player movement')

	ctx.ability_recasts[174] = 30
	assert_equal(#collect(ctx), 0, 'Ward recast unavailable')

	ctx.ability_recasts[174] = 0
	ctx.player.vitals.mp = 83
	assert_equal(#collect(ctx), 0, 'Ward insufficient MP')

	ctx.player.vitals.mp = 1000
	ctx.settings.summoner_ward_action = 'Not a Ward'
	ctx.settings.summoner_ward_actions = 'Not a Ward'
	actions = collect(ctx)
	assert_equal(#actions, 0, 'unsupported Ward must remain suppressed')
	assert_equal(provider.status.state, 'avatar_converged', 'invalid Ward must not invalidate desired avatar')
end

local function test_multi_effect_fenrir_ward()
	local ctx = context()
	ctx.settings.summoner_ward_action = 'Ecliptic Growl'
	ctx.settings.summoner_ward_actions = 'Ecliptic Growl'
	ctx.pet_present = true
	ctx.pet_id = 202
	ctx.pet_name = 'Ifrit'
	local actions = collect(ctx)
	assert_equal(actions[1].action_name, 'Release', 'missing Fenrir Ward must release the primary avatar')
	assert_equal(actions[1].detail.desired_avatar, 'Fenrir', 'Fenrir must own Ecliptic Growl')

	ctx.pet_id = 204
	ctx.pet_name = 'Fenrir'
	ctx.player.buffs = { 119, 120, 121, 122, 123, 124 }
	actions = collect(ctx)
	assert_equal(actions[1].action_name, 'Ecliptic Growl', 'one missing Growl effect must keep the Ward due')
	assert_equal(#actions[1].detail.pet_command.expected_effect_ids, 7, 'Growl must capture all maintained effects')

	ctx.player.buffs = { 119, 120, 121, 122, 123, 124, 125 }
	ctx.ability_recasts[174] = 30
	actions = collect(ctx)
	assert_equal(actions[1].action_name, 'Release', 'complete Growl effect set must return to the primary avatar')
	assert_equal(actions[1].detail.desired_avatar, 'Ifrit', 'completed Growl must restore the primary avatar')
end

local function test_cross_avatar_ward_rotation()
	local ctx = context()
	ctx.settings.summoner_ward_actions = 'Crimson Howl|Hastega II'
	ctx.settings.summoner_ward_action = 'Crimson Howl'
	ctx.pet_present = true
	ctx.pet_id = 202
	ctx.pet_name = 'Ifrit'

	local actions = collect(ctx)
	assert_true(find(actions, 'Crimson Howl') ~= nil, 'ordered primary-avatar Ward must be refreshed first')

	ctx.player.buffs = { 431, 68 }
	actions = collect(ctx)
	assert_equal(#actions, 1, 'missing cross-avatar Ward must begin one convergence action')
	assert_equal(actions[1].action_name, 'Release', 'primary avatar must release for due cross-avatar Ward')
	assert_equal(actions[1].detail.desired_avatar, 'Garuda', 'release must capture Ward avatar destination')

	ctx.pet_present = false
	ctx.pet_id = 0
	ctx.pet_name = ''
	actions = collect(ctx)
	assert_equal(#actions, 1, 'missing Ward avatar must produce one summon action')
	assert_equal(actions[1].action_name, 'Garuda', 'cross-avatar Ward must summon its owning avatar')

	ctx.pet_present = true
	ctx.pet_id = 203
	ctx.pet_name = 'Garuda'
	actions = collect(ctx)
	assert_equal(#actions, 1, 'Ward avatar convergence must produce only the due Ward')
	assert_equal(actions[1].action_name, 'Hastega II', 'cross-avatar Ward action mismatch')
	assert_equal(find(actions, 'Avatar\'s Favor'), nil, 'Favor must not be used on a temporary Ward avatar')

	ctx.player.buffs = { 68, 33 }
	ctx.ability_recasts[174] = 30
	actions = collect(ctx)
	assert_equal(#actions, 1, 'completed Ward rotation must return to the primary avatar')
	assert_equal(actions[1].action_name, 'Release', 'temporary Ward avatar must be released')
	assert_equal(actions[1].detail.desired_avatar, 'Ifrit', 'rotation must return to configured primary avatar')

	ctx.pet_present = true
	ctx.pet_id = 202
	ctx.pet_name = 'Ifrit'
	ctx.player.buffs = { 68 }
	actions = collect(ctx)
	assert_true(find(actions, 'Avatar\'s Favor') ~= nil, 'primary avatar must maintain Favor while Ward recast cools')
	assert_equal(find(actions, 'Release'), nil, 'primary avatar must not leave while the missing Ward is not executable')
end

local function test_mismatch_revalidation()
	local wrong = context()
	wrong.pet_present = true
	wrong.pet_id = 201
	wrong.pet_name = 'Garuda'
	local release = collect(wrong)[1]
	local valid = provider.revalidate(release, wrong)
	assert_true(valid, 'captured wrong pet should revalidate')
	wrong.pet_id = 202
	valid = provider.revalidate(release, wrong)
	assert_equal(valid, false, 'Release must reject a stale pet instance')
end

test_avatar_convergence()
test_favor_and_ward_satisfaction()
test_cross_avatar_ward_rotation()
test_multi_effect_fenrir_ward()
test_mismatch_revalidation()

print('selftest_smn_maintenance: OK')
