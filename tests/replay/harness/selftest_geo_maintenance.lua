package.path = package.path .. ';./?.lua'

local geo_maintenance = require('uc_geo_maintenance')

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(
			message or 'values differ',
			tostring(expected),
			tostring(actual)
		))
	end
end

local resources = {
	['Geo-Frailty'] = {
		id = 768,
		en = 'Geo-Frailty',
		range = 12,
		targets = {
			Enemy = true,
		},
	},
	['Indi-Haste'] = {
		id = 795,
		en = 'Indi-Haste',
		range = 1,
		targets = {
			Self = true,
		},
	},
}

local camp_anchor = {
	x = 10,
	y = 20,
}

local function new_provider(timeline_events, counters)
	timeline_events = type(timeline_events) == 'table' and timeline_events or {}
	counters = type(counters) == 'table' and counters or {}
	local function bump(name)
		counters[name] = (tonumber(counters[name]) or 0) + 1
	end
	return geo_maintenance.new({
		geo_maintenance_priority = 210,
		geo_creation_priority = 240,
		action_ready = function(name)
			bump('action_ready')
			if resources[name] ~= nil then
				return true, 'ready', 'spell'
			end
			return true, 'ready', 'ja'
		end,
		get_spell_resource = function(name)
			bump('get_spell_resource')
			return resources[name]
		end,
		get_ja_resource = function(name)
			bump('get_ja_resource')
			return {
				id = 1000,
				en = name,
			}
		end,
		get_party_members = function()
			bump('get_party_members')
			return {}
		end,
		get_friendly_claims = function()
			bump('get_friendly_claims')
			return {
				[900] = true,
			}
		end,
		resolve_camp_anchor = function()
			bump('resolve_camp_anchor')
			return camp_anchor, 'CAMP_READY'
		end,
		action_effective_range = function()
			return 20.0
		end,
		target_is_actionable = function(target)
			return type(target) == 'table' and tonumber(target.hpp) > 0
		end,
		target_is_ignored = function()
			return false
		end,
		player_is_moving = function()
			return false
		end,
		pull_active = function()
			return false
		end,
		log = function()
		end,
		action_timeline_log = function(event_code, fields)
			timeline_events[#timeline_events + 1] = {
				event_code = tostring(event_code or ''),
				fields = fields,
			}
		end,
	})
end

local function config()
	return {
		enabled = true,
		geo_spell = 'Geo-Frailty',
		geo_target = {
			kind = 'current_enemy',
			name = nil,
		},
		indi_spell = 'Indi-Haste',
		ordering = 'geo_first',
		require_camp = true,
		camp_tolerance_yalms = 1.0,
		enemy_geo_requires_camp_radius = false,
		unknown_existing_policy = 'wait_for_clear',
		entrust = {
			enabled = false,
		},
		luopan = {
			placement = 'target',
			use_blaze_of_glory = false,
			use_ecliptic_attrition = false,
			use_life_cycle = false,
			life_cycle_hpp = 50,
			replace_out_of_position = false,
			max_camp_distance_yalms = 6.0,
		},
	}
end

local function context(now)
	local target = {
		id = 200,
		name = 'Apex Bat',
		hpp = 100,
		distance = 25,
		x = 10,
		y = 20,
		valid_target = true,
		spawn_type = 16,
		claim_id = 900,
	}
	return {
		now = now,
		settings = {
			config = {
				maintenance = {
					geo = config(),
				},
			},
		},
		player_present = true,
		player = {
			id = 100,
			name = 'Geomancer',
			main_job = 'GEO',
			buffs = {},
		},
		player_id = 100,
		player_name = 'Geomancer',
		me = {
			id = 100,
			name = 'Geomancer',
			x = 10,
			y = 20,
		},
		target_present = false,
		target = {},
		target_id_snapshot = 0,
		pet_present = false,
		mob_array = {
			target,
		},
		mobs_by_id = {
			[200] = target,
		},
	}
end

local function converge_owned_luopan(provider, ctx, pet_x, pet_y)
	local out = {}
	provider.collect(ctx, out)
	assert_equal(#out, 1, 'initial GEO proposal count mismatch')
	assert_equal(out[1].action_name, 'Geo-Frailty', 'initial GEO proposal mismatch')
	provider.note_dispatch(out[1], ctx.now + 0.1)

	ctx.now = ctx.now + 1.0
	ctx.pet_present = true
	ctx.pet_id = 300
	ctx.pet = {
		id = 300,
		name = 'Luopan',
		hpp = 100,
		x = pet_x,
		y = pet_y,
	}
	out = {}
	provider.collect(ctx, out)
	assert_equal(#out, 1, 'owned Luopan should advance to Indi')
	assert_equal(out[1].action_name, 'Indi-Haste', 'owned Luopan Indi proposal mismatch')
	provider.note_dispatch(out[1], ctx.now + 0.1)

	ctx.now = ctx.now + 1.0
	ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
	out = {}
	provider.collect(ctx, out)
	assert_equal(#out, 0, 'owned GEO effects should converge')
	assert_equal(provider.status.state, 'converged', 'owned GEO convergence state mismatch')
end

local original_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)

local independent_camp_provider = new_provider()
local independent_camp_ctx = context(0.5)
independent_camp_ctx.settings.config.maintenance.geo.luopan.placement = 'camp'
independent_camp_ctx.settings.config.maintenance.geo.require_camp = false
local independent_out = {}
independent_camp_provider.collect(independent_camp_ctx, independent_out)
assert_equal(#independent_out, 1, 'camp placement must not require provider camp restriction')
assert_equal(independent_out[1].action_name, 'Geo-Frailty', 'independent camp placement proposal mismatch')

local provider = new_provider()
local ctx = context(1.0)
local out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'missing effects should emit one action')
assert_equal(out[1].provider, 'maintenance_geo', 'GEO provider id mismatch')
assert_equal(out[1].action_name, 'Geo-Frailty', 'geo_first should emit Geo spell')
assert_equal(out[1].target_id, 200, 'Geo target id mismatch')
assert_equal(out[1].priority_band, 240, 'Geo spell must use elevated GEO creation priority')

provider.note_dispatch(out[1], 1.1)
ctx.now = 2.0
ctx.pet_present = true
ctx.pet = {
	id = 300,
	name = 'Luopan',
	x = 10,
	y = 20,
}
out = {}
provider.collect(ctx, out)
assert_equal(#out, 1, 'observed luopan should advance to Indi')
assert_equal(out[1].action_name, 'Indi-Haste', 'Indi follow-up mismatch')
assert_equal(out[1].target_id, 100, 'Indi must target self')
assert_equal(out[1].priority_band, 210, 'Indi spell must use elevated GEO maintenance priority')

provider.note_dispatch(out[1], 2.1)
ctx.now = 3.0
ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
out = {}
provider.collect(ctx, out)
assert_equal(#out, 0, 'observed desired effects should converge')
assert_equal(provider.status.state, 'converged', 'converged state mismatch')

local unknown_provider = new_provider()
local unknown_ctx = context(5.0)
unknown_ctx.pet_present = true
unknown_ctx.pet = {
	id = 301,
	name = 'Luopan',
}
out = {}
unknown_provider.collect(unknown_ctx, out)
assert_equal(#out, 0, 'unknown existing luopan must not be overwritten')
assert_equal(unknown_provider.status.state, 'unknown_existing', 'unknown luopan state mismatch')

local camp_provider = new_provider()
local camp_ctx = context(6.0)
camp_ctx.me.x = 15
out = {}
camp_provider.collect(camp_ctx, out)
assert_equal(#out, 0, 'GEO maintenance must hold outside camp tolerance')
assert_equal(camp_provider.status.reason, 'GEO_AWAY_FROM_CAMP', 'camp hold reason mismatch')

local moving_provider = geo_maintenance.new({
	geo_maintenance_priority = 210,
	geo_creation_priority = 240,
	action_ready = function()
		return true, 'ready', 'spell'
	end,
	get_spell_resource = function(name)
		return resources[name]
	end,
	get_ja_resource = function(name)
		return {
			id = 1000,
			en = name,
		}
	end,
	get_party_members = function()
		return {}
	end,
	get_friendly_claims = function()
		return {
			[900] = true,
		}
	end,
	resolve_camp_anchor = function()
		return camp_anchor, 'CAMP_READY'
	end,
	action_effective_range = function()
		return 20.0
	end,
	target_is_actionable = function()
		return true
	end,
	target_is_ignored = function()
		return false
	end,
	player_is_moving = function()
		return true
	end,
	pull_active = function()
		return false
	end,
	log = function()
	end,
	action_timeline_log = function()
	end,
})
out = {}
moving_provider.collect(context(7.0), out)
assert_equal(#out, 1, 'moving player must still emit scheduler-coordinated GEO recovery')
assert_equal(out[1].action_name, 'Geo-Frailty', 'moving GEO recovery action mismatch')
assert_equal(out[1].priority_band, 240, 'moving GEO recovery must retain creation priority')

local dead_luopan_events = {}
local dead_luopan_provider = new_provider(dead_luopan_events)
local dead_luopan_ctx = context(8.0)
converge_owned_luopan(dead_luopan_provider, dead_luopan_ctx, 10, 20)
dead_luopan_ctx.now = dead_luopan_ctx.now + 1.0
dead_luopan_ctx.pet_present = true
dead_luopan_ctx.pet_id = 300
dead_luopan_ctx.pet.hpp = 0
out = {}
dead_luopan_provider.collect(dead_luopan_ctx, out)
assert_equal(#out, 1, '0-HP Luopan must be treated as absent and immediately recreated')
assert_equal(out[1].action_name, 'Geo-Frailty', 'dead Luopan recovery action mismatch')
assert_equal(out[1].priority_band, 240, 'dead Luopan recovery must use GEO creation priority')
assert_true(type(_G.UC_GEO_DIAGNOSTIC_STATUS) == 'table', 'GEO diagnostic overlay missing')
assert_equal(_G.UC_GEO_DIAGNOSTIC_STATUS.luopan_present, 'false', 'dead Luopan diagnostic presence mismatch')
assert_equal(_G.UC_GEO_DIAGNOSTIC_STATUS.outcome, 'proposed', 'dead Luopan diagnostic outcome mismatch')
assert_equal(_G.UC_GEO_DIAGNOSTIC_STATUS.reason, 'Geo-Frailty', 'dead Luopan diagnostic proposal mismatch')
local saw_dead_state = false
local saw_create_decision = false
for _, event in ipairs(dead_luopan_events) do
	if event.event_code == 'GEO_LUOPAN_STATE'
		and type(event.fields) == 'table'
		and event.fields.pet_hpp == '0'
		and event.fields.luopan_present == 'false' then
		saw_dead_state = true
	elseif event.event_code == 'GEO_CREATE_DECISION'
		and type(event.fields) == 'table'
		and event.fields.outcome == 'proposed'
		and event.fields.reason == 'Geo-Frailty' then
		saw_create_decision = true
	end
end
assert_true(saw_dead_state, 'dead Luopan state transition diagnostic missing')
assert_true(saw_create_decision, 'dead Luopan creation decision diagnostic missing')

local blocked_diag_events = {}
local blocked_diag_provider = new_provider(blocked_diag_events)
local blocked_diag_ctx = context(9.0)
blocked_diag_ctx.me.x = 15
out = {}
blocked_diag_provider.collect(blocked_diag_ctx, out)
assert_equal(#out, 0, 'blocked dead Luopan diagnostic must not invent a proposal')
assert_equal(_G.UC_GEO_DIAGNOSTIC_STATUS.outcome, 'blocked', 'blocked diagnostic outcome mismatch')
assert_equal(_G.UC_GEO_DIAGNOSTIC_STATUS.reason, 'outside_camp_tolerance', 'blocked diagnostic reason mismatch')
local saw_blocked_decision = false
for _, event in ipairs(blocked_diag_events) do
	if event.event_code == 'GEO_CREATE_DECISION'
		and type(event.fields) == 'table'
		and event.fields.outcome == 'blocked'
		and event.fields.reason == 'outside_camp_tolerance' then
		saw_blocked_decision = true
	end
end
assert_true(saw_blocked_decision, 'blocked GEO creation diagnostic missing exact gate')

local healthy_block_counters = {}
local healthy_block_provider = new_provider({}, healthy_block_counters)
local healthy_block_ctx = context(9.5)
converge_owned_luopan(healthy_block_provider, healthy_block_ctx, 10, 20)
healthy_block_ctx.now = healthy_block_ctx.now + 1.0
healthy_block_ctx.me.x = 15
out = {}
healthy_block_provider.collect(healthy_block_ctx, out)
assert_equal(healthy_block_provider.status.reason, 'GEO_AWAY_FROM_CAMP',
	'healthy slow spatial pass must publish camp blocker')
local blocked_camp_checks = tonumber(healthy_block_counters.resolve_camp_anchor) or 0
healthy_block_ctx.now = healthy_block_ctx.now + 0.20
out = {}
healthy_block_provider.collect(healthy_block_ctx, out)
assert_equal(healthy_block_provider.status.reason, 'GEO_AWAY_FROM_CAMP',
	'healthy fast observation must preserve the last spatial blocker')
assert_equal(tonumber(healthy_block_counters.resolve_camp_anchor) or 0, blocked_camp_checks,
	'healthy fast observation must not repeat blocked camp geometry before slow cadence')

local camp_outside_provider = new_provider()
local camp_outside_ctx = context(10.0)
camp_outside_ctx.settings.config.maintenance.geo.luopan.placement = 'camp'
camp_outside_ctx.settings.config.maintenance.geo.luopan.replace_out_of_position = true
converge_owned_luopan(camp_outside_provider, camp_outside_ctx, 10, 20)
camp_outside_ctx.now = 13.0
camp_outside_ctx.mobs_by_id[200].x = 18
camp_outside_ctx.mobs_by_id[200].distance = 64
out = {}
camp_outside_provider.collect(camp_outside_ctx, out)
assert_equal(#out, 0, 'camp-placed Luopan must ignore enemy outside 6.5 yalms')
assert_equal(camp_outside_provider.status.state, 'converged', 'camp placement outside-radius state mismatch')
assert_equal(camp_outside_provider.status_snapshot().sequence, nil, 'camp placement must not begin replacement')

local camp_inside_provider = new_provider()
local camp_inside_ctx = context(20.0)
camp_inside_ctx.settings.config.maintenance.geo.luopan.placement = 'camp'
camp_inside_ctx.settings.config.maintenance.geo.luopan.replace_out_of_position = true
converge_owned_luopan(camp_inside_provider, camp_inside_ctx, 10, 20)
camp_inside_ctx.now = 23.0
camp_inside_ctx.mobs_by_id[200].x = 16
camp_inside_ctx.mobs_by_id[200].distance = 36
out = {}
camp_inside_provider.collect(camp_inside_ctx, out)
assert_equal(#out, 0, 'camp-placed Luopan must remain satisfied inside 6.5 yalms')
assert_equal(camp_inside_provider.status.state, 'converged', 'camp placement inside-radius state mismatch')
assert_equal(camp_inside_provider.status_snapshot().sequence, nil, 'inside-radius camp placement must not replace')

local camp_no_replace_provider = new_provider()
local camp_no_replace_ctx = context(25.0)
camp_no_replace_ctx.settings.config.maintenance.geo.luopan.placement = 'camp'
converge_owned_luopan(camp_no_replace_provider, camp_no_replace_ctx, 10, 20)
camp_no_replace_ctx.now = 28.0
camp_no_replace_ctx.pet.x = 20
out = {}
camp_no_replace_provider.collect(camp_no_replace_ctx, out)
assert_equal(#out, 0, 'camp-misplaced Luopan must remain when replacement is disabled')
assert_equal(camp_no_replace_provider.status.state, 'converged', 'disabled camp replacement state mismatch')
assert_equal(camp_no_replace_provider.status_snapshot().sequence, nil, 'disabled camp replacement must not begin sequence')

local target_old_replace_provider = new_provider()
local target_old_replace_ctx = context(29.0)
target_old_replace_ctx.settings.config.maintenance.geo.luopan.replace_out_of_position = true
converge_owned_luopan(target_old_replace_provider, target_old_replace_ctx, 10, 20)
target_old_replace_ctx.now = 32.0
target_old_replace_ctx.pet.x = 20
target_old_replace_ctx.mobs_by_id[200].x = 20
target_old_replace_ctx.mobs_by_id[200].distance = 100
out = {}
target_old_replace_provider.collect(target_old_replace_ctx, out)
assert_equal(#out, 0, 'target placement must ignore camp distance despite old replacement setting')
assert_equal(target_old_replace_provider.status.state, 'converged', 'target placement old-setting state mismatch')
assert_equal(target_old_replace_provider.status_snapshot().sequence, nil, 'target placement old setting must not replace')

local target_centered_provider = new_provider()
local target_centered_ctx = context(35.0)
converge_owned_luopan(target_centered_provider, target_centered_ctx, 10, 20)
target_centered_ctx.now = 38.0
target_centered_ctx.mobs_by_id[200].x = 18
target_centered_ctx.mobs_by_id[200].distance = 64
out = {}
target_centered_provider.collect(target_centered_ctx, out)
assert_equal(#out, 1, 'target-centered Luopan must replace when enemy leaves 6.5 yalms')
assert_equal(out[1].action_name, 'Full Circle', 'target-centered reposition must begin with Full Circle')
local target_centered_sequence = target_centered_provider.status_snapshot().sequence
assert_true(type(target_centered_sequence) == 'table', 'target-centered replacement sequence missing')
assert_equal(target_centered_sequence.step, 'full_circle', 'target-centered replacement step mismatch')
assert_true(target_centered_sequence.replacement, 'target-centered replacement flag missing')

local perf_counters = {}
local perf_provider = new_provider({}, perf_counters)
local perf_ctx = context(40.0)
converge_owned_luopan(perf_provider, perf_ctx, 10, 20)
local baseline_spell_resource = tonumber(perf_counters.get_spell_resource) or 0
local baseline_ja_resource = tonumber(perf_counters.get_ja_resource) or 0
local baseline_camp = tonumber(perf_counters.resolve_camp_anchor) or 0
local baseline_claims = tonumber(perf_counters.get_friendly_claims) or 0
local baseline_ready = tonumber(perf_counters.action_ready) or 0

perf_ctx.now = perf_ctx.now + 0.20
out = {}
perf_provider.collect(perf_ctx, out)
assert_equal(#out, 0, 'healthy GEO fast observation must not invent work')
assert_equal(tonumber(perf_counters.get_spell_resource) or 0, baseline_spell_resource,
	'healthy fast observation must reuse cached spell contracts')
assert_equal(tonumber(perf_counters.get_ja_resource) or 0, baseline_ja_resource,
	'healthy fast observation must reuse cached ability contracts')
assert_equal(tonumber(perf_counters.resolve_camp_anchor) or 0, baseline_camp,
	'healthy fast observation must skip camp geometry between slow checks')
assert_equal(tonumber(perf_counters.get_friendly_claims) or 0, baseline_claims,
	'healthy fast observation must skip enemy target scans between slow checks')
assert_equal(tonumber(perf_counters.action_ready) or 0, baseline_ready,
	'healthy fast observation must skip readiness work when effects are satisfied')

perf_ctx.now = perf_ctx.now + 0.20
perf_ctx.player.buffs = {}
out = {}
perf_provider.collect(perf_ctx, out)
assert_equal(#out, 1, 'missing Indi must be proposed on the next 5 Hz GEO observation')
assert_equal(out[1].action_name, 'Indi-Haste', 'missing Indi fast observation action mismatch')
assert_equal(tonumber(perf_counters.get_friendly_claims) or 0, baseline_claims,
	'missing Indi self-cast must not scan enemy targets')

local cached_spell_resource = tonumber(perf_counters.get_spell_resource) or 0
perf_ctx.settings.config.maintenance.geo.camp_tolerance_yalms = 1.25
perf_ctx.now = perf_ctx.now + 0.20
out = {}
perf_provider.collect(perf_ctx, out)
assert_true((tonumber(perf_counters.get_spell_resource) or 0) > cached_spell_resource,
	'GEO config changes must invalidate cached resource contracts')

local engine_guard_provider = new_provider()
local engine_guard_ctx = context(45.0)
rawset(_G, 'Start_Engine', false)
out = {}
engine_guard_provider.collect(engine_guard_ctx, out)
assert_equal(#out, 0, 'engine-off GEO collection must remain a no-op')
rawset(_G, 'Start_Engine', true)
engine_guard_ctx.player.main_job = 'WHM'
out = {}
engine_guard_provider.collect(engine_guard_ctx, out)
assert_equal(#out, 0, 'non-GEO jobs must remain a no-op in the 5 Hz provider path')

if original_engine == nil then
	rawset(_G, 'Start_Engine', nil)
else
	rawset(_G, 'Start_Engine', original_engine)
end

assert_true(type(_G.UC_GEO_MAINTENANCE_STATUS) == 'table', 'GEO status overlay missing')
io.stdout:write('selftest_geo_maintenance: OK\n')
