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
local uc_active_config = require('uc_active_config')
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
		tank_spell_waiting = false,
		tank_spell_wait_until = 0,
		tank_pending_action = '',
		tank_pending_target_id = 0,
		tank_pending_sent_at = 0,
		tank_action_settle_key = '',
		tank_action_settle_until = 0,
		pending_engage = nil,
		engage_duplicate = nil,
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
	spell_lifecycle_probe_state = {
		token = '',
		local_events = {},
		recent_events = {},
		text_events = {},
		candidate_cast_complete = false,
		candidate_cast_interrupted = false,
	},
	defensive_spell_waiting = false,
	defensive_spell_wait_until = 0,
	defensive_pending_action = '',
	defensive_pending_target_id = 0,
	defensive_pending_sent_at = 0,
}

local can_act_statuses = { [0] = true, [1] = true, [5] = true, [85] = true }
local doom_buff_id = nil
local doom_last_item_at = 0
local DOOM_ITEM_COOLDOWN = 1.2
local choose_cure_spell
local BRD_OVERWRITE_CLUSTER_SECONDS = 5
local BRD_OVERWRITE_SAFETY_SECONDS = 6
scheduler.PENDING_ENGAGE_TIMEOUT_S = 1.75
scheduler.PENDING_ENGAGE_RETRY_DELAY_S = 0.40
scheduler.ENGAGE_REJECT_WAIT_LONGER_MESSAGE_ID = 94
scheduler.ENGAGE_DUPLICATE_RETRY_DEBOUNCE_S = 0.30
scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON = 'attack_on'

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

local function promoted_ownership_kill_switch_enabled()
	return rawget(_G, 'UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP') == true
end

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

local function action_mark_sent(kind, meta)
	if type(meta) == 'table' then
		return require('uc_scheduler_action_state').action_mark_sent_with_meta(scheduler, kind, now_s, meta)
	end
	return require('uc_scheduler_action_state').action_mark_sent(scheduler, kind, now_s)
end

local function action_mark_packet_start(meta)
	return require('uc_scheduler_action_state').action_mark_packet_start(scheduler, now_s, meta)
end

local function action_mark_packet_end(meta)
	return require('uc_scheduler_action_state').action_mark_packet_end(scheduler, now_s, meta)
end

local function action_is_acting()
	return require('uc_scheduler_action_state').action_is_acting(scheduler, now_s)
end

local function action_dispatch_blocked()
	return require('uc_scheduler_action_state').action_dispatch_blocked(scheduler, now_s, _G)
end

local function engage_attack_on_action_state_gate(meta)
	return require('uc_scheduler_action_state').engage_attack_on_action_state_gate(scheduler, now_s, _G, meta)
end

function scheduler.clear_local_spell_success(meta)
	return require('uc_scheduler_action_state').clear_local_spell_success(scheduler, now_s, meta)
end

function scheduler.clear_local_spell_interruption(meta)
	return require('uc_scheduler_action_state').clear_local_spell_interruption(scheduler, now_s, meta)
end

function scheduler.clear_local_defensive_spell_success(meta)
	return require('uc_scheduler_action_state').clear_local_defensive_spell_success(scheduler, now_s, meta)
end

function scheduler.clear_local_defensive_spell_interruption(meta)
	return require('uc_scheduler_action_state').clear_local_defensive_spell_interruption(scheduler, now_s, meta)
end

function scheduler.last_completion_ignore_reason()
	return require('uc_scheduler_action_state').last_completion_ignore_reason(scheduler)
end

function scheduler.is_spell_cast_complete_message_id(message_id)
	local mid = tonumber(message_id) or 0
	return mid == 2 or mid == 230 or mid == 236 or mid == 252
end

function scheduler.is_spell_cast_start_message_id(message_id)
	local mid = tonumber(message_id) or 0
	return mid == 3 or mid == 229
end

function scheduler.is_spell_cast_interrupted_message_id(message_id)
	local mid = tonumber(message_id) or 0
	return mid == 16
end

function scheduler.local_spell_cast_token_active(st)
	st = type(st) == 'table' and st or {}
	local token = tostring(tonumber(st.action_token) or 0)
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return false, 'not_spell'
	end
	if token == '0' then
		return false, 'missing_token'
	end
	if (tonumber(st.action_start) or 0) <= 0 then
		return false, 'missing_start'
	end
	if (tonumber(st.action_end) or 0) >= (tonumber(st.action_start) or 0) then
		return false, 'not_acting'
	end
	if tostring(st.terminal_outcome or '') ~= '' and tostring(st.terminal_action_token or '') == token then
		return false, 'terminal'
	end
	return true, 'active'
end

function scheduler.spell_name_from_cast_message(msg)
	msg = type(msg) == 'table' and msg or {}
	local name = tostring(msg.spell_name or msg.action_name or msg.name or '')
	return name
end

function scheduler.match_active_spell_token_to_cast_finish(msg, st)
	msg = type(msg) == 'table' and msg or {}
	st = type(st) == 'table' and st or {}
	local active, reason = scheduler.local_spell_cast_token_active(st)
	if not active then
		return false, reason
	end
	local active_spell = tostring(st.last_action_name or '')
	local message_spell = scheduler.spell_name_from_cast_message(msg)
	if active_spell ~= '' and message_spell ~= '' and active_spell ~= message_spell then
		return false, 'spell_mismatch'
	end
	return true, 'active_spell_cast'
end

function scheduler.spell_lifecycle_probe_enabled()
	return rawget(_G, 'UC_SPELL_LIFECYCLE_PROBE') ~= false
end

function scheduler.spell_lifecycle_probe_recent(st, now)
	st = type(st) == 'table' and st or {}
	if tostring(st.last_send_kind or '') ~= 'spell' then
		return false
	end
	local sent_at = tonumber(st.last_sent_at) or 0
	return sent_at > 0 and (now - sent_at) <= 12.0
end

function scheduler.spell_lifecycle_probe_reset_if_new_token(st)
	st = type(st) == 'table' and st or {}
	local probe = scheduler.spell_lifecycle_probe_state
	local token = tostring(tonumber(st.action_token) or 0)
	if token ~= tostring(probe.token or '') then
		probe.token = token
		probe.local_events = {}
		probe.recent_events = {}
		probe.text_events = {}
		probe.candidate_cast_complete = false
		probe.candidate_cast_interrupted = false
	end
	return probe
end

function scheduler.spell_lifecycle_probe_append(list, summary)
	if type(list) ~= 'table' then
		return
	end
	list[#list + 1] = tostring(summary or '')
	while #list > 5 do
		table.remove(list, 1)
	end
end

function scheduler.spell_lifecycle_probe_join(list)
	if type(list) ~= 'table' or #list == 0 then
		return ''
	end
	return table.concat(list, ' || ')
end

function scheduler.spell_lifecycle_probe_mob_name(id)
	local mob_id = tonumber(id) or 0
	if mob_id <= 0 then
		return ''
	end
	local mob = windower.ffxi.get_mob_by_id(mob_id)
	return tostring((mob and mob.name) or '')
end

function scheduler.spell_lifecycle_probe_actions_summary(act)
	if type(act) ~= 'table' or type(act.targets) ~= 'table' then
		return ''
	end
	local parts = {}
	for ti, target in ipairs(act.targets) do
		if ti > 3 then
			break
		end
		local action_parts = {}
		if type(target and target.actions) == 'table' then
			for ai, action in ipairs(target.actions) do
				if ai > 3 then
					break
				end
				action_parts[#action_parts + 1] = ('m%d:p%d:a%d:s%d'):format(
					tonumber(action and action.message) or 0,
					tonumber(action and action.param) or 0,
					tonumber(action and action.add_effect_param) or 0,
					tonumber(action and action.spike_effect_param) or 0
				)
			end
		end
		parts[#parts + 1] = ('t%d[%s]'):format(tonumber(target and target.id) or 0, table.concat(action_parts, ','))
	end
	return table.concat(parts, ';')
end

function scheduler.spell_lifecycle_probe_fields(source, payload, st, now, extra)
	payload = type(payload) == 'table' and payload or {}
	st = type(st) == 'table' and st or {}
	extra = type(extra) == 'table' and extra or {}
	local sent_at = tonumber(st.last_sent_at) or 0
	local packet_start_at = tonumber(st.packet_start_at) or 0
	local terminal_at = tonumber(st.terminal_at) or 0
	local actor_id = tonumber(payload.actor_id) or 0
	local target_id = tonumber(payload.target_id) or 0
	local category = payload.category
	local action_category = payload.action_category or payload.category
	local spell_id = tonumber(payload.spell_id) or tonumber(payload.param) or tonumber(payload.param_1) or 0
	local spell_name = tostring(payload.spell_name or payload.action_name or payload.name or '')
	return {
		source = tostring(source or ''),
		actor_id = actor_id,
		actor_name = tostring(payload.actor_name or scheduler.spell_lifecycle_probe_mob_name(actor_id)),
		target_id = target_id,
		target = tostring(payload.target_name or scheduler.spell_lifecycle_probe_mob_name(target_id)),
		message_id = tonumber(payload.message_id) or tonumber(payload.message) or 0,
		param = tonumber(payload.param_1) or tonumber(payload.param) or tonumber(payload.effect_id) or 0,
		category = tostring(category or ''),
		action_category = tostring(action_category or ''),
		spell_id = spell_id,
		spell_name = spell_name,
		interrupted = tostring(extra.interrupted or payload.interrupted or ''),
		raw_text = tostring(extra.raw_text or payload.raw_text or ''),
		action_param = tonumber(payload.action_param) or tonumber(payload.param) or tonumber(payload.param_1) or 0,
		targets_summary = tostring(extra.targets_summary or ''),
		actions_summary = tostring(extra.actions_summary or ''),
		active_spell = tostring(st.last_action_name or ''),
		active_target = tostring(st.last_target_name or ''),
		active_target_id = tonumber(st.last_target_id) or 0,
		action_token = tostring(tonumber(st.action_token) or 0),
		since_sent_s = (sent_at > 0) and ('%.2f'):format(math.max(0, now - sent_at)) or '',
		since_packet_start_s = (packet_start_at > 0) and ('%.2f'):format(math.max(0, now - packet_start_at)) or 'na',
		packet_start_detected = (packet_start_at > 0) and '1' or '0',
		action_state = scheduler.action_timeline_action_state_summary(now),
		terminal_outcome = tostring(st.terminal_outcome or ''),
		terminal_since_s = (terminal_at > 0) and ('%.2f'):format(math.max(0, now - terminal_at)) or '',
		matched_pattern = tostring(extra.matched_pattern or ''),
		parsed_actor = tostring(extra.parsed_actor or ''),
		parsed_spell = tostring(extra.parsed_spell or ''),
		parsed_target = tostring(extra.parsed_target or ''),
	}
end

function scheduler.spell_lifecycle_probe_emit(source, payload, extra)
	if not scheduler.spell_lifecycle_probe_enabled() then
		return
	end
	local player = windower.ffxi.get_player()
	local my_id = tonumber(player and player.id) or 0
	if my_id <= 0 then
		return
	end
	payload = type(payload) == 'table' and payload or {}
	local actor_id = tonumber(payload.actor_id) or 0
	if actor_id ~= my_id then
		return
	end
	local now = now_s()
	local st = action_state() or {}
	local recent = scheduler.spell_lifecycle_probe_recent(st, now)
	local active = scheduler.local_spell_cast_token_active(st)
	if not active and not recent then
		return
	end
	local probe = scheduler.spell_lifecycle_probe_reset_if_new_token(st)
	local fields = scheduler.spell_lifecycle_probe_fields(source, payload, st, now, extra)
	local summary = ('src=%s mid=%s param=%s cat=%s spell=%s token=%s'):format(
		tostring(fields.source or ''),
		tostring(fields.message_id or ''),
		tostring(fields.param or ''),
		tostring(fields.category or ''),
		tostring(fields.spell_name or ''),
		tostring(fields.action_token or '')
	)
	local complete_candidate = scheduler.is_spell_cast_complete_message_id(fields.message_id)
	local interrupt_candidate = scheduler.is_spell_cast_interrupted_message_id(fields.message_id)
	if complete_candidate then
		probe.candidate_cast_complete = true
	end
	if interrupt_candidate then
		probe.candidate_cast_interrupted = true
	end
	if active then
		scheduler.spell_lifecycle_probe_append(probe.local_events, summary)
		scheduler.action_timeline_log('SPELL_LIFECYCLE_PROBE_LOCAL_EVENT', fields, ('spell_lifecycle_probe_local:%s:%s:%s:%s'):format(tostring(fields.action_token or ''), tostring(fields.source or ''), tostring(fields.message_id or ''), tostring(fields.param or '')), 0.02)
	end
	if recent then
		scheduler.spell_lifecycle_probe_append(probe.recent_events, summary)
		scheduler.action_timeline_log('SPELL_LIFECYCLE_PROBE_RECENT_EVENT', fields, ('spell_lifecycle_probe_recent:%s:%s:%s:%s'):format(tostring(fields.action_token or ''), tostring(fields.source or ''), tostring(fields.message_id or ''), tostring(fields.param or '')), 0.02)
	end
end

function scheduler.spell_lifecycle_probe_text_pattern(raw_text)
	local text = tostring(raw_text or '')
	local actor, spell = text:match("^([^%s].-) starts casting (.-)%.?$")
	if actor and spell then
		return 'starts_casting', actor, spell, ''
	end
	actor, spell = text:match("^([^%s].-) casts (.-)%.?$")
	if actor and spell then
		return 'casts_spell', actor, spell, ''
	end
	actor = text:match("^([^%s].-)'s casting is interrupted%.?$")
	if actor then
		return 'casting_interrupted', actor, '', ''
	end
	return '', '', '', ''
end

local function spell_text_begins_with(raw_text, prefix)
	raw_text = tostring(raw_text or '')
	prefix = tostring(prefix or '')
	if prefix == '' then
		return false
	end
	return raw_text:sub(1, #prefix) == prefix
end

function scheduler.on_incoming_text(original, modified, mode, blocked)
	if not scheduler.spell_lifecycle_probe_enabled() then
		return
	end
	local player = windower.ffxi.get_player()
	local player_name = tostring((player and player.name) or '')
	if player_name == '' then
		return
	end
	local raw_text = tostring(original or modified or '')
	local matched, actor, spell, target = scheduler.spell_lifecycle_probe_text_pattern(raw_text)
	if matched == '' or actor ~= player_name then
		return
	end
	local now = now_s()
	local st = action_state() or {}
	local recent = scheduler.spell_lifecycle_probe_recent(st, now)
	local active = scheduler.local_spell_cast_token_active(st)
	if not active and not recent then
		return
	end
	local probe = scheduler.spell_lifecycle_probe_reset_if_new_token(st)
	local fields = scheduler.spell_lifecycle_probe_fields('incoming_text', {
		actor_id = tonumber(player.id) or 0,
		actor_name = player_name,
		spell_name = spell,
		raw_text = raw_text,
	}, st, now, {
		raw_text = raw_text,
		mode = tostring(mode or ''),
		matched_pattern = matched,
		parsed_actor = actor,
		parsed_spell = spell,
		parsed_target = target,
		interrupted = (matched == 'casting_interrupted') and '1' or '0',
	})
	fields.mode = tostring(mode or '')
	fields.blocked = tostring(blocked or '')
	if matched == 'casts_spell' then
		probe.candidate_cast_complete = true
	elseif matched == 'casting_interrupted' then
		probe.candidate_cast_interrupted = true
	end
	scheduler.spell_lifecycle_probe_append(probe.text_events, ('text=%s spell=%s token=%s'):format(matched, spell, tostring(fields.action_token or '')))
	scheduler.action_timeline_log('SPELL_LIFECYCLE_PROBE_TEXT', fields, ('spell_lifecycle_probe_text:%s:%s:%s'):format(tostring(fields.action_token or ''), matched, spell), 0.02)
	if not active then
		return
	end
	local active_spell = tostring(st.last_action_name or '')
	local provider = tostring(st.last_action_provider or '')
	local release_meta = {
		message_id = tonumber(fields.message_id) or 0,
		message_param = tonumber(fields.param) or 0,
		spell_name = active_spell,
		raw_text = raw_text,
		release_reason = '',
		completion_reason = '',
	}
	if matched == 'casts_spell' and active_spell ~= '' then
		local prefix = player_name .. ' casts ' .. active_spell
		if spell_text_begins_with(raw_text, prefix) then
			release_meta.release_reason = 'cast_complete_text'
			release_meta.completion_reason = 'cast_complete_text'
			if provider == 'defensive_internal' or provider == 'defensive_healbot' then
				scheduler.clear_local_defensive_spell_success(release_meta)
			else
				scheduler.clear_local_spell_success(release_meta)
			end
			return
		end
	elseif matched == 'casting_interrupted' and actor == player_name then
		local prefix = player_name .. "'s casting is interrupted"
		if spell_text_begins_with(raw_text, prefix) then
			release_meta.release_reason = 'cast_interrupted_text'
			release_meta.completion_reason = 'cast_interrupted_text'
			if provider == 'defensive_internal' or provider == 'defensive_healbot' then
				scheduler.clear_local_defensive_spell_interruption(release_meta)
			else
				scheduler.clear_local_spell_interruption(release_meta)
			end
			return
		end
	end
end

function scheduler.emit_spell_lifecycle_timeout_candidate_summary(scheduler_obj, now_s_fn, st)
	if not scheduler.spell_lifecycle_probe_enabled() then
		return
	end
	st = type(st) == 'table' and st or action_state() or {}
	local now = now_s_fn()
	local probe = scheduler.spell_lifecycle_probe_reset_if_new_token(st)
	scheduler.action_timeline_log('SPELL_LIFECYCLE_TIMEOUT_CANDIDATE_SUMMARY', {
		active_spell = tostring(st.last_action_name or ''),
		target = tostring(st.last_target_name or ''),
		target_id = tonumber(st.last_target_id) or 0,
		action_token = tostring(tonumber(st.action_token) or 0),
		packet_start_detected = (tonumber(st.packet_start_at) or 0) > 0 and '1' or '0',
		local_probe_last5 = scheduler.spell_lifecycle_probe_join(probe.local_events),
		recent_probe_last5 = scheduler.spell_lifecycle_probe_join(probe.recent_events),
		text_probe_last5 = scheduler.spell_lifecycle_probe_join(probe.text_events),
		candidate_cast_complete = probe.candidate_cast_complete and '1' or '0',
		candidate_cast_interrupted = probe.candidate_cast_interrupted and '1' or '0',
		since_sent_s = (tonumber(st.last_sent_at) or 0) > 0 and ('%.2f'):format(math.max(0, now - (tonumber(st.last_sent_at) or 0))) or '',
		since_packet_start_s = (tonumber(st.packet_start_at) or 0) > 0 and ('%.2f'):format(math.max(0, now - (tonumber(st.packet_start_at) or 0))) or 'na',
	}, ('spell_lifecycle_timeout_summary:%s'):format(tostring(tonumber(st.action_token) or 0)), 0.05)
end

function scheduler.p1_clear_tank_spell_wait_state(phase)
	phase.tank_spell_waiting = false
	phase.tank_spell_wait_until = 0
	phase.tank_pending_action = ''
	phase.tank_pending_target_id = 0
	phase.tank_pending_sent_at = 0
end

function scheduler.p1_begin_tank_spell_wait(phase, action_name, target_id, at)
	local now_value = tonumber(at) or now_s()
	phase.tank_spell_waiting = true
	phase.tank_spell_wait_until = now_value + 8.0
	phase.tank_pending_action = tostring(action_name or '')
	phase.tank_pending_target_id = tonumber(target_id) or 0
	phase.tank_pending_sent_at = now_value
end

function scheduler.p1_refresh_tank_spell_wait_lock(phase, at)
	if type(phase) ~= 'table' or phase.tank_spell_waiting ~= true then
		return false, 'inactive'
	end
	local now_value = tonumber(at) or now_s()
	local wait_until = tonumber(phase.tank_spell_wait_until) or 0
	if now_value >= wait_until then
		scheduler.p1_clear_tank_spell_wait_state(phase)
		return false, 'expired'
	end
	local ast = action_state()
	local send_kind = tostring(ast.last_send_kind or '')
	local cooldown_until = tonumber(ast.cooldown_until) or 0
	local acting = action_is_acting()
	if send_kind ~= 'spell' then
		scheduler.p1_clear_tank_spell_wait_state(phase)
		return false, 'released_nonspell'
	end
	if (not acting) and now_value >= cooldown_until then
		scheduler.p1_clear_tank_spell_wait_state(phase)
		return false, 'released_complete'
	end
	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = math.min(wait_until, now_value + 0.6)
	return true, (acting and 'acting') or 'cooldown'
end

function scheduler.clear_defensive_spell_wait_state()
	scheduler.defensive_spell_waiting = false
	scheduler.defensive_spell_wait_until = 0
	scheduler.defensive_pending_action = ''
	scheduler.defensive_pending_target_id = 0
	scheduler.defensive_pending_sent_at = 0
end

function scheduler.begin_defensive_spell_wait(action_name, target_id, at)
	local now_value = tonumber(at) or now_s()
	scheduler.defensive_spell_waiting = true
	scheduler.defensive_spell_wait_until = now_value + 8.0
	scheduler.defensive_pending_action = tostring(action_name or '')
	scheduler.defensive_pending_target_id = tonumber(target_id) or 0
	scheduler.defensive_pending_sent_at = now_value
end

function scheduler.refresh_defensive_spell_wait_lock(at)
	if scheduler.defensive_spell_waiting ~= true then
		return false, 'inactive'
	end
	local now_value = tonumber(at) or now_s()
	local wait_until = tonumber(scheduler.defensive_spell_wait_until) or 0
	if now_value >= wait_until then
		scheduler.clear_defensive_spell_wait_state()
		return false, 'expired'
	end
	local ast = action_state()
	local send_kind = tostring(ast.last_send_kind or '')
	local cooldown_until = tonumber(ast.cooldown_until) or 0
	local acting = action_is_acting()
	if send_kind ~= 'spell' then
		scheduler.clear_defensive_spell_wait_state()
		return false, 'released_nonspell'
	end
	if (not acting) and now_value >= cooldown_until then
		scheduler.clear_defensive_spell_wait_state()
		return false, 'released_complete'
	end
	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = math.min(wait_until, now_value + 0.6)
	return true, (acting and 'acting') or 'cooldown'
end

function scheduler.p1_pending_engage_state(phase)
	if type(phase) ~= 'table' then
		return nil
	end
	if type(phase.pending_engage) ~= 'table' then
		return nil
	end
	return phase.pending_engage
end

function scheduler.p1_pending_engage_live(phase, at)
	local pending = scheduler.p1_pending_engage_state(phase)
	if type(pending) ~= 'table' then
		return false
	end
	local now_value = tonumber(at) or now_s()
	local timeout_at = tonumber(pending.timeout_at) or 0
	return timeout_at > now_value
end

function scheduler.p1_clear_pending_engage(phase)
	if type(phase) ~= 'table' then
		return
	end
	phase.pending_engage = nil
end

function scheduler.p1_engage_duplicate_state(phase)
	if type(phase) ~= 'table' then
		return nil
	end
	if type(phase.engage_duplicate) ~= 'table' then
		return nil
	end
	return phase.engage_duplicate
end

function scheduler.p1_clear_engage_duplicate_state(phase, event_code, at, fields)
	if type(phase) ~= 'table' then
		return
	end
	local state = scheduler.p1_engage_duplicate_state(phase)
	if type(state) ~= 'table' then
		return
	end
	phase.engage_duplicate = nil
	local event_name = tostring(event_code or '')
	if event_name == '' then
		return
	end
	local now_value = tonumber(at) or now_s()
	local payload = type(fields) == 'table' and fields or {}
	if payload.tid == nil then
		payload.tid = tonumber(state.target_id) or 0
	end
	if payload.name == nil then
		payload.name = tostring(state.target_name or '')
	end
	if payload.status == nil then
		payload.status = tonumber(state.player_status) or 0
	end
	if payload.dispatch_method == nil then
		payload.dispatch_method = tostring(state.dispatch_method or scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON)
	end
	if payload.age_s == nil then
		payload.age_s = ('%.2f'):format(math.max(0, now_value - (tonumber(state.last_attempt_at) or now_value)))
	end
	if payload.remaining_s == nil then
		payload.remaining_s = ('%.2f'):format(math.max(0, (tonumber(state.suppressed_until) or 0) - now_value))
	end
	if payload.sent_for_target == nil then
		payload.sent_for_target = (((tonumber(state.target_id) or 0) > 0) and 1) or 0
	end
	scheduler.action_timeline_log(
		event_name,
		payload,
		('engage_dup_reset:%s:%d'):format(event_name:lower(), tonumber(payload.tid) or 0),
		0.05
	)
end

function scheduler.p1_note_engage_duplicate_attempt(phase, target_id, target_name, at, player_status, dispatch_method)
	if type(phase) ~= 'table' then
		return
	end
	local now_value = tonumber(at) or now_s()
	phase.engage_duplicate = {
		target_id = tonumber(target_id) or 0,
		target_name = tostring(target_name or ''),
		last_attempt_at = now_value,
		suppressed_until = now_value + (tonumber(scheduler.ENGAGE_DUPLICATE_RETRY_DEBOUNCE_S) or 0.30),
		player_status = tonumber(player_status) or 0,
		dispatch_method = tostring(dispatch_method or scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON),
	}
end

function scheduler.p1_validate_engage_duplicate_retry(ctx, proposal)
	if type(proposal) ~= 'table' then
		return 'apply_generic', nil
	end
	if tostring(proposal.family_id or '') ~= 'combat.engage.primary' or tostring(proposal.action_type or '') ~= 'engage' then
		return 'apply_generic', nil
	end
	local phase = scheduler.phase1 or {}
	local now_value = tonumber(ctx and ctx.now) or now_s()
	local target_id = tonumber(proposal.target_id) or 0
	local player_status = tonumber(ctx and ctx.player_status) or 0
	local dispatch_method = scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON
	if player_status == 1 then
		scheduler.p1_clear_engage_duplicate_state(phase, '', now_value)
		return 'apply_generic', nil
	end
	local state = scheduler.p1_engage_duplicate_state(phase)
	if type(state) == 'table' and (tonumber(state.target_id) or 0) > 0 and (tonumber(state.target_id) or 0) ~= target_id then
		scheduler.p1_clear_engage_duplicate_state(phase, 'ENGAGE_DUPLICATE_RESET_TARGET_CHANGE', now_value, {
			tid = target_id,
			name = tostring(proposal.target_name or ''),
			old_target_id = tonumber(state.target_id) or 0,
			status = player_status,
			dispatch_method = dispatch_method,
		})
		state = nil
	end
	local pending = scheduler.p1_pending_engage_state(phase)
	local pending_live = scheduler.p1_pending_engage_live(phase, now_value)
	if type(state) == 'table'
		and pending_live
		and type(pending) == 'table'
		and (tonumber(pending.target_id) or 0) == target_id
		and now_value >= (tonumber(pending.retry_ready_at) or 0)
		and (tonumber(state.suppressed_until) or 0) > now_value then
		scheduler.action_timeline_log('ENGAGE_DUPLICATE_ALLOWED_RETRY', {
			tid = target_id,
			name = tostring(proposal.target_name or ''),
			status = player_status,
			dispatch_method = dispatch_method,
			age_s = ('%.2f'):format(math.max(0, now_value - (tonumber(state.last_attempt_at) or now_value))),
			remaining_s = ('%.2f'):format(math.max(0, (tonumber(state.suppressed_until) or 0) - now_value)),
			pending_engage = 'retry_ready',
			sent_for_target = 1,
		}, ('engage_dup_allow_retry:%d'):format(target_id), 0.05)
		phase.engage_duplicate = nil
		state = nil
	end
	if type(state) == 'table' then
		local suppressed_until = tonumber(state.suppressed_until) or 0
		if suppressed_until > now_value then
			return 'suppressed', {
				tid = target_id,
				name = tostring(proposal.target_name or ''),
				reason = 'BLOCK_DUPLICATE',
				status = player_status,
				dispatch_method = dispatch_method,
				age_s = ('%.2f'):format(math.max(0, now_value - (tonumber(state.last_attempt_at) or now_value))),
				remaining_s = ('%.2f'):format(math.max(0, suppressed_until - now_value)),
				pending_engage = pending_live and 'active' or 'inactive',
				sent_for_target = 1,
			}
		end
	end
	return 'skip_generic', nil
end

function scheduler.p1_note_pending_engage_attempt(phase, target_id, target_name, at)
	if type(phase) ~= 'table' then
		return
	end
	local now_value = tonumber(at) or now_s()
	local tid = tonumber(target_id) or 0
	local name = tostring(target_name or '')
	local pending = scheduler.p1_pending_engage_state(phase)
	if type(pending) == 'table' and (tonumber(pending.target_id) or 0) == tid and scheduler.p1_pending_engage_live(phase, now_value) then
		pending.target_name = name
		pending.last_attempt_at = now_value
		pending.timeout_at = now_value + scheduler.PENDING_ENGAGE_TIMEOUT_S
		pending.retry_ready_at = now_value
		if (tonumber(pending.wait_longer_count) or 0) > 0 then
			scheduler.action_timeline_log('PENDING_ENGAGE_RETRY_ATTEMPT', {
				tid = tid,
				name = name,
				command = 'attack_on',
				retry_count = tonumber(pending.retry_count) or 0,
			}, ('pending_engage_retry_attempt:%d'):format(tid), 0.05)
		end
		return
	end
	phase.pending_engage = {
		target_id = tid,
		target_name = name,
		started_at = now_value,
		timeout_at = now_value + scheduler.PENDING_ENGAGE_TIMEOUT_S,
		retry_ready_at = now_value,
		last_attempt_at = now_value,
		retry_count = 0,
		wait_longer_count = 0,
	}
	scheduler.action_timeline_log('PENDING_ENGAGE_START', {
		tid = tid,
		name = name,
		command = 'attack_on',
	}, ('pending_engage_start:%d'):format(tid), 0.05)
end

function scheduler.p1_mark_pending_engage_rejected_wait_longer(phase, at, message_id)
	local pending = scheduler.p1_pending_engage_state(phase)
	if type(pending) ~= 'table' then
		return false
	end
	local now_value = tonumber(at) or now_s()
	if not scheduler.p1_pending_engage_live(phase, now_value) then
		scheduler.p1_clear_pending_engage(phase)
		return false
	end
	pending.wait_longer_count = (tonumber(pending.wait_longer_count) or 0) + 1
	pending.retry_count = (tonumber(pending.retry_count) or 0) + 1
	pending.retry_ready_at = math.min(
		tonumber(pending.timeout_at) or now_value,
		now_value + scheduler.PENDING_ENGAGE_RETRY_DELAY_S
	)
	pending.last_rejection_message_id = tonumber(message_id) or 0
	scheduler.action_timeline_log('PENDING_ENGAGE_REJECTED_WAIT_LONGER', {
		tid = tonumber(pending.target_id) or 0,
		name = tostring(pending.target_name or ''),
		message_id = tonumber(message_id) or 0,
	}, ('pending_engage_rejected:%d'):format(tonumber(pending.target_id) or 0), 0.05)
	scheduler.action_timeline_log('PENDING_ENGAGE_RETRY_READY', {
		tid = tonumber(pending.target_id) or 0,
		name = tostring(pending.target_name or ''),
		retry_in_s = ('%.2f'):format(math.max(0, (tonumber(pending.retry_ready_at) or now_value) - now_value)),
	}, ('pending_engage_retry_ready:%d'):format(tonumber(pending.target_id) or 0), 0.05)
	scheduler.p1_clear_engage_duplicate_state(phase, 'ENGAGE_DUPLICATE_RESET_REJECTION', now_value, {
		tid = tonumber(pending.target_id) or 0,
		name = tostring(pending.target_name or ''),
		status = 0,
		dispatch_method = scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON,
		pending_engage = 'rejected_wait_longer',
	})
	return true
end

function scheduler.p1_refresh_pending_engage(phase, player_status, at)
	local pending = scheduler.p1_pending_engage_state(phase)
	if type(pending) ~= 'table' then
		return false, 'inactive'
	end
	local now_value = tonumber(at) or now_s()
	if tonumber(player_status) == 1 then
		scheduler.p1_clear_engage_duplicate_state(phase, '', now_value)
		scheduler.action_timeline_log('PENDING_ENGAGE_CONFIRMED', {
			tid = tonumber(pending.target_id) or 0,
			name = tostring(pending.target_name or ''),
			status = 1,
		}, ('pending_engage_confirmed:%d'):format(tonumber(pending.target_id) or 0), 0.05)
		scheduler.p1_clear_pending_engage(phase)
		return false, 'confirmed'
	end
	local timeout_at = tonumber(pending.timeout_at) or 0
	if timeout_at > 0 and now_value >= timeout_at then
		scheduler.p1_clear_engage_duplicate_state(phase, '', now_value)
		local last_attempt_at = tonumber(pending.last_attempt_at) or tonumber(pending.started_at) or now_value
		scheduler.action_timeline_log('PENDING_ENGAGE_TIMEOUT', {
			tid = tonumber(pending.target_id) or 0,
			name = tostring(pending.target_name or ''),
			retry_count = tonumber(pending.retry_count) or 0,
			age_s = ('%.2f'):format(math.max(0, now_value - last_attempt_at)),
		}, ('pending_engage_timeout:%d'):format(tonumber(pending.target_id) or 0), 0.05)
		scheduler.p1_clear_pending_engage(phase)
		return false, 'timeout'
	end
	local expected_tid = tonumber(pending.target_id) or 0
	if expected_tid > 0 then
		local target = windower.ffxi.get_mob_by_id(expected_tid)
		if not target or not combat_core.is_live_actionable_combat_target(target, now_value, true) then
			scheduler.p1_clear_engage_duplicate_state(phase, '', now_value)
			scheduler.action_timeline_log('PENDING_ENGAGE_CLEARED_INVALID_TARGET', {
				tid = expected_tid,
				name = tostring(pending.target_name or ''),
			}, ('pending_engage_invalid:%d'):format(expected_tid), 0.05)
			scheduler.p1_clear_pending_engage(phase)
			return false, 'invalid_target'
		end
	end
	return true, 'active'
end

function scheduler.p1_is_critical_defensive_proposal(settings, selected)
	if type(selected) ~= 'table' then
		return false
	end
	local selected_provider = tostring(selected.provider or '')
	if selected_provider ~= 'defensive_internal' and selected_provider ~= 'defensive_healbot' then
		return false
	end
	local detail = type(selected.detail) == 'table' and selected.detail or {}
	if tostring(selected.action_type or '') ~= 'spell' or tostring(detail.def_action_type or '') ~= 'cure' then
		return false
	end
	local critical_hpp = tonumber(settings and settings.defensive_critical_hpp) or 35
	local target_hpp = tonumber(detail.target_hpp) or -1
	return target_hpp > 0 and target_hpp <= critical_hpp
end

function scheduler.p1_clear_pending_engage_for_critical_dispatch(phase, action_name, target_id, target_name)
	local pending = scheduler.p1_pending_engage_state(phase)
	if type(pending) ~= 'table' then
		return
	end
	scheduler.p1_clear_engage_duplicate_state(phase, '', now_s())
	scheduler.action_timeline_log('PENDING_ENGAGE_ALLOW_CRITICAL', {
		tid = tonumber(target_id) or tonumber(pending.target_id) or 0,
		name = tostring(target_name or pending.target_name or ''),
		action = tostring(action_name or ''),
	}, ('pending_engage_allow_critical:%s:%d'):format(tostring(action_name or ''), tonumber(target_id) or 0), 0.05)
	scheduler.p1_clear_pending_engage(phase)
end

function scheduler.p1_selected_is_critical_cure(settings, selected)
	if type(selected) ~= 'table' then
		return false
	end
	local detail = type(selected.detail) == 'table' and selected.detail or {}
	local target_hpp = tonumber(detail.target_hpp or -1) or -1
	local critical_hpp = tonumber(settings and settings.defensive_critical_hpp) or 35
	return tostring(selected.action_type or '') == 'spell'
		and tostring(detail.def_action_type or '') == 'cure'
		and target_hpp > 0
		and target_hpp <= critical_hpp
end

function scheduler.p1_maybe_clear_pending_engage_for_selected_critical(settings, selected)
	local phase = scheduler.phase1 or {}
	if not scheduler.p1_pending_engage_live(phase, now_s()) then
		return
	end
	if not scheduler.p1_selected_is_critical_cure(settings, selected) then
		return
	end
	scheduler.p1_clear_pending_engage_for_critical_dispatch(
		phase,
		tostring(selected.action_name or ''),
		tonumber(selected.target_id) or 0,
		tostring(selected.target_name or '')
	)
end

function scheduler.p1_maybe_release_stale_spell_lock_for_target_transition(selected, at)
	if type(selected) ~= 'table' then
		return false
	end
	local ast = action_state()
	if tostring(ast.last_send_kind or '') ~= 'spell' then
		return false
	end
	if tostring(ast.last_action_provider or '') ~= 'combat' then
		return false
	end
	if tostring(ast.last_target_kind or '') ~= 'mob' then
		return false
	end
	local now_value = tonumber(at) or now_s()
	local stale_age_s = math.max(0, now_value - (tonumber(ast.last_action) or now_value))
	local old_target_id = tonumber(ast.last_target_id) or 0
	local new_target_id = tonumber(selected.target_id) or 0
	if old_target_id <= 0 or new_target_id <= 0 or old_target_id == new_target_id then
		return false
	end
	local old_target = windower.ffxi.get_mob_by_id(old_target_id)
	local old_target_invalid = not old_target or not combat_core.is_live_actionable_combat_target(old_target, now_value, true)
	if not old_target_invalid then
		return false
	end
	local player_status_zero = (tonumber((windower.ffxi.get_player() or {}).status) or -1) == 0
	local cleared = require('uc_scheduler_action_state').clear_stale_combat_spell_lock(scheduler, now_s, {
		old_target_invalid = old_target_invalid,
		player_status_zero = player_status_zero,
		new_target_id = new_target_id,
	})
	if not cleared then
		return false
	end
	local reason = 'TARGET_TRANSITION'
	local immediate = 1
	if player_status_zero then
		reason = 'STATUS_ZERO_WITH_NEW_TARGET'
	elseif old_target_invalid then
		reason = 'OLD_TARGET_DEAD'
	end
	scheduler.action_timeline_log('STALE_SPELL_LOCK_RELEASE', {
		spell = tostring(ast.last_action_name or ''),
		provider = tostring(ast.last_action_provider or ''),
		old_target_id = old_target_id,
		tid = new_target_id,
		name = tostring(selected.target_name or ''),
		reason = reason,
		age_s = ('%.2f'):format(stale_age_s),
		immediate = immediate,
	}, ('stale_spell_release:%d:%d'):format(old_target_id, new_target_id), 0.05)
	return true
end

function scheduler.apply_defensive_spell_movement_lock(action_name, target_id, at)
	local now_value = tonumber(at) or now_s()
	local intent = {
		kind = 'run_stop',
		source = 'unified_scheduler:T3.1f_defensive_spell_lock',
		meta = {
			reason = 'DEFENSIVE_SPELL_CAST_LOCK',
			action_name = tostring(action_name or ''),
			target_id = tonumber(target_id) or 0,
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
		dispatcher = dispatcher,
		direct_run = windower.ffxi.run,
		run = windower.ffxi.run,
		ownership_enabled = false,
		intent = intent,
	})
	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_value + 0.6
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
	local dbg = uc_active_config.get_path('config.debug.enabled')
	if dbg == nil then
		dbg = s.debug == true or s.debug == 1 or tostring(s.debug or ''):lower() == 'true'
	else
		dbg = dbg == true
	end
	if not dbg then
		return
	end
	_G.UC_LAST_SCHED_ACTION = tostring(msg or '')
end

local function enemy_dispel_log(msg)
	local s = rawget(_G, 'UC_SETTINGS') or {}
	local log_on = uc_active_config.get_path('config.debug.def_sched')
	if log_on == nil then
		log_on = s.log_def_sched == true or s.log_def_sched == 1 or tostring(s.log_def_sched or ''):lower() == 'true'
	else
		log_on = log_on == true
	end
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
	local stop_intent = {
		kind = 'run_stop',
		source = 'unified_scheduler:T2.4j_darklaunch',
		meta = {
			reason = 'DOOM_HOLY_WATER',
			action_type = 'item',
			action_name = 'Holy Water',
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	local _stop_darklaunch_ok, _stop_darklaunch_reason = dispatcher.validate_intent(stop_intent)
	local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
		dispatcher = dispatcher,
		direct_run = windower.ffxi.run,
		run = windower.ffxi.run,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_RUN_STOP_OWNERSHIP == true),
		intent = stop_intent,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE = {
		ok = _stop_darklaunch_ok and true or false,
		reason = _stop_darklaunch_reason,
		kind = stop_intent.kind,
		source = stop_intent.source,
		ownership_enabled = run_stop_ownership_status.ownership_enabled,
		dispatched = run_stop_ownership_status.dispatched,
		dispatch_ok = run_stop_ownership_status.dispatch_ok,
		dispatch_reason = run_stop_ownership_status.dispatch_reason,
		fallback_used = run_stop_ownership_status.fallback_used,
		stop = run_stop_ownership_status.stop,
	}
	local now = now_s()
	if now - doom_last_item_at < DOOM_ITEM_COOLDOWN then
		_G.UC_LAST_SCHED_ACTION = '[doom]holding_for_item_reuse'
		return true, 'BLOCK_DOOM_WATER_HOLD'
	end
	doom_last_item_at = now
	local doom_holy_water_command = 'input /item "Holy Water" <me>'
	local intent = {
		kind = 'send_command',
		source = 'unified_scheduler:T2.3k_darklaunch',
		command = doom_holy_water_command,
		meta = {
			action_type = 'item',
			action_name = 'Holy Water',
			reason = 'doom_emergency',
		},
	}
	local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
	local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		direct_send_command = windower.send_command,
		send_command = windower.send_command,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DOOM_HOLY_WATER_COMMAND_OWNERSHIP == true),
		intent = intent,
		command = doom_holy_water_command,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE = {
		ok = _darklaunch_ok and true or false,
		reason = _darklaunch_reason,
		kind = intent.kind,
		source = intent.source,
		command_present = command_ownership_status.command_present,
		ownership_enabled = command_ownership_status.ownership_enabled,
		dispatched = command_ownership_status.dispatched,
		dispatch_ok = command_ownership_status.dispatch_ok,
		dispatch_reason = command_ownership_status.dispatch_reason,
		fallback_used = command_ownership_status.fallback_used,
	}
	_G.UC_LAST_SCHED_ACTION = '[doom]holy_water'
	return true, 'BLOCK_DOOM_WATER'
end

local function build_partner_target_set(settings)
	return require('uc_scheduler_context_utils').build_partner_target_set({
		bool_setting = bool_setting,
		uc_partner_list = uc_partner_list,
	}, settings)
end

function scheduler.sleep_spell_list_from_settings(settings)
	local out = {}
	local seen = {}
	local function append_spell(raw)
		local spell_name = tostring(raw or ''):match('^%s*(.-)%s*$') or ''
		if spell_name == '' then
			return
		end
		local key = spell_name:lower()
		if seen[key] == true then
			return
		end
		seen[key] = true
		out[#out + 1] = spell_name
	end
	local list = settings and settings.sleepspells or nil
	if type(list) == 'table' then
		for i = 1, #list do
			append_spell(list[i])
		end
	elseif type(list) == 'string' then
		append_spell(list)
	end
	if #out == 0 then
		append_spell(settings and settings.sleepspell or '')
	end
	return out
end

scheduler.SLEEP_MAX_TARGET_DISTANCE = 6.0
scheduler.SLEEP_TARGET_SUPPRESSION_TIMEOUT_S = 45.0
scheduler.TANK_TARGET_ACQUIRE_PRIORITY = 106
scheduler.TANK_TARGET_ACQUIRE_URGENCY = 0.80
scheduler.TANK_ENGAGE_PRIORITY = 107
scheduler.TANK_ENGAGE_URGENCY = 0.85
scheduler.DEFAULT_ENGAGE_PRIORITY = 72
scheduler.DEFAULT_ENGAGE_URGENCY = 0.70
scheduler.TARGET_ACQUIRE_DEBOUNCE_S = 0.20

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

scheduler.action_timeline_state = scheduler.action_timeline_state or {
	start_at = 0,
	initialized = false,
	last_event_at = {},
	last_status = nil,
}

function scheduler.action_timeline_enabled()
	return rawget(_G, 'UC_DEBUG_ACTION_TIMELINE') == true
end

function scheduler.action_timeline_player_name()
	local p = windower.ffxi.get_player()
	return tostring((p and p.name) or 'unknown')
end

function scheduler.action_timeline_log_path()
	local name = scheduler.action_timeline_player_name():lower()
	return windower.addon_path .. 'data/logs/action_timeline_' .. name .. '.log'
end

function scheduler.action_timeline_format_fields(fields)
	if type(fields) ~= 'table' then
		return ''
	end
	local order = {
		'tid', 'name', 'role', 'tank', 'spell', 'action', 'provider', 'band', 'urgency', 'critical', 'reason',
		'status', 'from', 'to', 'target', 'target_id', 'old_target_id', 'actor_id', 'actor_name', 'message_id', 'retry_in_s', 'retry_count', 'age_s', 'remaining_s', 'tail_s', 'kind', 'command', 'dispatch_method', 'pending_engage', 'sent_for_target', 'pull_owner', 'target_valid', 'range', 'claim_check', 'action_state', 'top_family', 'top_provider', 'top_action', 'best_action', 'best_provider', 'best_target', 'best_target_id', 'source', 'category', 'action_category', 'spell_id', 'spell_name', 'active_spell', 'active_target', 'active_target_id', 'interrupted', 'raw_text', 'mode', 'blocked', 'action_param', 'targets_summary', 'actions_summary', 'matched_pattern', 'parsed_actor', 'parsed_spell', 'parsed_target', 'since_sent_s', 'since_packet_start_s', 'terminal_since_s', 'release_reason', 'old_kind', 'cooldown_s', 'cast_type', 'action_token', 'completion_reason', 'terminal_outcome', 'param', 'active_song_count', 'expected_song_count', 'song_names', 'song_lowest_remaining_s', 'high_level_spell_sent', 'first_lifecycle_event', 'estimated_sent_at', 'packet_start_detected', 'last_local_message_id', 'last_local_message_param', 'last_ignored_message_id', 'last_ignored_message_param', 'accepted_completion_after_timeout', 'original_outcome', 'original_terminal_at', 'original_since_sent_s', 'late_message_id', 'late_message_param', 'late_completion', 'local_probe_last5', 'recent_probe_last5', 'text_probe_last5', 'candidate_cast_complete', 'candidate_cast_interrupted', 'throttle_key', 'now_value', 'next_allowed_at', 'proposal_emitted', 'last_maintenance_action', 'last_maintenance_token', 'immediate'
	}
	local parts = {}
	local seen = {}
	for i = 1, #order do
		local key = order[i]
		local val = fields[key]
		if val ~= nil and val ~= '' then
			seen[key] = true
			parts[#parts + 1] = tostring(key) .. '=' .. tostring(val)
		end
	end
	local extra = {}
	for key, val in pairs(fields) do
		if not seen[key] and val ~= nil and val ~= '' then
			extra[#extra + 1] = tostring(key)
		end
	end
	table.sort(extra)
	for i = 1, #extra do
		local key = extra[i]
		parts[#parts + 1] = tostring(key) .. '=' .. tostring(fields[key])
	end
	return table.concat(parts, ' ')
end

function scheduler.action_timeline_write_line(line)
	local fh = io.open(scheduler.action_timeline_log_path(), 'a')
	if fh then
		fh:write(tostring(line or '') .. '\n')
		fh:close()
	end
end

function scheduler.action_timeline_init(now_value)
	if scheduler.action_timeline_state.initialized == true then
		return
	end
	scheduler.action_timeline_state.initialized = true
	scheduler.action_timeline_state.start_at = tonumber(now_value) or now_s()
	scheduler.action_timeline_write_line(('%.3f | %s | SESSION_START | reload=1'):format(
		0,
		scheduler.action_timeline_player_name()
	))
end

function scheduler.action_timeline_log(event_code, fields, dedupe_key, min_interval)
	if not scheduler.action_timeline_enabled() then
		return false
	end
	local now_value = now_s()
	scheduler.action_timeline_init(now_value)
	local key = tostring(dedupe_key or event_code or '')
	local interval = tonumber(min_interval) or 0
	if key ~= '' and interval > 0 then
		local last_at = tonumber(scheduler.action_timeline_state.last_event_at[key]) or 0
		if last_at > 0 and (now_value - last_at) < interval then
			return false
		end
		scheduler.action_timeline_state.last_event_at[key] = now_value
	end
	local elapsed = (tonumber(now_value) or 0) - (tonumber(scheduler.action_timeline_state.start_at) or 0)
	local suffix = scheduler.action_timeline_format_fields(fields)
	local line = ('%.3f | %s | %s'):format(elapsed, scheduler.action_timeline_player_name(), tostring(event_code or 'EVENT'))
	if suffix ~= '' then
		line = line .. ' | ' .. suffix
	end
	scheduler.action_timeline_write_line(line)
	return true
end

_G.UC_ACTION_TIMELINE_LOG = function(event_code, fields, dedupe_key, min_interval)
	return scheduler.action_timeline_log(event_code, fields, dedupe_key, min_interval)
end

function scheduler.log_action_timeline_status_change(status)
	local st = tonumber(status) or -1
	local prev = tonumber(scheduler.action_timeline_state.last_status)
	if prev == st then
		return
	end
	scheduler.action_timeline_state.last_status = st
	scheduler.action_timeline_log('STATUS_CHANGED', {
		from = tostring(prev or 'nil'),
		to = st,
		status = st,
	}, ('status:%d'):format(st), 0)
end

function scheduler.action_timeline_action_state_summary(now_value)
	local st = action_state() or {}
	local now = tonumber(now_value) or now_s()
	local cooldown_until = tonumber(st.cooldown_until) or 0
	local tail_until = tonumber(st.post_spell_tail_until) or 0
	local packet_start_at = tonumber(st.packet_start_at) or 0
	local send_at = tonumber(st.last_sent_at) or 0
	local acting = (tonumber(st.action_end) or 0) < (tonumber(st.action_start) or 0)
	return table.concat({
		('kind=%s'):format(tostring(st.last_send_kind or '')),
		('acting=%s'):format(acting and '1' or '0'),
		('cooldown=%.2f'):format(math.max(0, cooldown_until - now)),
		('tail=%.2f'):format(math.max(0, tail_until - now)),
		('since_sent=%.2f'):format((send_at > 0) and math.max(0, now - send_at) or 0),
		(packet_start_at > 0)
			and ('since_packet=%.2f'):format(math.max(0, now - packet_start_at))
			or 'since_packet=na'
	}, ',')
end

function scheduler.action_timeline_note_spell_sent(fields)
	scheduler.action_timeline_state.last_spell_sent_at = now_s()
	fields = type(fields) == 'table' and fields or {}
	require('uc_scheduler_action_state').note_high_level_spell_sent(scheduler, now_s, fields)
	if tostring(fields.provider or '') ~= '' and tostring(fields.provider or '') ~= 'combat' then
		scheduler.action_timeline_state.last_maintenance_spell_dispatch_at = now_s()
		scheduler.action_timeline_state.last_maintenance_dispatch_action = tostring(fields.spell or fields.action_name or '')
		scheduler.action_timeline_state.last_maintenance_dispatch_token = tostring(tonumber(fields.action_token) or tonumber((action_state() or {}).action_token) or 0)
	end
end

function scheduler.handle_local_spell_action_message(phase, now, player, msg, st, message_id, message_param)
	local matched, match_reason = scheduler.match_active_spell_token_to_cast_finish(msg, st)
	if not matched then
		return false, match_reason
	end
	if scheduler.is_spell_cast_start_message_id(message_id) then
		return false, 'cast_start_message'
	end
	if scheduler.is_spell_cast_complete_message_id(message_id) then
		action_mark_packet_end({
			message_id = message_id,
			message_param = message_param,
		})
		local cleared = scheduler.clear_local_defensive_spell_success({
			message_id = message_id,
			message_param = message_param,
			completion_reason = 'cast_complete',
			release_reason = 'cast_complete',
		})
		if not cleared then
			cleared = scheduler.clear_local_spell_success({
				message_id = message_id,
				message_param = message_param,
				completion_reason = 'cast_complete',
				release_reason = 'cast_complete',
			})
		end
		if cleared then
			scheduler.p1_pending_mark_complete(now, ('spell_cast_complete_%d'):format(message_id))
			local current_lock_until = tonumber(_G.UC_MOVEMENT_LOCK_UNTIL) or 0
			_G.UC_MOVEMENT_LOCK_UNTIL = math.min(current_lock_until, now + 0.2)
			if scheduler.defensive_spell_waiting == true then
				scheduler.clear_defensive_spell_wait_state()
			end
			if tonumber(phase.tank_pending_target_id) and tonumber(phase.tank_pending_target_id) ~= 0 then
				scheduler.p1_clear_tank_spell_wait_state(phase)
			end
		end
		return cleared == true, cleared and 'cast_complete' or require('uc_scheduler_action_state').last_completion_ignore_reason(scheduler)
	end
	if scheduler.is_spell_cast_interrupted_message_id(message_id) then
		action_mark_packet_end({
			message_id = message_id,
			message_param = message_param,
		})
		local cleared = scheduler.clear_local_defensive_spell_interruption({
			message_id = message_id,
			message_param = message_param,
			completion_reason = 'cast_interrupted',
			release_reason = 'cast_interrupted',
		})
		if not cleared then
			cleared = scheduler.clear_local_spell_interruption({
				message_id = message_id,
				message_param = message_param,
				completion_reason = 'cast_interrupted',
				release_reason = 'cast_interrupted',
			})
		end
		if cleared then
			if scheduler.defensive_spell_waiting == true then
				scheduler.clear_defensive_spell_wait_state()
			end
			local current_lock_until = tonumber(_G.UC_MOVEMENT_LOCK_UNTIL) or 0
			_G.UC_MOVEMENT_LOCK_UNTIL = math.min(current_lock_until, now + 0.2)
			scheduler.p1_pending_mark_complete(now, ('spell_cast_interrupted_%d'):format(message_id))
		end
		return cleared == true, cleared and 'cast_interrupted' or require('uc_scheduler_action_state').last_completion_ignore_reason(scheduler)
	end
	return false, 'not_cast_terminal'
end

function scheduler.handle_local_spell_effect_observation(phase, now, msg, st, message_id, message_param)
	phase = type(phase) == 'table' and phase or {}
	st = type(st) == 'table' and st or {}
	local pending_action_name = tostring(phase.tank_pending_action or scheduler.defensive_pending_action or '')
	local last_action_name = tostring(st.last_action_name or pending_action_name or '')
	local expected_tid = tonumber(phase.tank_pending_target_id) or tonumber(scheduler.defensive_pending_target_id) or 0
	local msg_tid = tonumber(msg and msg.target_id) or 0
	if msg_tid > 0 and message_id == 204 and message_param == 2 and scheduler.is_sleep_spell_name(get_settings(), last_action_name) then
		scheduler.mark_sleep_target_suppressed(msg_tid, last_action_name, now)
	end
	if message_id == 17 and message_param == 0 then
		scheduler.record_confirmed_bard_song_success(pending_action_name, expected_tid, msg_tid)
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
		local intent = {
			kind = 'run_stop',
			source = 'unified_scheduler:T2.4c_darklaunch',
			meta = {
				reason = 'MOVE_COORD_CAST_FREEZE_PREP',
				movement_mode = 'CAST_FREEZE',
				freeze_prep_until = freeze_prep_until,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				direct_run = windower.ffxi.run,
				run = windower.ffxi.run,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_CAST_FREEZE_PREP_RUN_STOP_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			ownership_enabled = run_stop_ownership_status.ownership_enabled,
			dispatched = run_stop_ownership_status.dispatched,
			dispatch_ok = run_stop_ownership_status.dispatch_ok,
			dispatch_reason = run_stop_ownership_status.dispatch_reason,
			fallback_used = run_stop_ownership_status.fallback_used,
			stop = run_stop_ownership_status.stop,
		}
		return false, 'MOVE_COORD_CAST_FREEZE_PREP'
	end
	local pull_cast_hold_until = tonumber(rawget(_G, 'UC_PULL_CAST_HOLD_UNTIL')) or 0
	if now < pull_cast_hold_until then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_PULL_CAST_HOLD'
		local intent = {
			kind = 'run_stop',
			source = 'unified_scheduler:T2.4d_darklaunch',
			meta = {
				reason = 'MOVE_COORD_PULL_CAST_HOLD',
				movement_mode = 'CAST_FREEZE',
				pull_cast_hold_until = pull_cast_hold_until,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				direct_run = windower.ffxi.run,
				run = windower.ffxi.run,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_CAST_HOLD_RUN_STOP_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			ownership_enabled = run_stop_ownership_status.ownership_enabled,
			dispatched = run_stop_ownership_status.dispatched,
			dispatch_ok = run_stop_ownership_status.dispatch_ok,
			dispatch_reason = run_stop_ownership_status.dispatch_reason,
			fallback_used = run_stop_ownership_status.fallback_used,
			stop = run_stop_ownership_status.stop,
		}
		return false, 'MOVE_COORD_PULL_CAST_HOLD'
	end
	if rawget(_G, 'UC_PULL_SPELL_WAITING') == true then
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_PULL_SPELL_WAIT'
		local intent = {
			kind = 'run_stop',
			source = 'unified_scheduler:T2.4e_darklaunch',
			meta = {
				reason = 'MOVE_COORD_PULL_SPELL_WAIT',
				movement_mode = 'CAST_FREEZE',
				pull_spell_waiting = true,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				direct_run = windower.ffxi.run,
				run = windower.ffxi.run,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MOVE_COORD_PULL_SPELL_WAIT_RUN_STOP_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			ownership_enabled = run_stop_ownership_status.ownership_enabled,
			dispatched = run_stop_ownership_status.dispatched,
			dispatch_ok = run_stop_ownership_status.dispatch_ok,
			dispatch_reason = run_stop_ownership_status.dispatch_reason,
			fallback_used = run_stop_ownership_status.fallback_used,
			stop = run_stop_ownership_status.stop,
		}
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
	local _, id_set = require('uc_targeting_common').get_friendly_combat_member_ids()
	return id_set
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

function scheduler.action_status_id(name)
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

function scheduler.select_sleep_spell_for_target(settings, target)
	if type(target) ~= 'table' then
		return nil, 'SLEEP_BAD_TARGET'
	end
	local target_id = tonumber(target.id) or 0
	if target_id <= 0 then
		return nil, 'SLEEP_BAD_TARGET'
	end
	local dist = target.distance and target.distance:sqrt() or 999
	local sleep_spells = scheduler.sleep_spell_list_from_settings(settings)
	for index, spell_name in ipairs(sleep_spells) do
		local sp = get_spell_resource(spell_name)
		local ok_ready, ready_reason, action_kind = action_ready(spell_name, target_id)
		if ok_ready and action_kind == 'spell' and sp then
			local max_range = action_effective_range(sp.range)
			local effective_max_range = max_range
			if effective_max_range <= 0 or effective_max_range > scheduler.SLEEP_MAX_TARGET_DISTANCE then
				effective_max_range = scheduler.SLEEP_MAX_TARGET_DISTANCE
			end
			if effective_max_range > 0 and dist <= effective_max_range then
				return {
					name = tostring(spell_name),
					index = index,
					range_max = effective_max_range,
					dist = dist,
				}, ''
			end
			ready_reason = 'SLEEP_OUT_OF_RANGE'
		end
		if ready_reason == '' or ready_reason == nil then
			ready_reason = 'SLEEP_NOT_READY'
		end
	end
	return nil, 'SLEEP_NO_AVAILABLE_SPELL'
end

function scheduler.sleep_target_state_map()
	local p = scheduler.phase1 or {}
	p.sleep_targets = p.sleep_targets or {}
	scheduler.phase1 = p
	return p.sleep_targets
end

function scheduler.sleep_spell_effect_id_set_from_settings(settings)
	local out = {}
	local sleep_spells = scheduler.sleep_spell_list_from_settings(settings)
	for i = 1, #sleep_spells do
		local sp = get_spell_resource(sleep_spells[i])
		local eid = tonumber(sp and sp.status) or 0
		if eid > 0 then
			out[eid] = true
		end
	end
	return out
end

function scheduler.is_sleep_spell_name(settings, spell_name)
	local want = tostring(spell_name or ''):lower()
	if want == '' then
		return false
	end
	local sleep_spells = scheduler.sleep_spell_list_from_settings(settings)
	for i = 1, #sleep_spells do
		if tostring(sleep_spells[i] or ''):lower() == want then
			return true
		end
	end
	return false
end

function scheduler.clear_sleep_target_suppression(target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return false
	end
	local st = scheduler.sleep_target_state_map()
	local had = st[tid] ~= nil
	st[tid] = nil
	return had
end

function scheduler.mark_sleep_target_suppressed(target_id, spell_name, at)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return false
	end
	local now = tonumber(at) or now_s()
	local timeout_s = tonumber(scheduler.SLEEP_TARGET_SUPPRESSION_TIMEOUT_S) or 45.0
	local st = scheduler.sleep_target_state_map()
	st[tid] = {
		spell_name = tostring(spell_name or ''),
		seen_at = now,
		expires_at = now + timeout_s,
	}
	return true
end

function scheduler.target_has_active_sleep_effect(settings, target_id, at)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return false
	end
	enemy_effect_state_prune_expired(at)
	local effects = enemy_effect_state_map()[tid]
	if type(effects) ~= 'table' then
		return false
	end
	local sleep_effect_ids = scheduler.sleep_spell_effect_id_set_from_settings(settings)
	for effect_id, _ in pairs(sleep_effect_ids) do
		if effects[effect_id] ~= nil then
			return true, effect_id
		end
	end
	return false
end

function scheduler.prune_sleep_target_state(settings, at)
	local now = tonumber(at) or now_s()
	local st = scheduler.sleep_target_state_map()
	enemy_effect_state_prune_expired(now)
	for tid, row in pairs(st) do
		local remove = false
		if type(row) ~= 'table' then
			remove = true
		else
			local expires_at = tonumber(row.expires_at) or 0
			if expires_at > 0 and expires_at <= now then
				remove = true
			end
			if not remove then
				local mob = windower.ffxi.get_mob_by_id(tonumber(tid) or 0)
				if not mob or tonumber(mob.spawn_type) ~= 16 or (tonumber(mob.hpp) or 0) <= 0 then
					remove = true
				end
			end
			if not remove and scheduler.target_has_active_sleep_effect(settings, tid, now) then
				remove = true
			end
		end
		if remove then
			scheduler.clear_sleep_target_suppression(tid)
		end
	end
end

function scheduler.target_sleep_suppressed(settings, target_id, at)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return false
	end
	local now = tonumber(at) or now_s()
	scheduler.prune_sleep_target_state(settings, now)
	if scheduler.target_has_active_sleep_effect(settings, tid, now) then
		return true, 'effect'
	end
	local row = scheduler.sleep_target_state_map()[tid]
	if type(row) == 'table' then
		return true, 'local'
	end
	return false
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

function scheduler.resolve_party_member_name_by_id(target_id)
	local want = tonumber(target_id) or 0
	if want == 0 then
		return ''
	end
	for _, member in ipairs(get_party_members() or {}) do
		if tonumber(member and member.id) == want then
			return tostring(member.name or '')
		end
	end
	return ''
end

function scheduler.record_confirmed_bard_song_success(action_name, expected_target_id, message_target_id)
	if is_bard_song(action_name) ~= true then
		return
	end
	local success_target_id = tonumber(expected_target_id) or 0
	if success_target_id == 0 then
		success_target_id = tonumber(message_target_id) or 0
	end
	local success_target_name = scheduler.resolve_party_member_name_by_id(success_target_id)
	if success_target_name == '' then
		return
	end
	local now = now_s()
	local expires_at = now + action_duration_seconds(
		action_name,
		tonumber(get_settings().defensive_overwrite_interval or 150) or 150
	)
	hb_buff_maint.mark_bard_song_success(success_target_name, action_name, now, expires_at)
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
	if c.debuff and c.debuff.spell == 'Paralyna' and c.debuff.target.is_self then
		return c.debuff, 'BLOCK_DEFENSIVE_NA'
	end
	if majesty_action then
		return majesty_action, 'BLOCK_DEFENSIVE_MAJESTY'
	end
	if c.overwrite then
		return c.overwrite, 'BLOCK_DEFENSIVE_OVERWRITE'
	elseif c.cure then
		if c.debuff and ((c.debuff.prio + 2) < c.cure.prio) then
			return c.debuff, 'BLOCK_DEFENSIVE_NA'
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
	local phase = scheduler.phase1 or {}
	if scheduler.p1_pending_engage_live(phase, now_s()) then
		local atype = tostring(action.type or '')
		local target_hpp = tonumber(action.target and action.target.hpp) or -1
		local critical_hpp = tonumber(get_settings().defensive_critical_hpp) or 35
		local is_critical_cure = (atype == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp)
		if not is_critical_cure then
			scheduler.action_timeline_log('PENDING_ENGAGE_BLOCK_NONCRITICAL', {
				action = tostring(action.action and action.action.en or atype or 'healbot_action'),
				provider = 'defensive_healbot',
				target = tostring(action.target and action.target.name or ''),
				target_id = tonumber(action.target and action.target.id) or 0,
			}, ('pending_engage_block:healbot:%s'):format(tostring(action.action and action.action.en or atype or 'healbot_action')), 0.25)
			return false, nil
		end
		scheduler.p1_clear_pending_engage_for_critical_dispatch(phase, tostring(action.action and action.action.en or atype or 'healbot_action'), tonumber(action.target and action.target.id) or 0, tostring(action.target and action.target.name or ''))
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
		local phase = scheduler.phase1 or {}
		if scheduler.p1_pending_engage_live(phase, now) then
			local target_hpp = tonumber(action.target and action.target.hpp) or -1
			local critical_hpp = tonumber(s.defensive_critical_hpp) or 35
			local is_critical_cure = (tostring(action.type or '') == 'cure' and target_hpp > 0 and target_hpp <= critical_hpp)
			if not is_critical_cure then
				scheduler.action_timeline_log('PENDING_ENGAGE_BLOCK_NONCRITICAL', {
					action = tostring(action.spell or ''),
					provider = 'defensive_internal',
					target = tostring(action.target and action.target.name or ''),
					target_id = tonumber(action.target and action.target.id) or 0,
				}, ('pending_engage_block:legacy:%s'):format(tostring(action.spell or '')), 0.25)
				return false, nil
			end
			scheduler.p1_clear_pending_engage_for_critical_dispatch(phase, tostring(action.spell or ''), tonumber(action.target and action.target.id) or 0, tostring(action.target and action.target.name or ''))
		end
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
		_G.UC_DEFENSIVE_CHAIN_ACTION = {
			provider = 'defensive_internal',
			action_kind = tostring(action_kind or ''),
			def_action_type = tostring(action.type or ''),
			action_name = tostring(action.spell or ''),
		}
		local blocked, b_reason = action_dispatch_blocked()
		_G.UC_DEFENSIVE_CHAIN_ACTION = nil
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
		local target_hpp = tonumber(action.target and action.target.hpp) or -1
		local can_apply_defensive_spell_lock = (
			action_kind == 'spell'
			and cmd ~= ''
			and (tostring(action.type or '') ~= 'cure' or target_hpp > 0)
		)
		if can_apply_defensive_spell_lock then
			scheduler.apply_defensive_spell_movement_lock(tostring(action.spell or ''), tonumber(action.target and action.target.id) or 0, now)
		end
		log_def_sched(('DEF_SEND type=%s action="%s" target="%s" cmd=%s'):format(
			tostring(action_kind or action.type or 'defensive'),
			tostring(action.spell or ''),
			tostring(action.target and action.target.name or ''),
			tostring(cmd or '')
		))
		local intent = {
			kind = 'send_command',
			source = 'unified_scheduler:T2.1_darklaunch',
			command = cmd,
			meta = {
				action_kind = tostring(action_kind or action.type or 'defensive'),
				action_name = tostring(action.spell or ''),
				target_name = tostring(action.target and action.target.name or ''),
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				direct_send_command = windower.send_command,
				send_command = windower.send_command,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_INTERNAL_DISPATCH_COMMAND_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
				command = cmd,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_DISPATCH_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			command_present = command_ownership_status.command_present,
			ownership_enabled = command_ownership_status.ownership_enabled,
			dispatched = command_ownership_status.dispatched,
			dispatch_ok = command_ownership_status.dispatch_ok,
			dispatch_reason = command_ownership_status.dispatch_reason,
			fallback_used = command_ownership_status.fallback_used,
		}
		if can_apply_defensive_spell_lock then
			scheduler.begin_defensive_spell_wait(tostring(action.spell or ''), tonumber(action.target and action.target.id) or 0, now)
		end
		action_mark_sent(action_kind or action.type or 'defensive', {
			action_name = tostring(action.spell or ''),
			provider = 'defensive_internal',
			def_action_type = tostring(action.type or ''),
			target_id = tonumber(action.target and action.target.id) or 0,
			target_kind = ((tonumber(action.target and action.target.id) or 0) ~= 0 and (tonumber(action.target and action.target.id) or 0) ~= (tonumber(p and p.id) or 0)) and 'ally' or 'self',
		})
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

local p1_combat_helpers = {}

function p1_combat_helpers.sleep_target_eligible(ctx, mob, current_target_id, claims_set, partner_target_set)
	if not combat_core.is_live_actionable_combat_target(mob, ctx.now, true) then
		return false
	end
	local tid = tonumber(mob.id) or 0
	if tid <= 0 then
		return false
	end
	if current_target_id > 0 and tid == current_target_id then
		return false
	end
	if partner_target_set[tid] == true then
		return false
	end
	if claims_set[tonumber(mob.claim_id) or 0] ~= true then
		return false
	end
	if tonumber(mob.status) ~= 1 then
		return false
	end
	if (tonumber(mob.hpp) or 0) <= 99 then
		return false
	end
	local dist = mob.distance and mob.distance:sqrt() or 999
	if dist > scheduler.SLEEP_MAX_TARGET_DISTANCE then
		return false
	end
	if scheduler.target_sleep_suppressed(ctx.settings, tid, ctx.now) then
		return false
	end
	return true
end

function p1_combat_helpers.collect_combat_sleep(ctx, out)
	if not bool_setting(rawget(_G, 'Start_Engine'), false) then
		return
	end
	if not bool_setting(ctx.settings.scheduler_dark_launch_combat, false) then
		return
	end
	if not bool_setting(ctx.settings.sleep, false) then
		return
	end
	local configured_sleep_spells = scheduler.sleep_spell_list_from_settings(ctx.settings)
	if #configured_sleep_spells == 0 then
		return
	end
	local player = windower.ffxi.get_player()
	if not player then
		return
	end
	local current_target = windower.ffxi.get_mob_by_target('t')
	local current_target_id = 0
	if current_target and combat_core.is_live_actionable_combat_target(current_target, ctx.now, true) then
		current_target_id = tonumber(current_target.id) or 0
	end
	local _, claims_set = uc_targeting_common.build_friendly_claims()
	local partner_target_set = build_partner_target_set(ctx.settings)
	local best = nil
	local marray = windower.ffxi.get_mob_array() or {}
	for _, mob in pairs(marray) do
		if p1_combat_helpers.sleep_target_eligible(ctx, mob, current_target_id, claims_set, partner_target_set) then
			local spell_pick = scheduler.select_sleep_spell_for_target(ctx.settings, mob)
			if spell_pick then
				local tid = tonumber(mob.id) or 0
				local dist = tonumber(spell_pick.dist) or 999
				if not best
					or dist < best.dist
					or (dist == best.dist and tid < best.target_id) then
					best = {
						target_id = tid,
						target_name = tostring(mob.name or ''),
						dist = dist,
						spell_name = tostring(spell_pick.name or ''),
						spell_index = tonumber(spell_pick.index) or 0,
						range_max = tonumber(spell_pick.range_max) or 0,
						target_hpp = tonumber(mob.hpp) or 0,
					}
				end
			end
		end
	end
	if not best then
		return
	end
	local urgency = 0.55
	if best.range_max > 0 then
		urgency = 1.0 - math.min(1.0, best.dist / best.range_max)
		if urgency < 0.55 then
			urgency = 0.55
		end
	end
	out[#out + 1] = {
		proposal_id = ('combat.sleep.%s.%d.%d'):format(
			tostring(best.spell_name),
			tonumber(best.target_id) or 0,
			math.floor(ctx.now * 1000)
		),
		family_id = 'combat.sleep.primary',
		provider = 'combat',
		action_type = 'spell',
		action_name = tostring(best.spell_name),
		target_kind = 'mob',
		target_id = tonumber(best.target_id) or 0,
		target_name = tostring(best.target_name or ''),
		priority_band = 94,
		urgency = p1_clamp_urgency(urgency),
		starvation_eligible = true,
		created_at = ctx.now,
		expires_at = ctx.now + 0.30,
		commit_deadline = ctx.now + 0.20,
		movement_policy = 'must_stop',
		range_policy = { min = 0.0, max = tonumber(best.range_max) or 0, los_required = true },
		recast_key = ('sleep:%s'):format(tostring(best.spell_name)),
		duplicate_suppression_key = ('sleep:%s:%d'):format(
			tostring(best.spell_name),
			tonumber(best.target_id) or 0
		),
		lock_class = 'offense_action',
		expected_ack = 'action_start',
		expected_effect = 'spell_effect',
		sticky = false,
		can_preempt_movement = true,
		can_preempt_same_band = false,
		reason_code = 'sleep_add_control',
		detail = {
			sleep_spell_index = tonumber(best.spell_index) or 0,
			sleep_target_distance = tonumber(best.dist) or 0,
			sleep_target_hpp = tonumber(best.target_hpp) or 0,
			sleep_configured_count = #configured_sleep_spells,
			allow_target_id_send = true,
		},
		legacy_command = ('input /ma \"%s\" %d'):format(
			tostring(best.spell_name),
			tonumber(best.target_id) or 0
		),
		required_setting = 'sleep',
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
	local _, claims_set = uc_targeting_common.build_friendly_claims()
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
	local tank_mode = bool_setting(ctx.settings and ctx.settings.tank, false)
	local engage_priority = tank_mode and scheduler.TANK_ENGAGE_PRIORITY or scheduler.DEFAULT_ENGAGE_PRIORITY
	local engage_urgency = tank_mode and scheduler.TANK_ENGAGE_URGENCY or scheduler.DEFAULT_ENGAGE_URGENCY
	local engaged = tonumber(player.status) == 1
	local function p1_engage_action_state_summary()
		local st = scheduler.action_state or {}
		local now_value = tonumber(ctx.now) or now_s()
		local cooldown_until = tonumber(st.cooldown_until) or 0
		local post_spell_tail_until = tonumber(st.post_spell_tail_until) or 0
		local action_start = tonumber(st.action_start) or 0
		local action_end = tonumber(st.action_end) or 0
		local acting = action_end < action_start
		local parts = {
			('kind=%s'):format(tostring(st.last_send_kind or '')),
			('acting=%s'):format(acting and '1' or '0'),
			('cooldown=%.2f'):format(math.max(0, cooldown_until - now_value)),
			('tail=%.2f'):format(math.max(0, post_spell_tail_until - now_value)),
		}
		return table.concat(parts, ',')
	end
	local function p1_engage_pending_state_summary()
		local pending = scheduler.p1_pending_engage_state(scheduler.phase1)
		if type(pending) ~= 'table' then
			return 'inactive'
		end
		local retry_ready_at = tonumber(pending.retry_ready_at) or 0
		local retry_count = tonumber(pending.retry_count) or 0
		local now_value = tonumber(ctx.now) or now_s()
		if scheduler.p1_pending_engage_live(scheduler.phase1, now_value) then
			return ('active:retry=%.2f,count=%d'):format(math.max(0, retry_ready_at - now_value), retry_count)
		end
		return ('stale:count=%d'):format(retry_count)
	end
	local function p1_existing_top_proposal_summary()
		local top = type(out) == 'table' and out[1] or nil
		if type(top) ~= 'table' then
			return '', '', ''
		end
		return tostring(top.family_id or ''), tostring(top.provider or ''), tostring(top.action_name or '')
	end
	local function p1_log_engage_proposal_probe(event_code, target, skip_reason, pull_owner_state, claim_check)
		if not target or tonumber(player.status) == 1 then
			return
		end
		local dist = target.distance and target.distance:sqrt() or 999
		local top_family, top_provider, top_action = p1_existing_top_proposal_summary()
		scheduler.action_timeline_log(event_code, {
			tid = tonumber(target.id) or 0,
			name = tostring(target.name or ''),
			role = tank_mode and 'tank' or 'default',
			tank = tank_mode and 1 or 0,
			status = tonumber(player.status) or 0,
			pull_owner = tostring(pull_owner_state or ''),
			target_valid = target.valid_target == true and 1 or 0,
			range = ('%.2f'):format(tonumber(dist) or 999),
			claim_check = tostring(claim_check or ''),
			pending_engage = p1_engage_pending_state_summary(),
			action_state = p1_engage_action_state_summary(),
			top_family = top_family,
			top_provider = top_provider,
			top_action = top_action,
			reason = tostring(skip_reason or ''),
		}, ('engage_proposal_probe:%s:%d:%s'):format(
			tostring(event_code or ''),
			tonumber(target.id) or 0,
			tostring(skip_reason or '')
		), 0.50)
	end
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
		if t then
			p1_log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED', t, 'no_valid_target', 'inactive', 'not_checked')
		end
		return
	end
	-- Hunter/path pull ownership: when a pull action is currently applicable, suppress
	-- engage proposals so we do not run into melee before the configured pull executes.
	local pull_owner_state = 'inactive'
	if combat_core and type(combat_core.select_pull_for_scheduler) == 'function' then
		local pull_pick = combat_core.select_pull_for_scheduler(ctx.settings)
		if type(pull_pick) == 'table' then
			local pull_tid = tonumber(pull_pick.target_id) or 0
			local this_tid = tonumber(t.id) or 0
			pull_owner_state = ('candidate:%s:%s:%d'):format(
				tostring(pull_pick.provider or ''),
				tostring(pull_pick.action_name or pull_pick.action_type or ''),
				pull_tid
			)
			if pull_tid > 0 and this_tid > 0 and pull_tid == this_tid then
				if bool_setting(ctx.settings and ctx.settings.debug, false) then
					_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_skip:pull_owner tid=%d action=%s:%s'):format(
						this_tid,
						tostring(pull_pick.action_type or ''),
						tostring(pull_pick.action_name or '')
					)
				end
				p1_log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED', t, 'pull_owner', pull_owner_state, 'not_checked')
				return
			end
		end
	end
	local _, claims_set = uc_targeting_common.build_friendly_claims()
	local claim_id = tonumber(t.claim_id) or 0
	local party_ids = p1_build_party_id_set()
	local party_claimed_ok = claims_set[claim_id] == true
	local prime_unclaimed_ok = p1_prime_unclaimed_party_aggressive_ok(ctx.settings, t, party_ids)
	local force_leader_engage = (fight_leader_force_target_id > 0 and fight_leader_force_target_id == (tonumber(t.id) or 0))
	local claim_check = ('party_claimed=%s,prime_unclaimed=%s,force_leader=%s,claim_id=%d'):format(
		party_claimed_ok and '1' or '0',
		prime_unclaimed_ok and '1' or '0',
		force_leader_engage and '1' or '0',
		claim_id
	)
	if not party_claimed_ok and not prime_unclaimed_ok and not force_leader_engage then
		if bool_setting(ctx.settings and ctx.settings.debug, false) then
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:collect_skip:policy claim=%d st=%d prime=%s'):format(
				claim_id,
				tonumber(t.status) or 0,
				tostring(bool_setting(ctx.settings and ctx.settings.prime, false))
			)
		end
		p1_log_engage_proposal_probe('ENGAGE_PROPOSAL_SKIPPED', t, 'claim_policy', pull_owner_state, claim_check)
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
	scheduler.action_timeline_log('ENGAGE_PROPOSED', {
		tid = tonumber(t.id) or 0,
		name = tostring(t.name or ''),
		band = engage_priority,
		urgency = ('%.2f'):format(p1_clamp_urgency(engage_urgency)),
	}, ('engage_proposed:%d'):format(tonumber(t.id) or 0), 0.50)
	p1_log_engage_proposal_probe('ENGAGE_PROPOSAL_CREATED', t, 'engage_ready', pull_owner_state, claim_check)
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
	local tank_mode = bool_setting(ctx.settings and ctx.settings.tank, false)
	local priority_band = tank_mode and scheduler.TANK_TARGET_ACQUIRE_PRIORITY or 84
	local urgency = tank_mode and scheduler.TANK_TARGET_ACQUIRE_URGENCY or 0.55
	local cur = windower.ffxi.get_mob_by_target('t')
	if cur and tonumber(cur.id) == tid then
		scheduler.action_timeline_log('TARGET_SELECT_SKIPPED_ALREADY_TARGETED', {
			tid = tid,
			name = tostring(pick.target_name or ''),
		}, ('target_already:%d'):format(tid), 0.50)
		return
	end
	scheduler.action_timeline_log('TARGET_ACQUIRE_CANDIDATE', {
		tid = tid,
		name = tostring(pick.target_name or ''),
		band = priority_band,
		urgency = ('%.2f'):format(p1_clamp_urgency(urgency)),
	}, ('target_candidate:%d'):format(tid), 0.50)
	out[#out + 1] = {
		proposal_id = ('target.acquire.%d.%d'):format(tid, math.floor(ctx.now * 1000)),
		family_id = 'target.acquire.primary',
		provider = 'target_control',
		action_type = 'target',
		action_name = 'acquire_target',
		target_kind = 'mob',
		target_id = tid,
		target_name = tostring(pick.target_name or ''),
		priority_band = priority_band,
		urgency = p1_clamp_urgency(urgency),
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
	local tank_mode = bool_setting(ctx.settings and ctx.settings.tank, false)
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
					local priority_band = tank_mode and 99 or 70
					out[#out + 1] = {
						proposal_id = ('combat.ja.%s.%d.%d'):format(tostring(name), target_id, math.floor(ctx.now * 1000)),
						family_id = 'combat.ja.primary',
						provider = 'combat',
						action_type = 'ja',
						action_name = tostring(name),
						target_kind = target_kind,
						target_id = target_id,
						target_name = target_name,
						priority_band = priority_band,
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
	local function log_maint_candidate(event_code, key, action_name, provider, reason, urgency, detail, interval)
		detail = type(detail) == 'table' and detail or {}
		local fields = {
			spell = (tostring(detail.cast_type or '') == 'spell' or tostring(detail.action_type or '') == 'spell') and tostring(action_name or '') or '',
			action = tostring(action_name or ''),
			target = tostring(detail.target_name or player.name or ''),
			target_id = tonumber(detail.target_id) or tonumber(player.id) or 0,
			provider = tostring(provider or ''),
			band = 75,
			urgency = (urgency ~= nil) and ('%.2f'):format(p1_clamp_urgency(urgency)) or '',
			reason = tostring(reason or ''),
			status = tonumber(player.status) or 0,
			action_state = scheduler.action_timeline_action_state_summary(now),
			range = detail.range or '',
			target_valid = detail.target_valid,
		}
		for extra_key, extra_value in pairs(detail) do
			if fields[extra_key] == nil or fields[extra_key] == '' then
				fields[extra_key] = extra_value
			end
		end
		scheduler.action_timeline_log(event_code, fields, ('maint_candidate:%s:%s:%s'):format(tostring(event_code or ''), tostring(key or ''), tostring(reason or '')), interval or 2.0)
	end
	local function maybe_emit(key, provider, action_type, action_name, reason_code, urgency, detail)
		detail = type(detail) == 'table' and detail or {}
		detail.cast_type = action_type
		detail.action_type = action_type
		detail.target_name = tostring(player.name or '')
		detail.target_id = tonumber(player.id) or 0
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
					detail.proposal_emitted = '0'
					log_maint_candidate('MAINT_BUFF_CANDIDATE_HELD', key, action_name, provider, 'player_moving', urgency, detail, 2.0)
					return false, 'player_moving', 0
				end
			end
		end
		local next_at = p1_number(gate[key], 0)
		if now < next_at then
			detail.throttle_key = tostring(key or '')
			detail.now_value = ('%.2f'):format(now)
			detail.next_allowed_at = ('%.2f'):format(next_at)
			detail.remaining_s = ('%.2f'):format(math.max(0, next_at - now))
			detail.last_maintenance_action = tostring(scheduler.action_timeline_state.last_maintenance_dispatch_action or '')
			detail.last_maintenance_token = tostring(scheduler.action_timeline_state.last_maintenance_dispatch_token or '')
			detail.proposal_emitted = '0'
			log_maint_candidate('MAINT_BUFF_CANDIDATE_HELD', key, action_name, provider, 'throttle', urgency, detail, 2.0)
			return false, 'throttle', math.max(0, next_at - now)
		end
		gate[key] = now + 2.0
		detail.proposal_emitted = '1'
		log_maint_candidate('MAINT_BUFF_CANDIDATE_READY', key, action_name, provider, reason_code, urgency, detail, 0.50)
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
		return true, nil, 0
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
				log_maint_candidate('MAINT_BUFF_CANDIDATE_READY', key, action_name, 'maintenance_cor', tostring(action.reason_code or 'cor_roll_maint'), urgency, {
					target_name = target_name,
					target_id = target_id,
					action_type = 'ja',
				}, 0.50)
			else
				log_maint_candidate('MAINT_BUFF_CANDIDATE_HELD', key, tostring(action.action_name or ''), 'maintenance_cor', 'throttle', tonumber(action.urgency) or 0.65, {
					target_name = tostring(action.target_name or '<me>'),
					target_id = tonumber(action.target_id) or 0,
					action_type = 'ja',
				}, 2.0)
			end
		else
			log_def_sched('MAINT_COR_SKIP reason=PROPOSE_NIL')
			log_maint_candidate('MAINT_BUFF_CANDIDATE_SKIPPED', 'cor_rolls', '', 'maintenance_cor', 'propose_nil', 0.65, {
				action_type = 'ja',
			}, 2.0)
			gate.cor_rolls = 0
		end
	elseif job == 'BRD' then
		local song_count = count_matching_buffs(buff_list, maintenance_buff_cache.song_ids)
		if song_count < 2 then
			local emitted, blocker_reason, throttle_remaining = maybe_emit('brd_songs', 'brd', 'spell', 'maintenance_songs', 'songs_missing', (song_count == 0) and 0.80 or 0.50, {
				job = job,
				song_count = song_count,
				expected = 2,
			})
			if emitted ~= true then
				scheduler.action_timeline_log('MAINT_SONG_READY_NO_DISPATCH', {
					action = 'maintenance_songs',
					provider = 'brd',
					reason = tostring(blocker_reason or 'unknown'),
					song_count = tostring(song_count),
					expected = '2',
					best_action = 'maintenance_songs',
					top_provider = '',
					top_action = '',
					remaining_s = (tonumber(throttle_remaining) or 0) > 0 and ('%.2f'):format(tonumber(throttle_remaining) or 0) or '',
				}, ('maint_song_ready_no_dispatch:%s'):format(tostring(blocker_reason or 'unknown')), 2.0)
			end
		else
			local song_snapshot = scheduler.active_song_snapshot(buff_list, maintenance_buff_cache.song_ids)
			log_maint_candidate('MAINT_BUFF_CANDIDATE_SKIPPED', 'brd_songs', 'maintenance_songs', 'brd', 'songs_satisfied', 0.50, {
				action_type = 'spell',
				expected = 2,
				song_count = song_count,
				active_song_count = song_snapshot.active_song_count,
				expected_song_count = song_snapshot.expected_song_count,
				song_names = song_snapshot.song_names,
				song_lowest_remaining_s = song_snapshot.song_lowest_remaining_s,
			}, 2.0)
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
			log_maint_candidate('MAINT_BUFF_CANDIDATE_SKIPPED', 'geo_buffs', 'maintenance_geo', 'geo', 'geo_satisfied', 0.45, {
				action_type = 'spell',
			}, 2.0)
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
	p1_combat_helpers.collect_combat_sleep(ctx, out)
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
	for i = 1, #out do
		local proposal = out[i]
		if type(proposal) == 'table' then
			local provider = tostring(proposal.provider or '')
			local action_type = tostring(proposal.action_type or '')
			local detail = type(proposal.detail) == 'table' and proposal.detail or {}
			if provider == 'defensive_internal' or provider == 'defensive_healbot' then
				if action_type == 'spell' and tostring(detail.def_action_type or '') == 'cure' then
					local critical_hpp = tonumber(ctx.settings and ctx.settings.defensive_critical_hpp) or 35
					local target_hpp = tonumber(detail.target_hpp or -1) or -1
					local event_code = (target_hpp > 0 and target_hpp <= critical_hpp) and 'CRITICAL_CURE_PROPOSED' or 'NONCRITICAL_CURE_PROPOSED'
					scheduler.action_timeline_log(event_code, {
						spell = tostring(proposal.action_name or ''),
						target = tostring(proposal.target_name or ''),
						target_id = tonumber(proposal.target_id) or 0,
						critical = tostring(event_code == 'CRITICAL_CURE_PROPOSED'),
						band = tonumber(proposal.priority_band) or 0,
					}, ('%s:%s:%d'):format(event_code, tostring(proposal.action_name or ''), tonumber(proposal.target_id) or 0), 0.50)
				end
			elseif provider == 'maintenance' then
				scheduler.action_timeline_log('MAINT_BUFF_PROPOSED', {
					action = tostring(proposal.action_name or ''),
					provider = provider,
					band = tonumber(proposal.priority_band) or 0,
				}, ('maint_proposed:%s'):format(tostring(proposal.action_name or '')), 0.50)
			elseif tostring(proposal.family_id or '') == 'combat.sleep.primary' then
				scheduler.action_timeline_log('SLEEP_PROPOSED', {
					spell = tostring(proposal.action_name or ''),
					tid = tonumber(proposal.target_id) or 0,
					name = tostring(proposal.target_name or ''),
					band = tonumber(proposal.priority_band) or 0,
				}, ('sleep_proposed:%d:%s'):format(tonumber(proposal.target_id) or 0, tostring(proposal.action_name or '')), 0.50)
			end
		end
	end
	return out
end

function scheduler.p1_pending_is_live_state(state_name)
	return scheduler_locks.p1_pending_is_live_state(state_name)
end

function scheduler.p1_update_pending_state(ctx)
	return scheduler_pending.p1_update_pending_state(scheduler, ctx, scheduler.p1_pending_is_live_state, p1_number)
end

function scheduler.p1_duplicate_suppressed(ctx, proposal)
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

function scheduler.active_song_snapshot(buff_list, song_id_set)
	local names = {}
	for _, buff_id in ipairs(buff_list or {}) do
		local bid = tonumber(buff_id) or 0
		if bid > 0 and song_id_set[bid] == true then
			local buff = res.buffs and res.buffs[bid] or nil
			local name = tostring((buff and buff.en) or '')
			if name ~= '' then
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return {
		active_song_count = tostring(#names),
		expected_song_count = '2',
		song_names = (#names > 0) and table.concat(names, ', ') or '',
		song_lowest_remaining_s = 'na',
	}
end

function scheduler.p1_get_locks(ctx)
	return scheduler_locks.p1_get_locks(scheduler, ctx, p1_number, _G)
end

function scheduler.p1_hard_lock_reject(locks, proposal)
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
	local pending_engage_live = scheduler.p1_pending_engage_live(phase, ctx.now)
	if pending_engage_live then
		local provider = tostring(p.provider or '')
		local action_type = tostring(p.action_type or '')
		if provider ~= 'target_control' then
			if action_type == 'engage' then
				local pending = scheduler.p1_pending_engage_state(phase)
				local retry_ready_at = tonumber(pending and pending.retry_ready_at) or 0
				if retry_ready_at > ctx.now then
					scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
						tid = tonumber(p.target_id) or 0,
						name = tostring(p.target_name or ''),
						reason = 'pending_engage_retry_wait',
						retry_in_s = ('%.2f'):format(math.max(0, retry_ready_at - ctx.now)),
						retry_count = tonumber(pending and pending.retry_count) or 0,
						pending_engage = 'retry_wait',
						dispatch_method = scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON,
					}, ('engage_retry_wait:%d'):format(tonumber(p.target_id) or 0), 0.25)
					return false, 'pending_engage_retry_wait'
				end
			elseif not scheduler.p1_is_critical_defensive_proposal(ctx.settings, p) then
				scheduler.action_timeline_log('PENDING_ENGAGE_BLOCK_NONCRITICAL', {
					tid = tonumber(p.target_id) or 0,
					name = tostring(p.target_name or ''),
					action = tostring(p.action_name or ''),
					provider = provider,
				}, ('pending_engage_block:%s:%s'):format(provider, tostring(p.action_name or '')), 0.25)
				return false, 'pending_engage_block_noncritical'
			end
		end
	end
	if type(phase.pending) == 'table' and scheduler.p1_pending_is_live_state(tostring(phase.pending.state or '')) then
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
	local engage_duplicate_mode, engage_duplicate_fields = scheduler.p1_validate_engage_duplicate_retry(ctx, p)
	if engage_duplicate_mode == 'suppressed' then
		p._engage_duplicate_log_fields = engage_duplicate_fields
		return false, 'duplicate_suppressed'
	end
	if engage_duplicate_mode ~= 'skip_generic' and scheduler.p1_duplicate_suppressed(ctx, p) then
		p._engage_duplicate_log_fields = engage_duplicate_fields
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
	local locks = scheduler.p1_get_locks(ctx)
	local valid = {}
	local reject_counts = {}
	local rejected = {}
	local function add_reject(proposal, reason)
		local p = proposal or {}
		if tostring(p.family_id or '') == 'combat.engage.primary' and tostring(reason or '') == 'duplicate_suppressed' then
			local fields = type(p._engage_duplicate_log_fields) == 'table' and p._engage_duplicate_log_fields or {
				tid = tonumber(p.target_id) or 0,
				name = tostring(p.target_name or ''),
				reason = 'BLOCK_DUPLICATE',
				status = tonumber(ctx and ctx.player_status) or 0,
				dispatch_method = scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON,
			}
			scheduler.action_timeline_log('ENGAGE_DUPLICATE_SUPPRESSED', fields, ('engage_dup:%d'):format(tonumber(p.target_id) or 0), 0.50)
		end
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
			local lock_reject = scheduler.p1_hard_lock_reject(locks, proposal)
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
			local top = valid[1]
			local block_reason = 'BLOCK_UNKNOWN'
			if scheduler.p1_is_critical_defensive_proposal(ctx and ctx.settings or nil, top) then
				block_reason = 'BLOCK_CRITICAL_CURE'
			end
			scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
				tid = tonumber(valid[1] and valid[1].target_id) or 0,
				name = tostring(valid[1] and valid[1].target_name or ''),
				reason = block_reason,
				provider = top_provider,
				action = top_action,
			}, ('engage_rank_lost:%s:%s'):format(top_provider, top_action), 0.50)
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

function scheduler.p1_set_pending_globals()
	return scheduler_pending.p1_set_pending_globals(scheduler, _G)
end

function scheduler.p1_build_lock_summary(ctx, locks)
	return scheduler_locks.p1_build_lock_summary(ctx, locks, scheduler.p1_get_locks)
end

function scheduler.p1_record_legacy_dispatch(ctx)
	return require('uc_scheduler_pending_record').p1_record_legacy_dispatch(scheduler, ctx, p1_number)
end

function scheduler.p1_pending_mark_complete(now, result_code)
	return scheduler_pending.p1_pending_mark_complete(scheduler, now, result_code)
end

local function p1_run_dry(settings)
	local ctx = p1_build_ctx(settings)
	scheduler.p1_update_pending_state(ctx)
	local proposals = p1_collect_proposals(ctx)
	local ranked, reject_counts, locks, rejected = p1_rank(ctx, proposals)
	local function is_maint_spell_candidate(proposal)
		if type(proposal) ~= 'table' then
			return false
		end
		local provider = tostring(proposal.provider or '')
		local action_type = tostring(proposal.action_type or '')
		return action_type == 'spell' and (provider == 'maintenance' or provider == 'brd' or provider == 'geo' or provider == 'defensive_internal' or provider == 'defensive_healbot')
	end
	local function best_maint_candidate(list)
		if type(list) ~= 'table' then
			return nil
		end
		for i = 1, #list do
			if is_maint_spell_candidate(list[i]) then
				return list[i]
			end
		end
		return nil
	end
	local selected = ranked[1]
	if type(selected) == 'table' then
		local engage_candidate = scheduler.p1_pick_preemptive_engage(ctx, ranked)
		if type(engage_candidate) == 'table' then
			selected = engage_candidate
		end
	end
	if type(selected) == 'table' then
		local selected_provider_for_weave = tostring(selected.provider or '')
		local detail = type(selected.detail) == 'table' and selected.detail or nil
		local target_hpp = tonumber(detail and detail.target_hpp or -1) or -1
		local critical_hpp = tonumber(ctx.settings and ctx.settings.defensive_critical_hpp) or 35
		local is_defensive_cure_selected = (
			(selected_provider_for_weave == 'defensive_internal' or selected_provider_for_weave == 'defensive_healbot')
			and tostring(selected.action_type or '') == 'spell'
			and tostring(detail and detail.def_action_type or '') == 'cure'
		)
		local cure_is_critical = (target_hpp > 0 and target_hpp <= critical_hpp)
		if is_defensive_cure_selected
			and not cure_is_critical
			and require('uc_scheduler_action_state').defensive_cure_weave_ready(scheduler, now_s) then
			for i = 2, #ranked do
				local candidate = ranked[i]
				if type(candidate) == 'table'
					and tostring(candidate.provider or '') == 'combat'
					and (tostring(candidate.action_type or '') == 'ja' or tostring(candidate.action_type or '') == 'ws') then
					local target_kind = tostring(candidate.target_kind or '')
					local target_id = tonumber(candidate.target_id) or 0
					if target_kind ~= 'mob' or target_id > 0 then
						local candidate_plan = p1_build_dispatch_plan(ctx, candidate)
						local candidate_ok = p1_revalidate_plan_commit(ctx, candidate, candidate_plan)
						if candidate_ok then
							candidate._weave_from_provider = tostring(selected.provider or '')
							candidate._weave_from_action = tostring(selected.action_name or '')
							selected = candidate
							break
						end
					end
				end
			end
		end
	end
	local plan = p1_build_dispatch_plan(ctx, selected)
	local commit_ok, commit_reason = p1_revalidate_plan_commit(ctx, selected, plan)
	if selected and not commit_ok then
		selected = nil
		plan = nil
	end
	do
		local best_maint = best_maint_candidate(ranked)
		local top = type(selected) == 'table' and selected or ranked[1]
		if best_maint and top and best_maint ~= top then
			scheduler.action_timeline_log('MAINT_BUFF_CANDIDATE_LOST_RANKING', {
				spell = tostring(best_maint.action_name or ''),
				target = tostring(best_maint.target_name or ''),
				target_id = tonumber(best_maint.target_id) or 0,
				provider = tostring(best_maint.provider or ''),
				band = tonumber(best_maint.priority_band) or 0,
				urgency = ('%.2f'):format(p1_clamp_urgency(best_maint.urgency)),
				reason = 'top_other_selected',
				action_state = scheduler.action_timeline_action_state_summary(ctx.now),
				top_family = tostring(top.family_id or ''),
				top_provider = tostring(top.provider or ''),
				top_action = tostring(top.action_name or ''),
			}, ('maint_lost:%s:%s'):format(tostring(best_maint.action_name or ''), tostring(top.action_name or '')), 1.00)
		end
		local st = action_state() or {}
		local acting = action_is_acting()
		local tail_until = tonumber(st.post_spell_tail_until) or 0
		local sent_at = tonumber(scheduler.action_timeline_state.last_spell_sent_at) or 0
		local maint_at = tonumber(scheduler.action_timeline_state.last_maintenance_spell_dispatch_at) or 0
		if best_maint and not acting and ctx.now >= tail_until and (not selected or selected ~= best_maint) then
			scheduler.action_timeline_log('MAINT_BUFF_IDLE_GAP', {
				since_sent_s = (sent_at > 0) and ('%.2f'):format(math.max(0, ctx.now - sent_at)) or '',
				age_s = (maint_at > 0) and ('%.2f'):format(math.max(0, ctx.now - maint_at)) or '',
				top_family = tostring(top and top.family_id or ''),
				top_provider = tostring(top and top.provider or ''),
				top_action = tostring(top and top.action_name or ''),
				best_action = tostring(best_maint.action_name or ''),
				best_provider = tostring(best_maint.provider or ''),
				best_target = tostring(best_maint.target_name or ''),
				best_target_id = tonumber(best_maint.target_id) or 0,
				reason = top and 'different_top_selected' or 'no_selected_dispatch',
				action_state = scheduler.action_timeline_action_state_summary(ctx.now),
			}, ('maint_idle_gap:%s'):format(tostring(best_maint.action_name or '')), 2.00)
		end
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
		scheduler.p1_set_pending_globals,
		scheduler.p1_build_lock_summary
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
		local intent = {
			kind = 'select_target',
			source = 'unified_scheduler:T2.2_darklaunch',
			target_id = tid,
			meta = {
				current_target_id = tonumber(cur and cur.id) or 0,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
		local target_ownership_status = require('uc_scheduler_target_ownership').apply_target_ownership({
			dispatcher = dispatcher,
			direct_select_target = uc_settarget.select_by_id,
			set_target = uc_settarget.select_by_id,
			ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP == true),
			promoted_default_on = true,
			ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TARGET_OWNERSHIP == false),
			promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
			intent = intent,
			target_id = tid,
		})
		_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			target_id = tonumber(intent.target_id) or 0,
			ownership_enabled = target_ownership_status.ownership_enabled,
			dispatched = target_ownership_status.dispatched,
			dispatch_ok = target_ownership_status.dispatch_ok,
			dispatch_reason = target_ownership_status.dispatch_reason,
			fallback_used = target_ownership_status.fallback_used,
			selected = target_ownership_status.selected,
		}
		ok = target_ownership_status.selected
	end
	return ok
end

function scheduler.p1_apply_target_acquire_debounce(proposal, at)
	local dkey = tostring(proposal and proposal.duplicate_suppression_key or '')
	if dkey == '' then
		return
	end
	local now = tonumber(at) or now_s()
	local debounce_s = tonumber(scheduler.TARGET_ACQUIRE_DEBOUNCE_S) or 0.20
	scheduler.phase1.recent_duplicate_until[dkey] = now + debounce_s
end

function scheduler.p1_dispatch_target_control(selected, ctx)
	if type(selected) ~= 'table' then
		return false, nil
	end
	local tid = tonumber(selected.target_id) or 0
	if tid <= 0 then
		return false, nil
	end
	local ok = p1_try_target_prep(tid)
	if not ok then
		scheduler.action_timeline_log('TARGET_SELECT_BLOCKED', {
			tid = tid,
			name = tostring(selected.target_name or ''),
			reason = 'BLOCK_INVALID_TARGET',
		}, ('target_blocked:%d:prep'):format(tid), 0.50)
		return false, nil
	end
	scheduler.phase1.last_selected = selected
	scheduler.phase1.last_plan = p1_build_dispatch_plan(ctx, selected)
	scheduler.p1_apply_target_acquire_debounce(selected, ctx.now)
	scheduler.p1_maybe_release_stale_spell_lock_for_target_transition(selected, ctx.now)
	scheduler.action_timeline_log('TARGET_SELECTED', {
		tid = tid,
		name = tostring(selected.target_name or ''),
	}, ('target_selected:%d'):format(tid), 0.05)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]target:%d->%s'):format(tid, tostring(selected.target_name or ''))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_TARGET'
end

function scheduler.p1_try_nonblocking_target_acquire(settings)
	if not bool_setting(settings and settings.scheduler_dark_launch_combat, false) then
		return false, nil
	end
	local ctx = p1_build_ctx(settings)
	scheduler.p1_update_pending_state(ctx)
	local proposals = {}
	p1_collect_target_control(ctx, proposals)
	local selected = proposals[1]
	if type(selected) ~= 'table' then
		return false, nil
	end
	local ok, reject_reason = p1_validate_proposal(ctx, selected)
	if not ok then
		if tostring(reject_reason or '') == 'duplicate_suppressed' then
			scheduler.action_timeline_log('TARGET_SELECT_DEBOUNCED', {
				tid = tonumber(selected.target_id) or 0,
				name = tostring(selected.target_name or ''),
				reason = 'BLOCK_DEBOUNCE',
			}, ('target_debounced:%d'):format(tonumber(selected.target_id) or 0), 0.50)
		else
			scheduler.action_timeline_log('TARGET_SELECT_BLOCKED', {
				tid = tonumber(selected.target_id) or 0,
				name = tostring(selected.target_name or ''),
				reason = tostring(reject_reason or 'BLOCK_UNKNOWN'),
			}, ('target_blocked:%d:%s'):format(tonumber(selected.target_id) or 0, tostring(reject_reason or 'BLOCK_UNKNOWN')), 0.50)
		end
		return false, reject_reason
	end
	local p1_get_locks = scheduler.p1_get_locks
	local p1_hard_lock_reject = scheduler.p1_hard_lock_reject
	local lock_reject = p1_hard_lock_reject(p1_get_locks(ctx), selected)
	if lock_reject ~= '' then
		scheduler.action_timeline_log('TARGET_SELECT_BLOCKED', {
			tid = tonumber(selected.target_id) or 0,
			name = tostring(selected.target_name or ''),
			reason = tostring(lock_reject),
		}, ('target_blocked:%d:%s'):format(tonumber(selected.target_id) or 0, tostring(lock_reject)), 0.50)
		return false, lock_reject
	end
	local plan = p1_build_dispatch_plan(ctx, selected)
	local commit_ok = p1_revalidate_plan_commit(ctx, selected, plan)
	if not commit_ok then
		scheduler.action_timeline_log('TARGET_SELECT_BLOCKED', {
			tid = tonumber(selected.target_id) or 0,
			name = tostring(selected.target_name or ''),
			reason = 'commit_invalidated',
		}, ('target_blocked:%d:commit'):format(tonumber(selected.target_id) or 0), 0.50)
		return false, 'commit_invalidated'
	end
	return scheduler.p1_dispatch_target_control(selected, ctx)
end

function p1_combat_helpers.target_distance_to_id(target_id)
	return require('uc_scheduler_target_utils').p1_target_distance_to_id(scheduler, target_id)
end

function p1_combat_helpers.spell_target_dispatch_ready(selected, expected_tid, tank_enmity)
	if (tank_enmity or (type(selected.detail) == 'table' and selected.detail.allow_target_id_send == true)) and expected_tid > 0 then
		local max_range = math.max(0, p1_number(selected.range_policy and selected.range_policy.max, 0))
		local dist, mob = p1_combat_helpers.target_distance_to_id(expected_tid)
		if not mob or not combat_core.is_live_actionable_combat_target(mob, now_s(), true) then
			return false
		end
		if max_range > 0 and dist and dist > max_range then
			return false
		end
		return true
	end
	local target = windower.ffxi.get_mob_by_target('t')
	if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
		return false
	end
	return true
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
		local intent = {
			kind = 'turn',
			source = 'unified_scheduler:T2.3c_darklaunch',
			heading = heading,
			meta = {
				target_id = tid,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
		local turn_ownership_status = require('uc_scheduler_turn_ownership').apply_turn_ownership({
			dispatcher = dispatcher,
			direct_turn = windower.ffxi.turn,
			turn = windower.ffxi.turn,
			ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP == true),
			promoted_default_on = true,
			ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TURN_OWNERSHIP == false),
			promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
			intent = intent,
		})
		_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			heading = tonumber(intent.heading) or 0,
			ownership_enabled = turn_ownership_status.ownership_enabled,
			dispatched = turn_ownership_status.dispatched,
			dispatch_ok = turn_ownership_status.dispatch_ok,
			dispatch_reason = turn_ownership_status.dispatch_reason,
			fallback_used = turn_ownership_status.fallback_used,
		}
	end
end

local function p1_move_toward_mob(mob)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or not mob or me.x == nil or me.y == nil or mob.x == nil or mob.y == nil then
		return false
	end
	local heading = math.atan2(mob.y - me.y, mob.x - me.x)
	local intent = {
		kind = 'run',
		source = 'unified_scheduler:T2.3_darklaunch',
		run_x = math.cos(heading),
		run_y = math.sin(heading),
		meta = {
			target_id = tonumber(mob.id) or 0,
			heading = heading,
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
	local direct_run = windower.ffxi.run
	local dispatcher_run = function(run_x, run_y)
		if run_x == nil or run_y == nil then
			return direct_run(heading)
		end
		return direct_run(heading)
	end
	local run_ownership_status = require('uc_scheduler_run_ownership').apply_run_ownership({
		dispatcher = dispatcher,
		direct_run = direct_run,
		run = dispatcher_run,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP == true),
		intent = intent,
		heading = heading,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_RUN_VALIDATE = {
		ok = _darklaunch_ok and true or false,
		reason = _darklaunch_reason,
		kind = intent.kind,
		source = intent.source,
		run_x = run_ownership_status.run_x,
		run_y = run_ownership_status.run_y,
		heading = run_ownership_status.heading,
		ownership_enabled = run_ownership_status.ownership_enabled,
		dispatched = run_ownership_status.dispatched,
		dispatch_ok = run_ownership_status.dispatch_ok,
		dispatch_reason = run_ownership_status.dispatch_reason,
		fallback_used = run_ownership_status.fallback_used,
	}
	return true
end

local function p1_dispatch_combat_engage(selected, settings, phase, expected_tid)
	local target = windower.ffxi.get_mob_by_target('t')
	if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
		local ok_set = p1_try_target_prep(expected_tid)
		if not ok_set then
			log_combat_sched(('engage_drop reason=TARGET_PREP_FAIL expected_tid=%d'):format(expected_tid))
			if bool_setting(settings and settings.debug, false) then
				_G.UC_LAST_SCHED_ACTION = ('[p1]engage:dispatch_fail:settarget tid=%d'):format(expected_tid)
			end
			scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
				tid = expected_tid,
				name = tostring(selected.target_name or ''),
				reason = 'BLOCK_INVALID_TARGET',
			}, ('engage_dispatch_blocked:%d:settarget'):format(expected_tid), 0.50)
			return false, nil
		end
		target = windower.ffxi.get_mob_by_target('t')
	end
	if not combat_core.is_live_actionable_combat_target(target, now_s(), true) then
		log_combat_sched(('engage_drop reason=TARGET_NOT_ACTIONABLE expected_tid=%d'):format(expected_tid))
		if bool_setting(settings and settings.debug, false) then
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:dispatch_fail:not_actionable tid=%d'):format(expected_tid)
		end
		scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
			tid = expected_tid,
			name = tostring(selected.target_name or ''),
			reason = 'BLOCK_INVALID_TARGET',
		}, ('engage_dispatch_blocked:%d:not_actionable'):format(expected_tid), 0.50)
		return false, nil
	end
	local player = windower.ffxi.get_player()
	local player_status = tonumber(player and player.status) or 0
	local player_hp = tonumber(player and player.vitals and player.vitals.hp) or 0
	local player_hpp = tonumber(player and player.vitals and player.vitals.hpp) or 0
	local player_dead = (player_status == 3) or player_hp <= 0 or player_hpp <= 0
	if player_dead then
		log_combat_sched(('engage_drop reason=PLAYER_DEAD expected_tid=%d'):format(expected_tid))
		_G.UC_LAST_SCHED_ACTION = ('[p1]engage:blocked:dead tid=%d'):format(expected_tid)
		scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
			tid = expected_tid,
			name = tostring(selected.target_name or ''),
			reason = 'BLOCK_PLAYER_DEAD',
			status = player_status,
		}, ('engage_dispatch_blocked:%d:dead'):format(expected_tid), 0.50)
		return true, 'BLOCK_PLAYER_DEAD'
	end
	if player_status == 1 then
		local cur = windower.ffxi.get_mob_by_target('t')
		if cur and tonumber(cur.id) == expected_tid then
			log_combat_sched(('engage_drop reason=ALREADY_ENGAGED expected_tid=%d'):format(expected_tid))
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:already:%s'):format(tostring(selected.target_name or ''))
			scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
				tid = expected_tid,
				name = tostring(selected.target_name or ''),
				reason = 'BLOCK_ALREADY_ENGAGED',
				status = player_status,
			}, ('engage_dispatch_blocked:%d:already'):format(expected_tid), 0.50)
			return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_ENGAGED'
		end
	end
	_G.UC_ACTION_TIMELINE_CURRENT_ACTION = 'engage'
	scheduler.p1_maybe_release_stale_spell_lock_for_target_transition(selected, now_s())
	local pending = scheduler.p1_pending_engage_state(phase)
	local retry_ready_at = tonumber(pending and pending.retry_ready_at) or 0
	local retry_in_s = math.max(0, retry_ready_at - now_s())
	local blocked, block_reason = engage_attack_on_action_state_gate({
		explicit_attack_on = true,
		player_status = player_status,
		player_dead = player_dead,
		target_selected = true,
		target_valid = true,
		target_id = expected_tid,
		target_name = tostring(selected.target_name or ''),
		dispatch_method = scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON,
		retry_in_s = ('%.2f'):format(retry_in_s),
		retry_count = tonumber(pending and pending.retry_count) or 0,
	})
	_G.UC_ACTION_TIMELINE_CURRENT_ACTION = nil
	if blocked then
		log_combat_sched(('dispatch_block reason=%s type=%s name=\"%s\" tid=%d'):format(
			tostring(block_reason or 'BLOCKED'),
			tostring(selected.action_type or ''),
			tostring(selected.action_name or ''),
			tonumber(selected.target_id) or 0
		))
		scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
			tid = tonumber(selected.target_id) or 0,
			name = tostring(selected.target_name or ''),
			reason = tostring(block_reason or 'BLOCK_ACTION_STATE'),
		}, ('engage_blocked:%s'):format(tostring(block_reason or 'BLOCK_ACTION_STATE')), 0.50)
		return true, block_reason
	end
	scheduler.action_timeline_log('ENGAGE_DISPATCH_ATTEMPT', {
		tid = expected_tid,
		name = tostring(selected.target_name or ''),
		command = 'attack_on',
	}, ('engage_attempt:%d'):format(expected_tid), 0.05)
	if not uc_attack or type(uc_attack.engage_target) ~= 'function' then
		log_combat_sched('engage_drop reason=NO_UC_ATTACK')
		if bool_setting(settings and settings.debug, false) then
			_G.UC_LAST_SCHED_ACTION = '[p1]engage:dispatch_fail:no_uc_attack'
		end
		scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
			tid = expected_tid,
			name = tostring(selected.target_name or ''),
			reason = 'BLOCK_UNKNOWN',
		}, ('engage_dispatch_blocked:%d:no_attack'):format(expected_tid), 0.50)
		return false, nil
	end
	local ok_attack, engage_reason = uc_attack.engage_target(expected_tid)
	if not ok_attack then
		if scheduler.p1_pending_engage_live(phase, now_s()) then
			scheduler.p1_clear_pending_engage(phase)
		end
		scheduler.p1_clear_engage_duplicate_state(phase, '', now_s())
		log_combat_sched(('engage_send_fail tid=%d reason=%s'):format(expected_tid, tostring(engage_reason or 'ENGAGE_FAIL')))
		if bool_setting(settings and settings.debug, false) then
			_G.UC_LAST_SCHED_ACTION = ('[p1]engage:dispatch_fail:%s'):format(tostring(engage_reason or 'ENGAGE_FAIL'))
		end
		scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
			tid = expected_tid,
			name = tostring(selected.target_name or ''),
			reason = tostring(engage_reason or 'BLOCK_UNKNOWN'),
		}, ('engage_dispatch_blocked:%d:send'):format(expected_tid), 0.50)
		return false, nil
	end
	scheduler.p1_note_pending_engage_attempt(phase, expected_tid, tostring(selected.target_name or ''), now_s())
	scheduler.p1_note_engage_duplicate_attempt(
		phase,
		expected_tid,
		tostring(selected.target_name or ''),
		now_s(),
		tonumber((windower.ffxi.get_player() or {}).status) or 0,
		scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON
	)
	require('uc_scheduler_action_state').action_mark_engage_sent(scheduler, now_s)
	log_combat_sched(('engage_send_ok tid=%d target=\"%s\"'):format(expected_tid, tostring(selected.target_name or '')))
	_G.UC_LAST_SCHED_ACTION = ('[p1]engage:sent:%s'):format(tostring(selected.target_name or ''))
	scheduler.action_timeline_log('ENGAGE_DISPATCHED', {
		tid = expected_tid,
		name = tostring(selected.target_name or ''),
		command = 'attack_on',
	}, ('engage_dispatched:%d'):format(expected_tid), 0.05)
	return true, nil
end

local function p1_dispatch_pull_control(selected, settings)
	if not bool_setting(settings and settings.scheduler_dark_launch_combat, false) then
		return false, nil
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
	end
	if not combat_core or type(combat_core.dispatch_pull_for_scheduler) ~= 'function' then
		return false, nil
	end
	local target_id = tonumber(selected.target_id) or 0
	if target_id <= 0 then
		return false, nil
	end
	local ok, reason = combat_core.dispatch_pull_for_scheduler(settings, target_id)
	if not ok then
		return false, nil
	end
	local sent = tostring(reason or '') == 'PULL_ACTION_SENT'
	local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
	if sent then
		action_mark_sent('pull')
		scheduler.p1_record_legacy_dispatch(ctx)
		scheduler.p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	else
		p1_pending_mark_complete(ctx.now, ('pull_no_send:%s'):format(tostring(reason or 'BLOCK')))
		scheduler.p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	end
	_G.UC_LAST_SCHED_ACTION = ('[p1]pull:%s->%s:%s'):format(
		tostring(selected.action_name or ''),
		tostring(selected.target_name or ''),
		tostring(reason or '')
	)
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_PULL'
end

local function p1_dispatch_maintenance_cor(selected, settings, provider)
	if not bool_setting(settings and settings.scheduler_dark_launch_maintenance, false) then
		log_def_sched('MAINT_COR_DISPATCH_SKIP reason=TOGGLE_OFF')
		return false, nil
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		log_def_sched(('MAINT_COR_DISPATCH_BLOCK reason=%s'):format(tostring(block_reason or 'BLOCKED')))
		return true, block_reason
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
	local maintenance_cor_command = ('input /ja \"%s\" <me>'):format(ability)
	local intent = {
		kind = 'send_command',
		source = 'unified_scheduler:T2.3j_darklaunch',
		command = maintenance_cor_command,
		meta = {
			action_type = tostring(action_kind or 'ja'),
			action_name = ability,
			provider = tostring(provider or ''),
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
	local maintenance_command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		direct_send_command = windower.send_command,
		send_command = windower.send_command,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == true),
		promoted_default_on = true,
		ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == false),
		promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
		intent = intent,
		command = maintenance_cor_command,
	})
	scheduler.action_timeline_log('MAINT_BUFF_DISPATCHED', {
		action = tostring(ability or ''),
		provider = tostring(provider or ''),
		band = tonumber(selected.priority_band) or 0,
	}, ('maint_dispatch:%s'):format(tostring(ability or '')), 0.05)
	_G.UC_SCHED_P1_DARKLAUNCH_MAINTENANCE_COR_COMMAND_VALIDATE = {
		ok = _darklaunch_ok and true or false,
		reason = _darklaunch_reason,
		kind = intent.kind,
		source = intent.source,
		ownership_enabled = maintenance_command_ownership_status.ownership_enabled,
		dispatched = maintenance_command_ownership_status.dispatched,
		dispatch_ok = maintenance_command_ownership_status.dispatch_ok,
		dispatch_reason = maintenance_command_ownership_status.dispatch_reason,
		fallback_used = maintenance_command_ownership_status.fallback_used,
		command_present = maintenance_command_ownership_status.command_present,
	}
	log_def_sched(('MAINT_COR_DISPATCH_SEND action=\"%s\"'):format(tostring(ability)))
	action_mark_sent(action_kind or 'ja')
	local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.p1_record_legacy_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]cor:%s'):format(ability)
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_MAINT_COR'
end

local function p1_dispatch_defensive_internal(selected, settings)
	if not bool_setting(settings and settings.scheduler_dark_launch_defensive, false) then
		return false, nil
	end
	_G.UC_DEFENSIVE_CHAIN_ACTION = {
		provider = 'defensive_internal',
		action_kind = tostring(selected.action_type or ''),
		def_action_type = tostring(type(selected.detail) == 'table' and selected.detail.def_action_type or ''),
		action_name = tostring(selected.action_name or ''),
	}
	local blocked, block_reason = action_dispatch_blocked()
	_G.UC_DEFENSIVE_CHAIN_ACTION = nil
	if blocked then
		return true, block_reason
	end
	local cmd = tostring(selected.legacy_command or '')
	if cmd == '' then
		return false, nil
	end
	local ok_ready, _, action_kind = action_ready(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0)
	if action_kind == 'none' or not ok_ready then
		return false, nil
	end
	local player = windower.ffxi.get_player()
	local out_of_combat = (tonumber(player and player.status) or 0) ~= 1
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
	local intent = {
		kind = 'send_command',
		source = 'unified_scheduler:T2.3i_darklaunch',
		command = cmd,
		meta = {
			action_type = tostring(action_kind or selected.action_type or ''),
			action_name = tostring(selected.action_name or ''),
			target_id = tonumber(selected.target_id) or 0,
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
	local defensive_command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		direct_send_command = windower.send_command,
		send_command = windower.send_command,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == true),
		promoted_default_on = true,
		ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == false),
		promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
		intent = intent,
		command = cmd,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE = {
		ok = _darklaunch_ok and true or false,
		reason = _darklaunch_reason,
		kind = intent.kind,
		source = intent.source,
		command_present = defensive_command_ownership_status.command_present,
		ownership_enabled = defensive_command_ownership_status.ownership_enabled,
		dispatched = defensive_command_ownership_status.dispatched,
		dispatch_ok = defensive_command_ownership_status.dispatch_ok,
		dispatch_reason = defensive_command_ownership_status.dispatch_reason,
		fallback_used = defensive_command_ownership_status.fallback_used,
	}
	local detail = selected.detail
	local target_hpp = tonumber(type(detail) == 'table' and detail.target_hpp or -1) or -1
	scheduler.p1_maybe_clear_pending_engage_for_selected_critical(settings, selected)
	local can_apply_defensive_spell_lock = (
		action_kind == 'spell'
		and cmd ~= ''
		and (tostring(type(detail) == 'table' and detail.def_action_type or '') ~= 'cure' or target_hpp > 0)
	)
	if can_apply_defensive_spell_lock then
		scheduler.apply_defensive_spell_movement_lock(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0, now_gate)
		scheduler.begin_defensive_spell_wait(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0, now_gate)
	end
	action_mark_sent(action_kind or selected.action_type or 'defensive_internal', {
		action_name = tostring(selected.action_name or ''),
		provider = 'defensive_internal',
		def_action_type = tostring(type(selected.detail) == 'table' and selected.detail.def_action_type or ''),
		target_id = tonumber(selected.target_id) or 0,
		target_name = tostring(selected.target_name or ''),
		target_kind = tostring(selected.target_kind or ''),
	})
	if action_kind == 'spell' then
		local is_cure = tostring(type(detail) == 'table' and detail.def_action_type or '') == 'cure'
		local critical_hpp = tonumber(settings and settings.defensive_critical_hpp) or 35
		local event_code = 'MAINT_BUFF_DISPATCHED'
		if is_cure then
			event_code = (target_hpp > 0 and target_hpp <= critical_hpp) and 'CRITICAL_CURE_DISPATCHED' or 'NONCRITICAL_CURE_DISPATCHED'
		end
		scheduler.action_timeline_log(event_code, {
			spell = tostring(selected.action_name or ''),
			target = tostring(selected.target_name or ''),
			target_id = tonumber(selected.target_id) or 0,
			critical = tostring(event_code == 'CRITICAL_CURE_DISPATCHED'),
			band = tonumber(selected.priority_band) or 0,
		}, ('def_dispatch:%s:%d'):format(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0), 0.05)
		scheduler.action_timeline_log('SPELL_SENT', {
			spell = tostring(selected.action_name or ''),
			provider = 'defensive_internal',
			target = tostring(selected.target_name or ''),
			target_id = tonumber(selected.target_id) or 0,
			kind = 'spell',
			cast_type = tostring(type(detail) == 'table' and detail.def_action_type or ''),
			action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
		}, ('spell_sent:def:%s:%d'):format(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0), 0.05)
		scheduler.action_timeline_note_spell_sent({
			provider = 'defensive_internal',
			spell = tostring(selected.action_name or ''),
			action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
		})
	end
	local dispatch_now = now_s()
	local dispel_detail = selected.detail
	if type(dispel_detail) == 'table' and tostring(dispel_detail.enemy_dispel_attempt_key or '') ~= '' then
		mark_enemy_dispel_attempt(tostring(dispel_detail.enemy_dispel_attempt_key), dispatch_now)
	end
	local ctx = { now = dispatch_now, tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.p1_record_legacy_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]%s->%s'):format(tostring(selected.action_name or ''), tostring(selected.target_name or ''))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH'
end

local function p1_dispatch_defensive_healbot(selected, settings)
	if not bool_setting(settings and settings.scheduler_dark_launch_defensive, false) then
		return false, nil
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
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
	action_mark_sent('defensive_healbot', {
		action_name = tostring(selected.action_name or ''),
		provider = 'defensive_healbot',
		def_action_type = tostring(type(selected.detail) == 'table' and selected.detail.def_action_type or ''),
		target_id = tonumber(selected.target_id) or 0,
		target_kind = tostring(selected.target_kind or ''),
	})
	local hb_detail = type(selected.detail) == 'table' and selected.detail or {}
	scheduler.p1_maybe_clear_pending_engage_for_selected_critical(settings, selected)
	local hb_target_hpp = tonumber(hb_detail.target_hpp or -1) or -1
	local hb_critical_hpp = tonumber(settings and settings.defensive_critical_hpp) or 35
	local hb_event_code = 'MAINT_BUFF_DISPATCHED'
	if tostring(hb_detail.def_action_type or '') == 'cure' then
		hb_event_code = (hb_target_hpp > 0 and hb_target_hpp <= hb_critical_hpp) and 'CRITICAL_CURE_DISPATCHED' or 'NONCRITICAL_CURE_DISPATCHED'
	end
	scheduler.action_timeline_log(hb_event_code, {
		spell = tostring(selected.action_name or ''),
		target = tostring(selected.target_name or ''),
		target_id = tonumber(selected.target_id) or 0,
		critical = tostring(hb_event_code == 'CRITICAL_CURE_DISPATCHED'),
		band = tonumber(selected.priority_band) or 0,
	}, ('hb_dispatch:%s:%d'):format(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0), 0.05)
	local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.p1_record_legacy_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]hb:%s->%s'):format(tostring(selected.action_name or ''), tostring(selected.target_name or ''))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_HEALBOT'
end

local function p1_try_dark_launch_combat_dispatch(selected, settings, phase)
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
	local action_type = tostring(selected.action_type or '')
	local tank_enmity = p1_is_tank_enmity_selected(selected)
	local expected_tid = tonumber(selected.target_id) or 0
	local target_kind = tostring(selected.target_kind or 'self')
	if action_type ~= 'engage' then
		_G.UC_ACTION_TIMELINE_CURRENT_ACTION = nil
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
	end
	if tank_enmity and target_kind == 'mob' and expected_tid > 0 then
		local max_range = math.max(0, p1_number(selected.range_policy and selected.range_policy.max, 0))
		local dist, mob = p1_combat_helpers.target_distance_to_id(expected_tid)
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
		local intent = {
			kind = 'run_stop',
			source = 'unified_scheduler:T2.4f_darklaunch',
			meta = {
				reason = 'TANK_ACTION_SETTLE',
				action_type = action_type,
				action_name = selected.action_name,
				target_id = expected_tid,
				target_kind = target_kind,
				settle_key = settle_key,
				tank_action_settle_until = phase.tank_action_settle_until,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
		local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
			dispatcher = dispatcher,
			direct_run = windower.ffxi.run,
			run = windower.ffxi.run,
			ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP == true),
			promoted_default_on = true,
			ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP == false),
			promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
			intent = intent,
		})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE = {
			ok = _darklaunch_ok and true or false,
			reason = _darklaunch_reason,
			kind = intent.kind,
			source = intent.source,
			ownership_enabled = run_stop_ownership_status.ownership_enabled,
			dispatched = run_stop_ownership_status.dispatched,
			dispatch_ok = run_stop_ownership_status.dispatch_ok,
			dispatch_reason = run_stop_ownership_status.dispatch_reason,
			fallback_used = run_stop_ownership_status.fallback_used,
			stop = run_stop_ownership_status.stop,
		}
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
		return p1_dispatch_combat_engage(selected, settings, phase, expected_tid)
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
		if not target or (tonumber(target.id) or 0) ~= expected_tid then
			return false, nil
		end
		if not combat_core.is_live_actionable_combat_target(target, now_s(), true) then
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
			local ws_command = ('input /ws \"%s\" <t>'):format(ws)
			local intent = {
				kind = 'send_command',
				source = 'unified_scheduler:T2.3d_darklaunch',
				command = ws_command,
				meta = {
					action_type = tostring(action_type or ''),
					action_name = ws,
					target_id = expected_tid,
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				direct_send_command = windower.send_command,
				send_command = windower.send_command,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_WS_COMMAND_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
				command = ws_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_COMBAT_COMMAND_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				command_present = command_ownership_status.command_present,
				ownership_enabled = command_ownership_status.ownership_enabled,
				dispatched = command_ownership_status.dispatched,
				dispatch_ok = command_ownership_status.dispatch_ok,
				dispatch_reason = command_ownership_status.dispatch_reason,
				fallback_used = command_ownership_status.fallback_used,
			}
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
			local ja_target_command = ('input /ja \"%s\" %d'):format(ability, expected_tid)
			local intent = {
				kind = 'send_command',
				source = 'unified_scheduler:T2.3e_darklaunch',
				command = ja_target_command,
				meta = {
					action_type = tostring(action_type or ''),
					action_name = ability,
					target_id = expected_tid,
					target_kind = tostring(target_kind or ''),
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				direct_send_command = windower.send_command,
				send_command = windower.send_command,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
				command = ja_target_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				command_present = command_ownership_status.command_present,
				ownership_enabled = command_ownership_status.ownership_enabled,
				dispatched = command_ownership_status.dispatched,
				dispatch_ok = command_ownership_status.dispatch_ok,
				dispatch_reason = command_ownership_status.dispatch_reason,
				fallback_used = command_ownership_status.fallback_used,
			}
			action_mark_sent('ja')
			if tank_enmity then
				tank_enmity_diag('TANK_ENMITY_SEND_JA', selected, 'mode=target_id')
			end
			log_ja_sched(('dispatch_send name=\"%s\" mode=target tid=%d'):format(tostring(ability), tonumber(expected_tid) or 0))
		else
			if tank_enmity then
				local stop_intent = {
					kind = 'run_stop',
					source = 'unified_scheduler:T2.4k_darklaunch',
					meta = {
						reason = 'TANK_ENMITY_JA_SELF_SEND',
						action_type = action_type,
						action_name = ability,
						target_kind = target_kind,
						tank_enmity = true,
					},
				}
				local dispatcher = require('uc_scheduler_dispatcher')
				local _stop_darklaunch_ok, _stop_darklaunch_reason = dispatcher.validate_intent(stop_intent)
				local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
					dispatcher = dispatcher,
					direct_run = windower.ffxi.run,
					run = windower.ffxi.run,
					ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP == true),
					promoted_default_on = true,
					ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_JA_SELF_RUN_STOP_OWNERSHIP == false),
					promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
					intent = stop_intent,
				})
				_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE = {
					ok = _stop_darklaunch_ok and true or false,
					reason = _stop_darklaunch_reason,
					kind = stop_intent.kind,
					source = stop_intent.source,
					ownership_enabled = run_stop_ownership_status.ownership_enabled,
					dispatched = run_stop_ownership_status.dispatched,
					dispatch_ok = run_stop_ownership_status.dispatch_ok,
					dispatch_reason = run_stop_ownership_status.dispatch_reason,
					fallback_used = run_stop_ownership_status.fallback_used,
					stop = run_stop_ownership_status.stop,
				}
			end
			local ja_self_command = ('input /ja \"%s\" <me>'):format(ability)
			local intent = {
				kind = 'send_command',
				source = 'unified_scheduler:T2.3f_darklaunch',
				command = ja_self_command,
				meta = {
					action_type = tostring(action_type or ''),
					action_name = ability,
					target_kind = tostring(target_kind or ''),
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				direct_send_command = windower.send_command,
				send_command = windower.send_command,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_JA_COMMAND_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
				command = ja_self_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				command_present = command_ownership_status.command_present,
				ownership_enabled = command_ownership_status.ownership_enabled,
				dispatched = command_ownership_status.dispatched,
				dispatch_ok = command_ownership_status.dispatch_ok,
				dispatch_reason = command_ownership_status.dispatch_reason,
				fallback_used = command_ownership_status.fallback_used,
			}
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
			local intent = {
				kind = 'run_stop',
				source = 'unified_scheduler:T2.4l_darklaunch',
				meta = {
					reason = 'COMBAT_SPELL_SETTLE',
					action_type = action_type,
					action_name = spell,
					target_id = selected.target_id,
					target_kind = target_kind,
					prep_key = prep_key,
					freeze_prep_until = _G.UC_MOVE_FREEZE_PREP_UNTIL,
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				direct_run = windower.ffxi.run,
				run = windower.ffxi.run,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_SETTLE_RUN_STOP_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_SETTLE_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				ownership_enabled = run_stop_ownership_status.ownership_enabled,
				dispatched = run_stop_ownership_status.dispatched,
				dispatch_ok = run_stop_ownership_status.dispatch_ok,
				dispatch_reason = run_stop_ownership_status.dispatch_reason,
				fallback_used = run_stop_ownership_status.fallback_used,
				stop = run_stop_ownership_status.stop,
			}
			_G.UC_LAST_SCHED_ACTION = ('[p1]spell_settle:%s->%s'):format(spell, tostring(selected.target_name or ''))
			return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_SPELL_SETTLE'
		end
		if prep_now < prep_until then
			local intent = {
				kind = 'run_stop',
				source = 'unified_scheduler:T2.4m_darklaunch',
				meta = {
					reason = 'COMBAT_SPELL_PREP_WAIT',
					action_type = action_type,
					action_name = spell,
					target_id = selected.target_id,
					target_kind = target_kind,
					prep_key = prep_key,
					freeze_prep_until = prep_until,
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				direct_run = windower.ffxi.run,
				run = windower.ffxi.run,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_PREP_WAIT_RUN_STOP_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_COMBAT_SPELL_PREP_WAIT_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				ownership_enabled = run_stop_ownership_status.ownership_enabled,
				dispatched = run_stop_ownership_status.dispatched,
				dispatch_ok = run_stop_ownership_status.dispatch_ok,
				dispatch_reason = run_stop_ownership_status.dispatch_reason,
				fallback_used = run_stop_ownership_status.fallback_used,
				stop = run_stop_ownership_status.stop,
			}
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
			local intent = {
				kind = 'run_stop',
				source = 'unified_scheduler:T2.4g_darklaunch',
				meta = {
					reason = 'TANK_SPELL_SETTLE',
					action_type = action_type,
					action_name = spell,
					target_id = expected_tid,
					target_kind = target_kind,
					settle_key = settle_key,
					tank_spell_settle_until = phase.tank_spell_settle_until,
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				direct_run = windower.ffxi.run,
				run = windower.ffxi.run,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				ownership_enabled = run_stop_ownership_status.ownership_enabled,
				dispatched = run_stop_ownership_status.dispatched,
				dispatch_ok = run_stop_ownership_status.dispatch_ok,
				dispatch_reason = run_stop_ownership_status.dispatch_reason,
				fallback_used = run_stop_ownership_status.fallback_used,
				stop = run_stop_ownership_status.stop,
			}
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
			if not p1_combat_helpers.spell_target_dispatch_ready(selected, expected_tid, tank_enmity) then
				return false, nil
			end
			if tank_enmity then
				local intent = {
					kind = 'run_stop',
					source = 'unified_scheduler:T2.4h_darklaunch',
					meta = {
						reason = 'TANK_ENMITY_SPELL_TARGET_SEND',
						action_type = action_type,
						action_name = spell,
						target_id = expected_tid,
						target_kind = target_kind,
					},
				}
				local dispatcher = require('uc_scheduler_dispatcher')
				local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
				local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
					dispatcher = dispatcher,
					direct_run = windower.ffxi.run,
					run = windower.ffxi.run,
					ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP == true),
					ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP == false),
					promoted_default_on = true,
					promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
					intent = intent,
				})
				_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE = {
					ok = _darklaunch_ok and true or false,
					reason = _darklaunch_reason,
					kind = intent.kind,
					source = intent.source,
					ownership_enabled = run_stop_ownership_status.ownership_enabled,
					dispatched = run_stop_ownership_status.dispatched,
					dispatch_ok = run_stop_ownership_status.dispatch_ok,
					dispatch_reason = run_stop_ownership_status.dispatch_reason,
					fallback_used = run_stop_ownership_status.fallback_used,
					stop = run_stop_ownership_status.stop,
				}
			end
			local spell_target_command = ('input /ma \"%s\" %d'):format(spell, expected_tid)
			local intent = {
				kind = 'send_command',
				source = 'unified_scheduler:T2.3g_darklaunch',
				command = spell_target_command,
				meta = {
					action_type = tostring(action_type or ''),
					action_name = spell,
					target_id = expected_tid,
					target_kind = tostring(target_kind or ''),
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				direct_send_command = windower.send_command,
				send_command = windower.send_command,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
				command = spell_target_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_SPELL_TARGET_COMMAND_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				command_present = command_ownership_status.command_present,
				ownership_enabled = command_ownership_status.ownership_enabled,
				dispatched = command_ownership_status.dispatched,
				dispatch_ok = command_ownership_status.dispatch_ok,
				dispatch_reason = command_ownership_status.dispatch_reason,
				fallback_used = command_ownership_status.fallback_used,
			}
			action_mark_sent('spell', {
				action_name = spell,
				provider = 'combat',
				target_id = expected_tid,
				target_name = tostring(selected.target_name or ''),
				target_kind = tostring(target_kind or ''),
			})
			scheduler.action_timeline_log('SPELL_SENT', {
				spell = tostring(spell or ''),
				provider = 'combat',
				tid = expected_tid,
				name = tostring(selected.target_name or ''),
				kind = 'spell',
				target = tostring(selected.target_name or ''),
				target_id = expected_tid,
				cast_type = tostring(action_type or ''),
				action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
			}, ('spell_sent:%s:%d'):format(tostring(spell or ''), expected_tid), 0.05)
			scheduler.action_timeline_note_spell_sent({
				provider = 'combat',
				spell = tostring(spell or ''),
				action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
			})
			if scheduler.is_sleep_spell_name(settings, spell) then
				scheduler.action_timeline_log('SLEEP_DISPATCHED', {
					spell = tostring(spell or ''),
					tid = expected_tid,
					name = tostring(selected.target_name or ''),
				}, ('sleep_dispatched:%d:%s'):format(expected_tid, tostring(spell or '')), 0.05)
			end
			if tank_enmity then
				scheduler.p1_begin_tank_spell_wait(phase, spell, expected_tid, now_s())
				tank_enmity_diag('TANK_ENMITY_SEND_SPELL', selected, 'mode=target_id')
			end
		else
			if tank_enmity then
				local intent = {
					kind = 'run_stop',
					source = 'unified_scheduler:T2.4i_darklaunch',
					meta = {
						reason = 'TANK_ENMITY_SPELL_SELF_SEND',
						action_type = action_type,
						action_name = spell,
						target_kind = target_kind,
					},
				}
				local dispatcher = require('uc_scheduler_dispatcher')
				local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
				local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
					dispatcher = dispatcher,
					direct_run = windower.ffxi.run,
					run = windower.ffxi.run,
					ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP == true),
					ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP == false),
					promoted_default_on = true,
					promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
					intent = intent,
				})
				_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE = {
					ok = _darklaunch_ok and true or false,
					reason = _darklaunch_reason,
					kind = intent.kind,
					source = intent.source,
					ownership_enabled = run_stop_ownership_status.ownership_enabled,
					dispatched = run_stop_ownership_status.dispatched,
					dispatch_ok = run_stop_ownership_status.dispatch_ok,
					dispatch_reason = run_stop_ownership_status.dispatch_reason,
					fallback_used = run_stop_ownership_status.fallback_used,
					stop = run_stop_ownership_status.stop,
				}
			end
			local spell_self_command = ('input /ma \"%s\" <me>'):format(spell)
			local intent = {
				kind = 'send_command',
				source = 'unified_scheduler:T2.3h_darklaunch',
				command = spell_self_command,
				meta = {
					action_type = tostring(action_type or ''),
					action_name = spell,
					target_kind = tostring(target_kind or ''),
				},
			}
			local dispatcher = require('uc_scheduler_dispatcher')
			local _darklaunch_ok, _darklaunch_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				direct_send_command = windower.send_command,
				send_command = windower.send_command,
				ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == true),
				promoted_default_on = true,
				ownership_disabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_COMBAT_SPELL_COMMAND_OWNERSHIP == false),
				promoted_kill_switch = promoted_ownership_kill_switch_enabled(),
				intent = intent,
				command = spell_self_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE = {
				ok = _darklaunch_ok and true or false,
				reason = _darklaunch_reason,
				kind = intent.kind,
				source = intent.source,
				command_present = command_ownership_status.command_present,
				ownership_enabled = command_ownership_status.ownership_enabled,
				dispatched = command_ownership_status.dispatched,
				dispatch_ok = command_ownership_status.dispatch_ok,
				dispatch_reason = command_ownership_status.dispatch_reason,
				fallback_used = command_ownership_status.fallback_used,
			}
			action_mark_sent('spell', {
				action_name = spell,
				provider = 'combat',
				target_id = tonumber((windower.ffxi.get_player() or {}).id) or 0,
				target_name = tostring(selected.target_name or ''),
				target_kind = tostring(target_kind or ''),
			})
			scheduler.action_timeline_log('SPELL_SENT', {
				spell = tostring(spell or ''),
				provider = 'combat',
				kind = 'spell',
				target = tostring(selected.target_name or ''),
				target_id = tonumber((windower.ffxi.get_player() or {}).id) or 0,
				cast_type = tostring(action_type or ''),
				action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
			}, ('spell_sent:%s:self'):format(tostring(spell or '')), 0.05)
			scheduler.action_timeline_note_spell_sent({
				provider = 'combat',
				spell = tostring(spell or ''),
				action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
			})
			if tank_enmity then
				scheduler.p1_begin_tank_spell_wait(phase, spell, 0, now_s())
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
	scheduler.p1_record_legacy_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT'
end

local function p1_static_command_ownership_shape_defensive()
	local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		direct_send_command = windower.send_command,
		send_command = windower.send_command,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_DEFENSIVE_INTERNAL_COMMAND_OWNERSHIP == true),
		intent = intent,
		command = cmd,
	})
	return {
		ownership_enabled = command_ownership_status.ownership_enabled,
		dispatched = command_ownership_status.dispatched,
		dispatch_ok = command_ownership_status.dispatch_ok,
		dispatch_reason = command_ownership_status.dispatch_reason,
		command_present = command_ownership_status.command_present,
		fallback_used = command_ownership_status.fallback_used,
	}
end

local function p1_static_command_ownership_shape_maintenance()
	local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		direct_send_command = windower.send_command,
		send_command = windower.send_command,
		ownership_enabled = (_G.UC_SCHED_P1_ENABLE_DISPATCHER_MAINTENANCE_COR_COMMAND_OWNERSHIP == true),
		intent = intent,
		command = maintenance_cor_command,
	})
	return {
		ownership_enabled = command_ownership_status.ownership_enabled,
		dispatched = command_ownership_status.dispatched,
		dispatch_ok = command_ownership_status.dispatch_ok,
		dispatch_reason = command_ownership_status.dispatch_reason,
		fallback_used = command_ownership_status.fallback_used,
		command_present = command_ownership_status.command_present,
	}
end

local function p1_try_dark_launch_dispatch(settings)
	local phase = scheduler.phase1
	local selected = phase.last_selected
	if type(selected) ~= 'table' or type(phase.last_plan) ~= 'table' then
		return false, nil
	end
	local tank_spell_wait_locked = scheduler.p1_refresh_tank_spell_wait_lock(phase, now_s())
	if tank_spell_wait_locked then
		_G.UC_LAST_SCHED_ACTION = ('[p1]tank_spell_wait:%s'):format(tostring(phase.tank_pending_action or ''))
		return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_TANK_SPELL_WAIT'
	end
	local provider = tostring(selected.provider or '')
	if provider == 'target_control' then
		if not bool_setting(settings and settings.scheduler_dark_launch_combat, false) then
			return false, nil
		end
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		return scheduler.p1_dispatch_target_control(selected, ctx)
	end

	if provider == 'pull_control' then
		return p1_dispatch_pull_control(selected, settings)
	end
	if provider == 'combat' then
		return p1_try_dark_launch_combat_dispatch(selected, settings, phase)
	end
	if provider == 'defensive_internal' then
		_G.UC_DEFENSIVE_CHAIN_ACTION = {
			provider = 'defensive_internal',
			action_kind = tostring(selected.action_type or ''),
			def_action_type = tostring(type(selected.detail) == 'table' and selected.detail.def_action_type or ''),
			action_name = tostring(selected.action_name or ''),
		}
		local blocked, b_reason = action_dispatch_blocked()
		_G.UC_DEFENSIVE_CHAIN_ACTION = nil
		if blocked then
			return true, b_reason
		end
		return p1_dispatch_defensive_internal(selected, settings)
	end
	if provider == 'defensive_healbot' then
		return p1_dispatch_defensive_healbot(selected, settings)
	end
	if provider == 'maintenance_cor' then
		return p1_dispatch_maintenance_cor(selected, settings, provider)
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
		scheduler.p1_record_legacy_dispatch(ctx)
		scheduler.p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
		return true, doom_reason
	end
	local target_acted, target_reason = scheduler.p1_try_nonblocking_target_acquire(s)
	if target_acted then
		return true, target_reason
	end
	local defensive_spell_wait_locked = scheduler.refresh_defensive_spell_wait_lock(now_s())
	if defensive_spell_wait_locked then
		_G.UC_LAST_SCHED_ACTION = ('[def]spell_wait:%s'):format(tostring(scheduler.defensive_pending_action or ''))
		return true, 'BLOCK_DEFENSIVE_SPELL_WAITING'
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
			scheduler.p1_record_legacy_dispatch(ctx)
			scheduler.p1_set_pending_globals()
			_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
			return true, reason
		end
		return false, nil
	end
	acted, reason = try_internal_defensive_action()
	if acted then
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		scheduler.p1_record_legacy_dispatch(ctx)
		scheduler.p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
		return true, reason
	end
	return false, nil
end
function scheduler.on_ipc_message(msg)
	apply_party_state_ipc_message(msg)
end

function scheduler.p1_pick_preemptive_engage(ctx, ranked)
	if type(ranked) ~= 'table' or #ranked == 0 then
		return nil
	end
	local top = ranked[1]
	if scheduler.p1_is_critical_defensive_proposal(ctx and ctx.settings or nil, top) then
		return top
	end
	for i = 1, #ranked do
		local candidate = ranked[i]
		if tostring(candidate.provider or '') == 'combat' and tostring(candidate.action_type or '') == 'engage' then
			if candidate ~= top then
				scheduler.action_timeline_log('ENGAGE_PREEMPT_SELECTED', {
					tid = tonumber(candidate.target_id) or 0,
					name = tostring(candidate.target_name or ''),
					status = tonumber(ctx and ctx.player_status) or 0,
					reason = 'NONCRITICAL_ACTION',
					from = tostring(top and top.provider or ''),
					to = tostring(candidate.provider or ''),
				}, ('engage_preempt:%d'):format(tonumber(candidate.target_id) or 0), 0.25)
			end
			return candidate
		end
	end
	return top
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
	local enemy_buff_remove = uc_active_config.get_path('config.defensive.enemy_buffs.remove')
	if enemy_buff_remove == nil then
		enemy_buff_remove = bool_setting(cfg.def_remove_enemy_buffs, false)
	else
		enemy_buff_remove = enemy_buff_remove == true
	end
	local dbg_enemy_raw = _G.UC_LOG_DEF_SCHED and enemy_buff_remove
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
	local category_value = tonumber(act and act.category)
	local category = tostring(act and act.category or '')
	local start_lock_categories = {
		[4] = true,
		[6] = true,
		[13] = true,
		[14] = true,
		[15] = true,
		[3] = true,
		[11] = true,
		spell = true,
		job_ability = true,
		job_ability_unblinkable = true,
		weaponskill = true,
		weapon_skill = true,
		ranged_attack = true,
		item = true,
	}
	if my_id ~= 0 and actor_id == my_id then
		scheduler.spell_lifecycle_probe_emit('action_packet', act, {
			targets_summary = scheduler.spell_lifecycle_probe_actions_summary(act),
			actions_summary = scheduler.spell_lifecycle_probe_actions_summary(act),
		})
		-- HealBot-style actor-centric start lock, but scoped to real cast/action categories.
		-- Do not treat generic/melee action traffic as lock-start signals.
		if start_lock_categories[category_value] then
			require('uc_scheduler_action_state').note_local_spell_packet_start(scheduler, now_s, {
				message_id = category_value or 0,
			})
		elseif start_lock_categories[category] then
			action_mark_packet_start({
				message_id = category_value or 0,
			})
		end
	end

	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	local now = now_s()
	local state_name = tostring(pending.state or '')
	if not scheduler.p1_pending_is_live_state(state_name) then
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
				scheduler.p1_pending_mark_complete(now, 'action_target_effect')
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
	local enemy_buff_remove = uc_active_config.get_path('config.defensive.enemy_buffs.remove')
	if enemy_buff_remove == nil then
		enemy_buff_remove = bool_setting(cfg.def_remove_enemy_buffs, false)
	else
		enemy_buff_remove = enemy_buff_remove == true
	end
	local dbg_enemy_raw = _G.UC_LOG_DEF_SCHED and enemy_buff_remove
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
	local message_param = tonumber(msg and msg.param_1) or tonumber(msg and msg.param) or 0
	local now = now_s()
	local st = action_state() or {}
	if message_id ~= 0 then
		st.last_action_message_id = message_id
	end
	if my_id ~= 0 and actor_id == my_id and message_id ~= 0 then
		st.last_action_message_param = message_param
		scheduler.spell_lifecycle_probe_emit(tostring(msg and msg._uc_source or 'action_message'), msg, {})
	elseif actor_id ~= 0 and message_id ~= 0 then
		st.last_ignored_action_message_id = message_id
		st.last_ignored_action_message_param = message_param
	end
	-- No inference-based fallback here; enemy effect state is maintained from raw 0x028/0x029 packets.
	if my_id ~= 0 and actor_id == my_id and message_id ~= 0 and tostring(st.last_send_kind or '') ~= 'spell' then
		-- Actor-centric lock state (HealBot-style): always honor self action-complete messages,
		-- independent of scheduler pending bookkeeping.
		action_mark_packet_end({
			message_id = message_id,
		})
	end

	local phase = scheduler.phase1
	if my_id ~= 0 and actor_id == my_id and message_id == scheduler.ENGAGE_REJECT_WAIT_LONGER_MESSAGE_ID then
		scheduler.p1_mark_pending_engage_rejected_wait_longer(phase, now, message_id)
	end
	if my_id ~= 0 and actor_id == my_id and message_id ~= 0 then
		scheduler.handle_local_spell_action_message(phase, now, player, msg, st, message_id, message_param)
		scheduler.handle_local_spell_effect_observation(phase, now, msg, st, message_id, message_param)
	end
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	local state_name = tostring(pending.state or '')
	if not scheduler.p1_pending_is_live_state(state_name) and state_name ~= 'acknowledged' then
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
		scheduler.p1_pending_mark_complete(now, ('msg_%d'):format(message_id))
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

_G.UC_SCHED_OnIncomingText = function(original, modified, mode, blocked)
	local ok = pcall(scheduler.on_incoming_text, original, modified, mode, blocked)
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

