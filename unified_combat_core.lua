local function uc_now_s()
	local s = rawget(_G, 'socket')
	if type(s) ~= 'table' or type(s.gettime) ~= 'function' then
		local ok, mod = pcall(require, 'socket')
		if ok then
			s = mod
		end
	end
	if type(s) ~= 'table' or type(s.gettime) ~= 'function' then
		error('uc_now_s requires LuaSocket socket.gettime')
	end
	return s.gettime()
end

local res = require('resources')
local skills = require('skills')
local uc_ability_pipeline = require('uc_ability_pipeline')
local uc_ws_gate = require('uc_ws_gate')
local uc_ws_memory = require('uc_ws_memory')
local uc_ignore = require('uc_ignore')
local uc_target_ignore = require('uc_target_ignore')
local uc_partner_list = require('uc_partner_list')
local uc_fight_leader = require('uc_fight_leader')
local uc_add_control = require('uc_add_control')
local uc_targeting_common = require('uc_targeting_common')
local uc_settarget = require('uc_settarget')
local uc_attack = require('uc_attack')
local uc_path_hunter = require('uc_path_hunter')
local uc_skillchain_state = require('uc_skillchain_state')
local uc_camp_anchor = require('uc_camp_anchor')
local aftermath_table = dofile(windower.addon_path .. 'docs/aftermath_table.lua')

if type(os.clock) ~= 'function' then
	error('unified_combat_core requires monotonic os.clock for skillchain timing')
end

local function skillchain_telemetry(event_code, fields)
	local logger = rawget(_G, 'UC_ACTION_TIMELINE_LOG')
	if type(logger) == 'function' then
		logger(event_code, fields, nil, 0)
	end
end

local skillchain_runtime = uc_skillchain_state.new({
	now = os.clock,
	telemetry = skillchain_telemetry,
})

local core = {
	adapters = {},
	last_engine = '',
	resonating = skillchain_runtime.states,
	buffs = {},
	sticky_target_id = 0,
	sticky_hold_until = 0,
	last_player_status = 0,
	last_death_target_id = 0,
	last_death_at = 0,
	party_ws_hold_target_id = 0,
	party_ws_hold_actor_id = 0,
	party_ws_hold_until = 0,
	party_ws_hold_category = '',
	party_ws_hold_name = '',
	ja_lock_until = 0,
	ja_pending_name = '',
	ja_pending_recast_id = 0,
	ja_pending_sent_at = 0,
	ja_last_sent_at = {},
	ja_gate_log_at = {},
	chivalry_hold_until = 0,
	ws_intent_pending_target_id = 0,
	ws_intent_pending_name = '',
	ws_intent_pending_ready_at = 0,
	ws_intent_remote_target_id = 0,
	ws_intent_remote_name = '',
	ws_intent_remote_actor_id = 0,
	ws_intent_remote_until = 0,
	ws_intent_loser_cooldown_until = 0,
	ws_intent_loser_actor_id = 0,
	ws_hold_remote = {},
	spacing = {
		target_prev_x = nil,
		target_prev_y = nil,
		target_prev_t = nil,
		tick = 0,
	},
	hunter_acquire = {
		target_id = 0,
		started_at = 0,
	},
	hunter_ignore_until_by_id = {},
	pull_lock_until = 0,
	pull_pending_action = '',
	pull_pending_type = '',
	pull_pending_target_id = 0,
	pull_pending_sent_at = 0,
	pull_spell_waiting = false,
	pull_spell_wait_until = 0,
	pull_spell_halt_until = 0,
	pull_spell_settle_key = '',
	pull_spell_settle_until = 0,
	pull_last_sent_at = {},
	tank_spell_waiting = false,
	tank_spell_wait_until = 0,
	tank_spell_settle_key = '',
	tank_spell_settle_until = 0,
	tank_pending_action = '',
	tank_pending_type = '',
	tank_pending_target_id = 0,
	tank_pending_sent_at = 0,
	tank_last_sent_at = {},
	tank_debug_last_line = '',
	tank_debug_last_at = 0,
	tank_debug_last_violation_sig = '',
	tank_tick_log_at = 0,
	move_guard = {
		last_x = nil,
		last_y = nil,
		last_dist = nil,
		last_sample_at = 0,
		stuck_ticks = 0,
		recovery_active = false,
		recovery_dir = 1,
		recovery_hold_until = 0,
		recovery_flip_at = 0,
		recovery_flipped = false,
		recovery_until = 0,
		retreat_suppress_until = 0,
	},
}
local stop_run
local get_mover
local resolve_mob_current_target
local function set_preengage_approach_active(active)
	_G.UC_PREENGAGE_APPROACH_ACTIVE = (active == true)
end
local function set_movement_owner(owner, hold_s)
	_G.UC_MOVEMENT_OWNER = tostring(owner or 'none')
	local now = uc_now_s()
	local hold = tonumber(hold_s) or 0
	if hold > 0 then
		_G.UC_MOVEMENT_LOCK_UNTIL = now + hold
	else
		_G.UC_MOVEMENT_LOCK_UNTIL = now
	end
end

local function resolve_puller_id(settings)
	local puller_name = tostring((settings and settings.puller_name) or '')
	if puller_name ~= '' then
		local ffxi = windower and windower.ffxi
		if type(ffxi) == 'table' then
			local get_party = ffxi.get_party
			if type(get_party) == 'function' then
				local ok_party, party = pcall(get_party)
				if ok_party and type(party) == 'table' then
					for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
						local entry = party[key]
						local mob = entry and entry.mob
						if mob and type(mob.name) == 'string' and mob.name == puller_name then
							local mob_id = tonumber(mob.id) or 0
							if mob_id > 0 then
								return mob_id
							end
						end
					end
				end
			end
			local get_mob_by_name = ffxi.get_mob_by_name
			if type(get_mob_by_name) == 'function' then
				local ok_mob, mob = pcall(get_mob_by_name, puller_name)
				if ok_mob and mob then
					local mob_id = tonumber(mob.id) or 0
					if mob_id > 0 then
						return mob_id
					end
				end
			end
		end
	end
	return tonumber(settings and settings.puller_id) or 0
end

local skillchain_ids = {
	[288] = true, [289] = true, [290] = true, [291] = true, [292] = true, [293] = true, [294] = true, [295] = true,
	[296] = true, [297] = true, [298] = true, [299] = true, [300] = true, [301] = true, [385] = true, [386] = true,
	[387] = true, [388] = true, [389] = true, [390] = true, [391] = true, [392] = true, [393] = true, [394] = true,
	[395] = true, [396] = true, [397] = true, [767] = true, [768] = true, [769] = true, [770] = true,
}

local action_message_ids = {
	[110] = true, [185] = true, [187] = true, [317] = true, [802] = true,
}

local death_message_ids = {
	[6] = true, [20] = true, [113] = true, [406] = true, [605] = true, [646] = true,
}
local spell_success_message_ids = {
	[2] = true, [236] = true, [237] = true, [252] = true, [268] = true, [271] = true,
}
local spell_initiating_message_ids = {
	[3] = true, [43] = true, [326] = true, [327] = true, [675] = true, [716] = true,
}

local DEATH_SWITCH_WINDOW = 0.9
local PARTY_WS_HOLD_WINDOW = 1.6
local DEFAULT_MOVEMENT_MODEL_SIZE_FLOOR = 0.9
local CHIVALRY_MIN_TP = 2000
local CHIVALRY_MAX_MP_PCT = 50
local WS_INTENT_PREFIX = 'ucws_intent'
local WS_HOLD_PREFIX = 'ucws_hold'
local WS_INTENT_COMMIT_DELAY = 0.12
local WS_INTENT_REMOTE_HOLD = 0.9
local WS_INTENT_LOSER_COOLDOWN = 1.0

local action_categories = {
	weaponskill_finish = true,
	spell_finish = true,
	job_ability = true,
	mob_tp_finish = true,
	avatar_tp_finish = true,
	job_ability_unblinkable = true,
}

local buff_dur = { [163] = 40, [164] = 30, [470] = 60 }

local chainbound = {
	[1] = { 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' },
	[2] = { 'Gravitation', 'Fragmentation', 'Distortion', 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' },
	[3] = { 'Light', 'Darkness', 'Gravitation', 'Fragmentation', 'Distortion', 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' },
}

local function setting_enabled(v)
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function status_blocks_actions(status)
	return tonumber(status) == 3
end

local ws_incapacitating_buffs = {
	[2] = true,   -- Sleep
	[7] = true,   -- Petrification
	[10] = true,  -- Stun
	[14] = true,  -- Charm
	[16] = true,  -- Amnesia
	[17] = true,  -- Charm
	[19] = true,  -- Sleep
	[28] = true,  -- Terror
	[193] = true, -- Lullaby
}

local function ws_actor_has_incapacitating_buff(buff_ids)
	for _, buff_id in ipairs(buff_ids or {}) do
		if ws_incapacitating_buffs[tonumber(buff_id) or -1] == true then
			return true
		end
	end
	return false
end

local function party_follow_hold_seconds(settings)
	local n = tonumber(settings and settings.fight_follow_hold_s) or 8.0
	if n < 0 then
		n = 0
	elseif n > 60 then
		n = 60
	end
	return n
end

local function get_active_engine()
	return 'UC'
end

local function get_settings()
	return rawget(_G, 'UC_SETTINGS') or {}
end

local function split_pipe(s)
	if type(s) ~= 'string' or s == '' then
		return {}
	end
	local out = {}
	for part in s:gmatch('[^|]+') do
		local n = tostring(part):match('^%s*(.-)%s*$') or ''
		if n ~= '' then
			out[#out + 1] = n
		end
	end
	return out
end

local function list_has_name(list, name)
	local n = tostring(name or ''):lower()
	for _, v in ipairs(list or {}) do
		local probe = v
		if type(v) == 'table' then
			probe = v.key or v.name or ''
		end
		if tostring(probe or ''):lower() == n then
			return true
		end
	end
	return false
end

local function movement_model_size_floor(settings)
	local n = tonumber(settings and settings.spacing_model_size_floor)
	if n == nil then
		n = DEFAULT_MOVEMENT_MODEL_SIZE_FLOOR
	end
	if n < 0 then
		n = 0
	elseif n > 3 then
		n = 3
	end
	return n
end

local function get_current_target()
	return windower.ffxi.get_mob_by_target('t')
end

local function get_my_player_id()
	local p = windower.ffxi.get_player()
	return tonumber(p and p.id) or 0
end

local function ws_intent_clear_pending()
	core.ws_intent_pending_target_id = 0
	core.ws_intent_pending_name = ''
	core.ws_intent_pending_ready_at = 0
end

local function ws_intent_emit(ws_name, target_id)
	local my_id = get_my_player_id()
	local tid = tonumber(target_id) or 0
	local ws = tostring(ws_name or '')
	if my_id <= 0 or tid <= 0 or ws == '' then
		return false
	end
	-- IPC payload format: ucws_intent|actor_id|target_id|ws_name|clock
	-- ws_name in FFXI does not contain pipe characters.
	windower.send_ipc_message(('%s|%d|%d|%s|%.3f'):format(WS_INTENT_PREFIX, my_id, tid, ws, uc_now_s()))
	return true
end

local function ws_hold_emit(target_id, hold_until)
	local my_id = get_my_player_id()
	local tid = tonumber(target_id) or 0
	local until_ts = tonumber(hold_until) or 0
	if my_id <= 0 or tid <= 0 or until_ts <= 0 then
		return false
	end
	windower.send_ipc_message(('%s|%d|%d|%.3f|%.3f'):format(WS_HOLD_PREFIX, my_id, tid, until_ts, uc_now_s()))
	return true
end

local function ws_hold_remote_active_for(actor_id, target_id)
	local aid = tonumber(actor_id) or 0
	local tid = tonumber(target_id) or 0
	if aid == 0 or tid == 0 then
		return false
	end
	local entry = core.ws_hold_remote[aid]
	if type(entry) ~= 'table' then
		return false
	end
	local now = uc_now_s()
	local until_ts = tonumber(entry.until_ts) or 0
	if now >= until_ts then
		core.ws_hold_remote[aid] = nil
		return false
	end
	return (tonumber(entry.target_id) or 0) == tid
end

local function ws_intent_gate(settings, ws_name, target_id)
	if setting_enabled(settings and settings.solo) or setting_enabled(settings and settings.spam) then
		return true, 'WS_INTENT_BYPASS'
	end
	local now = uc_now_s()
	local my_id = get_my_player_id()
	local tid = tonumber(target_id) or 0
	local ws = tostring(ws_name or '')
	if tid <= 0 or ws == '' then
		return false, 'WS_INTENT_INVALID'
	end
	if now < (tonumber(core.ws_intent_loser_cooldown_until) or 0) then
		return false, ('WS_INTENT_COOLDOWN_LOST_TO:%d'):format(tonumber(core.ws_intent_loser_actor_id) or 0)
	end
	local remote_tid = tonumber(core.ws_intent_remote_target_id) or 0
	local remote_until = tonumber(core.ws_intent_remote_until) or 0
	local remote_ws = tostring(core.ws_intent_remote_name or '')
	if remote_tid == tid and now < remote_until and (remote_ws == '' or remote_ws == ws) then
		return false, ('WS_INTENT_WAIT_REMOTE:%d'):format(tonumber(core.ws_intent_remote_actor_id) or 0)
	end
	local pending_tid = tonumber(core.ws_intent_pending_target_id) or 0
	local pending_ws = tostring(core.ws_intent_pending_name or '')
	if pending_tid == tid and pending_ws == ws then
		if now < (tonumber(core.ws_intent_pending_ready_at) or 0) then
			return false, 'WS_INTENT_PENDING_COMMIT'
		end
		return true, 'WS_INTENT_COMMIT_OK'
	end
	if ws_intent_emit(ws, tid) then
		core.ws_intent_pending_target_id = tid
		core.ws_intent_pending_name = ws
		core.ws_intent_pending_ready_at = now + WS_INTENT_COMMIT_DELAY
		return false, 'WS_INTENT_BROADCAST'
	end
	return false, 'WS_INTENT_BROADCAST_FAIL'
end

local function path_sep()
	return package.config:sub(1, 1) == '\\' and '\\' or '/'
end

local function safe_char_name(name)
	local n = tostring(name or 'unknown'):lower():gsub('[^%w%-_]+', '_')
	if n == '' then
		n = 'unknown'
	end
	return n
end

local function ensure_log_dir()
	local ap = windower and windower.addon_path or nil
	if type(ap) ~= 'string' or ap == '' then
		return nil
	end
	local s = path_sep()
	local data_dir = ap .. 'data' .. s
	local log_dir = ap .. 'data' .. s .. 'logs' .. s
	if type(windower) == 'table' and windower.dir_exists and windower.create_dir then
		if not windower.dir_exists(data_dir) then
			windower.create_dir(data_dir)
		end
		if not windower.dir_exists(log_dir) then
			windower.create_dir(log_dir)
		end
	end
	return log_dir
end

local function debug_log_channel(channel, msg)
	local s = get_settings()
	if not setting_enabled(s and s.debug) then
		return
	end
	local line = tostring(msg or '')
	if tostring(channel or '') == 'ja_debug' then
		_G.UC_JA_LAST_DIAG = line
	end
	pcall(function()
		local p = windower.ffxi.get_player()
		local char = (p and p.name) or 'unknown'
		local dir = ensure_log_dir()
		if not dir then
			return
		end
		local suffix = tostring(channel or 'uc_debug')
		if suffix == '' then
			suffix = 'uc_debug'
		end
		local path = dir .. safe_char_name(char) .. '_' .. suffix .. '.log'
		local f = io.open(path, 'a')
		if not f then
			return
		end
		f:write(os.date('%Y-%m-%d %H:%M:%S'), '	', line:gsub('\r?\n', ' '), '\n')
		f:close()
	end)
end

local function debug_ja_dispatch(msg)
	debug_log_channel('ja_debug', msg)
end

_G.UC_LOG_DIAG = function(channel, msg)
	pcall(debug_log_channel, channel, msg)
end

local function debug_ja_gate(name, reason, extra)
	local now = uc_now_s()
	local key = tostring(name or '?') .. '|' .. tostring(reason or '?')
	local last = tonumber((core.ja_gate_log_at or {})[key]) or 0
	if (now - last) < 0.25 then
		return
	end
	core.ja_gate_log_at[key] = now
	local p = windower.ffxi.get_player() or {}
	local status = tonumber(p.status) or -1
	local lock_left = math.max(0, (tonumber(core.ja_lock_until) or 0) - now)
	local pending_name = tostring(core.ja_pending_name or '')
	local pending_age = 0
	local sent_at = tonumber(core.ja_pending_sent_at) or 0
	if sent_at > 0 then
		pending_age = now - sent_at
	end
	debug_ja_dispatch(('gate name=\"%s\" reason=%s status=%d lock_left=%.2f pending=\"%s\" pending_age=%.2f %s'):format(
		tostring(name or ''),
		tostring(reason or ''),
		status,
		lock_left,
		pending_name,
		pending_age,
		tostring(extra or '')
	))
end

local function is_party_member_id(id)
	return uc_targeting_common.is_friendly_party_or_alliance_member_id(id, {
		include_alliance = false,
	})
end

local function is_friendly_combat_member_id(id)
	return uc_targeting_common.is_friendly_party_or_alliance_member_id(id)
end

local function target_distance(mob)
	if not mob or mob.distance == nil then
		return 999
	end
	return mob.distance:sqrt()
end

local function target_real_distance(mob)
	if not mob then
		return 999
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or mob.distance == nil then
		return 999
	end
	return mob.distance:sqrt() - (mob.model_size or 0) - (me.model_size or 0)
end

local function movement_model_size_raw(mob)
	return tonumber(mob and mob.model_size) or 0
end

local function movement_target_model_size(mob, settings)
	local n = tonumber(mob and mob.model_size) or 0
	local floor = movement_model_size_floor(settings or get_settings())
	if n < floor then
		return floor
	end
	return n
end

local function target_real_distance_movement(mob, settings)
	if not mob then
		return 999
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or mob.distance == nil then
		return 999
	end
	return mob.distance:sqrt() - movement_target_model_size(mob, settings) - movement_model_size_raw(me)
end

local function mob_distance(a, b)
	if not a or not b or a.x == nil or a.y == nil or b.x == nil or b.y == nil then
		return 999
	end
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local PULLER_ENGAGE_RANGE_DEFAULT = 6.0

local function puller_engage_range(settings)
	local configured = tonumber(settings and settings.puller_engage_range)
	if configured == nil then
		configured = PULLER_ENGAGE_RANGE_DEFAULT
	end
	if configured < 0.1 then
		return 0.1
	end
	if configured > 50.0 then
		return 50.0
	end
	return configured
end

local function puller_engage_allowed(settings, target)
	local range = puller_engage_range(settings)
	if not setting_enabled(settings and settings.puller) then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_GATE_INACTIVE allowed=true max=%.2f'):format(range)
		return true, 'PULLER_GATE_INACTIVE', 0, range
	end
	local leash_source = settings and settings.puller_leash_source
	if leash_source == nil then
		leash_source = 'player'
	else
		leash_source = tostring(leash_source)
	end
	if leash_source == 'camp' then
		local camp, camp_reason = uc_camp_anchor.resolve_current_anchor()
		if not camp then
			_G.UC_PULLER_GATE_DIAG = ('reason=%s allowed=false source=camp max=%.2f'):format(
				tostring(camp_reason),
				range
			)
			return false, camp_reason, 999, range
		end
		if not target or target.x == nil or target.y == nil then
			_G.UC_PULLER_GATE_DIAG = ('reason=CAMP_GEOMETRY_UNAVAILABLE allowed=false source=camp target=%d max=%.2f'):format(
				tonumber(target and target.id) or 0,
				range
			)
			return false, 'CAMP_GEOMETRY_UNAVAILABLE', 999, range
		end
		local dist = mob_distance(target, camp)
		if dist <= range then
			_G.UC_PULLER_GATE_DIAG = ('reason=CAMP_IN_RANGE allowed=true source=camp setter=%s zone=%d target=%d dist=%.2f max=%.2f'):format(
				tostring(camp.set_by),
				tonumber(camp.zone_id),
				tonumber(target.id) or 0,
				dist,
				range
			)
			return true, 'CAMP_IN_RANGE', dist, range
		end
		if not setting_enabled(settings.puller_distance_only) and (tonumber(target and target.hpp) or 0) < 99 then
			_G.UC_PULLER_GATE_DIAG = ('reason=CAMP_HPP_BYPASS allowed=true source=camp setter=%s zone=%d target=%d hpp=%d dist=%.2f max=%.2f'):format(
				tostring(camp.set_by),
				tonumber(camp.zone_id),
				tonumber(target.id) or 0,
				tonumber(target.hpp) or 0,
				dist,
				range
			)
			return true, 'CAMP_HPP_BYPASS', dist, range
		end
		_G.UC_PULLER_GATE_DIAG = ('reason=CAMP_OUT_OF_RANGE allowed=false source=camp setter=%s zone=%d target=%d hpp=%d dist=%.2f max=%.2f'):format(
			tostring(camp.set_by),
			tonumber(camp.zone_id),
			tonumber(target.id) or 0,
			tonumber(target.hpp) or 0,
			dist,
			range
		)
		return false, 'CAMP_OUT_OF_RANGE', dist, range
	end
	if leash_source ~= 'player' then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_LEASH_SOURCE_INVALID allowed=false source=%s max=%.2f'):format(
			leash_source,
			range
		)
		return false, 'PULLER_LEASH_SOURCE_INVALID', 999, range
	end
	local puller_id = resolve_puller_id(settings)
	if puller_id <= 0 then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_UNRESOLVED allowed=false name=%s max=%.2f'):format(
			tostring(settings and settings.puller_name or ''),
			range
		)
		return false, 'PULLER_UNRESOLVED', 999, range
	end
	local puller = windower.ffxi.get_mob_by_id(puller_id)
	if not puller then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_UNAVAILABLE allowed=false name=%s id=%d max=%.2f'):format(
			tostring(settings and settings.puller_name or ''),
			puller_id,
			range
		)
		return false, 'PULLER_UNAVAILABLE', 999, range
	end
	if not target or target.x == nil or target.y == nil or puller.x == nil or puller.y == nil then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_GEOMETRY_UNAVAILABLE allowed=false name=%s id=%d target=%d max=%.2f'):format(
			tostring(settings and settings.puller_name or ''),
			puller_id,
			tonumber(target and target.id) or 0,
			range
		)
		return false, 'PULLER_GEOMETRY_UNAVAILABLE', 999, range
	end
	local dist = mob_distance(target, puller)
	if dist <= range then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_IN_RANGE allowed=true name=%s id=%d target=%d dist=%.2f max=%.2f'):format(
			tostring(settings and settings.puller_name or ''),
			puller_id,
			tonumber(target.id) or 0,
			dist,
			range
		)
		return true, 'PULLER_IN_RANGE', dist, range
	end
	if not setting_enabled(settings.puller_distance_only) and (tonumber(target and target.hpp) or 0) < 99 then
		_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_HPP_BYPASS allowed=true name=%s id=%d target=%d hpp=%d dist=%.2f max=%.2f'):format(
			tostring(settings and settings.puller_name or ''),
			puller_id,
			tonumber(target.id) or 0,
			tonumber(target.hpp) or 0,
			dist,
			range
		)
		return true, 'PULLER_HPP_BYPASS', dist, range
	end
	_G.UC_PULLER_GATE_DIAG = ('reason=PULLER_OUT_OF_RANGE allowed=false name=%s id=%d target=%d hpp=%d dist=%.2f max=%.2f'):format(
		tostring(settings and settings.puller_name or ''),
		puller_id,
		tonumber(target.id) or 0,
		tonumber(target.hpp) or 0,
		dist,
		range
	)
	return false, 'PULLER_OUT_OF_RANGE', dist, range
end

local function mob_real_distance(a, b)
	if not a or not b or a.x == nil or a.y == nil or b.x == nil or b.y == nil then
		return 999
	end
	local d = mob_distance(a, b)
	return d - (a.model_size or 0) - (b.model_size or 0)
end

local function mob_real_distance_movement(a, b, settings)
	if not a or not b or a.x == nil or a.y == nil or b.x == nil or b.y == nil then
		return 999
	end
	local d = mob_distance(a, b)
	return d - movement_model_size_raw(a) - movement_model_size_raw(b)
end

local function death_event_active_for_id(id, now)
	local tid = tonumber(id) or 0
	if tid <= 0 then
		return false
	end
	now = tonumber(now) or uc_now_s()
	return (tonumber(core.last_death_target_id) or 0) == tid and
		((now - (tonumber(core.last_death_at) or 0)) <= DEATH_SWITCH_WINDOW)
end

local function is_live_actionable_combat_target(mob_or_target, now, include_recent_death)
	if type(mob_or_target) ~= 'table' then
		return false
	end
	local tid = tonumber(mob_or_target.id) or 0
	if tid <= 0 then
		return false
	end
	if mob_or_target.valid_target ~= true then
		return false
	end
	if tonumber(mob_or_target.spawn_type) ~= 16 then
		return false
	end
	if mob_or_target.hpp == nil then
		return false
	end
	if (tonumber(mob_or_target.hpp) or 0) <= 0 then
		return false
	end
	if include_recent_death == true then
		now = tonumber(now) or uc_now_s()
		if death_event_active_for_id(tid, now) then
			return false
		end
	end
	return true
end

local function uc_heading_to(x, y)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or me.x == nil or me.y == nil or x == nil or y == nil then
		return nil
	end
	local dx = x - me.x
	local dy = y - me.y
	return (math.atan2(dx, dy) - 1.5708)
end

local function uc_heading_from_vector(vx, vy)
	if vx == nil or vy == nil then
		return nil
	end
	if (vx * vx + vy * vy) < 0.000001 then
		return nil
	end
	return (math.atan2(vx, vy) - 1.5708)
end

local SPACING_EPS = 1e-6

local function spacing_round(v)
	return math.floor((tonumber(v) or 0) * 10000 + 0.5) / 10000
end

local function spacing_dist_xy(ax, ay, bx, by)
	local dx = (ax or 0) - (bx or 0)
	local dy = (ay or 0) - (by or 0)
	return math.sqrt((dx * dx) + (dy * dy))
end

local function spacing_collect_agents(me, settings)
	local out = {}
	local party = windower.ffxi.get_party() or {}
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, k in ipairs(keys) do
		local e = party[k]
		local pm = e and e.mob
		local pid = pm and tonumber(pm.id) or 0
		if pid > 0 then
			local mob = windower.ffxi.get_mob_by_id(pid)
			if mob and mob.x ~= nil and mob.y ~= nil and (mob.hpp == nil or mob.hpp > 0) then
				local a = {
					id = pid,
					x = mob.x,
					y = mob.y,
					model = movement_model_size_raw(mob),
				}
				out[#out + 1] = a
			end
		end
	end
	local me_id = tonumber(me and me.id) or 0
	local me_present = false
	if me_id > 0 then
		for _, a in ipairs(out) do
			if tonumber(a.id) == me_id then
				me_present = true
				break
			end
		end
	end
	if me_id > 0 and (not me_present) and me.x ~= nil and me.y ~= nil then
		local a = {
			id = me_id,
			x = me.x,
			y = me.y,
			model = movement_model_size_raw(me),
		}
		out[#out + 1] = a
	end
	table.sort(out, function(a, b)
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)
	return out
end

local function spacing_predict_target(target, st, use_prediction, lookahead_s)
	local now = uc_now_s()
	local tx = tonumber(target and target.x) or 0
	local ty = tonumber(target and target.y) or 0
	local px, py = tx, ty
	if use_prediction and st.target_prev_x ~= nil and st.target_prev_y ~= nil and st.target_prev_t ~= nil then
		local dt = now - st.target_prev_t
		if dt > 0.01 and dt < 2.0 then
			local vx = (tx - st.target_prev_x) / dt
			local vy = (ty - st.target_prev_y) / dt
			px = tx + (vx * lookahead_s)
			py = ty + (vy * lookahead_s)
		end
	end
	st.target_prev_x = tx
	st.target_prev_y = ty
	st.target_prev_t = now
	return px, py
end

local function spacing_compute_band(target, agents, min_real, max_real, settings)
	local tmodel = movement_target_model_size(target, settings)
	local sum_model = 0
	local count = 0
	for _, a in ipairs(agents) do
		sum_model = sum_model + (tonumber(a.model) or 0)
		count = count + 1
	end
	local avg_model = (count > 0) and (sum_model / count) or 0.9
	local min_range = tmodel + avg_model + min_real
	local max_range = tmodel + avg_model + max_real
	if min_range < 0.1 then
		min_range = 0.1
	end
	if max_range <= min_range then
		max_range = min_range + 0.1
	end
	local preferred = (min_range + max_range) * 0.5
	local emergency_margin = math.max(0.1, (max_range - min_range) * 0.10)
	return min_range, max_range, preferred, emergency_margin
end

local function spacing_compute_heading(settings, me, target, min_real, max_real)
	local st = core.spacing or {}
	st.tick = (tonumber(st.tick) or 0) + 1
	core.spacing = st
	local use_prediction = setting_enabled(settings.spacing_use_prediction)
	local lookahead_s = tonumber(settings.spacing_lookahead_s) or 0.25
	if lookahead_s < 0 then
		lookahead_s = 0
	elseif lookahead_s > 1.5 then
		lookahead_s = 1.5
	end

	local band_dead = tonumber(settings.spacing_band_deadband) or 0.20
	if band_dead < 0.05 then
		band_dead = 0.05
	elseif band_dead > 1.0 then
		band_dead = 1.0
	end
	local repel_weight = tonumber(settings.spacing_repel_weight) or 0.35
	if repel_weight < 0.05 then
		repel_weight = 0.05
	elseif repel_weight > 1.5 then
		repel_weight = 1.5
	end
	local repel_deadband = tonumber(settings.spacing_overlap_deadband) or 0.10
	if repel_deadband < 0.05 then
		repel_deadband = 0.05
	elseif repel_deadband > 1.0 then
		repel_deadband = 1.0
	end
	local hold_s = tonumber(settings.spacing_repel_hold_ticks) or 5
	hold_s = hold_s * 0.04
	if hold_s < 0.08 then
		hold_s = 0.08
	elseif hold_s > 0.35 then
		hold_s = 0.35
	end

	local agents = spacing_collect_agents(me, settings)
	local local_id = tonumber(me and me.id) or 0
	if local_id <= 0 or #agents == 0 then
		return nil, 'HOLD_POSITION'
	end
	local tx, ty = spacing_predict_target(target, st, use_prediction, lookahead_s)
	local min_range, max_range, preferred_radius = spacing_compute_band(target, agents, min_real, max_real, settings)
	local mode = 'HOLD_POSITION'
	local dist_t = spacing_dist_xy(me.x, me.y, tx, ty)
	local rvx, rvy = 0, 0
	if dist_t > (max_range + band_dead) then
		local dx = tx - me.x
		local dy = ty - me.y
		local len = math.sqrt((dx * dx) + (dy * dy))
		if len > SPACING_EPS then
			rvx = dx / len
			rvy = dy / len
			mode = 'CLOSE_RADIAL'
		end
	elseif dist_t < (min_range - band_dead) then
		local dx = me.x - tx
		local dy = me.y - ty
		local len = math.sqrt((dx * dx) + (dy * dy))
		if len > SPACING_EPS then
			rvx = dx / len
			rvy = dy / len
			mode = 'RETREAT_RADIAL'
		end
	else
		mode = 'BAND_HOLD'
	end

	local me_model = movement_model_size_raw(me)
	local px, py = 0, 0
	local repelled = 0
	for _, a in ipairs(agents) do
		if tonumber(a.id) ~= local_id and a.x ~= nil and a.y ~= nil then
			local dx = me.x - a.x
			local dy = me.y - a.y
			local d = math.sqrt((dx * dx) + (dy * dy))
			if d > SPACING_EPS then
				local clearance = d - me_model - (tonumber(a.model) or 0)
				local desired = 0.0
				local overlap = desired - clearance
				if overlap > repel_deadband then
					local strength = overlap / math.max(0.05, desired)
					if strength > 1.5 then
						strength = 1.5
					end
					px = px + ((dx / d) * strength)
					py = py + ((dy / d) * strength)
					repelled = repelled + 1
				end
			end
		end
	end

	local vx = rvx + (px * repel_weight)
	local vy = rvy + (py * repel_weight)
	local vlen = math.sqrt((vx * vx) + (vy * vy))
	if vlen <= SPACING_EPS then
		if mode == 'BAND_HOLD' and repelled == 0 then
			_G.UC_SPACING_DIAG = ('mode=%s aid=%d slot=- anchor=- forced=- dist_t=%.2f range=[%.2f,%.2f] pref=%.2f goal=-,- me_sz=%.2f->%.2f tgt_sz=%.2f->%.2f'):format(
				'BAND_HOLD',
				local_id,
				dist_t,
				min_range,
				max_range,
				preferred_radius,
				tonumber(me and me.model_size) or 0,
				me_model,
				tonumber(target and target.model_size) or 0,
				movement_target_model_size(target, settings)
			)
			return nil, 'HOLD_POSITION'
		end
		return nil, 'HOLD_POSITION'
	end

	local now = uc_now_s()
	local heading = uc_heading_from_vector(vx, vy)
	if heading and repelled > 0 then
		local hold_until = tonumber(st.soft_heading_hold_until) or 0
		local held_heading = tonumber(st.soft_heading_last) or nil
		if held_heading and now < hold_until then
			heading = held_heading
			mode = 'SOFT_REPEL_HOLD'
		else
			st.soft_heading_last = heading
			st.soft_heading_hold_until = now + hold_s
			mode = (mode == 'BAND_HOLD') and 'SOFT_REPEL' or ('MIXED_' .. mode)
		end
	end

	local me_model_raw = tonumber(me and me.model_size) or 0
	local target_model_raw = tonumber(target and target.model_size) or 0
	local me_model_eff = movement_model_size_raw(me)
	local target_model_eff = movement_target_model_size(target, settings)
	_G.UC_SPACING_DIAG = ('mode=%s aid=%d slot=- anchor=- forced=- dist_t=%.2f range=[%.2f,%.2f] pref=%.2f goal=%s,%s me_sz=%.2f->%.2f tgt_sz=%.2f->%.2f'):format(
		tostring(mode or ''),
		local_id,
		dist_t,
		min_range,
		max_range,
		preferred_radius,
		tostring(spacing_round(vx)),
		tostring(spacing_round(vy)),
		me_model_raw,
		me_model_eff,
		target_model_raw,
		target_model_eff
	)
	return heading, mode
end

-- Real-time spacing-aware approach heading:
-- attract toward target while repelling from nearby party members.
local function uc_spacing_aware_approach_heading(settings, me, target)
	if not me or not target or me.x == nil or me.y == nil or target.x == nil or target.y == nil then
		return nil
	end
	local tx = target.x - me.x
	local ty = target.y - me.y
	local tlen = math.sqrt((tx * tx) + (ty * ty))
	if tlen < 0.0001 then
		return nil
	end

	local ax = tx / tlen
	local ay = ty / tlen
	local rx = 0
	local ry = 0
	local repel_range = 1.0
	local party = windower.ffxi.get_party() or {}
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }

	for _, k in ipairs(keys) do
		local e = party[k]
		local pm = e and e.mob
		local pid = pm and pm.id or 0
		if pid ~= 0 and pid ~= me.id then
			local member = windower.ffxi.get_mob_by_id(pid)
			if member and member.x ~= nil and member.y ~= nil then
				local pdist = mob_real_distance_movement(me, member, settings)
				if pdist < repel_range then
					local dx = me.x - member.x
					local dy = me.y - member.y
					local plen = math.sqrt((dx * dx) + (dy * dy))
					if plen > 0.0001 then
						local strength = (repel_range - pdist) / repel_range
						if strength < 0 then
							strength = 0
						end
						rx = rx + (dx / plen) * strength
						ry = ry + (dy / plen) * strength
					end
				end
			end
		end
	end

	local repel_weight = 1.35
	local vx = ax + (rx * repel_weight)
	local vy = ay + (ry * repel_weight)
	local heading = uc_heading_from_vector(vx, vy)
	if heading then
		return heading
	end
	return uc_heading_to(target.x, target.y)
end

local function find_candidate_target(settings)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me then
		return nil
	end
	local my_player_id = tonumber((windower.ffxi.get_player() or {}).id) or 0
	local function partner_engaged_on_target(tid)
		local target_id = tonumber(tid) or 0
		if target_id == 0 or not setting_enabled(settings and settings.partner) then
			return false, 0
		end
		local partner_ids = uc_partner_list.as_ordered_ids(settings)
		local lowest_partner_id = 0
		for _, pid in ipairs(partner_ids) do
			local pm = windower.ffxi.get_mob_by_id(pid)
			if pm and (tonumber(pm.status) or 0) == 1 and pm.target_index then
				local tm = windower.ffxi.get_mob_by_index(pm.target_index)
				if tm and (tonumber(tm.id) or 0) == target_id and tm.valid_target and (tonumber(tm.hpp) or 0) > 0 then
					if lowest_partner_id == 0 or pid < lowest_partner_id then
						lowest_partner_id = pid
					end
				end
			end
		end
		return lowest_partner_id ~= 0, lowest_partner_id
	end
	local function partner_target_owned_by_lower_id(tid)
		local target_id = tonumber(tid) or 0
		if target_id == 0 or not setting_enabled(settings and settings.partner) or my_player_id == 0 then
			return false
		end
		local partner_ids = uc_partner_list.as_ordered_ids(settings)
		local owner_id = 0
		for _, pid in ipairs(partner_ids) do
			local pm = windower.ffxi.get_mob_by_id(pid)
			if pm and pm.target_index then
				local tm = windower.ffxi.get_mob_by_index(pm.target_index)
				if tm and (tonumber(tm.id) or 0) == target_id then
					if owner_id == 0 or pid < owner_id then
						owner_id = pid
					end
				end
			end
		end
		return owner_id ~= 0 and my_player_id > owner_id
	end
	local function prime_unclaimed_party_aggressive_ok(mob, friendly_id_set)
		if not mob then
			return false
		end
		if not setting_enabled(settings.prime) then
			return false
		end
		if (tonumber(mob.status) or 0) ~= 1 then
			return false
		end
		local targets_friendly = uc_targeting_common.mob_targets_friendly_member(mob, friendly_id_set, uc_now_s())
		if not targets_friendly then
			return false
		end
		-- Prime should not target mobs clearly focused on non-friendly entities.
		local claim_id = tonumber(mob.claim_id) or 0
		if claim_id ~= 0 and not is_friendly_combat_member_id(claim_id) then
			return false
		end
		return true
	end
	local player = windower.ffxi.get_player()
	local engaged = player and player.status == 1
	-- Engaged retarget is only allowed for the explicit add-control flow (which already
	-- requires fight-leader + add-control). Do not unlock stickiness for fight-leader alone.
	local allow_engaged_retarget = uc_add_control.enabled(settings)
	local cur = get_current_target()
	local cur_alive_monster = cur and cur.valid_target and cur.hpp and cur.hpp > 0 and cur.spawn_type == 16
	local cur_dead_monster = cur and cur.spawn_type == 16 and ((cur.hpp or 0) <= 0 or death_event_active_for_id(cur.id))
	local partner_target_set = {}
	if setting_enabled(settings.partner) then
		local partner_ids = uc_partner_list.as_ordered_ids(settings)
		for _, pid in ipairs(partner_ids) do
			local pm = windower.ffxi.get_mob_by_id(pid)
			if pm and pm.target_index then
				local tm = windower.ffxi.get_mob_by_index(pm.target_index)
				local tid = tm and tm.id or 0
				if tid ~= 0 then
					partner_target_set[tid] = true
				end
			end
		end
	end
	local cur_is_partner_target = cur and partner_target_owned_by_lower_id(cur.id)
	if cur and cur_alive_monster and engaged then
		local partner_on_cur, lowest_partner_id = partner_engaged_on_target(cur.id)
		if partner_on_cur then
			-- Conflict resolver when two configured partners are on the same live mob:
			-- lower ID keeps, higher ID yields and reacquires elsewhere.
			cur_is_partner_target = (my_player_id > lowest_partner_id)
		end
	end
	if cur_is_partner_target and engaged and cur_alive_monster then
		-- Incumbent protection: if we are already engaged on a live target, do not
		-- force-yield it via ID tiebreak. Tiebreak is for new contention only.
		cur_is_partner_target = false
	end

	-- Engaged target stickiness:
	-- keep current living combat target locked unless explicit engaged retarget modes are enabled.
	if not allow_engaged_retarget then
		local sticky_id = tonumber(core.sticky_target_id) or 0
		local sticky_active = engaged or (uc_now_s() < (tonumber(core.sticky_hold_until) or 0))
		local sticky_dead_event = death_event_active_for_id(sticky_id)
		if sticky_id > 0 then
			local sticky = windower.ffxi.get_mob_by_id(sticky_id)
			local sticky_is_partner_target = sticky and partner_target_owned_by_lower_id(sticky.id)
			if sticky_is_partner_target and engaged and cur and sticky and (tonumber(cur.id) or 0) == (tonumber(sticky.id) or 0) and cur_alive_monster then
				-- Incumbent protection for sticky lock when it matches our current live target.
				sticky_is_partner_target = false
			end
			if sticky_active and (not sticky_dead_event) and (not sticky_is_partner_target) and sticky and sticky.valid_target and (sticky.hpp or 0) > 0 and sticky.spawn_type == 16 then
				return sticky
			end
			if not sticky_active then
				core.sticky_target_id = 0
			elseif sticky_dead_event then
				core.sticky_target_id = 0
			elseif sticky_is_partner_target then
				core.sticky_target_id = 0
			end
		end
		if engaged and cur_alive_monster and not cur_is_partner_target then
			core.sticky_target_id = cur.id
			core.sticky_hold_until = 0
			return cur
		end
		if engaged and cur_dead_monster then
			-- Current engaged target has died; allow one immediate rescan for next valid target
			-- so we can switch focus without waiting for full disengage/re-engage lag.
			core.sticky_target_id = 0
		end
		if engaged then
			-- Do not perform nearest-target evaluation while engaged unless add-control is enabled.
			-- This prevents mid-fight target churn from nearby newly-claimed mobs.
			if not cur_dead_monster and not cur_is_partner_target then
				return nil
			end
		end
	end

	local claims, claims_set = uc_targeting_common.build_friendly_claims()
	local path_hunter_filter_active = setting_enabled(settings.hunter) and setting_enabled(settings.path_follow_enabled)
	local path_hunter_max_z = tonumber(settings.path_hunter_max_z_delta) or 2.0
	local path_hunter_max_range = tonumber(settings.path_hunter_max_target_range) or 20.0
	if path_hunter_max_z < 0 then
		path_hunter_max_z = 0
	elseif path_hunter_max_z > 20 then
		path_hunter_max_z = 20
	end
	if path_hunter_max_range < 1 then
		path_hunter_max_range = 1
	elseif path_hunter_max_range > 80 then
		path_hunter_max_range = 80
	end
	local marray = windower.ffxi.get_mob_array() or {}
	local now = uc_now_s()
	local function hunter_cooldown_active(mid)
		local tid = tonumber(mid) or 0
		if tid == 0 then
			return false
		end
		local until_t = tonumber(core.hunter_ignore_until_by_id[tid]) or 0
		if until_t <= 0 then
			return false
		end
		if now < until_t then
			return true
		end
		core.hunter_ignore_until_by_id[tid] = nil
		return false
	end
	local leader_mid = uc_fight_leader.resolve_mid_override(settings, false, function(tid)
		return partner_target_set[tid] == true
	end)
	local add_mid = uc_add_control.pick(settings, claims, marray, leader_mid, {
		hunter_in_claim = false,
		melee_style = true,
		partner_block = function(mob)
			return mob and partner_target_set[mob.id] == true
		end,
	})
	local override_id = 0
	if add_mid and add_mid > 0 then
		override_id = add_mid
	elseif leader_mid and leader_mid > 0 then
		override_id = leader_mid
	end
	if override_id > 0 then
		local ov = windower.ffxi.get_mob_by_id(override_id)
		if ov and ov.valid_target and (ov.hpp or 0) > 0 and ov.spawn_type == 16 then
			return ov
		end
	end
	if engaged and allow_engaged_retarget then
		-- Add control may switch only to its listed add or the resolved leader target.
		-- Do not let it unlock the ordinary claimed / Prime candidate scan while engaged.
		return nil
	end
	if cur_alive_monster then
		if cur_is_partner_target then
			-- Current target is explicitly in partner-skip set; do not keep it.
			-- Continue scan for alternate valid targets.
			cur_alive_monster = false
		else
		if not path_hunter_filter_active then
			return cur
		end
		local hunter_ok = uc_path_hunter.matches_mob(settings, cur.name or '')
		local cur_prime_party_aggressive = prime_unclaimed_party_aggressive_ok(cur, claims_set)
		-- Prime party-aggressive targets should not be blocked by hunter name filters.
		if (not hunter_ok) and cur_prime_party_aggressive then
			hunter_ok = true
		end
		if hunter_ok and me and me.z ~= nil and cur.z ~= nil then
			local dz = math.abs((tonumber(cur.z) or 0) - (tonumber(me.z) or 0))
			if dz > path_hunter_max_z then
				hunter_ok = false
			end
		end
		if hunter_ok and target_distance(cur) > path_hunter_max_range then
			hunter_ok = false
		end
		if hunter_ok and not hunter_cooldown_active(cur.id) then
			local allow_prime_unclaimed = (not engaged) or allow_engaged_retarget
			local prime_unclaimed_ok = (allow_prime_unclaimed and prime_unclaimed_party_aggressive_ok(cur, claims_set))
			local hunter_idle_unclaimed_ok = (cur.claim_id == 0 and cur.status == 0)
			local claim_ok = claims_set[cur.claim_id] == true or prime_unclaimed_ok or hunter_idle_unclaimed_ok
			if claim_ok then
				return cur
			end
		end
		end
	end
	local best = nil
	local best_dist = 1e9
	local best_hpp = -1
	local tank_mode = setting_enabled(settings.tank)
	for _, mob in pairs(marray) do
		local partner_on_mob = false
		if mob and mob.id then
			partner_on_mob = select(1, partner_engaged_on_target(mob.id))
		end
		local keep_current_incumbent = engaged and cur and cur_alive_monster and ((tonumber(cur.id) or 0) == (tonumber(mob and mob.id) or 0))
		if mob and mob.id and mob.valid_target and mob.spawn_type == 16 and (mob.hpp or 0) > 0 and
			(not partner_on_mob or keep_current_incumbent) and
			(not partner_target_owned_by_lower_id(mob.id)) then
			if not uc_target_ignore.is_mob_blocked(settings, mob) then
				local hunter_ok = (not path_hunter_filter_active) or uc_path_hunter.matches_mob(settings, mob.name or '')
				local mob_prime_party_aggressive = prime_unclaimed_party_aggressive_ok(mob, claims_set)
				-- Prime party-aggressive targets should not be blocked by hunter name filters.
				if (not hunter_ok) and mob_prime_party_aggressive then
					hunter_ok = true
				end
				if hunter_ok then
					if path_hunter_filter_active and hunter_cooldown_active(mob.id) then
						hunter_ok = false
					end
				end
				if hunter_ok then
					if path_hunter_filter_active and me and me.z ~= nil and mob.z ~= nil then
						local dz = math.abs((tonumber(mob.z) or 0) - (tonumber(me.z) or 0))
						if dz > path_hunter_max_z then
							hunter_ok = false
						end
					end
				end
				if hunter_ok and path_hunter_filter_active and target_distance(mob) > path_hunter_max_range then
					hunter_ok = false
				end
				if hunter_ok then
					-- Do not pull unclaimed prime candidates while already engaged unless explicit
					-- engaged-retarget modes are active; this prevents mid-fight target flips.
					local allow_prime_unclaimed = (not engaged) or allow_engaged_retarget
					local prime_unclaimed_ok = (allow_prime_unclaimed and prime_unclaimed_party_aggressive_ok(mob, claims_set))
					local hunter_idle_unclaimed_ok = (path_hunter_filter_active and mob.claim_id == 0 and mob.status == 0)
					local claim_ok = claims_set[mob.claim_id] == true or prime_unclaimed_ok or hunter_idle_unclaimed_ok
					if claim_ok then
						local d = target_distance(mob)
						local hp = tonumber(mob.hpp) or 0
						local replace = false
						if not tank_mode then
							replace = d < best_dist
						else
							if hp ~= best_hpp then
								replace = hp > best_hpp
							elseif d ~= best_dist then
								replace = d < best_dist
							else
								replace = (tonumber(mob.id) or 0) < (tonumber(best and best.id) or 0)
							end
						end
						if replace then
							best_dist = d
							best_hpp = hp
							best = mob
						end
					end
				end
			end
		end
	end
	return best
end

local function target_is_partner_claimed(settings, tid)
	local target_id = tonumber(tid) or 0
	if target_id == 0 or not setting_enabled(settings and settings.partner) then
		return false
	end
	local my_player_id = tonumber((windower.ffxi.get_player() or {}).id) or 0
	if my_player_id == 0 then
		return false
	end
	local partner_ids = uc_partner_list.as_ordered_ids(settings or {})
	local owner_id = 0
	for _, pid in ipairs(partner_ids) do
		local pm = windower.ffxi.get_mob_by_id(pid)
		if pm and pm.target_index then
			local tm = windower.ffxi.get_mob_by_index(pm.target_index)
			if tm and (tonumber(tm.id) or 0) == target_id then
				if owner_id == 0 or pid < owner_id then
					owner_id = pid
				end
			end
		end
	end
	return owner_id ~= 0 and my_player_id > owner_id
end

local function clear_pull_spell_wait_state()
	core.pull_spell_waiting = false
	core.pull_spell_wait_until = 0
	core.pull_spell_halt_until = 0
	core.pull_pending_type = ''
	core.pull_pending_action = ''
	core.pull_pending_target_id = 0
	core.pull_pending_sent_at = 0
	core.pull_spell_settle_key = ''
	core.pull_spell_settle_until = 0
	_G.UC_PULL_SPELL_WAITING = false
	_G.UC_PULL_SPELL_WAIT_UNTIL = 0
end

local function get_spell_resource(name)
	if not name or name == '' then
		return nil
	end
	return res.spells:with('en', name)
end

local function get_ja_resource(name)
	if not name or name == '' then
		return nil
	end
	return res.job_abilities:with('en', name)
end

local RANGE_MULT = {
	[2] = 1.95,
	[3] = 1.490909,
	[4] = 1.44,
	[5] = 1.377778,
	[6] = 1.30,
	[7] = 1.15,
	[8] = 1.25,
	[9] = 1.377778,
	[10] = 1.45,
	[11] = 1.454545454545455,
	[12] = 1.666666666666667,
}

local function action_effective_range(raw_range)
	local r = tonumber(raw_range) or 0
	if r <= 0 then
		return 0
	end
	local m = RANGE_MULT[r]
	if m then
		return r * m
	end
	if r > 20 then
		return r * 0.01
	end
	return r
end

local function ja_targets_enemy(ja)
	local targets = ja and ja.targets
	if type(targets) == 'string' then
		return targets:find('Enemy', 1, true) ~= nil
	end
	if type(targets) == 'number' then
		local n = math.floor(targets)
		return (n % 64) >= 32
	end
	if type(targets) == 'table' then
		return targets.Enemy == true or targets.enemy == true
	end
	return false
end

local function normalize_angle_rad(a)
	local two_pi = math.pi * 2
	while a > math.pi do
		a = a - two_pi
	end
	while a < -math.pi do
		a = a + two_pi
	end
	return a
end

local function target_is_in_front_arc(target, arc)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or not target or me.x == nil or me.y == nil or target.x == nil or target.y == nil or me.facing == nil then
		return false
	end
	local heading = math.atan2(target.y - me.y, target.x - me.x)
	local delta = math.abs(normalize_angle_rad(heading - tonumber(me.facing)))
	return delta <= (tonumber(arc) or (math.pi / 2))
end

local function ja_requires_engaged_front(name, ja)
	if (tonumber(ja and ja.id) or 0) == 46 then -- Shield Bash
		return true
	end
	return tostring(name or ''):lower() == 'shield bash'
end

local function should_use_pull_action(settings, player, target)
	if not setting_enabled(settings and settings.hunter) then
		return false
	end
	if not setting_enabled(settings and settings.path_follow_enabled) then
		return false
	end
	if not target or not target.id or target.id == 0 then
		return false
	end
	if not uc_path_hunter.matches_mob(settings, target.name or '') then
		return false
	end
	if (tonumber(player and player.status) or 0) == 1 then
		return false
	end
	local claims, claims_set = uc_targeting_common.build_friendly_claims()
	if claims_set[target.claim_id] == true then
		return false
	end
	if tonumber(target.claim_id) ~= 0 then
		return false
	end
	return true
end

local function pull_action_config(settings)
	local at = tostring(settings and settings.path_pull_action_type or 'ja'):lower()
	if at ~= 'spell' then
		at = 'ja'
	end
	local name = tostring(settings and settings.path_pull_action_name or '')
	name = name:match('^%s*(.-)%s*$') or ''
	return at, name
end

local function pull_action_ready(action_type, action_name)
	local now = uc_now_s()
	if now < (tonumber(core.pull_lock_until) or 0) then
		return false, 'PULL_LOCK'
	end
	local player = windower.ffxi.get_player()
	if status_blocks_actions(player and player.status) then
		return false, 'ACTION_BLOCK_STATUS3'
	end
	local key = tostring(action_type) .. ':' .. tostring(action_name)
	local last = tonumber(core.pull_last_sent_at[key]) or 0
	if last > 0 and (now - last) < 0.5 then
		return false, 'PULL_RECENT_SEND'
	end
	if action_type == 'spell' then
		local sp = get_spell_resource(action_name)
		if not sp then
			return false, 'PULL_UNKNOWN_SPELL'
		end
		local known = windower.ffxi.get_spells() or {}
		if not known[sp.id] then
			return false, 'PULL_SPELL_NOT_LEARNED'
		end
		local recasts = windower.ffxi.get_spell_recasts() or {}
		local rc = recasts[sp.recast_id or sp.id] or recasts[sp.id] or 0
		if rc > 0 then
			return false, 'PULL_RECAST'
		end
		local mp = tonumber(((player or {}).vitals or {}).mp) or 0
		if mp < (tonumber(sp.mp_cost) or 0) then
			return false, 'PULL_NO_MP'
		end
		return true, ''
	end
	local ja = get_ja_resource(action_name)
	if not ja then
		return false, 'PULL_UNKNOWN_JA'
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	if (recasts[ja.recast_id] or 0) > 0 then
		return false, 'PULL_RECAST'
	end
	return true, ''
end

local function move_toward_target_for_pull(target)
	if not target then
		windower.ffxi.run(false)
		core.last_run_active = false
		set_movement_owner('none', 0)
		return false
	end
	-- Pull approach must be range-precise (stop to cast) and must not delegate to
	-- mover:move_towards(), which can continue advancing into melee beyond pull range.
	local heading = uc_heading_to(target.x, target.y)
	if heading then
		windower.ffxi.run(heading)
		core.last_run_active = true
		set_movement_owner('core', 0.8)
		return true
	end
	windower.ffxi.run(false)
	core.last_run_active = false
	set_movement_owner('none', 0)
	return false
end

local function debug_tank(msg, force)
	local s = get_settings()
	if not setting_enabled(s and s.debug) then
		return
	end
	local line = tostring(msg or '')
	if line == '' then
		return
	end
	local now = uc_now_s()
	if not force then
		local last_line = tostring(core.tank_debug_last_line or '')
		local last_at = tonumber(core.tank_debug_last_at) or 0
		if line == last_line and (now - last_at) < 0.30 then
			return
		end
	end
	core.tank_debug_last_line = line
	core.tank_debug_last_at = now
	_G.UC_TANK_LAST_DIAG = line
	pcall(function()
		local p = windower.ffxi.get_player()
		local char = (p and p.name) or 'unknown'
		local dir = ensure_log_dir()
		if not dir then
			return
		end
		local path = dir .. safe_char_name(char) .. '_tank_debug.log'
		local f = io.open(path, 'a')
		if not f then
			return
		end
		f:write(os.date('%Y-%m-%d %H:%M:%S'), '	', line:gsub('\r?\n', ' '), '\n')
		f:close()
	end)
end

local function clear_tank_spell_wait_state()
	core.tank_spell_waiting = false
	core.tank_spell_wait_until = 0
	core.tank_spell_settle_key = ''
	core.tank_spell_settle_until = 0
	core.tank_pending_action = ''
	core.tank_pending_type = ''
	core.tank_pending_target_id = 0
	core.tank_pending_sent_at = 0
end

local function parse_tank_enmity_actions(settings)
	local src = settings and settings.tank_enmity_actions or {}
	local rows = {}
	if type(src) == 'string' then
		src = split_pipe(src)
	end
	if type(src) ~= 'table' then
		return rows
	end
	for _, item in ipairs(src) do
		local raw = ''
		local kind = ''
		local name = ''
		if type(item) == 'table' then
			raw = tostring(item.raw or item.entry or item.name or '')
			kind = tostring(item.kind or item.type or ''):lower()
			name = tostring(item.name or '')
		else
			raw = tostring(item or '')
		end
		if raw ~= '' and name == '' then
			local k, n = raw:match('^(%a+)%s*:%s*(.+)$')
			if k and n then
				kind = tostring(k):lower()
				name = tostring(n)
			else
				name = raw
			end
		end
		name = tostring(name or ''):match('^%s*(.-)%s*$') or ''
		if name ~= '' then
			if kind ~= 'ja' and kind ~= 'spell' then
				if get_ja_resource(name) then
					kind = 'ja'
				elseif get_spell_resource(name) then
					kind = 'spell'
				end
			end
			if kind == 'ja' or kind == 'spell' then
				local key = kind .. ':' .. name:lower()
				if not list_has_name(rows, key) then
					rows[#rows + 1] = {
						kind = kind,
						name = name,
						key = key,
						raw = raw ~= '' and raw or (kind .. ':' .. name),
					}
				end
			end
		end
	end
	return rows
end

local function target_is_party_member_non_tank(target_id, me_id)
	local tid = tonumber(target_id) or 0
	local mid = tonumber(me_id) or 0
	if tid == 0 or tid == mid then
		return false
	end
	return is_friendly_combat_member_id(tid)
end

resolve_mob_current_target = function(mob)
	if not mob then
		return nil
	end
	local t = nil
	local claim_tid = tonumber(mob.claim_id) or 0
	if claim_tid > 0 and is_friendly_combat_member_id(claim_tid) then
		t = windower.ffxi.get_mob_by_id(claim_tid)
		if (not t or not t.id or t.id == 0) then
			t = { id = claim_tid, name = '(claim)' }
		end
	end
	local ti = tonumber(mob.target_index) or 0
	if (not t or not t.id or t.id == 0) and ti > 0 then
		t = windower.ffxi.get_mob_by_index(ti)
	end
	if (not t or not t.id or t.id == 0) then
		local tid = tonumber(mob.target) or 0
		if tid > 0 then
			t = windower.ffxi.get_mob_by_id(tid)
		end
	end
	if (not t or not t.id or t.id == 0) then
		local amap = rawget(_G, 'UC_MOB_LAST_ACTION_TARGETS')
		local rec = type(amap) == 'table' and amap[tonumber(mob.id) or 0] or nil
		if type(rec) == 'table' then
			local age = uc_now_s() - (tonumber(rec.at) or 0)
			if age >= 0 and age <= 5.0 then
				local rid = tonumber(rec.target_id) or 0
				if rid > 0 then
					t = windower.ffxi.get_mob_by_id(rid)
					if (not t or not t.id or t.id == 0) then
						t = { id = rid, name = '(pkt)' }
					end
				end
			end
		end
	end
	return t
end

local function pick_tank_violation_target(settings, player)
	if not setting_enabled(settings and settings.tank) then
		if core.tank_debug_last_violation_sig ~= 'OFF' then
			core.tank_debug_last_violation_sig = 'OFF'
			debug_tank('scan tank=off', true)
		end
		return nil
	end
	local me_id = tonumber((player or {}).id) or 0
	if me_id == 0 then
		if core.tank_debug_last_violation_sig ~= 'NO_ME' then
			core.tank_debug_last_violation_sig = 'NO_ME'
			debug_tank('scan no_player_id', true)
		end
		return nil
	end
	local marray = windower.ffxi.get_mob_array() or {}
	local best = nil
	for _, mob in pairs(marray) do
		if mob and mob.id and mob.id ~= 0 and mob.valid_target and mob.spawn_type == 16 and (tonumber(mob.hpp) or 0) > 0 then
			if (tonumber(mob.status) or 0) == 1 and not uc_target_ignore.is_mob_blocked(settings, mob) then
				local victim = resolve_mob_current_target(mob)
				local victim_id = tonumber(victim and victim.id) or 0
				if victim and target_is_party_member_non_tank(victim_id, me_id) then
					local c = {
						mob = mob,
						victim = victim,
						victim_hpp = tonumber(victim.hpp) or 100,
						dist = target_distance(mob),
						mob_hpp = tonumber(mob.hpp) or 0,
						mob_id = tonumber(mob.id) or 0,
					}
					if not best then
						best = c
					else
						local replace = false
						if c.victim_hpp ~= best.victim_hpp then
							replace = c.victim_hpp < best.victim_hpp
						elseif c.dist ~= best.dist then
							replace = c.dist < best.dist
						elseif c.mob_hpp ~= best.mob_hpp then
							replace = c.mob_hpp > best.mob_hpp
						else
							replace = c.mob_id < best.mob_id
						end
						if replace then
							best = c
						end
					end
				end
			end
		end
	end
	local sig
	if best and best.mob then
		sig = ('HIT:%d>%d'):format(tonumber(best.mob.id) or 0, tonumber((best.victim and best.victim.id) or 0) or 0)
	else
		sig = 'NONE'
	end
	if sig ~= core.tank_debug_last_violation_sig then
		core.tank_debug_last_violation_sig = sig
		if best and best.mob then
			debug_tank(('scan violation mob=%s[%d] victim=%s[%d] victim_hpp=%d dist=%.2f'):format(
				tostring(best.mob.name or '?'),
				tonumber(best.mob.id) or 0,
				tostring((best.victim and best.victim.name) or '?'),
				tonumber((best.victim and best.victim.id) or 0) or 0,
				tonumber(best.victim_hpp) or 0,
				tonumber(best.dist) or 0
			), true)
		else
			debug_tank('scan violation none', true)
		end
	end
	return best
end

local function tank_action_range(kind, resource)
	local max_range = action_effective_range(resource and resource.range)
	if max_range <= 0 then
		max_range = (kind == 'spell') and 20 or 10
	end
	local cast_max_range = max_range
	if kind == 'spell' then
		local buffer = max_range * 0.10
		cast_max_range = max_range - buffer
		if cast_max_range < 1.0 then
			cast_max_range = 1.0
		end
	end
	return max_range, cast_max_range
end

local function tank_action_ready(entry, mob, player)
	if not entry or not mob then
		return false, 'TANK_ACTION_INVALID'
	end
	local now = uc_now_s()
	if status_blocks_actions(player and player.status) then
		return false, 'ACTION_BLOCK_STATUS3'
	end
	local key = tostring(entry.kind) .. ':' .. tostring(entry.name)
	local last = tonumber(core.tank_last_sent_at[key]) or 0
	if last > 0 and (now - last) < 0.5 then
		return false, 'TANK_RECENT_SEND'
	end
	if entry.kind == 'ja' then
		local ja = get_ja_resource(entry.name)
		if not ja then
			return false, 'TANK_JA_UNKNOWN'
		end
		local recasts = windower.ffxi.get_ability_recasts() or {}
		if (recasts[ja.recast_id] or 0) > 0 then
			return false, 'TANK_RECAST'
		end
		if now < (tonumber(core.ja_lock_until) or 0) then
			return false, 'TANK_JA_LOCK'
		end
		local abil = windower.ffxi.get_abilities() or {}
		local owns = false
		for _, id in ipairs(abil.job_abilities or {}) do
			if id == ja.id then
				owns = true
				break
			end
		end
		if not owns then
			return false, 'TANK_JA_NOT_OWNED'
		end
		local targets = tostring(ja.targets or '')
		if not targets:find('Enemy', 1, true) then
			return false, 'TANK_JA_NOT_ENEMY'
		end
		local _, cast_max = tank_action_range('ja', ja)
		local dist = target_distance(mob)
		if dist > cast_max then
			return false, 'TANK_OUT_OF_RANGE', cast_max, dist
		end
		return true, '', cast_max, dist
	end
	local sp = get_spell_resource(entry.name)
	if not sp then
		return false, 'TANK_SPELL_UNKNOWN'
	end
	local targets = tostring(sp.targets or '')
	if not targets:find('Enemy', 1, true) then
		return false, 'TANK_SPELL_NOT_ENEMY'
	end
	local known = windower.ffxi.get_spells() or {}
	if not known[sp.id] then
		return false, 'TANK_SPELL_NOT_LEARNED'
	end
	local recasts = windower.ffxi.get_spell_recasts() or {}
	local rc = recasts[sp.recast_id or sp.id] or recasts[sp.id] or 0
	if rc > 0 then
		return false, 'TANK_RECAST'
	end
	local mp = tonumber(((player or {}).vitals or {}).mp) or 0
	if mp < (tonumber(sp.mp_cost) or 0) then
		return false, 'TANK_NO_MP'
	end
	if core.tank_spell_waiting == true and now < (tonumber(core.tank_spell_wait_until) or 0) then
		return false, 'TANK_SPELL_WAITING'
	end
	local _, cast_max = tank_action_range('spell', sp)
	local dist = target_distance(mob)
	if dist > cast_max then
		return false, 'TANK_OUT_OF_RANGE', cast_max, dist
	end
	return true, '', cast_max, dist
end

local function execute_tank_enmity(settings, player, violation)
	if not violation or not violation.mob then
		return false
	end
	local actions = parse_tank_enmity_actions(settings)
	if #actions == 0 then
		local mob = windower.ffxi.get_mob_by_id(violation.mob.id) or violation.mob
		_G.UC_LAST_BLOCK_REASON = 'TANK_ENMITY_NO_ACTIONS'
		_G.UC_WS_LAST_DIAG = ('core tank no_actions mob=%s victim=%s(%s%%)'):format(
			tostring((mob and mob.name) or '?'),
			tostring((violation.victim and violation.victim.name) or '?'),
			tostring(tonumber(violation.victim_hpp) or 0)
		)
		debug_tank(_G.UC_WS_LAST_DIAG)
		return false
	end
	local mob = windower.ffxi.get_mob_by_id(violation.mob.id) or violation.mob
	if not mob or not mob.id or not mob.valid_target or (tonumber(mob.hpp) or 0) <= 0 then
		return false
	end
	local now = uc_now_s()
	if core.tank_spell_waiting == true then
		if now < (tonumber(core.tank_spell_wait_until) or 0) then
			windower.ffxi.run(false)
			core.last_run_active = false
			_G.UC_LAST_BLOCK_REASON = 'TANK_SPELL_WAITING'
			_G.UC_WS_LAST_DIAG = ('core tank wait action=%s mob=%s'):format(tostring(core.tank_pending_action or ''), tostring(mob.name or '?'))
			debug_tank(_G.UC_WS_LAST_DIAG)
			return true
		end
		clear_tank_spell_wait_state()
	end
	for _, entry in ipairs(actions) do
		local ready, reason, cast_max, dist = tank_action_ready(entry, mob, player)
		if ready then
			if entry.kind == 'spell' then
				local settle_key = ('%s:%d'):format(tostring(entry.name), tonumber(mob.id) or 0)
				local now_settle = uc_now_s()
				if core.tank_spell_settle_key ~= settle_key then
					core.tank_spell_settle_key = settle_key
					core.tank_spell_settle_until = now_settle + 0.40
				end
				windower.ffxi.run(false)
				core.last_run_active = false
				if now_settle < (tonumber(core.tank_spell_settle_until) or 0) then
					_G.UC_LAST_BLOCK_REASON = 'TANK_PRECAST_SETTLE'
					_G.UC_WS_LAST_DIAG = ('core tank settle action=%s mob=%s'):format(tostring(entry.name), tostring(mob.name or '?'))
					debug_tank(_G.UC_WS_LAST_DIAG)
					return true
				end
				windower.send_command(('input /ma "%s" %d'):format(entry.name, tonumber(mob.id) or 0))
				core.tank_spell_waiting = true
				core.tank_spell_wait_until = now + 8.0
				core.tank_pending_type = 'spell'
				core.tank_pending_action = tostring(entry.name)
				core.tank_pending_target_id = tonumber(mob.id) or 0
				core.tank_pending_sent_at = now
				core.tank_last_sent_at[tostring(entry.kind) .. ':' .. tostring(entry.name)] = now
				_G.UC_LAST_BLOCK_REASON = 'TANK_ENMITY_SENT'
				_G.UC_WS_LAST_DIAG = ('core tank sent spell=%s mob=%s victim=%s'):format(tostring(entry.name), tostring(mob.name or '?'), tostring((violation.victim and violation.victim.name) or '?'))
				debug_tank(_G.UC_WS_LAST_DIAG, true)
				return true
			end
			local ja = get_ja_resource(entry.name)
			if ja then
				core.ja_pending_name = tostring(entry.name or '')
				core.ja_pending_recast_id = tonumber(ja.recast_id) or 0
				core.ja_pending_sent_at = now
				core.ja_lock_until = math.max(tonumber(core.ja_lock_until) or 0, now + 0.5)
				core.ja_last_sent_at[tostring(entry.name or '')] = now
			end
			windower.send_command(('input /ja "%s" %d'):format(entry.name, tonumber(mob.id) or 0))
			core.tank_pending_type = 'ja'
			core.tank_pending_action = tostring(entry.name)
			core.tank_pending_target_id = tonumber(mob.id) or 0
			core.tank_pending_sent_at = now
			core.tank_last_sent_at[tostring(entry.kind) .. ':' .. tostring(entry.name)] = now
			_G.UC_LAST_BLOCK_REASON = 'TANK_ENMITY_SENT'
			_G.UC_WS_LAST_DIAG = ('core tank sent ja=%s mob=%s victim=%s'):format(tostring(entry.name), tostring(mob.name or '?'), tostring((violation.victim and violation.victim.name) or '?'))
			debug_tank(_G.UC_WS_LAST_DIAG, true)
			return true
		end
		if reason == 'TANK_OUT_OF_RANGE' then
			move_toward_target_for_pull(mob)
			_G.UC_LAST_BLOCK_REASON = 'TANK_ENMITY_MOVE'
			_G.UC_WS_LAST_DIAG = ('core tank move action=%s:%s mob=%s dist=%.2f need<=%.2f victim=%s(%s%%)'):format(
				tostring(entry.kind),
				tostring(entry.name),
				tostring(mob.name or '?'),
				tonumber(dist) or 999,
				tonumber(cast_max) or 0,
				tostring((violation.victim and violation.victim.name) or '?'),
				tostring(tonumber(violation.victim_hpp) or 0)
			)
			debug_tank(_G.UC_WS_LAST_DIAG)
			return true
		end
		if reason ~= 'TANK_RECAST' and reason ~= 'TANK_RECENT_SEND' and reason ~= 'TANK_JA_LOCK' and reason ~= 'TANK_SPELL_WAITING' then
			_G.UC_WS_LAST_DIAG = ('core tank skip action=%s:%s reason=%s'):format(tostring(entry.kind), tostring(entry.name), tostring(reason or 'BLOCK'))
			debug_tank(_G.UC_WS_LAST_DIAG)
		end
	end
	_G.UC_LAST_BLOCK_REASON = 'TANK_ENMITY_NO_READY_ACTION'
	_G.UC_WS_LAST_DIAG = ('core tank no_ready_action mob=%s victim=%s(%s%%)'):format(
		tostring(mob.name or '?'),
		tostring((violation.victim and violation.victim.name) or '?'),
		tostring(tonumber(violation.victim_hpp) or 0)
	)
	debug_tank(_G.UC_WS_LAST_DIAG)
	return false
end

local function try_pull_action(settings, player, target)
	set_preengage_approach_active(false)
	if not should_use_pull_action(settings, player, target) then
		return false
	end
	local action_type, action_name = pull_action_config(settings)
	if action_name == '' then
		return false
	end
	local now = uc_now_s()
	if core.pull_spell_waiting == true then
		if now < (tonumber(core.pull_spell_wait_until) or 0) then
			-- Keep stationary until the spell action completion packet arrives.
			windower.ffxi.run(false)
			core.last_run_active = false
			set_movement_owner('core', 0.6)
			_G.UC_PULL_SPELL_WAITING = true
			_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.6
			_G.UC_LAST_BLOCK_REASON = 'PULL_SPELL_WAITING'
			_G.UC_WS_LAST_DIAG = ('core pull spell-wait action=%s'):format(tostring(core.pull_pending_action or action_name))
			return true
		end
		-- Safety timeout in case completion packets are missed.
		clear_pull_spell_wait_state()
	end
	if not target.valid_target or target.spawn_type ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
		return false
	end
	local resource = (action_type == 'spell') and get_spell_resource(action_name) or get_ja_resource(action_name)
	if not resource then
		_G.UC_LAST_BLOCK_REASON = 'PULL_ACTION_UNKNOWN'
		_G.UC_WS_LAST_DIAG = ('core pull unknown type=%s action=%s'):format(action_type, action_name)
		return true
	end

	local cur = get_current_target()
	if not cur or cur.id ~= target.id then
		local ok_set = uc_settarget.select_by_id(target.id)
		if not ok_set then
			windower.ffxi.run(false)
			core.last_run_active = false
			_G.UC_LAST_BLOCK_REASON = 'PULL_TARGET_SET_FAIL'
			_G.UC_WS_LAST_DIAG = ('core pull target-set fail tid=%d action=%s'):format(tonumber(target.id) or 0, action_name)
			return true
		end
		coroutine.sleep(0.05)
		cur = get_current_target()
		if not cur or cur.id ~= target.id then
			windower.ffxi.run(false)
			core.last_run_active = false
			_G.UC_LAST_BLOCK_REASON = 'PULL_TARGET_SET_FAIL'
			return true
		end
	end

	local max_range = action_effective_range(resource.range)
	if max_range <= 0 then
		max_range = (action_type == 'spell') and 20 or 10
	end
	if action_type == 'spell' and max_range < 5.0 then
		-- Pull spells are expected to be ranged actions; very small computed ranges
		-- indicate malformed resource-range mapping for this action.
		max_range = 20.0
	end
	local cast_max_range = max_range
	if action_type == 'spell' then
		local buffer = max_range * 0.10
		cast_max_range = max_range - buffer
		if cast_max_range < 1.0 then
			cast_max_range = 1.0
		end
	end
	local dist = target_real_distance(cur)
	if dist > cast_max_range then
		core.pull_spell_settle_key = ''
		core.pull_spell_settle_until = 0
		_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.8
		_G.UC_PULL_APPROACH_UNTIL = uc_now_s() + 0.8
		_G.UC_LAST_BLOCK_REASON = 'PULL_MOVE_INTO_RANGE'
		_G.UC_WS_LAST_DIAG = ('core pull move type=%s action=%s dist=%.2f cast_range=%.2f max=%.2f'):format(action_type, action_name, dist, cast_max_range, max_range)
		local moved = move_toward_target_for_pull(cur)
		if not moved then
			_G.UC_LAST_BLOCK_REASON = 'PULL_MOVE_VECTOR_FAIL'
		else
			set_preengage_approach_active(true)
		end
		return true
	end

	-- Hard-stop before pull spell casting only. JAs are intentionally allowed while moving.
	if action_type == 'spell' then
		local settle_key = ('%s:%d'):format(tostring(action_name), tonumber(cur.id) or 0)
		local now_settle = uc_now_s()
		if core.pull_spell_settle_key ~= settle_key then
			core.pull_spell_settle_key = settle_key
			core.pull_spell_settle_until = now_settle + 0.40
			core.pull_spell_halt_until = now_settle + 0.40
		end
		_G.UC_PULL_APPROACH_UNTIL = now_settle + 0.5
		windower.ffxi.run(false)
		core.last_run_active = false
		set_movement_owner('core', 0.5)
		_G.UC_MOVE_FREEZE_PREP_UNTIL = math.max(tonumber(rawget(_G, 'UC_MOVE_FREEZE_PREP_UNTIL')) or 0, now_settle + 0.45)
		if now_settle < (tonumber(core.pull_spell_halt_until) or 0) then
			_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.6
			_G.UC_LAST_BLOCK_REASON = 'PULL_PRECAST_HALT'
			_G.UC_WS_LAST_DIAG = ('core pull halt action=%s tid=%d'):format(action_name, tonumber(cur.id) or 0)
			return true
		end
		if now_settle < (tonumber(core.pull_spell_settle_until) or 0) then
			_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.6
			_G.UC_LAST_BLOCK_REASON = 'PULL_PRECAST_SETTLE'
			_G.UC_WS_LAST_DIAG = ('core pull settle action=%s tid=%d'):format(action_name, tonumber(cur.id) or 0)
			return true
		end
	end
	local ok_ready, why = pull_action_ready(action_type, action_name)
	if not ok_ready then
		_G.UC_LAST_BLOCK_REASON = why
		_G.UC_WS_LAST_DIAG = ('core pull wait type=%s action=%s reason=%s'):format(action_type, action_name, tostring(why or 'BLOCK'))
		return true
	end

	local sent_key = tostring(action_type) .. ':' .. tostring(action_name)
	if action_type == 'spell' then
		windower.send_command('input /ma "' .. action_name .. '" ' .. tostring(cur.id))
		core.pull_lock_until = math.max(tonumber(core.pull_lock_until) or 0, now + 0.9)
		core.pull_pending_type = 'spell'
		core.pull_spell_waiting = true
		core.pull_spell_wait_until = now + 8.0
		_G.UC_PULL_SPELL_WAITING = true
		_G.UC_PULL_SPELL_WAIT_UNTIL = core.pull_spell_wait_until
		_G.UC_PULL_CAST_HOLD_UNTIL = now + 1.0
		_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 2.5
		_G.UC_PULL_APPROACH_UNTIL = uc_now_s() + 2.5
	else
		windower.send_command('input /ja "' .. action_name .. '" ' .. tostring(cur.id))
		core.ja_lock_until = math.max(tonumber(core.ja_lock_until) or 0, now + 0.5)
		core.pull_lock_until = math.max(tonumber(core.pull_lock_until) or 0, now + 0.6)
		core.pull_pending_type = 'ja'
		_G.UC_PULL_APPROACH_UNTIL = uc_now_s() + 0.8
	end
	core.pull_pending_action = tostring(action_name)
	core.pull_pending_target_id = tonumber(cur.id) or 0
	core.pull_pending_sent_at = now
	core.pull_last_sent_at[sent_key] = now
	if (tonumber(core.hunter_acquire.target_id) or 0) == (tonumber(cur.id) or 0) then
		core.hunter_acquire.started_at = now
	end
	_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.8
	_G.UC_LAST_BLOCK_REASON = 'PULL_ACTION_SENT'
	_G.UC_WS_LAST_DIAG = ('core pull sent type=%s action=%s tid=%d cast_range=%.2f max=%.2f'):format(action_type, action_name, tonumber(cur.id) or 0, cast_max_range, max_range)
	return true
end

local function ensure_target_and_attack(tid)
	if not tid or tid == 0 then
		return false
	end
	local cur = get_current_target()
	local now = uc_now_s()
	local p = windower.ffxi.get_player()
	local engaged = p and p.status == 1
	if engaged and cur and cur.id and cur.id ~= tid then
		local ok_sw = uc_attack.switch_target(tid)
		if not ok_sw then
			_G.UC_LAST_BLOCK_REASON = 'TARGET_SWITCH_FAIL'
			return false
		end
		coroutine.sleep(0.05)
		cur = get_current_target()
	end
	if not cur or cur.id ~= tid then
		local ok = uc_settarget.select_by_id(tid)
		if not ok then
			_G.UC_LAST_BLOCK_REASON = 'TARGET_SET_FAIL'
			return false
		end
		coroutine.sleep(0.1)
		cur = get_current_target()
	end
	if not cur or cur.id ~= tid then
		return false
	end
	if not is_live_actionable_combat_target(cur, now, true) then
		_G.UC_LAST_BLOCK_REASON = 'TARGET_NOT_ACTIONABLE'
		return false
	end
	-- Avoid re-sending engage while already engaged on the correct target; repeated engage
	-- injections can create churn on some clients/servers.
	if engaged then
		return true
	end
	local ok_attack = uc_attack.engage_target(tid)
	if not ok_attack then
		_G.UC_LAST_BLOCK_REASON = 'ATTACK_PACKET_FAIL'
		return false
	end
	return true
end

core.is_live_actionable_combat_target = is_live_actionable_combat_target

stop_run = function()
	windower.ffxi.run(false)
	core.last_run_active = false
	set_movement_owner('none', 0)
end

get_mover = function()
	if core.mover ~= nil then
		return core.mover or nil
	end
	local actor_new = _libs and _libs.lor and _libs.lor.actor and _libs.lor.actor.Actor and _libs.lor.actor.Actor.new
	if type(actor_new) == 'function' then
		local ok, mover = pcall(actor_new)
		if ok and type(mover) == 'table' then
			core.mover = mover
			return mover
		end
	end
	core.mover = false
	return nil
end

local function apply_facing(settings, target)
	if not setting_enabled(settings.face) or not target then
		return
	end
	local heading = uc_heading_to(target.x, target.y)
	if heading then
		windower.ffxi.turn(heading)
	end
end

local function ensure_move_guard_state()
	if type(core.move_guard) ~= 'table' then
		core.move_guard = {}
	end
	local g = core.move_guard
	if type(g.stuck_ticks) ~= 'number' then
		g.stuck_ticks = 0
	end
	if type(g.recovery_active) ~= 'boolean' then
		g.recovery_active = false
	end
	if type(g.recovery_dir) ~= 'number' or g.recovery_dir == 0 then
		g.recovery_dir = 1
	end
	g.last_sample_at = tonumber(g.last_sample_at) or 0
	g.recovery_hold_until = tonumber(g.recovery_hold_until) or 0
	g.recovery_flip_at = tonumber(g.recovery_flip_at) or 0
	g.recovery_until = tonumber(g.recovery_until) or 0
	g.retreat_suppress_until = tonumber(g.retreat_suppress_until) or 0
	if type(g.recovery_flipped) ~= 'boolean' then
		g.recovery_flipped = false
	end
	return g
end

local function force_face_target(target)
	if not target or target.x == nil or target.y == nil then
		return
	end
	local heading = uc_heading_to(target.x, target.y)
	if heading then
		windower.ffxi.turn(heading)
	end
end

local function movement_guard_sample(g, me, dist, now)
	if not g or not me or me.x == nil or me.y == nil then
		return
	end
	local moved = nil
	local ddelta = nil
	if g.last_x ~= nil and g.last_y ~= nil then
		local dx = tonumber(me.x) - tonumber(g.last_x)
		local dy = tonumber(me.y) - tonumber(g.last_y)
		moved = math.sqrt((dx * dx) + (dy * dy))
	end
	if g.last_dist ~= nil then
		ddelta = math.abs((tonumber(dist) or 0) - (tonumber(g.last_dist) or 0))
	end
	if moved ~= nil and ddelta ~= nil then
		if moved < 0.05 and ddelta < 0.08 then
			g.stuck_ticks = (tonumber(g.stuck_ticks) or 0) + 1
		else
			g.stuck_ticks = 0
			if g.recovery_active then
				g.recovery_active = false
			end
		end
	end
	if g.recovery_active and now >= (tonumber(g.recovery_until) or 0) then
		g.recovery_active = false
	end
	g.last_x = tonumber(me.x)
	g.last_y = tonumber(me.y)
	g.last_dist = tonumber(dist) or 0
	g.last_sample_at = tonumber(now) or uc_now_s()
end

local function run_heading_guarded(target, me, heading, tag, is_retreat_intent)
	if not heading then
		return false
	end
	local g = ensure_move_guard_state()
	local now = uc_now_s()
	local away = is_retreat_intent == true
	if me and target and me.x ~= nil and me.y ~= nil and target.x ~= nil and target.y ~= nil then
		local tx = tonumber(target.x) - tonumber(me.x)
		local ty = tonumber(target.y) - tonumber(me.y)
		local len = math.sqrt((tx * tx) + (ty * ty))
		if len > 0.0001 then
			local ux = tx / len
			local uy = ty / len
			local rx = math.cos(heading)
			local ry = math.sin(heading)
			local dot = (ux * rx) + (uy * ry)
			if dot < -0.15 then
				away = true
			end
		end
	end
	if g.recovery_active and now < (tonumber(g.recovery_until) or 0) and target and target.x ~= nil and target.y ~= nil then
		if now < (tonumber(g.recovery_hold_until) or 0) then
			windower.ffxi.run(false)
			core.last_run_active = false
			force_face_target(target)
			_G.UC_MOVE_DIAG = ('stuck_recovery_hold ticks=%d'):format(tonumber(g.stuck_ticks) or 0)
			return false
		end
		if (not g.recovery_flipped) and now >= (tonumber(g.recovery_flip_at) or 0) then
			g.recovery_dir = (tonumber(g.recovery_dir) or 1) * -1
			g.recovery_flipped = true
		end
		local toward = uc_heading_to(target.x, target.y)
		if toward then
			local side = ((tonumber(g.recovery_dir) or 1) >= 0) and (math.pi / 2) or (-math.pi / 2)
			heading = toward + side
			away = false
			tag = (tostring(tag or '') .. ':sidestep')
		end
	end
	if away and now < (tonumber(g.retreat_suppress_until) or 0) then
		windower.ffxi.run(false)
		core.last_run_active = false
		force_face_target(target)
		_G.UC_MOVE_DIAG = ('retreat_suppressed until=%.2f tag=%s'):format(tonumber(g.retreat_suppress_until) or 0, tostring(tag or ''))
		return false
	end
	if away and (tonumber(g.stuck_ticks) or 0) >= 3 then
		g.recovery_active = true
		g.recovery_dir = (tonumber(g.recovery_dir) or 1) * -1
		g.recovery_hold_until = now + 0.20
		g.recovery_flip_at = now + 0.60
		g.recovery_flipped = false
		g.recovery_until = now + 1.00
		g.retreat_suppress_until = math.max(tonumber(g.retreat_suppress_until) or 0, now + 2.0)
		windower.ffxi.run(false)
		core.last_run_active = false
		force_face_target(target)
		_G.UC_MOVE_DIAG = ('stuck_detected ticks=%d tag=%s -> hold+sidestep+suppress'):format(tonumber(g.stuck_ticks) or 0, tostring(tag or ''))
		return false
	end
	windower.ffxi.run(heading)
	core.last_run_active = true
	_G.UC_MOVE_DIAG = ('move tag=%s away=%s stuck=%d'):format(tostring(tag or ''), tostring(away), tonumber(g.stuck_ticks) or 0)
	return true
end

local function apply_movement(settings, target)
	set_preengage_approach_active(false)
	_G.UC_PULLER_APPROACH_BLOCK_UNTIL = 0
	-- Guard: do not drive combat-close movement from a manually selected target
	-- unless autotarget is enabled (normal combat ownership) or explicit move mode is on.
	if (not setting_enabled(settings.autotarget)) and (not setting_enabled(settings.move)) then
		if core.last_run_active then
			stop_run()
		end
		return
	end
	if setting_enabled(settings.manual) or setting_enabled(settings.static) or not target then
		if core.last_run_active then
			stop_run()
		end
		return
	end
	if not is_live_actionable_combat_target(target, uc_now_s(), true) then
		if core.last_run_active then
			stop_run()
		end
		_G.UC_MOVE_DIAG = 'move_skip_not_actionable_target'
		return
	end
	local puller_allowed = puller_engage_allowed(settings, target)
	if not puller_allowed then
		-- Puller gate blocks combat-close movement: explicitly stop current run vector and
		-- let party-follow own movement for a short window to avoid orphan/stuck trajectories.
		windower.ffxi.run(false)
		core.last_run_active = false
		_G.UC_PULLER_APPROACH_BLOCK_UNTIL = uc_now_s() + 0.6
		return
	end
	local dist = target_real_distance_movement(target, settings)
	-- Comfortable fight-distance band around target.
	local max_range = tonumber(settings.spacing_band_max) or 0.4
	local min_range = tonumber(settings.spacing_band_min) or -0.9
	if min_range < -5 then
		min_range = -5
	elseif min_range > 2 then
		min_range = 2
	end
	if max_range < -1 then
		max_range = -1
	elseif max_range > 5 then
		max_range = 5
	end
	if max_range <= min_range then
		max_range = min_range + 0.1
	end
	local mover = get_mover()
	local me = windower.ffxi.get_mob_by_target('me')
	local p = windower.ffxi.get_player()
	local g = ensure_move_guard_state()
	movement_guard_sample(g, me, dist, uc_now_s())
	-- Spacing is combat-only behavior; never apply it while out of combat/following.
	local spacing_on = setting_enabled(settings.spacing) and p and (tonumber(p.status) or 0) == 1
	if spacing_on and me then
		local heading, mode = spacing_compute_heading(settings, me, target, min_range, max_range)
		if mode == 'HOLD_POSITION' then
			if core.last_run_active then
				stop_run()
			end
			return
		end
		if heading then
			windower.ffxi.run(heading)
			core.last_run_active = true
			return
		end
	end
	-- When spacing is off, use simple "close then stop" behavior.
	-- Do not run retreat/comfort-band corrections, which feel like hidden spacing.
	if not spacing_on then
		local stop_range = math.max(0.2, max_range)
		if dist > stop_range then
			local moved = false
			if mover and target.id and type(mover.move_towards) == 'function' then
				local ok = pcall(function()
					mover:move_towards(target.id)
				end)
				moved = ok
			end
			if not moved then
				local heading = uc_heading_to(target.x, target.y)
				if heading then
					windower.ffxi.run(heading)
					moved = true
				end
			end
			if not moved then
				windower.ffxi.run()
				moved = true
			end
			core.last_run_active = moved
			set_preengage_approach_active(moved)
		else
			if core.last_run_active then
				stop_run()
			end
		end
		return
	end
	local closing_to_target = dist > max_range
	if dist > max_range then
		local moved = false
		if spacing_on and me then
			local heading = uc_spacing_aware_approach_heading(settings, me, target)
			if heading then
				moved = run_heading_guarded(target, me, heading, 'close_spacing', false)
			end
		end
		if (not moved) and mover and target.id and type(mover.move_towards) == 'function' then
			local ok = pcall(function()
				mover:move_towards(target.id)
			end)
			moved = ok
		end
		if not moved then
			local heading = uc_heading_to(target.x, target.y)
			if heading then
				moved = run_heading_guarded(target, me, heading, 'close_direct', false)
			end
		end
		if not moved then
			windower.ffxi.run()
			moved = true
		end
		core.last_run_active = moved
		set_preengage_approach_active(moved)
	elseif dist < min_range then
		local moved = false
		local heading = uc_heading_to(target.x, target.y)
		if heading then
			moved = run_heading_guarded(target, me, heading + math.pi, 'retreat_target', true)
		end
		if not moved then
			stop_run()
			force_face_target(target)
		end
		core.last_run_active = moved
	else
		if core.last_run_active then
			stop_run()
		end
	end

	if closing_to_target then
		-- While closing, spacing is already folded into the approach vector above.
		return
	end

	if spacing_on then
		if p and me and p.status == 1 then
			local party = windower.ffxi.get_party() or {}
			local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
			local spacing_trigger = -0.22
			local chosen_id = 0
			local chosen_member = nil
			local chosen_dist = 999

			for _, k in ipairs(keys) do
				local e = party[k]
				local pm = e and e.mob
				local pid = pm and pm.id or 0
				if pid ~= 0 and pid ~= me.id then
					local member = windower.ffxi.get_mob_by_id(pid)
					local pdist = mob_real_distance_movement(me, member, settings)
					if pdist < spacing_trigger and pdist < chosen_dist then
						chosen_id = pid
						chosen_member = member
						chosen_dist = pdist
					end
				end
			end
			if chosen_id ~= 0 then
				local moved = false
				if mover and type(mover.move_away_from) == 'function' then
					local ok = pcall(function()
						mover:move_away_from(chosen_id)
					end)
					moved = ok
				end
				if not moved and chosen_member and chosen_member.x and chosen_member.y then
					local heading = uc_heading_to(chosen_member.x, chosen_member.y)
					if heading then
						moved = run_heading_guarded(target, me, heading + math.pi, 'retreat_party', true)
					end
				end
				core.last_run_active = moved
				return
			end
		end
	end
end

local function get_mob_id_by_index(index)
	local ok, mob = pcall(function()
		return windower.ffxi.get_mob_by_index(index)
	end)
	if ok and mob and mob.id then
		return mob.id
	end
	return 0
end

local function get_party_tp()
	local out = {}
	local party = windower.ffxi.get_party() or {}
	local keys = { 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, k in ipairs(keys) do
		local e = party[k]
		local mob = e and e.mob
		if mob and mob.id and mob.id ~= 0 then
			out[#out + 1] = {
				id = mob.id,
				name = tostring(mob.name or ''),
				target = get_mob_id_by_index(mob.target_index),
				tp = e.tp or 0,
				status = mob.status or 0,
			}
		end
	end
	return out
end

local aeonic_weapon_names_by_id = {
	[20515] = 'Godhand',
	[20594] = 'Aeneas',
	[20695] = 'Sequence',
	[20843] = 'Chango',
	[20890] = 'Anguta',
	[20935] = 'Trishula',
	[20977] = 'Heishi Shorinken',
	[21025] = 'Dojikiri Yasutsuna',
	[21082] = 'Tishtrya',
	[21147] = 'Khatvanga',
	[21485] = 'Fomalhaut',
	[21694] = 'Lionheart',
	[21753] = 'Tri-Edge',
	[22117] = 'Fail-Not',
	[22131] = 'Fail-Not',
	[22143] = 'Fomalhaut',
}

local function equipped_item_id(equipment, slot_name)
	local bag = equipment and equipment[slot_name .. '_bag']
	local index = equipment and equipment[slot_name]
	if bag == nil or index == nil then
		return 0
	end
	local item = windower.ffxi.get_items(bag, index)
	return tonumber(item and item.id) or 0
end

local function buff_level(buff_ids)
	local level = 0
	for _, buff_id in ipairs(buff_ids or {}) do
		local id = tonumber(buff_id) or 0
		if id >= 270 and id <= 272 then
			level = math.max(level, id - 269)
		end
	end
	return level
end

local function local_skillchain_actor_context()
	local player = windower.ffxi.get_player()
	if not player then
		error('skillchain actor context requires live player data')
	end
	local equipment = windower.ffxi.get_items('equipment')
	if type(equipment) ~= 'table' then
		error('skillchain actor context requires equipment data')
	end
	local main_id = equipped_item_id(equipment, 'main')
	local sub_id = equipped_item_id(equipment, 'sub')
	local range_id = equipped_item_id(equipment, 'range')
	return {
		actor_id = tonumber(player.id) or 0,
		aftermath_level = buff_level(player.buffs),
		diamond_aspis = sub_id == 26488,
		aeonic_weapon_name = aeonic_weapon_names_by_id[main_id] or aeonic_weapon_names_by_id[range_id] or '',
		weapon_signature = ('%d:%d:%d'):format(main_id, sub_id, range_id),
		main_item_id = main_id,
		sub_item_id = sub_id,
		range_item_id = range_id,
	}
end

local function effective_ws_properties(skill, actor_context)
	local properties = {}
	for i = 1, #(skill and skill.skillchain or {}) do
		properties[i] = skill.skillchain[i]
	end
	if skill and skill.aeonic
		and (tonumber(actor_context and actor_context.aftermath_level) or 0) > 0
		and tostring(skill.weapon or '') == tostring(actor_context and actor_context.aeonic_weapon_name or '') then
		properties[#properties + 1] = skill.aeonic
	end
	return properties
end

local function local_ws_candidates(actor_context)
	local player_abilities = windower.ffxi.get_abilities()
	if type(player_abilities) ~= 'table' or type(player_abilities.weapon_skills) ~= 'table' then
		error('skillchain planning requires learned weapon skill data')
	end
	local out = {}
	for _, ws_id in ipairs(player_abilities.weapon_skills) do
		local skill = skills.weapon_skills and skills.weapon_skills[ws_id]
		local ws = res.weapon_skills and res.weapon_skills[ws_id]
		local ws_name = ws and (ws.en or ws.name)
		if skill and type(skill.skillchain) == 'table' and ws_name and ws_name ~= '' then
			out[#out + 1] = {
				ws_id = ws_id,
				ws_name = ws_name,
				effective_properties = effective_ws_properties(skill, actor_context),
			}
		end
	end
	return out
end

local function ws_is_currently_available(ws_id)
	local abilities = windower.ffxi.get_abilities()
	if type(abilities) ~= 'table' or type(abilities.weapon_skills) ~= 'table' then
		return false
	end
	local expected = tonumber(ws_id) or 0
	for _, available_id in ipairs(abilities.weapon_skills) do
		if tonumber(available_id) == expected then
			return true
		end
	end
	return false
end

local function check_buff(t, i)
	if t[i] == true or t[i] - os.time() > 0 then
		return true
	end
	t[i] = nil
	return false
end

local function chain_buff(t)
	local i = t[164] and 164 or t[470] and 470
	if i and check_buff(t, i) then
		t[i] = nil
		return true
	end
	return t[163] and check_buff(t, 163)
end

function core.on_action(act)
	if not act or type(ActionPacket) ~= 'table' or type(ActionPacket.new) ~= 'function' then
		return
	end
	local skillchain_observed_at = os.clock()
	local ok, actionpacket = pcall(ActionPacket.new, act)
	if not ok or not actionpacket then
		return
	end
	local category = actionpacket:get_category_string()
	local actor = actionpacket:get_id()
	local target = actionpacket:get_targets()()
	if not target then
		return
	end
	local action = target:get_actions()()
	if not action then
		return
	end
	local message_id = action:get_message_id()
	local add_effect = action:get_add_effect()
	local param, resource, action_id, interrupted = action:get_spell()
	local ability = skills[resource] and skills[resource][action_id]
	local my_id = (windower.ffxi.get_player() or {}).id
	-- Packet-fed hostile-target evidence supplements live target fields used by Prime and Sleep.
	if actor and target and target.id and tonumber(actor) and tonumber(target.id) and tonumber(actor) > 0 and tonumber(target.id) > 0 then
		local am = windower.ffxi.get_mob_by_id(actor)
		if am and (tonumber(am.spawn_type) or 0) == 16 then
			local observed_target_id = tonumber(target.id) or 0
			local _, friendly_id_set = uc_targeting_common.get_friendly_combat_member_ids()
			for _, raw_target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
				local raw_target_id = tonumber(raw_target and raw_target.id) or 0
				if friendly_id_set[raw_target_id] == true then
					observed_target_id = raw_target_id
					break
				end
			end
			local map = rawget(_G, 'UC_MOB_LAST_ACTION_TARGETS')
			if type(map) ~= 'table' then
				map = {}
				_G.UC_MOB_LAST_ACTION_TARGETS = map
			end
			map[tonumber(actor)] = {
				target_id = observed_target_id,
				at = uc_now_s(),
				category = tostring(category or ''),
			}
		end
	end
	if my_id and actor == my_id and (category == 'job_ability' or category == 'job_ability_unblinkable') then
		local now = uc_now_s()
		core.ja_lock_until = math.max(tonumber(core.ja_lock_until) or 0, now + 0.5)
		local ack_name = tostring((ability and (ability.en or ability.name)) or '')
		if ack_name ~= '' and tostring(core.ja_pending_name or '') == ack_name then
			core.ja_pending_name = ''
			core.ja_pending_recast_id = 0
			core.ja_pending_sent_at = 0
		end
		if ack_name ~= '' then
			core.ja_last_sent_at[ack_name] = now
			debug_ja_dispatch(('ack name="%s" category=%s'):format(ack_name, tostring(category)))
		end
	end
	if my_id and actor == my_id and category == 'spell_finish' and core.pull_spell_waiting == true then
		local ack_name = tostring((ability and (ability.en or ability.name)) or '')
		local pending_name = tostring(core.pull_pending_action or '')
		local pending_tid = tonumber(core.pull_pending_target_id) or 0
		local target_ok = (pending_tid == 0) or (tonumber(target.id) or 0) == pending_tid
		local name_ok = (pending_name == '') or (ack_name ~= '' and pending_name == ack_name)
		if target_ok and name_ok then
			clear_pull_spell_wait_state()
			_G.UC_LAST_BLOCK_REASON = 'PULL_SPELL_COMPLETE'
			_G.UC_WS_LAST_DIAG = ('core pull spell-complete action=%s'):format(ack_name ~= '' and ack_name or pending_name)
		end
	end
	if my_id and actor == my_id and category == 'spell_finish' and core.tank_spell_waiting == true then
		local ack_name = tostring((ability and (ability.en or ability.name)) or '')
		local pending_name = tostring(core.tank_pending_action or '')
		local pending_tid = tonumber(core.tank_pending_target_id) or 0
		local target_ok = (pending_tid == 0) or (tonumber(target.id) or 0) == pending_tid
		local name_ok = (pending_name == '') or (ack_name ~= '' and pending_name == ack_name)
		if target_ok and name_ok then
			clear_tank_spell_wait_state()
			_G.UC_LAST_BLOCK_REASON = 'TANK_SPELL_COMPLETE'
			_G.UC_WS_LAST_DIAG = ('core tank spell-complete action=%s'):format(ack_name ~= '' and ack_name or pending_name)
			debug_tank(_G.UC_WS_LAST_DIAG, true)
		end
	end
	local is_ws_action = (resource == 'weapon_skills') and ability ~= nil
	if is_ws_action and actor ~= my_id and is_party_member_id(actor) and target and target.id and target.id ~= 0 then
		if category ~= 'weaponskill_finish' then
			core.party_ws_hold_target_id = target.id
			core.party_ws_hold_actor_id = actor
			core.party_ws_hold_until = uc_now_s() + PARTY_WS_HOLD_WINDOW
			core.party_ws_hold_category = tostring(category or '')
			core.party_ws_hold_name = tostring((ability and (ability.en or ability.name)) or '')
		else
			local held_tid = tonumber(core.party_ws_hold_target_id) or 0
			local held_actor = tonumber(core.party_ws_hold_actor_id) or 0
			if held_tid ~= 0 and held_tid == target.id and held_actor == actor then
				core.party_ws_hold_target_id = 0
				core.party_ws_hold_actor_id = 0
				core.party_ws_hold_until = 0
				core.party_ws_hold_category = ''
				core.party_ws_hold_name = ''
			end
		end
	end
	if not action_categories[category] or act.param == 0 then
		return
	end

	local server_skillchain = add_effect and skillchain_ids[add_effect.message_id]
	local chain_affinity_success = ability and message_id == 2 and core.buffs[actor] and chain_buff(core.buffs[actor])
	local has_properties = ability and type(ability.skillchain) == 'table' and #ability.skillchain > 0
	local action_success = uc_skillchain_state.action_succeeded({
		server_result = server_skillchain and true or false,
		message_success = action_message_ids[message_id] == true,
		chain_affinity_success = chain_affinity_success and true or false,
		chainbound_level = message_id == 529 and param or 0,
	})
	local should_observe_skillchain = uc_skillchain_state.should_observe_action({
		source_resource = resource,
		has_properties = has_properties and true or false,
		server_result = server_skillchain and true or false,
		chain_affinity_success = chain_affinity_success and true or false,
		chainbound_level = message_id == 529 and param or 0,
	})
	if should_observe_skillchain and target and (tonumber(target.id) or 0) > 0 then
		local actor_context = {
			actor_id = tonumber(actor) or 0,
			aftermath_level = 0,
			diamond_aspis = false,
			weapon_signature = '',
		}
		if tonumber(actor) == tonumber(my_id) then
			actor_context = local_skillchain_actor_context()
		end
		local properties = {}
		if message_id == 529 then
			properties = chainbound[param] or {}
		elseif ability and type(ability.skillchain) == 'table' then
			if resource == 'weapon_skills' and tonumber(actor) == tonumber(my_id) then
				properties = effective_ws_properties(ability, actor_context)
			else
				for i = 1, #ability.skillchain do
					properties[i] = ability.skillchain[i]
				end
			end
		end
		local resource_action = res[resource] and res[resource][action_id]
		local action_name = tostring(
			(ability and (ability.en or ability.name))
			or (resource_action and (resource_action.en or resource_action.name))
			or ''
		)
		local expires_at_override = nil
		if message_id == 529 then
			expires_at_override = uc_skillchain_state.chainbound_expires_at(action_id, skillchain_observed_at)
		end
		local server_result = server_skillchain and add_effect.animation and add_effect.animation:ucfirst() or ''
		local server_level = uc_skillchain_state.property_level(server_result)
		skillchain_runtime:observe_action_result({
			success = action_success and true or false,
			interrupted = interrupted == true,
			target_id = target.id,
			actor_id = actor,
			action_id = action_id,
			action_name = action_name,
			source_resource = resource,
			effective_properties = properties,
			server_result = server_result,
			server_result_level = server_level,
			delay = message_id == 529 and uc_skillchain_state.CHAINBOUND_DELAY_S or ((ability and ability.delay) or uc_skillchain_state.ORDINARY_WS_MIN_DELAY_S),
			chainbound_level = message_id == 529 and param or 0,
			expires_at_override = expires_at_override,
			actor_has_diamond_aspis = actor_context.diamond_aspis,
			actor_context = actor_context,
			message_id = message_id,
			observed_at = skillchain_observed_at,
		})
	end
	if message_id == 100 and buff_dur[param] then
		core.buffs[actor] = core.buffs[actor] or {}
		core.buffs[actor][param] = buff_dur[param] + os.time()
	end

	if my_id and actor == my_id and resource == 'weapon_skills' then
		-- no-op placeholder for future ws diagnostics
	end
end

function core.on_action_message(msg)
	if type(msg) ~= 'table' then
		return
	end
	local mid = tonumber(msg.message_id) or 0
	local tid = tonumber(msg.target_id) or 0
	local aid = tonumber(msg.actor_id) or 0
	if tid > 0 and death_message_ids[mid] then
		core.last_death_target_id = tid
		core.last_death_at = uc_now_s()
		skillchain_runtime:clear_target(tid, 'death')
	end
	if core.pull_spell_waiting == true then
		local my_id = tonumber((windower.ffxi.get_player() or {}).id) or 0
		local pending_tid = tonumber(core.pull_pending_target_id) or 0
		local actor_ok = (my_id > 0 and aid == my_id)
		local target_ok = (pending_tid == 0) or (tid > 0 and tid == pending_tid)
		if actor_ok and target_ok and mid ~= 0 then
			if spell_initiating_message_ids[mid] then
				-- Casting started/initiated: remain in pull-spell wait.
				_G.UC_PULL_SPELL_WAITING = true
				_G.UC_LAST_BLOCK_REASON = 'PULL_SPELL_WAITING'
				_G.UC_WS_LAST_DIAG = ('core pull spell-msg init mid=%d'):format(mid)
			elseif spell_success_message_ids[mid] then
				clear_pull_spell_wait_state()
				_G.UC_LAST_BLOCK_REASON = 'PULL_SPELL_COMPLETE'
				_G.UC_WS_LAST_DIAG = ('core pull spell-msg success mid=%d'):format(mid)
			else
				-- Includes out-of-range / invalid-cast style failures: end wait immediately
				-- so pull flow can move into range and retry.
				clear_pull_spell_wait_state()
				_G.UC_LAST_BLOCK_REASON = 'PULL_SPELL_RETRY'
				_G.UC_WS_LAST_DIAG = ('core pull spell-msg retry mid=%d'):format(mid)
			end
		end
	end
	if core.tank_spell_waiting == true then
		local my_id = tonumber((windower.ffxi.get_player() or {}).id) or 0
		local pending_tid = tonumber(core.tank_pending_target_id) or 0
		local actor_ok = (my_id > 0 and aid == my_id)
		local target_ok = (pending_tid == 0) or (tid > 0 and tid == pending_tid)
		if actor_ok and target_ok and mid ~= 0 then
			if spell_initiating_message_ids[mid] then
				_G.UC_LAST_BLOCK_REASON = 'TANK_SPELL_WAITING'
				_G.UC_WS_LAST_DIAG = ('core tank spell-msg init mid=%d'):format(mid)
				debug_tank(_G.UC_WS_LAST_DIAG)
			elseif spell_success_message_ids[mid] then
				clear_tank_spell_wait_state()
				_G.UC_LAST_BLOCK_REASON = 'TANK_SPELL_COMPLETE'
				_G.UC_WS_LAST_DIAG = ('core tank spell-msg success mid=%d'):format(mid)
				debug_tank(_G.UC_WS_LAST_DIAG, true)
			else
				clear_tank_spell_wait_state()
				_G.UC_LAST_BLOCK_REASON = 'TANK_SPELL_RETRY'
				_G.UC_WS_LAST_DIAG = ('core tank spell-msg retry mid=%d'):format(mid)
				debug_tank(_G.UC_WS_LAST_DIAG)
			end
		end
	end
end

function core.on_ipc_message(msg)
	if type(msg) ~= 'string' or msg == '' then
		return
	end
	if msg:sub(1, #WS_HOLD_PREFIX) == WS_HOLD_PREFIX then
		local parts = split_pipe(msg)
		if #parts >= 4 then
			local sender_id = tonumber(parts[2]) or 0
			local target_id = tonumber(parts[3]) or 0
			local hold_until = tonumber(parts[4]) or 0
			local my_id = get_my_player_id()
			if sender_id > 0 and sender_id ~= my_id and target_id > 0 and hold_until > uc_now_s() then
				core.ws_hold_remote[sender_id] = {
					target_id = target_id,
					until_ts = hold_until,
					seen_at = uc_now_s(),
				}
			end
		end
		return
	end
	if msg:sub(1, #WS_INTENT_PREFIX) ~= WS_INTENT_PREFIX then
		return
	end
	local parts = split_pipe(msg)
	if #parts < 4 then
		return
	end
	local sender_id = tonumber(parts[2]) or 0
	local target_id = tonumber(parts[3]) or 0
	local ws_name = tostring(parts[4] or '')
	if sender_id <= 0 or target_id <= 0 or ws_name == '' then
		return
	end
	local my_id = get_my_player_id()
	if my_id > 0 and sender_id == my_id then
		return
	end
	local now = uc_now_s()
	core.ws_intent_remote_target_id = target_id
	core.ws_intent_remote_name = ws_name
	core.ws_intent_remote_actor_id = sender_id
	core.ws_intent_remote_until = now + WS_INTENT_REMOTE_HOLD
	local pending_tid = tonumber(core.ws_intent_pending_target_id) or 0
	local pending_ws = tostring(core.ws_intent_pending_name or '')
	if pending_tid == target_id and pending_ws == ws_name and my_id > 0 and sender_id < my_id then
		core.ws_intent_loser_cooldown_until = now + WS_INTENT_LOSER_COOLDOWN
		core.ws_intent_loser_actor_id = sender_id
		ws_intent_clear_pending()
		_G.UC_WS_LAST_DIAG = ('core ws intent lose_tiebreak to=%d ws=%s tid=%d'):format(sender_id, ws_name, target_id)
	end
end

local function can_cast_ja(name)
	local ja = res.job_abilities:with('en', name)
	if not ja then
		debug_ja_gate(name, 'JA_UNKNOWN')
		return false
	end
	local player = windower.ffxi.get_player()
	if status_blocks_actions(player and player.status) then
		debug_ja_gate(name, 'ACTION_BLOCK_STATUS3')
		return false
	end
	local requires_engaged_front = ja_requires_engaged_front(name, ja)
	if requires_engaged_front and (tonumber(player and player.status) or 0) ~= 1 then
		debug_ja_gate(name, 'JA_REQUIRES_ENGAGED')
		return false
	end
	local now = uc_now_s()
	if now < (tonumber(core.ja_lock_until) or 0) then
		debug_ja_gate(name, 'JA_LOCK_ACTIVE')
		return false
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	local pending_name = tostring(core.ja_pending_name or '')
	if pending_name ~= '' and pending_name == tostring(name) then
		local pending_recast = tonumber(core.ja_pending_recast_id) or 0
		local pending_started = (pending_recast > 0 and (recasts[pending_recast] or 0) > 0)
		if pending_started then
			core.ja_pending_name = ''
			core.ja_pending_recast_id = 0
			core.ja_pending_sent_at = 0
			core.ja_lock_until = math.max(tonumber(core.ja_lock_until) or 0, now + 0.5)
			debug_ja_gate(name, 'PENDING_RECAST_STARTED')
			return false
		end
		local sent_at = tonumber(core.ja_pending_sent_at) or 0
		if sent_at > 0 and (now - sent_at) < 0.5 then
			debug_ja_gate(name, 'PENDING_RECENT_SEND')
			return false
		end
		core.ja_pending_name = ''
		core.ja_pending_recast_id = 0
		core.ja_pending_sent_at = 0
	end
	local last_sent = tonumber((core.ja_last_sent_at or {})[tostring(name)]) or 0
	if last_sent > 0 and (now - last_sent) < 0.5 then
		debug_ja_gate(name, 'LAST_SENT_WINDOW')
		return false
	end
	if (recasts[ja.recast_id] or 0) > 0 then
		debug_ja_gate(name, 'JA_RECAST')
		return false
	end
	local abil = windower.ffxi.get_abilities() or {}
	local owns = false
	for _, id in ipairs(abil.job_abilities or {}) do
		if id == ja.id then
			owns = true
			break
		end
	end
	if not owns then
		debug_ja_gate(name, 'JA_NOT_OWNED')
		return false
	end
	if tostring(name or ''):lower() == 'chivalry' then
		local tp = tonumber(((p or {}).vitals or {}).tp) or 0
		if tp < CHIVALRY_MIN_TP then
			debug_ja_gate(name, 'CHIVALRY_TP_LOW', ('tp=%d need=%d'):format(tp, CHIVALRY_MIN_TP))
			return false
		end
		local mp = tonumber(((p or {}).vitals or {}).mp) or 0
		local mmp = tonumber(((p or {}).vitals or {}).max_mp) or 0
		local mp_pct = (mmp > 0) and ((mp / mmp) * 100.0) or 100.0
		if mp_pct >= CHIVALRY_MAX_MP_PCT then
			debug_ja_gate(name, 'CHIVALRY_MP_TOO_HIGH', ('mp=%d max=%d mp_pct=%.1f need<%d'):format(mp, mmp, mp_pct, CHIVALRY_MAX_MP_PCT))
			return false
		end
	end
	local t = get_current_target()
	if ja_targets_enemy(ja) then
		if not t or t.id == 0 or not t.valid_target or tonumber(t.spawn_type) ~= 16 or (tonumber(t.hpp) or 0) <= 0 then
			debug_ja_gate(name, 'NO_TARGET')
			return false
		end
		local d = target_distance(t)
		local r = action_effective_range(ja.range)
		if r > 0 and d > r then
			debug_ja_gate(name, 'OUT_OF_RANGE', ('dist=%.2f range=%.2f'):format(tonumber(d) or 0, tonumber(r) or 0))
			return false
		end
		if requires_engaged_front and not target_is_in_front_arc(t, math.pi / 2) then
			debug_ja_gate(name, 'TARGET_NOT_IN_FRONT')
			return false
		end
	end
	debug_ja_gate(name, 'READY')
	return true
end

local function cast_ja(name)
	local ja = res.job_abilities:with('en', name)
	if not ja then
		return
	end
	local now = uc_now_s()
	core.ja_pending_name = tostring(name or '')
	core.ja_pending_recast_id = tonumber(ja.recast_id) or 0
	core.ja_pending_sent_at = now
	core.ja_lock_until = math.max(tonumber(core.ja_lock_until) or 0, now + 0.5)
	core.ja_last_sent_at[tostring(name or '')] = now
	if tostring(name or ''):lower() == 'chivalry' then
		core.chivalry_hold_until = math.max(tonumber(core.chivalry_hold_until) or 0, now + 1.25)
	end
	local p = windower.ffxi.get_player() or {}
	local status = tonumber(p.status) or 0
	local tp = (((p or {}).vitals or {}).tp) or 0
	local cur = get_current_target()
	local cur_id = (cur and cur.id) or 0
	local cur_name = (cur and cur.name) or ''
	local cur_dist = (cur and target_distance(cur)) or 0
	local target_desc = tostring(ja.targets or '')
	if tostring(ja.targets) == '{Self}' or tostring(ja.targets) == '{Self, Player}' then
		debug_ja_dispatch(('send name="%s" mode=self status=%d tp=%d cur=%d "%s" dist=%.2f'):format(
			tostring(name),
			status,
			tp,
			tonumber(cur_id) or 0,
			tostring(cur_name),
			tonumber(cur_dist) or 0
		))
		windower.send_command('input /ja "' .. name .. '" <me>')
	else
		local t = get_current_target()
		if t and t.id and t.id ~= 0 then
			local tdist = target_distance(t)
			debug_ja_dispatch(('send name="%s" mode=target ja_targets=%s status=%d tp=%d tid=%d "%s" dist=%.2f'):format(
				tostring(name),
				target_desc,
				status,
				tp,
				tonumber(t.id) or 0,
				tostring(t.name or ''),
				tonumber(tdist) or 0
			))
			windower.send_command('input /ja "' .. name .. '" ' .. tostring(t.id))
		else
			debug_ja_dispatch(('skip name="%s" mode=target reason=NO_CURRENT_TARGET ja_targets=%s status=%d tp=%d'):format(
				tostring(name),
				target_desc,
				status,
				tp
			))
		end
	end
end

local function chivalry_ws_reservation_reason(settings, player)
	if not setting_enabled(settings and settings.ability_active) then
		return nil
	end
	if not player or not player.vitals then
		return nil
	end
	local now = uc_now_s()
	if now < (tonumber(core.chivalry_hold_until) or 0) then
		return 'CHIVALRY_WAIT'
	end
	local abilities = uc_ability_pipeline.collect_ordered(settings or {}, 6)
	local has_chivalry = false
	for _, ability in ipairs(abilities) do
		if tostring(ability or ''):lower() == 'chivalry' then
			has_chivalry = true
			break
		end
	end
	if not has_chivalry then
		return nil
	end
	local ja = res.job_abilities:with('en', 'Chivalry')
	if not ja then
		return nil
	end
	local abil = windower.ffxi.get_abilities() or {}
	local owns = false
	for _, id in ipairs(abil.job_abilities or {}) do
		if id == ja.id then
			owns = true
			break
		end
	end
	if not owns then
		return nil
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	if (recasts[ja.recast_id] or 0) > 0 then
		return nil
	end
	local mp = tonumber(player.vitals.mp) or 0
	local mmp = tonumber(player.vitals.max_mp) or 0
	local mp_pct = (mmp > 0) and ((mp / mmp) * 100.0) or 100.0
	if mp_pct >= CHIVALRY_MAX_MP_PCT then
		return nil
	end
	local tp = tonumber(player.vitals.tp) or 0
	if tp < CHIVALRY_MIN_TP then
		return 'CHIVALRY_HOLD_TP'
	end
	return 'CHIVALRY_READY'
end

local function select_aftermath_maintenance_ws(settings, player)
	if not setting_enabled(settings and settings.aftermath_enabled) then
		return nil, nil
	end
	local am_ws = tostring(settings.aftermath_ws or '')
	if am_ws == '' then
		return nil, nil
	end
	local weapon_name, weapon = aftermath_table.get_weapon_by_ws(am_ws)
	if not weapon_name or type(weapon) ~= 'table' then
		return '', 'AM_WS_UNMAPPED'
	end
	local profile = weapon.aftermath
	local stage = tonumber(weapon.minimum_aftermath_stage) or 3
	local stage_info = profile and profile.tp and profile.tp[stage] or nil
	local required_buff_id = tonumber(stage_info and stage_info.buff_id) or 0
	if required_buff_id <= 0 then
		return '', 'AM_PROFILE_INVALID'
	end
	for _, bid in ipairs(player.buffs or {}) do
		if tonumber(bid) == required_buff_id then
			return nil, nil
		end
	end
	if not uc_ws_memory.valid_ws_name(am_ws) then
		return '', 'AM_WS_INVALID'
	end
	local tp = tonumber(player.vitals and player.vitals.tp) or 0
	if tp >= 3000 then
		return am_ws, 'AM_READY'
	end
	return '', 'AM_HOLD_TP'
end

local function get_ws_mode(settings)
	local mode = tostring((settings and settings.ws_mode) or 'smart'):lower()
	if mode == 'primary_no_sc' then
		return mode
	end
	return 'smart'
end

local function select_smart_ws(settings, target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return '', 'NO_TARGET'
	end
	local player = windower.ffxi.get_player() or {}
	local spam_on = setting_enabled(settings.spam) or setting_enabled(settings.solo)
	if not spam_on then
		local hold_tid = tonumber(core.party_ws_hold_target_id) or 0
		if hold_tid ~= 0 and hold_tid == tid then
			local hold_until = tonumber(core.party_ws_hold_until) or 0
			local now = uc_now_s()
			if now < hold_until then
				return '', ('ALLY_WS_READY_HOLD:%s:%s'):format(
					tostring(core.party_ws_hold_name or ''),
					tostring(core.party_ws_hold_category or '')
				)
			end
			core.party_ws_hold_target_id = 0
			core.party_ws_hold_actor_id = 0
			core.party_ws_hold_until = 0
			core.party_ws_hold_category = ''
			core.party_ws_hold_name = ''
		end
	end
	local ws_mode = get_ws_mode(settings)
	local primary_ws = tostring(settings.weaponskill or settings.ws1 or '')
	if spam_on then
		if primary_ws == '' or not uc_ws_memory.valid_ws_name(primary_ws) then
			return '', 'PRIMARY_WS_INVALID'
		end
		return primary_ws, 'READY_SPAM'
	end
	local actor_context = local_skillchain_actor_context()
	local state = skillchain_runtime:get_state(tid)
	local now = os.clock()
	local resonance_active = state
		and state.terminal ~= true
		and now <= skillchain_runtime:expiry_for_actor(tid, actor_context.actor_id)
	if ws_mode == 'primary_no_sc' then
		if primary_ws == '' or not uc_ws_memory.valid_ws_name(primary_ws) then
			return '', 'PRIMARY_WS_INVALID'
		end
		if resonance_active or (state and state.terminal == true and now < (tonumber(state.magic_burst_expires_at) or 0)) then
			return '', 'WS_MODE_PRIMARY_ONLY_SC_HOLD'
		end
		return primary_ws, 'WS_MODE_PRIMARY_ONLY_READY'
	end
	if state and state.terminal == true and now < (tonumber(state.magic_burst_expires_at) or 0) then
		return '', 'SC_TERMINAL'
	end
	local chivalry_reason = chivalry_ws_reservation_reason(settings, player)
	if chivalry_reason then
		return '', chivalry_reason
	end
	local aftermath_ws, aftermath_reason = select_aftermath_maintenance_ws(settings, player)
	if aftermath_reason then
		return aftermath_ws, aftermath_reason
	end
	if resonance_active then
		local plan, plan_reason = skillchain_runtime:plan_continuation(
			tid,
			local_ws_candidates(actor_context),
			actor_context,
			now
		)
		if plan and (plan_reason == 'SC_READY'
			or plan_reason == 'SC_WINDOW_HIGH_RISK'
			or plan_reason == 'SC_NOT_READY'
			or plan_reason == 'SC_DISPATCH_PENDING_RESULT') then
			return plan.ws_name, plan_reason, plan
		end
		local hold_until = skillchain_runtime:expiry_for_actor(tid, actor_context.actor_id)
		ws_hold_emit(tid, uc_now_s() + math.max(0, hold_until - now))
		return '', plan_reason
	end
	local my_tp = ((windower.ffxi.get_player() or {}).vitals or {}).tp or 0
	local my_id = (windower.ffxi.get_player() or {}).id or 0
	for _, value in ipairs(get_party_tp()) do
		if value.id ~= my_id and not uc_ignore.is_name_blocked(settings, value.name) then
			local ally_holding_sc = ws_hold_remote_active_for(value.id, tid)
			local ally_ws_ready = (value.tp or 0) >= 1000
			local ally_far_ahead = (value.tp or 0) >= (my_tp + 300)
			if (not ally_holding_sc) and value.target == tid and ally_ws_ready and ally_far_ahead and value.status == 1 then
				return '', 'ALLY_WAIT'
			end
		end
	end

	if primary_ws == '' or not uc_ws_memory.valid_ws_name(primary_ws) then
		return '', 'PRIMARY_WS_INVALID'
	end
	return primary_ws, 'READY'
end

local function run_unified_combat()
	set_preengage_approach_active(false)
	local s = get_settings()
	local p = windower.ffxi.get_player()
	if not p then
		_G.UC_WS_LAST_DIAG = 'core ws reason=NO_PLAYER'
		return
	end
	if setting_enabled(s.tank) then
		local now_dbg = uc_now_s()
		local last_dbg = tonumber(core.tank_tick_log_at) or 0
		if (now_dbg - last_dbg) >= 1.0 then
			core.tank_tick_log_at = now_dbg
			debug_tank(('tick status=%s autotarget=%s puller=%s hunter=%s'):format(
				tostring(p.status or 0),
				tostring(setting_enabled(s.autotarget)),
				tostring(setting_enabled(s.puller)),
				tostring(setting_enabled(s.hunter) and setting_enabled(s.path_follow_enabled))
			), true)
		end
	end
	_G.UC_WS_LAST_DIAG = 'core ws reason=PENDING'
	local combat_participant = false
	if type(rawget(_G, 'UC_IsCombatParticipant')) == 'function' then
		combat_participant = (_G.UC_IsCombatParticipant(s) == true)
	else
		combat_participant = setting_enabled(s.autotarget)
			or setting_enabled(s.move)
			or setting_enabled(s.tank)
			or (setting_enabled(s.hunter) and setting_enabled(s.path_follow_enabled))
			or setting_enabled(s.puller)
			or setting_enabled(s.add_control)
	end
	local now_status = p.status or 0
	if combat_participant and setting_enabled(s.autotarget) and now_status == 1 then
		_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL = uc_now_s() + party_follow_hold_seconds(s)
	end
	local now = uc_now_s()
	if core.pull_spell_waiting == true then
		if now < (tonumber(core.pull_spell_wait_until) or 0) then
			windower.ffxi.run(false)
			core.last_run_active = false
			set_movement_owner('core', 0.6)
			_G.UC_PULL_SPELL_WAITING = true
			_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.6
			_G.UC_LAST_BLOCK_REASON = 'PULL_SPELL_WAITING'
			_G.UC_WS_LAST_DIAG = ('core pull spell-wait action=%s'):format(tostring(core.pull_pending_action or ''))
			return
		end
		clear_pull_spell_wait_state()
	end
	-- Tank enmity spell wait is global movement/action lock until completion or timeout.
	-- This must apply even if the current violation disappears, otherwise normal movement
	-- can resume and self-interrupt the in-progress enmity cast.
	if core.tank_spell_waiting == true then
		if now < (tonumber(core.tank_spell_wait_until) or 0) then
			windower.ffxi.run(false)
			core.last_run_active = false
			set_movement_owner('core', 0.6)
			_G.UC_LAST_BLOCK_REASON = 'TANK_SPELL_WAITING'
			_G.UC_WS_LAST_DIAG = ('core tank spell-wait action=%s'):format(tostring(core.tank_pending_action or ''))
			debug_tank(_G.UC_WS_LAST_DIAG)
			return
		end
		clear_tank_spell_wait_state()
	end
	if now_status ~= 1 then
		if (core.last_player_status or 0) == 1 then
			-- Engagement just dropped; keep sticky target briefly to absorb status jitter.
			core.sticky_hold_until = now + 1.2
		elseif now > (tonumber(core.sticky_hold_until) or 0) then
			core.sticky_target_id = 0
		end
	elseif (core.last_player_status or 0) ~= 1 then
		-- just engaged: seed sticky target once; do not keep rewriting it every tick
		local cur = get_current_target()
		if cur and cur.valid_target and (cur.hpp or 0) > 0 and cur.spawn_type == 16 then
			core.sticky_target_id = cur.id
		end
		core.sticky_hold_until = 0
	end
	core.last_player_status = now_status
	-- Scheduler combat ownership short-circuit:
	-- avoid heavy target scans/arbitration/WS selection in core when scheduler combat dispatch is active.
	if setting_enabled(s.scheduler_dark_launch_combat) then
		local cur = get_current_target()
		apply_facing(s, cur)
		if not setting_enabled(s.scheduler_dark_launch_movement) then
			apply_movement(s, cur)
		end
		_G.UC_WS_LAST_DIAG = 'core ws reason=SCHED_COMBAT_OWNED'
		return
	end
	-- Hard partner arbitration while engaged:
	-- if two configured partners are actively on the same live mob, higher player id must yield.
	do
		local my_id = tonumber(p.id) or 0
		local cur_live = get_current_target()
		if setting_enabled(s.partner) and my_id > 0 and now_status == 1 and cur_live and cur_live.valid_target and
			(tonumber(cur_live.spawn_type) or 0) == 16 and (tonumber(cur_live.hpp) or 0) > 0 then
			local partner_ids = uc_partner_list.as_ordered_ids(s)
			local lowest_partner_on_cur = 0
			for _, pid in ipairs(partner_ids) do
				local pm = windower.ffxi.get_mob_by_id(pid)
				if pm and (tonumber(pm.status) or 0) == 1 and pm.target_index then
					local tm = windower.ffxi.get_mob_by_index(pm.target_index)
					if tm and (tonumber(tm.id) or 0) == (tonumber(cur_live.id) or 0) and tm.valid_target and (tonumber(tm.hpp) or 0) > 0 then
						if lowest_partner_on_cur == 0 or pid < lowest_partner_on_cur then
							lowest_partner_on_cur = pid
						end
					end
				end
			end
			if lowest_partner_on_cur > 0 and my_id > lowest_partner_on_cur and setting_enabled(s.autotarget) then
				local claims, claims_set = uc_targeting_common.build_friendly_claims()
				local marray = windower.ffxi.get_mob_array() or {}
				local best = nil
				local best_dist = 1e9
				for _, mob in pairs(marray) do
					if mob and mob.id and mob.id ~= cur_live.id and mob.valid_target and (tonumber(mob.spawn_type) or 0) == 16 and (tonumber(mob.hpp) or 0) > 0 then
						if not uc_target_ignore.is_mob_blocked(s, mob) then
							local claimed_ok = claims_set[tonumber(mob.claim_id) or 0] == true
							if claimed_ok then
								local partner_on_mob = false
								for _, pid in ipairs(partner_ids) do
									local pm = windower.ffxi.get_mob_by_id(pid)
									if pm and (tonumber(pm.status) or 0) == 1 and pm.target_index then
										local tm = windower.ffxi.get_mob_by_index(pm.target_index)
										if tm and (tonumber(tm.id) or 0) == (tonumber(mob.id) or 0) and tm.valid_target and (tonumber(tm.hpp) or 0) > 0 then
											partner_on_mob = true
											break
										end
									end
								end
								if not partner_on_mob then
									local d = target_distance(mob)
									if d < best_dist then
										best_dist = d
										best = mob
									end
								end
							end
						end
					end
				end
				if best and best.id and best.id ~= 0 then
					local ok_sw = uc_attack.switch_target(best.id)
					if ok_sw then
						core.sticky_target_id = best.id
						core.sticky_hold_until = 0
						_G.UC_LAST_BLOCK_REASON = 'PARTNER_TIEBREAK_SWITCH'
						_G.UC_WS_LAST_DIAG = ('core partner tiebreak yield my=%d winner=%d from=%d to=%d'):format(
							my_id, lowest_partner_on_cur, tonumber(cur_live.id) or 0, tonumber(best.id) or 0
						)
					end
				else
					uc_attack.disengage()
					core.sticky_target_id = 0
					core.sticky_hold_until = 0
					_G.UC_LAST_BLOCK_REASON = 'PARTNER_TIEBREAK_DISENGAGE'
					_G.UC_WS_LAST_DIAG = ('core partner tiebreak disengage my=%d winner=%d mob=%d'):format(
						my_id, lowest_partner_on_cur, tonumber(cur_live.id) or 0
					)
					return
				end
			end
		end
	end
	local sched_target_owned = setting_enabled(s.scheduler_dark_launch_combat) and setting_enabled(s.autotarget)
	local target = nil
	if sched_target_owned then
		-- G3 cutover step: when scheduler combat dark-launch is active, target acquisition
		-- ownership is scheduler-driven (target_control proposals). Core consumes currently
		-- selected target only and does not run nearest-scan arbitration.
		local cur = get_current_target()
		if cur and cur.valid_target and tonumber(cur.spawn_type) == 16 and (tonumber(cur.hpp) or 0) > 0 then
			target = cur
		end
	else
		target = find_candidate_target(s)
	end
	local path_hunter_filter_active = setting_enabled(s.hunter) and setting_enabled(s.path_follow_enabled)
	local claim_timeout = tonumber(s.path_hunter_claim_timeout_s) or 4.0
	local ignore_cooldown = tonumber(s.path_hunter_ignore_cooldown_s) or 20.0
	if claim_timeout < 0.5 then
		claim_timeout = 0.5
	elseif claim_timeout > 30 then
		claim_timeout = 30
	end
	if ignore_cooldown < 0 then
		ignore_cooldown = 0
	elseif ignore_cooldown > 120 then
		ignore_cooldown = 120
	end
	if not target and not setting_enabled(s.manual) then
		-- Tank fallback: if normal target selection yields none, still attempt to acquire
		-- a live violation target (mob attacking a non-tank party member).
		if (not sched_target_owned) and setting_enabled(s.tank) and setting_enabled(s.autotarget) then
			local tank_violation_fallback = pick_tank_violation_target(s, p)
			if tank_violation_fallback and tank_violation_fallback.mob and tank_violation_fallback.mob.id and tank_violation_fallback.mob.id ~= 0 then
				target = windower.ffxi.get_mob_by_id(tank_violation_fallback.mob.id) or tank_violation_fallback.mob
				_G.UC_LAST_BLOCK_REASON = 'TANK_FALLBACK_TARGET'
				_G.UC_WS_LAST_DIAG = ('core tank fallback-target mob=%s victim=%s(%s%%)'):format(
					tostring((target and target.name) or '?'),
					tostring((tank_violation_fallback.victim and tank_violation_fallback.victim.name) or '?'),
					tostring(tonumber(tank_violation_fallback.victim_hpp) or 0)
				)
				debug_tank(_G.UC_WS_LAST_DIAG, true)
			end
		end
		if not target then
			if path_hunter_filter_active then
				core.hunter_acquire.target_id = 0
				core.hunter_acquire.started_at = 0
			end
			-- No live target: pull wait/approach flags are stale and must be cleared so
			-- out-of-combat path follow can resume immediately.
			clear_pull_spell_wait_state()
			_G.UC_PULL_APPROACH_UNTIL = 0
			set_preengage_approach_active(false)
			-- Path-hunter route follow pauses while engaged. If no valid combat target remains,
			-- force disengage so path-follow can immediately resume after kill.
			if path_hunter_filter_active and (tonumber(p and p.status) or 0) == 1 then
				uc_attack.disengage()
			end
			_G.UC_COMBAT_INTENT_UNTIL = 0
			if core.last_run_active then
				stop_run()
			end
			_G.UC_LAST_BLOCK_REASON = 'NO_TARGET'
			_G.UC_WS_LAST_DIAG = 'core ws reason=NO_TARGET'
			if setting_enabled(s.tank) then
				debug_tank('tick no_target')
			end
			return
		end
	end
	if target and target.id and target.id ~= 0 then
		-- Hold a short combat-intent window so party-follow does not fight approach movement
		-- during post-kill re-engage delay.
		if combat_participant and setting_enabled(s.autotarget) then
			_G.UC_COMBAT_INTENT_UNTIL = uc_now_s() + 0.8
			_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL = uc_now_s() + party_follow_hold_seconds(s)
			set_movement_owner('core', 0.8)
		end
	end
	local tid = target and target.id or 0
	if path_hunter_filter_active and tid > 0 then
		local now = uc_now_s()
		if (tonumber(core.hunter_acquire.target_id) or 0) ~= tid then
			core.hunter_acquire.target_id = tid
			core.hunter_acquire.started_at = now
		else
			local mob = windower.ffxi.get_mob_by_id(tid)
			local claims, claims_set = uc_targeting_common.build_friendly_claims()
			local claimed = mob and claims_set[mob.claim_id] == true
			if not claimed and (p.status or 0) ~= 1 then
				local pull_wait_same_target = (core.pull_spell_waiting == true) and ((tonumber(core.pull_pending_target_id) or 0) == tid)
				if pull_wait_same_target then
					core.hunter_acquire.started_at = now
				end
				local started = tonumber(core.hunter_acquire.started_at) or now
				if (not pull_wait_same_target) and (now - started) >= claim_timeout then
					if ignore_cooldown > 0 then
						core.hunter_ignore_until_by_id[tid] = now + ignore_cooldown
					end
					core.hunter_acquire.target_id = 0
					core.hunter_acquire.started_at = 0
					_G.UC_COMBAT_INTENT_UNTIL = 0
					_G.UC_LAST_BLOCK_REASON = 'HUNTER_ACQUIRE_TIMEOUT'
					_G.UC_WS_LAST_DIAG = ('core hunter timeout tid=%d cooldown=%.1f'):format(tid, ignore_cooldown)
					if core.last_run_active then
						stop_run()
					end
					return
				end
			else
				core.hunter_acquire.target_id = 0
				core.hunter_acquire.started_at = 0
			end
		end
	elseif path_hunter_filter_active then
		core.hunter_acquire.target_id = 0
		core.hunter_acquire.started_at = 0
	end
	if tid > 0 and setting_enabled(s.autotarget) and (not setting_enabled(s.scheduler_dark_launch_combat)) then
		local pull_handled = try_pull_action(s, p, target)
		if pull_handled then
			if setting_enabled(s.tank) then
				debug_tank(('tick bypass_tank reason=pull_handled tid=%d'):format(tonumber(tid) or 0), true)
			end
			return
		end
	end
	local current_before = get_current_target()
	local current_dead = current_before and current_before.spawn_type == 16 and ((current_before.hpp or 0) <= 0)
	local switched_on_kill = false
	local incumbent_same_target = false
	if tid > 0 and p and (tonumber(p.status) or 0) == 1 then
		local cur_live = get_current_target()
		if cur_live and cur_live.valid_target and (tonumber(cur_live.hpp) or 0) > 0 and tonumber(cur_live.spawn_type) == 16 and
			(tonumber(cur_live.id) or 0) == tid then
			incumbent_same_target = true
		end
	end
	if tid > 0 and (not incumbent_same_target) and target_is_partner_claimed(s, tid) then
		-- Re-check partner target exclusion at commit time so death fast-switch can't
		-- re-lock us onto a partner target selected from a stale snapshot.
		tid = 0
		target = nil
	end
	if setting_enabled(s.autotarget) and current_dead and tid > 0 and
		(not current_before or current_before.id ~= tid) then
		local ok_sw = uc_attack.switch_target(tid)
		if ok_sw then
			core.sticky_target_id = tid
			core.sticky_hold_until = 0
			switched_on_kill = true
			_G.UC_WS_LAST_DIAG = ('core death fast-switch from=%d to=%d status=%d'):format(
				tonumber(current_before and current_before.id) or 0,
				tonumber(tid) or 0,
				tonumber(p and p.status) or 0
			)
		end
	end
	if tid > 0 and setting_enabled(s.autotarget) then
		local ok_target = ensure_target_and_attack(tid)
		if not ok_target then
			if switched_on_kill then
				_G.UC_WS_LAST_DIAG = 'core ws reason=TARGET_PREP_FAIL_AFTER_DEATH_SWITCH'
			else
				_G.UC_WS_LAST_DIAG = 'core ws reason=TARGET_PREP_FAIL'
			end
		end
	end
	local tank_violation = pick_tank_violation_target(s, p)
	if tank_violation and tank_violation.mob then
		_G.UC_TANK_VIOLATION_MOB_ID = tonumber(tank_violation.mob.id) or 0
		_G.UC_TANK_VIOLATION_MOB_NAME = tostring(tank_violation.mob.name or '')
		_G.UC_TANK_VIOLATION_VICTIM_ID = tonumber((tank_violation.victim and tank_violation.victim.id) or 0)
		_G.UC_TANK_VIOLATION_VICTIM_NAME = tostring((tank_violation.victim and tank_violation.victim.name) or '')
		_G.UC_TANK_VIOLATION_VICTIM_HPP = tonumber(tank_violation.victim_hpp) or 0
		-- T7: when combat dark launch is enabled, tank enmity dispatch is scheduler-owned.
		if setting_enabled(s.scheduler_dark_launch_combat) then
			_G.UC_LAST_BLOCK_REASON = 'TANK_ENMITY_SCHED_OWNED'
			_G.UC_WS_LAST_DIAG = ('core tank sched-owned mob=%s victim=%s(%s%%)'):format(
				tostring((tank_violation.mob and tank_violation.mob.name) or '?'),
				tostring((tank_violation.victim and tank_violation.victim.name) or '?'),
				tostring(tonumber(tank_violation.victim_hpp) or 0)
			)
			debug_tank(_G.UC_WS_LAST_DIAG, true)
		else
			local tank_handled = execute_tank_enmity(s, p, tank_violation)
			if tank_handled then
				return
			end
		end
	else
		_G.UC_TANK_VIOLATION_MOB_ID = 0
		_G.UC_TANK_VIOLATION_MOB_NAME = ''
		_G.UC_TANK_VIOLATION_VICTIM_ID = 0
		_G.UC_TANK_VIOLATION_VICTIM_NAME = ''
		_G.UC_TANK_VIOLATION_VICTIM_HPP = 0
	end
	local current = get_current_target()
	apply_facing(s, current)
	if not setting_enabled(s.scheduler_dark_launch_movement) then
		apply_movement(s, current)
	end

	local player = windower.ffxi.get_player()
	if status_blocks_actions(player and player.status) then
		_G.UC_LAST_BLOCK_REASON = 'ACTION_BLOCK_STATUS3'
		_G.UC_WS_LAST_DIAG = 'core action_block status=3'
		return
	end
	if setting_enabled(s.scheduler_dark_launch_combat) then
		-- G6: combat action dispatch is scheduler-owned in dark-launch combat mode.
		_G.UC_WS_LAST_DIAG = 'core ws reason=SCHED_COMBAT_OWNED'
		return
	end
	uc_ability_pipeline.execute_ordered_abilities({
		settings = s,
		ability_active = setting_enabled(s.ability_active),
		can_cast_fn = can_cast_ja,
		cast_fn = cast_ja,
		job_abilities = res.job_abilities,
		player_buffs = player and player.buffs or {},
	})

	local t = get_current_target()
	if not t or not t.id or t.id == 0 then
		_G.UC_WS_LAST_DIAG = 'core ws reason=NO_CURRENT_TARGET'
		return
	end
	local ws_name, ws_pick_reason = select_smart_ws(s, t and t.id or 0)
	local dist = target_distance(t)
	local hpp = (t and t.hpp) or 0
	local tp = (p and p.vitals and p.vitals.tp) or 0
	local ws_busy = uc_ws_gate.busy_for_gate({
		is_casting = false,
	})
	local ok_ws, reason = uc_ws_gate.evaluate({
		ws_enabled = setting_enabled(s.weaponskill_active),
		tp = tp,
		dist = dist,
		hpp = hpp,
		busy = ws_busy,
		max_dist = 4,
		ws_name = ws_name,
	})
	_G.UC_WS_LAST_DIAG = ('core ws pick=%s tp=%d dist=%.2f hpp=%d ws=%s reason=%s'):format(
		ws_pick_reason,
		tp,
		dist,
		hpp,
		ws_name,
		reason)
	if ok_ws and t and t.id and t.id ~= 0 then
		local sent, intent_reason = core.try_dispatch_ws_with_intent(ws_name, t.id, s)
		if not sent then
			_G.UC_WS_LAST_DIAG = ('core ws pick=%s tp=%d dist=%.2f hpp=%d ws=%s reason=%s intent=%s'):format(
				ws_pick_reason,
				tp,
				dist,
				hpp,
				ws_name,
				reason,
				tostring(intent_reason or 'BLOCK')
			)
		end
	end
end

function core.register_adapter(name, adapter)
	if type(name) ~= 'string' or name == '' or type(adapter) ~= 'table' then
		return false
	end
	core.adapters[name] = adapter
	return true
end

function core.get_adapter(name)
	return core.adapters[name]
end

function core.combat_tick_once()
	core.last_engine = get_active_engine()
	for target_id in pairs(skillchain_runtime.states) do
		local target = windower.ffxi.get_mob_by_id(target_id)
		if not target
			or target.valid_target ~= true
			or tonumber(target.spawn_type) ~= 16
			or (tonumber(target.hpp) or 0) <= 0 then
			skillchain_runtime:clear_target(target_id, 'despawn_or_invalid')
		end
	end
	run_unified_combat()
end

function core.assert_no_job_branch()
	return true
end

function core.select_smart_ws_for_scheduler(settings, target_id)
	local ws_name, ws_reason = select_smart_ws(settings or {}, target_id)
	return tostring(ws_name or ''), tostring(ws_reason or '')
end

function core.select_ws_plan_for_scheduler(settings, target_id)
	local ws_name, ws_reason, skillchain_plan = select_smart_ws(settings or {}, target_id)
	if tostring(ws_name or '') == '' then
		return nil, tostring(ws_reason or '')
	end
	return {
		ws_name = tostring(ws_name),
		reason = tostring(ws_reason or ''),
		skillchain_plan = skillchain_plan,
	}, tostring(ws_reason or '')
end

function core.revalidate_skillchain_plan(plan, settings, expected_target_id, expected_ws_name, commit_stage)
	if type(plan) ~= 'table' then
		return false, 'SC_INTENT_LOST'
	end
	local player = windower.ffxi.get_player()
	local current_target = windower.ffxi.get_mob_by_target('t')
	local target_id = tonumber(expected_target_id) or 0
	local target = target_id > 0 and windower.ffxi.get_mob_by_id(target_id) or nil
	local ws_name = tostring(expected_ws_name or '')
	local actor_context = local_skillchain_actor_context()
	local skill = skills.weapon_skills and skills.weapon_skills[tonumber(plan.ws_id) or 0]
	local effective_properties = effective_ws_properties(skill, actor_context)
	local target_valid = target
		and tonumber(target.id) == target_id
		and target.valid_target == true
		and tonumber(target.spawn_type) == 16
		and (tonumber(target.hpp) or 0) > 0
	if not target_valid and target_id > 0 then
		skillchain_runtime:clear_target(target_id, 'despawn_or_invalid')
	end
	local current_target_id = tonumber(current_target and current_target.id) or 0
	local reaction_lock = rawget(_G, 'UC_REACTION_LOCK')
	local ok, reason = skillchain_runtime:revalidate_plan(plan, {
		now = os.clock(),
		engine_enabled = rawget(_G, 'Start_Engine') == true and setting_enabled(settings and settings.weaponskill_active),
		current_target_id = current_target_id,
		target_valid = target_valid and true or false,
		ws_available = ws_name == tostring(plan.ws_name or '') and ws_is_currently_available(plan.ws_id),
		tp = tonumber(player and player.vitals and player.vitals.tp) or 0,
		actor_blocked = not player
			or tonumber(player.status) ~= 1
			or status_blocks_actions(player.status)
			or ws_actor_has_incapacitating_buff(player.buffs),
		range_valid = target_valid and target_distance(target) <= 5.5 or false,
		reaction_hold = type(reaction_lock) == 'table',
		intent_valid = target_id == tonumber(plan.target_id) and ws_name == tostring(plan.ws_name or ''),
		actor_context = actor_context,
		effective_properties = effective_properties,
		commit_stage = tostring(commit_stage or 'unspecified'),
	})
	return ok, reason
end

function core.try_dispatch_ws_with_intent(ws_name, target_id, settings, skillchain_plan)
	local ws = tostring(ws_name or '')
	local tid = tonumber(target_id) or 0
	if ws == '' or tid <= 0 then
		return false, 'WS_INTENT_INVALID'
	end
	local ok, why = ws_intent_gate(settings or get_settings(), ws, tid)
	if not ok then
		return false, tostring(why or 'WS_INTENT_BLOCK')
	end
	if skillchain_plan ~= nil then
		local plan_ok, plan_reason = core.revalidate_skillchain_plan(
			skillchain_plan,
			settings or get_settings(),
			tid,
			ws,
			'dispatch_commit'
		)
		if not plan_ok then
			ws_intent_clear_pending()
			return false, tostring(plan_reason)
		end
	end
	windower.send_command('input /ws "' .. ws .. '" ' .. tostring(tid))
	if skillchain_plan ~= nil then
		local marked, mark_reason = skillchain_runtime:mark_plan_dispatched(skillchain_plan, os.clock())
		if not marked then
			error('skillchain dispatch sent without generation reservation: ' .. tostring(mark_reason))
		end
	end
	ws_intent_clear_pending()
	core.ws_intent_remote_target_id = 0
	core.ws_intent_remote_name = ''
	core.ws_intent_remote_actor_id = 0
	core.ws_intent_remote_until = 0
	return true, 'WS_INTENT_SENT'
end

function core.get_skillchain_snapshot(target_id)
	return skillchain_runtime:get_snapshot(target_id)
end

function core.reset_skillchain_state(reason)
	skillchain_runtime:reset(reason)
	core.party_ws_hold_target_id = 0
	core.party_ws_hold_actor_id = 0
	core.party_ws_hold_until = 0
	core.party_ws_hold_category = ''
	core.party_ws_hold_name = ''
	core.ws_hold_remote = {}
	core.ws_intent_remote_target_id = 0
	core.ws_intent_remote_name = ''
	core.ws_intent_remote_actor_id = 0
	core.ws_intent_remote_until = 0
	core.ws_intent_loser_cooldown_until = 0
	core.ws_intent_loser_actor_id = 0
	ws_intent_clear_pending()
end

local function scheduler_settings_view(settings)
	local base = settings or get_settings() or {}
	local view = {}
	for key, value in pairs(base) do
		view[key] = value
	end
	local scheduler_config = require('uc_scheduler_config')
	view.autotarget = scheduler_config.combat_autotarget(base)
	view.prime = scheduler_config.combat_prime(base)
	view.tank = scheduler_config.tank_enabled(base)
	view.tank_enmity_actions = scheduler_config.tank_enmity_actions(base)
	return view
end

function core.select_tank_enmity_for_scheduler(settings)
	local s = scheduler_settings_view(settings)
	if not setting_enabled(s.tank) or not setting_enabled(s.autotarget) then
		return nil
	end
	local player = windower.ffxi.get_player()
	if not player then
		return nil
	end
	local violation = pick_tank_violation_target(s, player)
	if not violation or not violation.mob or not violation.mob.id then
		return nil
	end
	local mob = windower.ffxi.get_mob_by_id(violation.mob.id) or violation.mob
	if not mob or not mob.id or not mob.valid_target or (tonumber(mob.hpp) or 0) <= 0 or tonumber(mob.spawn_type) ~= 16 then
		return nil
	end
	local actions = parse_tank_enmity_actions(s)
	for _, entry in ipairs(actions) do
		local ready, reason, cast_max, dist = tank_action_ready(entry, mob, player)
		if ready then
			return {
				kind = tostring(entry.kind or ''),
				name = tostring(entry.name or ''),
				target_id = tonumber(mob.id) or 0,
				target_name = tostring(mob.name or ''),
				victim_id = tonumber((violation.victim and violation.victim.id) or 0),
				victim_name = tostring((violation.victim and violation.victim.name) or ''),
				victim_hpp = tonumber(violation.victim_hpp) or 0,
				mob_hpp = tonumber(mob.hpp) or 0,
				dist = target_distance(mob),
				action_dist = tonumber(dist) or target_distance(mob),
				action_range = tonumber(cast_max) or 0,
				reason = 'READY',
			}
		end
		if reason == 'TANK_OUT_OF_RANGE' then
			return {
				kind = tostring(entry.kind or ''),
				name = tostring(entry.name or ''),
				target_id = tonumber(mob.id) or 0,
				target_name = tostring(mob.name or ''),
				victim_id = tonumber((violation.victim and violation.victim.id) or 0),
				victim_name = tostring((violation.victim and violation.victim.name) or ''),
				victim_hpp = tonumber(violation.victim_hpp) or 0,
				mob_hpp = tonumber(mob.hpp) or 0,
				dist = tonumber(dist) or target_distance(mob),
				action_range = tonumber(cast_max) or 0,
				reason = 'OUT_OF_RANGE',
			}
		end
	end
	return nil
end

function core.select_target_for_scheduler(settings)
	local s = scheduler_settings_view(settings)
	if not setting_enabled(s.autotarget) then
		return nil
	end
	local target = find_candidate_target(s)
	if not target or not target.id or not target.valid_target then
		return nil
	end
	if tonumber(target.spawn_type) ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
		return nil
	end
	return {
		target_id = tonumber(target.id) or 0,
		target_name = tostring(target.name or ''),
		hpp = tonumber(target.hpp) or 0,
	}
end

function core.add_control_enabled_for_scheduler(settings)
	return uc_add_control.enabled(scheduler_settings_view(settings))
end

function core.puller_engage_allowed_for_scheduler(settings, target)
	return puller_engage_allowed(settings or get_settings() or {}, target)
end

function core.select_pull_for_scheduler(settings)
	local s = settings or get_settings() or {}
	local player = windower.ffxi.get_player()
	local target = get_current_target()
	if not player or not target or not target.id then
		return nil
	end
	if not should_use_pull_action(s, player, target) then
		return nil
	end
	local action_type, action_name = pull_action_config(s)
	if tostring(action_name or '') == '' then
		return nil
	end
	local resource = (action_type == 'spell') and get_spell_resource(action_name) or get_ja_resource(action_name)
	if not resource then
		return nil
	end
	local max_range = action_effective_range(resource.range)
	if max_range <= 0 then
		max_range = (action_type == 'spell') and 20 or 10
	end
	if action_type == 'spell' and max_range < 5.0 then
		max_range = 20.0
	end
	local cast_max_range = max_range
	if action_type == 'spell' then
		local buffer = max_range * 0.10
		cast_max_range = max_range - buffer
		if cast_max_range < 1.0 then
			cast_max_range = 1.0
		end
	end
	local dist = target_real_distance(target)
	local in_range = dist <= cast_max_range
	return {
		target_id = tonumber(target.id) or 0,
		target_name = tostring(target.name or ''),
		action_type = tostring(action_type or ''),
		action_name = tostring(action_name or ''),
		dist = tonumber(dist) or 999,
		range_max = tonumber(cast_max_range) or 0,
		in_range = in_range,
	}
end

function core.dispatch_pull_for_scheduler(settings, target_id)
	local s = settings or get_settings() or {}
	local player = windower.ffxi.get_player()
	local target = windower.ffxi.get_mob_by_id(tonumber(target_id) or 0)
	if not player or not target then
		return false, 'PULL_NO_CONTEXT'
	end
	local handled = try_pull_action(s, player, target)
	if handled then
		return true, tostring(rawget(_G, 'UC_LAST_BLOCK_REASON') or 'PULL_HANDLED')
	end
	return false, 'PULL_NOT_APPLICABLE'
end

function core.apply_movement_for_scheduler(settings)
	local s = settings or get_settings() or {}
	local current = get_current_target()
	local before_run = (core.last_run_active == true)
	apply_movement(s, current)
	local after_run = (core.last_run_active == true)
	local preengage = (rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true)
	-- Movement coordinator should only claim ownership when this tick produced
	-- active movement ownership intent.
	return after_run or preengage or (before_run and after_run)
end

return core
