local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local text = fh:read('*a')
	fh:close()
	return text
end

local function assert_contains(text, needle, message)
	if not text:find(needle, 1, true) then
		error((message or 'missing expected text') .. ': ' .. needle)
	end
end

local function assert_not_contains(text, needle, message)
	if text:find(needle, 1, true) then
		error((message or 'unexpected text') .. ': ' .. needle)
	end
end

local addon = read_file('UnifiedCombat.lua')
local scheduler = read_file('unified_scheduler.lua')
local bridge = read_file('remote_bridge.lua')

local incoming = scheduler:match(
	'function scheduler%.on_incoming_chunk%(id, data%)(.-)function scheduler%.seed_cached_status_snapshot'
)
if type(incoming) ~= 'string' then
	error('failed to capture scheduler.on_incoming_chunk')
end
assert_not_contains(incoming, 'Start_Engine', 'packet tracking must not depend on engine actuation state')
assert_contains(incoming, "require('uc_party_buff_tracker').ingest(data, now_s())", 'party buff packets must remain always observed')
assert_contains(incoming, "require('uc_brd_maintenance').on_status_snapshot(snap, now_s())", 'Bard timer snapshots must remain always observed')
assert_contains(incoming, 'ingest_enemy_effects_from_raw_action_028(data)', 'enemy effects must remain always observed')

local on_action = scheduler:match(
	'function scheduler%.on_action%(act%)(.-)function scheduler%.on_action_message'
)
if type(on_action) ~= 'string' then
	error('failed to capture scheduler.on_action')
end
local brd_observer_at = on_action:find("require('uc_brd_maintenance').on_action", 1, true)
local reaction_gate_at = on_action:find("if rawget(_G, 'Start_Engine') == true then", 1, true)
local enemy_observer_at = on_action:find('enemy_effect_tracker.on_action', 1, true)
if not brd_observer_at or not reaction_gate_at or not enemy_observer_at then
	error('scheduler action observation landmarks are incomplete')
end
if brd_observer_at >= reaction_gate_at then
	error('Bard action observation must occur before the engine-gated reaction controller')
end
if enemy_observer_at <= reaction_gate_at then
	error('enemy effect observation must remain outside the engine-gated reaction controller')
end

assert_contains(addon, "require('uc_brd_maintenance').suspend(stop_reason)", 'engine stop must suspend Bard actuation')
assert_not_contains(addon, "require('uc_brd_maintenance').reset('engine_stop')", 'engine stop must preserve Bard tracking')
assert_contains(addon, "require('uc_brd_maintenance').resume('engine_start')", 'engine start must reconcile Bard tracking')
assert_contains(addon, '_G.UC_COR_MAINT_OnIncomingChunk(id, data)', 'COR packet tracking must remain on the addon event path')
assert_contains(bridge, "_G.UC_StopUnifiedEngine('engine_stop')", 'remote engine stop must use the centralized lifecycle path')
assert_contains(incoming, "require('uc_brd_maintenance').reset('zone_change')", 'zone change must fully invalidate Bard tracking')
assert_contains(incoming, "require('uc_party_buff_tracker').reset()", 'zone change must invalidate cached party buffs')
assert_contains(incoming, 'enemy_effect_tracker.clear_all()', 'zone change must invalidate enemy effect tracking')

io.stdout:write('selftest_tracking_lifecycle_static: OK\n')
