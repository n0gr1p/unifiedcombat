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

local original_target = package.loaded.uc_sch_skillchain_target
local original_runtime = package.loaded.uc_sch_skillchain_runtime

package.loaded.uc_sch_skillchain_target = {
	bind = function()
		return true, ''
	end,
	clear = function()
	end,
}
package.loaded.uc_sch_skillchain_runtime = nil

local capabilities = require('uc_sch_capabilities')
local runtime_module = require('uc_sch_skillchain_runtime')
local dark_arts = capabilities.abilities.dark_arts.buff_id
local addendum_black = capabilities.abilities.addendum_black.buff_id
local immanence = capabilities.abilities.immanence.buff_id

local function config(closer)
	return {
		enabled = true,
		offense = {
			skillchain = {
				enabled = true,
				plans = {
					{ result = 'Fusion', closer = closer or 'Ionohelix II' },
				},
			},
		},
	}
end

local function target()
	return {
		id = 1001,
		name = 'Locus Camelopard',
		hpp = 100,
		valid_target = true,
	}
end

local function opener(properties, opts)
	opts = opts or {}
	return {
		generation = opts.generation or 7,
		active_properties = properties or { 'Liquefaction' },
		chainbound_level = 0,
		terminal = opts.terminal == true,
		earliest_close_at = opts.earliest_close_at or 101,
		preferred_execute_at = opts.preferred_execute_at or 102,
		latest_safe_at = opts.latest_safe_at or 106,
		expires_at = opts.expires_at or opts.latest_safe_at or 106,
		magic_burst_expires_at = opts.magic_burst_expires_at or 0,
	}
end

local function input(now, selected_config, snapshot, charges, buffs)
	return {
		now = now,
		config = selected_config,
		engine_enabled = true,
		maintenance_enabled = true,
		critical_cure_present = false,
		standard_sequence_active = false,
		target = target(),
		player_buffs = buffs or { dark_arts },
		skillchain_snapshot = snapshot,
		charge_snapshot = {
			confidence = 'confirmed',
			estimated_available = charges,
		},
	}
end

-- A party-provided Liquefaction opener is compatible with the configured
-- Ionohelix II Impaction closer. Even with an existing MB window, SCH should
-- adopt it and reserve only one Immanence charge.
local adopted = runtime_module.new()
local party_open = opener({ 'Liquefaction' }, { magic_burst_expires_at = 108 })
assert_true(adopted:update(input(100, config('Ionohelix II'), party_open, 1)),
	'compatible party opener must start with one charge')
local adopted_snapshot = adopted:snapshot()
assert_true(adopted_snapshot.active.opportunistic_close == true,
	'party opener must be marked as an opportunistic close')
assert_equal(adopted_snapshot.active.opener_generation, 7,
	'party opener generation must become the close baseline')
assert_equal(adopted_snapshot.active.phase, 'wait_closer_timing',
	'party opener must skip our opener phases')
assert_equal(adopted_snapshot.last_result, 'started_party_close:Fusion',
	'party-close diagnostic mismatch')

assert_true(adopted:update(input(101, config('Ionohelix II'), party_open, 1)),
	'party closer timing update must remain active')
local immanence_step, immanence_reason = adopted:next_step(101)
assert_true(type(immanence_step) == 'table',
	'party close must offer closer Immanence: ' .. tostring(immanence_reason))
assert_equal(immanence_step.action_name, 'Immanence', 'party close first charged action')
assert_equal(immanence_step.phase, 'use_immanence_closer', 'party close must skip opener Immanence')
assert_equal(immanence_step.required_available_charges, 1,
	'party close must reserve only one charge when Addendum is unnecessary')
assert_true(adopted:note_dispatched(immanence_step, 101), 'closer Immanence dispatch must be accepted')

assert_true(adopted:update(input(101.2, config('Ionohelix II'), party_open, 1, { dark_arts, immanence })),
	'confirmed closer Immanence must advance')
local closer_step, closer_reason = adopted:next_step(101.2)
assert_true(type(closer_step) == 'table',
	'party close must offer configured closer: ' .. tostring(closer_reason))
assert_equal(closer_step.action_name, 'Ionohelix II', 'party close must use configured exact closer')
assert_equal(closer_step.target_id, 1001, 'party close must retain bound enemy ID')
assert_true(adopted:note_dispatched(closer_step, 101.2), 'closer spell dispatch must be accepted')

local fusion_result = opener({ 'Fusion' }, {
	generation = 8,
	earliest_close_at = 103,
	preferred_execute_at = 104,
	latest_safe_at = 108,
	magic_burst_expires_at = 112,
})
assert_true(adopted:update(input(102, config('Ionohelix II'), fusion_result, 0, { dark_arts })),
	'confirmed Fusion result must complete adopted chain')
assert_equal(adopted:snapshot().active, nil, 'adopted chain must complete after Fusion evidence')

-- Do not stomp a live party opener that our configured closer cannot turn into
-- the requested result. Wait for the foreign window to change/expire instead.
local incompatible = runtime_module.new()
local induration = opener({ 'Induration' })
assert_equal(incompatible:update(input(100, config('Ionohelix II'), induration, 2)), false,
	'incompatible live opener must not start our own chain')
assert_equal(incompatible:snapshot().last_blocker, 'existing_skillchain_window_incompatible',
	'incompatible party opener blocker')

-- Once that incompatible window is gone, ordinary self-opening behavior still
-- requires both Immanence charges.
local expired = opener({ 'Induration' }, { latest_safe_at = 99, expires_at = 99 })
assert_equal(incompatible:update(input(100, config('Ionohelix II'), expired, 1)), false,
	'normal self-chain must not start with only one charge')
assert_equal(incompatible:snapshot().last_blocker, 'insufficient_confirmed_charges',
	'normal two-charge fallback blocker')

-- Tier IV/V closers still need Addendum: Black. Opportunistic closing saves the
-- opener charge, so Dark Arts + Thunder V requires exactly two charges total:
-- one Addendum: Black and one closer Immanence.
local high_tier = runtime_module.new()
assert_true(high_tier:update(input(100, config('Thunder V'), party_open, 2, { dark_arts })),
	'party close needing Addendum must start with two charges')
local addendum_step, addendum_reason = high_tier:next_step(100)
assert_true(type(addendum_step) == 'table',
	'party close must request Addendum: Black: ' .. tostring(addendum_reason))
assert_equal(addendum_step.action_name, 'Addendum: Black', 'high-tier party-close prerequisite')
assert_equal(addendum_step.required_available_charges, 2,
	'party close Addendum reservation must account for only Addendum + closer Immanence')

-- With Addendum already active, the same high-tier party close needs only the
-- closer Immanence charge.
local high_tier_ready = runtime_module.new()
assert_true(high_tier_ready:update(input(100, config('Thunder V'), party_open, 1, { dark_arts, addendum_black })),
	'Addendum-ready high-tier party close must start with one charge')
assert_equal(high_tier_ready:snapshot().active.phase, 'wait_closer_timing',
	'Addendum-ready party close must go directly to closer timing')

-- A terminal chain cannot be extended; preserve the existing MB hold instead.
local terminal = runtime_module.new()
local terminal_snapshot = opener({ 'Liquefaction' }, {
	terminal = true,
	magic_burst_expires_at = 108,
})
assert_equal(terminal:update(input(100, config('Ionohelix II'), terminal_snapshot, 3)), false,
	'terminal chain must not be adopted')
assert_equal(terminal:snapshot().last_blocker, 'existing_magic_burst_window',
	'terminal chain must retain MB hold behavior')

-- No existing party opener keeps the original two-charge self-chain path.
local normal = runtime_module.new()
assert_true(normal:update(input(100, config('Ionohelix II'), nil, 2)),
	'normal autonomous chain must still start with two charges')
local normal_step, normal_reason = normal:next_step(100)
assert_true(type(normal_step) == 'table',
	'normal autonomous chain must offer opener Immanence: ' .. tostring(normal_reason))
assert_equal(normal_step.phase, 'use_immanence_opener', 'normal chain must retain opener phase')
assert_equal(normal_step.required_available_charges, 2, 'normal opener must reserve both chain charges')

package.loaded.uc_sch_skillchain_runtime = original_runtime
package.loaded.uc_sch_skillchain_target = original_target

io.stdout:write('selftest_sch_skillchain_party_close: OK\n')