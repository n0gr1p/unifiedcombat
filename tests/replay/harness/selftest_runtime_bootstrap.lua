package.path = './?.lua;./?/?.lua;' .. package.path

package.loaded.uc_runtime_bootstrap = nil
local bootstrap = require('uc_runtime_bootstrap')

local function assert_true(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
	end
end

local resource_marker = { keep = true }
package.loaded.resources = resource_marker
package.loaded.uc_runtime_bootstrap_test_stale = { stale = true }
package.loaded.unified_runtime_bootstrap_test_stale = { stale = true }
package.loaded.remote_bridge = { stale = true }

local status = bootstrap.begin({ addon_path = './' })
assert_true(package.loaded.uc_runtime_bootstrap == bootstrap, 'bootstrap must preserve its fresh module instance')
assert_equal(package.loaded.uc_runtime_bootstrap_test_stale, nil, 'uc_* module must be purged')
assert_equal(package.loaded.unified_runtime_bootstrap_test_stale, nil, 'unified_* module must be purged')
assert_equal(package.loaded.remote_bridge, nil, 'remote_bridge must be purged')
assert_true(package.loaded.resources == resource_marker, 'non-UnifiedCombat modules must not be purged')
assert_true(type(status.source_fingerprint) == 'string' and #status.source_fingerprint == 8, 'source fingerprint must be present')
assert_true(type(status.files) == 'table' and status.files['unified_scheduler.lua'] ~= nil, 'scheduler file fingerprint must be present')
assert_true(status.purged_count >= 3, 'purge count must include injected stale modules')

local ok, finalized = bootstrap.finalize(status, {
	scheduler = { runtime_revision = bootstrap.EXPECTED_SCHEDULER_REVISION },
	engine = { runtime_revision = bootstrap.EXPECTED_ENGINE_REVISION },
})
assert_true(ok, 'matching runtime revisions must pass integrity')
assert_true(finalized.integrity_ok, 'matching runtime revisions must mark integrity ok')
assert_true(bootstrap.summary_line(finalized):find('integrity=ok', 1, true) ~= nil, 'summary must report integrity')
assert_true(#bootstrap.status_lines(finalized) > 2, 'status detail must include file fingerprints')

local bad_status = bootstrap.begin({ addon_path = './' })
local bad_ok, bad = bootstrap.finalize(bad_status, {
	scheduler = { runtime_revision = 'stale-scheduler' },
	engine = { runtime_revision = bootstrap.EXPECTED_ENGINE_REVISION },
})
assert_true(not bad_ok, 'stale scheduler revision must fail integrity')
assert_true(bad.integrity_error:find('scheduler expected=', 1, true) ~= nil, 'scheduler mismatch must be explicit')

print('runtime bootstrap self-test: ok')
