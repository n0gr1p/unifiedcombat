local res = require('resources')
local ability_pipeline = require('uc_ability_pipeline')
local combat_core = require('unified_combat_core')
local uc_targeting_common = require('uc_targeting_common')
local cor_maintenance = require('uc_cor_maintenance')
local uc_settarget = require('uc_settarget')
local uc_attack = require('uc_attack')
local uc_partner_list = require('uc_partner_list')
local uc_fight_leader = require('uc_fight_leader')
local hb_buff_maint = require('uc_hb_buff_maint')
local enemy_effect_tracker = require('uc_enemy_effect_tracker')
local lor_packets = require('lor/lor_packets')
local json = require('json')
local tb_effect_table = require('uc_tb_effect_table')
local scheduler_locks = require('uc_scheduler_locks')
local scheduler_pending = require('uc_scheduler_pending')
local socket_ok, socket_mod = pcall(require, 'socket')
local socket_gettime = (socket_ok and type(socket_mod) == 'table' and type(socket_mod.gettime) == 'function') and socket_mod.gettime
	or nil
local time_source_error_reported = false
local tb_spells = nil
local tb_abilities = nil
local tb_skills = nil

local action_buff_map = {}
do
	local ok, map = pcall(dofile, windower.addon_path .. 'data/action_buff_map.lua')
	if ok and type(map) == 'table' then
		action_buff_map = map
	end
end

local scheduler = {
	last_action_at = 0,
	action_delay = 1.5,
	attempted = {},
	last_overwrite = {},
	family_order = {},
	family_tokens = {},
	family_counts = {},
	recent_gain = {},
	phase1 = {
		tick = 0,
		last_selected = nil,
		last_noop_reason = 'init',
		last_reject_top = '',
		last_top3 = '',
		last_top5_lines = {},
		last_top5_items = {},
		last_plan = nil,
		pending = nil,
		recent_duplicate_until = {},
		recent_rejects = {},
		recent_reject_items = {},
		maintenance_next_at = {},
		tank_spell_settle_key = '',
		tank_spell_settle_until = 0,
		tank_action_settle_key = '',
		tank_action_settle_until = 0,
	},
	party_state_ipc = {
		last_sent_at = 0,
		send_interval = 0.5,
		ttl = 2.5,
		by_id = {},
	},
	maintenance_state = {
		buffs = {},
		debuffs = {},
		status_snapshot = {},
	},
	action_state = {
		action_start = 0,
		action_end = 0,
		action_delay = 0.1,
		last_action = 0,
		last_acting_state = false,
		cooldown_until = 0,
		lag_timeout = 8.0,
		ja_lag_timeout = 1.0,
		last_send_kind = '',
	},
}

local can_act_statuses = { [0] = true, [1] = true, [5] = true, [85] = true }
local doom_buff_id = nil
local doom_last_item_at = 0
local DOOM_ITEM_COOLDOWN = 1.2
local choose_cure_spell
local BRD_OVERWRITE_CLUSTER_SECONDS = 5
local BRD_OVERWRITE_SAFETY_SECONDS = 6

local debuff_map = {
	['Accuracy Down'] = 'Erase', ['addle'] = 'Erase', ['AGI Down'] = 'Erase', ['Attack Down'] = 'Erase',
	['bind'] = 'Erase', ['Bio'] = 'Erase', ['blindness'] = 'Blindna', ['Burn'] = 'Erase', ['Choke'] = 'Erase',
	['CHR Down'] = 'Erase', ['curse'] = 'Cursna', ['Defense Down'] = 'Erase', ['DEX Down'] = 'Erase',
	['Dia'] = 'Erase', ['disease'] = 'Viruna', ['doom'] = 'Cursna', ['Drown'] = 'Erase', ['Elegy'] = 'Erase',
	['Evasion Down'] = 'Erase', ['Frost'] = 'Erase', ['Inhibit TP'] = 'Erase', ['INT Down'] = 'Erase',
	['Lullaby'] = 'Cure', ['Magic Acc. Down'] = 'Erase', ['Magic Atk. Down'] = 'Erase', ['Magic Def. Down'] = 'Erase',
	['Magic Evasion Down'] = 'Erase', ['Max HP Down'] = 'Erase', ['Max MP Down'] = 'Erase', ['Max TP Down'] = 'Erase',
	['MND Down'] = 'Erase', ['Nocturne'] = 'Erase', ['paralysis'] = 'Paralyna', ['petrification'] = 'Stona',
	['plague'] = 'Viruna', ['poison'] = 'Poisona', ['Rasp'] = 'Erase', ['Requiem'] = 'Erase',
	['Shock'] = 'Erase', ['silence'] = 'Silena', ['slow'] = 'Erase', ['STR Down'] = 'Erase',
	['VIT Down'] = 'Erase', ['weight'] = 'Erase',
}

local status_removal_priority = {
	['addle'] = 2, ['attack_down'] = 3, ['bind'] = 4, ['bio'] = 3, ['blind'] = 4, ['curse'] = 2, ['disease'] = 4,
	['doom'] = 0, ['elegy'] = 1, ['paralysis'] = 1, ['petrification'] = 0, ['plague'] = 4, ['poison'] = 0,
	['silence'] = 1, ['slow'] = 1, ['weight'] = 4,
}

local function normalize_status_removal_key(buff_res)
	return require('uc_scheduler_enemy_effect_utils').normalize_status_removal_key(buff_res)
end

local buff_priority = {
	['Afflatus Solace'] = 0, ['Majesty'] = 0, ['Composure'] = 0, ['Light Arts'] = 0, ['Haste'] = 2,
	['Refresh'] = 2, ['Reraise'] = 3,
}

local maintenance_buff_cache = {
	built = false,
	roll_ids = {},
	song_ids = {},
	indi_ids = {},
	geo_ids = {},
}

local spell_name_cache = { built = false, by_name = {} }
local ja_name_cache = { built = false, by_name = {} }

local buff_runtime = {
	last_queue_debug = '',
}
local function to_roman_numeral(val)
	return require('uc_scheduler_text_utils').to_roman_numeral(val)
end

local function ucfirst(s)
	return require('uc_scheduler_text_utils').ucfirst(s)
end

local function decode_json_escapes(s)
	return require('uc_scheduler_text_utils').decode_json_escapes(s)
end

local function normalize_action_name_like_healbot(text)
	return require('uc_scheduler_text_utils').normalize_action_name_like_healbot(text)
end

local ensure_maintenance_buff_cache
local count_matching_buffs
local ensure_maintenance_state_tables
local canon_name
local action_ready
local PARTY_STATE_IPC_PREFIX = 'ucps'
local DISPell_ATTEMPT_COOLDOWN_S = 3.0

local dispellable_enemy_effect_priority = {
	[33] = 100,   -- Haste
	[580] = 95,   -- Haste II
	[604] = 95,   -- Flurry
	[605] = 96,   -- Flurry II
	[274] = 92,   -- Enfire
	[275] = 92,   -- Enblizzard
	[276] = 92,   -- Enaero
	[277] = 92,   -- Enstone
	[278] = 92,   -- Enthunder
	[279] = 92,   -- Enwater
	[94] = 88,    -- En-spells
	[95] = 88,
	[96] = 88,
	[97] = 88,
	[98] = 88,
	[99] = 88,
	[100] = 80,   -- Barfire
	[101] = 80,   -- Barblizzard
	[102] = 80,   -- Baraero
	[103] = 80,   -- Barstone
	[104] = 80,   -- Barthunder
	[105] = 80,   -- Barwater
	[106] = 80,   -- Barsleep
	[107] = 80,   -- Barpoison
	[108] = 80,   -- Barparalyze
	[109] = 80,   -- Barblind
	[110] = 80,   -- Barsilence
	[111] = 80,   -- Barpetrify
	[112] = 80,   -- Barvirus
	[40] = 78,    -- Protect
	[41] = 78,    -- Shell
	[43] = 82,    -- Refresh
	[116] = 82,   -- Phalanx
	[57] = 76,    -- Defender
	[64] = 76,    -- Boost
	[170] = 84,   -- Sneak
	[171] = 84,   -- Invisible
	[289] = 75,   -- Enmity Boost
	[621] = 75,   -- Majesty
}

local dispellable_enemy_effect_set = {}
for eid, _ in pairs(dispellable_enemy_effect_priority) do
	dispellable_enemy_effect_set[tonumber(eid) or 0] = true
end
local enemy_effect_observed_once = {}

local function danger_weight_to_priority(w)
	return require('uc_scheduler_enemy_effect_utils').danger_weight_to_priority(w)
end

local function load_enemy_dispel_map_from_json()
	local path = windower.addon_path .. 'docs/ffxi_enemy_dispellable_buffs.json'
	local f = io.open(path, 'r')
	if not f then
		error(('unified_scheduler fatal: unable to open dispel map JSON at %s'):format(tostring(path)))
	end
	local raw = f:read('*a')
	f:close()
	if type(raw) ~= 'string' or raw == '' then
		error(('unified_scheduler fatal: dispel map JSON is empty at %s'):format(tostring(path)))
	end

	-- Deterministic text parse for this schema:
	-- each buff record includes "buff_ids": [ ... ] and "danger_weight": N.
	-- This avoids runtime incompatibilities with Windower JSON container variants.
	local imported_count = 0
	local cursor = 1
	local guard = 0
	local guard_max = 250000
	while true do
		guard = guard + 1
		if guard > guard_max then
			error('unified_scheduler fatal: dispel map text parse exceeded safety limit')
		end
		local s1, e1, ids_blob = raw:find('"buff_ids"%s*:%s*%[(.-)%]', cursor)
		if not s1 then
			break
		end
		local tail = raw:sub(e1 + 1, math.min(#raw, e1 + 1200))
		local dw = tonumber(tail:match('"danger_weight"%s*:%s*(%d+)')) or 3
		local prio = danger_weight_to_priority(dw)
		for num in tostring(ids_blob or ''):gmatch('%d+') do
			local id = tonumber(num) or 0
			if id > 0 then
				local existing = tonumber(dispellable_enemy_effect_priority[id]) or 0
				if prio > existing then
					dispellable_enemy_effect_priority[id] = prio
				end
				dispellable_enemy_effect_set[id] = true
				imported_count = imported_count + 1
			end
		end
		cursor = e1 + 1
	end

	if imported_count <= 0 then
		error(('unified_scheduler fatal: dispel map JSON imported zero buff ids from %s'):format(tostring(path)))
	end
end

load_enemy_dispel_map_from_json()

local function now_s()
	if not socket_gettime then
		if not time_source_error_reported then
			time_source_error_reported = true
			if windower and windower.add_to_chat then
				windower.add_to_chat(123, 'UnifiedCombat: fatal scheduler timing error: socket.gettime unavailable.')
			end
		end
		error('unified_scheduler fatal: socket.gettime unavailable')
	end
	return socket_gettime()
end

local function load_targetbar_catalogs_once()
	if tb_spells ~= nil and tb_abilities ~= nil and tb_skills ~= nil then
		return
	end
	local base = tostring(windower.addon_path or '') .. 'TargetBar\\'
	local ok_s, s = pcall(dofile, base .. 'spells.lua')
	if not ok_s or type(s) ~= 'table' then
		error(('unified_scheduler fatal: failed loading TargetBar spells catalog from %s (%s)'):format(base .. 'spells.lua', tostring(s)))
	end
	local ok_a, a = pcall(dofile, base .. 'abilities.lua')
	if not ok_a or type(a) ~= 'table' then
		error(('unified_scheduler fatal: failed loading TargetBar abilities catalog from %s (%s)'):format(base .. 'abilities.lua', tostring(a)))
	end
	local ok_k, k = pcall(dofile, base .. 'skills.lua')
	if not ok_k or type(k) ~= 'table' then
		error(('unified_scheduler fatal: failed loading TargetBar skills catalog from %s (%s)'):format(base .. 'skills.lua', tostring(k)))
	end
	tb_spells = s
	tb_abilities = a
	tb_skills = k
end

local function apply_effect_list_to_target(target_id, effect_list, source, at)
	if type(effect_list) ~= 'table' then
		return
	end
	for i = 1, #effect_list do
		local row = effect_list[i]
		if type(row) == 'table' then
			local eid = tonumber(row[1]) or 0
			if eid > 0 then
				enemy_effect_state_set(target_id, eid, source, at)
			end
		end
	end
end

local function apply_catalog_effects(catalog, action_id, actor_id, target_id, from_player, source, at)
	local id = tonumber(action_id) or 0
	if id <= 0 or type(catalog) ~= 'table' then
		return
	end
	local entry = catalog[id]
	if type(entry) ~= 'table' or #entry == 0 then
		return
	end
	-- Single effect form: { effectId, duration }
	if type(entry[1]) == 'number' then
		local eid = tonumber(entry[1]) or 0
		if eid > 0 then
			enemy_effect_state_set(target_id, eid, source, at)
		end
		return
	end
	-- Multi-effect target form: { {e,d}, {e,d}, ... }
	if type(entry[1]) == 'table' and type(entry[1][1]) == 'number' then
		apply_effect_list_to_target(target_id, entry, source, at)
		return
	end
	-- Dual target/actor form: { { {e,d}, ... }, { {e,d}, ... } }
	if type(entry[1]) == 'table' and type(entry[1][1]) == 'table' then
		apply_effect_list_to_target(target_id, entry[1], source, at)
		if not from_player then
			apply_effect_list_to_target(actor_id, entry[2], source .. '_actor', at)
		end
	end
end

local function set_has(settbl, v)
	return require('uc_scheduler_maintenance_utils').set_has(settbl, v)
end

local function action_state()
	return require('uc_scheduler_action_state').action_state(scheduler)
end

local function action_mark_sent(kind)
	return require('uc_scheduler_action_state').action_mark_sent(scheduler, kind, now_s)
end

local function action_mark_packet_start()
	return require('uc_scheduler_action_state').action_mark_packet_start(scheduler, now_s)
end

local function action_mark_packet_end()
	return require('uc_scheduler_action_state').action_mark_packet_end(scheduler, now_s)
end

local function action_is_acting()
	return require('uc_scheduler_action_state').action_is_acting(scheduler, now_s)
end

local function action_dispatch_blocked()
	return require('uc_scheduler_action_state').action_dispatch_blocked(scheduler, now_s, _G)
end

local function split_pipe(msg)
	return require('uc_scheduler_text_utils').split_pipe(msg)
end

local function split_csv_numbers(s)
	return require('uc_scheduler_text_utils').split_csv_numbers(s)
end

local function current_zone_id()
	return require('uc_scheduler_context_utils').current_zone_id()
end

local function enemy_dispel_diag(msg)
	local s = rawget(_G, 'UC_SETTINGS') or {}
	local dbg = s.debug == true or s.debug == 1 or tostring(s.debug or ''):lower() == 'true'
	if not dbg then
		return
	end
	_G.UC_LAST_SCHED_ACTION = tostring(msg or '')
end

local function enemy_dispel_log(msg)
	local s = rawget(_G, 'UC_SETTINGS') or {}
	local log_on = s.log_def_sched == true or s.log_def_sched == 1 or tostring(s.log_def_sched or ''):lower() == 'true'
	if not log_on then
		return
	end
	local diag = rawget(_G, 'UC_LOG_DIAG')
	if type(diag) == 'function' then
		pcall(diag, 'def_sched', tostring(msg or ''))
	end
end

local function enemy_effect_log_label(effect_id)
	return require('uc_scheduler_enemy_effect_utils').enemy_effect_log_label({
		buffs = res and res.buffs,
	}, effect_id)
end

local function enemy_dispel_attempt_map()
	local p = scheduler.phase1 or {}
	p.enemy_dispel_attempts = p.enemy_dispel_attempts or {}
	scheduler.phase1 = p
	return p.enemy_dispel_attempts
end

local function enemy_effect_state_map()
	local p = scheduler.phase1 or {}
	p.effectiveTargets = p.effectiveTargets or {}
	scheduler.phase1 = p
	return p.effectiveTargets
end

local function enemy_effect_state_set(target_id, effect_id, source, at, duration_s)
	local tid = tonumber(target_id) or 0
	local eid = tonumber(effect_id) or 0
	if tid <= 0 or eid <= 0 then
		return
	end
	local ts = tonumber(at) or now_s()
	local d = tonumber(duration_s) or 0
	local expires_at = 0
	if d > 0 then
		expires_at = ts + d
	end
	local st = enemy_effect_state_map()
	st[tid] = st[tid] or {}
	st[tid][eid] = { seen_at = ts, source = tostring(source or ''), expires_at = expires_at }
end

local function enemy_effect_state_clear(target_id, effect_id)
	local tid = tonumber(target_id) or 0
	local eid = tonumber(effect_id) or 0
	if tid <= 0 or eid <= 0 then
		return false
	end
	local st = enemy_effect_state_map()
	if type(st[tid]) == 'table' and st[tid][eid] ~= nil then
		st[tid][eid] = nil
		return true
	end
	return false
end

local function enemy_effect_state_clear_target(target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return
	end
	local st = enemy_effect_state_map()
	st[tid] = nil
end

local function enemy_effect_state_prune_expired(at)
	local st = enemy_effect_state_map()
	local now = tonumber(at) or now_s()
	for tid, effects in pairs(st) do
		if type(effects) == 'table' then
			for eid, row in pairs(effects) do
				local ex = tonumber(row and row.expires_at) or 0
				if ex > 0 and ex <= now then
					effects[eid] = nil
				end
			end
			local any = false
			for _, _ in pairs(effects) do
				any = true
				break
			end
			if not any then
				st[tid] = nil
			end
		else
			st[tid] = nil
		end
	end
end

local function enemy_effect_state_sweep(max_age_s)
	local st = enemy_effect_state_map()
	local cutoff = now_s() - (tonumber(max_age_s) or 120)
	for tid, effects in pairs(st) do
		local remove_target = false
		local mob = windower.ffxi.get_mob_by_id(tonumber(tid) or 0)
		if not mob or tonumber(mob.spawn_type) ~= 16 or (tonumber(mob.hpp) or 0) <= 0 then
			remove_target = true
		elseif type(effects) ~= 'table' then
			remove_target = true
		else
			for eid, row in pairs(effects) do
				local seen_at = tonumber(row and row.seen_at) or 0
				if seen_at > 0 and seen_at < cutoff then
					effects[eid] = nil
				end
			end
			local has_any = false
			for _, _ in pairs(effects) do
				has_any = true
				break
			end
			if not has_any then
				remove_target = true
			end
		end
		if remove_target then
			st[tid] = nil
		end
	end
end

local function can_attempt_enemy_dispel(action_name, target_id, effect_id, now)
	local key = table.concat({
		tostring(action_name or ''),
		tostring(tonumber(target_id) or 0),
		tostring(tonumber(effect_id) or 0),
	}, ':')
	local attempts = enemy_dispel_attempt_map()
	local last = tonumber(attempts[key]) or 0
	if last > 0 and (now - last) < DISPell_ATTEMPT_COOLDOWN_S then
		return false, key
	end
	return true, key
end

local function mark_enemy_dispel_attempt(key, now)
	if tostring(key or '') == '' then
		return
	end
	local attempts = enemy_dispel_attempt_map()
	attempts[tostring(key)] = tonumber(now) or now_s()
end

local function enemy_dispel_choose_action(target_id)
	local ok_finale, _, kind_finale = action_ready('Magic Finale', target_id)
	if ok_finale and kind_finale == 'spell' then
		return 'Magic Finale'
	end
	local ok_dispel, _, kind_dispel = action_ready('Dispel', target_id)
	if ok_dispel and kind_dispel == 'spell' then
		return 'Dispel'
	end
	return ''
end

local function enemy_dispel_claim_valid(claim_id, party_claim_set)
	return require('uc_scheduler_enemy_effect_utils').enemy_dispel_claim_valid(claim_id, party_claim_set)
end

local raw_enemy_gain_messages = {
	[194] = true,
}

local raw_enemy_remove_messages = {
	[204] = true, [206] = true,
}

local raw_enemy_death_messages = {
	[6] = true, [20] = true, [113] = true, [406] = true, [605] = true, [646] = true,
}

local function is_enemy_mob_id(id)
	local n = tonumber(id) or 0
	if n <= 0 then
		return false
	end
	local m = windower.ffxi.get_mob_by_id(n)
	return m and tonumber(m.spawn_type) == 16 and (tonumber(m.hpp) or 0) > 0
end

local function ingest_enemy_effects_from_raw_action_028(data_or_act)
	load_targetbar_catalogs_once()
	local act = nil
	if type(data_or_act) == 'table' then
		act = data_or_act
	else
		if type(windower) ~= 'table' or type(windower.packets) ~= 'table' or type(windower.packets.parse_action) ~= 'function' then
			error('unified_scheduler fatal: windower.packets.parse_action is unavailable')
		end
		local ok, parsed = pcall(function() return windower.packets.parse_action(data_or_act) end)
		if not ok or type(parsed) ~= 'table' then
			error(('unified_scheduler fatal: failed to parse 0x028 action packet (%s)'):format(tostring(parsed)))
		end
		act = parsed
	end
	local player = windower.ffxi.get_player()
	local player_id = tonumber(player and player.id) or 0
	local actor_id = tonumber(act.actor_id) or 0
	if actor_id <= 0 then return end
	if player_id > 0 and actor_id == player_id then return end
	if type(act.targets) ~= 'table' then return end
	local category = tonumber(act.category) or 0
	local now = now_s()

	local aa_hit_msgs = { [1]=true,[67]=true,[157]=true,[353]=true,[577]=true }
	local aa_igan_msgs = { [15]=true,[31]=true,[70]=true,[354]=true,[355]=true }
	local spell_add_msgs = { [2]=true,[230]=true,[236]=true,[237]=true,[252]=true,[264]=true,[266]=true,[268]=true,[269]=true,[270]=true,[271]=true,[272]=true,[329]=true,[330]=true,[331]=true,[332]=true,[333]=true,[334]=true,[335]=true }
	local spell_remove_msgs = { [83]=true,[341]=true,[342]=true,[343]=true,[344]=true }
	local spell_ign_msgs = { [0]=true,[31]=true,[75]=true,[78]=true,[85]=true,[106]=true,[114]=true,[283]=true,[284]=true }
	local ja_add_msgs = { [100]=true,[102]=true,[110]=true,[115]=true,[116]=true,[117]=true,[118]=true,[119]=true,[120]=true,[121]=true,[126]=true,[131]=true,[134]=true,[143]=true,[148]=true,[149]=true,[266]=true,[285]=true,[286]=true,[287]=true,[304]=true,[317]=true,[319]=true,[452]=true,[519]=true,[529]=true,[667]=true,[668]=true,[669]=true }
	local ws_add_msgs = { [1]=true,[101]=true,[110]=true,[185]=true,[187]=true,[194]=true,[224]=true,[225]=true,[226]=true,[238]=true,[242]=true,[243]=true,[264]=true,[276]=true,[277]=true,[278]=true,[280]=true,[281]=true,[299]=true,[317]=true,[367]=true,[763]=true }
	local ws_ign_msgs = { [15]=true,[31]=true,[188]=true,[189]=true,[282]=true,[283]=true }

	for _, target in ipairs(act.targets) do
		local tid = tonumber(target and target.id) or 0
		if tid > 0 and type(target.actions) == 'table' then
			for i = 1, #target.actions do
				local a = target.actions[i] or {}
				local msg = tonumber(a.message) or tonumber(a.message_id) or 0
				local eid = tonumber(a.param) or 0

				-- TargetBar: paralysis actor lockout detection (message 29/84 on first action)
				if i == 1 and actor_id ~= 0 and (msg == 29 or msg == 84) then
					if dispellable_enemy_effect_set[4] == true then
						enemy_effect_state_set(actor_id, 4, 'raw_028_actor_para', now)
					end
				end

				if category == 1 or category == 2 then
					if aa_hit_msgs[msg] == true then
						enemy_effect_state_clear(tid, 36)
						enemy_effect_state_clear(tid, 66)
						enemy_effect_state_clear(tid, 444)
						enemy_effect_state_clear(tid, 445)
						enemy_effect_state_clear(tid, 446)
						if eid > 0 then enemy_effect_state_clear(tid, 37) end
					elseif msg == 30 then
						enemy_effect_state_clear(tid, 67)
					elseif aa_igan_msgs[msg] ~= true then
						-- keep parity with TargetBar branching; unknowns intentionally not inferred
					end
					if a.has_add_effect then
						local em = tonumber(a.add_effect_message) or 0
						local ee = tonumber(a.add_effect_param) or 0
						if (em == 160 or em == 164) and ee > 0 and dispellable_enemy_effect_set[ee] == true then
							enemy_effect_state_set(tid, ee, ('raw_028_add_effect_msg_%d'):format(em), now)
						end
					end
				elseif category == 4 then
					if spell_add_msgs[msg] == true then
						apply_catalog_effects(tb_spells, tonumber(act.param) or 0, actor_id, tid, false, ('raw_028_spell_msg_%d'):format(msg), now)
					elseif spell_remove_msgs[msg] == true then
						if eid > 0 then enemy_effect_state_clear(tid, eid) end
					elseif msg == 84 then
						if dispellable_enemy_effect_set[4] == true then
							enemy_effect_state_set(tid, 4, 'raw_028_spell_para', now)
						end
					elseif spell_ign_msgs[msg] ~= true then
						-- keep parity branch without inference
					end
				elseif category == 6 or category == 13 or category == 14 or category == 15 then
					if ja_add_msgs[msg] == true then
						apply_catalog_effects(tb_abilities, tonumber(act.param) or 0, actor_id, tid, false, ('raw_028_ja_msg_%d'):format(msg), now)
					end
				elseif category == 3 or category == 11 then
					if ws_add_msgs[msg] == true then
						apply_catalog_effects(tb_skills, tonumber(act.param) or 0, actor_id, tid, false, ('raw_028_ws_msg_%d'):format(msg), now)
					elseif ws_ign_msgs[msg] ~= true then
						-- keep parity branch without inference
					end
				end
			end
		end
	end

	-- TargetBar parity: clear actor disable effects after any successful action packet.
	if actor_id > 0 and (player_id <= 0 or actor_id ~= player_id) then
		enemy_effect_state_clear(actor_id, 10)
		enemy_effect_state_clear(actor_id, 2)
		enemy_effect_state_clear(actor_id, 7)
	end
end

local function encode_party_state_payload()
	local p = windower.ffxi.get_player()
	if not p or not p.name or not p.id or not p.vitals then
		return nil
	end
	local hp = tonumber(p.vitals.hp) or 0
	local hpp = tonumber(p.vitals.hpp) or 100
	local max_hp = tonumber(p.vitals.max_hp) or 0
	local mp = tonumber(p.vitals.mp) or 0
	local max_mp = tonumber(p.vitals.max_mp) or 0
	local mpp = tonumber(p.vitals.mpp) or ((max_mp > 0) and math.floor((mp / max_mp) * 100) or 100)
	local zone = current_zone_id()
	if zone <= 0 then
		return nil
	end
	local buffs = p.buffs or {}
	local bparts = {}
	for i = 1, #buffs do
		local bid = tonumber(buffs[i]) or 0
		if bid > 0 then
			bparts[#bparts + 1] = tostring(bid)
		end
	end
	local bcsv = table.concat(bparts, ',')
	local nm = tostring(p.name):gsub('|', '_')
	return table.concat({
		PARTY_STATE_IPC_PREFIX,
		'1',
		tostring(tonumber(p.id) or 0),
		nm,
		tostring(zone),
		tostring(hp),
		tostring(hpp),
		tostring(max_hp),
		tostring(mp),
		tostring(max_mp),
		tostring(mpp),
		bcsv,
		('%.3f'):format(now_s()),
	}, '|')
end

local function maybe_broadcast_party_state_ipc()
	local ps = scheduler.party_state_ipc or {}
	local now = now_s()
	local last = tonumber(ps.last_sent_at) or 0
	if (now - last) < (tonumber(ps.send_interval) or 1.0) then
		return
	end
	local payload = encode_party_state_payload()
	if not payload then
		return
	end
	ps.last_sent_at = now
	scheduler.party_state_ipc = ps
	windower.send_ipc_message(payload)
end

local function apply_party_state_ipc_message(msg)
	local parts = split_pipe(msg)
	if #parts < 13 then
		return
	end
	if tostring(parts[1]) ~= PARTY_STATE_IPC_PREFIX then
		return
	end
	if tostring(parts[2]) ~= '1' then
		return
	end
	local actor_id = tonumber(parts[3]) or 0
	local actor_name = tostring(parts[4] or '')
	local zone = tonumber(parts[5]) or 0
	if actor_id <= 0 or actor_name == '' or zone <= 0 then
		return
	end
	if zone ~= current_zone_id() then
		return
	end
	local hp = tonumber(parts[6]) or 0
	local hpp = tonumber(parts[7]) or 100
	local max_hp = tonumber(parts[8]) or 0
	local mp = tonumber(parts[9]) or 0
	local max_mp = tonumber(parts[10]) or 0
	local mpp = tonumber(parts[11]) or ((max_mp > 0) and math.floor((mp / max_mp) * 100) or 100)
	local buffs = split_csv_numbers(parts[12] or '')
	local stamp = tonumber(parts[13]) or now_s()
	local ps = scheduler.party_state_ipc or {}
	ps.by_id = ps.by_id or {}
	local prev = ps.by_id[actor_id]
	if prev and tonumber(prev.seq_ts or 0) > stamp then
		return
	end
	ps.by_id[actor_id] = {
		id = actor_id,
		name = actor_name,
		zone = zone,
		hp = hp,
		hpp = hpp,
		max_hp = max_hp,
		mp = mp,
		max_mp = max_mp,
		mpp = mpp,
		buffs = buffs,
		seq_ts = stamp,
		rcv_ts = now_s(),
	}
	scheduler.party_state_ipc = ps
end

local function get_party_state_ipc_entry(member_id, member_name)
	local ps = scheduler.party_state_ipc or {}
	local by_id = ps.by_id or {}
	local e = by_id[tonumber(member_id) or 0]
	if not e then
		return nil
	end
	local ttl = tonumber(ps.ttl) or 4.0
	local now = now_s()
	if (now - (tonumber(e.rcv_ts) or 0)) > ttl then
		by_id[tonumber(member_id) or 0] = nil
		return nil
	end
	if tonumber(e.zone) ~= current_zone_id() then
		return nil
	end
	local nm = tostring(member_name or '')
	if nm ~= '' and tostring(e.name or ''):lower() ~= nm:lower() then
		return nil
	end
	return e
end

local function get_settings()
	return require('uc_scheduler_context_utils').get_settings()
end

local function bool_setting(v, default_value)
	return require('uc_scheduler_numeric_utils').bool_setting(v, default_value)
end

local function resolve_doom_buff_id()
	doom_buff_id = require('uc_scheduler_defensive_utils').resolve_doom_buff_id(res, doom_buff_id)
	return doom_buff_id
end

local function player_has_doom(player)
	return require('uc_scheduler_defensive_utils').player_has_doom(resolve_doom_buff_id, player)
end

local function try_doom_water_emergency(settings)
	if not bool_setting(settings and settings.defensive_enabled, false) then
		return false, nil
	end
	if not bool_setting(settings and settings.defensive_doom_water, false) then
		return false, nil
	end
	local p = windower.ffxi.get_player()
	if not p then
		return false, nil
	end
	if not player_has_doom(p) then
		return false, nil
	end
	windower.ffxi.run(false)
	local now = now_s()
	if now - doom_last_item_at < DOOM_ITEM_COOLDOWN then
		_G.UC_LAST_SCHED_ACTION = '[doom]holding_for_item_reuse'
		return true, 'BLOCK_DOOM_WATER_HOLD'
	end
	doom_last_item_at = now
	windower.send_command('input /item "Holy Water" <me>')
	_G.UC_LAST_SCHED_ACTION = '[doom]holy_water'
	return true, 'BLOCK_DOOM_WATER'
end

local function build_partner_target_set(settings)
	return require('uc_scheduler_context_utils').build_partner_target_set({
		bool_setting = bool_setting,
		uc_partner_list = uc_partner_list,
	}, settings)
end

local maintenance_blocked_zone_names = {
	["southern san d'oria"] = true,
	["northern san d'oria"] = true,
	["port san d'oria"] = true,
	["chateau d'oraguille"] = true,
	["bastok mines"] = true,
	["bastok markets"] = true,
	["port bastok"] = true,
	["metalworks"] = true,
	["windurst waters"] = true,
	["windurst walls"] = true,
	["port windurst"] = true,
	["windurst woods"] = true,
	["heavens tower"] = true,
	["ru'lude gardens"] = true,
	["upper jeuno"] = true,
	["lower jeuno"] = true,
	["port jeuno"] = true,
	["norg"] = true,
	["selbina"] = true,
	["mhaura"] = true,
	["kazham"] = true,
	["rabao"] = true,
	["aht urhgan whitegate"] = true,
	["nashmau"] = true,
	["tavnazian safehold"] = true,
	["western adoulin"] = true,
	["eastern adoulin"] = true,
}

local function is_city_zone_for_maintenance()
	return require('uc_scheduler_context_utils').is_city_zone_for_maintenance(maintenance_blocked_zone_names)
end

local function log_ja_sched(msg)
	if rawget(_G, 'UC_LOG_JA_SCHED') ~= true then
		return
	end
	if type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
		pcall(_G.UC_LOG_DIAG, 'ja_sched', msg)
	end
end

local function log_tank_sched(msg)
	if rawget(_G, 'UC_LOG_TANK_SCHED') ~= true then
		return
	end
	if type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
		pcall(_G.UC_LOG_DIAG, 'tank_sched', msg)
	end
end

local function log_combat_sched(msg)
	if rawget(_G, 'UC_LOG_COMBAT_SCHED') ~= true then
		return
	end
	if type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
		pcall(_G.UC_LOG_DIAG, 'combat_sched', msg)
	end
end

local function log_def_sched(msg)
	if rawget(_G, 'UC_LOG_DEF_SCHED') ~= true then
		return
	end
	if type(rawget(_G, 'UC_LOG_DIAG')) == 'function' then
		pcall(_G.UC_LOG_DIAG, 'def_sched', msg)
	end
	local s = get_settings()
	if not bool_setting(s and s.debug, false) then
		return
	end
	local m = tostring(msg or '')
	local verbose = bool_setting(rawget(_G, 'UC_DEF_SCHED_VERBOSE_LOG'), false)
	if not verbose then
		local keep = (
			m:find('CURE_ACCEPT', 1, true) or
			m:find('BUFF_ACCEPT', 1, true) or
			m:find('BUFF_SKIP', 1, true) or
			m:find('MAINT_', 1, true) or
			m:find('MAINT_COR_', 1, true) or
			m:find('DEF_CFG_SET_OP', 1, true) or
			m:find('DEF_CFG_RECV', 1, true) or
			m:find('DEF_CFG_APPLY', 1, true)
		)
		if not keep then
			return
		end
	end
	local p = windower.ffxi.get_player()
	local name = tostring((p and p.name) or 'unknown'):lower()
	local path = windower.addon_path .. 'data/logs/' .. name .. '_def_sched.log'
	local fh = io.open(path, 'a')
	if fh then
		fh:write(('%s	%s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), m))
		fh:close()
	end
end

local diag_init = {
	ja_sched = false,
	ja_debug = false,
	def_sched = false,
	combat_sched = false,
}

local p1_apply_face_to_target

local function ensure_diag_logs_initialized()
	local s = get_settings()
	if not bool_setting(s and s.debug, false) then
		return
	end
	if type(rawget(_G, 'UC_LOG_DIAG')) ~= 'function' then
		return
	end
	if rawget(_G, 'UC_LOG_JA_SCHED') == true and not diag_init.ja_sched then
		diag_init.ja_sched = true
		pcall(_G.UC_LOG_DIAG, 'ja_sched', 'JA_SCHED_LOG_INIT')
	end
	if rawget(_G, 'UC_LOG_JA_DEBUG') == true and not diag_init.ja_debug then
		diag_init.ja_debug = true
		pcall(_G.UC_LOG_DIAG, 'ja_debug', 'JA_DEBUG_LOG_INIT')
	end
	if rawget(_G, 'UC_LOG_DEF_SCHED') == true and not diag_init.def_sched then
		diag_init.def_sched = true
		pcall(_G.UC_LOG_DIAG, 'def_sched', 'DEF_SCHED_LOG_INIT')
	end
	if rawget(_G, 'UC_LOG_COMBAT_SCHED') == true and not diag_init.combat_sched then
		diag_init.combat_sched = true
		pcall(_G.UC_LOG_DIAG, 'combat_sched', 'COMBAT_SCHED_LOG_INIT')
	end
end

local function run_movement_coordinator_tick()
	local s = get_settings()
	local now = now_s()
	local p = windower.ffxi.get_player()
	local status = tonumber(p and p.status) or -1
	local engaged = (status == 1)
	local combat_participant = false
	if type(rawget(_G, 'UC_IsCombatParticipant')) == 'function' then
		combat_participant = (_G.UC_IsCombatParticipant(s) == true)
	end
	local movement_participant = false
	if type(rawget(_G, 'UC_IsMovementParticipant')) == 'function' then
		movement_participant = (_G.UC_IsMovementParticipant(s) == true)
	end
	local mode = 'OUT_OF_COMBAT'
	if engaged and combat_participant and movement_participant then
		mode = 'IN_COMBAT_FIGHTER'
	elseif engaged then
		mode = 'IN_COMBAT_NON_FIGHTER'
	end
	_G.UC_MOVEMENT_MODE = mode
	_G.UC_MOVEMENT_BLOCK_REASON = ''
	-- Facing is coordinator-owned and evaluated every movement tick.
	-- C5 rule is enforced inside p1_apply_face_to_target (valid live combat mob only).
	do
		local t = windower.ffxi.get_mob_by_target('t')
		local tid = tonumber(t and t.id) or 0
		if tid > 0 then
			p1_apply_face_to_target(s, tid)
		end
	end
	local freeze_prep_until = tonumber(rawget(_G, 'UC_MOVE_FREEZE_PREP_UNTIL')) or 0
	if now < freeze_prep_until then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_CAST_FREEZE_PREP'
		windower.ffxi.run(false)
		return false, 'MOVE_COORD_CAST_FREEZE_PREP'
	end
	local pull_cast_hold_until = tonumber(rawget(_G, 'UC_PULL_CAST_HOLD_UNTIL')) or 0
	if now < pull_cast_hold_until then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_PULL_CAST_HOLD'
		windower.ffxi.run(false)
		return false, 'MOVE_COORD_PULL_CAST_HOLD'
	end
	if rawget(_G, 'UC_PULL_SPELL_WAITING') == true then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_PULL_SPELL_WAIT'
		windower.ffxi.run(false)
		return false, 'MOVE_COORD_PULL_SPELL_WAIT'
	end
	if not bool_setting(s and s.scheduler_dark_launch_movement, false) then
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_TOGGLE_OFF'
		return false, 'MOVE_COORD_TOGGLE_OFF'
	end
	-- Keep fight-follow hold semantics only for active combat participants.
	if engaged and combat_participant then
		local hold_s = tonumber(s and s.fight_follow_hold_s) or 8.0
		if hold_s < 0 then
			hold_s = 0
		elseif hold_s > 30 then
			hold_s = 30
		end
		_G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL = now_s() + hold_s
	end
	if not movement_participant then
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_NOT_PARTICIPANT'
		return false, 'MOVE_COORD_NOT_PARTICIPANT'
	end
	if mode == 'IN_COMBAT_NON_FIGHTER' then
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_NON_FIGHTER_ENGAGED'
		return false, 'MOVE_COORD_NON_FIGHTER_ENGAGED'
	end
	if not combat_core or type(combat_core.apply_movement_for_scheduler) ~= 'function' then
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_CORE_MISSING'
		return false, 'MOVE_COORD_CORE_MISSING'
	end
	if not p then
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_NO_PLAYER'
		return false, 'MOVE_COORD_NO_PLAYER'
	end
	-- Do not move while spellcasting/channeling.
	if status == 4 then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_CASTING_STATUS'
		return false, 'MOVE_COORD_CASTING_STATUS'
	end
	local ast = action_state()
	if tostring(ast.last_send_kind or '') == 'spell' and now < (tonumber(ast.cooldown_until) or 0) then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_CAST_FREEZE_COOLDOWN'
		return false, 'MOVE_COORD_CAST_FREEZE_COOLDOWN'
	end
	if action_is_acting() and tostring(ast.last_send_kind or '') == 'spell' then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_CASTING_ACTION'
		return false, 'MOVE_COORD_CASTING_ACTION'
	end
	local ok = false
	local ok_call, call_err = pcall(function()
		ok = combat_core.apply_movement_for_scheduler(s) == true
	end)
	if not ok_call then
		_G.UC_LAST_SCHED_ACTION = '[move]error:' .. tostring(call_err or '')
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_ERROR'
		return false, 'MOVE_COORD_ERROR'
	end
	if not ok then
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_NOOP'
		return false, 'MOVE_COORD_NOOP'
	end
	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.40
	return true, 'MOVE_COORD_APPLIED'
end

local function tank_enmity_diag(reason, selected, extra)
	local r = tostring(reason or '')
	local action = tostring(selected and selected.action_name or '')
	local target = tostring(selected and selected.target_name or '')
	local tid = tonumber(selected and selected.target_id) or 0
	local line = ('%s action="%s" target="%s" tid=%d'):format(r, action, target, tid)
	if extra and extra ~= '' then
		line = line .. ' ' .. tostring(extra)
	end
	_G.UC_TANK_ENMITY_BLOCK = line
	log_tank_sched(line)
end

local SCHED_RANGE_MULT = {
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
	return require('uc_scheduler_action_metadata').action_effective_range({
		SCHED_RANGE_MULT = SCHED_RANGE_MULT,
	}, raw_range)
end

local function ja_targets_enemy(ja)
	return require('uc_scheduler_action_predicates').ja_targets_enemy(ja)
end

local function normalize_angle_rad(a)
	return require('uc_scheduler_geometry').normalize_angle_rad(a)
end

local function target_is_in_front_arc(target, arc)
	return require('uc_scheduler_geometry').target_is_in_front_arc(target, arc)
end

local function ja_requires_engaged_front(name, ja)
	return require('uc_scheduler_action_predicates').ja_requires_engaged_front(name, ja)
end

local function get_party_members()
	local out = {}
	local party = windower.ffxi.get_party()
	local player = windower.ffxi.get_player()
	local self_id = player and player.id or 0
	if type(party) ~= 'table' then
		return out
	end
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, key in ipairs(keys) do
		local entry = party[key]
		if entry and entry.mob and entry.mob.id and entry.mob.id ~= 0 then
			local is_self = entry.mob.id == self_id
			local ipc = get_party_state_ipc_entry(entry.mob.id, entry.mob.name)
			local source = 'party'
			local hp = tonumber(entry.hp) or 0
			local hpp = tonumber(entry.hpp) or 100
			local mp = tonumber(entry.mp) or 0
			local mpp = tonumber(entry.mpp) or 100
			local max_mp = tonumber(entry.max_mp) or 0
			local max_hp = 0
			if hp > 0 and hpp > 0 then
				max_hp = math.floor((hp / hpp) * 100 + 0.5)
			end
			local buffs = entry.buffs or {}
			-- Source of truth for self state must be local player object, not party snapshot/IPC.
			if is_self and player and player.vitals then
				source = 'self_local'
				hp = tonumber(player.vitals.hp) or hp
				hpp = tonumber(player.vitals.hpp) or hpp
				mp = tonumber(player.vitals.mp) or mp
				mpp = tonumber(player.vitals.mpp) or mpp
				max_mp = tonumber(player.vitals.max_mp) or max_mp
				if tonumber(player.vitals.max_hp) and tonumber(player.vitals.max_hp) > 0 then
					max_hp = tonumber(player.vitals.max_hp)
				elseif hp > 0 and hpp > 0 then
					max_hp = math.floor((hp / hpp) * 100 + 0.5)
				end
				buffs = player.buffs or buffs
			end
			if ipc then
				source = is_self and 'self_local' or 'ipc'
				hp = tonumber(ipc.hp) or hp
				hpp = tonumber(ipc.hpp) or hpp
				max_hp = tonumber(ipc.max_hp) or max_hp
				mp = tonumber(ipc.mp) or mp
				max_mp = tonumber(ipc.max_mp) or max_mp
				mpp = tonumber(ipc.mpp) or mpp
				buffs = ipc.buffs or buffs
			end
			-- Never let IPC override local self authoritative state.
			if is_self and player and player.vitals then
				source = 'self_local'
				hp = tonumber(player.vitals.hp) or hp
				hpp = tonumber(player.vitals.hpp) or hpp
				mp = tonumber(player.vitals.mp) or mp
				mpp = tonumber(player.vitals.mpp) or mpp
				max_mp = tonumber(player.vitals.max_mp) or max_mp
				if tonumber(player.vitals.max_hp) and tonumber(player.vitals.max_hp) > 0 then
					max_hp = tonumber(player.vitals.max_hp)
				elseif hp > 0 and hpp > 0 then
					max_hp = math.floor((hp / hpp) * 100 + 0.5)
				end
				buffs = player.buffs or buffs
			end
			out[#out + 1] = {
				id = entry.mob.id,
				name = entry.mob.name,
				is_self = is_self,
				spawn_type = entry.mob.spawn_type,
				hpp = hpp,
				hp = hp,
				max_hp = max_hp,
				mp = mp,
				mpp = mpp,
				max_mp = max_mp,
				buffs = buffs,
				source = source,
			}
		end
	end
	return out
end

local function p1_build_party_id_set()
	return require('uc_scheduler_context_utils').p1_build_party_id_set({
		get_party_members = get_party_members,
	})
end

local function p1_prime_unclaimed_party_aggressive_ok(settings, mob, party_ids)
	if not bool_setting(settings and settings.prime, false) then
		return false
	end
	if not mob or (tonumber(mob.claim_id) or 0) ~= 0 then
		return false
	end
	if (tonumber(mob.status) or 0) ~= 1 then
		return false
	end
	-- Prime should only treat unclaimed mobs as aggressive-to-party based on
	-- recent packet-derived mob->target evidence. Runtime target fields are too
	-- unreliable in this environment.
	local function resolve_recent_packet_target_id(m)
		local amap = rawget(_G, 'UC_MOB_LAST_ACTION_TARGETS')
		local rec = type(amap) == 'table' and amap[tonumber(m and m.id) or 0] or nil
		if type(rec) ~= 'table' then
			return 0
		end
		local age = now_s() - (tonumber(rec.at) or 0)
		if age < 0 or age > 5.0 then
			return 0
		end
		return tonumber(rec.target_id) or 0
	end
	local tid = resolve_recent_packet_target_id(mob)
	if tid > 0 then
		return party_ids[tid] == true
	end
	return false
end

local function has_buff(buff_list, buff_id)
	return require('uc_scheduler_defensive_utils').has_buff(buff_list, buff_id)
end

local function in_party_cast_range(member)
	if not member or not member.id then
		return false
	end
	if member.is_self then
		return true
	end
	local m = windower.ffxi.get_mob_by_id(member.id)
	if not m or m.distance == nil then
		return false
	end
	-- Match HealBot casting window behavior.
	return m.distance:sqrt() < 20.9
end

local function get_spell_resource(name)
	if not name or name == '' then
		return nil
	end
	local function normalize_label(s)
		return decode_json_escapes(tostring(s or ''))
			:gsub('[\226\128\153\226\128\152`´]', "'")
			:gsub('%s+', ' ')
			:gsub('^%s+', '')
			:gsub('%s+$', '')
	end
	local want = normalize_label(name)
	local healbot_norm = normalize_action_name_like_healbot(want)
	if healbot_norm ~= '' then
		want = healbot_norm
	end
	local function ensure_spell_cache()
		if spell_name_cache.built then return end
		local map = {}
		for _, v in pairs(res.spells or {}) do
			local en = normalize_label(v and v.en or '')
			if en ~= '' then
				map[en:lower()] = v
				local en_norm = normalize_action_name_like_healbot(en)
				if en_norm ~= '' then
					map[en_norm:lower()] = v
				end
			end
		end
		spell_name_cache.by_name = map
		spell_name_cache.built = true
	end
	local sp = res.spells:with('en', want)
	if sp then
		return sp
	end
	local wl = want:lower()
	ensure_spell_cache()
	sp = spell_name_cache.by_name[wl]
	if sp then return sp end
	-- Last chance: direct lowercase resource map.
	local lc = _libs and _libs.lor and _libs.lor.resources and _libs.lor.resources.lc_res
	if lc and lc.spells and lc.spells[wl] then
		return lc.spells[wl]
	end
	return nil
end

local function spell_known_flag(v)
	return require('uc_scheduler_action_metadata').spell_known_flag(v)
end

local function job_id_by_short(short_name)
	return require('uc_scheduler_action_metadata').job_id_by_short({
		jobs = res and res.jobs,
	}, short_name)
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

local function spell_known_and_usable(sp)
	if type(sp) ~= 'table' or not sp.id then
		return false, 'BLOCK_DEFENSIVE_UNKNOWN_SPELL'
	end
	local known = windower.ffxi.get_spells() or {}
	if not spell_known_flag(known[sp.id]) then
		return false, 'BLOCK_DEFENSIVE_NOT_LEARNED'
	end
	if not spell_usable_by_current_job(sp) then
		return false, 'BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL'
	end
	return true, ''
end

local function get_ja_resource(name)
	if not name or name == '' then
		return nil
	end
	local function normalize_label(s)
		return decode_json_escapes(tostring(s or ''))
			:gsub('[\226\128\153\226\128\152`´]', "'")
			:gsub('%s+', ' ')
			:gsub('^%s+', '')
			:gsub('%s+$', '')
	end
	local want = normalize_label(name)
	local healbot_norm = normalize_action_name_like_healbot(want)
	if healbot_norm ~= '' then
		want = healbot_norm
	end
	local function ensure_ja_cache()
		if ja_name_cache.built then return end
		local map = {}
		for _, v in pairs(res.job_abilities or {}) do
			local en = normalize_label(v and v.en or '')
			if en ~= '' then
				map[en:lower()] = v
				local en_norm = normalize_action_name_like_healbot(en)
				if en_norm ~= '' then
					map[en_norm:lower()] = v
				end
			end
		end
		ja_name_cache.by_name = map
		ja_name_cache.built = true
	end
	local ja = res.job_abilities:with('en', want)
	if ja then
		return ja
	end
	local wl = want:lower()
	ensure_ja_cache()
	ja = ja_name_cache.by_name[wl]
	if ja then return ja end
	local lc = _libs and _libs.lor and _libs.lor.resources and _libs.lor.resources.lc_res
	if lc and lc.job_abilities and lc.job_abilities[wl] then
		return lc.job_abilities[wl]
	end
	return nil
end

local function action_status_id(name)
	return require('uc_scheduler_action_metadata').action_status_id({
		get_spell_resource = get_spell_resource,
		get_ja_resource = get_ja_resource,
	}, name)
end

local function spell_ready(name)
	local sp = get_spell_resource(name)
	if not sp then
		return false, 'BLOCK_DEFENSIVE_UNKNOWN_SPELL'
	end
	local known_ok, known_reason = spell_known_and_usable(sp)
	if not known_ok then
		return false, known_reason
	end
	local recasts = windower.ffxi.get_spell_recasts() or {}
	if (recasts[sp.recast_id] or 0) > 0 then
		return false, 'BLOCK_DEFENSIVE_RECAST'
	end
	local p = windower.ffxi.get_player()
	if not p or not p.vitals then
		return false, 'BLOCK_DEFENSIVE_NO_PLAYER'
	end
	if (p.vitals.mp or 0) < (sp.mp_cost or 0) then
		return false, 'BLOCK_DEFENSIVE_NO_MP'
	end
	return true, ''
end

local cure_by_tier = {
	[1] = { name = 'Cure', id = 1, potency = 120 },
	[2] = { name = 'Cure II', id = 2, potency = 260 },
	[3] = { name = 'Cure III', id = 3, potency = 520 },
	[4] = { name = 'Cure IV', id = 4, potency = 860 },
	[5] = { name = 'Cure V', id = 5, potency = 1300 },
	[6] = { name = 'Cure VI', id = 6, potency = 1700 },
}

local function estimate_missing_hp(member)
	return require('uc_scheduler_defensive_utils').estimate_missing_hp(member)
end

local function available_cure_tier_max()
	local highest = 0
	for tier = 1, 6 do
		local c = cure_by_tier[tier]
		if c and spell_ready(c.name) then
			highest = tier
		end
	end
	return highest
end

local function cure_tier_for_missing_hp(hp_missing, max_tier)
	return require('uc_scheduler_defensive_utils').cure_tier_for_missing_hp(hp_missing, max_tier, cure_by_tier)
end

local function get_usable_cure_from_tier(orig_tier, min_tier)
	local start_tier = math.max(1, math.min(tonumber(orig_tier) or 1, 6))
	local floor_tier = math.max(1, math.min(tonumber(min_tier) or 1, 6))
	if start_tier < floor_tier then
		return nil
	end
	local tier = start_tier
	while tier >= floor_tier do
		local c = cure_by_tier[tier]
		if c then
			local ok = spell_ready(c.name)
			if ok then
				return c.name, tier
			end
		end
		tier = tier - 1
	end
	return nil
end

local function dedupe_numeric_ids(ids)
	return require('uc_scheduler_maintenance_utils').dedupe_numeric_ids(ids)
end

local function ja_ready(name, target_id)
	local ja = get_ja_resource(name)
	if not ja then
		return false, 'BLOCK_DEFENSIVE_UNKNOWN_JA'
	end
	local abil = windower.ffxi.get_abilities() or {}
	local owns = false
	for _, id in ipairs(abil.job_abilities or {}) do
		if tonumber(id) == tonumber(ja.id) then
			owns = true
			break
		end
	end
	if not owns then
		return false, 'BLOCK_DEFENSIVE_JA_NOT_OWNED'
	end
	local p = windower.ffxi.get_player()
	local status = tonumber(p and p.status) or 0
	if status == 3 then
		return false, 'BLOCK_ACTION_STATUS3'
	end
	if tostring(name or ''):lower() == 'chivalry' then
		local tp = tonumber(((p or {}).vitals or {}).tp) or 0
		if tp < 2000 then
			return false, 'BLOCK_CHIVALRY_TP_LOW'
		end
		local mp = tonumber(((p or {}).vitals or {}).mp) or 0
		local mmp = tonumber(((p or {}).vitals or {}).max_mp) or 0
		local mp_pct = (mmp > 0) and ((mp / mmp) * 100.0) or 100.0
		if mp_pct >= 50 then
			return false, 'BLOCK_CHIVALRY_MP_TOO_HIGH'
		end
	end
	local requires_engaged_front = ja_requires_engaged_front(name, ja)
	if requires_engaged_front and status ~= 1 then
		return false, 'BLOCK_JA_REQUIRES_ENGAGED'
	end
	if ja_targets_enemy(ja) then
		local target = nil
		local tid = tonumber(target_id) or 0
		if tid > 0 then
			target = windower.ffxi.get_mob_by_id(tid)
		end
		if not target then
			target = windower.ffxi.get_mob_by_target('t')
		end
		if not target or not target.valid_target or tonumber(target.spawn_type) ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
			return false, 'BLOCK_JA_BAD_TARGET'
		end
		local r = action_effective_range(ja.range)
		if r > 0 then
			local d = target.distance and target.distance:sqrt() or 999
			if d > r then
				return false, 'BLOCK_JA_OUT_OF_RANGE'
			end
		end
		if requires_engaged_front and not target_is_in_front_arc(target, math.pi / 2) then
			return false, 'BLOCK_JA_NOT_FRONT'
		end
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	if (recasts[ja.recast_id] or 0) > 0 then
		return false, 'BLOCK_DEFENSIVE_RECAST'
	end
	return true, ''
end

action_ready = function(name, target_id)
	local sp = get_spell_resource(name)
	if sp then
		local ok, reason = spell_ready(name)
		return ok, reason, 'spell'
	end
	local ja = get_ja_resource(name)
	if ja then
		local ok, reason = ja_ready(name, target_id)
		return ok, reason, 'ja'
	end
	return false, 'BLOCK_DEFENSIVE_UNKNOWN_ACTION', 'none'
end

local function action_target_mode(action_name, action_kind)
	return require('uc_scheduler_action_metadata').action_target_mode({
		get_spell_resource = get_spell_resource,
		get_ja_resource = get_ja_resource,
	}, action_name, action_kind)
end

local function build_action_command(action_name, action_kind, target_member)
	return require('uc_scheduler_command_builder').build_action_command({
		action_target_mode = action_target_mode,
	}, action_name, action_kind, target_member)
end

local function member_priority(member)
	return require('uc_scheduler_defensive_utils').member_priority(member)
end

local function pri_default(player_prio, action_prio)
	return require('uc_scheduler_defensive_utils').pri_default(player_prio, action_prio)
end

local function danger_level(hpp)
	return require('uc_scheduler_defensive_utils').danger_level(hpp)
end

local function cure_better(c1, c2)
	return require('uc_scheduler_defensive_utils').cure_better(c1, c2)
end

local function debuff_spell_for_buff_id(buff_id)
	return require('uc_scheduler_defensive_utils').debuff_spell_for_buff_id(res, buff_id)
end

local function split_actions(raw)
	return require('uc_scheduler_maintenance_utils').split_actions(raw)
end

local function family_key(member_name, buff_id)
	return require('uc_scheduler_proposal_keys').family_key(member_name, buff_id)
end

local function attempt_key(kind, member_name, action_name)
	return require('uc_scheduler_proposal_keys').attempt_key(kind, member_name, action_name)
end

local function attempt_allowed(kind, member_name, action_name, now, min_gap)
	local key = attempt_key(kind, member_name, action_name)
	local last = scheduler.attempted[key]
	if last and (now - last) < (min_gap or 3) then
		return false
	end
	return true
end

local function mark_attempt(kind, member_name, action_name, now)
	local key = attempt_key(kind, member_name, action_name)
	scheduler.attempted[key] = now
end

local function count_buff_occurrences(buffs)
	return require('uc_scheduler_maintenance_utils').count_buff_occurrences(buffs)
end

local function is_bard_song(spell_name)
	return require('uc_scheduler_defensive_utils').is_bard_song(spell_name, get_spell_resource)
end

local function action_duration_seconds(name, default_seconds)
	return require('uc_scheduler_action_metadata').action_duration_seconds({
		get_spell_resource = get_spell_resource,
		get_ja_resource = get_ja_resource,
	}, name, default_seconds)
end

local function set_recent_gain(member_name, buff_id, spell_name, now)
	scheduler.recent_gain[family_key(member_name, buff_id)] = { name = spell_name, ts = now }
end

local function get_recent_gain(member_name, buff_id, max_age, now)
	local info = scheduler.recent_gain[family_key(member_name, buff_id)]
	if info and (now - (info.ts or 0)) <= (max_age or 20) then
		return info.name
	end
	return nil
end

local function family_tokens_for(member_name, buff_id)
	local k = family_key(member_name, buff_id)
	local tokens = scheduler.family_tokens[k]
	if type(tokens) ~= 'table' then
		tokens = {}
		scheduler.family_tokens[k] = tokens
	end
	return tokens
end


local function build_defensive_candidates()
	local s = get_settings()
	local members = get_party_members()
	local out = {
		cure = nil,
		debuff = nil,
		buff = nil,
		overwrite = nil,
	}
	local now = now_s()
	local ignore_trusts = bool_setting(s.def_heal_ignore_trusts, true)

	if bool_setting(s.defensive_buff_enabled, true) then
		log_def_sched(('BUFF_SCAN mode=%s buffs="%s" targeted="%s" members=%d'):format(
			bool_setting(s.defensive_buff_self_only, true) and 'self_only' or 'party',
			tostring(s.defensive_buffs or ''),
			tostring(s.defensive_targeted_buffs or ''),
			#members
		))
		for _, m in ipairs(members or {}) do
			log_def_sched(('BUFF_MEMBER name="%s" self=%s source=%s hpp=%d buffs=%d'):format(
				tostring(m.name or '?'),
				tostring(m.is_self == true),
				tostring(m.source or '?'),
				tonumber(m.hpp) or 0,
				#(m.buffs or {})
			))
		end
		scheduler.maintenance_scan = scheduler.maintenance_scan or { next_at = 0, buff_pick = nil }
		local scan = scheduler.maintenance_scan
		local picked = nil
		if now >= (tonumber(scan.next_at) or 0) then
			local buff_members = {}
			for _, m in ipairs(members or {}) do
				-- Do not include trusts in party buff maintenance targeting.
				if not (tonumber(m and m.spawn_type) == 14 and not (m and m.is_self)) then
					buff_members[#buff_members + 1] = m
				end
			end
			picked = hb_buff_maint.choose(s, buff_members, {
				bool_setting = bool_setting,
				in_party_cast_range = in_party_cast_range,
				action_ready = action_ready,
				get_spell_resource = get_spell_resource,
				get_ja_resource = get_ja_resource,
				is_bard_song = is_bard_song,
				attempt_allowed = attempt_allowed,
				member_priority = member_priority,
				pri_default = pri_default,
				buff_priority = buff_priority,
				last_overwrite = scheduler.last_overwrite,
				log_debug = log_def_sched,
			})
			scan.buff_pick = picked
			scan.next_at = now + 1.0
		else
			picked = scan.buff_pick
		end
		if picked and picked.spell and picked.target then
			log_def_sched(('BUFF_PICK type=%s action="%s" target="%s" reason=%s'):format(
				tostring(picked.type or ''),
				tostring(picked.spell or ''),
				tostring((picked.target and picked.target.name) or ''),
				tostring(picked.reason or '')
			))
			if picked.type == 'overwrite' then
				out.overwrite = picked
			else
				out.buff = picked
			end
		else
			log_def_sched('BUFF_PICK none')
		end
	else
		if scheduler.maintenance_scan then
			scheduler.maintenance_scan.buff_pick = nil
		end
	end

	for _, m in ipairs(members) do
		if not (ignore_trusts and tonumber(m.spawn_type) == 14) then
			local active_counts = count_buff_occurrences(m.buffs or {})
			if m.hpp > 0 and m.hpp < 95 and bool_setting(s.defensive_cure_enabled, true) and in_party_cast_range(m) then
			local missing_hp = estimate_missing_hp(m)
			local missing_gate = tonumber(s.def_heal_min_missing_hp) or 250
			missing_gate = math.max(0, missing_gate)
			log_def_sched(('CURE_CANDIDATE target="%s" hp=%d hpp=%d missing=%d gate=%d in_range=1'):format(
				tostring(m.name or '?'),
				tonumber(m.hp) or 0,
				tonumber(m.hpp) or 0,
				tonumber(missing_hp) or 0,
				tonumber(missing_gate) or 0
			))
			if missing_hp >= missing_gate then
			local spell = choose_cure_spell(m)
			if not spell then
				log_def_sched(('CURE_REJECT target="%s" reason=NO_SPELL hp=%d hpp=%d missing=%d gate=%d'):format(
					tostring(m.name or '?'),
					tonumber(m.hp) or 0,
					tonumber(m.hpp) or 0,
					tonumber(missing_hp) or 0,
					tonumber(missing_gate) or 0
				))
			end
			if spell then
				local ready = spell_ready(spell)
				if not ready then
					log_def_sched(('CURE_REJECT target="%s" reason=SPELL_NOT_READY spell="%s" hp=%d hpp=%d missing=%d gate=%d'):format(
						tostring(m.name or '?'),
						tostring(spell),
						tonumber(m.hp) or 0,
						tonumber(m.hpp) or 0,
						tonumber(missing_hp) or 0,
						tonumber(missing_gate) or 0
					))
				end
				if ready and attempt_allowed('cure', m.name, spell, now, 2.5) then
					local c = {
						type = 'cure',
						spell = spell,
						target = m,
						member_prio = member_priority(m),
						danger = danger_level(m.hpp),
						prio = member_priority(m),
					}
					if cure_better(c, out.cure) then
						out.cure = c
						log_def_sched(('CURE_ACCEPT target="%s" spell="%s" hp=%d hpp=%d missing=%d gate=%d prio=%0.2f'):format(
							tostring(m.name or '?'),
							tostring(spell),
							tonumber(m.hp) or 0,
							tonumber(m.hpp) or 0,
							tonumber(missing_hp) or 0,
							tonumber(missing_gate) or 0,
							tonumber(c.prio) or 0
						))
					end
				elseif ready then
					log_def_sched(('CURE_REJECT target="%s" reason=ATTEMPT_THROTTLE spell="%s" hp=%d hpp=%d missing=%d gate=%d'):format(
						tostring(m.name or '?'),
						tostring(spell),
						tonumber(m.hp) or 0,
						tonumber(m.hpp) or 0,
						tonumber(missing_hp) or 0,
						tonumber(missing_gate) or 0
					))
				end
			end
			else
				log_def_sched(('CURE_REJECT target="%s" reason=MISSING_BELOW_GATE hp=%d hpp=%d missing=%d gate=%d'):format(
					tostring(m.name or '?'),
					tonumber(m.hp) or 0,
					tonumber(m.hpp) or 0,
					tonumber(missing_hp) or 0,
					tonumber(missing_gate) or 0
				))
			end
			end
			if bool_setting(s.defensive_na_enabled, true) and in_party_cast_range(m) then
			local best = nil
			for _, buff_id in ipairs(m.buffs or {}) do
				local debuff = res.buffs[buff_id]
				local debuff_en = debuff and debuff.en or ''
				local na_spell = debuff_map[debuff_en] or debuff_spell_for_buff_id(buff_id)
				if na_spell then
					local ready = action_ready(na_spell)
					if ready and attempt_allowed('debuff', m.name, na_spell, now, 3) then
						local key = normalize_status_removal_key(debuff)
						local action_prio = status_removal_priority[key] or 5
						if (not best) or action_prio < best.action_prio then
							best = {
								spell = na_spell,
								buff_id = buff_id,
								action_prio = action_prio,
							}
						end
					end
				end
			end
			if best then
				local p = member_priority(m)
				local d = {
					type = 'debuff',
					spell = best.spell,
					target = m,
					buff_id = best.buff_id,
					prio = pri_default(p, best.action_prio),
				}
				if not out.debuff or d.prio < out.debuff.prio then
					out.debuff = d
				end
			end
			end
		end
	end
	return out
end

local function parse_status_snapshot_063(data)
	return require('uc_scheduler_status_snapshot_parser').parse_status_snapshot_063(data)
end

canon_name = function(s)
	return require('uc_scheduler_maintenance_utils').canon_name(s)
end


ensure_maintenance_state_tables = function()
	scheduler.maintenance_state = scheduler.maintenance_state or {}
	scheduler.maintenance_state.buffs = scheduler.maintenance_state.buffs or {}
	scheduler.maintenance_state.debuffs = scheduler.maintenance_state.debuffs or {}
	scheduler.maintenance_state.status_snapshot = scheduler.maintenance_state.status_snapshot or {}
	return scheduler.maintenance_state
end


local function choose_defensive_action(c)
	local function is_majesty_action(a)
		return type(a) == 'table' and tostring(a.spell or ''):lower() == 'majesty'
	end
	local function cure_is_critical(cure_action)
		if type(cure_action) ~= 'table' then
			return false
		end
		local target_hpp = tonumber(cure_action.target and cure_action.target.hpp) or 0
		if target_hpp <= 0 then
			return false
		end
		local critical_hpp = tonumber(get_settings().defensive_critical_hpp) or 35
		return target_hpp <= critical_hpp
	end
	local majesty_action = nil
	if is_majesty_action(c.buff) then
		majesty_action = c.buff
	elseif is_majesty_action(c.overwrite) then
		majesty_action = c.overwrite
	end
	if majesty_action and (not c.cure or not cure_is_critical(c.cure)) then
		return majesty_action, 'BLOCK_DEFENSIVE_MAJESTY'
	end
	if c.overwrite then
		return c.overwrite, 'BLOCK_DEFENSIVE_OVERWRITE'
	elseif c.cure then
		if c.debuff and c.debuff.spell == 'Paralyna' and c.debuff.target.is_self then
			return c.debuff, 'BLOCK_DEFENSIVE_NA'
		elseif c.debuff and ((c.debuff.prio + 2) < c.cure.prio) then
			return c.debuff, 'BLOCK_DEFENSIVE_NA'
		elseif c.buff and ((c.buff.prio + 2) < c.cure.prio) then
			return c.buff, 'BLOCK_DEFENSIVE_BUFF'
		end
		return c.cure, 'BLOCK_DEFENSIVE_CURE'
	elseif c.debuff then
		if c.buff and (c.buff.prio < c.debuff.prio) then
			return c.buff, 'BLOCK_DEFENSIVE_BUFF'
		end
		return c.debuff, 'BLOCK_DEFENSIVE_NA'
	elseif c.buff then
		return c.buff, 'BLOCK_DEFENSIVE_BUFF'
	end
	return nil, nil
end

local function try_delegate_healbot()
	local ok_actions = type(rawget(_G, 'actions')) == 'table' and type(_G.actions.get_defensive_action) == 'function'
	local ok_healer = type(rawget(_G, 'healer')) == 'table' and type(_G.healer.take_action) == 'function'
	if not ok_actions or not ok_healer then
		return false, 'BLOCK_DEFENSIVE_PROVIDER_UNAVAILABLE'
	end
	local action = _G.actions.get_defensive_action()
	if not action then
		return false, nil
	end
	_G.healer:take_action(action)
	local reason = 'BLOCK_DEFENSIVE_' .. tostring(action.type or 'ACTION')
	_G.UC_LAST_SCHED_ACTION = tostring(action.action and action.action.en or 'healbot_action')
	return true, reason
end

choose_cure_spell = function(member)
	local s = get_settings()
	local max_available = available_cure_tier_max()
	if max_available <= 0 then
		return nil
	end
	local min_tier = tonumber(s.def_heal_min_tier_cure) or 2
	local max_tier_cfg = tonumber(s.def_heal_max_tier_cure) or 4
	local max_tier = math.max(1, math.min(max_available, max_tier_cfg, 6))
	min_tier = math.max(1, math.min(min_tier, max_tier, 6))
	local missing = estimate_missing_hp(member)
	local wanted_tier = cure_tier_for_missing_hp(missing, max_tier)
	local spell = get_usable_cure_from_tier(wanted_tier, min_tier)
	if spell then
		return spell
	end
	-- Last-resort fallback for very low HP if configured floor blocked all options.
	local hpp = tonumber(member and member.hpp) or 100
	if hpp <= (tonumber(s.defensive_critical_hpp) or 35) then
		return get_usable_cure_from_tier(max_tier, 1)
	end
	return nil
end

local function try_internal_defensive_action()
	local s = get_settings()
	if not bool_setting(s.defensive_enabled, false) then
		log_def_sched('DEF_SKIP reason=DEFENSIVE_DISABLED')
		return false, nil
	end
	local p = windower.ffxi.get_player()
	if not p then
		log_def_sched('DEF_BLOCK reason=NO_PLAYER')
		return true, 'BLOCK_DEFENSIVE_NO_PLAYER'
	end
	if not can_act_statuses[p.status or -1] then
		log_def_sched(('DEF_BLOCK reason=PLAYER_STATUS status=%s'):format(tostring(p.status or -1)))
		return true, 'BLOCK_DEFENSIVE_PLAYER_STATUS'
	end
	local now = now_s()
	local candidates = build_defensive_candidates()
	_G.UC_BUFF_QUEUE = tostring(buff_runtime.last_queue_debug or '')
	local action, reason = choose_defensive_action(candidates)
	if action and action.spell and action.target and action.target.name then
		local _, _, action_kind = action_ready(action.spell)
		local out_of_combat = (tonumber(p and p.status) or 0) ~= 1
		local now_gate = now_s()
		local preengage_move_active = (rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true)
		local follow_run_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL')) or 0
		local follow_run_active = (rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE') == true) or (now_gate < follow_run_until)
		local follow_catchup_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL')) or 0
		local follow_needs_catchup = (rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP') == true) or (now_gate < follow_catchup_until)
		if action_kind == 'spell' and out_of_combat and preengage_move_active then
			_G.UC_LAST_SCHED_ACTION = ('def_defer_preengage_move:%s->%s'):format(
				tostring(action.spell or ''),
				tostring(action.target and action.target.name or '')
			)
			log_def_sched(('DEF_SKIP reason=PREENGAGE_MOVE_ACTIVE action="%s" target="%s"'):format(
				tostring(action.spell or ''),
				tostring(action.target and action.target.name or '')
			))
			return false, nil
		end
		if action_kind == 'spell' and out_of_combat and (follow_run_active or follow_needs_catchup) then
			_G.UC_LAST_SCHED_ACTION = ('def_defer_follow_move:%s->%s'):format(
				tostring(action.spell or ''),
				tostring(action.target and action.target.name or '')
			)
			log_def_sched(('DEF_SKIP reason=FOLLOW_MOVE_ACTIVE action="%s" target="%s"'):format(
				tostring(action.spell or ''),
				tostring(action.target and action.target.name or '')
			))
			return false, nil
		end
		local blocked, b_reason = action_dispatch_blocked()
		if blocked then
			log_def_sched(('DEF_BLOCK reason=%s action="%s" target="%s" type=%s'):format(
				tostring(b_reason or 'BLOCKED'),
				tostring(action.spell or ''),
				tostring(action.target and action.target.name or ''),
				tostring(action.type or '')
			))
			return true, b_reason
		end
		if now - scheduler.last_action_at < scheduler.action_delay then
			-- Cooldown paces defensive casts only; do not freeze offensive combat ticks.
			log_def_sched(('DEF_SKIP reason=LOCAL_DELAY action="%s" target="%s" dt=%.2f delay=%.2f'):format(
				tostring(action.spell or ''),
				tostring(action.target and action.target.name or ''),
				now - scheduler.last_action_at,
				tonumber(scheduler.action_delay) or 0
			))
			return false, nil
		end
		local cmd = build_action_command(action.spell, action_kind, action.target)
		log_def_sched(('DEF_SEND type=%s action="%s" target="%s" cmd=%s'):format(
			tostring(action_kind or action.type or 'defensive'),
			tostring(action.spell or ''),
			tostring(action.target and action.target.name or ''),
			tostring(cmd or '')
		))
		windower.send_command(cmd)
		action_mark_sent(action_kind or action.type or 'defensive')
		scheduler.last_action_at = now
		_G.UC_LAST_SCHED_ACTION = action.spell .. '->' .. tostring(action.target.name)
		mark_attempt(action.type or 'defensive', action.target.name, action.spell, now)
		if action.entry_key then
			local st = ensure_maintenance_state_tables()
			local e = st.buffs[action.entry_key] or {}
			e.attempted = now
			e.last_attempt_reason = tostring(action.reason or action.type or '')
			e.last_seen_at = now
			if action.type == 'buff' or action.type == 'overwrite' then
				e.landed = now + action_duration_seconds(action.spell, tonumber(get_settings().defensive_overwrite_interval or 150) or 150)
			end
			st.buffs[action.entry_key] = e
		end
		if action.type == 'overwrite' then
			scheduler.last_overwrite[attempt_key('overwrite', action.target.name, action.spell)] = now
		end
		if (action.type == 'buff' or action.type == 'overwrite') and action.buff_id then
			set_recent_gain(action.target.name, action.buff_id, action.spell, now)
			local tokens = family_tokens_for(action.target.name, action.buff_id)
			tokens[action.spell] = now + action_duration_seconds(action.spell, tonumber(get_settings().defensive_overwrite_interval or 150) or 150)
		end
		return true, reason
	end
	log_def_sched('DEF_SKIP reason=NO_ACTION')
	return false, nil
end

local function p1_number(v, default_value)
	return require('uc_scheduler_numeric_utils').p1_number(v, default_value)
end

local function p1_clamp_urgency(v)
	return require('uc_scheduler_numeric_utils').p1_clamp_urgency(v)
end

local function p1_build_ctx(settings)
	local player = windower.ffxi.get_player() or {}
	local me = windower.ffxi.get_mob_by_target('me') or {}
	local party = windower.ffxi.get_party() or {}
	local mob_array = windower.ffxi.get_mob_array() or {}
	local p = scheduler.phase1
	p.tick = (tonumber(p.tick) or 0) + 1
	return {
		now = now_s(),
		tick = p.tick,
		settings = settings or {},
		player = player,
		me = me,
		party = party,
		mob_array = mob_array,
		player_status = tonumber(player.status) or -1,
		player_id = tonumber(player.id) or 0,
		player_name = tostring(player.name or ''),
		me_id = tonumber(me.id) or 0,
		me_name = tostring(me.name or ''),
	}
end

local function p1_collect_defensive_internal(ctx, out)
	if not bool_setting(ctx.settings.defensive_enabled, false) then
		return
	end
	if tostring(ctx.settings.defensive_provider or 'internal') ~= 'internal' then
		return
	end
	local candidates = build_defensive_candidates()
	local action, reason = choose_defensive_action(candidates)
	if not action or not action.spell or not action.target or not action.target.name then
		return
	end
	local urgency = 0.35
	if action.type == 'overwrite' then
		urgency = 0.80
	elseif action.type == 'cure' then
		urgency = 0.70
	elseif action.type == 'debuff' then
		urgency = 0.60
	elseif action.type == 'buff' then
		urgency = 0.25
	end
	local target_kind = action.target.is_self and 'self' or 'ally'
	local target_id = tonumber(action.target.id) or 0
	local target_name = tostring(action.target.name or '')
	local action_name = tostring(action.spell or '')
	local target_hpp = tonumber(action.target.hpp) or -1
	local critical_hpp = tonumber(ctx.settings.defensive_critical_hpp) or 35
	local priority_band = 100
	if tostring(action.type or '') == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp then
		priority_band = 110
	end
	local _, _, action_kind = action_ready(action_name, target_id)
	local legacy_command = build_action_command(action_name, action_kind, action.target)
	local tank_mode = bool_setting(ctx.settings and ctx.settings.tank, false)
	local engage_priority = tank_mode and 109 or 72
	local engage_urgency = tank_mode and 0.95 or 0.70
	out[#out + 1] = {
		proposal_id = ('def.internal.%s.%s.%d'):format(tostring(action.type or 'action'), action_name, math.floor(ctx.now * 1000)),
		family_id = ('def.internal.%s'):format(tostring(action.type or 'action')),
		provider = 'defensive_internal',
		action_type = action_kind,
		action_name = action_name,
		target_kind = target_kind,
		target_id = target_id,
		target_name = target_name,
		priority_band = priority_band,
		urgency = p1_clamp_urgency(urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.40,
		commit_deadline = ctx.now + 0.25,
		movement_policy = 'must_stop',
		range_policy = { min = 0.0, max = 21.0, los_required = true },
		recast_key = ('spell:%s'):format(action_name),
		duplicate_suppression_key = ('spell:%s:%d'):format(action_name, target_id),
		lock_class = 'support_action',
		expected_ack = 'action_start',
		expected_effect = 'buff_gain',
		sticky = false,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = tostring(reason or ''),
		detail = {
			def_action_type = tostring(action.type or ''),
			target_hpp = target_hpp,
		},
		legacy_command = legacy_command,
	}
end

local function p1_collect_defensive_healbot(ctx, out)
	if not bool_setting(ctx.settings.defensive_enabled, false) then
		return
	end
	if tostring(ctx.settings.defensive_provider or 'internal') ~= 'healbot' then
		return
	end
	local ok_actions = type(rawget(_G, 'actions')) == 'table' and type(_G.actions.get_defensive_action) == 'function'
	local ok_healer = type(rawget(_G, 'healer')) == 'table' and type(_G.healer.take_action) == 'function'
	if not ok_actions or not ok_healer then
		return
	end
	local hb_action = _G.actions.get_defensive_action()
	if type(hb_action) ~= 'table' then
		return
	end
	local atype = tostring(hb_action.type or 'action')
	local aname = tostring((hb_action.action and hb_action.action.en) or atype or 'healbot_action')
	local target_obj = hb_action.target or {}
	local target_name = tostring(target_obj.name or target_obj.en or '')
	local target_id = tonumber(target_obj.id) or 0
	if target_name == '' then
		target_name = tostring(ctx.player_name or '')
	end
	local target_kind = (target_id ~= 0 and target_id ~= tonumber(ctx.player_id or 0)) and 'ally' or 'self'
	local target_hpp = tonumber(target_obj.hpp) or -1
	local critical_hpp = tonumber(ctx.settings.defensive_critical_hpp) or 35
	local priority_band = 100
	if atype == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp then
		priority_band = 110
	end
	local urgency = 0.45
	if atype == 'cure' then
		urgency = 0.70
	elseif atype == 'overwrite' then
		urgency = 0.80
	elseif atype == 'debuff' then
		urgency = 0.60
	elseif atype == 'buff' then
		urgency = 0.30
	end
	out[#out + 1] = {
		proposal_id = ('def.healbot.%s.%s.%d'):format(atype, aname, math.floor(ctx.now * 1000)),
		family_id = ('def.healbot.%s'):format(atype),
		provider = 'defensive_healbot',
		action_type = 'spell',
		action_name = aname,
		target_kind = target_kind,
		target_id = target_id,
		target_name = target_name,
		priority_band = priority_band,
		urgency = p1_clamp_urgency(urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.40,
		commit_deadline = ctx.now + 0.25,
		movement_policy = 'must_stop',
		range_policy = { min = 0.0, max = 21.0, los_required = true },
		recast_key = ('healbot:%s:%s'):format(atype, aname),
		duplicate_suppression_key = ('healbot:%s:%d'):format(aname, target_id),
		lock_class = 'support_action',
		expected_ack = 'action_start',
		expected_effect = 'buff_gain',
		sticky = false,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = ('healbot_%s'):format(atype),
		detail = {
			healbot_action = hb_action,
			def_action_type = atype,
			target_hpp = target_hpp,
		},
	}
end

local function p1_collect_combat_offense(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	if not bool_setting(ctx.settings.weaponskill_active, false) then
		return
	end
	local player = windower.ffxi.get_player()
	if not player or tonumber(player.status) ~= 1 then
		return
	end
	local tp = tonumber(player.vitals and player.vitals.tp) or 0
	if tp < 1000 then
		return
	end
	local target = windower.ffxi.get_mob_by_target('t')
	if not target or not target.valid_target or target.spawn_type ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
		return
	end
	local partner_target_set = build_partner_target_set(ctx.settings)
	if partner_target_set[tonumber(target.id) or 0] == true then
		return
	end
	local ws_pick_reason = ''
	local ws = ''
	if combat_core and type(combat_core.select_smart_ws_for_scheduler) == 'function' then
		ws, ws_pick_reason = combat_core.select_smart_ws_for_scheduler(ctx.settings, tonumber(target.id) or 0)
	end
	ws = tostring(ws or '')
	if ws == '' then
		return
	end
	local urgency = (tp - 1000) / 2000
	if urgency < 0 then
		urgency = 0
	elseif urgency > 1 then
		urgency = 1
	end
	local priority_band = 70
	local reason_code = 'tp_ready'
	if tostring(ws_pick_reason or '') == 'AM_READY' then
		-- Keep aftermath WS above defensive buffs/cures, but still below critical cures (110)
		-- and doom emergency handling, which is processed before proposal dispatch.
		priority_band = 108
		reason_code = 'aftermath_ready'
		urgency = 1
	end
	out[#out + 1] = {
		proposal_id = ('combat.ws.%s.%d.%d'):format(ws, tonumber(target.id) or 0, math.floor(ctx.now * 1000)),
		family_id = 'combat.ws.primary',
		provider = 'combat',
		action_type = 'ws',
		action_name = ws,
		target_kind = 'mob',
		target_id = tonumber(target.id) or 0,
		target_name = tostring(target.name or ''),
		priority_band = priority_band,
		urgency = p1_clamp_urgency(urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = 'requires_range',
		range_policy = { min = 0.0, max = 5.5, los_required = true },
		recast_key = ('ws:%s'):format(ws),
		duplicate_suppression_key = ('ws:%s:%d'):format(ws, tonumber(target.id) or 0),
		lock_class = 'offense_action',
		expected_ack = 'action_start',
		expected_effect = 'ws_effect',
		sticky = true,
		can_preempt_movement = false,
		can_preempt_same_band = false,
		reason_code = reason_code,
		detail = {
			tp = tp,
			ws_pick_reason = tostring(ws_pick_reason or ''),
		},
		legacy_command = ('input /ws \"%s\" <t>'):format(ws),
		required_setting = 'weaponskill_active',
	}
end

local function p1_collect_enemy_buff_removal(ctx, out)
	enemy_dispel_log(('ENEMY_DISPEL_TICK def_enabled=%s remove_enemy=%s provider=%s dark_def=%s'):format(
		tostring(bool_setting(ctx.settings.defensive_enabled, false)),
		tostring(bool_setting(ctx.settings.def_remove_enemy_buffs, false)),
		tostring(ctx.settings.defensive_provider or ''),
		tostring(bool_setting(ctx.settings.scheduler_dark_launch_defensive, false))
	))
	if not bool_setting(ctx.settings.defensive_enabled, false) then
		enemy_dispel_log('ENEMY_DISPEL_SKIP reason=DEFENSIVE_DISABLED')
		return
	end
	if not bool_setting(ctx.settings.def_remove_enemy_buffs, false) then
		enemy_dispel_log('ENEMY_DISPEL_SKIP reason=TOGGLE_OFF')
		return
	end
	local _, claims_set = uc_targeting_common.build_party_claims()
	enemy_effect_state_prune_expired(ctx.now)
	local state = enemy_effect_state_map()
	local has_any_target = false
	for _, _ in pairs(state) do
		has_any_target = true
		break
	end
	if not has_any_target then
		enemy_dispel_log('ENEMY_DISPEL_SKIP reason=NO_TRACKED_TARGETS')
		return
	end
	local best = nil
	local best_effect_id = 0
	local best_effect_prio = -1
	for tid, effects in pairs(state) do
		tid = tonumber(tid) or 0
		if tid > 0 then
			local mob = windower.ffxi.get_mob_by_id(tid)
			if mob and tonumber(mob.spawn_type) == 16 and (tonumber(mob.hpp) or 0) > 0 and enemy_dispel_claim_valid(mob.claim_id, claims_set) then
				local chosen_eid = 0
				local chosen_prio = -1
				for eid, _ in pairs(effects or {}) do
					eid = tonumber(eid) or 0
					local prio = tonumber(dispellable_enemy_effect_priority[eid]) or -1
					if prio > chosen_prio then
						chosen_prio = prio
						chosen_eid = eid
					end
				end
				if chosen_eid > 0 then
					local dist = mob.distance and mob.distance:sqrt() or 999
					local pick = {
						target_id = tid,
						target_name = tostring(mob.name or ''),
						effect_id = chosen_eid,
						effect_prio = chosen_prio,
						dist = tonumber(dist) or 999,
					}
					local is_better = false
					if not best then
						is_better = true
					elseif pick.effect_prio ~= best.effect_prio then
						is_better = pick.effect_prio > best.effect_prio
					elseif pick.dist ~= best.dist then
						is_better = pick.dist < best.dist
					else
						is_better = pick.target_id < best.target_id
					end
					if is_better then
						best = pick
						best_effect_id = chosen_eid
						best_effect_prio = chosen_prio
					end
				end
			end
		end
	end
	if not best then
		enemy_dispel_diag('[enemy_dispel]no_eligible_target')
		enemy_dispel_log('ENEMY_DISPEL_SKIP reason=NO_ELIGIBLE_TARGET')
		return
	end
	local action_name = enemy_dispel_choose_action(best.target_id)
	if action_name == '' then
		enemy_dispel_diag(('[enemy_dispel]not_ready target=%s effect=%d'):format(
			tostring(best.target_name or ''),
			tonumber(best_effect_id) or 0
		))
		enemy_dispel_log(('ENEMY_DISPEL_SKIP reason=NOT_READY target=\"%s\" effect=\"%s\"'):format(
			tostring(best.target_name or ''),
			enemy_effect_log_label(best_effect_id)
		))
		return
	end
	local attempt_ok, attempt_key = can_attempt_enemy_dispel(action_name, best.target_id, best_effect_id, ctx.now)
	if not attempt_ok then
		enemy_dispel_diag(('[enemy_dispel]attempt_gate action=%s target=%s effect=%d'):format(
			tostring(action_name),
			tostring(best.target_name or ''),
			tonumber(best_effect_id) or 0
		))
		enemy_dispel_log(('ENEMY_DISPEL_SKIP reason=ATTEMPT_GATE action=\"%s\" target=\"%s\" effect=\"%s\"'):format(
			tostring(action_name),
			tostring(best.target_name or ''),
			enemy_effect_log_label(best_effect_id)
		))
		return
	end
	local mob_target = { id = best.target_id, name = best.target_name, is_self = false, is_mob = true }
	local _, _, action_kind = action_ready(action_name, best.target_id)
	local legacy_command = build_action_command(action_name, action_kind, mob_target)
	enemy_dispel_diag(('[enemy_dispel]emit action=%s target=%s effect=%d prio=%d'):format(
		tostring(action_name),
		tostring(best.target_name or ''),
		tonumber(best_effect_id) or 0,
		tonumber(best_effect_prio) or 0
	))
	out[#out + 1] = {
		proposal_id = ('def.enemy_dispel.%s.%d.%d'):format(
			tostring(action_name),
			tonumber(best.target_id) or 0,
			math.floor(ctx.now * 1000)
		),
		family_id = 'def.enemy_dispel.primary',
		provider = 'defensive_internal',
		action_type = 'spell',
		action_name = tostring(action_name),
		target_kind = 'mob',
		target_id = tonumber(best.target_id) or 0,
		target_name = tostring(best.target_name or ''),
		priority_band = 106,
		urgency = p1_clamp_urgency(0.65),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.40,
		commit_deadline = ctx.now + 0.25,
		movement_policy = 'must_stop',
		range_policy = { min = 0.0, max = 21.0, los_required = true },
		recast_key = ('spell:%s'):format(action_name),
		duplicate_suppression_key = ('enemy_dispel:%s:%d:%d'):format(
			tostring(action_name),
			tonumber(best.target_id) or 0,
			tonumber(best_effect_id) or 0
		),
		lock_class = 'support_action',
		expected_ack = 'action_start',
		expected_effect = 'enemy_effect_removed',
		sticky = false,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = 'enemy_buff_remove',
		detail = {
			enemy_effect_id = tonumber(best_effect_id) or 0,
			enemy_effect_priority = tonumber(best_effect_prio) or 0,
			enemy_dispel_attempt_key = tostring(attempt_key or ''),
		},
		legacy_command = legacy_command,
	}
	enemy_dispel_log(('ENEMY_DISPEL_EMIT action=\"%s\" target=\"%s\" effect=\"%s\" prio=%d'):format(
		tostring(action_name),
		tostring(best.target_name or ''),
		enemy_effect_log_label(best_effect_id),
		tonumber(best_effect_prio) or 0
	))
end

local function p1_collect_combat_engage(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	if not bool_setting(ctx.settings.scheduler_dark_launch_combat, false) then
		return
	end
	if not bool_setting(ctx.settings.autotarget, false) then
		return
	end
	local player = windower.ffxi.get_player()
	if not player then
		return
	end
	local engaged = tonumber(player.status) == 1
	local fight_leader_force_target_id = 0
	local fight_leader_on = bool_setting(ctx.settings and ctx.settings.fight_leader, false)
	if fight_leader_on and (tonumber(ctx.settings and ctx.settings.fight_leader_id) or 0) > 0
		and uc_fight_leader and type(uc_fight_leader.leader_target_id) == 'function' then
		fight_leader_force_target_id = tonumber(uc_fight_leader.leader_target_id(tonumber(ctx.settings.fight_leader_id) or 0)) or 0
	end
	if engaged and fight_leader_force_target_id <= 0 then
		return
	end
	local t = nil
	if fight_leader_force_target_id > 0 then
		t = windower.ffxi.get_mob_by_id(fight_leader_force_target_id)
	end
	if not t then
		t = windower.ffxi.get_mob_by_target('t')
	end
	if not t or not t.valid_target or tonumber(t.spawn_type) ~= 16 or (tonumber(t.hpp) or 0) <= 0 then
		if bool_setting(ctx.settings and ctx.settings.debug, false) then
			_G.UC_LAST_SCHED_ACTION = '[p1]engage:collect_skip:no_valid_target'
		end
		return
	end
	-- Hunter/path pull ownership: when a pull action is currently applicable, suppress
	-- engage proposals so we do not run into melee before the configured pull executes.
	if combat_core and type(combat_core.select_pull_for_scheduler) == 'function' then
		local pull_pick = combat_core.select_pull_for_scheduler(ctx.settings)
		if type(pull_pick) == 'table' then
			local pull_tid = tonumber(pull_pick.target_id) or 0
			local this_tid = tonumber(t.id) or 0
			if pull_tid > 0 and this_tid > 0 and pull_tid == this_tid then
				if bool_setting(ctx.settings and ctx.settings.debug, false) then
					_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_skip:pull_owner tid=%d action=%s:%s'):format(
						this_tid,
						tostring(pull_pick.action_type or ''),
						tostring(pull_pick.action_name or '')
					)
				end
				return
			end
		end
	end
	local _, claims_set = uc_targeting_common.build_party_claims()
	local claim_id = tonumber(t.claim_id) or 0
	local party_ids = p1_build_party_id_set()
	local party_claimed_ok = claims_set[claim_id] == true
	local prime_unclaimed_ok = p1_prime_unclaimed_party_aggressive_ok(ctx.settings, t, party_ids)
	local force_leader_engage = (fight_leader_force_target_id > 0 and fight_leader_force_target_id == (tonumber(t.id) or 0))
	if not party_claimed_ok and not prime_unclaimed_ok and not force_leader_engage then
		if bool_setting(ctx.settings and ctx.settings.debug, false) then
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_skip:policy claim=%d st=%d prime=%s'):format(
				claim_id,
				tonumber(t.status) or 0,
				tostring(bool_setting(ctx.settings and ctx.settings.prime, false))
			)
		end
		return
	end
	if bool_setting(ctx.settings and ctx.settings.debug, false) then
		if force_leader_engage then
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_emit_force_leader tid=%d name=%s'):format(
				tonumber(t.id) or 0,
				tostring(t.name or '')
			)
		else
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_emit tid=%d name=%s'):format(
				tonumber(t.id) or 0,
				tostring(t.name or '')
			)
		end
	end
	out[#out + 1] = {
		proposal_id = ('combat.engage.%d.%d'):format(tonumber(t.id) or 0, math.floor(ctx.now * 1000)),
		family_id = 'combat.engage.primary',
		provider = 'combat',
		action_type = 'engage',
		action_name = 'engage_target',
		target_kind = 'mob',
		target_id = tonumber(t.id) or 0,
		target_name = tostring(t.name or ''),
		priority_band = engage_priority,
		urgency = p1_clamp_urgency(engage_urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = 'can_move',
		range_policy = { min = 0.0, max = 30.0, los_required = false },
		recast_key = 'engage:attack_on',
		duplicate_suppression_key = ('engage:%d'):format(tonumber(t.id) or 0),
		lock_class = 'offense_action',
		expected_ack = 'action_start',
		expected_effect = 'engage',
		sticky = true,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = 'engage_ready',
		detail = {},
		required_setting = 'autotarget',
	}
end

local function p1_collect_target_control(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	if not bool_setting(ctx.settings.autotarget, false) then
		return
	end
	if not combat_core or type(combat_core.select_target_for_scheduler) ~= 'function' then
		return
	end
	local player = windower.ffxi.get_player()
	if not player then
		return
	end
	-- Keep parity with core engaged stickiness for this first migration slice:
	-- target acquisition proposals are for pre-engage control only.
	if tonumber(player.status) == 1 then
		return
	end
	local pick = combat_core.select_target_for_scheduler(ctx.settings)
	if type(pick) ~= 'table' then
		return
	end
	local tid = tonumber(pick.target_id) or 0
	if tid <= 0 then
		return
	end
	local cur = windower.ffxi.get_mob_by_target('t')
	if cur and tonumber(cur.id) == tid then
		return
	end
	out[#out + 1] = {
		proposal_id = ('target.acquire.%d.%d'):format(tid, math.floor(ctx.now * 1000)),
		family_id = 'target.acquire.primary',
		provider = 'target_control',
		action_type = 'target',
		action_name = 'acquire_target',
		target_kind = 'mob',
		target_id = tid,
		target_name = tostring(pick.target_name or ''),
		priority_band = 84,
		urgency = p1_clamp_urgency(0.55),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.35,
		commit_deadline = ctx.now + 0.25,
		movement_policy = 'can_move',
		range_policy = { min = 0.0, max = 50.0, los_required = false },
		recast_key = ('target:%d'):format(tid),
		duplicate_suppression_key = ('target.acquire:%d'):format(tid),
		lock_class = 'target_control',
		expected_ack = 'target_set',
		expected_effect = 'target_selected',
		sticky = true,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = 'acquire_candidate',
		detail = {
			hpp = tonumber(pick.hpp) or 0,
		},
		required_setting = 'autotarget',
	}
end

local function p1_collect_pull_control(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	if not bool_setting(ctx.settings.scheduler_dark_launch_combat, false) then
		return
	end
	if not bool_setting(ctx.settings.autotarget, false) then
		return
	end
	if not combat_core or type(combat_core.select_pull_for_scheduler) ~= 'function' then
		return
	end
	local pick = combat_core.select_pull_for_scheduler(ctx.settings)
	if type(pick) ~= 'table' then
		return
	end
	local tid = tonumber(pick.target_id) or 0
	local aname = tostring(pick.action_name or '')
	local atype = tostring(pick.action_type or '')
	if tid <= 0 or aname == '' or (atype ~= 'spell' and atype ~= 'ja') then
		return
	end
	local urgency = (pick.in_range == true) and 0.92 or 0.75
	out[#out + 1] = {
		proposal_id = ('pull.%s.%s.%d.%d'):format(atype, aname, tid, math.floor(ctx.now * 1000)),
		family_id = 'combat.pull.primary',
		provider = 'pull_control',
		action_type = 'pull',
		action_name = aname,
		target_kind = 'mob',
		target_id = tid,
		target_name = tostring(pick.target_name or ''),
		priority_band = 82,
		urgency = p1_clamp_urgency(urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = 'requires_range',
		range_policy = { min = 0.0, max = tonumber(pick.range_max) or 20.0, los_required = false },
		recast_key = ('pull:%s:%s'):format(atype, aname),
		duplicate_suppression_key = ('pull:%s:%s:%d'):format(atype, aname, tid),
		lock_class = 'offense_action',
		expected_ack = 'action_start',
		expected_effect = 'pull_action',
		sticky = true,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = (pick.in_range == true) and 'pull_ready' or 'pull_move_into_range',
		detail = {
			action_type = atype,
			dist = tonumber(pick.dist) or 999,
			range_max = tonumber(pick.range_max) or 0,
			in_range = pick.in_range == true,
		},
		required_setting = 'autotarget',
	}
end

local function p1_collect_combat_tank_enmity(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	local player = windower.ffxi.get_player()
	if not player or tonumber(player.status) ~= 1 then
		-- Force initial /attack engagement to occur before enmity actions.
		return
	end
	if not combat_core or type(combat_core.select_tank_enmity_for_scheduler) ~= 'function' then
		return
	end
	local pick = combat_core.select_tank_enmity_for_scheduler(ctx.settings)
	if type(pick) ~= 'table' then
		return
	end
	local kind = tostring(pick.kind or ''):lower()
	if kind ~= 'ja' and kind ~= 'spell' then
		return
	end
	local action_name = tostring(pick.name or '')
	local target_id = tonumber(pick.target_id) or 0
	if action_name == '' or target_id <= 0 then
		return
	end
	-- Hard gate at collect-time so unusable tank actions never starve the queue.
	-- If action is on cooldown / blocked now, do not emit an intent.
	local ready_ok, ready_reason, ready_kind = action_ready(action_name, target_id)
	if not ready_ok then
		log_tank_sched(('collect_skip action=\"%s\" kind=%s reason=%s target_id=%d'):format(
			tostring(action_name),
			tostring(kind),
			tostring(ready_reason or 'NOT_READY'),
			target_id
		))
		return
	end
	-- Defensive consistency: ensure resolved action kind matches picked kind.
	if tostring(ready_kind or '') ~= kind then
		log_tank_sched(('collect_skip action=\"%s\" kind=%s reason=KIND_MISMATCH resolved=%s target_id=%d'):format(
			tostring(action_name),
			tostring(kind),
			tostring(ready_kind or ''),
			target_id
		))
		return
	end
	-- Tank enmity recovery should stay high, but cures must outrank it so
	-- party sustain wins over threat correction when both are available.
	-- Cure intents currently score from priority_band=100 (+ urgency), with
	-- critical cures at 110, so keep tank below that envelope.
	local prio = 96
	local urgency = 0.85
	local victim_hpp = tonumber(pick.victim_hpp) or 0
	if victim_hpp > 0 then
		urgency = p1_clamp_urgency(1.0 - (math.min(victim_hpp, 100) / 100.0))
		if urgency < 0.60 then
			urgency = 0.60
		end
	end
	local action_range = tonumber(pick.action_range)
	if not action_range or action_range <= 0 then
		action_range = 20.0
	end
	out[#out + 1] = {
		proposal_id = ('combat.tank.%s.%s.%d.%d'):format(kind, action_name, target_id, math.floor(ctx.now * 1000)),
		family_id = 'combat.tank_enmity.primary',
		provider = 'combat',
		action_type = kind,
		action_name = action_name,
		target_kind = 'mob',
		target_id = target_id,
		target_name = tostring(pick.target_name or ''),
		priority_band = prio,
		urgency = p1_clamp_urgency(urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = (kind == 'spell') and 'must_stop' or 'requires_range',
		range_policy = { min = 0.0, max = math.max(1.0, action_range), los_required = false },
		recast_key = ('tank:%s:%s'):format(kind, action_name),
		duplicate_suppression_key = ('tank:%s:%s:%d'):format(kind, action_name, target_id),
		lock_class = 'offense_action',
		expected_ack = 'action_start',
		expected_effect = (kind == 'spell') and 'spell_effect' or 'ja_effect',
		sticky = true,
		can_preempt_movement = true,
		can_preempt_same_band = true,
		reason_code = 'tank_enmity_violation',
		detail = {
			tank_enmity = true,
			victim_name = tostring(pick.victim_name or ''),
			victim_hpp = tonumber(pick.victim_hpp) or 0,
			mob_hpp = tonumber(pick.mob_hpp) or 0,
			dist = tonumber(pick.dist) or 0,
			action_range = tonumber(pick.action_range) or 0,
			selection_reason = tostring(pick.reason or ''),
		},
		legacy_command = (kind == 'spell')
			and ('input /ma \"%s\" %d'):format(action_name, target_id)
			or ('input /ja \"%s\" %d'):format(action_name, target_id),
	}
end

local function p1_collect_combat_ja(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	if not bool_setting(ctx.settings.ability_active, false) then
		return
	end
	local player = windower.ffxi.get_player()
	if not player or tonumber(player.status) ~= 1 then
		return
	end
	local ordered = ability_pipeline.collect_ordered(ctx.settings, 6)
	if #ordered == 0 then
		return
	end
	local target = windower.ffxi.get_mob_by_target('t')
	local partner_target_set = build_partner_target_set(ctx.settings)
	for _, name in ipairs(ordered) do
		local ja = get_ja_resource(name)
		if ja then
			local ok_ready, reason, kind = action_ready(name, target and target.id or 0)
			if ok_ready and kind == 'ja' then
				local target_kind = 'self'
				local target_id = tonumber(player.id) or 0
				local target_name = tostring(player.name or '')
				local ja_targets = tostring(ja.targets or '')
				local ja_target_ok = true
				if ja_targets == '{Enemy}' then
					if not target or not target.valid_target or target.spawn_type ~= 16 or (tonumber(target.hpp) or 0) <= 0 then
						ja_target_ok = false
					end
					if ja_target_ok and partner_target_set[tonumber(target.id) or 0] == true then
						ja_target_ok = false
					end
					if ja_target_ok then
						local r = action_effective_range(ja.range)
						if r > 0 then
							local d = target.distance and target.distance:sqrt() or 999
							if d > r then
								ja_target_ok = false
							end
						end
					end
					if ja_target_ok then
						target_kind = 'mob'
						target_id = tonumber(target.id) or 0
						target_name = tostring(target.name or '')
					end
				end
				if ja_target_ok then
					out[#out + 1] = {
						proposal_id = ('combat.ja.%s.%d.%d'):format(tostring(name), target_id, math.floor(ctx.now * 1000)),
						family_id = 'combat.ja.primary',
						provider = 'combat',
						action_type = 'ja',
						action_name = tostring(name),
						target_kind = target_kind,
						target_id = target_id,
						target_name = target_name,
						priority_band = 70,
						urgency = 0.35,
						starvation_eligible = true,
						created_at = ctx.now,
						expires_at = ctx.now + 0.30,
						commit_deadline = ctx.now + 0.20,
						movement_policy = 'must_stop',
						range_policy = { min = 0.0, max = 10.0, los_required = false },
						recast_key = ('ja:%s'):format(tostring(name)),
						duplicate_suppression_key = ('ja:%s:%d'):format(tostring(name), target_id),
						lock_class = 'offense_action',
						expected_ack = 'action_start',
						expected_effect = 'ja_effect',
						sticky = false,
						can_preempt_movement = true,
						can_preempt_same_band = false,
						reason_code = 'ability_ready',
						detail = {
							ability = tostring(name),
						},
						legacy_command = (target_kind == 'self') and ('input /ja \"%s\" <me>'):format(tostring(name))
							or ('input /ja \"%s\" %d'):format(tostring(name), target_id),
						required_setting = 'ability_active',
					}
					break
				else
					log_ja_sched(('collect_skip name=\"%s\" reason=TARGET_INVALID status=%s target_id=%s'):format(
						tostring(name),
						tostring((windower.ffxi.get_player() or {}).status or ''),
						tostring(target and target.id or 0)
					))
				end
			elseif kind == 'ja' then
				log_ja_sched(('collect_skip name=\"%s\" reason=%s status=%s pending=%s'):format(
					tostring(name),
					tostring(reason or 'NOT_READY'),
					tostring((windower.ffxi.get_player() or {}).status or ''),
					tostring((scheduler.phase1.pending and scheduler.phase1.pending.action_name) or '')
				))
			end
		end
	end
end

local function p1_collect_maintenance(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		log_def_sched('MAINT_SKIP reason=ENGINE_OFF')
		return
	end
	local player = windower.ffxi.get_player()
	if not player then
		log_def_sched('MAINT_SKIP reason=NO_PLAYER')
		return
	end
	local job = tostring(player.main_job or '')
	if job == '' then
		log_def_sched('MAINT_SKIP reason=NO_JOB')
		return
	end
	local phase = scheduler.phase1
	local gate = phase.maintenance_next_at or {}
	phase.maintenance_next_at = gate
	if is_city_zone_for_maintenance() then
		log_def_sched('MAINT_SKIP reason=CITY_ZONE')
		gate.cor_rolls = 0
		gate.brd_songs = 0
		gate.geo_buffs = 0
		return
	end
	local now = ctx.now
	ensure_maintenance_buff_cache()
	local buff_list = player.buffs or {}
	local function maybe_emit(key, provider, action_type, action_name, reason_code, urgency, detail)
		if action_type == 'spell' then
			local p = windower.ffxi.get_player() or {}
			local out_of_combat = tonumber(p.status) ~= 1
			if out_of_combat then
				local moving = false
				local ok_lor, lor_actor_mod = pcall(require, 'lor/lor_actor')
				if ok_lor and type(lor_actor_mod) == 'table' and type(lor_actor_mod.Actor) == 'table' and type(lor_actor_mod.Actor.new) == 'function' then
					local actor = rawget(_G, 'UC_SCHED_MAINT_LOCAL_ACTOR')
					if actor == nil then
						actor = lor_actor_mod.Actor.new()
						rawset(_G, 'UC_SCHED_MAINT_LOCAL_ACTOR', actor)
					end
					if type(actor) == 'table' and type(actor.is_moving) == 'function' then
						moving = actor:is_moving() == true
					end
				end
				if moving then
					return
				end
			end
		end
		local next_at = p1_number(gate[key], 0)
		if now < next_at then
			return
		end
		gate[key] = now + 2.0
		out[#out + 1] = {
			proposal_id = ('maint.%s.%d'):format(key, math.floor(now * 1000)),
			family_id = ('maintenance.%s'):format(key),
			provider = provider,
			action_type = action_type,
			action_name = action_name,
			target_kind = 'self',
			target_id = tonumber(player.id) or 0,
			target_name = tostring(player.name or ''),
			priority_band = 75,
			urgency = p1_clamp_urgency(urgency),
			starvation_eligible = true,
			created_at = now,
			expires_at = now + 0.40,
			commit_deadline = now + 0.25,
			movement_policy = 'must_stop',
			range_policy = { min = 0.0, max = 20.0, los_required = false },
			recast_key = ('maint:%s'):format(key),
			duplicate_suppression_key = ('maint:%s:%d'):format(key, tonumber(player.id) or 0),
			lock_class = 'support_action',
			expected_ack = 'action_start',
			expected_effect = 'buff_gain',
			sticky = true,
			can_preempt_movement = true,
			can_preempt_same_band = false,
			reason_code = reason_code,
			detail = detail or { job = job },
			legacy_command = '',
		}
	end
	if job == 'COR' then
		local action = cor_maintenance and cor_maintenance.propose and cor_maintenance.propose(ctx.settings) or nil
		if action and action.action_name and action.action_name ~= '' then
			local key = 'cor_rolls'
			local next_at = p1_number(gate[key], 0)
			if now >= next_at then
				gate[key] = now + 1.0
				local urgency = p1_clamp_urgency(tonumber(action.urgency) or 0.65)
				local action_name = tostring(action.action_name or '')
				local target_name = tostring(action.target_name or '<me>')
				local target_kind = tostring(action.target_kind or 'self')
				local target_id = tonumber(action.target_id) or 0
				out[#out + 1] = {
					proposal_id = ('maint.cor.%s.%d'):format(action_name, math.floor(now * 1000)),
					family_id = 'maintenance.cor.rolls',
					provider = 'maintenance_cor',
					action_type = 'ja',
					action_name = action_name,
					target_kind = target_kind,
					target_id = target_id,
					target_name = target_name,
					priority_band = 75,
					urgency = urgency,
					starvation_eligible = true,
					created_at = now,
					expires_at = now + 0.40,
					commit_deadline = now + 0.25,
					movement_policy = 'must_stop',
					range_policy = { min = 0.0, max = 20.0, los_required = false },
					recast_key = ('maint:cor:%s'):format(action_name),
					duplicate_suppression_key = ('maint:cor:%s:%d'):format(action_name, target_id),
					lock_class = 'support_action',
					expected_ack = 'action_start',
					expected_effect = 'buff_gain',
					sticky = true,
					can_preempt_movement = true,
					can_preempt_same_band = false,
					reason_code = tostring(action.reason_code or 'cor_roll_maint'),
					detail = action.detail or { job = job },
				}
			end
		else
			log_def_sched('MAINT_COR_SKIP reason=PROPOSE_NIL')
			gate.cor_rolls = 0
		end
	elseif job == 'BRD' then
		local song_count = count_matching_buffs(buff_list, maintenance_buff_cache.song_ids)
		if song_count < 2 then
			maybe_emit('brd_songs', 'brd', 'spell', 'maintenance_songs', 'songs_missing', (song_count == 0) and 0.80 or 0.50, {
				job = job,
				song_count = song_count,
				expected = 2,
			})
		else
			gate.brd_songs = 0
		end
	elseif job == 'GEO' then
		local indi_count = count_matching_buffs(buff_list, maintenance_buff_cache.indi_ids)
		local geo_count = count_matching_buffs(buff_list, maintenance_buff_cache.geo_ids)
		local missing_indi = indi_count < 1
		local missing_geo = geo_count < 1
		if missing_indi or missing_geo then
			local urgency = 0.45
			if missing_indi and missing_geo then
				urgency = 0.80
			elseif missing_indi then
				urgency = 0.65
			end
			maybe_emit('geo_buffs', 'geo', 'spell', 'maintenance_geo', 'geo_missing', urgency, {
				job = job,
				indi_count = indi_count,
				geo_count = geo_count,
				expected_indi = 1,
				expected_geo = 1,
			})
		else
			gate.geo_buffs = 0
		end
	end
end

local function p1_collect_proposals(ctx)
	local out = {}
	local s = ctx.settings or {}
	-- 5 Hz domains
	p1_collect_target_control(ctx, out)
	p1_collect_combat_engage(ctx, out)
	p1_collect_pull_control(ctx, out)
	p1_collect_combat_tank_enmity(ctx, out)
	p1_collect_combat_offense(ctx, out)
	p1_collect_combat_ja(ctx, out)
	-- 2 Hz defensive
	if ctx.now >= (tonumber(s._sched_next_defensive_at) or 0) then
		p1_collect_enemy_buff_removal(ctx, out)
		p1_collect_defensive_internal(ctx, out)
		p1_collect_defensive_healbot(ctx, out)
	end
	-- 1 Hz maintenance
	if ctx.now >= (tonumber(s._sched_next_maintenance_at) or 0) then
		p1_collect_maintenance(ctx, out)
	end
	return out
end

local function p1_pending_is_live_state(state_name)
	return scheduler_locks.p1_pending_is_live_state(state_name)
end

local function p1_update_pending_state(ctx)
	return scheduler_pending.p1_update_pending_state(scheduler, ctx, p1_pending_is_live_state, p1_number)
end

local function p1_duplicate_suppressed(ctx, proposal)
	return scheduler_locks.p1_duplicate_suppressed(scheduler, ctx, proposal, p1_number)
end

ensure_maintenance_buff_cache = function()
	if maintenance_buff_cache.built then
		return
	end
	local roll_ids, song_ids, indi_ids, geo_ids = {}, {}, {}, {}
	for id, b in pairs(res.buffs or {}) do
		local name = tostring((b and b.en) or '')
		local lname = name:lower()
		if lname:find('roll', 1, true) then
			roll_ids[id] = true
		end
		if lname:find('march', 1, true) or lname:find('madrigal', 1, true) or lname:find('minuet', 1, true) or
			lname:find('ballad', 1, true) or lname:find('paeon', 1, true) or lname:find('etude', 1, true) or
			lname:find('carol', 1, true) or lname:find('prelude', 1, true) or lname:find('scherzo', 1, true) or
			lname:find('minne', 1, true) or lname:find('mambo', 1, true) or lname:find('mazurka', 1, true) or
			lname:find('hymnus', 1, true) then
			song_ids[id] = true
		end
		if lname:sub(1, 5) == 'indi-' then
			indi_ids[id] = true
		end
		if lname:sub(1, 4) == 'geo-' then
			geo_ids[id] = true
		end
	end
	maintenance_buff_cache.roll_ids = roll_ids
	maintenance_buff_cache.song_ids = song_ids
	maintenance_buff_cache.indi_ids = indi_ids
	maintenance_buff_cache.geo_ids = geo_ids
	maintenance_buff_cache.built = true
end

count_matching_buffs = function(buff_list, id_set)
	return require('uc_scheduler_maintenance_utils').count_matching_buffs(buff_list, id_set)
end

local function p1_get_locks(ctx)
	return scheduler_locks.p1_get_locks(scheduler, ctx, p1_number, _G)
end

local function p1_hard_lock_reject(locks, proposal)
	return scheduler_locks.p1_hard_lock_reject(locks, proposal)
end

local function p1_validate_proposal(ctx, p)
	if type(p) ~= 'table' then
		return false, 'malformed'
	end
	if tostring(p.proposal_id or '') == '' or tostring(p.provider or '') == '' then
		return false, 'malformed'
	end
	local required_setting = tostring(p.required_setting or '')
	if required_setting ~= '' and not bool_setting(ctx.settings[required_setting], false) then
		return false, 'settings_disabled'
	end
	if p1_number(ctx.now - p1_number(p.created_at, ctx.now), 0) > 0.8 then
		return false, 'stale_snapshot'
	end
	local phase = scheduler.phase1
	if type(phase.pending) == 'table' and p1_pending_is_live_state(tostring(phase.pending.state or '')) then
		local pending_lock_class = tostring(phase.pending.lock_class or '')
		local proposal_lock_class = tostring(p.lock_class or '')
		if pending_lock_class ~= '' and proposal_lock_class ~= '' and pending_lock_class ~= proposal_lock_class then
			local at = tostring(p.action_type or '')
			if at == 'spell' or at == 'ja' or at == 'ws' or at == 'move' then
				return false, 'pending_conflict'
			end
		end
	end
	local expires_at = p1_number(p.expires_at, ctx.now + 0.40)
	if expires_at <= ctx.now then
		return false, 'expired'
	end
	p.expires_at = expires_at
	p.commit_deadline = p1_number(p.commit_deadline, ctx.now + 0.25)
	p.priority_band = math.floor(p1_number(p.priority_band, 0))
	p.urgency = p1_clamp_urgency(p.urgency)
	if p1_duplicate_suppressed(ctx, p) then
		return false, 'duplicate_suppressed'
	end
	return true, ''
end

local function p1_score(eval)
	local priority_band = math.floor(p1_number(eval.priority_band, 0))
	local urgency_bonus = p1_clamp_urgency(eval.urgency) * 9.9
	local starvation_bonus = 0
	local sticky_bonus = 0
	local risk_penalty = 0
	local score = priority_band + urgency_bonus + starvation_bonus + sticky_bonus - risk_penalty
	eval._score = score
	eval._score_parts = {
		priority_band = priority_band,
		urgency_bonus = urgency_bonus,
		starvation_bonus = starvation_bonus,
		sticky_bonus = sticky_bonus,
		risk_penalty = risk_penalty,
	}
	return score
end

local function p1_rank(ctx, proposals)
	local locks = p1_get_locks(ctx)
	local valid = {}
	local reject_counts = {}
	local rejected = {}
	local function add_reject(proposal, reason)
		local p = proposal or {}
		rejected[#rejected + 1] = {
			provider = tostring(p.provider or ''),
			family = tostring(p.family_id or ''),
			action = tostring(p.action_name or ''),
			reason = tostring(reason or ''),
		}
	end
	for _, proposal in ipairs(proposals) do
		local ok, reject_reason = p1_validate_proposal(ctx, proposal)
		if ok then
			local lock_reject = p1_hard_lock_reject(locks, proposal)
			if lock_reject ~= '' then
				reject_counts[lock_reject] = (reject_counts[lock_reject] or 0) + 1
				add_reject(proposal, lock_reject)
			else
				p1_score(proposal)
				valid[#valid + 1] = proposal
			end
		else
			local rr = reject_reason ~= '' and tostring(reject_reason) or 'invalid'
			reject_counts[rr] = (reject_counts[rr] or 0) + 1
			add_reject(proposal, rr)
		end
	end
	table.sort(valid, function(a, b)
		local sa = p1_number(a._score, -1e9)
		local sb = p1_number(b._score, -1e9)
		if sa ~= sb then
			return sa > sb
		end
		local ea = p1_number(a.expires_at, ctx.now + 999)
		local eb = p1_number(b.expires_at, ctx.now + 999)
		if ea ~= eb then
			return ea < eb
		end
		local pa = tostring(a.provider or '')
		local pb = tostring(b.provider or '')
		if pa ~= pb then
			return pa < pb
		end
		return tostring(a.proposal_id or '') < tostring(b.proposal_id or '')
	end)
	if bool_setting(ctx and ctx.settings and ctx.settings.debug, false) then
		local seen_engage = false
		local won_engage = false
		local top_provider = ''
		local top_family = ''
		local top_action = ''
		local top_score = 0
		if type(valid) == 'table' and #valid > 0 then
			top_provider = tostring(valid[1].provider or '')
			top_family = tostring(valid[1].family_id or '')
			top_action = tostring(valid[1].action_type or '')
			top_score = tonumber(valid[1]._score) or 0
		end
		for _, v in ipairs(valid) do
			if tostring(v.family_id or '') == 'combat.engage.primary' then
				seen_engage = true
				if v == valid[1] then
					won_engage = true
				end
				break
			end
		end
		if seen_engage and (not won_engage) then
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:rank_lost top=%s/%s/%s score=%.2f'):format(
				top_provider, top_family, top_action, top_score
			)
		elseif seen_engage and won_engage then
			_G.UC_LAST_SCHED_ACTION = '[p1]engage:rank_win'
		end
	end
	return valid, reject_counts, locks, rejected
end

local function p1_format_top3(ranked)
	return require('uc_scheduler_rank_output').p1_format_top3(scheduler, ranked, p1_number)
end

local function p1_format_top3_verbose(ranked)
	return require('uc_scheduler_rank_output').p1_format_top3_verbose(scheduler, ranked, p1_number)
end

local function p1_format_topn_lines(ranked, n)
	return require('uc_scheduler_rank_output').p1_format_topn_lines(scheduler, ranked, n, p1_number)
end

local function p1_capture_topn_items(ranked, n)
	return require('uc_scheduler_rank_output').p1_capture_topn_items(scheduler, ranked, n, p1_number)
end

local function p1_push_recent_rejects(ctx, rejected)
	return require('uc_scheduler_reject_history').p1_push_recent_rejects(scheduler, ctx, rejected)
end

local function p1_reject_top(reject_counts, proposal_count)
	return require('uc_scheduler_rank_output').p1_reject_top(scheduler, reject_counts, proposal_count)
end

local function p1_build_dispatch_plan(ctx, selected)
	return require('uc_scheduler_dispatch_plan').p1_build_dispatch_plan(scheduler, ctx, selected, p1_number)
end

local function p1_revalidate_plan_commit(ctx, selected, plan)
	return require('uc_scheduler_dispatch_plan').p1_revalidate_plan_commit(scheduler, ctx, selected, plan, p1_number, windower)
end

local function p1_set_pending_globals()
	return scheduler_pending.p1_set_pending_globals(scheduler, _G)
end

local function p1_build_lock_summary(ctx, locks)
	return scheduler_locks.p1_build_lock_summary(ctx, locks, p1_get_locks)
end

local function p1_record_legacy_dispatch(ctx)
	return require('uc_scheduler_pending_record').p1_record_legacy_dispatch(scheduler, ctx, p1_number)
end

local function p1_pending_mark_complete(now, result_code)
	return scheduler_pending.p1_pending_mark_complete(scheduler, now, result_code)
end

local function p1_run_dry(settings)
	local ctx = p1_build_ctx(settings)
	p1_update_pending_state(ctx)
	local proposals = p1_collect_proposals(ctx)
	local ranked, reject_counts, locks, rejected = p1_rank(ctx, proposals)
	local selected = ranked[1]
	local plan = p1_build_dispatch_plan(ctx, selected)
	local commit_ok, commit_reason = p1_revalidate_plan_commit(ctx, selected, plan)
	if selected and not commit_ok then
		selected = nil
		plan = nil
	end
	require('uc_scheduler_dryrun_publish').publish(
		scheduler,
		_G,
		ctx,
		selected,
		ranked,
		reject_counts,
		rejected,
		proposals,
		locks,
		plan,
		commit_reason,
		p1_format_top3,
		p1_format_top3_verbose,
		p1_format_topn_lines,
		p1_capture_topn_items,
		p1_push_recent_rejects,
		p1_reject_top,
		p1_set_pending_globals,
		p1_build_lock_summary
	)
end

local function p1_is_tank_enmity_selected(selected)
	return require('uc_scheduler_target_utils').p1_is_tank_enmity_selected(scheduler, selected)
end

local function p1_try_target_prep(target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return false
	end
	local cur = windower.ffxi.get_mob_by_target('t')
	if cur and tonumber(cur.id) == tid then
		return true
	end
	local ok = false
	if uc_settarget and type(uc_settarget.select_by_id) == 'function' then
		ok = (uc_settarget.select_by_id(tid) == true)
	end
	return ok
end

local function p1_target_distance_to_id(target_id)
	return require('uc_scheduler_target_utils').p1_target_distance_to_id(scheduler, target_id)
end

p1_apply_face_to_target = function(settings, target_id)
	if not bool_setting(settings and settings.face, false) then
		return
	end
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return
	end
	local me = windower.ffxi.get_mob_by_target('me')
	local mob = windower.ffxi.get_mob_by_id(tid)
	if not me or not mob then
		return
	end
	-- C5: face only valid combat targets.
	-- If target is not a live monster combat target, do not issue explicit turn.
	local is_valid_combat_target = (mob.valid_target == true)
		and ((tonumber(mob.spawn_type) or 0) == 16)
		and ((tonumber(mob.hpp) or 0) > 0)
	if not is_valid_combat_target then
		return
	end
	if me.x == nil or me.y == nil or mob.x == nil or mob.y == nil then
		return
	end
	-- Match core exactly: atan2(dx, dy) - pi/2.
	local dx = (mob.x - me.x)
	local dy = (mob.y - me.y)
	local heading = math.atan2(dx, dy) - 1.5708
	if heading then
		windower.ffxi.turn(heading)
	end
end

local function p1_move_toward_mob(mob)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or not mob or me.x == nil or me.y == nil or mob.x == nil or mob.y == nil then
		return false
	end
	local heading = math.atan2(mob.y - me.y, mob.x - me.x)
	windower.ffxi.run(heading)
	return true
end

local function p1_try_dark_launch_dispatch(settings)
	local phase = scheduler.phase1
	local selected = phase.last_selected
	local plan = phase.last_plan
	if type(selected) ~= 'table' or type(plan) ~= 'table' then
		return false, nil
	end
	local provider = tostring(selected.provider or '')
	if provider == 'target_control' then
		if not bool_setting(settings and settings.scheduler_dark_launch_combat, false) then
			return false, nil
		end
		local tid = tonumber(selected.target_id) or 0
		if tid <= 0 then
			return false, nil
		end
		local ok = p1_try_target_prep(tid)
		if not ok then
			return false, nil
		end
		-- Target prep is a focus-selection operation, not a cast/JA/WS in-flight action.
		-- Do not enter the global acting lock path here or engage can be delayed by timeout.
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		_G.UC_LAST_SCHED_ACTION = ('[p1]target:%d->%s'):format(tid, tostring(selected.target_name or ''))
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH_TARGET'
	end

	if provider == 'pull_control' then
		if not bool_setting(settings and settings.scheduler_dark_launch_combat, false) then
			return false, nil
		end
		local blocked, b_reason = action_dispatch_blocked()
		if blocked then
			return true, b_reason
		end
		if not combat_core or type(combat_core.dispatch_pull_for_scheduler) ~= 'function' then
			return false, nil
		end
		local tid = tonumber(selected.target_id) or 0
		if tid <= 0 then
			return false, nil
		end
		local ok, reason = combat_core.dispatch_pull_for_scheduler(settings, tid)
		if not ok then
			return false, nil
		end
		local sent = tostring(reason or '') == 'PULL_ACTION_SENT'
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		if sent then
			-- Only create/refresh scheduler pending locks when an actual pull action packet
			-- was sent. Movement/setup states must not enter acting lock bookkeeping.
			action_mark_sent('pull')
			p1_record_legacy_dispatch(ctx)
			p1_set_pending_globals()
			_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		else
			-- Pull move/setup/no-op outcomes should never keep a live pending lock.
			p1_pending_mark_complete(ctx.now, ('pull_no_send:%s'):format(tostring(reason or 'BLOCK')))
			p1_set_pending_globals()
			_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		end
		_G.UC_LAST_SCHED_ACTION = ('[p1]pull:%s->%s:%s'):format(
			tostring(selected.action_name or ''),
			tostring(selected.target_name or ''),
			tostring(reason or '')
		)
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH_PULL'
	end
	if provider == 'combat' then
		_G.UC_TANK_ENMITY_BLOCK = ''
		if not bool_setting(settings and settings.scheduler_dark_launch_combat, false) then
			return false, nil
		end
		p1_apply_face_to_target(settings, tonumber(selected.target_id) or 0)
		log_combat_sched(('dispatch_select type=%s name=\"%s\" target=\"%s\" tid=%d provider=%s family=%s'):format(
			tostring(selected.action_type or ''),
			tostring(selected.action_name or ''),
			tostring(selected.target_name or ''),
			tonumber(selected.target_id) or 0,
			tostring(selected.provider or ''),
			tostring(selected.family_id or '')
		))
		local blocked, b_reason = action_dispatch_blocked()
		if blocked then
			log_combat_sched(('dispatch_block reason=%s type=%s name=\"%s\" tid=%d'):format(
				tostring(b_reason or 'BLOCKED'),
				tostring(selected.action_type or ''),
				tostring(selected.action_name or ''),
				tonumber(selected.target_id) or 0
			))
			return true, b_reason
		end
		local action_type = tostring(selected.action_type or '')
		local tank_enmity = p1_is_tank_enmity_selected(selected)
		local expected_tid = tonumber(selected.target_id) or 0
		local target_kind = tostring(selected.target_kind or 'self')
		if tank_enmity and target_kind == 'mob' and expected_tid > 0 then
			local max_range = math.max(0, p1_number(selected.range_policy and selected.range_policy.max, 0))
			local dist, mob = p1_target_distance_to_id(expected_tid)
			if not mob or not mob.valid_target or (tonumber(mob.hpp) or 0) <= 0 then
				tank_enmity_diag('TANK_ENMITY_DROP_BAD_TARGET', selected, ('dist=%s max=%.2f'):format(tostring(dist), max_range))
				log_combat_sched(('dispatch_drop reason=TANK_BAD_TARGET name=\"%s\" tid=%d'):format(
					tostring(selected.action_name or ''), expected_tid
				))
				return false, nil
			end
			-- Safety: do not force-move from scheduler for tank intents while parity is stabilizing.
			-- Let core movement/follow/spacing continue to own locomotion to avoid run-lock behavior.
			if max_range > 0 and dist and dist > max_range then
				tank_enmity_diag('TANK_ENMITY_DROP_OUT_OF_RANGE', selected, ('dist=%.2f max=%.2f'):format(tonumber(dist) or -1, max_range))
				log_combat_sched(('dispatch_drop reason=TANK_OUT_OF_RANGE name=\"%s\" tid=%d dist=%.2f max=%.2f'):format(
					tostring(selected.action_name or ''), expected_tid, tonumber(dist) or -1, tonumber(max_range) or 0
				))
				return false, nil
			end
			-- Tank enmity dispatch is by target_id; no prep target-switch required.
		end
		if tank_enmity and (action_type == 'ja' or action_type == 'spell') and target_kind == 'mob' and expected_tid > 0 then
			-- Regression guard: always stop briefly before tank enmity action dispatch so we
			-- don't issue JA/spell while still carrying a previous run vector.
			local settle_key = ('%s:%s:%d'):format(action_type, tostring(selected.action_name or ''), expected_tid)
			local now = now_s()
			if tostring(phase.tank_action_settle_key or '') ~= settle_key then
				phase.tank_action_settle_key = settle_key
				phase.tank_action_settle_until = now + 0.25
			end
			windower.ffxi.run(false)
			if now < p1_number(phase.tank_action_settle_until, 0) then
				tank_enmity_diag('TANK_ENMITY_WAIT_ACTION_SETTLE', selected, ('remain=%.2f'):format(p1_number(phase.tank_action_settle_until, 0) - now))
				log_combat_sched(('dispatch_block reason=TANK_ACTION_SETTLE name=\"%s\" tid=%d remain=%.2f'):format(
					tostring(selected.action_name or ''), expected_tid, p1_number(phase.tank_action_settle_until, 0) - now
				))
				_G.UC_LAST_SCHED_ACTION = ('[p1]tank_action_settle:%s->%s'):format(
					tostring(selected.action_name or ''),
					tostring(selected.target_name or '')
				)
				return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_TANK_ACTION_SETTLE'
			end
			phase.tank_action_settle_key = ''
			phase.tank_action_settle_until = 0
		end
		if action_type == 'engage' then
			local target = windower.ffxi.get_mob_by_target('t')
			if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
				local ok_set = p1_try_target_prep(expected_tid)
				if not ok_set then
					log_combat_sched(('engage_drop reason=TARGET_PREP_FAIL expected_tid=%d'):format(expected_tid))
					if bool_setting(settings and settings.debug, false) then
						_G.UC_LAST_SCHED_ACTION = ('[p1]engage:dispatch_fail:settarget tid=%d'):format(expected_tid)
					end
					return false, nil
				end
			end
			local p = windower.ffxi.get_player()
			if p and tonumber(p.status) == 1 then
				local cur = windower.ffxi.get_mob_by_target('t')
				if cur and tonumber(cur.id) == expected_tid then
					log_combat_sched(('engage_drop reason=ALREADY_ENGAGED expected_tid=%d'):format(expected_tid))
					_G.UC_LAST_SCHED_ACTION = ('[p1]engage:already:%s'):format(tostring(selected.target_name or ''))
					return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_ENGAGED'
				end
			end
			if not uc_attack or type(uc_attack.engage_target) ~= 'function' then
				log_combat_sched('engage_drop reason=NO_UC_ATTACK')
				if bool_setting(settings and settings.debug, false) then
					_G.UC_LAST_SCHED_ACTION = '[p1]engage:dispatch_fail:no_uc_attack'
				end
				return false, nil
			end
			local ok_attack, engage_reason = uc_attack.engage_target(expected_tid)
			if not ok_attack then
				log_combat_sched(('engage_send_fail tid=%d reason=%s'):format(expected_tid, tostring(engage_reason or 'ENGAGE_FAIL')))
				if bool_setting(settings and settings.debug, false) then
					_G.UC_LAST_SCHED_ACTION = ('[p1]engage:dispatch_fail:%s'):format(tostring(engage_reason or 'ENGAGE_FAIL'))
				end
				return false, nil
			end
			action_mark_sent('engage')
			log_combat_sched(('engage_send_ok tid=%d target=\"%s\"'):format(expected_tid, tostring(selected.target_name or '')))
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:sent:%s'):format(tostring(selected.target_name or ''))
		elseif action_type == 'ws' then
			local player = windower.ffxi.get_player()
			if not player or tonumber(player.status) ~= 1 then
				return false, nil
			end
			local tp = tonumber(player.vitals and player.vitals.tp) or 0
			if tp < 1000 then
				return false, nil
			end
			local target = windower.ffxi.get_mob_by_target('t')
			if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
				return false, nil
			end
			local ws = tostring(selected.action_name or '')
			if ws == '' then
				return false, nil
			end
			if combat_core and type(combat_core.try_dispatch_ws_with_intent) == 'function' then
				local sent, why = combat_core.try_dispatch_ws_with_intent(ws, expected_tid, settings)
				if not sent then
					_G.UC_LAST_SCHED_ACTION = ('[p1]ws_hold:%s:%s'):format(ws, tostring(why or 'BLOCK'))
					return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_WS_INTENT'
				end
				action_mark_sent('ws')
			else
				windower.send_command(('input /ws \"%s\" <t>'):format(ws))
				action_mark_sent('ws')
			end
			_G.UC_LAST_SCHED_ACTION = ('[p1]ws:%s->%s'):format(ws, tostring(selected.target_name or ''))
		elseif action_type == 'ja' then
			local ability = tostring(selected.action_name or '')
			if ability == '' then
				log_combat_sched('dispatch_drop reason=JA_EMPTY')
				return false, nil
			end
			local ok_ready, reason, action_kind = action_ready(ability, expected_tid)
			if action_kind ~= 'ja' or not ok_ready then
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_DROP_JA_NOT_READY', selected, ('reason=%s kind=%s'):format(tostring(reason or ''), tostring(action_kind or '')))
				end
				log_ja_sched(('dispatch_block name=\"%s\" reason=%s kind=%s status=%s pending=%s'):format(
					tostring(ability),
					tostring(reason or 'NOT_READY'),
					tostring(action_kind or ''),
					tostring((windower.ffxi.get_player() or {}).status or ''),
					tostring((scheduler.phase1.pending and scheduler.phase1.pending.action_name) or '')
				))
				return false, nil
			end
			if target_kind == 'mob' then
				-- For tank-enmity parity, we dispatch JA by id after scheduler target prep.
				if not tank_enmity then
					local target = windower.ffxi.get_mob_by_target('t')
					if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
						return false, nil
					end
				end
				windower.send_command(('input /ja \"%s\" %d'):format(ability, expected_tid))
				action_mark_sent('ja')
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_SEND_JA', selected, 'mode=target_id')
				end
				log_ja_sched(('dispatch_send name=\"%s\" mode=target tid=%d'):format(tostring(ability), tonumber(expected_tid) or 0))
			else
				if tank_enmity then
					windower.ffxi.run(false)
				end
				windower.send_command(('input /ja \"%s\" <me>'):format(ability))
				action_mark_sent('ja')
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_SEND_JA', selected, 'mode=self')
				end
				log_ja_sched(('dispatch_send name=\"%s\" mode=self'):format(tostring(ability)))
			end
			_G.UC_LAST_SCHED_ACTION = ('[p1]ja:%s->%s'):format(ability, tostring(selected.target_name or ''))
	elseif action_type == 'spell' then
			local spell = tostring(selected.action_name or '')
			if spell == '' then
				log_combat_sched('dispatch_drop reason=SPELL_EMPTY')
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_DROP_SPELL_EMPTY', selected, '')
				end
				return false, nil
			end
			local prep_now = now_s()
			local prep_key = ('%s:%d'):format(spell, tonumber(selected.target_id) or 0)
			local active_key = tostring(rawget(_G, 'UC_MOVE_FREEZE_PREP_KEY') or '')
			local prep_until = tonumber(rawget(_G, 'UC_MOVE_FREEZE_PREP_UNTIL')) or 0
			if active_key ~= prep_key then
				_G.UC_MOVE_FREEZE_PREP_KEY = prep_key
				_G.UC_MOVE_FREEZE_PREP_UNTIL = prep_now + 0.75
				windower.ffxi.run(false)
				_G.UC_LAST_SCHED_ACTION = ('[p1]spell_settle:%s->%s'):format(spell, tostring(selected.target_name or ''))
				return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_SPELL_SETTLE'
			end
			if prep_now < prep_until then
				windower.ffxi.run(false)
				_G.UC_LAST_SCHED_ACTION = ('[p1]spell_prep:%s->%s'):format(spell, tostring(selected.target_name or ''))
				return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_SPELL_PREP'
			end
			_G.UC_MOVE_FREEZE_PREP_KEY = ''
			_G.UC_MOVE_FREEZE_PREP_UNTIL = 0
			local ok_ready, ready_reason, action_kind = action_ready(spell)
			if action_kind ~= 'spell' or not ok_ready then
				log_combat_sched(('dispatch_drop reason=SPELL_NOT_READY spell=\"%s\" ready_reason=%s kind=%s'):format(
					tostring(spell), tostring(ready_reason or ''), tostring(action_kind or '')
				))
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_DROP_SPELL_NOT_READY', selected, ('reason=%s kind=%s'):format(tostring(ready_reason or ''), tostring(action_kind or '')))
				end
				return false, nil
			end
			if tank_enmity then
				local settle_key = ('%s:%d'):format(spell, expected_tid)
				local now = now_s()
				if tostring(phase.tank_spell_settle_key or '') ~= settle_key then
					phase.tank_spell_settle_key = settle_key
					phase.tank_spell_settle_until = now + 0.75
				end
				windower.ffxi.run(false)
				if now < p1_number(phase.tank_spell_settle_until, 0) then
					tank_enmity_diag('TANK_ENMITY_WAIT_SPELL_SETTLE', selected, ('remain=%.2f'):format(p1_number(phase.tank_spell_settle_until, 0) - now))
					log_combat_sched(('dispatch_block reason=TANK_SPELL_SETTLE spell=\"%s\" tid=%d remain=%.2f'):format(
						tostring(spell), expected_tid, p1_number(phase.tank_spell_settle_until, 0) - now
					))
					_G.UC_LAST_SCHED_ACTION = ('[p1]tank_settle:%s->%s'):format(spell, tostring(selected.target_name or ''))
					return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_TANK_SETTLE'
				end
				phase.tank_spell_settle_key = ''
				phase.tank_spell_settle_until = 0
			end
			if target_kind == 'mob' then
				if not tank_enmity then
					local target = windower.ffxi.get_mob_by_target('t')
					if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
						return false, nil
					end
				end
				if tank_enmity then
					windower.ffxi.run(false)
				end
				windower.send_command(('input /ma \"%s\" %d'):format(spell, expected_tid))
				action_mark_sent('spell')
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_SEND_SPELL', selected, 'mode=target_id')
				end
			else
				if tank_enmity then
					windower.ffxi.run(false)
				end
				windower.send_command(('input /ma \"%s\" <me>'):format(spell))
				action_mark_sent('spell')
				if tank_enmity then
					tank_enmity_diag('TANK_ENMITY_SEND_SPELL', selected, 'mode=self')
				end
			end
			_G.UC_LAST_SCHED_ACTION = ('[p1]spell:%s->%s'):format(spell, tostring(selected.target_name or ''))
		else
			if tank_enmity then
				tank_enmity_diag('TANK_ENMITY_DROP_UNSUPPORTED_ACTION_TYPE', selected, ('action_type=%s'):format(action_type))
			end
			return false, nil
		end
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT'
	end
	if provider == 'defensive_internal' then
		if not bool_setting(settings and settings.scheduler_dark_launch_defensive, false) then
			return false, nil
		end
		local blocked, b_reason = action_dispatch_blocked()
		if blocked then
			return true, b_reason
		end
		local cmd = tostring(selected.legacy_command or '')
		if cmd == '' then
			return false, nil
		end
		local ok_ready, _, action_kind = action_ready(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0)
		if action_kind == 'none' then
			return false, nil
		end
		if not ok_ready then
			return false, nil
		end
		local p = windower.ffxi.get_player()
		local out_of_combat = (tonumber(p and p.status) or 0) ~= 1
		local now_gate = now_s()
		local preengage_move_active = (rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true)
		local follow_run_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL')) or 0
		local follow_run_active = (rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE') == true) or (now_gate < follow_run_until)
		local follow_catchup_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL')) or 0
		local follow_needs_catchup = (rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP') == true) or (now_gate < follow_catchup_until)
		if action_kind == 'spell' and out_of_combat and preengage_move_active then
			_G.UC_LAST_SCHED_ACTION = ('[p1]defer_preengage_move:%s->%s'):format(
				tostring(selected.action_name or ''),
				tostring(selected.target_name or '')
			)
			return true, 'BLOCK_DEFENSIVE_PREENGAGE_MOVE_ACTIVE'
		end
		if action_kind == 'spell' and out_of_combat and (follow_run_active or follow_needs_catchup) then
			_G.UC_LAST_SCHED_ACTION = ('[p1]defer_follow_move:%s->%s'):format(
				tostring(selected.action_name or ''),
				tostring(selected.target_name or '')
			)
			return true, 'BLOCK_DEFENSIVE_FOLLOW_MOVE_ACTIVE'
		end
		windower.send_command(cmd)
		action_mark_sent(action_kind or selected.action_type or 'defensive_internal')
		local dispatch_now = now_s()
		local d = selected.detail
		if type(d) == 'table' and tostring(d.enemy_dispel_attempt_key or '') ~= '' then
			mark_enemy_dispel_attempt(tostring(d.enemy_dispel_attempt_key), dispatch_now)
		end
		local ctx = { now = dispatch_now, tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		_G.UC_LAST_SCHED_ACTION = ('[p1]%s->%s'):format(tostring(selected.action_name or ''), tostring(selected.target_name or ''))
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH'
	end
	if provider == 'defensive_healbot' then
		if not bool_setting(settings and settings.scheduler_dark_launch_defensive, false) then
			return false, nil
		end
		local blocked, b_reason = action_dispatch_blocked()
		if blocked then
			return true, b_reason
		end
		local hb_action = selected.detail and selected.detail.healbot_action or nil
		if type(hb_action) ~= 'table' then
			return false, nil
		end
		local ok_actions = type(rawget(_G, 'actions')) == 'table' and type(_G.actions.get_defensive_action) == 'function'
		local ok_healer = type(rawget(_G, 'healer')) == 'table' and type(_G.healer.take_action) == 'function'
		if not ok_actions or not ok_healer then
			return false, nil
		end
		_G.healer:take_action(hb_action)
		action_mark_sent('defensive_healbot')
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		_G.UC_LAST_SCHED_ACTION = ('[p1]hb:%s->%s'):format(tostring(selected.action_name or ''), tostring(selected.target_name or ''))
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH_HEALBOT'
	end
	-- C1 codification:
	-- mobility provider dispatch removed from ranked proposal execution.
	if provider == 'maintenance_cor' then
		if not bool_setting(settings and settings.scheduler_dark_launch_maintenance, false) then
			log_def_sched('MAINT_COR_DISPATCH_SKIP reason=TOGGLE_OFF')
			return false, nil
		end
		local blocked, b_reason = action_dispatch_blocked()
		if blocked then
			log_def_sched(('MAINT_COR_DISPATCH_BLOCK reason=%s'):format(tostring(b_reason or 'BLOCKED')))
			return true, b_reason
		end
		local ability = tostring(selected.action_name or '')
		if ability == '' then
			log_def_sched('MAINT_COR_DISPATCH_SKIP reason=EMPTY_ACTION')
			return false, nil
		end
		local ok_ready, ready_reason, action_kind = action_ready(ability)
		if action_kind ~= 'ja' or not ok_ready then
			log_def_sched(('MAINT_COR_DISPATCH_SKIP reason=NOT_READY action=\"%s\" kind=%s ready_kind=%s ready_reason=%s'):format(
				tostring(ability),
				'ja',
				tostring(action_kind or ''),
				tostring(ready_reason or '')
			))
			return false, nil
		end
		log_def_sched(('MAINT_COR_DISPATCH_SEND action=\"%s\"'):format(tostring(ability)))
		windower.send_command(('input /ja \"%s\" <me>'):format(ability))
		action_mark_sent(action_kind or 'ja')
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		_G.UC_LAST_SCHED_ACTION = ('[p1]cor:%s'):format(ability)
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH_MAINT_COR'
	end
	return false, nil
end

function scheduler.process_tick(cadence)
	_G.UC_LAST_SCHED_ACTION = ''
	local s = get_settings()
	if type(cadence) == 'table' then
		s._sched_next_defensive_at = tonumber(cadence.next_defensive_at) or 0
		s._sched_next_maintenance_at = tonumber(cadence.next_maintenance_at) or 0
	end
	_G.UC_LOG_COMBAT_SCHED = bool_setting(s and s.log_combat_sched, false)
	_G.UC_LOG_JA_SCHED = bool_setting(s and s.log_ja_sched, false)
	_G.UC_LOG_JA_DEBUG = bool_setting(s and s.log_ja_debug, false)
	_G.UC_LOG_DEF_SCHED = bool_setting(s and s.log_def_sched, false)
	_G.UC_LOG_TANK_SCHED = bool_setting(s and s.log_tank_sched, false)
	ensure_diag_logs_initialized()
	maybe_broadcast_party_state_ipc()
	local doom_blocked, doom_reason = try_doom_water_emergency(s)
	if doom_blocked then
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		return true, doom_reason
	end
	p1_run_dry(s)
	local p1_acted, p1_reason = p1_try_dark_launch_dispatch(s)
	local move_acted, move_reason = run_movement_coordinator_tick()
	if p1_acted then
		if move_acted then
			_G.UC_LAST_SCHED_ACTION = tostring(_G.UC_LAST_SCHED_ACTION or '') .. '|move'
		elseif move_reason and move_reason ~= '' then
			_G.UC_MOVEMENT_BLOCK_REASON = move_reason
		end
		return true, p1_reason
	end
	if move_acted then
		_G.UC_LAST_SCHED_ACTION = '[move]coordinator_tick'
	end
	if not bool_setting(s.defensive_enabled, false) then
		return false, nil
	end
	local provider = tostring(s.defensive_provider or 'internal')
	_G.UC_SCHED_PROVIDER = provider
	local acted, reason
	if provider == 'healbot' then
		acted, reason = try_delegate_healbot()
		if not acted and reason == 'BLOCK_DEFENSIVE_PROVIDER_UNAVAILABLE' then
			_G.UC_LAST_SCHED_ACTION = 'healbot_unavailable_no_block'
			return false, nil
		end
		if acted then
			local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
			p1_record_legacy_dispatch(ctx)
			p1_set_pending_globals()
			_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
			return true, reason
		end
		return false, nil
	end
	acted, reason = try_internal_defensive_action()
	if acted then
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		return true, reason
	end
	return false, nil
end

function scheduler.on_ipc_message(msg)
	apply_party_state_ipc_message(msg)
end

function scheduler.on_incoming_chunk(id, data)
	local nid = tonumber(id) or 0
	if nid == 0x00A or nid == 0x00B then
		enemy_effect_tracker.clear_all()
		scheduler.phase1.effectiveTargets = {}
		return
	end
	if nid == 0x028 and type(data) == 'string' then
		ingest_enemy_effects_from_raw_action_028(data)
		return
	end
	if nid == 0x029 and type(data) == 'string' then
		-- Mirror TargetBar: parse Action Message directly from raw packet bytes.
		local msg = {
			actor_id = data:unpack('I', 0x05),
			target_id = data:unpack('I', 0x09),
			param_1 = data:unpack('I', 0x0D),
			effect_id = data:unpack('I', 0x0D),
			message_id = data:unpack('H', 0x19) % 32768,
			_uc_source = 'raw_029',
		}
		local tid = tonumber(msg.target_id) or 0
		local mid = tonumber(msg.message_id) or 0
		local eid = tonumber(msg.effect_id) or 0
		if tid > 0 then
			if raw_enemy_death_messages[mid] == true then
				enemy_effect_state_clear_target(tid)
			elseif raw_enemy_remove_messages[mid] == true then
				enemy_effect_state_clear(tid, eid)
			end
		end
		pcall(scheduler.on_action_message, msg)
		local phase = scheduler.phase1 or {}
		phase.last_action_message_sig = table.concat({
			tostring(tonumber(msg.actor_id) or 0),
			tostring(tonumber(msg.target_id) or 0),
			tostring(tonumber(msg.message_id) or 0),
			tostring(tonumber(msg.effect_id) or 0),
		}, ':')
		phase.last_action_message_sig_at = now_s()
		scheduler.phase1 = phase
		return
	end
	if nid ~= 0x063 then
		return
	end
	local player = windower.ffxi.get_player()
	if not player or not player.name then
		return
	end
	local snap = parse_status_snapshot_063(data)
	if not snap then
		return
	end
	local st = ensure_maintenance_state_tables()
	st.status_snapshot[tostring(player.name)] = snap
end

function scheduler.on_action(act)
	if type(act) == 'table' then
		local p = windower.ffxi.get_player()
		tb_effect_table.apply_from_action(
			act,
			tonumber(p and p.id) or 0,
			enemy_effect_state_set,
			enemy_effect_state_clear,
			now_s()
		)
	end
	local cfg = rawget(_G, 'UC_SETTINGS') or {}
	local dbg_enemy_raw = _G.UC_LOG_DEF_SCHED and bool_setting(cfg.def_remove_enemy_buffs, false)
	local raw_actor_id = tonumber(act and act.actor_id) or 0
	local raw_actor = raw_actor_id > 0 and windower.ffxi.get_mob_by_id(raw_actor_id) or nil
	if dbg_enemy_raw and raw_actor and tonumber(raw_actor.spawn_type) == 16 then
		enemy_dispel_log(('ENEMY_RAW_ACTION actor=%d name=\"%s\" category=%s targets=%d'):format(
			raw_actor_id,
			tostring(raw_actor.name or '?'),
			tostring(act and act.category or ''),
			type(act and act.targets) == 'table' and #act.targets or 0
		))
	end
	local evs = enemy_effect_tracker.on_action(act, dispellable_enemy_effect_set) or {}
	for _, ev in ipairs(evs) do
		enemy_dispel_log(('ENEMY_TRACK event=%s source=%s target=%d effect=%d'):format(
			tostring(ev.event or ''),
			tostring(ev.source or ''),
			tonumber(ev.target_id) or 0,
			tonumber(ev.effect_id) or 0
		))
	end
	-- Debug-only visibility into enemy self-buff params we do not currently classify as dispellable.
	-- Helps map cases like Scissor Guard when packet effect ids differ from assumptions.
	if _G.UC_LOG_DEF_SCHED and bool_setting(cfg.def_remove_enemy_buffs, false) then
		local actor_id = tonumber(act and act.actor_id) or 0
		local actor = actor_id > 0 and windower.ffxi.get_mob_by_id(actor_id) or nil
		if actor and tonumber(actor.spawn_type) == 16 and type(act and act.targets) == 'table' then
			for _, t in ipairs(act.targets) do
				local tid = tonumber(t and t.id) or 0
				if type(t.actions) == 'table' then
					for _, a in ipairs(t.actions) do
						if dbg_enemy_raw then
							enemy_dispel_log(('ENEMY_RAW_ACTION_DETAIL actor=%d target=%d msg=%d param=%d add=%d spike=%d'):format(
								actor_id,
								tid,
								tonumber(a and a.message) or 0,
								tonumber(a and a.param) or 0,
								tonumber(a and a.add_effect_param) or 0,
								tonumber(a and a.spike_effect_param) or 0
							))
						end
						local candidates = {
							tonumber(a and a.param) or 0,
							tonumber(a and a.add_effect_param) or 0,
							tonumber(a and a.spike_effect_param) or 0,
						}
						for _, eid in ipairs(candidates) do
							if eid > 0 and not dispellable_enemy_effect_set[eid] then
								local k = ('act:%d:%d'):format(eid, tonumber(a and a.message) or 0)
								if not enemy_effect_observed_once[k] then
									enemy_effect_observed_once[k] = true
									enemy_dispel_log(('ENEMY_EFFECT_OBS source=action actor=%d target=%d effect=%d msg=%d dispel_known=false'):format(
										actor_id,
										tid,
										eid,
										tonumber(a and a.message) or 0
									))
								end
							end
						end
					end
				end
			end
		end
	end
	local player = windower.ffxi.get_player()
	local my_id = tonumber(player and player.id) or 0
	local actor_id = tonumber(act and act.actor_id) or 0
	local category = tostring(act and act.category or '')
	local start_lock_categories = {
		spell = true,
		spell_finish = true,
		job_ability = true,
		job_ability_unblinkable = true,
		weaponskill = true,
		weapon_skill = true,
		ranged_attack = true,
		item = true,
	}
	if my_id ~= 0 and actor_id == my_id then
		-- HealBot-style actor-centric start lock, but scoped to real cast/action categories.
		-- Do not treat generic/melee action traffic as lock-start signals.
		if start_lock_categories[category] then
			action_mark_packet_start()
		end
	end

	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	local now = now_s()
	local state_name = tostring(pending.state or '')
	if not p1_pending_is_live_state(state_name) then
		return
	end
	if my_id ~= 0 and actor_id == my_id then
		pending.state = 'acknowledged'
		pending.ack_at = now
	end
	local expected_tid = tonumber(pending.target_id) or 0
	if expected_tid ~= 0 and type(act and act.targets) == 'table' then
		for _, t in ipairs(act.targets) do
			if tonumber(t and t.id) == expected_tid then
				p1_pending_mark_complete(now, 'action_target_effect')
				break
			end
		end
	end
end

function scheduler.on_action_message(msg)
	local phase = scheduler.phase1 or {}
	if tostring(msg and msg._uc_source or '') ~= 'raw_029' then
		local sig = table.concat({
			tostring(tonumber(msg and msg.actor_id) or 0),
			tostring(tonumber(msg and msg.target_id) or 0),
			tostring(tonumber(msg and msg.message_id) or 0),
			tostring(tonumber(msg and msg.effect_id) or tonumber(msg and msg.param_1) or 0),
		}, ':')
		local last_sig = tostring(phase.last_action_message_sig or '')
		local last_at = tonumber(phase.last_action_message_sig_at) or 0
		local now = now_s()
		if sig ~= '' and sig == last_sig and last_at > 0 and (now - last_at) <= 0.25 then
			return
		end
	end
	local cfg = rawget(_G, 'UC_SETTINGS') or {}
	local dbg_enemy_raw = _G.UC_LOG_DEF_SCHED and bool_setting(cfg.def_remove_enemy_buffs, false)
	if dbg_enemy_raw then
		local ra = tonumber(msg and msg.actor_id) or 0
		local rt = tonumber(msg and msg.target_id) or 0
		local actor = ra > 0 and windower.ffxi.get_mob_by_id(ra) or nil
		local target = rt > 0 and windower.ffxi.get_mob_by_id(rt) or nil
		if (actor and tonumber(actor.spawn_type) == 16) or (target and tonumber(target.spawn_type) == 16) then
			enemy_dispel_log(('ENEMY_RAW_MSG actor=%d target=%d msg=%d p1=%d p2=%d p3=%d actor_name=\"%s\"'):format(
				ra, rt,
				tonumber(msg and msg.message_id) or 0,
				tonumber(msg and msg.param_1) or 0,
				tonumber(msg and msg.param_2) or 0,
				tonumber(msg and msg.param_3) or 0,
				tostring((actor and actor.name) or '?')
			))
		end
	end
	local evs = enemy_effect_tracker.on_action_message(msg, dispellable_enemy_effect_set) or {}
	local removed_enemy_effect = false
	for _, ev in ipairs(evs) do
		if tostring(ev.event or '') == 'remove' then
			removed_enemy_effect = true
		end
		enemy_dispel_log(('ENEMY_TRACK event=%s source=%s target=%d effect=%d'):format(
			tostring(ev.event or ''),
			tostring(ev.source or ''),
			tonumber(ev.target_id) or 0,
			tonumber(ev.effect_id) or 0
		))
	end
	if _G.UC_LOG_DEF_SCHED and bool_setting(cfg.def_remove_enemy_buffs, false) then
		local actor_id = tonumber(msg and msg.actor_id) or 0
		local target_id = tonumber(msg and msg.target_id) or 0
		local effect_id = tonumber(msg and msg.param_1) or 0
		local message_id = tonumber(msg and msg.message_id) or 0
		local target = target_id > 0 and windower.ffxi.get_mob_by_id(target_id) or nil
		if effect_id > 0 and target and tonumber(target.spawn_type) == 16 and target_id == actor_id and not dispellable_enemy_effect_set[effect_id] then
			local k = ('msg:%d:%d'):format(effect_id, message_id)
			if not enemy_effect_observed_once[k] then
				enemy_effect_observed_once[k] = true
				enemy_dispel_log(('ENEMY_EFFECT_OBS source=action_message actor=%d target=%d effect=%d msg=%d dispel_known=false'):format(
					actor_id, target_id, effect_id, message_id
				))
			end
		end
	end
	local player = windower.ffxi.get_player()
	local my_id = tonumber(player and player.id) or 0
	local actor_id = tonumber(msg and msg.actor_id) or 0
	local message_id = tonumber(msg and msg.message_id) or 0
	-- No inference-based fallback here; enemy effect state is maintained from raw 0x028/0x029 packets.
	if my_id ~= 0 and actor_id == my_id and message_id ~= 0 then
		-- Actor-centric lock state (HealBot-style): always honor self action-complete messages,
		-- independent of scheduler pending bookkeeping.
		action_mark_packet_end()
	end

	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	local now = now_s()
	local state_name = tostring(pending.state or '')
	if not p1_pending_is_live_state(state_name) and state_name ~= 'acknowledged' then
		return
	end
	if my_id ~= 0 and actor_id ~= my_id then
		return
	end
	local expected_tid = tonumber(pending.target_id) or 0
	local msg_tid = tonumber(msg and msg.target_id) or 0
	if expected_tid ~= 0 and msg_tid ~= 0 and expected_tid ~= msg_tid then
		return
	end
	if message_id ~= 0 then
		p1_pending_mark_complete(now, ('msg_%d'):format(message_id))
	end
end

_G.UC_SCHED_OnAction = function(act)
	local ok = pcall(scheduler.on_action, act)
	if not ok then
		-- scheduler hooks are best-effort; never destabilize combat tick.
	end
end

_G.UC_SCHED_OnActionMessage = function(msg)
	local ok = pcall(scheduler.on_action_message, msg)
	if not ok then
		-- scheduler hooks are best-effort; never destabilize combat tick.
	end
end

_G.UC_SCHED_OnIpcMessage = function(msg)
	local ok = pcall(scheduler.on_ipc_message, msg)
	if not ok then
		-- scheduler hooks are best-effort; never destabilize combat tick.
	end
end

_G.UC_SCHED_OnIncomingChunk = function(id, data)
	local ok = pcall(scheduler.on_incoming_chunk, id, data)
	if not ok then
		-- scheduler hooks are best-effort; never destabilize combat tick.
	end
end

_G.UC_COR_MAINT_OnIncomingChunk = function(id, data)
	if cor_maintenance and type(cor_maintenance.update_from_incoming_chunk) == 'function' then
		pcall(cor_maintenance.update_from_incoming_chunk, id, data)
	end
end

function scheduler.get_debug_overlay()
	local phase = scheduler.phase1 or {}
	local s = get_settings()
	local function build_buff_up_lines()
		local lines = {}
		local function buff_label_from_id(bid)
			local id = tonumber(bid) or 0
			if id <= 0 then
				return ''
			end
			local b = res.buffs and res.buffs[id] or nil
			local bn = tostring((b and b.en) or ('id:' .. tostring(id)))
			return ('%s[%d]'):format(bn, id)
		end
		local function buff_labels(list)
			local out = {}
			for _, bid in ipairs(list or {}) do
				local lbl = buff_label_from_id(bid)
				if lbl ~= '' then
					out[#out + 1] = lbl
				end
			end
			return out
		end
		local function pad_right(s, w)
			local t = tostring(s or '')
			local n = w - #t
			if n <= 0 then
				return t
			end
			return t .. string.rep(' ', n)
		end

		local members = get_party_members()
		if type(members) ~= 'table' or #members == 0 then
			lines[#lines + 1] = 'self: (no party member view)'
			return lines
		end
		local self_member = nil
		for _, m in ipairs(members) do
			if m and m.is_self == true then
				self_member = m
				break
			end
		end
		if not self_member then
			lines[#lines + 1] = 'self: (not found in scheduler member view)'
			return lines
		end
		local self_name = tostring(self_member.name or '')
		local self_source = tostring(self_member.source or 'unknown')

		-- Effective buffs used by scheduler evaluation.
		local eval_buffs = self_member.buffs or {}

		-- Raw source views for side-by-side comparison.
		local p = windower.ffxi.get_player()
		local self_local_buffs = (p and p.buffs) or {}

		local ipc_buffs = {}
		do
			local ipc = get_party_state_ipc_entry(tonumber(self_member.id) or 0, self_name)
			if ipc and type(ipc.buffs) == 'table' then
				ipc_buffs = ipc.buffs
			end
		end

		local party_buffs = {}
		do
			local party = windower.ffxi.get_party() or {}
			local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
			for _, k in ipairs(keys) do
				local e = party[k]
				if e and e.mob and tonumber(e.mob.id) == tonumber(self_member.id) then
					party_buffs = e.buffs or {}
					break
				end
			end
		end

		local st = ensure_maintenance_state_tables()
		local snap = (st.status_snapshot or {})[self_name]
		local snap_count = 0
		if type(snap) == 'table' then
			for _, _ in pairs(snap) do
				snap_count = snap_count + 1
			end
		end

		lines[#lines + 1] = ('eval_source=%s self=%s snapshot_ids=%d'):format(self_source, self_name, snap_count)

		local col_eval = buff_labels(eval_buffs)
		local col_self = buff_labels(self_local_buffs)
		local col_ipc = buff_labels(ipc_buffs)
		local col_party = buff_labels(party_buffs)
		local max_rows = math.max(#col_eval, #col_self, #col_ipc, #col_party)
		local show_rows = math.max(1, max_rows)

		local w_eval, w_self, w_ipc = 30, 30, 30
		lines[#lines + 1] = pad_right('eval(used)', w_eval) .. ' | '
			.. pad_right('self_local', w_self) .. ' | '
			.. pad_right('ipc', w_ipc) .. ' | party'

		for i = 1, show_rows do
			local e = col_eval[i] or ''
			local sl = col_self[i] or ''
			local ip = col_ipc[i] or ''
			local pa = col_party[i] or ''
			lines[#lines + 1] = pad_right(e, w_eval) .. ' | '
				.. pad_right(sl, w_self) .. ' | '
				.. pad_right(ip, w_ipc) .. ' | ' .. pa
		end
		return lines
	end
	local function enabled_for_provider(provider)
		local p = tostring(provider or '')
		if p == 'combat' then
			return bool_setting(s.scheduler_dark_launch_combat, false)
		elseif p == 'defensive_internal' then
			return bool_setting(s.scheduler_dark_launch_defensive, false)
		elseif p == 'defensive_healbot' then
			return bool_setting(s.scheduler_dark_launch_defensive, false)
		elseif p == 'maintenance_cor' then
			return bool_setting(s.scheduler_dark_launch_maintenance, false)
		end
		return false
	end
	local queued = {}
	for _, item in ipairs(phase.last_top5_items or {}) do
		if enabled_for_provider(item.provider) then
			queued[#queued + 1] = ('%d) %.2f %s/%s %s u=%.2f rp=%.2f'):format(
				tonumber(item.idx) or 0,
				tonumber(item.score) or 0,
				tostring(item.provider or ''),
				tostring(item.family or ''),
				tostring(item.action or ''),
				tonumber(item.urgency_bonus) or 0,
				tonumber(item.risk_penalty) or 0
			)
		end
	end
	local rejected = {}
	local rri = phase.recent_reject_items or {}
	local accepted = {}
	for _, item in ipairs(rri) do
		if enabled_for_provider(item.provider) then
			accepted[#accepted + 1] = item
		end
	end
	local start = math.max(1, #accepted - 4)
	for i = #accepted, start, -1 do
		local item = accepted[i]
		rejected[#rejected + 1] = ('t%s %s/%s %s :: %s'):format(
			tostring(item.tick or ''),
			tostring(item.provider or ''),
			tostring(item.family or ''),
			tostring(item.action or ''),
			tostring(item.reason or '')
		)
	end
	return {
		tick = p1_number(phase.tick, 0),
		queued = queued,
		rejected = rejected,
		buff_up = build_buff_up_lines(),
	}
end

function scheduler.reset_runtime_locks()
	scheduler_locks.reset_runtime_locks(_G, action_state)
end

_G.UC_ResetSchedulerRuntimeLocks = function()
	if scheduler and type(scheduler.reset_runtime_locks) == 'function' then
		scheduler.reset_runtime_locks()
	end
end

function scheduler.get_enemy_effect_table_overlay()
	enemy_effect_state_prune_expired(now_s())
	local phase = scheduler.phase1 or {}
	local et = type(phase.effectiveTargets) == 'table' and phase.effectiveTargets or {}
	local lines = { 'Enemy Effect Table (effectiveTargets)' }
	local target_ids = {}
	for tid, effects in pairs(et) do
		if type(effects) == 'table' then
			target_ids[#target_ids + 1] = tonumber(tid) or 0
		end
	end
	table.sort(target_ids)
	if #target_ids == 0 then
		lines[#lines + 1] = '(none)'
		return { lines = lines }
	end
	for _, tid in ipairs(target_ids) do
		if tid > 0 then
			local mob = windower.ffxi.get_mob_by_id(tid)
			local mname = tostring((mob and mob.name) or '?')
			local hpp = tonumber((mob and mob.hpp) or 0) or 0
			lines[#lines + 1] = ('%s[%d] hpp=%d'):format(mname, tid, hpp)
			local effects = et[tid] or et[tostring(tid)] or {}
			local eids = {}
			for eid, _ in pairs(effects) do
				local n = tonumber(eid) or 0
				if n > 0 then
					eids[#eids + 1] = n
				end
			end
			table.sort(eids)
			if #eids == 0 then
				lines[#lines + 1] = '  (no effects)'
			else
				for _, eid in ipairs(eids) do
					local b = res.buffs and res.buffs[eid] or nil
					local bn = tostring((b and b.en) or ('id:' .. tostring(eid)))
					local rec = effects[eid] or effects[tostring(eid)] or {}
					local src = tostring(rec.source or '')
					if src ~= '' then
						lines[#lines + 1] = ('  - %s(%d) src=%s'):format(bn, eid, src)
					else
						lines[#lines + 1] = ('  - %s(%d)'):format(bn, eid)
					end
				end
			end
		end
	end
	return { lines = lines }
end

return scheduler

