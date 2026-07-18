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

local function clamp_urgency(value)
    local num = tonumber(value) or 0
    if num < 0 then
        return 0
    end
    if num > 1 then
        return 1
    end
    return num
end

local function score(proposal)
    return (tonumber(proposal.priority_band) or 0) + (clamp_urgency(proposal.urgency) * 9.9)
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
    assert_contains(generic_slice, "local tank_mode = bool_setting(uc_scheduler_config.tank_enabled(ctx.settings), false)", 'generic configured JAs must read the tank flag for tank-mode weighting')
    assert_contains(generic_slice, "local priority_band = tank_mode and 99 or 70", 'tank-mode configured JAs must use the safer higher band without changing DPS baseline')
    assert_contains(generic_slice, "required_setting = 'ability_active'", 'generic configured JAs must keep the explicit setting dependency')

    assert_contains(tank_slice, "local pick = combat_core.select_tank_enmity_for_scheduler(ctx.settings)", 'tank-enmity lane must remain separate from generic configured JAs')
    assert_contains(tank_slice, "local prio = 96", 'tank-enmity lane must keep the higher tank priority band')
    assert_contains(tank_slice, "tank_enmity = true", 'tank-enmity lane must keep its tank-specific detail marker')

    local tank_configured_ja = {
        name = "tank configured JA",
        priority_band = 99,
        urgency = 0.35,
    }
    local low_urgency_tank_enmity = {
        name = "low urgency tank enmity",
        priority_band = 96,
        urgency = 0.60,
    }
    local urgent_tank_enmity = {
        name = "urgent tank enmity",
        priority_band = 96,
        urgency = 0.95,
    }
    local normal_ws = {
        name = "normal WS",
        priority_band = 70,
        urgency = 0.35,
    }
    local critical_cure = {
        name = "critical cure",
        priority_band = 117,
        urgency = 0.70,
    }
    local dps_configured_ja = {
        name = "dps configured JA",
        priority_band = 70,
        urgency = 0.35,
    }

    assert_true(score(tank_configured_ja) > score(low_urgency_tank_enmity), 'tank-mode configured JAs must outrank low-urgency tank-enmity actions')
    assert_true(score(tank_configured_ja) > score(normal_ws), 'tank-mode configured JAs must outrank normal WS-level offense')
    assert_true(score(urgent_tank_enmity) > score(tank_configured_ja), 'urgent tank-enmity actions must still outrank tank-mode configured JAs')
    assert_true(score(critical_cure) > score(tank_configured_ja), 'critical cure must still outrank tank-mode configured JAs')
    assert_true(score(dps_configured_ja) == score(normal_ws), 'DPS configured JAs must keep the existing baseline band')

    io.stdout:write('selftest_tank_configured_ja_starvation: OK\n')
end

main()
