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
local state_source = read_file('uc_scheduler_enemy_effect_state.lua')

assert_contains(
	scheduler_source,
	"require('uc_scheduler_enemy_effect_state').load_dispel_map(windower.addon_path)",
	'scheduler must initialize extracted enemy state'
)
assert_contains(
	scheduler_source,
	"require('uc_scheduler_enemy_effect_state').ingest_raw_action(",
	'raw 0x028 ingestion must route through extracted enemy state'
)
assert_contains(
	scheduler_source,
	"require('uc_scheduler_enemy_effect_state').is_raw_death_message(mid)",
	'raw death messages must route through extracted enemy state'
)
assert_contains(
	state_source,
	'function M.effect_map(phase1)',
	'extracted module must own effectiveTargets state'
)
assert_contains(
	state_source,
	'function M.ingest_raw_action(phase1, data_or_action, deps)',
	'extracted module must own raw action ingestion'
)
assert_not_contains(
	scheduler_source,
	'local dispellable_enemy_effect_set =',
	'scheduler must not retain dispellable effect state'
)
assert_not_contains(
	scheduler_source,
	'local enemy_effect_observed_once =',
	'scheduler must not retain unknown-effect observation state'
)

io.stdout:write('selftest_scheduler_enemy_effect_state_static: OK\n')
