package.path = package.path .. ';./?.lua'

local camp_puller = require('uc_camp_puller')
local pull_registry = require('uc_camp_pull_registry')
pull_registry.reset('selftest_start')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(
			message or 'values differ',
			tostring(expected),
			tostring(actual)
		))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local config = {
	enabled = true,
	mode = 'camp',
	action = {
		type = 'spell',
		name = 'Dia II',
	},
	targets = {
		{ name = 'Apex Crab', priority = 20 },
	},
	match_mode = 'exact',
	max_active_mobs = 1,
	replenish_below_hpp = 20,
	leash_yalms = 35.0,
	max_z_delta = 2.0,
	cast_range_ratio = 0.90,
	settle_seconds = 0.40,
	reaction_timeout_seconds = 4.0,
	retry_limit = 2,
	retry_window_seconds = 2.5,
	target_cooldown_seconds = 20.0,
	camp_arrival_yalms = 0.75,
}

local timeline_events = {}
local pull_action_active = false
local start_lane_available = true
local start_lane_reason = ''
local ipc_messages = {}
local provider = camp_puller.new({
	resolve_camp_anchor = function()
		return {
			x = 0,
			y = 0,
		}, 'CAMP_READY'
	end,
	get_friendly_claims = function()
		return {
			[100] = true,
		}
	end,
	ignored = function()
		return false
	end,
	get_spell_resource = function(name)
		if name == 'Dia II' then
			return {
				id = 24,
				en = 'Dia II',
				range = 12,
			}
		end
		return nil
	end,
	get_ja_resource = function()
		return nil
	end,
	action_effective_range = function()
		return 20.0
	end,
	action_ready = function()
		return true, 'ready', 'spell'
	end,
	log = function()
	end,
	action_timeline_log = function(event_code, fields)
		timeline_events[#timeline_events + 1] = {
			event_code = event_code,
			fields = fields,
		}
	end,
	pull_action_in_flight = function()
		return pull_action_active
	end,
	can_start_journey = function()
		return start_lane_available, start_lane_reason
	end,
	get_zone_id = function()
		return 100
	end,
	send_ipc_message = function(message)
		ipc_messages[#ipc_messages + 1] = message
	end,
})

local mob = {
	id = 300,
	name = 'Apex Crab',
	valid_target = true,
	spawn_type = 16,
	hpp = 100,
	status = 0,
	claim_id = 0,
	x = 20,
	y = 0,
	z = 0,
	distance = 400,
}
local ctx = {
	now = 1.0,
	settings = {
		camp_pulling = config,
	},
	me = {
		id = 10,
		x = 0,
		y = 0,
		z = 0,
	},
	mob_array = { mob },
	mobs_by_id = {
		[300] = mob,
	},
	target_id_snapshot = 0,
}

local original_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)
assert_true(provider.movement_reserved(ctx.settings.camp_pulling), 'enabled camp pulling must reserve movement while idle')

start_lane_available = false
start_lane_reason = 'BRD_LANE:brd_targeted_pianissimo'
assert_true(not provider.acquire_lane(ctx), 'blocked action-lane handoff must not acquire the pull journey')
assert_equal(provider.status_snapshot().state, 'IDLE', 'blocked pre-target handoff must remain idle')
local out = {}
provider.collect(ctx, out)
assert_equal(#out, 0, 'blocked action-lane handoff must not emit a pull proposal')
assert_equal(provider.status_snapshot().state, 'IDLE', 'blocked action-lane handoff must remain idle')
assert_equal(
	provider.status_snapshot().detail,
	'PULL_WAIT_ACTION_LANE:BRD_LANE:brd_targeted_pianissimo',
	'blocked action-lane handoff reason mismatch'
)
start_lane_available = true
start_lane_reason = ''

out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'candidate selection must immediately emit an ID-based approach')
assert_equal(out[1].action_type, 'camp_approach', 'direct candidate approach proposal mismatch')
assert_equal(out[1].target_id, mob.id, 'direct candidate approach must retain the selected entity id')
assert_equal(timeline_events[#timeline_events].event_code, 'CAMP_PULL_STATE', 'state transition must be written to the action timeline')
assert_equal(timeline_events[#timeline_events].fields.target_distance, 20, 'timeline must include observed target distance')
assert_equal(provider.status_snapshot().state, 'APPROACH', 'candidate selection must enter approach without changing the game target')

ctx.now = 1.2
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'prepared distant target must emit approach without waiting for a target snapshot')
assert_equal(out[1].action_type, 'camp_approach', 'approach proposal mismatch')

mob.distance = 100
ctx.now = 1.4
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'in-range target must emit precast stop')
assert_equal(out[1].action_type, 'camp_stop', 'precast stop proposal mismatch')
provider.note_dispatch(out[1], ctx.now, config)

ctx.now = 1.6
out = {}
provider.collect(ctx, out)
assert_equal(#out, 0, 'settle interval must wait without blocking')
assert_equal(provider.status_snapshot().reason, 'PULL_SETTLE', 'settle status mismatch')

ctx.now = 1.9
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'settled puller must emit configured action')
assert_equal(out[1].action_type, 'spell', 'pull spell proposal type mismatch')
assert_equal(out[1].action_name, 'Dia II', 'pull spell proposal name mismatch')
provider.note_dispatch(out[1], ctx.now, config)

ctx.now = 2.0
out = {}
provider.collect(ctx, out)
assert_equal(#out, 0, 'pull action result must be awaited')
assert_equal(provider.status_snapshot().state, 'WAIT_ACTION_RESULT', 'action wait state mismatch')

config.retry_window_seconds = 0.1
pull_action_active = true
ctx.now = 2.1
out = {}
provider.collect(ctx, out)
assert_equal(#out, 0, 'an in-flight pull action must remain protected after the retry window')
assert_equal(provider.status_snapshot().state, 'WAIT_ACTION_RESULT', 'in-flight pull action must not time out')
assert_equal(provider.status_snapshot().detail, 'PULL_ACTION_IN_FLIGHT', 'in-flight wait detail mismatch')

config.retry_window_seconds = 2.5
pull_action_active = false
ctx.now = 2.2
provider.note_action_result(false, ctx.now, config)
assert_equal(provider.status_snapshot().state, 'SETTLE', 'failed pull action should enter bounded retry settle')

ctx.now = 2.7
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'settled retry must re-emit configured action')
assert_equal(out[1].action_name, 'Dia II', 'retry action mismatch')
provider.note_dispatch(out[1], ctx.now, config)
provider.note_action_result(true, ctx.now, config)

ctx.now = 2.9
mob.hpp = 99
mob.status = 1
ctx.me.x = 10
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'reacted target must begin return')
assert_equal(out[1].action_type, 'camp_return', 'camp return proposal mismatch')

ctx.now = 3.1
ctx.me.x = 0
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'camp arrival must emit explicit stop')
assert_equal(out[1].action_type, 'camp_stop', 'camp arrival stop mismatch')
provider.note_dispatch(out[1], ctx.now, config)
assert_equal(provider.status_snapshot().state, 'IDLE', 'camp stop must complete journey')
assert_equal(provider.status_snapshot().tracked_count, 1, 'successful reacted pull must remain tracked after return')
assert_true(#ipc_messages > 0, 'successful reacted pull must publish registry state over IPC')
pull_registry.reset('selftest_next_scenario')

mob.hpp = 100
mob.status = 0
mob.claim_id = 0
mob.distance = 400
ctx.target_id_snapshot = 0
ctx.now = 3.3
out = {}
provider.collect(ctx, out)
assert_equal(provider.status_snapshot().state, 'APPROACH', 'engine-stop scenario must start an active journey')
rawset(_G, 'Start_Engine', false)
assert_true(not provider.movement_reserved(ctx.settings.camp_pulling), 'engine stop must release camp-puller movement reservation')
ctx.now = 3.4
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'engine stop during a journey must emit a movement stop')
assert_equal(out[1].action_type, 'camp_stop', 'engine stop proposal mismatch')
assert_equal(provider.status_snapshot().state, 'ABORT_STOP', 'engine stop must enter abort state')

rawset(_G, 'Start_Engine', true)
provider.note_dispatch(out[1], ctx.now, config)
mob.hpp = 100
mob.status = 0
mob.claim_id = 0
mob.distance = 400
ctx.me.x = 0
ctx.mob_array = { mob }
ctx.now = 4.0
out = {}
provider.collect(ctx, out)
assert_equal(out[1].action_type, 'camp_approach', 'quota revalidation scenario must approach by entity id')

local active_mob = {
	id = 301,
	name = 'Apex Crab',
	valid_target = true,
	spawn_type = 16,
	hpp = 80,
	status = 1,
	claim_id = 100,
	x = 1,
	y = 0,
	z = 0,
	distance = 1,
}
ctx.mob_array = { mob, active_mob }
ctx.mobs_by_id[301] = active_mob
ctx.now = 4.2
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'quota becoming satisfied before dispatch must terminate the selected journey')
assert_equal(out[1].action_type, 'camp_stop', 'quota cancellation at camp must emit an explicit stop')
assert_equal(provider.status_snapshot().state, 'RETURN_TO_CAMP', 'quota cancellation must enter return state')
assert_true(
	provider.status_snapshot().detail == 'PULL_CAMP_ARRIVED',
	'quota cancellation at camp must stop without dispatching the pull action'
)

local scheduler_file = assert(io.open('unified_scheduler.lua', 'rb'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
local pathing_file = assert(io.open('uc_pathing.lua', 'rb'))
local pathing_source = pathing_file:read('*a')
pathing_file:close()
local follow_file = assert(io.open('uc_party_follow.lua', 'rb'))
local follow_source = follow_file:read('*a')
follow_file:close()
assert_true(
	scheduler_source:find('PULL_COMBAT_DOMAIN_DISABLED', 1, true) ~= nil,
	'combat-domain disable must have an explicit camp-puller terminal reason'
)
assert_true(
	scheduler_source:find('PULL_MOVEMENT_DOMAIN_DISABLED', 1, true) ~= nil,
	'movement-domain disable must explicitly stop and release an active camp journey'
)
assert_true(
	scheduler_source:find("p1_build_pull_executor().stop({", 1, true) ~= nil,
	'combat-domain disable must dispatch an explicit movement stop'
)
assert_true(
	scheduler_source:find("if scheduler.providers.camp_puller.movement_reserved(camp_pulling_config()) then", 1, true) ~= nil,
	'enabled camp pulling must reserve movement even while idle at camp'
)
assert_true(
	scheduler_source:find("return false, 'MOVE_COORD_CAMP_PULL_RESERVED'", 1, true) ~= nil,
	'normal movement coordinator must yield while camp pulling is enabled'
)
assert_true(
	scheduler_source:find('pull_action_in_flight = function(target_id, action_type, action_name)', 1, true) ~= nil,
	'camp puller must receive the scheduler action-state ownership check'
)
assert_true(
	scheduler_source:find('return action_is_acting()', 1, true) ~= nil,
	'camp pull action timeout must reuse scheduler action-state waiting'
)
assert_true(
	scheduler_source:find('scheduler.p1_camp_lane_blocks_proposal', 1, true) ~= nil,
	'active camp journeys must have an explicit scheduler action-lane policy'
)
assert_true(
	scheduler_source:find("return tostring(proposal.provider or '') ~= 'camp_puller'", 1, true) ~= nil,
	'camp action-lane ownership must reject every competing provider'
)
assert_true(
	scheduler_source:find('and not camp_journey_active', 1, true) ~= nil,
	'maintenance collection must defer while a camp journey is active'
)
assert_true(
	scheduler_source:find("return true, 'BLOCK_CAMP_PULL_ACTION_LANE'", 1, true) ~= nil,
	'camp action-lane ownership must persist across proposal gaps'
)
assert_true(
	scheduler_source:find('scheduler.providers.camp_puller.acquire_lane(acquisition_ctx)', 1, true) ~= nil,
	'the camp puller must acquire its action lane before nonblocking target selection'
)
assert_true(
	scheduler_source:find("return false, 'BRD_LANE:' .. tostring(brd_reason or '')", 1, true) ~= nil,
	'a camp journey must not begin while Bard owns its atomic lane'
)
assert_true(
	scheduler_source:find("return false, 'SCH_ATOMIC_LANE:' .. tostring(sch_lane.reason or '')", 1, true) ~= nil,
	'a camp journey must not begin while Scholar owns its atomic lane'
)
assert_true(
	scheduler_source:find("return false, 'GEO_LANE'", 1, true) ~= nil,
	'a camp journey must not begin during a non-pull GEO atomic sequence'
)
assert_true(
	scheduler_source:find("return false, 'REACTION_LANE'", 1, true) ~= nil,
	'a camp journey must not begin while a reaction sequence owns action or movement'
)
assert_true(
	scheduler_source:find("return false, 'NYZUL_MOVEMENT_HOLD'", 1, true) ~= nil,
	'a camp journey must not begin while Nyzul owns movement'
)
assert_true(
	scheduler_source:match(
		'get_reaction_lock%s*=%s*function%(%)%s*'
			.. 'if%s+scheduler%.providers%.camp_puller%.active%(%)%s*then%s*return%s+nil'
	) ~= nil,
	'an active camp journey must defer reaction proposal blocking until the journey completes'
)
assert_true(
	scheduler_source:find("if action_type == 'camp_prepare_target'", 1, true) == nil,
	'camp pulling must never install a pull candidate as the selected game target'
)
assert_true(
	scheduler_source:find('local command = build_action_command(action_name, action_type, {', 1, true) ~= nil,
	'camp pull actions must dispatch directly through the entity-id command builder'
)
assert_true(
	pathing_source:find("return true, 'OWNER_camp_puller'", 1, true) ~= nil,
	'route/path movement must yield without stopping camp-puller movement'
)
assert_true(
	follow_source:find('if uc_camp_puller.movement_reserved(s.camp_pulling) then', 1, true) ~= nil,
	'party-follow movement must yield while camp pulling owns movement'
)

if original_engine == nil then
	rawset(_G, 'Start_Engine', nil)
else
	rawset(_G, 'Start_Engine', original_engine)
end

io.stdout:write('selftest_camp_puller: OK\n')
