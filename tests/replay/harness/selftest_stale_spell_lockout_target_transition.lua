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

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
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

    assert_contains(scheduler_source, "function scheduler.p1_maybe_release_stale_spell_lock_for_target_transition", "scheduler must define a narrow stale spell release helper")
    assert_contains(scheduler_source, "STALE_SPELL_LOCK_RELEASE", "scheduler must log stale spell lock release events")
    assert_contains(scheduler_source, "age_s = ('%.2f'):format(stale_age_s)", "stale spell release logs must include the stale lock age")
    assert_contains(scheduler_source, "immediate = immediate", "stale spell release logs must include whether release was immediate")
    assert_contains(action_state_source, "function M.clear_stale_combat_spell_lock", "action-state module must define a narrow stale combat spell release helper")
    assert_contains(action_state_source, "if tostring(st.last_action_provider or '') ~= 'combat' then", "stale release must stay scoped to combat spells")
    assert_contains(action_state_source, "if tostring(st.last_target_kind or '') ~= 'mob' then", "stale release must stay scoped to mob-target combat spells")

    local scheduler = {}
    now_value = 10.00
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Flash",
        provider = "combat",
        target_id = 1001,
        target_kind = "mob",
    })
    local st = action_state.action_state(scheduler)
    st.action_end = 10.20
    st.cooldown_until = 16.00
    st.action_delay = 0.2
    st.last_acting_state = false
    now_value = 10.70
    local cleared = action_state.clear_stale_combat_spell_lock(scheduler, now_s, {
        old_target_invalid = true,
        player_status_zero = true,
        new_target_id = 1002,
    })
    assert_equal(cleared, true, "old dead target plus new selected target must clear stale combat spell lock")
    local blocked, reason = action_state.action_dispatch_blocked(scheduler, now_s, {})
    assert_equal(blocked, false, "stale combat spell release must remove the old engage block")
    assert_equal(reason, nil, "cleared stale combat spell must not keep a block reason")

    local in_progress = {}
    now_value = 20.00
    action_state.action_mark_sent_with_meta(in_progress, "spell", now_s, {
        action_name = "Flash",
        provider = "combat",
        target_id = 2001,
        target_kind = "mob",
    })
    now_value = 20.10
    cleared = action_state.clear_stale_combat_spell_lock(in_progress, now_s, {
        old_target_invalid = true,
        player_status_zero = true,
        new_target_id = 2002,
    })
    assert_equal(cleared, true, "proven stale in-progress combat spells should clear immediately on target transition")

    local defensive = {}
    now_value = 30.00
    action_state.action_mark_sent_with_meta(defensive, "spell", now_s, {
        action_name = "Cure IV",
        provider = "defensive_internal",
        def_action_type = "cure",
        target_id = 3001,
        target_kind = "ally",
    })
    now_value = 30.70
    cleared = action_state.clear_stale_combat_spell_lock(defensive, now_s, {
        old_target_invalid = true,
        player_status_zero = true,
        new_target_id = 3002,
    })
    assert_equal(cleared, false, "defensive Cure state must not be aggressively cleared by target transition")

    local ja_scheduler = {}
    now_value = 40.00
    action_state.action_mark_sent_with_meta(ja_scheduler, "ja", now_s, {
        action_name = "Provoke",
        provider = "combat",
        target_id = 4001,
        target_kind = "mob",
    })
    now_value = 40.70
    cleared = action_state.clear_stale_combat_spell_lock(ja_scheduler, now_s, {
        old_target_invalid = true,
        player_status_zero = true,
        new_target_id = 4002,
    })
    assert_equal(cleared, false, "stale spell release must not clear JA state")

    local ws_scheduler = {}
    now_value = 50.00
    action_state.action_mark_sent_with_meta(ws_scheduler, "ws", now_s, {
        action_name = "Savage Blade",
        provider = "combat",
        target_id = 5001,
        target_kind = "mob",
    })
    now_value = 50.70
    cleared = action_state.clear_stale_combat_spell_lock(ws_scheduler, now_s, {
        old_target_invalid = true,
        player_status_zero = true,
        new_target_id = 5002,
    })
    assert_equal(cleared, false, "stale spell release must not clear WS state")

    io.stdout:write("selftest_stale_spell_lockout_target_transition: OK\n")
end

main()
