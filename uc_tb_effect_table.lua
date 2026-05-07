local M = {}

local spells = dofile(windower.addon_path .. 'TargetBar\\spells.lua')
local abilities = dofile(windower.addon_path .. 'TargetBar\\abilities.lua')
local skills = dofile(windower.addon_path .. 'TargetBar\\skills.lua')

local function apply_list(set_effect, target_id, list, source, now)
	if type(list) ~= 'table' then return end
	for i = 1, #list do
		local r = list[i]
		if type(r) == 'table' then
			local eid = tonumber(r[1]) or 0
			local dur = tonumber(r[2]) or 0
			if eid > 0 then
				set_effect(target_id, eid, source, now, dur)
			end
		end
	end
end

local function apply_catalog(set_effect, action_id, actor_id, target_id, from_player, catalog, source, now)
	local id = tonumber(action_id) or 0
	if id <= 0 or type(catalog) ~= 'table' then return end
	local entry = catalog[id]
	if type(entry) ~= 'table' or #entry == 0 then return end
	if type(entry[1]) == 'number' then
		local eid = tonumber(entry[1]) or 0
		local dur = tonumber(entry[2]) or 0
		if eid > 0 then set_effect(target_id, eid, source, now, dur) end
		return
	end
	if type(entry[1]) == 'table' and type(entry[1][1]) == 'number' then
		apply_list(set_effect, target_id, entry, source, now)
		return
	end
	if type(entry[1]) == 'table' and type(entry[1][1]) == 'table' then
		apply_list(set_effect, target_id, entry[1], source, now)
		if not from_player then
			apply_list(set_effect, actor_id, entry[2], source .. '_actor', now)
		end
	end
end

-- Literal branch/message semantics ported from TargetBar AddEffectToTargets.
function M.apply_from_action(act, player_id, set_effect, clear_effect, now)
	if type(act) ~= 'table' or type(act.targets) ~= 'table' then return end
	local actor_id = tonumber(act.actor_id) or 0
	if actor_id <= 0 then return end
	local from_player = (tonumber(player_id) > 0 and actor_id == tonumber(player_id))
	local category = tonumber(act.category) or 0

	for _, target in ipairs(act.targets) do
		local tid = tonumber(target and target.id) or 0
		if tid > 0 and type(target.actions) == 'table' then
			for i = 1, #target.actions do
				local a = target.actions[i] or {}
				local msg = tonumber(a.message) or tonumber(a.message_id) or 0
				local eid = tonumber(a.param) or 0

				if (not from_player) and i == 1 and (msg == 29 or msg == 84) then
					set_effect(actor_id, 4, 'tb_actor_para', now, 60)
				end

				if category == 1 or category == 2 then
					if msg == 1 or msg == 67 or msg == 157 or msg == 353 or msg == 577 then
						clear_effect(tid, 36); clear_effect(tid, 66); clear_effect(tid, 444); clear_effect(tid, 445); clear_effect(tid, 446)
						if eid > 0 then clear_effect(tid, 37) end
					elseif msg == 30 then
						clear_effect(tid, 67)
					end
					if a.has_add_effect then
						local em = tonumber(a.add_effect_message) or 0
						local ee = tonumber(a.add_effect_param) or 0
						if (em == 160 or em == 164) and ee > 0 then
							set_effect(tid, ee, ('tb_add_%d'):format(em), now, 60)
						end
					end
				elseif category == 4 then
					if msg == 2 or msg == 230 or msg == 236 or msg == 237 or msg == 252 or msg == 264 or msg == 266
						or msg == 268 or msg == 269 or msg == 270 or msg == 271 or msg == 272
						or msg == 329 or msg == 330 or msg == 331 or msg == 332 or msg == 333 or msg == 334 or msg == 335 then
						apply_catalog(set_effect, tonumber(act.param) or 0, actor_id, tid, from_player, spells, ('tb_spell_%d'):format(msg), now)
					elseif msg == 83 or msg == 341 or msg == 342 or msg == 343 or msg == 344 then
						clear_effect(tid, eid)
					elseif msg == 84 then
						set_effect(tid, 4, 'tb_spell_para', now, 60)
					end
				elseif category == 6 or category == 13 or category == 14 or category == 15 then
					if msg == 100 or msg == 102 or msg == 110 or msg == 115 or msg == 116 or msg == 117 or msg == 118 or msg == 119
						or msg == 120 or msg == 121 or msg == 126 or msg == 131 or msg == 134 or msg == 143 or msg == 148 or msg == 149
						or msg == 266 or msg == 285 or msg == 286 or msg == 287 or msg == 304 or msg == 317 or msg == 319
						or msg == 452 or msg == 519 or msg == 529 or msg == 667 or msg == 668 or msg == 669 then
						apply_catalog(set_effect, tonumber(act.param) or 0, actor_id, tid, from_player, abilities, ('tb_ja_%d'):format(msg), now)
					end
				elseif category == 3 or category == 11 then
					if msg == 1 or msg == 101 or msg == 110 or msg == 185 or msg == 187 or msg == 194 or msg == 224 or msg == 225
						or msg == 226 or msg == 238 or msg == 242 or msg == 243 or msg == 264 or msg == 276 or msg == 277
						or msg == 278 or msg == 280 or msg == 281 or msg == 299 or msg == 317 or msg == 367 or msg == 763 then
						apply_catalog(set_effect, tonumber(act.param) or 0, actor_id, tid, from_player, skills, ('tb_ws_%d'):format(msg), now)
					end
				end
			end
		end
	end
	if not from_player then
		clear_effect(actor_id, 10); clear_effect(actor_id, 2); clear_effect(actor_id, 7)
	end
end

return M
