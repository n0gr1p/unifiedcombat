---@diagnostic disable: undefined-global
--[[
  Party follow: same-zone run vector toward the configured leader.
  Multibox: IPC position stream (ucpf_up) + FastFollow-style zone replay (ucpf_zone + packets.inject).
]]

local M = {}
local packets = require('packets')
local REQUEST_ZONE = 0x05E
local zone_min_linear = 5
local zone_min_dist_sq = zone_min_linear * zone_min_linear

--- [nameLower] = { x, y, zone, t = os.clock() }
local ipc_pos = {}
local last_ipc_broadcast = 0
local ipc_broadcast_interval = 0.05
local function trim(s)
	if not s then
		return ''
	end
	return tostring(s):match('^%s*(.-)%s*$') or ''
end

local function leader_name_lower(s, lid)
	local n = trim(s and s.party_follow_leader_name)
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

local function dist_sq(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return dx * dx + dy * dy
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

--- FastFollow-style: wait, walk to leader's last IPC xy, inject same Zone Line / Type.
local function zone_follow_replay(zone_line, zone_type, leader_zone, lx, ly)
	coroutine.sleep(0.2 + math.random() * 2.5)
	local self = windower.ffxi.get_mob_by_target('me')
	local info = windower.ffxi.get_info()
	if not self or not info or not zones_equivalent(info.zone, leader_zone) then
		_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_ZONE_ABORT:not_same_zone'
		return
	end
	local ok, packet = pcall(function()
		return packets.new('outgoing', REQUEST_ZONE, {
			['Zone Line'] = zone_line,
			['Type'] = zone_type,
		})
	end)
	if not ok or not packet then
		_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_ZONE_ABORT:packet_new_failed'
		return
	end
	local i = 0
	while i < 12 do
		self = windower.ffxi.get_mob_by_target('me')
		if not self or not self.x or not self.y then
			_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_ZONE_ABORT:no_self_mob'
			return
		end
		if dist_sq(self.x, self.y, lx, ly) <= zone_min_dist_sq then
			break
		end
		coroutine.sleep(0.25)
		i = i + 1
	end
	self = windower.ffxi.get_mob_by_target('me')
	if not self or dist_sq(self.x, self.y, lx, ly) > zone_min_dist_sq then
		_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_ZONE_TOO_FAR:min_linear_yalms=' .. tostring(zone_min_linear)
		return
	end
	local inj_ok, inj_err = pcall(function()
		packets.inject(packet)
	end)
	if not inj_ok then
		_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_ZONE_INJECT_FAIL:' .. tostring(inj_err)
		return
	end
	_G.UC_LAST_PARTY_FOLLOW_OP = ''
end

local function ipc_dispatch_ucpf_zone(msg)
	local parts = {}
	for part in msg:gmatch('[^|]+') do
		parts[#parts + 1] = part
	end
	if #parts < 4 or parts[1] ~= 'ucpf_zone' then
		return
	end
	local leader_nm = parts[2]
	local zone_line = tonumber(parts[3])
	local zone_type = tonumber(parts[4])
	if leader_nm == nil or leader_nm == '' or zone_line == nil or zone_type == nil then
		return
	end
	local s = _G.UC_SETTINGS
	if not s or not s.party_follow or (s.party_follow_id or 0) == 0 then
		return
	end
	local lid = s.party_follow_id or 0
	local lname = leader_name_lower(s, lid)
	if lname == '' or leader_nm:lower() ~= lname then
		return
	end
	local c = ipc_pos[lname]
	if not c or not c.x or not c.y then
		_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_ZONE_NO_LEADER_POS:' .. lname
		return
	end
	coroutine.schedule(function()
		zone_follow_replay(zone_line, zone_type, c.zone, c.x, c.y)
	end, 0.05)
end

function M.ipc_message(msg)
	if type(msg) ~= 'string' then
		return
	end
	if msg:sub(1, 11) == 'ucpf_zone|' then
		ipc_dispatch_ucpf_zone(msg)
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
	ipc_pos[name:lower()] = { x = x, y = y, zone = zraw, t = os.clock() }
end

--- Call every prerender from UnifiedCombat (all instances) so followers receive fresh x/y.
function M.broadcast_self_ipc()
	local now = os.clock()
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
function M.outgoing_chunk(id, data, blocked)
	if blocked or id ~= REQUEST_ZONE or not data then
		return false
	end
	local p = windower.ffxi.get_player()
	if not p or not p.name then
		return false
	end
	local ok, pkt = pcall(function()
		return packets.parse('outgoing', data)
	end)
	if ok and pkt then
		local zl = pkt['Zone Line']
		local zt = pkt['Type']
		if zl ~= nil and zt ~= nil then
			local nm = tostring(p.name):gsub('|', '_')
			windower.send_ipc_message(('ucpf_zone|%s|%s|%s'):format(nm, tostring(zl), tostring(zt)))
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
	local mn = tonumber(s and s.party_follow_min) or 0.5
	local mx = tonumber(s and s.party_follow_max) or 50
	local ff_until = tonumber(rawget(_G, 'UC_FIGHT_FOLLOW_ACTIVE_UNTIL')) or 0
	if os.clock() < ff_until then
		local fight_min = tonumber(s and s.fight_follow_min) or mn
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

local function combat_engine_suppresses_follow()
	if not Start_Engine then
		return false
	end
	-- Exception: if combat-close approach is currently gated by puller policy, allow party-follow
	-- to continue moving the character so it does not orphan or keep stale run vectors.
	local puller_block_until = tonumber(rawget(_G, 'UC_PULLER_APPROACH_BLOCK_UNTIL')) or 0
	if os.clock() < puller_block_until then
		return false
	end
	local p = windower.ffxi.get_player()
	if not p then
		return true
	end
	if p.status == 1 then
		return true
	end
	-- Core sets this while a valid combat target exists (including pre-engage windows).
	-- Honor it so party-follow never overrides approach movement.
	local ci_until = tonumber(rawget(_G, 'UC_COMBAT_INTENT_UNTIL')) or 0
	if os.clock() < ci_until then
		return true
	end
	-- Additional guard: if autotarget is active and we currently have a living monster
	-- selected, suppress follow even before status flips to Engaged.
	local s = rawget(_G, 'UC_SETTINGS')
	if s and s.autotarget then
		local t = windower.ffxi.get_mob_by_target('t')
		if t and t.id and t.id ~= 0 and t.valid_target and t.spawn_type == 16 and (t.hpp or 0) > 0 then
			return true
		end
	end
	return false
end

local function zone_suspend_active()
	local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	return type(zu) == 'number' and os.clock() < zu
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
		if c and c.x and c.y and (os.clock() - c.t) < 2.5 then
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
	local s = _G.UC_SETTINGS
	if not s or not s.party_follow or (s.party_follow_id or 0) == 0 then
		return
	end
	if combat_engine_suppresses_follow() then
		return
	end
	if zone_suspend_active() then
		return
	end
	local p = windower.ffxi.get_player()
	if not p then
		return
	end
	local lid = s.party_follow_id or 0
	if lid == p.id then
		return
	end
	local self_mob = windower.ffxi.get_mob_by_target('me')
	if not self_mob or not self_mob.x or not self_mob.y then
		return
	end
	local info = windower.ffxi.get_info()
	local zone_self = info and info.zone
	local lname = leader_name_lower(s, lid)
	local lx, ly = resolve_leader_xy(s, lid, lname, zone_self)
	if not lx or not ly then
		windower.ffxi.run(false)
		return
	end
	local ok, leader_mob = pcall(function()
		return windower.ffxi.get_mob_by_id(lid)
	end)
	if ok and leader_mob and leader_mob.id and leader_mob.id ~= 0 and leader_mob.hpp ~= nil and leader_mob.hpp <= 0 then
		windower.ffxi.run(false)
		return
	end
	local min_dist, max_dist = follow_dist_sq_bounds(s)
	local d2 = dist_sq(self_mob.x, self_mob.y, lx, ly)
	if d2 > min_dist and d2 < max_dist then
		local len = math.sqrt(d2)
		if len < 1 then
			len = 1
		end
		windower.ffxi.run((lx - self_mob.x) / len, (ly - self_mob.y) / len)
	elseif d2 <= min_dist then
		windower.ffxi.run(false)
	else
		windower.ffxi.run(false)
	end
end

return M
