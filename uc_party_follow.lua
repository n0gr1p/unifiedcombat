---@diagnostic disable: undefined-global
--[[
  Party follow: same-zone run vector toward the configured leader.
  Multibox: IPC position stream (ucpf_up) + FastFollow-style zone replay (ucpf_zone + packets.inject).
]]

local M = {}
local packets = require('packets')
local uc_active_config = require('uc_active_config')
local uc_camp_puller = require('uc_camp_puller')
local uc_nyzul_runtime = require('uc_nyzul_runtime')
local movement_dispatcher = require('uc_movement_dispatcher').build({
	dispatcher = require('uc_scheduler_dispatcher'),
	run = windower.ffxi.run,
	source_prefix = 'party_follow',
})
local socket_ok, socket_mod = pcall(require, 'socket')
local socket_gettime = (socket_ok and type(socket_mod) == 'table' and type(socket_mod.gettime) == 'function') and socket_mod.gettime or nil

local function now_s()
	-- C7 unified timing source for follow/movement gating (no os.clock fallback).
	return socket_gettime()
end

local REQUEST_ZONE = 0x05E
local zone_min_linear = 5
local zone_min_dist_sq = zone_min_linear * zone_min_linear
local zone_suppress = 3.0
local local_zone_change_block_s = 5.0
local zone_post_snapshot_delay_s = 2.5

--- [nameLower] = { x, y, zone, t = now_s() }
local ipc_pos = {}
local last_ipc_broadcast = 0
local ipc_broadcast_interval = 0.05
local last_zone = now_s()
local ff_following = nil -- FastFollow-parity: lowercase leader name when in follower mode
local ff_target = nil    -- FastFollow-parity: { zone, x, y } from update stream for ff_following
local last_seen_zone_change_at = 0
local last_follow_suppressed = false
local follow_run_active_hold_s = 0.4
local follow_needs_catchup_hold_s = 0.4
local dist_sq
local recent_local_zone_change
local recent_local_request
local last_local_request_at = 0
local last_noisy_log_text = ''
local last_noisy_log_at = 0

local function pf_timestamp()
	local base = os.date('%H:%M:%S')
	local ms = math.floor((now_s() % 1) * 1000)
	return ('%s.%03d'):format(base, ms)
end

local function truthy(v)
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function debug_enabled()
	local s = rawget(_G, 'UC_SETTINGS')
	local active_value = uc_active_config.get_path('config.debug.enabled')
	if active_value ~= nil then
		return active_value == true
	end
	return s and truthy(s.debug) or false
end

local function active_value_or_flat(path, flat_value)
	local active_value = uc_active_config.get_path(path)
	if active_value ~= nil then
		return active_value
	end
	return flat_value
end

local function party_follow_enabled(s)
	return active_value_or_flat('config.follow.party.enabled', s and s.party_follow) == true
end

local function party_follow_id(s)
	return tonumber(active_value_or_flat('config.follow.party.leader_id', s and s.party_follow_id)) or 0
end

local function party_follow_leader_name(s)
	return active_value_or_flat('config.follow.party.leader_name', s and s.party_follow_leader_name)
end

local function party_follow_min(s)
	return tonumber(active_value_or_flat('config.follow.party.min', s and s.party_follow_min)) or 0.5
end

local function party_follow_max(s)
	return tonumber(active_value_or_flat('config.follow.party.max', s and s.party_follow_max)) or 50
end

local function fight_follow_min(s)
	return tonumber(active_value_or_flat('config.follow.fight.min', s and s.fight_follow_min))
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

local function file_log(text)
	if not debug_enabled() or type(text) ~= 'string' or text == '' then
		return
	end
	pcall(function()
		local p = windower.ffxi.get_player()
		local char = (p and p.name) or 'unknown'
		local dir = ensure_log_dir()
		if not dir then
			return
		end
		local path = dir .. safe_char_name(char) .. '_follow_zone_debug.log'
		local f = io.open(path, 'a')
		if not f then
			return
		end
		f:write(pf_timestamp(), '	', text:gsub('\r?\n', ' '), '\n')
		f:close()
	end)
end

local function hex_preview(raw, max_bytes)
	if type(raw) ~= 'string' then
		return ''
	end
	local n = tonumber(max_bytes) or 32
	if n < 1 then
		n = 1
	end
	if n > #raw then
		n = #raw
	end
	local out = {}
	for i = 1, n do
		out[#out + 1] = ('%02X'):format(raw:byte(i))
	end
	return table.concat(out, ' ')
end

local function packet_raw_preview(pkt)
	local ok, built = pcall(function()
		return packets.build(pkt)
	end)
	if not ok or type(built) ~= 'string' then
		return ''
	end
	return hex_preview(built, 32)
end

local function state_snapshot(extra)
	local p = windower.ffxi.get_player()
	local me = windower.ffxi.get_mob_by_target('me')
	local info = windower.ffxi.get_info()
	local now = now_s()
	local parts = {
		('char=%s'):format(tostring(p and p.name or '?')),
		('self_zone=%s'):format(tostring(info and info.zone or '?')),
		('self_x=%.3f'):format(tonumber(me and me.x) or -999),
		('self_y=%.3f'):format(tonumber(me and me.y) or -999),
		('party_follow=%s'):format(tostring(party_follow_enabled(rawget(_G, 'UC_SETTINGS')))),
		('ff_following=%s'):format(tostring(ff_following or '')),
		('ff_target_zone=%s'):format(tostring(ff_target and ff_target.zone or '')),
		('ff_target_x=%.3f'):format(tonumber(ff_target and ff_target.x) or -999),
		('ff_target_y=%.3f'):format(tonumber(ff_target and ff_target.y) or -999),
		('last_zone_delta=%.3f'):format(now - (tonumber(last_zone) or 0)),
		('recent_zone_change=%s'):format(tostring(recent_local_zone_change(local_zone_change_block_s))),
	}
	if me and ff_target and ff_target.x ~= nil and ff_target.y ~= nil then
		local d = math.sqrt(dist_sq(me.x, me.y, ff_target.x, ff_target.y))
		parts[#parts + 1] = ('dist_to_ff_target=%.3f'):format(d)
	end
	if type(extra) == 'string' and extra ~= '' then
		parts[#parts + 1] = extra
	end
	return table.concat(parts, ' ')
end

local function pf_set_op(op_text)
	local msg = tostring(op_text or '')
	_G.UC_LAST_PARTY_FOLLOW_OP = msg
	local log = rawget(_G, 'UC_PARTY_FOLLOW_OP_LOG')
	if type(log) ~= 'table' then
		log = {}
	end
	table.insert(log, 1, ('%s %s'):format(pf_timestamp(), msg))
	while #log > 5 do
		table.remove(log)
	end
	_G.UC_PARTY_FOLLOW_OP_LOG = log
	local noisy = (
		msg == 'PARTY_FOLLOW_ZONE_SKIP_SEND:follower_mode' or
		msg == 'PARTY_FOLLOW_ZONE_SUPPRESS:block_outgoing_request' or
		msg == 'PARTY_FOLLOW_ZONE_SUPPRESS:block_after_zone_change'
	)
	if noisy then
		local now = now_s()
		if msg == last_noisy_log_text and (now - last_noisy_log_at) < 1.5 then
			return
		end
		last_noisy_log_text = msg
		last_noisy_log_at = now
	end
	file_log(('op=%s %s'):format(msg, state_snapshot()))
end

local function set_follow_run_active(active)
	local now = now_s()
	if active == true then
		_G.UC_PARTY_FOLLOW_RUN_ACTIVE = true
		_G.UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL = now + follow_run_active_hold_s
		return
	end
	local keep_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL')) or 0
	if now < keep_until then
		_G.UC_PARTY_FOLLOW_RUN_ACTIVE = true
		return
	end
	_G.UC_PARTY_FOLLOW_RUN_ACTIVE = false
end

local function set_follow_needs_catchup(active)
	local now = now_s()
	if active == true then
		_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
		_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = now + follow_needs_catchup_hold_s
		return
	end
	local keep_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL')) or 0
	if now < keep_until then
		_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
		return
	end
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = false
end

local function clear_follow_needs_catchup()
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = false
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = 0
end

local function formation_movement_active()
	local status = rawget(_G, 'UC_FORMATION_STATUS')
	local formation = uc_active_config.get_path('config.movement.formation')
	local movement_domain_enabled = uc_active_config.get_path('config.ownership.domain_movement_enabled')
	return movement_domain_enabled == true
		and type(formation) == 'table'
		and formation.enabled == true
		and type(status) == 'table'
		and status.enabled == true
		and tostring(status.phase or '') == 'active'
end

local function stop_and_release_follow_movement()
	if tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or '') ~= 'follow' then
		return false
	end
	movement_dispatcher.stop()
	_G.UC_MOVEMENT_OWNER = 'none'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_s()
	return true
end

local function trim(s)
	if not s then
		return ''
	end
	return tostring(s):match('^%s*(.-)%s*$') or ''
end

local function leader_name_lower(s, lid)
	local n = trim(party_follow_leader_name(s))
	if n ~= '' then
		return n:lower()
	end
	if not lid or lid == 0 then
		return ''
	end
	local party = windower.ffxi.get_party()
	if not party then
		return ''
	end
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local e = party[key]
		local mob = e and e.mob
		if mob and mob.id == lid and mob.name and mob.name ~= '' then
			return mob.name:lower()
		end
	end
	return ''
end

dist_sq = function(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return dx * dx + dy * dy
end

local function refresh_ff_following_from_settings()
	local s = _G.UC_SETTINGS
	if not s or not party_follow_enabled(s) then
		ff_following = nil
		ff_target = nil
		return
	end
	local lname = leader_name_lower(s, party_follow_id(s))
	if lname == '' then
		ff_following = nil
		ff_target = nil
		return
	end
	ff_following = lname
end

local function zones_equivalent(zone_self, zipc)
	if zone_self == nil or zipc == nil then
		return true
	end
	if tostring(zone_self) == tostring(zipc) then
		return true
	end
	local a, b = tonumber(zone_self), tonumber(zipc)
	return a ~= nil and b ~= nil and a == b
end

function M.get_ipc_position(name_lower, zone_self, max_age_s)
	if type(name_lower) ~= 'string' or name_lower == '' then
		return nil, nil
	end
	local c = ipc_pos[name_lower]
	if not c or c.x == nil or c.y == nil then
		return nil, nil
	end
	local age = now_s() - (tonumber(c.t) or 0)
	local max_age = tonumber(max_age_s) or 2.5
	if age > max_age then
		return nil, nil
	end
	if not zones_equivalent(zone_self, c.zone) then
		return nil, nil
	end
	return c.x, c.y
end

--- FastFollow-parity zone replay core.
local function zone_follow_replay(zone_line, zone_type, leader_zone, lx, ly, mh_door_menu)
	file_log(('event=REPLAY_START line=%s type=%s leader_zone=%s lx=%.3f ly=%.3f %s'):format(
		tostring(zone_line), tostring(zone_type), tostring(leader_zone), tonumber(lx) or -999, tonumber(ly) or -999, state_snapshot()
	))
	local function replay_stomped_by_local_zone()
		return recent_local_request(local_zone_change_block_s) or recent_local_zone_change(local_zone_change_block_s)
	end
	if replay_stomped_by_local_zone() then
		pf_set_op(('PARTY_FOLLOW_ZONE_ABORT:local_zone_priority_pre_sleep line=%s type=%s'):format(
			tostring(zone_line), tostring(zone_type)
		))
		return
	end
	coroutine.sleep(0.2 + math.random() * 2.5)
	if replay_stomped_by_local_zone() then
		pf_set_op(('PARTY_FOLLOW_ZONE_ABORT:local_zone_priority_post_sleep line=%s type=%s'):format(
			tostring(zone_line), tostring(zone_type)
		))
		return
	end
	local self = windower.ffxi.get_mob_by_target('me')
	local info = windower.ffxi.get_info()
	if not self or not info then
		pf_set_op('PARTY_FOLLOW_ZONE_ABORT:not_ready')
		return
	end
	if not zones_equivalent(info.zone, leader_zone) then
		pf_set_op('PARTY_FOLLOW_ZONE_ABORT:not_same_zone')
		return
	end
	local ok, packet = pcall(function()
		local spec = {
			['Zone Line'] = zone_line,
			['Type'] = zone_type,
		}
		if mh_door_menu ~= nil then
			spec['MH Door Menu'] = mh_door_menu
		end
		return packets.new('outgoing', REQUEST_ZONE, spec)
	end)
	if not ok or not packet then
		pf_set_op('PARTY_FOLLOW_ZONE_ABORT:packet_new_failed')
		return
	end
	local i = 0
	local d2 = dist_sq(self.x, self.y, lx, ly)
	file_log(('event=REPLAY_RANGE_INIT d2=%.3f %s'):format(d2, state_snapshot()))
	while d2 > zone_min_dist_sq and i < 12 do
		if replay_stomped_by_local_zone() then
			pf_set_op(('PARTY_FOLLOW_ZONE_ABORT:local_zone_priority_in_range_wait line=%s type=%s'):format(
				tostring(zone_line), tostring(zone_type)
			))
			return
		end
		coroutine.sleep(0.25)
		self = windower.ffxi.get_mob_by_target('me')
		if not self then
			pf_set_op('PARTY_FOLLOW_ZONE_ABORT:no_self_mob')
			return
		end
		d2 = dist_sq(self.x, self.y, lx, ly)
		i = i + 1
		file_log(('event=REPLAY_RANGE_TICK i=%d d2=%.3f %s'):format(i, d2, state_snapshot()))
	end
	if d2 > zone_min_dist_sq then
		pf_set_op('PARTY_FOLLOW_ZONE_TOO_FAR:min_linear_yalms=' .. tostring(zone_min_linear))
		return
	end
	if replay_stomped_by_local_zone() then
		pf_set_op(('PARTY_FOLLOW_ZONE_ABORT:local_zone_priority_pre_inject line=%s type=%s'):format(
			tostring(zone_line), tostring(zone_type)
		))
		return
	end
	file_log(('event=REPLAY_PACKET_SEND id=0x05E line=%s type=%s mh=%s raw=\"%s\" %s'):format(
		tostring(zone_line),
		tostring(zone_type),
		tostring(mh_door_menu),
		packet_raw_preview(packet),
		state_snapshot()
	))
	local inj_ok, inj_err = pcall(function()
		packets.inject(packet)
	end)
	if not inj_ok then
		pf_set_op('PARTY_FOLLOW_ZONE_INJECT_FAIL:' .. tostring(inj_err))
		return
	end
	file_log(('event=REPLAY_INJECT_OK line=%s type=%s %s'):format(tostring(zone_line), tostring(zone_type), state_snapshot()))
	last_zone = now_s()
	pf_set_op(('PARTY_FOLLOW_ZONE_OK:line=%s type=%s leader_zone=%s'):format(
		tostring(zone_line),
		tostring(zone_type),
		tostring(leader_zone)
	))
end

recent_local_zone_change = function(window_s)
	local last = tonumber(rawget(_G, 'UC_LAST_ZONE_CHANGE_AT')) or 0
	local w = tonumber(window_s) or 0
	return last > 0 and (now_s() - last) < w
end

recent_local_request = function(window_s)
	local w = tonumber(window_s) or 0
	return (tonumber(last_local_request_at) or 0) > 0 and (now_s() - last_local_request_at) < w
end

local function ipc_dispatch_zone(msg)
	file_log(('event=IPC_ZONE_RECV_RAW msg=\"%s\" %s'):format(tostring(msg), state_snapshot()))
	local args = {}
	for part in msg:lower():gmatch('%S+') do
		args[#args + 1] = part
	end
	if #args < 4 or args[1] ~= 'zone' then return end
	refresh_ff_following_from_settings()
	if not ff_following or args[2] ~= ff_following then
		return
	end
	local zone_line = tonumber(args[3])
	local zone_type = tonumber(args[4])
	if not zone_line or not zone_type then
		return
	end
	-- Hard stomp: while local zone flow is active/recent, discard incoming IPC zone
	-- requests entirely. We do not queue/replay them later.
	if recent_local_zone_change(local_zone_change_block_s) then
		pf_set_op(('PARTY_FOLLOW_ZONE_SKIP:local_zone_change_recent line=%s type=%s'):format(
			tostring(zone_line), tostring(zone_type)
		))
		return
	end
	if recent_local_request(local_zone_change_block_s) then
		pf_set_op(('PARTY_FOLLOW_ZONE_SKIP:local_request_recent line=%s type=%s'):format(
			tostring(zone_line), tostring(zone_type)
		))
		return
	end
	local source_zone = tonumber(args[5])
	local source_mh = tonumber(args[6])
	if source_zone ~= nil then
		local info = windower.ffxi.get_info()
		local zself = info and info.zone
		if zself == nil or not zones_equivalent(zself, source_zone) then
			pf_set_op(('PARTY_FOLLOW_ZONE_SKIP:stale_source_zone self=%s src=%s'):format(
				tostring(zself),
				tostring(source_zone)
			))
			return
		end
	end
	if not ff_target or ff_target.x == nil or ff_target.y == nil or ff_target.zone == nil then
		pf_set_op('PARTY_FOLLOW_ZONE_NO_LEADER_POS:' .. tostring(ff_following))
		return
	end
	pf_set_op(('PARTY_FOLLOW_ZONE_RECV:leader=%s line=%s type=%s'):format(
		tostring(args[2]), tostring(zone_line), tostring(zone_type)
	))
	zone_follow_replay(zone_line, zone_type, source_zone or ff_target.zone, ff_target.x, ff_target.y, source_mh)
end

function M.ipc_message(msg)
	if type(msg) ~= 'string' then
		return
	end
	if msg:sub(1, 5) == 'zone ' then
		ipc_dispatch_zone(msg)
		return
	end
	if msg:sub(1, 8) ~= 'ucpf_up|' then
		return
	end
	local parts = {}
	for part in msg:gmatch('[^|]+') do
		parts[#parts + 1] = part
	end
	if #parts < 5 or parts[1] ~= 'ucpf_up' then
		return
	end
	local name = parts[2]
	local zraw = parts[3]
	local x = tonumber(parts[4])
	local y = tonumber(parts[5])
	if not name or not x or not y or zraw == nil or zraw == '' then
		return
	end
	local lname = name:lower()
	ipc_pos[lname] = { x = x, y = y, zone = zraw, t = now_s() }
	if ff_following and lname == ff_following then
		ff_target = { x = x, y = y, zone = tonumber(zraw) or zraw }
	end
end

--- Call every prerender from UnifiedCombat (all instances) so followers receive fresh x/y.
function M.broadcast_self_ipc()
	local now = now_s()
	if now - last_ipc_broadcast < ipc_broadcast_interval then
		return
	end
	local p = windower.ffxi.get_player()
	if not p or not p.name then
		return
	end
	local me = windower.ffxi.get_mob_by_target('me')
	local info = windower.ffxi.get_info()
	if not me or not info or me.x == nil or me.y == nil then
		return
	end
	local z = info.zone
	if z == nil then
		return
	end
	last_ipc_broadcast = now
	local nm = tostring(p.name):gsub('|', '_')
	windower.send_ipc_message(('ucpf_up|%s|%s|%.4f|%.4f'):format(nm, tostring(z), me.x, me.y))
end

--- Announce this client's zone line/type on IPC so multibox followers can replay (FastFollow-style).
function M.outgoing_chunk(id, data, blocked, injected)
	if blocked or id ~= REQUEST_ZONE or not data then
		return false
	end
	local now = now_s()
	local p = windower.ffxi.get_player()
	if not p or not p.name then
		return false
	end
	local s = _G.UC_SETTINGS
	if s and party_follow_enabled(s) then
		local okp, pktp = pcall(function()
			return packets.parse('outgoing', data)
		end)
		if okp and pktp then
			file_log(('event=OUT_05E_PACKET_OBSERVED_FOLLOWER id=0x05E line=%s type=%s mh=%s injected=%s raw=\"%s\" %s'):format(
				tostring(pktp['Zone Line']),
				tostring(pktp['Type']),
				tostring(pktp['MH Door Menu']),
				tostring(injected == true),
				hex_preview(data, 32),
				state_snapshot()
			))
		end
		-- When following (UC wrapper), mirror FastFollow zone suppress behavior.
		refresh_ff_following_from_settings()
		if recent_local_zone_change(local_zone_change_block_s) then
			pf_set_op('PARTY_FOLLOW_ZONE_SUPPRESS:block_after_zone_change')
			return true
		end
		if (now - (tonumber(last_zone) or 0)) < zone_suppress then
			pf_set_op('PARTY_FOLLOW_ZONE_SUPPRESS:block_outgoing_request')
			return true
		end
		pf_set_op('PARTY_FOLLOW_ZONE_SKIP_SEND:follower_mode')
		last_local_request_at = now
		file_log(('event=FOLLOWER_LOCAL_ZONE_REQUEST_ACTIVATE hold_s=%.2f %s'):format(
			tonumber(local_zone_change_block_s) or 0,
			state_snapshot()
		))
		last_zone = now
		return false
	end
	local ok, pkt = pcall(function()
		return packets.parse('outgoing', data)
	end)
	if not ok then
		file_log(('event=OUT_05E_PARSE_FAIL %s'):format(state_snapshot()))
	end
	if ok and pkt then
		local zl = pkt['Zone Line']
		local zt = pkt['Type']
		local zmh = pkt['MH Door Menu']
		file_log(('event=OUT_05E_PACKET_OBSERVED id=0x05E line=%s type=%s mh=%s raw=\"%s\" %s'):format(
			tostring(zl),
			tostring(zt),
			tostring(zmh),
			hex_preview(data, 32),
			state_snapshot()
		))
		if zl ~= nil and zt ~= nil then
			local nm = tostring(p.name):gsub('|', '_')
			local info = windower.ffxi.get_info()
			local src = tonumber(info and info.zone)
			pf_set_op(('PARTY_FOLLOW_ZONE_SEND:line=%s type=%s mh=%s'):format(
				tostring(zl), tostring(zt), tostring(zmh)
			))
			if src ~= nil then
				windower.send_ipc_message(('zone %s %s %s %s %s'):format(
					nm,
					tostring(zl),
					tostring(zt),
					tostring(src),
					tostring(tonumber(zmh) or 0)
				))
			else
				windower.send_ipc_message(('zone %s %s %s'):format(nm, tostring(zl), tostring(zt)))
			end
			last_zone = now
		end
	end
	return false
end

if not M._ipc_registered then
	M._ipc_registered = true
	windower.register_event('ipc message', function(msg)
		M.ipc_message(msg)
	end)
end

local function follow_dist_sq_bounds(s)
	local mn = party_follow_min(s)
	local mx = party_follow_max(s)
	local ff_until = tonumber(rawget(_G, 'UC_FIGHT_FOLLOW_ACTIVE_UNTIL')) or 0
	local allow_fight_follow = false
	if type(rawget(_G, 'UC_IsCombatParticipant')) == 'function' then
		allow_fight_follow = _G.UC_IsCombatParticipant(s) == true
	end
	if allow_fight_follow and now_s() < ff_until then
		local fight_min = fight_follow_min(s) or mn
		if fight_min >= 0.01 and fight_min <= 99 then
			mn = fight_min
		end
	end
	if mn < 0.01 then
		mn = 0.01
	end
	if mn > 99 then
		mn = 99
	end
	if mx < 0.1 then
		mx = 0.1
	end
	if mx > 200 then
		mx = 200
	end
	if mn >= mx then
		mx = math.min(200, mn + 0.01)
	end
	if mn >= mx then
		mn, mx = 0.5, 50
	end
	return mn * mn, mx * mx
end

local function movement_arbitration_enabled()
	return rawget(_G, 'UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION') == true
end

local function combat_participant_active(s)
	if type(rawget(_G, 'UC_IsCombatParticipant')) == 'function' then
		return _G.UC_IsCombatParticipant(s) == true
	end
	return false
end

local function live_combat_transition_target_exists()
	local ffxi = windower and windower.ffxi
	if type(ffxi) ~= 'table' or type(ffxi.get_mob_by_target) ~= 'function' then
		return false
	end
	local target = ffxi.get_mob_by_target('t')
	if not target or target.valid_target ~= true then
		return false
	end
	if tonumber(target.spawn_type) ~= 16 then
		return false
	end
	if (tonumber(target.hpp) or 0) <= 0 then
		return false
	end
	return true
end

local function should_suppress_follow_or_path_return_now(s, now)
	now = tonumber(now) or now_s()
	local owner = tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or 'none')
	local lock_until = tonumber(rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')) or 0
	if owner == 'scheduler_formation' and now < lock_until then
		return true, 'formation_movement_lock'
	end
	if not movement_arbitration_enabled() then
		return false, 'flag_off'
	end
	if owner == 'scheduler' and now < lock_until then
		return true, 'scheduler_movement_lock'
	end
	if owner == 'scheduler_brd' and now < lock_until then
		return true, 'bard_reposition_movement_lock'
	end
	if not combat_participant_active(s) then
		return false, 'not_combat_participant'
	end
	if owner == 'core' and now < lock_until then
		return true, 'movement_lock'
	end
	if rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true then
		return true, 'preengage'
	end
	local have_live_transition_target = live_combat_transition_target_exists()
	local intent_until = tonumber(rawget(_G, 'UC_COMBAT_INTENT_UNTIL')) or 0
	if now < intent_until then
		if have_live_transition_target then
			return true, 'combat_intent_target'
		end
		return false, 'combat_intent_stale'
	end
	local fight_follow_until = tonumber(rawget(_G, 'UC_FIGHT_FOLLOW_ACTIVE_UNTIL')) or 0
	if now < fight_follow_until then
		if have_live_transition_target then
			return true, 'fight_follow_hold_target'
		end
		return false, 'fight_follow_hold_stale'
	end
	return false, 'none'
end

M.should_suppress_follow_or_path_return_now = should_suppress_follow_or_path_return_now

local function combat_engine_suppresses_follow(s)
	if uc_camp_puller.movement_reserved(s.camp_pulling) then
		return true, 'camp_puller'
	end
	local now = now_s()
	local arbitration_suppress = should_suppress_follow_or_path_return_now(s, now)
	if arbitration_suppress == true then
		return true
	end
	-- Hard engage suppression for combat participants:
	-- prevents follow from re-asserting between short movement lock refresh windows.
	local combat_participant = false
	if type(rawget(_G, 'UC_IsCombatParticipant')) == 'function' then
		combat_participant = _G.UC_IsCombatParticipant(s) == true
	end
	if combat_participant then
		local p = windower.ffxi.get_player()
		if p and tonumber(p.status) == 1 then
			return true
		end
		if rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true then
			return true
		end
		local intent_until = tonumber(rawget(_G, 'UC_COMBAT_INTENT_UNTIL')) or 0
		if now < intent_until then
			return true
		end
	end
	-- Spell freeze / cast settle guard.
	local prep_until = tonumber(rawget(_G, 'UC_MOVE_FREEZE_PREP_UNTIL')) or 0
	if now < prep_until then
		return true
	end
	if tostring(rawget(_G, 'UC_MOVEMENT_MODE') or '') == 'CAST_FREEZE' then
		return true
	end
	-- Hard suppressors (explicit cast/item wait states) remain valid even if movement
	-- ownership lock was not refreshed this exact frame.
	if rawget(_G, 'UC_PULL_SPELL_WAITING') == true then
		return true
	end
	return false
end

local function zone_suspend_active()
	local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	if type(zu) == 'number' and now_s() < zu then
		return true
	end
	-- Local zone request should take priority over follow movement/replay.
	return recent_local_request(local_zone_change_block_s)
end

local function leader_mob_from_party(lid, lname)
	lname = lname or ''
	local party = windower.ffxi.get_party()
	if not party then
		return nil
	end
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local e = party[key]
		local mob = e and e.mob
		if mob and mob.id and mob.id ~= 0 and mob.x and mob.y then
			if lid and lid > 0 and mob.id == lid then
				return mob
			end
			if lname ~= '' and mob.name and mob.name:lower() == lname then
				return mob
			end
		end
	end
	return nil
end

local function resolve_leader_xy(s, lid, lname, zone_self)
	lname = lname or ''
	if lname ~= '' then
		local c = ipc_pos[lname]
		if c and c.x and c.y and (now_s() - c.t) < 2.5 then
			if zones_equivalent(zone_self, c.zone) then
				return c.x, c.y
			end
		end
	end
	local pm = leader_mob_from_party(lid, lname)
	if pm and pm.x and pm.y then
		return pm.x, pm.y
	end
	if lid and lid > 0 then
		local ok, m = pcall(function()
			return windower.ffxi.get_mob_by_id(lid)
		end)
		if ok and m and m.x and m.y and m.id and m.id ~= 0 then
			return m.x, m.y
		end
	end
	return nil
end

function M.prerender()
	local zc = tonumber(rawget(_G, 'UC_LAST_ZONE_CHANGE_AT')) or 0
	if debug_enabled() and zc > 0 and zc ~= last_seen_zone_change_at then
		last_seen_zone_change_at = zc
		file_log(('event=ZONE_CHANGE_DETECTED zone_change_at=%.3f %s'):format(zc, state_snapshot()))
		coroutine.schedule(function()
			file_log(('event=ZONE_POST_SNAPSHOT delay=%.2f %s'):format(zone_post_snapshot_delay_s, state_snapshot()))
		end, zone_post_snapshot_delay_s)
	end
	refresh_ff_following_from_settings()
	if uc_nyzul_runtime.enforce_movement_hold() then
		set_follow_run_active(false)
		set_follow_needs_catchup(false)
		last_follow_suppressed = false
		return
	end
	local s = _G.UC_SETTINGS
	if not s or not party_follow_enabled(s) then
		set_follow_run_active(false)
		set_follow_needs_catchup(false)
		stop_and_release_follow_movement()
		last_follow_suppressed = false
		return
	end
	if type(rawget(_G, 'UC_IsFollowParticipant')) == 'function' and not _G.UC_IsFollowParticipant(s) then
		set_follow_run_active(false)
		set_follow_needs_catchup(false)
		stop_and_release_follow_movement()
		last_follow_suppressed = false
		return
	end
	if formation_movement_active() then
		clear_follow_needs_catchup()
	else
		local p = windower.ffxi.get_player()
		local out_of_combat = (tonumber(p and p.status) or 0) ~= 1
		if out_of_combat then
			local lid = party_follow_id(s)
			local self_mob = windower.ffxi.get_mob_by_target('me')
			local info = windower.ffxi.get_info()
			local zone_self = info and info.zone
			local lname = leader_name_lower(s, lid)
			local lx, ly = resolve_leader_xy(s, lid, lname, zone_self)
			if self_mob and self_mob.x and self_mob.y and lx and ly then
				local min_dist, _ = follow_dist_sq_bounds(s)
				local d2 = dist_sq(self_mob.x, self_mob.y, lx, ly)
				set_follow_needs_catchup(d2 > min_dist)
			else
				set_follow_needs_catchup(false)
			end
		else
			set_follow_needs_catchup(false)
		end
	end
	local suppressed, suppression_owner = combat_engine_suppresses_follow(s)
	if suppressed then
		-- Transition hard-stop: prevent stale run vector drift when follow yields to
		-- combat-owned movement.
		if not last_follow_suppressed then
			if not stop_and_release_follow_movement() then
				movement_dispatcher.stop()
			end
		end
		set_follow_run_active(false)
		if suppression_owner == 'camp_puller' then
			clear_follow_needs_catchup()
		end
		last_follow_suppressed = true
		return
	end
	last_follow_suppressed = false
	local p = windower.ffxi.get_player()
	if not p then
		stop_and_release_follow_movement()
		set_follow_run_active(false)
		return
	end
	local lid = party_follow_id(s)
	if lid == p.id then
		stop_and_release_follow_movement()
		set_follow_run_active(false)
		return
	end
	local self_mob = windower.ffxi.get_mob_by_target('me')
	if not self_mob or not self_mob.x or not self_mob.y then
		stop_and_release_follow_movement()
		set_follow_run_active(false)
		return
	end
	local info = windower.ffxi.get_info()
	local zone_self = info and info.zone
	local lname = leader_name_lower(s, lid)
	local lx, ly = resolve_leader_xy(s, lid, lname, zone_self)
	if not lx or not ly then
		movement_dispatcher.stop()
		set_follow_run_active(false)
		_G.UC_MOVEMENT_OWNER = 'follow'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.20
		return
	end
	local ok, leader_mob = pcall(function()
		return windower.ffxi.get_mob_by_id(lid)
	end)
	if ok and leader_mob and leader_mob.id and leader_mob.id ~= 0 and leader_mob.hpp ~= nil and leader_mob.hpp <= 0 then
		movement_dispatcher.stop()
		set_follow_run_active(false)
		_G.UC_MOVEMENT_OWNER = 'follow'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.20
		return
	end
	local min_dist, max_dist = follow_dist_sq_bounds(s)
	local d2 = dist_sq(self_mob.x, self_mob.y, lx, ly)
	if d2 > min_dist and d2 < max_dist then
		local len = math.sqrt(d2)
		if len < 1 then
			len = 1
		end
		movement_dispatcher.run_vector((lx - self_mob.x) / len, (ly - self_mob.y) / len)
		set_follow_run_active(true)
		_G.UC_MOVEMENT_OWNER = 'follow'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.25
	elseif d2 <= min_dist then
		movement_dispatcher.stop()
		set_follow_run_active(false)
		_G.UC_MOVEMENT_OWNER = 'follow'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.20
	else
		movement_dispatcher.stop()
		set_follow_run_active(false)
		_G.UC_MOVEMENT_OWNER = 'follow'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.20
	end
end

return M

