local res = require('resources')

local M = {}

local BOSS_NAME = 'Bygone Geomancer'
local LUOPAN_NAME = 'Luopan'
local PENDING_CAST_TTL_S = 5.0
local POSITION_MATCH_MAX_YALMS = 6.0
local POSITION_MATCH_MARGIN_YALMS = 0.75

local WEAKNESS_SPELLS = {
	['Geo-Poison'] = { 'Thunder' },
	['Geo-Fade'] = { 'Water' },
	['Geo-Malaise'] = { 'Stone' },
	['Geo-Vex'] = { 'Stone', 'Water', 'Blizzard' },
	['Geo-Languor'] = { 'Aero', 'Fire', 'Thunder' },
	['Geo-Slow'] = { 'Aero' },
	['Geo-Paralysis'] = { 'Fire' },
	['Geo-Gravity'] = { 'Blizzard' },
}

local function copy(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copy(item)
	end
	return out
end

local function emit(event_code, fields, key, interval)
	local logger = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(logger) == 'function' then
		logger(event_code, fields or {}, key, interval or 0)
	end
end

local function new_state()
	return {
		enabled = false,
		configured = false,
		phase = 'idle',
		error = '',
		boss = nil,
		player_id = 0,
		player_name = '',
		last_observed_at = 0,
		pending_casts = {},
		seen_luopans = {},
		luopans = {},
		unbound_luopans = {},
		destroyed_count = 0,
		last_transition = 'initial',
		last_reset_reason = 'initial',
	}
end

local state = new_state()

local function reset_combat(reason)
	local enabled = state.enabled
	local configured = state.configured
	state = new_state()
	state.enabled = enabled
	state.configured = configured
	state.phase = enabled and 'awaiting_boss' or 'idle'
	state.last_reset_reason = tostring(reason or '')
	state.last_transition = 'reset:' .. tostring(reason or '')
end

local function spell_name_from_action(act, category)
	local spell_id = 0
	if category == 8 then
		local target = type(act) == 'table' and type(act.targets) == 'table' and act.targets[1] or nil
		local action = target and type(target.actions) == 'table' and target.actions[1] or nil
		spell_id = tonumber(action and action.param) or 0
	elseif category == 4 then
		spell_id = tonumber(type(act) == 'table' and act.param) or 0
	end
	local spell = spell_id > 0 and res.spells and res.spells[spell_id] or nil
	return tostring(spell and spell.en or ''), spell_id
end

local function position_of(value)
	if type(value) ~= 'table' then
		return nil
	end
	local x = tonumber(value.x)
	local y = tonumber(value.y)
	if x == nil or y == nil then
		return nil
	end
	return { x = x, y = y, z = tonumber(value.z) }
end

local function distance(left, right)
	local a = position_of(left)
	local b = position_of(right)
	if a == nil or b == nil then
		return nil
	end
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function prune_pending(now)
	local kept = {}
	for i = 1, #state.pending_casts do
		local pending = state.pending_casts[i]
		if now - (tonumber(pending.started_at) or 0) <= PENDING_CAST_TTL_S then
			kept[#kept + 1] = pending
		else
			emit('SAVED_BELL_GEO_CAST_EXPIRED', {
				geo_spell = pending.geo_spell,
				started_at = pending.started_at,
			}, 'saved_bell_cast_expired:' .. tostring(pending.sequence or i), 0)
		end
	end
	state.pending_casts = kept
end

local function choose_pending_for_luopan(luopan)
	if #state.pending_casts == 0 then
		return nil
	end
	if #state.pending_casts == 1 then
		return 1
	end

	local scored = {}
	for i = 1, #state.pending_casts do
		local pending = state.pending_casts[i]
		local d = distance(luopan, pending.expected_position)
		if d ~= nil then
			scored[#scored + 1] = { index = i, distance = d }
		end
	end
	if #scored == 0 then
		return nil
	end
	table.sort(scored, function(left, right)
		if left.distance ~= right.distance then
			return left.distance < right.distance
		end
		return left.index < right.index
	end)
	local best = scored[1]
	if best.distance > POSITION_MATCH_MAX_YALMS then
		return nil
	end
	if scored[2] ~= nil and (scored[2].distance - best.distance) < POSITION_MATCH_MARGIN_YALMS then
		return nil
	end
	return best.index
end

local function bind_luopan(luopan, now)
	local pending_index = choose_pending_for_luopan(luopan)
	if pending_index == nil then
		state.unbound_luopans[tonumber(luopan.id) or 0] = {
			id = tonumber(luopan.id) or 0,
			first_seen_at = now,
			x = tonumber(luopan.x),
			y = tonumber(luopan.y),
			z = tonumber(luopan.z),
		}
		emit('SAVED_BELL_LUOPAN_UNBOUND', {
			luopan_id = tonumber(luopan.id) or 0,
			pending_casts = #state.pending_casts,
		}, 'saved_bell_unbound:' .. tostring(luopan.id), 0)
		return false
	end

	local pending = table.remove(state.pending_casts, pending_index)
	local id = tonumber(luopan.id) or 0
	state.luopans[id] = {
		id = id,
		name = LUOPAN_NAME,
		geo_spell = pending.geo_spell,
		weakness_spells = copy(WEAKNESS_SPELLS[pending.geo_spell]),
		bound_at = now,
		cast_started_at = pending.started_at,
		x = tonumber(luopan.x),
		y = tonumber(luopan.y),
		z = tonumber(luopan.z),
		hpp = tonumber(luopan.hpp),
		status = tonumber(luopan.status),
	}
	state.unbound_luopans[id] = nil
	state.last_transition = ('bound:%s:%d'):format(pending.geo_spell, id)
	emit('SAVED_BELL_LUOPAN_BOUND', {
		luopan_id = id,
		geo_spell = pending.geo_spell,
		weakness_spells = table.concat(WEAKNESS_SPELLS[pending.geo_spell] or {}, '|'),
		cast_started_at = pending.started_at,
		bound_at = now,
	}, 'saved_bell_bound:' .. tostring(id), 0)
	return true
end

function M.configure(config)
	if type(config) ~= 'table' then
		error('uc_saved_by_bell_encounter.configure requires config')
	end
	local should_enable = config.enabled == true and tostring(config.id or '') == 'saved_by_the_bell'
	if not should_enable then
		if state.enabled or state.configured then
			state.enabled = false
			state.configured = false
			reset_combat('encounter_disabled_or_changed')
		end
		return false, 'DISABLED'
	end
	if state.enabled ~= true or state.configured ~= true then
		state.enabled = true
		state.configured = true
		reset_combat('configuration_changed')
	end
	state.enabled = true
	state.configured = true
	return true, 'CONFIGURED'
end

function M.observe_snapshot(snapshot)
	if type(snapshot) ~= 'table' then
		error('uc_saved_by_bell_encounter.observe_snapshot requires snapshot')
	end
	if state.enabled ~= true then
		return false, 'DISABLED'
	end
	local now = tonumber(snapshot.now)
	if now == nil then
		error('Saved by the Bell snapshot requires now')
	end
	state.last_observed_at = now
	state.player_id = tonumber(snapshot.player_id) or 0
	state.player_name = tostring(snapshot.player_name or '')

	local boss = type(snapshot.boss) == 'table' and snapshot.boss or nil
	if boss == nil or tostring(boss.name or '') ~= BOSS_NAME or (tonumber(boss.id) or 0) <= 0 then
		if state.boss ~= nil or state.phase == 'active' then
			reset_combat('boss_missing')
			state.last_observed_at = now
			state.player_id = tonumber(snapshot.player_id) or 0
			state.player_name = tostring(snapshot.player_name or '')
		end
		return false, 'BOSS_NOT_PRESENT'
	end

	local boss_id = tonumber(boss.id) or 0
	if state.boss == nil or tonumber(state.boss.id) ~= boss_id then
		reset_combat('boss_appeared_or_changed')
		state.last_observed_at = now
		state.player_id = tonumber(snapshot.player_id) or 0
		state.player_name = tostring(snapshot.player_name or '')
		state.boss = copy(boss)
		state.phase = 'active'
		for _, luopan in ipairs(snapshot.luopans or {}) do
			local id = tonumber(luopan and luopan.id) or 0
			if id > 0 then
				state.seen_luopans[id] = true
				state.unbound_luopans[id] = {
					id = id,
					first_seen_at = now,
					x = tonumber(luopan.x),
					y = tonumber(luopan.y),
					z = tonumber(luopan.z),
				}
			end
		end
		state.last_transition = 'boss_active'
		emit('SAVED_BELL_BOSS_ACTIVE', {
			boss_id = boss_id,
			baseline_luopans = #(snapshot.luopans or {}),
		}, 'saved_bell_boss_active:' .. tostring(boss_id), 0)
		return true, 'BOSS_ACTIVE'
	end

	state.boss = copy(boss)
	state.phase = 'active'
	prune_pending(now)

	local current = {}
	local new_luopans = {}
	for _, luopan in ipairs(snapshot.luopans or {}) do
		local id = tonumber(luopan and luopan.id) or 0
		if id > 0 then
			current[id] = luopan
			if state.seen_luopans[id] ~= true then
				new_luopans[#new_luopans + 1] = luopan
				state.seen_luopans[id] = true
			end
			if type(state.luopans[id]) == 'table' then
				state.luopans[id].x = tonumber(luopan.x)
				state.luopans[id].y = tonumber(luopan.y)
				state.luopans[id].z = tonumber(luopan.z)
				state.luopans[id].hpp = tonumber(luopan.hpp)
				state.luopans[id].status = tonumber(luopan.status)
			end
		end
	end

	table.sort(new_luopans, function(left, right)
		return (tonumber(left.id) or 0) < (tonumber(right.id) or 0)
	end)
	for i = 1, #new_luopans do
		bind_luopan(new_luopans[i], now)
	end

	for id, luopan in pairs(state.luopans) do
		if current[id] == nil then
			state.luopans[id] = nil
			state.destroyed_count = state.destroyed_count + 1
			state.last_transition = ('luopan_gone:%d'):format(id)
			emit('SAVED_BELL_LUOPAN_GONE', {
				luopan_id = id,
				geo_spell = luopan.geo_spell,
				destroyed_count = state.destroyed_count,
			}, 'saved_bell_luopan_gone:' .. tostring(id), 0)
		end
	end
	for id in pairs(state.unbound_luopans) do
		if current[id] == nil then
			state.unbound_luopans[id] = nil
		end
	end
	for id in pairs(state.seen_luopans) do
		if current[id] == nil then
			state.seen_luopans[id] = nil
		end
	end

	return true, 'ACTIVE'
end

function M.on_action(act, now, context)
	if type(act) ~= 'table' then
		error('uc_saved_by_bell_encounter.on_action requires act')
	end
	if state.enabled ~= true or state.phase ~= 'active' or state.boss == nil then
		return false, 'NOT_ACTIVE'
	end
	local observed_at = tonumber(now)
	if observed_at == nil then
		error('Saved by the Bell action requires now')
	end
	local category = tonumber(act.category) or 0
	if category ~= 8 then
		return false, 'NOT_GEO_CAST_START'
	end
	local actor_id = tonumber(act.actor_id) or 0
	if actor_id ~= (tonumber(state.boss.id) or 0) then
		return false, 'NOT_BYGONE_GEOMANCER'
	end
	context = type(context) == 'table' and context or {}
	if tostring(context.actor_name or BOSS_NAME) ~= BOSS_NAME then
		return false, 'NOT_BYGONE_GEOMANCER'
	end
	local spell_name, spell_id = spell_name_from_action(act, category)
	if WEAKNESS_SPELLS[spell_name] == nil then
		return false, 'UNTRACKED_SPELL'
	end
	prune_pending(observed_at)
	local latest = state.pending_casts[#state.pending_casts]
	if latest and latest.geo_spell == spell_name
		and observed_at - (tonumber(latest.started_at) or 0) < 0.25 then
		return true, 'DUPLICATE_CAST_START'
	end
	local expected_position = position_of(context.target_position)
		or position_of(context.player_position)
	state.pending_casts[#state.pending_casts + 1] = {
		sequence = math.floor(observed_at * 1000),
		geo_spell = spell_name,
		spell_id = spell_id,
		started_at = observed_at,
		expected_position = expected_position,
	}
	state.last_transition = 'geo_cast:' .. spell_name
	emit('SAVED_BELL_GEO_CAST', {
		actor_id = actor_id,
		geo_spell = spell_name,
		spell_id = spell_id,
		pending_casts = #state.pending_casts,
		expected_x = expected_position and expected_position.x or '',
		expected_y = expected_position and expected_position.y or '',
	}, 'saved_bell_geo_cast:' .. tostring(math.floor(observed_at * 1000)), 0)
	return true, 'GEO_CAST_TRACKED'
end

function M.weakness_spells(geo_spell)
	return copy(WEAKNESS_SPELLS[tostring(geo_spell or '')] or {})
end

function M.snapshot()
	return copy(state)
end

function M.reset(reason)
	state = new_state()
	state.last_reset_reason = tostring(reason or '')
	state.last_transition = 'reset:' .. tostring(reason or '')
end

M.BOSS_NAME = BOSS_NAME
M.LUOPAN_NAME = LUOPAN_NAME
M.PENDING_CAST_TTL_S = PENDING_CAST_TTL_S
M.WEAKNESS_SPELLS = copy(WEAKNESS_SPELLS)

return M
