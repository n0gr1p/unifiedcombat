local audit = require('tests.replay.harness.skillchain_field_log_audit')

local path = tostring(arg and arg[1] or '')
if path == '' then
	error('usage: lua tests/replay/harness/audit_scheduler_owned_ws_skillchain_field_log.lua <log> [minimum_dispatches] [non_aeonic]')
end

local result = audit.audit_file(path, {
	minimum_dispatches = tonumber(arg[2]) or 5,
	expect_non_aeonic = tostring(arg[3] or '') == 'non_aeonic',
})

io.stdout:write(('field_log=%s sessions=%d dispatches=%d ultimate_predictions=%d after_preferred_min=%s before_latest_min=%s\n'):format(
	path,
	result.session_count,
	result.dispatch_count,
	result.ultimate_predictions,
	result.after_preferred_min and ('%.3f'):format(result.after_preferred_min) or 'n/a',
	result.before_latest_min and ('%.3f'):format(result.before_latest_min) or 'n/a'
))

if not result.ok then
	for i = 1, #result.failures do
		io.stdout:write('FAIL: ' .. result.failures[i] .. '\n')
	end
	error('scheduler-owned WS skillchain field log audit failed')
end

io.stdout:write('audit_scheduler_owned_ws_skillchain_field_log: PASS\n')
