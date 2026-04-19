require('lor/lor_chat')
require('lor/lor_utils')
require('strings')
require('chat')
require('logger')
require('tables')
require('luau')
require('pack')
require('actions')
require('lists')
local texts = require('texts')
local skills = require('skills')
local config = require('config')
local res = require('resources')
local packets = require('packets')
local uc_ws_memory = require('uc_ws_memory')
local uc_ignore = require('uc_ignore')
local uc_partner_list = require('uc_partner_list')
local uc_fight_leader = require('uc_fight_leader')
local uc_target_ignore = require('uc_target_ignore')
local uc_add_control = require('uc_add_control')
local socket = require("socket")

require('lor/lor_utils')
_libs.lor.include_addon_name = true
_libs.lor.req('all', { n = 'packets', v = '2016.10.27.0' })
_libs.req('queues')

-- _addon registered by UnifiedCombat.lua
_static = S { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN',
	'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' }

Start_Engine = false
local isCasting = false
local isBusy = 0
local buffactive = {}
local targetset = false
local targetsetid = 0
Action_Delay = 1
local spaceon = false
local moved = false
local moving = false
local partyMembers = T {}
local fighttime = 0
local fightnow = 0
local wsused = ''
local bwsused = false
local wsinuse = false
local status = 'initializing'
local actiontext = ''
local wsusedonmytarget = ''
local wstimer = os.clock()
local pullerpetid = 0
local WSForSkillchain = T {}
local attacksent = false
local once = false
local precast = false


local default = {}
default.ability1 = ""
default.ability2 = ""
default.ability3 = ""
default.ability4 = ""
default.ability5 = ""
default.ability6 = ""
default.ability1rc = 0
default.ability2rc = 0
default.ability_active = true
default.targetability = ""
default.targetability_active = false
default.spell = ""
default.spell_active = true
default.ws1 = "Savage Blade"
default.wsgear = ""
default.tpgear = ""
default.target1 = "apex bats"
default.target2 = "apex jagil"
default.target3 = "apex crab"
default.weaponskill_active = false
default.autotarget = true
default.targets = { default.target1, default.target2, default.target3 }
default.move = false
default.debug = false
default.manual = false
default.solo = false
default.UpdateFrequency = 0.2
default.Show = { burst = _static, pet = S { 'BST', 'SMN' }, props = _static, spell = S { 'SCH', 'BLU' }, step = _static,
	timer = _static, weapon = _static }
default.aeonic = false
default.color = false
default.display = { text = { size = 12, font = 'Consolas' }, pos = { x = 0, y = 0 }, bg = { visible = true } }
default.partner_id = 0
default.partner_id2 = 0
default.partner_ids = {}
default.static = false
default.prime = false
default.parnter_name = ''
default.partnertarget = 0
default.partnertarget2 = 0
default.spacing = false
default.face = true
default.ignore = T {}
default.target_ignore_names = {}
default.spam = false
default.puller = false
default.puller_id = 0
default.puller_distance_only = false
default.fight_leader = false
default.fight_leader_id = 0
default.party_follow = false
default.party_follow_id = 0
default.party_follow_leader_name = ''
default.party_follow_min = 0.5
default.party_follow_max = 50
default.add_control = false
default.add_priority_names = {}
default.sub = false
default.sub2 = false
default.partners = T {}
default.profiles = T { WAR = T {}, MNK = T {}, SAM = T {}, DRG = T {}, DRK = T {}, DD2 = T {} }
-- DD2 engine keys (shared settings table)
default.abilities = T {}
default.wsabilities = T {}
default.dd2_spell_slots = { [1] = { spell = 'Dia' } }
default.weaponskill = nil
default.tank = false
default.sleep = false
default.sleepspell = "Horde Lullaby II"
default.command = false
default.hunter = false
default.closer = false
default.show_ingame_ui = true
default.defensive_enabled = false
default.defensive_provider = 'internal'
default.defensive_cure_enabled = true
default.defensive_na_enabled = true
default.defensive_buff_enabled = true
default.defensive_critical_hpp = 35
default.defensive_medium_hpp = 55
default.defensive_overwrite_enabled = false
default.defensive_overwrite_interval = 150
default.defensive_buff_self_only = true
default.defensive_buffs = ''

default.default_text_settings = {}
default.default_text_settings.pos = {}
default.default_text_settings.pos.x = 1850
default.default_text_settings.pos.y = 1230
default.default_text_settings.bg = {}
default.default_text_settings.bg.alpha = 255
default.default_text_settings.bg.red = 0
default.default_text_settings.bg.green = 0
default.default_text_settings.bg.blue = 0
default.default_text_settings.bg.visible = true
default.default_text_settings.flags = {}
default.default_text_settings.flags.right = false
default.default_text_settings.flags.bottom = false
default.default_text_settings.flags.bold = false
default.default_text_settings.flags.draggable = true
default.default_text_settings.flags.italic = false
default.default_text_settings.padding = 0
default.default_text_settings.text = {}
default.default_text_settings.text.size = 12
default.default_text_settings.text.font = 'Consolas'
default.default_text_settings.text.fonts = {}
default.default_text_settings.text.alpha = 255
default.default_text_settings.text.red = 255
default.default_text_settings.text.green = 255
default.default_text_settings.text.blue = 255
default.default_text_settings.text.stroke = {}
default.default_text_settings.text.stroke.width = 0
default.default_text_settings.text.stroke.alpha = 255
default.default_text_settings.text.stroke.red = 0
default.default_text_settings.text.stroke.green = 0
default.default_text_settings.text.stroke.blue = 0

default.default_text_settings2 = {}
default.default_text_settings2.pos = {}
default.default_text_settings2.pos.x = 500
default.default_text_settings2.pos.y = 500
default.default_text_settings2.bg = {}
default.default_text_settings2.bg.alpha = 200
default.default_text_settings2.bg.red = 0
default.default_text_settings2.bg.green = 0
default.default_text_settings2.bg.blue = 0
default.default_text_settings2.bg.visible = true
default.default_text_settings2.flags = {}
default.default_text_settings2.flags.right = false
default.default_text_settings2.flags.bottom = false
default.default_text_settings2.flags.bold = false
default.default_text_settings2.flags.draggable = true
default.default_text_settings2.flags.italic = false
default.default_text_settings2.padding = 0
default.default_text_settings2.text = {}
default.default_text_settings2.text.size = 12
default.default_text_settings2.text.font = 'Consolas'
default.default_text_settings2.text.fonts = {}
default.default_text_settings2.text.alpha = 255
default.default_text_settings2.text.red = 255
default.default_text_settings2.text.green = 255
default.default_text_settings2.text.blue = 255
default.default_text_settings2.text.stroke = {}
default.default_text_settings2.text.stroke.width = 0
default.default_text_settings2.text.stroke.alpha = 255
default.default_text_settings2.text.stroke.red = 0
default.default_text_settings2.text.stroke.green = 0
default.default_text_settings2.text.stroke.blue = 0

local mkey = 0
local mid = 0
local primemid = 0
local mtarget = 0
local lasttarget = 0
local last = (os.clock() - 0)
local last2 = (os.clock() - 0)
local ws = 1
local step = 0
local combatflag = false
local wstp = 1000

if not _G.UC_SETTINGS then
	_G.UC_SETTINGS = config.load(default)
end
local settings = setmetatable({}, {
	__index = function(_, k)
		return _G.UC_SETTINGS[k]
	end,
	__newindex = function(_, k, v)
		_G.UC_SETTINGS[k] = v
	end,
})
local skill_props = texts.new('', settings.display, settings)
local message_ids = S { 110, 185, 187, 317, 802 }
local skillchain_ids = S { 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 385, 386, 387, 388, 389,
	390, 391, 392, 393, 394, 395, 396, 397, 767, 768, 769, 770 }
local buff_dur = { [163] = 40, [164] = 30, [470] = 60 }
local info = {}
local resonating = {}
local buffs = {}
local movement = false
local dd = _libs.lor.actor.Actor.new()
local wstouse
local ws_gate_debug = 'WS gate: init'

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

--- Resolve WS for combat: optional override (skillchain winner) must be a non-empty string to be used;
--- otherwise configured value is read only from settings after uc_ws_memory.sync_settings (explicit diag on restore / bad types).
local function resolve_weaponskill_for_use(override_ws)
	uc_ws_memory.sync_settings(settings)
	local n
	if type(override_ws) == 'string' and override_ws ~= '' then
		n = override_ws
	else
		n = settings.ws1 or settings.weaponskill
	end
	if type(n) ~= 'string' then
		_G.UC_WS_LAST_DIAG = ('WS_RESOLVE_NOT_STRING:%s'):format(type(n))
		return ''
	end
	if n == '' then
		return ''
	end
	local abilities = windower.ffxi.get_abilities()
	local ws_ids = abilities and abilities.weapon_skills or {}
	local valid_ids = S(ws_ids)
	for _, ws_id in ipairs(ws_ids) do
		local ws = res.weapon_skills[ws_id]
		if ws and ws.en and ws.en ~= '' and ws.en == n then
			uc_ws_memory.remember(n)
			return n
		end
	end
	local requested = res.weapon_skills:with('en', n)
	if requested and valid_ids:contains(requested.id) then
		uc_ws_memory.remember(n)
		return n
	end
	return ''
end

local function can_use_weaponskill_now()
	local player = windower.ffxi.get_player()
	local tp = (player and player.vitals and player.vitals.tp) or 0
	local dist = GetDistance()
	local hpp = GetHppById(targetsetid)
	local max_ws_dist = 6
	local ws_on = setting_enabled(settings.weaponskill_active)
	local ws_name = resolve_weaponskill_for_use(nil)
	if not ws_on then
		return false, ('WS gate: OFF ws=%s tp=%d'):format(ws_name ~= '' and ws_name or 'none', tp)
	end
	if tp <= 999 then
		return false, ('WS gate: TP<1000 ws=%s tp=%d'):format(ws_name ~= '' and ws_name or 'none', tp)
	end
	if dist >= max_ws_dist then
		return false, ('WS gate: RANGE ws=%s dist=%.2f'):format(ws_name ~= '' and ws_name or 'none', dist)
	end
	if hpp <= 0 then
		return false, ('WS gate: DEADTGT ws=%s hpp=%d'):format(ws_name ~= '' and ws_name or 'none', hpp)
	end
	if isBusy ~= 0 then
		return false, ('WS gate: BUSY ws=%s busy=%d'):format(ws_name ~= '' and ws_name or 'none', isBusy)
	end
	if ws_name == '' then
		return false, 'WS gate: NO_VALID_WS'
	end
	return true, ('WS gate: READY ws=%s tp=%d dist=%.2f'):format(ws_name, tp, dist)
end

local smartws = {
	[1] = function()
		local spam_on = setting_enabled(settings.spam)
		if not spam_on then
			local my_tp = GetTP()
			local player = windower.ffxi.get_player()
			local my_id = player and player.id or 0
			for index, value in ipairs(GetPartyTp()) do
				if value.id ~= my_id and not uc_ignore.has_id(_G.UC_SETTINGS, value.id) then
					-- Don't hard-block forever: only wait if ally is actually WS-ready and materially ahead.
					local ally_ws_ready = (value.tp or 0) >= 1000
					local ally_far_ahead = (value.tp or 0) >= (my_tp + 300)
					if value.target == targetsetid and ally_ws_ready and ally_far_ahead and value.status == 1 and not setting_enabled(settings.solo) then
						ws_gate_debug = ('WS fire: waiting ally tp=%d my=%d'):format(value.tp or 0, my_tp)
						return
					end
				end
			end
		end
		local tempwslvl = 0
		wstouse = ''
		if GetResonatingStep(targetsetid) == 0 then
			WSForSkillchain = T{}
		end
		for index, value in ipairs(WSForSkillchain) do
			if value.lvl >= tempwslvl then
				wstouse = value.ws
				tempwslvl = value.lvl
			end
		end
		if wstouse == '' or spam_on or GetResonatingStep(targetsetid) == 0 then
			wstouse = settings.ws1 or settings.weaponskill or ''
		end
		wstouse = resolve_weaponskill_for_use(wstouse)
		if wstouse == '' then
			ws_gate_debug = 'WS fire: blocked no valid WS for equipped weapon'
			return
		end
		if GetTP() >= wstp then
			if (os.clock() >= wstimer or GetResonatingStep(targetsetid) == 0) and wstouse ~= '' then
				debugmsg(11, ('melee smartws send ws="%s" target=%d tp=%d'):format(wstouse, targetsetid or 0, GetTP()))
				windower.send_command('input /ws "' .. wstouse .. '" ' .. tostring(targetsetid))
				actiontext = wstouse
				ws_gate_debug = ('WS fire: sent %s'):format(wstouse)
			elseif spam_on and wstouse ~= '' then
				debugmsg(11, ('melee smartws send spam ws="%s" target=%d tp=%d'):format(wstouse, targetsetid or 0, GetTP()))
				windower.send_command('input /ws "' .. wstouse .. '" ' .. tostring(targetsetid))
				actiontext = wstouse
				ws_gate_debug = ('WS fire: sent spam %s'):format(wstouse)
			else
				ws_gate_debug = ('WS fire: timer lock ws=%s tleft=%.2f'):format(wstouse, math.max(0, wstimer - os.clock()))
			end
		end
	end
}

local skillchains = { 'Light', 'Darkness', 'Gravitation', 'Fragmentation', 'Distortion', 'Fusion', 'Compression',
	'Liquefaction', 'Induration', 'Reverberation', 'Transfixion', 'Scission', 'Detonation', 'Impaction', 'Radiance', 'Umbra' }

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

local chainbound = {}
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

initialize = function(text, settings)
	if not windower.ffxi.get_info().logged_in then
		return
	end
	if not info.job then
		local player = windower.ffxi.get_player()
		info.job = player.main_job
		info.player = player.id
	end
	local properties = L {}
	if settings.Show.timer[info.job] then
		properties:append('${timer}')
	end
	if settings.Show.step[info.job] then
		properties:append('Step: ${step} → ${name}')
	end
	if settings.Show.props[info.job] then
		properties:append('[${props}] ${elements}')
	elseif settings.Show.burst[info.job] then
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

function GetResonatingStep(tid)
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
				if resource == 'weapon_skills' and res[resource][ability_id].name then
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
	if settings.Show.spell[info.job] and info.job == 'SCH' then
		t = add_skills(t, { 0, 1, 2, 3, 4, 5, 6, 7 }, reson.active, 'elements')
	elseif settings.Show.spell[info.job] and info.job == 'BLU' then
		t = add_skills(t, windower.ffxi.get_mjob_data().spells, reson.active, 'spells')
	elseif settings.Show.pet[info.job] and windower.ffxi.get_mob_by_target('pet') then
		t = add_skills(t, windower.ffxi.get_abilities().job_abilities, reson.active, 'job_abilities')
	end
	if settings.Show.weapon[info.job] then
		t = add_skills(t, windower.ffxi.get_abilities().weapon_skills, reson.active, 'weapon_skills',
			info.aeonic and aeonic_am(reson.step))
	end
	return _raw.table.concat(t, '\n')
end

function colorize(t)
	local temp
	local a = '%s%s\\cr'
	if settings.color then
		temp = {}
		for k = 1, #t do
			temp[k] = a:format(colors[t[k]], t[k])
		end
	end
	return _raw.table.concat(temp or t, ',')
end

local next_frame = os.clock()
local fast_frame = os.clock()

function sleep(x)
	coroutine.sleep(x)
end

function uc_melee_incoming_chunk(id, data)
	if id == 0x028 then
		local action_message = packets.parse('incoming', data)
		if action_message["Category"] == 4 then
			isCasting = false
		elseif action_message["Category"] == 8 then
			isCasting = true
			if action_message["Target 1 Action 1 Message"] == 0 then
				isCasting = false
				isBusy = Action_Delay
			end
		end
	end
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
		buffs[info.player] = set_buff
	end
end

function BS()
	local player = windower.ffxi.get_player()
	if GetHppById(targetsetid) > 0 and not settings.static then
		if movement == false then
			--debugmsg(3, 'follow off')
			windower.send_command('hb follow off')
			movement = true
		end
	elseif GetHppById(targetsetid) == 0 and not settings.static then
		if movement == true then
			--debugmsg(3, 'follow on')
			windower.send_command('hb follow resume')
			movement = false
		end
	end
end

function GetMobByTarget()
	local test, targ = pcall(function() return windower.ffxi.get_mob_by_target('t') end)
	if test then
		return targ
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

function GetPullerPetId()
	StoreParty()
	for index, value in ipairs(partyMembers) do
		if value.name == puller then
			local test, petid = pcall(function() return windower.ffxi.get_mob_by_index(value.pet_index).id end)
			if test then
				return petid
			else
				return 0
			end
			break
		end
	end
	return 0
end

function TestParty(value)
	local test, mob = pcall(function() return value.mob end)
	if test then
		return mob
	else
		return nil
	end
end

function StoreParty()
	moved = false
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

function debugmsg(i, vs)
	if settings.debug == true then
		windower.add_to_chat(i, vs)
	end
end

function GetDistToPuller()
	local pullerid = settings.puller_id or 0
	if not settings.puller or pullerid == 0 then
		return 0
	end
	return GetDistanceBetween(targetsetid, pullerid)
end

--- When puller is on with an id: gate MoveIntoRange unless target is near puller, or (unless puller_distance_only) target is damaged.
function uc_puller_allows_spacing_move()
	if not settings.puller or (settings.puller_id or 0) == 0 then
		return true
	end
	local near = GetDistToPuller() <= 6
	if settings.puller_distance_only then
		return near
	end
	return near or (GetHppById(targetsetid) < 99)
end

function GetMobById(id)
	local test, mob = pcall(function() return windower.ffxi.get_mob_by_id(id) end)
	if test then
		return mob
	else
		return nil
	end
end

function GetPartnerTargetIdFromPartnerMobId(partner_mob_id)
	if not partner_mob_id or partner_mob_id == 0 then
		return 0
	end
	local partner = GetMobById(partner_mob_id)
	if partner then
		local partnermob = GetMobIdByIndex(partner.target_index)
		if partnermob then
			return partnermob
		end
	end
	return 0
end

function GetPartnerTargetId()
	return GetPartnerTargetIdFromPartnerMobId(settings.partner_id)
end

function GetPartnerTargetId2()
	return GetPartnerTargetIdFromPartnerMobId(settings.partner_id2)
end

local function uc_melee_mob_is_any_partner_target(mob_id)
	if not settings.partner or settings.manual then
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

local function uc_melee_partner_sub_clear_attack_if_needed()
	if not settings.partner then
		return false
	end
	local ids = uc_partner_list.as_ordered_ids(settings)
	for i, pid in ipairs(ids) do
		local pt = GetPartnerTargetIdFromPartnerMobId(pid)
		if pt > 0 and GetTargetId() == pt then
			if i == 1 and settings.sub then
				windower.send_command('input /attack off')
				targetsetid = 0
				targetset = false
				return true
			end
			if i == 2 and settings.sub2 then
				windower.send_command('input /attack off')
				targetsetid = 0
				targetset = false
				return true
			end
		end
	end
	return false
end

function GetPartnerTargetIds()
	local partnerTargetIds = T {}
	local count = 1
	if settings.partners then
		for id, value in pairs(settings.partners) do
			local partner = GetMobById(id)
			if partner and value.status then
				local partnermob = GetMobIdByIndex(partner.target_index)
				if partnermob then
					partnerTargetIds[count] = partnermob
					count = count + 1
				end
			end
		end
	end
	return partnerTargetIds
end

function GetTargetId()
	local test, id = pcall(function() return GetMobByTarget().id end)
	if test == true then
		return id
	else
		return 0
	end
end

function GetNameById(id)
	local test, name = pcall(function() return windower.ffxi.get_mob_by_id(id).name end)
	if test then
		return name
	else
		return 'none'
	end
end

function PartnerName(name)
	if name == nil then
		return '\\cs(255,0,0)None\\cr'
	else
		return GetNameById(name)
	end
end

function ColorOnOff(bla, bla2)
	local onformat = '[\\cs(0,255,0)%s\\cr]'
	local offformat = '[\\cs(255,0,0)%s\\cr]'
	if bla2 == nil then
		bla2 = 'X'
	end
	return (bla and string.format(onformat, bla2) or string.format(offformat, bla2))
end

function ColorOnOff2(bla)
	local on = '[\\cs(0,255,0)O\\cr]'
	local off = '[\\cs(255,0,0)X\\cr]'
	return (bla and on or off)
end

local display_box = function()
	statustext = ('Status: %-12s Player: %s\n'):format(status, res.statuses:with('id', windower.ffxi.get_player().status).en)
	local midtext = 'MID: N/A\n'
	local fidtext = 'N/A\n'
	local midt = GetMobById(mid)
	if mid > 0 and midt then
		midtext = ('MID: %-10s - %-10d HPP:%3d\n'):format(midt.name, midt.id, midt.hpp)
	end
	fidtext = 'TargetSet: ' .. tostring(targetset) .. ' ID: ' .. tostring(targetsetid)
	local actiont = '\nL/A: ' .. actiontext
	local target = GetMobByTarget()
	local targettext = ''
	if target then
		targettext = ('UIT: %-10s - %-10d HPP:%3d\n'):format(target.name, target.id, target.hpp)
	else
		targettext = 'UIT: N/A\n'
	end
	local timertext = '\nFight Timer: ' .. tostring(math.floor(fighttime - fightnow))
	local restext = '\nResonating: ' .. tostring(GetResonatingStep(targetsetid)) .. ' WSTableSize: ' .. tostring(WSForSkillchain:length())
	local dtext = '\nPuller Dist: ' .. tostring(math.floor(GetDistToPuller() * 100) / 100)
	local pmobtext = '\nPartner Target: ' .. tostring(GetPartnerTargetId())
	local wsgatetext = '\n' .. ws_gate_debug

	return statustext .. midtext .. targettext .. fidtext .. timertext .. actiont .. restext .. dtext .. pmobtext .. wsgatetext
end

local display_box2 = function()
	local line = '%-12s%s'
	local newline = '%-12s%s\n'
	local samstatus = string.format(newline, 'Melee status:', (ColorOnOff2(Start_Engine)))
	local ability = string.format(line, 'Abilities:', ColorOnOff2(settings.ability_active))
	local autotarget = string.format(newline, 'Autotarget:', ColorOnOff2(settings.autotarget))
	local wepskill = string.format(newline, 'Weaponskill:', ColorOnOff(settings.weaponskill_active, settings.ws1))
	local spam = string.format(line, 'Spam:', ColorOnOff2(settings.spam))
	local closer = string.format(newline, 'Closer:', ColorOnOff2(settings.closer))
	local manual = string.format(line, 'Manual:', ColorOnOff2(settings.manual))
	local prime = string.format(newline, 'Prime:', ColorOnOff2(settings.prime))
	local static = string.format(line, 'Static:', ColorOnOff2(settings.static))
	local spacing = string.format(newline, 'Spacing:', ColorOnOff2(settings.spacing))
	local facing = string.format(newline, 'Facing:', ColorOnOff2(settings.face))
	local partner_names = {}
	for _, pid in ipairs(uc_partner_list.as_ordered_ids(settings)) do
		partner_names[#partner_names + 1] = tostring(GetNameById(pid))
	end
	local partner_summary = #partner_names > 0 and table.concat(partner_names, ', ') or 'none'
	local partner = string.format(newline, 'Partners:', ColorOnOff(settings.partner, partner_summary))
	local puller = string.format(newline, 'Puller:', ColorOnOff(settings.puller, GetNameById(settings.puller_id)))
	local add_ctrl = string.format(newline, 'Add control:', ColorOnOff2(settings.add_control))
	local wsgate = string.format(newline, 'WS Gate:', ws_gate_debug)
	local ignore = 'WS wait ignore:\n'
	local ignoreList = ''
	if type(settings.ignore) == 'table' then
		for _, id in pairs(settings.ignore) do
			if type(id) == 'number' and id ~= 0 then
				ignoreList = ignoreList .. '- ' .. tostring(GetNameById(id)) .. '\n'
			end
		end
	end
	local tign = 'Target ignore (by name):\n'
	local tilist = ''
	for _, nm in ipairs(uc_target_ignore.as_ordered_names(settings)) do
		tilist = tilist .. '- ' .. tostring(nm) .. '\n'
	end
	if tilist == '' then
		tilist = '- (none)\n'
	end
	return 	samstatus ..
			ability ..autotarget ..
			wepskill ..
			spam .. closer .. 
			manual .. prime .. 
			static .. spacing .. 
			facing .. 
			partner .. 
			puller .. 
			add_ctrl ..
			wsgate ..
			ignore .. ignoreList ..
			tign .. tilist

end

local function uc_ingame_ui_enabled()
	return settings.show_ingame_ui ~= false
end

local _status = texts.new(display_box(), settings.default_text_settings)
local sam_status = texts.new(display_box2(), settings.default_text_settings2)
local _uc_last_ui_w = 0
local _uc_last_ui_h = 0

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
	-- Conservative padding keeps at least box headers visible.
	-- Keep a generous inset so text boxes remain easy to click-drag after downsizing resolution.
	local c1 = uc_clamp_text_pos(settings.default_text_settings and settings.default_text_settings.pos, w, h, 460, 180)
	local c2 = uc_clamp_text_pos(settings.default_text_settings2 and settings.default_text_settings2.pos, w, h, 520, 180)
	local c3 = uc_clamp_text_pos(settings.display and settings.display.pos, w, h, 420, 180)
	if c1 and _status then
		pcall(function() _status:pos(settings.default_text_settings.pos.x, settings.default_text_settings.pos.y) end)
	end
	if c2 and sam_status then
		pcall(function() sam_status:pos(settings.default_text_settings2.pos.x, settings.default_text_settings2.pos.y) end)
	end
	if c3 and skill_props then
		pcall(function() skill_props:pos(settings.display.pos.x, settings.display.pos.y) end)
	end
	-- Intentionally do not auto-save here; multiple clients can reload simultaneously.
	-- Persist through explicit Save (XML) from the external UI or addon command.
end

local function melee_CheckTarget()
	if GetTargetId() ~= targetsetid and targetsetid > 0 and not settings.manual and GetHppById(targetsetid) > 0 then
		if windower.ffxi.get_player().status == 1 then
			windower.send_command('input /attack off')
		else
			windower.send_command(('st %d'):format(targetsetid))
		end
	end
end

function uc_melee_prerender()
	uc_keep_ui_visible()
	local now = os.clock()
	if uc_ingame_ui_enabled() then
		sam_status:text(display_box2())
		sam_status:show()
	else
		sam_status:hide()
	end
	if Start_Engine == true then
		BS()
		TurnToTarget()
		if not moving then
			MoveIntoRange(dd)
			if not spaceon then
				Spacing(dd)
			end
		end
	end
	if now < fast_frame then
		return
	end
	fast_frame = now + 0.1
	if Start_Engine == true then
		fightnow = os.clock()
		--Find_Nearest_Target()
		melee_CheckTarget()
	end
	if uc_ingame_ui_enabled() and settings.debug then
		_status:text(display_box())
		_status:show()
	else
		_status:hide()
	end
	if not uc_ingame_ui_enabled() then
		skill_props:hide()
	end

	if now < next_frame then
		return
	end
	next_frame = now + 0.5


	--windower.add_to_chat(9,'Step: '..GetResonatingStep(GetTargetId()))
	for k, v in pairs(resonating) do
		if v.times - now + 10 < 0 then
			resonating[k] = nil
		end
	end

	local targ = windower.ffxi.get_mob_by_target('t')
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
		elseif settings.Show.burst[info.job] then
			reson.disp_info = ''
			local fml = 'Burst %d'
			reson.timer = fml:format(timer)
			WSForSkillchain = T {}
		else
			resonating[targ_id] = nil
			WSForSkillchain = T {}
			return
		end
		reson.name = res[reson.res][reson.id].name
		local c = 'Chainbound Lv.%d'
		reson.props = reson.props or not reson.bound and colorize(reson.active) or c:format(reson.bound)
		local d = '(%s)'
		reson.elements = reson.elements or
			reson.step > 1 and settings.Show.burst[info.job] and d:format(colorize(sc_info[reson.active[1]])) or ''
		if uc_ingame_ui_enabled() then
			skill_props:update(reson)
			skill_props:show()
		else
			skill_props:hide()
		end
	elseif not visible then
		skill_props:hide()
	end
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

function apply_properties(target, resource, action_id, properties, delay, step1, closed, bound)
	local clock = os.clock()
	resonating[target] = {
		res = resource,
		id = action_id,
		active = properties,
		delay = clock + delay,
		times = clock + delay + 8 - step1,
		step = step1,
		closed = closed,
		bound = bound
	}
	if target == targ_id then
		next_frame = clock
	end
end

local function melee_action_handler(act)
	local actionpacket = ActionPacket.new(act)
	local category = actionpacket:get_category_string()

	if not categories:contains(category) or act.param == 0 then
		return
	end

	local actor = actionpacket:get_id()
	local target = actionpacket:get_targets()()
	local action = target:get_actions()()
	local message_id = action:get_message_id()
	local add_effect = action:get_add_effect()
	--local basic_info = action:get_basic_info()
	local param, resource, action_id, interruption, conclusion = action:get_spell()
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
		local step1 = (reson and reson.step or 1) + 1

		if level == 3 and reson and ability then
			level = check_props(reson.active, aeonic_prop(ability, actor))
		end

		local closed = step1 > 5 or level == 4

		apply_properties(target.id, resource, action_id, { skillchain }, delay, step1, closed)
	elseif ability and (message_ids:contains(message_id) or message_id == 2 and buffs[actor] and chain_buff(buffs[actor])) then
		apply_properties(target.id, resource, action_id, aeonic_prop(ability, actor), ability.delay or 3, 1)
	elseif message_id == 529 then
		apply_properties(target.id, resource, action_id, chainbound[param], 2, 1, false, param)
	elseif message_id == 100 and buff_dur[param] then
		buffs[actor] = buffs[actor] or {}
		buffs[actor][param] = buff_dur[param] + os.time()
	end
end

function uc_melee_action_handler(act)
	melee_action_handler(act)
end

-- ActionPacket.open_listener registered from UnifiedCombat.lua

function uc_melee_outgoing_chunk(id, data)
	if id == 0x015 then
		local action_message = packets.parse('outgoing', data)
		PlayerH = action_message["Rotation"]
	end
end

function uc_melee_addon_command(...)
	local commands = T { ... }
	local args = T { ... }:map(string.lower)
	if args[1] == nil or args[1] == "help" then
		print("Help Info")
	elseif args[1] == "start" then
		if (not Start_Engine) then
			windower.add_to_chat(2, "....Starting DD Helper....")
			Start_Engine = true
			uc_melee_start_engine()
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
	elseif args[1] == "show" then
		windower.add_to_chat(11, "Autotarget: " .. tostring(settings.autotarget))
		windower.add_to_chat(11, "Spell: " .. settings.spell)
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
	elseif args[1] == "target1" then
		settings.target1 = args[2]
	elseif args[1] == "target2" then
		settings.target2 = args[2]
	elseif args[1] == "target3" then
		settings.target3 = args[2]
	elseif args[1] == "ws" then
		if args[2] == "on" then
			settings.weaponskill_active = true
			windower.add_to_chat(3, "WeaponSkill: True")
		elseif args[2] == "off" then
			settings.weaponskill_active = false
			windower.add_to_chat(3, "WeaponSkill: False")
		else
			if res.weapon_skills:with('en', commands[2]) then
				local newws = res.weapon_skills:with('en', commands[2])
				windower.add_to_chat(3, 'found ws in res:' .. newws.en)
				if S(windower.ffxi.get_abilities().weapon_skills):contains(newws.id) then
					settings.ws1 = commands[2]
					windower.add_to_chat(3, 'WS set: ' .. settings.ws1)
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
			windower.add_to_chat(3, "Ability: True")
		else
			settings.ability_active = false
			windower.add_to_chat(3, "Ability: False")
		end
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
	elseif args[1] == "prime" then
		if args[2] == "on" then
			settings.prime = true
			windower.add_to_chat(3, "prime: True")
		else
			settings.prime = false
			windower.add_to_chat(3, "prime: False")
		end
	elseif args[1] == "team" then
		if args[2] == "on" then
			settings.team = true
			windower.add_to_chat(3, "team: True")
		else
			settings.team = false
			windower.add_to_chat(3, "team: False")
		end
	elseif args[1] == "face" then
		if args[2] == "on" then
			settings.face = true
			windower.add_to_chat(3, "face: True")
		else
			settings.face = false
			windower.add_to_chat(3, "face: False")
		end
	elseif args[1] == "static" then
		if args[2] == "on" then
			settings.static = true
			windower.add_to_chat(3, "static: True")
		else
			settings.static = false
			windower.add_to_chat(3, "static: False")
		end
	elseif args[1] == "spacing" then
		if args[2] == "on" then
			settings.spacing = true
			windower.add_to_chat(3, "spacing: True")
		else
			settings.spacing = false
			windower.add_to_chat(3, "spacing: False")
		end
	elseif args[1] == "spam" then
		if args[2] == "on" then
			settings.spam = true
			windower.add_to_chat(3, "spam: True")
		else
			settings.spam = false
			windower.add_to_chat(3, "spam: False")
		end
	elseif args[1] == "sub" then
		if args[2] == "on" then
			settings.sub = true
			windower.add_to_chat(3, "sub: True")
		else
			settings.sub = false
			windower.add_to_chat(3, "sub: False")
		end
	elseif args[1] == "sub2" then
		if args[2] == "on" then
			settings.sub2 = true
			windower.add_to_chat(3, "sub: True")
		else
			settings.sub2 = false
			windower.add_to_chat(3, "sub: False")
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
			if nm and nm ~= '' then
				local tid = GetTargetIDByName(nm)
				if tid then
					local ok, why = uc_partner_list.append_id(settings, tid)
					if ok and why == 'PARTNER_ALREADY' then
						windower.add_to_chat(3, 'Partner: already listed: ' .. nm)
					elseif ok then
						settings.parnter_name = nm
						windower.add_to_chat(3, 'Partner added: ' .. nm)
					end
				else
					windower.add_to_chat(3, 'Partner: no mob named: ' .. tostring(nm))
				end
			end
		end
	elseif args[1] == 'partner2' then
		if args[2] == 'on' or args[2] == 'off' then
			windower.add_to_chat(3, 'partner2 on/off removed — use partner list + sub/sub2 (slots 1–2).')
		else
			local nm = commands[2]
			if nm and nm ~= '' then
				local tid = GetTargetIDByName(nm)
				if tid then
					local ok, why = uc_partner_list.append_id(settings, tid)
					if ok and why == 'PARTNER_ALREADY' then
						windower.add_to_chat(3, 'Partner: already listed: ' .. nm)
					elseif ok then
						windower.add_to_chat(3, 'Partner added: ' .. nm)
					end
				else
					windower.add_to_chat(3, 'Partner: no mob named: ' .. tostring(nm))
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
				settings.puller_name = commands[2]
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
	elseif args[1] == 'ptid' and commands[2] then
		if args[2] then
			settings.partnertarget = tonumber(args[2])
			--windower.add_to_chat(3,'Partner Target: '..tostring(settings.partnertarget))
		end
	end
end

function HeadingTo(X, Y)
	local x = X - GetMobById(windower.ffxi.get_player().id).x
	local y = Y - GetMobById(windower.ffxi.get_player().id).y
	local H = math.atan2(x, y)
	return H - 1.5708
end

function TurnToTarget()
	if PlayerH ~= nil and settings.face then
		if windower.ffxi.get_player().status == 1 then
			local testx, destX = pcall(function() return GetMobById(GetTargetId()).x end)
			local testy, destY = pcall(function() return GetMobById(GetTargetId()).y end)
			if testx and testy then
				local direction = math.abs(PlayerH - math.deg(HeadingTo(destX, destY)))
				if direction > 10 then
					windower.ffxi.turn(HeadingTo(destX, destY))
				end
			end
		elseif targetsetid > 0 and windower.ffxi.get_player().status ~= 2 and windower.ffxi.get_player().status ~= 3 then
			local destX = GetMobById(targetsetid).x
			local destY = GetMobById(targetsetid).y
			local direction = math.abs(PlayerH - math.deg(HeadingTo(destX, destY)))
			if direction > 10 then
				windower.ffxi.turn(HeadingTo(destX, destY))
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

function Find_Nearest_Target()
	-- Normally skip rescan while a target is locked; add control needs fresh `mid` while engaged.
	if targetset and targetsetid > 0 then
		if not uc_add_control.enabled(settings) then
			return
		end
	end
	--debugmsg(3, 'updating targeting')
	actiontext = 'updating targeting'
	local claims = getClaims()
	local id_targ = -1
	local dist_targ = -1
	local marray = windower.ffxi.get_mob_array()
	local idalt_targ = -1
	local distalt_targ = -1
	for key, mob in pairs(marray) do
		if has_value(claims, mob["claim_id"]) and mob['valid_target'] and
			not uc_target_ignore.is_mob_blocked(settings, mob) then
			if settings.manual or not settings.partner or not uc_melee_mob_is_any_partner_target(mob['id']) then
				if (mob["spawn_type"] == 16 or settings.manual) and mob["hpp"] > 0 then
					if dist_targ == -1 then
						id_targ = mob["id"]
						dist_targ = mob["distance"]
					elseif mob["distance"] < dist_targ then
						id_targ = mob["id"]
						dist_targ = mob["distance"]
					end
				end
			end
		elseif settings.prime and id_targ == -1 then
			if mob["claim_id"] == 0 and mob["spawn_type"] == 16 and mob["status"] == 1 and
				not uc_target_ignore.is_mob_blocked(settings, mob) then
				local tempd = mob["distance"]
				if tempd:sqrt() < 8 then
					if mob["valid_target"] and mob["hpp"] > 0 then
						if distalt_targ == -1 then
							idalt_targ = mob["id"]
							distalt_targ = mob["distance"]
						elseif mob["distance"] < distalt_targ then
							idalt_targ = mob["id"]
							distalt_targ = mob["distance"]
						end
					end
				end
			end
		end
		--end
	end
	local leader_mid = uc_fight_leader.resolve_mid_override(settings, false, function(tid)
		return settings.partner and not settings.manual and uc_melee_mob_is_any_partner_target(tid)
	end)
	local add_mid = uc_add_control.pick(settings, claims, marray, leader_mid, {
		hunter_in_claim = false,
		melee_style = true,
		partner_block = function(mob)
			return (not settings.manual) and settings.partner and uc_melee_mob_is_any_partner_target(mob['id'])
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
	if settings.debug == true and uc_add_control.enabled(settings) then
		uc_add_control.log_line(settings,
			('melee FnT add_pick=%s leader_mid=%s id_targ=%s idalt=%s -> mid=%s primemid=%s'):format(
				tostring(add_mid), tostring(leader_mid), tostring(id_targ), tostring(idalt_targ), tostring(mid), tostring(primemid)))
	end
end

function uc_melee_combat_tick_once()
	if isBusy < 1 then
		local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
		if type(zu) ~= 'number' or os.clock() >= zu then
			uc_melee_Combat()
		end
	else
		isBusy = isBusy - 1
	end
end

local function uc_melee_engine_tick()
	if _G.UC_USE_UNIFIED_ENGINE then
		return
	end
	uc_melee_combat_tick_once()
	if Start_Engine and _G.UC_ENGINE == 'melee' then
		coroutine.schedule(uc_melee_engine_tick, 0.25)
	end
end

function uc_melee_start_engine()
	if type(_G.UC_StartUnifiedEngine) == 'function' then
		_G.UC_StartUnifiedEngine()
		return
	end
	if _G.UC_ENGINE == 'melee' then
		uc_melee_engine_tick()
	end
end

function Engine()
	if type(_G.UC_StartUnifiedEngine) == 'function' then
		_G.UC_StartUnifiedEngine()
		return
	end
	uc_melee_engine_tick()
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

function GetDistanceById(targetid)
	local testa, playersize = pcall(function() return windower.ffxi.get_mob_by_target('me').model_size end)
	local testb, mobsize = pcall(function() return GetMobById(targetid).model_size end)
	local testc, value = pcall(function() return GetMobById(targetid).distance:sqrt() end)
	if testa and testb and testc then
		local real_dist = value - mobsize - playersize
		return real_dist
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

function IsValidTarget(id)
	local test, valid = pcall(function()
		return windower.ffxi.get_mob_by_id(id).valid_target
	end)
	if test then
		return valid
	else
		return false
	end
end

function GetMyPetHpp()
	local test, pethpp = pcall(function() return windower.ffxi.get_mob_by_target('pet').hpp end)
	if test then
		return pethpp
	else
		return 0
	end
end

function MoveIntoRange(loractor)
	moving = true
	if not settings.manual and not settings.static then
		if (GetMobById(targetsetid)) then
			if uc_puller_allows_spacing_move() then
				if (GetMobById(targetsetid).spawn_type == 16) then
					local tempdist = GetDistance()
					local range = 0.25
					local mindist = -0.75
					while (mindist > tempdist or tempdist > range) and GetHppById(targetsetid) > 0 do
						if tempdist > range then
							while tempdist > range and GetHppById(targetsetid) > 0 do
								TurnToTarget()
								loractor:move_towards(targetsetid)
								sleep(0.05)
								tempdist = GetDistance()
							end
							windower.ffxi.run(false)
							moved = true
							actiontext = 'Moved Toward'
						end
						if tempdist < mindist then
							while tempdist < mindist and GetHppById(targetsetid) > 0 do
								loractor:move_away_from(targetsetid)
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
	end
	moving = false
end

function Spacing(loractor)
	if --[[targetsetid > 0 and]] settings.spacing then
		spaceon = true
		for index, value in ipairs(partyMembers) do
			local tempdist = GetRealDistanceById(value.id)
			local mindist = -0.1
			if tempdist < mindist then
				while tempdist < mindist do
					actiontext = 'Move away from ' .. value.name
					loractor:move_away_from(value)
					sleep(0.05)
					tempdist = GetRealDistanceById(value.id)
				end
				windower.ffxi.run(false)
			end
		end
		spaceon = false
	end
end

local function Get_Configured_Abilities()
	local out = {}
	local seen = {}
	if type(settings.abilities) == 'table' then
		for _, ability in ipairs(settings.abilities) do
			if ability and ability ~= '' and not seen[ability] then
				seen[ability] = true
				out[#out + 1] = ability
			end
		end
	end
	if #out == 0 then
		for i = 1, 6 do
			local ability = settings['ability' .. tostring(i)]
			if ability and ability ~= '' and not seen[ability] then
				seen[ability] = true
				out[#out + 1] = ability
			end
		end
	end
	return out
end

local function Cast_Configured_Abilities_Me(max_distance)
	if settings.ability_active ~= true or GetDistance() > (max_distance or 10) then
		return
	end
	local function player_has_buff(buff_id)
		local p = windower.ffxi.get_player()
		local pbuffs = p and p.buffs or nil
		if type(pbuffs) ~= 'table' then
			return false
		end
		if table.contains then
			return table.contains(pbuffs, buff_id)
		end
		for _, b in ipairs(pbuffs) do
			if b == buff_id then
				return true
			end
		end
		return false
	end
	local function should_skip_active_buff_ability(ability_name)
		if not ability_name or ability_name == '' then
			return false
		end
		local ja = res.job_abilities:with('en', ability_name)
		local status = ja and ja.status or nil
		if type(status) == 'number' then
			return player_has_buff(status)
		end
		return false
	end
	local abilities = Get_Configured_Abilities()
	for _, ability in ipairs(abilities) do
		local skip = should_skip_active_buff_ability(ability)
		if not skip then
			if Can_Cast_Ability_Me(ability) then
				Cast_Ability_Me(ability)
			end
		end
	end
end

function Combat_MNK()
	if windower.ffxi.get_player().vitals.hpp < 50 then
		if Can_Cast_Ability_Me('Chakra') then
			Cast_Ability_Me('Chakra')
		end
	end
	if table.contains(windower.ffxi.get_player().buffs, 461) and not table.contains(windower.ffxi.get_player().buffs, 58) then
		if Can_Cast_Ability_Me('Aggressor') then
			Cast_Ability_Me('Aggressor')
		end
	end
	if windower.ffxi.get_player().status == 1 then
		if GetHppById(targetsetid) == 0 then
			targetsetid = GetTargetId()
		end
		if targetsetid == 0 then
			targetsetid = GetTargetId()
		end
		if not GetTargetId() == targetsetid and not settings.manual then
			windower.send_command('input /attack off')
		end
		if uc_melee_partner_sub_clear_attack_if_needed() then
			return
		end
		status = 'Fighting'
		if combatflag == true then
			StoreParty()
			combatflag = false
			fighttime = os.clock() + 15
		end
		if not table.contains(windower.ffxi.get_player().buffs, 461) and targetsetid > 0 then
			if Can_Cast_Ability_Me('Impetus') then
				Cast_Ability_Me('Impetus')
			elseif Can_Cast_Ability_Me('Berserk') then
				Cast_Ability_Me('Berserk')
			elseif Can_Cast_Ability_Me('Footwork') then
				Cast_Ability_Me('Footwork')
			elseif Can_Cast_Ability_Me('Hundred Fists') then
				Cast_Ability_Me('Hundred Fists')
			elseif Can_Cast_Ability_Me('Inner Strength') then
				Cast_Ability_Me('Inner Strength')
			elseif Can_Cast_Ability_Me('Mantra') then
				Cast_Ability_Me('Mantra')
			elseif Can_Cast_Ability_Me('Dodge') then
				Cast_Ability_Me('Dodge')
			end
		end
		if targetsetid ~= lasttarget then
			pullerpetid = GetPullerPetId()
			WSForSkillchain = T {}
			bwsused = false
			wsused = ''
			ws = 1
			wstp = 1000
			lasttarget = targetsetid
		end
		local can_ws, ws_reason = can_use_weaponskill_now()
		ws_gate_debug = ws_reason
		if can_ws then
			local act = smartws[1]
			if act and not wsinuse then
				wsinuse = true
				act()
				fighttime = os.clock() + 15
				wsinuse = false
			end
		end
	elseif settings.autotarget == true then
		status = 'Targeting'
		if not attacksent then
			bwsused = false
			if targetset and (targetsetid > 0) then
				if not has_value(getClaims(), GetClaimIdById(targetsetid)) and not GetClaimIdById(targetsetid) == 0 then
					targetsetid = 0
					targetset = false
				end
			end
			if combatflag == false then
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
			elseif primemid > 0 and GetHppById(primemid) > 0 and GetMobById(primemid).spawn_type == 16 and mid < 0 and
				not targetset then
				targetsetid = primemid
				targetset = true
			end
			if targetsetid > 0 and targetset and GetHppById(targetsetid) > 0 then
				attacksent = true
				windower.send_command(('input /attack %d'):format(targetsetid))
				sleep(1)
				attacksent = false
			end
			if targetsetid > 0 and targetset then
				if Can_Cast_Ability('Chi Blast', targetsetid) then
					Cast_Ability('Chi Blast', targetsetid)
				elseif Can_Cast_Ability('Provoke', targetsetid) then
					Cast_Ability('Provoke', targetsetid)
				end
			end
		end
	end
end

function Combat_SAM()
	if windower.ffxi.get_player().status == 1 then
		if GetHppById(targetsetid) == 0 then
			targetsetid = GetTargetId()
		end
		if targetsetid == 0 then
			targetsetid = GetTargetId()
		end
		if not GetTargetId() == targetsetid and not settings.manual then
			windower.send_command('input /attack off')
			targetsetid = 0
			targetset = false
			return
		end
		if uc_melee_partner_sub_clear_attack_if_needed() then
			return
		end
		status = 'Fighting'
		if not table.contains(windower.ffxi.get_player().buffs, 353) then
			if Can_Cast_Ability_Me('Hasso') then
				Cast_Ability_Me('Hasso')
			end
		end
		if combatflag == true then
			StoreParty()
			combatflag = false
			fighttime = os.clock() + 15
		end
		if targetsetid ~= lasttarget then
			pullerpetid = GetPullerPetId()
			WSForSkillchain = T {}
			bwsused = false
			wsused = ''
			ws = 1
			wstp = 1000
			lasttarget = targetsetid
			Cast_Configured_Abilities_Me(10)
		end
		local can_ws, ws_reason = can_use_weaponskill_now()
		ws_gate_debug = ws_reason
		if can_ws then
			local act = smartws[1]
			if act and not wsinuse then
				wsinuse = true
				act()
				fighttime = os.clock() + 15
				wsinuse = false
			end
		end
	elseif settings.autotarget == true then
		status = 'Targeting'
		if not attacksent then
			bwsused = false
			if targetset and (targetsetid > 0) then
				if not has_value(getClaims(), GetClaimIdById(targetsetid)) and not GetClaimIdById(targetsetid) == 0 then
					targetsetid = 0
					targetset = false
				end
			end
			if combatflag == false then
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
			elseif primemid > 0 and GetHppById(primemid) > 0 and GetMobById(primemid).spawn_type == 16 and mid < 0 and
				not targetset then
				targetsetid = primemid
				targetset = true
			end
			if targetsetid > 0 and targetset then
				attacksent = true
				windower.send_command(('input /attack %d'):format(targetsetid))
				sleep(1)
				attacksent = false
			end
		end
	end
end

function Combat_DRG()
	if windower.ffxi.get_player().status == 1 then
		if GetMyPetHpp() == 0 then
			if Can_Cast_Ability_Me('Call Wyvern') then
				Cast_Ability_Me('Call Wyvern')
			end
		end
		if GetHppById(targetsetid) == 0 then
			targetsetid = GetTargetId()
		end
		if targetsetid == 0 then
			targetsetid = GetTargetId()
		end
		if not GetTargetId() == targetsetid and not settings.manual then
			windower.send_command('input /attack off')
			targetsetid = 0
			targetset = false
		end
		if GetPartnerTargetIds():contains(GetTargetId()) then
			windower.send_command('input /attack off')
			targetsetid = 0
			targetset = false
			return
		end
		status = 'Fighting'
		if not table.contains(windower.ffxi.get_player().buffs, 353) then
			if Can_Cast_Ability_Me(settings.ability1) then
				Cast_Ability_Me(settings.ability1)
			end
		end
		if GetMyPetHpp() < 75 and Can_Cast_Ability_Me('Spirit Link') then
			Cast_Ability_Me('Spirit Link')
		end
		if combatflag == true then
			StoreParty()
			combatflag = false
			fighttime = os.clock() + 15
		end
		if targetsetid ~= lasttarget then
			pullerpetid = GetPullerPetId()
			WSForSkillchain = T {}
			bwsused = false
			wsused = ''
			ws = 1
			wstp = 1000
			lasttarget = targetsetid
			Cast_Configured_Abilities_Me(10)
		end
		local can_ws, ws_reason = can_use_weaponskill_now()
		ws_gate_debug = ws_reason
		if can_ws then
			local act = smartws[1]
			if act and not wsinuse then
				wsinuse = true
				act()
				fighttime = os.clock() + 15
				wsinuse = false
			end
		end
	elseif settings.autotarget == true then
		status = 'Targeting'
		if not attacksent then
			bwsused = false
			if targetset and (targetsetid > 0) then
				if not has_value(getClaims(), GetClaimIdById(targetsetid)) and not GetClaimIdById(targetsetid) == 0 then
					targetsetid = 0
					targetset = false
				end
			end
			if combatflag == false then
				combatflag = true
				targetsetid = 0
				targetset = false
				once = true
			end
			if (targetsetid > 0) and not (GetHppById(targetsetid) > 0) then
				targetsetid = 0
				targetset = false
			end
			if targetset and targetsetid == 0 then
				targetset = false
			end
			if targetsetid > 0 and targetset and GetTargetId() == targetsetid then
				attacksent = true
				windower.send_command(('input /attack %d'):format(targetsetid))
				sleep(1)
				attacksent = false
			end
		end
		if targetsetid > 0 and GetDistance() <= 9.5 and targetset and once and not GetPartnerTargetIds():contains(targetsetid) then
			windower.add_to_chat(3, 'Jump?')
			if Can_Cast_Ability('Soul Jump', targetsetid) then
				Cast_Ability('Soul Jump', targetsetid)
			elseif Can_Cast_Ability('Spirit Jump', targetsetid) then
				Cast_Ability('Spirit Jump', targetsetid)
			elseif Can_Cast_Ability('High Jump', targetsetid) then
				Cast_Ability('High Jump', targetsetid)
			elseif Can_Cast_Ability('Jump', targetsetid) then
				Cast_Ability('Jump', targetsetid)
			end
			once = false
		end
	end
end

function Combat_DRK()
	if windower.ffxi.get_player().status == 1 then
		if GetHppById(targetsetid) == 0 then
			targetsetid = GetTargetId()
		end
		if targetsetid == 0 then
			targetsetid = GetTargetId()
		end
		if not GetTargetId() == targetsetid and not settings.manual then
			windower.send_command('input /attack off')
		end
		if uc_melee_partner_sub_clear_attack_if_needed() then
			return
		end
		status = 'Fighting'
		if not table.contains(windower.ffxi.get_player().buffs, 353) then
			if Can_Cast_Ability_Me(settings.ability1) then
				Cast_Ability_Me(settings.ability1)
			end
		end
		if not table.contains(windower.ffxi.get_player().buffs, 64) and not table.contains(windower.ffxi.get_player().buffs, 63) then
			if Can_Cast_Ability_Me('Last Resort') then
				Cast_Ability_Me('Last Resort')
			elseif Can_Cast_Ability_Me('Souleater') then
				Cast_Ability_Me('Souleater')
			end
		end
		if not table.contains(windower.ffxi.get_player().buffs, 479) and not table.contains(windower.ffxi.get_player().buffs, 480) then
			if Can_Cast_Ability_Me('Scarlet Delirium') then
				Cast_Ability_Me('Scarlet Delirium')
			end
		end
		if combatflag == true then
			StoreParty()
			combatflag = false
			fighttime = os.clock() + 15
		end
		if targetsetid ~= lasttarget then
			pullerpetid = GetPullerPetId()
			WSForSkillchain = T {}
			bwsused = false
			wsused = ''
			ws = 1
			wstp = 1000
			lasttarget = targetsetid
			if settings.ability_active == true and GetDistance() <= 10 then
				if Can_Cast_Ability_Me('Diabolic Eye') then
					Cast_Ability_Me('Diabolic Eye')
				elseif Can_Cast_Ability_Me('Meditate') then
					Cast_Ability_Me('Meditate')
				end
			end
		end
		if Can_Cast_Spell_T('Absorb-TP', targetsetid) then
			Cast_Spell_T('Absorb-TP', targetsetid)
		end
		local can_ws, ws_reason = can_use_weaponskill_now()
		ws_gate_debug = ws_reason
		if can_ws then
			local act = smartws[1]
			if act and not wsinuse then
				wsinuse = true
				act()
				fighttime = os.clock() + 15
				wsinuse = false
			end
		end
	elseif settings.autotarget == true then
		status = 'Targeting'
		if not attacksent then
			bwsused = false
			if targetset and (targetsetid > 0) then
				if not has_value(getClaims(), GetClaimIdById(targetsetid)) and not GetClaimIdById(targetsetid) == 0 then
					targetsetid = 0
					targetset = false
				end
			end
			if combatflag == false then
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
			if not table.contains(windower.ffxi.get_player().buffs, 288) and mid > 0 then
				if Can_Cast_Spell_Me('Endark II') then
					Cast_Spell_Me('Endark II')
				end
				return
			end
			if not table.contains(windower.ffxi.get_player().buffs, 173) and mid > 0 then
				if Can_Cast_Spell_Me('Dread Spikes') then
					Cast_Spell_Me('Dread Spikes')
				end
				return
			end
			if mid > 0 and GetHppById(mid) > 0 and GetMobById(mid).spawn_type == 16 and not targetset then
				targetsetid = mid
				targetset = true
			elseif primemid > 0 and GetHppById(primemid) > 0 and GetMobById(primemid).spawn_type == 16 and mid < 0 and
				not targetset then
				targetsetid = primemid
				targetset = true
			end
			precast = true
			if targetsetid > 0 then
				if Can_Cast_Spell_T('Absorb-DEX', targetsetid) then
					Cast_Spell_T('Absorb-DEX', targetsetid)
					return
				end
				if Can_Cast_Spell_T('Absorb-STR', targetsetid) then
					Cast_Spell_T('Absorb-STR', targetsetid)
					return
				end
			end
			if Get_Recast('Absorb-STR') == 0 or Get_Recast('Absorb-DEX') == 0 then
				return
			end
			precast = false
			if targetsetid > 0 and targetset then
				attacksent = true
				windower.send_command(('input /attack %d'):format(targetsetid))
				sleep(1)
				attacksent = false
			end
		end
	end
end

function uc_melee_Combat()
	-- Fight leader + add control: keep `mid` current and break attack lock to switch to adds.
	if windower.ffxi.get_player().status == 1 and uc_add_control.enabled(settings) and not settings.manual then
		Find_Nearest_Target()
		local cur_tid = GetTargetId()
		local can_st = mid > 0 and GetMobById(mid) and GetMobById(mid).spawn_type == 16 and GetHppById(mid) > 0 and
			cur_tid ~= mid
		if settings.debug == true and uc_add_control.enabled(settings) then
			local reasons = {}
			if settings.manual then
				reasons[#reasons + 1] = 'manual_on'
			end
			if mid <= 0 then
				reasons[#reasons + 1] = 'mid_zero'
			end
			if mid > 0 and (not GetMobById(mid) or GetMobById(mid).spawn_type ~= 16) then
				reasons[#reasons + 1] = 'mid_not_spawn16'
			end
			if mid > 0 and GetHppById(mid) <= 0 then
				reasons[#reasons + 1] = 'mid_dead'
			end
			if cur_tid == mid then
				reasons[#reasons + 1] = 'already_on_mid'
			end
			uc_add_control.log_line(settings, ('melee retarget cur=%s mid=%s exec=%s gates=%s'):format(
				tostring(cur_tid), tostring(mid), tostring(can_st), table.concat(reasons, ',') ~= '' and table.concat(reasons, ',') or 'none'))
		end
		if can_st then
			if uc_add_control.execute_add_retarget(settings, mid, ('input /attack %d'):format(mid)) then
				targetsetid = mid
			end
		end
	end
	local j = (info.job or ''):upper()
	if j == 'MNK' then
		Combat_MNK()
	elseif j == 'SAM' then
		Combat_SAM()
	elseif j == 'DRG' then
		Combat_DRG()
	elseif j == 'DRK' then
		Combat_DRK()
	else
		Combat_WAR()
	end
end

function Combat_WAR()

	-- if we have Restraint up try and use aggressor to maximize accuracy
	if table.contains(windower.ffxi.get_player().buffs, 435) and not table.contains(windower.ffxi.get_player().buffs, 58) then
		if Can_Cast_Ability_Me('Aggressor') then
			Cast_Ability_Me('Aggressor')
		end
	end

	-- is Engaged / combat
	if windower.ffxi.get_player().status == 1 then
		if GetHppById(targetsetid) == 0 then
			targetsetid = GetTargetId()
		end
		if targetsetid == 0 then
			targetsetid = GetTargetId()
		end
		if not GetTargetId() == targetsetid and not settings.manual then
			windower.send_command('input /attack off')
		end
		if uc_melee_partner_sub_clear_attack_if_needed() then
			return
		end
		status = 'Fighting'
		if not table.contains(windower.ffxi.get_player().buffs, 353) then
			if Can_Cast_Ability_Me('Hasso') then
				Cast_Ability_Me('Hasso')
			end
		end
		if not table.contains(windower.ffxi.get_player().buffs, 405) then
			if Can_Cast_Ability_Me('Retaliation') then
				Cast_Ability_Me('Retaliation')
			end
		end
		if combatflag == true then
			StoreParty()
			--debugmsg(11, "in combat")
			combatflag = false
			fighttime = os.clock() + 15
		end

		if targetsetid ~= lasttarget then
			pullerpetid = GetPullerPetId()
			WSForSkillchain = T {}
			bwsused = false
			wsused = ''
			ws = 1
			wstp = 1000
			--debugmsg(11, "ws reset in fight")
			lasttarget = targetsetid
			if Can_Cast_Ability('Provoke', targetsetid) then
				Cast_Ability('Provoke', targetsetid)
			elseif Can_Cast_Ability_Me('Restraint') then
				Cast_Ability_Me('Restraint')
			elseif Can_Cast_Ability_Me('Blood Rage') then
				Cast_Ability_Me('Blood Rage')
			elseif Can_Cast_Ability_Me('Brazen Rush') then
				Cast_Ability_Me('Brazen Rush')
			elseif Can_Cast_Ability_Me('Mighty Strikes') then
				Cast_Ability_Me('Mighty Strikes')
			elseif Can_Cast_Ability_Me('Berserk') then
				Cast_Ability_Me('Berserk')
			elseif Can_Cast_Ability_Me('Meditate') then
				Cast_Ability_Me('Meditate')
			end
		end

		local can_ws, ws_reason = can_use_weaponskill_now()
		ws_gate_debug = ws_reason
		if can_ws then
			local act
			act = smartws[1]
			if (act) and not wsinuse then
				wsinuse = true
				act()
				fighttime = os.clock() + 15
				wsinuse = false
			end
		end

	elseif settings.autotarget == true then

		status = 'Targeting'
		if not attacksent then
			bwsused = false
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
				--windower.send_command(('st %d'):format(targetsetid))
			elseif primemid > 0 and GetHppById(primemid) > 0 and GetMobById(primemid).spawn_type == 16 and mid < 0 and
				not targetset then
				targetsetid = primemid
				targetset = true
				--windower.send_command(('st %d'):format(targetsetid))
			end

			if targetsetid > 0 and targetset and GetHppById(targetsetid) > 0 then
				attacksent = true
				windower.send_command(('input /attack %d'):format(targetsetid))
				sleep(1)
				attacksent = false
			end

			if targetsetid > 0 and targetset then
				if Can_Cast_Ability('Provoke', targetsetid) then
					Cast_Ability('Provoke', targetsetid)
				end
			end
		end
	end
end

function Can_Cast_Spell(spell, targetid)
	local result = false
	local myspell = res.spells:with('en', spell)
	Recasts = windower.ffxi.get_spell_recasts()
	if Recasts[myspell.id] == 0 and not isCasting and
		GetDistanceById(targetid) <= (GetDistMult(myspell.range) * myspell.range) and
		windower.ffxi.get_player().vitals.mp >= myspell.mp_cost then
		result = true
	end
	return result
end

function Can_Cast_Spell_Me(spell)
	local result = false
	local myspell = res.spells:with('en', spell)
	Recasts = windower.ffxi.get_spell_recasts()
	if Recasts[myspell.id] == 0 and not isCasting and windower.ffxi.get_player().vitals.mp >= myspell.mp_cost then
		result = true
	end
	return result
end

function Can_Cast_Ability(ability, targetid)
	local result = false
	local myability = res.job_abilities:with('en', ability)
	local myAbilities = S { windower.ffxi.get_abilities().job_abilities }
	if not has_value(myAbilities,myability.id) then return false end
	if not myability then return false end
	Recasts = windower.ffxi.get_ability_recasts()
	if (Recasts[myability.recast_id] == 0) and (not isCasting) and
		(GetDistanceById(targetid) <= (GetDistMult(myability.range) * myability.range)) then
		result = true
	end
	return result
end

function Can_Cast_Ability_Me(ability)
	local result = false
	local myability = res.job_abilities:with('en', ability)
	local myAbilities = windower.ffxi.get_abilities().job_abilities
	if not has_value(myAbilities,myability.id) then return false end
	if not myability then return false end
	Recasts = windower.ffxi.get_ability_recasts()
	if (Recasts[myability.recast_id] == 0) and (not isCasting) then
		result = true
	end
	return result
end

function Cast_Spell(spell, targetid)
	local myspell = res.spells:with('en', spell)
	actiontext = myspell.en
	while Can_Cast_Spell(spell, targetid) do
		windower.send_command("input /ma \"" .. myspell.en .. "\" " .. tostring(targetid))
		sleep(0.5)
	end
end

function Cast_Spell_Me(spell)
	local myspell = res.spells:with('en', spell)
	actiontext = myspell.en
	while Can_Cast_Spell_Me(spell) do
		windower.send_command("input /ma \"" .. myspell.en .. "\" <me>")
		sleep(0.5)
	end
end

function Can_Cast_Spell_T(spell, targetid)
	local result = false
	local myspell = res.spells:with('en', spell)
	local myspells = windower.ffxi.get_spells()
	if myspells[myspell.id] == 'false' then return result end
	Recasts = windower.ffxi.get_spell_recasts()
	if Recasts[myspell.id] == 0 and not isCasting and
		GetDistanceById(targetid) <= (GetDistMult(myspell.range) * myspell.range) and
		windower.ffxi.get_player().vitals.mp >= myspell.mp_cost then
		result = true
	end
	return result
end

function Cast_Spell_T(spell, targetid)
	local myspell = res.spells:with('en', spell)
	actiontext = myspell.en
	while Can_Cast_Spell_T(spell, targetid) do
		windower.send_command("input /ma \"" .. myspell.en .. "\" " .. tostring(targetid))
		sleep(0.5)
	end
end

function Get_Recast(spell)
	local myspell = res.spells:with('en', spell)
	Recasts = windower.ffxi.get_spell_recasts()
	return Recasts[myspell.id]
end

--poop is poopie

function Cast_Ability(ability, targetid)
	local myability = res.job_abilities:with('en', ability)
	actiontext = myability.en
	while Can_Cast_Ability(ability, targetid) do
		windower.send_command("input /ja \"" .. myability.en .. "\" " .. tostring(targetid))
		sleep(0.5)
	end
end

function Cast_Ability_Me(ability)
	local myability = res.job_abilities:with('en', ability)
	actiontext = myability.en
	while Can_Cast_Ability_Me(ability) do
		windower.send_command("input /ja \"" .. myability.en .. "\" <me>")
		sleep(0.5)
	end
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

function uc_melee_job_change(job, lvl)
	job = res.jobs:with('id', job).english_short
	if job ~= info.job then
		info.job = job
	end
end

function uc_melee_zone_change()
	resonating = {}
	mid = 0
	primemid = 0
	mtarget = 0
	mkey = 0
	targetsetid = 0
	targetset = false
	lasttarget = 0
	WSForSkillchain = T {}
	ws = 1
	wstp = 1000
	bwsused = false
	wsused = ''
	wsinuse = false
	attacksent = false
	combatflag = false
	precast = false
	once = false
	fighttime = 0
	fightnow = 0
	pullerpetid = 0
	wstimer = os.clock()
	actiontext = ''
	ws_gate_debug = 'WS gate: zone reset'
end

function uc_melee_load()
	if windower.ffxi.get_info().logged_in then
		local player = windower.ffxi.get_player()
		info.job = player.main_job
		info.player = player.id
		local equip = windower.ffxi.get_items('equipment')
		info.main_weapon = equip.main
		info.main_bag = equip.main_bag
		info.range = equip.range
		info.range_bag = equip.range_bag
		update_weapon()
		buffs[info.player] = {}
	end
end

function uc_melee_unload()
	if check_weapon then
		coroutine.close(check_weapon)
	end
end

function uc_melee_logout()
	if check_weapon then
		coroutine.close(check_weapon)
	end
	check_weapon = nil
	info = {}
	resonating = {}
	buffs = {}
end

function Death()
	Start_Engine = false
end

function uc_melee_status_change(new, old)
	if new > 1 and new < 4 then
		Death()
	end
end