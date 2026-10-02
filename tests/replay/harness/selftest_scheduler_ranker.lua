local ranker = require('uc_scheduler_ranker')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local timeline = {}
local published_last_action = ''
local phase1 = {}
local duplicate_mode = 'normal'
local duplicate_result = false
local debug_enabled = false

local deps = {
	bool_setting = function(value, default_value)
		if value == nil then
			return default_value == true
		end
		return value == true
	end,
	required_setting_value = function(config, name)
		local values = type(config) == 'table' and config.required_settings or nil
		if type(values) == 'table' then
			return values[name]
		end
		return nil
	end,
	phase1 = phase1,
	pending_engage_live = function()
		return false
	end,
	pending_engage_state = function(phase)
		return phase.pending_engage
	end,
	priority_bypasses_engage = function(proposal)
		return type(proposal.priority_band) == 'number' and proposal.priority_band >= 90
	end,
	timeline_log = function(event, fields)
		timeline[#timeline + 1] = { event = event, fields = fields }
	end,
	pending_is_live_state = function(state)
		return state == 'sent'
	end,
	validate_engage_duplicate_retry = function()
		return duplicate_mode, { reason = 'fixture_duplicate' }
	end,
	duplicate_suppressed = function()
		return duplicate_result
	end,
	get_locks = function()
		return { action = false }
	end,
	hard_lock_reject = function(_, proposal)
		return tostring(proposal.fixture_lock_reject or '')
	end,
	reaction_blocks_proposal = function(_, proposal)
		return proposal.fixture_reaction_hold == true
	end,
	get_reaction_lock = function()
		return nil
	end,
	debug_enabled = function()
		return debug_enabled
	end,
	publish_last_action = function(value)
		published_last_action = value
	end,
	is_critical_defensive_proposal = function()
		return false
	end,
	encounter_validate_proposal = function(_, candidate)
		if candidate.fixture_encounter_reject == true then
			return false, 'encounter_water_damage'
		end
		return true, ''
	end,
	engage_dispatch_method = 'attack_on',
}

local function proposal(id, provider, band, urgency, expires_at)
	return {
		proposal_id = id,
		family_id = 'fixture.' .. id,
		provider = provider,
		action_type = 'ja',
		action_name = id,
		priority_band = band,
		urgency = urgency,
		created_at = 100,
		expires_at = expires_at,
		commit_deadline = 100.5,
		lock_class = 'offense_action',
	}
end

local ctx = {
	now = 100,
	settings = {},
	config = { required_settings = {} },
	player_status = 1,
}

local malformed_ok, malformed_reason = ranker.validate_proposal(ctx, {}, deps)
assert_equal(malformed_ok, false, 'malformed proposal rejected')
assert_equal(malformed_reason, 'malformed', 'malformed rejection reason')

local disabled = proposal('disabled', 'combat', 70, 0, 101)
disabled.required_setting = 'enabled'
local disabled_ok, disabled_reason = ranker.validate_proposal(ctx, disabled, deps)
assert_equal(disabled_ok, false, 'disabled proposal rejected')
assert_equal(disabled_reason, 'settings_disabled', 'disabled rejection reason')

ctx.settings.ability_active = false
ctx.config.required_settings.ability_active = true
local canonical_on = proposal('canonical_on', 'combat', 70, 0, 101)
canonical_on.required_setting = 'ability_active'
local canonical_on_ok, canonical_on_reason = ranker.validate_proposal(ctx, canonical_on, deps)
assert_equal(canonical_on_ok, true, 'canonical required setting true must beat flat false')
assert_equal(canonical_on_reason, '', 'canonical required setting true reason')

ctx.settings.ability_active = true
ctx.config.required_settings.ability_active = false
local canonical_off = proposal('canonical_off', 'combat', 70, 0, 101)
canonical_off.required_setting = 'ability_active'
local canonical_off_ok, canonical_off_reason = ranker.validate_proposal(ctx, canonical_off, deps)
assert_equal(canonical_off_ok, false, 'canonical required setting false must beat flat true')
assert_equal(canonical_off_reason, 'settings_disabled', 'canonical required setting false reason')
ctx.settings.ability_active = nil
ctx.config.required_settings.ability_active = nil

local stale = proposal('stale', 'combat', 70, 0, 101)
stale.created_at = 99
local stale_ok, stale_reason = ranker.validate_proposal(ctx, stale, deps)
assert_equal(stale_ok, false, 'stale proposal rejected')
assert_equal(stale_reason, 'stale_snapshot', 'stale rejection reason')

local encounter_rejected = proposal('encounter_rejected', 'combat', 70, 0, 101)
encounter_rejected.fixture_encounter_reject = true
local encounter_ok, encounter_reason = ranker.validate_proposal(ctx, encounter_rejected, deps)
assert_equal(encounter_ok, false, 'encounter policy proposal rejected')
assert_equal(encounter_reason, 'encounter_water_damage', 'encounter policy rejection reason')

phase1.pending = { state = 'sent', lock_class = 'support_action' }
local conflict = proposal('conflict', 'combat', 70, 0, 101)
local conflict_ok, conflict_reason = ranker.validate_proposal(ctx, conflict, deps)
assert_equal(conflict_ok, false, 'pending conflict rejected')
assert_equal(conflict_reason, 'pending_conflict', 'pending conflict reason')
phase1.pending = nil

duplicate_mode = 'suppressed'
local duplicate = proposal('duplicate', 'combat', 70, 0, 101)
local duplicate_ok, duplicate_reason = ranker.validate_proposal(ctx, duplicate, deps)
assert_equal(duplicate_ok, false, 'duplicate proposal rejected')
assert_equal(duplicate_reason, 'duplicate_suppressed', 'duplicate rejection reason')
assert_equal(duplicate._engage_duplicate_log_fields.reason, 'fixture_duplicate', 'duplicate fields')
duplicate_mode = 'normal'

local ranked, reject_counts, locks, rejected = ranker.rank(ctx, {
	proposal('z_provider', 'zeta', 70, 0.5, 101),
	proposal('b_id', 'alpha', 70, 0.5, 101),
	proposal('a_id', 'alpha', 70, 0.5, 101),
	proposal('expires_first', 'zeta', 70, 0.5, 100.8),
	proposal('highest_score', 'omega', 80, 0, 101),
	{
		proposal_id = 'reaction',
		family_id = 'fixture.reaction',
		provider = 'combat',
		action_type = 'ja',
		action_name = 'reaction',
		created_at = 100,
		expires_at = 101,
		fixture_reaction_hold = true,
	},
	proposal('locked', 'combat', 90, 0, 101),
}, deps)
ranked[1].fixture_lock_reject = nil
assert_equal(ranked[1].proposal_id, 'locked', 'highest band ranks first')
assert_equal(ranked[2].proposal_id, 'highest_score', 'next score ranks second')
assert_equal(ranked[3].proposal_id, 'expires_first', 'expiry tie-break')
assert_equal(ranked[4].proposal_id, 'a_id', 'provider then proposal id tie-break')
assert_equal(ranked[5].proposal_id, 'b_id', 'proposal id second')
assert_equal(ranked[6].proposal_id, 'z_provider', 'provider tie-break last')
assert_equal(reject_counts.reaction_hold, 1, 'reaction rejection counted')
assert_equal(rejected[1].reason, 'reaction_hold', 'reaction rejection captured')
assert_equal(locks.action, false, 'locks returned unchanged')
assert_equal(ranked[2]._score_parts.priority_band, 80, 'score parts preserved')
assert_equal(ranked[3]._score_parts.urgency_bonus, 4.95, 'urgency score preserved')

debug_enabled = true
local engage = proposal('engage', 'combat', 70, 0, 101)
engage.family_id = 'combat.engage.primary'
engage.action_type = 'engage'
local top = proposal('top', 'defensive_internal', 80, 0, 101)
ranker.rank(ctx, { engage, top }, deps)
assert_equal(
	published_last_action,
	'[p1]engage:rank_lost top=defensive_internal/fixture.top/ja score=80.00',
	'engage rank debug shape'
)
assert_equal(timeline[#timeline].event, 'ENGAGE_DISPATCH_BLOCKED', 'engage block log')

io.stdout:write('selftest_scheduler_ranker: OK\n')
