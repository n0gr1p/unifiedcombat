local res = require('resources')

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
		last_plan = nil,
		pending = nil,
		recent_duplicate_until = {},
	},
}

local can_act_statuses = { [0] = true, [1] = true, [5] = true, [85] = true }
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

local buff_priority = {
	['Afflatus Solace'] = 0, ['Majesty'] = 0, ['Composure'] = 0, ['Light Arts'] = 0, ['Haste'] = 2,
	['Refresh'] = 2, ['Reraise'] = 3,
}

local function get_settings()
	return rawget(_G, 'UC_SETTINGS') or {}
end

local function bool_setting(v, default_value)
	if v == nil then
		return default_value == true
	end
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
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
			out[#out + 1] = {
				id = entry.mob.id,
				name = entry.mob.name,
				is_self = entry.mob.id == self_id,
				spawn_type = entry.mob.spawn_type,
				hpp = tonumber(entry.hpp) or 100,
				hp = tonumber(entry.hp) or 0,
				buffs = entry.buffs or {},
			}
		end
	end
	return out
end

local function has_buff(buff_list, buff_id)
	if type(buff_list) ~= 'table' then
		return false
	end
	for _, b in ipairs(buff_list) do
		if b == buff_id then
			return true
		end
	end
	return false
end

local function in_party_cast_range(member)
	if not member or not member.id then
		return false
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
	return res.spells:with('en', name)
end

local function get_ja_resource(name)
	if not name or name == '' then
		return nil
	end
	return res.job_abilities:with('en', name)
end

local function action_status_id(name)
	local sp = get_spell_resource(name)
	if sp and type(sp.status) == 'number' then
		return sp.status
	end
	local ja = get_ja_resource(name)
	if ja and type(ja.status) == 'number' then
		return ja.status
	end
	return nil
end

local function spell_ready(name)
	local sp = get_spell_resource(name)
	if not sp then
		return false, 'BLOCK_DEFENSIVE_UNKNOWN_SPELL'
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

local function ja_ready(name)
	local ja = get_ja_resource(name)
	if not ja then
		return false, 'BLOCK_DEFENSIVE_UNKNOWN_JA'
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	if (recasts[ja.recast_id] or 0) > 0 then
		return false, 'BLOCK_DEFENSIVE_RECAST'
	end
	return true, ''
end

local function action_ready(name)
	local sp = get_spell_resource(name)
	if sp then
		local ok, reason = spell_ready(name)
		return ok, reason, 'spell'
	end
	local ja = get_ja_resource(name)
	if ja then
		local ok, reason = ja_ready(name)
		return ok, reason, 'ja'
	end
	return false, 'BLOCK_DEFENSIVE_UNKNOWN_ACTION', 'none'
end

local function member_priority(member)
	-- Lower number means higher priority.
	if member.is_self then
		return 1
	end
	if member.spawn_type == 14 then
		return 6
	end
	return 5
end

local function pri_default(player_prio, action_prio)
	return player_prio + ((action_prio or 5) / 10)
end

local function danger_level(hpp)
	if hpp <= 20 then
		return 3
	elseif hpp <= 40 then
		return 2
	elseif hpp <= 60 then
		return 1
	end
	return 0
end

local function cure_better(c1, c2)
	if not c1 then
		return false
	end
	if not c2 then
		return true
	end
	local p1, p2 = c1.member_prio, c2.member_prio
	local d1, d2 = c1.danger, c2.danger
	if p1 < p2 then
		return not (d2 > d1)
	elseif p1 > p2 then
		return d1 > d2
	end
	if d1 ~= d2 then
		return d1 > d2
	end
	return c1.target.hpp < c2.target.hpp
end

local function debuff_spell_for_buff_id(buff_id)
	local b = res.buffs[buff_id]
	local en = b and b.en and b.en:lower() or ''
	if en == '' then
		return nil
	end
	local mapping = {
		['paralysis'] = 'Paralyna',
		['silence'] = 'Silena',
		['blindness'] = 'Blindna',
		['poison'] = 'Poisona',
		['petrification'] = 'Stona',
		['curse'] = 'Cursna',
		['disease'] = 'Viruna',
		['plague'] = 'Viruna',
	}
	return mapping[en]
end

local function split_actions(raw)
	local out = {}
	if type(raw) == 'table' then
		for _, v in ipairs(raw) do
			if v and v ~= '' then
				out[#out + 1] = tostring(v)
			end
		end
		return out
	end
	for token in tostring(raw or ''):gmatch('[^|,]+') do
		local t = token:gsub('^%s+', ''):gsub('%s+$', '')
		if t ~= '' then
			out[#out + 1] = t
		end
	end
	return out
end

local function family_key(member_name, buff_id)
	return tostring(member_name) .. ':' .. tostring(buff_id)
end

local function attempt_key(kind, member_name, action_name)
	return table.concat({ tostring(kind), tostring(member_name), tostring(action_name) }, '::')
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
	local out = {}
	for _, bid in ipairs(buffs or {}) do
		out[bid] = (out[bid] or 0) + 1
	end
	return out
end

local function is_bard_song(spell_name)
	local sp = get_spell_resource(spell_name)
	if not sp then
		return false
	end
	if tostring(sp.type or '') == 'BardSong' then
		return true
	end
	local skill = tostring(sp.skill or ''):lower()
	return skill == 'singing'
end

local function action_duration_seconds(name, default_seconds)
	local sp = get_spell_resource(name)
	if sp and type(sp.duration) == 'number' and sp.duration > 0 then
		return sp.duration
	end
	return default_seconds
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

local function family_order_for(member_name, buff_id)
	local k = family_key(member_name, buff_id)
	local order = scheduler.family_order[k]
	if type(order) ~= 'table' then
		order = {}
		scheduler.family_order[k] = order
	end
	return order
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

local function prune_family_unknown(order, tokens, known)
	for i = #order, 1, -1 do
		if not known[order[i]] then
			table.remove(order, i)
		end
	end
	for name, _ in pairs(tokens) do
		if not known[name] then
			tokens[name] = nil
		end
	end
end

local function due_overwrite_names(member_name, buff_id, order, tokens)
	local rem = {}
	local due = {}
	local songs = {}
	local now = os.clock()
	for _, name in ipairs(order) do
		local expiry = tokens[name]
		if expiry ~= nil and is_bard_song(name) then
			local remaining = expiry - now
			rem[name] = remaining
			songs[#songs + 1] = name
		end
	end
	if #songs == 0 then
		return due, rem
	end
	table.sort(songs, function(a, b)
		local ar, br = rem[a] or 1e9, rem[b] or 1e9
		if ar ~= br then
			return ar < br
		end
		return tostring(a) < tostring(b)
	end)
	local i = 1
	while i <= #songs do
		local cluster_start = i
		local cluster_end = i
		while cluster_end < #songs do
			local cur = rem[songs[cluster_end]] or 1e9
			local nxt = rem[songs[cluster_end + 1]] or 1e9
			if (nxt - cur) <= BRD_OVERWRITE_CLUSTER_SECONDS then
				cluster_end = cluster_end + 1
			else
				break
			end
		end
		local cluster_size = (cluster_end - cluster_start + 1)
		local lead = (BRD_OVERWRITE_CLUSTER_SECONDS * cluster_size) + BRD_OVERWRITE_SAFETY_SECONDS
		local earliest = rem[songs[cluster_start]] or 1e9
		if earliest <= lead then
			for idx = cluster_start, cluster_end do
				due[songs[idx]] = true
			end
		end
		i = cluster_end + 1
	end
	return due, rem
end

local function reconcile_family_state(member_name, buff_id, family_actions, active_count, default_duration, now)
	local known = {}
	for _, name in ipairs(family_actions) do
		known[name] = true
	end
	local order = family_order_for(member_name, buff_id)
	local tokens = family_tokens_for(member_name, buff_id)
	prune_family_unknown(order, tokens, known)
	local in_order = {}
	for _, name in ipairs(order) do
		in_order[name] = true
	end
	for _, name in ipairs(family_actions) do
		if not in_order[name] then
			order[#order + 1] = name
		end
	end
	for name, expiry in pairs(tokens) do
		if expiry ~= nil and expiry <= now then
			tokens[name] = nil
		end
	end
	local target = math.max(0, math.min(tonumber(active_count) or 0, #family_actions))
	local active_names = {}
	for name, expiry in pairs(tokens) do
		if expiry ~= nil and expiry > now then
			active_names[#active_names + 1] = name
		end
	end
	local active_n = #active_names
	if target == 0 then
		for name, _ in pairs(tokens) do
			tokens[name] = nil
		end
		scheduler.family_counts[family_key(member_name, buff_id)] = 0
		return order, tokens
	end
	if active_n < target then
		local recent = get_recent_gain(member_name, buff_id, 20, now)
		if recent and known[recent] and tokens[recent] == nil then
			tokens[recent] = now + action_duration_seconds(recent, default_duration)
			active_n = active_n + 1
		end
		for idx = #order, 1, -1 do
			if active_n >= target then
				break
			end
			local name = order[idx]
			if known[name] and tokens[name] == nil then
				tokens[name] = now + action_duration_seconds(name, default_duration)
				active_n = active_n + 1
			end
		end
	elseif active_n > target then
		table.sort(active_names, function(a, b)
			local ar, br = tokens[a] or 1e9, tokens[b] or 1e9
			if ar ~= br then
				return ar < br
			end
			return tostring(a) < tostring(b)
		end)
		for i = 1, (active_n - target) do
			tokens[active_names[i]] = nil
		end
	end
	scheduler.family_counts[family_key(member_name, buff_id)] = target
	return order, tokens
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
	local now = os.clock()
	local overwrite_enabled = bool_setting(s.defensive_buff_enabled, true) and bool_setting(s.defensive_overwrite_enabled, false)
	local overwrite_interval = tonumber(s.defensive_overwrite_interval or 150) or 150
	local desired_buffs = split_actions(s.defensive_buffs or '')
	local self_only_buffs = bool_setting(s.defensive_buff_self_only, true)
	for _, m in ipairs(members) do
		local active_counts = count_buff_occurrences(m.buffs or {})
		if m.hpp > 0 and m.hpp < 95 and bool_setting(s.defensive_cure_enabled, true) and in_party_cast_range(m) then
			local spell = choose_cure_spell(m.hpp)
			if spell then
				local ready = spell_ready(spell)
				if ready then
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
					end
				end
			end
		end
		if bool_setting(s.defensive_na_enabled, true) and in_party_cast_range(m) then
			for _, buff_id in ipairs(m.buffs or {}) do
				local debuff = res.buffs[buff_id]
				local debuff_en = debuff and debuff.en or ''
				local na_spell = debuff_map[debuff_en] or debuff_spell_for_buff_id(buff_id)
				if na_spell then
					local ready = action_ready(na_spell)
					if ready and attempt_allowed('debuff', m.name, na_spell, now, 3) then
						local p = member_priority(m)
						local action_prio = status_removal_priority[(debuff and (debuff.enn or debuff_en:lower():gsub('%s+', '_'))) or ''] or 5
						local d = {
							type = 'debuff',
							spell = na_spell,
							target = m,
							buff_id = buff_id,
							prio = pri_default(p, action_prio),
						}
						if not out.debuff or d.prio < out.debuff.prio then
							out.debuff = d
						end
					end
					break
				end
			end
		end
		if bool_setting(s.defensive_buff_enabled, true) and in_party_cast_range(m) and (not self_only_buffs or m.is_self) then
			local by_name = {}
			local by_family = {}
			for _, buff_action in ipairs(desired_buffs) do
				local bid = action_status_id(buff_action)
				if bid ~= nil then
					by_name[buff_action] = { bid = bid, name = buff_action }
					by_family[bid] = by_family[bid] or {}
					by_family[bid][#by_family[bid] + 1] = buff_action
				end
			end
			local family_due = {}
			local family_remaining = {}
			for bid, names in pairs(by_family) do
				local order, tokens = reconcile_family_state(
					m.name,
					bid,
					names,
					active_counts[bid] or 0,
					overwrite_interval,
					now
				)
				if overwrite_enabled and (#names > 1) then
					local due, rem = due_overwrite_names(m.name, bid, order, tokens)
					family_due[bid] = due
					family_remaining[bid] = rem
				end
			end
			local spell_names = {}
			for name, _ in pairs(by_name) do
				spell_names[#spell_names + 1] = name
			end
			table.sort(spell_names, function(a, b)
				local ai = by_name[a]
				local bi = by_name[b]
				local ad = ai and family_due[ai.bid] and family_due[ai.bid][a] == true or false
				local bd = bi and family_due[bi.bid] and family_due[bi.bid][b] == true or false
				if ad and bd then
					local ar = family_remaining[ai.bid] and family_remaining[ai.bid][a] or 1e9
					local br = family_remaining[bi.bid] and family_remaining[bi.bid][b] or 1e9
					if ar ~= br then
						return ar < br
					end
					return tostring(a) < tostring(b)
				elseif ad ~= bd then
					return ad
				end
				return tostring(a) < tostring(b)
			end)
			local family_enqueued = {}
			for _, buff_action in ipairs(spell_names) do
				local info = by_name[buff_action]
				local bid = info and info.bid or nil
				if bid then
					local tokens = family_tokens_for(m.name, bid)
					local landed = tokens[buff_action] ~= nil and tokens[buff_action] > now
					local due = family_due[bid] and family_due[bid][buff_action] == true or false
					local should_queue = false
					local reason = nil
					if not landed then
						should_queue = true
						reason = 'missing'
					elseif due then
						should_queue = true
						reason = 'overwrite'
					end
					if should_queue and attempt_allowed(reason or 'buff', m.name, buff_action, now, 3) then
						local is_dup_family = (by_family[bid] and #by_family[bid] > 1) or false
						local block_for_family_wait = is_dup_family and family_enqueued[bid] and (reason ~= 'overwrite')
						if not block_for_family_wait then
							local ready = action_ready(buff_action)
							if ready then
								local bprio = buff_priority[buff_action] or 5
								local candidate = {
									type = (reason == 'overwrite') and 'overwrite' or 'buff',
									spell = buff_action,
									target = m,
									buff_id = bid,
									prio = pri_default(member_priority(m), bprio),
								}
								if candidate.type == 'overwrite' then
									if not out.overwrite or candidate.prio < out.overwrite.prio then
										out.overwrite = candidate
									end
								else
									if not out.buff or candidate.prio < out.buff.prio then
										out.buff = candidate
									end
								end
								if is_dup_family then
									family_enqueued[bid] = true
								end
							end
						end
					end
				end
			end
		end
	end
	return out
end

local function choose_defensive_action(c)
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

choose_cure_spell = function(hpp)
	local s = get_settings()
	local crit = tonumber(s.defensive_critical_hpp) or 35
	local med = tonumber(s.defensive_medium_hpp) or 55
	if hpp <= crit then
		return 'Cure IV'
	elseif hpp <= med then
		return 'Cure III'
	elseif hpp <= 75 then
		return 'Cure II'
	end
	return nil
end

local function try_internal_defensive_action()
	local s = get_settings()
	if not bool_setting(s.defensive_enabled, false) then
		return false, nil
	end
	local p = windower.ffxi.get_player()
	if not p then
		return true, 'BLOCK_DEFENSIVE_NO_PLAYER'
	end
	if not can_act_statuses[p.status or -1] then
		return true, 'BLOCK_DEFENSIVE_PLAYER_STATUS'
	end
	local now = os.clock()
	local candidates = build_defensive_candidates()
	local action, reason = choose_defensive_action(candidates)
	if action and action.spell and action.target and action.target.name then
		if now - scheduler.last_action_at < scheduler.action_delay then
			-- Cooldown paces defensive casts only; do not freeze offensive combat ticks.
			return false, nil
		end
		local _, _, action_kind = action_ready(action.spell)
		local cmd
		if action_kind == 'ja' then
			local target_name = action.target.is_self and '<me>' or action.target.name
			cmd = ('input /ja "%s" %s'):format(action.spell, target_name)
		else
			cmd = ('input /ma "%s" %s'):format(action.spell, action.target.name)
		end
		windower.send_command(cmd)
		scheduler.last_action_at = now
		_G.UC_LAST_SCHED_ACTION = action.spell .. '->' .. tostring(action.target.name)
		mark_attempt(action.type or 'defensive', action.target.name, action.spell, now)
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
	return false, nil
end

local function p1_number(v, default_value)
	local n = tonumber(v)
	if n == nil then
		return default_value
	end
	return n
end

local function p1_clamp_urgency(v)
	local n = p1_number(v, 0)
	if n < 0 then
		return 0
	end
	if n > 1 then
		return 1
	end
	return n
end

local function p1_build_ctx(settings)
	local player = windower.ffxi.get_player() or {}
	local me = windower.ffxi.get_mob_by_target('me') or {}
	local p = scheduler.phase1
	p.tick = (tonumber(p.tick) or 0) + 1
	return {
		now = os.clock(),
		tick = p.tick,
		settings = settings or {},
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
	local legacy_command = action.target.is_self and ('input /ma "%s" <me>'):format(action_name) or ('input /ma "%s" %s'):format(action_name, target_name)
	out[#out + 1] = {
		proposal_id = ('def.internal.%s.%s.%d'):format(tostring(action.type or 'action'), action_name, math.floor(ctx.now * 1000)),
		family_id = ('def.internal.%s'):format(tostring(action.type or 'action')),
		provider = 'defensive_internal',
		action_type = 'spell',
		action_name = action_name,
		target_kind = target_kind,
		target_id = target_id,
		target_name = target_name,
		priority_band = 100,
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
			target_hpp = tonumber(action.target.hpp) or -1,
		},
		legacy_command = legacy_command,
	}
end

local function p1_collect_proposals(ctx)
	local out = {}
	p1_collect_defensive_internal(ctx, out)
	return out
end

local function p1_pending_is_live_state(state_name)
	return state_name == 'selected' or state_name == 'dispatching' or state_name == 'sent' or state_name == 'acknowledged'
end

local function p1_update_pending_state(ctx)
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		phase.pending = nil
		return
	end
	local now = ctx.now
	local state_name = tostring(pending.state or '')
	if p1_pending_is_live_state(state_name) and now > p1_number(pending.effect_deadline, 0) then
		pending.state = 'timed_out'
		pending.result = 'effect_timeout'
		local dkey = tostring(pending.duplicate_suppression_key or '')
		if dkey ~= '' then
			phase.recent_duplicate_until[dkey] = now + 0.75
		end
	end
	if (pending.state == 'timed_out' or pending.state == 'failed' or pending.state == 'canceled') and now > p1_number(pending.completion_deadline, now) then
		phase.pending = nil
	end
	if pending.state == 'complete' and now > p1_number(pending.completion_deadline, now) then
		phase.pending = nil
	end
end

local function p1_duplicate_suppressed(ctx, proposal)
	local dkey = tostring(proposal and proposal.duplicate_suppression_key or '')
	if dkey == '' then
		return false
	end
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) == 'table' then
		local pkey = tostring(pending.duplicate_suppression_key or '')
		local state_name = tostring(pending.state or '')
		if pkey == dkey and p1_pending_is_live_state(state_name) then
			return true
		end
	end
	local until_ts = p1_number(phase.recent_duplicate_until[dkey], 0)
	if until_ts > ctx.now then
		return true
	end
	return false
end

local function p1_get_locks(ctx)
	local phase = scheduler.phase1
	local pending = phase.pending
	local pending_live = type(pending) == 'table' and p1_pending_is_live_state(tostring(pending.state or ''))
	local zone_suspend_until = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	local zone_guard_active = type(zone_suspend_until) == 'number' and ctx.now < zone_suspend_until
	return {
		zone_guard_lock = { hard = zone_guard_active },
		cast_lock = { hard = pending_live },
		movement_lock = { hard = pending_live },
		target_lock = { hard = false },
	}
end

local function p1_hard_lock_reject(locks, proposal)
	if locks.zone_guard_lock and locks.zone_guard_lock.hard then
		return 'zone_guard'
	end
	local action_type = tostring(proposal and proposal.action_type or '')
	if (action_type == 'spell' or action_type == 'ja' or action_type == 'ws') and locks.cast_lock and locks.cast_lock.hard then
		return 'hard_locked'
	end
	if action_type == 'move' and locks.movement_lock and locks.movement_lock.hard then
		return 'hard_locked'
	end
	return ''
end

local function p1_validate_proposal(ctx, p)
	if type(p) ~= 'table' then
		return false, 'malformed'
	end
	if tostring(p.proposal_id or '') == '' or tostring(p.provider or '') == '' then
		return false, 'malformed'
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
	for _, proposal in ipairs(proposals) do
		local ok, reject_reason = p1_validate_proposal(ctx, proposal)
		if ok then
			local lock_reject = p1_hard_lock_reject(locks, proposal)
			if lock_reject ~= '' then
				reject_counts[lock_reject] = (reject_counts[lock_reject] or 0) + 1
			else
				p1_score(proposal)
				valid[#valid + 1] = proposal
			end
		else
			reject_counts[reject_reason] = (reject_counts[reject_reason] or 0) + 1
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
	return valid, reject_counts, locks
end

local function p1_format_top3(ranked)
	local parts = {}
	local count = math.min(3, #ranked)
	for i = 1, count do
		local p = ranked[i]
		parts[#parts + 1] = ('%d)%s %.2f %s'):format(i, tostring(p.provider or ''), p1_number(p._score, 0), tostring(p.action_name or ''))
	end
	return table.concat(parts, ' | ')
end

local function p1_reject_top(reject_counts, proposal_count)
	if proposal_count <= 0 then
		return 'no_proposals'
	end
	local best_reason, best_count = '', -1
	for reason, count in pairs(reject_counts) do
		if count > best_count then
			best_reason = tostring(reason or '')
			best_count = count
		end
	end
	if best_count < 0 then
		return ''
	end
	return ('%s:%d'):format(best_reason, best_count)
end

local function p1_build_dispatch_plan(ctx, selected)
	if not selected then
		return nil
	end
	local prelude_type = 'none'
	if tostring(selected.movement_policy or '') == 'must_stop' then
		prelude_type = 'stop'
	end
	return {
		plan_id = ('plan.%d.%d'):format(math.floor(ctx.now * 1000), math.floor(ctx.tick)),
		selected_proposal_id = tostring(selected.proposal_id or ''),
		prelude = {
			type = prelude_type,
			target_id = tonumber(selected.target_id) or 0,
			timeout_s = 0.20,
		},
		primary = {
			action_type = tostring(selected.action_type or ''),
			action_name = tostring(selected.action_name or ''),
			target_id = tonumber(selected.target_id) or 0,
			target_name = tostring(selected.target_name or ''),
		},
		commit_deadline = p1_number(selected.commit_deadline, ctx.now + 0.25),
		created_at = ctx.now,
	}
end

local function p1_revalidate_plan_commit(ctx, selected, plan)
	if not selected or not plan then
		return false, 'invalid_plan'
	end
	if p1_number(selected.expires_at, 0) <= ctx.now then
		return false, 'expired'
	end
	if p1_number(plan.commit_deadline, 0) < ctx.now then
		return false, 'commit_deadline'
	end
	local target_kind = tostring(selected.target_kind or 'none')
	if target_kind == 'self' then
		return true, ''
	end
	local target_id = tonumber(selected.target_id) or 0
	if target_kind == 'ally' then
		if target_id <= 0 then
			return false, 'invalid_target'
		end
		local m = windower.ffxi.get_mob_by_id(target_id)
		if not m then
			return false, 'invalid_target'
		end
		return true, ''
	end
	if target_kind == 'mob' then
		if target_id <= 0 then
			return false, 'invalid_target'
		end
		local mob = windower.ffxi.get_mob_by_id(target_id)
		if not mob or not mob.valid_target or (tonumber(mob.hpp) or 0) <= 0 then
			return false, 'invalid_target'
		end
		return true, ''
	end
	return true, ''
end

local function p1_set_pending_globals()
	local phase = scheduler.phase1
	local pending = phase.pending
	if type(pending) ~= 'table' then
		_G.UC_SCHED_P1_PENDING_STATE = ''
		return
	end
	_G.UC_SCHED_P1_PENDING_STATE = tostring(pending.state or '')
end

local function p1_build_lock_summary(ctx, locks)
	local phase = scheduler.phase1
	local parts = {}
	local lock_state = locks or p1_get_locks(ctx)
	if lock_state.zone_guard_lock and lock_state.zone_guard_lock.hard then
		parts[#parts + 1] = 'zone_guard_lock'
	end
	if lock_state.cast_lock and lock_state.cast_lock.hard then
		parts[#parts + 1] = 'cast_lock'
	end
	if lock_state.movement_lock and lock_state.movement_lock.hard then
		parts[#parts + 1] = 'movement_lock'
	end
	local now = ctx.now
	local has_dup = false
	for _, until_ts in pairs(phase.recent_duplicate_until) do
		if p1_number(until_ts, 0) > now then
			has_dup = true
			break
		end
	end
	if has_dup then
		parts[#parts + 1] = 'duplicate_lock'
	end
	return table.concat(parts, '|')
end

local function p1_record_legacy_dispatch(ctx)
	local phase = scheduler.phase1
	local selected = phase.last_selected
	local plan = phase.last_plan
	if not selected or not plan then
		return
	end
	local duplicate_key = tostring(selected.duplicate_suppression_key or '')
	phase.pending = {
		pending_id = ('pend.%d.%d'):format(math.floor(ctx.now * 1000), math.floor(ctx.tick)),
		proposal_id = tostring(selected.proposal_id or ''),
		family_id = tostring(selected.family_id or ''),
		duplicate_suppression_key = duplicate_key,
		provider = tostring(selected.provider or ''),
		action_type = tostring(selected.action_type or ''),
		action_name = tostring(selected.action_name or ''),
		target_id = tonumber(selected.target_id) or 0,
		state = 'sent',
		selected_at = p1_number(selected.created_at, ctx.now),
		dispatched_at = ctx.now,
		ack_deadline = ctx.now + 0.6,
		effect_deadline = ctx.now + 2.5,
		completion_deadline = ctx.now + 3.0,
		expected_ack = tostring(selected.expected_ack or ''),
		expected_effect = tostring(selected.expected_effect or ''),
		result = '',
	}
	if duplicate_key ~= '' then
		phase.recent_duplicate_until[duplicate_key] = ctx.now + 0.75
	end
end

local function p1_run_dry(settings)
	local ctx = p1_build_ctx(settings)
	p1_update_pending_state(ctx)
	local proposals = p1_collect_proposals(ctx)
	local ranked, reject_counts, locks = p1_rank(ctx, proposals)
	local selected = ranked[1]
	local plan = p1_build_dispatch_plan(ctx, selected)
	local commit_ok, commit_reason = p1_revalidate_plan_commit(ctx, selected, plan)
	if selected and not commit_ok then
		selected = nil
		plan = nil
	end
	local phase = scheduler.phase1
	phase.last_selected = selected
	phase.last_plan = plan
	phase.last_top3 = p1_format_top3(ranked)
	phase.last_reject_top = p1_reject_top(reject_counts, #proposals)
	if selected then
		phase.last_noop_reason = ''
	else
		if commit_reason and commit_reason ~= '' then
			phase.last_noop_reason = 'commit_invalidated:' .. tostring(commit_reason)
		else
			phase.last_noop_reason = (#proposals == 0) and 'no_proposals' or 'all_rejected'
		end
	end
	_G.UC_SCHED_P1_TICK = ctx.tick
	_G.UC_SCHED_P1_SELECTED_PROPOSAL = selected and tostring(selected.proposal_id or '') or ''
	_G.UC_SCHED_P1_SELECTED_PROVIDER = selected and tostring(selected.provider or '') or ''
	_G.UC_SCHED_P1_SELECTED_FAMILY = selected and tostring(selected.family_id or '') or ''
	_G.UC_SCHED_P1_PLAN_PRELUDE = (plan and plan.prelude and tostring(plan.prelude.type or '')) or ''
	p1_set_pending_globals()
	_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, locks)
	_G.UC_SCHED_P1_REJECT_TOP = phase.last_reject_top or ''
	_G.UC_SCHED_P1_NOOP_REASON = phase.last_noop_reason or ''
	_G.UC_SCHED_P1_TOP3 = phase.last_top3 or ''
end

function scheduler.process_tick()
	_G.UC_LAST_SCHED_ACTION = ''
	local s = get_settings()
	p1_run_dry(s)
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
			local ctx = { now = os.clock(), tick = p1_number(scheduler.phase1.tick, 0) }
			p1_record_legacy_dispatch(ctx)
			p1_set_pending_globals()
			_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
			return true, reason
		end
		return false, nil
	end
	acted, reason = try_internal_defensive_action()
	if acted then
		local ctx = { now = os.clock(), tick = p1_number(scheduler.phase1.tick, 0) }
		p1_record_legacy_dispatch(ctx)
		p1_set_pending_globals()
		_G.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, p1_get_locks(ctx))
		return true, reason
	end
	return false, nil
end

return scheduler
