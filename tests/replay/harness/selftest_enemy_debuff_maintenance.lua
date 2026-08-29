local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

local spells = {
	[23] = { id = 23, en = 'Dia', status = 134, targets = 32 },
	[24] = { id = 24, en = 'Dia II', status = 134, targets = 32, overwrites = { 23, 230 } },
	[25] = { id = 25, en = 'Dia III', status = 134, targets = 32, overwrites = { 23, 24, 230, 231 } },
	[230] = { id = 230, en = 'Bio', status = 135, targets = 32, overwrites = { 23 } },
	[232] = { id = 232, en = 'Bio III', status = 135, targets = 32, overwrites = { 23, 24, 25, 230, 231 } },
	[882] = { id = 882, en = 'Distract III', status = 148, targets = 32, overwrites = { 841, 842 } },
}

local spells_by_name = {}
for _, spell in pairs(spells) do
	spells_by_name[spell.en] = spell
end

local effects = {}
local attempts_blocked = {}
local settings = {
	defensive_enabled = true,
	def_maintain_enemy_debuffs = true,
	defensive_enemy_debuffs = 'Dia III|Distract III',
}

local function distance(value)
	return setmetatable({ value = value }, {
		__index = {
			sqrt = function(self) return self.value end,
		},
	})
end

local provider = require('uc_provider_enemy_debuff_maintenance').new({
	bool_setting = function(value) return value == true end,
	active_value_or_flat = function(_, flat_value) return flat_value end,
	get_spell_resource = function(name) return spells_by_name[name] end,
	get_spell_by_id = function(id) return spells[id] end,
	build_friendly_claims = function() return { 1001 }, { [1001] = true } end,
	claim_valid = function(claim_id, claim_set) return claim_set[claim_id] == true end,
	effect_map = function() return effects end,
	prune_expired = function() end,
	can_attempt = function(action_name, target_id, effect_id)
		local key = table.concat({ action_name, target_id, effect_id }, ':')
		return attempts_blocked[key] ~= true, key
	end,
	action_ready = function() return true, '', 'spell' end,
	build_action_command = function(action_name, _, target)
		return ('input /ma "%s" %d'):format(action_name, target.id)
	end,
	clamp_urgency = function(value) return value end,
	log = function() end,
})

local function context(target_id)
	return {
		now = 50,
		settings = settings,
		target_id_snapshot = target_id or 0,
		mobs_by_id = {
			[2001] = { id = 2001, name = 'Near Mob', valid_target = true, spawn_type = 16, hpp = 80, claim_id = 1001, distance = distance(8) },
			[2002] = { id = 2002, name = 'Party Mob', valid_target = true, spawn_type = 16, hpp = 90, claim_id = 1001, distance = distance(14) },
			[2003] = { id = 2003, name = 'Foreign Mob', valid_target = true, spawn_type = 16, hpp = 100, claim_id = 9999, distance = distance(3) },
			[2004] = { id = 2004, name = 'Far Mob', valid_target = true, spawn_type = 16, hpp = 100, claim_id = 1001, distance = distance(22) },
		},
	}
end

local out = {}
provider.collect(context(2002), out)
assert_equal(#out, 1, 'missing debuff must emit one proposal')
assert_equal(out[1].action_name, 'Dia III', 'configured order must set action priority')
assert_equal(out[1].target_id, 2002, 'eligible current target should win target tie-break without being required')
assert_equal(out[1].provider, 'defensive_internal', 'proposal must use established defensive dispatcher')
assert_equal(out[1].priority_band, 99, 'enemy debuff must remain below cure and status-removal band')

out = {}
provider.collect(context(0), out)
assert_equal(out[1].target_id, 2001, 'backline character with no current target must use nearest party-claimed mob')

effects = {
	[2001] = { [134] = { action_id = 25 } },
	[2002] = { [134] = { action_id = 25 } },
}
out = {}
provider.collect(context(0), out)
assert_equal(out[1].action_name, 'Distract III', 'confirmed first debuff must advance to next configured debuff')

settings.defensive_enemy_debuffs = 'Dia II'
effects = {
	[2001] = { [134] = { action_id = 25 } },
	[2002] = { [134] = { action_id = 25 } },
}
out = {}
provider.collect(context(0), out)
assert_equal(#out, 0, 'stronger observed tier must satisfy configured weaker tier')

settings.defensive_enemy_debuffs = 'Dia III'
effects = {
	[2001] = { [134] = { action_id = 24 } },
	[2002] = { [134] = { action_id = 24 } },
}
out = {}
provider.collect(context(0), out)
assert_equal(#out, 1, 'weaker observed tier must be eligible for configured upgrade')

effects = {
	[2001] = { [134] = { action_id = 0 } },
	[2002] = { [134] = { action_id = 0 } },
}
out = {}
provider.collect(context(0), out)
assert_equal(#out, 0, 'unknown observed tier identity must block unsafe overwrite')

effects = {}
attempts_blocked['Dia III:2001:134'] = true
attempts_blocked['Dia III:2002:134'] = true
out = {}
provider.collect(context(0), out)
assert_equal(#out, 0, 'per-target attempt gates must suppress retry spam')

settings.defensive_enemy_debuffs = 'Dia III|Bio III'
local conflict_ok = pcall(function()
	provider.collect(context(0), {})
end)
assert_equal(conflict_ok, false, 'mutually overwriting configured debuffs must fail fast')

settings.def_maintain_enemy_debuffs = false
settings.defensive_enemy_debuffs = 'Dia III'
out = {}
provider.collect(context(0), out)
assert_equal(#out, 0, 'disabled maintenance must emit nothing')

print('selftest_enemy_debuff_maintenance: OK')
