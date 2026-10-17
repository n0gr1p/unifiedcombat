local function assert_true(value, message)
    if value ~= true then error(message or ('expected true, got ' .. tostring(value))) end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
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

local function count_literal(source, literal)
    local count = 0
    local from = 1
    while true do
        local first, last = source:find(literal, from, true)
        if not first then return count end
        count = count + 1
        from = last + 1
    end
end

package.path = './?.lua;' .. package.path
package.loaded.uc_config_runtime = nil
local runtime = require('uc_config_runtime')

local published = {
    schema_version = 1,
    ok = true,
    available = true,
    normalizer_version = 1,
    source = 'UC_PROFILE_V2',
    character = 'Tester',
    main_job = 'WAR',
    sub_job = 'DNC',
    domains = { 'combat', 'follow' },
    warnings = {},
    errors = {},
}

local cloned = runtime.config_contract_status(nil, nil, false, published)
assert_true(type(cloned) == 'table', 'published status clone must be returned without settings')
assert_true(cloned ~= published, 'published status accessor must clone instead of exposing mutable source')
assert_equal(cloned.ok, true, 'published status clone must preserve ok')
assert_equal(cloned.source, 'UC_PROFILE_V2', 'published status clone must preserve source')
assert_equal(cloned.character, 'Tester', 'published status clone must preserve character')
assert_equal(cloned.domains[1], 'combat', 'published status clone must preserve domains')
cloned.domains[1] = 'changed'
assert_equal(published.domains[1], 'combat', 'published status nested values must be cloned')

local bridge = read_all('remote_bridge.lua')
local expected_call =
    'config_contract_status = uc_config_runtime.config_contract_status(nil, nil, nil, _G.UC_CONFIG_CONTRACT_STATUS),'

assert_equal(count_literal(bridge, expected_call), 2,
    'both bridge state/options snapshots must clone published config status explicitly')
assert_not_contains(bridge, 'config_contract_status(_G.UC_SETTINGS)',
    'bridge config status must not normalize or read flat settings')
assert_not_contains(bridge, 'config_contract_status = _G.UC_CONFIG_CONTRACT_STATUS',
    'bridge must not expose the mutable published global directly')
assert_equal(count_literal(bridge, 'UC_SETTINGS'), 0,
    'remote bridge must now contain zero direct UC_SETTINGS references')
assert_equal(count_literal(bridge, 'project_flat_settings('), 0,
    'bridge config publication must contain no canonical-to-flat projection')
assert_equal(count_literal(bridge, 'sync_flat_settings_in_place('), 0,
    'bridge must not republish flat settings')

print('selftest_phase6_bridge_status_decoupling: OK (published config status no longer depends on flat settings)')
