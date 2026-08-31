local sent = {}
local zone_id = 100
local current_player = { name = 'Setter', id = 101 }
local party = {}

local previous_windower = rawget(_G, 'windower')
local previous_scope = rawget(_G, 'UC_ENABLE_ALLIANCE_TARGET_SCOPE')
local previous_time = os.time
local previous_camp_module = package.loaded['uc_camp_anchor']
local previous_targeting_module = package.loaded['uc_targeting_common']

local function member(name, id)
	return { mob = { name = name, id = id } }
end

local function set_standard_party()
	party = {
		p0 = member(current_player.name, current_player.id),
		p1 = member('Setter', 101),
		p2 = member('Peer', 202),
		p3 = member('Newmember', 303),
		a10 = member('Alliance', 404),
	}
end

local function switch_player(name, id)
	current_player = { name = name, id = id }
	set_standard_party()
end

local function clear_sent()
	for i = #sent, 1, -1 do
		sent[i] = nil
	end
end

windower = {
	send_ipc_message = function(message)
		sent[#sent + 1] = message
	end,
	ffxi = {
		get_info = function()
			return { zone = zone_id }
		end,
		get_player = function()
			return current_player
		end,
		get_party = function()
			return party
		end,
		get_mob_by_target = function(target)
			if target == 'me' then
				return { x = 12.5, y = -8.25 }
			end
			return nil
		end,
	},
}

os.time = function()
	return 2000000000
end
_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
switch_player('Setter', 101)

package.loaded['uc_targeting_common'] = nil
package.loaded['uc_camp_anchor'] = nil
local camp = require('uc_camp_anchor')

local function assert_true(value, message)
	if not value then
		error(message or 'expected true')
	end
end

local function assert_false(value, message)
	if value then
		error(message or 'expected false')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function revision_parts(revision)
	local timestamp, counter, author = revision:match('^(%d+):(%d+):([A-Za-z]+)$')
	if timestamp == nil then
		error('invalid test revision: ' .. tostring(revision))
	end
	return tonumber(timestamp), tonumber(counter), author
end

local function assert_revision_newer(newer, older, message)
	local new_timestamp, new_counter, new_author = revision_parts(newer)
	local old_timestamp, old_counter, old_author = revision_parts(older)
	local is_newer = new_timestamp > old_timestamp
		or (new_timestamp == old_timestamp and new_counter > old_counter)
		or (new_timestamp == old_timestamp and new_counter == old_counter and new_author:lower() > old_author:lower())
	assert_true(is_newer, message)
end

local function assert_state_unchanged(before, message)
	local after = camp.status()
	assert_equal(after.known, before.known, message .. ' known')
	assert_equal(after.active, before.active, message .. ' active')
	assert_equal(after.zone_id, before.zone_id, message .. ' zone')
	assert_equal(after.x, before.x, message .. ' x')
	assert_equal(after.y, before.y, message .. ' y')
	assert_equal(after.set_by, before.set_by, message .. ' setter')
	assert_equal(after.cleared_by, before.cleared_by, message .. ' clearer')
	assert_equal(after.revision, before.revision, message .. ' revision')
end

local function read_file(path)
	local handle, err = io.open(path, 'r')
	if handle == nil then
		error('failed to read ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local text = handle:read('*a')
	handle:close()
	return text
end

local function assert_contains(text, needle, message)
	if not text:find(needle, 1, true) then
		error((message or 'missing expected text') .. ': ' .. needle)
	end
end

-- Existing local SET and replicated SET behavior.
local anchor, reason = camp.resolve_current_anchor()
assert_equal(anchor, nil, 'unknown camp must not resolve')
assert_equal(reason, 'CAMP_UNSET', 'unknown camp reason mismatch')

local ok
ok, reason = camp.set_current_position()
assert_true(ok, 'local camp capture must succeed')
assert_equal(reason, 'CAMP_SET', 'local camp reason mismatch')
assert_equal(#sent, 1, 'local camp capture must broadcast once')
assert_true(sent[1]:find('uc_camp_anchor_v2|set|100|12.500000|-8.250000|Setter|101|', 1, true) == 1, 'camp SET payload mismatch')
local set_payload = sent[1]
local set_revision = camp.status().revision
assert_equal(camp.status().source, 'authored', 'local SET must be marked authored')

switch_player('Peer', 202)
camp.clear()
local consumed
consumed, ok, reason = camp.on_ipc_message(set_payload)
assert_true(consumed and ok, 'same-group SET IPC must install')
assert_equal(reason, 'CAMP_SET', 'replicated SET reason mismatch')
anchor = camp.resolve_current_anchor()
assert_equal(anchor.x, 12.5, 'replicated camp x mismatch')
assert_equal(anchor.y, -8.25, 'replicated camp y mismatch')
assert_equal(anchor.set_by, 'Setter', 'replicated camp setter mismatch')
assert_equal(anchor.revision, set_revision, 'replicated SET must preserve revision')

-- Explicit CLEAR is a newer replicated tombstone; stale SET cannot resurrect it.
clear_sent()
ok, reason = camp.clear_shared()
assert_true(ok, 'explicit shared clear must succeed')
assert_equal(reason, 'CAMP_CLEARED', 'explicit shared clear reason mismatch')
assert_equal(#sent, 1, 'explicit shared clear must broadcast once')
local clear_payload = sent[1]
local clear_status = camp.status()
local clear_revision = clear_status.revision
assert_true(clear_status.known and not clear_status.active, 'explicit clear must retain known tombstone state')
assert_equal(clear_status.cleared_by, 'Peer', 'tombstone clearer mismatch')
assert_revision_newer(clear_revision, set_revision, 'explicit CLEAR must mint a newer revision')

switch_player('Setter', 101)
camp.clear()
consumed, ok = camp.on_ipc_message(clear_payload)
assert_true(consumed and ok, 'same-group CLEAR IPC must install')
assert_true(camp.status().known and not camp.status().active, 'CLEAR IPC must install tombstone')
consumed, ok, reason = camp.on_ipc_message(set_payload)
assert_true(consumed and not ok, 'older SET must be rejected after newer CLEAR')
assert_equal(reason, 'CAMP_REVISION_STALE', 'older SET rejection mismatch')
assert_true(camp.status().known and not camp.status().active, 'older SET must not resurrect tombstone')
assert_equal(camp.status().revision, clear_revision, 'stale SET must not replace tombstone revision')

clear_sent()
consumed, ok = camp.on_ipc_message('uc_camp_anchor_v2|request|Newmember|303|100')
assert_true(consumed and ok, 'peer with tombstone knowledge must answer request')
local tombstone_state_payload = sent[1]
assert_true(tombstone_state_payload:find('|clear|-|-|Peer|202|' .. clear_revision .. '|Setter|101', 1, true) ~= nil, 'CLEAR STATE response must preserve tombstone revision')
switch_player('Newmember', 303)
camp.clear()
consumed, ok = camp.on_ipc_message(tombstone_state_payload)
assert_true(consumed and ok, 'requester must install replayed tombstone')
consumed, ok = camp.on_ipc_message(set_payload)
assert_true(consumed and not ok, 'stale peer SET must not resurrect replayed tombstone')
assert_equal(camp.status().revision, clear_revision, 'replayed tombstone must remain authoritative')

-- Request/replay plus reload recovery. The requester emits one request, a peer
-- responds without minting, and the requester installs the targeted response.
switch_player('Newmember', 303)
camp.clear()
clear_sent()
ok, reason = camp.request_current_state()
assert_true(ok, 'state request must send when runtime context is valid')
assert_equal(reason, 'CAMP_STATE_REQUESTED', 'request reason mismatch')
assert_equal(#sent, 1, 'state request must send one IPC message')
assert_equal(sent[1], 'uc_camp_anchor_v2|request|Newmember|303|100', 'request payload mismatch')
local request_payload = sent[1]

switch_player('Setter', 101)
camp.clear()
consumed, ok = camp.on_ipc_message(set_payload)
assert_true(consumed and ok, 'peer fixture must restore active camp knowledge')
clear_sent()
consumed, ok, reason = camp.on_ipc_message(request_payload)
assert_true(consumed and ok, 'same-group same-zone peer must answer request')
assert_equal(reason, 'CAMP_STATE_SENT', 'request response reason mismatch')
assert_equal(#sent, 1, 'one peer must emit one STATE response')
local state_payload = sent[1]
assert_true(state_payload:find('uc_camp_anchor_v2|state|Newmember|303|100|set|12.500000|-8.250000|Setter|101|' .. set_revision .. '|Setter|101', 1, true) == 1, 'STATE payload mismatch')

switch_player('Newmember', 303)
camp.clear()
consumed, ok, reason = camp.on_ipc_message(state_payload)
assert_true(consumed and ok, 'requester must install targeted active STATE')
assert_equal(reason, 'CAMP_SET', 'active STATE install reason mismatch')
local restored = camp.status()
assert_true(restored.known and restored.active, 'reload recovery must restore active camp')
assert_equal(restored.set_by, 'Setter', 'STATE replay must preserve original setter')
assert_equal(restored.revision, set_revision, 'STATE replay must preserve original revision')
assert_equal(restored.source, 'synchronized', 'STATE replay source mismatch')
consumed, ok = camp.on_ipc_message(state_payload)
assert_true(consumed and ok, 'identical STATE responses must be idempotent')
assert_equal(camp.status().revision, set_revision, 'idempotent replay must not mint a revision')

-- Membership changes emit one request for the new fingerprint and then remain silent.
clear_sent()
ok = camp.request_current_state()
assert_true(ok, 'baseline membership request must succeed')
clear_sent()
party.p4 = member('Joiner', 505)
local requested
requested, reason = camp.observe_runtime()
assert_true(requested, 'party membership change must trigger request')
assert_equal(reason, 'CAMP_STATE_REQUESTED', 'membership request reason mismatch')
assert_equal(#sent, 1, 'membership change must send one request')
requested, reason = camp.observe_runtime()
assert_false(requested, 'unchanged membership must remain silent')
assert_equal(reason, 'CAMP_GROUP_UNCHANGED', 'unchanged membership reason mismatch')
assert_equal(#sent, 1, 'unchanged membership must not spam IPC')

-- Wrong-zone requests and responses fail closed. A lifecycle clear is local-only,
-- and a later response in the entered zone can restore the camp.
switch_player('Setter', 101)
camp.clear()
camp.on_ipc_message(set_payload)
clear_sent()
zone_id = 101
consumed, ok = camp.on_ipc_message('uc_camp_anchor_v2|request|Newmember|303|100')
assert_true(consumed and not ok, 'wrong-zone request must be rejected')
assert_equal(#sent, 0, 'wrong-zone request must not receive response')

switch_player('Newmember', 303)
camp.clear()
local before_wrong_zone = camp.status()
consumed, ok = camp.on_ipc_message(state_payload)
assert_true(consumed and not ok, 'wrong-zone STATE must be rejected')
assert_state_unchanged(before_wrong_zone, 'wrong-zone STATE')

zone_id = 100
camp.on_ipc_message(state_payload)
clear_sent()
camp.clear()
assert_equal(#sent, 0, 'zone lifecycle clear must not broadcast shared CLEAR')
assert_false(camp.status().known, 'zone lifecycle clear must discard local knowledge')
camp.schedule_state_request()
requested, reason = camp.observe_runtime()
assert_true(requested, 'zone arrival must issue scheduled request once context is valid')
assert_equal(reason, 'CAMP_STATE_REQUESTED', 'zone arrival request reason mismatch')
camp.clear()
consumed, ok = camp.on_ipc_message(state_payload)
assert_true(consumed and ok, 'character entering camp zone must reacquire state')

-- Group isolation applies to requests, direct events, and targeted STATE.
clear_sent()
local isolated_before = camp.status()
consumed, ok = camp.on_ipc_message('uc_camp_anchor_v2|request|Outsider|999|100')
assert_true(consumed and not ok, 'out-of-group request must be rejected')
assert_equal(#sent, 0, 'out-of-group request must not receive camp state')
consumed, ok = camp.on_ipc_message('uc_camp_anchor_v2|set|100|1|2|Outsider|999|3000000000:0:Outsider')
assert_true(consumed and not ok, 'out-of-group SET must be rejected')
assert_state_unchanged(isolated_before, 'out-of-group SET')
local outsider_state = state_payload:gsub('|Setter|101$', '|Outsider|999')
consumed, ok = camp.on_ipc_message(outsider_state)
assert_true(consumed and not ok, 'STATE from unrelated responder must be rejected')
assert_state_unchanged(isolated_before, 'out-of-group STATE')

-- Alliance inclusion follows the established UnifiedCombat scope flag.
switch_player('Setter', 101)
camp.clear()
camp.on_ipc_message(set_payload)
clear_sent()
_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false
consumed, ok = camp.on_ipc_message('uc_camp_anchor_v2|request|Alliance|404|100')
assert_true(consumed and not ok, 'alliance requester must be excluded when alliance scope is disabled')
_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
consumed, ok = camp.on_ipc_message('uc_camp_anchor_v2|request|Alliance|404|100')
assert_true(consumed and ok, 'alliance requester must be included when alliance scope is enabled')
assert_equal(#sent, 1, 'enabled alliance requester must receive one response')

-- Newer SET wins, newer CLEAR wins, replay does not mint, and a subsequent
-- explicit SET legitimately reactivates the tombstone with a newer revision.
switch_player('Newmember', 303)
camp.clear()
local older_set = 'uc_camp_anchor_v2|state|Newmember|303|100|set|1.000000|2.000000|Setter|101|1000:0:Setter|Peer|202'
local newer_set = 'uc_camp_anchor_v2|state|Newmember|303|100|set|3.000000|4.000000|Setter|101|2000:0:Setter|Peer|202'
local newer_clear = 'uc_camp_anchor_v2|state|Newmember|303|100|clear|-|-|Peer|202|3000:0:Peer|Setter|101'
camp.on_ipc_message(older_set)
camp.on_ipc_message(newer_set)
assert_equal(camp.status().x, 3, 'newer SET must beat older SET')
camp.on_ipc_message(newer_clear)
assert_true(camp.status().known and not camp.status().active, 'newer CLEAR must beat older SET')
consumed, ok = camp.on_ipc_message(older_set)
assert_true(consumed and not ok, 'old SET must remain stale after tombstone replay')
assert_equal(camp.status().revision, '3000:0:Peer', 'tombstone revision must survive stale replay')
clear_sent()
ok = camp.set_current_position()
assert_true(ok, 'explicit SET after CLEAR must reactivate camp')
local reactivated = camp.status()
assert_true(reactivated.active, 'explicit SET after CLEAR must be active')
assert_revision_newer(reactivated.revision, '3000:0:Peer', 'explicit SET after CLEAR must be newer')

-- Malformed names, IDs, zones, coordinates, revisions, and shapes never mutate.
local valid_before_malformed = camp.status()
local malformed_messages = {
	'uc_camp_anchor_v2|set|100|1|2|Setter|101',
	'uc_camp_anchor_v2|set|bad|1|2|Setter|101|4000000000:0:Setter',
	'uc_camp_anchor_v2|set|100|nan|2|Setter|101|4000000000:0:Setter',
	'uc_camp_anchor_v2|set|100|1|2|Bad_Name|101|4000000000:0:BadName',
	'uc_camp_anchor_v2|set|100|1|2|Setter|bad|4000000000:0:Setter',
	'uc_camp_anchor_v2|set|100|1|2|Setter|101|not-a-revision',
	'uc_camp_anchor_v2|set|100|1|2|Setter|101|4000000000:0:Peer',
	'uc_camp_anchor_v2|state|Other|303|100|set|1|2|Setter|101|4000000000:0:Setter|Peer|202',
	'uc_camp_anchor_v2|state|Newmember|303|100|invalid|1|2|Setter|101|4000000000:0:Setter|Peer|202',
}
for i = 1, #malformed_messages do
	consumed, ok = camp.on_ipc_message(malformed_messages[i])
	assert_true(consumed and not ok, 'malformed IPC must fail: case ' .. tostring(i))
	assert_state_unchanged(valid_before_malformed, 'malformed IPC case ' .. tostring(i))
end

-- Lifecycle wiring is intentionally event-driven: load/login request directly,
-- zone schedules after local loss, and prerender only observes roster changes.
local addon_source = read_file('UnifiedCombat.lua')
assert_contains(addon_source, 'uc_camp_anchor.request_current_state()', 'load/login request wiring missing')
assert_contains(addon_source, 'uc_camp_anchor.observe_runtime()', 'membership observation wiring missing')
assert_contains(addon_source, 'uc_camp_anchor.schedule_state_request()', 'zone request scheduling missing')

package.loaded['uc_camp_anchor'] = previous_camp_module
package.loaded['uc_targeting_common'] = previous_targeting_module
os.time = previous_time
rawset(_G, 'UC_ENABLE_ALLIANCE_TARGET_SCOPE', previous_scope)
rawset(_G, 'windower', previous_windower)

print('selftest_camp_anchor: OK')
