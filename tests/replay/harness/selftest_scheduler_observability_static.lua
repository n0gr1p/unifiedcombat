local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local text = fh:read('*a')
	fh:close()
	return text
end

local function assert_contains(text, needle, label)
	if not text:find(needle, 1, true) then
		error((label or 'missing expected text') .. ': ' .. needle)
	end
end

local function assert_not_contains(text, needle, label)
	if text:find(needle, 1, true) then
		error((label or 'unexpected text') .. ': ' .. needle)
	end
end

local scheduler_source = read_file('unified_scheduler.lua')
local observability_source = read_file('uc_scheduler_observability.lua')

assert_contains(
	scheduler_source,
	"require('uc_scheduler_observability').publish_dryrun(",
	'dry-run publication must use observability facade'
)
assert_contains(
	scheduler_source,
	"require('uc_scheduler_observability').build_debug_overlay(phase, {",
	'debug overlay must use observability facade'
)
assert_contains(
	scheduler_source,
	"require('uc_scheduler_observability').build_enemy_effect_overlay(",
	'enemy overlay must use observability facade'
)
assert_contains(
	observability_source,
	'function M.build_debug_overlay(phase1, deps)',
	'observability facade must own debug formatting'
)
assert_not_contains(
	scheduler_source,
	'local function build_buff_up_lines()',
	'scheduler must not retain nested buff overlay formatter'
)
assert_not_contains(
	scheduler_source,
	'local function p1_format_top3(',
	'scheduler must not retain ranking formatter wrappers'
)

io.stdout:write('selftest_scheduler_observability_static: OK\n')
