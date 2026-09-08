local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local original_windower = rawget(_G, 'windower')
local original_targeting_common = package.loaded.uc_targeting_common
local original_skillchain_target = package.loaded.uc_sch_skillchain_target

local friendly_claim_id = 5001
local foreign_claim_id = 9001
local mobs = {
	[1001] = {
		id = 1001,
		index = 41,
		name = 'Locus Camelopard',
		hpp = 100,
		valid_target = true,
		spawn_type = 16,
		claim_id = friendly_claim_id,
		distance = 100,
	},
	[1002] = {
		id = 1002,
		index = 42,
		name = 'Foreign Mob',
		hpp = 100,
		valid_target = true,
		spawn_type = 16,
		claim_id = foreign_claim_id,
		distance = 25,
	},
}
local selected = nil

windower = {
	ffxi = {
		get_party = function()
			return {
				p0 = { mob = { id = 5000, name = 'Scholar' } },
				p1 = { mob = { id = friendly_claim_id, name = 'Tank' } },
			}
		end,
		get_mob_by_target = function(token)
			assert_equal(token, 't', 'selected target token')
			return selected
		end,
		get_mob_array = function()
			return mobs
		end,
		get_mob_by_id = function(id)
			return mobs[tonumber(id)]
		end,
	},
}

package.loaded.uc_targeting_common = nil
package.loaded.uc_sch_skillchain_target = nil
local target_state = require('uc_sch_skillchain_target')

target_state.clear()
local picked, reason = target_state.select()
assert_true(type(picked) == 'table', 'party-claimed mob must be selected without a UI target: ' .. tostring(reason))
assert_equal(picked.id, 1001, 'party-claimed target without UI target')

local bound, bind_reason = target_state.bind(picked)
assert_true(bound, 'binding party-claimed target must succeed: ' .. tostring(bind_reason))
selected = mobs[1002]
local still_bound, bound_reason = target_state.select()
assert_true(type(still_bound) == 'table', 'changing UI target must not break the bound target: ' .. tostring(bound_reason))
assert_equal(still_bound.id, 1001, 'bound target must ignore UI target changes')

mobs[1001].claim_id = foreign_claim_id
local invalid, invalid_reason = target_state.select()
assert_equal(invalid, nil, 'lost friendly claim must invalidate bound target')
assert_equal(invalid_reason, 'target_not_party_claimed', 'lost-claim blocker')
local valid_bound, validate_reason = target_state.validate_bound({ require_cast_range = true })
assert_equal(valid_bound, false, 'dispatch validation must reject lost friendly claim')
assert_equal(validate_reason, 'target_not_party_claimed', 'dispatch lost-claim reason')

target_state.clear()
mobs[1001].claim_id = friendly_claim_id
selected = mobs[1002]
picked, reason = target_state.select()
assert_true(type(picked) == 'table', 'foreign selected target must fall back to friendly claim: ' .. tostring(reason))
assert_equal(picked.id, 1001, 'foreign UI target must not control Scholar chain')

target_state.clear()
selected = nil
mobs[1001].distance = 22 * 22
picked, reason = target_state.select()
assert_equal(picked, nil, 'out-of-range friendly claim must not spend Immanence')
assert_equal(reason, 'no_valid_party_claimed_target', 'out-of-range selection reason')

target_state.clear()
package.loaded.uc_sch_skillchain_target = original_skillchain_target
package.loaded.uc_targeting_common = original_targeting_common
_G.windower = original_windower

io.stdout:write('selftest_sch_skillchain_target: OK\n')
