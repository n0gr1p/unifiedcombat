---@diagnostic disable: lowercase-global, undefined-field, undefined-global, deprecated, param-type-mismatch
require('chat')
require('logger')
require('tables')
require('luau')
require('pack')
require('actions')
local texts = require('texts')
local skills = require('skills')
local config = require('config')
local res = require('resources')
local packets = require('packets')
local socket = require("socket")
local uc_ws_memory = require('uc_ws_memory')
local uc_ignore = require('uc_ignore')
local uc_partner_list = require('uc_partner_list')
local uc_fight_leader = require('uc_fight_leader')
local uc_target_ignore = require('uc_target_ignore')
local uc_add_control = require('uc_add_control')

require('lor/lor_utils')
_libs.lor.include_addon_name = true
_libs.lor.req('all', { n = 'packets', v = '2016.10.27.0' })
_libs.req('queues')

return (function()

_static = S { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN',
	'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' }
-- Start_Engine is global (UnifiedCombat)

local isCasting = false
local isBusy = 0
local Action_Delay = 1
local targetset = false
local targetsetid = 0
local spaceon = false
local moved = false
local moving = false
local partyMembers = T {}
local WSForSkillchain = T {}
local wstimer = os.clock()
local wsinuse = false
local maneuver = 0
local mv = false
local lastmanuever = os.clock()
local lastmv = 0
local attacksent = false
local box = 0
local quick = 0
local feather = 0
local stutter = 0

local settings = setmetatable({}, {
    __index = function(_, k) return _G.UC_SETTINGS[k] end,
    __newindex = function(_, k, v) _G.UC_SETTINGS[k] = v end,
})
local skill_props = texts.new('', settings.display, settings)
local message_ids = S { 110, 185, 187, 317, 802 }
local skillchain_ids = S { 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 385, 386, 387, 388, 389,
	390, 391, 392, 393, 394, 395, 396, 397, 767, 768, 769, 770 }
local buff_dur = { [163] = 40, [164] = 30, [470] = 60 }
local info = {}
local resonating = {}
local buffs = {}
local debuffed_mobs = {}
local mkey = 0
local mid = 0
local primemid = 0
local mtarget = 0
local lasttarget = 0
local ws = 1
local combatflag = false
local hbstatus = false
local movement = false
local dd = _libs.lor.actor.Actor.new()
local actiontext = ''
local last_ws_precheck_log = 0
local last_ws_decision_log = 0

local next_frame = os.clock()
local firem = 0
local earthm = 0
local waterm = 0
local windm = 0
local icem = 0
local thunderm = 0
local lightm = 0
local darkm = 0

local function dd2_bool(v)
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function log_ws_precheck(prefix)
	if not settings.debug then
		return
	end
	local now = os.clock()
	if now - last_ws_precheck_log < 0.75 then
		return
	end
	last_ws_precheck_log = now
	local player = windower.ffxi.get_player()
	local tp = (player and player.vitals and player.vitals.tp) or 0
	local dist = GetRealDistanceById(targetsetid)
	local hpp = GetHppById(targetsetid)
	local ws_on = dd2_bool(settings.weaponskill_active)
	local ws_name = tostring(settings.weaponskill or settings.ws1 or '')
	local reason = 'READY'
	if not ws_on then
		reason = 'WS_OFF'
	elseif tp < 1000 then
		reason = 'TP_LT_1000'
	elseif dist >= 4 then
		reason = 'OUT_OF_RANGE'
	elseif hpp <= 0 then
		reason = 'TARGET_DEAD'
	elseif wsinuse then
		reason = 'WS_IN_USE'
	end
	debugmsg(11, ('%s ws_precheck tp=%d dist=%.2f hpp=%d ws_on=%s ws="%s" target=%d reason=%s'):format(
		prefix or 'dd2',
		tp,
		dist,
		hpp,
		tostring(ws_on),
		ws_name,
		targetsetid or 0,
		reason
	))
end

local function log_ws_decision(msg)
	if not settings.debug then
		return
	end
	local now = os.clock()
	if now - last_ws_decision_log < 0.5 then
		return
	end
	last_ws_decision_log = now
	debugmsg(11, msg)
end

local smartws = {
	[1] = function()
		if _G.UC_ENGINE ~= 'dd2' then
			log_ws_decision('dd2 smartws ignored (inactive engine)')
			return
		end
		uc_ws_memory.sync_settings(settings)
		local my_tp = GetTP()
		for index, value in ipairs(GetPartyTp()) do
			if not uc_ignore.has_id(_G.UC_SETTINGS, value.id) then
				local ally_ws_ready = (value.tp or 0) >= 1000
				local ally_far_ahead = (value.tp or 0) >= (my_tp + 300)
				if value.target == targetsetid and ally_ws_ready and ally_far_ahead and value.status == 1 and not dd2_bool(settings.solo) then
					log_ws_decision(('smartws wait ally id=%d tp=%d my_tp=%d'):format(value.id or 0, value.tp or 0, my_tp))
					return
				end
			end
		end
		local tempwslvl = 0
		local wstouse = ''
		if dd2_GetResonatingStep(targetsetid) == 0 then
			WSForSkillchain = T{}
		end
		for index, value in ipairs(WSForSkillchain) do
			if value.lvl >= tempwslvl then
				wstouse = value.ws
				tempwslvl = value.lvl
			end
		end
		if wstouse == '' or settings.closer then
			wstouse = settings.weaponskill or settings.ws1 or ''
		end
		if wstouse ~= '' and not uc_ws_memory.valid_ws_name(wstouse) then
			wstouse = uc_ws_memory.recall() or ''
		end
		if wstouse == '' then
			log_ws_decision('smartws block no ws selected')
			return
		end
		if GetTP() > 999 and dd2_bool(settings.weaponskill_active) then
			if  (os.clock() >= wstimer or dd2_GetResonatingStep(targetsetid) == 0) or (GetHppById(targetsetid) < 20 and settings.closer) then
				if settings.ability_active == true then
					for i, v in pairs(settings.wsabilities) do
						if Can_Cast_Ability(v) then
							Cast_Ability(v)
						end
					end
				end
				if wstouse ~= '' then
					log_ws_decision(('dd2 smartws send ws="%s" target=%d tp=%d'):format(wstouse, targetsetid or 0, GetTP()))
					uc_ws_memory.remember(wstouse)
					windower.send_command('input /ws "' .. wstouse .. '" ' .. tostring(targetsetid))
					actiontext = wstouse
				end
			else
				log_ws_decision(('smartws timer lock wstimer_left=%.2f reson=%d'):format(math.max(0, wstimer - os.clock()), dd2_GetResonatingStep(targetsetid)))
			end
		else
			log_ws_decision(('smartws gate fail tp=%d ws_on=%s'):format(GetTP(), tostring(dd2_bool(settings.weaponskill_active))))
		end
	end
}

function sleep(x)
	coroutine.sleep(x)
end

local function uc_dd2_incoming_chunk(id, data)
	if id == 0x028 then
		local action_message = packets.parse('incoming', data)
		if action_message['Category'] == 4 then
			isCasting = false
		elseif action_message['Category'] == 8 then
			isCasting = true
			if action_message['Target 1 Action 1 Message'] == 0 then
				isCasting = false
				isBusy = Action_Delay
			end
		end
	end
	-- skillchain

	if id == 0x29 and data:unpack('H', 25) == 206 and data:unpack('I', 9) == info.player then
		buffs[info.player][data:unpack('H', 13)] = nil
	elseif id == 0x50 and data:byte(6) == 0 then
		info.main_weapon = data:byte(5)
		info.main_bag = data:byte(7)
		update_weapon()
	elseif id == 0x50 and data:byte(6) == 2 then
		info.range = data:byte(5)
		info.range_bag = data:byte(7)
		update_weapon()
	elseif id == 0x63 and data:byte(5) == 9 then
		local set_buff = {}
		for n = 1, 32 do
			local buff = data:unpack('H', n * 2 + 7)
			if buff_dur[buff] or buff > 269 and buff < 273 then
				set_buff[buff] = true
			end
		end
		local pid = info.player
		if not pid then
			local p = windower.ffxi.get_player()
			pid = p and p.id
			if pid then
				info.player = pid
			end
		end
		if pid then
			buffs[pid] = set_buff
		end
	end
	if id == 0x028 then
		inc_action(windower.packets.parse_action(data))
	elseif id == 0x029 then
		local arr = {}
		arr.target_id = data:unpack('I', 0x09)
		arr.param_1 = data:unpack('I', 0x0D)
		arr.message_id = data:unpack('H', 0x19) % 32768

		inc_action_message(arr)
	end
end

function inc_action(act)
	if act.category ~= 4 then
		if act.category == 6 and act.param == 131 then
			handle_shot(act.targets[1].id)
		end
		return
	end

	-- Damaging spells
	if S { 2, 252 }:contains(act.targets[1].actions[1].message) then
		local target = act.targets[1].id
		local spell = act.param
		local effect = res.spells[spell].status
		local actor = act.actor_id

		if effect then
			apply_debuff(target, effect, spell, actor)
		end

		-- Non-damaging spells
	elseif S { 236, 237, 268, 271 }:contains(act.targets[1].actions[1].message) then
		local target = act.targets[1].id
		local effect = act.targets[1].actions[1].param
		local spell = act.param
		local actor = act.actor_id

		if res.spells[spell].status and res.spells[spell].status == effect then
			apply_debuff(target, effect, spell, actor)
		end
	end
end

function inc_action_message(arr)

	-- Unit died
	if S { 6, 20, 113, 406, 605, 646 }:contains(arr.message_id) then
		debuffed_mobs[arr.target_id] = nil

		-- Debuff expired
	elseif S { 64, 204, 206, 350, 531 }:contains(arr.message_id) then
		if debuffed_mobs[arr.target_id] then
			debuffed_mobs[arr.target_id][arr.param_1] = nil
		end
	end
end

function apply_debuff(target, effect, spell, actor)
	if not debuffed_mobs[target] then
		debuffed_mobs[target] = {}
	end

	-- Check overwrite conditions
	local overwrites = res.spells[spell].overwrites or {}
	if not handle_overwrites(target, spell, overwrites) then
		return
	end

	-- Create timer
	debuffed_mobs[target][effect] = { id = spell, timer = (os.clock() + (res.spells[spell].duration or 0)), actor = actor }
end

function handle_shot(target)
	if not debuffed_mobs[target] or not debuffed_mobs[target][134] then
		return true
	end

	local current = debuffed_mobs[target][134].id
	if current < 26 then
		debuffed_mobs[target][134].id = current + 1
	end
end

function handle_overwrites(target, new, t)
	if not debuffed_mobs[target] then
		return true
	end

	for effect, spell in pairs(debuffed_mobs[target]) do
		local old = res.spells[spell.id].overwrites or {}

		-- Check if there isn't a higher priority debuff active
		if table.length(old) > 0 then
			for _, v in ipairs(old) do
				if new == v then
					return false
				end
			end
		end

		-- Check if a lower priority debuff is being overwritten
		if table.length(t) > 0 then
			for _, v in ipairs(t) do
				if spell.id == v then
					debuffed_mobs[target][effect] = nil
				end
			end
		end
	end
	return true
end

function GetSteps()
	local steps = {[1]=381,[2]=382,[3]=383,[4]=384,[5]=385,[6]=588}
	for si, sv in ipairs(steps) do
		if table.contains(windower.ffxi.get_player().buffs,sv) then
			return si
		end
	end
	return 0
end

wsready = 'no'
renderskip = 5

function GetNameById(id)
	local test, name = pcall(function() return windower.ffxi.get_mob_by_id(id).name end)
	if test then
		return name
	else
		return 'None'
	end
end

function EasyLife(bla, bla2)
	local onformat = '\\cs(0,255,0)%s\\cr'
	local offformat = '\\cs(255,0,0)%s\\cr'
	if bla2 == nil then
		bla2 = 'X'
	end
	return (bla and string.format(onformat, bla2) or string.format(offformat, bla2))	
end

function EasyLife2(bla)
	local on = '\\cs(0,255,0)O\\cr'
	local off = '\\cs(255,0,0)X\\cr'
	return (bla and on or off)
end

local display_box = function()
	local dd2status = 'DD2 status: [ '..EasyLife2(Start_Engine)..' ]'
	local autotarget = '\nAutotarget: [ '..EasyLife2(settings.autotarget)..' ]'
	local manual = '\nManual: [ '..EasyLife2(settings.manual)..' ]'
	local wepskill = '\nWeaponskill: [ '..EasyLife(settings.weaponskill_active, settings.weaponskill)..' ]'
	local ability = '\nAbilities: [ '..EasyLife2(settings.ability_active)..' ]'
	local sleep = '\nSleep: [ '..EasyLife2(settings.sleep)..' ]'
	local facing = '\nFacing: [ '..EasyLife2(settings.face)..' ]'
	local closer = '\nCloser: [ '..EasyLife2(settings.closer)..' ]'
	local prime = '\nPrime: [ '..EasyLife2(settings.prime)..' ]'
	local static = '\nStatic: [ '..EasyLife2(settings.static)..' ]'
	local spacing = '\nSpacing: [ '..EasyLife2(settings.spacing)..' ]'
	local pnames = {}
	for _, pid in ipairs(uc_partner_list.as_ordered_ids(settings)) do
		pnames[#pnames + 1] = GetNameById(pid)
	end
	local psum = #pnames > 0 and table.concat(pnames, ', ') or 'none'
	local partner = '\nPartners: [ '..EasyLife(settings.partner, psum)..' ]'
	local puller = '\nPuller: [ '..EasyLife(settings.puller, GetNameById(settings.puller_id))..' ]'
	local fight_leader_ln = '\nFight leader: [ '..EasyLife(settings.fight_leader, GetNameById(settings.fight_leader_id))..' ]'
	local add_ctrl = '\nAdd control: [ '..EasyLife2(settings.add_control)..' ]'
	local ignore = '\nWS wait ignore: '
	local str = ''
	local ig = settings.ignore
	if type(ig) == 'table' then
		for _, id in pairs(ig) do
			if type(id) == 'number' and id ~= 0 then
				str = str .. '\n- ' .. tostring(GetNameById(id))
			end
		end
	end
	local tign = '\nTarget ignore (by name): '
	local tistr = ''
	for _, nm in ipairs(uc_target_ignore.as_ordered_names(settings)) do
		tistr = tistr .. '\n- ' .. tostring(nm)
	end
	if tistr == '' then
		tistr = '\n- (none)'
	end
	return dd2status .. autotarget .. wepskill .. ability .. manual .. prime.. sleep .. facing .. closer .. static .. spacing .. partner .. puller .. fight_leader_ln .. add_ctrl .. ignore .. str .. tign .. tistr
	
end 

local dd2_status = texts.new(display_box(), settings.default_text_settings)
local _uc_last_ui_w = 0
local _uc_last_ui_h = 0

local function uc_ingame_ui_enabled()
	return settings.show_ingame_ui ~= false
end

local function uc_get_ui_resolution()
	local ws = windower.get_windower_settings and windower.get_windower_settings() or nil
	if not ws then
		return nil, nil
	end
	local w = tonumber(ws.ui_x_res or ws.x_res or ws.window_x_res)
	local h = tonumber(ws.ui_y_res or ws.y_res or ws.window_y_res)
	return w, h
end

local function uc_clamp_text_pos(pos_tbl, max_w, max_h, pad_x, pad_y)
	if type(pos_tbl) ~= 'table' then
		return false
	end
	local x = tonumber(pos_tbl.x)
	local y = tonumber(pos_tbl.y)
	if not x or not y then
		return false
	end
	local nx = math.max(0, math.min(x, math.max(0, max_w - pad_x)))
	local ny = math.max(0, math.min(y, math.max(0, max_h - pad_y)))
	if nx ~= x or ny ~= y then
		pos_tbl.x = nx
		pos_tbl.y = ny
		return true
	end
	return false
end

local function uc_keep_ui_visible()
	local w, h = uc_get_ui_resolution()
	if not w or not h or w <= 0 or h <= 0 then
		return
	end
	if _uc_last_ui_w == w and _uc_last_ui_h == h then
		return
	end
	_uc_last_ui_w = w
	_uc_last_ui_h = h
	-- Keep a generous inset so text boxes remain easy to click-drag after downsizing resolution.
	local c1 = uc_clamp_text_pos(settings.default_text_settings and settings.default_text_settings.pos, w, h, 520, 180)
	local c2 = uc_clamp_text_pos(settings.display and settings.display.pos, w, h, 420, 180)
	if c1 and dd2_status then
		pcall(function() dd2_status:pos(settings.default_text_settings.pos.x, settings.default_text_settings.pos.y) end)
	end
	if c2 and skill_props then
		pcall(function() skill_props:pos(settings.display.pos.x, settings.display.pos.y) end)
	end
	-- Intentionally do not auto-save here; multiple clients can reload simultaneously.
	-- Persist through explicit Save (XML) from the external UI or addon command.
end

local function uc_dd2_outgoing_chunk(id, data)
	if id == 0x015 then
		local action_message = packets.parse('outgoing', data)
		PlayerH = action_message['Rotation']
	end
end

local function uc_dd2_addon_command(...)
	local commands = T { ... }
	local args = T { ... }:map(string.lower)
	if args[1] == nil or args[1] == "help" then
		print("Help Info")
	elseif args[1] == "start" then
		if (not Start_Engine) then
			windower.add_to_chat(2, "....Starting DD Helper....")
			Start_Engine = true
			uc_dd2_start_engine()
		else
			windower.add_to_chat(2, "....DD Helper already running....")
		end
	elseif args[1] == "stop" then
		windower.add_to_chat(2, "....Stopping DD Helper....")
		Start_Engine = false
	elseif args[1] == "reload" then
		windower.add_to_chat(2, "....Reloading Config....")
		if type(_G.UC_ReloadActiveProfile) == 'function' then
			_G.UC_ReloadActiveProfile()
		elseif _G.UC_SETTINGS then
			config.reload(_G.UC_SETTINGS)
		end
	elseif args[1] == "save" then
		if type(_G.UC_SaveActiveProfile) == 'function' then
			_G.UC_SaveActiveProfile()
		elseif _G.UC_SETTINGS then
			config.save(_G.UC_SETTINGS, windower.ffxi.get_player().name)
		end
	elseif args[1] == "test" then
		test()
	elseif args[1] == "show" then
		windower.add_to_chat(11, "Autotarget: " .. tostring(settings.autotarget))
		windower.add_to_chat(11, "Spell slots: " .. tostring(type(settings.dd2_spell_slots) == 'table' and '(dd2 table)' or settings.dd2_spell_slots))
		windower.add_to_chat(11, "Use Spell " .. tostring(settings.spell_active))
		windower.add_to_chat(11, "Use Weaponskill: " .. tostring(settings.weaponskill_active))
		for i, v in ipairs(settings.targets) do
			windower.add_to_chat(11, "Target:" .. v)
		end
	elseif args[1] == "autotarget" then
		if args[2] == "on" then
			settings.autotarget = true
			windower.add_to_chat(3, "Autotarget: True")
		else
			settings.autotarget = false
			windower.add_to_chat(3, "Autotarget: False")
		end
	elseif args[1] == "hunter" then
		if args[2] == "on" then
			settings.hunter = true
			windower.add_to_chat(3, "Autotarget: True")
		else
			settings.hunter = false
			windower.add_to_chat(3, "Autotarget: False")
		end
	elseif args[1] == "target1" then
		settings.target1 = args[2]
	elseif args[1] == "target2" then
		settings.target2 = args[2]
	elseif args[1] == "target3" then
		settings.target3 = args[2]
	elseif args[1] == "move" then
		if args[2] == "on" then
			settings.move = true
			windower.add_to_chat(3, "AutoMove: True")
		else
			settings.move = false
			windower.add_to_chat(3, "AutoMove: False")
		end
	elseif args[1] == "debug" then
		if args[2] == "on" then
			settings.debug = true
			windower.add_to_chat(3, "Debug: True")
		else
			settings.debug = false
			windower.add_to_chat(3, "Debug: False")
		end
	elseif args[1] == "manual" then
		if args[2] == "on" then
			settings.manual = true
			windower.add_to_chat(3, "manual: True")
		else
			settings.manual = false
			windower.add_to_chat(3, "manual: False")
		end
	elseif args[1] == "ws" then
		if args[2] == "on" then
			settings.weaponskill_active = true
			windower.add_to_chat(3, "weaponskill: True")
		elseif args[2] == "off" then
			settings.weaponskill_active = false
			windower.add_to_chat(3, "weaponskill: False")
		else
			if res.weapon_skills:with('en', commands[2]) then
				local newws = res.weapon_skills:with('en', commands[2])
				windower.add_to_chat(3, 'found ws in res:' .. newws.en)
				if S(windower.ffxi.get_abilities().weapon_skills):contains(newws.id) then
					settings.weaponskill = commands[2]
				else
					windower.add_to_chat(3, 'invalid WS: ' .. commands[2])
				end
			else
				windower.add_to_chat(3, 'invalid WS: ' .. commands[2])
			end
		end
	elseif args[1] == "ability" then
		if args[2] == "on" then
			settings.ability_active = true
			windower.add_to_chat(3, "ability: True")
		else
			settings.ability_active = false
			windower.add_to_chat(3, "ability: False")
		end
	elseif args[1] == "face" then
		if args[2] == "on" then
			settings.face = true
			windower.add_to_chat(3, "face: True")
		else
			settings.face = false
			windower.add_to_chat(3, "face: False")
		end
	elseif args[1] == "tank" then
		if args[2] == "on" then
			settings.tank = true
			windower.add_to_chat(3, "tank: True")
		else
			settings.tank = false
			windower.add_to_chat(3, "tank: False")
		end
	elseif args[1] == "closer" then
		if args[2] == "on" then
			settings.closer = true
			windower.add_to_chat(3, "closer: True")
		else
			settings.closer = false
			windower.add_to_chat(3, "closer: False")
		end
	elseif args[1] == "prime" then
		if args[2] == "on" then
			settings.prime = true
			windower.add_to_chat(3, "prime: True")
		else
			settings.prime = false
			windower.add_to_chat(3, "prime: False")
		end
	elseif args[1] == "static" then
		if args[2] == "on" then
			settings.static = true
			windower.add_to_chat(3, "static: True")
		else
			settings.static = false
			windower.add_to_chat(3, "static: False")
		end
	elseif args[1] == "command" then
		if args[2] == "on" then
			settings.command = true
			windower.add_to_chat(3, "command: True")
		else
			settings.command = false
			windower.add_to_chat(3, "command: False")
		end
	elseif args[1] == "spacing" then
		if args[2] == "on" then
			settings.spacing = true
			windower.add_to_chat(3, "spacing: True")
		else
			settings.spacing = false
			windower.add_to_chat(3, "spacing: False")
		end
	elseif args[1] == "style" then
		if args[2] == "ranger" then
			firem = 2
			earthm = 0
			waterm = 0
			windm = 1
			icem = 0
			thunderm = 0
			lightm = 0
			darkm = 0
			windower.add_to_chat(3, "style: Ranger")
		elseif args[2] == "tank" then
			firem = 1
			earthm = 0
			waterm = 0
			windm = 1
			icem = 0
			thunderm = 0
			lightm = 1
			darkm = 0
			windower.add_to_chat(3, "style: Tank")
		elseif args[2] == "redmage" then
			firem = 0
			earthm = 0
			waterm = 0
			windm = 0
			icem = 1
			thunderm = 0
			lightm = 1
			darkm = 1
			windower.add_to_chat(3, "style: Red Mage")
		elseif args[2] == "blackmage" then
			firem = 0
			earthm = 0
			waterm = 0
			windm = 0
			icem = 1
			thunderm = 0
			lightm = 1
			darkm = 1
			windower.add_to_chat(3, "style: Black Mage")
		elseif args[2] == "boomy" then
			firem = 0
			earthm = 0
			waterm = 0
			windm = 0
			icem = 2
			thunderm = 0
			lightm = 0
			darkm = 1
			windower.add_to_chat(3, "style: BOOM!")
		elseif args[2] == "whitemage" then
			firem = 0
			earthm = 0
			waterm = 0
			windm = 0
			icem = 0
			thunderm = 0
			lightm = 2
			darkm = 1
			windower.add_to_chat(3, "style: White Mage")
		elseif args[2] == "wtf" then
			firem = 0
			earthm = 0
			waterm = 0
			windm = 1
			icem = 0
			thunderm = 1
			lightm = 1
			darkm = 0
			windower.add_to_chat(3, "style: lol")
		elseif args[2] == "ballista" then
			firem = 2
			earthm = 0
			waterm = 0
			windm = 1
			icem = 0
			thunderm = 0
			lightm = 0
			darkm = 0
			windower.add_to_chat(3, "style: BOOM!")
		elseif args[2] == "brr" then
			firem = 0
			earthm = 0
			waterm = 0
			windm = 3
			icem = 0
			thunderm = 0
			lightm = 0
			darkm = 0
			windower.add_to_chat(3, "style: brrrrrrt!")
		end
	elseif args[1] == 'partner' then
		if args[2] == 'on' then
			settings.partner = true
			windower.add_to_chat(3, 'Partner: True')
		elseif args[2] == 'off' then
			settings.partner = false
			windower.add_to_chat(3, 'Partner: False')
		elseif args[2] == 'clear' then
			settings.partner_ids = {}
			uc_partner_list.sync_legacy_partner_fields(settings)
			windower.add_to_chat(3, 'Partner list cleared')
		else
			local nm = commands[2] and tostring(commands[2]) or ''
			if nm ~= '' then
				local tid = GetTargetIDByName(nm)
				if tid then
					local ok, why = uc_partner_list.append_id(settings, tid)
					if ok and why == 'PARTNER_ALREADY' then
						windower.add_to_chat(3, 'Partner: already listed: ' .. nm)
					elseif ok then
						windower.add_to_chat(3, 'Partner added: ' .. nm)
					end
				else
					windower.add_to_chat(3, 'Partner: no mob named: ' .. nm)
				end
			end
		end
	elseif args[1] == 'partner_remove' and commands[2] then
		local tid = tonumber(commands[2]) or GetTargetIDByName(commands[2])
		if tid and tid ~= 0 then
			local ok, why = uc_partner_list.remove_id(settings, tid)
			if ok then
				windower.add_to_chat(3, 'Partner removed id ' .. tostring(tid))
			else
				windower.add_to_chat(3, 'Partner remove: ' .. tostring(why))
			end
		end
	elseif args[1] == 'puller' then
		if args[2] == 'on' then
			settings.puller = true
			windower.add_to_chat(3, 'Puller: True')
		elseif args[2] == 'off' then
			settings.puller = false
			windower.add_to_chat(3, 'Puller: False')
		else
			if GetTargetIDByName(commands[2]) then
				settings.puller_id = GetTargetIDByName(commands[2])
				windower.add_to_chat(3, 'Puller set: ' .. commands[2])
			end
		end
	elseif args[1] == 'ignore' then
		if args[2] then
			local tid = GetTargetIDByName(commands[2])
			if tid then
				local ok, why = uc_ignore.append_id(_G.UC_SETTINGS, tid)
				if ok and why ~= 'IGNORE_ALREADY' then
					windower.add_to_chat(3, 'ignoring set: ' .. commands[2])
				elseif why == 'IGNORE_ALREADY' then
					windower.add_to_chat(3, 'ignore: already listed: ' .. commands[2])
				end
			else
				windower.add_to_chat(3, 'ignore: no mob named: ' .. tostring(commands[2]))
			end
		end
	elseif args[1] == 'sleep' then
		if args[2] == 'on' then
			settings.sleep = true
			windower.add_to_chat(3, 'Sleep: True')
		elseif args[2] == 'off' then
			settings.sleep = false
			windower.add_to_chat(3, 'Sleep: False')
		else
			local spells = res.spells
			local sleepspell = commands[2]
			if table.with(spells, 'en', sleepspell) then
				settings.sleepspell = sleepspell
				windower.add_to_chat(3, 'Sleep spell: ' .. settings.sleepspell)
			end
		end
	end
end

function HeadingTo(X, Y)
	local x = X - GetMobById(windower.ffxi.get_player().id).x
	local y = Y - GetMobById(windower.ffxi.get_player().id).y
	local H = math.atan2(x, y)
	return H - 1.5708
end

function GetMobById(id)
	local test, mob = pcall(function() return windower.ffxi.get_mob_by_id(id) end)
	if test then
		return mob
	else
		return nil
	end
end

function GetDistanceBetween(a, b)
	local moba = GetMobById(a)
	local mobb = GetMobById(b)
	if moba and mobb then
		local size = moba.model_size
		x = math.abs(moba.x - mobb.x)
		y = math.abs(moba.y - mobb.y)
		local dist = math.sqrt((x * x) + (y * y))
		return dist - size
	else
		return 100
	end
end

function GetDistToPuller()
	local pullerid = settings.puller_id or 0
	if pullerid == 0 or not settings.puller then
		return 0
	else
		return GetDistanceBetween(targetsetid, pullerid)
	end
end

local function uc_dd2_puller_allows_spacing_move()
	if not settings.puller or (settings.puller_id or 0) == 0 then
		return true
	end
	local near = GetDistToPuller() <= 6
	if settings.puller_distance_only then
		return near
	end
	return near or (GetHppById(targetsetid) < 99)
end

function GetTargetIDByName(name)
	--windower.add_to_chat(3,'Looking up name: '..name)
	local test, id = pcall(function() return windower.ffxi.get_mob_by_name(name).id end)
	if test then
		--windower.add_to_chat(3,'success')
		return id
	else
		--windower.add_to_chat(3,'failure')
		return nil
	end
end

function GetMobByTarget()
	return windower.ffxi.get_mob_by_target('t')
end

function GetMobIdByIndex(index)
	local test, mobid = pcall(function()
		return windower.ffxi.get_mob_by_index(index).id
	end)
	if test then
		return mobid
	else
		return 0
	end
end

function GetPartyTp()
	local party = windower.ffxi.get_party()
	local keys = { "p1", "p2", "p3", "p4", "p5" }
	local temptps = {}
	for k, v in ipairs(keys) do
		local mob = TestParty(party[v])
		if mob ~= nil then
			table.insert(temptps,
				{ id = mob.id, target = GetMobIdByIndex(mob.target_index), tp = party[v].tp, status = mob.status })
		end
	end
	return temptps
end

function TurnToTarget()
	if PlayerH ~= nil and settings.face then
		if windower.ffxi.get_player().status == 1 then
			local testx, destX = pcall(function() return GetMobByTarget().x end)
			local testy, destY = pcall(function() return GetMobByTarget().y end)
			if testx and testy then
				local direction = math.abs(PlayerH - math.deg(HeadingTo(destX, destY)))
				if direction > 10 then
					windower.ffxi.turn(HeadingTo(destX, destY))
				end
			end
		elseif (mid or 0) > 0 and windower.ffxi.get_player().status ~= 2 and windower.ffxi.get_player().status ~= 3 then
			if GetMobById(mid) then
				local destX = GetMobById(mid).x
				local destY = GetMobById(mid).y
				local direction = math.abs(PlayerH - math.deg(HeadingTo(destX, destY)))
				if direction > 10 then
					windower.ffxi.turn(HeadingTo(destX, destY))
				end
			end
		end
	end
end

function has_value(tab, val)
	for index, value in ipairs(tab) do
		if value == val then
			return true
		end
	end

	return false
end

function has_value_string(tab, val)
	for index, value in ipairs(tab) do
		if string.lower(value) == string.lower(val) then
			return true
		end
	end
	return false
end

function TestParty(value)
	local test, mob = pcall(function() return value.mob end)
	if test then
		return mob
	else
		return nil
	end
end

function getClaims()
	local party = windower.ffxi.get_party()
	local keys = { "p0", "p1", "p2", "p3", "p4", "p5" }
	local tempclaims = {}
	for k, v in pairs(keys) do
		local mob = TestParty(party[v])
		if mob ~= nil then
			table.insert(tempclaims, mob.id)
		end
	end
	return tempclaims
end

function StoreParty()
	partyMembers = T {}
	local party = windower.ffxi.get_party()
	local keys = { "p1", "p2", "p3", "p4", "p5" }
	for k, v in pairs(keys) do
		local mob = TestParty(party[v])
		if mob ~= nil then
			table.insert(partyMembers, mob)
		end
	end
	return tempclaims
end

function GetPartnerTargetIdFromPartnerMobId(partner_mob_id)
	if not partner_mob_id or partner_mob_id == 0 then
		return 0
	end
	local test, partindex = pcall(function() return GetMobById(partner_mob_id).target_index end)
	if test then
		local test2, partid = pcall(function() return windower.ffxi.get_mob_by_index(partindex).id end)
		if test2 then
			return partid
		else
			return 0
		end
	else
		return 0
	end
end

function GetPartnerTargetId()
	return GetPartnerTargetIdFromPartnerMobId(settings.partner_id)
end

--- Living monster the engine uses for combat (matches Find_Nearest_Target / autotarget).
local function uc_dd2_is_monster_combat_target_id(id)
	if not id or id == 0 then
		return false
	end
	local m = GetMobById(id)
	if not m then
		return false
	end
	if m.spawn_type ~= 16 then
		return false
	end
	local hpp = m.hpp
	if hpp == nil or hpp <= 0 then
		return false
	end
	return true
end

--- Keep client target on `mid` when engine picked a mob (e.g. cursor still on a PC buffer).
local function dd2_CheckTarget()
	if settings.manual then
		return
	end
	if mid <= 0 or not uc_dd2_is_monster_combat_target_id(mid) then
		return
	end
	local t = GetMobByTarget()
	local cur = (t and t.id) or 0
	if cur ~= mid then
		windower.send_command('st ' .. tostring(mid))
	end
end

local function uc_dd2_mob_is_any_partner_target(mob_id)
	if not settings.partner then
		return false
	end
	for _, pid in ipairs(uc_partner_list.as_ordered_ids(settings)) do
		local pt = GetPartnerTargetIdFromPartnerMobId(pid)
		if pt > 0 and mob_id == pt then
			return true
		end
	end
	return false
end

local sleepid
function Find_Nearest_Target()
	local claims = getClaims()
	local id_targ = -1
	local dist_targ = -1
	local id_sleep = -1
	local sleep_targ = -1
	local hpp_targ = -1
	local marray = windower.ffxi.get_mob_array()
	local tempmkey = -1
	local idalt_targ = -1
	local distalt_targ = -1
	for key, mob in pairs(marray) do
		if (has_value(claims, mob['claim_id']) or settings.hunter) and
			(not settings.partner or not uc_dd2_mob_is_any_partner_target(mob['id'])) and mob['valid_target'] and
			not uc_target_ignore.is_mob_blocked(settings, mob) then
			if not settings.tank then
				if mob['spawn_type'] == 16 and mob['hpp'] > 0 then
					if dist_targ == -1 then
						id_targ = mob['id']
						dist_targ = mob['distance']
						tempmkey = key
					elseif mob['distance'] < dist_targ then
						id_targ = mob['id']
						dist_targ = mob['distance']
						tempmkey = key
					end
				end
			else
				if mob['spawn_type'] == 16 and mob['hpp'] > 0 then
					if hpp_targ == -1 then
						id_targ = mob['id']
						hpp_targ = mob['hpp']
						tempmkey = key
					elseif mob['hpp'] > hpp_targ then
						id_targ = mob['id']
						hpp_targ = mob['hpp']
						tempmkey = key
					end
				end
			end
		end
		if settings.sleep then
			if mob['spawn_type'] == 16 and mob['status'] == 1 and mob['valid_target'] and
				not uc_target_ignore.is_mob_blocked(settings, mob) then
				local data = debuffed_mobs[mob['id']]
				local sleepcast = true
				local sleepdist = mob['distance']
				if sleepdist:sqrt() <= 6 then
					if data then
						--windower.add_to_chat(3,"has data: "..mob['name'])
						for effect, spell in pairs(data) do
							--windower.add_to_chat(3,"spell: "..res.spells[spell.id].name)
							local name = res.spells[spell.id].name
							if name == 'Horde Lullaby II' then
								sleepcast = false
							end
						end
					end
					if mob['hpp'] > 99 and sleepcast then
						local sdata = debuffed_mobs[sleepid]
						local sleepcast = true
						if sdata then
							for seffect, sspell in pairs(sdata) do
								local name = res.spells[sspell.id].name
								if name == 'Horde Lullaby II' then
									sleepcast = false
								end
							end
						end
						if sleepcast then
							if sleep_targ == -1 then
								id_sleep = mob['id']
								sleep_targ = mob['distance']
							elseif mob['distance'] < sleep_targ then
								id_sleep = mob['id']
								sleep_targ = mob['distance']
							end
						end
					end
				end
			end
		end
		if settings.prime and id_targ == -1 then
			if mob['claim_id'] == 0 and mob['spawn_type'] == 16 and mob['status'] == 1 and mob['valid_target'] and
				not uc_target_ignore.is_mob_blocked(settings, mob) then
				local tempd = mob['distance']
				if tempd:sqrt() < 8 then
					if mob['valid_target'] and mob['hpp'] > 0 then
						if distalt_targ == -1 then
							idalt_targ = mob['id']
							distalt_targ = mob['distance']
						elseif mob['distance'] < distalt_targ then
							idalt_targ = mob['id']
							distalt_targ = mob['distance']
						end
					end
				end
			end
		end
	end
	local leader_mid = uc_fight_leader.resolve_mid_override(settings, true, function(tid)
		return settings.partner and uc_dd2_mob_is_any_partner_target(tid)
	end)
	local add_mid = uc_add_control.pick(settings, claims, marray, leader_mid, {
		hunter_in_claim = true,
		melee_style = false,
		partner_block = function(mob)
			return settings.partner and uc_dd2_mob_is_any_partner_target(mob['id'])
		end,
	})
	if add_mid > 0 then
		mid = add_mid
		primemid = 0
	elseif leader_mid > 0 then
		mid = leader_mid
		primemid = 0
	else
		mid = id_targ
		if mid > 0 then
			primemid = 0
		else
			primemid = idalt_targ
		end
	end
	if dd2_bool(settings.debug) and uc_add_control.enabled(settings) then
		uc_add_control.log_line(settings,
			('FnT add_pick=%s leader_mid=%s id_targ=%s idalt=%s -> mid=%s primemid=%s'):format(
				tostring(add_mid), tostring(leader_mid), tostring(id_targ), tostring(idalt_targ), tostring(mid), tostring(primemid)))
	end
	sleepid = id_sleep
	if sleepid > 0 and hbstatus == false then
		windower.add_to_chat(3, 'Sleep Target')
		windower.send_command('hb off')
		hbstatus = true
	elseif sleepid < 0 and hbstatus == true then
		windower.add_to_chat(3, 'No Sleep')
		windower.send_command('hb on')
		hbstatus = false
	end
end

function Check_Distance()
	local distance = GetDistance()
	if distance >= 3 then
		TurnToTarget()
		windower.ffxi.run(true)
	else
		TurnToTarget()
		windower.ffxi.run(false)
	end
end

function Check_Distance_Num(a)
	local distance = GetDistance()
	if distance > 1 then
		if distance > a then
			TurnToTarget()
			windower.ffxi.run(true)
		else
			TurnToTarget()
			windower.ffxi.run(false)
		end
	end
end

function debugmsg(i, vs)
	if settings.debug == true then
		windower.add_to_chat(i, vs)
	end
end

local function dd2_combat_tick_once()
	if _G.UC_ENGINE ~= 'dd2' then
		return
	end
	if isBusy < 1 then
		local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
		if type(zu) ~= 'number' or os.clock() >= zu then
			dd2_Combat()
		end
	else
		isBusy = isBusy - 1
	end
end

local function dd2_engine_tick()
	if _G.UC_USE_UNIFIED_ENGINE then
		return
	end
	dd2_combat_tick_once()
	if Start_Engine and _G.UC_ENGINE == 'dd2' then
		coroutine.schedule(dd2_engine_tick, 0.5)
	end
end

function uc_dd2_start_engine()
	if type(_G.UC_StartUnifiedEngine) == 'function' then
		_G.UC_StartUnifiedEngine()
		return
	end
	if _G.UC_ENGINE == 'dd2' then
		dd2_engine_tick()
	end
end

function Engine()
	if type(_G.UC_StartUnifiedEngine) == 'function' then
		_G.UC_StartUnifiedEngine()
		return
	end
	dd2_engine_tick()
end

function GetDistanceById(targetid)
	local test, value = pcall(function()
		return GetMobById(targetid).distance:sqrt()
	end)
	if test then
		return value
	else
		return 0
	end
end

function GetDistance()
	local testa, playersize = pcall(function() return windower.ffxi.get_mob_by_target('me').model_size end)
	local testb, mobsize = pcall(function() return GetMobById(targetsetid).model_size end)
	local testc, value = pcall(function() return GetMobById(targetsetid).distance:sqrt() end)
	if testa and testb and testc then
		local real_dist = value - mobsize - playersize
		return real_dist
	else
		return 0
	end
end

function GetRealDistanceById(id)
	local testa, playersize = pcall(function() return windower.ffxi.get_mob_by_target('me').model_size end)
	local testb, mobsize = pcall(function() return GetMobById(id).model_size end)
	local testc, value = pcall(function() return GetMobById(id).distance:sqrt() end)
	if testa and testb and testc then
		local real_dist = value - mobsize - playersize
		return real_dist
	else
		return 0
	end
end

function GetTargetId()
	local test, id = pcall(function() return GetMobByTarget().id end)
	if test == true then
		return id
	else
		return 0
	end
end

function GetTargetClaimId()
	local test, id = pcall(function() return GetMobByTarget().claim_id end)
	if test == true then
		return id
	else
		return 0
	end
end

function GetClaimIdById(id)
	local test, id = pcall(function() return GetMobById(id).claim_id end)
	if test == true then
		return id
	else
		return 0
	end
end

function GetTP()
	return windower.ffxi.get_player().vitals.tp
end

function GetHppById(targetid)
	local test, value = pcall(function() return GetMobById(targetid).hpp end)
	if test then
		return value
	else
		return 0
	end
end
function GetTargetName()
	local test, value = pcall(function() return windower.ffxi.get_mob_by_target('t').name end)
	if test then
		return value
	else
		return ""
	end
end

function dd2_GetResonatingStep(tid)
	local reson = resonating[tid]
	local timer = reson and (reson.times - os.clock()) or 0
	if reson then
		if not reson.closed and timer > 0 then
			return reson.step
		else
			return 0
		end
	else
		return 0
	end
end

function GetResonatingDelay(tid)
	local test, value = pcall(function() return resonating[tid].delay end)
	if test then
		return value
	else
		return 100;
	end
end

function GetResonatingTimes(tid)
	local test, value = pcall(function() return resonating[tid].times end)
	if test then
		return value
	else
		return 0;
	end
end

function GetMyPetName()
	local test, petname = pcall(function() return windower.ffxi.get_mob_by_target('pet').name end)
	if test then
		return petname
	else
		return "none"
	end
end

function GetMyPetStatus()
	local test, petstatus = pcall(function() return windower.ffxi.get_mob_by_target('pet').status end)
	if test then
		return petstatus
	else
		return -1
	end
end

function GetMyPetHPP()
	local test, petstatus = pcall(function() return windower.ffxi.get_mob_by_target('pet').hpp end)
	if test then
		return petstatus
	else
		return 0
	end
end

function IsTargetNpc()
	local test, npc = pcall(function() return windower.ffxi.get_mob_by_target('t').is_npc end)
	if test then
		return npc
	else
		return false
	end
end

local function ToInteger(number)
	return math.floor(tonumber(number) or error("Could not cast '" .. tostring(number) .. "' to number.'"))
end

function BS()
	local player = windower.ffxi.get_player()

	if player.status == 1 and not settings.static then
		if movement == false then
			--windower.add_to_chat(3, 'follow off')
			windower.send_command('hb follow off')
			windower.ffxi.run(false)
			movement = true
			sleep(0.5)
		end
	elseif player.status ~= 1 and not settings.static then
		if movement == true then
			--windower.add_to_chat(3, 'follow on')
			windower.send_command('hb follow resume')
			movement = false
		end
	end
end

function MoveIntoRange()
	if not settings.static and not settings.manual then
		moving = true
		if (GetMobById(targetsetid)) then
			if uc_dd2_puller_allows_spacing_move() then
				if (GetMobById(targetsetid).spawn_type == 16) then
					local tempdist = GetDistance()
					local range = 0.25
					local mindist = -0.75
					while (mindist > tempdist or tempdist > range) and GetHppById(GetTargetId()) > 0 do
						if tempdist > range then
							while tempdist > range and GetHppById(GetTargetId()) > 0 do
								dd:move_towards(GetTargetId())
								TurnToTarget()
								sleep(0.05)
								tempdist = GetDistance()
							end
							windower.ffxi.run(false)
							moved = true
							actiontext = 'Moved Toward'
						end
						if tempdist < mindist then
							while tempdist < mindist and GetHppById(GetTargetId()) > 0 do
								dd:move_away_from(GetTargetId())
								TurnToTarget()
								sleep(0.05)
								tempdist = GetDistance()
							end
							windower.ffxi.run(false)
							moved = true
							actiontext = 'Moved Away'
						end
					end
				end
			end
		end
		moving = false
	end
end

function Spacing(loractor)
	if targetsetid > 0 and windower.ffxi.get_player().status == 1 then
		spaceon = true
		for index, value in ipairs(partyMembers) do
			local tempdist = GetRealDistanceById(value.id)
			local mindist = -0.1
			if tempdist < mindist then
				while tempdist < mindist do
					loractor:move_away_from(value.id)
					sleep(0.1)
					tempdist = GetRealDistanceById(value.id)
				end
				windower.ffxi.run(false)
			end
			sleep(0.1)
		end
		spaceon = false
	end

end

lasttargetid = 0
function dd2_Combat()
	Find_Nearest_Target()

	if settings.sleep and Can_Cast_Spell_Target(settings.sleepspell, sleepid) and GetHppById(sleepid) > 0 then
		Cast_Spell_Target(settings.sleepspell, sleepid)
	end

	-- is Engaged / combat
	if windower.ffxi.get_player().status == 1 then
		if GetHppById(targetsetid) == 0 then
			targetsetid = GetTargetId()
		end
		if targetsetid == 0 then
			targetsetid = GetTargetId()
		end
		-- Do not treat PCs / invalid targets as the combat mob (e.g. buff target between fights).
		if targetsetid ~= 0 and not uc_dd2_is_monster_combat_target_id(targetsetid) then
			targetsetid = 0
		end
		local cur_tid = GetTargetId()
		if cur_tid ~= targetsetid then
			if uc_dd2_is_monster_combat_target_id(targetsetid) and not uc_dd2_is_monster_combat_target_id(cur_tid) then
				if not settings.manual then
					windower.send_command('st ' .. tostring(targetsetid))
				end
			else
				windower.send_command('input /attack off')
			end
		end
		if string.lower(windower.ffxi.get_player().main_job) == 'run' then
			if windower.ffxi.get_ability_recasts()[5] == 0 then
				Cast_Ability('Provoke')
				return
			end
			if Can_Cast_Ability('Odyllic Subterfuge') then
				Cast_Ability('Odyllic Subterfuge')
				return
			end
			if Can_Cast_Ability('Pflug') then
				Cast_Ability('Pflug')
				return
			end
			if Can_Cast_Ability('Valiance') then
				Cast_Ability('Valiance')
				return
			end
			if Can_Cast_Ability('Battuta') then
				Cast_Ability('Battuta')
				return
			end
			if Can_Cast_Ability('Swordplay') then
				Cast_Ability('Swordplay')
				return
			end
			if Can_Cast_Ability('Defender') then
				Cast_Ability('Defender')
				return
			end
			--[[if Can_Cast_Spell_Target('Flash', targetsetid) then
				Cast_Spell_Target('Flash', targetsetid)
				return
			end]]--
		end
		targetset = false
		if GetTargetId() ~= lasttarget then
			ws = 1
			debugmsg(11, "ws reset in fight")
			lasttarget = GetTargetId();
			box = 0
			quick = 0
			feather = 0
			stutter = 0
			--if string.lower(windower.ffxi.get_player().main_job) == 'pup' then
			--	if Can_Cast_Ability('Deploy') then
			--		Cast_Ability('Deploy')
			--	end
			--end
			WSForSkillchain = T {}
			--windower.send_command('cancel shell,protect,haste,phalanx')
		end

		if settings.sleep and Can_Cast_Spell_Target(settings.sleepspell, sleepid) and GetHppById(sleepid) > 0 then
			Cast_Spell_Target(settings.sleepspell, sleepid)
		end

		if settings.partner then
			for _, pid in ipairs(uc_partner_list.as_ordered_ids(settings)) do
				local pt = GetPartnerTargetIdFromPartnerMobId(pid)
				if pt > 0 and pt == GetTargetId() then
					windower.send_command('input /attack off')
					return
				end
			end
		end

		-- Add control: `mid` can move to an add while engaged; client target/attack must follow.
		do
			local ac_on = uc_add_control.enabled(settings)
			local cur_tid = GetTargetId()
			local can_st = ac_on and (not settings.manual) and mid > 0 and uc_dd2_is_monster_combat_target_id(mid) and
				GetHppById(mid) > 0 and cur_tid ~= mid
			if ac_on and dd2_bool(settings.debug) then
				local reasons = {}
				if settings.manual then
					reasons[#reasons + 1] = 'manual_on'
				end
				if mid <= 0 then
					reasons[#reasons + 1] = 'mid_zero'
				end
				if mid > 0 and not uc_dd2_is_monster_combat_target_id(mid) then
					reasons[#reasons + 1] = 'mid_not_eng_monster'
				end
				if mid > 0 and GetHppById(mid) <= 0 then
					reasons[#reasons + 1] = 'mid_dead'
				end
				if cur_tid == mid then
					reasons[#reasons + 1] = 'already_on_mid'
				end
				uc_add_control.log_line(settings, ('retarget cur=%s mid=%s exec=%s gates=%s'):format(
					tostring(cur_tid), tostring(mid), tostring(can_st), table.concat(reasons, ',') ~= '' and table.concat(reasons, ',') or 'none'))
			end
			if can_st then
				if uc_add_control.execute_add_retarget(settings, mid, 'input /attack on') then
					targetsetid = mid
				end
			end
		end

		if has_value(getClaims(), GetTargetClaimId()) or (settings.manual) or (GetTargetClaimId() == 0 and settings.prime) then
			if settings.manual then
				targetset = true
				targetsetid = GetTargetId()
			end
			if GetTargetId() ~= mid and settings.tank then
				lasttargetid = GetTargetId()
				windower.send_command('st ' .. tostring(mid))
				sleep(0.5)
				--windower.add_to_chat(9,'not a tank target')
				windower.send_command('input /attack')
			else
				log_ws_precheck('fight')
				if string.lower(windower.ffxi.get_player().main_job) == 'nin' then
					local pbuffs = windower.ffxi.get_player().buffs
					if not table.contains(pbuffs, 66) and not table.contains(pbuffs, 444) and not table.contains(pbuffs, 445) and
						not table.contains(pbuffs, 446) then
						if Can_Cast_Spell('Utsusemi: San') then
							Cast_Spell('Utsusemi: San')
						elseif Can_Cast_Spell('Utsusemi: Ni') then
							Cast_Spell('Utsusemi: Ni')
						elseif Can_Cast_Spell('Utsusemi: Ichi') then
							Cast_Spell('Utsusemi: Ichi')
						end
					end
				end
				if combatflag == true then
					debugmsg(11, "in combat")
					combatflag = false
				end
				if GetDistanceById(mid) >= 3 and settings.move then
					Check_Distance()
				end

				BS()


				if settings.ability_active == true then
					for i, v in pairs(settings.abilities) do
						if (GetMyPetStatus() == 1 and v == 'Assault') or (GetMyPetName() == 'none' and v == 'Assault') then
							--Don't spam assault
						else
							if Can_Cast_Ability(v) then
								Cast_Ability(v)
							end
						end
					end
				end
				if settings.ability_active == true and string.lower(windower.ffxi.get_player().main_job) == 'dnc' then
					local dncabilities = {
						[1]='Fan Dance',
						[2]='No Foot Rise',
						[3]='Warcry',
						[4]='Aggressor',
						[5]='Berserk',
						[6]='Presto',
						[7]='Box Step',
						[8]='Feather Step',
						[9]='Reverse Flourish',
						[10]='Climactic Flourish',
					}
					for i, v in pairs(dncabilities) do
						if not table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Box Step' then
						elseif not table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Quicktep' then
						elseif not table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Stutter Step' then
						elseif not table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Feather Step' then
						elseif table.contains(windower.ffxi.get_player().buffs, 370) and v == 'Haste Samba' then
						elseif GetSteps() < 5 and v == 'Reverse Flourish' and GetTP() < 2000 then
						elseif GetSteps() < 1 and v == 'Climactic Flourish' then
						elseif GetSteps() < 2 and v == 'Wild Flourish' then
						elseif GetSteps() > 1 and v == 'No Foot Rise' then
						elseif GetSteps() < 1 and v == 'Animated Flourish' then
						elseif table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Box Step' then
							if Can_Cast_Ability(v) and box < 2 then
								Cast_Ability(v)
								box = box + 1
							end
						elseif table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Quicktep' then
							if Can_Cast_Ability(v) and quick < 2 then
								Cast_Ability(v)
								quick = quick + 1
							end
						elseif table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Stutter Step' then
							if Can_Cast_Ability(v) and stutter < 2 then
								Cast_Ability(v)
								stutter = stutter + 1
							end
						elseif table.contains(windower.ffxi.get_player().buffs, 442) and v == 'Feather Step' then
							if Can_Cast_Ability(v) and feather < 2 then
								Cast_Ability(v)
								feather = feather + 1
							end
						else
							if Can_Cast_Ability(v) then
								Cast_Ability(v)
							end
						end
					end
				end
				if (GetMyPetHPP() == 0) and string.lower(windower.ffxi.get_player().main_job) == 'pup' then
					if Can_Cast_Ability('Activate') then
						Cast_Ability('Activate')
					end
				end
				if (GetMyPetHPP() == 0) and string.lower(windower.ffxi.get_player().main_job) == 'bst' then
					if Can_Cast_Ability('Bestial Loyalty') then
						windower.send_command('input /equip ammo "feculent broth"')
						windower.send_command('input /ja "Bestial Loyalty" <me>')
						coroutine.sleep(1)
						windower.send_command('input /equip ammo')
					end
				end
				--if (GetMyPetStatus() == 0) and string.lower(windower.ffxi.get_player().main_job) == 'pup' then
				--	if Can_Cast_Ability('Deploy') then
				--		Cast_Ability('Deploy')
				--	end
				--end
				local act = smartws[1]
				log_ws_precheck('prews')
				if windower.ffxi.get_player().vitals.tp >= 1000 and GetRealDistanceById(targetsetid) < 4 and
					GetHppById(targetsetid) > 0 then
					if (act) and not wsinuse then
						wsinuse = true
						--windower.add_to_chat(3,"ws?")
						act()
						wsinuse = false
					else
						debugmsg(11, "action failed!")
						--poop!
					end
				end
			end
		else
			-- Bad cursor target (e.g. out-of-party buffer): recover onto autotarget mob instead of disengaging.
			if mid > 0 and uc_dd2_is_monster_combat_target_id(mid) then
				targetsetid = mid
				windower.send_command(('st %d'):format(mid))
				sleep(0.3)
				windower.send_command('input /attack on')
			else
				windower.send_command('input /attack off')
			end
		end

	elseif settings.autotarget == true then

		BS()
		if not attacksent then
			if targetset and (targetsetid > 0) then
				if not has_value(getClaims(), GetClaimIdById(targetsetid)) and not GetClaimIdById(targetsetid) == 0 then
					targetsetid = 0
					targetset = false
				end
			end

			if combatflag == false then
				--debugmsg(11, "out of combat once")
				combatflag = true
				targetsetid = 0
				targetset = false
			end
			if (targetsetid > 0) and not (GetHppById(targetsetid) > 0) then
				targetsetid = 0
				targetset = false
			end
			if targetset and targetsetid == 0 then
				targetset = false
			end

			if not targetset then
				Find_Nearest_Target()
			end

			if mid > 0 and GetHppById(mid) > 0 and GetMobById(mid).spawn_type == 16 and not targetset then
				targetsetid = mid
				targetset = true
				windower.send_command(('st %d'):format(targetsetid))
			elseif primemid > 0 and GetHppById(primemid) > 0 and GetMobById(primemid).spawn_type == 16 and mid < 0 and
				not targetset then
				targetsetid = primemid
				targetset = true
				windower.send_command(('st %d'):format(targetsetid))
			end

			if targetsetid > 0 and string.lower(windower.ffxi.get_player().main_job) == 'run' and
				GetMobById(targetsetid).spawn_type == 16 then
				if windower.ffxi.get_ability_recasts()[5] == 0 then
					Cast_Ability('Provoke')
					return
				end
			end


			if targetsetid > 0 and targetset then
				if GetTargetId() ~= targetsetid and uc_dd2_is_monster_combat_target_id(targetsetid) then
					windower.send_command(('st %d'):format(targetsetid))
					sleep(0.1)
				end
				attacksent = true
				windower.send_command('input /attack on')
				sleep(0.35)
				attacksent = false
			end
		end
	end
end

function Can_Cast_Ability(ability)
	local result = false
	local myability = res.job_abilities:with('en', ability)
	Recasts = windower.ffxi.get_ability_recasts()
	local myabilities = windower.ffxi.get_abilities()
	if T(myabilities.job_abilities):contains(myability.id) or T(myabilities.pet_commands):contains(myability.id) then
		if tostring(myability.targets) == '{Self}' or tostring(myability.targets) == '{Self, Player}' then
			if (Recasts[myability.recast_id] == 0) then
				result = true
			end
		elseif tostring(myability.targets) == '{Enemy}' and GetTargetId() ~= 0 then
			if GetMobByTarget().entity_type ~= 8 then
				return false
			end
			if (Recasts[myability.recast_id] == 0) and
				(GetDistanceById(GetTargetId()) <= (GetDistMult(myability.range) * myability.range)) then
				result = true
			end
		end
		return result
	else
		return false
	end
end

function Cast_Ability(ability)
	mv = true
	local myability = res.job_abilities:with('en', ability)
	local timer = 0
	if tostring(myability.targets) == '{Self}' or tostring(myability.targets) == '{Self, Player}' then
		windower.send_command('input ' .. myability.prefix .. ' "' .. myability.en .. '" <me>')
	elseif tostring(myability.targets) == '{Enemy}' and GetTargetId() > 0 then
		windower.send_command('input ' .. myability.prefix .. ' "' .. myability.en .. '" ' .. tostring(GetTargetId()))
	end
	mv = false
end

function Can_Cast_Spell(spell)
	--windower.add_to_chat(9,spell)
	local result = false
	--windower.add_to_chat(9,ability)
	local myspell = res.spells:with('en', spell)
	local Recasts = windower.ffxi.get_spell_recasts()
	--windower.add_to_chat(9,myspell.targets)
	if tostring(myspell.targets) == '{Self}' then
		if (Recasts[myspell.recast_id] == 0) and (not isCasting) then
			result = true
		end
	elseif tostring(myspell.targets) == '{Enemy}' then
		if GetMobByTarget().entity_type ~= 8 then
			return false
		end
		if (Recasts[myspell.recast_id] == 0) and (not isCasting) and
			(GetDistanceById(GetTargetId()) <= (GetDistMult(myspell.range) * myspell.range)) then
			result = true
		end
	end
	return result
end

spellstop = false

function Cast_Spell(spell)
	local wasmoving = moving
	local myspell = res.spells:with('en', spell)
	while Can_Cast_Spell(spell) do
		if moving then
			spellstop = true
			windower.ffxi.run(false)
			sleep(1)
		end
		if tostring(myspell.targets) == '{Self}' then
			windower.send_command('input ' .. myspell.prefix .. ' "' .. myspell.en .. '" <me>')
		elseif tostring(myspell.targets) == '{Enemy}' then
			windower.send_command('input ' .. myspell.prefix .. ' "' .. myspell.en .. '" ' .. tostring(GetTargetId()))
		end
		sleep(0.5)
	end
	if wasmoving then
		spellstop = false
		windower.ffxi.run()
	end
end

function Cast_Spell_Target(spell, id)
	local myspell = res.spells:with('en', spell)
	while Can_Cast_Spell_Target(spell, id) do
		windower.send_command('input ' .. myspell.prefix .. ' "' .. myspell.en .. '" ' .. tostring(id))
		sleep(0.5)
	end
end

function Can_Cast_Spell_Target(spell, id)
	local result = false
	local myspell = res.spells:with('en', spell)
	local Recasts = windower.ffxi.get_spell_recasts()
	--if GetMobById(id).entity_type ~= 8 then
	--	return false
	--end
	if (Recasts[myspell.recast_id] == 0) and (not isCasting) and
		(GetDistanceById(id) <= (GetDistMult(myspell.range) * myspell.range)) then
		result = true
	end
	return result
end

function GetDistMult(key)

	local range_mult = {
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

	return range_mult[key]
end

_static = S { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN',
	'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' }

message_ids = S { 110, 185, 187, 317, 802 }
skillchain_ids = S { 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 385, 386, 387, 388, 389, 390,
	391, 392, 393, 394, 395, 396, 397, 767, 768, 769, 770 }
buff_dur = { [163] = 40, [164] = 30, [470] = 60 }
info = {}
resonating = {}
buffs = {}

skillchains = { 'Light', 'Darkness', 'Gravitation', 'Fragmentation', 'Distortion', 'Fusion', 'Compression',
	'Liquefaction', 'Induration', 'Reverberation', 'Transfixion', 'Scission', 'Detonation', 'Impaction', 'Radiance', 'Umbra' }

sc_info = {
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
	Induration = { 'Ice', Reverberation = { 2, 'Fragmentation' }, Compression = { 1, 'Compression' },
		Impaction = { 1, 'Impaction' }, lvl = 1 },
	Reverberation = { 'Water', Induration = { 1, 'Induration' }, Impaction = { 1, 'Impaction' }, lvl = 1 },
	Transfixion = { 'Light', Scission = { 2, 'Distortion' }, Reverberation = { 1, 'Reverberation' },
		Compression = { 1, 'Compression' }, lvl = 1 },
	Scission = { 'Earth', Liquefaction = { 1, 'Liquefaction' }, Reverberation = { 1, 'Reverberation' },
		Detonation = { 1, 'Detonation' }, lvl = 1 },
	Detonation = { 'Wind', Compression = { 2, 'Gravitation' }, Scission = { 1, 'Scission' }, lvl = 1 },
	Impaction = { 'Lightning', Liquefaction = { 1, 'Liquefaction' }, Detonation = { 1, 'Detonation' }, lvl = 1 },
}

chainbound = {}
chainbound[1] = L { 'Compression', 'Liquefaction', 'Induration', 'Reverberation', 'Scission' }
chainbound[2] = L { 'Gravitation', 'Fragmentation', 'Distortion' } + chainbound[1]
chainbound[3] = L { 'Light', 'Darkness' } + chainbound[2]

local aeonic_weapon = {
	[20515] = 'Godhands',
	[20594] = 'Aeneas',
	[20695] = 'Sequence',
	[20843] = 'Chango',
	[20890] = 'Anguta',
	[20935] = 'Trishula',
	[20977] = 'Heishi Shorinken',
	[21025] = 'Dojikiri Yasutsuna',
	[21082] = 'Tishtrya',
	[21147] = 'Khatvanga',
	[21485] = 'Fomalhaut',
	[21694] = 'Lionheart',
	[21753] = 'Tri-edge',
	[22117] = 'Fail-Not',
	[22131] = 'Fail-Not',
	[22143] = 'Fomalhaut'
}

initialize = function(text, sett)
	if not windower.ffxi.get_info().logged_in then
		return
	end
	if not info.job then
		local player = windower.ffxi.get_player()
		if player then
			info.job = player.main_job
			info.player = player.id
		end
	elseif not info.player then
		-- job_change (or other code) can set info.job before initialize runs; still need player id for buff tables
		local player = windower.ffxi.get_player()
		if player then
			info.player = player.id
		end
	end
	local properties = L {}
	if sett.Show.timer[info.job] then
		properties:append('${timer}')
	end
	if sett.Show.step[info.job] then
		properties:append('Step: ${step} → ${name}')
	end
	if sett.Show.props[info.job] then
		properties:append('[${props}] ${elements}')
	elseif sett.Show.burst[info.job] then
		properties:append('${elements}')
	end
	properties:append('${disp_info}')
	text:clear()
	text:append(properties:concat('\n'))
end

skill_props:register_event('reload', initialize)

function update_weapon()
	if not settings.Show.weapon[info.job] then
		return
	end
	local main_weapon = windower.ffxi.get_items(info.main_bag, info.main_weapon).id
	if main_weapon ~= 0 then
		info.aeonic = aeonic_weapon[main_weapon] or
			info.range and aeonic_weapon[windower.ffxi.get_items(info.range_bag, info.range).id]
		return
	end
	if not check_weapon or coroutine.status(check_weapon) ~= 'suspended' then
		check_weapon = coroutine.schedule(update_weapon, 10)
	end
end

function aeonic_am(step1)
	for x = 270, 272 do
		if buffs[info.player][x] then
			return 272 - x < step1
		end
	end
	return false
end

function aeonic_prop(ability, actor)
	if ability.aeonic and
		(ability.weapon == info.aeonic and actor == info.player or settings.aeonic and info.player ~= actor) then
		return { ability.skillchain[1], ability.skillchain[2], ability.aeonic }
	end
	return ability.skillchain
end

function check_props(old, new)
	for k = 1, #old do
		local first = old[k]
		local combo = sc_info[first]
		for i = 1, #new do
			local second = new[i]
			local result = combo[second]
			if result then
				return unpack(result)
			end
			if #old > 3 and combo.lvl == sc_info[second].lvl then
				break
			end
		end
	end
end

function add_skills(t, abilities, active, resource, AM)
	--windower.add_to_chat(3,'adding skills ...')
	WSForSkillchain = T {}
	local tt = { {}, {}, {}, {} }
	for k = 1, #abilities do
		local ability_id = abilities[k]
		local skillchain = skills[resource][ability_id]
		if skillchain then
			local lv, prop, aeonic = check_props(active, aeonic_prop(skillchain, info.player))
			if prop then
				prop = AM and aeonic or prop
				local a = '%-16s → Lv.%d %s%-14s\\cr'
				local b = '%-16s → Lv.%d %-14s'
				tt[lv][#tt[lv] + 1] = settings.color and
					a:format(res[resource][ability_id].name, lv, colors[prop], prop) or
					b:format(res[resource][ability_id].name, lv, prop)
				if not res[resource][ability_id].skill == 25 and not res[resource][ability_id].skill == 26 then
					WSForSkillchain:append({ ws = res[resource][ability_id].name, lvl = lv })
				end
			end
		end
	end
	for x = 4, 1, -1 do
		for k = #tt[x], 1, -1 do
			t[#t + 1] = tt[x][k]
		end
	end
	return t
end

function check_results(reson)
	local t = {}
	--windower.add_to_chat(3,'Check results ...')
	--if settings.Show.weapon[info.job] then
	t = add_skills(t, windower.ffxi.get_abilities().weapon_skills, reson.active, 'weapon_skills',
		info.aeonic and aeonic_am(reson.step))
	--end
	return _raw.table.concat(t, '\n')
end

function colorize(t)
	local temp
	if settings.color then
		temp = {}
		local a = '%s%s\\cr'
		for k = 1, #t do
			temp[k] = a:format(colors[t[k]], t[k])
		end
	end
	return _raw.table.concat(temp or t, ',')
end

function check_buff(t, i)
	if t[i] == true or t[i] - os.time() > 0 then
		return true
	end
	t[i] = nil
end

function chain_buff(t)
	local i = t[164] and 164 or t[470] and 470
	if i and check_buff(t, i) then
		t[i] = nil
		return true
	end
	return t[163] and check_buff(t, 163)
end

categories = S {
	'weaponskill_finish',
	'spell_finish',
	'job_ability',
	'mob_tp_finish',
	'avatar_tp_finish',
	'job_ability_unblinkable',
}

function apply_properties(target, resource, action_id, properties, delay, step, closed, bound)
	local clock = os.clock()
	resonating[target] = {
		res = resource,
		id = action_id,
		active = properties,
		delay = clock + delay,
		times = clock + delay + 8 - step,
		step = step,
		closed = closed,
		bound = bound
	}
	if target == targ_id then
		next_frame = clock
	end
end

local function dd2_action_handler(act)
	local actionpacket = ActionPacket.new(act)
	local category = actionpacket:get_category_string()

	if not categories:contains(category) or act.param == 0 then
		return
	end

	local actor = actionpacket:get_id()
	local target = actionpacket:get_targets()()
	local actiona = target:get_actions()()
	local message_id = actiona:get_message_id()
	local add_effect = actiona:get_add_effect()
	--local basic_info = action:get_basic_info()
	local param, resource, action_id, interruption, conclusion = actiona:get_spell()
	local ability = skills[resource] and skills[resource][action_id]

	if actor and actor == windower.ffxi.get_player().id then
		if ability then
			wsused = ability.en
		end
	end
	if target and target.id == GetTargetId() then
		if ability then
			if resource == 'weapon_skills' then
				wsusedonmytarget = ability.en
				wstimer = os.clock() + 3
			end
		end
	end
	if add_effect and conclusion and skillchain_ids:contains(add_effect.message_id) then
		local skillchain = add_effect.animation:ucfirst()
		local level = sc_info[skillchain].lvl
		local reson = resonating[target.id]
		local delay = ability and ability.delay or 3
		local step = (reson and reson.step or 1) + 1

		if level == 3 and reson and ability then
			level = check_props(reson.active, aeonic_prop(ability, actor))
		end

		local closed = step > 5 or level == 4

		apply_properties(target.id, resource, action_id, { skillchain }, delay, step, closed)
	elseif ability and (message_ids:contains(message_id) or message_id == 2 and buffs[actor] and chain_buff(buffs[actor])) then
		apply_properties(target.id, resource, action_id, aeonic_prop(ability, actor), 3, 1)
	elseif message_id == 529 then
		apply_properties(target.id, resource, action_id, chainbound[param], 3, 1, false, param)
	elseif message_id == 100 and buff_dur[param] then
		buffs[actor] = buffs[actor] or {}
		buffs[actor][param] = buff_dur[param] + os.time()
	end
end

-- ActionPacket listener registered by UnifiedCombat


local function uc_dd2_job_change(job, lvl)
	local row = res.jobs:with('id', job)
	local job_en = row and row.english_short
	if job_en and job_en ~= info.job then
		info.job = job_en
	end
	local player = windower.ffxi.get_player()
	if player and player.id then
		info.player = player.id
	end
end

local function uc_dd2_zone_change()
	resonating = {}
	mid = 0
	primemid = 0
	mtarget = 0
	mkey = 0
	targetsetid = 0
	targetset = false
	lasttarget = 0
	lasttargetid = 0
	sleepid = -1
	WSForSkillchain = T {}
	ws = 1
	wstimer = os.clock()
	wsinuse = false
	attacksent = false
	combatflag = false
	box = 0
	quick = 0
	feather = 0
	stutter = 0
	debuffed_mobs = {}
	wstimer = os.clock()
end

local function uc_dd2_unload()
	coroutine.close(check_weapon)
end

local function uc_dd2_logout()
	coroutine.close(check_weapon)
	check_weapon = nil
	info = {}
	resonating = {}
	buffs = {}
end

function Get_Recast_A(spell)
	local myspell = res.job_abilities:with('en', spell)
	Recasts = windower.ffxi.get_ability_recasts()
	return Recasts[myspell.recast_id]
end

local function uc_dd2_load()
	if windower.ffxi.get_info().logged_in then
		local equip = windower.ffxi.get_items('equipment')
		info.main_weapon = equip.main
		info.main_bag = equip.main_bag
		info.range = equip.range
		info.range_bag = equip.range_bag
		update_weapon()
		if not info.player then
			info.player = windower.ffxi.get_player().id
		end
		buffs[info.player] = {}
	end
end

local function uc_dd2_prerender()
	uc_keep_ui_visible()
	local now = os.clock()

	if uc_ingame_ui_enabled() then
		dd2_status:text(display_box())
		dd2_status:show()
	else
		dd2_status:hide()
	end
	if now < next_frame then
		return
	end
	if Start_Engine == true then
		dd2_CheckTarget()
		if GetMobById(targetsetid) and GetDistToPuller() < 6 then
			if (GetMyPetStatus() ~= 1) and string.lower(windower.ffxi.get_player().main_job) == 'pup' and
				windower.ffxi.get_player().status == 1 and not (GetMyPetHPP() == 0) and targetsetid > 0 then
				windower.send_command('input /pet deploy ' .. tostring(targetsetid))
			end
		end
		if GetMobById(targetsetid) and GetDistToPuller() < 6 then
			if (GetMyPetStatus() ~= 1) and string.lower(windower.ffxi.get_player().main_job) == 'bst' and
				windower.ffxi.get_player().status == 1 and not (GetMyPetHPP() == 0) and targetsetid > 0 then
				windower.send_command('input /pet fight ' .. tostring(targetsetid))
			end
		end
		if GetMobById(targetsetid) and GetDistToPuller() < 6 then
			if (GetMyPetStatus() == 1) and string.lower(windower.ffxi.get_player().main_job) == 'bst' and
				windower.ffxi.get_player().status == 1 and not (GetMyPetHPP() == 0) and targetsetid > 0 then
					if Get_Recast_A('Sic') == 0 then
						windower.send_command('input /pet "Jettatura" <me>')
					end
			end
		end
		if GetMyPetHPP() < 50 and Can_Cast_Ability('Role Reversal') and GetMyPetHPP() > 0 then
			if not mv then
				Cast_Ability('Role Reversal')
			end
		end
		if GetMyPetHPP() < 10 and Get_Recast_A('Reward') == 0 and Get_Recast_A('Bestial Loyalty') ~= 0 and GetMyPetHPP() > 0 and string.lower(windower.ffxi.get_player().main_job) == 'bst' then
			windower.send_command('input /equip ammo "pet food theta"')
			windower.send_command('input /ja "reward" <me>')
		end
		if Get_Recast_A('Run Wild') == 0 and Get_Recast_A('Bestial Loyalty') <= 300 and GetMyPetHPP() > 0 and string.lower(windower.ffxi.get_player().main_job) == 'bst' then
			windower.send_command('input /ja "Run Wild" <me>')
		end
		if (GetMyPetHPP() > 0) and string.lower(windower.ffxi.get_player().main_job) == 'pup' then
			local pupbuffs = windower.ffxi.get_player().buffs
			local fire = 0
			local earth = 0
			local water = 0
			local wind = 0
			local ice = 0
			local thunder = 0
			local light = 0
			local dark = 0
			--[[
			[300] = {id=300,en="Fire Maneuver",ja="ファイアマニューバ",enl="Fire Maneuver",jal="ファイアマニューバ"},
			[301] = {id=301,en="Ice Maneuver",ja="アイスマニューバ",enl="Ice Maneuver",jal="アイスマニューバ"},
			[302] = {id=302,en="Wind Maneuver",ja="ウィンドマニューバ",enl="Wind Maneuver",jal="ウィンドマニューバ"},
			[303] = {id=303,en="Earth Maneuver",ja="アースマニューバ",enl="Earth Maneuver",jal="アースマニューバ"},
			[304] = {id=304,en="Thunder Maneuver",ja="サンダーマニューバ",enl="Thunder Maneuver",jal="サンダーマニューバ"},
			[305] = {id=305,en="Water Maneuver",ja="ウォータマニューバ",enl="Water Maneuver",jal="ウォータマニューバ"},
			[306] = {id=306,en="Light Maneuver",ja="ライトマニューバ",enl="Light Maneuver",jal="ライトマニューバ"},
			[307] = {id=307,en="Dark Maneuver",ja="ダークマニューバ",enl="Dark Maneuver",jal="ダークマニューバ"},
			--]]
			for index, value in ipairs(pupbuffs) do
				if value == 300 then
					fire = fire + 1
				elseif value == 301 then
					ice = ice + 1
				elseif value == 302 then
					wind = wind + 1
				elseif value == 303 then
					earth = earth + 1
				elseif value == 304 then
					thunder = thunder + 1
				elseif value == 305 then
					water = water + 1
				elseif value == 306 then
					light = light + 1
				elseif value == 307 then
					dark = dark + 1
				end
			end
			if fire < firem and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 1) then
				if Can_Cast_Ability('Fire Maneuver') then
					Cast_Ability('Fire Maneuver')
					lastmv = 1
					lastmanuever = os.clock()
				end
			elseif ice < icem and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 2) then
				if Can_Cast_Ability('Ice Maneuver') then
					Cast_Ability('Ice Maneuver')
					lastmv = 2
					lastmanuever = os.clock()
				end
			elseif wind < windm and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 3) then
				if Can_Cast_Ability('Wind Maneuver') then
					Cast_Ability('Wind Maneuver')
					lastmv = 3
					lastmanuever = os.clock()
				end
			elseif earth < earthm and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 4) then
				if Can_Cast_Ability('Earth Maneuver') then
					Cast_Ability('Earth Maneuver')
					lastmv = 4
					lastmanuever = os.clock()
				end
			elseif thunder < thunderm and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 5) then
				if Can_Cast_Ability('Thunder Maneuver') then
					Cast_Ability('Thunder Maneuver')
					lastmv = 5
					lastmanuever = os.clock()
				end
			elseif water < waterm and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 6) then
				if Can_Cast_Ability('Water Maneuver') then
					Cast_Ability('Water Maneuver')
					lastmv = 6
					lastmanuever = os.clock()
				end
			elseif light < lightm and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 7) then
				if Can_Cast_Ability('Light Maneuver') then
					Cast_Ability('Light Maneuver')
					lastmv = 7
					lastmanuever = os.clock()
				end
			elseif dark < darkm and not mv and (os.clock() > lastmanuever + 45 or lastmv ~= 8) then
				if Can_Cast_Ability('Dark Maneuver') then
					Cast_Ability('Dark Maneuver')
					lastmv = 8
					lastmanuever = os.clock()
				end
			end
		end
		if string.lower(windower.ffxi.get_player().main_job) == 'run' then
			local runbuffs = windower.ffxi.get_player().buffs
			local fire = 0
			local earth = 0
			local water = 0
			local wind = 0
			local ice = 0
			local thunder = 0
			local light = 0
			local dark = 0
			--[[
			[523] = {id=523,en="Ignis",ja="イグニス",enl="Ignis",jal="イグニス"},
			[524] = {id=524,en="Gelus",ja="ゲールス",enl="Gelus",jal="ゲールス"},
			[525] = {id=525,en="Flabra",ja="フラブラ",enl="Flabra",jal="フラブラ"},
			[526] = {id=526,en="Tellus",ja="テッルス",enl="Tellus",jal="テッルス"},
			[527] = {id=527,en="Sulpor",ja="スルポール",enl="Sulpor",jal="スルポール"},
			[528] = {id=528,en="Unda",ja="ウンダ",enl="Unda",jal="ウンダ"},
			[529] = {id=529,en="Lux",ja="ルックス",enl="Lux",jal="ルックス"},
			[530] = {id=530,en="Tenebrae",ja="テネブレイ",enl="Tenebrae",jal="テネブレイ"},
			--]]
			for index, value in ipairs(runbuffs) do
				if value == 523 then
					fire = fire + 1
				elseif value == 524 then
					ice = ice + 1
				elseif value == 525 then
					wind = wind + 1
				elseif value == 526 then
					earth = earth + 1
				elseif value == 527 then
					thunder = thunder + 1
				elseif value == 528 then
					water = water + 1
				elseif value == 529 then
					light = light + 1
				elseif value == 530 then
					dark = dark + 1
				end
			end

			local firerun = 0
			local icerun = 0
			local windrun = 0
			local earthrun = 0
			local thunderrun = 0
			local waterrun = 3
			local lightrun = 0
			local darkrun = 0

			if fire < firerun and not mv then
				if Can_Cast_Ability('Ignis') then
					Cast_Ability('Ignis')
				end
			elseif ice < icerun and not mv then
				if Can_Cast_Ability('Gelus') then
					Cast_Ability('Gelus')
				end
			elseif wind < windrun and not mv then
				if Can_Cast_Ability('Flabra') then
					Cast_Ability('Flabra')
				end
			elseif earth < earthrun and not mv then
				if Can_Cast_Ability('Tellus') then
					Cast_Ability('Tellus')
				end
			elseif thunder < thunderrun and not mv then
				if Can_Cast_Ability('Sulpor') then
					Cast_Ability('Sulpor')
				end
			elseif water < waterrun and not mv then
				if Can_Cast_Ability('Unda') then
					Cast_Ability('Unda')
				end
			elseif light < lightrun and not mv then
				if Can_Cast_Ability('Lux') then
					Cast_Ability('Lux')
				end
			elseif dark < darkrun and not mv then
				if Can_Cast_Ability('Tenebrae') then
					Cast_Ability('Tenebrae')
				end
			end
		end
	end
	next_frame = now + 0.2

	--windower.add_to_chat(3,'step: '..tostring(dd2_GetResonatingStep(GetTargetId()))..' ready: '..tostring(wsready))
	if Start_Engine == true then
		TurnToTarget()
		Find_Nearest_Target()
		if not moving and not settings.static then
			MoveIntoRange()
			if not spaceon and settings.spacing then
				StoreParty()
				Spacing(dd)
			end
		end
	end

	--skillchains


	for k, v in pairs(resonating) do
		if v.times - now + 10 < 0 then
			resonating[k] = nil
		end
	end

	local targ = windower.ffxi.get_mob_by_target('t', 'bt')
	targ_id = targ and targ.id
	local reson = resonating[targ_id]
	local timer = reson and (reson.times - now) or 0

	if targ and targ.hpp > 0 and timer > 0 then
		if not reson.closed then
			reson.disp_info = reson.disp_info or check_results(reson)
			local delay = reson.delay
			local a = '\\cs(255,0,0)Wait  %.1f\\cr'
			local b = '\\cs(0,255,0)Go!   %.1f\\cr'
			reson.timer = now < delay and
				a:format(delay - now) or
				b:format(timer)
			wsready = now < delay and 'no' or 'yes'
		else
			wsready = 'no'
			resonating[targ_id] = nil
			return
		end
		reson.name = res[reson.res][reson.id].name
		local c = 'Chainbound Lv.%d'
		reson.props = reson.props or not reson.bound and colorize(reson.active) or c:format(reson.bound)
		reson.elements = reson.elements
		--skill_props:update(reson)
		--skill_props:show()
	else
		wsready = 'no'
	end
end


return {
    incoming_chunk = uc_dd2_incoming_chunk,
    outgoing_chunk = uc_dd2_outgoing_chunk,
    addon_command = uc_dd2_addon_command,
    job_change = uc_dd2_job_change,
    zone_change = uc_dd2_zone_change,
    unload = uc_dd2_unload,
    logout = uc_dd2_logout,
    load = uc_dd2_load,
    prerender = uc_dd2_prerender,
    action_handler = dd2_action_handler,
    combat_tick = dd2_combat_tick_once,
}
end)()
