local function uc_now_s()
	return require('uc_time').now()
end

--[[
  Non-blocking TCP client to Python hub. NDJSON over newline.
  Expect _G.UC_SETTINGS, _G.UC_ENGINE, Start_Engine, windower.
]]

local socket = require('socket')
local uc_time = require('uc_time')
local json = require('json')
local res = require('resources')
local uc_ws_memory = require('uc_ws_memory')
local uc_config_runtime = require('uc_config_runtime')
local uc_active_config = require('uc_active_config')
local uc_camp_anchor = require('uc_camp_anchor')

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

local function json_escape_simple(value)
	local text = tostring(value)
	text = text:gsub('\\', '\\\\')
	text = text:gsub('"', '\\"')
	text = text:gsub('[%c]', function(char)
		if char == '\b' then
			return '\\b'
		elseif char == '\f' then
			return '\\f'
		elseif char == '\n' then
			return '\\n'
		elseif char == '\r' then
			return '\\r'
		elseif char == '\t' then
			return '\\t'
		end
		return string.format('\\u%04x', char:byte())
	end)
	return text
end

local function json_encode_value(value, seen)
	local value_type = type(value)
	if value_type == 'nil' then
		return 'null'
	elseif value_type == 'string' then
		return '"' .. json_escape_simple(value) .. '"'
	elseif value_type == 'boolean' then
		return value and 'true' or 'false'
	elseif value_type == 'number' then
		return tostring(value)
	elseif value_type ~= 'table' then
		error('unsupported JSON value type: ' .. value_type)
	end

	local visited = seen or {}
	if visited[value] then
		error('cycle detected while encoding bridge JSON')
	end
	visited[value] = true
	local count = 0
	local max_index = 0
	local is_array = true
	for key in pairs(value) do
		count = count + 1
		if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
			is_array = false
		elseif key > max_index then
			max_index = key
		end
	end
	if is_array and max_index == count then
		local parts = {}
		for i = 1, max_index do
			parts[#parts + 1] = json_encode_value(value[i], visited)
		end
		visited[value] = nil
		return '[' .. table.concat(parts, ',') .. ']'
	end

	local parts = {}
	for key, inner_value in pairs(value) do
		parts[#parts + 1] = '"' .. json_escape_simple(key) .. '":' .. json_encode_value(inner_value, visited)
	end
	visited[value] = nil
	return '{' .. table.concat(parts, ',') .. '}'
end

local function json_encode_simple(value)
	return json_encode_value(value)
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
	local now_ms = math.floor(uc_time.now() * 1000)
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

function uc_remote_activity_request(action, name)
	if not safe_send_line(json_encode_simple({ op = 'activity_request', action = action, name = name })) then
		windower.add_to_chat(167, 'UnifiedCombat: activity request failed; UI connection unavailable')
		return
	end
	windower.add_to_chat(207, 'UnifiedCombat: activity request sent to UI')
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
	if key == 'path_recording' or key == 'path_follow_enabled' or key == 'path_pull_attack_fallback_enabled' then
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

local function uc_apply_active_list_edit(method_name, path, ...)
	local method = uc_active_config[method_name]
	if type(method) ~= 'function' then
		return false, 'ACTIVE_CONFIG_EDITOR_UNAVAILABLE'
	end
	local ok, reason = method(path, ...)
	if ok ~= true then
		return false, tostring(reason or 'ACTIVE_CONFIG_EDIT_FAILED')
	end
	-- Phase 6: canonical edits are authoritative immediately. Do not republish
	-- durable policy into the legacy flat settings table; migrated runtime
	-- consumers read the active Profile V2 config directly. The bridge still invalidates its state
	-- snapshot so the UI observes the canonical edit promptly.
	last_state_send = 0
	return true, tostring(reason or '')
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

local function uc_get_bard_song_names()
	return require('uc_brd_song_options').collect(res, windower.ffxi.get_spells(), windower.ffxi.get_player())
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
		local jp_spent = 0
		do
			local jp = type(p.job_points) == 'table' and p.job_points or nil
			local mj = tostring(p.main_job or ''):lower()
			local row = jp and jp[mj] or nil
			jp_spent = tonumber(row and row.jp_spent) or 0
		end
		local jobs = sp.jobs or sp.levels
		if type(jobs) ~= 'table' then
			-- If resource does not expose per-job requirements, do not over-filter.
			return true
		end
		local req_main = tonumber(jobs[main_id] or jobs[tostring(main_id)])
		if req_main and req_main > 0 and (main_lvl >= req_main or jp_spent >= req_main) then
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

local function uc_get_resurrection_spell_names()
	local allowed = {
		['Arise'] = true,
		['Raise III'] = true,
		['Raise II'] = true,
		['Raise'] = true,
	}
	local function known_flag(v)
		return v == true or v == 1 or v == 'true'
	end
	local function job_id_by_short(short_name)
		local j = res.jobs:with('english_short', tostring(short_name or ''))
		return tonumber(j and j.id) or 0
	end
	local function usable(sp)
		if type(sp) ~= 'table' then return false end
		local p = windower.ffxi.get_player() or {}
		local main_id = tonumber(p.main_job_id) or job_id_by_short(p.main_job)
		local sub_id = tonumber(p.sub_job_id) or job_id_by_short(p.sub_job)
		local main_lvl = tonumber(p.main_job_level) or tonumber(p.main_job_lv) or 99
		local sub_lvl = tonumber(p.sub_job_level) or tonumber(p.sub_job_lv) or 49
		local jp_spent = 0
		local jp = type(p.job_points) == 'table' and p.job_points or nil
		local row = jp and jp[tostring(p.main_job or ''):lower()] or nil
		jp_spent = tonumber(row and row.jp_spent) or 0
		local jobs = sp.jobs or sp.levels
		if type(jobs) ~= 'table' then return true end
		local req_main = tonumber(jobs[main_id] or jobs[tostring(main_id)])
		if req_main and req_main > 0 and (main_lvl >= req_main or jp_spent >= req_main) then return true end
		local req_sub = tonumber(jobs[sub_id] or jobs[tostring(sub_id)])
		return req_sub ~= nil and req_sub > 0 and sub_lvl >= req_sub
	end
	local out = {}
	local known = windower.ffxi.get_spells() or {}
	for id, has in pairs(known) do
		if known_flag(has) then
			local sp = res.spells[tonumber(id) or 0]
			if sp and allowed[sp.en] == true and usable(sp) then
				out[#out + 1] = sp.en
			end
		end
	end
	local preferred = { 'Arise', 'Raise III', 'Raise II', 'Raise' }
	local present = {}
	for _, name in ipairs(out) do present[name] = true end
	local ordered = {}
	for _, name in ipairs(preferred) do
		if present[name] then ordered[#ordered + 1] = name end
	end
	return ordered
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
	local jp = type(p.job_points) == 'table' and p.job_points or nil
	local jp_row = jp and jp[tostring(main_job):lower()] or nil
	local jp_spent = tonumber(jp_row and jp_row.jp_spent) or 0
	return table.concat({ main_job, sub_job, level_sync, tostring(jp_spent) }, '|')
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
	if op == 'activity_result' then
		if type(msg.message) ~= 'string' or type(msg.ok) ~= 'boolean' then
			error('Invalid activity result from UI')
		end
		windower.add_to_chat(msg.ok and 207 or 167, 'UnifiedCombat: ' .. msg.message)
		return
	end
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
			resurrection_options = uc_join_pipe(uc_get_resurrection_spell_names()),
			cor_roll_options = uc_join_pipe(uc_get_roll_ability_names()),
			brd_song_options = uc_join_pipe(uc_get_bard_song_names()),
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
		local slot = tostring(msg.slot or '')
		local name = uc_trim(tostring(msg.name or ''))
		if slot == 'puller' then
			local ok, why = uc_apply_active_list_edit(
				'replace_name',
				'config.follow.partner.puller_name',
				name
			)
			if ok then
				local _, name_to_id = uc_get_party_name_maps(true)
				if name ~= '' and (name_to_id[name] or 0) == 0 then
					_G.UC_LAST_PARTNER_OP = 'PULLER_NAME_NOT_IN_PARTY:' .. name
				else
					_G.UC_LAST_PARTNER_OP = ''
				end
			else
				_G.UC_LAST_PARTNER_OP = 'PULLER_SET_FAIL:' .. tostring(why)
			end
		else
			_G.UC_LAST_PARTNER_OP = 'PARTNER_SET_LEGACY_IGNORED:' .. slot
		end
	elseif op == 'set_fight_leader' then
		local name = uc_trim(tostring(msg.name or ''))
		local ok, why = uc_apply_active_list_edit(
			'replace_name',
			'config.follow.fight.leader_name',
			name
		)
		if ok then
			local _, name_to_id = uc_get_party_name_maps()
			if name ~= '' and (name_to_id[name] or 0) == 0 then
				_G.UC_LAST_FIGHT_LEADER_OP = 'FIGHT_LEADER_NAME_NOT_IN_PARTY:' .. name
			else
				_G.UC_LAST_FIGHT_LEADER_OP = ''
			end
		else
			_G.UC_LAST_FIGHT_LEADER_OP = 'FIGHT_LEADER_SET_FAIL:' .. tostring(why)
		end
	elseif op == 'set_party_follow' then
		local name = uc_trim(tostring(msg.name or ''))
		local ok, why = uc_apply_active_list_edit(
			'replace_name',
			'config.follow.party.leader_name',
			name
		)
		if ok then
			local _, name_to_id = uc_get_party_name_maps()
			if name ~= '' and (name_to_id[name] or 0) == 0 then
				_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_NAME_NOT_IN_PARTY:' .. name
			else
				_G.UC_LAST_PARTY_FOLLOW_OP = ''
			end
		else
			_G.UC_LAST_PARTY_FOLLOW_OP = 'PARTY_FOLLOW_SET_FAIL:' .. tostring(why)
		end
	elseif op == 'partner_add' then
		local name = uc_trim(tostring(msg.name or ''))
		if name == '' then
			_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_NO_NAME'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.follow.partner.names',
				name
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ALREADY:' .. name
			elseif ok then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_OK:' .. name
			else
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'partner_add_current' then
		local tname, tid = uc_current_target_snapshot()
		if tid == 0 or uc_trim(tostring(tname or '')) == '' then
			_G.UC_LAST_PARTNER_OP = 'PARTNER_NO_TARGET'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.follow.partner.names',
				tname
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ALREADY:' .. tname
			elseif ok then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_OK:' .. tname
			else
				_G.UC_LAST_PARTNER_OP = 'PARTNER_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'partner_remove' then
		local name = uc_trim(tostring(msg.name or ''))
		local tid = uc_remote_message_mob_id(msg, 'mob_id', 'id')
		if name == '' and tid and tid ~= 0 then
			local _, _, id_to_name = uc_get_party_name_maps(true)
			name = uc_trim(tostring(id_to_name[tid] or ''))
		end
		if name == '' then
			_G.UC_LAST_PARTNER_OP = 'PARTNER_REMOVE_BAD_ID'
		else
			local ok, why = uc_apply_active_list_edit(
				'remove_string_list_value',
				'config.follow.partner.names',
				name
			)
			if ok then
				_G.UC_LAST_PARTNER_OP = 'PARTNER_REMOVE_OK:' .. name
			else
				_G.UC_LAST_PARTNER_OP = 'PARTNER_REMOVE_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'set_abilities' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.abilities.configured',
			uc_split_pipe(msg.value)
		)
	elseif op == 'tank_enmity_replace_actions' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.tank.enmity.actions',
			uc_split_pipe(msg.value)
		)
	elseif op == 'ignore_replace_names' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.combat.weaponskill.wait_ignore_names',
			uc_split_pipe(msg.value)
		)
	elseif op == 'partner_replace_names' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.follow.partner.names',
			uc_split_pipe(uc_msg_get(msg, 'value'))
		)
	elseif op == 'no_skillchain_target_replace_names' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.combat.weaponskill.no_skillchain_targets',
			uc_split_pipe(msg.value)
		)
	elseif op == 'target_ignore_replace_names' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.targeting.target_ignore_names',
			uc_split_pipe(msg.value)
		)
	elseif op == 'cor_roll_range_replace_names' then
		uc_apply_active_list_edit(
			'replace_pipe_string_list',
			'config.maintenance.cor.range_selected',
			uc_split_pipe(msg.value)
		)
	elseif op == 'add_priority_replace_names' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.targeting.targets',
			uc_split_pipe(msg.value)
		)
	elseif op == 'sleep_replace_spells' then
		local sleep_cfg = rawget(_G, 'UC_SleepSpell')
		if type(sleep_cfg) == 'table' and type(sleep_cfg.validate_names) == 'function' then
			local validated = sleep_cfg.validate_names(uc_split_pipe(msg.value))
			if type(validated) == 'table' then
				uc_apply_active_list_edit(
					'replace_string_list',
					'config.sleep.order',
					validated
				)
			end
		end
	elseif op == 'path_hunter_replace_names' then
		uc_apply_active_list_edit(
			'replace_string_list',
			'config.movement.path.hunter_targets',
			uc_split_pipe(msg.value)
		)
	elseif op == 'ignore_add' then
		local name = uc_trim(msg.name)
		if name == '' then
			_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_NO_NAME'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.combat.weaponskill.wait_ignore_names',
				name
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ALREADY:' .. name
			elseif ok then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_OK:' .. name
			else
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'ignore_add_current' then
		local tname, tid = uc_current_target_snapshot()
		if tid == 0 then
			_G.UC_LAST_IGNORE_OP = 'IGNORE_NO_TARGET'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.combat.weaponskill.wait_ignore_names',
				tname
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ALREADY:' .. tname
			elseif ok then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_OK:' .. tname
			else
				_G.UC_LAST_IGNORE_OP = 'IGNORE_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'ignore_remove' then
		local tid = uc_remote_message_mob_id(msg, 'mob_id', 'id')
		if not tid or tid == 0 then
			_G.UC_LAST_IGNORE_OP = 'IGNORE_REMOVE_BAD_ID'
		else
			local _, _, id_to_name = uc_get_party_name_maps(true)
			local name = id_to_name[tid]
			if not name or name == '' then
				_G.UC_LAST_IGNORE_OP = 'IGNORE_REMOVE_ID_NOT_FOUND:' .. tostring(tid)
			else
				local ok, why = uc_apply_active_list_edit(
					'remove_string_list_value',
					'config.combat.weaponskill.wait_ignore_names',
					name
				)
				if ok then
					_G.UC_LAST_IGNORE_OP = 'IGNORE_REMOVE_OK:' .. tostring(tid)
				else
					_G.UC_LAST_IGNORE_OP = 'IGNORE_REMOVE_FAIL:' .. tostring(why)
				end
			end
		end
	elseif op == 'no_skillchain_target_add' then
		local name = uc_trim(msg.name)
		if name ~= '' then
			uc_apply_active_list_edit(
				'append_string_list',
				'config.combat.weaponskill.no_skillchain_targets',
				name
			)
		end
	elseif op == 'no_skillchain_target_add_current' then
		local tname, tid = uc_current_target_snapshot()
		if tid ~= 0 then
			uc_apply_active_list_edit(
				'append_string_list',
				'config.combat.weaponskill.no_skillchain_targets',
				tname
			)
		end
	elseif op == 'no_skillchain_target_remove' then
		local idx = uc_remote_list_index(msg, line)
		if idx then
			uc_apply_active_list_edit(
				'remove_string_list_index',
				'config.combat.weaponskill.no_skillchain_targets',
				math.floor(idx + 0.5)
			)
		end
	elseif op == 'target_ignore_add' then
		local name = uc_trim(msg.name)
		if name == '' then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_NO_NAME'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.targeting.target_ignore_names',
				name
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ALREADY:' .. name
			elseif ok then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_OK:' .. name
			else
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'target_ignore_add_current' then
		local tname, tid = uc_current_target_snapshot()
		if tid == 0 then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_NO_TARGET'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.targeting.target_ignore_names',
				tname
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ALREADY:' .. tname
			elseif ok then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_OK:' .. tname
			else
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'target_ignore_remove' then
		local idx = uc_remote_list_index(msg, line)
		if not idx then
			_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_REMOVE_BAD_INDEX'
		else
			local ok, why = uc_apply_active_list_edit(
				'remove_string_list_index',
				'config.targeting.target_ignore_names',
				math.floor(idx + 0.5)
			)
			if ok then
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_REMOVE_OK:' .. tostring(idx)
			else
				_G.UC_LAST_TARGET_IGNORE_OP = 'TARGET_IGNORE_REMOVE_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'add_priority_add' then
		local name = uc_trim(msg.name)
		if name == '' then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_NO_NAME'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.targeting.targets',
				name
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ALREADY:' .. name
			elseif ok then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_OK:' .. name
			else
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'add_priority_add_current' then
		local tname, tid = uc_current_target_snapshot()
		if tid == 0 then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_NO_TARGET'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.targeting.targets',
				tname
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ALREADY:' .. tname
			elseif ok then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_OK:' .. tname
			else
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'add_priority_remove' then
		local idx = uc_remote_list_index(msg, line)
		if not idx then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_REMOVE_BAD_INDEX'
		else
			local ok, why = uc_apply_active_list_edit(
				'remove_string_list_index',
				'config.targeting.targets',
				math.floor(idx + 0.5)
			)
			if ok then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_REMOVE_OK:' .. tostring(idx)
			else
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_REMOVE_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'add_priority_move' then
		local idx = uc_remote_list_index(msg, line)
		local dir = tostring(uc_trim(tostring(msg.direction or msg.Direction or msg.dir or msg.Dir or ''))):lower()
		local delta = (dir == 'up' or dir == '-1') and -1 or ((dir == 'down' or dir == '1') and 1 or nil)
		if not idx or idx < 1 or not delta then
			_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_MOVE_BAD_ARGS'
		else
			local ok, why = uc_apply_active_list_edit(
				'move_string_list_index',
				'config.targeting.targets',
				math.floor(idx + 0.5),
				delta
			)
			if ok then
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_MOVE_OK:' .. tostring(idx) .. ':' .. dir
			else
				_G.UC_LAST_ADD_PRIORITY_OP = 'ADD_PRIORITY_MOVE_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'sleep_add_spell' then
		local sleep_cfg = rawget(_G, 'UC_SleepSpell')
		local name = uc_trim(msg.name)
		if name ~= '' and type(sleep_cfg) == 'table' and type(sleep_cfg.validate_names) == 'function' then
			local validated = sleep_cfg.validate_names({ name })
			if type(validated) == 'table' and #validated == 1 then
				uc_apply_active_list_edit(
					'append_string_list',
					'config.sleep.order',
					validated[1]
				)
			end
		end
	elseif op == 'sleep_remove_spell' then
		local idx = uc_remote_list_index(msg, line)
		if idx then
			uc_apply_active_list_edit(
				'remove_string_list_index',
				'config.sleep.order',
				math.floor(idx + 0.5)
			)
		end
	elseif op == 'sleep_move_spell' then
		local idx = uc_remote_list_index(msg, line)
		local dir = tostring(uc_trim(tostring(msg.direction or msg.Direction or msg.dir or msg.Dir or ''))):lower()
		local delta = (dir == 'up' or dir == '-1') and -1 or ((dir == 'down' or dir == '1') and 1 or nil)
		if idx and delta then
			uc_apply_active_list_edit(
				'move_string_list_index',
				'config.sleep.order',
				math.floor(idx + 0.5),
				delta
			)
		end
	elseif op == 'path_hunter_add' then
		local name = uc_trim(msg.name)
		if name == '' then
			_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_ADD_NO_NAME'
		else
			local ok, why = uc_apply_active_list_edit(
				'append_string_list',
				'config.movement.path.hunter_targets',
				name
			)
			if ok and why == 'ALREADY' then
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_ALREADY:' .. name
			elseif ok then
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_ADD_OK:' .. name
			else
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_ADD_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'path_hunter_remove' then
		local idx = uc_remote_list_index(msg, line)
		if not idx then
			_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_REMOVE_BAD_INDEX'
		else
			local ok, why = uc_apply_active_list_edit(
				'remove_string_list_index',
				'config.movement.path.hunter_targets',
				math.floor(idx + 0.5)
			)
			if ok then
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_REMOVE_OK:' .. tostring(idx)
			else
				_G.UC_LAST_PATH_HUNTER_OP = 'PATH_HUNTER_REMOVE_FAIL:' .. tostring(why)
			end
		end
	elseif op == 'toggle' and msg.key == 'Start_Engine' then
		local was_running = Start_Engine
		Start_Engine = not Start_Engine
		if _G.UC_SETTINGS then
			_G.UC_SETTINGS.engine_enabled = (Start_Engine == true)
		end
		if was_running and (not Start_Engine) and type(_G.UC_ResetMovementLocksForFollow) == 'function' then
			_G.UC_ResetMovementLocksForFollow()
		end
		if was_running and (not Start_Engine) and type(_G.UC_StopUnifiedEngine) == 'function' then
			_G.UC_StopUnifiedEngine('engine_stop')
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
		if type(_G.UC_StopUnifiedEngine) == 'function' then
			_G.UC_StopUnifiedEngine('engine_stop')
		end
	elseif op == 'camp_set' then
		local ok, reason = uc_camp_anchor.set_current_position()
		_G.UC_LAST_CAMP_OP = tostring(reason)
		if not ok then
			windower.add_to_chat(167, 'UC camp: ' .. tostring(reason))
		end
		last_state_send = 0
	elseif op == 'camp_clear' then
		local ok, reason = uc_camp_anchor.clear_shared()
		_G.UC_LAST_CAMP_OP = tostring(reason)
		if not ok then
			windower.add_to_chat(167, 'UC camp: ' .. tostring(reason))
		end
		last_state_send = 0
	elseif op == 'profile_v2_reload' then
		local request_id = uc_trim(uc_msg_get(msg, 'request_id'))
		local response = {
			op = 'profile_v2_reload_result',
			request_id = request_id,
			ok = false,
			character = '',
			main_job = '',
			sub_job = '',
			diff_count = -1,
			error = '',
		}
		if request_id == '' then
			response.error = 'missing request id'
		elseif type(_G.UC_ReloadProfileV2ForCurrentIdentity) ~= 'function' then
			response.error = 'profile v2 reload unavailable'
		else
			local ok_call, result = pcall(_G.UC_ReloadProfileV2ForCurrentIdentity)
			if not ok_call or type(result) ~= 'table' then
				response.error = ok_call and 'invalid profile v2 reload result' or tostring(result)
			else
				response.ok = result.ok == true
				response.character = tostring(result.character or '')
				response.main_job = tostring(result.main_job or '')
				response.sub_job = tostring(result.sub_job or '')
				response.diff_count = tonumber(result.diff_count) or -1
				response.error = tostring(result.error or '')
			end
		end
		safe_send_line(json_encode_simple(response))
		last_state_send = 0
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
	local camp_status = uc_camp_anchor.status()
	local camp_last_op = rawget(_G, 'UC_LAST_CAMP_OP')
	if type(camp_last_op) ~= 'string' then
		camp_last_op = ''
	end
	local geo_runtime = rawget(_G, 'UC_GEO_MAINTENANCE_STATUS')
	if type(geo_runtime) ~= 'table' then
		geo_runtime = {
			state = 'unavailable',
			reason = 'GEO_STATUS_UNAVAILABLE',
			detail = '',
		}
	end
	local current_target_name, current_target_id = uc_current_target_snapshot()
	local pull_runtime = rawget(_G, 'UC_CAMP_PULLER_STATUS')
	if type(pull_runtime) ~= 'table' then
		pull_runtime = {
			state = 'unavailable',
			reason = 'PULL_STATUS_UNAVAILABLE',
			detail = '',
			target_id = 0,
			target_name = '',
			active_count = 0,
			quota = 0,
			last_intent = '',
		}
	end
	local st = {
		op = 'state',
		session = session_id,
		char = p.name,
		job = p.main_job,
		sub_job = p.sub_job,
		engine = _G.UC_ENGINE,
		Start_Engine = Start_Engine,
		zone_suspend_active = zone_suspend_active,
		camp_active = camp_status.active,
		camp_zone_id = camp_status.zone_id,
		camp_x = camp_status.x,
		camp_y = camp_status.y,
		camp_z = camp_status.z,
		camp_coordinate_mode = camp_status.coordinate_mode,
		camp_set_by = camp_status.set_by,
		camp_last_op = camp_last_op,
		current_target_id = current_target_id,
		current_target_name = current_target_name,
		geo_runtime_state = geo_runtime.state,
		geo_runtime_reason = geo_runtime.reason,
		geo_runtime_detail = geo_runtime.detail,
		camp_pull_runtime_state = pull_runtime.state,
		camp_pull_runtime_reason = pull_runtime.reason,
		camp_pull_runtime_detail = pull_runtime.detail,
		camp_pull_runtime_target_id = pull_runtime.target_id,
		camp_pull_runtime_target_name = pull_runtime.target_name,
		camp_pull_runtime_active_count = pull_runtime.active_count,
		camp_pull_runtime_quota = pull_runtime.quota,
		camp_pull_runtime_intent = pull_runtime.last_intent,
		profile_contract_status = _G.UC_PROFILE_CONTRACT_STATUS,
		config_contract_status = uc_config_runtime.config_contract_status(_G.UC_SETTINGS),
	}
	local active_profile = uc_active_config.get_active_profile()
	if type(active_profile) ~= 'table' then
		error('remote bridge state requires an active configuration')
	end
	local active_settings, projection_err = uc_active_config.project_flat_settings(active_profile, {})
	if type(active_settings) ~= 'table' then
		error('remote bridge active-config projection failed: ' .. tostring(projection_err))
	end
	active_settings.Start_Engine = Start_Engine == true
	st.active_config = active_settings
	if not safe_send_line(json_encode_simple(st)) then
		return
	end
end

function uc_remote_unload()
	close_sock()
end
