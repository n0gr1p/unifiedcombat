local function read_file(path)
	local fh, err = io.open(path, 'r')
	if not fh then
		error('unable to read ' .. tostring(path) .. ': ' .. tostring(err))
	end
	local content = fh:read('*a')
	fh:close()
	return content
end

local function assert_contains(content, needle, message)
	if content:find(needle, 1, true) == nil then
		error(message or ('missing ' .. tostring(needle)))
	end
end

local function assert_not_contains(content, needle, message)
	if content:find(needle, 1, true) ~= nil then
		error(message or ('unexpected ' .. tostring(needle)))
	end
end

local migrated = {
	'uc_provider_food.lua',
	'uc_provider_recurring_spells.lua',
	'uc_provider_defensive.lua',
	'uc_provider_enemy_buff_removal.lua',
	'uc_provider_enemy_debuff_maintenance.lua',
	'uc_provider_maintenance.lua',
	'uc_hb_buff_maint.lua',
	'uc_cor_maintenance.lua',
	'uc_geo_camp_placement.lua',
	'uc_raise_accept.lua',
	'uc_recovery_hold.lua',
}

for _, path in ipairs(migrated) do
	local source = read_file(path)
	assert_not_contains(source, 'UC_SETTINGS', path .. ' must not read flat global settings')
	assert_not_contains(source, 'ctx.settings', path .. ' must not read flat scheduler settings')
	assert_not_contains(source, 'active_value_or_flat(', path .. ' must not retain flat fallback helper')
end

for _, path in ipairs({
	'uc_provider_food.lua',
	'uc_provider_recurring_spells.lua',
	'uc_provider_defensive.lua',
	'uc_provider_enemy_buff_removal.lua',
	'uc_provider_enemy_debuff_maintenance.lua',
}) do
	assert_contains(read_file(path), 'ctx.config', path .. ' must consume the canonical scheduler snapshot')
end

local maintenance = read_file('uc_provider_maintenance.lua')
assert_contains(maintenance, 'cor_propose(ctx.config)', 'COR maintenance provider must receive canonical config')

local hb = read_file('uc_hb_buff_maint.lua')
assert_contains(hb, 'function mod.choose(config, members, helpers)', 'HB buff maintenance must receive canonical config explicitly')
assert_contains(hb, "type(config.defensive) == 'table'", 'HB buff maintenance must read canonical defensive config')

local cor = read_file('uc_cor_maintenance.lua')
assert_contains(cor, 'function mod.propose(config)', 'COR maintenance must receive canonical config explicitly')
assert_contains(cor, "type(config.maintenance) == 'table'", 'COR maintenance must read canonical maintenance config')
assert_contains(cor, 'abilities.configured', 'COR ability fallback must stay inside canonical config')

local scheduler = read_file('unified_scheduler.lua')
assert_contains(
	scheduler,
	"hb_buff_maint.choose(type(ctx.config) == 'table' and ctx.config or {}, buff_members",
	'scheduler must pass canonical config to defensive buff maintenance'
)

local raise_accept = read_file('uc_raise_accept.lua')
assert_contains(raise_accept, "config.ownership.auto_accept_raise", 'raise acceptance must read canonical ownership config')

local recovery = read_file('uc_recovery_hold.lua')
assert_contains(recovery, "config.ownership.pause_automation_while_weakened", 'recovery hold must read canonical ownership config')

local geo = read_file('uc_geo_camp_placement.lua')
assert_contains(geo, "config.maintenance.geo", 'GEO camp placement must read canonical maintenance config')

io.stdout:write('selftest_phase2_canonical_leaf_consumers: OK\n')
