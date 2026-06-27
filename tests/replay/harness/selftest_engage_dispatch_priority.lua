local scheduler_path = "unified_scheduler.lua"
local action_state_path = "uc_scheduler_action_state.lua"

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

local function assert_close(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error((message or "assert_close failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
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

local function sort_proposals(proposals)
    table.sort(proposals, function(a, b)
        local sa = score(a)
        local sb = score(b)
        if sa ~= sb then
            return sa > sb
        end
        return tostring(a.proposal_id or "") < tostring(b.proposal_id or "")
    end)
    return proposals
end

local function mock_engage(settings, target)
    if settings.scheduler_dark_launch_combat ~= true or settings.autotarget ~= true then
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
        priority_band = 110
    end
    local urgency = 0.25
    if kind == "cure" then
        urgency = 0.70
    elseif kind == "buff" then
        urgency = 0.25
    end
    return {
        proposal_id = "defensive." .. tostring(kind or "action"),
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
        priority_band = 94,
        urgency = 0.55,
    }
end

local function is_critical_defensive(settings, proposal)
    if type(proposal) ~= "table" then
        return false
    end
    if tostring(proposal.provider or "") ~= "defensive_internal" and tostring(proposal.provider or "") ~= "defensive_healbot" then
        return false
    end
    local detail = type(proposal.detail) == "table" and proposal.detail or {}
    if tostring(proposal.action_type or "") ~= "spell" or tostring(detail.def_action_type or "") ~= "cure" then
        return false
    end
    local threshold = tonumber(settings.defensive_critical_hpp) or 35
    local target_hpp = tonumber(detail.target_hpp) or -1
    return target_hpp > 0 and target_hpp <= threshold
end

local function pick_preemptive_engage(settings, proposals)
    local ranked = sort_proposals(proposals)
    local top = ranked[1]
    if is_critical_defensive(settings, top) then
        return top
    end
    for i = 1, #ranked do
        local candidate = ranked[i]
        if tostring(candidate.provider or "") == "combat" and tostring(candidate.action_type or "") == "engage" then
            return candidate
        end
    end
    return top
end

package.loaded["uc_scheduler_action_state"] = nil
local action_state = dofile(action_state_path)

local now_value = 0

local function now_s()
    return now_value
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local action_state_source = read_file(action_state_path)

    assert_contains(scheduler_source, "function scheduler.p1_pick_preemptive_engage(ctx, ranked)", "scheduler must define engage preemption helper")
    assert_contains(scheduler_source, "function scheduler.p1_is_critical_defensive_proposal(settings, selected)", "scheduler must define critical defensive engage exception helper")
    assert_contains(scheduler_source, "local engage_candidate = scheduler.p1_pick_preemptive_engage(ctx, ranked)", "dry-run selection must consider engage preemption")
    assert_contains(scheduler_source, "scheduler.p1_is_critical_defensive_proposal(ctx and ctx.settings or nil, top)", "engage preemption must keep the critical Cure exception")
    assert_contains(scheduler_source, "function scheduler.clear_local_spell_success(meta)", "scheduler must expose generic spell-success release helper")
    assert_contains(scheduler_source, "function scheduler.clear_local_spell_interruption(meta)", "scheduler must expose generic spell-interruption release helper")
    assert_contains(scheduler_source, "scheduler.clear_local_spell_success(release_meta)", "scheduler action-message handling must shorten generic local spell success lockout")
    assert_contains(scheduler_source, "scheduler.clear_local_spell_interruption(release_meta)", "scheduler action-message handling must shorten generic local spell interruption lockout")
    assert_contains(scheduler_source, "scheduler.p1_clear_tank_spell_wait_state(phase)", "scheduler action-message handling must clear tank spell wait on matching local spell completion")
    assert_contains(action_state_source, "function M.clear_local_spell_success", "action-state module must define generic spell-success release helper")
    assert_contains(action_state_source, "function M.clear_local_spell_interruption", "action-state module must define generic spell-interruption release helper")

    local helper_block = scheduler_source:match("function scheduler%.p1_pick_preemptive_engage%(ctx, ranked%)(.-)\nend\n\nfunction scheduler%.on_incoming_chunk")
    assert_true(type(helper_block) == "string", "failed to capture engage preemption helper block")
    assert_not_contains(helper_block, "windower.send_command", "engage preemption helper must not introduce direct command side-effect calls")
    assert_not_contains(helper_block, "windower.ffxi.run", "engage preemption helper must not introduce direct run side-effect calls")

    local settings = {
        scheduler_dark_launch_combat = true,
        autotarget = true,
        tank = true,
        defensive_critical_hpp = 35,
    }
    local target = {
        id = 200,
        valid = true,
        hpp = 100,
        in_scope = true,
        in_range = true,
    }
    local engage = assert(mock_engage(settings, target), "expected engage candidate")

    local selected = pick_preemptive_engage(settings, {
        engage,
        defensive_proposal("cure", 80),
    })
    assert_equal(selected.family_id, "combat.engage.primary", "selected valid target plus non-critical Cure must prefer engage")

    selected = pick_preemptive_engage(settings, {
        engage,
        defensive_proposal("buff", 100),
    })
    assert_equal(selected.family_id, "combat.engage.primary", "selected valid target plus maintenance/self-buff must prefer engage")

    selected = pick_preemptive_engage(settings, {
        engage,
        sleep_proposal(),
    })
    assert_equal(selected.family_id, "combat.engage.primary", "selected valid target plus Sleep must prefer engage")

    selected = pick_preemptive_engage(settings, {
        engage,
        defensive_proposal("cure", 20),
    })
    assert_equal(selected.provider, "defensive_internal", "critical Cure must still outrank engage")

    local non_tank_settings = {
        scheduler_dark_launch_combat = true,
        autotarget = true,
        tank = false,
        defensive_critical_hpp = 35,
    }
    selected = pick_preemptive_engage(non_tank_settings, {
        assert(mock_engage(non_tank_settings, target), "expected non-tank engage candidate"),
        defensive_proposal("cure", 75),
    })
    assert_equal(selected.family_id, "combat.engage.primary", "non-tank prompt engage must also beat non-critical Cure once the target is already selected")

    assert_equal(mock_engage(settings, {
        id = 201,
        valid = true,
        hpp = 100,
        in_scope = false,
        in_range = true,
    }), nil, "out-of-scope targets must not force engage")

    assert_equal(mock_engage(settings, {
        id = 202,
        valid = true,
        hpp = 100,
        recent_death = true,
        in_scope = true,
        in_range = true,
    }), nil, "recent-death targets must not force engage")

    assert_equal(mock_engage(settings, {
        id = 203,
        valid = true,
        hpp = 100,
        in_scope = true,
        in_range = true,
        duplicate_suppressed = true,
    }), nil, "engage duplicate protection must still suppress repeat engage sends")

    local spell_scheduler = {}
    now_value = 10
    action_state.action_mark_sent_with_meta(spell_scheduler, "spell", now_s, {
        action_name = "Protect V",
        provider = "combat",
        def_action_type = "",
    })
    assert_equal(action_state.action_is_acting(spell_scheduler, now_s), true, "in-progress spell must still block engage before completion")
    local blocked, reason = action_state.action_dispatch_blocked(spell_scheduler, now_s, {})
    assert_equal(blocked, true, "in-progress spell must block engage dispatch")
    assert_equal(reason, "BLOCK_ACTION_ACTING", "in-progress spell must block through acting state")

    local cleared = action_state.clear_local_spell_success(spell_scheduler, now_s)
    assert_equal(cleared, true, "confirmed local spell success must shorten generic post-spell lockout")
    assert_equal(action_state.action_is_acting(spell_scheduler, now_s), false, "confirmed local spell success must end acting state immediately")
    local st = action_state.action_state(spell_scheduler)
    assert_close(tonumber(st.cooldown_until) or 0, 10.2, 0.0001, "generic spell success must leave only a short bounded cooldown tail")
    blocked, reason = action_state.action_dispatch_blocked(spell_scheduler, now_s, {})
    assert_equal(blocked, true, "bounded post-cast tail may still debounce immediate engage repeat")
    assert_equal(reason, "BLOCK_ACTION_COOLDOWN", "bounded post-cast tail must be cooldown-based after confirmed success")
    now_value = 10.21
    blocked, reason = action_state.action_dispatch_blocked(spell_scheduler, now_s, {})
    assert_equal(blocked, false, "confirmed local spell success must not create multi-second engage delay")
    assert_equal(reason, nil, "released post-cast tail must not return a block reason")

    local interrupt_scheduler = {}
    now_value = 20
    action_state.action_mark_sent_with_meta(interrupt_scheduler, "spell", now_s, {
        action_name = "Phalanx",
        provider = "combat",
        def_action_type = "",
    })
    cleared = action_state.clear_local_spell_interruption(interrupt_scheduler, now_s)
    assert_equal(cleared, true, "confirmed local spell interruption must clear generic spell lockout promptly")
    blocked, reason = action_state.action_dispatch_blocked(interrupt_scheduler, now_s, {})
    assert_equal(blocked, false, "interrupted local spell must not leave stale engage cooldown")
    assert_equal(reason, nil, "interrupted local spell should not leave a block reason")

    assert_contains(scheduler_source, "function scheduler.p1_try_nonblocking_target_acquire(settings)", "T3.4g nonblocking target-acquire lane must remain intact")
    assert_contains(scheduler_source, "local target_acted, target_reason = scheduler.p1_try_nonblocking_target_acquire(s)", "target-acquire lane must still run before ranked dispatch")
    assert_contains(scheduler_source, "scheduler.TANK_ENGAGE_PRIORITY = 107", "T3.4f tank engage priority band must remain intact")

    io.stdout:write("selftest_engage_dispatch_priority: OK\n")
end

main()
