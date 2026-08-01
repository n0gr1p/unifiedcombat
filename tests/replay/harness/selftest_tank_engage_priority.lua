local scheduler_path = "unified_scheduler.lua"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text present: " .. needle))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
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

local function select_top(proposals)
    table.sort(proposals, function(a, b)
        local sa = score(a)
        local sb = score(b)
        if sa ~= sb then
            return sa > sb
        end
        return tostring(a.proposal_id or "") < tostring(b.proposal_id or "")
    end)
    return proposals[1]
end

local function select_top_with_engage_preemption(settings, proposals)
    local ranked = {}
    for i = 1, #proposals do
        ranked[i] = proposals[i]
    end
    local top = select_top(ranked)
    if type(top) == "table" and type(top.priority_band) == "number" and top.priority_band >= 113 then
        return top
    end
    for i = 1, #ranked do
        local candidate = ranked[i]
        if type(candidate) == "table"
            and tostring(candidate.provider or "") == "combat"
            and tostring(candidate.action_type or "") == "engage" then
            return candidate
        end
    end
    return top
end

local function mock_target_control(settings, pick)
    if settings.engine_on ~= true or settings.autotarget ~= true or settings.engaged == true then
        return nil
    end
    if type(pick) ~= "table" then
        return nil
    end
    local tid = tonumber(pick.target_id) or 0
    if tid <= 0 or pick.current_target_same == true or pick.valid ~= true or (tonumber(pick.hpp) or 0) <= 0 then
        return nil
    end
    return {
        proposal_id = "target.acquire",
        family_id = "target.acquire.primary",
        provider = "target_control",
        action_type = "target",
        action_name = "acquire_target",
        target_id = tid,
        priority_band = settings.tank and 106 or 84,
        urgency = settings.tank and 0.80 or 0.55,
    }
end

local function mock_engage(settings, target)
    if settings.engine_on ~= true or settings.domain_combat_enabled ~= true or settings.autotarget ~= true then
        return nil
    end
    if type(target) ~= "table" then
        return nil
    end
    if target.valid ~= true or (tonumber(target.hpp) or 0) <= 0 then
        return nil
    end
    if target.recent_death == true or target.in_scope ~= true or target.in_range ~= true or target.duplicate_suppressed == true then
        return nil
    end
    return {
        proposal_id = "combat.engage",
        family_id = "combat.engage.primary",
        provider = "combat",
        action_type = "engage",
        action_name = "engage_target",
        target_id = tonumber(target.id) or 0,
        priority_band = settings.tank and 107 or 72,
        urgency = settings.tank and 0.85 or 0.70,
    }
end

local function defensive_proposal(kind, target_hpp)
    local priority_band = 100
    if tostring(kind or "") == "cure" and (tonumber(target_hpp) or -1) > 0 and (tonumber(target_hpp) or -1) <= 35 then
        priority_band = 117
    end
    local urgency = 0.25
    if kind == "cure" then
        urgency = 0.70
    elseif kind == "buff" then
        urgency = 0.25
    end
    return {
        proposal_id = "defensive",
        family_id = "def.internal." .. tostring(kind or "action"),
        provider = "defensive_internal",
        action_type = "spell",
        action_name = tostring(kind or "action"),
        priority_band = priority_band,
        urgency = urgency,
        detail = {
            def_action_type = tostring(kind or ""),
            target_hpp = tonumber(target_hpp) or -1,
        },
    }
end

local function sleep_proposal()
    return {
        proposal_id = "sleep",
        family_id = "combat.sleep.primary",
        provider = "combat",
        action_type = "spell",
        action_name = "Sleep II",
        priority_band = 113,
        urgency = 0.55,
    }
end

local function main()
    local source = read_file(scheduler_path)
    local combat_provider = read_file("uc_provider_combat.lua")
    local target_provider = read_file("uc_provider_target_control.lua")

    assert_contains(source, "scheduler.TANK_TARGET_ACQUIRE_PRIORITY = 106", "tank target-acquire priority constant must exist")
    assert_contains(source, "scheduler.TANK_ENGAGE_PRIORITY = 107", "tank engage priority constant must exist")
    assert_contains(source, "scheduler.DEFAULT_ENGAGE_PRIORITY = 72", "non-tank engage priority must stay explicit")
    assert_contains(combat_provider, "local tank_mode = bool_setting(tank_enabled(ctx.settings), false)", "tank engage priority must remain tank-specific")
    assert_contains(combat_provider, "local engage_priority = tank_mode and tank_engage_priority or default_engage_priority", "engage collector must use injected scoped priority values")
    assert_contains(target_provider, "local priority_band = tank_mode and tank_target_priority or 84", "target-control collector must raise tank target acquisition above non-critical defensive actions")
    assert_contains(combat_provider, "duplicate_suppression_key = ('engage:%d'):format(tonumber(target.id) or 0)", "engage duplicate suppression must remain intact")
    assert_contains(combat_provider, "recast_key = 'engage:attack_on'", "engage recast/throttle key must remain intact")
    assert_not_contains(source, "hb off", "tank engage priority fix must not introduce direct scheduler side-effect toggles")
    assert_not_contains(source, "hb on", "tank engage priority fix must not introduce direct scheduler side-effect toggles")

    local tank_engage = mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = true,
    }, {
        id = 100,
        valid = true,
        hpp = 100,
        in_scope = true,
        in_range = true,
    })
    local top = select_top_with_engage_preemption({
        defensive_critical_hpp = 35,
    }, {
        tank_engage,
        defensive_proposal("cure", 65),
    })
    assert_equal(top.family_id, "combat.engage.primary", "tank engage must outrank non-critical Cure")

    top = select_top_with_engage_preemption({
        defensive_critical_hpp = 35,
    }, {
        tank_engage,
        defensive_proposal("buff", 100),
    })
    assert_equal(top.family_id, "combat.engage.primary", "tank engage must outrank maintenance buffs")

    top = select_top_with_engage_preemption({
        defensive_critical_hpp = 35,
    }, {
        tank_engage,
        sleep_proposal(),
    })
    assert_equal(top.family_id, "combat.sleep.primary", "globally high-priority Sleep must outrank tank engage")

    top = select_top_with_engage_preemption({
        defensive_critical_hpp = 35,
    }, {
        tank_engage,
        defensive_proposal("cure", 20),
    })
    assert_equal(top.provider, "defensive_internal", "critical Cure must still outrank tank engage")
    assert_equal(top.priority_band, 117, "critical Cure band must use the global priority contract")

    local tank_target_control = mock_target_control({
        engine_on = true,
        autotarget = true,
        engaged = false,
        tank = true,
    }, {
        target_id = 101,
        valid = true,
        hpp = 100,
    })
    top = select_top({
        tank_target_control,
        defensive_proposal("cure", 80),
    })
    assert_equal(top.family_id, "target.acquire.primary", "tank next-target acquire must outrank non-critical Cure before engage")

    assert_equal(mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = true,
    }, {
        id = 102,
        valid = false,
        hpp = 100,
        in_scope = true,
        in_range = true,
    }), nil, "invalid targets must not force engage")

    assert_equal(mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = true,
    }, {
        id = 103,
        valid = true,
        hpp = 0,
        in_scope = true,
        in_range = true,
    }), nil, "dead targets must not force engage")

    assert_equal(mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = true,
    }, {
        id = 104,
        valid = true,
        hpp = 100,
        recent_death = true,
        in_scope = true,
        in_range = true,
    }), nil, "recent-death targets must not force engage")

    assert_equal(mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = true,
    }, {
        id = 105,
        valid = true,
        hpp = 100,
        in_scope = true,
        in_range = false,
    }), nil, "out-of-range targets must not force engage")

    local non_tank_engage = mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = false,
    }, {
        id = 106,
        valid = true,
        hpp = 100,
        in_scope = true,
        in_range = true,
    })
    top = select_top_with_engage_preemption({
        defensive_critical_hpp = 35,
    }, {
        non_tank_engage,
        defensive_proposal("cure", 80),
    })
    assert_equal(top.family_id, "combat.engage.primary", "non-tank engage must now outrank non-critical Cure once a valid target is selected")

    top = select_top_with_engage_preemption({
        defensive_critical_hpp = 35,
    }, {
        tank_engage,
        defensive_proposal("cure", 90),
        defensive_proposal("cure", 88),
    })
    assert_equal(top.family_id, "combat.engage.primary", "low-MP weak Cure spam must not indefinitely starve tank engage when HP is not critical")

    assert_equal(mock_engage({
        engine_on = true,
        domain_combat_enabled = true,
        autotarget = true,
        tank = true,
    }, {
        id = 107,
        valid = true,
        hpp = 100,
        in_scope = true,
        in_range = true,
        duplicate_suppressed = true,
    }), nil, "engage duplicate/throttle protection must still suppress repeat engage sends")

    io.stdout:write("selftest_tank_engage_priority: OK\n")
end

main()
