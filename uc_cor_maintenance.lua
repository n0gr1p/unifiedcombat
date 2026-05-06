local mod = {}

local default_roll_pair = { "Ninja Roll", "Corsair's Roll" }

local rolls = {
	[98] = { id = 98, buff = 310, en = "Fighter's Roll", lucky = 5, unlucky = 9 },
	[99] = { id = 99, buff = 311, en = "Monk's Roll", lucky = 3, unlucky = 7 },
	[100] = { id = 100, buff = 312, en = "Healer's Roll", lucky = 3, unlucky = 7 },
	[101] = { id = 101, buff = 313, en = "Wizard's Roll", lucky = 5, unlucky = 9 },
	[102] = { id = 102, buff = 314, en = "Warlock's Roll", lucky = 4, unlucky = 8 },
	[103] = { id = 103, buff = 315, en = "Rogue's Roll", lucky = 5, unlucky = 9 },
	[104] = { id = 104, buff = 316, en = "Gallant's Roll", lucky = 3, unlucky = 7 },
	[105] = { id = 105, buff = 317, en = "Chaos Roll", lucky = 4, unlucky = 8 },
	[106] = { id = 106, buff = 318, en = "Beast Roll", lucky = 4, unlucky = 8 },
	[107] = { id = 107, buff = 319, en = "Choral Roll", lucky = 2, unlucky = 6 },
	[108] = { id = 108, buff = 320, en = "Hunter's Roll", lucky = 4, unlucky = 8 },
	[109] = { id = 109, buff = 321, en = "Samurai Roll", lucky = 2, unlucky = 6 },
	[110] = { id = 110, buff = 322, en = "Ninja Roll", lucky = 4, unlucky = 8 },
	[111] = { id = 111, buff = 323, en = "Drachen Roll", lucky = 4, unlucky = 7 },
	[112] = { id = 112, buff = 324, en = "Evoker's Roll", lucky = 5, unlucky = 9 },
	[113] = { id = 113, buff = 325, en = "Magus's Roll", lucky = 2, unlucky = 6 },
	[114] = { id = 114, buff = 326, en = "Corsair's Roll", lucky = 5, unlucky = 9 },
	[115] = { id = 115, buff = 327, en = "Puppet Roll", lucky = 3, unlucky = 8 },
	[116] = { id = 116, buff = 328, en = "Dancer's Roll", lucky = 3, unlucky = 7 },
	[117] = { id = 117, buff = 329, en = "Scholar's Roll", lucky = 2, unlucky = 6 },
	[118] = { id = 118, buff = 330, en = "Bolter's Roll", lucky = 3, unlucky = 9 },
	[119] = { id = 119, buff = 331, en = "Caster's Roll", lucky = 2, unlucky = 7 },
	[120] = { id = 120, buff = 332, en = "Courser's Roll", lucky = 3, unlucky = 9 },
	[121] = { id = 121, buff = 333, en = "Blitzer's Roll", lucky = 4, unlucky = 9 },
	[122] = { id = 122, buff = 334, en = "Tactician's Roll", lucky = 5, unlucky = 8 },
	[302] = { id = 302, buff = 335, en = "Allies' Roll", lucky = 3, unlucky = 10 },
	[303] = { id = 303, buff = 336, en = "Miser's Roll", lucky = 5, unlucky = 7 },
	[304] = { id = 304, buff = 337, en = "Companion's Roll", lucky = 2, unlucky = 10 },
	[305] = { id = 305, buff = 338, en = "Avenger's Roll", lucky = 4, unlucky = 8 },
	[390] = { id = 390, buff = 339, en = "Naturalist's Roll", lucky = 3, unlucky = 7 },
	[391] = { id = 391, buff = 600, en = "Runeist's Roll", lucky = 4, unlucky = 8 },
}

local finish_act = { [2] = true, [3] = true, [5] = true }
local start_act = { [7] = true, [8] = true, [9] = true, [12] = true }

local state = {
	roll_value_by_buff = {},
	active_roll_id = 0,
	bust_roll_id = 0,
	is_busy = false,
	busy_until = 0,
}

local cor_diag_state = {
	last_sig = "",
	last_at = 0,
}

local function cor_diag(sig, msg)
	if type(rawget(_G, "UC_LOG_DIAG")) ~= "function" then
		return
	end
	local s = tostring(sig or "")
	local line = tostring(msg or "")
	local now = os.clock()
	if s ~= "" then
		if s == cor_diag_state.last_sig and (now - (tonumber(cor_diag_state.last_at) or 0)) < 1.5 then
			return
		end
		cor_diag_state.last_sig = s
		cor_diag_state.last_at = now
	end
	pcall(_G.UC_LOG_DIAG, "cor_sched", line)
end

local function normalize_roll_name(name)
	local s = tostring(name or "")
	if s == "" then
		return ""
	end
	s = s:gsub("\\u0027", "'")
	s = s:gsub("\\x27", "'")
	s = s:gsub("’", "'")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("%s+", " ")
	return s:lower()
end

local roll_by_name = {}
for _, info in pairs(rolls) do
	local n = tostring(info.en or "")
	if n ~= "" then
		roll_by_name[normalize_roll_name(n)] = info
	end
end

local function has_buff(player, buff_id)
	for _, b in ipairs(player and player.buffs or {}) do
		if b == buff_id then
			return true
		end
	end
	return false
end

local function make_action(ja_name, reason_code, urgency, detail)
	return {
		action_name = ja_name,
		action_type = "ja",
		target_kind = "self",
		target_name = "<me>",
		target_id = 0,
		reason_code = reason_code,
		urgency = urgency,
		detail = detail or {},
	}
end

local function resolve_roll_pair(settings)
	local r1_raw = tostring(settings and settings.cor_roll_1 or "")
	local r2_raw = tostring(settings and settings.cor_roll_2 or "")
	local r1 = roll_by_name[normalize_roll_name(r1_raw)]
	local r2 = roll_by_name[normalize_roll_name(r2_raw)]
	if r1 and r2 then
		return r1.en, r2.en, "configured"
	end
	local picks = {}
	for _, a in ipairs(settings and settings.abilities or {}) do
		local info = roll_by_name[normalize_roll_name(a)]
		if info then
			picks[#picks + 1] = info.en
			if #picks >= 2 then
				break
			end
		end
	end
	if #picks >= 2 then
		return picks[1], picks[2], "abilities"
	end
	return default_roll_pair[1], default_roll_pair[2], "default"
end

local function has_luzaf_ring_anywhere()
	local equippable_bags = { 'Inventory', 'Wardrobe', 'Wardrobe2', 'Wardrobe3', 'Wardrobe4' }
	for _, bag in ipairs(equippable_bags) do
		local items = windower.ffxi.get_items(bag)
		if items and items.enabled then
			for _, v in ipairs(items) do
				if v and tonumber(v.id) == 15810 then
					return true
				end
			end
		end
	end
	return false
end

local function roll_aoe_range(settings)
	if settings and settings.cor_luzaf_range_override == true then
		return 16
	end
	return has_luzaf_ring_anywhere() and 16 or 8
end

local function in_required_roll_range(settings, max_range)
	local req = settings and settings.cor_roll_range_require_ids or {}
	if type(req) ~= 'table' or #req == 0 then
		return true, nil
	end
	for _, pid in ipairs(req) do
		local member = windower.ffxi.get_mob_by_id(tonumber(pid) or 0)
		if not member or member.hpp <= 0 then
			return false, pid
		end
		local d = member.distance and member.distance:sqrt() or 999
		if d >= max_range then
			return false, pid
		end
	end
	return true, nil
end

function mod.update_from_incoming_chunk(id, data)
	if type(id) ~= "number" or type(data) ~= "string" then
		return
	end
	local me = windower.ffxi.get_mob_by_target("me")
	local me_id = tonumber(me and me.id) or 0
	if me_id == 0 then
		return
	end
	if id == 0x028 then
		local actor_id = data:unpack("I", 6)
		if actor_id ~= me_id then
			return
		end
		local category, param = data:unpack("b4b16", 11, 3)
		local recast = data:unpack("b32", 15, 7)
		local effect, message = data:unpack("b17b10", 27, 6)
		local now = os.clock()
		if start_act[category] then
			state.is_busy = true
			local hold = tonumber(recast) or 0
			if hold < 1.0 then
				hold = 1.0
			end
			state.busy_until = now + hold
		elseif finish_act[category] then
			state.is_busy = false
			state.busy_until = 0
		end
		if category == 6 then
			local roll = rolls[param]
			if message == 420 and roll then
				state.roll_value_by_buff[roll.buff] = effect
				state.active_roll_id = tonumber(param) or 0
			elseif message == 424 and roll then
				state.roll_value_by_buff[roll.buff] = effect
			elseif message == 426 and roll then
				state.roll_value_by_buff[roll.buff] = nil
				state.bust_roll_id = tonumber(param) or 0
			end
		end
	elseif id == 0x063 and data:byte(5) == 9 then
		local keep = {}
		for n = 1, 32 do
			local buff = data:unpack("H", n * 2 + 7)
			if buff == 255 then
				break
			end
			if (buff >= 310 and buff <= 339) or buff == 600 then
				keep[buff] = state.roll_value_by_buff[buff] or 11
			end
		end
		state.roll_value_by_buff = keep
	end
end

function mod.propose(settings)
	local p = windower.ffxi.get_player()
	if not p then
		cor_diag("no_player", "skip no_player")
		return nil
	end
	local main = tostring(p.main_job or "")
	local sub = tostring(p.sub_job or "")
	if main ~= "COR" and sub ~= "COR" then
		cor_diag("not_cor", ("skip not_cor main=%s sub=%s"):format(main, sub))
		return nil
	end
	if tonumber(p.status) and tonumber(p.status) > 1 then
		cor_diag("status_block", ("skip status=%s"):format(tostring(p.status or 0)))
		return nil
	end
	if has_buff(p, 16) then
		cor_diag("amnesia", "skip amnesia")
		return nil
	end
	if state.is_busy and os.clock() < (tonumber(state.busy_until) or 0) then
		cor_diag("busy", ("skip busy_until=%.2f now=%.2f"):format(tonumber(state.busy_until) or 0, os.clock()))
		return nil
	end
	local max_range = roll_aoe_range(settings or {})
	local in_range, bad_id = in_required_roll_range(settings or {}, max_range)
	if not in_range then
		cor_diag("range_gate", ("skip range_gate max=%.1f bad_id=%s"):format(tonumber(max_range) or 0, tostring(bad_id or 0)))
		return nil
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	local roll1, roll2, source = resolve_roll_pair(settings or {})
	local infos = { roll_by_name[normalize_roll_name(roll1)], roll_by_name[normalize_roll_name(roll2)] }
	local roll_count = (main == "COR") and 2 or 1
	local crooked_slot = tonumber(settings and settings.cor_crooked_roll_slot) or 0
	-- Crooked Cards is main-COR only; completely disable for sub-COR path.
	if main ~= "COR" then
		crooked_slot = 0
	end
	-- Guard against stale/invalid profile values.
	if crooked_slot < 0 or crooked_slot > 2 then
		crooked_slot = 0
	end
	local elevens = settings and settings.cor_elevens == true
	local has_bust = has_buff(p, 309)
	cor_diag(
		("cfg:%s|%s|slot=%d|e11=%s|max=%.1f|r96=%d|r193=%d"):format(
			tostring(roll1), tostring(roll2), tonumber(crooked_slot) or 0, tostring(elevens), tonumber(max_range) or 0,
			tonumber(recasts[96] or 0), tonumber(recasts[193] or 0)
		),
		("cfg main=%s sub=%s rolls=[%s,%s] source=%s roll_count=%d crooked_slot=%d elevens=%s max_range=%.1f recast96=%d recast193=%d has601=%s"):format(
			main, sub, tostring(roll1), tostring(roll2), tostring(source), tonumber(roll_count) or 0, tonumber(crooked_slot) or 0, tostring(elevens),
			tonumber(max_range) or 0, tonumber(recasts[96] or 0), tonumber(recasts[193] or 0), tostring(has_buff(p, 601))
		)
	)

	for idx = 1, roll_count do
		local info = infos[idx]
		if info then
			local has_roll_buff = has_buff(p, info.buff)
			local roll_val = tonumber(state.roll_value_by_buff[info.buff]) or nil
			local active_roll_id = tonumber(state.active_roll_id) or 0
			local has_snake_eye = has_buff(p, 357)

			if not has_roll_buff then
				if crooked_slot == idx and not has_buff(p, 601) and (recasts[96] or 0) == 0 then
					cor_diag(
						("pick_cc:%d:%s"):format(idx, tostring(info.en)),
						('pick action="Crooked Cards" slot=%d roll="%s" reason=roll_missing recast96=%d has601=%s'):format(
							tonumber(idx) or 0, tostring(info.en), tonumber(recasts[96] or 0), tostring(has_buff(p, 601))
						)
					)
					return make_action("Crooked Cards", "cor_roll_crooked_cards", 0.78, {
						roll_slot = idx,
						roll = info.en,
						roll_source = source,
						max_range = max_range,
						range_gate_target_id = tonumber(bad_id) or 0,
					})
				elseif crooked_slot == idx then
					cor_diag(
						("skip_cc:%d:%s:%d:%s"):format(idx, tostring(info.en), tonumber(recasts[96] or 0), tostring(has_buff(p, 601))),
						('skip action="Crooked Cards" slot=%d roll="%s" reason=%s recast96=%d has601=%s'):format(
							tonumber(idx) or 0,
							tostring(info.en),
							has_buff(p, 601) and "already_buffed" or "recast",
							tonumber(recasts[96] or 0),
							tostring(has_buff(p, 601))
						)
					)
				end
				if (recasts[193] or 0) == 0 then
					cor_diag(
						("pick_roll:%d:%s"):format(idx, tostring(info.en)),
						('pick action="%s" slot=%d reason=roll_missing recast193=%d'):format(
							tostring(info.en), tonumber(idx) or 0, tonumber(recasts[193] or 0)
						)
					)
					return make_action(info.en, "cor_roll_missing", 0.75, {
						roll_slot = idx,
						roll_source = source,
						roll = info.en,
						max_range = max_range,
						range_gate_target_id = tonumber(bad_id) or 0,
					})
				else
					cor_diag(
						("skip_roll:%d:%s:%d"):format(idx, tostring(info.en), tonumber(recasts[193] or 0)),
						('skip action="%s" slot=%d reason=phantom_recast recast193=%d'):format(
							tostring(info.en), tonumber(idx) or 0, tonumber(recasts[193] or 0)
						)
					)
				end
			elseif active_roll_id == info.id and roll_val and roll_val ~= 11 then
				if elevens then
					if roll_val == 10 and not has_snake_eye and (recasts[197] or 0) == 0 then
						cor_diag(("pick_snake_e11:%s:%d"):format(tostring(info.en), tonumber(roll_val) or 0), ('pick action="Snake Eye" roll="%s" roll_val=%d mode=elevens'):format(tostring(info.en), tonumber(roll_val) or 0))
						return make_action("Snake Eye", "cor_roll_eleven_snake_eye", 0.70, { roll = info.en, roll_val = roll_val })
					end
					if (has_snake_eye or roll_val < 11) and (recasts[194] or 0) == 0 then
						cor_diag(("pick_du_e11:%s:%d"):format(tostring(info.en), tonumber(roll_val) or 0), ('pick action="Double-Up" roll="%s" roll_val=%d mode=elevens'):format(tostring(info.en), tonumber(roll_val) or 0))
						return make_action("Double-Up", "cor_roll_eleven_double_up", 0.68, { roll = info.en, roll_val = roll_val })
					end
				elseif roll_val ~= info.lucky then
					local should_snake = (roll_val == (info.lucky - 1)) or roll_val == 10 or (info.unlucky > 6 and roll_val == info.unlucky)
					if should_snake and not has_snake_eye and (recasts[197] or 0) == 0 then
						cor_diag(("pick_snake:%s:%d"):format(tostring(info.en), tonumber(roll_val) or 0), ('pick action="Snake Eye" roll="%s" roll_val=%d'):format(tostring(info.en), tonumber(roll_val) or 0))
						return make_action("Snake Eye", "cor_roll_snake_eye", 0.70, { roll = info.en, roll_val = roll_val, lucky = info.lucky, unlucky = info.unlucky })
					end
					if (has_snake_eye or roll_val < 7) and (recasts[194] or 0) == 0 then
						cor_diag(("pick_du:%s:%d"):format(tostring(info.en), tonumber(roll_val) or 0), ('pick action="Double-Up" roll="%s" roll_val=%d'):format(tostring(info.en), tonumber(roll_val) or 0))
						return make_action("Double-Up", "cor_roll_double_up", 0.68, { roll = info.en, roll_val = roll_val, lucky = info.lucky, unlucky = info.unlucky })
					end
				end
			end
		end
	end

	if has_bust then
		local both_not_11 = true
		for idx = 1, roll_count do
			local info = infos[idx]
			if info and (tonumber(state.roll_value_by_buff[info.buff]) or 0) == 11 then
				both_not_11 = false
				break
			end
		end
		if both_not_11 and (recasts[198] or 0) == 0 then
			cor_diag("pick_fold", ('pick action="Fold" bust_roll_id=%d'):format(tonumber(state.bust_roll_id) or 0))
			return make_action("Fold", "cor_roll_fold", 0.85, { bust_roll_id = tonumber(state.bust_roll_id) or 0 })
		end
	end
	cor_diag("no_action", "skip no_action_all_conditions")
	return nil
end

return mod
