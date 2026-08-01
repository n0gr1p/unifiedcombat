package.path = package.path .. ';./?.lua'

package.loaded['uc_camp_pull_registry'] = nil
local registry = require('uc_camp_pull_registry')

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

local sent = {}
local function send(message)
	sent[#sent + 1] = message
end

local friendly = {
	[100] = true,
	[101] = true,
}

local mob1 = {
	id = 300,
	name = 'Apex Crab',
	valid_target = true,
	spawn_type = 16,
	hpp = 99,
	status = 1,
	claim_id = 100,
}
local mob2 = {
	id = 301,
	name = 'Apex Crab',
	valid_target = true,
	spawn_type = 16,
	hpp = 100,
	status = 1,
	claim_id = 101,
}

registry.reset('selftest_start')
assert_equal(registry.register_reacted(mob1, friendly, 50, send), 'ACTIVE_PULL', 'friendly reacted pull state mismatch')
assert_equal(registry.register_reacted(mob2, friendly, 50, send), 'ACTIVE_PULL', 'second reacted pull state mismatch')
assert_equal(registry.combat_order(mob1, friendly), 1, 'first pull order mismatch')
assert_equal(registry.combat_order(mob2, friendly), 2, 'second pull order mismatch')
assert_true(registry.candidate_excluded(mob1.id), 'tracked pull must be excluded from new pull candidates')

mob1.claim_id = 0
assert_true(registry.quota_eligible(mob1, friendly), 'yellow hostile must re-enter quota immediately from live state')
assert_equal(registry.combat_order(mob1, friendly), 1, 'yellow hostile must re-enter cleanup immediately from live state')
registry.observe({ mob1, mob2 }, friendly, 50, send)
assert_equal(registry.snapshot().records[mob1.id].state, 'ACTIVE_PULL', 'yellow hostile pull must remain active')
assert_true(registry.quota_eligible(mob1, friendly), 'yellow hostile pull must continue occupying quota')

mob1.claim_id = 900
registry.observe({ mob1, mob2 }, friendly, 50, send)
assert_equal(registry.snapshot().records[mob1.id].state, 'FOREIGN_CLAIMED', 'outside claim must mark pull foreign-owned')
assert_true(not registry.quota_eligible(mob1, friendly), 'foreign-owned pull must not occupy quota')
assert_true(registry.combat_order(mob1, friendly) == nil, 'foreign-owned pull must not be a combat target')

mob1.claim_id = 0
assert_true(registry.quota_eligible(mob1, friendly), 'foreign-orphaned yellow mob must re-enter quota before registry observation')
assert_equal(registry.combat_order(mob1, friendly), 1, 'foreign-orphaned yellow mob must re-enter cleanup before registry observation')
registry.observe({ mob1, mob2 }, friendly, 50, send)
assert_equal(registry.snapshot().records[mob1.id].state, 'ORPHANED_HOSTILE', 'yellow hostile mob after foreign claim must become orphaned hostile')
assert_true(registry.quota_eligible(mob1, friendly), 'orphaned hostile must occupy quota')
assert_equal(registry.combat_order(mob1, friendly), 1, 'orphaned hostile must retain original cleanup order')

mob1.status = 0
registry.observe({ mob1, mob2 }, friendly, 50, send)
assert_equal(registry.snapshot().records[mob1.id].state, 'FORFEITED_IDLE', 'de-aggroed foreign-seen mob must become forfeited idle')
assert_true(not registry.quota_eligible(mob1, friendly), 'forfeited idle mob must not occupy quota')
assert_true(registry.candidate_excluded(mob1.id), 'forfeited idle mob must remain pull-excluded for its spawn')

mob1.status = 1
mob1.claim_id = 100
registry.observe({ mob1, mob2 }, friendly, 50, send)
assert_equal(registry.snapshot().records[mob1.id].state, 'ACTIVE_PULL', 'friendly reclaim must reactivate tracked pull')
assert_true(registry.snapshot().records[mob1.id].foreign_seen, 'friendly reclaim must retain foreign-claim history')

assert_true(registry.note_death(mob1.id), 'tracked death message must end the pull record')
assert_equal(registry.snapshot().records[mob1.id].state, 'ENDED', 'death message must enter ended state')
assert_true(registry.candidate_excluded(mob1.id), 'ended spawn must remain excluded until fresh spawn evidence')

mob1.hpp = 100
mob1.status = 0
mob1.claim_id = 0
registry.observe({ mob1, mob2 }, friendly, 50, send)
assert_true(registry.snapshot().records[mob1.id] == nil, 'fresh idle respawn after ended state must clear the old record')
assert_true(not registry.candidate_excluded(mob1.id), 'fresh spawn must become pull-eligible again')

local first_upsert = sent[1]
assert_true(type(first_upsert) == 'string' and first_upsert:find('uc_camp_pull_registry_v1|upsert|50|300|1|ACTIVE_PULL|0|Apex Crab', 1, true) == 1,
	'registry upsert IPC payload mismatch')
registry.reset('selftest_ipc_receiver')
local consumed, installed, reason = registry.on_ipc_message(first_upsert, 50)
assert_true(consumed, 'registry IPC message must be consumed')
assert_true(installed, 'valid registry IPC message must install')
assert_equal(reason, 'PULL_REGISTRY_UPDATED', 'registry IPC install reason mismatch')
assert_equal(registry.snapshot().records[300].pull_order, 1, 'registry IPC pull order mismatch')

consumed, installed, reason = registry.on_ipc_message(first_upsert, 51)
assert_true(consumed, 'cross-zone registry IPC message must be consumed')
assert_true(not installed, 'cross-zone registry IPC message must be rejected')
assert_equal(reason, 'PULL_REGISTRY_IPC_ZONE_MISMATCH', 'cross-zone registry IPC reason mismatch')

registry.reset('selftest_complete')
io.stdout:write('selftest_camp_pull_registry: OK\n')
