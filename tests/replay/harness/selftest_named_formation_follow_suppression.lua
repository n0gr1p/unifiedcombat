local function read_file(path)
    local handle = assert(io.open(path, 'r'))
    local content = handle:read('*a')
    handle:close()
    return content
end

local function assert_contains(source, needle, message)
    if not source:find(needle, 1, true) then
        error((message or 'assert_contains failed') .. ': missing ' .. needle)
    end
end

local function assert_not_contains(source, needle, message)
    if source:find(needle, 1, true) then
        error((message or 'assert_not_contains failed') .. ': unexpected ' .. needle)
    end
end

local function main()
    local source = read_file('uc_party_follow.lua')
    local start_pos = assert(source:find('local function formation_movement_active()', 1, true), 'formation_movement_active missing')
    local end_pos = assert(source:find('\nend\n', start_pos, true), 'formation_movement_active end missing') + 4
    local body = source:sub(start_pos, end_pos)

    assert_contains(body, "local status = rawget(_G, 'UC_FORMATION_STATUS')", 'formation suppression must use runtime formation status')
    assert_contains(body, "local movement_domain_enabled = uc_active_config.get_path('config.ownership.domain_movement_enabled')", 'formation suppression must honor movement domain')
    assert_contains(body, "status.enabled == true", 'active runtime formation must be enabled')
    assert_contains(body, "tostring(status.phase or '') == 'active'", 'active runtime formation phase must gate suppression')
    assert_not_contains(body, "config.movement.formation", 'named formations must not require the base formation config to be enabled')
    assert_not_contains(body, "formation.enabled == true", 'named formations must not require the base formation flag')

    assert_contains(source, "if formation_movement_active() then\n\t\tclear_follow_needs_catchup()", 'active named formation must clear Party Follow catch-up state')

    print('selftest_named_formation_follow_suppression: OK')
end

main()
