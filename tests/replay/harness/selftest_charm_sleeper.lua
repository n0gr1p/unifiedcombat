package.path = package.path .. ';./?.lua'

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local function assert_contains(value, needle, message)
	if not tostring(value):find(needle, 1, true) then
		error(('%s: missing %s in %s'):format(message, tostring(needle), tostring(value)))
	end
end

local loaded_policy = require('uc_charm_sleeper_policy').get('./')
assert_equal(#loaded_policy.spells, 12, 'checked-in policy safe spell count mismatch')
assert_equal(loaded_policy.spells[1].name, 'Repose', 'checked-in policy strongest spell mismatch')
assert_equal(loaded_policy.effect_ids[2], true, 'checked-in policy Sleep effect id mismatch')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
local charm_prepass_at = assert(scheduler_source:find(
	'local charm_blocked, charm_reason = try_charm_sleeper_emergency',
	1,
	true
))
local doom_prepass_at = assert(scheduler_source:find(
	'local doom_blocked, doom_reason = try_doom_water_emergency',
	1,
	true
))
assert_true(charm_prepass_at < doom_prepass_at, 'charm sleeper emergency must arbitrate before Doom water')

local members = {}
local mobs = {}
local ready = {}
local logs = {}
local player_info = { main_job_id = 1, sub_job_id = 2 }
local main_job_data = { spells = {} }
local sub_job_data = { spells = {} }
local resources = {
	['Repose'] = { id = 1, range = 20 },
	['Sleep II'] = { id = 2, range = 20 },
	['Dream Flower'] = { id = 3, range = 20, type = 'BlueMagic' },
}

local provider = require('uc_provider_charm_sleeper').new({
	get_party_members = function()
		return members
	end,
	get_mob_by_id = function(target_id)
		return mobs[target_id]
	end,
	action_ready = function(name)
		if ready[name] == true then
			return true, '', 'spell'
		end
		return false, 'NOT_READY', 'spell'
	end,
	get_spell_resource = function(name)
		return resources[name]
	end,
	get_player = function()
		return player_info
	end,
	get_mjob_data = function()
		return main_job_data
	end,
	get_sjob_data = function()
		return sub_job_data
	end,
	action_effective_range = function(raw_range)
		return raw_range
	end,
	action_target_mode = function()
		return 'target'
	end,
	build_action_command = function(name, _, target)
		return ('input /ma "%s" %d'):format(name, target.id)
	end,
	has_buff = function(buffs, effect_id)
		for _, buff_id in ipairs(buffs) do
			if buff_id == effect_id then
				return true
			end
		end
		return false
	end,
	clamp_urgency = function(value)
		return value
	end,
	log = function(message)
		logs[#logs + 1] = message
	end,
	policy = {
		spells = {
			{ id = 'repose', name = 'Repose', duration_s = 90, effect_id = 2, range_yalms = 20, area = 'single' },
			{ id = 'sleep_ii', name = 'Sleep II', duration_s = 90, effect_id = 2, range_yalms = 20, area = 'single' },
			{ id = 'dream_flower', name = 'Dream Flower', duration_s = 90, effect_id = 2, range_yalms = 20, area = 'aoe_centered_on_caster' },
		},
		effect_ids = { [2] = true },
	},
	spell_effect_gain_messages = { [2] = true },
	priority_band = 1000,
})

local function settings(enabled)
	return {
		defensive_enabled = true,
		def_charm_sleeper_enabled = enabled,
	}
end

local function config(enabled)
	return {
		defensive = {
			enabled = true,
			charm_sleeper = { enabled = enabled },
		},
	}
end

local function collect(now, enabled)
	local out = {}
	provider.collect({
		now = now,
		config = config(enabled),
		settings = settings(not enabled),
	}, out)
	return out
end

members = {
	{
		id = 100,
		name = 'CharmedPlayer',
		charmed = true,
		is_self = false,
		is_npc = false,
		spawn_type = 13,
		hpp = 100,
		buffs = {},
		buff_source = 'packet_076',
	},
}
mobs[100] = { id = 100, charmed = true, hpp = 100, distance = 100 }
ready['Repose'] = false
ready['Sleep II'] = true

assert_equal(#collect(1, false), 0, 'disabled toggle must emit no proposal')
local proposals = collect(2, true)
assert_equal(#proposals, 1, 'unslept charmed player must emit a proposal')
assert_equal(proposals[1].action_name, 'Sleep II', 'selector must choose first ready policy spell')
assert_equal(proposals[1].family_id, 'emergency.charm_sleep.primary', 'proposal family mismatch')
assert_equal(proposals[1].priority_band, 1000, 'charm sleeper priority mismatch')
assert_contains(proposals[1].legacy_command, '100', 'target-id command required')

ready['Sleep II'] = false
ready['Dream Flower'] = true
assert_equal(#collect(2.5, true), 0, 'learned but unset BLU sleep must not emit a proposal')
player_info.main_job_id = 16
main_job_data.spells = { 3 }
assert_equal(collect(2.6, true)[1].action_name, 'Dream Flower', 'set main-job BLU sleep must be selectable')
player_info.main_job_id = 1
main_job_data.spells = {}
ready['Sleep II'] = true
ready['Dream Flower'] = false

members[1].buffs = { 2 }
assert_equal(#collect(3, true), 0, 'live party Sleep buff must suppress recast')

members[1].buffs = nil
provider.note_dispatch(proposals[1], 4)
assert_equal(provider.observe_action({
	actor_id = 500,
	category = 4,
	param = 2,
	targets = {
		{ id = 100, actions = { { message = 2 } } },
	},
}, 500, 5), 1, 'successful local action must record projection')
assert_equal(#collect(50, true), 0, 'projection must suppress while party buff data is missing')
assert_equal(#collect(94, true), 1, 'pre-clear must release projection shortly before projected end')

members[1].buffs = {}
assert_equal(#collect(96, true), 1, 'observed early Sleep break must retry after minimal gate')

members[1].charmed = false
mobs[100].charmed = false
assert_equal(#collect(97, true), 0, 'charm clear must stop proposals')
assert_equal(provider._test.state.attempts[100], nil, 'charm clear must remove attempt state')
assert_equal(provider._test.state.projections[100], nil, 'charm clear must remove projected state')

members = {
	{
		id = 500,
		name = 'SelfPlayer',
		charmed = true,
		is_self = true,
		is_npc = false,
		spawn_type = 13,
		hpp = 100,
		buffs = {},
		buff_source = 'self_local',
	},
}
mobs[500] = { id = 500, charmed = true, hpp = 100, distance = 0 }
assert_equal(#collect(98, true), 0, 'self charm must never dispatch')

io.stdout:write('selftest_charm_sleeper: OK\n')
