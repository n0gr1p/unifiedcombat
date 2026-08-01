local observability = require('uc_scheduler_observability')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local phase1 = {
	tick = 9,
	last_top5_items = {
		{
			idx = 1,
			score = 80,
			provider = 'combat',
			family = 'combat.ws',
			action = 'Savage Blade',
			urgency_bonus = 5,
			risk_penalty = 0,
		},
		{
			idx = 2,
			score = 70,
			provider = 'disabled',
			family = 'hidden',
			action = 'Hidden',
			urgency_bonus = 0,
			risk_penalty = 0,
		},
	},
	recent_reject_items = {
		{
			tick = '8',
			provider = 'combat',
			family = 'combat.ja',
			action = 'Provoke',
			reason = 'cooldown',
		},
		{
			tick = '9',
			provider = 'disabled',
			family = 'hidden',
			action = 'Hidden',
			reason = 'hidden',
		},
	},
}

local overlay = observability.build_debug_overlay(phase1, {
	provider_enabled = function(provider)
		return provider == 'combat'
	end,
	get_party_members = function()
		return {
			{
				id = 1,
				name = 'Player',
				is_self = true,
				source = 'self_local',
				buffs = { 33 },
			},
		}
	end,
	resources_buffs = {
		[33] = { en = 'Haste' },
	},
	get_player = function()
		return { buffs = { 33 } }
	end,
	get_party_state_ipc_entry = function()
		return { buffs = { 33 } }
	end,
	get_party = function()
		return {
			p0 = {
				mob = { id = 1 },
				buffs = { 33 },
			},
		}
	end,
	ensure_maintenance_state_tables = function()
		return {
			status_snapshot = {
				Player = { [33] = true },
			},
		}
	end,
})

assert_equal(overlay.tick, 9, 'debug overlay tick')
assert_equal(#overlay.queued, 1, 'disabled queued provider filtered')
assert_equal(
	overlay.queued[1],
	'1) 80.00 combat/combat.ws Savage Blade u=5.00 rp=0.00',
	'queued output shape'
)
assert_equal(#overlay.rejected, 1, 'disabled rejection filtered')
assert_equal(
	overlay.rejected[1],
	't8 combat/combat.ja Provoke :: cooldown',
	'rejected output shape'
)
assert_equal(
	overlay.buff_up[1],
	'eval_source=self_local self=Player snapshot_ids=1',
	'buff overlay summary shape'
)

local enemy_overlay = observability.build_enemy_effect_overlay({
	[200] = {
		[33] = { source = 'fixture' },
	},
}, {
	resources_buffs = {
		[33] = { en = 'Haste' },
	},
	get_mob_by_id = function(target_id)
		return { id = target_id, name = 'Enemy', hpp = 75 }
	end,
})
assert_equal(enemy_overlay.lines[1], 'Enemy Effect Table (effectiveTargets)', 'enemy header')
assert_equal(enemy_overlay.lines[2], 'Enemy[200] hpp=75', 'enemy row shape')
assert_equal(enemy_overlay.lines[3], '  - Haste(33) src=fixture', 'enemy effect row shape')

local scheduler = { phase1 = {} }
local globals = {}
observability.publish_dryrun(
	scheduler,
	globals,
	{ tick = 1 },
	nil,
	{},
	{},
	{},
	{},
	{},
	nil,
	'',
	{
		set_pending_globals = function()
			globals.pending_called = true
		end,
		build_lock_summary = function()
			return 'locks'
		end,
	}
)
assert_equal(globals.UC_SCHED_P1_TICK, 1, 'published tick shape')
assert_equal(globals.UC_SCHED_P1_NOOP_REASON, 'no_proposals', 'published noop shape')
assert_equal(globals.UC_SCHED_P1_LOCK_SUMMARY, 'locks', 'published lock summary')
assert_equal(globals.pending_called, true, 'pending globals hook')

io.stdout:write('selftest_scheduler_observability: OK\n')
