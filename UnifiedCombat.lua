local function uc_prefer_addon_local_libs()
	local ap = windower and windower.addon_path or nil
	if type(ap) ~= 'string' or ap == '' then
		return
	end
	ap = ap:gsub('\\', '/')
	if ap:sub(-1) ~= '/' then
		ap = ap .. '/'
	end
	local p1 = ap .. '?.lua'
	local p2 = ap .. '?/?.lua'
	if not package.path:find(p1, 1, true) then
		package.path = p1 .. ';' .. p2 .. ';' .. package.path
	end
end

uc_prefer_addon_local_libs()

require('lor/lor_utils')
require('tables')
require('luau')

_addon.name = 'unifiedcombat'
_addon.author = 'me'
_addon.version = '1.0'
_addon.commands = { 'uc', 'unifiedcombat' }

UC_ENGINE = 'UC'
_G.UC_REMOTE_HOST = _G.UC_REMOTE_HOST or '127.0.0.1'
_G.UC_REMOTE_PORT = _G.UC_REMOTE_PORT or 27182

Start_Engine = false
_G.UC_ENABLE_LEGACY_JOB_ADAPTERS = false

-- After zoning, suspend unified combat ticks (scheduler + offense) so mob data can settle and we
-- do not immediately autotarget with stale/cleared engine state (zone resets engagement; no /attack off).
local UC_ZONE_SUSPEND_SEC = 15

UC_JOB_DEFAULTS = {
	WAR = {
		ws1 = 'Savage Blade',
		ability1 = '',
		ability2 = '',
		ability3 = '',
		ability4 = '',
		ability5 = '',
		ability6 = '',
	},
	MNK = {
		ws1 = 'Shijin Spiral',
		ability1 = '',
		ability2 = '',
		ability3 = '',
		ability4 = '',
		ability5 = '',
		ability6 = '',
	},
	SAM = {
		ws1 = 'Tachi: Kasha',
		ability1 = 'Hasso',
		ability2 = 'Third Eye',
		ability3 = 'Berserk',
		ability4 = 'Aggressor',
		ability5 = 'Meditate',
		ability6 = '',
	},
	DRG = {
		ws1 = 'Stardiver',
		ability1 = 'Hasso',
		ability2 = '',
		ability3 = 'Berserk',
		ability4 = 'Aggressor',
		ability5 = 'Meditate',
		ability6 = '',
	},
	DRK = {
		ws1 = 'Entropy',
		ability1 = 'Hasso',
		ability2 = 'Third Eye',
		ability3 = 'Last Resort',
		ability4 = 'Diabolic Eye',
		ability5 = 'Meditate',
		ability6 = 'Consume Mana',
	},
}

local res = require('resources')
local files = require('files')
require('actions')

local uc_partner_list = require('uc_partner_list')
local uc_add_priority = require('uc_add_priority')

local function uc_new_settings_defaults()
	return {
		profiles = { UC = {} },
		engine_mode = 'UC',
		ability_active = false,
		abilities = {},
		weaponskill = '',
		ws1 = '',
		weaponskill_active = false,
		aftermath_enabled = false,
		aftermath_ws = '',
		autotarget = false,
		spam = false,
		closer = false,
		manual = false,
		prime = false,
		static = false,
		spacing = false,
		spacing_band_min = -0.9,
		spacing_band_max = 0.4,
		spacing_use_prediction = true,
		spacing_lookahead_s = 0.25,
		spacing_anchor_invalid_ticks = 5,
		spacing_emergency_margin = 0.10,
		spacing_slot_switch_penalty = 0.75,
		spacing_slot_switch_margin = 0.35,
		spacing_slot_arrival_tolerance = 0.20,
		spacing_max_agents = 6,
		face = false,
		partner = false,
		partner2 = false,
		puller = false,
		puller_distance_only = false,
		partner_id = 0,
		partner_id2 = 0,
		partner_ids = {},
		puller_id = 0,
		fight_leader = false,
		fight_leader_id = 0,
		party_follow = false,
		party_follow_id = 0,
		party_follow_leader_name = '',
		party_follow_min = 0.5,
		party_follow_max = 50,
		fight_follow_min = 3.0,
		fight_follow_hold_s = 8.0,
		add_control = false,
		add_priority_names = {},
		sub = false,
		sub2 = false,
		move = false,
		debug = false,
		solo = false,
		aeonic = false,
		color = false,
		tank = false,
		sleep = false,
		command = false,
		hunter = false,
		sleepspell = 'Horde Lullaby II',
		defensive_enabled = false,
		defensive_provider = 'internal',
		defensive_cure_enabled = false,
		defensive_na_enabled = false,
		defensive_buff_enabled = false,
		defensive_critical_hpp = 35,
		defensive_medium_hpp = 55,
		defensive_overwrite_enabled = false,
		defensive_overwrite_interval = 150,
		defensive_buff_self_only = true,
		defensive_buffs = '',
		scheduler_dark_launch_defensive = false,
		scheduler_dark_launch_movement = false,
		ignore = {},
		target_ignore_names = {},
		show_ingame_ui = false,
	}
end

_G.UC_SETTINGS = uc_new_settings_defaults()

require('remote_bridge')
local UC_COMBAT_CORE = require('unified_combat_core')
local UC_UNIFIED_ENGINE = require('unified_engine')
local uc_party_follow = require('uc_party_follow')

local function uc_update_engine()
	UC_ENGINE = 'UC'
end

local function uc_start_active_engine_if_running()
	if not Start_Engine then
		return
	end
	if UC_UNIFIED_ENGINE and type(UC_UNIFIED_ENGINE.start) == 'function' then
		UC_UNIFIED_ENGINE.start()
	end
end

_G.UC_StartUnifiedEngine = function()
	if UC_UNIFIED_ENGINE and type(UC_UNIFIED_ENGINE.start) == 'function' then
		UC_UNIFIED_ENGINE.start()
	end
end

_G.UC_StopUnifiedEngine = function()
	if UC_UNIFIED_ENGINE and type(UC_UNIFIED_ENGINE.stop) == 'function' then
		UC_UNIFIED_ENGINE.stop()
	end
end

_G.UC_CoreCombatTickOnce = function()
	if UC_COMBAT_CORE and type(UC_COMBAT_CORE.combat_tick_once) == 'function' then
		UC_COMBAT_CORE.combat_tick_once()
	end
end

local function uc_apply_job_defaults(job)
	if not job or not _G.UC_SETTINGS then
		return
	end
	local j = job
	if type(j) ~= 'string' then
		j = res.jobs:with('id', j).english_short
	end
	j = j:upper()
	local d = UC_JOB_DEFAULTS[j]
	if not d then
		return
	end
	for k, v in pairs(d) do
		local cur = _G.UC_SETTINGS[k]
		if cur == nil or cur == '' then
			_G.UC_SETTINGS[k] = v
		end
	end
end

local PROFILE_KEYS = {
	'ability1', 'ability2', 'ability3', 'ability4', 'ability5', 'ability6',
	'ability_active', 'abilities', 'wsabilities',
	'ws1', 'weaponskill', 'weaponskill_active',
	'aftermath_enabled', 'aftermath_ws',
	'engine_mode',
	'show_ingame_ui',
	'defensive_enabled', 'defensive_provider', 'defensive_cure_enabled', 'defensive_na_enabled', 'defensive_buff_enabled',
	'defensive_critical_hpp', 'defensive_medium_hpp',
	'defensive_overwrite_enabled', 'defensive_overwrite_interval', 'defensive_buff_self_only', 'defensive_buffs',
	'scheduler_dark_launch_defensive', 'scheduler_dark_launch_movement',
	'autotarget', 'spam', 'closer', 'manual', 'prime', 'static', 'spacing', 'face',
	'spacing_band_min', 'spacing_band_max', 'spacing_use_prediction', 'spacing_lookahead_s',
	'spacing_anchor_invalid_ticks', 'spacing_emergency_margin', 'spacing_slot_switch_penalty',
	'spacing_slot_switch_margin', 'spacing_slot_arrival_tolerance', 'spacing_max_agents',
	'partner', 'partner2', 'puller', 'puller_distance_only', 'partner_id', 'partner_id2', 'partner_ids', 'puller_id',
	'fight_leader', 'fight_leader_id', 'party_follow', 'party_follow_id', 'party_follow_leader_name', 'party_follow_min', 'party_follow_max', 'fight_follow_min', 'fight_follow_hold_s',
	'add_control', 'add_priority_names',
	'sub', 'sub2', 'move', 'debug', 'solo', 'aeonic', 'color', 'tank', 'sleep', 'command', 'hunter',
	'target1', 'target2', 'target3', 'targets',
	'targetability', 'targetability_active',
	'spell', 'spell_active', 'sleepspell',
	'dd2_spell_slots', 'ignore', 'target_ignore_names',
}

local function uc_clone_value(v)
	if type(v) ~= 'table' then
		return v
	end
	local out = {}
	for k, vv in pairs(v) do
		out[k] = uc_clone_value(vv)
	end
	return out
end

local function uc_safe_filename(name)
	local n = tostring(name or 'unknown'):lower()
	n = n:gsub('[^%w%-_]+', '_')
	if n == '' then
		n = 'unknown'
	end
	return n
end

local function uc_profiles_file_path(char_name)
	return 'data/profiles/' .. uc_safe_filename(char_name) .. '.lua'
end

local uc_normalize_profiles_tree

local function uc_serialize_lua(v, indent)
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
			key = '[' .. uc_serialize_lua(k, next_indent) .. ']'
		end
		parts[#parts + 1] = '\n' .. npad .. key .. ' = ' .. uc_serialize_lua(vv, next_indent) .. ','
	end
	if #parts > 1 then
		parts[#parts + 1] = '\n' .. pad .. '}'
	else
		parts[#parts + 1] = '}'
	end
	return table.concat(parts, '')
end

local function uc_write_profiles_file(char_name, profiles_tbl)
	local path = uc_profiles_file_path(char_name)
	local payload = {
		version = 1,
		profiles = uc_normalize_profiles_tree(uc_clone_value(profiles_tbl or {})),
	}
	local content = 'return ' .. uc_serialize_lua(payload, 0) .. '\n'
	local fobj = files.new(path, true)
	local ok = files.write(fobj, content)
	return ok ~= nil
end

local function uc_read_profiles_file(char_name)
	local path = uc_profiles_file_path(char_name)
	if not files.exists(path) then
		return nil
	end
	local content = files.read(path)
	if type(content) ~= 'string' or content == '' then
		return nil
	end
	local loader = loadstring or load
	local chunk = loader and loader(content) or nil
	if type(chunk) ~= 'function' then
		return nil
	end
	local ok, payload = pcall(chunk)
	if not ok or type(payload) ~= 'table' then
		return nil
	end
	if type(payload.profiles) == 'table' then
		return payload.profiles
	end
	if type(payload.melee) == 'table' or type(payload.dd2) == 'table' then
		return payload
	end
	return nil
end

local uc_get_active_profile_coords

local function uc_normalize_abilities(s)
	local out = {}
	if type(s.abilities) == 'table' then
		for _, a in ipairs(s.abilities) do
			if a and a ~= '' then
				out[#out + 1] = a
			end
		end
	end
	if #out == 0 then
		for i = 1, 6 do
			local a = s['ability' .. tostring(i)]
			if a and a ~= '' then
				out[#out + 1] = a
			end
		end
	end
	s.abilities = out
	for i = 1, 6 do
		s['ability' .. tostring(i)] = out[i] or ''
	end
end

local function uc_normalize_targets(s)
	if type(s.targets) ~= 'table' then
		s.targets = {}
	end
	if #s.targets == 0 then
		local arr = {}
		for i = 1, 3 do
			local t = s['target' .. tostring(i)]
			if t and t ~= '' then
				arr[#arr + 1] = t
			end
		end
		s.targets = arr
	else
		for i = 1, 3 do
			s['target' .. tostring(i)] = s.targets[i] or ''
		end
	end
end

local function uc_normalize_ws_for_engine(s, eng)
	local ws = s.weaponskill or s.ws1 or ''
	s.weaponskill = ws
	s.ws1 = ws
	s.engine_mode = eng
end

local function uc_normalize_active_settings()
	local s = _G.UC_SETTINGS
	if not s then
		return
	end
	local eng, _ = uc_get_active_profile_coords()
	uc_normalize_abilities(s)
	uc_normalize_targets(s)
	uc_normalize_ws_for_engine(s, eng)
	uc_partner_list.migrate_from_legacy(s)
	uc_partner_list.sync_legacy_partner_fields(s)
end

uc_get_active_profile_coords = function()
	local p = windower.ffxi.get_player()
	local eng = 'UC'
	local job = p and p.main_job or 'UNKNOWN'
	if type(job) ~= 'string' then
		local rj = res.jobs:with('id', job)
		job = (rj and rj.english_short) or tostring(job)
	end
	job = tostring(job):upper()
	return eng, job
end

local function uc_get_profiles_root()
	local s = _G.UC_SETTINGS
	if not s then
		return nil
	end
	if type(s.profiles) ~= 'table' then
		s.profiles = {}
	end
	if type(s.profiles.UC) ~= 'table' then
		s.profiles.UC = {}
	end
	return s.profiles
end

local function uc_table_has_any(t)
	if type(t) ~= 'table' then
		return false
	end
	for _ in pairs(t) do
		return true
	end
	return false
end

uc_normalize_profiles_tree = function(profiles)
	if type(profiles) ~= 'table' then
		return { UC = {} }
	end
	local uc_branch = profiles.UC
	if type(uc_branch) ~= 'table' then
		uc_branch = {}
		local candidates = { profiles.melee, profiles.dd2, profiles.DD2 }
		for _, branch in ipairs(candidates) do
			if type(branch) == 'table' then
				for job, pdata in pairs(branch) do
					local j = tostring(job):upper()
					if type(uc_branch[j]) ~= 'table' then
						uc_branch[j] = uc_clone_value(pdata)
					end
				end
			end
		end
		for key, val in pairs(profiles) do
			if key ~= 'UC' and key ~= 'melee' and key ~= 'dd2' and key ~= 'DD2' and type(val) == 'table' then
				local j = tostring(key):upper()
				if type(uc_branch[j]) ~= 'table' then
					uc_branch[j] = uc_clone_value(val)
				end
			end
		end
	end
	local out = { UC = {} }
	for job, pdata in pairs(uc_branch) do
		local j = tostring(job):upper()
		out.UC[j] = uc_clone_value(pdata)
	end
	return out
end

local function uc_load_profiles_for_character(char_name)
	if not _G.UC_SETTINGS or not char_name or char_name == '' then
		return false
	end
	local file_profiles = uc_read_profiles_file(char_name)
	if type(file_profiles) ~= 'table' then
		return false
	end
	_G.UC_SETTINGS.profiles = uc_normalize_profiles_tree(uc_clone_value(file_profiles))
	uc_get_profiles_root()
	return true
end

local function uc_capture_active_profile()
	local s = _G.UC_SETTINGS
	local profiles = uc_get_profiles_root()
	if not s or not profiles then
		return false
	end
	uc_normalize_active_settings()
	local eng, job = uc_get_active_profile_coords()
	profiles[eng][job] = profiles[eng][job] or {}
	local dst = profiles[eng][job]
	for _, key in ipairs(PROFILE_KEYS) do
		if s[key] ~= nil then
			dst[key] = uc_clone_value(s[key])
		else
			dst[key] = nil
		end
	end
	return true
end

local function uc_apply_active_profile()
	local s = _G.UC_SETTINGS
	local profiles = uc_get_profiles_root()
	if not s or not profiles then
		return false
	end
	local eng, job = uc_get_active_profile_coords()
	local src = profiles[eng] and profiles[eng][job] or nil
	if type(src) ~= 'table' or not uc_table_has_any(src) then
		return false
	end
	for _, key in ipairs(PROFILE_KEYS) do
		s[key] = uc_clone_value(src[key])
	end
	uc_normalize_active_settings()
	return true
end

local function uc_save_active_profile()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not _G.UC_SETTINGS then
		return
	end
	uc_capture_active_profile()
	local profiles = uc_normalize_profiles_tree(uc_get_profiles_root())
	uc_write_profiles_file(p.name, profiles)
end

local function uc_reload_character_settings()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not _G.UC_SETTINGS then
		return nil
	end
	return p
end

local function uc_reload_active_profile(job_for_defaults)
	local p = uc_reload_character_settings()
	if not p then
		return nil
	end
	local loaded_from_file = uc_load_profiles_for_character(p.name)
	if job_for_defaults then
		uc_apply_job_defaults(job_for_defaults)
	else
		uc_apply_job_defaults(p.main_job)
	end
	if not uc_apply_active_profile() then
		-- Missing profile: capture exactly current state without silent correction.
		uc_capture_active_profile()
	end
	if not loaded_from_file then
		local profiles = uc_normalize_profiles_tree(uc_get_profiles_root())
		uc_write_profiles_file(p.name, profiles)
	end
	return p
end

_G.UC_SaveActiveProfile = uc_save_active_profile
_G.UC_ReloadActiveProfile = uc_reload_active_profile

local ap_listener_id

local function uc_register_action_listener()
	if ap_listener_id then
		ActionPacket.close_listener(ap_listener_id)
		ap_listener_id = nil
	end
	ap_listener_id = ActionPacket.open_listener(function(act_org, act_mod)
		local act = act_org
		if UC_COMBAT_CORE and type(UC_COMBAT_CORE.on_action) == 'function' then
			UC_COMBAT_CORE.on_action(act)
		end
		if type(_G.UC_SCHED_OnAction) == 'function' then
			_G.UC_SCHED_OnAction(act)
		end
	end)
end

windower.register_event('load', function()
	uc_register_action_listener()
	if windower.ffxi.get_info().logged_in then
		uc_update_engine()
		uc_reload_active_profile()
	end
end)

windower.register_event('incoming chunk', function(id, data)
	if id == 0x029 and type(data) == 'string' and UC_COMBAT_CORE and type(UC_COMBAT_CORE.on_action_message) == 'function' then
		local ok = pcall(function()
			local msg = {
				target_id = data:unpack('I', 0x09),
				message_id = data:unpack('H', 0x19) % 32768,
			}
			UC_COMBAT_CORE.on_action_message(msg)
			if type(_G.UC_SCHED_OnActionMessage) == 'function' then
				_G.UC_SCHED_OnActionMessage(msg)
			end
		end)
		if not ok then
			-- ignore malformed packet parse; core tick remains authoritative fallback.
		end
	end
end)

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
	local buf = modified or data
	if uc_party_follow.outgoing_chunk(id, buf, blocked) then
		return true
	end
end)

windower.register_event('prerender', function()
	uc_party_follow.broadcast_self_ipc()
	uc_remote_tick()
	uc_party_follow.prerender()
end)

windower.register_event('job change', function(job, lvl)
	local jname = res.jobs:with('id', job).english_short
	uc_update_engine()
	uc_reload_active_profile(jname)
	uc_start_active_engine_if_running()
	uc_register_action_listener()
end)

windower.register_event('zone change', function()
	_G.UC_ZONE_SUSPEND_UNTIL = os.clock() + UC_ZONE_SUSPEND_SEC
	_G.UC_LAST_BLOCK_REASON = 'ZONE_SUSPEND'
end)

windower.register_event('unload', function()
	uc_remote_unload()
	if type(_G.UC_StopUnifiedEngine) == 'function' then
		_G.UC_StopUnifiedEngine()
	end
	if ap_listener_id then
		ActionPacket.close_listener(ap_listener_id)
		ap_listener_id = nil
	end
end)

windower.register_event('logout', function()
	_G.UC_ZONE_SUSPEND_UNTIL = nil
	uc_remote_unload()
	if type(_G.UC_StopUnifiedEngine) == 'function' then
		_G.UC_StopUnifiedEngine()
	end
end)

windower.register_event('status change', function(a, b)
	-- unified core handles runtime behavior; no legacy status hooks.
end)

local function uc_fight_leader_party_id_by_name(name)
	if not name or name == '' then
		return 0
	end
	local want = tostring(name):lower()
	local party = windower.ffxi.get_party()
	if not party then
		return 0
	end
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, key in ipairs(keys) do
		local e = party[key]
		local mob = e and e.mob
		if mob and mob.name and mob.name:lower() == want and mob.id and mob.id ~= 0 then
			return mob.id
		end
	end
	return 0
end

windower.register_event('addon command', function(...)
	local args = { ... }
	local a = args[1] and tostring(args[1]):lower() or ''
	if a == 'start' then
		if not Start_Engine then
			Start_Engine = true
			uc_start_active_engine_if_running()
			windower.add_to_chat(207, 'UnifiedCombat: engine started')
		end
		return
	elseif a == 'stop' then
		Start_Engine = false
		if type(_G.UC_StopUnifiedEngine) == 'function' then
			_G.UC_StopUnifiedEngine()
		end
		windower.add_to_chat(207, 'UnifiedCombat: engine stopped')
		return
	elseif a == 'save' then
		if type(_G.UC_SaveActiveProfile) == 'function' then
			_G.UC_SaveActiveProfile()
		end
		windower.add_to_chat(207, 'UnifiedCombat: profile saved')
		return
	elseif a == 'reload' then
		if type(_G.UC_ReloadActiveProfile) == 'function' then
			_G.UC_ReloadActiveProfile()
		end
		windower.add_to_chat(207, 'UnifiedCombat: profile reloaded')
		return
	elseif a == 'host' and args[2] then
		_G.UC_REMOTE_HOST = tostring(args[2])
		windower.add_to_chat(207, 'UnifiedCombat remote host: ' .. _G.UC_REMOTE_HOST)
		return
	elseif a == 'port' and args[2] then
		_G.UC_REMOTE_PORT = tonumber(args[2]) or 27182
		windower.add_to_chat(207, 'UnifiedCombat remote port: ' .. tostring(_G.UC_REMOTE_PORT))
		return
	elseif a == 'engine' then
		windower.add_to_chat(207, 'UnifiedCombat engine: ' .. UC_ENGINE)
		return
	elseif a == 'fight_leader' or a == 'fightleader' then
		local s = _G.UC_SETTINGS
		if not s then
			return
		end
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'on' then
			s.fight_leader = true
			windower.add_to_chat(207, 'Fight leader: on')
			return
		elseif sub == 'off' then
			s.fight_leader = false
			windower.add_to_chat(207, 'Fight leader: off')
			return
		elseif sub == 'clear' then
			s.fight_leader_id = 0
			windower.add_to_chat(207, 'Fight leader: id cleared')
			return
		elseif args[2] then
			local nm = tostring(args[2])
			local pid = uc_fight_leader_party_id_by_name(nm)
			if pid == 0 then
				windower.add_to_chat(167, 'Fight leader: not in party: ' .. nm)
				return
			end
			s.fight_leader = true
			s.fight_leader_id = pid
			windower.add_to_chat(207, 'Fight leader set: ' .. nm)
			return
		end
		windower.add_to_chat(207, '//uc fight_leader on|off|clear|<party name>')
		return
	elseif a == 'add_priority' or a == 'addpriority' then
		local s = _G.UC_SETTINGS
		if not s then
			return
		end
		local sub = args[2] and tostring(args[2]):lower() or ''
		if sub == 'clear' then
			s.add_priority_names = {}
			_G.UC_LAST_ADD_PRIORITY_OP = 'clear'
			windower.add_to_chat(207, 'Add priority list cleared (fight-adds uses distance/tank only).')
			return
		elseif sub == 'list' then
			local arr = uc_add_priority.as_ordered_names(s)
			if #arr == 0 then
				windower.add_to_chat(207, 'Add priority list: (empty)')
			else
				for i, nm in ipairs(arr) do
					windower.add_to_chat(207, ('  %d. %s'):format(i, nm))
				end
			end
			return
		elseif sub == 'add' then
			local raw = table.concat(args, ' ', 3)
			local nm = type(raw) == 'string' and (raw:match('^%s*(.-)%s*$') or '') or ''
			if nm == '' then
				windower.add_to_chat(167, 'Add priority: need name after add')
				return
			end
			local ok, why = uc_add_priority.append_name(s, nm)
			if not ok then
				if why == 'ADD_PRIORITY_ALREADY' then
					windower.add_to_chat(167, 'Add priority: already listed: ' .. nm)
				else
					windower.add_to_chat(167, 'Add priority: could not add: ' .. tostring(why))
				end
				return
			end
			_G.UC_LAST_ADD_PRIORITY_OP = 'add:' .. nm
			windower.add_to_chat(207, 'Add priority appended: ' .. nm)
			return
		elseif sub == 'remove' and args[3] then
			local idx = tonumber(args[3])
			local ok, why = uc_add_priority.remove_index(s, idx)
			if not ok then
				windower.add_to_chat(167, 'Add priority remove failed: ' .. tostring(why) .. ' (use //uc add_priority list)')
				return
			end
			_G.UC_LAST_ADD_PRIORITY_OP = 'remove:' .. tostring(idx)
			windower.add_to_chat(207, 'Add priority removed index ' .. tostring(idx))
			return
		end
		windower.add_to_chat(207, '//uc add_priority add <mob name>|remove <n>|list|clear')
		return
	end
	windower.add_to_chat(167, 'Unknown command.')
end)

windower.register_event('login', function()
	uc_update_engine()
	uc_reload_active_profile()
	uc_start_active_engine_if_running()
	uc_register_action_listener()
end)
