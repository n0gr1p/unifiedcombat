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

local function normalize_roll_name(name)
	local s = tostring(name or "")
	if s == "" then
		return ""
	end
	-- Handle escaped apostrophes seen in bridge/profile payloads.
	s = s:gsub("\\u0027", "'")
	s = s:gsub("\\x27", "'")
	-- Normalize curly apostrophe variants to straight apostrophe.
	s = s:gsub("’", "'")
	-- Normalize spacing/case for stable lookup.
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("%s+", " ")
	return s:lower()
end

local roll_by_name = {}
for id, info in pairs(rolls) do
	local n = tostring(info.en or "")
	if n ~= "" then
		roll_by_name[normalize_roll_name(n)] = info
	end
end

local state = {
	roll_value_by_buff = {},
	active_roll_id = 0, -- buff 308 payload (roll id currently on double-up window)
	bust_roll_id = 0, -- buff 309 payload (roll id busted)
}

local function has_buff(player, buff_id)
	for _, b in ipairs(player and player.buffs or {}) do
		if b == buff_id then
			return true
		end
	end
	return false
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
		local name = tostring(a or "")
		local info = roll_by_name[normalize_roll_name(name)]
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
		local effect, message = data:unpack("b17b10", 27, 6)
		if category == 6 then
			local roll = rolls[param]
			if message == 420 and roll then -- Phantom Roll
				state.roll_value_by_buff[roll.buff] = effect
				state.active_roll_id = tonumber(param) or 0
			elseif message == 424 and roll then -- Double-Up
				state.roll_value_by_buff[roll.buff] = effect
			elseif message == 426 and roll then -- Bust
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
		return nil
	end
	local main = tostring(p.main_job or "")
	local sub = tostring(p.sub_job or "")
	if main ~= "COR" and sub ~= "COR" then
		return nil
	end
	if tonumber(p.status) and tonumber(p.status) > 1 then
		return nil
	end
	-- Keep maintenance passive while occupied.
	if has_buff(p, 16) then
		return nil
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	local roll1, roll2, source = resolve_roll_pair(settings or {})
	local infos = { roll_by_name[roll1:lower()], roll_by_name[roll2:lower()] }
	for idx = 1, #infos do
		local info = infos[idx]
		if info then
			local has_roll_buff = has_buff(p, info.buff)
			local roll_val = tonumber(state.roll_value_by_buff[info.buff]) or nil
			local active_roll_id = tonumber(state.active_roll_id) or 0
			if not has_roll_buff then
				if (recasts[193] or 0) == 0 then
					return make_action(info.en, "cor_roll_missing", 0.75, { roll_slot = idx, roll_source = source, roll = info.en })
				end
			elseif active_roll_id == info.id and roll_val and roll_val ~= info.lucky and roll_val ~= 11 then
				local has_snake_eye = has_buff(p, 357)
				local should_snake = (roll_val == (info.lucky - 1)) or roll_val == 10 or (info.unlucky > 6 and roll_val == info.unlucky)
				if should_snake and not has_snake_eye and (recasts[197] or 0) == 0 then
					return make_action("Snake Eye", "cor_roll_snake_eye", 0.70, { roll = info.en, roll_val = roll_val, lucky = info.lucky, unlucky = info.unlucky })
				end
				if (has_snake_eye or roll_val < 7) and (recasts[194] or 0) == 0 then
					return make_action("Double-Up", "cor_roll_double_up", 0.68, { roll = info.en, roll_val = roll_val, lucky = info.lucky, unlucky = info.unlucky })
				end
			end
		end
	end
	local has_bust = has_buff(p, 309)
	if has_bust and (recasts[198] or 0) == 0 then
		return make_action("Fold", "cor_roll_fold", 0.85, { bust_roll_id = tonumber(state.bust_roll_id) or 0 })
	end
	return nil
end

return mod
