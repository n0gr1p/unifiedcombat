local function assert_true(value, message)
	if not value then error(message or 'assertion failed') end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local old_resources = package.loaded.resources
local old_module = package.loaded.uc_brd_maintenance
local old_windower = windower

local song_options = require('uc_brd_song_options')
local option_resources = {
	spells = {
		[100] = { en = "Army's Paeon", type = 'BardSong', targets = { Self = true }, levels = { [10] = 5 } },
		[101] = { en = 'Honor March', type = 'BardSong', targets = { Self = true }, levels = { [10] = 99 } },
		[102] = { en = 'Foe Requiem', type = 'BardSong', targets = { Enemy = true }, levels = { [10] = 7 } },
	},
}
local main_options, main_option_stats = song_options.collect(option_resources, { [100] = true, [101] = true, [102] = true }, {
	main_job = 'BRD',
	sub_job = 'WHM',
	main_job_level = 99,
	sub_job_level = 49,
})
assert_equal(#main_options, 2, 'main-job BRD options must include learned level-eligible area songs')
assert_equal(main_options[1], "Army's Paeon", 'BRD options must be sorted')
assert_equal(main_options[2], 'Honor March', 'main-job BRD options must include level-99 songs')
assert_equal(main_option_stats.resource_song_count, 3, 'BRD option resource count mismatch')
assert_equal(main_option_stats.learned_song_count, 3, 'BRD learned-song count mismatch')

option_resources.spells[100].targets = 1
local raw_mask_options = song_options.collect(option_resources, { [100] = true }, {
	main_job = 'BRD',
	sub_job = 'WHM',
	main_job_level = 99,
	sub_job_level = 49,
})
assert_equal(#raw_mask_options, 1, 'BRD options must also accept unprocessed numeric target masks')
option_resources.spells[100].targets = { Self = true }
local sub_options = song_options.collect(option_resources, { [100] = true, [101] = true }, {
	main_job = 'SCH',
	sub_job = 'BRD',
	main_job_level = 99,
	sub_job_level = 49,
})
assert_equal(#sub_options, 1, 'support-job BRD options must exclude songs above support-job level')
assert_equal(sub_options[1], "Army's Paeon", 'support-job BRD option mismatch')

package.loaded.resources = {
	spells = {
		[1] = { id = 1, en = 'Honor March', status = 100, type = 'BardSong', targets = { Self = true } },
		[2] = { id = 2, en = 'Victory March', status = 100, type = 'BardSong', targets = { Self = true } },
		[3] = { id = 3, en = "Army's Paeon", status = 101, type = 'BardSong', targets = { Self = true } },
		[4] = { id = 4, en = "Army's Paeon II", status = 101, type = 'BardSong', targets = { Self = true } },
		[5] = { id = 5, en = 'Magic Finale', status = 102, type = 'BardSong', targets = { Enemy = true } },
		[6] = { id = 6, en = 'Valor Minuet V', status = 103, type = 'BardSong', targets = { Self = true } },
		[7] = { id = 7, en = 'Valor Minuet IV', status = 103, type = 'BardSong', targets = { Self = true } },
		[8] = { id = 8, en = 'Mage\'s Ballad III', status = 104, type = 'BardSong', targets = { Self = true } },
	},
}
package.loaded.uc_brd_maintenance = nil

local brd = require('uc_brd_maintenance')
local player = { id = 77, name = 'Redrogue', main_job = 'BRD', sub_job = 'WHM', buffs = {} }
windower = {
	addon_path = './',
	ffxi = {
		get_player = function()
			return { name = 'Selftestbrd' }
		end,
	},
}
local ready = function(name)
	if name == 'Nightingale' or name == 'Troubadour' or name == 'Marcato' or name == 'Clarion Call' then
		return true, '', 'ja'
	end
	return true, '', 'spell'
end
local config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March' },
	dummy_songs = {},
	use_nitro = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
}
local log_ok, log_path = brd.start_diagnostic_log()
assert_true(log_ok == true, 'BRD diagnostic log must start in the replay harness')

local ok, reason = brd._test.validate_config(config, player)
assert_true(ok, 'valid dedicated BRD config rejected: ' .. tostring(reason))
local clock_epoch = 1784356393
local clock_timestamp = 123456789
local clock_packet_offset = 54321
local clock_vana_time = clock_timestamp * 60 - math.floor(clock_packet_offset)
local expected_clock_offset = math.floor(clock_epoch - (clock_vana_time % 0x100000000) / 60)
assert_true(brd.on_server_clock(clock_timestamp, clock_packet_offset, clock_epoch) == true, '0x037 server clock update must be accepted')
assert_equal(brd._test.state.server_time_offset, expected_clock_offset, '0x037 server clock offset conversion mismatch')
assert_equal(brd._test.state.server_time_source, 'packet_037', 'server clock source must identify authoritative packet calibration')
local calibrated_endtime = (clock_epoch - expected_clock_offset) * 60 + 6000
assert_equal(brd._test.remaining_seconds(calibrated_endtime, clock_epoch), 100, 'remaining duration must use the calibrated packet clock')
local bad = {
	enabled = true,
	songs = { 'Magic Finale' },
	dummy_songs = {},
	use_nitro = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
}
assert_true(brd._test.validate_config(bad, player) == false, 'enemy-targeted Bard song must be rejected')

local bootstrap_action = brd.propose(config, { now = 0.5, player = player, action_ready = ready })
assert_equal(bootstrap_action.action_name, 'Honor March', 'missing cached snapshot must start an ownership rebuild instead of deadlocking')
assert_equal(brd._test.state.snapshot_source, 'startup_rebuild', 'BRD bootstrap snapshot source mismatch')
assert_equal(brd._test.state.last_transition, 'snapshot_bootstrap_rebuild', 'BRD bootstrap transition mismatch')
brd.reset('bootstrap_test_complete')

brd.on_status_snapshot({}, 1)
local action = brd.propose(config, { now = 1, player = player, action_ready = ready })
assert_equal(action.action_name, 'Honor March', 'first base song proposal mismatch')
assert_equal(action.action_type, 'spell', 'song proposal action type mismatch')
brd.note_dispatch(action, '11', 1)
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 1,
	targets = {
		{ id = 77, actions = { { message = 205, param = 100 } } },
		{ id = 88, actions = { { message = 205, param = 100 } } },
	},
}, 77, 1.1)
local future_one = brd._test.server_now_raw(os.time()) + 36000
local future_two = future_one + 600
brd.on_status_snapshot({ [100] = { count = 1, endtimes = { future_one } } }, 1.2)
assert_true(brd._test.state.owners['Honor March'] ~= nil, 'confirmed song must receive exact runtime ownership')
assert_equal(#brd._test.state.owners['Honor March'].recipients, 2, 'area-song recipients must come from successful 0x028 targets')

action = brd.propose(config, { now = 2, player = player, action_ready = ready })
assert_equal(action.action_name, 'Victory March', 'second base song proposal mismatch')
brd.note_dispatch(action, '12', 2)
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 2,
	targets = { { id = 77, actions = { { message = 230, param = 100 } } } },
}, 77, 2.1)
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { future_one, future_two } } }, 2.2)
assert_true(brd._test.state.owners['Victory March'] ~= nil, 'same-family exact song must receive its own timer owner')

brd.reset('live_timer_jitter_test')
local jitter_honor = 3523079878
brd.on_status_snapshot({ [100] = { count = 1, endtimes = { jitter_honor } } }, 3)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = jitter_honor, recipients = { 77 } }
action = brd.propose(config, { now = 3.1, player = player, action_ready = ready })
assert_equal(action.action_name, 'Victory March', 'timer jitter setup must propose the missing same-family song')
brd.note_dispatch(action, 'jitter-victory', 3.1)
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 2,
	targets = { { id = 77, actions = { { message = 230, param = 100 } } } },
}, 77, 3.2)
local jitter_victory = 3523078810
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { jitter_victory, jitter_honor + 3 } } }, 3.3)
assert_true(brd._test.state.owners['Honor March'] ~= nil, 'ordinary packet timer jitter must not prune an existing song owner')
assert_equal(brd._test.state.owners['Honor March'].endtime, jitter_honor + 3, 'preserved owner must track the newest packet timer observation')
assert_true(brd._test.state.owners['Victory March'] ~= nil, 'one real timer addition plus jitter must confirm the incoming song')
action = brd.propose(config, { now = 3.4, player = player, action_ready = ready })
assert_true(action == nil, 'both same-family songs must remain satisfied after jitter-aware confirmation')

brd.note_dispatch({ action_type = 'spell', action_name = 'Victory March', detail = { required_recipient_ids = { 77 } } }, 'jitter-refresh', 3.5)
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 2,
	targets = { { id = 77, actions = { { message = 230, param = 100 } } } },
}, 77, 3.6)
local refreshed_victory = jitter_victory + 981
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { refreshed_victory, jitter_honor } } }, 3.7)
assert_true(brd._test.state.owners['Honor March'] ~= nil, 'refreshing one same-family song must preserve the other owner through timer jitter')
assert_true(brd._test.state.owners['Victory March'] ~= nil, 'refreshing a same-family song must retain its exact owner')
assert_equal(brd._test.state.owners['Victory March'].endtime, refreshed_victory, 'refresh must assign the unmatched new timer to the cast song')

brd.reset('confirmation_phase_timeout_test')
brd.on_status_snapshot({}, 100)
action = brd.propose(config, { now = 100, player = player, action_ready = ready })
brd.note_dispatch(action, 'phase-timeout', 100)
brd.on_action({
	actor_id = 77,
	category = 8,
	param = 24931,
	targets = { { id = 77, actions = { { message = 327, param = 1 } } } },
}, 77, 100.3)
assert_equal(brd._test.state.pending.started_at, 100.3, 'category-8 song packet must begin the cast timeout phase')
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 1,
	targets = { { id = 77, actions = { { message = 230, param = 100 } } } },
}, 77, 103.3)
action = brd.propose(config, { now = 104.2, player = player, action_ready = ready })
assert_true(action == nil, 'successful song must receive a full confirmation window after cast completion')
assert_true(brd._test.state.pending ~= nil, 'dispatch-age timeout must not discard a successfully completed song')
brd.on_status_snapshot({ [100] = { count = 1, endtimes = { 3523200000 } } }, 104.3)
assert_true(brd._test.state.owners['Honor March'] ~= nil, 'snapshot inside the post-success window must confirm ownership')

brd.reset('cast_phase_timeout_test')
brd.on_status_snapshot({}, 110)
action = brd.propose(config, { now = 110, player = player, action_ready = ready })
brd.note_dispatch(action, 'cast-timeout', 110)
brd.on_action({
	actor_id = 77,
	category = 8,
	param = 24931,
	targets = { { id = 77, actions = { { message = 327, param = 1 } } } },
}, 77, 110.2)
assert_true(brd.reject_pending_before_start(17, 110.3) == false, 'unable-cast rejection must not cancel a song after cast start')
action = brd.propose(config, { now = 114.3, player = player, action_ready = ready })
assert_true(action == nil and brd._test.state.pending ~= nil, 'observed song cast must not use the shorter command-start timeout')
brd.cancel_pending('cast_phase_timeout_test_complete')

brd.reset('unable_cast_prestart_test')
brd.on_status_snapshot({}, 120)
action = brd.propose(config, { now = 120, player = player, action_ready = ready })
brd.note_dispatch(action, 'unable-cast', 120)
assert_equal(brd._test.state.pending.phase, 'awaiting_start', 'new BRD dispatch must await explicit cast-start evidence')
assert_true(brd.reject_pending_before_start(17, 120.4) == true, 'message 17 must immediately reject pre-start BRD pending work')
assert_true(brd._test.state.pending == nil, 'unable-cast rejection must clear provider pending state')
assert_true(brd._test.state.owners['Honor March'] == nil, 'unable-cast rejection must not create song ownership')

brd.reset('silent_start_timeout_test')
brd.on_status_snapshot({}, 130)
action = brd.propose(config, { now = 130, player = player, action_ready = ready })
brd.note_dispatch(action, 'silent-start-timeout', 130)
brd.propose(config, { now = 132.1, player = player, action_ready = ready })
local scheduler_failure = brd.take_scheduler_failure()
assert_true(type(scheduler_failure) == 'table', 'silent BRD start timeout must publish a scheduler failure')
assert_equal(scheduler_failure.reason, 'start_timeout', 'silent BRD start timeout failure reason mismatch')
assert_equal(scheduler_failure.retry_delay, 0.75, 'silent BRD start timeout retry delay mismatch')
assert_true(brd.take_scheduler_failure() == nil, 'scheduler failure must be consumed exactly once')

brd.reset('capacity_test')
local capacity_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II" },
	use_nitro = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
}
assert_true(brd._test.validate_config(capacity_config, player) == true, 'valid four-song capacity config rejected')
local cap_one = brd._test.server_now_raw(os.time()) + 40000
local cap_two = cap_one + 600
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { cap_one, cap_two } } }, 5)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cap_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cap_two, recipients = { 77 } }
action = brd.propose(capacity_config, { now = 5, player = player, action_ready = ready })
assert_equal(action.action_name, "Army's Paeon", 'capacity build must use the first configured dummy song')
assert_equal(action.reason_code, 'brd_build_capacity_dummy', 'capacity build proposal reason mismatch')

brd.reset('five_without_clarion_test')
local five_without_clarion = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', 'Mage\'s Ballad III' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II" },
	use_nitro = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
}
assert_true(brd._test.validate_config(five_without_clarion, player) == true, 'fifth configured song must not require Clarion when only the first four are effective')
local effective_without_clarion = brd._test.effective_config(five_without_clarion, player)
assert_equal(#effective_without_clarion.songs, 4, 'Clarion-disabled effective song list must contain the first four songs')
assert_equal(effective_without_clarion.songs[4], 'Valor Minuet IV', 'Clarion-disabled effective song order mismatch')
local five_with_clarion = brd._test.effective_config({
	enabled = true,
	songs = five_without_clarion.songs,
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
	use_nitro = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
}, player)
assert_equal(#five_with_clarion.songs, 5, 'Clarion-enabled effective song list must retain the fifth song')

brd.reset('nitro_test')
local nitro_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March' },
	dummy_songs = {},
	use_nitro = true,
	use_clarion_call = false,
	use_marcato = true,
	marcato_song = 'Honor March',
}
local nitro_one = brd._test.server_now_raw(os.time()) + 42000
local nitro_two = nitro_one + 600
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { nitro_one, nitro_two } } }, 10)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = nitro_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = nitro_two, recipients = { 77 } }
action = brd.propose(nitro_config, { now = 10, player = player, action_ready = ready })
assert_equal(action.action_name, 'Nightingale', 'NITRO must start with Nightingale only when both abilities are ready')
player.buffs = { 347 }
action = brd.propose(nitro_config, { now = 11, player = player, action_ready = ready })
assert_equal(action.action_name, 'Troubadour', 'NITRO must pair Troubadour after Nightingale is active')
player.buffs = { 347, 348 }
action = brd.propose(nitro_config, { now = 12, player = player, action_ready = ready })
assert_equal(action.action_name, 'Marcato', 'Marcato must be reserved immediately before its configured NITRO song')

brd.reset('failure_message_test')
player.buffs = {}
brd.on_status_snapshot({}, 20)
action = brd.propose(config, { now = 20, player = player, action_ready = ready })
brd.note_dispatch(action, '20', 20)
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 1,
	targets = { { id = 77, actions = { { message = 17, param = 0 } } } },
}, 77, 20.1)
brd.on_status_snapshot({ [100] = { count = 1, endtimes = { 500200 } } }, 20.2)
assert_true(brd._test.state.owners['Honor March'] == nil, 'message 17 must never confirm Bard song ownership')

brd.reset('manual_capture_test')
brd.arm_manual_capture_once()
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 1,
	targets = { { id = 77, actions = { { message = 230, param = 100 } } } },
}, 77, 30)
brd.on_status_snapshot({ [100] = { count = 1, endtimes = { 500300 } } }, 30.1)
local capture_text = table.concat(brd._test.state.trace_lines, '\n')
assert_true(capture_text:find('capture 028 song=Honor March', 1, true) ~= nil, 'manual capture must record raw 0x028 song evidence')
assert_true(capture_text:find('results=[77:230:100]', 1, true) ~= nil, 'manual capture must record target message and parameter evidence')
assert_true(capture_text:find('capture 063 song=Honor March status=100 count=1 endtimes=[500300]', 1, true) ~= nil, 'manual capture must record the next status-family snapshot')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(scheduler_source:find("provider = 'maintenance_brd'", 1, true) ~= nil, 'scheduler must emit the dedicated BRD provider')
assert_true(scheduler_source:find('scheduler.p1_dispatch_maintenance_brd', 1, true) ~= nil, 'scheduler must own dedicated BRD dispatch')
assert_true(scheduler_source:find('is_spell_prestart_rejection_message_id', 1, true) ~= nil, 'scheduler must classify unable-cast action messages')
assert_true(scheduler_source:find("return mid == 17 or mid == 18", 1, true) ~= nil, 'scheduler must recognize both unable-cast message ids')
assert_true(scheduler_source:find("[8] = true", 1, true) ~= nil, 'scheduler action state must recognize category-8 song start packets')
assert_true(scheduler_source:find('p1_pending_mark_failed', 1, true) ~= nil, 'unable-cast handling must fail scheduler pending work')
assert_true(scheduler_source:find('maintenance_next_at.brd_songs', 1, true) ~= nil, 'unable-cast handling must use the scheduler BRD retry gate')
assert_true(scheduler_source:find('take_scheduler_failure', 1, true) ~= nil, 'scheduler must consume silent BRD lifecycle failures')
assert_true(scheduler_source:find("'maintenance_songs'", 1, true) == nil, 'old non-dispatchable Bard placeholder must be removed')

local addon_file = assert(io.open('UnifiedCombat.lua', 'r'))
local addon_source = addon_file:read('*a')
addon_file:close()
assert_true(addon_source:find("a == 'brd'", 1, true) ~= nil, 'addon must expose focused BRD diagnostics')
assert_true(addon_source:find("arm_trace_once", 1, true) ~= nil, 'addon must expose one-shot BRD packet tracing')
assert_true(addon_source:find("arm_manual_capture_once", 1, true) ~= nil, 'addon must expose passive manual-cast capture')

brd.stop_diagnostic_log()
local log_file = assert(io.open(log_path, 'r'))
local log_text = log_file:read('*a')
log_file:close()
assert_true(log_text:find('\tPROPOSAL\t', 1, true) ~= nil, 'BRD diagnostic log must record proposals')
assert_true(log_text:find('\tDISPATCH\t', 1, true) ~= nil, 'BRD diagnostic log must record dispatch baselines')
assert_true(log_text:find('\tACTION_028\t', 1, true) ~= nil, 'BRD diagnostic log must record raw action results')
assert_true(log_text:find('\tACTION_START\t', 1, true) ~= nil, 'BRD diagnostic log must record cast-start transitions')
assert_true(log_text:find('\tSERVER_REJECT\t', 1, true) ~= nil, 'BRD diagnostic log must record unable-cast rejection')
assert_true(log_text:find('\tSNAPSHOT_063\t', 1, true) ~= nil, 'BRD diagnostic log must record parsed status snapshots')
assert_true(log_text:find('\tTIMER_DELTA\t', 1, true) ~= nil, 'BRD diagnostic log must record timer deltas')
assert_true(log_text:find('\tOWNER_CONFIRM\t', 1, true) ~= nil, 'BRD diagnostic log must record owner confirmation')
os.remove(log_path)

package.loaded.uc_brd_maintenance = old_module
package.loaded.resources = old_resources
windower = old_windower

io.stdout:write('selftest_brd_maintenance: OK\n')
