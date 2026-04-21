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

function scheduler.process_tick()
	_G.UC_LAST_SCHED_ACTION = ''
	local s = get_settings()
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
			return true, reason
		end
		return false, nil
	end
	acted, reason = try_internal_defensive_action()
	if acted then
		return true, reason
	end
	return false, nil
end

return scheduler
