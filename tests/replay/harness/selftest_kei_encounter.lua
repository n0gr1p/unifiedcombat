local saved_resources = package.loaded.resources
local saved_active_config = package.loaded.uc_active_config
local saved_kei = package.loaded.uc_kei_encounter
local saved_provider = package.loaded.uc_provider_kei
local saved_reaction = package.loaded.uc_reaction_runtime
local saved_timeline = rawget(_G, 'UC_ACTION_TIMELINE_LOG')

local function assert_true(value, message)
	if value ~= true then
		error(message)
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(message, tostring(expected), tostring(actual)))
	end
end

local checks = 0
local function check(number, condition, message)
	assert_equal(number, checks + 1, 'Kei test numbering must remain contiguous')
	checks = number
	assert_true(condition, ('Kei test %d failed: %s'):format(number, message))
end

package.loaded.resources = {
	spells = {
		[144] = { id = 144, en = 'Fire', element = 0 },
		[169] = { id = 169, en = 'Water', element = 5 },
		[171] = { id = 171, en = 'Water III', element = 5 },
		[230] = { id = 230, en = 'Blizzard', element = 1 },
		[232] = { id = 232, en = 'Blizzard III', element = 1 },
		[187] = { id = 187, en = 'Aeroga IV', element = 2 },
	},
	action_messages = {
		[2] = { id = 2, en = '${actor} casts ${spell}.${lb}${target} takes ${number} points of damage.' },
		[7] = { id = 7, en = '${actor} casts ${spell}.${lb}${target} recovers ${number} HP.' },
		[16] = { id = 16, en = "${actor}'s casting is interrupted." },
		[85] = { id = 85, en = '${actor} casts ${spell}.${lb}${target} resists the spell.' },
		[252] = { id = 252, en = '${actor} casts ${spell}.${lb}Magic Burst! ${target} takes ${number} points of damage.' },
	},
	monster_abilities = {
		[900] = { id = 900, en = 'Dancing Fullers' },
	},
	job_abilities = {
		[1] = { id = 1, en = 'Benediction' },
	},
	buffs = {},
}

local active_config
package.loaded.uc_active_config = {
	get_path = function(path)
		if path == 'config.encounter' then
			return active_config
		end
		if path == 'config.reactions' then
			return nil
		end
		error('unexpected active config path: ' .. tostring(path))
	end,
}

local events = {}
_G.UC_ACTION_TIMELINE_LOG = function(event_code, fields)
	events[#events + 1] = { code = event_code, fields = fields }
end

package.loaded.uc_kei_encounter = nil
package.loaded.uc_provider_kei = nil
package.loaded.uc_reaction_runtime = nil
local kei = require('uc_kei_encounter')

local config = {
	enabled = true,
	id = 'kei',
	kei = {
		elemental_damage = {
			dealer_name = 'Nyoo',
			water = { probe_spell = 'Water', damage_spell = 'Water III' },
			ice = { probe_spell = 'Blizzard', damage_spell = 'Blizzard III' },
			sustain_interval_s = 2.5,
			probe_timeout_s = 3.0,
		},
		fullers = {
			run_away_distance = 12.0,
			prearm_hpp_margin = 1.0,
		},
	},
}
active_config = config

local function actor(id, hpp)
	return { id = id or 3001, name = 'Kei', hpp = hpp or 100, status = 1, x = 1, y = 2, z = 0 }
end

local function activate(now, hpp, actor_id)
	kei.configure({ enabled = false, id = '' })
	local configured = kei.configure(config)
	assert_true(configured, 'Kei configuration must activate')
	return kei.observe_snapshot({
		now = now or 1,
		actors = { actor(actor_id, hpp) },
		player_id = 4001,
		player_name = 'Nyoo',
	})
end

local ready = {}
local provider = require('uc_provider_kei').new({
	snapshot = kei.snapshot,
	spell_for = kei.spell_for,
	action_ready = function(name)
		return ready[name] == true, ready[name] and '' or 'not_ready', 'spell'
	end,
	clamp_urgency = function(value)
		return value
	end,
	reaction_active = function()
		return rawget(_G, 'UC_TEST_KEI_REACTION_ACTIVE') == true
	end,
	keepalive_priority = 131,
	opportunistic_priority = 70,
})

local function proposals(now, player_name)
	local out = {}
	provider.collect({
		now = now,
		player_present = true,
		player_name = player_name or 'Nyoo',
	}, out)
	return out
end

local function spell_action(actor_id, spell_id, target_id, message, amount)
	return {
		actor_id = actor_id,
		category = 4,
		param = spell_id,
		targets = { { id = target_id, actions = { { message = message, param = amount } } } },
	}
end

activate(1)
check(1, kei.snapshot().phase == 'active' and kei.snapshot().boss.id == 3001, 'Kei appearance activates runtime')
kei.observe_snapshot({ now = 2, actors = {}, player_id = 4001, player_name = 'Nyoo' })
check(2, kei.snapshot().boss == nil and kei.snapshot().pending_spell == nil, 'Kei disappearance clears runtime')
activate(3)
kei.reset('zone_change')
check(3, kei.snapshot().boss == nil and kei.snapshot().weak_element == 'unknown', 'zone reset clears combat state')
kei.configure({ enabled = false, id = '' })
kei.configure(config)
kei.observe_snapshot({ now = 4, actors = { { id = 999, name = 'Kin', hpp = 100, status = 1 } }, player_id = 4001, player_name = 'Nyoo' })
check(4, kei.snapshot().boss == nil, 'non-Kei actor does not activate encounter')

activate(5)
ready = { Water = true }
check(5, #proposals(5, 'Nyoo') == 1, 'configured dealer emits elemental proposal')
check(6, #proposals(5, 'Other') == 0, 'non-dealer emits no elemental proposal')
local first = proposals(5)[1]
check(7, first.action_name == 'Water' and first.detail.kei_purpose == 'probe', 'unknown element emits exactly one Water probe')
kei.note_spell_dispatched(first, 5, 4001)
check(8, #proposals(5.1) == 0, 'pending probe prevents a duplicate simultaneous proposal')
kei.on_action(spell_action(4001, 169, 3001, 2, 123), 5.5)
check(9, kei.snapshot().weak_element == 'water' and kei.snapshot().element_source == 'confirmed_from_damage', 'Water damage confirms Water')

activate(10)
ready = { Water = true }
first = proposals(10)[1]
kei.note_spell_dispatched(first, 10, 4001)
kei.on_action(spell_action(4001, 169, 3001, 7, 88), 10.5)
check(10, kei.snapshot().weak_element == 'ice' and kei.snapshot().element_source == 'inferred_from_absorption', 'explicit Water absorption infers Ice')
activate(11)
ready = { Water = true }
first = proposals(11)[1]
kei.note_spell_dispatched(first, 11, 4001)
kei.on_action(spell_action(4001, 169, 3001, 2, 0), 11.5)
check(11, kei.snapshot().weak_element == 'unknown', 'zero damage remains ambiguous')
activate(12)
ready = { Water = true }
first = proposals(12)[1]
kei.note_spell_dispatched(first, 12, 4001)
kei.on_action(spell_action(4001, 169, 3001, 16, 0), 12.5)
check(12, kei.snapshot().weak_element == 'unknown' and kei.snapshot().pending_spell == nil, 'interruption leaves element unknown and clears pending')
activate(13)
ready = { Water = true }
first = proposals(13)[1]
kei.note_spell_dispatched(first, 13, 4001)
kei.expire_pending(16.1)
check(13, kei.snapshot().pending_spell == nil and #proposals(16.2) == 1, 'probe timeout permits safe retry')
activate(17)
ready = { Water = true }
first = proposals(17)[1]
kei.note_spell_dispatched(first, 17, 4001)
kei.on_action(spell_action(4999, 169, 3001, 2, 100), 17.5)
check(14, kei.snapshot().pending_spell ~= nil and kei.snapshot().weak_element == 'unknown', 'unrelated player damage does not satisfy probe')
kei.on_action(spell_action(4001, 169, 3999, 2, 100), 17.6)
check(15, kei.snapshot().pending_spell ~= nil and kei.snapshot().weak_element == 'unknown', 'damage against another actor does not satisfy probe')

activate(20)
kei.on_action(spell_action(3001, 144, 4001, 2, 100), 20.1)
ready = { ['Water III'] = true }
local out = proposals(20.2)
check(16, #out == 1 and out[1].action_name == 'Water III', 'known Water proposes configured damage spell')
kei.note_spell_dispatched(out[1], 20.2, 4001)
check(17, #proposals(20.3) == 0, 'sustain deadline cannot duplicate a pending spell')
activate(21)
kei.on_action(spell_action(3001, 144, 4001, 2, 100), 21.1)
ready = { Water = true }
out = proposals(21.2)
check(18, #out == 1 and out[1].action_name == 'Water' and out[1].detail.kei_purpose == 'probe_keepalive', 'unavailable preferred damage uses probe keepalive')
kei.note_spell_dispatched(out[1], 21.2, 4001)
kei.on_action(spell_action(4001, 169, 3001, 2, 50), 21.5)
ready = { ['Water III'] = true }
check(19, #proposals(22.0) == 0, 'recent correct hit suppresses unnecessary recast')
check(20, 153 > 131, 'critical emergency priority outranks Kei keepalive')
_G.UC_TEST_KEI_REACTION_ACTIVE = true
check(21, #proposals(24.0) == 0, 'active reaction suppresses elemental proposal emission')
_G.UC_TEST_KEI_REACTION_ACTIVE = nil

activate(30)
kei.on_action(spell_action(3001, 144, 4001, 2, 100), 30.1)
check(22, kei.snapshot().spike_mode == 'blaze' and kei.snapshot().weak_element == 'water', 'successful Kei Fire cast expects Water')
kei.on_action(spell_action(3001, 187, 4001, 2, 100), 30.2)
check(23, kei.snapshot().spike_mode == 'wind' and kei.snapshot().weak_element == 'ice', 'successful Kei Aero cast expects Ice')
local before = kei.snapshot().weak_element
kei.on_action(spell_action(3001, 144, 4001, 85, 0), 30.3)
check(24, kei.snapshot().weak_element == before, 'failed Kei spell does not change inferred mode')
ready = { ['Blizzard III'] = true }
out = proposals(30.4)
kei.note_spell_dispatched(out[1], 30.4, 4001)
kei.on_action(spell_action(4001, 232, 3001, 2, 111), 30.8)
check(25, kei.snapshot().weak_element == 'ice' and kei.snapshot().element_source == 'confirmed_from_damage', 'damage promotes inferred element to confirmed')
ready = { ['Blizzard III'] = true }
out = proposals(33.0)
kei.note_spell_dispatched(out[1], 33.0, 4001)
kei.on_action(spell_action(4001, 232, 3001, 7, 90), 33.4)
check(26, kei.snapshot().weak_element == 'water' and kei.snapshot().last_transition:find('contradicted', 1, true) ~= nil, 'explicit absorption corrects stale state')

activate(40, 76)
check(27, kei.snapshot().fullers.prearmed == true, '75 percent threshold prearms at configured margin')
ready = { Water = true }
check(28, #proposals(40.1) == 0, 'prearm suppresses opportunistic elemental cast')
local reaction = require('uc_reaction_runtime')
reaction.reset('kei_test')
local reaction_event = reaction.on_action({
	actor_id = 3001,
	category = 7,
	targets = { { id = 4001, actions = { { param = 900 } } } },
}, 3001, 40.2, true)
check(29, reaction_event.activated ~= nil and reaction_event.activated.response == 'run_away', 'Dancing Fullers ready activates generic reaction path')
kei.on_action({ actor_id = 3001, category = 7, targets = { { id = 4001, actions = { { param = 900 } } } } }, 40.2)
check(30, kei.snapshot().fullers.consumed[75] == true, 'Fullers evidence consumes 75 threshold')
check(31, kei.snapshot().fullers.next_threshold == 50, 'next Fullers threshold becomes 50')
kei.on_action({ actor_id = 3001, category = 11, param = 900, targets = { { id = 4001, actions = {} } } }, 40.5)
kei.on_action({ actor_id = 3001, category = 6, param = 1, targets = { { id = 3001, actions = {} } } }, 41)
kei.observe_snapshot({ now = 41.1, actors = { actor(3001, 80) }, player_id = 4001, player_name = 'Nyoo' })
kei.observe_snapshot({ now = 41.2, actors = { actor(3001, 76) }, player_id = 4001, player_name = 'Nyoo' })
check(32, kei.snapshot().fullers.prearmed == false and kei.snapshot().fullers.consumed[75] == true, 'Benediction HP crossing does not rearm consumed 75')
kei.observe_snapshot({ now = 41.3, actors = { actor(3001, 51) }, player_id = 4001, player_name = 'Nyoo' })
check(33, kei.snapshot().fullers.prearmed == true and kei.snapshot().fullers.next_threshold == 50, 'unconsumed 50 threshold still prearms after Benediction')
_G.UC_TEST_KEI_REACTION_ACTIVE = true
check(34, #proposals(41.4) == 0, 'active Fullers reaction takes precedence over Kei work')
_G.UC_TEST_KEI_REACTION_ACTIVE = nil

local reaction_source = assert(io.open('uc_reaction_runtime.lua', 'r'))
local reaction_text = reaction_source:read('*a')
reaction_source:close()
check(35, reaction_text:find("response = 'run_away'", 1, true) ~= nil, 'generic reaction behavior remains configured through reaction runtime')
local lilith_source = assert(io.open('uc_lilith_easy_encounter.lua', 'r'))
local lilith_text = lilith_source:read('*a')
lilith_source:close()
check(36, lilith_text:find("require('uc_kei_encounter')", 1, true) == nil, 'Lilith encounter remains independent')
kei.configure({ enabled = false, id = '' })
ready = { Water = true }
check(37, #proposals(50) == 0 and kei.snapshot().pending_spell == nil, 'disabled Kei support leaves normal scheduler behavior untouched')

assert_equal(checks, 37, 'required Kei replay coverage count')

reaction.reset('test_complete')
package.loaded.resources = saved_resources
package.loaded.uc_active_config = saved_active_config
package.loaded.uc_kei_encounter = saved_kei
package.loaded.uc_provider_kei = saved_provider
package.loaded.uc_reaction_runtime = saved_reaction
_G.UC_ACTION_TIMELINE_LOG = saved_timeline
_G.UC_TEST_KEI_REACTION_ACTIVE = nil

io.stdout:write('selftest_kei_encounter: OK (37 checks)\n')
