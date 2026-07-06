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

-- Add control: when fight leader is active, prefer a non-leader mob (add) other than the leader target.
-- Requires settings.add_control, settings.fight_leader, and a resolved leader_mid > 0.
-- Fight-adds only considers mobs within ADD_PICK_MAX_YALM (see below); unclaimed adds still need settings.prime
-- with the same mob filters as Find_Nearest_Target prime, except range uses ADD_PICK_MAX_YALM not prime melee (8).
-- Optional settings.add_priority_names: ordered strings, top = highest priority (exact name, case-insensitive).
-- When non-empty, pick prefers lower list index over nearer distance; empty list = legacy nearest / tank-hpp only.
-- Verbose evaluation: set settings.debug = true → append to per-character file under data/logs/.

local uc_target_ignore = require('uc_target_ignore')
local uc_add_priority = require('uc_add_priority')
local uc_runtime_overrides = require('uc_runtime_overrides')

local M = {}

local last_detail_emit = 0.0
local DETAIL_INTERVAL = 0.75
local last_retarget_blocked_chat = 0.0
local RETARGET_BLOCK_CHAT_INTERVAL = 4.0

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
	local ap = windower.addon_path
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

--- Append one line (ISO timestamp, tab, message) when settings.debug is on; one file per character.
local function file_log(settings, text)
	if not settings or not truthy(settings.debug) or type(text) ~= 'string' or text == '' then
		return
	end
	pcall(function()
		local p = windower.ffxi.get_player()
		local char = (p and p.name) or 'unknown'
		local dir = ensure_log_dir()
		if not dir then
			return
		end
		local path = dir .. safe_char_name(char) .. '_add_control.log'
		local f = io.open(path, 'a')
		if not f then
			return
		end
		f:write(os.date('%Y-%m-%d %H:%M:%S'), '	', text:gsub('\r?\n', ' '), '\n')
		f:close()
	end)
end

function M.enabled(s)
	if not s then
		return false
	end
	return truthy(s.add_control) and uc_runtime_overrides.fight_leader_enabled(s)
end

local function has_value(tab, val)
	if not tab or val == nil then
		return false
	end
	for _, x in ipairs(tab) do
		if x == val then
			return true
		end
	end
	return false
end

local function mob_label(mob)
	local n = mob and mob['name']
	if type(n) == 'string' and n ~= '' then
		n = n:gsub('[%c]', ' '):sub(1, 18)
		return n
	end
	return '?'
end

local function should_emit_detail(settings)
	if not settings or not truthy(settings.debug) then
		return false
	end
	local now = uc_now_s()
	if now - last_detail_emit < DETAIL_INTERVAL then
		return false
	end
	last_detail_emit = now
	return true
end

-- Fight-adds scan radius (yalms); stricter than prime autotarget melee (8) on purpose.
local ADD_PICK_MAX_YALM = 25

--- When settings.add_priority_names is non-empty, lower rank wins; ties use tank hpp / nearest distance.
local function add_pick_replace_best(use_prio, tank_mode, rank, hp, dist_sq, best_id, best_rank, best_hpp, best_dist)
	if best_id == 0 then
		return true
	end
	if not use_prio then
		if tank_mode then
			return best_hpp == nil or hp > best_hpp
		end
		return best_dist == nil or dist_sq < best_dist
	end
	if rank < best_rank then
		return true
	end
	if rank > best_rank then
		return false
	end
	if tank_mode then
		return best_hpp == nil or hp > best_hpp
	end
	return best_dist == nil or dist_sq < best_dist
end

local function add_pick_yalms(mob)
	local d = mob and mob['distance']
	if not d then
		return nil
	end
	local ok, y = pcall(function()
		return d:sqrt()
	end)
	if not ok or type(y) ~= 'number' then
		return nil
	end
	return y
end

--- Same filters as Find_Nearest_Target prime branch for unclaimed (claim 0) combat mobs; range is enforced separately via ADD_PICK_MAX_YALM for all add picks.
local function prime_unclaimed_ok(settings, mob)
	if not settings or not mob or not truthy(settings.prime) then
		return false
	end
	if (mob['claim_id'] or -1) ~= 0 then
		return false
	end
	if mob['spawn_type'] ~= 16 or (mob['status'] or -1) ~= 1 then
		return false
	end
	if uc_target_ignore.is_mob_blocked(settings, mob) then
		return false
	end
	if not mob['valid_target'] then
		return false
	end
	local hp = mob['hpp']
	return hp ~= nil and hp > 0
end

--- @param partner_block fun(mob: table): boolean  if true, skip this mob
function M.pick(settings, claims, marray, leader_mid, opts)
	if not settings or not marray or type(claims) ~= 'table' then
		if should_emit_detail(settings) then
			file_log(settings, '[UC add] pick ABORT: bad settings/marray/claims')
		end
		return 0
	end
	if not M.enabled(settings) then
		return 0
	end
	if not leader_mid or leader_mid <= 0 then
		if should_emit_detail(settings) then
			file_log(settings, '[UC add] pick SKIP: no leader_mid (fight leader off, no target, or target invalid)')
		end
		return 0
	end

	opts = opts or {}
	local hunter_in_claim = opts.hunter_in_claim == true
	local melee_style = opts.melee_style == true
	local manual = truthy(settings.manual)
	local partner_block = opts.partner_block
	local tank = truthy(settings.tank)
	local emit = should_emit_detail(settings)

	local lines = {}
	local function L(fmt, ...)
		if emit then
			lines[#lines + 1] = fmt:format(...)
		end
	end

	local prio_list = uc_add_priority.as_ordered_names(settings)
	local use_prio = #prio_list > 0

	if emit then
		L('[UC add] === pick start leader_mid=%d hunter_in_claim=%s prime=%s tank=%s melee_style=%s manual=%s add_max_yalm=%d add_priority=%d',
			leader_mid, tostring(hunter_in_claim), tostring(truthy(settings.prime)), tostring(tank), tostring(melee_style),
			tostring(manual), ADD_PICK_MAX_YALM, #prio_list)
		local lm = leader_mid
		pcall(function()
			if type(GetNameById) == 'function' then
				local nm = GetNameById(lm)
				if nm and nm ~= '' then
					L('[UC add] leader mob name: %s', tostring(nm))
				end
			end
		end)
	end

	local best_id = 0
	local best_dist = nil
	local best_hpp = nil
	local best_rank = nil
	local n_seen = 0
	local n_logged = 0
	local MAX_ROWS = 18

	for _, mob in pairs(marray) do
		if type(mob) ~= 'table' then
			-- skip
		else
			n_seen = n_seen + 1
			local mid = mob['id']
			local label = mob_label(mob)
			if not mid or mid == 0 then
				-- skip
			elseif mid == leader_mid then
				if emit and n_logged < MAX_ROWS then
					local st = mob['spawn_type']
					local hp = mob['hpp']
					local cl = mob['claim_id']
					n_logged = n_logged + 1
					L('[UC add]   id=%d %s spawn=%s hpp=%s claim=%s -> LEADER_TARGET (not an add)', mid, label,
						tostring(st), tostring(hp), tostring(cl))
				end
			else
				local party_claim = has_value(claims, mob['claim_id'])
				local hunter_claim = hunter_in_claim and truthy(settings.hunter)
				local prime_ok = prime_unclaimed_ok(settings, mob)
				local claim_ok = party_claim or hunter_claim or prime_ok
				local st = mob['spawn_type']
				local hp = mob['hpp']
				local vt = mob['valid_target']
				local cl = mob['claim_id']
				local interesting = claim_ok or (st == 16 and hp and hp > 0)
				if not interesting then
					-- skip chat (hundreds of empty slots)
				else
					if not claim_ok then
						if emit and n_logged < MAX_ROWS then
							n_logged = n_logged + 1
							L('[UC add]   id=%d %s spawn=%s hpp=%s claim=%s -> GATE:no_party_claim (hunter=%s prime=%s)', mid, label,
								tostring(st), tostring(hp), tostring(cl), tostring(truthy(settings.hunter)),
								tostring(truthy(settings.prime)))
						end
					elseif not vt then
						if emit and n_logged < MAX_ROWS then
							n_logged = n_logged + 1
							L('[UC add]   id=%d %s -> GATE:valid_target=false', mid, label)
						end
					elseif uc_target_ignore.is_mob_blocked(settings, mob) then
						if emit and n_logged < MAX_ROWS then
							n_logged = n_logged + 1
							L('[UC add]   id=%d %s -> GATE:target_name_ignore_list', mid, label)
						end
					else
						local skip_partner = partner_block and partner_block(mob)
						if skip_partner then
							if emit and n_logged < MAX_ROWS then
								n_logged = n_logged + 1
								L('[UC add]   id=%d %s -> GATE:partner_skip', mid, label)
							end
						elseif hp == nil or hp <= 0 then
							if emit and n_logged < MAX_ROWS then
								n_logged = n_logged + 1
								L('[UC add]   id=%d %s -> GATE:dead_or_no_hpp (%s)', mid, label, tostring(hp))
							end
						else
							local spawn_ok
							if melee_style then
								spawn_ok = (st == 16) or manual
							else
								spawn_ok = (st == 16)
							end
							if not spawn_ok then
								if emit and n_logged < MAX_ROWS then
									n_logged = n_logged + 1
									L('[UC add]   id=%d %s spawn=%s -> GATE:spawn_not_monster (melee_style=%s manual=%s)', mid,
										label, tostring(st), tostring(melee_style), tostring(manual))
								end
							elseif not mob['distance'] then
								if emit and n_logged < MAX_ROWS then
									n_logged = n_logged + 1
									L('[UC add]   id=%d %s -> GATE:no_distance', mid, label)
								end
							else
								local yalm = add_pick_yalms(mob)
								if yalm == nil then
									if emit and n_logged < MAX_ROWS then
										n_logged = n_logged + 1
										L('[UC add]   id=%d %s -> GATE:no_distance_yalms', mid, label)
									end
								elseif yalm > ADD_PICK_MAX_YALM then
									if emit and n_logged < MAX_ROWS then
										n_logged = n_logged + 1
										L('[UC add]   id=%d %s -> GATE:out_of_add_range yalms=%.2f max=%d', mid, label, yalm,
											ADD_PICK_MAX_YALM)
									end
								else
									local rank = uc_add_priority.rank_for_mob_name(settings, mob['name'])
									local dist_sq = mob['distance']
									if add_pick_replace_best(use_prio, tank, rank, hp, dist_sq, best_id, best_rank, best_hpp, best_dist) then
										best_id = mid
										best_dist = dist_sq
										best_hpp = hp
										if use_prio then
											best_rank = rank
										end
									end
									if emit and n_logged < MAX_ROWS then
										n_logged = n_logged + 1
										if use_prio then
											L('[UC add]   id=%d %s dist=%s yalms=%.2f hpp=%s prio_rank=%s -> CANDIDATE (tank_pick=%s)', mid,
												label, tostring(mob['distance']), yalm, tostring(hp),
												rank and tostring(rank) .. '/' .. tostring(#prio_list + 1) or '?', tostring(tank))
										else
											L('[UC add]   id=%d %s dist=%s yalms=%.2f hpp=%s -> CANDIDATE (tank_pick=%s)', mid, label,
												tostring(mob['distance']), yalm, tostring(hp), tostring(tank))
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	if emit then
		local pr = '-'
		if use_prio and best_id ~= 0 and best_rank ~= nil then
			pr = tostring(best_rank) .. '/' .. tostring(#prio_list + 1)
		elseif use_prio then
			pr = 'none'
		end
		L('[UC add] === pick result add_mid=%d prio_rank=%s (mobs_seen=%d rows=%d)', best_id, pr, n_seen, n_logged)
		for _, ln in ipairs(lines) do
			file_log(settings, ln)
		end
	end

	return best_id
end

-- Add-control retarget: /attack off does not clear `st` target, but client status should leave
-- Engaged (1) and become Idle (0) per res.statuses — wait for Idle before `st` + attack (bounded).
local ADD_RETARGET_SLICE = 0.08
local ADD_RETARGET_MAX_LOOPS = 45
local ADD_RETARGET_POST_ST = 0.12
local STATUS_IDLE = 0
local STATUS_ENGAGED = 1

local function co_sleep(sec)
	if type(sec) ~= 'number' or sec <= 0 then
		return
	end
	pcall(coroutine.sleep, sec)
end

local function get_player_status()
	local p = windower.ffxi.get_player()
	if not p then
		return nil
	end
	return p.status
end

--- Disengage, wait until Idle (0) after attack off, then `st` and final attack input.
--- If still Engaged (1) after the wait budget, does **not** run `st` or attack — returns false (no silent retarget).
--- @param attack_cmd string  e.g. `input /attack 12345` (melee) or `input /attack on` (dd2)
--- @return boolean true if `st` + attack were sent
function M.execute_add_retarget(settings, want_mid, attack_cmd)
	if not settings or not want_mid or want_mid <= 0 then
		return false
	end
	if type(attack_cmd) ~= 'string' or attack_cmd == '' then
		if truthy(settings.debug) then
			file_log(settings, '[UC add] retarget ABORT: empty attack_cmd')
		end
		return false
	end
	local status_before = get_player_status()
	windower.send_command('input /attack off')
	local loops = 0
	local reason = 'timeout'
	local last_status = status_before
	if status_before ~= STATUS_ENGAGED then
		-- Not Engaged (e.g. race or already disengaged): brief settle then `st` — do not wait for Idle transition.
		co_sleep(ADD_RETARGET_SLICE * 2)
		last_status = get_player_status()
		reason = 'not_engaged_skip_wait'
	else
		while loops < ADD_RETARGET_MAX_LOOPS do
			co_sleep(ADD_RETARGET_SLICE)
			loops = loops + 1
			local st = get_player_status()
			last_status = st
			if st == STATUS_IDLE then
				reason = 'idle_after_attack_off'
				break
			end
		end
	end
	if reason == 'timeout' then
		if truthy(settings.debug) then
			file_log(settings, ('[UC add] retarget BLOCKED still_engaged want=%d status_before=%s last_status=%s loops=%d (no st/attack)'):format(
				want_mid, tostring(status_before), tostring(last_status), loops))
		end
		M.log_line(settings, ('retarget BLOCKED still_engaged loops=%d want=%d status_before=%s last_status=%s'):format(
			loops, want_mid, tostring(status_before), tostring(last_status)))
		local nowc = uc_now_s()
		if nowc - last_retarget_blocked_chat >= RETARGET_BLOCK_CHAT_INTERVAL then
			last_retarget_blocked_chat = nowc
			pcall(function()
				windower.add_to_chat(167,
					('[UC add] Retarget blocked: still Engaged after /attack off (want id %d). Not changing target; next tick will retry.'):format(
						want_mid))
			end)
		end
		return false
	end
	M.log_line(settings, ('retarget seq reason=%s loops=%d want=%d status_before=%s last_status=%s'):format(
		reason, loops, want_mid, tostring(status_before), tostring(last_status)))
	windower.send_command(('st %d'):format(want_mid))
	co_sleep(ADD_RETARGET_POST_ST)
	windower.send_command(attack_cmd)
	return true
end

--- Short one-line log (throttled) when settings.debug is on.
function M.log_line(settings, msg)
	if not settings or not truthy(settings.debug) or type(msg) ~= 'string' then
		return
	end
	local now = uc_now_s()
	_G.UC_ADD_LINE_LOG_T = _G.UC_ADD_LINE_LOG_T or 0
	if now - _G.UC_ADD_LINE_LOG_T < 0.5 then
		return
	end
	_G.UC_ADD_LINE_LOG_T = now
	file_log(settings, '[UC add] ' .. msg)
end

return M
