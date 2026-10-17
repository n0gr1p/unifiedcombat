package.path = './?.lua;./tests/replay/fixtures/?.lua;' .. package.path

local fixtures = dofile('tests/replay/fixtures/summoner/summoner_replay_fixtures.lua')
local coordinator = require('uc_pet_command_coordinator')
local maintenance_module = require('uc_smn_maintenance')
local runtime = require('uc_smn_runtime')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function base_observation(now)
	return {
		now = now,
		pet_present = true,
		pet_id = 200,
		pet_status = 0,
		pet_target_id = 0,
		pet_target_matches_current = false,
		pet_inferred_target_id = 0,
		player_buffs = {},
		ability_recasts_present = true,
		ability_recasts = {
			[173] = 0,
			[174] = 0,
		},
		combat_generation = 1,
		target_id = 300,
		target_valid = true,
		target_hpp = 100,
	}
end

local function replay_pet_command(fixture)
	local state = coordinator.new({
		timeout = 2.5,
		ward_effect_timeout = 8.0,
		backoff_base = 1,
		backoff_max = 8,
	})
	coordinator.begin(state, fixture.command, 0)
	local event = nil
	for _, step in ipairs(fixture.steps) do
		if step.type == 'snapshot' then
			local observation = base_observation(step.now)
			for key, value in pairs(step) do
				if key ~= 'type' and key ~= 'rage_recast' then
					observation[key] = value
				end
			end
			if step.rage_recast ~= nil then
				observation.ability_recasts[173] = step.rage_recast
			end
			event = coordinator.observe(state, observation)
		elseif step.type == 'message' then
			event = coordinator.observe_action_message(state, step, 100, step.now)
		else
			error('unsupported Summoner replay step: ' .. tostring(step.type))
		end
		if event ~= nil then
			break
		end
	end
	assert_equal(event and event.outcome, fixture.expected_outcome, fixture.name .. ' outcome')
	assert_equal(event and event.reason, fixture.expected_reason, fixture.name .. ' reason')
end

local maintenance = maintenance_module.new({
	action_ready = function(name)
		if name == 'Ifrit' then
			return true, '', 'spell'
		end
		if name == 'Avatar\'s Favor' then
			return true, '', 'ja'
		end
		return false, 'unknown', 'none'
	end,
	coordinator_can_attempt = function()
		return true, '', 0
	end,
	player_is_moving = function()
		return false
	end,
	get_ja_resource = function(name)
		if name == 'Crimson Howl' then
			return { mp_cost = 84 }
		end
		return nil
	end,
	log = function()
	end,
})

local function replay_maintenance(fixture)
	local ctx = {
		now = 1,
		settings = {
			summoner_enabled = true,
			summoner_avatar = 'Ifrit',
			summoner_avatar_favor = true,
			summoner_ward_enabled = true,
			summoner_ward_action = 'Crimson Howl',
			summoner_engage_on_combat_start = true,
			summoner_rage_enabled = true,
			summoner_rage_action = 'Flaming Crush',
			summoner_rage_usage = 'on_cooldown',
		},
		player_present = true,
		player = {
			id = 100,
			name = 'Tester',
			main_job = 'SMN',
			vitals = {
				mp = 1000,
			},
			buffs = fixture.player_buffs or {},
		},
		player_id = 100,
		player_name = 'Tester',
		pet_present = fixture.pet_present,
		pet_id = fixture.pet_id or 0,
		pet_name = fixture.pet_name or '',
		ability_recasts_present = true,
		ability_recasts = {
			[172] = 0,
			[174] = 0,
		},
	}
	ctx.config = { summoner = select(1, runtime.config_from_settings(ctx.settings)) }
	local out = {}
	maintenance.collect(ctx, out)
	assert_equal(#out, #fixture.expected, fixture.name .. ' action count')
	for i = 1, #fixture.expected do
		assert_equal(out[i].action_name, fixture.expected[i], fixture.name .. ' action ' .. i)
	end
end

_G.Start_Engine = true
for _, fixture in ipairs(fixtures.pet_commands) do
	replay_pet_command(fixture)
end
for _, fixture in ipairs(fixtures.maintenance) do
	replay_maintenance(fixture)
end

print('selftest_smn_replay_fixtures: OK')
