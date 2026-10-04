package.path = './?.lua;' .. package.path

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

local runtime_files = {
    'uc_smn_maintenance.lua',
    'uc_smn_pet_combat_adapter.lua',
    'uc_pup_runtime.lua',
    'uc_pup_pet_combat_adapter.lua',
    'uc_provider_sch_maintenance.lua',
    'uc_geo_maintenance.lua',
    'uc_provider_maintenance.lua',
    'uc_brd_maintenance.lua',
    'uc_cor_maintenance.lua',
}

for _, path in ipairs(runtime_files) do
    local source = read_all(path)
    assert_not_contains(source, 'ctx.settings', path .. ' must not consume scheduler compatibility settings')
    assert_not_contains(source, 'UC_SETTINGS', path .. ' must not consume flat global settings')
    assert_not_contains(source, 'uc_active_config', path .. ' must not resample active config at action time')
    assert_not_contains(source, 'active_value_or_flat', path .. ' must not retain active/flat fallback helpers')
end

local smn_maint = read_all('uc_smn_maintenance.lua')
local smn_pet = read_all('uc_smn_pet_combat_adapter.lua')
assert_contains(smn_maint, 'runtime.config_from_config(ctx.config)', 'SMN maintenance canonical reader')
assert_contains(smn_pet, 'runtime.config_from_config(ctx.config)', 'SMN pet-combat canonical reader')

local pup_runtime = read_all('uc_pup_runtime.lua')
local pup_pet = read_all('uc_pup_pet_combat_adapter.lua')
assert_contains(pup_runtime, 'M.config_from_config(ctx.config)', 'PUP runtime canonical observation reader')
assert_contains(pup_pet, 'runtime.config_from_config(ctx.config)', 'PUP pet-combat canonical reader')

local sch = read_all('uc_provider_sch_maintenance.lua')
assert_contains(sch, 'local config = M.config_from_context(ctx)', 'SCH canonical context adapter')
assert_contains(sch, 'root_config.defensive.thresholds.critical_hpp', 'SCH shared defensive canonical threshold')

local geo = read_all('uc_geo_maintenance.lua')
assert_contains(geo, 'local config = M.config_from_context(ctx)', 'GEO canonical context adapter')
assert_contains(geo, 'target_is_ignored(ctx.config, mob)', 'GEO canonical target-ignore context')

local provider = read_all('uc_provider_maintenance.lua')
assert_contains(provider, "require_table(maintenance_config.brd, 'ctx.config.maintenance.brd')",
    'BRD canonical maintenance subtree')
assert_contains(provider, "require_table(combat_config.pulling, 'ctx.config.combat.pulling')",
    'BRD canonical pulling dependency')
assert_contains(provider, 'local action = cor_propose(ctx.config)',
    'COR provider must route canonical root by identity')

local cor = read_all('uc_cor_maintenance.lua')
assert_contains(cor, 'local cor = cor_config(config)', 'COR runtime explicit canonical config')
assert_contains(cor, 'for _, a in ipairs(configured_abilities(config)) do',
    'COR configured-ability fallback must use canonical root')

print('selftest_phase4_exit_audit: OK (SMN/PUP/SCH/GEO/BRD/COR runtime authority)')
