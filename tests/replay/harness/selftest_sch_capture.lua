local function assert_true(value, message)
	if value ~= true then
		error(message or 'assertion failed')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected)
			.. ' actual=' .. tostring(actual))
	end
end

local function read_file(path)
	local handle, open_error = io.open(path, 'rb')
	if handle == nil then
		error('failed to open ' .. path .. ': ' .. tostring(open_error))
	end
	local content = handle:read('*a')
	handle:close()
	return content
end

local function assert_contains(content, literal, message)
	if content:find(literal, 1, true) == nil then
		error(message or ('missing expected text: ' .. literal))
	end
end

local function assert_not_contains(content, literal, message)
	if content:find(literal, 1, true) ~= nil then
		error(message or ('unexpected text: ' .. literal))
	end
end

local function main()
	package.loaded.uc_sch_capture = nil
	local capture_module = require('uc_sch_capture')
	local directories = {
		['C:\\UC\\data'] = true,
	}
	local files = {}
	local function fake_handle(path)
		local handle = {}
		function handle:write(value)
			files[path] = (files[path] or '') .. value
			return self
		end
		function handle:flush()
			return true
		end
		function handle:close()
			return true
		end
		return handle
	end
	local capture = capture_module.new({
		addon_path = function()
			return 'C:\\UC'
		end,
		dir_exists = function(path)
			return directories[path] == true
		end,
		create_dir = function(path)
			directories[path] = true
			return true
		end,
		open_file = function(path, mode)
			assert_equal(mode, 'wb', 'capture open mode mismatch')
			files[path] = ''
			return fake_handle(path)
		end,
		file_exists = function(path)
			return files[path] ~= nil
		end,
		file_stamp = function()
			return '20260820T120000Z'
		end,
	})

	local started, message, path = capture.start({
		label = 'solo_phase1',
		character = 'Scholar',
		main_job = 'SCH',
		sub_job = 'RDM',
	}, 100)
	assert_true(started, 'capture failed to start: ' .. tostring(message))
	assert_equal(
		path,
		'C:\\UC\\data\\sch_captures\\Scholar_solo_phase1_20260820T120000Z.lua.log',
		'capture path mismatch'
	)
	assert_true(not capture.start({
		label = 'duplicate',
		character = 'Scholar',
		main_job = 'SCH',
		sub_job = 'RDM',
	}, 100.1), 'duplicate capture start must fail')
	assert_true(capture.mark('light_arts_success', 101), 'capture mark failed')
	local sample = {
		main_job = 'SCH',
		job_points_present = true,
		job_points_spent = 2100,
		recast_present = true,
		recast = 33,
		buffs = {},
		party = {},
	}
	assert_true(capture.record_sample(sample, 101.1), 'capture sample failed')
	assert_true(not capture.record_sample(sample, 101.2), 'unchanged sample must deduplicate')
	local changed = {
		main_job = 'SCH',
		job_points_present = true,
		job_points_spent = 2100,
		recast_present = true,
		recast = 32,
		buffs = { 358 },
		party = {},
	}
	assert_true(capture.record_sample(changed, 102), 'changed sample must persist')
	assert_true(capture.record_trace({
		id = 1,
		phase = 'complete',
		terminal_reason = 'settled',
		events = {
			{ kind = 'action', action_name = 'Light Arts', at = 101.5 },
		},
	}, 104), 'capture trace failed')
	local stopped, stop_message, stop_path = capture.stop('operator_stop', 105)
	assert_true(stopped, 'capture failed to stop: ' .. tostring(stop_message))
	assert_equal(stop_path, path, 'capture stop path mismatch')

	local entries = {}
	for line in files[path]:gmatch('[^\r\n]+') do
		local chunk, load_error = loadstring(line, '@sch_capture_line')
		assert_true(type(chunk) == 'function', 'capture line did not parse: ' .. tostring(load_error))
		entries[#entries + 1] = chunk()
	end
	assert_equal(#entries, 6, 'capture entry count mismatch')
	assert_equal(entries[1].kind, 'session_start', 'capture header missing')
	assert_equal(entries[2].kind, 'mark', 'capture mark entry missing')
	assert_equal(entries[3].kind, 'sample', 'first capture sample missing')
	assert_equal(entries[4].sample.recast, 32, 'changed capture sample mismatch')
	assert_equal(entries[5].kind, 'trace', 'capture trace entry missing')
	assert_equal(entries[5].mark, 'light_arts_success', 'trace mark mismatch')
	assert_equal(entries[6].trace_count, 1, 'capture stop trace count mismatch')
	assert_true(not capture.stop('operator_stop', 106), 'inactive capture stop must fail')

	local invalid = capture_module.new({
		addon_path = function() return 'C:\\UC' end,
		dir_exists = function(path) return directories[path] == true end,
		create_dir = function(path) directories[path] = true return true end,
		open_file = function(path) return fake_handle(path) end,
		file_exists = function() return false end,
		file_stamp = function() return '20260820T120001Z' end,
	})
	assert_true(not pcall(invalid.start, {
		label = 'bad label',
		character = 'Scholar',
		main_job = 'SCH',
		sub_job = 'RDM',
	}, 200), 'unsafe capture label must fail fast')

	local provider_source = read_file('uc_provider_sch_maintenance.lua')
	local addon_source = read_file('UnifiedCombat.lua')
	local solo_script = read_file('scripts/sch_capture_solo.txt')
	local party_script = read_file('scripts/sch_capture_party_ranges.txt')
	assert_contains(provider_source, 'capture.record_sample(trace_sample, ctx.now)',
		'Scholar provider must continuously persist changing capture samples')
	assert_contains(provider_source, 'capture.record_trace(trace_snapshot.last, ctx.now)',
		'Scholar provider must persist completed raw traces')
	assert_contains(addon_source, "capture_command == 'start'",
		'addon must expose Scholar capture start')
	assert_contains(addon_source, "capture_command == 'stop'",
		'addon must expose Scholar capture stop')
	assert_contains(solo_script, 'uc sch capture start solo_phase1',
		'solo script must start one durable capture')
	assert_contains(solo_script, 'uc sch capture stop',
		'solo script must stop its durable capture')
	assert_contains(solo_script, 'uc sch trace once',
		'solo script must arm bounded raw traces automatically')
	assert_not_contains(solo_script, 'input //uc',
		'solo script must use direct Windower addon command syntax')
	assert_not_contains(solo_script, 'Tabula Rasa',
		'solo script must not spend Tabula Rasa')
	assert_contains(party_script, 'uc sch capture start party_ranges',
		'party script must start one durable capture')
	assert_contains(party_script, 'input /ma "Regen V" <p1>',
		'party script must capture p1-centered Accession geometry')
	assert_contains(party_script, 'input /ma "Regen V" <p2>',
		'party script must capture p2-centered Accession geometry')
	assert_contains(party_script, 'input /ma "Regen V" <p3>',
		'party script must capture p3-centered Accession geometry')
	assert_not_contains(party_script, 'input //uc',
		'party script must use direct Windower addon command syntax')

	print('selftest_sch_capture: OK')
end

main()
