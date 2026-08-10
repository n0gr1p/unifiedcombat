local audit = require('tests.replay.harness.uc_encounter_field_log_audit')

local path = arg and arg[1] or nil
if type(path) ~= 'string' or path == '' then
	error('usage: lua tests/replay/harness/audit_sortie_encounter_field_log.lua <action_timeline_log>')
end

local file, open_error = io.open(path, 'r')
if file == nil then
	error('unable to open encounter field log: ' .. tostring(open_error))
end
local lines = {}
for line in file:lines() do
	lines[#lines + 1] = line
end
file:close()

local result = audit.analyze(lines)
local summary = audit.summary_lines(result)
for i = 1, #summary do
	io.stdout:write(summary[i] .. '\n')
end
if #result.ability_events == 0 then
	error('field log contains no ENCOUNTER_RAW_ABILITY_CANDIDATE events')
end
