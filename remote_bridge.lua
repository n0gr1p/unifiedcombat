--[[
  Non-blocking TCP client to Python hub. NDJSON over newline.
  Expect _G.UC_SETTINGS, _G.UC_ENGINE, Start_Engine, windower.
]]

local socket = require('socket')
local json = require('json')
local res = require('resources')
local uc_ws_memory = require('uc_ws_memory')
local uc_ignore = require('uc_ignore')
local uc_partner_list = require('uc_partner_list')
local uc_target_ignore = require('uc_target_ignore')
local uc_add_priority = require('uc_add_priority')

local function uc_trim(s)
	if not s then
		return ''
	end
	return tostring(s):match('^%s*(.-)%s*$') or ''
end

--- Decode numeric mob id from hub JSON. Uses rawget so T-table __index (table.*) does not shadow keys like "id".
local function uc_remote_message_mob_id(msg, ...)
	if not msg then
		return nil
	end
	for i = 1, select('#', ...) do
		local key = select(i, ...)
		local v = rawget(msg, key)
		if v ~= nil then
			if type(v) == 'number' then
				local n = math.floor(v + 0.5)
				if n ~= 0 then
					return n
				end
			elseif type(v) == 'string' then
				local n = tonumber(uc_trim(v))
				if n and n ~= 0 then
					return n
				end
			end
		end
	end
	return nil
end

--- Last-resort: read 1-based list index from raw JSON line (handles odd decoders / nested keys).
local function uc_remote_list_index_from_line(raw_line)
	if type(raw_line) ~= 'string' then
		return nil
	end
	local n = tonumber(raw_line:match('"index"%s*:%s*(%d+)') or raw_line:match('"Index"%s*:%s*(%d+)') or
		raw_line:match('"slot"%s*:%s*(%d+)') or raw_line:match('"Slot"%s*:%s*(%d+)'))
	if n and n >= 1 then
		return math.floor(n + 0.5)
	end
	return nil
end

--- 1-based list slot from WinForms / hub JSON (index or slot).
--- Unwraps mirror_forward so `index` inside `msg` is visible when the game receives the full envelope.
local function uc_remote_list_index(msg, raw_line)
	if not msg or type(msg) ~= 'table' then
		return uc_remote_list_index_from_line(raw_line)
	end
	if msg.op == 'mirror_forward' and type(msg.msg) == 'table' then
		msg = msg.msg
	end
	local v = msg.index or msg.Index or msg.slot or msg.Slot
	if v == nil then
		for k, val in pairs(msg) do
			if type(k) == 'string' then
				local kl = k:lower()
				if (kl == 'index' or kl == 'slot') and val ~= nil then
					v = val
					break
				end
			end
		end
	end
	if v ~= nil then
		local n = tonumber(uc_trim(tostring(v)))
		if n and n >= 1 then
			return math.floor(n + 0.5)
		end
	end
	return uc_remote_list_index_from_line(raw_line)
end

local function uc_resolve_target_id_by_name(name)
	name = uc_trim(name)
	if name == '' then
		return nil
	end
	if type(GetTargetIDByName) == 'function' then
		local tid = GetTargetIDByName(name)
		if tid and tid ~= 0 then
			return tid
		end
	end
	local ok, mob = pcall(function()
		return windower.ffxi.get_mob_by_name(name)
	end)
	if ok and mob and mob.id and mob.id ~= 0 then
		return mob.id
	end
	return nil
end

local function uc_current_target_snapshot()
	local ok, t = pcall(function()
		return windower.ffxi.get_mob_by_target('t')
	end)
	if not ok or not t or not t.id or t.id == 0 then
		return '', 0
	end
	return tostring(t.name or ''), t.id
end

local function json_encode_simple(t)
	local parts = {}
	for k, v in pairs(t) do
		local ks = '"' .. tostring(k) .. '":'
		local vs
		if type(v) == 'string' then
			vs = '"' .. tostring(v):gsub('"', '\\"') .. '"'
		elseif type(v) == 'boolean' then
			vs = v and 'true' or 'false'
		elseif type(v) == 'number' then
			vs = tostring(v)
		else
			vs = '"' .. tostring(v):gsub('"', '\\"') .. '"'
		end
		parts[#parts + 1] = ks .. vs
	end
	return '{' .. table.concat(parts, ',') .. '}'
end

local sock = nil
local recv_buf = ''
local last_connect_try = 0
local last_state_send = 0
local session_id = nil
local cached_ability_options = ''
local last_ability_signature = ''

local function build_session_id()
	local p = windower.ffxi.get_player()
	local char = (p and p.name) or 'unknown'
	local pid = (p and p.id) or 0
	local now_ms = math.floor((socket.gettime and socket.gettime() or os.clock()) * 1000)
	return table.concat({ char, tostring(pid), tostring(now_ms) }, '_')
end

local function close_sock()
	if sock then
		pcall(function()
			sock:close()
		end)
		sock = nil
	end
end

local function safe_send_line(payload)
	if not sock then
		return false
	end
	local ok, err = sock:send(payload .. '\n')
	if not ok then
		close_sock()
		return false
	end
	return true
end

local function uc_remote_host()
	return _G.UC_REMOTE_HOST or '127.0.0.1'
end

local function uc_remote_port()
	return _G.UC_REMOTE_PORT or 27182
end

local function try_connect()
	local now = os.clock()
	if sock then
		return
	end
	if now - last_connect_try < 2 then
		return
	end
	last_connect_try = now
	local tcp, err = socket.tcp()
	if not tcp then
		return
	end
	tcp:settimeout(0.15)
	local ok, cerr = tcp:connect(uc_remote_host(), uc_remote_port())
	tcp:settimeout(0)
	if not ok and cerr ~= 'timeout' then
		tcp:close()
		return
	end
	sock = tcp
	recv_buf = ''
	if not session_id or session_id == '' then
		session_id = build_session_id()
	end
	local p = windower.ffxi.get_player()
	local hello = {
		op = 'hello',
		session = session_id,
		char = p and p.name or 'unknown',
		job = p and p.main_job or '',
		engine = _G.UC_ENGINE or 'melee',
	}
	if not safe_send_line(json_encode_simple(hello)) then
		return
	end
end

local function apply_set(path, value)
	local s = _G.UC_SETTINGS
	if not s or not path then
		return
	end
	local parts = {}
	for part in tostring(path):gmatch('[^.]+') do
		parts[#parts + 1] = part
	end
	local t = s
	for i = 1, #parts - 1 do
		local k = parts[i]
		if t[k] == nil then
			t[k] = {}
		end
		t = t[k]
	end
	local key = parts[#parts]
	local existing = t[key]
	if type(value) == 'string' then
		local v = value:lower()
		if v == 'true' or v == 'on' or v == '1' then
			value = true
		elseif v == 'false' or v == 'off' or v == '0' then
			value = false
		end
	end
	-- Keep bool settings as bool even if transport sent strings.
	if type(existing) == 'boolean' and type(value) ~= 'boolean' then
		value = not (value == nil or value == false or value == '' or value == 0)
	end
	if key == 'party_follow_min' or key == 'party_follow_max' then
		local n = tonumber(tostring(value))
		if not n then
			_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_BAD_NUMBER:' .. key .. ':' .. tostring(value)
			return
		end
		local cur_min = tonumber(s.party_follow_min) or 0.5
		local cur_max = tonumber(s.party_follow_max) or 50
		local next_min, next_max = cur_min, cur_max
		if key == 'party_follow_min' then
			if n < 0.01 then
				n = 0.01
			elseif n > 99 then
				n = 99
			end
			next_min = n
		else
			if n < 0.1 then
				n = 0.1
			elseif n > 200 then
				n = 200
			end
			next_max = n
		end
		if next_min >= next_max then
			_G.UC_LAST_PARTY_FOLLOW_OP = ('PARTY_FOLLOW_MIN_NOT_LT_MAX:min=%.4g max=%.4g'):format(next_min, next_max)
			return
		end
		if key == 'party_follow_min' then
			s.party_follow_min = next_min
		else
			s.party_follow_max = next_max
		end
		_G.UC_LAST_PARTY_FOLLOW_OP = ''
		last_state_send = 0
		return
	end
	if key == 'fight_follow_min' then
		local n = tonumber(tostring(value))
		if not n then
			_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_BAD_NUMBER:' .. key .. ':' .. tostring(value)
			return
		end
		if n < 0.01 then
			n = 0.01
		elseif n > 99 then
			n = 99
		end
		s.fight_follow_min = n
		_G.UC_LAST_PARTY_FOLLOW_OP = ''
		last_state_send = 0
		return
	end
	if key == 'fight_follow_hold_s' then
		local n = tonumber(tostring(value))
		if not n then
			_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_BAD_NUMBER:' .. key .. ':' .. tostring(value)
			return
		end
		if n < 0 then
			n = 0
		elseif n > 60 then
			n = 60
		end
		s.fight_follow_hold_s = n
		_G.UC_LAST_PARTY_FOLLOW_OP = ''
		last_state_send = 0
		return
	end
	if key == 'spacing_band_min' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < -5 then
			n = -5
		elseif n > 2 then
			n = 2
		end
		s.spacing_band_min = n
		last_state_send = 0
		return
	end
	if key == 'spacing_band_max' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < -1 then
			n = -1
		elseif n > 5 then
			n = 5
		end
		s.spacing_band_max = n
		last_state_send = 0
		return
	end
	if key == 'spacing_lookahead_s' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 1.5 then
			n = 1.5
		end
		s.spacing_lookahead_s = n
		last_state_send = 0
		return
	end
	if key == 'spacing_anchor_invalid_ticks' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		n = math.floor(n + 0.5)
		if n < 1 then
			n = 1
		elseif n > 50 then
			n = 50
		end
		s.spacing_anchor_invalid_ticks = n
		last_state_send = 0
		return
	end
	if key == 'spacing_emergency_margin' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 5 then
			n = 5
		end
		s.spacing_emergency_margin = n
		last_state_send = 0
		return
	end
	if key == 'spacing_slot_switch_penalty' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 10 then
			n = 10
		end
		s.spacing_slot_switch_penalty = n
		last_state_send = 0
		return
	end
	if key == 'spacing_slot_switch_margin' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 10 then
			n = 10
		end
		s.spacing_slot_switch_margin = n
		last_state_send = 0
		return
	end
	if key == 'spacing_slot_arrival_tolerance' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 5 then
			n = 5
		end
		s.spacing_slot_arrival_tolerance = n
		last_state_send = 0
		return
	end
	if key == 'spacing_max_agents' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		n = math.floor(n + 0.5)
		if n < 1 then
			n = 1
		elseif n > 6 then
			n = 6
		end
		s.spacing_max_agents = n
		last_state_send = 0
		return
	end
	t[key] = value
end

local function uc_split_pipe(raw)
	local out = {}
	if not raw or raw == '' then
		return out
	end
	for token in tostring(raw):gmatch('[^|]+') do
		if token and token ~= '' then
			out[#out + 1] = token
		end
	end
	return out
end

local function uc_join_pipe(values)
	if not values or #values == 0 then
		return ''
	end
	return table.concat(values, '|')
end

local function uc_unique_sorted(values)
	local seen = {}
	local out = {}
	for _, v in ipairs(values or {}) do
		if v and v ~= '' and not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	table.sort(out)
	return out
end

local function uc_get_job_ability_names()
	local out = {}
	local ab = windower.ffxi.get_abilities()
	local ids = ab and ab.job_abilities or {}
	for _, id in ipairs(ids) do
		local ja = res.job_abilities[id]
		if ja and ja.en then
			out[#out + 1] = ja.en
		end
	end
	return uc_unique_sorted(out)
end

local function uc_get_ability_signature()
	local p = windower.ffxi.get_player()
	local info = windower.ffxi.get_info()
	if not p then
		return ''
	end
	local main_job = p.main_job or ''
	local sub_job = p.sub_job or ''
	local level_sync = info and info.level_sync and tostring(info.level_sync) or ''
	return table.concat({ main_job, sub_job, level_sync }, '|')
end

local function uc_get_cached_ability_options()
	local sig = uc_get_ability_signature()
	if sig ~= last_ability_signature then
		last_ability_signature = sig
		cached_ability_options = uc_join_pipe(uc_get_job_ability_names())
	end
	return cached_ability_options
end

local function uc_get_main_weapon_skill_id()
	local eq = windower.ffxi.get_items('equipment')
	if not eq or not eq.main_bag or not eq.main then
		return nil
	end
	local item = windower.ffxi.get_items(eq.main_bag, eq.main)
	if not item or not item.id then
		return nil
	end
	local it = res.items[item.id]
	if not it then
		return nil
	end
	return it.skill
end

local function uc_get_weaponskill_names()
	local out = {}
	local main_skill_id = uc_get_main_weapon_skill_id()
	local ab = windower.ffxi.get_abilities()
	local ws_ids = ab and ab.weapon_skills or {}
	for _, id in ipairs(ws_ids) do
		local ws = res.weapon_skills[id]
		if ws and ws.en then
			if (not main_skill_id) or ws.skill == main_skill_id then
				out[#out + 1] = ws.en
			end
		end
	end
	return uc_unique_sorted(out)
end

local function uc_get_party_name_maps()
	local names = {}
	local name_to_id = {}
	local id_to_name = {}
	local p = windower.ffxi.get_player()
	local self_id = p and p.id or 0
	local party = windower.ffxi.get_party()
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, key in ipairs(keys) do
		local entry = party and party[key]
		if entry and entry.mob and entry.mob.id and entry.mob.id ~= 0 and entry.mob.id ~= self_id then
			local name = entry.mob.name
			if name and name ~= '' and not name_to_id[name] then
				name_to_id[name] = entry.mob.id
				id_to_name[entry.mob.id] = name
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return names, name_to_id, id_to_name
end

local function process_line(line)
	local ok, msg = pcall(json.parse, line)
	if not ok or type(msg) ~= 'table' then
		return
	end
	-- WinForms → hub sends mirror_forward; if anything forwards the full envelope to the game,
	-- all fields (including index) sit under msg.msg.
	if msg.op == 'mirror_forward' and type(msg.msg) == 'table' then
		msg = msg.msg
	elseif msg.op == 'mirror_forward' and type(msg.msg) == 'string' then
		local ok2, inner = pcall(json.parse, msg.msg)
		if ok2 and type(inner) == 'table' then
			msg = inner
		end
	end
	local op = msg.op
	local function maybe_start_active_engine()
		if type(_G.UC_StartUnifiedEngine) == 'function' then
			_G.UC_StartUnifiedEngine()
		end
	end
	if op == 'set' then
		apply_set(msg.path, msg.value)
	elseif op == 'set_partner' then
		local s = _G.UC_SETTINGS
		if s then
			local _, name_to_id = uc_get_party_name_maps()
			local slot = tostring(msg.slot or '')
			local name = tostring(msg.name or '')
			local id = name_to_id[name] or 0
			if slot == 'puller' then
				if name ~= '' and id == 0 then
					_G.UC_LAST_PARTNER_OP = 'PULLER_NAME_NOT_IN_PARTY:' .. name
				end
				s.puller_id = id
			else
				_G.UC_LAST_PARTNER_OP = 'PARTNER_SET_LEGACY_IGNORED:' .. slot
			end
		end
	elseif op == 'set_fight_leader' then
		local s = _G.UC_SETTINGS
		if s then
			local _, name_to_id = uc_get_party_name_maps()
			local name = tostring(msg.name or '')
			local id = name_to_id[name] or 0
			if name ~= '' and id == 0 then
				_G.UC_LAST_FIGHT_LEADER_OP = 'FIGHT_LEADER_NAME_NOT_IN_PARTY:' .. name
			else
				_G.UC_LAST_FIGHT_LEADER_OP = ''
			end
			s.fight_leader_id = id
		end
	elseif op == 'set_party_follow' then
		local s = _G.UC_SETTINGS
		if s then
			local _, name_to_id = uc_get_party_name_maps()
			local name = tostring(msg.name or '')
			local id = name_to_id[name] or 0
			if name ~= '' and id == 0 then
				_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_NAME_NOT_IN_PARTY:' .. name
			else
				_G.UC_LAST_PARTY_FOLLOW_OP = ''
			end
			s.party_follow_id = id
			if id > 0 and name ~= '' then
				s.party_follow_leader_name = name
			else
				s.party_follow_leader_name = ''
			end
		end
		last_state_send = 0
	elseif op == 'partner_add' then
		local s = _G.UC_SETTINGS
		local name = uc_trim(msg.name)
		if not s or name == '' then
			_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_NO_NAME'
		else
			local tid = uc_resolve_target_id_by_name(name)
			if not tid then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_NAME_NOT_FOUND:' .. name
			else
				local ok, why = uc_partner_list.append_id(s, tid)
				if ok and why == 'PARTNER_ALREADY' then
					_G.UC_LAST_PARTNER_OP = 'PARTNER_ALREADY:' .. name
				elseif ok then
					_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_OK:' .. name
				else
					_G.UC_LAST_PARTNER_OP = tostring(why or 'PARTNER_ADD_FAIL')
				end
			end
		end
		last_state_send = 0
	elseif op == 'partner_add_current' then
		local s = _G.UC_SETTINGS
		if not s then
			_G.UC_LAST_PARTNER_OP = 'PARTNER_NO_SETTINGS'
		else
			local tname, tid = uc_current_target_snapshot()
			if tid == 0 then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_NO_TARGET'
			else
				local ok, why = uc_partner_list.append_id(s, tid)
				if ok and why == 'PARTNER_ALREADY' then
					_G.UC_LAST_PARTNER_OP = 'PARTNER_ALREADY:' .. tname
				elseif ok then
					_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_OK:' .. tname
				else
					_G.UC_LAST_PARTNER_OP = tostring(why or 'PARTNER_ADD_FAIL')
				end
			end
		end
		last_state_send = 0
	elseif op == 'partner_remove' then
		local s = _G.UC_SETTINGS
		local tid = uc_remote_message_mob_id(msg, 'mob_id', 'id')
		if not s or not tid or tid == 0 then
			_G.UC_LAST_PARTNER_OP = 'PARTNER_REMOVE_BAD_ID'
		else
			local ok, why = uc_partner_list.remove_id(s, tid)
			if ok then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_REMOVE_OK:' .. tostring(tid)
			else
				_G.UC_LAST_PARTNER_OP = tostring(why or 'PARTNER_REMOVE_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'set_abilities' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			s.abilities = vals
			for i = 1, 6 do
				s['ability' .. tostring(i)] = vals[i] or ''
			end
		end
	elseif op == 'ignore_add' then
		local s = _G.UC_SETTINGS
		local name = uc_trim(msg.name)
		if not s or name == '' then
			_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_NO_NAME'
		else
			local tid = uc_resolve_target_id_by_name(name)
			if not tid then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_NAME_NOT_FOUND:' .. name
			else
				local ok, why = uc_ignore.append_id(s, tid)
				if ok and why == 'IGNORE_ALREADY' then
					_G.UC_LAST_IGNORE_OP = 'IGNORE_ALREADY:' .. name
				elseif ok then
					_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_OK:' .. name
				else
					_G.UC_LAST_IGNORE_OP = tostring(why or 'IGNORE_ADD_FAIL')
				end
			end
		end
		last_state_send = 0
	elseif op == 'ignore_add_current' then
		local s = _G.UC_SETTINGS
		if not s then
			_G.UC_LAST_IGNORE_OP = 'IGNORE_NO_SETTINGS'
		else
			local tname, tid = uc_current_target_snapshot()
			if tid == 0 then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_NO_TARGET'
			else
				local ok, why = uc_ignore.append_id(s, tid)
				if ok and why == 'IGNORE_ALREADY' then
					_G.UC_LAST_IGNORE_OP = 'IGNORE_ALREADY:' .. tname
				elseif ok then
					_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_OK:' .. tname
				else
					_G.UC_LAST_IGNORE_OP = tostring(why or 'IGNORE_ADD_FAIL')
				end
			end
		end
		last_state_send = 0
	elseif op == 'ignore_remove' then
		local s = _G.UC_SETTINGS
		local tid = uc_remote_message_mob_id(msg, 'mob_id', 'id')
		if not s or not tid or tid == 0 then
			_G.UC_LAST_IGNORE_OP = 'IGNORE_REMOVE_BAD_ID'
		else
			local ok, why = uc_ignore.remove_id(s, tid)
			if ok then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_REMOVE_OK:' .. tostring(tid)
			else
				_G.UC_LAST_IGNORE_OP = tostring(why or 'IGNORE_REMOVE_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'target_ignore_add' then
		local s = _G.UC_SETTINGS
		local name = uc_trim(msg.name)
		if not s or name == '' then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_NO_NAME'
		else
			local ok, why = uc_target_ignore.append_name(s, name)
			if ok and why == 'TARGET_IGNORE_ALREADY' then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ALREADY:' .. name
			elseif ok then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_OK:' .. name
			else
				_G.UC_LAST_TARGET_IGNORE_OP = tostring(why or 'TARGET_IGNORE_ADD_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'target_ignore_add_current' then
		local s = _G.UC_SETTINGS
		if not s then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_NO_SETTINGS'
		else
			local tname, tid = uc_current_target_snapshot()
			if tid == 0 then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_NO_TARGET'
			else
				local ok, why = uc_target_ignore.append_name(s, tname)
				if ok and why == 'TARGET_IGNORE_ALREADY' then
					_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ALREADY:' .. tname
				elseif ok then
					_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_OK:' .. tname
				else
					_G.UC_LAST_TARGET_IGNORE_OP = tostring(why or 'TARGET_IGNORE_ADD_FAIL')
				end
			end
		end
		last_state_send = 0
	elseif op == 'target_ignore_remove' then
		local s = _G.UC_SETTINGS
		local idx = uc_remote_list_index(msg, line)
		if not s then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_REMOVE_NO_SETTINGS'
		elseif not idx then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_REMOVE_BAD_INDEX'
		else
			local ok, why = uc_target_ignore.remove_index(s, math.floor(idx + 0.5))
			if ok then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_REMOVE_OK:' .. tostring(idx)
			else
				_G.UC_LAST_TARGET_IGNORE_OP = tostring(why or 'TARGET_IGNORE_REMOVE_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'add_priority_add' then
		local s = _G.UC_SETTINGS
		local name = uc_trim(msg.name)
		if not s or name == '' then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_NO_NAME'
		else
			local ok, why = uc_add_priority.append_name(s, name)
			if not ok then
				if why == 'ADD_PRIORITY_ALREADY' then
					_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ALREADY:' .. name
				else
					_G.UC_LAST_ADD_PRIORITY_OP = tostring(why or 'ADD_PRIORITY_ADD_FAIL')
				end
			else
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_OK:' .. name
			end
		end
		last_state_send = 0
	elseif op == 'add_priority_add_current' then
		local s = _G.UC_SETTINGS
		if not s then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_NO_SETTINGS'
		else
			local tname, tid = uc_current_target_snapshot()
			if tid == 0 then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_NO_TARGET'
			else
				local ok, why = uc_add_priority.append_name(s, tname)
				if not ok then
					if why == 'ADD_PRIORITY_ALREADY' then
						_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ALREADY:' .. tname
					else
						_G.UC_LAST_ADD_PRIORITY_OP = tostring(why or 'ADD_PRIORITY_ADD_FAIL')
					end
				else
					_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_OK:' .. tname
				end
			end
		end
		last_state_send = 0
	elseif op == 'add_priority_remove' then
		local s = _G.UC_SETTINGS
		local idx = uc_remote_list_index(msg, line)
		if not s then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_REMOVE_NO_SETTINGS'
		elseif not idx then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_REMOVE_BAD_INDEX'
		else
			local ok, why = uc_add_priority.remove_index(s, math.floor(idx + 0.5))
			if ok then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_REMOVE_OK:' .. tostring(idx)
			else
				_G.UC_LAST_ADD_PRIORITY_OP = tostring(why or 'ADD_PRIORITY_REMOVE_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'add_priority_move' then
		local s = _G.UC_SETTINGS
		local idx = uc_remote_list_index(msg, line)
		local dir = tostring(uc_trim(tostring(msg.direction or msg.Direction or msg.dir or msg.Dir or ''))):lower()
		local delta = (dir == 'up' or dir == '-1') and -1 or ((dir == 'down' or dir == '1') and 1 or nil)
		if not s or not idx or idx < 1 or not delta then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_MOVE_BAD_ARGS'
		else
			local ok, why = uc_add_priority.move_index(s, math.floor(idx + 0.5), delta)
			if ok then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_MOVE_OK:' .. tostring(idx) .. ':' .. dir
			else
				_G.UC_LAST_ADD_PRIORITY_OP = tostring(why or 'ADD_PRIORITY_MOVE_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'toggle' and msg.key == 'Start_Engine' then
		local was_running = Start_Engine
		Start_Engine = not Start_Engine
		if (not was_running) and Start_Engine then
			maybe_start_active_engine()
		end
	elseif op == 'start_engine' then
		local was_running = Start_Engine
		Start_Engine = true
		if not was_running then
			maybe_start_active_engine()
		end
	elseif op == 'stop_engine' then
		Start_Engine = false
	elseif op == 'save' then
		if type(_G.UC_SaveActiveProfile) == 'function' then
			_G.UC_SaveActiveProfile()
		end
	elseif op == 'reload' then
		if type(_G.UC_ReloadActiveProfile) == 'function' then
			_G.UC_ReloadActiveProfile()
		end
	elseif op == 'request_state' then
		last_state_send = 0
	end
end

function uc_remote_tick()
	try_connect()
	if not sock then
		return
	end
	local data, err, part = sock:receive(4096)
	if data then
		recv_buf = recv_buf .. data
	elseif part and part ~= '' then
		recv_buf = recv_buf .. part
	elseif err == 'closed' then
		close_sock()
		return
	end
	while true do
		local nl = recv_buf:find('\n', 1, true)
		if not nl then
			break
		end
		local line = recv_buf:sub(1, nl - 1)
		recv_buf = recv_buf:sub(nl + 1)
		if line ~= '' then
			process_line(line)
		end
	end
	local now = os.clock()
	if now - last_state_send < 1.5 then
		return
	end
	last_state_send = now
	local p = windower.ffxi.get_player()
	if not p then
		return
	end
	local s = _G.UC_SETTINGS
	if not s then
		return
	end
	pcall(function()
		uc_ws_memory.sync_settings(s)
	end)
	pcall(function()
		uc_partner_list.migrate_from_legacy(s)
		uc_partner_list.sync_legacy_partner_fields(s)
	end)
	local selected_abilities = {}
	if type(s.abilities) == 'table' then
		for _, a in ipairs(s.abilities) do
			if a and a ~= '' then
				selected_abilities[#selected_abilities + 1] = a
			end
		end
	else
		for i = 1, 6 do
			local a = s['ability' .. tostring(i)]
			if a and a ~= '' then
				selected_abilities[#selected_abilities + 1] = a
			end
		end
	end
	local party_names, _, id_to_name = uc_get_party_name_maps()
	local function uc_name_by_id(id)
		local nid = tonumber(id) or 0
		if nid == 0 then
			return nil
		end
		if type(GetNameById) == 'function' then
			local ok, res = pcall(GetNameById, nid)
			if ok and type(res) == 'string' and res ~= '' then
				return res
			end
		end
		local pn = id_to_name[nid]
		if type(pn) == 'string' and pn ~= '' then
			return pn
		end
		local okm, mob = pcall(function()
			return windower.ffxi.get_mob_by_id(nid)
		end)
		if okm and mob and type(mob.name) == 'string' and mob.name ~= '' then
			return mob.name
		end
		return nil
	end
	local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	local zone_suspend_active = type(zu) == 'number' and os.clock() < zu
	local st = {
		op = 'state',
		session = session_id,
		char = p.name,
		job = p.main_job,
		sub_job = p.sub_job,
		level_sync = windower.ffxi.get_info() and windower.ffxi.get_info().level_sync or '',
		engine = _G.UC_ENGINE,
		Start_Engine = Start_Engine,
		zone_suspend_active = zone_suspend_active,
		ws1 = s.ws1,
		weaponskill = s.weaponskill,
		show_ingame_ui = (s.show_ingame_ui ~= false),
		defensive_enabled = s.defensive_enabled,
		defensive_provider = s.defensive_provider,
		defensive_cure_enabled = s.defensive_cure_enabled,
		defensive_na_enabled = s.defensive_na_enabled,
		defensive_buff_enabled = s.defensive_buff_enabled,
		defensive_critical_hpp = s.defensive_critical_hpp,
		defensive_medium_hpp = s.defensive_medium_hpp,
		defensive_overwrite_enabled = s.defensive_overwrite_enabled,
		defensive_overwrite_interval = s.defensive_overwrite_interval,
		defensive_buff_self_only = s.defensive_buff_self_only,
		defensive_buffs = s.defensive_buffs,
		block_reason = _G.UC_LAST_BLOCK_REASON or '',
		ws_diag = _G.UC_WS_LAST_DIAG or '',
		scheduler_action = _G.UC_LAST_SCHED_ACTION or '',
		scheduler_provider = _G.UC_SCHED_PROVIDER or '',
		scheduler_tick_seq = _G.UC_SCHED_TICK_SEQ or 0,
		scheduler_tick = _G.UC_SCHED_P1_TICK or 0,
		scheduler_selected_proposal = _G.UC_SCHED_P1_SELECTED_PROPOSAL or '',
		scheduler_selected_provider = _G.UC_SCHED_P1_SELECTED_PROVIDER or '',
		scheduler_selected_family = _G.UC_SCHED_P1_SELECTED_FAMILY or '',
		scheduler_plan_prelude = _G.UC_SCHED_P1_PLAN_PRELUDE or '',
		scheduler_pending_state = _G.UC_SCHED_P1_PENDING_STATE or '',
		scheduler_lock_summary = _G.UC_SCHED_P1_LOCK_SUMMARY or '',
		scheduler_reject_top = _G.UC_SCHED_P1_REJECT_TOP or '',
		scheduler_noop_reason = _G.UC_SCHED_P1_NOOP_REASON or '',
		scheduler_top3 = _G.UC_SCHED_P1_TOP3 or '',
		scheduler_top3_verbose = _G.UC_SCHED_P1_TOP3_VERBOSE or '',
		autotarget = s.autotarget,
		ability_active = s.ability_active,
		weaponskill_active = s.weaponskill_active,
		aftermath_enabled = s.aftermath_enabled,
		aftermath_ws = s.aftermath_ws,
		spam = s.spam,
		closer = s.closer,
		manual = s.manual,
		prime = s.prime,
		static = s.static,
		spacing = s.spacing,
		spacing_band_min = tonumber(s.spacing_band_min) or -0.9,
		spacing_band_max = tonumber(s.spacing_band_max) or 0.4,
		spacing_use_prediction = (s.spacing_use_prediction ~= false),
		spacing_lookahead_s = tonumber(s.spacing_lookahead_s) or 0.25,
		spacing_anchor_invalid_ticks = tonumber(s.spacing_anchor_invalid_ticks) or 5,
		spacing_emergency_margin = tonumber(s.spacing_emergency_margin) or 0.10,
		spacing_slot_switch_penalty = tonumber(s.spacing_slot_switch_penalty) or 0.75,
		spacing_slot_switch_margin = tonumber(s.spacing_slot_switch_margin) or 0.35,
		spacing_slot_arrival_tolerance = tonumber(s.spacing_slot_arrival_tolerance) or 0.20,
		spacing_max_agents = tonumber(s.spacing_max_agents) or 6,
		face = s.face,
		partner = s.partner,
		partner2 = s.partner2,
		puller = s.puller,
		fight_leader = s.fight_leader,
		party_follow = s.party_follow,
		party_follow_min = tonumber(s.party_follow_min) or 0.5,
		party_follow_max = tonumber(s.party_follow_max) or 50,
		fight_follow_min = tonumber(s.fight_follow_min) or 3.0,
		fight_follow_hold_s = tonumber(s.fight_follow_hold_s) or 8.0,
		party_follow_leader_name = tostring(s.party_follow_leader_name or ''),
		add_control = s.add_control,
		puller_distance_only = (s.puller_distance_only == true),
		sub = s.sub,
		sub2 = s.sub2,
		move = s.move,
		debug = s.debug,
		solo = s.solo,
		aeonic = s.aeonic,
		color = s.color,
		tank = s.tank,
		sleep = s.sleep,
		command = s.command,
		hunter = s.hunter,
		ability1 = s.ability1,
		ability2 = s.ability2,
		ability3 = s.ability3,
		ability4 = s.ability4,
		ability5 = s.ability5,
		ability6 = s.ability6,
		abilities_selected = uc_join_pipe(selected_abilities),
		ability_options = uc_get_cached_ability_options(),
		weaponskill_options = uc_join_pipe(uc_get_weaponskill_names()),
		ignore_entries = uc_ignore.encode_for_ui(s, uc_name_by_id),
		ignore_last_op = _G.UC_LAST_IGNORE_OP or '',
		target_ignore_entries = uc_target_ignore.encode_for_ui(s),
		target_ignore_last_op = _G.UC_LAST_TARGET_IGNORE_OP or '',
		add_priority_entries = uc_add_priority.encode_for_ui(s),
		add_priority_last_op = _G.UC_LAST_ADD_PRIORITY_OP or '',
		partner_entries = uc_partner_list.encode_for_ui(s, uc_name_by_id),
		partner_last_op = _G.UC_LAST_PARTNER_OP or '',
	}
	local tnm, tid = uc_current_target_snapshot()
	st.ignore_target_name = tnm
	st.ignore_target_id = tid
	st.partner_options = uc_join_pipe(party_names)
	st.puller_selected = id_to_name[s.puller_id] or ''
	st.fight_leader_selected = id_to_name[s.fight_leader_id] or ''
	st.fight_leader_last_op = _G.UC_LAST_FIGHT_LEADER_OP or ''
	st.party_follow_selected = id_to_name[s.party_follow_id] or ''
	st.party_follow_last_op = _G.UC_LAST_PARTY_FOLLOW_OP or ''
	if not safe_send_line(json_encode_simple(st)) then
		return
	end
end

function uc_remote_unload()
	close_sock()
end
