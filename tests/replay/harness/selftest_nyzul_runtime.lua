package.path = './?.lua;' .. package.path

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local current_name = 'Redrogue'
local sent_ipc = {}
local run_calls = {}
local registered_events = {}
local chat_lines = {}

_G.socket = {
	gettime = function()
		return 123.456
	end,
}

_G.windower = {
	ffxi = {
		get_player = function()
			return { name = current_name, id = 1 }
		end,
		get_party = function()
			local names = { 'Redrogue', 'Terrasjr', 'Nyoourke', 'Ponponponponp', 'Niightsiide' }
			local party = {}
			for i = 1, #names do
				party['p' .. tostring(i - 1)] = { mob = { name = names[i], id = i } }
			end
			return party
		end,
		run = function(value)
			run_calls[#run_calls + 1] = value
		end,
	},
	send_ipc_message = function(message)
		sent_ipc[#sent_ipc + 1] = message
	end,
	register_event = function(name, callback)
		registered_events[#registered_events + 1] = { name = name, callback = callback }
		return #registered_events
	end,
	add_to_chat = function(color, message)
		chat_lines[#chat_lines + 1] = { color = color, message = message }
	end,
}

package.loaded.uc_active_config = nil
local active_config = require('uc_active_config')
local profile_v2 = require('uc_profile_v2')
local profile, profile_error = active_config.build_active_profile_from_v2_payload({
	version = 2,
	profile = {
		schema_version = 2,
		engine = 'UC',
		character = 'Redrogue',
		main_job = 'BRD',
		sub_job = 'WHM',
		source = 'ui',
	},
	config = {
		follow = {
			nyzul = {
				coordinator_name = 'Redrogue',
				anchor_name = 'Terrasjr',
				parking_order = { 'Nyoourke', 'Ponponponponp', 'Niightsiide' },
			},
		},
	},
}, {
	character = 'Redrogue',
	main_job = 'BRD',
	sub_job = 'WHM',
	source = 'UC_PROFILE_V2',
})
assert_true(type(profile) == 'table', 'active Nyzul profile failed: ' .. tostring(profile_error))
assert_true(active_config.set_active_profile(profile) == true, 'active Nyzul profile was not installed')

local omitted_diff = profile_v2.diff_durable_config({
	follow = {
		nyzul = {
			coordinator_name = '',
			anchor_name = '',
			parking_order = {},
		},
	},
}, {
	follow = {},
})
assert_equal(omitted_diff.count, 0, 'unconfigured Nyzul section must be equivalent to omission')

local configured_diff = profile_v2.diff_durable_config({
	follow = {
		nyzul = {
			coordinator_name = 'Redrogue',
			anchor_name = 'Terrasjr',
			parking_order = { 'Nyoourke', 'Ponponponponp' },
		},
	},
}, {
	follow = {
		nyzul = {
			coordinator_name = 'Redrogue',
			anchor_name = 'Terrasjr',
			parking_order = { 'Nyoourke', 'Ponponponponp' },
		},
	},
})
assert_equal(configured_diff.count, 0, 'configured Nyzul roster must compare durably')

local function load_runtime_instance()
	local chunk = assert(loadfile('uc_nyzul_runtime.lua'))
	return chunk()
end

local coordinator = load_runtime_instance()
local anchor = load_runtime_instance()
local first_parker = load_runtime_instance()
local second_parker = load_runtime_instance()

current_name = 'Redrogue'
local ok, message = coordinator.begin()
assert_true(ok, 'Nyzul begin failed: ' .. tostring(message))
assert_true(sent_ipc[#sent_ipc]:find('|begin|', 1, true) ~= nil, 'begin must use Nyzul IPC')
assert_true(sent_ipc[#sent_ipc]:find('|Terrasjr', 1, true) ~= nil, 'begin must target configured anchor')
assert_true(_G.UC_SETTINGS == nil or _G.UC_SETTINGS.engine_enabled == nil, 'Nyzul begin must not mutate engine state')

current_name = 'Terrasjr'
assert_true(anchor.ipc_message(sent_ipc[#sent_ipc]), 'anchor must consume begin IPC')
assert_equal(anchor.status().role, 'anchor', 'configured anchor must enter anchor hold')
assert_true(anchor.status().active, 'anchor must see the active Nyzul run')
assert_true(anchor.is_movement_held(), 'anchor must hold movement')

current_name = 'Redrogue'
ok, message = coordinator.park_next()
assert_true(ok, 'first park failed: ' .. tostring(message))
assert_true(message:find('Nyoourke', 1, true) ~= nil, 'first park must choose first configured parker')
local first_park_message = sent_ipc[#sent_ipc]
assert_true(first_park_message:find('|Nyoourke', 1, true) ~= nil, 'first park IPC target mismatch')

current_name = 'Nyoourke'
assert_true(first_parker.ipc_message(first_park_message), 'first parker must consume park IPC')
assert_equal(first_parker.status().role, 'lamp', 'first parker must enter lamp hold')
assert_true(first_parker.enforce_movement_hold(), 'lamp hold must enforce movement stop')
assert_equal(run_calls[#run_calls], false, 'lamp hold must issue run(false)')
local first_ack = sent_ipc[#sent_ipc]
assert_true(first_ack:find('|ack|', 1, true) ~= nil, 'parker must acknowledge park IPC')
current_name = 'Redrogue'
coordinator.ipc_message(first_ack)
assert_equal(coordinator.status().parked_order[1], 'Nyoourke', 'queue must advance only after parker acknowledgement')

current_name = 'Redrogue'
ok, message = coordinator.park_next()
assert_true(ok, 'second park failed: ' .. tostring(message))
assert_true(message:find('Ponponponponp', 1, true) ~= nil, 'second park must choose second configured parker')
local second_park_message = sent_ipc[#sent_ipc]
current_name = 'Ponponponponp'
second_parker.ipc_message(second_park_message)
local second_ack = sent_ipc[#sent_ipc]
current_name = 'Redrogue'
coordinator.ipc_message(second_ack)

ok, message = coordinator.undo()
assert_true(ok, 'undo failed: ' .. tostring(message))
assert_true(message:find('Ponponponponp', 1, true) ~= nil, 'undo must release most recent parker')

ok, message = coordinator.regroup()
assert_true(ok, 'regroup failed: ' .. tostring(message))
local regroup_message = sent_ipc[#sent_ipc]
current_name = 'Nyoourke'
first_parker.ipc_message(regroup_message)
assert_equal(first_parker.status().role, 'none', 'regroup must release temporary lamp hold')
current_name = 'Terrasjr'
anchor.ipc_message(regroup_message)
assert_equal(anchor.status().role, 'anchor', 'regroup must preserve anchor hold')

current_name = 'Redrogue'
ok, message = coordinator.park_next()
assert_true(ok, 'post-regroup park failed: ' .. tostring(message))
assert_true(message:find('Nyoourke', 1, true) ~= nil, 'regroup must reset queue to first parker')

ok, message = coordinator.finish()
assert_true(ok, 'Nyzul end failed: ' .. tostring(message))
local end_message = sent_ipc[#sent_ipc]
current_name = 'Terrasjr'
anchor.ipc_message(end_message)
assert_equal(anchor.status().role, 'none', 'Nyzul end must release anchor')
assert_true(not anchor.status().active, 'anchor must see the ended Nyzul run')

local follow_source = assert(io.open('uc_party_follow.lua', 'rb')):read('*a')
local path_source = assert(io.open('uc_pathing.lua', 'rb')):read('*a')
local scheduler_source = assert(io.open('unified_scheduler.lua', 'rb')):read('*a')
assert_true(follow_source:find('uc_nyzul_runtime.enforce_movement_hold()', 1, true) ~= nil, 'party follow must honor Nyzul hold')
assert_true(path_source:find('uc_nyzul_runtime.is_movement_held()', 1, true) ~= nil, 'path movement must honor Nyzul hold')
assert_true(scheduler_source:find("UC_MOVEMENT_MODE = 'NYZUL_HOLD'", 1, true) ~= nil, 'scheduler movement must honor Nyzul hold')

print('selftest_nyzul_runtime: OK')
