package.path = package.path .. ';./?.lua'

local geo_maintenance = require('uc_geo_maintenance')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected=%s actual=%s'):format(
			message or 'values differ',
			tostring(expected),
			tostring(actual)
		))
	end
end

local function assert_true(actual, message)
	assert_equal(actual, true, message)
end

local resources = {
	['Geo-Frailty'] = {
		id = 768,
		en = 'Geo-Frailty',
		range = 12,
		targets = { Enemy = true },
	},
	['Indi-Haste'] = {
		id = 795,
		en = 'Indi-Haste',
		range = 1,
		targets = { Self = true },
	},
	['Indi-Fury'] = {
		id = 791,
		en = 'Indi-Fury',
		range = 1,
		targets = { Self = true },
	},
}

local function base_config()
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
			spell = nil,
			target_name = nil,
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

local function context(config)
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
		now = 1.0,
		settings = {
			config = {
				maintenance = {
					geo = config,
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
			x = 10,
			y = 20,
		},
		target_present = false,
		target = {},
		target_id_snapshot = 0,
		pet_present = false,
		pet_id = 0,
		pet = {},
		mob_array = {
			target,
		},
		mobs_by_id = {
			[200] = target,
		},
	}
end

local function new_provider(party_members, pull_state, ability_ready)
	return geo_maintenance.new({
		geo_maintenance_priority = 210,
		geo_creation_priority = 240,
		action_ready = function(name)
			if resources[name] ~= nil then
				if type(ability_ready) == 'table' and ability_ready[name] == false then
					return false, 'recast', 'spell'
				end
				return true, 'ready', 'spell'
			end
			if type(ability_ready) == 'table' and ability_ready[name] == false then
				return false, 'recast', 'ja'
			end
			return true, 'ready', 'ja'
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
			return party_members
		end,
		get_friendly_claims = function()
			return {
				[900] = true,
			}
		end,
		resolve_camp_anchor = function()
			return {
				x = 10,
				y = 20,
			}, 'CAMP_READY'
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
			return pull_state.active == true
		end,
		log = function()
		end,
		action_timeline_log = function()
		end,
	})
end

local function mark_luopan(ctx, id, hpp, x, y)
	ctx.pet_present = true
	ctx.pet_id = id
	ctx.pet = {
		id = id,
		name = 'Luopan',
		hpp = hpp,
		x = x,
		y = y,
	}
end

local function collect_one(provider, ctx)
	local out = {}
	provider.collect(ctx, out)
	assert_equal(#out, 1, 'expected exactly one GEO sequence proposal')
	return out[1]
end

local original_engine = rawget(_G, 'Start_Engine')
rawset(_G, 'Start_Engine', true)

local active_pull_config = base_config()
active_pull_config.luopan.use_life_cycle = true
local active_pull_state = {
	active = false,
}
local active_pull_provider = new_provider({}, active_pull_state)
local active_pull_ctx = context(active_pull_config)
local action = collect_one(active_pull_provider, active_pull_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'active-pull regression setup must create the luopan')
active_pull_provider.note_dispatch(action, 1.1)
active_pull_ctx.now = 2.0
mark_luopan(active_pull_ctx, 299, 25, 10, 20)
active_pull_state.active = true
action = collect_one(active_pull_provider, active_pull_ctx)
assert_equal(action.action_name, 'Indi-Haste', 'active pull with a luopan must not suppress missing Indi')
active_pull_provider.note_dispatch(action, 2.1)
active_pull_ctx.now = 3.0
active_pull_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
local active_pull_out = {}
active_pull_provider.collect(active_pull_ctx, active_pull_out)
assert_equal(#active_pull_out, 0, 'active pull must still defer optional luopan maintenance')
assert_equal(active_pull_provider.status.state, 'blocked', 'active-pull optional maintenance hold state mismatch')
assert_equal(active_pull_provider.status.detail, 'pull_active', 'active-pull optional maintenance hold detail mismatch')

local blaze_config = base_config()
blaze_config.luopan.use_blaze_of_glory = true
local blaze_pull_state = {
	active = false,
	target_id = 0,
}
local blaze_provider = new_provider({}, blaze_pull_state)
local blaze_ctx = context(blaze_config)
action = collect_one(blaze_provider, blaze_ctx)
assert_equal(action.action_name, 'Blaze of Glory', 'Blaze must precede enhanced Geo')
assert_equal(action.action_type, 'ja', 'Blaze proposal type mismatch')
blaze_provider.note_dispatch(action, 1.1)
blaze_ctx.now = 2.0
blaze_ctx.player.buffs = { geo_maintenance.BLAZE_OF_GLORY_BUFF_ID }
blaze_ctx.mobs_by_id[200].hpp = 0
local incoming_target = {
	id = 201,
	name = 'Apex Crab',
	hpp = 100,
	distance = 36,
	x = 10,
	y = 20,
	valid_target = true,
	spawn_type = 16,
	claim_id = 0,
}
blaze_ctx.mob_array[#blaze_ctx.mob_array + 1] = incoming_target
blaze_ctx.mobs_by_id[201] = incoming_target
blaze_pull_state.active = true
blaze_pull_state.target_id = 201
local deferred_out = {}
blaze_provider.collect(blaze_ctx, deferred_out)
assert_equal(#deferred_out, 0, 'consumed Blaze must wait while the incoming enemy is unclaimed')
assert_true(blaze_provider.lane_reserved(), 'consumed Blaze must retain the atomic GEO lane')
assert_true(blaze_provider.pull_for_enemy_allowed(), 'atomic GEO wait must admit the camp pull workflow')
incoming_target.claim_id = 900
blaze_ctx.me.x = 15
deferred_out = {}
blaze_provider.collect(blaze_ctx, deferred_out)
assert_equal(#deferred_out, 0, 'claimed replacement target must wait until the GEO returns to camp')
assert_equal(blaze_provider.status.reason, 'GEO_AWAY_FROM_CAMP', 'away-from-camp deferral reason mismatch')
assert_true(blaze_provider.pull_for_enemy_allowed(), 'camp return must remain admitted while GEO is away')
blaze_ctx.me.x = 10
blaze_pull_state.active = false
blaze_pull_state.target_id = 0
action = collect_one(blaze_provider, blaze_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'Blaze observation must advance to Geo')
assert_equal(action.target_id, 201, 'consumed Blaze must retarget the newly claimed enemy by id')
assert_true(not blaze_provider.pull_for_enemy_allowed(), 'GEO cast readiness must close the pull admission bridge')
assert_true(blaze_provider.lane_reserved(), 'consumed Blaze must reserve atomic GEO lane')
blaze_provider.note_dispatch(action, 2.1)
blaze_ctx.now = 3.0
mark_luopan(blaze_ctx, 300, 100, 10, 20)
action = collect_one(blaze_provider, blaze_ctx)
assert_equal(action.action_name, 'Indi-Haste', 'confirmed enhanced Geo must advance to Indi')
assert_equal(blaze_provider.lane_reserved(), false, 'completed enhanced Geo sequence must release lane')
assert_true(
	blaze_provider.status_snapshot().owned_geo_blaze_enhanced,
	'Blaze-created luopan must retain enhanced identity'
)

local replacement_config = base_config()
replacement_config.luopan.use_blaze_of_glory = true
local replacement_abilities = {
	['Blaze of Glory'] = false,
}
local replacement_provider = new_provider({}, { active = false }, replacement_abilities)
local replacement_ctx = context(replacement_config)
action = collect_one(replacement_provider, replacement_ctx)
assert_equal(
	action.action_name,
	'Geo-Frailty',
	'missing luopan must be replaced normally while Blaze is unavailable'
)
replacement_provider.note_dispatch(action, 1.1)
replacement_ctx.now = 2.0
mark_luopan(replacement_ctx, 301, 100, 10, 20)
action = collect_one(replacement_provider, replacement_ctx)
assert_equal(action.action_name, 'Indi-Haste', 'normal luopan replacement must continue to Indi')
replacement_provider.note_dispatch(action, 2.1)
replacement_ctx.now = 3.0
replacement_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
local replacement_out = {}
replacement_provider.collect(replacement_ctx, replacement_out)
assert_equal(#replacement_out, 0, 'normal luopan must remain while Blaze is unavailable')
assert_equal(
	replacement_provider.status_snapshot().owned_geo_blaze_enhanced,
	false,
	'normal luopan must not be marked Blaze-enhanced'
)

replacement_abilities['Blaze of Glory'] = true
replacement_ctx.now = 4.0
action = collect_one(replacement_provider, replacement_ctx)
assert_equal(action.action_name, 'Full Circle', 'ready Blaze must begin by releasing the normal luopan')
replacement_provider.note_dispatch(action, 4.1)
replacement_ctx.now = 5.0
replacement_ctx.pet_present = false
replacement_ctx.pet_id = 0
replacement_ctx.pet = {}
action = collect_one(replacement_provider, replacement_ctx)
assert_equal(action.action_name, 'Blaze of Glory', 'released normal luopan must advance to Blaze')
replacement_provider.note_dispatch(action, 5.1)
replacement_ctx.now = 6.0
replacement_ctx.player.buffs = {
	geo_maintenance.INDI_COLURE_BUFF_ID,
	geo_maintenance.BLAZE_OF_GLORY_BUFF_ID,
}
action = collect_one(replacement_provider, replacement_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'consumed Blaze must advance to replacement Geo')
replacement_provider.note_dispatch(action, 6.1)
replacement_ctx.now = 7.0
mark_luopan(replacement_ctx, 302, 100, 10, 20)
replacement_out = {}
replacement_provider.collect(replacement_ctx, replacement_out)
assert_equal(#replacement_out, 0, 'enhanced replacement must converge')
assert_true(
	replacement_provider.status_snapshot().owned_geo_blaze_enhanced,
	'upgraded luopan must be marked Blaze-enhanced'
)

replacement_abilities['Blaze of Glory'] = false
replacement_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
replacement_ctx.pet_present = false
replacement_ctx.pet_id = 0
replacement_ctx.pet = {}
replacement_ctx.now = 8.0
action = collect_one(replacement_provider, replacement_ctx)
assert_equal(
	action.action_name,
	'Geo-Frailty',
	'expired enhanced luopan must be replaced normally while Blaze is unavailable'
)

local ecliptic_config = base_config()
ecliptic_config.luopan.use_blaze_of_glory = true
ecliptic_config.luopan.use_ecliptic_attrition = true
local ecliptic_pull_state = { active = false }
local ecliptic_abilities = {
	['Ecliptic Attrition'] = false,
}
local ecliptic_provider = new_provider({}, ecliptic_pull_state, ecliptic_abilities)
local ecliptic_ctx = context(ecliptic_config)
action = collect_one(ecliptic_provider, ecliptic_ctx)
ecliptic_provider.note_dispatch(action, 1.1)
ecliptic_ctx.now = 2.0
ecliptic_ctx.player.buffs = { geo_maintenance.BLAZE_OF_GLORY_BUFF_ID }
action = collect_one(ecliptic_provider, ecliptic_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'Ecliptic sequence must create the enhanced luopan first')
ecliptic_provider.note_dispatch(action, 2.1)
ecliptic_ctx.now = 3.0
mark_luopan(ecliptic_ctx, 305, 100, 10, 20)
action = collect_one(ecliptic_provider, ecliptic_ctx)
assert_equal(action.action_name, 'Indi-Haste',
	'Ecliptic on recast must not block missing core Indi')
assert_equal(
	ecliptic_provider.status_snapshot().sequence,
	nil,
	'unavailable Ecliptic follow-up must not retain sequence ownership'
)
ecliptic_provider.note_dispatch(action, 3.1)
ecliptic_ctx.now = 4.0
ecliptic_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
local ecliptic_out = {}
ecliptic_provider.collect(ecliptic_ctx, ecliptic_out)
assert_equal(#ecliptic_out, 0, 'Ecliptic on recast must remain opportunistic')
assert_equal(ecliptic_provider.status.state, 'ja_blocked', 'Ecliptic recast blocker state mismatch')
assert_equal(ecliptic_provider.status.detail, 'recast', 'Ecliptic recast blocker detail mismatch')
assert_equal(ecliptic_provider.status_snapshot().sequence, nil,
	'Ecliptic on recast must not create a persistent sequence')
ecliptic_pull_state.active = true
ecliptic_ctx.now = 4.2
ecliptic_out = {}
ecliptic_provider.collect(ecliptic_ctx, ecliptic_out)
assert_equal(#ecliptic_out, 0, 'active pull must defer optional Ecliptic work')
assert_equal(ecliptic_provider.status.state, 'blocked', 'active-pull optional hold state mismatch')
assert_equal(ecliptic_provider.status.detail, 'pull_active', 'active-pull optional hold detail mismatch')
assert_equal(ecliptic_provider.status_snapshot().sequence, nil,
	'pull deferral must not retain unavailable Ecliptic state')
ecliptic_pull_state.active = false
ecliptic_abilities['Ecliptic Attrition'] = true
ecliptic_ctx.now = 5.0
action = collect_one(ecliptic_provider, ecliptic_ctx)
assert_equal(action.action_name, 'Ecliptic Attrition', 'ready Ecliptic must resume after cooldown and pulling clear')
assert_equal(ecliptic_provider.lane_reserved(), false, 'ready Ecliptic proposal must remain non-atomic')
ecliptic_provider.note_dispatch(action, 5.1)
local completed, completion_reason = ecliptic_provider.note_ja_action({
	actor_id = 999,
	category = 6,
	param = 1000,
	targets = {
		{ id = 305 },
	},
}, ecliptic_ctx.player_id)
assert_equal(completed, false, 'another actor must not complete the pending GEO ability')
assert_equal(completion_reason, 'geo_ja_actor_mismatch', 'GEO JA actor mismatch reason')
completed, completion_reason = ecliptic_provider.note_ja_action({
	actor_id = ecliptic_ctx.player_id,
	category = 4,
	param = 1000,
	targets = {
		{ id = 305 },
	},
}, ecliptic_ctx.player_id)
assert_equal(completed, false, 'a spell packet must not complete the pending GEO ability')
assert_equal(completion_reason, 'geo_ja_category_mismatch', 'GEO JA category mismatch reason')
completed, completion_reason = ecliptic_provider.note_ja_action({
	actor_id = ecliptic_ctx.player_id,
	category = 6,
	param = 999,
	targets = {
		{ id = 305 },
	},
}, ecliptic_ctx.player_id)
assert_equal(completed, false, 'a different job ability must not complete Ecliptic Attrition')
assert_equal(completion_reason, 'geo_ja_action_mismatch', 'GEO JA identity mismatch reason')
completed, completion_reason = ecliptic_provider.note_ja_action({
	actor_id = ecliptic_ctx.player_id,
	category = 6,
	param = 1000,
	targets = {
		{ id = 305 },
	},
}, ecliptic_ctx.player_id)
assert_equal(completed, true, 'exact Ecliptic action identity must complete despite its luopan target')
assert_equal(completion_reason, 'geo_ja_action_identity', 'GEO JA completion reason mismatch')
assert_equal(ecliptic_provider.lane_reserved(), false, 'Ecliptic completion must leave the GEO lane released')
ecliptic_ctx.now = 6.0
action = collect_one(ecliptic_provider, ecliptic_ctx)
assert_equal(action.action_name, 'Indi-Haste', 'Ecliptic completion must advance ordinary maintenance')

local no_target_config = base_config()
no_target_config.luopan.use_blaze_of_glory = true
local no_target_provider = new_provider({}, { active = false })
local no_target_ctx = context(no_target_config)
no_target_ctx.mobs_by_id[200].hpp = 0
local no_target_out = {}
no_target_provider.collect(no_target_ctx, no_target_out)
assert_equal(#no_target_out, 0, 'Blaze must not start without a tracked live enemy')
assert_equal(no_target_provider.status.reason, 'GEO_TARGET_UNAVAILABLE', 'missing fight target reason mismatch')
assert_equal(no_target_provider.lane_reserved(), false, 'unstarted Blaze sequence must not reserve the lane')
assert_equal(
	no_target_provider.creation_preempts_pull(no_target_ctx),
	false,
	'Luopan recovery must not block pulling when no legal Geo target exists'
)

local party_members = {
	{
		id = 101,
		name = 'Tank',
		buffs = {},
	},
}
local entrust_config = base_config()
entrust_config.entrust.enabled = true
entrust_config.entrust.spell = 'Indi-Fury'
entrust_config.entrust.target_name = 'Tank'
local entrust_provider = new_provider(party_members, { active = false })
local entrust_ctx = context(entrust_config)
action = collect_one(entrust_provider, entrust_ctx)
entrust_provider.note_dispatch(action, 1.1)
entrust_ctx.now = 2.0
mark_luopan(entrust_ctx, 310, 100, 10, 20)
action = collect_one(entrust_provider, entrust_ctx)
entrust_provider.note_dispatch(action, 2.1)
entrust_ctx.now = 3.0
entrust_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
entrust_ctx.mobs_by_id[101] = {
	id = 101,
	distance = 16,
}
action = collect_one(entrust_provider, entrust_ctx)
assert_equal(action.action_name, 'Entrust', 'converged base effects must begin Entrust')
entrust_provider.note_dispatch(action, 3.1)
entrust_ctx.now = 4.0
entrust_ctx.player.buffs = {
	geo_maintenance.INDI_COLURE_BUFF_ID,
	geo_maintenance.ENTRUST_BUFF_ID,
}
action = collect_one(entrust_provider, entrust_ctx)
assert_equal(action.action_name, 'Indi-Fury', 'Entrust buff must advance to configured Indi')
assert_equal(action.target_id, 101, 'Entrust spell target mismatch')
assert_true(entrust_provider.lane_reserved(), 'consumed Entrust must reserve atomic GEO lane')
entrust_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
local entrust_valid, entrust_reason = entrust_provider.revalidate(action, entrust_ctx)
assert_equal(entrust_valid, false, 'Entrust spell commit must fail without the Entrust buff')
assert_equal(entrust_reason, 'entrust_buff_missing', 'missing Entrust buff rejection mismatch')
entrust_ctx.player.buffs = {
	geo_maintenance.INDI_COLURE_BUFF_ID,
	geo_maintenance.ENTRUST_BUFF_ID,
}
entrust_valid, entrust_reason = entrust_provider.revalidate(action, entrust_ctx)
assert_equal(entrust_valid, true, 'Entrust spell commit must remain valid while Entrust is active')
entrust_provider.note_dispatch(action, 4.1)
entrust_ctx.now = 5.0
party_members[1].buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
local out = {}
entrust_provider.collect(entrust_ctx, out)
assert_equal(#out, 0, 'observed entrusted Indi must finish sequence')
assert_equal(entrust_provider.status.state, 'converged', 'Entrust convergence state mismatch')
assert_equal(entrust_provider.lane_reserved(), false, 'completed Entrust must release lane')

local entrust_cooldown_members = {
	{
		id = 111,
		name = 'EntrustCooldownTank',
		buffs = {},
	},
}
local entrust_cooldown_config = base_config()
entrust_cooldown_config.entrust.enabled = true
entrust_cooldown_config.entrust.spell = 'Indi-Fury'
entrust_cooldown_config.entrust.target_name = 'EntrustCooldownTank'
local entrust_cooldown_abilities = {
	Entrust = false,
}
local entrust_cooldown_provider = new_provider(
	entrust_cooldown_members,
	{ active = false },
	entrust_cooldown_abilities
)
local entrust_cooldown_ctx = context(entrust_cooldown_config)
entrust_cooldown_ctx.mobs_by_id[111] = { id = 111, distance = 16 }
action = collect_one(entrust_cooldown_provider, entrust_cooldown_ctx)
entrust_cooldown_provider.note_dispatch(action, 1.1)
entrust_cooldown_ctx.now = 2.0
mark_luopan(entrust_cooldown_ctx, 311, 100, 10, 20)
action = collect_one(entrust_cooldown_provider, entrust_cooldown_ctx)
entrust_cooldown_provider.note_dispatch(action, 2.1)
entrust_cooldown_ctx.now = 3.0
entrust_cooldown_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
local entrust_cooldown_out = {}
entrust_cooldown_provider.collect(entrust_cooldown_ctx, entrust_cooldown_out)
assert_equal(#entrust_cooldown_out, 0, 'Entrust on cooldown must remain opportunistic')
assert_equal(entrust_cooldown_provider.status_snapshot().sequence, nil,
	'Entrust on cooldown must not create a persistent sequence')
entrust_cooldown_ctx.now = 3.2
entrust_cooldown_ctx.pet_present = false
entrust_cooldown_ctx.pet_id = 0
entrust_cooldown_ctx.pet = {}
action = collect_one(entrust_cooldown_provider, entrust_cooldown_ctx)
assert_equal(action.action_name, 'Geo-Frailty',
	'Entrust cooldown must never block missing-Luopan recovery')
assert_equal(action.priority_band, 240,
	'Entrust cooldown recovery must retain GEO creation priority')

local stale_entrust_members = {
	{
		id = 112,
		name = 'StaleEntrustTank',
		buffs = {},
	},
}
local stale_entrust_config = base_config()
stale_entrust_config.entrust.enabled = true
stale_entrust_config.entrust.spell = 'Indi-Fury'
stale_entrust_config.entrust.target_name = 'StaleEntrustTank'
local stale_entrust_provider = new_provider(stale_entrust_members, { active = false }, {})
local stale_entrust_ctx = context(stale_entrust_config)
stale_entrust_ctx.mobs_by_id[112] = { id = 112, distance = 16 }
action = collect_one(stale_entrust_provider, stale_entrust_ctx)
stale_entrust_provider.note_dispatch(action, 1.1)
stale_entrust_ctx.now = 2.0
mark_luopan(stale_entrust_ctx, 312, 100, 10, 20)
action = collect_one(stale_entrust_provider, stale_entrust_ctx)
stale_entrust_provider.note_dispatch(action, 2.1)
stale_entrust_ctx.now = 3.0
stale_entrust_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
action = collect_one(stale_entrust_provider, stale_entrust_ctx)
assert_equal(action.action_name, 'Entrust', 'stale Entrust setup must admit the optional JA')
assert_equal(stale_entrust_provider.status_snapshot().sequence.step, 'entrust_ja',
	'stale Entrust setup sequence mismatch')
stale_entrust_ctx.now = 3.2
stale_entrust_ctx.pet_present = false
stale_entrust_ctx.pet_id = 0
stale_entrust_ctx.pet = {}
action = collect_one(stale_entrust_provider, stale_entrust_ctx)
assert_equal(action.action_name, 'Geo-Frailty',
	'missing Luopan must preempt an undispatched Entrust sequence')
assert_true(
	stale_entrust_provider.status_snapshot().sequence == nil
		or stale_entrust_provider.status_snapshot().sequence.kind == 'geo_create',
	'core recovery must remove unrelated Entrust sequence ownership'
)

local entrust_spell_members = {
	{
		id = 113,
		name = 'EntrustSpellTank',
		buffs = {},
	},
}
local entrust_spell_config = base_config()
entrust_spell_config.entrust.enabled = true
entrust_spell_config.entrust.spell = 'Indi-Fury'
entrust_spell_config.entrust.target_name = 'EntrustSpellTank'
local entrust_spell_abilities = {
	['Indi-Fury'] = false,
}
local entrust_spell_provider = new_provider(
	entrust_spell_members,
	{ active = false },
	entrust_spell_abilities
)
local entrust_spell_ctx = context(entrust_spell_config)
entrust_spell_ctx.mobs_by_id[113] = { id = 113, distance = 16 }
action = collect_one(entrust_spell_provider, entrust_spell_ctx)
entrust_spell_provider.note_dispatch(action, 1.1)
entrust_spell_ctx.now = 2.0
mark_luopan(entrust_spell_ctx, 313, 100, 10, 20)
action = collect_one(entrust_spell_provider, entrust_spell_ctx)
entrust_spell_provider.note_dispatch(action, 2.1)
entrust_spell_ctx.now = 3.0
entrust_spell_ctx.player.buffs = {
	geo_maintenance.INDI_COLURE_BUFF_ID,
	geo_maintenance.ENTRUST_BUFF_ID,
}
local entrust_spell_out = {}
entrust_spell_provider.collect(entrust_spell_ctx, entrust_spell_out)
assert_equal(#entrust_spell_out, 0,
	'unavailable entrusted Indi must not emit a proposal')
assert_equal(entrust_spell_provider.status_snapshot().sequence, nil,
	'unavailable entrusted Indi must relinquish optional sequence ownership')
entrust_spell_abilities['Indi-Fury'] = true
entrust_spell_ctx.now = 3.2
action = collect_one(entrust_spell_provider, entrust_spell_ctx)
assert_equal(action.action_name, 'Indi-Fury',
	'active Entrust buff must retry the entrusted spell without recasting Entrust')

local pull_state = { active = true }
local pull_provider = new_provider({}, pull_state)
local pull_ctx = context(base_config())
out = {}
pull_provider.collect(pull_ctx, out)
assert_equal(#out, 1, 'active pull must admit missing-Luopan recovery')
assert_equal(out[1].action_name, 'Geo-Frailty', 'missing-Luopan recovery action mismatch')
assert_equal(out[1].priority_band, 240, 'missing-Luopan recovery priority mismatch')
assert_true(pull_provider.creation_preempts_pull(pull_ctx), 'ready Luopan recovery must preempt pulling')

local pull_indi_first_config = base_config()
pull_indi_first_config.ordering = 'indi_first'
local pull_indi_first_provider = new_provider({}, pull_state)
local pull_indi_first_ctx = context(pull_indi_first_config)
action = collect_one(pull_indi_first_provider, pull_indi_first_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'pull preemption must restore the Luopan before routine Indi')

local pull_blaze_config = base_config()
pull_blaze_config.luopan.use_blaze_of_glory = true
local pull_blaze_provider = new_provider({}, pull_state)
local pull_blaze_ctx = context(pull_blaze_config)
action = collect_one(pull_blaze_provider, pull_blaze_ctx)
assert_equal(action.action_name, 'Blaze of Glory', 'ready Blaze must begin recovery during a pull')
assert_equal(action.priority_band, 240, 'Blaze creation priority mismatch')

local failed_target_provider = new_provider({}, { active = false })
local failed_target_ctx = context(base_config())
local alternate_target = {
	id = 201,
	name = 'Apex Crab',
	hpp = 100,
	distance = 36,
	x = 11,
	y = 20,
	valid_target = true,
	spawn_type = 16,
	claim_id = 900,
}
failed_target_ctx.mob_array[#failed_target_ctx.mob_array + 1] = alternate_target
failed_target_ctx.mobs_by_id[alternate_target.id] = alternate_target
action = collect_one(failed_target_provider, failed_target_ctx)
assert_equal(action.target_id, 200, 'initial Geo target mismatch')
failed_target_provider.note_dispatch(action, 1.1)
assert_true(failed_target_provider.note_failure(action.action_name, 1.2), 'Geo failure must be accepted')
failed_target_ctx.now = 1.3
action = collect_one(failed_target_provider, failed_target_ctx)
assert_equal(action.target_id, 201, 'failed Geo target must be invalidated before retry')

local lowest_hpp_provider = new_provider({}, { active = false })
local lowest_hpp_ctx = context(base_config())
lowest_hpp_ctx.mobs_by_id[200].hpp = 70
local low_hpp_target = {
	id = 202,
	name = 'Apex Low HP',
	hpp = 25,
	distance = 36,
	x = 11,
	y = 20,
	valid_target = true,
	spawn_type = 16,
	claim_id = 900,
}
lowest_hpp_ctx.mob_array[#lowest_hpp_ctx.mob_array + 1] = low_hpp_target
lowest_hpp_ctx.mobs_by_id[low_hpp_target.id] = low_hpp_target
action = collect_one(lowest_hpp_provider, lowest_hpp_ctx)
assert_equal(action.target_id, low_hpp_target.id, 'enemy-targeted Geo must select the lowest-HPP claimed mob')

local distant_target_provider = new_provider({}, { active = false })
local distant_target_ctx = context(base_config())
distant_target_ctx.mobs_by_id[200].x = 16.1
action = collect_one(distant_target_provider, distant_target_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'default policy must continue to allow distant enemy Geo')

local camp_target_config = base_config()
camp_target_config.enemy_geo_requires_camp_radius = true
local camp_target_provider = new_provider({}, { active = false })
local camp_target_ctx = context(camp_target_config)
camp_target_ctx.mobs_by_id[200].x = 16.1
out = {}
camp_target_provider.collect(camp_target_ctx, out)
assert_equal(#out, 0, 'camp-restricted enemy Geo must wait outside the configured radius')
assert_equal(
	camp_target_provider.status.reason,
	'GEO_ENEMY_OUTSIDE_CAMP_RADIUS',
	'outside-camp enemy Geo hold reason mismatch'
)
camp_target_ctx.now = 2.0
camp_target_ctx.mobs_by_id[200].x = 16.0
action = collect_one(camp_target_provider, camp_target_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'enemy at the camp-radius boundary must admit Geo')
camp_target_ctx.mobs_by_id[200].x = 16.1
local camp_target_valid, camp_target_reason = camp_target_provider.revalidate(action, camp_target_ctx)
assert_equal(camp_target_valid, false, 'enemy leaving camp radius before dispatch must reject Geo')
assert_equal(camp_target_reason, 'enemy_outside_camp_radius', 'Geo revalidation camp-radius reason mismatch')

local atomic_camp_config = base_config()
atomic_camp_config.enemy_geo_requires_camp_radius = true
atomic_camp_config.luopan.use_blaze_of_glory = true
local atomic_camp_provider = new_provider({}, { active = false })
local atomic_camp_ctx = context(atomic_camp_config)
atomic_camp_ctx.mobs_by_id[200].x = 16.1
out = {}
atomic_camp_provider.collect(atomic_camp_ctx, out)
assert_equal(#out, 0, 'Blaze must not start while its enemy is outside the camp radius')
atomic_camp_ctx.now = 2.0
atomic_camp_ctx.mobs_by_id[200].x = 16.0
action = collect_one(atomic_camp_provider, atomic_camp_ctx)
assert_equal(action.action_name, 'Blaze of Glory', 'inside-camp enemy must admit Blaze preparation')
atomic_camp_provider.note_dispatch(action, 2.1)
atomic_camp_ctx.now = 3.0
atomic_camp_ctx.player.buffs = { geo_maintenance.BLAZE_OF_GLORY_BUFF_ID }
atomic_camp_ctx.mobs_by_id[200].x = 16.1
out = {}
atomic_camp_provider.collect(atomic_camp_ctx, out)
assert_equal(#out, 0, 'consumed Blaze sequence must wait when its enemy leaves the camp radius')
assert_true(atomic_camp_provider.lane_reserved(), 'consumed Blaze must retain its atomic lane while waiting')
assert_true(
	atomic_camp_provider.pull_for_enemy_allowed(),
	'atomic Geo wait outside camp radius must admit camp pulling'
)
atomic_camp_ctx.now = 4.0
atomic_camp_ctx.mobs_by_id[200].x = 16.0
action = collect_one(atomic_camp_provider, atomic_camp_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'atomic Geo must resume after its enemy enters camp radius')

local radius_provider = new_provider({}, { active = false })
local radius_ctx = context(base_config())
action = collect_one(radius_provider, radius_ctx)
radius_provider.note_dispatch(action, 1.1)
radius_ctx.now = 2.0
mark_luopan(radius_ctx, 315, 100, 10, 20)
action = collect_one(radius_provider, radius_ctx)
assert_equal(action.action_name, 'Indi-Haste', 'radius scenario must establish base GEO effects')
radius_provider.note_dispatch(action, 2.1)
radius_ctx.now = 3.0
radius_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
radius_ctx.mobs_by_id[200].x = 16.5
out = {}
radius_provider.collect(radius_ctx, out)
assert_equal(#out, 0, 'enemy at the 6.5-yalm boundary must remain covered')
radius_ctx.now = 4.0
radius_ctx.mobs_by_id[200].x = 16.6
action = collect_one(radius_provider, radius_ctx)
assert_equal(action.action_name, 'Full Circle', 'enemy outside the luopan radius must dismiss the luopan')
assert_equal(action.priority_band, 240, 'radius-driven Full Circle must use creation priority')
assert_true(not radius_provider.lane_reserved(), 'replacement must not reserve the lane before luopan dismissal')
radius_provider.note_dispatch(action, 4.1)
radius_ctx.now = 5.0
radius_ctx.pet_present = false
radius_ctx.pet_id = 0
radius_ctx.pet = {}
action = collect_one(radius_provider, radius_ctx)
assert_equal(action.action_name, 'Geo-Frailty', 'dismissed out-of-range luopan must be recast')
assert_equal(action.target_id, 200, 'replacement Geo must target the current lowest-HPP claimed mob')
assert_equal(action.priority_band, 240, 'replacement Geo must retain creation priority')
assert_true(not radius_provider.lane_reserved(), 'reposition must preserve emergency scheduler preemption')

local life_config = base_config()
life_config.luopan.use_life_cycle = true
local life_provider = new_provider({}, { active = false })
local life_ctx = context(life_config)
action = collect_one(life_provider, life_ctx)
life_provider.note_dispatch(action, 1.1)
life_ctx.now = 2.0
mark_luopan(life_ctx, 320, 40, 10, 20)
action = collect_one(life_provider, life_ctx)
life_provider.note_dispatch(action, 2.1)
life_ctx.now = 3.0
life_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
action = collect_one(life_provider, life_ctx)
assert_equal(action.action_name, 'Life Cycle', 'low luopan HPP must propose Life Cycle')

local placement_config = base_config()
placement_config.luopan.placement = 'camp'
placement_config.luopan.replace_out_of_position = true
local placement_provider = new_provider({}, { active = false })
local placement_ctx = context(placement_config)
action = collect_one(placement_provider, placement_ctx)
placement_provider.note_dispatch(action, 1.1)
placement_ctx.now = 2.0
mark_luopan(placement_ctx, 330, 100, 10, 20)
action = collect_one(placement_provider, placement_ctx)
placement_provider.note_dispatch(action, 2.1)
placement_ctx.now = 3.0
placement_ctx.player.buffs = { geo_maintenance.INDI_COLURE_BUFF_ID }
placement_ctx.pet.x = 20
action = collect_one(placement_provider, placement_ctx)
assert_equal(action.action_name, 'Full Circle', 'misplaced owned luopan must be replaced through Full Circle')

local ok, message = placement_provider.arm_bolster(true)
assert_true(ok, 'Bolster arm command failed')
assert_equal(message, 'GEO_BOLSTER_ARMED', 'Bolster arm result mismatch')
assert_true(placement_provider.status_snapshot().bolster_armed, 'Bolster arm state missing')
placement_provider.reseed()
assert_equal(placement_provider.status_snapshot().owned_geo_spell, nil, 'reseed must clear GEO identity')
placement_provider.reset('GEO_ZONE_CHANGE')
assert_true(not placement_provider.runtime_active(), 'zone reset must clear GEO sequence and arm state')
assert_true(not placement_provider.status_snapshot().bolster_armed, 'zone reset must disarm Bolster')

local scheduler_file = assert(io.open('unified_scheduler.lua', 'rb'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(
	scheduler_source:find(
		'local pull_for_enemy = scheduler.providers.geo_maintenance.pull_for_enemy_allowed()',
		1,
		true
	) ~= nil,
	'atomic GEO lane must query its explicit pull-admission state'
)
assert_true(
	scheduler_source:find(
		'local critical_cure = scheduler.p1_is_critical_defensive_proposal(',
		1,
		true
	) ~= nil,
	'atomic GEO lane must classify critical Cure proposals'
)
assert_true(
	scheduler_source:find('local allowed = critical_cure', 1, true) ~= nil,
	'atomic GEO lane must admit critical Cure proposals'
)
assert_true(
	scheduler_source:find("or (pull_for_enemy and provider == 'camp_puller')", 1, true) ~= nil,
	'atomic enemy wait must continue admitting the camp puller'
)
assert_true(
	scheduler_source:find("or (not pull_for_enemy and provider == 'maintenance_geo')", 1, true) ~= nil,
	'atomic GEO cast readiness must admit only GEO maintenance'
)
assert_true(
	scheduler_source:find(
		'scheduler.providers.geo_maintenance.note_ja_action(act, my_id)',
		1,
		true
	) ~= nil,
	'scheduler must acknowledge GEO job abilities through exact action identity'
)

if original_engine == nil then
	rawset(_G, 'Start_Engine', nil)
else
	rawset(_G, 'Start_Engine', original_engine)
end

io.stdout:write('selftest_geo_sequences: OK\n')
