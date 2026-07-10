local res = require('resources')
local uc_active_config = require('uc_active_config')
local socket_ok, socket_mod = pcall(require, 'socket')
local socket_gettime = (socket_ok and type(socket_mod) == 'table' and type(socket_mod.gettime) == 'function') and socket_mod.gettime
	or nil

local function now_s()
	return socket_gettime()
end

local function active_value_or_flat(path, flat_value)
	local active_value = uc_active_config.get_path(path)
	if active_value ~= nil then
		return active_value
	end
	return flat_value
end

local mod = {}
local state = {
	last_family_action = {},
	confirmed_bard_song_identity = {},
}

local action_buff_map = {}
do
	local ok, map = pcall(dofile, windower.addon_path .. 'data/action_buff_map.lua')
	if ok and type(map) == 'table' then
		action_buff_map = map
	end
end

local dec2roman = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI' }

local function to_roman(val)
	local n = tonumber(val)
	if not n then
		return nil
	end
	return dec2roman[n]
end

local function normalize_name(text)
	local raw = tostring(text or '')
	raw = raw:gsub('\\u0027', "'")
	raw = raw:gsub('[\226\128\153\226\128\152`´]', "'")
	raw = raw:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if raw == '' then
		return ''
	end
	local out = {}
	for part in raw:gmatch('%S+') do
		local rn = to_roman(part)
		local up = tostring(part):upper()
		if rn then
			out[#out + 1] = rn
		elseif up:match('^[IVX]+$') then
			out[#out + 1] = up
		else
			out[#out + 1] = part
		end
	end
	return table.concat(out, ' ')
end

local function split_actions(raw)
	local out = {}
	for token in tostring(raw or ''):gmatch('[^|,]+') do
		local n = normalize_name(token)
		if n ~= '' then
			out[#out + 1] = n
		end
	end
	return out
end

local function parse_targeted_buffs(raw)
	local out = {}
	for token in tostring(raw or ''):gmatch('[^|]+') do
		local t = tostring(token or ''):gsub('^%s+', ''):gsub('%s+$', '')
		local sep = t:find(':', 1, true)
		if sep and sep > 1 and sep < #t then
			local target = normalize_name(t:sub(1, sep - 1))
			local action = normalize_name(t:sub(sep + 1))
			if target ~= '' and action ~= '' then
				out[#out + 1] = { target = target, action = action }
			end
		end
	end
	return out
end

local function active_targeted_buffs(settings)
	local structured = uc_active_config.get_path('config.defensive.buffs.targeted')
	if structured ~= nil then
		local out = {}
		if type(structured) == 'table' then
			for i = 1, #structured do
				local entry = structured[i]
				if type(entry) == 'table' then
					local target = normalize_name(entry.character or entry.target or entry.name)
					local action = normalize_name(entry.buff or entry.action)
					if target ~= '' and action ~= '' then
						out[#out + 1] = { target = target, action = action }
					end
				end
			end
		end
		return out
	end
	return parse_targeted_buffs(settings.defensive_targeted_buffs or '')
end

-- HealBot-style action->buff family aliases.
local buff_map = {
	["Army's Paeon"] = 'Paeon', ["Army's Paeon II"] = 'Paeon', ["Army's Paeon III"] = 'Paeon',
	["Army's Paeon IV"] = 'Paeon', ["Army's Paeon V"] = 'Paeon', ["Army's Paeon VI"] = 'Paeon',
	["Army's Paeon VII"] = 'Paeon', ["Army's Paeon VIII"] = 'Paeon',
	["Mage's Ballad"] = 'Ballad', ["Mage's Ballad II"] = 'Ballad', ["Mage's Ballad III"] = 'Ballad',
	["Knight's Minne"] = 'Minne', ["Knight's Minne II"] = 'Minne', ["Knight's Minne III"] = 'Minne',
	["Knight's Minne IV"] = 'Minne', ["Knight's Minne V"] = 'Minne',
	["Valor Minuet"] = 'Minuet', ["Valor Minuet II"] = 'Minuet', ["Valor Minuet III"] = 'Minuet',
	["Valor Minuet IV"] = 'Minuet', ["Valor Minuet V"] = 'Minuet',
	["Sword Madrigal"] = 'Madrigal', ["Blade Madrigal"] = 'Madrigal',
	["Hunter's Prelude"] = 'Prelude', ["Archer's Prelude"] = 'Prelude',
	["Sheepfoe Mambo"] = 'Mambo', ["Dragonfoe Mambo"] = 'Mambo',
	["Advancing March"] = 'March', ["Victory March"] = 'March', ["Honor March"] = 'March',
	['Enlight II'] = 'Enlight',
	['Boost-STR'] = 'STR Boost', ['Boost-DEX'] = 'DEX Boost', ['Boost-VIT'] = 'VIT Boost',
	['Boost-AGI'] = 'AGI Boost', ['Boost-INT'] = 'INT Boost', ['Boost-MND'] = 'MND Boost',
	['Boost-CHR'] = 'CHR Boost', ['Gain-STR'] = 'STR Boost', ['Gain-DEX'] = 'DEX Boost',
	['Gain-VIT'] = 'VIT Boost', ['Gain-AGI'] = 'AGI Boost', ['Gain-INT'] = 'INT Boost',
	['Gain-MND'] = 'MND Boost', ['Gain-CHR'] = 'CHR Boost',
}

local function status_ids_by_buff_name(name)
	local want = normalize_name(name):lower()
	local out = {}
	if want == '' then
		return out
	end
	for bid, b in pairs(res.buffs or {}) do
		local en = normalize_name((b and b.en) or ''):lower()
		if en == want then
			out[#out + 1] = tonumber(bid) or 0
		end
	end
	return out
end

local function dedupe(ids)
	local out, seen = {}, {}
	for _, v in ipairs(ids or {}) do
		local n = tonumber(v) or 0
		if n > 0 and not seen[n] then
			out[#out + 1] = n
			seen[n] = true
		end
	end
	return out
end

local function resolve_status_ids(action_name, get_spell_resource, get_ja_resource)
	local ids = {}
	local norm_action = normalize_name(action_name)
	local mapped = buff_map[norm_action]
	if mapped then
		for _, bid in ipairs(status_ids_by_buff_name(mapped)) do
			ids[#ids + 1] = bid
		end
	end

	local sp = get_spell_resource(action_name)
	if sp and action_buff_map and type(action_buff_map) == 'table' then
		local by_cat = action_buff_map[tostring(sp.type or '')]
		local mapped_id = by_cat and by_cat[tonumber(sp.id) or 0]
		if tonumber(mapped_id) and tonumber(mapped_id) > 0 then
			ids[#ids + 1] = tonumber(mapped_id)
		end
	end
	if sp and tonumber(sp.status) and tonumber(sp.status) > 0 then
		ids[#ids + 1] = tonumber(sp.status)
	end

	local ja = get_ja_resource(action_name)
	if ja and action_buff_map and type(action_buff_map) == 'table' then
		local by_cat = action_buff_map[tostring(ja.type or 'JobAbility')] or action_buff_map['JobAbility']
		local mapped_id = by_cat and by_cat[tonumber(ja.id) or 0]
		if tonumber(mapped_id) and tonumber(mapped_id) > 0 then
			ids[#ids + 1] = tonumber(mapped_id)
		end
	end
	if ja and tonumber(ja.status) and tonumber(ja.status) > 0 then
		ids[#ids + 1] = tonumber(ja.status)
	end

	if #ids == 0 then
		for _, bid in ipairs(status_ids_by_buff_name(norm_action)) do
			ids[#ids + 1] = bid
		end
	end

	-- HealBot-style final fallback:
	-- If a tiered spell name has no direct status mapping (e.g. "Enlight II"),
	-- retry lookup by first token ("Enlight").
	if #ids == 0 then
		local first = norm_action:match('^([^%s]+)')
		if first and first ~= '' and first:lower() ~= norm_action:lower() then
			local fallback_name = buff_map[first] or first
			for _, bid in ipairs(status_ids_by_buff_name(fallback_name)) do
				ids[#ids + 1] = bid
			end
			if #ids == 0 and fallback_name ~= first then
				for _, bid in ipairs(status_ids_by_buff_name(first)) do
					ids[#ids + 1] = bid
				end
			end
		end
	end
	return dedupe(ids)
end

local function has_any_buff(member_buffs, status_ids)
	local present = {}
	for _, bid in ipairs(member_buffs or {}) do
		present[tonumber(bid) or 0] = true
	end
	for _, sid in ipairs(status_ids or {}) do
		if present[tonumber(sid) or 0] then
			return true
		end
	end
	return false
end

local function family_for_name(name)
	return buff_map[normalize_name(name)]
end

local function build_family_lookup()
	local out = {}
	for k, fam in pairs(buff_map) do
		local kn = normalize_name(k):lower()
		local fn = normalize_name(fam):lower()
		if kn ~= '' and fam and fam ~= '' then
			out[kn] = fam
		end
		if fn ~= '' and fam and fam ~= '' then
			out[fn] = fam
		end
	end
	return out
end

local family_lookup = build_family_lookup()

local function count_existing_family_buffs(member_buffs)
	local out = {}
	for _, bid in ipairs(member_buffs or {}) do
		local b = res.buffs and res.buffs[tonumber(bid) or 0] or nil
		local bname = normalize_name((b and b.en) or '')
		local fam = family_lookup[bname:lower()]
		if fam then
			out[fam] = (out[fam] or 0) + 1
		end
	end
	return out
end

local function mark_last_family_action(member_name, family, action_name, now)
	local key = tostring(member_name or '') .. '::' .. tostring(family or '')
	state.last_family_action[key] = { action = tostring(action_name or ''), at = tonumber(now) or 0 }
end

local function get_last_family_action(member_name, family)
	local key = tostring(member_name or '') .. '::' .. tostring(family or '')
	local v = state.last_family_action[key]
	if type(v) ~= 'table' then
		return '', 0
	end
	return tostring(v.action or ''), tonumber(v.at) or 0
end

local function bard_song_identity_member(member_name)
	local key = tostring(member_name or '')
	local bucket = state.confirmed_bard_song_identity[key]
	if type(bucket) ~= 'table' then
		bucket = {}
		state.confirmed_bard_song_identity[key] = bucket
	end
	return bucket
end

local function prune_bard_song_identity(member_name, family, now)
	local member_bucket = bard_song_identity_member(member_name)
	local family_key = tostring(family or '')
	local family_bucket = member_bucket[family_key]
	if type(family_bucket) ~= 'table' then
		return {}
	end
	local active = {}
	for action_name, entry in pairs(family_bucket) do
		local expires_at = tonumber(entry and entry.expires_at) or 0
		if expires_at > now then
			active[#active + 1] = {
				action = tostring(action_name or ''),
				at = tonumber(entry and entry.at) or 0,
				expires_at = expires_at,
			}
		else
			family_bucket[action_name] = nil
		end
	end
	if next(family_bucket) == nil then
		member_bucket[family_key] = nil
	end
	return active
end

local function confirmed_bard_song_identity_set(member_name, family, action_name, now, family_count)
	if (tonumber(family_count) or 0) <= 0 then
		return false
	end
	local active = prune_bard_song_identity(member_name, family, now)
	if #active == 0 then
		return false
	end
	table.sort(active, function(left, right)
		local lat = tonumber(left.at) or 0
		local rat = tonumber(right.at) or 0
		if lat == rat then
			return tostring(left.action or '') < tostring(right.action or '')
		end
		return lat > rat
	end)
	local limit = math.min(tonumber(family_count) or 0, #active)
	for index = 1, limit do
		if tostring(active[index].action or '') == tostring(action_name or '') then
			return true
		end
	end
	return false
end

function mod.mark_bard_song_success(member_name, action_name, now, expires_at)
	local normalized_action = normalize_name(action_name)
	local family = family_for_name(normalized_action)
	if family == nil or family == '' then
		return false
	end
	local member_bucket = bard_song_identity_member(member_name)
	local family_key = tostring(family)
	local family_bucket = member_bucket[family_key]
	if type(family_bucket) ~= 'table' then
		family_bucket = {}
		member_bucket[family_key] = family_bucket
	end
	family_bucket[normalized_action] = {
		at = tonumber(now) or 0,
		expires_at = tonumber(expires_at) or 0,
	}
	return true
end

function mod._reset_test_state()
	state.last_family_action = {}
	state.confirmed_bard_song_identity = {}
end

function mod.choose(settings, members, helpers)
	local desired = split_actions(active_value_or_flat('config.defensive.buffs.list', settings.defensive_buffs) or '')
	local targeted = active_targeted_buffs(settings)
	local self_only = helpers.bool_setting(active_value_or_flat('config.defensive.buffs.self_only', settings.defensive_buff_self_only), true)
	local overwrite = helpers.bool_setting(active_value_or_flat('config.defensive.buffs.overwrite_enabled', settings.defensive_overwrite_enabled), false)
	local overwrite_interval = tonumber(active_value_or_flat('config.defensive.buffs.overwrite_interval', settings.defensive_overwrite_interval) or 150) or 150
	local now = now_s()
	local first_eligible_non_majesty = nil

	local function is_majesty_action(action_name)
		return normalize_name(action_name):lower() == 'majesty'
	end

	for _, m in ipairs(members or {}) do
		local in_range = helpers.in_party_cast_range(m)
		if helpers.log_debug then
			helpers.log_debug(('HB_BUFF_MEMBER name="%s" self=%s in_range=%s self_only=%s'):format(
				tostring(m.name or '?'),
				tostring(m.is_self == true),
				tostring(in_range == true),
				tostring(self_only == true)
			))
		end
		if in_range and ((not self_only) or m.is_self) then
			local actions = {}
			for _, a in ipairs(desired) do
				actions[#actions + 1] = a
			end
			for _, t in ipairs(targeted) do
				if normalize_name(t.target):lower() == normalize_name(m.name):lower() then
					actions[#actions + 1] = t.action
				end
			end

			local desired_family_counts = {}
			local family_actions = {}
			for _, action_name in ipairs(actions) do
				if helpers.is_bard_song(action_name) then
					local fam = family_for_name(action_name)
					if fam then
						desired_family_counts[fam] = (desired_family_counts[fam] or 0) + 1
						family_actions[fam] = family_actions[fam] or {}
						family_actions[fam][#family_actions[fam] + 1] = action_name
					end
				end
			end
			local existing_family_counts = count_existing_family_buffs(m.buffs or {})

			for _, action_name in ipairs(actions) do
				local ready, reason, action_kind = helpers.action_ready(action_name)
				if ready then
					local bids = resolve_status_ids(action_name, helpers.get_spell_resource, helpers.get_ja_resource)
					if helpers.log_debug and normalize_name(action_name):lower() == 'enlight ii' then
						local id_parts = {}
						for _, bid in ipairs(bids or {}) do
							id_parts[#id_parts + 1] = tostring(bid)
						end
						helpers.log_debug(('HB_BUFF_TRACE action="%s" target="%s" ready=1 status_ids=[%s]'):format(
							tostring(action_name),
							tostring(m.name or '?'),
							table.concat(id_parts, ',')
						))
					end
					local is_present = has_any_buff(m.buffs or {}, bids)
					local should_cast = not is_present
					local fam = nil
					if helpers.is_bard_song(action_name) then
						fam = family_for_name(action_name)
						if fam then
							local have = tonumber(existing_family_counts[fam]) or 0
							local need = tonumber(desired_family_counts[fam]) or 1
							local exact_confirmed = confirmed_bard_song_identity_set(m.name, fam, action_name, now, have)
							-- For BRD families, decide by family coverage (not per-song status id),
							-- because songs in the same family share buff identity in status data.
							should_cast = have < need
							if need > 1 and exact_confirmed then
								should_cast = false
							end
							if should_cast and need > 1 then
								-- Avoid looping the same family action when a different family mate is needed.
								local last_name, last_at = get_last_family_action(m.name, fam)
								local fam_list = family_actions[fam] or {}
								if #fam_list > 1 and last_name ~= '' and last_name == action_name and (now - last_at) < 20 then
									should_cast = false
								end
							end
						end
					end
					if not should_cast and overwrite and helpers.is_bard_song(action_name) then
						local key = tostring(m.name or '') .. '::' .. tostring(action_name)
						local last = tonumber(helpers.last_overwrite[key]) or 0
						should_cast = (now - last) >= overwrite_interval
					end
					if should_cast and helpers.attempt_allowed('buff', m.name, action_name, now, 3) then
						local candidate = {
							type = overwrite and 'overwrite' or 'buff',
							spell = action_name,
							target = m,
							buff_id = tonumber(bids[1]) or 0,
							prio = helpers.pri_default(helpers.member_priority(m), helpers.buff_priority[action_name] or 5),
							reason = is_present and 'overwrite' or 'missing',
							action_kind = action_kind,
						}
						if is_majesty_action(action_name) then
							return candidate
						end
						if not first_eligible_non_majesty then
							if fam then
								mark_last_family_action(m.name, fam, action_name, now)
							end
							first_eligible_non_majesty = candidate
						end
					elseif helpers.log_debug then
						helpers.log_debug(('HB_BUFF_SKIP name="%s" target="%s" reason=attempt_gate'):format(
							tostring(action_name),
							tostring(m.name or '?')
						))
					end
				elseif helpers.log_debug then
					-- Emit explicit non-ready reason for visibility; previously most
					-- reasons were silent unless not-learned/job-level.
					helpers.log_debug(('HB_BUFF_SKIP name="%s" target="%s" reason=%s'):format(
						tostring(action_name),
						tostring(m.name or '?'),
						tostring(reason or 'NOT_READY')
					))
					if normalize_name(action_name):lower() == 'enlight ii' then
						helpers.log_debug(('HB_BUFF_TRACE action="%s" target="%s" ready=0 reason=%s'):format(
							tostring(action_name),
							tostring(m.name or '?'),
							tostring(reason or 'NOT_READY')
						))
					end
				end
			end
		end
	end
	return first_eligible_non_majesty
end

return mod
