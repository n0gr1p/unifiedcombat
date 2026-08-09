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
		error(('%s: missing %s'):format(message, tostring(needle)))
	end
end

local sleep_status = require('uc_sleep_status')
assert_equal(sleep_status.effect_ids[2], true, 'Sleep buff id 2 must be recognized')
assert_equal(sleep_status.effect_ids[19], true, 'Sleep buff id 19 must be recognized')
assert_equal(sleep_status.has_sleep({ 2 }), true, 'buff id 2 must detect Sleep')
assert_equal(sleep_status.has_sleep({ 19 }), true, 'buff id 19 must detect Sleep')
assert_equal(sleep_status.has_sleep({ 3, 4 }), false, 'unrelated buffs must not detect Sleep')
assert_equal(sleep_status.validate_resources({
	[2] = { en = 'sleep' },
	[19] = { en = 'sleep' },
}), true, 'Sleep resources must validate')
assert_equal(pcall(sleep_status.validate_resources, {
	[2] = { en = 'sleep' },
	[19] = { en = 'nightmare' },
}), false, 'Sleep resource mismatch must fail fast')

local members = {}
local mobs = {}
local ready = true
local logs = {}
local provider = require('uc_provider_sleep_waker').new({
	bool_setting = function(value)
		return value == true
	end,
	active_value_or_flat = function(_, flat)
		return flat
	end,
	get_party_members = function()
		return members
	end,
	get_mob_by_id = function(target_id)
		return mobs[target_id]
	end,
	in_party_cast_range = function()
		return true
	end,
	action_ready = function(name)
		assert_equal(name, 'Cure', 'sleep waker must only select Cure')
		if ready then
			return true, '', 'spell'
		end
		return false, 'CURE_NOT_READY', 'spell'
	end,
	build_action_command = function(name, kind, target)
		return ('input /ma "%s" "%s"'):format(name, target.name)
	end,
	clamp_urgency = function(value)
		return value
	end,
	log = function(message)
		logs[#logs + 1] = message
	end,
	sleep_status = sleep_status,
	priority_band = 149,
})

local function settings(enabled)
	return {
		defensive_enabled = true,
		def_sleep_waker_enabled = enabled,
		defensive_cure_enabled = false,
	}
end

local function collect(now, enabled)
	local out = {}
	provider.collect({
		now = now,
		settings = settings(enabled),
	}, out)
	return out
end

members = {
	{
		id = 100,
		name = 'SleepingPlayer',
		charmed = false,
		is_self = false,
		is_npc = false,
		spawn_type = 13,
		hpp = 100,
		buffs = { 2 },
		buff_source = 'packet_076',
	},
}
mobs[100] = { id = 100, charmed = false, hpp = 100, distance = 100 }

assert_equal(#collect(1, false), 0, 'disabled sleep waker must emit no proposal')
assert_equal(#collect(2, true), 0, 'first Sleep observation must wait for the observation gate')
assert_equal(#collect(2.2, true), 0, 'Sleep observation gate must remain closed before its deadline')
local proposals = collect(2.4, true)
assert_equal(#proposals, 1, 'confirmed uncharmed Sleep must emit a proposal')
assert_equal(proposals[1].action_name, 'Cure', 'sleep waker action mismatch')
assert_equal(proposals[1].family_id, 'emergency.sleep_wake.primary', 'sleep waker family mismatch')
assert_equal(proposals[1].priority_band, 149, 'sleep waker priority mismatch')
assert_equal(proposals[1].detail.def_action_type, 'cure', 'sleep waker must use Cure dispatch semantics')
assert_equal(proposals[1].detail.cure_intent, 'sleep_wake', 'sleep waker intent mismatch')
assert_contains(proposals[1].legacy_command, 'SleepingPlayer', 'sleep waker command must identify the party member')

provider.note_dispatch(proposals[1], 2.4)
assert_equal(#collect(3.0, true), 0, 'sleep waker attempt gate must suppress repeated Cure')
assert_equal(#collect(5.0, true), 1, 'sleep waker must retry if Sleep remains after the attempt gate')

members[1].charmed = true
mobs[100].charmed = true
assert_equal(#collect(6.0, true), 0, 'charmed sleeping target must never emit a wake proposal')
assert_equal(provider._test.state.observed[100], nil, 'charmed target must clear observation state')
assert_equal(provider._test.state.attempts[100], nil, 'charmed target must clear attempt state')

members[1].charmed = false
mobs[100].charmed = nil
assert_equal(#collect(7.0, true), 0, 'unknown authoritative Charm state must fail closed')

mobs[100].charmed = false
members[1].buffs = { 19 }
assert_equal(#collect(8.0, true), 0, 'Sleep buff id 19 must use the observation gate')
assert_equal(#collect(8.4, true), 1, 'Sleep buff id 19 must emit a Cure proposal')

members[1].buffs = {}
assert_equal(#collect(9.0, true), 0, 'cleared Sleep must emit no proposal')
assert_equal(provider._test.state.observed[100], nil, 'cleared Sleep must clear observation state')

members[1].buffs = { 2 }
members[1].is_self = true
assert_equal(#collect(10.0, true), 0, 'local sleeping player must never dispatch its own wake Cure')

local safety = require('uc_cure_target_safety')
local safety_member = {
	id = 100,
	buffs = { 2 },
}
local safety_mob = {
	id = 100,
	charmed = false,
}
local safety_deps = {
	get_mob_by_id = function()
		return safety_mob
	end,
	get_party_member_by_id = function()
		return safety_member
	end,
	sleep_status = sleep_status,
}
local wake_proposal = {
	action_type = 'spell',
	target_kind = 'ally',
	target_id = 100,
	detail = {
		def_action_type = 'cure',
		cure_intent = 'sleep_wake',
	},
}
local regular_cure = {
	action_type = 'spell',
	target_kind = 'ally',
	target_id = 100,
	detail = {
		def_action_type = 'cure',
	},
}

local valid, reason = safety.validate(wake_proposal, safety_deps)
assert_equal(valid, true, 'sleeping uncharmed wake target must pass commit safety')
assert_equal(reason, '', 'valid wake target reason mismatch')

safety_mob.charmed = true
valid, reason = safety.validate(wake_proposal, safety_deps)
assert_equal(valid, false, 'charmed wake target must fail commit safety')
assert_equal(reason, 'BLOCK_DEFENSIVE_CURE_CHARMED_TARGET', 'charmed wake reason mismatch')
valid, reason = safety.validate(regular_cure, safety_deps)
assert_equal(valid, false, 'ordinary Cure must also reject a charmed target')
assert_equal(reason, 'BLOCK_DEFENSIVE_CURE_CHARMED_TARGET', 'ordinary charmed Cure reason mismatch')

safety_mob.charmed = nil
valid, reason = safety.validate(wake_proposal, safety_deps)
assert_equal(valid, false, 'wake target with unknown Charm state must fail closed')
assert_equal(reason, 'BLOCK_SLEEP_WAKE_CHARM_STATE_UNKNOWN', 'unknown Charm reason mismatch')

safety_mob.charmed = false
safety_member.buffs = {}
valid, reason = safety.validate(wake_proposal, safety_deps)
assert_equal(valid, false, 'awake target must fail wake commit safety')
assert_equal(reason, 'BLOCK_SLEEP_WAKE_TARGET_AWAKE', 'awake target reason mismatch')

safety_member.buffs = nil
valid, reason = safety.validate(wake_proposal, safety_deps)
assert_equal(valid, false, 'missing buff snapshot must fail wake commit safety')
assert_equal(reason, 'BLOCK_SLEEP_WAKE_BUFF_STATE_UNKNOWN', 'missing buff snapshot reason mismatch')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_contains(scheduler_source, 'scheduler.PRIORITY_BAND_SLEEP_WAKE = 149', 'scheduler sleep-wake priority missing')
assert_contains(scheduler_source, 'scheduler.providers.sleep_waker.collect(ctx, out)', 'scheduler sleep-wake collection missing')
assert_contains(scheduler_source, 'return scheduler.validate_cure_target(selected)', 'rank commit Cure safety missing')
assert_contains(scheduler_source, 'local cure_target_ok, cure_target_reason = scheduler.validate_cure_target(selected)', 'dispatch-time Cure safety missing')
assert_contains(scheduler_source, "scheduler.providers.sleep_waker.reset('ZONE_CHANGE')", 'zone reset missing')
assert_contains(scheduler_source, "scheduler.providers.sleep_waker.reset('DEFENSIVE_DOMAIN_DISABLED')", 'defensive-domain reset missing')
assert_contains(scheduler_source, "event_code = 'SLEEP_WAKE_PROPOSED'", 'Sleep-wake proposal timeline event missing')
assert_contains(scheduler_source, "event_code = 'SLEEP_WAKE_DISPATCHED'", 'Sleep-wake dispatch timeline event missing')
assert_contains(scheduler_source, "if m.charmed ~= true and m.hpp > 0", 'internal Cure collection Charm exclusion missing')

local engine_file = assert(io.open('unified_engine.lua', 'r'))
local engine_source = engine_file:read('*a')
engine_file:close()
assert_contains(engine_source, "('SleepWaker: %s'):format(sleep_waker_status)", 'Sleep-wake overlay status missing')

assert_true(#logs > 0, 'sleep waker diagnostics must be observable')
io.stdout:write('selftest_sleep_waker: OK\n')
