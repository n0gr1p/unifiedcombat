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
require('lor/lor_packets') -- initializes _libs.lor.packets for lazy lor/lor_actor loading
local tb_effect_table = require('uc_tb_effect_table')
local scheduler_locks = require('uc_scheduler_locks')
local scheduler_pending = require('uc_scheduler_pending')
local uc_scheduler_config = require('uc_scheduler_config')
local domain_ownership = require('uc_domain_ownership')
local pet_command_coordinator = require('uc_pet_command_coordinator')
local sleep_status = require('uc_sleep_status')
sleep_status.validate_resources(res.buffs)
local recovery_hold = require('uc_recovery_hold')
local uc_time = require('uc_time')
local socket_gettime = uc_time.gettime
local time_source_error_reported = false
local CAST_MOVEMENT_SETTLE_SECONDS = 0.1

local action_buff_map = {}
do
	local ok, map = pcall(dofile, windower.addon_path .. 'data/action_buff_map.lua')
	if ok and type(map) == 'table' then
		action_buff_map = map
	end
end

local scheduler = {
	runtime_revision = '20260910-sequence-dispatch-2',
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
	pet_command_state = pet_command_coordinator.new({
		timeout = 2.5,
		ward_effect_timeout = 8.0,
		backoff_base = 1.0,
		backoff_max = 8.0,
	}),
	pet_combat_state = require('uc_pet_combat_state').new(),
	pet_tp_state = require('uc_pet_tp_state').new(),
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
local camp_pulling_config
local p1_build_pull_executor
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

local known_status_removal_keys = {}
for status_name in pairs(debuff_map) do
	known_status_removal_keys[normalize_status_removal_key({ en = status_name })] = true
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
local DISPell_ATTEMPT_COOLDOWN_S = 3.0
local ENEMY_DEBUFF_ATTEMPT_COOLDOWN_S = 5.0

require('uc_scheduler_enemy_effect_state').load_dispel_map(windower.addon_path)

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

function scheduler.clear_local_brd_spell_failure(meta)
	return require('uc_scheduler_action_state').clear_local_brd_spell_failure(scheduler, now_s, meta)
end

function scheduler.clear_local_spell_prestart_rejection(meta)
	return require('uc_scheduler_action_state').clear_local_spell_prestart_rejection(scheduler, now_s, meta)
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

function scheduler.is_spell_prestart_rejection_message_id(message_id)
	local mid = tonumber(message_id) or 0
	return mid == 17 or mid == 18
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
			local cleared
			if provider == 'defensive_internal' or provider == 'defensive_healbot' then
				cleared = scheduler.clear_local_defensive_spell_success(release_meta)
			else
				cleared = scheduler.clear_local_spell_success(release_meta)
			end
			if cleared and provider == 'camp_puller' then
				scheduler.p1_pending_mark_complete(now, 'spell_cast_complete_text')
				scheduler.providers.camp_puller.note_action_result(
					true,
					now,
					camp_pulling_config()
				)
			end
			return
		end
	elseif matched == 'casting_interrupted' and actor == player_name then
		local prefix = player_name .. "'s casting is interrupted"
		if spell_text_begins_with(raw_text, prefix) then
			release_meta.release_reason = 'cast_interrupted_text'
			release_meta.completion_reason = 'cast_interrupted_text'
			local cleared
			if provider == 'defensive_internal' or provider == 'defensive_healbot' then
				cleared = scheduler.clear_local_defensive_spell_interruption(release_meta)
			else
				cleared = scheduler.clear_local_spell_interruption(release_meta)
			end
			if cleared and provider == 'camp_puller' then
				scheduler.p1_pending_mark_complete(now, 'spell_cast_interrupted_text')
				scheduler.providers.camp_puller.note_action_result(
					false,
					now,
					camp_pulling_config()
				)
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
	local action_type = tostring(selected.action_type or '')
	if (action_type ~= 'spell' and action_type ~= 'ja') or tostring(detail.def_action_type or '') ~= 'cure' then
		return false
	end
	local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', settings and settings.defensive_critical_hpp)) or 35
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
	local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', settings and settings.defensive_critical_hpp)) or 35
	local action_type = tostring(selected.action_type or '')
	return (action_type == 'spell' or action_type == 'ja')
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
		run = windower.ffxi.run,
		intent = intent,
	})
	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_value + 0.6
end

function scheduler.refresh_brd_maintenance_movement_lock(reason, at)
	local now_value = tonumber(at) or now_s()
	local current_owner = tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or 'none')
	local current_lock_until = tonumber(rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')) or 0
	if current_owner == 'nyzul_hold' and current_lock_until > now_value then
		return false
	end
	-- A reserved Bard lane can spend multiple ticks without an actionable proposal.
	-- Reassert the physical stop here so no earlier follow/path vector survives that wait.
	local intent = {
		kind = 'run_stop',
		source = 'unified_scheduler:brd_maintenance_movement_lock',
		meta = {
			reason = 'BRD_MAINTENANCE_LANE_LOCK',
			lane_reason = tostring(reason or 'brd_sequence'),
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
		dispatcher = dispatcher,
		run = windower.ffxi.run,
		intent = intent,
	})
	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = math.max(current_lock_until, now_value + 0.6)
	_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
	_G.UC_MOVEMENT_BLOCK_REASON = 'BRD_LANE:' .. tostring(reason or 'brd_sequence')
	return true
end

function scheduler.apply_brd_maintenance_movement_lock(action_name, target_id, reason, at)
	local now_value = tonumber(at) or now_s()
	if not scheduler.refresh_brd_maintenance_movement_lock(reason, now_value) then
		return false
	end
	scheduler.action_timeline_log('BRD_MOVEMENT_HOLD', {
		action = tostring(action_name or ''),
		target_id = tonumber(target_id) or 0,
		reason = tostring(reason or 'brd_sequence'),
	}, ('brd_movement_hold:%s'):format(tostring(action_name or '')), 0.05)
	return true
end

function scheduler.apply_brd_maintenance_lane_movement(reason, at)
	local now_value = tonumber(at) or now_s()
	local current_owner = tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or 'none')
	local current_lock_until = tonumber(rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')) or 0
	if current_owner == 'nyzul_hold' and current_lock_until > now_value then
		return false
	end
	local positioning = require('uc_brd_positioning')
	local positioning_status = positioning.status()
	if positioning_status.phase == 'moving' and not domain_ownership.is_enabled('movement') then
		positioning.fail('BRD_REPOSITION_MOVEMENT_DOMAIN_DISABLED')
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if type(me) ~= 'table' or tonumber(me.x) == nil or tonumber(me.y) == nil then
		error('Bard positioning requires the local player coordinates')
	end
	local request = positioning.movement_request(me, now_value)
	if request == nil or request.kind == 'stop' then
		return scheduler.refresh_brd_maintenance_movement_lock(
			request and request.reason or reason,
			now_value
		)
	end
	if request.kind ~= 'run' then
		error('unsupported Bard positioning movement request: ' .. tostring(request.kind))
	end
	local movement = require('uc_movement_dispatcher').build({
		dispatcher = require('uc_scheduler_dispatcher'),
		run = windower.ffxi.run,
		source_prefix = 'scheduler_brd_positioning',
	})
	movement.run_vector(request.run_x, request.run_y, {
		reason = request.reason,
		target_x = request.target_x,
		target_y = request.target_y,
		coverage_count = request.coverage_count,
		recipient_count = request.recipient_count,
		full_coverage = request.full_coverage,
	})
	_G.UC_MOVEMENT_OWNER = 'scheduler_brd'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_value + 0.40
	_G.UC_MOVEMENT_MODE = 'BRD_REPOSITION'
	_G.UC_MOVEMENT_BLOCK_REASON = tostring(request.reason or 'BRD_REPOSITION')
	scheduler.action_timeline_log('BRD_REPOSITION_MOVE', {
		reason = tostring(request.reason or ''),
		remaining = ('%.2f'):format(tonumber(request.remaining) or 0),
		coverage = ('%d/%d'):format(
			tonumber(request.coverage_count) or 0,
			tonumber(request.recipient_count) or 0
		),
		full = request.full_coverage == true,
	}, 'brd_reposition_move', 0.50)
	return true
end

function scheduler.apply_sch_lane_movement(reason, at)
	if type(reason) ~= 'string' or reason == '' then
		error('Scholar lane movement hold requires a non-empty reason')
	end
	if type(at) ~= 'number' then
		error('Scholar lane movement hold requires a numeric time')
	end
	local current_owner = rawget(_G, 'UC_MOVEMENT_OWNER')
	local current_lock_until = rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')
	if current_owner == 'scheduler_sch'
		and type(current_lock_until) == 'number'
		and current_lock_until > at then
		_G.UC_MOVEMENT_LOCK_UNTIL = at + 0.6
		_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
		_G.UC_MOVEMENT_BLOCK_REASON = 'SCH_LANE:' .. reason
		return true
	end
	local intent = {
		kind = 'run_stop',
		source = 'unified_scheduler:sch_lane_movement_hold',
		meta = {
			reason = 'SCH_LANE_MOVEMENT_HOLD',
			lane_reason = reason,
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
		dispatcher = dispatcher,
		run = windower.ffxi.run,
		intent = intent,
	})
	_G.UC_MOVEMENT_OWNER = 'scheduler_sch'
	_G.UC_MOVEMENT_LOCK_UNTIL = at + 0.6
	_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
	_G.UC_MOVEMENT_BLOCK_REASON = 'SCH_LANE:' .. reason
	scheduler.action_timeline_log('SCH_MOVEMENT_HOLD', {
		reason = reason,
	}, 'sch_movement_hold:' .. reason, 0.25)
	return true
end

function scheduler.apply_cast_movement_hold(reason, at)
	local now_value = tonumber(at) or now_s()
	local block_reason = tostring(reason or 'MOVE_COORD_CASTING_ACTION')
	local intent = {
		kind = 'run_stop',
		source = 'unified_scheduler:cast_movement_hold',
		meta = {
			reason = block_reason,
			movement_mode = 'CAST_FREEZE',
		},
	}
	local dispatcher = require('uc_scheduler_dispatcher')
	require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
		dispatcher = dispatcher,
		run = windower.ffxi.run,
		intent = intent,
	})
	local current_owner = tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or 'none')
	local current_lock_until = tonumber(rawget(_G, 'UC_MOVEMENT_LOCK_UNTIL')) or 0
	if current_owner ~= 'nyzul_hold' or current_lock_until <= now_value then
		_G.UC_MOVEMENT_OWNER = 'scheduler'
		_G.UC_MOVEMENT_LOCK_UNTIL = math.max(current_lock_until, now_value + 0.6)
	end
	_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
	_G.UC_MOVEMENT_BLOCK_REASON = block_reason
	scheduler.action_timeline_log('CAST_MOVEMENT_HOLD', {
		action = tostring((action_state() or {}).last_action_name or ''),
		reason = block_reason,
	}, ('cast_movement_hold:%s'):format(block_reason), 0.20)
end

function scheduler.cast_movement_settle_blocked(selected)
	if type(selected) ~= 'table' then
		error('cast movement settle requires a selected action')
	end
	if type(selected.action_type) ~= 'string' then
		error('cast movement settle selected action_type must be a string')
	end
	if selected.action_type ~= 'spell' then
		return false, nil
	end
	if type(selected.action_name) ~= 'string' or selected.action_name == '' then
		error('cast movement settle selected spell requires an action name')
	end
	if type(selected.target_name) ~= 'string' then
		error('cast movement settle selected spell requires a target name')
	end
	local target_id = tonumber(selected.target_id)
	if target_id == nil then
		error('cast movement settle selected spell requires a numeric target id')
	end

	local lor_actor_mod = require('lor/lor_actor')
	if type(lor_actor_mod) ~= 'table'
		or type(lor_actor_mod.Actor) ~= 'table'
		or type(lor_actor_mod.Actor.new) ~= 'function' then
		error('scheduler cast movement settle lor/lor_actor contract is invalid')
	end
	local actor = rawget(_G, 'UC_SCHED_CAST_LOCAL_ACTOR')
	if actor == nil then
		actor = lor_actor_mod.Actor.new()
		rawset(_G, 'UC_SCHED_CAST_LOCAL_ACTOR', actor)
	end
	if type(actor) ~= 'table' or type(actor.is_moving) ~= 'function' then
		error('scheduler cast movement settle local actor contract is invalid')
	end

	local now = now_s()
	local settle_until_value = rawget(_G, 'UC_CAST_MOVEMENT_SETTLE_UNTIL')
	if settle_until_value ~= nil and type(settle_until_value) ~= 'number' then
		error('UC_CAST_MOVEMENT_SETTLE_UNTIL must be numeric when set')
	end
	local settle_until = 0
	if settle_until_value ~= nil then
		settle_until = settle_until_value
	end
	local moving = actor:is_moving() == true
	if moving then
		settle_until = now + CAST_MOVEMENT_SETTLE_SECONDS
		_G.UC_CAST_MOVEMENT_SETTLE_UNTIL = settle_until
	end
	if moving or now < settle_until then
		scheduler.apply_cast_movement_hold('MOVE_COORD_CAST_SETTLE', now)
		_G.UC_LAST_SCHED_ACTION = ('[p1]cast_move_settle:%s->%s'):format(
			selected.action_name,
			selected.target_name
		)
		scheduler.action_timeline_log('CAST_MOVEMENT_SETTLE', {
			action = selected.action_name,
			target_id = target_id,
			moving = tostring(moving),
			remaining_s = ('%.2f'):format(math.max(0, settle_until - now)),
		}, ('cast_movement_settle:%s:%d'):format(
			selected.action_name,
			target_id
		), 0.10)
		return true, 'BLOCK_SCHED_CAST_MOVEMENT_SETTLE'
	end
	if settle_until_value ~= nil then
		_G.UC_CAST_MOVEMENT_SETTLE_UNTIL = nil
	end
	return false, nil
end

local function current_zone_id()
	return require('uc_scheduler_context_utils').current_zone_id()
end

local function enemy_dispel_diag(msg)
	if not uc_scheduler_config.debug_enabled() then
		return
	end
	_G.UC_LAST_SCHED_ACTION = tostring(msg or '')
end

local function enemy_dispel_log(msg)
	if not uc_scheduler_config.debug_log_def_sched() then
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
	return require('uc_scheduler_enemy_effect_state').attempt_map(scheduler.phase1)
end

local function enemy_effect_state_map()
	return require('uc_scheduler_enemy_effect_state').effect_map(scheduler.phase1)
end

local function enemy_effect_state_set(target_id, effect_id, source, at, duration_s, action_id)
	return require('uc_scheduler_enemy_effect_state').set(
		scheduler.phase1,
		target_id,
		effect_id,
		source,
		at,
		duration_s,
		now_s,
		action_id
	)
end

local function enemy_effect_state_clear(target_id, effect_id)
	return require('uc_scheduler_enemy_effect_state').clear(
		scheduler.phase1,
		target_id,
		effect_id
	)
end

local function enemy_effect_state_clear_target(target_id)
	return require('uc_scheduler_enemy_effect_state').clear_target(
		scheduler.phase1,
		target_id
	)
end

local function enemy_effect_state_prune_expired(at)
	return require('uc_scheduler_enemy_effect_state').prune_expired(
		scheduler.phase1,
		at,
		now_s
	)
end

local function enemy_effect_state_sweep(max_age_s)
	return require('uc_scheduler_enemy_effect_state').sweep(
		scheduler.phase1,
		max_age_s,
		now_s,
		windower.ffxi.get_mob_by_id
	)
end

local function can_attempt_enemy_dispel(action_name, target_id, effect_id, now)
	return require('uc_scheduler_enemy_effect_state').can_attempt(
		scheduler.phase1,
		action_name,
		target_id,
		effect_id,
		now,
		DISPell_ATTEMPT_COOLDOWN_S
	)
end

local function can_attempt_enemy_debuff(action_name, target_id, effect_id, now)
	return require('uc_scheduler_enemy_effect_state').can_attempt(
		scheduler.phase1,
		action_name,
		target_id,
		effect_id,
		now,
		ENEMY_DEBUFF_ATTEMPT_COOLDOWN_S
	)
end

local function mark_enemy_dispel_attempt(key, now)
	return require('uc_scheduler_enemy_effect_state').mark_attempt(
		scheduler.phase1,
		key,
		now,
		now_s
	)
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

scheduler.spell_effect_gain_messages = {
	[2] = true, [230] = true, [236] = true, [237] = true, [252] = true,
	[264] = true, [266] = true, [268] = true, [269] = true, [270] = true,
	[271] = true, [272] = true, [329] = true, [330] = true, [331] = true,
	[332] = true, [333] = true, [334] = true, [335] = true,
}

local function ingest_enemy_effects_from_raw_action_028(data_or_act)
	return require('uc_scheduler_enemy_effect_state').ingest_raw_action(
		scheduler.phase1,
		data_or_act,
		{
			addon_path = windower.addon_path,
			parse_action = windower.packets.parse_action,
			get_player = windower.ffxi.get_player,
			now = now_s,
			spell_effect_gain_messages = scheduler.spell_effect_gain_messages,
		}
	)
end

local function maybe_broadcast_party_state_ipc()
	return require('uc_scheduler_party_state').maybe_broadcast(
		scheduler.party_state_ipc,
		{
			now = now_s,
			get_player = windower.ffxi.get_player,
			current_zone_id = current_zone_id,
			send_ipc_message = windower.send_ipc_message,
		}
	)
end

local function apply_party_state_ipc_message(msg)
	return require('uc_scheduler_party_state').apply_message(
		scheduler.party_state_ipc,
		msg,
		{
			current_zone_id = current_zone_id,
			now = now_s,
		}
	)
end

local function get_party_state_ipc_entry(member_id, member_name)
	return require('uc_scheduler_party_state').get_entry(
		scheduler.party_state_ipc,
		member_id,
		member_name,
		{
			current_zone_id = current_zone_id,
			now = now_s,
		}
	)
end

local function get_settings()
	return require('uc_scheduler_context_utils').get_settings()
end

camp_pulling_config = function()
	local settings = get_settings()
	local config = settings.camp_pulling
	if type(config) ~= 'table' then
		error('normalized combat.pulling configuration is required')
	end
	return config
end

function scheduler.active_value_or_flat(path, flat_value)
	return uc_scheduler_config.active_value_or_flat(path, flat_value)
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
	if not bool_setting(scheduler.active_value_or_flat('config.defensive.enabled', settings and settings.defensive_enabled), false) then
		return false, nil
	end
	if not bool_setting(scheduler.active_value_or_flat('config.defensive.doom.holy_water_enabled', settings and settings.defensive_doom_water), false) then
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
	local _stop_intent_ok, _stop_intent_reason = dispatcher.validate_intent(stop_intent)
	local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
		dispatcher = dispatcher,
		run = windower.ffxi.run,
		intent = stop_intent,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_DOOM_HOLY_WATER_VALIDATE = {
		ok = _stop_intent_ok and true or false,
		reason = _stop_intent_reason,
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
	local sch_lane = require('uc_sch_runtime').lane_status()
	if sch_lane.reserved and not sch_lane.atomic then
		local preempted, preempt_reason = require('uc_sch_runtime').preempt(
			'doom_emergency_preemption',
			now
		)
		if preempted or preempt_reason ~= 'doom_emergency_preemption' then
			error('Scholar Doom preemption did not abort the active sequence')
		end
		log_def_sched(('SCH_LANE_PREEMPT emergency=doom lane=%s'):format(
			tostring(sch_lane.class)
		))
	elseif sch_lane.atomic then
		log_def_sched(('SCH_ATOMIC_LANE_RETAIN emergency=doom lane=%s'):format(
			tostring(sch_lane.class)
		))
	end
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
	local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
	local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		send_command = windower.send_command,
		intent = intent,
		command = doom_holy_water_command,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_DOOM_HOLY_WATER_COMMAND_VALIDATE = {
		ok = _intent_ok and true or false,
		reason = _intent_reason,
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
	local runtime_overrides = require('uc_runtime_overrides')
	return runtime_overrides.sleep_spell_names(settings)
end

scheduler.SLEEP_MAX_TARGET_DISTANCE = 6.0
scheduler.SLEEP_TARGET_SUPPRESSION_TIMEOUT_S = 45.0
scheduler.TANK_TARGET_ACQUIRE_PRIORITY = 106
scheduler.TANK_TARGET_ACQUIRE_URGENCY = 0.80

function scheduler.sleep_max_target_distance(settings)
	local configured = tonumber(scheduler.active_value_or_flat(
		'config.sleep.max_target_range',
		settings and settings.sleep_max_target_range
	))
	if configured == nil then
		configured = scheduler.SLEEP_MAX_TARGET_DISTANCE
	end
	if configured < 0.1 then
		return 0.1
	end
	if configured > 50.0 then
		return 50.0
	end
	return configured
end

function scheduler.try_partner_tiebreak(settings)
	if not bool_setting(settings and settings.partner, false) then
		return false, nil
	end

	local player = windower.ffxi.get_player()
	local current = windower.ffxi.get_mob_by_target('t')
	local partner_snapshots = {}
	for _, partner_id in ipairs(uc_partner_list.as_ordered_ids(settings)) do
		local partner = windower.ffxi.get_mob_by_id(partner_id)
		local target = partner and partner.target_index and windower.ffxi.get_mob_by_index(partner.target_index) or nil
		partner_snapshots[#partner_snapshots + 1] = {
			id = partner_id,
			status = partner and partner.status,
			target_id = target and target.id,
			target_live = target and target.valid_target == true and (tonumber(target.hpp) or 0) > 0,
		}
	end

	local mobs = windower.ffxi.get_mob_array()
	assert(type(mobs) == 'table', 'scheduler partner arbitration requires mob array')
	local _, claims_set = uc_targeting_common.build_friendly_claims()
	assert(type(claims_set) == 'table', 'scheduler partner arbitration requires friendly claims')
	local blocked_mob_ids = {}
	for _, mob in pairs(mobs) do
		local mob_id = tonumber(mob and mob.id) or 0
		if mob_id > 0 and require('uc_target_ignore').is_mob_blocked(settings, mob) then
			blocked_mob_ids[mob_id] = true
		end
	end

	local decision = require('uc_scheduler_partner_arbitration').decide({
		partner_enabled = true,
		autotarget_enabled = bool_setting(uc_scheduler_config.combat_autotarget(settings), false),
		my_id = player and player.id,
		player_status = player and player.status,
		current_target = current,
		partners = partner_snapshots,
		mobs = mobs,
		claims_set = claims_set,
		blocked_mob_ids = blocked_mob_ids,
	})
	if not decision then
		return false, nil
	end

	local ok, dispatch_reason
	if decision.action == 'switch' then
		local result = require('uc_scheduler_dispatcher').dispatch_intent({
			kind = 'switch_target',
			source = 'unified_scheduler:partner_tiebreak',
			target_id = decision.target_id,
		}, {
			execute = true,
			switch_target = uc_attack.switch_target,
		})
		ok = result.ok and result.executed
		dispatch_reason = result.reason
		if ok then
			_G.UC_LAST_BLOCK_REASON = 'PARTNER_TIEBREAK_SWITCH'
			_G.UC_LAST_SCHED_ACTION = ('[partner]tiebreak_switch:%d->%d'):format(decision.from_target_id, decision.target_id)
			_G.UC_WS_LAST_DIAG = ('scheduler partner tiebreak yield my=%d winner=%d from=%d to=%d'):format(
				tonumber(player.id), decision.winner_id, decision.from_target_id, decision.target_id
			)
			return true, 'BLOCK_PARTNER_TIEBREAK_SWITCH'
		end
	elseif decision.action == 'disengage' then
		local result = require('uc_scheduler_dispatcher').dispatch_intent({
			kind = 'disengage',
			source = 'unified_scheduler:partner_tiebreak',
		}, {
			execute = true,
			disengage = uc_attack.disengage,
		})
		ok = result.ok and result.executed
		dispatch_reason = result.reason
		if ok then
			_G.UC_LAST_BLOCK_REASON = 'PARTNER_TIEBREAK_DISENGAGE'
			_G.UC_LAST_SCHED_ACTION = ('[partner]tiebreak_disengage:%d'):format(decision.from_target_id)
			_G.UC_WS_LAST_DIAG = ('scheduler partner tiebreak disengage my=%d winner=%d mob=%d'):format(
				tonumber(player.id), decision.winner_id, decision.from_target_id
			)
			return true, 'BLOCK_PARTNER_TIEBREAK_DISENGAGE'
		end
	else
		error('scheduler partner arbitration returned unsupported action: ' .. tostring(decision.action))
	end

	error(('scheduler partner arbitration dispatch failed action=%s reason=%s'):format(
		tostring(decision.action), tostring(dispatch_reason)
	))
end
scheduler.TANK_ENGAGE_PRIORITY = 107
scheduler.TANK_ENGAGE_URGENCY = 0.85
scheduler.DEFAULT_ENGAGE_PRIORITY = 72
scheduler.DEFAULT_ENGAGE_URGENCY = 0.70
scheduler.PRIORITY_BAND_AFTERMATH_WS = 108
scheduler.PRIORITY_BAND_BRD_MAINTENANCE = 200
scheduler.PRIORITY_BAND_SCH_ROUTINE = 75
scheduler.PRIORITY_BAND_SCH_PREPARED = 150
scheduler.PRIORITY_BAND_SCH_DEFENSIVE = 145
scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION = 131
scheduler.PRIORITY_BAND_SLEEP = 142
scheduler.PRIORITY_BAND_GEO_MAINTENANCE = 210
scheduler.PRIORITY_BAND_GEO_CREATION = 240
scheduler.PRIORITY_BAND_DEATH_SWITCH = 148
scheduler.PRIORITY_BAND_SLEEP_WAKE = 149
scheduler.PRIORITY_BAND_CRITICAL_CURE = 250
scheduler.PRIORITY_BAND_CHARM_SLEEPER = 1000
scheduler.PRIORITY_BAND_ENGAGE_BYPASS = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION
scheduler.TARGET_ACQUIRE_DEBOUNCE_S = 0.20
scheduler.DEATH_SWITCH_DEBOUNCE_S = 0.90

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
	if not uc_scheduler_config.debug_enabled(s) then
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
	local active_provider = tostring(st.last_action_provider or '')
	if scheduler.is_spell_prestart_rejection_message_id(message_id) then
		if (tonumber(st.packet_start_at) or 0) > 0 then
			return false, 'prestart_rejection_after_cast_start'
		end
		local provider = tostring(st.last_action_provider or '')
		local action_name = tostring(st.last_action_name or '')
		local cleared = scheduler.clear_local_spell_prestart_rejection({
			message_id = message_id,
			message_param = message_param,
			terminal_outcome = 'server_reject_unable_cast',
		})
		if not cleared then
			return false, require('uc_scheduler_action_state').last_completion_ignore_reason(scheduler)
		end
		if scheduler.defensive_spell_waiting == true then
			scheduler.clear_defensive_spell_wait_state()
		end
		local current_lock_until = tonumber(_G.UC_MOVEMENT_LOCK_UNTIL) or 0
		_G.UC_MOVEMENT_LOCK_UNTIL = math.min(current_lock_until, now + 0.2)
		scheduler.p1_pending_mark_failed(now, ('spell_server_reject_%d'):format(message_id), 0.75)
		if provider == 'maintenance_brd' then
			require('uc_brd_maintenance').reject_pending_before_start(message_id, now)
			phase.maintenance_next_at = phase.maintenance_next_at or {}
			phase.maintenance_next_at.brd_songs = math.max(
				tonumber(phase.maintenance_next_at.brd_songs) or 0,
				now + 0.75
			)
		elseif provider == 'maintenance_geo' then
			scheduler.providers.geo_maintenance.note_failure(action_name, now)
		elseif provider == 'camp_puller' then
			scheduler.providers.camp_puller.note_action_result(
				false,
				now,
				camp_pulling_config()
			)
		end
		return true, 'server_reject_unable_cast'
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
			if active_provider == 'camp_puller' then
				scheduler.providers.camp_puller.note_action_result(
					true,
					now,
					camp_pulling_config()
				)
			end
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
		local provider = tostring(st.last_action_provider or '')
		local action_name = tostring(st.last_action_name or '')
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
			require('uc_brd_maintenance').cancel_pending('cast_interrupted')
			if provider == 'maintenance_geo' then
				scheduler.providers.geo_maintenance.note_failure(action_name, now)
			elseif provider == 'camp_puller' then
				scheduler.providers.camp_puller.note_action_result(
					false,
					now,
					camp_pulling_config()
				)
			end
		end
		return cleared == true, cleared and 'cast_interrupted' or require('uc_scheduler_action_state').last_completion_ignore_reason(scheduler)
	end
	return false, 'not_cast_terminal'
end

local diag_init = {
	ja_sched = false,
	ja_debug = false,
	def_sched = false,
	combat_sched = false,
}

local p1_apply_face_to_target

function scheduler.reaction_observed_effect_set()
	local observed = require('uc_scheduler_enemy_effect_state').copy_dispellable_set()
	for effect_id in pairs(require('uc_reaction_runtime').effect_watch_set()) do
		observed[effect_id] = true
	end
	return observed
end

function scheduler.apply_reaction_turn(lock, turn_away)
	if type(lock) ~= 'table' then
		return false
	end
	local applied = p1_apply_face_to_target(
		get_settings(),
		tonumber(lock.actor_id) or 0,
		turn_away == true,
		true
	)
	if applied and turn_away == true then
		require('uc_reaction_runtime').mark_turn_applied(lock.key)
		lock.turn_applied = true
	end
	return applied
end

function scheduler.apply_reaction_response(lock)
	if type(lock) ~= 'table' then
		return false
	end
	local response = tostring(lock.response or '')
	if response == 'turn_away' then
		return scheduler.apply_reaction_turn(lock, true)
	end
	if response == 'run_away' or response == 'move_to_range' then
		require('uc_reaction_runtime').mark_turn_applied(lock.key)
		lock.turn_applied = true
		return true
	end
	if response == 'use_action' or response == 'use_sequence' then
		-- Action-bearing reactions are executed by the combat proposal path.
		-- Activation itself has no immediate facing/disengage side effect.
		return true
	end
	if response ~= 'stop_attacking' then
		error('unified_scheduler received unsupported reaction response: ' .. response)
	end
	local player = windower.ffxi.get_player()
	local player_status = tonumber(player and player.status) or -1
	if require('uc_reaction_runtime').requires_disengage(lock, player_status) then
		local result = require('uc_scheduler_dispatcher').dispatch_intent({
			kind = 'disengage',
			source = 'unified_scheduler:reaction_stop_attacking',
		}, {
			execute = true,
			disengage = uc_attack.disengage,
		})
		if not result.ok or not result.executed then
			error('unified_scheduler failed to disengage for stop_attacking reaction: ' .. tostring(result.reason))
		end
	end
	require('uc_reaction_runtime').mark_turn_applied(lock.key)
	lock.turn_applied = true
	return true
end

local function reaction_movement_executor()
	return require('uc_scheduler_movement_facade').build({
		dispatcher = require('uc_scheduler_dispatcher'),
		run = windower.ffxi.run,
		turn = windower.ffxi.turn,
	})
end

function scheduler.pause_reaction_movement(lock, reason)
	if not require('uc_reaction_runtime').owns_movement(lock) then
		return false
	end
	if rawget(_G, 'UC_MOVEMENT_OWNER') ~= 'scheduler_reaction' then
		return false
	end
	reaction_movement_executor().stop({
		reason = reason,
		ability = lock.name,
		actor_id = lock.actor_id,
	})
	_G.UC_MOVEMENT_OWNER = 'none'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_s()
	return true
end

function scheduler.release_reaction_movement(lock, reason)
	if not require('uc_reaction_runtime').owns_movement(lock) then
		return false
	end
	local response = tostring(lock.response or '')
	reaction_movement_executor().stop({
		reason = tostring(reason or 'REACTION_MOVEMENT_RELEASED'),
		ability = tostring(lock.name or ''),
		actor_id = tonumber(lock.actor_id) or 0,
	})
	if tostring(rawget(_G, 'UC_MOVEMENT_OWNER') or '') == 'scheduler_reaction' then
		_G.UC_MOVEMENT_OWNER = 'none'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s()
	end
	scheduler.action_timeline_log('REACTION_CLEARED', {
		ability = tostring(lock.name or ''),
		response = response,
		target_distance = tonumber(lock.distance),
		reason = tostring(reason or 'released'),
	}, ('reaction_cleared:%s:%d'):format(tostring(lock.name or ''), tonumber(lock.actor_id) or 0), 0)
	return true
end

function scheduler.apply_reaction_movement(lock, formation_runtime)
	local reaction_runtime = require('uc_reaction_runtime')
	if not reaction_runtime.owns_movement(lock) then
		error('reaction scheduler movement requires a movement-owning reaction lock')
	end
	local response = tostring(lock.response or '')
	local actor_id = tonumber(lock.actor_id) or 0
	local enemy = actor_id > 0 and windower.ffxi.get_mob_by_id(actor_id) or nil
	if type(enemy) ~= 'table'
		or enemy.valid_target ~= true
		or tonumber(enemy.spawn_type) ~= 16
		or (tonumber(enemy.hpp) or 0) <= 0 then
		local released, replacement = reaction_runtime.cancel(lock.key, 'actor_unavailable')
		scheduler.release_reaction_movement(released, 'REACTION_MOVEMENT_ACTOR_UNAVAILABLE')
		_G.UC_REACTION_LOCK = replacement
		return false, 'MOVE_COORD_REACTION_ACTOR_UNAVAILABLE'
	end
	local me = windower.ffxi.get_mob_by_target('me')
	local request
	if response == 'run_away' then
		request = reaction_runtime.run_away_request(lock, me, enemy)
	elseif response == 'move_to_range' then
		request = reaction_runtime.move_to_range_request(lock, me, enemy)
	else
		error('unsupported reaction movement response: ' .. response)
	end
	formation_runtime.stop('FORMATION_REACTION_MOVEMENT')
	local movement = reaction_movement_executor()
	if request.kind == 'run' then
		movement.run_vector(request.run_x, request.run_y, {
			reason = request.reason,
			ability = tostring(lock.name or ''),
			actor_id = actor_id,
			current_distance = request.current_distance,
			target_distance = request.target_distance,
		})
	elseif request.kind == 'stop' then
		movement.stop({
			reason = request.reason,
			ability = tostring(lock.name or ''),
			actor_id = actor_id,
			current_distance = request.current_distance,
			target_distance = request.target_distance,
		})
	elseif request.kind ~= 'hold' then
		error('unsupported reaction movement request: ' .. tostring(request.kind))
	end
	_G.UC_MOVEMENT_MODE = response == 'run_away' and 'REACTION_RUN_AWAY' or 'REACTION_MOVE_TO_RANGE'
	_G.UC_MOVEMENT_BLOCK_REASON = request.reason
	_G.UC_MOVEMENT_OWNER = 'scheduler_reaction'
	_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.40
	if request.phase_changed == true then
		scheduler.action_timeline_log(request.reason, {
			ability = tostring(lock.name or ''),
			response = response,
			actor_id = actor_id,
			current_distance = request.current_distance,
			target_distance = request.target_distance,
		}, ('reaction_movement:%s:%d:%s'):format(
			tostring(lock.name or ''),
			actor_id,
			tostring(request.reason)
		), 0)
	end
	return request.kind ~= 'hold', request.reason
end

function scheduler.apply_reaction_run_away(lock, formation_runtime)
	if type(lock) ~= 'table' or tostring(lock.response or '') ~= 'run_away' then
		error('run-away scheduler movement requires a run_away reaction lock')
	end
	return scheduler.apply_reaction_movement(lock, formation_runtime)
end

function scheduler.refresh_reaction_lock()
	local refresh_now = now_s()
	local target = windower.ffxi.get_mob_by_target('t')
	local target_id = tonumber(target and target.id) or 0
	local effects = target_id > 0 and enemy_effect_tracker.get_effects(target_id) or {}
	local previous_lock = rawget(_G, 'UC_REACTION_LOCK')
	local reaction_runtime = require('uc_reaction_runtime')
	local invalidated_lock = reaction_runtime.prune_invalid_ability_windows(function(actor_id)
		local actor = windower.ffxi.get_mob_by_id(actor_id)
		return actor ~= nil and combat_core.is_live_actionable_combat_target(actor, refresh_now, true)
	end)
	local lock, released_target_id = reaction_runtime.evaluate(target_id, effects, refresh_now)
	local camp_lane_reserved = scheduler.providers.camp_puller.active()
	_G.UC_REACTION_LOCK = lock
	if invalidated_lock then
		scheduler.action_timeline_log('REACTION_CLEARED', {
			ability = tostring(invalidated_lock.name or ''),
			response = tostring(invalidated_lock.response or ''),
			reason = 'actor_unavailable',
		}, ('reaction_cleared:%s:%d'):format(
			tostring(invalidated_lock.name or ''),
			tonumber(invalidated_lock.actor_id) or 0
		), 0)
	end
	if reaction_runtime.owns_movement(previous_lock)
		and (type(lock) ~= 'table' or tostring(lock.key or '') ~= tostring(previous_lock.key or '')) then
		scheduler.release_reaction_movement(previous_lock, 'REACTION_MOVEMENT_EVALUATION_RELEASE')
	end
	if not camp_lane_reserved
		and released_target_id and released_target_id > 0 and target_id > 0 then
		scheduler.apply_reaction_turn({ actor_id = target_id }, false)
	end
	if not camp_lane_reserved and lock and lock.turn_applied ~= true then
		scheduler.apply_reaction_response(lock)
	end
	return lock
end

local function ensure_diag_logs_initialized()
	local s = get_settings()
	if not uc_scheduler_config.debug_enabled(s) then
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
	if not domain_ownership.is_enabled('movement') then
		scheduler.pause_reaction_movement(
			rawget(_G, 'UC_REACTION_LOCK'),
			'REACTION_MOVEMENT_DOMAIN_DISABLED'
		)
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_DOMAIN_DISABLED'
		return false, 'MOVE_COORD_DOMAIN_DISABLED'
	end
	local nyzul_runtime = require('uc_nyzul_runtime')
	if nyzul_runtime.is_movement_held()
		and not scheduler.providers.camp_puller.active() then
		scheduler.pause_reaction_movement(
			rawget(_G, 'UC_REACTION_LOCK'),
			'REACTION_MOVEMENT_NYZUL_HOLD'
		)
		local reason = nyzul_runtime.movement_hold_reason()
		_G.UC_MOVEMENT_MODE = 'NYZUL_HOLD'
		_G.UC_MOVEMENT_BLOCK_REASON = reason
		_G.UC_MOVEMENT_OWNER = 'nyzul_hold'
		_G.UC_MOVEMENT_LOCK_UNTIL = math.huge
		return false, reason
	end
	if scheduler.providers.camp_puller.movement_reserved(camp_pulling_config()) then
		local pull_status = scheduler.providers.camp_puller.status_snapshot()
		if pull_status.state == 'IDLE' then
			if rawget(_G, 'UC_CAMP_PULL_IDLE_STOPPED') ~= true then
				p1_build_pull_executor().stop({
					reason = 'PULL_IDLE_MOVEMENT_HOLD',
					provider = 'camp_puller',
				})
				_G.UC_CAMP_PULL_IDLE_STOPPED = true
			end
		else
			_G.UC_CAMP_PULL_IDLE_STOPPED = false
		end
		_G.UC_MOVEMENT_MODE = 'CAMP_PULL'
		_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_CAMP_PULL_RESERVED'
		_G.UC_MOVEMENT_OWNER = 'camp_puller'
		scheduler.action_timeline_log('CAMP_PULL_MOVEMENT_RESERVED', {
			state = pull_status.state,
			reason = pull_status.reason,
			target = pull_status.target_name,
			target_id = pull_status.target_id,
			camp_distance = pull_status.camp_distance,
			target_distance = pull_status.target_distance,
		}, ('camp_pull_movement_reserved:%s:%d'):format(
			tostring(pull_status.state or ''),
			tonumber(pull_status.target_id) or 0
		), 0.5)
		return false, 'MOVE_COORD_CAMP_PULL_RESERVED'
	end
	_G.UC_CAMP_PULL_IDLE_STOPPED = false
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
	local formation_runtime = require('uc_formation_runtime')
	local formation_observation = formation_runtime.observe(now)
	local reaction_lock = rawget(_G, 'UC_REACTION_LOCK')
	if type(reaction_lock) == 'table' then
		if reaction_lock.turn_applied ~= true then
			scheduler.apply_reaction_response(reaction_lock)
		end
		if require('uc_reaction_runtime').owns_movement(reaction_lock) then
			return scheduler.apply_reaction_movement(reaction_lock, formation_runtime)
		end
		if require('uc_reaction_runtime').blocks_movement(reaction_lock) then
			formation_runtime.stop('FORMATION_REACTION_HOLD')
			_G.UC_MOVEMENT_MODE = 'REACTION_HOLD'
			_G.UC_MOVEMENT_BLOCK_REASON = 'MOVE_COORD_REACTION_HOLD'
			return false, 'MOVE_COORD_REACTION_HOLD'
		end
	end
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
		formation_runtime.stop('FORMATION_CAST_FREEZE_PREP')
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
		local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				run = windower.ffxi.run,
				intent = intent,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_VALIDATE = {
			ok = _intent_ok and true or false,
			reason = _intent_reason,
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
		formation_runtime.stop('FORMATION_PULL_CAST_HOLD')
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
		local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				run = windower.ffxi.run,
				intent = intent,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_CAST_HOLD_VALIDATE = {
			ok = _intent_ok and true or false,
			reason = _intent_reason,
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
		formation_runtime.stop('FORMATION_PULL_SPELL_WAIT')
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
		local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				run = windower.ffxi.run,
				intent = intent,
			})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_PULL_SPELL_WAIT_VALIDATE = {
			ok = _intent_ok and true or false,
			reason = _intent_reason,
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
		formation_runtime.stop('FORMATION_CASTING_STATUS')
		scheduler.apply_cast_movement_hold('MOVE_COORD_CASTING_STATUS', now)
		return false, 'MOVE_COORD_CASTING_STATUS'
	end
	local ast = action_state()
	if tostring(ast.last_send_kind or '') == 'spell' and now < (tonumber(ast.cooldown_until) or 0) then
		formation_runtime.stop('FORMATION_CAST_FREEZE_COOLDOWN')
		scheduler.apply_cast_movement_hold('MOVE_COORD_CAST_FREEZE_COOLDOWN', now)
		return false, 'MOVE_COORD_CAST_FREEZE_COOLDOWN'
	end
	if action_is_acting() and tostring(ast.last_send_kind or '') == 'spell' then
		formation_runtime.stop('FORMATION_CASTING_ACTION')
		scheduler.apply_cast_movement_hold('MOVE_COORD_CASTING_ACTION', now)
		return false, 'MOVE_COORD_CASTING_ACTION'
	end
	local formation_acted, formation_reason, formation_owns = formation_runtime.run_tick(formation_observation)
	if formation_owns then
		_G.UC_MOVEMENT_MODE = 'FORMATION'
		_G.UC_MOVEMENT_BLOCK_REASON = formation_reason
		_G.UC_MOVEMENT_OWNER = 'scheduler_formation'
		_G.UC_MOVEMENT_LOCK_UNTIL = now_s() + 0.40
		return formation_acted, formation_reason
	end
	local ok = false
	local movement_executor = require('uc_scheduler_movement_facade').build({
		dispatcher = require('uc_scheduler_dispatcher'),
		run = windower.ffxi.run,
		turn = windower.ffxi.turn,
	})
	local ok_call, call_err = pcall(function()
		ok = combat_core.apply_movement_for_scheduler(s, movement_executor) == true
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

local function get_party_members(ctx)
	local out = {}
	local party = type(ctx) == 'table' and ctx.party or windower.ffxi.get_party()
	local player = type(ctx) == 'table' and ctx.player or windower.ffxi.get_player()
	local coordinate_observed_at = type(ctx) == 'table' and tonumber(ctx.now) or now_s()
	local self_id = player and player.id or 0
	if type(party) ~= 'table' then
		return out
	end
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, key in ipairs(keys) do
		local entry = party[key]
		if entry and entry.mob and entry.mob.id and entry.mob.id ~= 0 then
			local is_self = entry.mob.id == self_id
			local squared_distance = tonumber(entry.mob.distance)
			local distance_yalms = is_self and 0 or (squared_distance and math.sqrt(math.max(0, squared_distance)) or nil)
			local ipc = get_party_state_ipc_entry(entry.mob.id, entry.mob.name)
			local packet_buffs = require('uc_party_buff_tracker').get(entry.mob.id)
			local source = 'party'
			local buff_source = 'missing'
			local hp = tonumber(entry.hp) or 0
			local hpp = tonumber(entry.hpp) or 100
			local mp = tonumber(entry.mp) or 0
			local mpp = tonumber(entry.mpp) or 100
			local max_mp = tonumber(entry.max_mp) or 0
			local max_hp = 0
			if hp > 0 and hpp > 0 then
				max_hp = math.floor((hp / hpp) * 100 + 0.5)
			end
			local buffs = nil
			if type(packet_buffs) == 'table' and type(packet_buffs.buffs) == 'table' then
				buffs = packet_buffs.buffs
				buff_source = 'packet_076'
			end
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
				buffs = player.buffs
				buff_source = 'self_local'
			end
			if ipc then
				source = is_self and 'self_local' or 'ipc'
				hp = tonumber(ipc.hp) or hp
				hpp = tonumber(ipc.hpp) or hpp
				max_hp = tonumber(ipc.max_hp) or max_hp
				mp = tonumber(ipc.mp) or mp
				max_mp = tonumber(ipc.max_mp) or max_mp
				mpp = tonumber(ipc.mpp) or mpp
				if buffs == nil and type(ipc.buffs) == 'table' then
					buffs = ipc.buffs
					buff_source = 'ipc'
				end
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
				buffs = player.buffs
				buff_source = 'self_local'
			end
			out[#out + 1] = {
				id = entry.mob.id,
				name = entry.mob.name,
				x = entry.mob.x,
				y = entry.mob.y,
				z = entry.mob.z,
				coordinate_observed_at = coordinate_observed_at,
				distance_yalms = distance_yalms,
				is_self = is_self,
				spawn_type = entry.mob.spawn_type,
				is_npc = entry.mob.is_npc == true,
				hpp = hpp,
				hp = hp,
				max_hp = max_hp,
				mp = mp,
				mpp = mpp,
				max_mp = max_mp,
				buffs = buffs,
				source = source,
				buff_source = buff_source,
				charmed = entry.mob.charmed == true,
			}
		end
	end
	return out
end

local function get_live_party_member_by_id(target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return nil
	end
	for _, member in ipairs(get_party_members()) do
		if tonumber(member.id) == tid then
			return member
		end
	end
	return nil
end

function scheduler.validate_cure_target(selected)
	return require('uc_cure_target_safety').validate(selected, {
		get_mob_by_id = windower.ffxi.get_mob_by_id,
		get_party_member_by_id = get_live_party_member_by_id,
		sleep_status = sleep_status,
	})
end

local function p1_build_party_id_set()
	local _, id_set = require('uc_targeting_common').get_friendly_combat_member_ids()
	return id_set
end

local function p1_prime_unclaimed_party_aggressive_ok(settings, mob, party_ids)
	if not bool_setting(uc_scheduler_config.combat_prime(settings), false) then
		return false
	end
	if not mob or (tonumber(mob.claim_id) or 0) ~= 0 then
		return false
	end
	if (tonumber(mob.status) or 0) ~= 1 then
		return false
	end
	return uc_targeting_common.mob_targets_friendly_member(mob, party_ids, now_s())
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

local function sch_spell_ready(name, target_id, mp_multiplier)
	local multiplier = tonumber(mp_multiplier)
	if multiplier ~= 0.5 and multiplier ~= 1.0 and multiplier ~= 2.0 then
		error('Scholar spell readiness requires an exact supported MP multiplier')
	end
	local sp = get_spell_resource(name)
	if not sp then return false, 'BLOCK_DEFENSIVE_UNKNOWN_SPELL', 'spell' end
	local known_ok, known_reason = spell_known_and_usable(sp)
	if not known_ok then return false, known_reason, 'spell' end
	local recasts = windower.ffxi.get_spell_recasts() or {}
	if (recasts[sp.recast_id] or 0) > 0 then
		return false, 'BLOCK_DEFENSIVE_RECAST', 'spell'
	end
	local player = windower.ffxi.get_player()
	if not player or not player.vitals then
		return false, 'BLOCK_DEFENSIVE_NO_PLAYER', 'spell'
	end
	local required_mp = math.ceil((tonumber(sp.mp_cost) or 0) * multiplier)
	if (tonumber(player.vitals.mp) or 0) < required_mp then
		return false, 'BLOCK_DEFENSIVE_NO_MP', 'spell'
	end
	return true, '', 'spell'
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
	local configured_max_range = scheduler.sleep_max_target_distance(settings)
	local sleep_spells = scheduler.sleep_spell_list_from_settings(settings)
	for index, spell_name in ipairs(sleep_spells) do
		local sp = get_spell_resource(spell_name)
		local ok_ready, ready_reason, action_kind = action_ready(spell_name, target_id)
		if ok_ready and action_kind == 'spell' and sp then
			local max_range = action_effective_range(sp.range)
			local effective_max_range = max_range
			if effective_max_range <= 0 or effective_max_range > configured_max_range then
				effective_max_range = configured_max_range
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
		local eid = require('uc_scheduler_enemy_effect_state').spell_effect_id(
			windower.addon_path,
			tonumber(sp and sp.id) or 0
		)
		if eid > 0 then
			out[eid] = true
		end
	end
	return out
end

function scheduler.observe_local_sleep_action(act, player_id, at)
	if type(act) ~= 'table' or tonumber(act.actor_id) ~= tonumber(player_id) or tonumber(act.category) ~= 4 then
		return 0
	end
	local spell = res.spells and res.spells[tonumber(act.param) or 0] or nil
	local spell_name = tostring(spell and spell.en or '')
	if spell_name == '' or not scheduler.is_sleep_spell_name(get_settings(), spell_name) then
		return 0
	end
	local marked = 0
	local now = tonumber(at) or now_s()
	for _, target in ipairs(type(act.targets) == 'table' and act.targets or {}) do
		local tid = tonumber(target and target.id) or 0
		local successful = false
		for _, action in ipairs(type(target and target.actions) == 'table' and target.actions or {}) do
			local message_id = tonumber(action and (action.message or action.message_id)) or 0
			if scheduler.spell_effect_gain_messages[message_id] == true then
				successful = true
				break
			end
		end
		if tid > 0 and successful then
			scheduler.mark_sleep_target_suppressed(tid, spell_name, now)
			marked = marked + 1
		end
	end
	return marked
end

function scheduler.handle_local_spell_finish_action(act, player_id, observed_at)
	if type(act) ~= 'table'
		or tonumber(act.actor_id) ~= tonumber(player_id)
		or tonumber(act.category) ~= 4 then
		return false, 'not_local_spell_finish'
	end
	local st = action_state()
	if type(st) ~= 'table' then
		error('scheduler action state must be a table')
	end
	local active, active_reason = scheduler.local_spell_cast_token_active(st)
	if not active then
		return false, active_reason
	end
	local active_spell_name = tostring(st.last_action_name or '')
	local active_provider = tostring(st.last_action_provider or '')
	if active_spell_name == '' then
		error('active scheduler spell name must not be empty')
	end
	local active_spell = get_spell_resource(active_spell_name)
	if type(active_spell) ~= 'table' then
		error('active scheduler spell resource missing: ' .. active_spell_name)
	end
	local packet_spell_id = tonumber(act.param)
	if packet_spell_id == nil then
		error('local spell finish action is missing a numeric spell id')
	end
	local active_spell_id = tonumber(active_spell.id)
	if active_spell_id == nil then
		error('active scheduler spell resource id must be numeric: ' .. active_spell_name)
	end
	if packet_spell_id ~= active_spell_id then
		return false, 'spell_mismatch'
	end
	local active_target_id = tonumber(st.last_target_id)
	if active_target_id == nil or active_target_id <= 0 then
		error('active scheduler spell target id must be a positive number: ' .. active_spell_name)
	end
	if type(act.targets) ~= 'table' then
		error('local spell finish action targets must be a table')
	end
	local target_matched = false
	local result_message_id
	local result_message_param
	for _, target in ipairs(act.targets) do
		if tonumber(target and target.id) == active_target_id then
			target_matched = true
			if type(target.actions) ~= 'table' or type(target.actions[1]) ~= 'table' then
				error('matching local spell finish target is missing action results')
			end
			local result = target.actions[1]
			result_message_id = tonumber(result.message)
			result_message_param = tonumber(result.param)
			if result_message_id == nil or result_message_param == nil then
				error('local spell finish result message and param must be numeric')
			end
			break
		end
	end
	if not target_matched then
		return false, 'target_mismatch'
	end
	local now = tonumber(observed_at)
	if now == nil then
		error('local spell finish observation time must be numeric')
	end
	action_mark_packet_end({
		message_id = result_message_id,
		message_param = result_message_param,
	})
	local release_meta = {
		message_id = result_message_id,
		message_param = result_message_param,
		spell_name = active_spell_name,
		completion_reason = 'cast_complete_action_packet',
		release_reason = 'cast_complete_action_packet',
	}
	local cleared = scheduler.clear_local_defensive_spell_success(release_meta)
	if not cleared then
		cleared = scheduler.clear_local_spell_success(release_meta)
	end
	if not cleared then
		return false, require('uc_scheduler_action_state').last_completion_ignore_reason(scheduler)
	end
	scheduler.p1_pending_mark_complete(now, ('spell_action_packet_finish_%d'):format(packet_spell_id))
	if active_provider == 'camp_puller' then
		scheduler.providers.camp_puller.note_action_result(
			true,
			now,
			camp_pulling_config()
		)
	end
	if tostring(_G.UC_MOVEMENT_OWNER or '') == 'scheduler' then
		local current_lock_until = tonumber(_G.UC_MOVEMENT_LOCK_UNTIL)
		if current_lock_until == nil then
			error('scheduler-owned UC_MOVEMENT_LOCK_UNTIL must be numeric during local spell completion')
		end
		_G.UC_MOVEMENT_LOCK_UNTIL = math.min(current_lock_until, now + 0.2)
	end
	if scheduler.defensive_spell_waiting == true then
		scheduler.clear_defensive_spell_wait_state()
	end
	local phase = scheduler.phase1
	if type(phase) ~= 'table' then
		error('scheduler phase1 state must be a table')
	end
	if tonumber(phase.tank_pending_target_id) and tonumber(phase.tank_pending_target_id) ~= 0 then
		scheduler.p1_clear_tank_spell_wait_state(phase)
	end
	return true, 'cast_complete_action_packet'
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

local function sch_select_cure_spell(member, mp_multiplier)
	local s = get_settings()
	local min_tier = tonumber(scheduler.active_value_or_flat(
		'config.defensive.cure.min_tier', s.def_heal_min_tier_cure
	)) or 2
	local max_tier = tonumber(scheduler.active_value_or_flat(
		'config.defensive.cure.max_tier', s.def_heal_max_tier_cure
	)) or 4
	min_tier = math.max(1, math.min(min_tier, 4))
	max_tier = math.max(min_tier, math.min(max_tier, 4))
	local wanted_tier = cure_tier_for_missing_hp(estimate_missing_hp(member), max_tier)
	local last_reason = 'BLOCK_DEFENSIVE_NO_CURE'
	for tier = wanted_tier, min_tier, -1 do
		local cure = cure_by_tier[tier]
		local ready, reason = sch_spell_ready(cure.name, member.id, mp_multiplier)
		if ready then return cure.name, '' end
		last_reason = reason
	end
	return nil, last_reason
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

local attempt_allowed

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

local curaga_by_tier = {
	[1] = 'Curaga',
	[2] = 'Curaga II',
	[3] = 'Curaga III',
	[4] = 'Curaga IV',
	[5] = 'Curaga V',
}

local curing_waltz_by_tier = {
	[1] = 'Curing Waltz',
	[2] = 'Curing Waltz II',
	[3] = 'Curing Waltz III',
	[4] = 'Curing Waltz IV',
	[5] = 'Curing Waltz V',
}

local function player_has_named_buff(player, wanted_name)
	if type(player) ~= 'table' or type(player.buffs) ~= 'table' then
		return nil
	end
	local wanted = tostring(wanted_name or ''):lower()
	for _, buff_id in ipairs(player.buffs) do
		local buff = res.buffs[tonumber(buff_id) or 0]
		if buff and tostring(buff.en or ''):lower() == wanted then
			return true
		end
	end
	return false
end

local function waltz_ready(name, target_id, tp_reserve)
	local ready, reason, kind = action_ready(name, target_id)
	local player = windower.ffxi.get_player()
	local ja = get_ja_resource(name)
	if type(player) ~= 'table' or type(player.buffs) ~= 'table' or type(player.vitals) ~= 'table' then
		return false, 'WALTZ_ACTOR_STATUS_UNKNOWN'
	end
	if type(ja) ~= 'table' then return false, 'WALTZ_RESOURCE_UNKNOWN' end
	local result = require('uc_defensive_healing').evaluate_waltz_resource_gate({
		action_ready = ready,
		action_reason = reason,
		action_kind = kind,
		player_buffs = player.buffs,
		buff_resources = res.buffs,
		ja_resource = ja,
		current_tp = player.vitals.tp,
		tp_reserve = tp_reserve,
	})
	return result.ready, result.reason, result
end

local function member_within_action_range(member, max_range)
	if type(member) ~= 'table' then
		return false
	end
	if member.is_self == true then
		return true
	end
	local distance = tonumber(member.distance_yalms)
	return distance ~= nil and distance <= max_range
end

local function choose_curaga_action(plan)
	local wanted_tier = cure_tier_for_missing_hp(tonumber(plan.maximum_missing_hp) or 0, 5)
	for tier = wanted_tier, 1, -1 do
		local name = curaga_by_tier[tier]
		if name and spell_ready(name) then
			return name
		end
	end
	return nil
end

local function choose_curing_waltz_action(member, tp_reserve, now)
	local healing = require('uc_defensive_healing')
	local wanted_tier = cure_tier_for_missing_hp(estimate_missing_hp(member), 5)
	for tier = wanted_tier, 1, -1 do
		local name = curing_waltz_by_tier[tier]
		local action_range = healing.mechanics.curing_waltz_ranges[name]
		if name and action_range and member_within_action_range(member, action_range) then
			local ready, reason, detail = waltz_ready(name, member.id, tp_reserve)
			if ready then
				if attempt_allowed('cure', member.name, name, now, 2.5) then
					detail.target_range = action_range
					return name, detail
				end
				return nil
			end
			log_def_sched(('WALTZ_REJECT action="%s" target="%s" reason=%s'):format(name, tostring(member.name or ''), tostring(reason)))
		end
	end
	return nil
end

local function choose_divine_waltz_action(plan, tp_reserve, critical_hpp)
	local order = { 'Divine Waltz', 'Divine Waltz II' }
	if tonumber(plan.lowest_covered_hpp) <= tonumber(critical_hpp) then
		order = { 'Divine Waltz II', 'Divine Waltz' }
	end
	for _, name in ipairs(order) do
		local ready, reason, detail = waltz_ready(name, plan.anchor.id, tp_reserve)
		if ready then
			return name, detail
		end
		log_def_sched(('WALTZ_REJECT action="%s" target="%s" reason=%s'):format(name, tostring(plan.anchor_name or ''), tostring(reason)))
	end
	return nil
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

attempt_allowed = function(kind, member_name, action_name, now, min_gap)
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

local function build_defensive_candidates(ctx)
	local s = type(ctx) == 'table' and ctx.settings or get_settings()
	local members = get_party_members(ctx)
	local out = {
		cure = nil,
		debuff = nil,
		buff = nil,
		overwrite = nil,
	}
	local now = type(ctx) == 'table' and ctx.now or now_s()
	local ignore_trusts = bool_setting(scheduler.active_value_or_flat('config.defensive.cure.ignore_trusts', s.def_heal_ignore_trusts), true)
	local cure_enabled = bool_setting(scheduler.active_value_or_flat('config.defensive.cure.enabled', s.defensive_cure_enabled), true)
	local curaga_enabled = bool_setting(scheduler.active_value_or_flat('config.defensive.cure.curaga.enabled', s.defensive_curaga_enabled), false)
	local curaga_min_targets = tonumber(scheduler.active_value_or_flat('config.defensive.cure.curaga.min_targets', s.defensive_curaga_min_targets)) or 3
	local waltz_enabled = bool_setting(scheduler.active_value_or_flat('config.defensive.waltz.enabled', s.defensive_waltz_enabled), false)
	local waltz_tp_reserve = tonumber(scheduler.active_value_or_flat('config.defensive.waltz.tp_reserve', s.defensive_waltz_tp_reserve)) or 0
	local divine_min_targets = tonumber(scheduler.active_value_or_flat('config.defensive.waltz.divine_min_targets', s.defensive_divine_waltz_min_targets)) or 3
	if curaga_min_targets < 2 or curaga_min_targets > 6 or curaga_min_targets % 1 ~= 0 then
		error('normalized defensive Curaga minimum targets must be an integer from 2 through 6')
	end
	if waltz_tp_reserve < 0 or waltz_tp_reserve > 3000 or waltz_tp_reserve % 1 ~= 0 then
		error('normalized defensive Waltz TP reserve must be an integer from 0 through 3000')
	end
	if divine_min_targets < 2 or divine_min_targets > 6 or divine_min_targets % 1 ~= 0 then
		error('normalized defensive Divine Waltz minimum targets must be an integer from 2 through 6')
	end
	local na_members = {}
	local aoe_members = {}
	local injured_members = {}
	local injured_ids = {}
	local missing_gate = math.max(0, tonumber(scheduler.active_value_or_flat('config.defensive.cure.min_missing_hp', s.def_heal_min_missing_hp)) or 250)
	local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', s.defensive_critical_hpp)) or 35
	local actor_silenced = waltz_enabled and player_has_named_buff(windower.ffxi.get_player(), 'silence') == true

	if bool_setting(scheduler.active_value_or_flat('config.defensive.buffs.enabled', s.defensive_buff_enabled), true) then
		log_def_sched(('BUFF_SCAN mode=%s buffs="%s" targeted="%s" members=%d'):format(
			bool_setting(scheduler.active_value_or_flat('config.defensive.buffs.self_only', s.defensive_buff_self_only), true) and 'self_only' or 'party',
			tostring(scheduler.active_value_or_flat('config.defensive.buffs.list', s.defensive_buffs) or ''),
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
			na_members[#na_members + 1] = m
			if m.charmed == true then
				log_def_sched(('CURE_REJECT target="%s" reason=CHARMED_TARGET'):format(tostring(m.name or '?')))
			elseif (tonumber(m.hpp) or 0) > 0 then
				aoe_members[#aoe_members + 1] = m
			end
			if cure_enabled and m.charmed ~= true and (tonumber(m.hpp) or 0) > 0 and (tonumber(m.hpp) or 100) < 95 then
				local missing_hp = estimate_missing_hp(m)
				if missing_hp >= missing_gate then
					injured_members[#injured_members + 1] = m
					injured_ids[#injured_ids + 1] = m.id
					if in_party_cast_range(m) then
						log_def_sched(('CURE_CANDIDATE target="%s" hp=%d hpp=%d missing=%d gate=%d in_range=1'):format(
							tostring(m.name or '?'), tonumber(m.hp) or 0, tonumber(m.hpp) or 0,
							missing_hp, missing_gate
						))
						local spell = actor_silenced and nil or choose_cure_spell(m)
						local ready = spell and spell_ready(spell) or false
						if ready and attempt_allowed('cure', m.name, spell, now, 2.5) then
							local candidate = {
								type = 'cure',
								spell = spell,
								action_name = spell,
								action_kind = 'spell',
								target = m,
								member_prio = member_priority(m),
								danger = danger_level(m.hpp),
								prio = member_priority(m),
							}
							if cure_better(candidate, out.cure) then
								out.cure = candidate
								log_def_sched(('CURE_ACCEPT target="%s" action="%s" kind=spell hp=%d hpp=%d missing=%d gate=%d'):format(
									tostring(m.name or '?'), spell, tonumber(m.hp) or 0, tonumber(m.hpp) or 0,
									missing_hp, missing_gate
								))
							end
						elseif actor_silenced then
							log_def_sched(('CURE_REJECT target="%s" reason=SPELL_SILENCED_WALTZ_ENABLED'):format(tostring(m.name or '?')))
						elseif not spell then
							log_def_sched(('CURE_REJECT target="%s" reason=NO_SPELL hp=%d hpp=%d missing=%d gate=%d'):format(
								tostring(m.name or '?'), tonumber(m.hp) or 0, tonumber(m.hpp) or 0, missing_hp, missing_gate
							))
						elseif not ready then
							log_def_sched(('CURE_REJECT target="%s" reason=SPELL_NOT_READY spell="%s" hp=%d hpp=%d missing=%d gate=%d'):format(
								tostring(m.name or '?'), tostring(spell), tonumber(m.hp) or 0, tonumber(m.hpp) or 0, missing_hp, missing_gate
							))
						else
							log_def_sched(('CURE_REJECT target="%s" reason=ATTEMPT_THROTTLE spell="%s" hp=%d hpp=%d missing=%d gate=%d'):format(
								tostring(m.name or '?'), tostring(spell), tonumber(m.hp) or 0, tonumber(m.hpp) or 0, missing_hp, missing_gate
							))
						end
					end
				else
					log_def_sched(('CURE_REJECT target="%s" reason=MISSING_BELOW_GATE hp=%d hpp=%d missing=%d gate=%d'):format(
						tostring(m.name or '?'), tonumber(m.hp) or 0, tonumber(m.hpp) or 0, missing_hp, missing_gate
					))
				end
			end
		end
	end

	local healing = require('uc_defensive_healing')
	local function aoe_action_from_plan(name, kind, plan, waltz_detail)
		local covered_prio = 99
		local covered = {}
		for _, id in ipairs(plan.covered_ids) do covered[tonumber(id) or 0] = true end
		for _, member in ipairs(aoe_members) do
			if covered[tonumber(member.id) or 0] then
				covered_prio = math.min(covered_prio, member_priority(member))
			end
		end
		return {
			type = 'cure',
			spell = kind == 'spell' and name or nil,
			action_name = name,
			action_kind = kind,
			target = plan.anchor,
			member_prio = covered_prio,
			danger = danger_level(plan.lowest_covered_hpp),
			prio = covered_prio,
			aoe = true,
			covered_ids = plan.covered_ids,
			covered_names = plan.covered_names,
			coverage_count = plan.coverage_count,
			aggregate_missing_hp = plan.aggregate_missing_hp,
			lowest_covered_hpp = plan.lowest_covered_hpp,
			maximum_missing_hp = plan.maximum_missing_hp,
			aoe_radius = plan.radius,
			target_range = plan.target_range,
			anchor_distance = plan.anchor_distance,
			action_detail = waltz_detail,
		}
	end
	local function admit_aoe(candidate)
		local allowed, reason = healing.should_admit_aoe(out.cure, candidate, critical_hpp)
		if not allowed then return false, reason end
		out.cure = candidate
		return true, ''
	end
	if cure_enabled and waltz_enabled then
		for _, member in ipairs(injured_members) do
			local name, detail = choose_curing_waltz_action(member, waltz_tp_reserve, now)
			if name then
				local candidate = {
					type = 'cure', action_name = name, action_kind = 'ja', target = member,
					member_prio = member_priority(member), danger = danger_level(member.hpp), prio = member_priority(member),
					target_range = detail.target_range, action_detail = detail,
				}
				if cure_better(candidate, out.cure) then
					out.cure = candidate
					log_def_sched(('CURE_ACCEPT target="%s" action="%s" kind=ja hp=%d hpp=%d tp_cost=%d tp_reserve=%d'):format(
						tostring(member.name or '?'), name, tonumber(member.hp) or 0, tonumber(member.hpp) or 0,
						detail.tp_cost, detail.tp_reserve
					))
				end
			end
		end
	end

	if cure_enabled and curaga_enabled and not actor_silenced then
		local result = healing.plan_aoe({
			now = now,
			members = aoe_members,
			injured_recipient_ids = injured_ids,
			minimum_targets = curaga_min_targets,
			mechanics = healing.mechanics.curaga,
			member_priority = member_priority,
			estimate_missing_hp = estimate_missing_hp,
		})
		if result.state == 'ready' then
			local name = choose_curaga_action(result.selected)
			if name and attempt_allowed('cure', result.selected.anchor_name, name, now, 2.5) then
				local candidate = aoe_action_from_plan(name, 'spell', result.selected)
				local admitted, admit_reason = admit_aoe(candidate)
				if admitted then
					log_def_sched(('AOE_HEAL_ACCEPT action="%s" kind=spell anchor="%s" anchor_id=%d anchor_dist=%.2f radius=%.1f coverage=%d covered="%s" aggregate_missing=%d lowest_hpp=%d'):format(
						name, result.selected.anchor_name, result.selected.anchor_id, result.selected.anchor_distance,
						result.selected.radius, result.selected.coverage_count, table.concat(result.selected.covered_names, '|'),
						result.selected.aggregate_missing_hp, result.selected.lowest_covered_hpp
					))
				else
					log_def_sched(('AOE_HEAL_REJECT family=Curaga action="%s" reason=%s'):format(name, admit_reason))
				end
			elseif not name then
				log_def_sched('AOE_HEAL_REJECT family=Curaga reason=NO_READY_CURAGA')
			end
		else
			log_def_sched(('AOE_HEAL_REJECT family=Curaga reason=%s'):format(tostring(result.blocker)))
		end
	end

	if cure_enabled and waltz_enabled then
		local result = healing.plan_aoe({
			now = now,
			members = aoe_members,
			injured_recipient_ids = injured_ids,
			minimum_targets = divine_min_targets,
			mechanics = healing.mechanics.divine_waltz,
			member_priority = member_priority,
			estimate_missing_hp = estimate_missing_hp,
		})
		if result.state == 'ready' then
			local name, detail = choose_divine_waltz_action(result.selected, waltz_tp_reserve, critical_hpp)
			if name and attempt_allowed('cure', result.selected.anchor_name, name, now, 2.5) then
				detail.target_range = result.selected.target_range
				local candidate = aoe_action_from_plan(name, 'ja', result.selected, detail)
				local admitted, admit_reason = admit_aoe(candidate)
				if admitted then
					log_def_sched(('AOE_HEAL_ACCEPT action="%s" kind=ja anchor="%s" anchor_id=%d anchor_dist=%.2f radius=%.1f coverage=%d covered="%s" aggregate_missing=%d lowest_hpp=%d tp_cost=%d tp_reserve=%d'):format(
						name, result.selected.anchor_name, result.selected.anchor_id, result.selected.anchor_distance,
						result.selected.radius, result.selected.coverage_count, table.concat(result.selected.covered_names, '|'),
						result.selected.aggregate_missing_hp, result.selected.lowest_covered_hpp, detail.tp_cost, detail.tp_reserve
					))
				else
					log_def_sched(('AOE_HEAL_REJECT family=DivineWaltz action="%s" reason=%s'):format(name, admit_reason))
				end
			end
		else
			log_def_sched(('AOE_HEAL_REJECT family=DivineWaltz reason=%s'):format(tostring(result.blocker)))
		end
	end
	out.debuff = require('uc_scheduler_na_policy').choose_status_removal(na_members, {
		enabled = bool_setting(scheduler.active_value_or_flat('config.defensive.na.enabled', s.defensive_na_enabled), true),
		limit_enabled = bool_setting(scheduler.active_value_or_flat('config.defensive.na.limit_enabled', s.defensive_na_limit_enabled), false),
		priority = scheduler.active_value_or_flat('config.defensive.na.priority', s.defensive_na_priority),
		now = now,
	}, {
		buffs = res.buffs,
		debuff_map = debuff_map,
		status_removal_priority = status_removal_priority,
		known_status_keys = known_status_removal_keys,
		debuff_spell_for_buff_id = debuff_spell_for_buff_id,
		normalize_status_removal_key = normalize_status_removal_key,
		action_ready = action_ready,
		attempt_allowed = attempt_allowed,
		in_party_cast_range = in_party_cast_range,
		spell_status_removal_blocked = function()
			return waltz_enabled and actor_silenced
		end,
		status_removal_alternative_in_range = function(member)
			return waltz_enabled and member.charmed ~= true and (tonumber(member.hpp) or 0) > 0
				and member_within_action_range(member, healing.mechanics.healing_waltz_range)
		end,
		status_removal_alternative = function(member, _buff_id, status_key, mapped_spell)
			if not waltz_enabled or member.charmed == true or (tonumber(member.hpp) or 0) <= 0 then return nil end
			if not healing.healing_waltz_supports(status_key, mapped_spell) then
				log_def_sched(('HEALING_WALTZ_REJECT target="%s" status=%s reason=HEALING_WALTZ_UNSUPPORTED_STATUS'):format(tostring(member.name or ''), tostring(status_key)))
				return nil
			end
			if not member_within_action_range(member, healing.mechanics.healing_waltz_range) then return nil end
			local ready, reason, detail = waltz_ready('Healing Waltz', member.id, waltz_tp_reserve)
			if not ready then
				log_def_sched(('HEALING_WALTZ_REJECT target="%s" status=%s reason=%s'):format(tostring(member.name or ''), tostring(status_key), tostring(reason)))
				return nil
			end
			detail.target_range = healing.mechanics.healing_waltz_range
			return { action_name = 'Healing Waltz', action_kind = 'ja', target_range = detail.target_range, tp_cost = detail.tp_cost, tp_reserve = detail.tp_reserve, recast_id = detail.recast_id }
		end,
		member_priority = member_priority,
		pri_default = pri_default,
	})
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
	local s = get_settings()
	local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', s.defensive_critical_hpp)) or 35
	return require('uc_scheduler_na_policy').choose_defensive_action(c, critical_hpp)
end


choose_cure_spell = function(member)
	local s = get_settings()
	local max_available = available_cure_tier_max()
	if max_available <= 0 then
		return nil
	end
	local min_tier = tonumber(scheduler.active_value_or_flat('config.defensive.cure.min_tier', s.def_heal_min_tier_cure)) or 2
	local max_tier_cfg = tonumber(scheduler.active_value_or_flat('config.defensive.cure.max_tier', s.def_heal_max_tier_cure)) or 4
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
	if hpp <= (tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', s.defensive_critical_hpp)) or 35) then
		return get_usable_cure_from_tier(max_tier, 1)
	end
	return nil
end


local function p1_number(v, default_value)
	return require('uc_scheduler_numeric_utils').p1_number(v, default_value)
end

local function p1_clamp_urgency(v)
	return require('uc_scheduler_numeric_utils').p1_clamp_urgency(v)
end

local function p1_build_ctx(settings)
	local ctx = require('uc_scheduler_context').build(settings, scheduler.phase1, {
		get_player = windower.ffxi.get_player,
		get_mob_by_target = windower.ffxi.get_mob_by_target,
		get_mob_by_index = windower.ffxi.get_mob_by_index,
		get_party = windower.ffxi.get_party,
		get_mob_array = windower.ffxi.get_mob_array,
		now = now_s,
	})
	local pet_tp_state = require('uc_pet_tp_state')
	local pet_tp_present = ctx.pet_present == true and ctx.pet_index > 0
	pet_tp_state.observe_pet(
		scheduler.pet_tp_state,
		pet_tp_present,
		ctx.pet_id,
		ctx.pet_index
	)
	if pet_tp_present then
		ctx.pet_tp = pet_tp_state.current_tp(
			scheduler.pet_tp_state,
			ctx.pet_id,
			ctx.pet_index
		)
	end
	local ability_recasts = windower.ffxi.get_ability_recasts()
	ctx.ability_recasts_present = type(ability_recasts) == 'table'
	if ctx.ability_recasts_present then
		ctx.ability_recasts = ability_recasts
	end
	ctx.engine_enabled = rawget(_G, 'Start_Engine') == true
	ctx.maintenance_enabled = domain_ownership.is_enabled('maintenance')
	ctx.defensive_enabled = domain_ownership.is_enabled('defensive')
	return ctx
end

local p1_combat_helpers = {}

function scheduler.p1_brd_lane_blocks_proposal(proposal, lane_reserved)
	if lane_reserved ~= true or type(proposal) ~= 'table' then
		return false
	end
	if tostring(proposal.provider or '') == 'maintenance_brd' then
		return false
	end
	return true
end

function scheduler.p1_camp_lane_blocks_proposal(proposal, lane_reserved)
	if lane_reserved ~= true or type(proposal) ~= 'table' then
		return false
	end
	return tostring(proposal.provider or '') ~= 'camp_puller'
end

local function p1_collect_proposals(ctx)
	local out = {}
	local s = ctx.settings or {}
	local defensive_evidence_current = false
	-- 5 Hz domains
	if domain_ownership.is_enabled('combat') then
		scheduler.providers.target_control.collect_target(ctx, out)
		scheduler.providers.combat.collect_engage(ctx, out)
		scheduler.providers.target_control.collect_pull(ctx, out)
		if ctx.geo_creation_preempts_pull ~= true then
			scheduler.providers.camp_puller.collect(ctx, out)
		end
		scheduler.providers.tank_enmity.collect(ctx, out)
		scheduler.providers.combat.collect_sleep(ctx, out)
		scheduler.providers.combat.collect_offense(ctx, out)
		scheduler.providers.combat.collect_ja(ctx, out)
		scheduler.providers.pet_combat.collect(ctx, out)
		scheduler.providers.kei.collect(ctx, out)
	end
	-- 2 Hz defensive
	if domain_ownership.is_enabled('defensive')
		and ctx.now >= (tonumber(s._sched_next_defensive_at) or 0) then
		defensive_evidence_current = true
		scheduler.providers.charm_sleeper.collect(ctx, out)
		scheduler.providers.sleep_waker.collect(ctx, out)
		scheduler.providers.enemy_debuff_maintenance.collect(ctx, out)
		scheduler.providers.enemy_buff_removal.collect(ctx, out)
		scheduler.providers.defensive.collect_internal(ctx, out)
		scheduler.providers.defensive.collect_healbot(ctx, out)
	end
	-- BRD sequencing participates every scheduler tick so lower-band defensive
	-- work cannot enter between song lifecycle transitions. Other maintenance
	-- providers retain the engine's 1 Hz collection cadence.
	local player = ctx.player or {}
	local main_job = tostring(player.main_job or '')
	local sub_job = tostring(player.sub_job or '')
	local maintenance_enabled = domain_ownership.is_enabled('maintenance')
	local defensive_enabled = domain_ownership.is_enabled('defensive')
	local brd_provider_active = maintenance_enabled
		and main_job ~= 'COR'
		and (main_job == 'BRD' or sub_job == 'BRD')
	local sch_fast_tick_active = (maintenance_enabled or defensive_enabled)
		and main_job == 'SCH'
		and (require('uc_sch_runtime').requires_fast_tick()
			or scheduler.providers.sch_maintenance.trace_active())
	local camp_journey_active = scheduler.providers.camp_puller.active()
	local sch_provider_collected = false
	if maintenance_enabled
		and not camp_journey_active
		and (brd_provider_active or sch_fast_tick_active
			or ctx.now >= (tonumber(s._sched_next_maintenance_at) or 0)) then
		scheduler.providers.maintenance.collect(ctx, out)
		scheduler.providers.summoner_maintenance.collect(ctx, out)
		if main_job == 'SCH' then
			ctx.sch_defensive_evidence_current = defensive_evidence_current
			scheduler.providers.sch_maintenance.collect(ctx, out)
			sch_provider_collected = true
		end
		scheduler.providers.geo_maintenance.collect(ctx, out)
	end
	if not sch_provider_collected and not camp_journey_active and main_job == 'SCH'
		and (sch_fast_tick_active or (defensive_enabled and defensive_evidence_current)) then
		ctx.sch_defensive_evidence_current = defensive_evidence_current
		scheduler.providers.sch_maintenance.collect(ctx, out)
	end
	if camp_journey_active then
		for i = #out, 1, -1 do
			local proposal = out[i]
			if scheduler.p1_camp_lane_blocks_proposal(proposal, true) then
				log_def_sched(('CAMP_PULL_ACTION_LANE_HOLD action="%s" provider=%s type=%s reason=camp_journey_active'):format(
					tostring(proposal and proposal.action_name or ''),
					tostring(proposal and proposal.provider or ''),
					tostring(proposal and proposal.action_type or '')
				))
				table.remove(out, i)
			end
		end
	elseif scheduler.providers.geo_maintenance.lane_reserved() then
		local pull_for_enemy = scheduler.providers.geo_maintenance.pull_for_enemy_allowed()
		for i = #out, 1, -1 do
			local proposal = out[i]
			local provider = tostring(proposal and proposal.provider or '')
			local critical_cure = scheduler.p1_is_critical_defensive_proposal(
				ctx.settings,
				proposal
			)
			local allowed = critical_cure
				or (pull_for_enemy and provider == 'camp_puller')
				or (not pull_for_enemy and provider == 'maintenance_geo')
			if not allowed then
				log_def_sched(('GEO_ATOMIC_LANE_HOLD provider=%s reason=%s'):format(
					provider,
					pull_for_enemy and 'awaiting_claimed_enemy' or 'consumable_sequence'
				))
				table.remove(out, i)
			end
		end
	end
	if brd_provider_active and not camp_journey_active then
		local lane_reserved, lane_reason = require('uc_brd_maintenance').action_lane_status()
		if lane_reserved then
			for i = #out, 1, -1 do
				local proposal = out[i]
				if scheduler.p1_brd_lane_blocks_proposal(proposal, true) then
					log_def_sched(('BRD_LANE_HOLD action="%s" provider=%s type=%s reason=%s'):format(
						tostring(proposal.action_name or ''),
						tostring(proposal.provider or ''),
						tostring(proposal.action_type or ''),
						tostring(lane_reason or '')
					))
					table.remove(out, i)
				end
			end
		end
	end
	local sch_lane = require('uc_sch_runtime').lane_status()
	if main_job == 'SCH' and type(s.sch) == 'table' and s.sch.enabled == true then
		for i = 1, #out do
			local proposal = out[i]
			local provider = tostring(proposal and proposal.provider or '')
			local detail = type(proposal and proposal.detail) == 'table' and proposal.detail or nil
			local defensive_type = detail and tostring(detail.def_action_type or '') or ''
			if (provider == 'defensive_internal' or provider == 'defensive_healbot')
				and (defensive_type == 'cure' or defensive_type == 'debuff') then
				log_def_sched(('SCH_DEFENSIVE_PARITY provider=%s type=%s action="%s" target="%s" target_id=%d band=%d lane=%s source=existing_defensive'):format(
					provider,
					defensive_type,
					tostring(proposal.action_name or ''),
					tostring(proposal.target_name or ''),
					tonumber(proposal.target_id) or 0,
					tonumber(proposal.priority_band) or 0,
					tostring(sch_lane.class)
				))
			end
		end
	end
	if sch_lane.reserved then
		local sch_lane_policy = require('uc_sch_lane_policy')
		for i = #out, 1, -1 do
			local proposal = out[i]
			local provider = tostring(proposal and proposal.provider or '')
			local decision = sch_lane_policy.decide(
				sch_lane,
				proposal,
				scheduler.p1_is_critical_defensive_proposal(ctx.settings, proposal),
				provider == 'charm_sleeper'
			)
			if not decision.allowed then
				log_def_sched(('SCH_LANE_HOLD action="%s" provider=%s type=%s lane=%s reason=%s'):format(
					tostring(proposal.action_name or ''),
					provider,
					tostring(proposal.action_type or ''),
					tostring(sch_lane.class),
					decision.reason
				))
				table.remove(out, i)
			elseif decision.preempt then
				proposal._sch_lane_preempt_reason = decision.reason
				log_def_sched(('SCH_LANE_PREEMPT_ELIGIBLE action="%s" provider=%s lane=%s reason=%s'):format(
					tostring(proposal.action_name or ''),
					provider,
					tostring(sch_lane.class),
					decision.reason
				))
			end
		end
	end
	for i = 1, #out do
		local proposal = out[i]
		if type(proposal) == 'table' then
			local provider = tostring(proposal.provider or '')
			local action_type = tostring(proposal.action_type or '')
			local detail = type(proposal.detail) == 'table' and proposal.detail or {}
			if provider == 'defensive_internal' or provider == 'defensive_healbot' then
				if action_type == 'spell' and tostring(detail.def_action_type or '') == 'cure' then
					local event_code = 'SLEEP_WAKE_PROPOSED'
					if tostring(detail.cure_intent or '') ~= 'sleep_wake' then
						local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', ctx.settings and ctx.settings.defensive_critical_hpp)) or 35
						local target_hpp = tonumber(detail.target_hpp or -1) or -1
						event_code = (target_hpp > 0 and target_hpp <= critical_hpp) and 'CRITICAL_CURE_PROPOSED' or 'NONCRITICAL_CURE_PROPOSED'
					end
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

function scheduler.p1_priority_bypasses_engage(proposal)
	return require('uc_scheduler_proposals').priority_bypasses_engage(
		proposal,
		scheduler.PRIORITY_BAND_ENGAGE_BYPASS
	)
end

local function p1_ranker_dependencies()
	return {
		bool_setting = bool_setting,
		phase1 = scheduler.phase1,
		pending_engage_live = scheduler.p1_pending_engage_live,
		pending_engage_state = scheduler.p1_pending_engage_state,
		priority_bypasses_engage = scheduler.p1_priority_bypasses_engage,
		timeline_log = scheduler.action_timeline_log,
		pending_is_live_state = scheduler.p1_pending_is_live_state,
		validate_engage_duplicate_retry = scheduler.p1_validate_engage_duplicate_retry,
		duplicate_suppressed = scheduler.p1_duplicate_suppressed,
		get_locks = scheduler.p1_get_locks,
		hard_lock_reject = scheduler.p1_hard_lock_reject,
		reaction_blocks_proposal = require('uc_reaction_runtime').blocks_proposal,
		get_reaction_lock = function()
			if scheduler.providers.camp_puller.active() then
				return nil
			end
			return rawget(_G, 'UC_REACTION_LOCK')
		end,
		debug_enabled = uc_scheduler_config.debug_enabled,
		publish_last_action = function(value)
			_G.UC_LAST_SCHED_ACTION = value
		end,
		is_critical_defensive_proposal = scheduler.p1_is_critical_defensive_proposal,
		encounter_validate_proposal = require('uc_encounter_runtime').validate_proposal,
		engage_dispatch_method = scheduler.ENGAGE_DISPATCH_METHOD_ATTACK_ON,
	}
end

local function p1_validate_proposal(ctx, proposal)
	return require('uc_scheduler_ranker').validate_proposal(
		ctx,
		proposal,
		p1_ranker_dependencies()
	)
end

local function p1_rank(ctx, proposals)
	return require('uc_scheduler_ranker').rank(ctx, proposals, p1_ranker_dependencies())
end

local function p1_build_dispatch_plan(ctx, selected)
	return require('uc_scheduler_dispatch_plan').p1_build_dispatch_plan(scheduler, ctx, selected, p1_number)
end

local function p1_revalidate_plan_commit(ctx, selected, plan)
	if recovery_hold.current() then
		return false, recovery_hold.BLOCK_REASON
	end
	local valid, reason = require('uc_scheduler_dispatch_plan').p1_revalidate_plan_commit(
		scheduler,
		ctx,
		selected,
		plan,
		p1_number,
		windower,
		combat_core
	)
	if not valid then
		return false, reason
	end
	local policy_ok, policy_reason = require('uc_encounter_runtime').validate_proposal(ctx, selected)
	if policy_ok ~= true then
		return false, policy_reason
	end
	return scheduler.validate_cure_target(selected)
end

function scheduler.p1_set_pending_globals()
	return scheduler_pending.p1_set_pending_globals(scheduler, _G)
end

function scheduler.p1_build_lock_summary(ctx, locks)
	return scheduler_locks.p1_build_lock_summary(ctx, locks, scheduler.p1_get_locks)
end

function scheduler.record_dispatch(ctx)
	return require('uc_scheduler_pending_record').record_dispatch(scheduler, ctx, p1_number)
end

function scheduler.p1_pending_mark_complete(now, result_code)
	return scheduler_pending.p1_pending_mark_complete(scheduler, now, result_code)
end

function scheduler.p1_pending_mark_failed(now, result_code, retry_delay)
	return scheduler_pending.p1_pending_mark_failed(scheduler, now, result_code, retry_delay)
end

local function p1_apply_pet_command_event(event)
	if type(event) ~= 'table' then
		return
	end
	if scheduler.providers and scheduler.providers.pet_combat then
		scheduler.providers.pet_combat.observe_coordinator_event(event)
	end
	if event.outcome == 'complete' then
		scheduler.p1_pending_mark_complete(event.at, 'pet_' .. tostring(event.reason))
	elseif event.outcome == 'failed' then
		scheduler.p1_pending_mark_failed(
			event.at,
			'pet_' .. tostring(event.reason),
			tonumber(event.retry_delay) or 0
		)
	end
	_G.UC_SMN_PET_COMMAND_STATE = {
		outcome = tostring(event.outcome or ''),
		reason = tostring(event.reason or ''),
		kind = tostring(event.kind or ''),
		action_name = tostring(event.action_name or ''),
		pet_id = tonumber(event.pet_id) or 0,
		target_id = tonumber(event.target_id) or 0,
		combat_generation = tonumber(event.combat_generation) or 0,
		retry_delay = tonumber(event.retry_delay) or 0,
	}
end

local function p1_prepare_pet_context(ctx)
	if type(ctx) ~= 'table' then
		error('pet runtime requires scheduler context')
	end
	ctx.combat_domain_enabled = domain_ownership.is_enabled('combat')
	scheduler.providers.pet_combat.observe_target(ctx)
	local scheduler_pending_action = scheduler.phase1.pending
	if type(scheduler_pending_action) == 'table'
		and scheduler.p1_pending_is_live_state(tostring(scheduler_pending_action.state or ''))
		and tostring(scheduler_pending_action.provider or '') == 'maintenance_summoner' then
		local pending_action_type = tostring(scheduler_pending_action.action_type or '')
		local pending_action_name = tostring(scheduler_pending_action.action_name or '')
		if pending_action_type == 'spell'
			and ctx.pet_present == true
			and ctx.pet_name == pending_action_name then
			scheduler.p1_pending_mark_complete(ctx.now, 'desired_avatar_observed')
		elseif pending_action_type == 'ja'
			and pending_action_name == 'Avatar\'s Favor'
			and require('uc_smn_runtime').has_buff(ctx.player, require('uc_smn_runtime').BUFF_FAVOR) then
			scheduler.p1_pending_mark_complete(ctx.now, 'avatar_favor_observed')
		end
	end
	local inferred_pet_target_id = 0
	if ctx.pet_present == true then
		inferred_pet_target_id = require('uc_pet_combat_state').observed_pet_target(
			scheduler.pet_combat_state,
			ctx.pet_id
		)
	end
	local observe_ctx = {
		now = ctx.now,
		pet_present = ctx.pet_present,
		pet_id = ctx.pet_id,
		pet_status = ctx.pet_status,
		pet_target_id = ctx.pet_target_id,
		pet_target_matches_current = ctx.pet_target_matches_current,
		pet_inferred_target_id = inferred_pet_target_id,
		player_buffs = ctx.player.buffs,
		ability_recasts_present = ctx.ability_recasts_present,
		ability_recasts = ctx.ability_recasts,
		combat_generation = ctx.combat_generation,
		target_id = ctx.target_id,
		target_valid = ctx.target_valid,
		target_hpp = ctx.target_hpp,
	}
	local event = pet_command_coordinator.observe(scheduler.pet_command_state, observe_ctx)
	p1_apply_pet_command_event(event)
end

local function p1_run_dry(settings, ctx)
	if type(ctx) ~= 'table' then
		ctx = p1_build_ctx(settings)
	end
	p1_prepare_pet_context(ctx)
	scheduler.p1_update_pending_state(ctx)
	local proposals = p1_collect_proposals(ctx)
	local ranked, reject_counts, locks, rejected = p1_rank(ctx, proposals)
	local function is_maint_spell_candidate(proposal)
		if type(proposal) ~= 'table' then
			return false
		end
		local provider = tostring(proposal.provider or '')
		local action_type = tostring(proposal.action_type or '')
		return action_type == 'spell' and (provider == 'maintenance' or provider == 'brd' or provider == 'maintenance_geo' or provider == 'defensive_internal' or provider == 'defensive_healbot')
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
		local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', ctx.settings and ctx.settings.defensive_critical_hpp)) or 35
		local is_defensive_cure_selected = (
			(selected_provider_for_weave == 'defensive_internal' or selected_provider_for_weave == 'defensive_healbot')
			and (tostring(selected.action_type or '') == 'spell' or tostring(selected.action_type or '') == 'ja')
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
	require('uc_scheduler_observability').publish_dryrun(
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
		{
			set_pending_globals = scheduler.p1_set_pending_globals,
			build_lock_summary = scheduler.p1_build_lock_summary,
		}
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
		local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
		local target_ownership_status = require('uc_scheduler_target_ownership').apply_target_ownership({
			dispatcher = dispatcher,
			set_target = uc_settarget.select_by_id,
			intent = intent,
			target_id = tid,
		})
		_G.UC_SCHED_P1_DARKLAUNCH_TARGET_VALIDATE = {
			ok = _intent_ok and true or false,
			reason = _intent_reason,
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
	local detail = type(proposal and proposal.detail) == 'table' and proposal.detail or {}
	local debounce_s = detail.death_switch == true
		and (tonumber(scheduler.DEATH_SWITCH_DEBOUNCE_S) or 0.90)
		or (tonumber(scheduler.TARGET_ACQUIRE_DEBOUNCE_S) or 0.20)
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
	local detail = type(selected.detail) == 'table' and selected.detail or {}
	local player = windower.ffxi.get_player()
	local death_switch = detail.death_switch == true
	local engaged_retarget = detail.add_control_retarget == true and player and tonumber(player.status) == 1
	local ok
	local dispatch_reason = nil
	if death_switch then
		local result = require('uc_scheduler_dispatcher').dispatch_intent({
			kind = 'switch_target',
			source = 'unified_scheduler:death_switch',
			target_id = tid,
		}, {
			execute = true,
			switch_target = uc_attack.switch_target,
		}, {
			revalidate = function()
				return combat_core.revalidate_death_switch_for_scheduler(
					ctx.settings,
					tid,
					detail.death_switch_incumbent_id
				)
			end,
		})
		ok = result.ok and result.executed
		dispatch_reason = result.reason
		-- A packet failure must not retry every scheduler frame during the death window.
		scheduler.p1_apply_target_acquire_debounce(selected, ctx.now)
	elseif engaged_retarget then
		local result = require('uc_scheduler_dispatcher').dispatch_intent({
			kind = 'switch_target',
			source = 'unified_scheduler:target_control',
			target_id = tid,
		}, {
			execute = true,
			switch_target = uc_attack.switch_target,
		})
		ok = result.ok and result.executed
		dispatch_reason = result.reason
	else
		ok = p1_try_target_prep(tid)
	end
	if not ok then
		scheduler.action_timeline_log('TARGET_SELECT_BLOCKED', {
			tid = tid,
			name = tostring(selected.target_name or ''),
			reason = tostring(dispatch_reason or 'BLOCK_INVALID_TARGET'),
		}, ('target_blocked:%d:prep'):format(tid), 0.50)
		return false, nil
	end
	scheduler.phase1.last_selected = selected
	scheduler.phase1.last_plan = p1_build_dispatch_plan(ctx, selected)
	if not death_switch then
		scheduler.p1_apply_target_acquire_debounce(selected, ctx.now)
	end
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

function scheduler.p1_try_nonblocking_target_acquire(settings, ctx)
	if not domain_ownership.is_enabled('combat') then
		return false, nil
	end
	if type(rawget(_G, 'UC_REACTION_LOCK')) == 'table' then
		return false, 'reaction_hold'
	end
	if type(ctx) ~= 'table' then
		ctx = p1_build_ctx(settings)
	end
	scheduler.p1_update_pending_state(ctx)
	local proposals = {}
	scheduler.providers.target_control.collect_target(ctx, proposals)
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

p1_apply_face_to_target = function(settings, target_id, turn_away, force_face)
	if turn_away ~= true and force_face ~= true and not bool_setting(settings and settings.face, false) then
		return false
	end
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return false
	end
	local me = windower.ffxi.get_mob_by_target('me')
	local mob = windower.ffxi.get_mob_by_id(tid)
	if not me or not mob then
		return false
	end
	-- C5: face only valid combat targets.
	-- If target is not a live monster combat target, do not issue explicit turn.
	local is_valid_combat_target = (mob.valid_target == true)
		and ((tonumber(mob.spawn_type) or 0) == 16)
		and ((tonumber(mob.hpp) or 0) > 0)
	if not is_valid_combat_target then
		return false
	end
	if me.x == nil or me.y == nil or mob.x == nil or mob.y == nil then
		return false
	end
	-- Match core exactly: atan2(dx, dy) - pi/2.
	local dx = (mob.x - me.x)
	local dy = (mob.y - me.y)
	local heading = math.atan2(dx, dy) - 1.5708
	if turn_away == true then
		heading = heading + math.pi
		if heading > math.pi then
			heading = heading - (2 * math.pi)
		end
	end
	if heading then
		local intent = {
			kind = 'turn',
			source = turn_away == true and 'unified_scheduler:reaction_turn_away' or 'unified_scheduler:T2.3c_darklaunch',
			heading = heading,
			meta = {
				target_id = tid,
			},
		}
		local dispatcher = require('uc_scheduler_dispatcher')
		local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
		local turn_ownership_status = require('uc_scheduler_turn_ownership').apply_turn_ownership({
			dispatcher = dispatcher,
			turn = windower.ffxi.turn,
			intent = intent,
		})
		_G.UC_SCHED_P1_DARKLAUNCH_TURN_VALIDATE = {
			ok = _intent_ok and true or false,
			reason = _intent_reason,
			kind = intent.kind,
			source = intent.source,
			heading = tonumber(intent.heading) or 0,
			ownership_enabled = turn_ownership_status.ownership_enabled,
			dispatched = turn_ownership_status.dispatched,
			dispatch_ok = turn_ownership_status.dispatch_ok,
			dispatch_reason = turn_ownership_status.dispatch_reason,
			fallback_used = turn_ownership_status.fallback_used,
		}
		return true
	end
	return false
end

local function p1_dispatch_combat_engage(selected, settings, phase, expected_tid)
	local target = windower.ffxi.get_mob_by_target('t')
	if not target or not target.valid_target or (tonumber(target.id) or 0) ~= expected_tid then
		local ok_set = p1_try_target_prep(expected_tid)
		if not ok_set then
			log_combat_sched(('engage_drop reason=TARGET_PREP_FAIL expected_tid=%d'):format(expected_tid))
			if uc_scheduler_config.debug_enabled(settings) then
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
		if uc_scheduler_config.debug_enabled(settings) then
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
		if uc_scheduler_config.debug_enabled(settings) then
			_G.UC_LAST_SCHED_ACTION = '[p1]engage:dispatch_fail:no_uc_attack'
		end
		scheduler.action_timeline_log('ENGAGE_DISPATCH_BLOCKED', {
			tid = expected_tid,
			name = tostring(selected.target_name or ''),
			reason = 'BLOCK_UNKNOWN',
		}, ('engage_dispatch_blocked:%d:no_attack'):format(expected_tid), 0.50)
		return false, nil
	end
	local engage_result = require('uc_scheduler_dispatcher').dispatch_intent({
		kind = 'engage',
		source = 'unified_scheduler:combat_engage',
		target_id = expected_tid,
	}, {
		execute = true,
		engage_target = uc_attack.engage_target,
	})
	local ok_attack = engage_result.ok and engage_result.executed
	local engage_reason = engage_result.reason
	if not ok_attack then
		if scheduler.p1_pending_engage_live(phase, now_s()) then
			scheduler.p1_clear_pending_engage(phase)
		end
		scheduler.p1_clear_engage_duplicate_state(phase, '', now_s())
		log_combat_sched(('engage_send_fail tid=%d reason=%s'):format(expected_tid, tostring(engage_reason or 'ENGAGE_FAIL')))
		if uc_scheduler_config.debug_enabled(settings) then
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

p1_build_pull_executor = function()
	return require('uc_scheduler_pull_executor').build({
		dispatcher = require('uc_scheduler_dispatcher'),
		run = windower.ffxi.run,
		set_target = uc_settarget.select_by_id,
		send_command = windower.send_command,
		sleep = coroutine.sleep,
	})
end

local function p1_dispatch_pull_control(selected, settings)
	if not domain_ownership.is_enabled('combat') then
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
	local ok, reason = combat_core.dispatch_pull_for_scheduler(settings, target_id, p1_build_pull_executor())
	if not ok then
		return false, nil
	end
	local sent = tostring(reason or '') == 'PULL_ACTION_SENT'
	local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
	if sent then
		action_mark_sent('pull')
		scheduler.record_dispatch(ctx)
		scheduler.p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	else
		scheduler.p1_pending_mark_complete(ctx.now, ('pull_no_send:%s'):format(tostring(reason or 'BLOCK')))
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

local function p1_dispatch_camp_puller(selected, settings)
	if not domain_ownership.is_enabled('combat') then
		return false, nil
	end
	local ctx = p1_build_ctx(settings)
	local valid, reason = scheduler.providers.camp_puller.revalidate(selected, ctx)
	if not valid then
		_G.UC_LAST_SCHED_ACTION = '[camp_pull]commit_rejected:' .. tostring(reason)
		return false, nil
	end
	local config = ctx.settings.camp_pulling
	if type(config) ~= 'table' then
		error('camp pull dispatch requires normalized configuration')
	end
	local action_type = tostring(selected.action_type or '')
	local executor = p1_build_pull_executor()
	if action_type == 'camp_approach'
		or action_type == 'camp_return'
		or action_type == 'camp_recover' then
		local detail = selected.detail
		if type(detail) ~= 'table' or tonumber(detail.heading) == nil then
			error('camp pull movement proposal requires a numeric heading')
		end
		executor.run_heading(tonumber(detail.heading), {
			reason = tostring(selected.reason_code or ''),
			target_id = tonumber(selected.target_id) or 0,
		})
		_G.UC_MOVEMENT_OWNER = 'camp_puller'
		_G.UC_MOVEMENT_LOCK_UNTIL = ctx.now + 0.8
		scheduler.providers.camp_puller.note_dispatch(selected, ctx.now, config)
		_G.UC_LAST_SCHED_ACTION = '[camp_pull]' .. action_type
		return true, 'BLOCK_SCHED_CAMP_PULL_MOVEMENT'
	end
	if action_type == 'camp_stop' then
		executor.stop({
			reason = tostring(selected.reason_code or ''),
		})
		_G.UC_MOVEMENT_OWNER = 'none'
		_G.UC_MOVEMENT_LOCK_UNTIL = ctx.now
		scheduler.providers.camp_puller.note_dispatch(selected, ctx.now, config)
		_G.UC_LAST_SCHED_ACTION = '[camp_pull]stop'
		return true, 'BLOCK_SCHED_CAMP_PULL_STOP'
	end
	if action_type ~= 'spell' and action_type ~= 'ja' then
		error('camp pull dispatcher received unsupported action type: ' .. action_type)
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
	end
	local action_name = tostring(selected.action_name or '')
	local ready, ready_reason, ready_kind = action_ready(action_name, tonumber(selected.target_id) or 0)
	if not ready or ready_kind ~= action_type then
		_G.UC_LAST_SCHED_ACTION = '[camp_pull]not_ready:' .. tostring(ready_reason)
		return false, nil
	end
	local command = build_action_command(action_name, action_type, {
		id = tonumber(selected.target_id) or 0,
		name = tostring(selected.target_name or ''),
		is_mob = true,
	})
	executor.send_command(command, {
		action_type = action_type,
		action_name = action_name,
		provider = 'camp_puller',
		target_id = tonumber(selected.target_id) or 0,
	})
	scheduler.providers.camp_puller.note_dispatch(selected, ctx.now, config)
	action_mark_sent(action_type, {
		action_name = action_name,
		provider = 'camp_puller',
		target_id = tonumber(selected.target_id) or 0,
		target_name = tostring(selected.target_name or ''),
		target_kind = 'mob',
	})
	local dispatch_ctx = {
		now = ctx.now,
		tick = p1_number(scheduler.phase1.tick, 0),
	}
	scheduler.record_dispatch(dispatch_ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(
		dispatch_ctx,
		scheduler.p1_get_locks(dispatch_ctx)
	)
	_G.UC_LAST_SCHED_ACTION = ('[camp_pull]%s:%s'):format(action_type, action_name)
	return true, 'BLOCK_SCHED_CAMP_PULL_ACTION'
end

local function p1_dispatch_maintenance_cor(selected, settings, provider)
	if not domain_ownership.is_enabled('maintenance') then
		log_def_sched('MAINT_COR_DISPATCH_SKIP reason=DOMAIN_DISABLED')
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
	local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
	local maintenance_command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		send_command = windower.send_command,
		intent = intent,
		command = maintenance_cor_command,
	})
	scheduler.action_timeline_log('MAINT_BUFF_DISPATCHED', {
		action = tostring(ability or ''),
		provider = tostring(provider or ''),
		band = tonumber(selected.priority_band) or 0,
	}, ('maint_dispatch:%s'):format(tostring(ability or '')), 0.05)
	_G.UC_SCHED_P1_DARKLAUNCH_MAINTENANCE_COR_COMMAND_VALIDATE = {
		ok = _intent_ok and true or false,
		reason = _intent_reason,
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
	scheduler.record_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]cor:%s'):format(ability)
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_MAINT_COR'
end

function scheduler.p1_dispatch_maintenance_brd(selected, settings)
	if not domain_ownership.is_enabled('maintenance') then
		return false, nil
	end
	local action_name = tostring(selected.action_name or '')
	local action_type = tostring(selected.action_type or '')
	if action_name == '' or (action_type ~= 'spell' and action_type ~= 'ja') then
		return false, nil
	end
	local target_id = tonumber(selected.target_id) or 0
	local lane_reserved, lane_reason = require('uc_brd_maintenance').action_lane_status()
	scheduler.apply_brd_maintenance_movement_lock(
		action_name,
		target_id,
		lane_reserved and lane_reason or tostring(selected.reason_code or 'brd_maintenance_dispatch'),
		now_s()
	)
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		require('uc_brd_maintenance').note_scheduler_rejection(block_reason, selected.action_name)
		return true, block_reason
	end
	local ok_ready, ready_reason, ready_kind = action_ready(action_name, tonumber(selected.target_id) or 0)
	if not ok_ready or ready_kind ~= action_type then
		require('uc_brd_maintenance').note_scheduler_rejection(ready_reason, action_name)
		log_def_sched(('MAINT_BRD_DISPATCH_SKIP reason=NOT_READY action="%s" kind=%s ready_kind=%s ready_reason=%s'):format(
			action_name,
			action_type,
			tostring(ready_kind or ''),
			tostring(ready_reason or '')
		))
		return false, nil
	end
	local command_kind = action_type == 'spell' and 'ma' or 'ja'
	local command_target = '<me>'
	local player = windower.ffxi.get_player() or {}
	local player_id = tonumber(player.id) or 0
	if action_type == 'spell' and target_id ~= player_id then
		local target_name = tostring(selected.target_name or '')
		if target_id <= 0 or target_name == '' then
			error('targeted Bard spell requires target id and name')
		end
		command_target = '"' .. target_name:gsub('"', '') .. '"'
	end
	local command = ('input /%s "%s" %s'):format(command_kind, action_name, command_target)
	local dispatcher = require('uc_scheduler_dispatcher')
	local result = dispatcher.dispatch_intent({
		kind = 'send_command',
		source = 'unified_scheduler:maintenance_brd',
		command = command,
		meta = {
			action_type = action_type,
			action_name = action_name,
			provider = 'maintenance_brd',
			target_id = target_id,
			target_name = tostring(selected.target_name or ''),
		},
	}, {
		execute = true,
		send_command = windower.send_command,
	})
	if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
		require('uc_brd_maintenance').note_scheduler_rejection(type(result) == 'table' and result.reason or 'dispatcher_failed', action_name)
		log_def_sched(('MAINT_BRD_DISPATCH_SKIP reason=%s action="%s"'):format(
			tostring(type(result) == 'table' and result.reason or 'dispatcher_failed'),
			action_name
		))
		return false, nil
	end
	action_mark_sent(action_type, {
		action_name = action_name,
		provider = 'maintenance_brd',
		target_id = target_id,
		target_name = tostring(selected.target_name or ''),
	})
	local token = tostring(tonumber((action_state() or {}).action_token) or 0)
	require('uc_brd_maintenance').note_dispatch({
		action_type = action_type,
		action_name = action_name,
		detail = selected.detail,
	}, token, now_s())
	local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.record_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]brd:%s'):format(action_name)
	scheduler.action_timeline_log('MAINT_BUFF_DISPATCHED', {
		action = action_name,
		provider = 'maintenance_brd',
		band = tonumber(selected.priority_band) or 0,
		action_token = token,
	}, ('maint_brd_dispatch:%s'):format(action_name), 0.05)
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_MAINT_BRD'
end

function scheduler.p1_dispatch_maintenance_sch(selected, settings)
	local provider_id = tostring(selected.provider or '')
	local defensive = provider_id == 'defensive_sch'
	if defensive and not domain_ownership.is_enabled('defensive') then
		return false, nil
	end
	if not defensive and not domain_ownership.is_enabled('maintenance') then
		return false, nil
	end
	local action_name = tostring(selected.action_name or '')
	local action_type = tostring(selected.action_type or '')
	if action_name == '' or (action_type ~= 'spell' and action_type ~= 'ja') then
		return false, nil
	end
	local detail = selected.detail
	if type(detail) ~= 'table' or type(detail.sch_step) ~= 'table' then
		error('Scholar maintenance proposal requires its exact runtime step')
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
	end
	local target_id = tonumber(selected.target_id) or 0
	local ready, ready_reason, ready_kind
	if action_type == 'spell' then
		ready, ready_reason, ready_kind = sch_spell_ready(
			action_name,
			target_id,
			tonumber(detail.sch_step.spell_mp_multiplier) or 1.0
		)
	else
		if detail.sch_step.uses_reserved_charge == true then
			ready, ready_reason = require('uc_sch_runtime').reserved_charge_step_ready(
				detail.sch_step
			)
			ready_kind = 'ja'
		else
			ready, ready_reason, ready_kind = action_ready(action_name, target_id)
		end
	end
	if not ready or ready_kind ~= action_type then
		log_def_sched(('MAINT_SCH_DISPATCH_SKIP reason=NOT_READY action="%s" kind=%s ready_kind=%s ready_reason=%s'):format(
			action_name,
			action_type,
			tostring(ready_kind or ''),
			tostring(ready_reason or '')
		))
		return false, nil
	end
	local target_kind = tostring(selected.target_kind or '')
	local target_member = {
		id = target_id,
		name = tostring(selected.target_name or ''),
		is_self = target_kind == 'self',
		is_mob = false,
	}
	local command = build_action_command(action_name, action_type, target_member)
	local result = require('uc_scheduler_dispatcher').dispatch_intent({
		kind = 'send_command',
		source = 'unified_scheduler:sch_sequence',
		command = command,
		meta = {
			action_type = action_type,
			action_name = action_name,
			provider = provider_id,
			target_id = target_id,
			target_name = target_member.name,
		},
	}, {
		execute = true,
		send_command = windower.send_command,
	})
	if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
		return false, nil
	end
	local dispatched_at = now_s()
	local noted, note_reason = scheduler.providers.sch_maintenance.note_dispatched(
		detail.sch_step,
		dispatched_at
	)
	if not noted then
		error('Scholar runtime rejected a dispatched step: ' .. tostring(note_reason))
	end
	action_mark_sent(action_type, {
		action_name = action_name,
		provider = provider_id,
		target_id = target_id,
		target_name = target_member.name,
		target_kind = target_kind,
	})
	local ctx = {
		now = dispatched_at,
		tick = p1_number(scheduler.phase1.tick, 0),
	}
	scheduler.record_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(
		ctx,
		scheduler.p1_get_locks(ctx)
	)
	_G.UC_LAST_SCHED_ACTION = ('[sch]%s:%s'):format(action_type, action_name)
	scheduler.action_timeline_log('SCH_MAINTENANCE_DISPATCHED', {
		action = action_name,
		provider = provider_id,
		band = tonumber(selected.priority_band) or 0,
		sequence_id = tostring(detail.sch_step.sequence_id or ''),
		phase = tostring(detail.sch_step.phase or ''),
	}, ('sch_dispatch:%s:%s'):format(
		tostring(detail.sch_step.sequence_generation or ''),
		tostring(detail.sch_step.phase or '')
	), 0.05)
	return true, 'BLOCK_SCHED_P1_SCH_MAINTENANCE'
end

function scheduler.defensive_spell_movement_blocked(selected, action_kind, now_gate)
	if action_kind ~= 'spell' then
		return false, nil
	end
	local player = windower.ffxi.get_player()
	local out_of_combat = (tonumber(player and player.status) or 0) ~= 1
	local preengage_move_active = (rawget(_G, 'UC_PREENGAGE_APPROACH_ACTIVE') == true)
	local follow_run_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE_UNTIL')) or 0
	local follow_run_active = (rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE') == true) or (now_gate < follow_run_until)
	local follow_catchup_until = tonumber(rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL')) or 0
	local follow_needs_catchup = (rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP') == true) or (now_gate < follow_catchup_until)
	if out_of_combat and preengage_move_active then
		_G.UC_LAST_SCHED_ACTION = ('[p1]defer_preengage_move:%s->%s'):format(
			tostring(selected.action_name or ''),
			tostring(selected.target_name or '')
		)
		return true, 'BLOCK_DEFENSIVE_PREENGAGE_MOVE_ACTIVE'
	end
	if out_of_combat and (follow_run_active or follow_needs_catchup) then
		_G.UC_LAST_SCHED_ACTION = ('[p1]defer_follow_move:%s->%s'):format(
			tostring(selected.action_name or ''),
			tostring(selected.target_name or '')
		)
		scheduler.action_timeline_log('DEFENSIVE_FOLLOW_MOVE_BLOCKED', {
			action = tostring(selected.action_name or ''),
			target = tostring(selected.target_name or ''),
			target_id = tonumber(selected.target_id) or 0,
			reason = 'BLOCK_DEFENSIVE_FOLLOW_MOVE_ACTIVE',
			follow_run_active = tostring(follow_run_active),
			follow_needs_catchup = tostring(follow_needs_catchup),
			follow_run_remaining_s = ('%.2f'):format(math.max(0, follow_run_until - now_gate)),
			follow_catchup_remaining_s = ('%.2f'):format(math.max(0, follow_catchup_until - now_gate)),
		}, ('defensive_follow_move_block:%s:%d'):format(
			tostring(selected.action_name or ''),
			tonumber(selected.target_id) or 0
		), 0.25)
		return true, 'BLOCK_DEFENSIVE_FOLLOW_MOVE_ACTIVE'
	end
	return false, nil
end

local function p1_dispatch_defensive_internal(selected, settings)
	if not domain_ownership.is_enabled('defensive') then
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
	local cure_target_ok, cure_target_reason = scheduler.validate_cure_target(selected)
	if not cure_target_ok then
		log_def_sched(('DEFENSIVE_CURE_DISPATCH_REJECT action="%s" target="%s" target_id=%d reason=%s'):format(
			tostring(selected.action_name or ''),
			tostring(selected.target_name or ''),
			tonumber(selected.target_id) or 0,
			tostring(cure_target_reason)
		))
		return true, cure_target_reason
	end
	local ok_ready, _, action_kind = action_ready(tostring(selected.action_name or ''), tonumber(selected.target_id) or 0)
	if action_kind == 'none' or not ok_ready then
		return false, nil
	end
	local detail = type(selected.detail) == 'table' and selected.detail or {}
	if action_kind == 'ja' and detail.waltz_action == true then
		local waltz_ok, waltz_reason = waltz_ready(
			tostring(selected.action_name or ''),
			tonumber(selected.target_id) or 0,
			tonumber(detail.tp_reserve)
		)
		if not waltz_ok then
			log_def_sched(('WALTZ_DISPATCH_REJECT action="%s" target="%s" reason=%s'):format(
				tostring(selected.action_name or ''), tostring(selected.target_name or ''), tostring(waltz_reason)
			))
			return true, tostring(waltz_reason)
		end
	end
	local now_gate = now_s()
	local movement_blocked, movement_reason = scheduler.defensive_spell_movement_blocked(selected, action_kind, now_gate)
	if movement_blocked then
		return true, movement_reason
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
	local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
	local defensive_command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
		dispatcher = dispatcher,
		send_command = windower.send_command,
		intent = intent,
		command = cmd,
	})
	_G.UC_SCHED_P1_DARKLAUNCH_DEFENSIVE_INTERNAL_COMMAND_VALIDATE = {
		ok = _intent_ok and true or false,
		reason = _intent_reason,
		kind = intent.kind,
		source = intent.source,
		command_present = defensive_command_ownership_status.command_present,
		ownership_enabled = defensive_command_ownership_status.ownership_enabled,
		dispatched = defensive_command_ownership_status.dispatched,
		dispatch_ok = defensive_command_ownership_status.dispatch_ok,
		dispatch_reason = defensive_command_ownership_status.dispatch_reason,
		fallback_used = defensive_command_ownership_status.fallback_used,
	}
	if defensive_command_ownership_status.dispatch_ok == true
		and type(detail) == 'table'
		and detail.def_action_type == 'charm_sleep' then
		scheduler.providers.charm_sleeper.note_dispatch(selected, now_gate)
	end
	if defensive_command_ownership_status.dispatch_ok == true
		and type(detail) == 'table'
		and detail.cure_intent == 'sleep_wake' then
		scheduler.providers.sleep_waker.note_dispatch(selected, now_gate)
	end
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
		local critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', settings and settings.defensive_critical_hpp)) or 35
		local event_code = 'MAINT_BUFF_DISPATCHED'
		if is_cure then
			if tostring(type(detail) == 'table' and detail.cure_intent or '') == 'sleep_wake' then
				event_code = 'SLEEP_WAKE_DISPATCHED'
			else
				event_code = (target_hpp > 0 and target_hpp <= critical_hpp) and 'CRITICAL_CURE_DISPATCHED' or 'NONCRITICAL_CURE_DISPATCHED'
			end
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
	if type(dispel_detail) == 'table' and tostring(dispel_detail.enemy_debuff_attempt_key or '') ~= '' then
		mark_enemy_dispel_attempt(tostring(dispel_detail.enemy_debuff_attempt_key), dispatch_now)
	end
	local ctx = { now = dispatch_now, tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.record_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]%s->%s'):format(tostring(selected.action_name or ''), tostring(selected.target_name or ''))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH'
end

local function p1_dispatch_defensive_healbot(selected, settings)
	if not domain_ownership.is_enabled('defensive') then
		return false, nil
	end
	local cure_target_ok, cure_target_reason = scheduler.validate_cure_target(selected)
	if not cure_target_ok then
		log_def_sched(('DEFENSIVE_CURE_DISPATCH_REJECT action="%s" target="%s" target_id=%d reason=%s'):format(
			tostring(selected.action_name or ''),
			tostring(selected.target_name or ''),
			tonumber(selected.target_id) or 0,
			tostring(cure_target_reason)
		))
		return true, cure_target_reason
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
	local hb_critical_hpp = tonumber(scheduler.active_value_or_flat('config.defensive.thresholds.critical_hpp', settings and settings.defensive_critical_hpp)) or 35
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
	scheduler.record_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	_G.UC_LAST_SCHED_ACTION = ('[p1]hb:%s->%s'):format(tostring(selected.action_name or ''), tostring(selected.target_name or ''))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_HEALBOT'
end

local function p1_dispatch_combat(selected, settings, phase)
	_G.UC_TANK_ENMITY_BLOCK = ''
	if not domain_ownership.is_enabled('combat') then
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
		local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
		local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
			dispatcher = dispatcher,
			run = windower.ffxi.run,
			intent = intent,
		})
		_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ACTION_SETTLE_VALIDATE = {
			ok = _intent_ok and true or false,
			reason = _intent_reason,
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
		local required_tp = selected.required_tp
		if type(required_tp) ~= 'number'
			or required_tp % 1 ~= 0
			or required_tp < 1000
			or required_tp > 3000 then
			error('scheduler combat WS proposal required_tp must be an integer from 1000 to 3000')
		end
		if tp < required_tp then
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
		if not combat_core or type(combat_core.try_dispatch_ws_with_intent) ~= 'function' then
			error('scheduler combat WS dispatch requires core intent owner')
		end
		local sent, why = combat_core.try_dispatch_ws_with_intent(ws, expected_tid, settings, selected.skillchain_plan)
		if not sent then
			_G.UC_LAST_SCHED_ACTION = ('[p1]ws_hold:%s:%s'):format(ws, tostring(why or 'BLOCK'))
			if type(selected.skillchain_plan) == 'table' then
				scheduler.action_timeline_log('SC_COMMIT_RESULT', {
					target_id = expected_tid,
					resonance_generation = tonumber(selected.skillchain_plan.resonance_generation) or 0,
					ws_name = ws,
					predicted_result = tostring(selected.skillchain_plan.predicted_result or ''),
					commit_result = tostring(why or 'SC_INTENT_LOST'),
				}, nil, 0)
			end
			return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_WS_INTENT'
		end
		action_mark_sent('ws')
		if type(selected.skillchain_plan) == 'table' then
			scheduler.action_timeline_log('SC_WS_DISPATCHED', {
				target_id = expected_tid,
				resonance_generation = tonumber(selected.skillchain_plan.resonance_generation) or 0,
				ws_id = tonumber(selected.skillchain_plan.ws_id) or 0,
				ws_name = ws,
				predicted_result = tostring(selected.skillchain_plan.predicted_result or ''),
				band = tonumber(selected.priority_band) or 0,
				urgency = ('%.2f'):format(p1_clamp_urgency(selected.urgency)),
			}, nil, 0)
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
			local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				send_command = windower.send_command,
				intent = intent,
				command = ja_target_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_JA_COMMAND_VALIDATE = {
				ok = _intent_ok and true or false,
				reason = _intent_reason,
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
				local _stop_intent_ok, _stop_intent_reason = dispatcher.validate_intent(stop_intent)
				local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
					dispatcher = dispatcher,
					run = windower.ffxi.run,
					intent = stop_intent,
				})
				_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_JA_SELF_SEND_VALIDATE = {
					ok = _stop_intent_ok and true or false,
					reason = _stop_intent_reason,
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
			local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				send_command = windower.send_command,
				intent = intent,
				command = ja_self_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_JA_SELF_COMMAND_VALIDATE = {
				ok = _intent_ok and true or false,
				reason = _intent_reason,
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
			local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
				dispatcher = dispatcher,
				run = windower.ffxi.run,
				intent = intent,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_SPELL_SETTLE_VALIDATE = {
				ok = _intent_ok and true or false,
				reason = _intent_reason,
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
				local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
				local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
					dispatcher = dispatcher,
					run = windower.ffxi.run,
					intent = intent,
				})
				_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SEND_VALIDATE = {
					ok = _intent_ok and true or false,
					reason = _intent_reason,
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
			local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				send_command = windower.send_command,
				intent = intent,
				command = spell_target_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_SPELL_TARGET_COMMAND_VALIDATE = {
				ok = _intent_ok and true or false,
				reason = _intent_reason,
				kind = intent.kind,
				source = intent.source,
				command_present = command_ownership_status.command_present,
				ownership_enabled = command_ownership_status.ownership_enabled,
				dispatched = command_ownership_status.dispatched,
				dispatch_ok = command_ownership_status.dispatch_ok,
				dispatch_reason = command_ownership_status.dispatch_reason,
				fallback_used = command_ownership_status.fallback_used,
			}
			if tostring(selected.provider or '') == 'encounter_kei'
				and (command_ownership_status.dispatched ~= true or command_ownership_status.dispatch_ok ~= true) then
				return false, nil
			end
			action_mark_sent('spell', {
				action_name = spell,
				provider = tostring(selected.provider or ''),
				target_id = expected_tid,
				target_name = tostring(selected.target_name or ''),
				target_kind = tostring(target_kind or ''),
			})
			scheduler.action_timeline_log('SPELL_SENT', {
				spell = tostring(spell or ''),
				provider = tostring(selected.provider or ''),
				tid = expected_tid,
				name = tostring(selected.target_name or ''),
				kind = 'spell',
				target = tostring(selected.target_name or ''),
				target_id = expected_tid,
				cast_type = tostring(action_type or ''),
				action_token = tostring(tonumber((action_state() or {}).action_token) or 0),
			}, ('spell_sent:%s:%d'):format(tostring(spell or ''), expected_tid), 0.05)
			scheduler.action_timeline_note_spell_sent({
				provider = tostring(selected.provider or ''),
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
			if tostring(selected.provider or '') == 'encounter_kei' then
				require('uc_kei_encounter').note_spell_dispatched(
					selected,
					now_s(),
					(windower.ffxi.get_player() or {}).id
				)
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
				local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
				local run_stop_ownership_status = require('uc_scheduler_run_stop_ownership').apply_run_stop_ownership({
					dispatcher = dispatcher,
					run = windower.ffxi.run,
					intent = intent,
				})
				_G.UC_SCHED_P1_DARKLAUNCH_RUN_STOP_TANK_ENMITY_SPELL_SELF_SEND_VALIDATE = {
					ok = _intent_ok and true or false,
					reason = _intent_reason,
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
			local _intent_ok, _intent_reason = dispatcher.validate_intent(intent)
			local command_ownership_status = require('uc_scheduler_command_ownership').apply_command_ownership({
				dispatcher = dispatcher,
				send_command = windower.send_command,
				intent = intent,
				command = spell_self_command,
			})
			_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE = {
				ok = _intent_ok and true or false,
				reason = _intent_reason,
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
	scheduler.record_dispatch(ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
	return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT'
end

local function p1_dispatch_summoner_maintenance(selected, settings)
	if not domain_ownership.is_enabled('maintenance') then
		return false, nil
	end
	local action_type = tostring(selected.action_type or '')
	if action_type == 'pet' then
		error('Summoner pet commands must use the shared pet dispatcher')
	end
	if action_type ~= 'spell' and action_type ~= 'ja' then
		return false, nil
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
	end
	local ctx = p1_build_ctx(settings)
	p1_prepare_pet_context(ctx)
	local valid, reason = scheduler.providers.summoner_maintenance.revalidate(selected, ctx)
	if not valid then
		_G.UC_LAST_SCHED_ACTION = '[smn]commit_rejected:' .. tostring(reason)
		return false, nil
	end
	local action_name = tostring(selected.action_name or '')
	local ready, ready_reason, ready_kind = action_ready(action_name, tonumber(selected.target_id) or 0)
	if not ready or ready_kind ~= action_type then
		_G.UC_LAST_SCHED_ACTION = '[smn]not_ready:' .. tostring(ready_reason)
		return false, nil
	end
	if action_name == '' or action_name:find('"', 1, true) then
		error('Summoner maintenance action name is not command-safe')
	end
	local command_kind = action_type == 'spell' and 'ma' or 'ja'
	local command = ('input /%s "%s" <me>'):format(command_kind, action_name)
	local result = require('uc_scheduler_dispatcher').dispatch_intent({
		kind = 'send_command',
		source = 'unified_scheduler:summoner_maintenance',
		command = command,
		meta = {
			action_type = action_type,
			action_name = action_name,
			provider = 'maintenance_summoner',
			target_id = tonumber(selected.target_id) or 0,
		},
	}, {
		execute = true,
		send_command = windower.send_command,
	})
	if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
		return false, nil
	end
	action_mark_sent(action_type, {
		action_name = action_name,
		provider = 'maintenance_summoner',
		target_id = tonumber(selected.target_id) or 0,
		target_name = tostring(selected.target_name or ''),
		target_kind = tostring(selected.target_kind or ''),
	})
	local dispatch_ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.record_dispatch(dispatch_ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(
		dispatch_ctx,
		scheduler.p1_get_locks(dispatch_ctx)
	)
	_G.UC_LAST_SCHED_ACTION = ('[smn]%s:%s'):format(action_type, action_name)
	return true, 'BLOCK_SCHED_P1_SUMMONER_MAINTENANCE'
end

local function p1_dispatch_geo_maintenance(selected, settings)
	if not domain_ownership.is_enabled('maintenance') then
		return false, nil
	end
	local action_type = tostring(selected.action_type or '')
	if action_type ~= 'spell' and action_type ~= 'ja' then
		error('GEO maintenance dispatcher requires a spell or ja proposal')
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
	end
	local ctx = p1_build_ctx(settings)
	local valid, reason = scheduler.providers.geo_maintenance.revalidate(selected, ctx)
	if not valid then
		_G.UC_LAST_SCHED_ACTION = '[geo]commit_rejected:' .. tostring(reason)
		return false, nil
	end
	local action_name = tostring(selected.action_name or '')
	local ready, ready_reason, ready_kind = action_ready(action_name, tonumber(selected.target_id) or 0)
	if not ready or ready_kind ~= action_type then
		_G.UC_LAST_SCHED_ACTION = '[geo]not_ready:' .. tostring(ready_reason)
		return false, nil
	end
	if action_name == '' or action_name:find('"', 1, true) then
		error('GEO maintenance action name is not command-safe')
	end
	local target_kind = tostring(selected.target_kind or '')
	local detail = selected.detail
	if type(detail) ~= 'table' then
		error('GEO maintenance action requires proposal detail')
	end
	local geo_kind = tostring(detail.geo_kind or '')
	local target_member = {
		id = tonumber(selected.target_id) or 0,
		name = tostring(selected.target_name or ''),
		is_self = target_kind == 'self',
		is_mob = target_kind == 'mob',
	}
	if geo_kind == 'entrust' then
		if action_type ~= 'spell' or target_kind ~= 'party' then
			error('GEO Entrust follow-up requires a party-targeted spell')
		end
		target_member.use_entity_id = true
	end
	local command = build_action_command(action_name, action_type, target_member)
	local result = require('uc_scheduler_dispatcher').dispatch_intent({
		kind = 'send_command',
		source = 'unified_scheduler:geo_maintenance',
		command = command,
		meta = {
			action_type = action_type,
			action_name = action_name,
			provider = 'maintenance_geo',
			target_id = target_member.id,
		},
	}, {
		execute = true,
		send_command = windower.send_command,
	})
	if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
		return false, nil
	end
	if geo_kind == 'entrust' then
		scheduler.action_timeline_log('GEO_ENTRUST_DISPATCH', {
			action = action_name,
			target = target_member.name,
			target_id = target_member.id,
			dispatch_method = 'entity_id',
			entrust_buff = true,
		}, ('geo_entrust_dispatch:%s:%d'):format(action_name, target_member.id), 0.05)
	end
	scheduler.providers.geo_maintenance.note_dispatch(selected, ctx.now)
	action_mark_sent(action_type, {
		action_name = action_name,
		provider = 'maintenance_geo',
		target_id = target_member.id,
		target_name = target_member.name,
		target_kind = target_kind,
	})
	local dispatch_ctx = {
		now = ctx.now,
		tick = p1_number(scheduler.phase1.tick, 0),
	}
	scheduler.record_dispatch(dispatch_ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(
		dispatch_ctx,
		scheduler.p1_get_locks(dispatch_ctx)
	)
	_G.UC_LAST_SCHED_ACTION = ('[geo]%s:%s'):format(action_type, action_name)
	return true, 'BLOCK_SCHED_P1_GEO_MAINTENANCE'
end

local function p1_dispatch_pet_command(selected, settings)
	local provider_name = tostring(selected.provider or '')
	if provider_name == 'maintenance_summoner' then
		if not domain_ownership.is_enabled('maintenance') then
			return false, nil
		end
	elseif provider_name == 'pet_combat' then
		if not domain_ownership.is_enabled('combat') then
			return false, nil
		end
	else
		error('shared pet dispatcher received an unsupported provider: ' .. provider_name)
	end
	if tostring(selected.action_type or '') ~= 'pet' then
		error('shared pet dispatcher requires action_type pet')
	end
	local blocked, block_reason = action_dispatch_blocked()
	if blocked then
		return true, block_reason
	end
	local ctx = p1_build_ctx(settings)
	p1_prepare_pet_context(ctx)
	local valid, reason
	if provider_name == 'maintenance_summoner' then
		valid, reason = scheduler.providers.summoner_maintenance.revalidate(selected, ctx)
	else
		valid, reason = scheduler.providers.pet_combat.revalidate(selected, ctx)
	end
	if not valid then
		_G.UC_LAST_SCHED_ACTION = '[pet]commit_rejected:' .. tostring(reason)
		return false, nil
	end
	local detail = selected.detail
	if type(detail) ~= 'table' or type(detail.pet_command) ~= 'table' then
		error('pet proposal is missing captured command detail')
	end
	local command_spec = detail.pet_command
	local allowed, retry_reason = pet_command_coordinator.can_attempt(
		scheduler.pet_command_state,
		command_spec.retry_key,
		ctx.now
	)
	if not allowed then
		_G.UC_LAST_SCHED_ACTION = '[pet]blocked:' .. tostring(retry_reason)
		return false, nil
	end
	local command = require('uc_pet_commands').serialize(command_spec)
	local result = require('uc_scheduler_dispatcher').dispatch_intent({
		kind = 'send_command',
		source = 'unified_scheduler:pet_command',
		command = command,
		meta = {
			action_type = 'pet',
			pet_command_kind = command_spec.kind,
			action_name = command_spec.action_name,
			provider = provider_name,
			pet_id = command_spec.pet_id,
			target_id = command_spec.target_id,
			combat_generation = command_spec.combat_generation,
		},
	}, {
		execute = true,
		send_command = windower.send_command,
	})
	if type(result) ~= 'table' or result.ok ~= true or result.executed ~= true then
		return false, nil
	end
	pet_command_coordinator.begin(scheduler.pet_command_state, command_spec, ctx.now)
	local dispatch_ctx = { now = ctx.now, tick = p1_number(scheduler.phase1.tick, 0) }
	scheduler.record_dispatch(dispatch_ctx)
	scheduler.p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(
		dispatch_ctx,
		scheduler.p1_get_locks(dispatch_ctx)
	)
	_G.UC_LAST_SCHED_ACTION = ('[pet]%s:%s'):format(command_spec.kind, command_spec.action_name)
	return true, 'BLOCK_SCHED_P1_PET_COMMAND'
end

function scheduler.dispatch_selected_plan(settings)
	local phase = scheduler.phase1
	local selected = phase.last_selected
	if type(selected) ~= 'table' or type(phase.last_plan) ~= 'table' then
		return false, nil
	end
	if domain_ownership.is_enabled('combat') then
		local tank_spell_wait_locked = scheduler.p1_refresh_tank_spell_wait_lock(phase, now_s())
		if tank_spell_wait_locked then
			_G.UC_LAST_SCHED_ACTION = ('[p1]tank_spell_wait:%s'):format(tostring(phase.tank_pending_action or ''))
			return true, 'BLOCK_SCHED_P1_DARKLAUNCH_COMBAT_TANK_SPELL_WAIT'
		end
	end
	-- Defer defensive spells before cast settling can stop follow/preengage movement.
	-- The defensive sender checks again immediately before dispatch.
	if selected.provider == 'defensive_internal' and domain_ownership.is_enabled('defensive') then
		local movement_blocked, movement_reason = scheduler.defensive_spell_movement_blocked(selected, selected.action_type, now_s())
		if movement_blocked then
			return true, movement_reason
		end
	end
	local cast_movement_blocked, cast_movement_reason = scheduler.cast_movement_settle_blocked(selected)
	if cast_movement_blocked then
		return true, cast_movement_reason
	end
	local sch_preempt_reason = selected._sch_lane_preempt_reason
	if sch_preempt_reason ~= nil then
		if type(sch_preempt_reason) ~= 'string' or sch_preempt_reason == '' then
			error('Scholar lane preemption marker must be a non-empty string')
		end
		local sch_lane = require('uc_sch_runtime').lane_status()
		if sch_lane.reserved then
			local preempted, preempt_reason = require('uc_sch_runtime').preempt(
				sch_preempt_reason,
				now_s()
			)
			if preempted or preempt_reason ~= sch_preempt_reason then
				error('Scholar selected-action preemption did not abort the active sequence')
			end
			log_def_sched(('SCH_LANE_PREEMPT_DISPATCH action="%s" provider=%s lane=%s reason=%s'):format(
				tostring(selected.action_name or ''),
				tostring(selected.provider or ''),
				tostring(sch_lane.class),
				sch_preempt_reason
			))
		end
	end
	local provider = tostring(selected.provider or '')
	if provider == 'target_control' then
		if not domain_ownership.is_enabled('combat') then
			return false, nil
		end
		local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
		return scheduler.p1_dispatch_target_control(selected, ctx)
	end

	if provider == 'pull_control' then
		return p1_dispatch_pull_control(selected, settings)
	end
	if provider == 'camp_puller' then
		return p1_dispatch_camp_puller(selected, settings)
	end
	if provider == 'combat' or provider == 'encounter_kei' then
		return p1_dispatch_combat(selected, settings, phase)
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
	if provider == 'maintenance_brd' then
		return scheduler.p1_dispatch_maintenance_brd(selected, settings)
	end
	if provider == 'maintenance_sch' or provider == 'defensive_sch' then
		return scheduler.p1_dispatch_maintenance_sch(selected, settings)
	end
	if provider == 'maintenance_summoner' then
		if tostring(selected.action_type or '') == 'pet' then
			return p1_dispatch_pet_command(selected, settings)
		end
		return p1_dispatch_summoner_maintenance(selected, settings)
	end
	if provider == 'maintenance_geo' then
		return p1_dispatch_geo_maintenance(selected, settings)
	end
	if provider == 'pet_combat' then
		return p1_dispatch_pet_command(selected, settings)
	end
	return false, nil
end

local function try_charm_sleeper_emergency(settings, ctx)
	local proposals = {}
	scheduler.providers.charm_sleeper.collect(ctx, proposals)
	if #proposals == 0 then
		return false, nil
	end
	local ranked = p1_rank(ctx, proposals)
	local selected = ranked[1]
	if type(selected) ~= 'table' then
		log_def_sched('CHARM_SLEEP_EMERGENCY_HOLD reason=GLOBAL_LOCK')
		_G.UC_LAST_SCHED_ACTION = '[charm_sleep]blocked:global_lock'
		return true, 'BLOCK_CHARM_SLEEPER_GLOBAL_LOCK'
	end
	local plan = p1_build_dispatch_plan(ctx, selected)
	local commit_ok, commit_reason = p1_revalidate_plan_commit(ctx, selected, plan)
	if not commit_ok then
		log_def_sched(('CHARM_SLEEP_EMERGENCY_HOLD reason=%s'):format(tostring(commit_reason)))
		_G.UC_LAST_SCHED_ACTION = '[charm_sleep]blocked:' .. tostring(commit_reason)
		return true, 'BLOCK_CHARM_SLEEPER_COMMIT:' .. tostring(commit_reason)
	end
	scheduler.phase1.last_selected = selected
	scheduler.phase1.last_plan = plan
	_G.UC_SCHED_P1_SELECTED_PROVIDER = tostring(selected.provider or '')
	_G.UC_SCHED_P1_SELECTED_FAMILY = tostring(selected.family_id or '')
	local sch_lane = require('uc_sch_runtime').lane_status()
	if sch_lane.reserved then
		if sch_lane.atomic then
			log_def_sched(('CHARM_SLEEP_EMERGENCY_HOLD reason=SCH_ATOMIC_LANE lane=%s'):format(
				tostring(sch_lane.class)
			))
			_G.UC_LAST_SCHED_ACTION = '[charm_sleep]blocked:sch_atomic_lane'
			return true, 'BLOCK_CHARM_SLEEPER_SCH_ATOMIC_LANE'
		end
		selected._sch_lane_preempt_reason = 'charm_sleeper_preemption'
		log_def_sched(('SCH_LANE_PREEMPT_ELIGIBLE emergency=charm_sleeper lane=%s'):format(
			tostring(sch_lane.class)
		))
	end
	local acted, reason = scheduler.dispatch_selected_plan(settings)
	if acted then
		return true, reason
	end
	_G.UC_LAST_SCHED_ACTION = '[charm_sleep]blocked:dispatch_revalidation'
	return true, 'BLOCK_CHARM_SLEEPER_DISPATCH_REVALIDATION'
end

function scheduler.on_recovery_hold_entered()
	local phase = scheduler.phase1
	phase.last_selected = nil
	phase.last_plan = nil
	phase.last_noop_reason = recovery_hold.BLOCK_REASON
	_G.UC_SCHED_P1_SELECTED_PROPOSAL = ''
	_G.UC_SCHED_P1_SELECTED_PROVIDER = ''
	_G.UC_SCHED_P1_SELECTED_FAMILY = ''
	_G.UC_SCHED_P1_PLAN_PRELUDE = ''
	scheduler.action_timeline_log('RECOVERY_HOLD_ENTER', {
		reason = recovery_hold.BLOCK_REASON,
	}, 'recovery_hold_enter', 0)
end

_G.UC_SCHED_OnRecoveryHoldEntered = scheduler.on_recovery_hold_entered

function scheduler.process_tick(cadence)
	_G.UC_LAST_SCHED_ACTION = ''
	require('uc_encounter_runtime').observe(now_s())
	local s = get_settings()
	local combat_domain_enabled = domain_ownership.is_enabled('combat')
	local defensive_domain_enabled = domain_ownership.is_enabled('defensive')
	local movement_domain_enabled = domain_ownership.is_enabled('movement')
	local maintenance_domain_enabled = domain_ownership.is_enabled('maintenance')
	local tick_ctx = nil
	local function get_tick_ctx()
		if tick_ctx == nil then
			tick_ctx = p1_build_ctx(s)
		end
		return tick_ctx
	end
	enemy_effect_tracker.sweep_invalid()
	if type(cadence) == 'table' then
		s._sched_next_defensive_at = tonumber(cadence.next_defensive_at) or 0
		s._sched_next_maintenance_at = tonumber(cadence.next_maintenance_at) or 0
	end
	_G.UC_LOG_COMBAT_SCHED = uc_scheduler_config.debug_log_combat_sched(s)
	_G.UC_LOG_JA_SCHED = uc_scheduler_config.debug_log_ja_sched(s)
	_G.UC_LOG_JA_DEBUG = uc_scheduler_config.debug_log_ja_debug(s)
	_G.UC_LOG_DEF_SCHED = uc_scheduler_config.debug_log_def_sched(s)
	_G.UC_LOG_TANK_SCHED = uc_scheduler_config.debug_log_tank_sched(s)
	ensure_diag_logs_initialized()
	maybe_broadcast_party_state_ipc()
	if recovery_hold.current() then
		scheduler.phase1.last_selected = nil
		scheduler.phase1.last_plan = nil
		scheduler.phase1.last_noop_reason = recovery_hold.BLOCK_REASON
		_G.UC_LAST_SCHED_ACTION = '[recovery_hold]Weakness'
		_G.UC_TARGET_BLOCK_REASON = recovery_hold.BLOCK_REASON
		_G.UC_MOVEMENT_MODE = 'RECOVERY_HOLD'
		_G.UC_MOVEMENT_BLOCK_REASON = recovery_hold.BLOCK_REASON
		return true, recovery_hold.BLOCK_REASON
	end
	if not defensive_domain_enabled then
		scheduler.providers.sleep_waker.reset('DEFENSIVE_DOMAIN_DISABLED')
	end
	if not combat_domain_enabled and scheduler.providers.camp_puller.active() then
		p1_build_pull_executor().stop({
			reason = 'PULL_COMBAT_DOMAIN_DISABLED',
			provider = 'camp_puller',
		})
		scheduler.providers.camp_puller.reset('PULL_COMBAT_DOMAIN_DISABLED')
	end
	if not movement_domain_enabled and scheduler.providers.camp_puller.active() then
		p1_build_pull_executor().stop({
			reason = 'PULL_MOVEMENT_DOMAIN_DISABLED',
			provider = 'camp_puller',
		})
		scheduler.providers.camp_puller.reset('PULL_MOVEMENT_DOMAIN_DISABLED')
	end
	if not maintenance_domain_enabled and scheduler.providers.geo_maintenance.runtime_active() then
		scheduler.providers.geo_maintenance.reset('GEO_MAINTENANCE_DOMAIN_DISABLED')
	end
	if not maintenance_domain_enabled
		and require('uc_sch_runtime').snapshot().active_sequence ~= nil then
		require('uc_sch_runtime').cancel('maintenance_domain_disabled', now_s(), 0)
	end
	local geo_creation_preempts_pull = false
	if maintenance_domain_enabled then
		local geo_creation_ctx = get_tick_ctx()
		geo_creation_preempts_pull = scheduler.providers.geo_maintenance.creation_preempts_pull(geo_creation_ctx)
		geo_creation_ctx.geo_creation_preempts_pull = geo_creation_preempts_pull
	end
	if geo_creation_preempts_pull and scheduler.providers.camp_puller.active() then
		p1_build_pull_executor().stop({
			reason = 'PULL_PREEMPTED_FOR_GEO_CREATION',
			provider = 'camp_puller',
		})
		scheduler.providers.camp_puller.reset('PULL_PREEMPTED_FOR_GEO_CREATION')
	end
	local camp_lane_reserved = combat_domain_enabled and scheduler.providers.camp_puller.active()
	if defensive_domain_enabled then
		local charm_blocked, charm_reason = try_charm_sleeper_emergency(s, get_tick_ctx())
		if charm_blocked then
			return true, charm_reason
		end
	end
	if defensive_domain_enabled and not camp_lane_reserved then
		local doom_blocked, doom_reason = try_doom_water_emergency(s)
		if doom_blocked then
			local ctx = { now = now_s(), tick = p1_number(scheduler.phase1.tick, 0) }
			scheduler.record_dispatch(ctx)
			scheduler.p1_set_pending_globals()
			_G.UC_SCHED_P1_LOCK_SUMMARY = scheduler.p1_build_lock_summary(ctx, scheduler.p1_get_locks(ctx))
			return true, doom_reason
		end
	end
	if combat_domain_enabled and not camp_lane_reserved and not geo_creation_preempts_pull then
		local acquisition_ctx = get_tick_ctx()
		scheduler.p1_update_pending_state(acquisition_ctx)
		scheduler.providers.camp_puller.acquire_lane(acquisition_ctx)
		camp_lane_reserved = scheduler.providers.camp_puller.active()
	end
	if combat_domain_enabled and not camp_lane_reserved then
		local partner_blocked, partner_reason = scheduler.try_partner_tiebreak(s)
		if partner_blocked then
			return true, partner_reason
		end
	end
	scheduler.refresh_reaction_lock()
	local brd_lane_reserved, brd_lane_reason = false, ''
	if maintenance_domain_enabled then
		brd_lane_reserved, brd_lane_reason = require('uc_brd_maintenance').action_lane_status()
	end
	local sch_lane = require('uc_sch_runtime').lane_status()
	local sch_lane_holds = require('uc_sch_lane_policy').holds_movement_and_targeting(sch_lane)
	if not brd_lane_reserved and not camp_lane_reserved and not sch_lane_holds then
		local target_ctx = nil
		if combat_domain_enabled and type(rawget(_G, 'UC_REACTION_LOCK')) ~= 'table' then
			target_ctx = get_tick_ctx()
		end
		if combat_domain_enabled then
			local target_acted, target_reason = scheduler.p1_try_nonblocking_target_acquire(s, target_ctx)
			if target_acted then
				return true, target_reason
			end
		end
	elseif brd_lane_reserved and not camp_lane_reserved then
		scheduler.apply_brd_maintenance_lane_movement(brd_lane_reason, now_s())
		_G.UC_TARGET_BLOCK_REASON = 'BRD_LANE:' .. tostring(brd_lane_reason or '')
	elseif sch_lane_holds and not camp_lane_reserved then
		scheduler.apply_sch_lane_movement(sch_lane.reason, now_s())
		_G.UC_TARGET_BLOCK_REASON = 'SCH_LANE:' .. sch_lane.reason
	elseif camp_lane_reserved then
		_G.UC_TARGET_BLOCK_REASON = 'CAMP_PULL_ACTION_LANE'
	end
	if defensive_domain_enabled and not camp_lane_reserved then
		local defensive_spell_wait_locked = scheduler.refresh_defensive_spell_wait_lock(now_s())
		if defensive_spell_wait_locked then
			_G.UC_LAST_SCHED_ACTION = ('[def]spell_wait:%s'):format(tostring(scheduler.defensive_pending_action or ''))
			return true, 'BLOCK_DEFENSIVE_SPELL_WAITING'
		end
	end
	p1_run_dry(s, get_tick_ctx())
	local p1_acted, p1_reason = scheduler.dispatch_selected_plan(s)
	brd_lane_reserved, brd_lane_reason = false, ''
	if maintenance_domain_enabled then
		brd_lane_reserved, brd_lane_reason = require('uc_brd_maintenance').action_lane_status()
	end
	sch_lane = require('uc_sch_runtime').lane_status()
	sch_lane_holds = require('uc_sch_lane_policy').holds_movement_and_targeting(sch_lane)
	camp_lane_reserved = combat_domain_enabled and scheduler.providers.camp_puller.active()
	local move_acted, move_reason = false, ''
	if camp_lane_reserved or (not brd_lane_reserved and not sch_lane_holds) then
		move_acted, move_reason = run_movement_coordinator_tick()
	elseif brd_lane_reserved then
		scheduler.apply_brd_maintenance_lane_movement(brd_lane_reason, now_s())
		_G.UC_MOVEMENT_BLOCK_REASON = 'BRD_LANE:' .. tostring(brd_lane_reason or '')
	elseif sch_lane_holds then
		scheduler.apply_sch_lane_movement(sch_lane.reason, now_s())
		_G.UC_MOVEMENT_BLOCK_REASON = 'SCH_LANE:' .. sch_lane.reason
	end
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
	if camp_lane_reserved then
		_G.UC_LAST_SCHED_ACTION = '[p1]camp_pull_lane_hold'
		return true, 'BLOCK_CAMP_PULL_ACTION_LANE'
	end
	if brd_lane_reserved then
		_G.UC_LAST_SCHED_ACTION = '[p1]brd_lane_hold'
		return true, 'BLOCK_BRD_ACTION_LANE:' .. tostring(brd_lane_reason or '')
	end
	if sch_lane_holds then
		_G.UC_LAST_SCHED_ACTION = '[p1]sch_lane_hold'
		return true, 'BLOCK_SCH_ACTION_LANE:' .. sch_lane.reason
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
	if scheduler.p1_priority_bypasses_engage(top) then
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
		scheduler.providers.charm_sleeper.reset('ZONE_CHANGE')
		scheduler.providers.sleep_waker.reset('ZONE_CHANGE')
		scheduler.release_reaction_movement(rawget(_G, 'UC_REACTION_LOCK'), 'REACTION_ZONE_CHANGE_PACKET')
		require('uc_reaction_runtime').reset('zone_change')
		require('uc_encounter_runtime').reset('zone_change_packet')
		require('uc_lilith_easy_encounter').reset('zone_change_packet')
		require('uc_formation_runtime').reset('zone_change_packet')
		_G.UC_REACTION_LOCK = nil
		scheduler.phase1.effectiveTargets = {}
		pet_command_coordinator.reset(scheduler.pet_command_state, 'zone_change')
		require('uc_pet_combat_state').reset(scheduler.pet_combat_state)
		require('uc_pet_tp_state').reset(scheduler.pet_tp_state)
		_G.UC_SMN_PET_COMMAND_STATE = nil
		_G.UC_SMN_PET_COMBAT_STATUS = nil
		_G.UC_SMN_MAINTENANCE_STATUS = nil
		require('uc_brd_maintenance').reset('zone_change')
		require('uc_sch_runtime').reset('zone_change_packet', now_s())
		scheduler.providers.geo_maintenance.reset('GEO_ZONE_CHANGE')
		if scheduler.providers.camp_puller.active() then
			p1_build_pull_executor().stop({
				reason = 'PULL_ZONE_CHANGE',
				provider = 'camp_puller',
			})
		end
		scheduler.providers.camp_puller.reset('PULL_ZONE_CHANGE')
		require('uc_party_buff_tracker').reset()
		return
	end
	if (nid == 0x067 or nid == 0x068) and type(data) == 'string' then
		local player = windower.ffxi.get_player()
		local player_index = type(player) == 'table' and tonumber(player.index) or nil
		if player_index ~= nil and player_index > 0 then
			require('uc_pet_tp_state').ingest(
				scheduler.pet_tp_state,
				nid,
				data,
				player_index,
				require('packets').parse
			)
		end
		return
	end
	if nid == 0x076 and type(data) == 'string' then
		require('uc_party_buff_tracker').ingest(data, now_s())
		return
	end
	if nid == 0x028 and type(data) == 'string' then
		ingest_enemy_effects_from_raw_action_028(data)
		return
	end
	if nid == 0x037 and type(data) == 'string' then
		local parsed = require('packets').parse('incoming', data)
		if parsed and parsed['Timestamp'] and parsed['Time offset?'] then
			require('uc_brd_maintenance').on_server_clock(
				parsed['Timestamp'],
				parsed['Time offset?'],
				os.time()
			)
		end
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
			if require('uc_scheduler_enemy_effect_state').is_raw_death_message(mid) then
				enemy_effect_state_clear_target(tid)
			elseif require('uc_scheduler_enemy_effect_state').is_raw_remove_message(mid) then
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
	require('uc_brd_maintenance').on_status_snapshot(snap, now_s())
end

function scheduler.seed_cached_status_snapshot()
	require('uc_party_buff_tracker').seed_cached(windower.packets.last_incoming, now_s())
	local data = windower.packets.last_incoming(0x063)
	if type(data) ~= 'string' then
		return false
	end
	local snap = parse_status_snapshot_063(data)
	if type(snap) ~= 'table' then
		return false
	end
	local player = windower.ffxi.get_player()
	if not player or not player.name then
		return false
	end
	local st = ensure_maintenance_state_tables()
	st.status_snapshot[tostring(player.name)] = snap
	require('uc_brd_maintenance').on_status_snapshot(snap, now_s())
	return true
end

function scheduler.on_action(act)
	if type(act) == 'table' then
		local p = windower.ffxi.get_player()
		local observed_at = now_s()
		local player_id = tonumber(p and p.id) or 0
		if scheduler.providers and scheduler.providers.pet_combat then
			scheduler.providers.pet_combat.observe_pet_action(act, observed_at)
		end
		local pet_event = pet_command_coordinator.observe_action(
			scheduler.pet_command_state,
			act,
			observed_at
		)
		p1_apply_pet_command_event(pet_event)
		local _, brd_action_event = require('uc_brd_maintenance').on_action(act, player_id, observed_at)
		if player_id > 0 then
			scheduler.providers.sch_maintenance.observe_action(act, player_id, observed_at)
		end
		if brd_action_event == 'pianissimo_confirmed' then
			action_mark_packet_end({
				message_id = tonumber(act.category) or 0,
			})
			local brd_pending = scheduler.phase1 and scheduler.phase1.pending
			if type(brd_pending) == 'table'
				and tostring(brd_pending.provider or '') == 'maintenance_brd'
				and tostring(brd_pending.action_name or '') == 'Pianissimo' then
				scheduler.p1_pending_mark_complete(observed_at, 'brd_pianissimo_action')
			end
		end
		scheduler.observe_local_sleep_action(act, player_id, observed_at)
		scheduler.providers.charm_sleeper.observe_action(act, player_id, observed_at)
		if rawget(_G, 'Start_Engine') == true then
			local get_target = windower.ffxi.get_mob_by_target
			local target = type(get_target) == 'function' and get_target('t') or nil
			local reaction_actor_id = tonumber(act.actor_id) or 0
			local reaction_actor = reaction_actor_id > 0 and windower.ffxi.get_mob_by_id(reaction_actor_id) or nil
			local reaction_actor_is_valid_enemy = reaction_actor ~= nil
				and reaction_actor.valid_target == true
				and (tonumber(reaction_actor.spawn_type) or 0) == 16
				and (tonumber(reaction_actor.hpp) or 0) > 0
			local reaction_event = require('uc_reaction_runtime').on_action(
				act,
				tonumber(target and target.id) or 0,
				observed_at,
				reaction_actor_is_valid_enemy
			)
			if type(reaction_event.released) == 'table' then
				scheduler.release_reaction_movement(reaction_event.released, 'REACTION_ABILITY_WINDOW_COMPLETE')
			end
			if type(reaction_event.activated) == 'table' then
				_G.UC_REACTION_LOCK = reaction_event.activated
				scheduler.action_timeline_log('REACTION_ACTIVATED', {
					ability = tostring(reaction_event.activated.name or ''),
					response = tostring(reaction_event.activated.response or ''),
					actor_id = tonumber(reaction_event.activated.actor_id) or 0,
					target_distance = tonumber(reaction_event.activated.distance),
				}, ('reaction_activated:%s:%d'):format(
					tostring(reaction_event.activated.name or ''),
					tonumber(reaction_event.activated.actor_id) or 0
				), 0)
				if not scheduler.providers.camp_puller.active() then
					scheduler.apply_reaction_response(reaction_event.activated)
				end
			elseif (tonumber(reaction_event.released_target_id) or 0) > 0 then
				_G.UC_REACTION_LOCK = nil
				local current_target_id = tonumber(target and target.id) or 0
				if current_target_id > 0
					and not scheduler.providers.camp_puller.active() then
					scheduler.apply_reaction_turn({ actor_id = current_target_id }, false)
				end
			end
		end
		local observed_effect_set = scheduler.reaction_observed_effect_set()
		local catalog_events = {}
		tb_effect_table.apply_from_action(
			act,
			player_id,
			function(target_id, effect_id, source, now, duration)
				enemy_effect_state_set(target_id, effect_id, source, now, duration)
				local event = enemy_effect_tracker.observe_effect(target_id, effect_id, source, observed_effect_set)
				if event then
					catalog_events[#catalog_events + 1] = event
				end
			end,
			function(target_id, effect_id)
				enemy_effect_state_clear(target_id, effect_id)
				local event = enemy_effect_tracker.clear_effect(target_id, effect_id)
				if event then
					catalog_events[#catalog_events + 1] = event
				end
			end,
			observed_at
		)
		for _, event in ipairs(catalog_events) do
			enemy_dispel_log(('ENEMY_TRACK event=%s source=%s target=%d effect=%d'):format(
				tostring(event.event or ''),
				tostring(event.source or ''),
				tonumber(event.target_id) or 0,
				tonumber(event.effect_id) or 0
			))
		end
	end
	local enemy_buff_remove = bool_setting(uc_scheduler_config.defensive_enemy_buffs_remove(), false)
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
	local evs = enemy_effect_tracker.on_action(act, scheduler.reaction_observed_effect_set()) or {}
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
	if _G.UC_LOG_DEF_SCHED and enemy_buff_remove then
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
							if eid > 0
								and not require('uc_scheduler_enemy_effect_state').is_dispellable(eid) then
								local k = ('act:%d:%d'):format(eid, tonumber(a and a.message) or 0)
								if require('uc_scheduler_enemy_effect_state').observe_unknown_once(k) then
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
		[6] = true,
		[8] = true,
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
		local local_spell_finished = scheduler.handle_local_spell_finish_action(act, my_id, now_s())
		local local_ws_result = category_value == 3 or category == 'weaponskill_finish'
		if local_ws_result then
			require('uc_scheduler_action_state').action_mark_ws_result(scheduler, now_s, {
				category = category_value or 0,
				target_id = tonumber(act and act.targets and act.targets[1] and act.targets[1].id) or 0,
			})
		end
		-- HealBot-style actor-centric start lock, but scoped to real cast/action categories.
		-- Do not treat generic/melee action traffic as lock-start signals.
		if not local_spell_finished and start_lock_categories[category_value] then
			require('uc_scheduler_action_state').note_local_spell_packet_start(scheduler, now_s, {
				message_id = category_value or 0,
			})
		elseif not local_spell_finished and start_lock_categories[category] then
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
	if tostring(pending.action_type or '') == 'pet' then
		return
	end
	if tostring(pending.provider or '') == 'maintenance_geo'
		and tostring(pending.action_type or '') == 'ja' then
		local completed, completion_reason =
			scheduler.providers.geo_maintenance.note_ja_action(act, my_id)
		if completed then
			scheduler.p1_pending_mark_complete(now, completion_reason)
			scheduler.action_timeline_log('GEO_JA_COMPLETED', {
				action = tostring(pending.action_name or ''),
				actor_id = actor_id,
				action_category = category_value or 0,
				action_param = tonumber(act and act.param) or 0,
				target_id = tonumber(act and act.targets and act.targets[1] and act.targets[1].id) or 0,
				completion_reason = completion_reason,
			}, ('geo_ja_completed:%s:%d'):format(
				tostring(pending.action_name or ''),
				tonumber(act and act.param) or 0
			), 0.05)
		elseif actor_id == my_id then
			scheduler.action_timeline_log('GEO_JA_PACKET_IGNORED', {
				action = tostring(pending.action_name or ''),
				actor_id = actor_id,
				action_category = category_value or 0,
				action_param = tonumber(act and act.param) or 0,
				reason = completion_reason,
			}, ('geo_ja_ignored:%s:%s:%d'):format(
				tostring(pending.action_name or ''),
				tostring(completion_reason or ''),
				tonumber(act and act.param) or 0
			), 0.25)
		end
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
				if tostring(pending.provider or '') == 'camp_puller'
					and tostring(pending.action_type or '') == 'ja' then
					scheduler.providers.camp_puller.note_action_result(
						true,
						now,
						camp_pulling_config()
					)
				end
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
	local enemy_buff_remove = bool_setting(uc_scheduler_config.defensive_enemy_buffs_remove(), false)
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
	local evs = enemy_effect_tracker.on_action_message(msg, scheduler.reaction_observed_effect_set()) or {}
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
	if _G.UC_LOG_DEF_SCHED and enemy_buff_remove then
		local actor_id = tonumber(msg and msg.actor_id) or 0
		local target_id = tonumber(msg and msg.target_id) or 0
		local effect_id = tonumber(msg and msg.param_1) or 0
		local message_id = tonumber(msg and msg.message_id) or 0
		local target = target_id > 0 and windower.ffxi.get_mob_by_id(target_id) or nil
		if effect_id > 0 and target and tonumber(target.spawn_type) == 16
			and target_id == actor_id
			and not require('uc_scheduler_enemy_effect_state').is_dispellable(effect_id) then
			local k = ('msg:%d:%d'):format(effect_id, message_id)
			if require('uc_scheduler_enemy_effect_state').observe_unknown_once(k) then
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
	scheduler.providers.sch_maintenance.observe_action_message(msg, my_id, now)
	local pet_event = pet_command_coordinator.observe_action_message(
		scheduler.pet_command_state,
		msg,
		my_id,
		now
	)
	p1_apply_pet_command_event(pet_event)
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
	end
	local pending = phase.pending
	if type(pending) ~= 'table' then
		return
	end
	if tostring(pending.provider or '') == 'maintenance_summoner'
		and my_id ~= 0
		and actor_id == my_id
		and pet_command_coordinator.is_failure_message(message_id) then
		scheduler.p1_pending_mark_failed(now, ('summoner_action_message_%d'):format(message_id), 1.0)
		return
	end
	if tostring(pending.provider or '') == 'maintenance_geo'
		and my_id ~= 0
		and actor_id == my_id
		and pet_command_coordinator.is_failure_message(message_id) then
		scheduler.providers.geo_maintenance.note_failure(
			tostring(pending.action_name or ''),
			now
		)
		scheduler.p1_pending_mark_failed(now, ('geo_action_message_%d'):format(message_id), 2.0)
		return
	end
	if tostring(pending.provider or '') == 'camp_puller'
		and my_id ~= 0
		and actor_id == my_id
		and pet_command_coordinator.is_failure_message(message_id) then
		scheduler.providers.camp_puller.note_action_result(
			false,
			now,
			camp_pulling_config()
		)
		scheduler.p1_pending_mark_failed(now, ('camp_pull_action_message_%d'):format(message_id), 2.0)
		return
	end
	if tostring(pending.action_type or '') == 'pet' then
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
	local function enabled_for_provider(provider)
		local p = tostring(provider or '')
		if p == 'combat' then
			return domain_ownership.is_enabled('combat')
		elseif p == 'camp_puller' then
			return domain_ownership.is_enabled('combat')
		elseif p == 'defensive_internal' then
			return domain_ownership.is_enabled('defensive')
		elseif p == 'defensive_healbot' then
			return domain_ownership.is_enabled('defensive')
		elseif p == 'maintenance_cor' then
			return domain_ownership.is_enabled('maintenance')
		elseif p == 'maintenance_brd' then
			return domain_ownership.is_enabled('maintenance')
		elseif p == 'maintenance_summoner' then
			return domain_ownership.is_enabled('maintenance')
		elseif p == 'maintenance_sch' then
			return domain_ownership.is_enabled('maintenance')
		elseif p == 'defensive_sch' then
			return domain_ownership.is_enabled('defensive')
		elseif p == 'maintenance_geo' then
			return domain_ownership.is_enabled('maintenance')
		elseif p == 'pet_combat' then
			return domain_ownership.is_enabled('combat')
		end
		return false
	end
	return require('uc_scheduler_observability').build_debug_overlay(phase, {
		provider_enabled = enabled_for_provider,
		get_party_members = get_party_members,
		resources_buffs = res and res.buffs,
		get_player = windower.ffxi.get_player,
		get_party_state_ipc_entry = get_party_state_ipc_entry,
		get_party = windower.ffxi.get_party,
		ensure_maintenance_state_tables = ensure_maintenance_state_tables,
	})
end

function scheduler.geo_maintenance_status()
	return scheduler.providers.geo_maintenance.status_snapshot()
end

function scheduler.sch_maintenance_status()
	return scheduler.providers.sch_maintenance.status_snapshot()
end

function scheduler.sch_maintenance_status_lines()
	return scheduler.providers.sch_maintenance.status_lines(now_s())
end

local function sch_capture_player()
	local player = windower.ffxi.get_player()
	if type(player) ~= 'table' or tostring(player.main_job or '') ~= 'SCH' then
		return nil, 'Scholar capture requires SCH as the current main job.'
	end
	if rawget(_G, 'Start_Engine') ~= true then
		return nil, 'Scholar capture requires the UnifiedCombat engine to be running.'
	end
	if not domain_ownership.is_enabled('maintenance') then
		return nil, 'Scholar capture requires the maintenance domain to be enabled.'
	end
	if type(player.name) ~= 'string' or player.name == '' then
		error('Scholar capture player name is unavailable')
	end
	return player, nil
end

function scheduler.sch_maintenance_trace_once()
	local player, reason = sch_capture_player()
	if player == nil then
		return false, reason:gsub('capture', 'trace', 1)
	end
	return scheduler.providers.sch_maintenance.arm_trace_once(now_s())
end

function scheduler.sch_maintenance_capture_start(label)
	local player, reason = sch_capture_player()
	if player == nil then
		return false, reason, nil
	end
	return scheduler.providers.sch_maintenance.start_capture({
		label = label,
		character = player.name,
		main_job = player.main_job,
		sub_job = player.sub_job,
	}, now_s())
end

function scheduler.sch_maintenance_capture_mark(label)
	return scheduler.providers.sch_maintenance.mark_capture(label, now_s())
end

function scheduler.sch_maintenance_capture_stop(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('Scholar capture stop reason must be a non-empty string')
	end
	return scheduler.providers.sch_maintenance.stop_capture(reason, now_s())
end

function scheduler.sch_maintenance_capture_status()
	return scheduler.providers.sch_maintenance.capture_status()
end

function scheduler.sch_maintenance_trace_snapshot()
	return scheduler.providers.sch_maintenance.trace_snapshot()
end

function scheduler.sch_maintenance_trace_lines()
	local trace = scheduler.sch_maintenance_trace_snapshot()
	local record = type(trace.active) == 'table' and trace.active or trace.last
	if type(record) ~= 'table' then
		return nil
	end
	return require('uc_sch_diagnostics').trace_lines(record)
end

function scheduler.geo_maintenance_reseed()
	return scheduler.providers.geo_maintenance.reseed()
end

function scheduler.geo_maintenance_arm_bolster(armed)
	return scheduler.providers.geo_maintenance.arm_bolster(armed)
end

function scheduler.camp_puller_status()
	return scheduler.providers.camp_puller.status_snapshot()
end

function scheduler.reset_runtime_locks()
	scheduler_locks.reset_runtime_locks(_G, action_state)
	scheduler.release_reaction_movement(rawget(_G, 'UC_REACTION_LOCK'), 'REACTION_SCHEDULER_LOCK_RESET')
	require('uc_reaction_runtime').reset('scheduler_lock_reset')
	require('uc_sch_runtime').reset('scheduler_lock_reset', now_s())
	_G.UC_REACTION_LOCK = nil
	_G.UC_CAST_MOVEMENT_SETTLE_UNTIL = nil
	_G.UC_SCHED_CAST_LOCAL_ACTOR = nil
end

_G.UC_ResetSchedulerRuntimeLocks = function()
	if scheduler and type(scheduler.reset_runtime_locks) == 'function' then
		scheduler.reset_runtime_locks()
	end
end

local function smn_player_is_moving()
	local lor_actor_mod = require('lor/lor_actor')
	if type(lor_actor_mod) ~= 'table'
		or type(lor_actor_mod.Actor) ~= 'table'
		or type(lor_actor_mod.Actor.new) ~= 'function' then
		error('Summoner maintenance lor/lor_actor contract is invalid')
	end
	local actor = rawget(_G, 'UC_SCHED_SMN_LOCAL_ACTOR')
	if actor == nil then
		actor = lor_actor_mod.Actor.new()
		rawset(_G, 'UC_SCHED_SMN_LOCAL_ACTOR', actor)
	end
	if type(actor) ~= 'table' or type(actor.is_moving) ~= 'function' then
		error('Summoner maintenance local actor contract is invalid')
	end
	return actor:is_moving() == true
end

function scheduler.get_enemy_effect_table_overlay()
	enemy_effect_state_prune_expired(now_s())
	return require('uc_scheduler_observability').build_enemy_effect_overlay(
		enemy_effect_state_map(),
		{
			resources_buffs = res and res.buffs,
			get_mob_by_id = windower.ffxi.get_mob_by_id,
		}
	)
end

scheduler.providers = {}
local smn_pet_combat_adapter = require('uc_smn_pet_combat_adapter').new({
	get_ja_resource = get_ja_resource,
	action_effective_range = action_effective_range,
})
scheduler.providers.pet_combat = require('uc_pet_combat_provider').new({
	adapter = smn_pet_combat_adapter,
	state = scheduler.pet_combat_state,
	target_is_actionable = combat_core.is_live_actionable_combat_target,
	coordinator_can_attempt = function(retry_key, at)
		return pet_command_coordinator.can_attempt(scheduler.pet_command_state, retry_key, at)
	end,
})
scheduler.providers.summoner_maintenance = require('uc_smn_maintenance').new({
	action_ready = action_ready,
	coordinator_can_attempt = function(retry_key, at)
		return pet_command_coordinator.can_attempt(scheduler.pet_command_state, retry_key, at)
	end,
	player_is_moving = smn_player_is_moving,
	get_ja_resource = get_ja_resource,
	log = log_def_sched,
})
function scheduler.sch_sublimation_safety(ctx, proposals)
	if type(ctx) ~= 'table' then
		error('Scholar Sublimation safety requires scheduler context')
	end
	if type(ctx.settings) ~= 'table' then
		error('Scholar Sublimation safety requires scheduler settings')
	end
	if type(ctx.player) ~= 'table' then
		error('Scholar Sublimation safety requires the player snapshot')
	end
	if type(proposals) ~= 'table' then
		error('Scholar Sublimation safety requires the current proposal set')
	end
	return require('uc_sch_sublimation').scheduler_safety({
		proposals = proposals,
		player_doom_present = player_has_doom(ctx.player),
		defensive_evidence_current = ctx.sch_defensive_evidence_current,
		is_critical_defensive = function(proposal)
			return scheduler.p1_is_critical_defensive_proposal(ctx.settings, proposal)
		end,
		source = 'unified_scheduler:existing_critical_defense_doom_charm_signals',
	})
end
scheduler.providers.sch_maintenance = require('uc_provider_sch_maintenance').new({
	capture = require('uc_sch_capture').new(),
	get_party_members = get_party_members,
	resolve_spell_name = function(id)
		local spell = res.spells[id]
		if spell == nil then
			return nil
		end
		if type(spell.en) ~= 'string' or spell.en == '' then
			error('Scholar spell resource is missing its English name')
		end
		return spell.en
	end,
	resolve_ability_name = function(id)
		local ability = res.job_abilities[id]
		if ability == nil then
			return nil
		end
		if type(ability.en) ~= 'string' or ability.en == '' then
			error('Scholar job ability resource is missing its English name')
		end
		return ability.en
	end,
	get_action_result_catalog = require('uc_sch_action_results').production_catalog,
	get_charge_catalog = require('uc_sch_charge_model').production_catalog,
	get_area_mechanics = require('uc_sch_area_planner').production_mechanics,
	action_ready = action_ready,
	sch_spell_ready = sch_spell_ready,
	select_cure_spell = sch_select_cure_spell,
	status_removal_for_buff = function(buff_id)
		local id = tonumber(buff_id)
		local buff = id and res.buffs[id] or nil
		if buff == nil then return nil end
		local spell = debuff_map[buff.en] or debuff_spell_for_buff_id(id)
		if spell == nil then return nil end
		local status_key = normalize_status_removal_key(buff)
		return {
			buff_id = id,
			spell = spell,
			status_key = status_key,
			priority = status_removal_priority[status_key] or 5,
		}
	end,
	is_critical_defensive = function(proposal, settings)
		return scheduler.p1_is_critical_defensive_proposal(settings, proposal)
	end,
	get_sublimation_safety = scheduler.sch_sublimation_safety,
	get_sublimation_release_mechanics = require('uc_sch_sublimation').production_release_mechanics,
	ignore_trusts = function(settings)
		local value = settings.def_heal_ignore_trusts
		if type(value) ~= 'boolean' then
			error('normalized defensive cure ignore_trusts setting is required')
		end
		return value
	end,
	routine_priority = scheduler.PRIORITY_BAND_SCH_ROUTINE,
	prepared_priority = scheduler.PRIORITY_BAND_SCH_PREPARED,
	defensive_priority = scheduler.PRIORITY_BAND_SCH_DEFENSIVE,
	log = log_def_sched,
})
scheduler.providers.geo_maintenance = require('uc_geo_maintenance').new({
	geo_maintenance_priority = scheduler.PRIORITY_BAND_GEO_MAINTENANCE,
	geo_creation_priority = scheduler.PRIORITY_BAND_GEO_CREATION,
	action_ready = action_ready,
	get_spell_resource = get_spell_resource,
	get_ja_resource = get_ja_resource,
	get_party_members = get_party_members,
	get_friendly_claims = function(ctx)
		local _, claim_set = uc_targeting_common.get_friendly_combat_member_ids({
			party = ctx.party,
		})
		return claim_set
	end,
	resolve_camp_anchor = require('uc_camp_anchor').resolve_current_anchor,
	action_effective_range = action_effective_range,
	target_is_actionable = combat_core.is_live_actionable_combat_target,
	target_is_ignored = function(settings, mob)
		return require('uc_target_ignore').is_mob_blocked(settings, mob)
	end,
	player_is_moving = smn_player_is_moving,
	pull_active = function()
		if scheduler.providers.camp_puller
			and scheduler.providers.camp_puller.active() then
			return true
		end
		local pending = scheduler.phase1 and scheduler.phase1.pending
		if type(pending) == 'table'
			and scheduler.p1_pending_is_live_state(tostring(pending.state or ''))
			and tostring(pending.provider or '') == 'pull_control' then
			return true
		end
		return rawget(_G, 'UC_PULL_SPELL_WAITING') == true
			or (tonumber(rawget(_G, 'UC_PULL_APPROACH_UNTIL')) or 0) > now_s()
	end,
	log = log_def_sched,
	action_timeline_log = function(...)
		return scheduler.action_timeline_log(...)
	end,
})
scheduler.providers.defensive = require('uc_provider_defensive').new({
	bool_setting = bool_setting,
	active_value_or_flat = scheduler.active_value_or_flat,
	build_defensive_candidates = build_defensive_candidates,
	choose_defensive_action = choose_defensive_action,
	action_ready = action_ready,
	action_range = function(action_name, action_kind)
		local resource = action_kind == 'spell' and get_spell_resource(action_name) or get_ja_resource(action_name)
		if type(resource) ~= 'table' or tonumber(resource.range) == nil then
			error(('defensive action %s has no authoritative resource range'):format(tostring(action_name)))
		end
		return action_effective_range(resource.range)
	end,
	build_action_command = build_action_command,
	cure_target_allowed = function(target_id, target_kind)
		if tostring(target_kind or '') == 'self' then
			return true
		end
		local mob = windower.ffxi.get_mob_by_id(tonumber(target_id) or 0)
		return type(mob) == 'table' and mob.charmed ~= true
	end,
	clamp_urgency = p1_clamp_urgency,
	critical_cure_priority = scheduler.PRIORITY_BAND_CRITICAL_CURE,
})
scheduler.providers.charm_sleeper = require('uc_provider_charm_sleeper').new({
	bool_setting = bool_setting,
	active_value_or_flat = scheduler.active_value_or_flat,
	get_party_members = get_party_members,
	get_mob_by_id = windower.ffxi.get_mob_by_id,
	action_ready = action_ready,
	get_spell_resource = get_spell_resource,
	get_player = windower.ffxi.get_player,
	get_mjob_data = windower.ffxi.get_mjob_data,
	get_sjob_data = windower.ffxi.get_sjob_data,
	action_effective_range = action_effective_range,
	action_target_mode = action_target_mode,
	build_action_command = build_action_command,
	has_buff = has_buff,
	clamp_urgency = p1_clamp_urgency,
	log = log_def_sched,
	policy = require('uc_charm_sleeper_policy').get(windower.addon_path),
	spell_effect_gain_messages = scheduler.spell_effect_gain_messages,
	priority_band = scheduler.PRIORITY_BAND_CHARM_SLEEPER,
})
scheduler.providers.sleep_waker = require('uc_provider_sleep_waker').new({
	bool_setting = bool_setting,
	active_value_or_flat = scheduler.active_value_or_flat,
	get_party_members = get_party_members,
	get_mob_by_id = windower.ffxi.get_mob_by_id,
	in_party_cast_range = in_party_cast_range,
	action_ready = action_ready,
	build_action_command = build_action_command,
	clamp_urgency = p1_clamp_urgency,
	log = log_def_sched,
	sleep_status = sleep_status,
	priority_band = scheduler.PRIORITY_BAND_SLEEP_WAKE,
})
scheduler.providers.enemy_buff_removal = require('uc_provider_enemy_buff_removal').new({
	bool_setting = bool_setting,
	active_value_or_flat = scheduler.active_value_or_flat,
	log = enemy_dispel_log,
	build_friendly_claims = uc_targeting_common.build_friendly_claims,
	list_targets = enemy_effect_tracker.list_targets,
	get_effects = enemy_effect_tracker.get_effects,
	claim_valid = enemy_dispel_claim_valid,
	is_dispellable = require('uc_scheduler_enemy_effect_state').is_dispellable,
	dispel_priority = require('uc_scheduler_enemy_effect_state').dispel_priority,
	diag = enemy_dispel_diag,
	choose_action = enemy_dispel_choose_action,
	effect_label = enemy_effect_log_label,
	can_attempt = can_attempt_enemy_dispel,
	action_ready = action_ready,
	build_action_command = build_action_command,
	clamp_urgency = p1_clamp_urgency,
})
scheduler.providers.enemy_debuff_maintenance = require('uc_provider_enemy_debuff_maintenance').new({
	bool_setting = bool_setting,
	active_value_or_flat = scheduler.active_value_or_flat,
	get_spell_resource = get_spell_resource,
	get_spell_by_id = function(spell_id)
		return res.spells[tonumber(spell_id) or 0]
	end,
	build_friendly_claims = uc_targeting_common.build_friendly_claims,
	claim_valid = enemy_dispel_claim_valid,
	effect_map = enemy_effect_state_map,
	prune_expired = enemy_effect_state_prune_expired,
	can_attempt = can_attempt_enemy_debuff,
	action_ready = action_ready,
	build_action_command = build_action_command,
	clamp_urgency = p1_clamp_urgency,
	log = enemy_dispel_log,
})
scheduler.providers.tank_enmity = require('uc_provider_tank_enmity').new({
	bool_setting = bool_setting,
	select_tank_enmity = combat_core.select_tank_enmity_for_scheduler,
	action_ready = action_ready,
	action_effective_range = action_effective_range,
	log_tank_sched = log_tank_sched,
	clamp_urgency = p1_clamp_urgency,
})
scheduler.providers.target_control = require('uc_provider_target_control').new({
	bool_setting = bool_setting,
	combat_autotarget = uc_scheduler_config.combat_autotarget,
	combat_domain_enabled = function()
		return domain_ownership.is_enabled('combat')
	end,
	tank_enabled = uc_scheduler_config.tank_enabled,
	select_target = combat_core.select_target_for_scheduler,
	add_control_enabled = combat_core.add_control_enabled_for_scheduler,
	select_pull = combat_core.select_pull_for_scheduler,
	action_timeline_log = function(...)
		return scheduler.action_timeline_log(...)
	end,
	clamp_urgency = p1_clamp_urgency,
	tank_target_priority = scheduler.TANK_TARGET_ACQUIRE_PRIORITY,
	tank_target_urgency = scheduler.TANK_TARGET_ACQUIRE_URGENCY,
	death_switch_priority = scheduler.PRIORITY_BAND_DEATH_SWITCH,
	death_switch_urgency = 1.0,
})
scheduler.providers.combat = require('uc_provider_combat').new({
	bool_setting = bool_setting,
	clamp_urgency = p1_clamp_urgency,
	build_partner_target_set = build_partner_target_set,
	select_ws_plan = combat_core.select_ws_plan_for_scheduler,
	action_timeline_log = function(...)
		return scheduler.action_timeline_log(...)
	end,
	combat_domain_enabled = function()
		return domain_ownership.is_enabled('combat')
	end,
	sleep_enabled = require('uc_runtime_overrides').sleep_enabled,
	sleep_spell_list = scheduler.sleep_spell_list_from_settings,
	is_live_actionable_target = combat_core.is_live_actionable_combat_target,
	build_friendly_claims = uc_targeting_common.build_friendly_claims,
	mob_targets_friendly_member = uc_targeting_common.mob_targets_friendly_member,
	sleep_max_target_distance = scheduler.sleep_max_target_distance,
	target_sleep_suppressed = scheduler.target_sleep_suppressed,
	select_sleep_spell = scheduler.select_sleep_spell_for_target,
	combat_autotarget = uc_scheduler_config.combat_autotarget,
	tank_enabled = uc_scheduler_config.tank_enabled,
	debug_enabled = uc_scheduler_config.debug_enabled,
	combat_prime = uc_scheduler_config.combat_prime,
	fight_leader_enabled = require('uc_runtime_overrides').fight_leader_enabled,
	fight_leader_id = require('uc_runtime_overrides').fight_leader_id,
	fight_leader_target_id = uc_fight_leader.leader_target_id,
	add_control_enabled = combat_core.add_control_enabled_for_scheduler,
	select_pull = combat_core.select_pull_for_scheduler,
	build_party_id_set = p1_build_party_id_set,
	prime_unclaimed_party_aggressive_ok = p1_prime_unclaimed_party_aggressive_ok,
	pending_engage_state = scheduler.p1_pending_engage_state,
	pending_engage_live = scheduler.p1_pending_engage_live,
	collect_ordered_abilities = ability_pipeline.collect_ordered,
	get_ja_resource = get_ja_resource,
	action_ready = action_ready,
	action_effective_range = action_effective_range,
	log_ja_sched = log_ja_sched,
	phase1 = scheduler.phase1,
	action_state = scheduler.action_state,
	skillchain_priority = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION,
	aftermath_priority = scheduler.PRIORITY_BAND_AFTERMATH_WS,
	sleep_priority = scheduler.PRIORITY_BAND_SLEEP,
	tank_engage_priority = scheduler.TANK_ENGAGE_PRIORITY,
	default_engage_priority = scheduler.DEFAULT_ENGAGE_PRIORITY,
	tank_engage_urgency = scheduler.TANK_ENGAGE_URGENCY,
	default_engage_urgency = scheduler.DEFAULT_ENGAGE_URGENCY,
})
scheduler.providers.kei = require('uc_provider_kei').new({
	snapshot = require('uc_kei_encounter').snapshot,
	spell_for = require('uc_kei_encounter').spell_for,
	action_ready = action_ready,
	clamp_urgency = p1_clamp_urgency,
	reaction_active = function()
		return type(rawget(_G, 'UC_REACTION_LOCK')) == 'table'
	end,
	keepalive_priority = scheduler.PRIORITY_BAND_SKILLCHAIN_CONTINUATION,
	opportunistic_priority = 70,
})
scheduler.providers.camp_puller = require('uc_camp_puller').new({
	resolve_camp_anchor = require('uc_camp_anchor').resolve_current_anchor,
	get_zone_id = current_zone_id,
	send_ipc_message = windower.send_ipc_message,
	get_friendly_claims = function()
		local _, id_set = uc_targeting_common.get_friendly_combat_member_ids()
		return id_set
	end,
	ignored = function(settings, mob)
		return require('uc_target_ignore').is_mob_blocked(settings, mob)
	end,
	get_spell_resource = get_spell_resource,
	get_ja_resource = get_ja_resource,
	action_effective_range = action_effective_range,
	action_ready = action_ready,
	log = log_combat_sched,
	action_timeline_log = function(...)
		return scheduler.action_timeline_log(...)
	end,
	can_start_journey = function()
		if not domain_ownership.is_enabled('movement') then
			return false, 'MOVEMENT_DOMAIN_DISABLED'
		end
		if require('uc_nyzul_runtime').is_movement_held() then
			return false, 'NYZUL_MOVEMENT_HOLD'
		end
		if type(rawget(_G, 'UC_REACTION_LOCK')) == 'table' then
			return false, 'REACTION_LANE'
		end
		local pending = scheduler.phase1 and scheduler.phase1.pending
		if type(pending) == 'table'
			and scheduler.p1_pending_is_live_state(tostring(pending.state or '')) then
			return false, ('SCHEDULER_PENDING:%s:%s'):format(
				tostring(pending.provider or ''),
				tostring(pending.action_name or '')
			)
		end
		if domain_ownership.is_enabled('maintenance') then
			local brd_reserved, brd_reason = require('uc_brd_maintenance').action_lane_status()
			if brd_reserved then
				return false, 'BRD_LANE:' .. tostring(brd_reason or '')
			end
			local sch_lane = require('uc_sch_runtime').lane_status()
			if sch_lane.atomic then
				return false, 'SCH_ATOMIC_LANE:' .. tostring(sch_lane.reason or '')
			end
			if scheduler.providers.geo_maintenance.lane_reserved()
				and not scheduler.providers.geo_maintenance.pull_for_enemy_allowed() then
				return false, 'GEO_LANE'
			end
		end
		return true, ''
	end,
	pull_action_in_flight = function(target_id, action_type, action_name)
		local st = action_state() or {}
		if tostring(st.last_action_provider or '') ~= 'camp_puller'
			or tonumber(st.last_target_id) ~= tonumber(target_id)
			or tostring(st.last_send_kind or '') ~= tostring(action_type or '')
			or tostring(st.last_action_name or '') ~= tostring(action_name or '') then
			return false
		end
		return action_is_acting()
	end,
})
scheduler.providers.maintenance = require('uc_provider_maintenance').new({
	bool_setting = bool_setting,
	log_def_sched = log_def_sched,
	is_city_zone = is_city_zone_for_maintenance,
	ensure_buff_cache = ensure_maintenance_buff_cache,
	number = p1_number,
	clamp_urgency = p1_clamp_urgency,
	action_timeline_action_state_summary = function(...)
		return scheduler.action_timeline_action_state_summary(...)
	end,
	action_timeline_log = function(...)
		return scheduler.action_timeline_log(...)
	end,
	cor_propose = cor_maintenance.propose,
	get_party_members = get_party_members,
	action_ready = action_ready,
	clear_local_brd_spell_failure = function(...)
		return scheduler.clear_local_brd_spell_failure(...)
	end,
	pending_mark_failed = function(...)
		return scheduler.p1_pending_mark_failed(...)
	end,
	count_matching_buffs = count_matching_buffs,
	phase1 = scheduler.phase1,
	maintenance_buff_cache = maintenance_buff_cache,
	action_timeline_state = scheduler.action_timeline_state,
	brd_maintenance_priority = scheduler.PRIORITY_BAND_BRD_MAINTENANCE,
})

return scheduler

