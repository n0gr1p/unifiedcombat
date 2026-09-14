package.path = './?.lua;' .. package.path

package.loaded.uc_target_ignore = {
	is_mob_blocked = function() return false end,
}

local detector = require('uc_tank_pet_enmity')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local tank = { id = 100, name = 'Tank' }
local owner = { id = 200, name = 'Summoner', pet_index = 55 }
local pet = { id = 300, name = 'Ifrit', index = 55, hpp = 87 }
local enemy = {
	id = 900,
	name = 'Zerde',
	valid_target = true,
	spawn_type = 16,
	hpp = 76,
	status = 1,
	target_index = 55,
	distance = 16,
	claim_id = owner.id,
}

local opts = {
	get_party = function()
		return {
			p0 = { mob = tank },
			p1 = { mob = owner, pet_index = 55 },
		}
	end,
	get_mob_by_index = function(index)
		if index == 55 then return pet end
		return nil
	end,
	get_mob_by_id = function(id)
		if id == tank.id then return tank end
		if id == owner.id then return owner end
		if id == pet.id then return pet end
		return nil
	end,
	get_mob_array = function()
		return { enemy }
	end,
	now = 100,
}

local map = detector.friendly_pet_map(tank.id, opts)
assert_equal(map[pet.id].owner_id, owner.id, 'friendly pet owner id')
assert_equal(map[pet.id].owner_name, owner.name, 'friendly pet owner name')

local violation = detector.find_violation({}, tank, opts)
assert_equal(violation.victim_id, pet.id, 'pet victim id')
assert_equal(violation.victim_name, pet.name, 'pet victim name')
assert_equal(violation.victim_kind, 'pet', 'pet victim kind')
assert_equal(violation.owner_id, owner.id, 'pet violation owner id')
assert_equal(violation.owner_name, owner.name, 'pet violation owner name')
assert_equal(violation.mob_id, enemy.id, 'pet violation enemy id')

-- Claim ownership must not hide the real current target. Zerde can remain claimed
-- to the Summoner while its actual target_index points at Ifrit.
assert_equal(enemy.claim_id, owner.id, 'fixture claim owner')
assert_equal(violation.victim_id, pet.id, 'actual pet target wins over claim owner')

-- The tank's own pet follows the existing player rule: self is not an enmity
-- violation victim.
local tank_pet = { id = 301, name = 'Tank Pet', index = 56, hpp = 100 }
tank.pet_index = 56
enemy.target_index = 56
opts.get_mob_by_index = function(index)
	if index == 55 then return pet end
	if index == 56 then return tank_pet end
	return nil
end
opts.get_mob_by_id = function(id)
	if id == tank.id then return tank end
	if id == owner.id then return owner end
	if id == pet.id then return pet end
	if id == tank_pet.id then return tank_pet end
	return nil
end
assert_equal(detector.find_violation({}, tank, opts), nil, 'tank own pet is not a violation')

print('selftest_tank_pet_enmity: OK')
