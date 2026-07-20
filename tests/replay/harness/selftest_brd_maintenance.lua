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
		[9] = { id = 9, en = 'Goblin Gavotte', status = 105, type = 'BardSong', targets = { Self = true } },
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
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
}
local log_ok, log_path = brd.start_diagnostic_log()
assert_true(log_ok == true, 'BRD diagnostic log must start in the replay harness')

local ok, reason = brd._test.validate_config(config, player)
assert_true(ok, 'valid dedicated BRD config rejected: ' .. tostring(reason))
config.recovery_range_yalms = 20.1
local range_ok, range_reason = brd._test.validate_config(config, player)
assert_true(range_ok == false, 'out-of-range BRD recovery distance must be rejected')
assert_equal(range_reason, 'invalid_recovery_range_yalms', 'invalid BRD recovery distance blocker mismatch')
config.recovery_range_yalms = 9.9
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
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
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
local action = brd.propose(config, {
	now = 1,
	player = player,
	party = {
		p0 = { id = 77 },
		p1 = { id = 99 },
	},
	action_ready = ready,
})
assert_equal(action.action_name, 'Honor March', 'first base song proposal mismatch')
assert_equal(action.action_type, 'spell', 'song proposal action type mismatch')
assert_equal(#action.detail.required_recipient_ids, 1, 'general-song ownership must not require absent party roster members')
assert_equal(action.detail.required_recipient_ids[1], 77, 'general-song ownership must require the local Bard timer')
local lane_reserved, lane_reason = brd.action_lane_status()
assert_true(lane_reserved == true, 'missing-song sequence must reserve the scheduler action lane')
assert_equal(lane_reason, 'brd_build_base_song', 'missing-song lane reason mismatch')
brd.note_dispatch(action, '11', 1)
action = brd.propose(config, { now = 1.05, player = player, action_ready = ready })
assert_true(action == nil, 'pending song confirmation must not emit another action')
assert_true(brd.action_lane_status() == true, 'pending song confirmation must retain the scheduler action lane')
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

action = brd.propose(config, {
	now = 2,
	player = player,
	party = {
		p0 = { id = 77 },
		p1 = { id = 99 },
	},
	action_ready = ready,
})
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
assert_true(brd.action_lane_status() == false, 'satisfied song maintenance must release the scheduler action lane')

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
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
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

local party_song_state = require('uc_brd_party_song_state')
local range_distance = {
	sqrt = function() return 9.9 end,
}
local range_member = { id = 88, name = 'RangeTest' }
local range_mob_lookup = function(id)
	assert_equal(id, 88, 'BRD recovery range lookup id mismatch')
	return { distance = range_distance }
end
assert_true(party_song_state.in_recovery_range(range_member, 9.9, range_mob_lookup), 'recipient at configured BRD recovery boundary must be eligible')
assert_true(not party_song_state.in_recovery_range(range_member, 9.8, range_mob_lookup), 'recipient outside configured BRD recovery range must be ineligible')
assert_true(not party_song_state.in_recovery_range(range_member, 20.1, range_mob_lookup), 'invalid BRD recovery range must not admit recipients')
local recovery_sequence_config = {
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', 'Mage\'s Ballad III' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
}
local function observe_recovery_member(count, now, extra)
	local buffs = {}
	for i = 1, count do buffs[i] = 100 end
	local member = {
		id = 88,
		name = 'ReturningPlayer',
		is_npc = false,
		spawn_type = 1,
		hpp = 100,
		in_song_range = true,
		buffs = buffs,
	}
	for key, value in pairs(extra or {}) do member[key] = value end
	party_song_state.observe({ member }, {}, { [100] = true }, now)
end

local function seed_recovery_song(song_name, endtime, count)
	party_song_state.record_delivery({
		song_name = song_name,
		status_id = 100,
		endtime = endtime,
		recipients = { 88 },
		confirmed_at = 1,
		is_dummy = false,
		cast_capacity = 2,
		song_limit = count,
	})
end

party_song_state.reset()
observe_recovery_member(3, 1)
seed_recovery_song('Honor March', 10000, 3)
seed_recovery_song('Victory March', 11000, 3)
seed_recovery_song('Valor Minuet V', 12000, 3)
local recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
assert_equal(recovery_step.action_name, "Army's Paeon", 'three-to-four recovery must add exactly one capacity dummy')
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 101,
	endtime = 5000,
	recipients = { 88 },
	confirmed_at = 1.1,
	is_dummy = true,
	cast_capacity = recovery_step.cast_capacity,
	song_limit = 4,
	recovery_member_id = 88,
})
assert_true(party_song_state.next_action(recovery_sequence_config, 4, false, false) == nil, 'recovery must wait for observed recipient count growth')
observe_recovery_member(4, 1.2)
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
assert_equal(recovery_step.action_name, 'Valor Minuet IV', 'confirmed fourth slot must replace the uniquely shortest dummy with only the missing final')
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 103,
	endtime = 13000,
	recipients = { 88 },
	confirmed_at = 1.3,
	is_dummy = false,
	cast_capacity = 2,
	song_limit = 4,
	recovery_member_id = 88,
})
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
assert_true(recovery_step == nil, 'confirmed four-song recovery must stop when the exact four-song set is restored')

-- A later real loss must invalidate the completed state and start recovery again.
observe_recovery_member(3, 2)
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
assert_equal(recovery_step.action_name, "Army's Paeon", 'a later observed count loss must not be hidden by prior recovery completion')

-- A successful action result without count growth must fail explicitly.
party_song_state.reset()
observe_recovery_member(3, 10)
seed_recovery_song('Honor March', 10000, 3)
seed_recovery_song('Victory March', 11000, 3)
seed_recovery_song('Valor Minuet V', 12000, 3)
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 101,
	endtime = 5000,
	recipients = { 88 },
	confirmed_at = 10.1,
	is_dummy = true,
	cast_capacity = 4,
	song_limit = 4,
	recovery_member_id = 88,
})
observe_recovery_member(3, 12.2)
assert_true(party_song_state.next_action(recovery_sequence_config, 4, false, false) == nil, 'a dummy with no observed count increase must not advance recovery')
assert_true(party_song_state.last_blocker():find('capacity_transition_failed', 1, true) ~= nil, 'failed capacity verification must expose an explicit blocker')

-- A recipient whose original songs expired after all dummy names were used
-- must grow with a desired song instead of stalling on dummy-name exhaustion.
party_song_state.reset()
observe_recovery_member(3, 15)
for index, dummy_name in ipairs(recovery_sequence_config.dummy_songs) do
	party_song_state.record_delivery({
		song_name = dummy_name,
		status_id = index < 3 and 101 or 105,
		endtime = 5000 + index * 1000,
		recipients = { 88 },
		confirmed_at = 15,
		is_dummy = true,
		cast_capacity = 2,
		song_limit = 4,
	})
end
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
assert_equal(recovery_step.action_name, 'Honor March', 'three-dummy recipient recovery must grow the fourth slot with a final song')
assert_equal(recovery_step.reason_code, 'brd_recovery_capacity_final', 'recipient desired-song capacity growth reason mismatch')
assert_equal(recovery_step.cast_capacity, 4, 'recipient desired-song growth must advertise four-slot capacity')

-- Ignore, dead, trust, and out-of-range members never start recovery.
party_song_state.reset()
party_song_state.observe({
	{ id = 88, name = 'ReturningPlayer', spawn_type = 1, is_npc = false, hpp = 100, in_song_range = true, buffs = {} },
	{ id = 89, name = 'DeadPlayer', spawn_type = 1, is_npc = false, hpp = 0, in_song_range = true, buffs = {} },
	{ id = 90, name = 'Trust', spawn_type = 14, is_npc = false, hpp = 100, in_song_range = true, buffs = {} },
	{ id = 91, name = 'RemotePlayer', spawn_type = 1, is_npc = false, hpp = 100, in_song_range = false, buffs = {} },
}, { 'ReturningPlayer' }, { [100] = true }, 20)
assert_true(party_song_state.next_action(recovery_sequence_config, 4, false, false) == nil, 'ignored, dead, trust, and out-of-range members must not trigger recovery')

-- Four-to-five recovery waits for Clarion and adds only the one missing slot.
party_song_state.reset()
observe_recovery_member(4, 30)
seed_recovery_song('Honor March', 10000, 4)
seed_recovery_song('Victory March', 11000, 4)
seed_recovery_song('Valor Minuet V', 12000, 4)
seed_recovery_song('Valor Minuet IV', 13000, 4)
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, true)
assert_equal(recovery_step.action_name, 'Clarion Call', 'four-to-five party recovery must wait for Clarion before adding the fifth slot')
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, true, false)
assert_equal(recovery_step.action_name, "Army's Paeon", 'four-to-five party recovery must add only one distinct dummy')
assert_equal(recovery_step.cast_capacity, 5, 'fifth-slot recovery dummy must require five-song cast capacity')

-- Clarion cooldown must not leave a four-slot recipient wearing dummies.
party_song_state.reset()
observe_recovery_member(4, 35)
party_song_state.record_delivery({
	song_name = 'Honor March', status_id = 100, endtime = 10000,
	recipients = { 88 }, confirmed_at = 35, is_dummy = false, cast_capacity = 2, song_limit = 5,
})
for index, dummy_name in ipairs(recovery_sequence_config.dummy_songs) do
	party_song_state.record_delivery({
		song_name = dummy_name,
		status_id = index < 3 and 101 or 105,
		endtime = 4000 + index * 1000,
		recipients = { 88 },
		confirmed_at = 35,
		is_dummy = true,
		cast_capacity = 2,
		song_limit = 5,
	})
end
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, false)
assert_equal(recovery_step.action_name, 'Victory March', 'Clarion cooldown must still replace uniquely shortest dummies in the first four slots')
assert_equal(recovery_step.reason_code, 'brd_recovery_degraded_final', 'degraded recipient final replacement reason mismatch')

party_song_state.reset()
observe_recovery_member(4, 36)
for _, delivery in ipairs({
	{ name = 'Victory March', endtime = 4000, dummy = false },
	{ name = "Army's Paeon", endtime = 4300, dummy = true },
	{ name = 'Valor Minuet V', endtime = 5000, dummy = false },
	{ name = 'Honor March', endtime = 6000, dummy = false },
}) do
	party_song_state.record_delivery({
		song_name = delivery.name,
		status_id = delivery.dummy and 101 or 100,
		endtime = delivery.endtime,
		recipients = { 88 },
		confirmed_at = 36,
		is_dummy = delivery.dummy,
		cast_capacity = 2,
		song_limit = 5,
	})
end
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, false)
assert_equal(recovery_step.action_name, 'Victory March', 'recipient recovery must exact-refresh a shorter desired song before replacing the remaining dummy')
assert_equal(recovery_step.reason_code, 'brd_recovery_align_shortest', 'recipient alignment refresh reason mismatch')

-- An AoE recovery dummy must update every successful recipient, including the
-- collateral overwrite on already-full members.
party_song_state.reset()
local function recovery_member(id, name, count)
	local buffs = {}
	for i = 1, count do buffs[i] = 100 end
	return { id = id, name = name, spawn_type = 1, is_npc = false, hpp = 100, in_song_range = true, buffs = buffs }
end
party_song_state.observe({
	recovery_member(88, 'ReturningPlayer', 3),
	recovery_member(99, 'FullPlayer', 4),
}, {}, { [100] = true }, 40)
for index, song_name in ipairs({ 'Honor March', 'Victory March', 'Valor Minuet V' }) do
	party_song_state.record_delivery({
		song_name = song_name,
		status_id = 100,
		endtime = 9000 + index * 1000,
		recipients = { 88, 99 },
		confirmed_at = 40,
		is_dummy = false,
		cast_capacity = 2,
		song_limit = 4,
	})
end
party_song_state.record_delivery({
	song_name = 'Valor Minuet IV',
	status_id = 103,
	endtime = 13000,
	recipients = { 99 },
	confirmed_at = 40,
	is_dummy = false,
	cast_capacity = 2,
	song_limit = 4,
})
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 101,
	endtime = 5000,
	recipients = { 88, 99 },
	confirmed_at = 40.1,
	is_dummy = true,
	cast_capacity = 4,
	song_limit = 4,
	recovery_member_id = 88,
})
party_song_state.observe({
	recovery_member(88, 'ReturningPlayer', 4),
	recovery_member(99, 'FullPlayer', 4),
}, {}, { [100] = true }, 40.2)
recovery_step = party_song_state.next_action(recovery_sequence_config, 4, false, false)
assert_equal(recovery_step.action_name, 'Honor March', 'AoE recovery must repair the exact song displaced on an already-full recipient')

brd.reset('five_without_clarion_test')
local five_without_clarion = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', 'Mage\'s Ballad III' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II" },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
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
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
}, player)
assert_equal(#five_with_clarion.songs, 5, 'Clarion-enabled effective song list must retain the fifth song')

brd.reset('five_clarion_cooldown_capacity_test')
local clarion_cooldown_config = {
	enabled = true,
	songs = five_without_clarion.songs,
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
}
local clarion_cooldown_ready = function(name)
	if name == 'Clarion Call' then return false, 'recast', 'ja' end
	return true, '', 'spell'
end
local cooldown_one = brd._test.server_now_raw(os.time()) + 40000
local cooldown_two = cooldown_one + 600
local cooldown_three = cooldown_two + 600
local cooldown_four = cooldown_three + 600
local cooldown_five = brd._test.server_now_raw(os.time()) + 300
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { cooldown_one, cooldown_two } },
	[103] = { count = 2, endtimes = { cooldown_three, cooldown_four } },
	[104] = { count = 1, endtimes = { cooldown_five } },
}, 15)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cooldown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cooldown_two, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = cooldown_three, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = cooldown_four, recipients = { 77 } }
brd._test.state.owners['Mage\'s Ballad III'] = { status_id = 104, endtime = cooldown_five, recipients = { 77 } }
action = brd.propose(clarion_cooldown_config, { now = 15, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Mage\'s Ballad III', 'persisted fifth song must remain an expiration-maintenance target while Clarion is on cooldown')
assert_equal(action.reason_code, 'brd_song_expiring', 'persisted fifth song must use ordinary exact-refresh maintenance')

brd.reset('five_clarion_three_dummies_test')
local dummy_short = brd._test.server_now_raw(os.time()) + 12000
local dummy_middle = dummy_short + 600
local dummy_long = dummy_middle + 600
brd.on_status_snapshot({
	[101] = { count = 2, endtimes = { dummy_short, dummy_middle } },
	[105] = { count = 1, endtimes = { dummy_long } },
}, 15.1)
brd._test.state.owners["Army's Paeon"] = { status_id = 101, endtime = dummy_short, recipients = { 77 }, is_dummy = true }
brd._test.state.owners["Army's Paeon II"] = { status_id = 101, endtime = dummy_middle, recipients = { 77 }, is_dummy = true }
brd._test.state.owners['Goblin Gavotte'] = { status_id = 105, endtime = dummy_long, recipients = { 77 }, is_dummy = true }
action = brd.propose(clarion_cooldown_config, { now = 15.1, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Honor March', 'three tracked dummies must use a desired song to grow safely to the fourth slot')
assert_equal(action.reason_code, 'brd_build_capacity_final', 'desired-song capacity growth reason mismatch')
assert_equal(action.detail.cast_capacity, 4, 'pre-Clarion desired-song capacity growth must stop at four slots')

brd.reset('five_clarion_four_slots_with_dummies_test')
local degraded_final = dummy_long + 600
brd.on_status_snapshot({
	[100] = { count = 1, endtimes = { degraded_final } },
	[101] = { count = 2, endtimes = { dummy_short, dummy_middle } },
	[105] = { count = 1, endtimes = { dummy_long } },
}, 15.2)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = degraded_final, recipients = { 77 }, is_dummy = false }
brd._test.state.owners["Army's Paeon"] = { status_id = 101, endtime = dummy_short, recipients = { 77 }, is_dummy = true }
brd._test.state.owners["Army's Paeon II"] = { status_id = 101, endtime = dummy_middle, recipients = { 77 }, is_dummy = true }
brd._test.state.owners['Goblin Gavotte'] = { status_id = 105, endtime = dummy_long, recipients = { 77 }, is_dummy = true }
action = brd.propose(clarion_cooldown_config, { now = 15.2, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Victory March', 'degraded four-slot setup must replace a uniquely shortest dummy with the next final song')
assert_equal(action.reason_code, 'brd_degraded_replace_dummy', 'degraded dummy replacement reason mismatch')

brd.reset('five_clarion_degraded_alignment_test')
local alignment_victory = dummy_short
local alignment_dummy = alignment_victory + 300
local alignment_minuet = alignment_dummy + 600
local alignment_honor = alignment_minuet + 600
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { alignment_victory, alignment_honor } },
	[101] = { count = 1, endtimes = { alignment_dummy } },
	[103] = { count = 1, endtimes = { alignment_minuet } },
}, 15.21)
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = alignment_victory, recipients = { 77 }, is_dummy = false }
brd._test.state.owners["Army's Paeon"] = { status_id = 101, endtime = alignment_dummy, recipients = { 77 }, is_dummy = true }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = alignment_minuet, recipients = { 77 }, is_dummy = false }
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = alignment_honor, recipients = { 77 }, is_dummy = false }
action = brd.propose(clarion_cooldown_config, { now = 15.21, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Victory March', 'a desired song shorter than the remaining dummy must be exact-refreshed for alignment')
assert_equal(action.reason_code, 'brd_degraded_align_shortest', 'degraded alignment refresh reason mismatch')

brd.reset('five_clarion_degraded_aligned_dummy_test')
local aligned_victory = alignment_honor + 600
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { alignment_honor, aligned_victory } },
	[101] = { count = 1, endtimes = { alignment_dummy } },
	[103] = { count = 1, endtimes = { alignment_minuet } },
}, 15.215)
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = aligned_victory, recipients = { 77 }, is_dummy = false }
brd._test.state.owners["Army's Paeon"] = { status_id = 101, endtime = alignment_dummy, recipients = { 77 }, is_dummy = true }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = alignment_minuet, recipients = { 77 }, is_dummy = false }
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = alignment_honor, recipients = { 77 }, is_dummy = false }
action = brd.propose(clarion_cooldown_config, { now = 15.215, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Valor Minuet IV', 'after alignment the missing final must replace the uniquely shortest dummy')
assert_equal(action.reason_code, 'brd_degraded_replace_dummy', 'post-alignment dummy replacement reason mismatch')

brd.reset('five_clarion_reload_partial_ownership_test')
local unknown_long = degraded_final + 1200
brd.on_status_snapshot({
	[101] = { count = 2, endtimes = { dummy_short, dummy_middle } },
	[103] = { count = 1, endtimes = { degraded_final } },
	[104] = { count = 1, endtimes = { unknown_long } },
}, 15.22)
brd._test.state.owners["Army's Paeon"] = { status_id = 101, endtime = dummy_short, recipients = { 77 }, is_dummy = true }
brd._test.state.owners["Army's Paeon II"] = { status_id = 101, endtime = dummy_middle, recipients = { 77 }, is_dummy = true }
action = brd.propose(clarion_cooldown_config, { now = 15.22, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Honor March', 'reload recovery may replace a uniquely shortest known dummy even when longer slots have unknown identity')
assert_equal(action.reason_code, 'brd_degraded_replace_dummy', 'partial-ownership reload replacement reason mismatch')

brd.reset('five_clarion_reload_unknown_shortest_test')
local unknown_short = dummy_short - 600
brd.on_status_snapshot({
	[101] = { count = 2, endtimes = { dummy_short, dummy_middle } },
	[103] = { count = 1, endtimes = { unknown_short } },
	[104] = { count = 1, endtimes = { unknown_long } },
}, 15.23)
brd._test.state.owners["Army's Paeon"] = { status_id = 101, endtime = dummy_short, recipients = { 77 }, is_dummy = true }
brd._test.state.owners["Army's Paeon II"] = { status_id = 101, endtime = dummy_middle, recipients = { 77 }, is_dummy = true }
action = brd.propose(clarion_cooldown_config, { now = 15.23, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Honor March', 'reload recovery must rebuild desired identity when the uniquely shortest slot is unknown')
assert_equal(action.reason_code, 'brd_degraded_rebuild_unknown', 'unknown-slot rebuild reason mismatch')

brd.reset('five_clarion_degraded_test')
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { cooldown_one, cooldown_two } },
	[103] = { count = 2, endtimes = { cooldown_three, cooldown_four } },
}, 15.25)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cooldown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cooldown_two, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = cooldown_three, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = cooldown_four, recipients = { 77 } }
action = brd.propose(clarion_cooldown_config, { now = 15.25, player = player, action_ready = clarion_cooldown_ready })
assert_true(action == nil, 'a lost fifth slot must remain degraded instead of rotating four songs while Clarion is unavailable')
assert_true(table.concat(brd.status_lines(), ' | '):find('degraded_fifth_waiting_for_clarion', 1, true) ~= nil, 'degraded fifth-slot state must be diagnostic')

brd.reset('five_clarion_active_capacity_test')
player.buffs = { 499 }
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { cooldown_one, cooldown_two } },
	[103] = { count = 2, endtimes = { cooldown_three, cooldown_four } },
}, 15.5)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cooldown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cooldown_two, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = cooldown_three, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = cooldown_four, recipients = { 77 } }
action = brd.propose(clarion_cooldown_config, { now = 15.5, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, "Army's Paeon", 'four-to-five recovery needs only one capacity dummy while Clarion is active')
assert_equal(action.detail.cast_capacity, 5, 'Clarion capacity dummy must require five-song add capacity')
player.buffs = {}

brd.reset('five_clarion_cooldown_force_test')
local cooldown_force_five = cooldown_four + 600
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { cooldown_one, cooldown_two } },
	[103] = { count = 2, endtimes = { cooldown_three, cooldown_four } },
	[104] = { count = 1, endtimes = { cooldown_force_five } },
}, 16)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cooldown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cooldown_two, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = cooldown_three, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = cooldown_four, recipients = { 77 } }
brd._test.state.owners['Mage\'s Ballad III'] = { status_id = 104, endtime = cooldown_force_five, recipients = { 77 } }
brd._test.state.force = {
	complete = {
		['Honor March'] = true,
		['Victory March'] = true,
		['Valor Minuet V'] = true,
		['Valor Minuet IV'] = true,
	},
	started_at = 16,
}
action = brd.propose(clarion_cooldown_config, { now = 16, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Mage\'s Ballad III', 'NITRO generation must refresh a persisted fifth song while Clarion is on cooldown')
assert_equal(action.reason_code, 'brd_nitro_forced_refresh', 'persisted fifth NITRO refresh reason mismatch')

brd.reset('nitro_test')
local nitro_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March' },
	dummy_songs = {},
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
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
assert_true(scheduler_source:find('scheduler.PRIORITY_BAND_BRD_MAINTENANCE = 120', 1, true) ~= nil, 'scheduler must globally prioritize BRD maintenance')
assert_true(scheduler_source:find('scheduler.p1_brd_lane_blocks_proposal', 1, true) ~= nil, 'scheduler must preserve BRD sequence ownership across proposal gaps')
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
