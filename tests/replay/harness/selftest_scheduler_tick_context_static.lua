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

local source = read_file('unified_scheduler.lua')

assert_contains(
	source,
	"local ctx = require('uc_scheduler_context').build(settings, scheduler.phase1, {",
	'scheduler context wrapper must use the extracted builder'
)

local process_tick = source:match(
	"function scheduler%.process_tick%(cadence%)(.-)function scheduler%.on_ipc_message"
)
if type(process_tick) ~= 'string' then
	error('failed to capture scheduler.process_tick')
end
assert_contains(process_tick, 'local tick_ctx = nil', 'tick context cache missing')
assert_contains(process_tick, 'local function get_tick_ctx()', 'tick context accessor missing')
assert_contains(process_tick, 'tick_ctx = p1_build_ctx(s)', 'tick context must be built once')
assert_contains(
	process_tick,
	'scheduler.p1_try_nonblocking_target_acquire(s, target_ctx)',
	'target acquisition must receive the shared context'
)
assert_contains(
	process_tick,
	'p1_run_dry(s, get_tick_ctx())',
	'ranking path must receive the shared context'
)

local provider_files = {
	'uc_provider_combat.lua',
	'uc_provider_defensive.lua',
	'uc_provider_enemy_buff_removal.lua',
	'uc_provider_maintenance.lua',
	'uc_provider_tank_enmity.lua',
	'uc_provider_target_control.lua',
	'uc_pet_combat_provider.lua',
	'uc_smn_maintenance.lua',
	'uc_smn_pet_combat_adapter.lua',
}
local provider_parts = {}
for _, path in ipairs(provider_files) do
	provider_parts[#provider_parts + 1] = read_file(path)
end
local provider_block = table.concat(provider_parts, '\n')
assert_not_contains(
	provider_block,
	'windower.ffxi.get_',
	'proposal providers must not resample Windower world state'
)
assert_not_contains(
	provider_block,
	'now_s()',
	'proposal providers must use the tick-stable context time'
)

io.stdout:write('selftest_scheduler_tick_context_static: OK\n')
