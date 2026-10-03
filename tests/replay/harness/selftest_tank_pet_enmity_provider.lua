package.path = './?.lua;' .. package.path

local include_pets = false
package.loaded.uc_scheduler_config = {
	tank_enabled_from_config = function(config)
		return type(config) == 'table' and type(config.tank) == 'table' and config.tank.enabled == true
	end,
	tank_enmity_actions_from_config = function(config)
		local enmity = type(config) == 'table' and type(config.tank) == 'table' and config.tank.enmity or nil
		return type(enmity) == 'table' and enmity.actions or {}
	end,
	tank_enmity_include_pets_from_config = function(config)
		local enmity = type(config) == 'table' and type(config.tank) == 'table' and config.tank.enmity or nil
		return type(enmity) == 'table' and enmity.include_pets == true
	end,
	targeting_ignore_names_from_config = function(config)
		local targeting = type(config) == 'table' and config.targeting or nil
		return type(targeting) == 'table' and targeting.target_ignore_names or {}
	end,
}
package.loaded.uc_provider_run_tank = {
	new = function()
		return { collect = function() end }
	end,
}
package.loaded.uc_target_ignore = {
	is_mob_blocked = function() return false end,
}
package.loaded.resources = {
	spells = {
		with = function(_, key, name)
			if key == 'en' and name == 'Flash' then return { en = 'Flash', range = 12 } end
			return nil
		end,
	},
	job_abilities = {},
}

local tank = { id = 100, name = 'Tank', status = 1 }
local owner = { id = 200, name = 'Summoner', pet_index = 55 }
local pet = { id = 300, name = 'Ifrit', index = 55, hpp = 100 }
local enemy = {
	id = 900,
	name = 'Zerde',
	valid_target = true,
	spawn_type = 16,
	hpp = 90,
	status = 1,
	target_index = 55,
	distance = 16,
	claim_id = owner.id,
}

_G.windower = {
	ffxi = {
		get_party = function()
			return { p0 = { mob = tank }, p1 = { mob = owner, pet_index = 55 } }
		end,
		get_mob_by_index = function(index) return index == 55 and pet or nil end,
		get_mob_by_id = function(id)
			if id == tank.id then return tank end
			if id == owner.id then return owner end
			if id == pet.id then return pet end
			return nil
		end,
		get_mob_array = function() return { enemy } end,
	},
}
_G.Start_Engine = true

local provider = require('uc_provider_tank_enmity').new({
	bool_setting = function(value, default_value)
		if value == nil then return default_value end
		return value == true
	end,
	abilities_allow_unengaged = function(config)
		return type(config) == 'table' and type(config.abilities) == 'table' and config.abilities.allow_unengaged == true
	end,
	select_tank_enmity = function() return nil end,
	action_ready = function(name, target_id)
		if name == 'Flash' and target_id == enemy.id then return true, '', 'spell' end
		return false, 'not_ready', 'spell'
	end,
	action_effective_range = function() return 20 end,
	log_tank_sched = function() end,
	clamp_urgency = function(value) return value end,
})

local ctx = {
	now = 10,
	config = {
		abilities = { enabled = true, allow_unengaged = true, configured = {}, legacy_slots = {} },
		tank = { enabled = true, enmity = { actions = { 'Flash' }, include_pets = false } },
		targeting = { target_ignore_names = {} },
	},
	settings = { tank = false, ability_allow_unengaged = true, tank_enmity_actions = { 'Provoke' }, tank_enmity_include_pets = true },
	player_present = true,
	player = tank,
	mobs_by_id = { [enemy.id] = enemy },
}

local out = {}
provider.collect(ctx, out)
if #out ~= 0 then error('disabled pet enmity toggle must preserve player-only behavior') end

include_pets = true
ctx.config.tank.enmity.include_pets = true
out = {}
provider.collect(ctx, out)
if #out ~= 1 then error(('enabled pet enmity toggle expected one proposal, got %d'):format(#out)) end
local proposal = out[1]
if proposal.action_name ~= 'Flash' then error('pet enmity recovery should use configured Flash') end
if proposal.target_id ~= enemy.id then error('pet enmity recovery should target the enemy, not the pet') end
if proposal.detail.victim_kind ~= 'pet' then error('pet victim kind telemetry missing') end
if proposal.detail.victim_id ~= pet.id then error('pet victim id telemetry missing') end
if proposal.detail.owner_id ~= owner.id or proposal.detail.owner_name ~= owner.name then
	error('pet owner telemetry missing')
end

print('selftest_tank_pet_enmity_provider: OK')
