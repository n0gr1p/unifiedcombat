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

local files = require('files')
local res = require('resources')
local uc_active_config = require('uc_active_config')
local uc_party_follow = require('uc_party_follow')
local texts_ok, texts = pcall(require, 'texts')

local mod = {}

local last_recording = false
local last_follow_enabled = false
local last_tick_at = 0
local tick_interval = 0.20
local last_autoload_file = ''
local last_autoload_at = 0
local autoload_interval = 1.0
local follow_state = {
	index = 1,
	dir = 1, -- 1 forward, -1 reverse
}
local follow_arrival_tolerance = 0.8
local single_point_slack_yalms = 0.5
local debug_overlay = nil
local debug_target_overlay = nil
local follow_paused = false
local follow_pause_anchor_index = nil
local follow_pause_reason = 'NONE'

local function active_value_or_flat(path, flat_value)
	local active_value = uc_active_config.get_path(path)
	if active_value ~= nil then
		return active_value
	end
	return flat_value
end

local function path_recording_enabled(settings)
	return active_value_or_flat('config.movement.path.recording', settings and settings.path_recording) == true
end

local function path_follow_enabled(settings)
	return active_value_or_flat('config.movement.path.follow_enabled', settings and settings.path_follow_enabled) == true
end

local function path_file_name(settings)
	return tostring(active_value_or_flat('config.movement.path.file_name', settings and settings.path_file_name) or '')
end

local function path_route_type(settings)
	return tostring(active_value_or_flat('config.movement.path.route_type', settings and settings.path_route_type) or 'unknown')
end

local function path_party_gate_yalms(settings)
	return tonumber(active_value_or_flat('config.movement.path.party_gate_yalms', settings and settings.path_party_gate_yalms)) or 3.0
end

local function path_resume_index_window(settings)
	return tonumber(active_value_or_flat('config.movement.path.resume_index_window', settings and settings.path_resume_index_window)) or 12
end

local function party_follow_enabled(settings)
	return active_value_or_flat('config.follow.party.enabled', settings and settings.party_follow) == true
end

local function party_follow_id(settings)
	return tonumber(active_value_or_flat('config.follow.party.leader_id', settings and settings.party_follow_id)) or 0
end

local function sanitize_name(s)
	local v = tostring(s or ''):lower()
	v = v:gsub('[^%w%-_]+', '_')
	v = v:gsub('_+', '_')
	v = v:gsub('^_+', ''):gsub('_+$', '')
	if v == '' then
		return 'unknown'
	end
	return v
end

local function clone_points(points)
	local out = {}
	for i = 1, #(points or {}) do
		local p = points[i]
		out[#out + 1] = { x = p.x, y = p.y, z = p.z }
	end
	return out
end

local function dist3(a, b)
	local dx = (a.x or 0) - (b.x or 0)
	local dy = (a.y or 0) - (b.y or 0)
	local dz = (a.z or 0) - (b.z or 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function get_zone_name()
	local info = windower.ffxi.get_info()
	local zid = info and info.zone
	local z = zid and res.zones[zid]
	return tostring((z and z.en) or 'unknown_zone')
end

local function build_path_file_name()
	local p = windower.ffxi.get_player() or {}
	local char = sanitize_name(p.name or 'unknown')
	local job = sanitize_name(p.main_job or 'unknown')
	local zone = sanitize_name(get_zone_name())
	return string.format('%s_%s_%s_Path.lua', char, job, zone)
end

local function path_file_relpath(file_name)
	return 'data/paths/' .. tostring(file_name or '')
end

local function serialize_lua(v, indent)
	indent = indent or 0
	local t = type(v)
	if t == 'nil' then
		return 'nil'
	elseif t == 'number' or t == 'boolean' then
		return tostring(v)
	elseif t == 'string' then
		return string.format('%q', v)
	elseif t ~= 'table' then
		return string.format('%q', tostring(v))
	end
	local next_indent = indent + 2
	local pad = string.rep(' ', indent)
	local npad = string.rep(' ', next_indent)
	local parts = { '{' }
	for k, vv in pairs(v) do
		local key
		if type(k) == 'string' and k:match('^[_%a][_%w]*$') then
			key = k
		else
			key = '[' .. serialize_lua(k, next_indent) .. ']'
		end
		parts[#parts + 1] = '\n' .. npad .. key .. ' = ' .. serialize_lua(vv, next_indent) .. ','
	end
	if #parts > 1 then
		parts[#parts + 1] = '\n' .. pad .. '}'
	else
		parts[#parts + 1] = '}'
	end
	return table.concat(parts, '')
end

local function write_path_file(settings)
	local file_name = path_file_name(settings)
	if file_name == '' then
		return false
	end
	local p = windower.ffxi.get_player() or {}
	local payload = {
		version = 1,
		character = tostring(p.name or ''),
		job = tostring(p.main_job or ''),
		zone = get_zone_name(),
		route_type = path_route_type(settings),
		points = clone_points(settings.path_points or {}),
	}
	local content = 'return ' .. serialize_lua(payload, 0) .. '\n'
	local fobj = files.new(path_file_relpath(file_name), true)
	local ok = files.write(fobj, content)
	return ok ~= nil
end

local function read_path_file(settings)
	local file_name = path_file_name(settings)
	if file_name == '' then
		return false
	end
	local path = path_file_relpath(file_name)
	if not files.exists(path) then
		return false
	end
	local content = files.read(path)
	if type(content) ~= 'string' or content == '' then
		return false
	end
	local loader = loadstring or load
	local chunk = loader and loader(content) or nil
	if type(chunk) ~= 'function' then
		return false
	end
	local ok, payload = pcall(chunk)
	if not ok or type(payload) ~= 'table' or type(payload.points) ~= 'table' then
		return false
	end
	local out = {}
	for i = 1, #payload.points do
		local p = payload.points[i]
		local x = tonumber(p and p.x)
		local y = tonumber(p and p.y)
		local z = tonumber(p and p.z)
		if x and y and z then
			out[#out + 1] = { x = x, y = y, z = z }
		end
	end
	settings.path_points = out
	settings.path_route_type = tostring(payload.route_type or path_route_type(settings) or 'unknown')
	return #out > 0
end

local function reset_recording_state(settings)
	settings.path_file_name = build_path_file_name()
	settings.path_points = {}
	settings.path_route_type = 'unknown'
	settings.path_distance_to_start = 0
end

local function classify_route(settings)
	local points = settings.path_points or {}
	if #points < 2 then
		settings.path_route_type = 'unknown'
		settings.path_distance_to_start = 0
		return
	end
	local d = dist3(points[1], points[#points])
	settings.path_distance_to_start = d
	if d <= 10.0 then
		settings.path_route_type = 'loop'
	else
		settings.path_route_type = 'patrol'
	end
end

local function classify_route_from_points(points)
	if #points < 2 then
		return 'unknown'
	end
	local d = dist3(points[1], points[#points])
	if d <= 10.0 then
		return 'loop'
	end
	return 'patrol'
end

local function current_position()
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or not me.x or not me.y or not me.z then
		return nil
	end
	return { x = me.x, y = me.y, z = me.z }
end

local function dist2_xy(a, b)
	local dx = (a.x or 0) - (b.x or 0)
	local dy = (a.y or 0) - (b.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function closest_point_index(points, me)
	local best_i = 1
	local best_d = math.huge
	for i = 1, #points do
		local p = points[i]
		if p and p.x ~= nil and p.y ~= nil then
			local d = dist2_xy(me, p)
			if d < best_d then
				best_d = d
				best_i = i
			end
		end
	end
	return best_i
end

local function normalize_resume_window(settings)
	local w = path_resume_index_window(settings)
	w = math.floor(w + 0.5)
	if w < 1 then
		w = 1
	elseif w > 200 then
		w = 200
	end
	return w
end

local function normalize_route(settings, points)
	local route = path_route_type(settings)
	if route == 'unknown' then
		route = classify_route_from_points(points or {})
		if settings then
			settings.path_route_type = route
		end
	end
	return route
end

local function index_distance(route, n, a, b)
	local da = math.abs((a or 1) - (b or 1))
	if route == 'loop' and n > 1 then
		local wrap = n - da
		if wrap < da then
			return wrap
		end
	end
	return da
end

local function closest_point_index_near_anchor(settings, points, me, anchor_index)
	local n = #points
	if n <= 0 then
		return 1
	end
	local anchor = math.max(1, math.min(n, tonumber(anchor_index) or 1))
	local route = normalize_route(settings, points)
	local window = normalize_resume_window(settings)
	local best_i, best_d = nil, math.huge
	for i = 1, n do
		local p = points[i]
		if p and p.x ~= nil and p.y ~= nil then
			local idx_d = index_distance(route, n, i, anchor)
			if idx_d <= window then
				local d = dist2_xy(me, p)
				if d < best_d then
					best_d = d
					best_i = i
				end
			end
		end
	end
	if best_i then
		return best_i
	end
	return anchor
end

local function set_follow_paused(paused)
	if paused then
		if not follow_paused then
			follow_pause_anchor_index = tonumber(follow_state.index) or 1
		end
		follow_paused = true
		return
	end
	follow_paused = false
	follow_pause_anchor_index = nil
	follow_pause_reason = 'NONE'
end

local function update_distance_to_start(settings, pos)
	local points = settings.path_points or {}
	if #points == 0 then
		settings.path_distance_to_start = 0
		return
	end
	settings.path_distance_to_start = dist3(pos, points[1])
end

local function maybe_capture_point(settings)
	local pos = current_position()
	if not pos then
		return false
	end
	settings.path_points = settings.path_points or {}
	update_distance_to_start(settings, pos)
	local points = settings.path_points
	local last = points[#points]
	if not last or dist3(pos, last) > 0.9 then
		points[#points + 1] = pos
		write_path_file(settings)
		return true
	end
	return false
end

local function party_follow_active(settings)
	return party_follow_enabled(settings) and party_follow_id(settings) > 0
end

local function resolve_member_xy(pm, zone_self)
	if not pm then
		return nil, nil, 'srv'
	end
	local px, py = nil, nil
	local pname = pm.name and tostring(pm.name):lower() or ''
	if pname ~= '' and uc_party_follow and type(uc_party_follow.get_ipc_position) == 'function' then
		px, py = uc_party_follow.get_ipc_position(pname, zone_self, 1.2)
	end
	if px ~= nil and py ~= nil then
		return px, py, 'ipc'
	end
	return pm.x, pm.y, 'srv'
end

local function party_cohesion_ok(max_dist)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or me.x == nil or me.y == nil then
		return false
	end
	local info = windower.ffxi.get_info()
	local zone_self = info and info.zone
	local party = windower.ffxi.get_party() or {}
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local e = party[key]
		local pm = e and e.mob
		if pm and pm.id and pm.id ~= 0 and pm.id ~= me.id and (pm.hpp == nil or pm.hpp > 0) then
			local px, py = resolve_member_xy(pm, zone_self)
			if px ~= nil and py ~= nil then
				local d = math.sqrt((px - me.x) * (px - me.x) + (py - me.y) * (py - me.y))
				if d > max_dist then
					return false
				end
			end
		end
	end
	return true
end

local function collect_party_distances()
	local out = {}
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or me.x == nil or me.y == nil then
		return out
	end
	local info = windower.ffxi.get_info()
	local zone_self = info and info.zone
	local party = windower.ffxi.get_party() or {}
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local e = party[key]
		local pm = e and e.mob
		if pm and pm.id and pm.id ~= 0 and pm.id ~= me.id and (pm.hpp == nil or pm.hpp > 0) and pm.x ~= nil and pm.y ~= nil then
			local px, py, source = resolve_member_xy(pm, zone_self)
			if px ~= nil and py ~= nil then
				local d = math.sqrt((px - me.x) * (px - me.x) + (py - me.y) * (py - me.y))
				out[#out + 1] = { name = tostring(pm.name or ('id:' .. tostring(pm.id))), dist = d, source = source }
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.dist or 999) < (b.dist or 999)
	end)
	return out
end

local function collect_aggressive_mobs_with_targets(max_dist)
	local out = {}
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or me.x == nil or me.y == nil then
		return out
	end
	local party_name_by_id = {}
	local p = windower.ffxi.get_player()
	if p and p.id and p.id ~= 0 then
		party_name_by_id[tonumber(p.id) or 0] = tostring(p.name or 'me')
	end
	local party = windower.ffxi.get_party() or {}
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local e = party[key]
		local pm = e and e.mob
		if pm and pm.id and pm.id ~= 0 then
			party_name_by_id[tonumber(pm.id) or 0] = tostring(pm.name or ('id:' .. tostring(pm.id)))
		end
	end
	local max_scan = tonumber(max_dist) or 30.0
	if max_scan < 5.0 then
		max_scan = 5.0
	elseif max_scan > 120.0 then
		max_scan = 120.0
	end
	local marray = windower.ffxi.get_mob_array() or {}
	for _, mob in pairs(marray) do
		if mob and mob.id and mob.id ~= 0 and mob.is_npc == true and (tonumber(mob.hpp) or 0) > 0 and mob.x ~= nil and mob.y ~= nil and (tonumber(mob.status) or 0) == 1 then
			local dx = (mob.x or 0) - (me.x or 0)
			local dy = (mob.y or 0) - (me.y or 0)
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist <= max_scan then
				local t = nil
				local claim_tid = tonumber(mob.claim_id) or 0
				if claim_tid > 0 and party_name_by_id[claim_tid] ~= nil then
					local ok_claim, by_claim = pcall(function()
						return windower.ffxi.get_mob_by_id(claim_tid)
					end)
					if ok_claim then
						t = by_claim
					end
					if not t or not t.id or t.id == 0 then
						t = { id = claim_tid, name = '(claim)' }
					end
				end
				if (not t or not t.id or t.id == 0) and mob.target_index and tonumber(mob.target_index) and tonumber(mob.target_index) > 0 then
					local ok_idx, by_idx = pcall(function()
						return windower.ffxi.get_mob_by_index(mob.target_index)
					end)
					if ok_idx then
						t = by_idx
					end
				end
				if (not t or not t.id or t.id == 0) and mob.target and tonumber(mob.target) and tonumber(mob.target) > 0 then
					local ok_id, by_id = pcall(function()
						return windower.ffxi.get_mob_by_id(mob.target)
					end)
					if ok_id then
						t = by_id
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
								local ok_rec, by_rec = pcall(function()
									return windower.ffxi.get_mob_by_id(rid)
								end)
								if ok_rec and by_rec and by_rec.id and by_rec.id ~= 0 then
									t = by_rec
								else
									t = { id = rid, name = '(pkt)' }
								end
							end
						end
					end
				end
				local tid = tonumber(t and t.id) or 0
				local pname = party_name_by_id[tid]
				local target_name = pname or tostring((t and t.name) or '(none)')
				out[#out + 1] = {
					mob_name = tostring(mob.name or ('mob:' .. tostring(mob.id))),
					mob_id = tonumber(mob.id) or 0,
					dist = dist,
					hpp = tonumber(mob.hpp) or 0,
					status = tonumber(mob.status) or 0,
					spawn_type = tonumber(mob.spawn_type) or 0,
					valid_target = mob.valid_target == true and 1 or 0,
					claim_id = claim_tid,
					target_name = target_name,
					target_id = tid,
					target_is_party = pname and 1 or 0,
				}
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.target_is_party or 0) ~= (b.target_is_party or 0) then
			return (a.target_is_party or 0) > (b.target_is_party or 0)
		end
		if (a.dist or 999) ~= (b.dist or 999) then
			return (a.dist or 999) < (b.dist or 999)
		end
		return (a.mob_id or 0) < (b.mob_id or 0)
	end)
	return out
end

local function ensure_debug_overlay()
	if not texts_ok or not texts then
		return nil
	end
	if debug_overlay then
		return debug_overlay
	end
	debug_overlay = texts.new('', {
		pos = { x = 100, y = 360 },
		bg = { alpha = 180, red = 20, green = 20, blue = 20 },
		flags = { right = false, bottom = false, bold = false, draggable = true },
		padding = 6,
		text = { font = 'Consolas', size = 10, alpha = 255, red = 180, green = 220, blue = 255, stroke = { width = 1, alpha = 180 } },
	})
	return debug_overlay
end

local function ensure_target_debug_overlay()
	if not texts_ok or not texts then
		return nil
	end
	if debug_target_overlay then
		return debug_target_overlay
	end
	debug_target_overlay = texts.new('', {
		pos = { x = 620, y = 360 },
		bg = { alpha = 180, red = 20, green = 20, blue = 20 },
		flags = { right = false, bottom = false, bold = false, draggable = true },
		padding = 6,
		text = { font = 'Consolas', size = 10, alpha = 255, red = 220, green = 220, blue = 220, stroke = { width = 1, alpha = 180 } },
	})
	return debug_target_overlay
end

local function hide_debug_overlay()
	if debug_overlay then
		pcall(function()
			debug_overlay:hide()
		end)
	end
	if debug_target_overlay then
		pcall(function()
			debug_target_overlay:hide()
		end)
	end
end

local function player_status_description(status)
	local s = tonumber(status) or -1
	local map = {
		[0] = 'Idle',
		[1] = 'Engaged',
		[2] = 'Dead',
		[3] = 'Event/Cutscene',
		[4] = 'Chocobo/Mount',
	}
	return map[s] or 'Unknown'
end

local function append_table_lines(out, key, value, indent, depth, max_depth, max_lines, seen)
	if #out >= max_lines then
		return
	end
	local pad = string.rep(' ', indent)
	local vt = type(value)
	if vt ~= 'table' then
		local rendered
		if vt == 'string' then
			rendered = string.format('%q', value)
		else
			rendered = tostring(value)
		end
		out[#out + 1] = string.format('%s%s: %s', pad, tostring(key), rendered)
		return
	end
	if seen[value] then
		out[#out + 1] = string.format('%s%s: <cycle>', pad, tostring(key))
		return
	end
	seen[value] = true
	out[#out + 1] = string.format('%s%s: {', pad, tostring(key))
	if depth >= max_depth then
		out[#out + 1] = string.format('%s  ...', pad)
		out[#out + 1] = string.format('%s}', pad)
		return
	end
	local keys = {}
	for k in pairs(value) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for i = 1, #keys do
		if #out >= max_lines then
			break
		end
		local k = keys[i]
		append_table_lines(out, k, value[k], indent + 2, depth + 1, max_depth, max_lines, seen)
	end
	if #out < max_lines then
		out[#out + 1] = string.format('%s}', pad)
	end
end

local function render_target_debug_overlay()
	local ov = ensure_target_debug_overlay()
	if not ov then
		return
	end
	local lines = { 'UC Target Metadata (get_mob_by_id)' }
	local cur = windower.ffxi.get_mob_by_target('t')
	if not cur or not cur.id or cur.id == 0 then
		lines[#lines + 1] = '(no current target)'
		ov:text(table.concat(lines, '\n'))
		ov:show()
		return
	end
	local mob = windower.ffxi.get_mob_by_id(cur.id)
	if not mob then
		lines[#lines + 1] = ('target_id=%d (lookup failed)'):format(tonumber(cur.id) or 0)
		ov:text(table.concat(lines, '\n'))
		ov:show()
		return
	end
	lines[#lines + 1] = ('target_id=%d name=%s'):format(tonumber(mob.id) or 0, tostring(mob.name or '?'))
	local claim_id = tonumber(mob.claim_id) or 0
	if claim_id > 0 then
		local claim_name = ''
		local claim_mob = windower.ffxi.get_mob_by_id(claim_id)
		if claim_mob and claim_mob.name and tostring(claim_mob.name) ~= '' then
			claim_name = tostring(claim_mob.name)
		else
			local party = windower.ffxi.get_party() or {}
			for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
				local entry = party[key]
				local pm = entry and entry.mob
				if pm and tonumber(pm.id) == claim_id then
					claim_name = tostring(pm.name or '')
					break
				end
			end
		end
		if claim_name == '' then
			claim_name = '(unknown)'
		end
		lines[#lines + 1] = ('claim: %d -> %s'):format(claim_id, claim_name)
	else
		lines[#lines + 1] = ('claim: %d -> (unclaimed)'):format(claim_id)
	end
	append_table_lines(lines, 'mob', mob, 0, 0, 3, 140, {})
	ov:text(table.concat(lines, '\n'))
	ov:show()
end

local function render_debug_overlay(settings)
	local debug_enabled = uc_active_config.get_path('config.debug.enabled')
	if debug_enabled == nil then
		debug_enabled = settings.debug
	end
	if debug_enabled ~= true then
		hide_debug_overlay()
		return
	end
	local ov = ensure_debug_overlay()
	if not ov then
		return
	end
	local rows = collect_party_distances()
	local lines = { 'UC Pathing Party Distances (yalm)' }
	local player = windower.ffxi.get_player() or {}
	local st = tonumber(player.status) or -1
	lines[#lines + 1] = ('state: %d %s'):format(st, player_status_description(st))
	local gate = path_party_gate_yalms(settings)
	if gate < 0.5 then
		gate = 0.5
	elseif gate > 50 then
		gate = 50
	end
	local cohesion = party_cohesion_ok(gate)
	lines[#lines + 1] = ('cohesion<=%.2f: %s'):format(gate, cohesion and 'PASS' or 'BLOCK')
	lines[#lines + 1] = ('path_follow_enabled: %s'):format(tostring(path_follow_enabled(settings)))
	lines[#lines + 1] = ('path_points_count: %d'):format(type(settings.path_points) == 'table' and #settings.path_points or 0)
	lines[#lines + 1] = ('path_follow_paused: %s'):format(tostring(follow_paused == true))
	lines[#lines + 1] = ('path_pause_reason: %s'):format(tostring(follow_pause_reason or 'NONE'))
	local function count_tank_actions(v)
		if type(v) == 'table' then
			return #v
		end
		if type(v) == 'string' then
			local n = 0
			for part in v:gmatch('[^|]+') do
				if tostring(part):match('%S') then
					n = n + 1
				end
			end
			return n
		end
		return 0
	end
	local tank_on = (settings and (settings.tank == true or settings.tank == 1 or tostring(settings.tank):lower() == 'true')) and 1 or 0
	local at_on = (settings and (settings.autotarget == true or settings.autotarget == 1 or tostring(settings.autotarget):lower() == 'true')) and 1 or 0
	local ta_n = count_tank_actions(settings and settings.tank_enmity_actions)
	local v_mob = tostring(rawget(_G, 'UC_TANK_VIOLATION_MOB_NAME') or '')
	local v_victim = tostring(rawget(_G, 'UC_TANK_VIOLATION_VICTIM_NAME') or '')
	local v_hpp = tonumber(rawget(_G, 'UC_TANK_VIOLATION_VICTIM_HPP') or 0) or 0
	local last_br = tostring(rawget(_G, 'UC_LAST_BLOCK_REASON') or '')
	if last_br == '' then
		last_br = '(none)'
	end
	local tank_sched = tostring(rawget(_G, 'UC_TANK_ENMITY_BLOCK') or '')
	if tank_sched == '' then
		tank_sched = '(none)'
	end
	lines[#lines + 1] = ('tank=%d autotarget=%d tank_actions=%d'):format(tank_on, at_on, ta_n)
	lines[#lines + 1] = ('tank_violation: mob=%s victim=%s(%d%%)'):format(v_mob ~= '' and v_mob or '(none)', v_victim ~= '' and v_victim or '(none)', v_hpp)
	lines[#lines + 1] = ('last_block: %s'):format(last_br)
	lines[#lines + 1] = ('tank_sched: %s'):format(tank_sched)
	local pf_op = tostring(rawget(_G, 'UC_LAST_PARTY_FOLLOW_OP') or '')
	if pf_op == '' then
		pf_op = '(none)'
	end
	lines[#lines + 1] = 'party_follow_last_op: ' .. pf_op
	lines[#lines + 1] = 'party_follow_last_5:'
	local op_log = rawget(_G, 'UC_PARTY_FOLLOW_OP_LOG')
	if type(op_log) == 'table' and #op_log > 0 then
		for i = 1, math.min(5, #op_log) do
			lines[#lines + 1] = ('  %d) %s'):format(i, tostring(op_log[i] or ''))
		end
	else
		lines[#lines + 1] = '  1) (none)'
	end
	if #rows == 0 then
		lines[#lines + 1] = '(no party members found)'
	else
		for i = 1, #rows do
			local r = rows[i]
			lines[#lines + 1] = ('%s: %.2f [%s]'):format(r.name, r.dist or 0, r.source or 'srv')
		end
	end
	local tank_rows = collect_aggressive_mobs_with_targets(30.0)
	lines[#lines + 1] = ''
	lines[#lines + 1] = 'aggressive mobs<=30y (party targets first):'
	if #tank_rows == 0 then
		lines[#lines + 1] = '  (none)'
	else
		local shown = math.min(8, #tank_rows)
		for i = 1, shown do
			local r = tank_rows[i]
			lines[#lines + 1] = ('  %s[%d] %.1fy hpp=%d st=%d sp=%d vt=%d -> %s[%d] party=%d'):format(
				tostring(r.mob_name or '?'),
				tonumber(r.mob_id) or 0,
				tonumber(r.dist) or 0,
				tonumber(r.hpp) or 0,
				tonumber(r.status) or 0,
				tonumber(r.spawn_type) or 0,
				tonumber(r.valid_target) or 0,
				tostring(r.target_name or '?'),
				tonumber(r.target_id) or 0,
				tonumber(r.target_is_party) or 0
			)
			if tonumber(r.claim_id) and tonumber(r.claim_id) > 0 then
				lines[#lines] = lines[#lines] .. (' claim=%d'):format(tonumber(r.claim_id))
			end
		end
	end
	ov:text(table.concat(lines, '\n'))
	ov:show()
	render_target_debug_overlay()
end

local function should_pause_for_combat()
	if not Start_Engine then
		return false, 'ENGINE_OFF'
	end
	local now = uc_now_s()
	local owner = tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or 'none')
	local lock_until = tonumber(rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')) or 0
	if owner ~= 'none' and owner ~= 'path' and now < lock_until then
		return true, ('OWNER_%s'):format(owner)
	end
	if uc_party_follow and type(uc_party_follow.should_suppress_follow_or_path_return_now) == 'function' then
		local suppress, suppress_reason = uc_party_follow.should_suppress_follow_or_path_return_now(rawget(_G, 'UC_SETTINGS') or {}, now)
		if suppress == true then
			return true, ('COMBAT_TRANSITION:%s'):format(tostring(suppress_reason or 'ACTIVE'))
		end
	end
	local p = windower.ffxi.get_player()
	if not p then
		return true, 'NO_PLAYER'
	end
	local engaged = tonumber(p.status) == 1
	local cur = windower.ffxi.get_mob_by_target('t')
	local have_live_target = cur and cur.valid_target and tonumber(cur.spawn_type) == 16 and (tonumber(cur.hpp) or 0) > 0
	local pull_waiting = (rawget(_G, 'UC_PULL_SPELL_WAITING') == true)
	local pull_wait_until = tonumber(rawget(_G, 'UC_PULL_SPELL_WAIT_UNTIL')) or 0
	local pull_cast_hold_until = tonumber(rawget(_G, 'UC_PULL_CAST_HOLD_UNTIL')) or 0
	if now < pull_cast_hold_until then
		return true, 'PULL_CAST_HOLD'
	end
	if pull_waiting and now >= pull_wait_until and pull_wait_until > 0 then
		-- Pull wait timed out but flag survived: clear stale wait so path-follow can resume.
		_G.UC_PULL_SPELL_WAITING = false
		_G.UC_PULL_SPELL_WAIT_UNTIL = 0
		pull_waiting = false
	end
	if (not engaged) and (not have_live_target) and (not pull_waiting) then
		-- Defensive stale-state cleanup: these flags should only hold while actively
		-- approaching/casting pull. If we are idle with no live combat target, clear them.
		_G.UC_PREENGAGE_APPROACH_ACTIVE = false
		local pa = tonumber(rawget(_G, 'UC_PULL_APPROACH_UNTIL')) or 0
		if pa > now then
			_G.UC_PULL_APPROACH_UNTIL = 0
		end
	end
	local pull_approach_until = tonumber(rawget(_G, 'UC_PULL_APPROACH_UNTIL')) or 0
	if now < pull_approach_until then
		return true, 'PULL_APPROACH'
	end
	if rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true then
		return true, 'PREENGAGE'
	end
	if pull_waiting then
		return true, 'PULL_WAIT'
	end
	if engaged then
		return true, 'ENGAGED'
	end
	return false, 'NONE'
end

local function stop_move()
	windower.ffxi.run(false)
end

local function run_to_point(me, point)
	local dx = (point.x or 0) - (me.x or 0)
	local dy = (point.y or 0) - (me.y or 0)
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.001 then
		return false
	end
	windower.ffxi.run(dx / len, dy / len)
	return true
end

local function ensure_path_points(settings)
	if type(settings.path_points) == 'table' and #settings.path_points > 0 then
		return true
	end
	return read_path_file(settings)
end

local function maybe_autoload_for_ui(settings)
	local file_name = path_file_name(settings)
	if file_name == '' then
		return false
	end
	local now = uc_now_s()
	if file_name == last_autoload_file and (now - last_autoload_at) < autoload_interval then
		return false
	end
	last_autoload_file = file_name
	last_autoload_at = now
	local have_points = type(settings.path_points) == 'table' and #settings.path_points > 0
	if have_points then
		return false
	end
	return read_path_file(settings)
end

local function ensure_path_file_binding(settings)
	local expected = build_path_file_name()
	if path_file_name(settings) == '' then
		settings.path_file_name = expected
		return
	end
	-- If char/job/zone changed, rebind to that context for follow.
	if path_file_name(settings) ~= expected and not path_recording_enabled(settings) then
		settings.path_file_name = expected
		settings.path_points = {}
		settings.path_route_type = 'unknown'
	end
end

local function advance_follow_index(settings, points)
	local n = #points
	if n <= 1 then
		follow_state.index = 1
		return
	end
	local route = path_route_type(settings)
	if route == 'unknown' then
		route = classify_route_from_points(points)
		settings.path_route_type = route
	end
	if route == 'loop' then
		follow_state.index = follow_state.index + 1
		if follow_state.index > n then
			follow_state.index = 1
		end
		return
	end
	-- patrol behavior (or unknown fallback): bounce back and forth.
	local next_index = follow_state.index + follow_state.dir
	if next_index > n then
		follow_state.dir = -1
		next_index = n - 1
		if next_index < 1 then
			next_index = 1
		end
	elseif next_index < 1 then
		follow_state.dir = 1
		next_index = 2
		if next_index > n then
			next_index = n
		end
	end
	follow_state.index = next_index
end

local function tick_follow(settings)
	if not path_follow_enabled(settings) then
		follow_pause_reason = 'PATH_FOLLOW_DISABLED'
		return
	end
	ensure_path_file_binding(settings)
	if not ensure_path_points(settings) then
		follow_pause_reason = 'NO_PATH_POINTS'
		stop_move()
		return
	end
	local points = settings.path_points
	if #points == 0 then
		follow_pause_reason = 'NO_PATH_POINTS'
		stop_move()
		return
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or me.x == nil or me.y == nil then
		stop_move()
		return
	end
	update_distance_to_start(settings, { x = me.x, y = me.y, z = me.z or 0 })
	if party_follow_active(settings) then
		-- Party-follow owns movement when active.
		follow_pause_reason = 'PARTY_FOLLOW_ACTIVE'
		set_follow_paused(true)
		return
	end
	local gate = path_party_gate_yalms(settings)
	if gate < 0.5 then
		gate = 0.5
	elseif gate > 50 then
		gate = 50
	end
	if not party_cohesion_ok(gate) then
		follow_pause_reason = 'PARTY_COHESION_BLOCK'
		stop_move()
		set_follow_paused(true)
		return
	end
	local combat_pause, combat_pause_why = should_pause_for_combat()
	if combat_pause then
		local why = tostring(combat_pause_why or 'UNKNOWN')
		local owner_pause = (why:find('^OWNER_', 1, false) ~= nil)
		local pull_approach_pause = (why == 'PULL_APPROACH')
		-- Yield-only pauses: another movement source should continue driving motion.
		if not owner_pause and not pull_approach_pause then
			stop_move()
		end
		follow_pause_reason = 'COMBAT_PAUSE:' .. why
		set_follow_paused(true)
		return
	end
	if follow_paused and #points > 0 then
		follow_state.index = closest_point_index_near_anchor(
			settings,
			points,
			{ x = me.x, y = me.y },
			follow_pause_anchor_index or follow_state.index
		)
		if follow_state.index >= #points then
			follow_state.dir = -1
		else
			follow_state.dir = 1
		end
		set_follow_paused(false)
	end
	if follow_state.index < 1 or follow_state.index > #points then
		follow_state.index = 1
		follow_state.dir = 1
	end
	local pt = points[follow_state.index]
	if not pt then
		stop_move()
		return
	end
	local d = dist2_xy({ x = me.x, y = me.y }, pt)
	if #points == 1 then
		-- Single-point path acts as a soft anchor: return to point only when outside
		-- slack radius to avoid jitter/bounce around exact coordinates.
		if d <= single_point_slack_yalms then
			stop_move()
			follow_pause_reason = 'SINGLE_POINT_HOLD'
			return
		end
		run_to_point(me, pt)
		follow_pause_reason = 'RUNNING_PATH'
		return
	end
	if d <= follow_arrival_tolerance then
		advance_follow_index(settings, points)
		pt = points[follow_state.index]
		if not pt then
			stop_move()
			return
		end
	end
	run_to_point(me, pt)
	follow_pause_reason = 'RUNNING_PATH'
end

function mod.tick()
	local now = uc_now_s()
	if (now - last_tick_at) < tick_interval then
		return
	end
	last_tick_at = now

	local s = rawget(_G, 'UC_SETTINGS')
	if type(s) ~= 'table' then
		hide_debug_overlay()
		return
	end
	render_debug_overlay(s)
	ensure_path_file_binding(s)
	maybe_autoload_for_ui(s)

	if path_recording_enabled(s) and not last_recording then
		reset_recording_state(s)
		write_path_file(s)
	end

	if path_recording_enabled(s) then
		maybe_capture_point(s)
	elseif last_recording then
		classify_route(s)
		write_path_file(s)
	else
		local pos = current_position()
		if pos then
			update_distance_to_start(s, pos)
		end
	end

	if path_follow_enabled(s) and not last_follow_enabled then
		follow_state.index = 1
		follow_state.dir = 1
		if #s.path_points == 0 then
			read_path_file(s)
		end
		local me = windower.ffxi.get_mob_by_target('me')
		if me and me.x ~= nil and me.y ~= nil and type(s.path_points) == 'table' and #s.path_points > 0 then
			follow_state.index = closest_point_index(s.path_points, { x = me.x, y = me.y })
			if follow_state.index >= #s.path_points then
				follow_state.dir = -1
			else
				follow_state.dir = 1
			end
		end
	elseif not path_follow_enabled(s) and last_follow_enabled then
		-- Explicitly stop any active run vector when path-follow is disabled.
		stop_move()
		set_follow_paused(false)
	end
	if not path_recording_enabled(s) then
		tick_follow(s)
	else
		-- Recording should not inherit prior movement vectors from follow.
		stop_move()
	end

	last_recording = path_recording_enabled(s)
	last_follow_enabled = path_follow_enabled(s)
end

return mod
