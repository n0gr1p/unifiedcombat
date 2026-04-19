local res = require('resources')
local skills = require('skills')
local uc_ability_pipeline = require('uc_ability_pipeline')
local uc_ws_gate = require('uc_ws_gate')
local uc_ws_memory = require('uc_ws_memory')
local uc_ignore = require('uc_ignore')
local uc_target_ignore = require('uc_target_ignore')
local uc_partner_list = require('uc_partner_list')
local uc_fight_leader = require('uc_fight_leader')
local uc_add_control = require('uc_add_control')
local uc_targeting_common = require('uc_targeting_common')
local uc_settarget = require('uc_settarget')
local uc_attack = require('uc_attack')

local core = {
	adapters = {},
	last_engine = '',
	resonating = {},
	ws_candidates = {},
	ws_timer = 0,
	buffs = {},
	last_spacing_member_id = 0,
	last_spacing_until = 0,
	sticky_target_id = 0,
	sticky_hold_until = 0,
	last_player_status = 0,
	last_death_target_id = 0,
	last_death_at = 0,
}

local skillchain_ids = {
	[288] = true, [289] = true, [290] = true, [291] = true, [292] = true, [293] = true, [294] = true, [295] = true,
	[296] = true, [297] = true, [298] = true, [299] = true, [300] = true, [301] = true, [385] = true, [386] = true,
	[387] = true, [388] = true, [389] = true, [390] = true, [391] = true, [392] = true, [393] = true, [394] = true,
	[395] = true, [396] = true, [397] = true, [767] = true, [768] = true, [769] = true, [770] = true,
}

local action_message_ids = {
	[110] = true, [185] = true, [187] = true, [317] = true, [802] = true,
}

local death_message_ids = {
	[6] = true, [20] = true, [113] = true, [406] = true, [605] = true, [646] = true,
}

local DEATH_SWITCH_WINDOW = 0.9

local action_categories = {
	weaponskill_finish = true,
	spell_finish = true,
	job_ability = true,
	mob_tp_finish = true,
	avatar_tp_finish = true,
	job_ability_unblinkable = true,
}

local buff_dur = { [163] = 40, [164] = 30, [470] = 60 }

local sc_info = {
	Radiance = { 'Fire', 'Wind', 'Lightning', 'Light', lvl = 4 },
	Umbra = { 'Earth', 'Ice', 'Water', 'Dark', lvl = 4 },
	Light = { 'Fire', 'Wind', 'Lightning', 'Light', Light = { 4, 'Light', 'Radiance' }, lvl = 3 },
	Darkness = { 'Earth', 'Ice', 'Water', 'Dark', Darkness = { 4, 'Darkness', 'Umbra' }, lvl = 3 },
	Gravitation = { 'Earth', 'Dark', Distortion = { 3, 'Darkness' }, Fragmentation = { 2, 'Fragmentation' }, lvl = 2 },
	Fragmentation = { 'Wind', 'Lightning', Fusion = { 3, 'Light' }, Distortion = { 2, 'Distortion' }, lvl = 2 },
	Distortion = { 'Ice', 'Water', Gravitation = { 3, 'Darkness' }, Fusion = { 2, 'Fusion' }, lvl = 2 },
	Fusion = { 'Fire', 'Light', Fragmentation = { 3, 'Light' }, Gravitation = { 2, 'Gravitation' }, lvl = 2 },
	Compression = { 'Darkness', Transfixion = { 1, 'Transfixion' }, Detonation = { 1, 'Detonation' }, lvl = 1 },
	Liquefaction = { 'Fire', Impaction = { 2, 'Fusion' }, Scission = { 1, 'Scission' }, lvl = 1 },
	Induration = { 'Ice', Reverberation = { 2, 'Fragmentation' }, Compression = { 1, 'Compression' }, Impaction = { 1, 'Impaction' }, lvl = 1 },
	Reverberation = { 'Water', Induration = { 1, 'Induration' }, Impaction = { 1, 'Impaction' }, lvl = 1 },
	Transfixion = { 'Light', Scission = { 2, 'Distortion' }, Reverberation = { 1, 'Reverberation' }, Compression = { 1, 'Compression' }, lvl = 1 },
	Scission = { 'Earth', Liquefaction = { 1, 'Liquefaction' }, Reverberation = { 1, 'Reverberation' }, Detonation = { 1, 'Detonation' }, lvl = 1 },
	Detonation = { 'Wind', Compression = { 2, 'Gravitation' }, Scission = { 1, 'Scission' }, lvl = 1 },
	Impaction = { 'Lightning', Liquefaction = { 1, 'Liquefaction' }, Detonation = { 1, 'Detonation' }, lvl = 1 },
}

local chainbound = {
	[1] = { 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' },
	[2] = { 'Gravitation', 'Fragmentation', 'Distortion', 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' },
	[3] = { 'Light', 'Darkness', 'Gravitation', 'Fragmentation', 'Distortion', 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' },
}

local function setting_enabled(v)
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function get_active_engine()
	return 'UC'
end

local function get_settings()
	return rawget(_G, 'UC_SETTINGS') or {}
end

local function get_current_target()
	return windower.ffxi.get_mob_by_target('t')
end

local function target_distance(mob)
	if not mob or mob.distance == nil then
		return 999
	end
	return mob.distance:sqrt()
end

local function target_real_distance(mob)
	if not mob then
		return 999
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or mob.distance == nil then
		return 999
	end
	return mob.distance:sqrt() - (mob.model_size or 0) - (me.model_size or 0)
end

local function mob_distance(a, b)
	if not a or not b or a.x == nil or a.y == nil or b.x == nil or b.y == nil then
		return 999
	end
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local function mob_real_distance(a, b)
	if not a or not b or a.x == nil or a.y == nil or b.x == nil or b.y == nil then
		return 999
	end
	local d = mob_distance(a, b)
	return d - (a.model_size or 0) - (b.model_size or 0)
end

local function death_event_active_for_id(id)
	local tid = tonumber(id) or 0
	if tid <= 0 then
		return false
	end
	return (tonumber(core.last_death_target_id) or 0) == tid and
		((os.clock() - (tonumber(core.last_death_at) or 0)) <= DEATH_SWITCH_WINDOW)
end

local function uc_heading_to(x, y)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or me.x == nil or me.y == nil or x == nil or y == nil then
		return nil
	end
	local dx = x - me.x
	local dy = y - me.y
	return (math.atan2(dx, dy) - 1.5708)
end

local function uc_heading_from_vector(vx, vy)
	if vx == nil or vy == nil then
		return nil
	end
	if (vx * vx + vy * vy) < 0.000001 then
		return nil
	end
	return (math.atan2(vx, vy) - 1.5708)
end

-- Real-time spacing-aware approach heading:
-- attract toward target while repelling from nearby party members.
local function uc_spacing_aware_approach_heading(me, target)
	if not me or not target or me.x == nil or me.y == nil or target.x == nil or target.y == nil then
		return nil
	end
	local tx = target.x - me.x
	local ty = target.y - me.y
	local tlen = math.sqrt((tx * tx) + (ty * ty))
	if tlen < 0.0001 then
		return nil
	end

	local ax = tx / tlen
	local ay = ty / tlen
	local rx = 0
	local ry = 0
	local repel_range = 1.0
	local party = windower.ffxi.get_party() or {}
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }

	for _, k in ipairs(keys) do
		local e = party[k]
		local pm = e and e.mob
		local pid = pm and pm.id or 0
		if pid ~= 0 and pid ~= me.id then
			local member = windower.ffxi.get_mob_by_id(pid)
			if member and member.x ~= nil and member.y ~= nil then
				local pdist = mob_real_distance(me, member)
				if pdist < repel_range then
					local dx = me.x - member.x
					local dy = me.y - member.y
					local plen = math.sqrt((dx * dx) + (dy * dy))
					if plen > 0.0001 then
						local strength = (repel_range - pdist) / repel_range
						if strength < 0 then
							strength = 0
						end
						rx = rx + (dx / plen) * strength
						ry = ry + (dy / plen) * strength
					end
				end
			end
		end
	end

	local repel_weight = 1.35
	local vx = ax + (rx * repel_weight)
	local vy = ay + (ry * repel_weight)
	local heading = uc_heading_from_vector(vx, vy)
	if heading then
		return heading
	end
	return uc_heading_to(target.x, target.y)
end

local function find_candidate_target(settings)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me then
		return nil
	end
	local player = windower.ffxi.get_player()
	local engaged = player and player.status == 1
	-- Engaged retarget is only allowed for the explicit add-control flow (which already
	-- requires fight-leader + add-control). Do not unlock stickiness for fight-leader alone.
	local allow_engaged_retarget = uc_add_control.enabled(settings)
	local cur = get_current_target()
	local cur_alive_monster = cur and cur.valid_target and cur.hpp and cur.hpp > 0 and cur.spawn_type == 16
	local cur_dead_monster = cur and cur.spawn_type == 16 and ((cur.hpp or 0) <= 0 or death_event_active_for_id(cur.id))

	-- Engaged target stickiness:
	-- keep current living combat target locked unless explicit engaged retarget modes are enabled.
	if not allow_engaged_retarget then
		local sticky_id = tonumber(core.sticky_target_id) or 0
		local sticky_active = engaged or (os.clock() < (tonumber(core.sticky_hold_until) or 0))
		local sticky_dead_event = death_event_active_for_id(sticky_id)
		if sticky_id > 0 then
			local sticky = windower.ffxi.get_mob_by_id(sticky_id)
			if sticky_active and (not sticky_dead_event) and sticky and sticky.valid_target and (sticky.hpp or 0) > 0 and sticky.spawn_type == 16 then
				return sticky
			end
			if not sticky_active then
				core.sticky_target_id = 0
			elseif sticky_dead_event then
				core.sticky_target_id = 0
			end
		end
		if engaged and cur_alive_monster then
			core.sticky_target_id = cur.id
			core.sticky_hold_until = 0
			return cur
		end
		if engaged and cur_dead_monster then
			-- Current engaged target has died; allow one immediate rescan for next valid target
			-- so we can switch focus without waiting for full disengage/re-engage lag.
			core.sticky_target_id = 0
		end
		if engaged then
			-- Do not perform nearest-target evaluation while engaged unless add-control is enabled.
			-- This prevents mid-fight target churn from nearby newly-claimed mobs.
			if not cur_dead_monster then
				return nil
			end
		end
	end

	local claims, claims_set = uc_targeting_common.build_party_claims()
	local marray = windower.ffxi.get_mob_array() or {}
	local partner_target_set = {}
	if setting_enabled(settings.partner) then
		local partner_ids = uc_partner_list.as_ordered_ids(settings)
		for _, pid in ipairs(partner_ids) do
			local pm = windower.ffxi.get_mob_by_id(pid)
			if pm and pm.target_index then
				local tm = windower.ffxi.get_mob_by_index(pm.target_index)
				local tid = tm and tm.id or 0
				if tid ~= 0 then
					partner_target_set[tid] = true
				end
			end
		end
	end
	local leader_mid = uc_fight_leader.resolve_mid_override(settings, false, function(tid)
		return partner_target_set[tid] == true
	end)
	local add_mid = uc_add_control.pick(settings, claims, marray, leader_mid, {
		hunter_in_claim = false,
		melee_style = true,
		partner_block = function(mob)
			return mob and partner_target_set[mob.id] == true
		end,
	})
	local override_id = 0
	if add_mid and add_mid > 0 then
		override_id = add_mid
	elseif leader_mid and leader_mid > 0 then
		override_id = leader_mid
	end
	if override_id > 0 then
		local ov = windower.ffxi.get_mob_by_id(override_id)
		if ov and ov.valid_target and (ov.hpp or 0) > 0 and ov.spawn_type == 16 then
			return ov
		end
	end
	if cur_alive_monster then
		return cur
	end
	local best = nil
	local best_dist = 1e9
	for _, mob in pairs(marray) do
		if mob and mob.id and mob.valid_target and mob.spawn_type == 16 and (mob.hpp or 0) > 0 then
			if not uc_target_ignore.is_mob_blocked(settings, mob) then
				-- Do not pull unclaimed prime candidates while already engaged unless explicit
				-- engaged-retarget modes are active; this prevents mid-fight target flips.
				local allow_prime_unclaimed = (not engaged) or allow_engaged_retarget
				local prime_unclaimed_ok = (allow_prime_unclaimed and mob.claim_id == 0 and setting_enabled(settings.prime) and mob.status == 1)
				local claim_ok = claims_set[mob.claim_id] == true or prime_unclaimed_ok
				if claim_ok then
					local d = target_distance(mob)
					if d < best_dist then
						best_dist = d
						best = mob
					end
				end
			end
		end
	end
	return best
end

local function ensure_target_and_attack(tid)
	if not tid or tid == 0 then
		return false
	end
	local cur = get_current_target()
	local p = windower.ffxi.get_player()
	local engaged = p and p.status == 1
	if engaged and cur and cur.id and cur.id ~= tid then
		local ok_sw = uc_attack.switch_target(tid)
		if not ok_sw then
			_G.UC_LAST_BLOCK_REASON = 'TARGET_SWITCH_FAIL'
			return false
		end
		coroutine.sleep(0.05)
		cur = get_current_target()
	end
	if not cur or cur.id ~= tid then
		local ok = uc_settarget.select_by_id(tid)
		if not ok then
			_G.UC_LAST_BLOCK_REASON = 'TARGET_SET_FAIL'
			return false
		end
		coroutine.sleep(0.1)
		cur = get_current_target()
	end
	if not cur or cur.id ~= tid then
		return false
	end
	-- Avoid re-sending engage while already engaged on the correct target; repeated engage
	-- injections can create churn on some clients/servers.
	if engaged then
		return true
	end
	local ok_attack = uc_attack.engage_target(tid)
	if not ok_attack then
		_G.UC_LAST_BLOCK_REASON = 'ATTACK_PACKET_FAIL'
		return false
	end
	return true
end

local function stop_run()
	windower.ffxi.run(false)
	core.last_run_active = false
end

local function get_mover()
	if core.mover ~= nil then
		return core.mover or nil
	end
	local actor_new = _libs and _libs.lor and _libs.lor.actor and _libs.lor.actor.Actor and _libs.lor.actor.Actor.new
	if type(actor_new) == 'function' then
		local ok, mover = pcall(actor_new)
		if ok and type(mover) == 'table' then
			core.mover = mover
			return mover
		end
	end
	core.mover = false
	return nil
end

local function apply_facing(settings, target)
	if not setting_enabled(settings.face) or not target then
		return
	end
	local heading = uc_heading_to(target.x, target.y)
	if heading then
		windower.ffxi.turn(heading)
	end
end

local function apply_movement(settings, target)
	if setting_enabled(settings.manual) or setting_enabled(settings.static) or not target then
		if core.last_run_active then
			stop_run()
		end
		return
	end
	if setting_enabled(settings.puller) and (tonumber(settings.puller_id) or 0) > 0 then
		local puller = windower.ffxi.get_mob_by_id(tonumber(settings.puller_id))
		local near = mob_distance(target, puller) <= 6
		local allow = near
		if not setting_enabled(settings.puller_distance_only) then
			allow = near or ((target.hpp or 0) < 99)
		end
		if not allow then
			if core.last_run_active then
				stop_run()
			end
			return
		end
	end
	local dist = target_real_distance(target)
	-- Comfortable fight-distance band around target.
	local max_range = 0.4
	local min_range = -0.9
	local mover = get_mover()
	local me = windower.ffxi.get_mob_by_target('me')
	local closing_to_target = dist > max_range
	if dist > max_range then
		local moved = false
		if setting_enabled(settings.spacing) and me then
			local heading = uc_spacing_aware_approach_heading(me, target)
			if heading then
				windower.ffxi.run(heading)
				moved = true
			end
		end
		if (not moved) and mover and target.id and type(mover.move_towards) == 'function' then
			local ok = pcall(function()
				mover:move_towards(target.id)
			end)
			moved = ok
		end
		if not moved then
			local heading = uc_heading_to(target.x, target.y)
			if heading then
				windower.ffxi.run(heading)
				moved = true
			end
		end
		if not moved then
			windower.ffxi.run()
			moved = true
		end
		core.last_run_active = true
	elseif dist < min_range then
		local moved = false
		if mover and target.id and type(mover.move_away_from) == 'function' then
			local ok = pcall(function()
				mover:move_away_from(target.id)
			end)
			moved = ok
		end
		if not moved then
			local heading = uc_heading_to(target.x, target.y)
			if heading then
				windower.ffxi.run(heading + math.pi)
				moved = true
			end
		end
		if not moved then
			stop_run()
		end
		core.last_run_active = moved
	else
		if core.last_run_active then
			stop_run()
		end
	end

	if closing_to_target then
		-- While closing, spacing is already folded into the approach vector above.
		return
	end

	if setting_enabled(settings.spacing) then
		local p = windower.ffxi.get_player()
		if p and me and p.status == 1 then
			local party = windower.ffxi.get_party() or {}
			local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
			local spacing_trigger = -0.22
			local chosen_id = 0
			local chosen_member = nil
			local chosen_dist = 999

			for _, k in ipairs(keys) do
				local e = party[k]
				local pm = e and e.mob
				local pid = pm and pm.id or 0
				if pid ~= 0 and pid ~= me.id then
					local member = windower.ffxi.get_mob_by_id(pid)
					local pdist = mob_real_distance(me, member)
					if pdist < spacing_trigger and pdist < chosen_dist then
						chosen_id = pid
						chosen_member = member
						chosen_dist = pdist
					end
				end
			end
			if chosen_id ~= 0 then
				local moved = false
				if mover and type(mover.move_away_from) == 'function' then
					local ok = pcall(function()
						mover:move_away_from(chosen_id)
					end)
					moved = ok
				end
				if not moved and chosen_member and chosen_member.x and chosen_member.y then
					local heading = uc_heading_to(chosen_member.x, chosen_member.y)
					if heading then
						windower.ffxi.run(heading + math.pi)
						moved = true
					end
				end
				core.last_run_active = moved
				return
			end
		end
	end
end

local function get_mob_id_by_index(index)
	local ok, mob = pcall(function()
		return windower.ffxi.get_mob_by_index(index)
	end)
	if ok and mob and mob.id then
		return mob.id
	end
	return 0
end

local function get_party_tp()
	local out = {}
	local party = windower.ffxi.get_party() or {}
	local keys = { 'p1', 'p2', 'p3', 'p4', 'p5' }
	for _, k in ipairs(keys) do
		local e = party[k]
		local mob = e and e.mob
		if mob and mob.id and mob.id ~= 0 then
			out[#out + 1] = {
				id = mob.id,
				target = get_mob_id_by_index(mob.target_index),
				tp = e.tp or 0,
				status = mob.status or 0,
			}
		end
	end
	return out
end

local function get_resonating_step(tid)
	local reson = core.resonating[tid]
	local timer = reson and (reson.times - os.clock()) or 0
	if reson and (not reson.closed) and timer > 0 then
		return reson.step or 0
	end
	return 0
end

local function check_props(old_props, new_props)
	for k = 1, #old_props do
		local first = old_props[k]
		local combo = sc_info[first]
		if combo then
			for i = 1, #new_props do
				local second = new_props[i]
				local result = combo[second]
				if result then
					return unpack(result)
				end
				if #old_props > 3 and combo.lvl == (sc_info[second] and sc_info[second].lvl) then
					break
				end
			end
		end
	end
end

local function apply_properties(target_id, resource, action_id, properties, delay, step, closed, bound)
	local clock = os.clock()
	core.resonating[target_id] = {
		res = resource,
		id = action_id,
		active = properties or {},
		delay = clock + (delay or 3),
		times = clock + (delay or 3) + 8 - (step or 1),
		step = step or 1,
		closed = closed == true,
		bound = bound,
	}
end

local function check_buff(t, i)
	if t[i] == true or t[i] - os.time() > 0 then
		return true
	end
	t[i] = nil
	return false
end

local function chain_buff(t)
	local i = t[164] and 164 or t[470] and 470
	if i and check_buff(t, i) then
		t[i] = nil
		return true
	end
	return t[163] and check_buff(t, 163)
end

local function rebuild_ws_candidates(tid)
	local reson = core.resonating[tid]
	local active = reson and reson.active
	if type(active) ~= 'table' or #active == 0 then
		core.ws_candidates[tid] = {}
		return
	end
	local player_abilities = windower.ffxi.get_abilities() or {}
	local ws_ids = player_abilities.weapon_skills or {}
	local out = {}
	for _, ws_id in ipairs(ws_ids) do
		local skillchain = skills.weapon_skills and skills.weapon_skills[ws_id]
		if skillchain and type(skillchain.skillchain) == 'table' then
			local lv, prop = check_props(active, skillchain.skillchain)
			if prop then
				local ws = res.weapon_skills[ws_id]
				local ws_name = ws and (ws.name or ws.en)
				if ws_name and ws_name ~= '' then
					out[#out + 1] = { ws = ws_name, lvl = lv or 0 }
				end
			end
		end
	end
	core.ws_candidates[tid] = out
end

function core.on_action(act)
	if not act or type(ActionPacket) ~= 'table' or type(ActionPacket.new) ~= 'function' then
		return
	end
	local ok, actionpacket = pcall(ActionPacket.new, act)
	if not ok or not actionpacket then
		return
	end
	local category = actionpacket:get_category_string()
	if not action_categories[category] or act.param == 0 then
		return
	end
	local actor = actionpacket:get_id()
	local target = actionpacket:get_targets()()
	if not target then
		return
	end
	local action = target:get_actions()()
	if not action then
		return
	end
	local message_id = action:get_message_id()
	local add_effect = action:get_add_effect()
	local param, resource, action_id, _, conclusion = action:get_spell()
	local ability = skills[resource] and skills[resource][action_id]
	local my_id = (windower.ffxi.get_player() or {}).id
	local current = get_current_target()
	if target and current and target.id == current.id and ability and resource == 'weapon_skills' then
		core.ws_timer = os.clock() + 3
	end

	if add_effect and conclusion and skillchain_ids[add_effect.message_id] then
		local skillchain = add_effect.animation and add_effect.animation:ucfirst()
		local level = skillchain and sc_info[skillchain] and sc_info[skillchain].lvl
		local reson = core.resonating[target.id]
		local delay = (ability and ability.delay) or 3
		local step = ((reson and reson.step) or 1) + 1
		if level == 3 and reson and ability and type(ability.skillchain) == 'table' then
			level = check_props(reson.active, ability.skillchain)
		end
		local closed = step > 5 or level == 4
		if skillchain then
			apply_properties(target.id, resource, action_id, { skillchain }, delay, step, closed)
			rebuild_ws_candidates(target.id)
		end
	elseif ability and (action_message_ids[message_id] or (message_id == 2 and core.buffs[actor] and chain_buff(core.buffs[actor]))) then
		local props = ability.skillchain or {}
		apply_properties(target.id, resource, action_id, props, ability.delay or 3, 1)
		rebuild_ws_candidates(target.id)
	elseif message_id == 529 then
		apply_properties(target.id, resource, action_id, chainbound[param] or {}, 2, 1, false, param)
		rebuild_ws_candidates(target.id)
	elseif message_id == 100 and buff_dur[param] then
		core.buffs[actor] = core.buffs[actor] or {}
		core.buffs[actor][param] = buff_dur[param] + os.time()
	end

	if my_id and actor == my_id and resource == 'weapon_skills' then
		-- no-op placeholder for future ws diagnostics
	end
end

function core.on_action_message(msg)
	if type(msg) ~= 'table' then
		return
	end
	local mid = tonumber(msg.message_id) or 0
	local tid = tonumber(msg.target_id) or 0
	if tid > 0 and death_message_ids[mid] then
		core.last_death_target_id = tid
		core.last_death_at = os.clock()
	end
end

local function can_cast_ja(name)
	local ja = res.job_abilities:with('en', name)
	if not ja then
		return false
	end
	local recasts = windower.ffxi.get_ability_recasts() or {}
	if (recasts[ja.recast_id] or 0) > 0 then
		return false
	end
	local abil = windower.ffxi.get_abilities() or {}
	local owns = false
	for _, id in ipairs(abil.job_abilities or {}) do
		if id == ja.id then
			owns = true
			break
		end
	end
	if not owns then
		return false
	end
	local t = get_current_target()
	if tostring(ja.targets) == '{Enemy}' then
		if not t or t.id == 0 then
			return false
		end
		local d = target_distance(t)
		local r = (tonumber(ja.range) or 0) * ((tonumber(ja.range) or 0) > 20 and 0.01 or 1)
		if r > 0 and d > r then
			return false
		end
	end
	return true
end

local function cast_ja(name)
	local ja = res.job_abilities:with('en', name)
	if not ja then
		return
	end
	if tostring(ja.targets) == '{Self}' or tostring(ja.targets) == '{Self, Player}' then
		windower.send_command('input /ja "' .. name .. '" <me>')
	else
		local t = get_current_target()
		if t and t.id and t.id ~= 0 then
			windower.send_command('input /ja "' .. name .. '" ' .. tostring(t.id))
		end
	end
end

local function select_smart_ws(settings, target_id)
	local tid = tonumber(target_id) or 0
	if tid <= 0 then
		return '', 'NO_TARGET'
	end
	local player = windower.ffxi.get_player() or {}
	if setting_enabled(settings.aftermath_enabled) then
		local am_ws = tostring(settings.aftermath_ws or '')
		if am_ws ~= '' then
			local has_am = false
			for _, bid in ipairs(player.buffs or {}) do
				-- Only treat AM3 as satisfied: Lv1/Lv2 are intentionally ignored and 273 may be external.
				if bid == 272 then
					has_am = true
					break
				end
			end
			if not has_am then
				if not uc_ws_memory.valid_ws_name(am_ws) then
					return '', 'AM_WS_INVALID'
				end
				local tp = (player.vitals and player.vitals.tp) or 0
				if tp >= 3000 then
					return am_ws, 'AM_READY'
				end
				return '', 'AM_HOLD_TP'
			end
		end
	end
	local spam_on = setting_enabled(settings.spam)
	if not spam_on then
		local my_tp = ((windower.ffxi.get_player() or {}).vitals or {}).tp or 0
		local my_id = (windower.ffxi.get_player() or {}).id or 0
		for _, value in ipairs(get_party_tp()) do
			if value.id ~= my_id and not uc_ignore.has_id(settings, value.id) then
				local ally_ws_ready = (value.tp or 0) >= 1000
				local ally_far_ahead = (value.tp or 0) >= (my_tp + 300)
				if value.target == tid and ally_ws_ready and ally_far_ahead and value.status == 1 and not setting_enabled(settings.solo) then
					return '', 'ALLY_WAIT'
				end
			end
		end
	end

	if get_resonating_step(tid) == 0 then
		core.ws_candidates[tid] = {}
	end
	rebuild_ws_candidates(tid)
	local tempwslvl = 0
	local chosen = ''
	for _, value in ipairs(core.ws_candidates[tid] or {}) do
		if (value.lvl or 0) >= tempwslvl then
			chosen = value.ws or ''
			tempwslvl = value.lvl or 0
		end
	end
	if chosen == '' or spam_on or get_resonating_step(tid) == 0 then
		chosen = tostring(settings.weaponskill or settings.ws1 or '')
	end
	if chosen ~= '' and not uc_ws_memory.valid_ws_name(chosen) then
		chosen = uc_ws_memory.recall() or ''
	end
	if chosen == '' then
		return '', 'NO_VALID_WS'
	end
	local target = windower.ffxi.get_mob_by_id(tid)
	local hpp = (target and target.hpp) or 0
	if spam_on then
		return chosen, 'READY_SPAM'
	end
	if os.clock() >= (core.ws_timer or 0) or get_resonating_step(tid) == 0 or (hpp < 20 and setting_enabled(settings.closer)) then
		return chosen, 'READY'
	end
	return '', 'TIMER_LOCK'
end

local function run_unified_combat()
	local s = get_settings()
	local p = windower.ffxi.get_player()
	if not p then
		_G.UC_WS_LAST_DIAG = 'core ws reason=NO_PLAYER'
		return
	end
	_G.UC_WS_LAST_DIAG = 'core ws reason=PENDING'
	local now_status = p.status or 0
	local now = os.clock()
	if now_status ~= 1 then
		if (core.last_player_status or 0) == 1 then
			-- Engagement just dropped; keep sticky target briefly to absorb status jitter.
			core.sticky_hold_until = now + 1.2
		elseif now > (tonumber(core.sticky_hold_until) or 0) then
			core.sticky_target_id = 0
		end
	elseif (core.last_player_status or 0) ~= 1 then
		-- just engaged: seed sticky target once; do not keep rewriting it every tick
		local cur = get_current_target()
		if cur and cur.valid_target and (cur.hpp or 0) > 0 and cur.spawn_type == 16 then
			core.sticky_target_id = cur.id
		end
		core.sticky_hold_until = 0
	end
	core.last_player_status = now_status
	local target = find_candidate_target(s)
	if not target and not setting_enabled(s.manual) then
		_G.UC_COMBAT_INTENT_UNTIL = 0
		if core.last_run_active then
			stop_run()
		end
		_G.UC_LAST_BLOCK_REASON = 'NO_TARGET'
		_G.UC_WS_LAST_DIAG = 'core ws reason=NO_TARGET'
		return
	end
	if target and target.id and target.id ~= 0 then
		-- Hold a short combat-intent window so party-follow does not fight approach movement
		-- during post-kill re-engage delay.
		_G.UC_COMBAT_INTENT_UNTIL = os.clock() + 0.8
	end
	local tid = target and target.id or 0
	local current_before = get_current_target()
	local current_dead = current_before and current_before.spawn_type == 16 and ((current_before.hpp or 0) <= 0)
	local switched_on_kill = false
	if setting_enabled(s.autotarget) and p.status == 1 and current_dead and tid > 0 and
		(not current_before or current_before.id ~= tid) then
		local ok_sw = uc_attack.switch_target(tid)
		if ok_sw then
			core.sticky_target_id = tid
			core.sticky_hold_until = 0
			switched_on_kill = true
		end
	end
	if tid > 0 and setting_enabled(s.autotarget) then
		if not switched_on_kill then
			local ok_target = ensure_target_and_attack(tid)
			if not ok_target then
				_G.UC_WS_LAST_DIAG = 'core ws reason=TARGET_PREP_FAIL'
			end
		end
	end
	local current = get_current_target()
	apply_facing(s, current)
	apply_movement(s, current)

	local player = windower.ffxi.get_player()
	uc_ability_pipeline.execute_ordered_abilities({
		settings = s,
		ability_active = setting_enabled(s.ability_active),
		can_cast_fn = can_cast_ja,
		cast_fn = cast_ja,
		job_abilities = res.job_abilities,
		player_buffs = player and player.buffs or {},
	})

	local t = get_current_target()
	if not t or not t.id or t.id == 0 then
		_G.UC_WS_LAST_DIAG = 'core ws reason=NO_CURRENT_TARGET'
		return
	end
	local ws_name, ws_pick_reason = select_smart_ws(s, t and t.id or 0)
	local dist = target_distance(t)
	local hpp = (t and t.hpp) or 0
	local tp = (p and p.vitals and p.vitals.tp) or 0
	local ws_busy = uc_ws_gate.busy_for_gate({
		is_casting = false,
	})
	local ok_ws, reason = uc_ws_gate.evaluate({
		ws_enabled = setting_enabled(s.weaponskill_active),
		tp = tp,
		dist = dist,
		hpp = hpp,
		busy = ws_busy,
		max_dist = 4,
		ws_name = ws_name,
	})
	_G.UC_WS_LAST_DIAG = ('core ws pick=%s tp=%d dist=%.2f hpp=%d ws=%s reason=%s'):format(
		ws_pick_reason,
		tp,
		dist,
		hpp,
		ws_name,
		reason)
	if ok_ws and t and t.id and t.id ~= 0 then
		windower.send_command('input /ws "' .. ws_name .. '" ' .. tostring(t.id))
	end
end

function core.register_adapter(name, adapter)
	if type(name) ~= 'string' or name == '' or type(adapter) ~= 'table' then
		return false
	end
	core.adapters[name] = adapter
	return true
end

function core.get_adapter(name)
	return core.adapters[name]
end

function core.combat_tick_once()
	core.last_engine = get_active_engine()
	run_unified_combat()
end

function core.assert_no_job_branch()
	return true
end

return core
