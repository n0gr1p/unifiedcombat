local function read_file(path)
    local fh, err = io.open(path, 'r')
    if not fh then
        error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
    end
    local text = fh:read('*a')
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ('missing expected text: ' .. needle))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or 'assert_true failed')
    end
end

local function main()
    local source = read_file('unified_scheduler.lua')
    local generic_ja_pos = source:find('local function p1_collect_combat_ja(ctx, out)', 1, true)
    local tank_enmity_pos = source:find('local function p1_collect_combat_tank_enmity(ctx, out)', 1, true)
    local maintenance_pos = source:find('local function p1_collect_maintenance(ctx, out)', 1, true)

    assert_true(generic_ja_pos ~= nil, 'generic configured-JA collector must exist')
    assert_true(tank_enmity_pos ~= nil, 'tank-enmity collector must exist')
    assert_true(maintenance_pos ~= nil, 'maintenance collector must exist')
    assert_true(tank_enmity_pos < generic_ja_pos, 'tank-enmity collector must still run before generic configured JAs')

    local generic_slice = source:sub(generic_ja_pos, maintenance_pos - 1)
    local tank_slice = source:sub(tank_enmity_pos, generic_ja_pos - 1)

    assert_contains(generic_slice, "if not bool_setting(ctx.settings.ability_active, false) then", 'generic configured JAs must stay gated by ability_active')
    assert_contains(generic_slice, "local ordered = ability_pipeline.collect_ordered(ctx.settings, 6)", 'generic configured JAs must still come from the configured ability list')
    assert_contains(generic_slice, "priority_band = 70", 'generic configured JAs must keep their lower combat priority band')
    assert_contains(generic_slice, "required_setting = 'ability_active'", 'generic configured JAs must keep the explicit setting dependency')

    assert_contains(tank_slice, "local pick = combat_core.select_tank_enmity_for_scheduler(ctx.settings)", 'tank-enmity lane must remain separate from generic configured JAs')
    assert_contains(tank_slice, "local prio = 96", 'tank-enmity lane must keep the higher tank priority band')
    assert_contains(tank_slice, "tank_enmity = true", 'tank-enmity lane must keep its tank-specific detail marker')

    io.stdout:write('selftest_tank_configured_ja_starvation: OK\n')
end

main()
