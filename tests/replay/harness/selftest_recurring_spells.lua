package.path = './?.lua;' .. package.path

local recurring = require('uc_provider_recurring_spells')
local normalizer = require('uc_config_normalizer_base')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s (expected=%s actual=%s)'):format(message, tostring(expected), tostring(actual)))
	end
end

local function assert_true(value, message)
	if value ~= true then error(message) end
end

local active = {}
local ready = {
	['Absorb-TP'] = false,
	['Absorb-STR'] = true,
}
local provider = recurring.new({
	bool_setting = function(value, default)
		if value == nil then return default end
		return value == true
	end,
	active_value_or_flat = function(path, flat)
		local value = active[path]
		if value ~= nil then return value end
		return flat
	end,
	get_spell_resource = function(name)
		local spells = {
			['Absorb-TP'] = { id = 275, en = 'Absorb-TP', targets = 32, range = 4 },
			['Absorb-STR'] = { id = 266, en = 'Absorb-STR', targets = 32, range = 4 },
			['Cure'] = { id = 1, en = 'Cure', targets = { Self = true, Party = true }, range = 4 },
		}
		return spells[name]
	end,
	action_ready = function(name)
		return ready[name] == true, ready[name] and 'READY' or 'RECAST', 'spell'
	end,
	action_effective_range = function() return 20.9 end,
	clamp_urgency = function(value) return value end,
	combat_domain_enabled = function() return true end,
	action_timeline_log = function() end,
	build_friendly_claims = function()
		return { 1001 }, { [1001] = true }
	end,
	priority_band = 70,
})

local old_engine = rawget(_G, 'Start_Engine')
_G.Start_Engine = true

local function collect(status, target)
	local out = {}
	provider.collect({
		now = 12.5,
		settings = {
			recurring_spells_enabled = true,
			recurring_spells = 'Absorb-TP|Absorb-STR',
		},
		player_present = true,
		player = { status = status },
		target_present = target ~= nil,
		target = target,
	}, out)
	return out
end

local target = {
	id = 900,
	name = 'Colibri',
	valid_target = true,
	spawn_type = 16,
	hpp = 100,
	claim_id = 1001,
}

local proposals = collect(1, target)
assert_equal(#proposals, 1, 'first ready configured spell must emit one proposal')
assert_equal(proposals[1].action_name, 'Absorb-STR', 'provider must fall through spells on recast')
assert_equal(proposals[1].provider, 'combat', 'recurring spells must reuse combat dispatch lifecycle')
assert_equal(proposals[1].family_id, 'combat.recurring_spell.primary', 'recurring spell family')
assert_equal(proposals[1].action_type, 'spell', 'recurring action type')
assert_equal(proposals[1].target_id, 900, 'recurring target id')
assert_equal(proposals[1].priority_band, 70, 'recurring spell priority')
assert_equal(proposals[1].movement_policy, 'must_stop', 'recurring spells require cast settle')
assert_equal(proposals[1].detail.allow_target_id_send, true, 'recurring spells must support target-id dispatch')
assert_equal(proposals[1].detail.require_current_target, true, 'recurring spells must require the selected mob to remain current at dispatch')
assert_equal(proposals[1].detail.require_friendly_claim, true, 'recurring spells must revalidate friendly claim at dispatch')
assert_equal(proposals[1].detail.configured_index, 2, 'configured ordering must be preserved')

ready['Absorb-TP'] = true
proposals = collect(1, target)
assert_equal(proposals[1].action_name, 'Absorb-TP', 'first ready spell in the configured order must win')
assert_equal(proposals[1].detail.configured_index, 1, 'first configured spell index')

assert_equal(#collect(0, target), 1, 'recurring spells may fire while unengaged against the current friendly-claimed target')
assert_equal(#collect(1, nil), 0, 'recurring spells require a current target')

local unclaimed_target = {
	id = 901,
	name = 'Unclaimed Colibri',
	valid_target = true,
	spawn_type = 16,
	hpp = 100,
	claim_id = 0,
}
assert_equal(#collect(0, unclaimed_target), 0, 'recurring spells must reject unclaimed current targets')

local foreign_claimed_target = {
	id = 902,
	name = 'Foreign Colibri',
	valid_target = true,
	spawn_type = 16,
	hpp = 100,
	claim_id = 2002,
}
assert_equal(#collect(0, foreign_claimed_target), 0, 'recurring spells must reject targets claimed outside the friendly claim set')

active['config.combat.recurring_spells.enabled'] = false
assert_equal(#collect(1, target), 0, 'canonical disabled setting must override flat compatibility setting')
active = {}

local nested = normalizer.normalize({
	combat = {
		recurring_spells = {
			enabled = true,
			list = { 'Absorb-TP', 'Absorb-STR' },
		},
	},
})
assert_true(nested.combat.recurring_spells.enabled, 'structured recurring spells enabled must normalize')
assert_equal(nested.combat.recurring_spells.list[1], 'Absorb-TP', 'structured recurring spell order 1')
assert_equal(nested.combat.recurring_spells.list[2], 'Absorb-STR', 'structured recurring spell order 2')

local flat = normalizer.normalize({
	recurring_spells_enabled = true,
	recurring_spells = 'Absorb-TP|Absorb-STR',
})
assert_true(flat.combat.recurring_spells.enabled, 'flat recurring spells enabled must normalize')
assert_equal(flat.combat.recurring_spells.list[2], 'Absorb-STR', 'flat recurring spell list must normalize')

local ok = pcall(function()
	normalizer.normalize({
		combat = { recurring_spells = { enabled = true, list = {} } },
	})
end)
assert_true(not ok, 'enabled recurring spells must require at least one configured spell')

_G.Start_Engine = old_engine

local scheduler_file = assert(io.open('./unified_scheduler.lua', 'r'))
local scheduler_source = scheduler_file:read('*a')
scheduler_file:close()
assert_true(scheduler_source:find('scheduler.PRIORITY_BAND_RECURRING_SPELL = 70', 1, true) ~= nil, 'recurring spell priority band missing')
assert_true(scheduler_source:find('scheduler.providers.recurring_spells.collect(ctx, out)', 1, true) ~= nil, 'recurring spell provider collection missing')
assert_true(scheduler_source:find("scheduler.providers.recurring_spells = require('uc_provider_recurring_spells').new({", 1, true) ~= nil, 'recurring spell provider initialization missing')
assert_true(scheduler_source:find("require_current_target == true", 1, true) ~= nil, 'recurring spell dispatch must revalidate the current target')
assert_true(scheduler_source:find("require_friendly_claim == true", 1, true) ~= nil, 'recurring spell dispatch must revalidate friendly claim ownership')

io.stdout:write('selftest_recurring_spells: OK\n')
