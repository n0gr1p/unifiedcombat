package.path = package.path .. ';./?.lua'

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_contains(value, needle, message)
	if not tostring(value):find(needle, 1, true) then
		error(('%s: missing %s'):format(message, tostring(needle)))
	end
end

local members = {}
local ready = {
	['Arise'] = false,
	['Raise III'] = true,
	['Raise II'] = true,
	['Raise'] = true,
}
local provider = require('uc_provider_defensive').new({
	bool_setting = function(value) return value == true end,
	active_value_or_flat = function(_, flat) return flat end,
	build_defensive_candidates = function() return {} end,
	choose_defensive_action = function() return nil end,
	action_ready = function(name)
		if ready[name] then return true, '', 'spell' end
		return false, 'NOT_READY', 'spell'
	end,
	action_range = function() return 20.9 end,
	build_action_command = function(name, _, target)
		return ('input /ma "%s" "%s"'):format(name, target.name)
	end,
	cure_target_allowed = function() return true end,
	clamp_urgency = function(value) return value end,
	get_party_members = function() return members end,
	in_party_cast_range = function(member) return member.in_range ~= false end,
	log = function() end,
	critical_cure_priority = 150,
})

local function collect(now, enabled, priority)
	local out = {}
	provider.collect_resurrection({
		now = now,
		settings = {
			defensive_enabled = true,
			defensive_resurrection_enabled = enabled,
			defensive_resurrection_priority = priority or 'Arise|Raise III|Raise II|Raise',
		},
	}, out)
	return out
end

members = {
	{ id = 100, name = 'DownedPlayer', is_self = false, is_npc = false, spawn_type = 13, hpp = 0 },
	{ id = 101, name = 'DeadTrust', is_self = false, is_npc = true, spawn_type = 14, hpp = 0 },
	{ id = 102, name = 'Self', is_self = true, is_npc = false, spawn_type = 13, hpp = 0 },
}

assert_equal(#collect(1.0, false), 0, 'disabled resurrection must emit no proposal')
assert_equal(#collect(2.0, true), 0, 'first dead observation must wait for observation gate')
local proposals = collect(2.4, true)
assert_equal(#proposals, 1, 'confirmed downed party member must emit one proposal')
assert_equal(proposals[1].action_name, 'Raise III', 'provider must fall through to first ready configured resurrection spell')
assert_equal(proposals[1].target_id, 100, 'provider must target the downed human party member')
assert_equal(proposals[1].detail.def_action_type, 'resurrection', 'proposal type mismatch')
assert_equal(proposals[1].priority_band, 150, 'resurrection priority band mismatch')
assert_contains(proposals[1].legacy_command, 'DownedPlayer', 'resurrection command must identify target')

provider.note_dispatch(proposals[1], 2.4)
assert_equal(#collect(3.0, true), 0, 'dispatch gate must suppress immediate repeated Raise')
assert_equal(#collect(31.9, true), 0, 'dispatch gate must remain closed before retry deadline')
assert_equal(#collect(32.5, true), 1, 'still-downed target may retry after dispatch gate')

members[1].hpp = 50
assert_equal(#collect(33.0, true), 0, 'living party member must not receive Raise')
assert_equal(provider._resurrection_test.state.attempts[100], nil, 'living target must clear resurrection attempt state')
members[1].hpp = 0
assert_equal(#collect(34.0, true), 0, 'new death must restart observation gate')
ready['Arise'] = true
proposals = collect(34.4, true)
assert_equal(proposals[1].action_name, 'Arise', 'highest configured ready resurrection spell must win')

members[1].in_range = false
assert_equal(#collect(35.0, true), 0, 'out-of-range downed target must not emit')
members[1].in_range = true
ready['Arise'] = false
ready['Raise III'] = false
proposals = collect(35.5, true, 'Raise II|Raise')
assert_equal(proposals[1].action_name, 'Raise II', 'custom resurrection priority order must be honored')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_contains(scheduler_source, 'scheduler.providers.defensive.collect_resurrection(ctx, out)', 'scheduler resurrection collection missing')
assert_contains(scheduler_source, "detail.def_action_type == 'resurrection'", 'scheduler resurrection dispatch acknowledgement missing')
assert_contains(scheduler_source, "event_code = 'RESURRECTION_DISPATCHED'", 'resurrection dispatch timeline event missing')

io.stdout:write('selftest_defensive_resurrection: OK\n')
