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
	if name == 'Nightingale' or name == 'Troubadour' or name == 'Marcato' or name == 'Clarion Call'
		or name == 'Soul Voice' or name == 'Pianissimo' then
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
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
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
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
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
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
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

local function recovery_member(id, name, count)
	local buffs = {}
	for i = 1, count do buffs[i] = 100 end
	return { id = id, name = name, spawn_type = 1, is_npc = false, hpp = 100, in_song_range = true, buffs = buffs }
end

-- A fifth-slot dummy sung under Troubadour must be exact-refreshed after
-- Troubadour expires when its doubled duration obstructs final replacement.
party_song_state.reset()
observe_recovery_member(4, 37)
for _, delivery in ipairs({
	{ name = 'Victory March', endtime = 4000, status_id = 100 },
	{ name = "Mage's Ballad III", endtime = 4200, status_id = 104 },
	{ name = 'Valor Minuet V', endtime = 5000, status_id = 103 },
	{ name = 'Honor March', endtime = 6000, status_id = 100 },
}) do
	party_song_state.record_delivery({
		song_name = delivery.name,
		status_id = delivery.status_id,
		endtime = delivery.endtime,
		recipients = { 88 },
		confirmed_at = 37,
		is_dummy = false,
		cast_capacity = 2,
		song_limit = 5,
	})
end
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, true, false, true)
assert_equal(recovery_step.action_name, "Army's Paeon", 'fifth-slot recovery must add its capacity dummy while Troubadour is active')
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 101,
	endtime = 8000,
	recipients = { 88 },
	confirmed_at = 37.1,
	is_dummy = true,
	troubadour_active = true,
	cast_capacity = 5,
	song_limit = 5,
	recovery_member_id = 88,
})
observe_recovery_member(5, 37.2)
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, false, false)
assert_equal(recovery_step.action_name, "Army's Paeon", 'expired Troubadour must normalize the obstructing enhanced dummy first')
assert_equal(recovery_step.reason_code, 'brd_recovery_normalize_dummy', 'enhanced dummy normalization reason mismatch')
assert_true(recovery_step.normalizes_dummy == true, 'enhanced dummy normalization must be explicit action metadata')
assert_true(recovery_step.is_dummy == true, 'enhanced dummy normalization must retain dummy identity')
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 101,
	endtime = 4500,
	recipients = { 88 },
	confirmed_at = 37.3,
	is_dummy = true,
	troubadour_active = false,
	normalizes_dummy = true,
	cast_capacity = 2,
	song_limit = 5,
	recovery_member_id = 88,
})
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, false, false)
assert_equal(recovery_step.action_name, 'Victory March', 'shorter final must align after dummy normalization')
assert_true(recovery_step.aligns_final == true, 'post-normalization final alignment must be explicit action metadata')
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 100,
	endtime = 7000,
	recipients = { 88 },
	confirmed_at = 37.4,
	is_dummy = false,
	aligns_final = true,
	cast_capacity = 2,
	song_limit = 5,
	recovery_member_id = 88,
})
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, false, false)
assert_equal(recovery_step.action_name, "Mage's Ballad III", 'every final shorter than the normalized dummy must align once')
party_song_state.record_delivery({
	song_name = recovery_step.action_name,
	status_id = 104,
	endtime = 7100,
	recipients = { 88 },
	confirmed_at = 37.5,
	is_dummy = false,
	aligns_final = true,
	cast_capacity = 2,
	song_limit = 5,
	recovery_member_id = 88,
})
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, false, false, false)
assert_equal(recovery_step.action_name, 'Valor Minuet IV', 'missing final must replace the uniquely shortest normalized dummy')
assert_true(recovery_step.normalizes_dummy ~= true and recovery_step.aligns_final ~= true,
	'final replacement must not retain normalization or alignment metadata')

party_song_state.reset()
observe_recovery_member(5, 37.6)
party_song_state._test.state.members[88].effects = {
	['Victory March'] = { endtime = 7000, status_id = 100, is_dummy = false, alignment_attempted = true },
	["Army's Paeon"] = { endtime = 8000, status_id = 101, is_dummy = true, normalization_attempted = true },
	['Valor Minuet V'] = { endtime = 9000, status_id = 103, is_dummy = false },
	['Honor March'] = { endtime = 10000, status_id = 100, is_dummy = false },
	["Mage's Ballad III"] = { endtime = 11000, status_id = 104, is_dummy = false },
}
party_song_state._test.state.members[88].unknown_count = 0
party_song_state._test.state.members[88].confidence = 'confirmed'
party_song_state._test.state.recovery = {
	member_id = 88,
	member_name = 'ReturningPlayer',
	song_limit = 5,
	phase = 'capacity',
	awaiting_count = false,
}
assert_true(party_song_state.next_action(recovery_sequence_config, 5, false, false, false) == nil,
	'a normalized dummy that remains obstructive must not trigger repeated final refreshes')
assert_true(party_song_state.last_blocker():find('dummy_duration_normalization_failed', 1, true) ~= nil,
	'failed dummy normalization must expose an explicit terminal blocker')

-- Normalization is allowed only when every eligible AoE recipient already has
-- the exact dummy. Otherwise the same cast could overwrite a protected song.
party_song_state.reset()
party_song_state.observe({
	recovery_member(88, 'ReturningPlayer', 4),
	recovery_member(99, 'FullPlayer', 5),
}, {}, { [100] = true }, 38)
for _, delivery in ipairs({
	{ name = 'Victory March', endtime = 4000 },
	{ name = "Mage's Ballad III", endtime = 4200 },
	{ name = 'Valor Minuet V', endtime = 5000 },
	{ name = 'Honor March', endtime = 6000 },
}) do
	party_song_state.record_delivery({
		song_name = delivery.name, status_id = 100, endtime = delivery.endtime,
		recipients = { 88, 99 }, confirmed_at = 38, is_dummy = false, cast_capacity = 2, song_limit = 5,
	})
end
party_song_state.record_delivery({
	song_name = 'Valor Minuet IV', status_id = 103, endtime = 7000,
	recipients = { 99 }, confirmed_at = 38, is_dummy = false, cast_capacity = 2, song_limit = 5,
})
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, true, false, true)
party_song_state.record_delivery({
	song_name = recovery_step.action_name, status_id = 101, endtime = 8000,
	recipients = { 88 }, confirmed_at = 38.1, is_dummy = true, troubadour_active = true,
	cast_capacity = 5, song_limit = 5, recovery_member_id = 88,
})
party_song_state.observe({
	recovery_member(88, 'ReturningPlayer', 5),
	recovery_member(99, 'FullPlayer', 5),
}, {}, { [100] = true }, 38.2)
assert_true(party_song_state.next_action(recovery_sequence_config, 5, false, false, false) == nil,
	'normalization must block when an eligible AoE recipient lacks the exact dummy')
assert_true(party_song_state.last_blocker():find('normalization_not_exact_refresh:FullPlayer', 1, true) ~= nil,
	'unsafe AoE normalization must identify the recipient lacking the dummy')

-- An AoE recovery dummy must update every successful recipient, including the
-- collateral overwrite on already-full members.
party_song_state.reset()
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

-- The local Bard ownership path must make the same normalization decision and
-- carry its duration context through dispatch and authoritative 0x063 confirmation.
brd.reset('local_enhanced_dummy_normalization_test')
local local_normalization_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', "Mage's Ballad III" },
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
}
local local_base = brd._test.server_now_raw(os.time())
local local_victory = local_base + 14400
local local_ballad = local_base + 15000
local local_minuet = local_base + 18000
local local_honor = local_base + 21000
local local_dummy_long = local_base + 30000
local local_snapshot = {
	[100] = { count = 2, endtimes = { local_victory, local_honor } },
	[101] = { count = 1, endtimes = { local_dummy_long } },
	[103] = { count = 1, endtimes = { local_minuet } },
	[104] = { count = 1, endtimes = { local_ballad } },
}
brd.on_status_snapshot(local_snapshot, 45)
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = local_victory, recipients = { 77 }, is_dummy = false }
brd._test.state.owners["Mage's Ballad III"] = { status_id = 104, endtime = local_ballad, recipients = { 77 }, is_dummy = false }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = local_minuet, recipients = { 77 }, is_dummy = false }
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = local_honor, recipients = { 77 }, is_dummy = false }
brd._test.state.owners["Army's Paeon"] = {
	status_id = 101,
	endtime = local_dummy_long,
	recipients = { 77 },
	is_dummy = true,
	troubadour_active = true,
}
action = brd.propose(local_normalization_config, { now = 45, player = player, action_ready = ready, party_members = {} })
assert_equal(action.action_name, "Army's Paeon", 'local replacement must normalize the enhanced dummy before refreshing finals')
assert_equal(action.reason_code, 'brd_normalize_dummy_duration', 'local dummy normalization reason mismatch')
assert_true(action.detail.normalizes_dummy == true, 'local normalization proposal must carry explicit metadata')
assert_true(action.detail.troubadour_active == false, 'local normalization proposal must record expired Troubadour')
brd.note_dispatch(action, 'normalize-local-dummy', 45)
assert_true(brd._test.state.pending.normalizes_dummy == true, 'normalization metadata must survive dispatch')
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 3,
	targets = { { id = 77, actions = { { message = 205, param = 101 } } } },
}, 77, 45.1)
local local_dummy_normal = local_base + 12000
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { local_victory, local_honor } },
	[101] = { count = 1, endtimes = { local_dummy_normal } },
	[103] = { count = 1, endtimes = { local_minuet } },
	[104] = { count = 1, endtimes = { local_ballad } },
}, 45.2)
assert_true(brd._test.state.owners["Army's Paeon"].normalization_attempted == true,
	'confirmed normalized dummy must be marked as a bounded attempt')
assert_true(brd._test.state.owners["Army's Paeon"].troubadour_active == false,
	'confirmed normalized dummy must replace its enhanced duration context')
action = brd.propose(local_normalization_config, { now = 46, player = player, action_ready = ready, party_members = {} })
assert_equal(action.action_name, 'Valor Minuet IV', 'missing final must replace the confirmed shortest normalized dummy')

brd.reset('party_normalization_self_guard_test')
local self_guard_base = brd._test.server_now_raw(os.time())
party_song_state.observe({ recovery_member(88, 'ReturningPlayer', 4) }, {}, { [100] = true }, 47)
for _, delivery in ipairs({
	{ name = 'Victory March', endtime = self_guard_base + 18000, status_id = 100 },
	{ name = "Mage's Ballad III", endtime = self_guard_base + 18600, status_id = 104 },
	{ name = 'Valor Minuet V', endtime = self_guard_base + 19200, status_id = 103 },
	{ name = 'Honor March', endtime = self_guard_base + 19800, status_id = 100 },
}) do
	party_song_state.record_delivery({
		song_name = delivery.name, status_id = delivery.status_id, endtime = delivery.endtime,
		recipients = { 88 }, confirmed_at = 47, is_dummy = false, cast_capacity = 2, song_limit = 5,
	})
end
recovery_step = party_song_state.next_action(recovery_sequence_config, 5, true, false, true)
party_song_state.record_delivery({
	song_name = recovery_step.action_name, status_id = 101, endtime = self_guard_base + 30000,
	recipients = { 88 }, confirmed_at = 47.1, is_dummy = true, troubadour_active = true,
	cast_capacity = 5, song_limit = 5, recovery_member_id = 88,
})
party_song_state.observe({ recovery_member(88, 'ReturningPlayer', 5) }, {}, { [100] = true }, 47.2)
local self_guard_snapshot = {
	[100] = { count = 2, endtimes = { self_guard_base + 18000, self_guard_base + 18600 } },
	[103] = { count = 2, endtimes = { self_guard_base + 19200, self_guard_base + 19800 } },
	[104] = { count = 1, endtimes = { self_guard_base + 20400 } },
}
brd.on_status_snapshot(self_guard_snapshot, 47.2)
for index, song_name in ipairs(local_normalization_config.songs) do
	local status_id = index <= 2 and 100 or (index <= 4 and 103 or 104)
	local endtime = index <= 2 and self_guard_snapshot[100].endtimes[index]
		or (index <= 4 and self_guard_snapshot[103].endtimes[index - 2] or self_guard_snapshot[104].endtimes[1])
	brd._test.state.owners[song_name] = {
		status_id = status_id,
		endtime = endtime,
		recipients = { 77 },
		is_dummy = false,
	}
end
action = brd.propose(local_normalization_config, {
	now = 47.3,
	player = player,
	action_ready = ready,
	party_members = { recovery_member(88, 'ReturningPlayer', 5) },
})
assert_true(action == nil, 'party dummy normalization must not overwrite a local Bard song: '
	.. tostring(action and action.action_name or 'nil'))
assert_equal(brd._test.state.last_blocker, 'normalization_not_exact_refresh:self',
	'unsafe local normalization must expose an explicit self blocker')

brd.reset('five_without_clarion_test')
local five_without_clarion = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', 'Mage\'s Ballad III' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II" },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
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
	use_soul_voice = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
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
	use_soul_voice = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
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

brd.reset('party_deadline_precedes_pianissimo_extended_self_test')
local party_deadline_now = os.time()
local party_deadline_short = brd._test.server_now_raw(party_deadline_now) + 600
local party_deadline_long = brd._test.server_now_raw(party_deadline_now) + 24000
local party_deadline_later = party_deadline_long + 600
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { party_deadline_long, party_deadline_later } },
}, party_deadline_now)
brd._test.state.owners['Honor March'] = {
	status_id = 100,
	endtime = party_deadline_long,
	recipients = { 77 },
	pianissimo_applied = true,
}
brd._test.state.owners['Victory March'] = {
	status_id = 100,
	endtime = party_deadline_later,
	recipients = { 77 },
}
local party_deadline_member = {
	id = 88,
	name = 'PartyDeadline',
	hpp = 100,
	spawn_type = 1,
	is_npc = false,
	in_song_range = true,
	buffs = { 100, 100 },
}
local party_deadline_state = require('uc_brd_party_song_state')
party_deadline_state.observe({ party_deadline_member }, {}, { [100] = true }, party_deadline_now)
party_deadline_state.record_delivery({
	song_name = 'Honor March',
	status_id = 100,
	endtime = party_deadline_short,
	recipients = { 88 },
	confirmed_at = party_deadline_now,
	cast_capacity = 2,
	song_limit = 2,
})
party_deadline_state.record_delivery({
	song_name = 'Victory March',
	status_id = 100,
	endtime = party_deadline_later,
	recipients = { 88 },
	confirmed_at = party_deadline_now,
	cast_capacity = 2,
	song_limit = 2,
})
action = brd.propose(config, {
	now = party_deadline_now,
	player = player,
	party_members = { party_deadline_member },
	action_ready = ready,
})
assert_equal(action.action_name, 'Honor March', 'earliest remote recipient timer must drive group refresh after a self Pianissimo refresh')
assert_equal(action.reason_code, 'brd_party_song_expiring', 'remote-driven group refresh reason mismatch')

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

brd.reset('five_clarion_reload_tied_unknown_shortest_test')
local tied_unknown_short = unknown_short - 600
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { tied_unknown_short, tied_unknown_short + 1 } },
	[103] = { count = 2, endtimes = { dummy_middle, degraded_final } },
	[104] = { count = 1, endtimes = { unknown_long } },
}, 15.24)
action = brd.propose(clarion_cooldown_config, { now = 15.24, player = player, action_ready = clarion_cooldown_ready })
assert_equal(action.action_name, 'Honor March', 'reload recovery must rebuild desired identity when every tied shortest slot is unknown')
assert_equal(action.reason_code, 'brd_rebuild_unknown', 'tied unknown-slot rebuild reason mismatch')

brd.reset('five_clarion_reload_tied_known_shortest_test')
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { tied_unknown_short, tied_unknown_short + 1 } },
	[103] = { count = 2, endtimes = { dummy_middle, degraded_final } },
	[104] = { count = 1, endtimes = { unknown_long } },
}, 15.245)
brd._test.state.owners['Victory March'] = {
	status_id = 100,
	endtime = tied_unknown_short,
	recipients = { 77 },
	is_dummy = false,
}
action = brd.propose(clarion_cooldown_config, { now = 15.245, player = player, action_ready = clarion_cooldown_ready })
assert_true(action == nil, 'reload recovery must remain blocked when a tied shortest slot has a known owner')
assert_true(table.concat(brd.status_lines(), ' | '):find('ambiguous_overwrite_victim', 1, true) ~= nil,
	'tied known-slot reload blocker must remain diagnostic')

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

brd.reset('five_clarion_degraded_nitro_test')
local degraded_nitro_config = {
	enabled = true,
	songs = five_without_clarion.songs,
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = true,
	use_soul_voice = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {},
}
local degraded_action_ready = function(name)
	if name == 'Clarion Call' then return false, 'recast', 'ja' end
	return ready(name)
end
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { cooldown_one, cooldown_two } },
	[103] = { count = 2, endtimes = { cooldown_three, cooldown_four } },
}, 15.3)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cooldown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cooldown_two, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = cooldown_three, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = cooldown_four, recipients = { 77 } }
action = brd.propose(degraded_nitro_config, { now = 15.3, player = player, action_ready = degraded_action_ready })
assert_equal(action.action_name, 'Nightingale', 'a satisfied degraded four-song set must continue into NITRO planning')

brd.reset('five_clarion_degraded_targeted_test')
local degraded_targeted_config = {
	enabled = true,
	songs = five_without_clarion.songs,
	dummy_songs = { "Army's Paeon", "Army's Paeon II", 'Goblin Gavotte' },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = { 'Target' },
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {
		{ recipients = { 'Target' }, priority_songs = { "Mage's Ballad III" } },
	},
}
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { cooldown_one, cooldown_two } },
	[103] = { count = 2, endtimes = { cooldown_three, cooldown_four } },
}, 15.4)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = cooldown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = cooldown_two, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = cooldown_three, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = cooldown_four, recipients = { 77 } }
local degraded_target = {
	id = 99,
	name = 'Target',
	hpp = 100,
	spawn_type = 13,
	is_npc = false,
	in_song_range = true,
	buffs = { 100, 100, 103, 103 },
}
local degraded_party_state = require('uc_brd_party_song_state')
degraded_party_state.observe({ degraded_target }, { 'Target' }, { [100] = true, [103] = true }, 15.4)
for _, delivery in ipairs({
	{ song_name = 'Honor March', status_id = 100, endtime = cooldown_one },
	{ song_name = 'Victory March', status_id = 100, endtime = cooldown_two },
	{ song_name = 'Valor Minuet V', status_id = 103, endtime = cooldown_three },
	{ song_name = 'Valor Minuet IV', status_id = 103, endtime = cooldown_four },
}) do
	degraded_party_state.record_delivery({
		song_name = delivery.song_name,
		status_id = delivery.status_id,
		endtime = delivery.endtime,
		recipients = { 99 },
		cast_capacity = 4,
	})
end
action = brd.propose(degraded_targeted_config, {
	now = 15.4,
	player = player,
	party_members = { degraded_target },
	action_ready = degraded_action_ready,
})
assert_equal(action.action_name, 'Pianissimo', 'a satisfied degraded four-song set must continue into targeted overlay planning')

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

brd.reset('five_song_targeted_self_alignment_lane_test')
local self_alignment_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV', 'Goblin Gavotte' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II", "Mage's Ballad III" },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = true,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {
		{ recipients = { 'Redrogue' }, priority_songs = { "Mage's Ballad III" } },
	},
}
local alignment_now = os.time()
local alignment_ballad = brd._test.server_now_raw(alignment_now) + 24000
local alignment_honor = alignment_ballad + 1000
local alignment_minuet_four = alignment_honor + 1000
local alignment_dummy = alignment_minuet_four + 4000
local alignment_minuet_five = alignment_dummy + 1000
brd.on_status_snapshot({
	[100] = { count = 1, endtimes = { alignment_honor } },
	[101] = { count = 1, endtimes = { alignment_dummy } },
	[103] = { count = 2, endtimes = { alignment_minuet_four, alignment_minuet_five } },
	[104] = { count = 1, endtimes = { alignment_ballad } },
}, alignment_now)
for _, owner in ipairs({
	{ name = 'Honor March', status_id = 100, endtime = alignment_honor },
	{ name = "Army's Paeon", status_id = 101, endtime = alignment_dummy, is_dummy = true },
	{ name = 'Valor Minuet IV', status_id = 103, endtime = alignment_minuet_four },
	{ name = 'Valor Minuet V', status_id = 103, endtime = alignment_minuet_five },
	{ name = "Mage's Ballad III", status_id = 104, endtime = alignment_ballad },
}) do
	brd._test.state.owners[owner.name] = {
		status_id = owner.status_id,
		endtime = owner.endtime,
		recipients = { 77 },
		is_dummy = owner.is_dummy == true,
	}
end
local self_alignment_member = {
	id = 77,
	name = 'Redrogue',
	hpp = 100,
	spawn_type = 1,
	is_npc = false,
	in_song_range = true,
	buffs = { 100, 101, 103, 103, 104 },
}
local self_alignment_party_state = require('uc_brd_party_song_state')
self_alignment_party_state.observe({ self_alignment_member }, {}, { [100] = true, [101] = true, [103] = true, [104] = true }, alignment_now)
for _, delivery in ipairs({
	{ name = 'Honor March', status_id = 100, endtime = alignment_honor },
	{ name = "Army's Paeon", status_id = 101, endtime = alignment_dummy, is_dummy = true },
	{ name = 'Valor Minuet IV', status_id = 103, endtime = alignment_minuet_four },
	{ name = 'Valor Minuet V', status_id = 103, endtime = alignment_minuet_five },
	{ name = "Mage's Ballad III", status_id = 104, endtime = alignment_ballad },
}) do
	self_alignment_party_state.record_delivery({
		song_name = delivery.name,
		status_id = delivery.status_id,
		endtime = delivery.endtime,
		recipients = { 77 },
		confirmed_at = alignment_now,
		is_dummy = delivery.is_dummy == true,
		cast_capacity = 5,
		song_limit = 5,
	})
end
player.buffs = { 499 }
local self_alignment_wait_ready = function(name)
	if name == 'Pianissimo' then return false, 'recast', 'ja' end
	return ready(name)
end
action = brd.propose(self_alignment_config, {
	now = alignment_now,
	player = player,
	party_members = { self_alignment_member },
	action_ready = self_alignment_wait_ready,
})
assert_true(action == nil, 'fifth-song setup must wait when Pianissimo is temporarily unavailable')
assert_true(type(brd._test.state.targeted_transaction) == 'table', 'Pianissimo wait must preserve the targeted setup transaction')
assert_true(brd.action_lane_status() == true, 'Pianissimo wait must retain the Bard setup lane')
action = brd.propose(self_alignment_config, {
	now = alignment_now + 0.01,
	player = player,
	party_members = { self_alignment_member },
	action_ready = ready,
})
assert_equal(action.action_name, 'Pianissimo', 'targeted self song blocking a fifth-slot dummy must be aligned through Pianissimo')
assert_true(brd._test.state.targeted_transaction.preserve_action_lane == true, 'fifth-song targeted alignment must retain setup-lane ownership')
brd.note_dispatch(action, 'self-alignment-pianissimo', alignment_now)
brd.on_action({
	actor_id = 77,
	category = 6,
	param = 229,
	targets = { { id = 77, actions = {} } },
}, 77, alignment_now + 0.1)
player.buffs = { 499, 409 }
action = brd.propose(self_alignment_config, {
	now = alignment_now + 0.1,
	player = player,
	party_members = { self_alignment_member },
	action_ready = ready,
})
assert_equal(action.action_name, "Mage's Ballad III", 'confirmed setup Pianissimo must refresh the blocking targeted self song')
brd.note_dispatch(action, 'self-alignment-ballad', alignment_now + 0.1)
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 8,
	targets = { { id = 77, actions = { { message = 230, param = 104 } } } },
}, 77, alignment_now + 0.2)
local refreshed_ballad = alignment_minuet_five + 1000
brd.on_status_snapshot({
	[100] = { count = 1, endtimes = { alignment_honor } },
	[101] = { count = 1, endtimes = { alignment_dummy } },
	[103] = { count = 2, endtimes = { alignment_minuet_four, alignment_minuet_five } },
	[104] = { count = 1, endtimes = { refreshed_ballad } },
}, alignment_now + 0.3)
assert_true(brd.action_lane_status() == true, 'targeted setup alignment confirmation must not release the Bard lane')
player.buffs = { 499 }
action = brd.propose(self_alignment_config, {
	now = alignment_now + 0.4,
	player = player,
	party_members = { self_alignment_member },
	action_ready = ready,
})
assert_equal(action.action_name, 'Honor March', 'fifth-song setup must continue immediately with the next alignment action')
assert_equal(action.reason_code, 'brd_align_shortest_final', 'continued fifth-song setup alignment reason mismatch')
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
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = true,
	marcato_song = 'Honor March',
	targeted_songs = {},
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

brd.reset('soul_voice_generation_test')
player.buffs = {}
local soul_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March' },
	dummy_songs = {},
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = true,
	use_soul_voice = true,
	use_clarion_call = false,
	use_marcato = true,
	marcato_song = 'Honor March',
	targeted_songs = {},
}
local soul_one = brd._test.server_now_raw(os.time()) + 42000
local soul_two = soul_one + 600
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { soul_one, soul_two } } }, os.time())
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = soul_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = soul_two, recipients = { 77 } }
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_equal(action.action_name, 'Nightingale', 'Soul Voice generation must begin by activating NITRO')
assert_true(type(brd._test.state.soul_voice_generation) == 'table', 'Soul Voice generation state must arm before NITRO')
brd.note_dispatch(action, 'soul-night', os.time())
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_true(action == nil, 'Nightingale confirmation gap must not admit another Bard action')
assert_true(brd.action_lane_status() == true, 'Nightingale confirmation gap must retain the Bard action lane')
assert_equal(brd._test.state.last_blocker, 'nightingale_confirmation_pending', 'Nightingale confirmation blocker mismatch')
player.buffs = { 347 }
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_equal(action.action_name, 'Troubadour', 'Soul Voice generation must confirm full NITRO before Soul Voice')
brd.note_dispatch(action, 'soul-troub', os.time())
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_true(action == nil, 'Troubadour confirmation gap must not admit another Bard action')
assert_true(brd.action_lane_status() == true, 'Troubadour confirmation gap must retain the Bard action lane')
assert_equal(brd._test.state.last_blocker, 'troubadour_confirmation_pending', 'Troubadour confirmation blocker mismatch')
player.buffs = { 347, 348 }
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { soul_one, soul_two } },
	[347] = { count = 1, endtimes = { soul_two } },
	[348] = { count = 1, endtimes = { soul_two } },
}, os.time())
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_equal(action.action_name, 'Soul Voice', 'Soul Voice must dispatch only after NITRO is active')
player.buffs = { 347, 348, 52 }
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_equal(action.action_name, 'Honor March', 'confirmed Soul Voice must start the forced group refresh')
assert_equal(action.reason_code, 'brd_nitro_forced_refresh', 'Soul Voice group refresh reason mismatch')
assert_true(action.action_name ~= 'Marcato', 'Marcato must be excluded from a Soul Voice generation')

brd.reset('soul_voice_manual_nitro_marcato_exemption_test')
player.buffs = { 347, 348, 231 }
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { soul_one, soul_two } },
	[347] = { count = 1, endtimes = { soul_two } },
	[348] = { count = 1, endtimes = { soul_two } },
}, os.time())
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = soul_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = soul_two, recipients = { 77 } }
brd._test.state.marcato_reservation = 'Honor March'
action = brd.propose(soul_config, { now = os.time(), player = player, action_ready = ready })
assert_equal(action.action_name, 'Soul Voice', 'active NITRO must activate Soul Voice before spending a Marcato reservation')
assert_equal(brd._test.state.marcato_reservation, '', 'Soul Voice generation must clear addon-owned Marcato reservations')
local short_nitro_endtime = brd._test.server_now_raw(os.time()) + 600
brd.on_status_snapshot({
	[347] = { count = 1, endtimes = { short_nitro_endtime } },
	[348] = { count = 1, endtimes = { short_nitro_endtime } },
}, os.time())
assert_true(brd._test.nitro_supports_soul_voice({ now = os.time(), player = player }, 2) == false, 'Soul Voice must reject a NITRO window too short for the minimum group refresh')

local invalid_soul_config = {}
for key, value in pairs(soul_config) do invalid_soul_config[key] = value end
invalid_soul_config.use_nitro = false
local soul_ok, soul_reason = brd._test.validate_config(invalid_soul_config, player)
assert_true(soul_ok == false, 'Soul Voice without NITRO must be rejected')
assert_equal(soul_reason, 'soul_voice_requires_nitro', 'Soul Voice without NITRO blocker mismatch')

brd.reset('nightingale_confirmation_retry_test')
player.buffs = {}
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { soul_one, soul_two } } }, 50)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = soul_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = soul_two, recipients = { 77 } }
action = brd.propose(soul_config, { now = 50, player = player, action_ready = ready })
assert_equal(action.action_name, 'Nightingale', 'Nightingale retry setup proposal mismatch')
brd.note_dispatch(action, 'nightingale-timeout', 50)
action = brd.propose(soul_config, { now = 50.6, player = player, action_ready = ready })
assert_true(action == nil, 'missing Nightingale confirmation must first return the reserved step to retry eligibility')
assert_equal(brd._test.state.last_blocker, 'nightingale_confirmation_retry', 'Nightingale confirmation retry blocker mismatch')
assert_true(brd.action_lane_status() == true, 'Nightingale confirmation retry must retain the Bard lane')
action = brd.propose(soul_config, { now = 50.7, player = player, action_ready = ready })
assert_equal(action.action_name, 'Nightingale', 'missing Nightingale confirmation must retry the same reserved ability')

brd.reset('targeted_pianissimo_test')
player.buffs = {}
local targeted_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March' },
	dummy_songs = {},
	recovery_range_yalms = 9.9,
	recovery_ignore_names = {},
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {
		{ recipients = { 'Target' }, priority_songs = { "Mage's Ballad III", "Army's Paeon" } },
	},
}
local targeted_one = brd._test.server_now_raw(os.time()) + 30000
local targeted_two = targeted_one + 600
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { targeted_one, targeted_two } } }, os.time())
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = targeted_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = targeted_two, recipients = { 77 } }
local party_state = require('uc_brd_party_song_state')
local targeted_member = {
	id = 99,
	name = 'Target',
	hpp = 100,
	spawn_type = 13,
	is_npc = false,
	in_song_range = true,
	buffs = { 100, 100 },
}
party_state.observe({ targeted_member }, { 'Target' }, { [100] = true, [104] = true }, os.time())
assert_true(party_state._test.state.members[99].eligible == false, 'recovery ignore policy must exclude the recipient from area recovery')
assert_true(party_state._test.state.members[99].targetable == true, 'recovery ignore policy must not make an explicit Pianissimo recipient untargetable')
assert_equal(party_state._test.state.members[99].unknown_count, 2, 'targetable ignored recipients must still reconcile observed song counts conservatively')
party_state.reset()
party_state.observe({ targeted_member }, {}, { [100] = true, [104] = true }, os.time())
party_state.record_delivery({ song_name = 'Honor March', status_id = 100, endtime = targeted_one, recipients = { 99 }, cast_capacity = 2 })
party_state.record_delivery({ song_name = 'Victory March', status_id = 100, endtime = targeted_two, recipients = { 99 }, cast_capacity = 2 })
action = brd.propose(targeted_config, {
	now = os.time(),
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_equal(action.action_name, 'Pianissimo', 'normal targeted overlay must reserve Pianissimo')
assert_equal(brd._test.state.targeted_transaction.song_name, "Mage's Ballad III", 'best-effort overlay must select the highest-priority safe song first')
brd.note_dispatch(action, 'targeted-pianissimo', os.time())
action = brd.propose(targeted_config, {
	now = os.time(),
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_true(action == nil, 'Pianissimo confirmation gap must not admit another Bard action')
assert_true(brd.action_lane_status() == true, 'Pianissimo confirmation gap must retain the Bard action lane')
assert_equal(brd._test.state.last_blocker, 'pianissimo_confirmation_pending:Target', 'Pianissimo confirmation blocker mismatch')
local pianissimo_confirmed, pianissimo_event = brd.on_action({
	actor_id = 77,
	category = 6,
	param = 229,
	targets = { { id = 77, actions = {} } },
}, 77, os.time())
assert_true(pianissimo_confirmed == true, 'successful local Pianissimo action packet must confirm the reserved transaction')
assert_equal(pianissimo_event, 'pianissimo_confirmed', 'Pianissimo confirmation must identify the scheduler action-state release event')
assert_equal(brd._test.state.targeted_transaction.phase, 'awaiting_song', 'Pianissimo action packet must advance directly to the reserved song')
action = brd.propose(targeted_config, {
	now = os.time(),
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_equal(action.action_name, "Mage's Ballad III", 'action-confirmed Pianissimo must dispatch the reserved targeted song without waiting for buff polling')
assert_equal(action.detail.target_id, 99, 'targeted song proposal must preserve recipient server ID')
assert_true(action.detail.requires_troubadour == false, 'normal victim must not require Troubadour')
brd.note_scheduler_rejection('BLOCK_ACTION_COOLDOWN', action.action_name)
assert_equal(brd._test.state.targeted_transaction.phase, 'awaiting_song', 'scheduler rejection must leave the targeted song eligible for retry')
action = brd.propose(targeted_config, {
	now = os.time(),
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_equal(action.action_name, "Mage's Ballad III", 'scheduler cooldown rejection must retry the same targeted song')
assert_equal(action.detail.target_id, 99, 'scheduler cooldown retry must preserve the same recipient')
assert_true(brd.action_lane_status() == true, 'scheduler cooldown retry must retain the Bard action lane')
player.buffs = { 409 }
brd.note_dispatch(action, 'targeted-1', os.time())
assert_equal(brd._test.state.targeted_transaction.phase, 'song_dispatched', 'successful dispatch must own the targeted transaction phase transition')
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 8,
	targets = { { id = 99, actions = { { message = 205, param = 104 } } } },
}, 77, os.time())
assert_true(type(party_state._test.state.members[99].effects["Mage's Ballad III"]) == 'table', 'targeted success must update only the confirmed recipient')
assert_true(party_state._test.state.members[99].effects["Mage's Ballad III"].pianissimo_applied == true, 'targeted effect must retain Pianissimo provenance')
action = brd.propose(targeted_config, {
	now = os.time(),
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_true(action == nil, 'a consumed Pianissimo must clear before another targeted song can begin')
assert_equal(brd._test.state.last_blocker, 'targeted_waiting_for_pianissimo_consumption', 'Pianissimo consumption wait blocker mismatch')

party_state.reset()
party_state._test.state.members[99] = {
	id = 99,
	name = 'Target',
	eligible = true,
	targetable = true,
	observed_song_count = 2,
	unknown_count = 0,
	effects = {
		['Honor March'] = { endtime = targeted_one, troubadour_active = true },
		['Victory March'] = { endtime = targeted_two, troubadour_active = false },
	},
}
party_state._test.state.order = { 99 }
local targeted_plan = assert(party_state.plan_targeted_song(99, "Mage's Ballad III", 2, {}))
assert_true(targeted_plan.requires_troubadour == true, 'targeted overlay over a Troubadour victim must require Troubadour')
local modifier_now = os.time()
local modifier_endtime = brd._test.server_now_raw(modifier_now) + 1200
brd.on_status_snapshot({ [348] = { count = 1, endtimes = { modifier_endtime } } }, modifier_now)
assert_true(brd._test.status_active_at_resolution(348, modifier_now) == true, 'Troubadour must be proven active from its authoritative endtime at resolution')
assert_true(brd._test.status_active_at_resolution(348, modifier_now + 21) == false, 'expired Troubadour must fail resolution-time evidence')
brd._test.state.pending = {
	name = "Mage's Ballad III",
	spell_id = 8,
	status_id = 104,
	targeted = true,
	target_id = 99,
	target_name = 'Target',
	requires_troubadour = true,
	targeted_candidate_names = { 'Honor March' },
}
brd._test.state.targeted_transaction = { recipient_id = 99, recipient_name = 'Target' }
assert_true(brd.on_action({
	actor_id = 77,
	category = 4,
	param = 8,
	targets = { { id = 99, actions = { { message = 205, param = 104 } } } },
}, 77, modifier_now + 21) == false, 'targeted resolution must fail when required Troubadour has expired')
assert_equal(brd._test.state.last_blocker, "targeted_troubadour_expired_at_resolution:Mage's Ballad III", 'resolution-time Troubadour failure blocker mismatch')
assert_equal(party_state._test.state.members[99].confidence, 'unknown', 'expired required Troubadour must invalidate recipient song ownership')

brd.reset('targeted_unknown_overwrite_retry_test')
player.buffs = {}
local unknown_targeted_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March' },
	dummy_songs = {},
	recovery_range_yalms = 9.9,
	recovery_ignore_names = { 'Target' },
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {
		{ recipients = { 'Target' }, priority_songs = { "Mage's Ballad III" } },
	},
}
local unknown_now = os.time()
local unknown_one = brd._test.server_now_raw(unknown_now) + 30000
local unknown_two = unknown_one + 600
brd.on_status_snapshot({ [100] = { count = 2, endtimes = { unknown_one, unknown_two } } }, unknown_now)
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = unknown_one, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = unknown_two, recipients = { 77 } }
party_state.observe({ targeted_member }, { 'Target' }, { [100] = true, [104] = true }, unknown_now)
action = brd.propose(unknown_targeted_config, {
	now = unknown_now,
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_true(action == nil, 'unknown overwrite victim must remain blocked without safe Troubadour evidence')
assert_equal(brd._test.state.last_blocker, 'targeted_blocked:Target:unknown_overwrite_victim', 'unknown targeted victim blocker mismatch')
assert_equal(brd._test.state.targeted_skip_reasons["1:target:Mage's Ballad III"], 'unknown_overwrite_victim', 'per-recipient skip reason must retain the exact blocker')

local unknown_troubadour_endtime = brd._test.server_now_raw(unknown_now) + 1200
player.buffs = { 348 }
brd.on_status_snapshot({
	[100] = { count = 2, endtimes = { unknown_one, unknown_two } },
	[348] = { count = 1, endtimes = { unknown_troubadour_endtime } },
}, unknown_now)
action = brd.propose(unknown_targeted_config, {
	now = unknown_now,
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_equal(action.action_name, 'Pianissimo', 'safe Troubadour window must make an unknown targeted victim retryable')
assert_equal(brd._test.state.targeted_transaction.recipient_name, 'Target', 'unknown overwrite retry must preserve deterministic recipient selection')
brd.note_dispatch(action, 'pianissimo-retry', unknown_now)
action = brd.propose(unknown_targeted_config, {
	now = unknown_now + 0.6,
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_true(action == nil, 'missing Pianissimo confirmation must return the same transaction to retry eligibility')
assert_equal(brd._test.state.last_blocker, 'pianissimo_confirmation_retry:Target', 'Pianissimo confirmation retry blocker mismatch')
action = brd.propose(unknown_targeted_config, {
	now = unknown_now + 0.7,
	player = player,
	party_members = { targeted_member },
	action_ready = ready,
})
assert_equal(action.action_name, 'Pianissimo', 'missing Pianissimo confirmation must retry after half a second')
assert_equal(brd._test.state.targeted_transaction.recipient_name, 'Target', 'Pianissimo retry must not advance to another recipient')
local pianissimo_recast_consumed = function(name)
	if name == 'Pianissimo' then return false, 'recast', 'ja' end
	return ready(name)
end
action = brd.propose(unknown_targeted_config, {
	now = unknown_now + 1.3,
	player = player,
	party_members = { targeted_member },
	action_ready = pianissimo_recast_consumed,
})
assert_true(action == nil, 'an undispatched retry must not discard evidence from the original Pianissimo dispatch')
assert_equal(brd._test.state.last_blocker, 'pianissimo_confirmation_pending_recast:Target', 'original Pianissimo dispatch blocker mismatch after retry loses arbitration')
assert_equal(brd._test.state.targeted_transaction.phase, 'awaiting_pianissimo', 'undispatched retry must preserve the original transaction')
assert_true(brd.action_lane_status() == true, 'undispatched retry must retain the Bard action lane while the original recast is consumed')
player.buffs = { 348, 409 }
action = brd.propose(unknown_targeted_config, {
	now = unknown_now + 1.4,
	player = player,
	party_members = { targeted_member },
	action_ready = pianissimo_recast_consumed,
})
assert_equal(action.action_name, "Mage's Ballad III", 'late Pianissimo buff confirmation must continue directly to the reserved song')
assert_equal(action.detail.target_id, 99, 'late Pianissimo confirmation must preserve the reserved recipient')
assert_true(brd.action_lane_status() == true, 'late Pianissimo confirmation must keep the Bard lane reserved through song proposal')

brd.reset('targeted_self_final_candidate_test')
player.buffs = {}
local self_targeted_config = {
	enabled = true,
	songs = { 'Honor March', 'Victory March', 'Valor Minuet V', 'Valor Minuet IV' },
	dummy_songs = { "Army's Paeon", "Army's Paeon II" },
	recovery_range_yalms = 9.9,
	recovery_ignore_names = { 'Niightsiide', 'Terrasjr', 'Redrogue' },
	use_nitro = false,
	use_soul_voice = false,
	use_clarion_call = false,
	use_marcato = false,
	marcato_song = '',
	targeted_songs = {
		{
			recipients = { 'Niightsiide', 'Terrasjr', 'Redrogue' },
			priority_songs = { "Mage's Ballad III" },
		},
	},
}
local self_targeted_base = brd._test.server_now_raw(os.time()) + 30000
local self_targeted_snapshot = {
	[100] = { count = 2, endtimes = { self_targeted_base, self_targeted_base + 120 } },
	[103] = { count = 2, endtimes = { self_targeted_base + 240, self_targeted_base + 360 } },
}
brd.on_status_snapshot(self_targeted_snapshot, os.time())
brd._test.state.owners['Honor March'] = { status_id = 100, endtime = self_targeted_base, recipients = { 77 } }
brd._test.state.owners['Victory March'] = { status_id = 100, endtime = self_targeted_base + 120, recipients = { 77 } }
brd._test.state.owners['Valor Minuet V'] = { status_id = 103, endtime = self_targeted_base + 240, recipients = { 77 } }
brd._test.state.owners['Valor Minuet IV'] = { status_id = 103, endtime = self_targeted_base + 360, recipients = { 77 } }
local self_targeted_members = {
	{ id = 91, name = 'Niightsiide', hpp = 100, spawn_type = 13, is_npc = false, in_song_range = true, buffs = { 100, 103, 103, 104 } },
	{ id = 92, name = 'Terrasjr', hpp = 100, spawn_type = 13, is_npc = false, in_song_range = true, buffs = { 100, 103, 103, 104 } },
	{ id = 77, name = 'Redrogue', hpp = 100, spawn_type = 13, is_npc = false, is_self = true, in_song_range = true, buffs = { 100, 100, 103, 103 } },
}
party_state.observe(self_targeted_members, self_targeted_config.recovery_ignore_names, { [100] = true, [103] = true, [104] = true }, os.time())
assert_true(party_state._test.state.members[77].eligible == false, 'the Bard must remain excluded from party recovery')
assert_true(party_state._test.state.members[77].targetable == true, 'the Bard must be targetable for an explicit self Pianissimo overlay')
for _, member_id in ipairs({ 91, 92, 77 }) do
	for _, delivery in ipairs({
		{ song_name = 'Honor March', status_id = 100, endtime = self_targeted_base },
		{ song_name = 'Victory March', status_id = 100, endtime = self_targeted_base + 120 },
		{ song_name = 'Valor Minuet V', status_id = 103, endtime = self_targeted_base + 240 },
		{ song_name = 'Valor Minuet IV', status_id = 103, endtime = self_targeted_base + 360 },
	}) do
		party_state.record_delivery({
			song_name = delivery.song_name,
			status_id = delivery.status_id,
			endtime = delivery.endtime,
			recipients = { member_id },
			cast_capacity = 4,
		})
	end
end
for _, member_id in ipairs({ 91, 92 }) do
	party_state.record_delivery({
		song_name = "Mage's Ballad III",
		status_id = 104,
		endtime = self_targeted_base + 480,
		recipients = { member_id },
		cast_capacity = 2,
	})
end
action = brd.propose(self_targeted_config, {
	now = os.time(),
	player = player,
	party_members = self_targeted_members,
	action_ready = ready,
})
assert_equal(action.action_name, 'Pianissimo', 'the Bard must be selected after earlier targeted recipients are already satisfied')
assert_equal(brd._test.state.targeted_transaction.recipient_name, 'Redrogue', 'the final targeted transaction must resolve the configured self recipient')
brd.note_dispatch(action, 'targeted-self-pianissimo', os.time())
assert_true(brd.on_action({ actor_id = 77, category = 6, param = 229, targets = { { id = 77, actions = {} } } }, 77, os.time()) == true, 'self-targeted Pianissimo must confirm')
action = brd.propose(self_targeted_config, {
	now = os.time(),
	player = player,
	party_members = self_targeted_members,
	action_ready = ready,
})
assert_equal(action.action_name, "Mage's Ballad III", 'confirmed self Pianissimo must reserve the configured song')
assert_equal(action.detail.target_id, 77, 'self-targeted song must preserve the Bard server ID')
player.buffs = { 409 }
brd.note_dispatch(action, 'targeted-self-song', os.time())
brd.on_action({
	actor_id = 77,
	category = 4,
	param = 8,
	targets = { { id = 77, actions = { { message = 230, param = 104 } } } },
}, 77, os.time())
self_targeted_members[3].buffs = { 100, 103, 103, 104 }
brd.on_status_snapshot({
	[100] = { count = 1, endtimes = { self_targeted_base + 120 } },
	[103] = self_targeted_snapshot[103],
	[104] = { count = 1, endtimes = { self_targeted_base + 480 } },
}, os.time())
assert_true(type(brd._test.state.owners["Mage's Ballad III"]) == 'table', 'self-targeted song must use authoritative local timer ownership')
assert_true(brd._test.state.owners["Mage's Ballad III"].pianissimo_applied == true, 'self-targeted local ownership must retain Pianissimo provenance')
assert_true(brd._test.state.targeted_transaction == nil, 'self-targeted local timer confirmation must complete the transaction')
player.buffs = {}
action = brd.propose(self_targeted_config, {
	now = os.time(),
	player = player,
	party_members = self_targeted_members,
	action_ready = ready,
})
assert_true(action == nil, 'a confirmed self overlay must remain an accepted replacement instead of triggering group-song repair')

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
local maintenance_provider_file = assert(io.open('uc_provider_maintenance.lua', 'r'))
local maintenance_provider_source = maintenance_provider_file:read('*a')
maintenance_provider_file:close()
assert_true(maintenance_provider_source:find("'maintenance_brd'", 1, true) ~= nil
	and maintenance_provider_source:find('provider = source_provider', 1, true) ~= nil,
	'maintenance provider must emit the dedicated BRD provider')
assert_true(scheduler_source:find('scheduler.PRIORITY_BAND_BRD_MAINTENANCE = 200', 1, true) ~= nil, 'scheduler must globally prioritize BRD maintenance above every non-Doom proposal')
assert_true(scheduler_source:find('scheduler.p1_brd_lane_blocks_proposal', 1, true) ~= nil, 'scheduler must preserve BRD sequence ownership across proposal gaps')
assert_true(scheduler_source:find('scheduler.p1_dispatch_maintenance_brd', 1, true) ~= nil, 'scheduler must own dedicated BRD dispatch')
assert_true(scheduler_source:find("command_target = '\"' .. target_name", 1, true) ~= nil, 'scheduler must dispatch targeted Bard spells by verified party name')
assert_true(scheduler_source:find('is_spell_prestart_rejection_message_id', 1, true) ~= nil, 'scheduler must classify unable-cast action messages')
assert_true(scheduler_source:find("return mid == 17 or mid == 18", 1, true) ~= nil, 'scheduler must recognize both unable-cast message ids')
assert_true(scheduler_source:find("[8] = true", 1, true) ~= nil, 'scheduler action state must recognize category-8 song start packets')
assert_true(scheduler_source:find('p1_pending_mark_failed', 1, true) ~= nil, 'unable-cast handling must fail scheduler pending work')
assert_true(scheduler_source:find('maintenance_next_at.brd_songs', 1, true) ~= nil, 'unable-cast handling must use the scheduler BRD retry gate')
assert_true(maintenance_provider_source:find('take_scheduler_failure', 1, true) ~= nil, 'maintenance provider must consume silent BRD lifecycle failures')
assert_true(maintenance_provider_source:find("'maintenance_songs'", 1, true) == nil, 'old non-dispatchable Bard placeholder must be removed')

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
assert_true(log_text:find('\tPLANNER_BLOCKED\t', 1, true) ~= nil, 'BRD diagnostic log must record no-action planner blockers')
assert_true(log_text:find('\tTARGETED_RECIPIENT_SKIPPED\t', 1, true) ~= nil, 'BRD diagnostic log must record each targeted recipient skip reason')
assert_true(log_text:find('\tPIANISSIMO_CONFIRMATION_RETRY\t', 1, true) ~= nil, 'BRD diagnostic log must record missing Pianissimo confirmation retries')
os.remove(log_path)

local old_auto_brd_log = rawget(_G, 'UC_BRD_DIAGNOSTIC_LOG')
_G.UC_BRD_DIAGNOSTIC_LOG = true
brd.reset('auto_diagnostic_log_test')
player.buffs = {}
brd.propose(config, { now = 40, player = player, action_ready = ready })
local auto_log_enabled, auto_log_path = brd.diagnostic_log_status()
assert_true(auto_log_enabled == true, 'local Bard diagnostic flag must auto-start logging after reload initialization')
_G.UC_BRD_DIAGNOSTIC_LOG = nil
brd.propose(config, { now = 40.1, player = player, action_ready = ready })
assert_true(brd.diagnostic_log_status() == false, 'clearing the local Bard diagnostic flag must stop only an auto-started log')
os.remove(auto_log_path)
_G.UC_BRD_DIAGNOSTIC_LOG = old_auto_brd_log

package.loaded.uc_brd_maintenance = old_module
package.loaded.resources = old_resources
windower = old_windower

io.stdout:write('selftest_brd_maintenance: OK\n')
