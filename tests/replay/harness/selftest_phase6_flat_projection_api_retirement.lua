package.path = './?.lua;' .. package.path

local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_nil(value, message)
    if value ~= nil then error(message or ('expected nil, got ' .. tostring(value))) end
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then error(message or ('missing text: ' .. needle)) end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then error(message or ('unexpected text: ' .. needle)) end
end

local function read_all(path)
    local fh, err = io.open(path, 'rb')
    if not fh then error('failed to open ' .. tostring(path) .. ': ' .. tostring(err)) end
    local source = fh:read('*a')
    fh:close()
    return source
end

package.loaded.uc_active_config = nil
local active_config = require('uc_active_config')

assert_nil(active_config.project_flat_settings,
    'canonical->flat project_flat_settings API must remain retired')
assert_nil(active_config.sync_flat_settings_in_place,
    'flat full-table sync API must remain retired')
assert_true(type(active_config.build_active_profile_from_settings) == 'function',
    'separate flat->canonical compatibility builder must remain available for the later bootstrap cut')
assert_true(type(active_config.initialize_active_profile) == 'function',
    'separate initial addon bootstrap seam must remain explicitly tracked')

local active_source = read_all('uc_active_config.lua')
assert_not_contains(active_source, 'function M.project_' .. 'flat_settings',
    'uc_active_config must not reintroduce the projection API')
assert_not_contains(active_source, 'function M.sync_' .. 'flat_settings_in_place',
    'uc_active_config must not reintroduce the full-table sync API')
assert_not_contains(active_source, 'apply_structured_config_to_candidate',
    'retired canonical->flat serializer must stay deleted')
assert_not_contains(active_source, 'serialize_targeted_buffs',
    'projection-only defensive serializer must stay deleted')
assert_not_contains(active_source, 'serialize_brd_targeted_songs',
    'projection-only BRD serializer must stay deleted')
assert_not_contains(active_source, 'serialize_sch_storm_assignments',
    'projection-only SCH serializer must stay deleted')
assert_not_contains(active_source, 'resolve_party_member_ids_by_names',
    'projection-only durable-name->runtime-id list adapter must stay deleted')
assert_not_contains(active_source, 'resolve_configured_identity_id',
    'projection-only durable identity->runtime-id adapter must stay deleted')

for _, path in ipairs({
    'UnifiedCombat.lua',
    'remote_bridge.lua',
    'uc_profile_v2.lua',
}) do
    local source = read_all(path)
    assert_not_contains(source, 'project_' .. 'flat_settings(',
        path .. ' must not call retired canonical->flat projection')
    assert_not_contains(source, 'sync_' .. 'flat_settings_in_place(',
        path .. ' must not call retired full-table flat publication')
end

assert_contains(active_source, 'function M.build_active_profile_from_settings(settings, context)',
    'flat->canonical compatibility must remain distinct from retired canonical->flat projection')
assert_contains(active_source, 'function M.initialize_active_profile(settings, context)',
    'initial addon flat->canonical bootstrap must remain visible for the next dedicated cut')

print('selftest_phase6_flat_projection_api_retirement: OK (canonical->flat projection/sync API removed)')
