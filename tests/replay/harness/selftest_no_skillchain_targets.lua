local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_false(value, message)
	if value ~= false then
		error(message or 'expected false')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
	end
end

package.loaded['uc_no_skillchain_targets'] = nil
local targets = require('uc_no_skillchain_targets')

local settings = {}
assert_false(targets.is_name_blocked(settings, 'Gyre'), 'empty list must be a no-op')
assert_false(targets.is_mob_blocked(settings, { name = 'Gyre' }), 'empty list mob check must be a no-op')

local ok, reason = targets.append_name(settings, ' Gyre ')
assert_true(ok, 'Gyre should append')
assert_equal(reason, '', 'first append reason')
assert_equal(settings.weaponskill_no_skillchain_targets[1], 'Gyre', 'name must be trimmed')
assert_true(targets.is_name_blocked(settings, 'gyre'), 'matching must be case-insensitive')
assert_true(targets.is_mob_blocked(settings, { name = 'GYRE' }), 'mob matching must be case-insensitive')
assert_false(targets.is_name_blocked(settings, 'Lilith'), 'unlisted mob must remain a no-op')

local duplicate_ok, duplicate_reason = targets.append_name(settings, 'gYrE')
assert_true(duplicate_ok, 'duplicate append should be harmless')
assert_equal(duplicate_reason, 'NO_SKILLCHAIN_TARGET_ALREADY', 'duplicate reason mismatch')
assert_equal(#settings.weaponskill_no_skillchain_targets, 1, 'duplicate must not create a second entry')

assert_true(targets.append_name(settings, 'Other Add'), 'second target should append')
assert_equal(#targets.as_ordered_names(settings), 2, 'two target names expected')

local removed, remove_reason = targets.remove_index(settings, 1)
assert_true(removed, 'first target should remove')
assert_equal(remove_reason, '', 'remove reason mismatch')
assert_equal(settings.weaponskill_no_skillchain_targets[1], 'Other Add', 'remaining target mismatch')
assert_false(targets.is_name_blocked(settings, 'Gyre'), 'removed target must no longer match')

local core = assert(io.open('unified_combat_core.lua', 'rb')):read('*a')
assert_true(core:find("NO_SKILLCHAIN_TARGET_HOLD", 1, true) ~= nil,
	'core must expose a dedicated deny-list hold reason')
assert_true(core:find("core.revalidate_no_skillchain_target", 1, true) ~= nil,
	'core must revalidate the gate at dispatch time')
assert_true(core:find("uc_no_skillchain_targets.is_mob_blocked", 1, true) ~= nil,
	'core must scope the gate by current mob name')

print('selftest_no_skillchain_targets: OK')
