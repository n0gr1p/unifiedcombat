package.path = './?.lua;' .. package.path

local sch_config = require('uc_sch_config')
local provider_module = require('uc_provider_sch_maintenance')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local function assert_true(value, message)
	assert_equal(value, true, message)
end

local function assert_false(value, message)
	assert_equal(value, false, message)
end

local function assert_contains(source, needle, message)
	if not source:find(needle, 1, true) then
		error(message or ('missing text: ' .. needle))
	end
end

local function assert_not_contains(source, needle, message)
	if source:find(needle, 1, true) then
		error(message or ('unexpected text: ' .. needle))
	end
end

local function read_all(path)
	local fh = assert(io.open(path, 'rb'))
	local source = fh:read('*a')
	fh:close()
	return source
end

local canonical = sch_config.default_config()
canonical.enabled = true
canonical.arts.minimum_commit_s = 27
canonical.arts.emergency_off_art_casts = false
canonical.sublimation.enabled = true
canonical.sublimation.release_when_mpp_at_most = 38
canonical.sublimation.release_when_complete = true
canonical.sublimation.minimum_hpp_to_activate = 82
canonical.support.regen.enabled = true
canonical.support.regen.minimum_coverage = 5
canonical.support.regen.refresh_before_s = 41
canonical.support.storms.enabled = true
canonical.support.storms.refresh_before_s = 47
canonical.support.storms.assignments = {
	{ spell = 'Thunderstorm II', targets = { 'Tester' } },
}
canonical.defensive.accession_cure.enabled = true
canonical.defensive.accession_cure.minimum_members = 4
canonical.defensive.accession_cure.member_hpp_at_most = 68
canonical.defensive.accession_cure.minimum_total_missing_hp = 3200
canonical.defensive.accession_status_removal.enabled = true
canonical.defensive.accession_status_removal.minimum_members = 3
canonical.defensive.rapture.enabled = true
canonical.defensive.rapture.minimum_missing_hp = 2100
canonical.defensive.penury.enabled = true
canonical.defensive.penury.maximum_mpp = 39
canonical.offense.skillchain.enabled = true
canonical.offense.skillchain.plans = {
	{ result = 'Fragmentation', opener = 'Blizzard', closer = 'Water' },
}

local compatibility = sch_config.default_config()
compatibility.enabled = false
compatibility.arts.minimum_commit_s = 1
compatibility.sublimation.release_when_mpp_at_most = 90
compatibility.support.regen.minimum_coverage = 1
compatibility.support.storms.refresh_before_s = 5
compatibility.defensive.accession_cure.minimum_members = 2
compatibility.defensive.penury.maximum_mpp = 90

local ctx = {
	config = {
		profile = { main_job = 'SCH' },
		sch = canonical,
		defensive = {
			cure = { ignore_trusts = false },
			thresholds = { critical_hpp = 37 },
		},
	},
	settings = {
		sch = compatibility,
		def_heal_ignore_trusts = true,
		defensive_critical_hpp = 99,
	},
}

local resolved = provider_module.config_from_context(ctx)
assert_true(resolved.enabled, 'canonical SCH enabled must beat compatibility disabled')
assert_equal(resolved.arts.minimum_commit_s, 27, 'canonical Arts commit duration')
assert_false(resolved.arts.emergency_off_art_casts, 'canonical off-Art emergency policy')
assert_true(resolved.sublimation.enabled, 'canonical Sublimation enabled')
assert_equal(resolved.sublimation.release_when_mpp_at_most, 38, 'canonical Sublimation threshold')
assert_true(resolved.sublimation.release_when_complete, 'canonical complete Sublimation release')
assert_equal(resolved.sublimation.minimum_hpp_to_activate, 82, 'canonical Sublimation HPP floor')
assert_true(resolved.support.regen.enabled, 'canonical Regen enabled')
assert_equal(resolved.support.regen.minimum_coverage, 5, 'canonical Regen coverage')
assert_equal(resolved.support.regen.refresh_before_s, 41, 'canonical Regen refresh')
assert_true(resolved.support.storms.enabled, 'canonical Storm enabled')
assert_equal(resolved.support.storms.refresh_before_s, 47, 'canonical Storm refresh')
assert_equal(resolved.support.storms.assignments[1].spell, 'Thunderstorm II', 'canonical Storm assignment')
assert_true(resolved.defensive.accession_cure.enabled, 'canonical Accession Cure enabled')
assert_equal(resolved.defensive.accession_cure.minimum_members, 4, 'canonical Accession Cure members')
assert_equal(resolved.defensive.accession_cure.member_hpp_at_most, 68, 'canonical Accession Cure HPP')
assert_equal(resolved.defensive.accession_cure.minimum_total_missing_hp, 3200, 'canonical Accession Cure missing HP')
assert_true(resolved.defensive.accession_status_removal.enabled, 'canonical Accession status enabled')
assert_equal(resolved.defensive.accession_status_removal.minimum_members, 3, 'canonical Accession status members')
assert_true(resolved.defensive.rapture.enabled, 'canonical Rapture enabled')
assert_equal(resolved.defensive.rapture.minimum_missing_hp, 2100, 'canonical Rapture threshold')
assert_true(resolved.defensive.penury.enabled, 'canonical Penury enabled')
assert_equal(resolved.defensive.penury.maximum_mpp, 39, 'canonical Penury threshold')
assert_true(resolved.offense.skillchain.enabled, 'canonical skillchain enabled')
assert_equal(resolved.offense.skillchain.plans[1].result, 'Fragmentation', 'canonical skillchain plan')

local provider_source = read_all('uc_provider_sch_maintenance.lua')
local scheduler_source = read_all('unified_scheduler.lua')
assert_not_contains(provider_source, 'ctx.settings', 'SCH provider must not consume compatibility scheduler settings')
assert_not_contains(provider_source, 'settings.sch', 'SCH provider must not source job config from projected settings')
assert_contains(provider_source, 'local config = M.config_from_context(ctx)', 'SCH provider must use canonical context adapter')
assert_contains(provider_source, 'ignore_trusts(root_config)', 'SCH trust filtering must use canonical common config')
assert_contains(provider_source, 'is_critical_defensive(out[proposal_index], root_config)',
	'SCH critical defensive classification must use canonical common config')
assert_contains(provider_source, 'root_config.defensive.thresholds.critical_hpp',
	'SCH defensive threshold must come from canonical common config')
assert_contains(scheduler_source, 'is_critical_defensive = function(proposal, config)',
	'SCH critical defensive dependency must accept explicit canonical config')
assert_contains(scheduler_source, 'ignore_trusts = function(config)',
	'SCH trust-filter dependency must accept explicit canonical config')
assert_not_contains(scheduler_source, 'settings.def_heal_ignore_trusts',
	'SCH wiring must not read the flat defensive trust mirror')

print('selftest_phase4_sch_authority: OK (canonical SCH provider authority)')
