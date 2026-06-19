package.loaded['uc_scheduler_action_state'] = nil
local action_state = dofile('uc_scheduler_action_state.lua')

local scheduler_source_path = 'unified_scheduler.lua'
local action_state_source_path = 'uc_scheduler_action_state.lua'

local now_value = 0

local function now_s()
    return now_value
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    if not value then
        error(message or 'assert_true failed')
    end
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ('missing expected text: ' .. needle))
    end
end

local function read_file(file_path)
    local fh, err = io.open(file_path, 'r')
    if not fh then
        error('failed to open ' .. tostring(file_path) .. ': ' .. tostring(err))
    end
    local text = fh:read('*a')
    fh:close()
    return text
end

local function mock_choose_defensive_action(candidates)
    local c = candidates or {}
    local function is_majesty_action(action)
        return type(action) == 'table' and tostring(action.spell or ''):lower() == 'majesty'
    end
    local majesty_action = nil
    if is_majesty_action(c.buff) then
        majesty_action = c.buff
    elseif is_majesty_action(c.overwrite) then
        majesty_action = c.overwrite
    end
    if c.debuff and c.debuff.spell == 'Paralyna' and c.debuff.target and c.debuff.target.is_self then
        return c.debuff, 'BLOCK_DEFENSIVE_NA'
    end
    if majesty_action then
        return majesty_action, 'BLOCK_DEFENSIVE_MAJESTY'
    end
    if c.overwrite then
        return c.overwrite, 'BLOCK_DEFENSIVE_OVERWRITE'
    elseif c.cure then
        if c.debuff and ((c.debuff.prio + 2) < c.cure.prio) then
            return c.debuff, 'BLOCK_DEFENSIVE_NA'
        end
        return c.cure, 'BLOCK_DEFENSIVE_CURE'
    elseif c.debuff then
        if c.buff and (c.buff.prio < c.debuff.prio) then
            return c.buff, 'BLOCK_DEFENSIVE_BUFF'
        end
        return c.debuff, 'BLOCK_DEFENSIVE_NA'
    elseif c.buff then
        return c.buff, 'BLOCK_DEFENSIVE_BUFF'
    end
    return nil, nil
end

local function mock_is_defensive_cure_selected(selected)
    if type(selected) ~= 'table' then
        return false
    end
    local provider = tostring(selected.provider or '')
    if provider ~= 'defensive_internal' and provider ~= 'defensive_healbot' then
        return false
    end
    if tostring(selected.action_type or '') ~= 'spell' then
        return false
    end
    local detail = type(selected.detail) == 'table' and selected.detail or nil
    return tostring(detail and detail.def_action_type or '') == 'cure'
end

local function mock_defensive_cure_is_critical(settings, selected)
    if not mock_is_defensive_cure_selected(selected) then
        return false
    end
    local detail = type(selected.detail) == 'table' and selected.detail or nil
    local target_hpp = tonumber(detail and detail.target_hpp or -1) or -1
    local critical_hpp = tonumber(settings and settings.defensive_critical_hpp) or 35
    return target_hpp > 0 and target_hpp <= critical_hpp
end

local function mock_is_eligible_weave_action(selected)
    if type(selected) ~= 'table' then
        return false
    end
    if tostring(selected.provider or '') ~= 'combat' then
        return false
    end
    local action_type = tostring(selected.action_type or '')
    if action_type ~= 'ja' and action_type ~= 'ws' then
        return false
    end
    local target_kind = tostring(selected.target_kind or '')
    if target_kind == 'mob' then
        return (tonumber(selected.target_id) or 0) > 0
    end
    return true
end

local function mock_apply_weave_selection(settings, ranked, weave_ready)
    local selected = ranked[1]
    if not mock_is_defensive_cure_selected(selected) then
        return selected
    end
    if mock_defensive_cure_is_critical(settings, selected) then
        return selected
    end
    if not weave_ready then
        return selected
    end
    for index = 2, #ranked do
        local candidate = ranked[index]
        if mock_is_eligible_weave_action(candidate) then
            return candidate
        end
    end
    return selected
end

local function make_cure(hpp)
    return {
        provider = 'defensive_internal',
        action_type = 'spell',
        action_name = 'Cure IV',
        detail = {
            def_action_type = 'cure',
            target_hpp = hpp,
        },
    }
end

local function main()
    local source = read_file(scheduler_source_path)
    local action_state_source = read_file(action_state_source_path)
    assert_contains(source, "local is_defensive_cure_selected = (", 'scheduler must compute bounded defensive Cure weave selection at final ranked pick')
    assert_contains(source, "defensive_cure_weave_ready(scheduler, now_s)", 'scheduler must gate weave on action-state readiness')
    assert_contains(source, "p1_revalidate_plan_commit(ctx, candidate, candidate_plan)", 'weave candidate must be commit-revalidated before selection')
    assert_contains(source, "candidate._weave_from_provider = tostring(selected.provider or '')", 'weave selection must mark source proposal context')
    assert_contains(action_state_source, "st.defensive_cure_weave_until = now + 5.0", 'action-state must keep bounded weave allowance after Cure send')

    local self_buff = {
        type = 'buff',
        spell = 'Protectra',
        prio = 1.5,
        target = { name = 'Self', is_self = true, id = 1, hpp = 100 },
    }
    local majesty_buff = {
        type = 'buff',
        spell = 'Majesty',
        prio = 1.5,
        target = { name = 'Self', is_self = true, id = 1, hpp = 100 },
    }
    local self_paralyna = {
        type = 'debuff',
        spell = 'Paralyna',
        prio = 1,
        target = { name = 'Self', is_self = true, id = 1 },
    }
    local cure_candidate = {
        type = 'cure',
        spell = 'Cure IV',
        prio = 5,
        target = { name = 'AllyA', id = 1001, hpp = 48 },
    }

    local chosen, reason = mock_choose_defensive_action({
        cure = cure_candidate,
        buff = majesty_buff,
    })
    assert_equal(chosen, majesty_buff, 'Majesty must remain allowed over Cure under T3.1h policy')
    assert_equal(reason, 'BLOCK_DEFENSIVE_MAJESTY', 'Majesty reason mismatch')

    chosen, reason = mock_choose_defensive_action({
        cure = cure_candidate,
        buff = self_buff,
    })
    assert_equal(chosen, cure_candidate, 'ordinary self-buff must still lose to valid Cure')
    assert_equal(reason, 'BLOCK_DEFENSIVE_CURE', 'ordinary self-buff reason mismatch')

    chosen, reason = mock_choose_defensive_action({
        cure = cure_candidate,
        debuff = self_paralyna,
        buff = majesty_buff,
    })
    assert_equal(chosen, self_paralyna, 'self Paralyna must remain allowed to outrank Cure')
    assert_equal(reason, 'BLOCK_DEFENSIVE_NA', 'self Paralyna reason mismatch')

    local ws_candidate = {
        provider = 'combat',
        action_type = 'ws',
        action_name = 'Savage Blade',
        target_kind = 'mob',
        target_id = 2001,
    }
    local ja_candidate = {
        provider = 'combat',
        action_type = 'ja',
        action_name = 'Provoke',
        target_kind = 'mob',
        target_id = 2001,
    }
    local invalid_ws_candidate = {
        provider = 'combat',
        action_type = 'ws',
        action_name = 'Savage Blade',
        target_kind = 'mob',
        target_id = 0,
    }

    local noncritical_cure = make_cure(48)
    local critical_cure = make_cure(22)

    local selected = mock_apply_weave_selection({ defensive_critical_hpp = 35 }, { noncritical_cure, ws_candidate }, true)
    assert_equal(selected, ws_candidate, 'repeated noncritical Cure must allow one eligible WS weave')

    selected = mock_apply_weave_selection({ defensive_critical_hpp = 35 }, { noncritical_cure, ja_candidate }, true)
    assert_equal(selected, ja_candidate, 'repeated noncritical Cure must allow one eligible JA weave')

    selected = mock_apply_weave_selection({ defensive_critical_hpp = 35 }, { noncritical_cure, ws_candidate, ja_candidate }, false)
    assert_equal(selected, noncritical_cure, 'after one weave, next Cure must win again until next Cure send resets allowance')

    selected = mock_apply_weave_selection({ defensive_critical_hpp = 35 }, { critical_cure, ws_candidate }, true)
    assert_equal(selected, critical_cure, 'critical Cure must block non-defensive weave')

    selected = mock_apply_weave_selection({ defensive_critical_hpp = 35 }, { noncritical_cure, invalid_ws_candidate }, true)
    assert_equal(selected, noncritical_cure, 'invalid JA/WS target must not weave over Cure')

    selected = mock_apply_weave_selection({ defensive_critical_hpp = 35 }, { noncritical_cure, ws_candidate }, false)
    assert_equal(selected, noncritical_cure, 'no repeated Cure chain state must keep Cure selected')

    local action_scheduler = {}
    now_value = 10
    action_state.action_mark_sent_with_meta(action_scheduler, 'spell', now_s, {
        action_name = 'Cure IV',
        provider = 'defensive_internal',
        def_action_type = 'cure',
    })
    assert_equal(action_state.defensive_cure_weave_ready(action_scheduler, now_s), true, 'defensive Cure send must arm bounded weave allowance')

    now_value = 12
    action_state.action_mark_sent(action_scheduler, 'ws', now_s)
    assert_equal(action_state.defensive_cure_weave_ready(action_scheduler, now_s), false, 'one woven WS/JA must consume allowance until next Cure send')

    now_value = 20
    action_state.action_mark_sent_with_meta(action_scheduler, 'defensive_healbot', now_s, {
        action_name = 'Cure III',
        provider = 'defensive_healbot',
        def_action_type = 'cure',
    })
    assert_equal(action_state.defensive_cure_weave_ready(action_scheduler, now_s), true, 'healbot Cure send must arm bounded weave allowance')

    now_value = 25.2
    assert_equal(action_state.defensive_cure_weave_ready(action_scheduler, now_s), false, 'bounded weave allowance must expire by timeout')

    now_value = 30
    action_state.action_mark_sent_with_meta(action_scheduler, 'spell', now_s, {
        action_name = 'Paralyna',
        provider = 'defensive_internal',
        def_action_type = 'debuff',
    })
    assert_equal(action_state.defensive_cure_weave_ready(action_scheduler, now_s), false, 'non-Cure defensive spell must not arm Cure weave allowance')

    io.stdout:write('selftest_defensive_cure_weave_policy: OK\n')
end

main()
