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
local uc_path_hunter = require('uc_path_hunter')
local uc_config_runtime = require('uc_config_runtime')

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
local last_cfg_version = 0
local session_id = nil
local cached_ability_options = ''
local last_ability_signature = ''
local cached_pull_ja_options = ''
local cached_pull_spell_options = ''
local last_pull_option_signature = ''
local uc_pull_action_name_valid

local function build_session_id()
	local p = windower.ffxi.get_player()
	local char = (p and p.name) or 'unknown'
	local pid = (p and p.id) or 0
	local now_ms = math.floor((socket.gettime and socket.gettime() or uc_now_s()) * 1000)
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
	local now = uc_now_s()
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
		sub_job = p and p.sub_job or '',
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
	-- Keep numeric selector keys as numeric strings; generic bool coercion
	-- would turn "1" into true and break tonumber parsing later.
	if type(value) == 'string' and key ~= 'cor_crooked_roll_slot' then
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
	if key == 'spacing_model_size_floor' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 3 then
			n = 3
		end
		s.spacing_model_size_floor = n
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
	if key == 'spacing_repel_hold_ticks' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		n = math.floor(n + 0.5)
		if n < 1 then
			n = 1
		elseif n > 9 then
			n = 9
		end
		s.spacing_repel_hold_ticks = n
		last_state_send = 0
		return
	end
	if key == 'spacing_overlap_deadband' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0.05 then
			n = 0.05
		elseif n > 1 then
			n = 1
		end
		s.spacing_overlap_deadband = n
		last_state_send = 0
		return
	end
	if key == 'spacing_repel_weight' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0.05 then
			n = 0.05
		elseif n > 1.5 then
			n = 1.5
		end
		s.spacing_repel_weight = n
		last_state_send = 0
		return
	end
	if key == 'spacing_band_deadband' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0.05 then
			n = 0.05
		elseif n > 1 then
			n = 1
		end
		s.spacing_band_deadband = n
		last_state_send = 0
		return
	end
	if key == 'path_party_gate_yalms' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0.5 then
			n = 0.5
		elseif n > 50 then
			n = 50
		end
		s.path_party_gate_yalms = n
		last_state_send = 0
		return
	end
	if key == 'path_resume_index_window' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		n = math.floor(n + 0.5)
		if n < 1 then
			n = 1
		elseif n > 200 then
			n = 200
		end
		s.path_resume_index_window = n
		last_state_send = 0
		return
	end
	if key == 'path_hunter_max_z_delta' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 20 then
			n = 20
		end
		s.path_hunter_max_z_delta = n
		last_state_send = 0
		return
	end
	if key == 'path_hunter_max_target_range' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 1 then
			n = 1
		elseif n > 80 then
			n = 80
		end
		s.path_hunter_max_target_range = n
		last_state_send = 0
		return
	end
	if key == 'path_hunter_claim_timeout_s' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0.5 then
			n = 0.5
		elseif n > 30 then
			n = 30
		end
		s.path_hunter_claim_timeout_s = n
		last_state_send = 0
		return
	end
	if key == 'path_hunter_ignore_cooldown_s' then
		local n = tonumber(tostring(value))
		if not n then
			return
		end
		if n < 0 then
			n = 0
		elseif n > 120 then
			n = 120
		end
		s.path_hunter_ignore_cooldown_s = n
		last_state_send = 0
		return
	end
	if key == 'path_pull_action_type' then
		local v = tostring(value or ''):lower()
		if v ~= 'ja' and v ~= 'spell' then
			v = 'ja'
		end
		s.path_pull_action_type = v
		if not uc_pull_action_name_valid(v, s.path_pull_action_name) then
			s.path_pull_action_name = ''
		end
		last_state_send = 0
		return
	end
	if key == 'path_pull_action_name' then
		local v = uc_trim(value or '')
		local at = tostring(s.path_pull_action_type or 'ja')
		if uc_pull_action_name_valid(at, v) then
			s.path_pull_action_name = v
		else
			s.path_pull_action_name = ''
		end
		last_state_send = 0
		return
	end
	if key == 'cor_crooked_roll_slot' then
		local n = tonumber(tostring(value))
		if not n then
			n = 0
		end
		n = math.floor(n + 0.5)
		if n < 0 then
			n = 0
		elseif n > 2 then
			n = 2
		end
		s.cor_crooked_roll_slot = n
		last_state_send = 0
		return
	end
	if key == 'def_heal_min_missing_hp' then
		if rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
			local p = windower.ffxi.get_player() or {}
			pcall(_G.UC_LOG_DIAG, 'def_sched', ('DEF_CFG_RECV key=def_heal_min_missing_hp raw=%s type=%s char=%s job=%s'):format(
				tostring(value),
				type(value),
				tostring(p.name or '?'),
				tostring(p.main_job or '?')
			))
		end
		local n = tonumber(tostring(value))
		if not n then
			if rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
				pcall(_G.UC_LOG_DIAG, 'def_sched', 'DEF_CFG_REJECT key=def_heal_min_missing_hp reason=bad_number')
			end
			return
		end
		n = math.floor(n + 0.5)
		if n < 0 then
			n = 0
		elseif n > 5000 then
			n = 5000
		end
		if tonumber(s.def_heal_min_missing_hp) == n then
			return
		end
		s.def_heal_min_missing_hp = n
		if rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
			pcall(_G.UC_LOG_DIAG, 'def_sched', ('DEF_CFG_APPLY key=def_heal_min_missing_hp value=%d'):format(n))
		end
		last_state_send = 0
		return
	end
	if key == 'def_remove_enemy_buffs' then
		if rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
			pcall(_G.UC_LOG_DIAG, 'def_sched', ('DEF_CFG_RECV key=def_remove_enemy_buffs raw=%s type=%s'):format(
				tostring(value),
				type(value)
			))
		end
		local b = value
		if type(b) == 'string' then
			local v = b:lower()
			if v == 'true' or v == 'on' or v == '1' or v == 'yes' then
				b = true
			elseif v == 'false' or v == 'off' or v == '0' or v == 'no' then
				b = false
			else
				b = nil
			end
		elseif type(b) == 'number' then
			b = (b ~= 0)
		end
		if type(b) ~= 'boolean' then
			if rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
				pcall(_G.UC_LOG_DIAG, 'def_sched',
					'DEF_CFG_REJECT key=def_remove_enemy_buffs reason=bad_bool')
			end
			return
		end
		if s.def_remove_enemy_buffs == b then
			return
		end
		s.def_remove_enemy_buffs = b
		if rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
			pcall(_G.UC_LOG_DIAG, 'def_sched', ('DEF_CFG_APPLY key=def_remove_enemy_buffs value=%s'):format(
				tostring(b)
			))
		end
		last_state_send = 0
		return
	end
	if t[key] == value then
		return
	end
	t[key] = value
	if key == 'path_recording' or key == 'path_follow_enabled' then
		last_state_send = 0
	end
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

local function uc_targets_include_enemy(targets)
	if type(targets) == 'string' then
		return targets:find('Enemy', 1, true) ~= nil
	end
	if type(targets) ~= 'table' then
		return false
	end
	if targets.Enemy == true or targets.enemy == true then
		return true
	end
	for k, v in pairs(targets) do
		if v == true and (k == 'Enemy' or k == 'enemy') then
			return true
		end
		if type(v) == 'string' and (v == 'Enemy' or v == 'enemy') then
			return true
		end
	end
	return false
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

local function uc_get_enemy_job_ability_names()
	local out = {}
	local ab = windower.ffxi.get_abilities()
	local ids = ab and ab.job_abilities or {}
	for _, id in ipairs(ids) do
		local ja = res.job_abilities[id]
		local targets = ja and ja.targets or nil
		if ja and ja.en and uc_targets_include_enemy(targets) then
			out[#out + 1] = ja.en
		end
	end
	return uc_unique_sorted(out)
end

local function uc_get_roll_ability_names()
	local out = {}
	local ab = windower.ffxi.get_abilities()
	local ids = ab and ab.job_abilities or {}
	for _, id in ipairs(ids) do
		local ja = res.job_abilities[id]
		if ja and ja.en and tostring(ja.en):find('Roll', 1, true) then
			out[#out + 1] = ja.en
		end
	end
	return uc_unique_sorted(out)
end

local function uc_get_enemy_spell_names()
	local function spell_known_flag(v)
		return v == true or v == 1 or v == 'true'
	end
	local function job_id_by_short(short_name)
		local j = res.jobs:with('english_short', tostring(short_name or ''))
		return tonumber(j and j.id) or 0
	end
	local function spell_usable_by_current_job(sp)
		if type(sp) ~= 'table' then
			return false
		end
		local p = windower.ffxi.get_player() or {}
		local main_id = tonumber(p.main_job_id) or job_id_by_short(p.main_job)
		local sub_id = tonumber(p.sub_job_id) or job_id_by_short(p.sub_job)
		local main_lvl = tonumber(p.main_job_level) or tonumber(p.main_job_lv) or 99
		local sub_lvl = tonumber(p.sub_job_level) or tonumber(p.sub_job_lv) or 49
		local jobs = sp.jobs or sp.levels
		if type(jobs) ~= 'table' then
			-- If resource does not expose per-job requirements, do not over-filter.
			return true
		end
		local req_main = tonumber(jobs[main_id] or jobs[tostring(main_id)])
		if req_main and req_main > 0 and main_lvl >= req_main then
			return true
		end
		local req_sub = tonumber(jobs[sub_id] or jobs[tostring(sub_id)])
		if req_sub and req_sub > 0 and sub_lvl >= req_sub then
			return true
		end
		return false
	end
	local out = {}
	local known = windower.ffxi.get_spells() or {}
	for id, has in pairs(known) do
		if spell_known_flag(has) then
			local sid = tonumber(id) or 0
			local sp = sid > 0 and res.spells[sid] or nil
			local targets = sp and sp.targets or nil
			if sp and sp.en and uc_targets_include_enemy(targets) and spell_usable_by_current_job(sp) then
				out[#out + 1] = sp.en
			end
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

local function uc_get_cached_pull_action_options()
	local sig = uc_get_ability_signature()
	if sig ~= last_pull_option_signature then
		last_pull_option_signature = sig
		cached_pull_ja_options = uc_join_pipe(uc_get_enemy_job_ability_names())
		cached_pull_spell_options = uc_join_pipe(uc_get_enemy_spell_names())
	end
	return cached_pull_ja_options, cached_pull_spell_options
end

uc_pull_action_name_valid = function(action_type, action_name)
	local at = tostring(action_type or 'ja'):lower()
	if at ~= 'spell' then
		at = 'ja'
	end
	local nm = uc_trim(action_name or '')
	if nm == '' then
		return true
	end
	local ja_opts, spell_opts = uc_get_cached_pull_action_options()
	local options = (at == 'spell') and uc_split_pipe(spell_opts) or uc_split_pipe(ja_opts)
	for _, v in ipairs(options) do
		if v == nm then
			return true
		end
	end
	return false
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

local function uc_get_ranged_weapon_skill_id()
	local eq = windower.ffxi.get_items('equipment')
	if not eq or not eq.range_bag or not eq.range then
		return nil
	end
	local item = windower.ffxi.get_items(eq.range_bag, eq.range)
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
	local allowed_skills = {}
	local main_skill_id = uc_get_main_weapon_skill_id()
	local ranged_skill_id = uc_get_ranged_weapon_skill_id()
	if main_skill_id then
		allowed_skills[main_skill_id] = true
	end
	if ranged_skill_id then
		allowed_skills[ranged_skill_id] = true
	end
	local has_allowed = next(allowed_skills) ~= nil
	local ab = windower.ffxi.get_abilities()
	local ws_ids = ab and ab.weapon_skills or {}
	for _, id in ipairs(ws_ids) do
		local ws = res.weapon_skills[id]
		if ws and ws.en then
			if (not has_allowed) or allowed_skills[ws.skill] then
				out[#out + 1] = ws.en
			end
		end
	end
	return uc_unique_sorted(out)
end

local function uc_get_party_name_maps(include_self)
	local names = {}
	local name_to_id = {}
	local id_to_name = {}
	local p = windower.ffxi.get_player()
	local self_id = p and p.id or 0
	local party = windower.ffxi.get_party()
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, key in ipairs(keys) do
		local entry = party and party[key]
		if entry and entry.mob and entry.mob.id and entry.mob.id ~= 0 and (include_self or entry.mob.id ~= self_id) then
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
	local function uc_msg_get(tbl, key)
		if type(tbl) ~= 'table' then
			return nil
		end
		local v = rawget(tbl, key)
		if v ~= nil then
			return v
		end
		v = tbl[key]
		if v ~= nil then
			return v
		end
		if type(line) ~= 'string' or key == nil then
			return nil
		end
		local k = tostring(key)
		local q = line:match('"' .. k .. '"%s*:%s*"(.-)"')
		if q ~= nil then
			q = q:gsub('\\"', '"')
			q = q:gsub('\\\\', '\\')
			q = q:gsub('\\u0027', "'")
			q = q:gsub('\\x27', "'")
			return q
		end
		local n = line:match('"' .. k .. '"%s*:%s*(-?%d+)')
		if n ~= nil then
			return tonumber(n)
		end
		local b = line:match('"' .. k .. '"%s*:%s*(true|false)')
		if b ~= nil then
			return b == 'true'
		end
		return nil
	end

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
	local op = tostring(uc_msg_get(msg, 'op') or '')
	local function maybe_start_active_engine()
		if type(_G.UC_StartUnifiedEngine) == 'function' then
			_G.UC_StartUnifiedEngine()
		end
	end
	local function send_options_snapshot()
		local p = windower.ffxi.get_player()
		if not p then
			return
		end
		local st = {
			op = 'options',
			session = session_id,
			char = p.name,
			job = p.main_job,
			sub_job = p.sub_job,
			engine = _G.UC_ENGINE,
			profile_contract_status = _G.UC_PROFILE_CONTRACT_STATUS,
			config_contract_status = uc_config_runtime.config_contract_status(_G.UC_SETTINGS),
			ability_options = uc_get_cached_ability_options(),
			weaponskill_options = uc_join_pipe(uc_get_weaponskill_names()),
			path_pull_ja_options = select(1, uc_get_cached_pull_action_options()),
			path_pull_spell_options = select(2, uc_get_cached_pull_action_options()),
			cor_roll_options = uc_join_pipe(uc_get_roll_ability_names()),
			party_options = uc_join_pipe(select(1, uc_get_party_name_maps(false))),
		}
		safe_send_line(json_encode_simple(st))
	end
	if op == 'set' then
		local cfg_ver = tonumber(uc_msg_get(msg, 'cfg_version')) or 0
		if cfg_ver > 0 then
			if cfg_ver <= last_cfg_version then
				return
			end
			last_cfg_version = cfg_ver
		end
		local set_path = uc_msg_get(msg, 'path')
		local set_value = uc_msg_get(msg, 'value')
		local set_trace = uc_msg_get(msg, 'trace_id')
		if set_path == 'def_remove_enemy_buffs' and rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
			local raw_line = tostring(line or '')
			pcall(_G.UC_LOG_DIAG, 'def_sched', ('DEF_CFG_SET_OP path=%s raw=%s type=%s trace=%s line=%s'):format(
				tostring(set_path),
				tostring(set_value),
				type(set_value),
				tostring(set_trace or ''),
				raw_line
			))
		end
		-- Fallback parse for malformed decoder tables where key lookup loses numeric fields.
		if set_value == nil and type(line) == 'string' and set_path == 'def_heal_min_missing_hp' then
			local parsed_num = tonumber(line:match('"value"%s*:%s*(-?%d+)'))
			if parsed_num ~= nil then
				set_value = parsed_num
			end
		end
		-- Parse boolean directly from raw json when table decode loses "value".
		if set_value == nil and type(line) == 'string' and set_path == 'def_remove_enemy_buffs' then
			local parsed_bool = line:match('"value"%s*:%s*(true|false)')
			if parsed_bool ~= nil then
				set_value = (parsed_bool == 'true')
			end
		end
		if set_path == 'def_heal_min_missing_hp' and rawget(_G, 'UC_LOG_DEF_SCHED') == true and type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
			local raw_val = tostring(set_value)
			local raw_type = type(set_value)
			local raw_line = tostring(line or '')
			pcall(_G.UC_LOG_DIAG, 'def_sched', ('DEF_CFG_SET_OP path=%s raw=%s type=%s line=%s'):format(
				tostring(set_path),
				raw_val,
				raw_type,
				raw_line
			))
		end
		apply_set(set_path, set_value)
	elseif op == 'set_partner' then
		local s = _G.UC_SETTINGS
		if s then
			local slot = tostring(msg.slot or '')
			local name = tostring(msg.name or '')
			if slot == 'puller' then
				local _, name_to_id = uc_get_party_name_maps(true)
				local id = name_to_id[name] or 0
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
	elseif op == 'tank_enmity_replace_actions' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			local out = {}
			local seen = {}
			for _, entry in ipairs(vals) do
				local n = uc_trim(entry)
				local k = n:lower()
				if n ~= '' and not seen[k] then
					seen[k] = true
					out[#out + 1] = n
				end
			end
			s.tank_enmity_actions = out
		end
		last_state_send = 0
	elseif op == 'ignore_replace_names' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			s.ignore = {}
			for _, name in ipairs(vals) do
				local tid = uc_resolve_target_id_by_name(name)
				if tid and tid ~= 0 then
					uc_ignore.append_id(s, tid)
				end
			end
		end
		last_state_send = 0
	elseif op == 'partner_replace_names' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(uc_msg_get(msg, 'value'))
			s.partner_ids = {}
			for _, name in ipairs(vals) do
				local tid = uc_resolve_target_id_by_name(name)
				if tid and tid ~= 0 then
					uc_partner_list.append_id(s, tid)
				end
			end
			uc_partner_list.sync_legacy_partner_fields(s)
		end
		last_state_send = 0
	elseif op == 'target_ignore_replace_names' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			local out = {}
			local seen = {}
			for _, name in ipairs(vals) do
				local n = uc_trim(name)
				local k = n:lower()
				if n ~= '' and not seen[k] then
					seen[k] = true
					out[#out + 1] = n
				end
			end
			s.target_ignore_names = out
		end
		last_state_send = 0
	elseif op == 'cor_roll_range_replace_names' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			local out = {}
			local seen = {}
			local keep_names = {}
			local seen_name = {}
			local _, name_to_id = uc_get_party_name_maps(false)
			for _, name in ipairs(vals) do
				local n = uc_trim(name)
				local pid = name_to_id[n] or 0
				if n ~= '' and pid ~= 0 and not seen[pid] then
					seen[pid] = true
					out[#out + 1] = pid
					local nk = n:lower()
					if not seen_name[nk] then
						seen_name[nk] = true
						keep_names[#keep_names + 1] = n
					end
				end
			end
			s.cor_roll_range_require_ids = out
			s.cor_roll_range_selected = table.concat(keep_names, '|')
		end
		last_state_send = 0
	elseif op == 'add_priority_replace_names' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			local out = {}
			local seen = {}
			for _, name in ipairs(vals) do
				local n = uc_trim(name)
				local k = n:lower()
				if n ~= '' and not seen[k] then
					seen[k] = true
					out[#out + 1] = n
				end
			end
			s.add_priority_names = out
		end
		last_state_send = 0
	elseif op == 'sleep_replace_spells' then
		local s = _G.UC_SETTINGS
		local sleep_cfg = rawget(_G, 'UC_SleepSpell')
		if s and type(sleep_cfg) == 'table' and type(sleep_cfg.replace_names) == 'function' then
			local vals = uc_split_pipe(msg.value)
			sleep_cfg.replace_names(s, vals)
		end
		last_state_send = 0
	elseif op == 'path_hunter_replace_names' then
		local s = _G.UC_SETTINGS
		if s then
			local vals = uc_split_pipe(msg.value)
			local out = {}
			local seen = {}
			for _, name in ipairs(vals) do
				local n = uc_trim(name)
				local k = n:lower()
				if n ~= '' and not seen[k] then
					seen[k] = true
					out[#out + 1] = n
				end
			end
			s.path_hunter_targets = out
		end
		last_state_send = 0
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
	elseif op == 'sleep_add_spell' then
		local s = _G.UC_SETTINGS
		local sleep_cfg = rawget(_G, 'UC_SleepSpell')
		local name = uc_trim(msg.name)
		if s and type(sleep_cfg) == 'table' and type(sleep_cfg.append_name) == 'function' and name ~= '' then
			sleep_cfg.append_name(s, name)
		end
		last_state_send = 0
	elseif op == 'sleep_remove_spell' then
		local s = _G.UC_SETTINGS
		local sleep_cfg = rawget(_G, 'UC_SleepSpell')
		local idx = uc_remote_list_index(msg, line)
		if s and type(sleep_cfg) == 'table' and type(sleep_cfg.remove_index) == 'function' and idx then
			sleep_cfg.remove_index(s, math.floor(idx + 0.5))
		end
		last_state_send = 0
	elseif op == 'sleep_move_spell' then
		local s = _G.UC_SETTINGS
		local sleep_cfg = rawget(_G, 'UC_SleepSpell')
		local idx = uc_remote_list_index(msg, line)
		local dir = tostring(uc_trim(tostring(msg.direction or msg.Direction or msg.dir or msg.Dir or ''))):lower()
		local delta = (dir == 'up' or dir == '-1') and -1 or ((dir == 'down' or dir == '1') and 1 or nil)
		if s and type(sleep_cfg) == 'table' and type(sleep_cfg.move_index) == 'function' and idx and delta then
			sleep_cfg.move_index(s, math.floor(idx + 0.5), delta)
		end
		last_state_send = 0
	elseif op == 'path_hunter_add' then
		local s = _G.UC_SETTINGS
		local name = uc_trim(msg.name)
		if not s or name == '' then
			_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_ADD_NO_NAME'
		else
			local ok, why = uc_path_hunter.append_name(s, name)
			if ok then
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_ADD_OK:' .. name
			else
				_G.UC_LAST_PATH_HUNTER_OP = tostring(why or 'PATH_HUNTER_ADD_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'path_hunter_remove' then
		local s = _G.UC_SETTINGS
		local idx = uc_remote_list_index(msg, line)
		if not s then
			_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_REMOVE_NO_SETTINGS'
		elseif not idx then
			_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_REMOVE_BAD_INDEX'
		else
			local ok, why = uc_path_hunter.remove_index(s, math.floor(idx + 0.5))
			if ok then
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_REMOVE_OK:' .. tostring(idx)
			else
				_G.UC_LAST_PATH_HUNTER_OP = tostring(why or 'PATH_HUNTER_REMOVE_FAIL')
			end
		end
		last_state_send = 0
	elseif op == 'toggle' and msg.key == 'Start_Engine' then
		local was_running = Start_Engine
		Start_Engine = not Start_Engine
		if _G.UC_SETTINGS then
			_G.UC_SETTINGS.engine_enabled = (Start_Engine == true)
		end
		if was_running and (not Start_Engine) and type(_G.UC_ResetMovementLocksForFollow) == 'function' then
			_G.UC_ResetMovementLocksForFollow()
		end
		if (not was_running) and Start_Engine then
			maybe_start_active_engine()
		end
	elseif op == 'start_engine' then
		local was_running = Start_Engine
		Start_Engine = true
		if _G.UC_SETTINGS then
			_G.UC_SETTINGS.engine_enabled = true
		end
		if not was_running then
			maybe_start_active_engine()
		end
	elseif op == 'stop_engine' then
		Start_Engine = false
		if _G.UC_SETTINGS then
			_G.UC_SETTINGS.engine_enabled = false
		end
		if type(_G.UC_ResetMovementLocksForFollow) == 'function' then
			_G.UC_ResetMovementLocksForFollow()
		end
	elseif op == 'save' then
		if type(_G.UC_SaveActiveProfile) == 'function' then
			_G.UC_SaveActiveProfile()
		end
	elseif op == 'reload' then
		if type(_G.UC_ReloadActiveProfile) == 'function' then
			_G.UC_ReloadActiveProfile()
		end
	elseif op == 'addon_reload' then
		-- Explicit UI-initiated full addon reload. This is intentionally separate from profile reload.
		windower.send_command('lua reload unifiedcombat')
	elseif op == 'request_state' then
		last_state_send = 0
	elseif op == 'request_options' then
		send_options_snapshot()
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
	local now = uc_now_s()
	if now - last_state_send < 1.5 then
		return
	end
	last_state_send = now
	local p = windower.ffxi.get_player()
	if not p then
		return
	end
	local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	local zone_suspend_active = type(zu) == 'number' and uc_now_s() < zu
	local st = {
		op = 'state',
		session = session_id,
		char = p.name,
		job = p.main_job,
		sub_job = p.sub_job,
		engine = _G.UC_ENGINE,
		Start_Engine = Start_Engine,
		zone_suspend_active = zone_suspend_active,
		profile_contract_status = _G.UC_PROFILE_CONTRACT_STATUS,
		config_contract_status = uc_config_runtime.config_contract_status(_G.UC_SETTINGS),
	}
	if not safe_send_line(json_encode_simple(st)) then
		return
	end
end

function uc_remote_unload()
	close_sock()
end
