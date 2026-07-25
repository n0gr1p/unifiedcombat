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

local function select_target_nonblocking_mock(input)
    local state = input.state or {}
    state.recent_duplicate_until = state.recent_duplicate_until or {}
    local now = tonumber(input.now) or 0
    local debounce_s = 0.20
    local candidate = input.candidate
    if input.domain_combat_enabled ~= true or input.autotarget ~= true then
        return false, "disabled", state
    end
    if type(candidate) ~= "table" then
        return false, "no_candidate", state
    end
    local tid = tonumber(candidate.target_id) or 0
    if tid <= 0 then
        return false, "invalid", state
    end
    if candidate.valid ~= true then
        return false, "invalid", state
    end
    if (tonumber(candidate.hpp) or 0) <= 0 then
        return false, "dead", state
    end
    if candidate.recent_death == true then
        return false, "recent_death", state
    end
    if candidate.in_range ~= true then
        return false, "range", state
    end
    if candidate.claim_ok ~= true then
        return false, "claim", state
    end
    if candidate.already_targeted == true then
        return false, "already_targeted", state
    end
    local dkey = "target.acquire:" .. tostring(tid)
    if (tonumber(state.recent_duplicate_until[dkey]) or 0) > now then
        return false, "debounced", state
    end
    state.recent_duplicate_until[dkey] = now + debounce_s
    state.last_target_id = tid
    return true, "sent", state
end

local function main()
    local source = read_file(scheduler_path)

    assert_contains(source, "scheduler.TARGET_ACQUIRE_DEBOUNCE_S = 0.20", "target acquire lane must use a short debounce")
    assert_contains(source, "function scheduler.p1_try_nonblocking_target_acquire(settings, ctx)", "scheduler must define a nonblocking target acquire lane")
    assert_contains(source, "scheduler.providers.target_control.collect_target(ctx, proposals)", "nonblocking lane must reuse extracted target-control proposal generation")
    assert_contains(source, "local lock_reject = p1_hard_lock_reject(p1_get_locks(ctx), selected)", "nonblocking lane must still respect scheduler safety locks")
    assert_contains(source, "return scheduler.p1_dispatch_target_control(selected, ctx)", "nonblocking lane must dispatch through the existing target ownership seam")
    assert_contains(source, "scheduler.p1_apply_target_acquire_debounce(selected, ctx.now)", "target acquire dispatch must debounce without creating multi-second lag")

    local process_pos = assert(source:find("local target_acted, target_reason = scheduler.p1_try_nonblocking_target_acquire(s, target_ctx)", 1, true))
    local dryrun_pos = assert(source:find("p1_run_dry(s, get_tick_ctx())", 1, true))
    local def_wait_pos = assert(source:find("local defensive_spell_wait_locked = scheduler.refresh_defensive_spell_wait_lock(now_s())", 1, true))
    assert_true(process_pos < dryrun_pos, "nonblocking target acquire must run before ranked action-economy dryrun")
    assert_true(process_pos < def_wait_pos, "nonblocking target acquire must run before defensive spell wait can block the tick")

    local helper_block = source:match("function scheduler%.p1_dispatch_target_control%(selected, ctx%)(.-)\nend\n\nfunction scheduler%.p1_try_nonblocking_target_acquire")
    assert_true(type(helper_block) == "string", "failed to capture nonblocking target dispatch helper")
    assert_not_contains(helper_block, "record_dispatch(ctx)", "nonblocking target dispatch helper must not create a normal pending action lock")
    assert_not_contains(helper_block, "action_mark_sent(", "nonblocking target dispatch helper must not consume spell/JA/WS action economy")

    local target_block = source:match("if provider == 'target_control' then(.-)\n\tend\n\n\tif provider == 'pull_control' then")
    assert_true(type(target_block) == "string", "failed to capture target_control dispatch block")
    assert_not_contains(target_block, "record_dispatch(ctx)", "ranked target-control dispatch must also avoid creating a normal pending action lock")
    assert_not_contains(target_block, "action_mark_sent(", "target-control dispatch must not consume spell/JA/WS action economy")

    local disabled_ok, disabled_reason = select_target_nonblocking_mock({
        domain_combat_enabled = false,
        autotarget = true,
        now = 9.0,
        state = {},
        candidate = { target_id = 99, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(disabled_ok, false, "disabled combat domain must suppress target acquisition")
    assert_equal(disabled_reason, "disabled", "disabled combat domain reason mismatch")

    local ok, reason, state = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 10.0,
        state = {},
        candidate = { target_id = 100, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, true, "tank with valid next target and non-critical Cure pending should still set target promptly")
    assert_equal(reason, "sent", "valid target should be sent immediately")

    ok, reason, state = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 10.05,
        state = state,
        candidate = { target_id = 100, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, false, "target acquire debounce should prevent immediate spam")
    assert_equal(reason, "debounced", "repeat target acquire should debounce briefly")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 10.25,
        state = state,
        candidate = { target_id = 100, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, true, "target acquire debounce must clear quickly and not create multi-second lag")
    assert_equal(reason, "sent", "target acquire should resend after the short debounce")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 11.0,
        state = {},
        candidate = { target_id = 101, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, true, "tank with maintenance buff pending should still set target promptly")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 12.0,
        state = {},
        candidate = { target_id = 102, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, true, "tank with Sleep proposal pending should still set target promptly")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 13.0,
        state = {},
        candidate = { target_id = 103, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, true, "tank with critical Cure pending should still set target promptly while Cure may still win action dispatch")

    local tank_ok = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 14.0,
        state = {},
        candidate = { target_id = 104, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    local dps_ok = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 14.0,
        state = {},
        candidate = { target_id = 104, valid = true, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(tank_ok, dps_ok, "target acquisition should be role-neutral when the same valid target exists")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 15.0,
        state = {},
        candidate = { target_id = 105, valid = false, hpp = 100, in_range = true, claim_ok = true },
    })
    assert_equal(ok, false, "invalid targets must not be selected")
    assert_equal(reason, "invalid", "invalid target reason mismatch")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 16.0,
        state = {},
        candidate = { target_id = 106, valid = true, hpp = 0, in_range = true, claim_ok = true },
    })
    assert_equal(ok, false, "dead targets must not be selected")
    assert_equal(reason, "dead", "dead target reason mismatch")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 17.0,
        state = {},
        candidate = { target_id = 107, valid = true, hpp = 100, recent_death = true, in_range = true, claim_ok = true },
    })
    assert_equal(ok, false, "recent-death targets must not be selected")
    assert_equal(reason, "recent_death", "recent-death reason mismatch")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 18.0,
        state = {},
        candidate = { target_id = 108, valid = true, hpp = 100, in_range = false, claim_ok = true },
    })
    assert_equal(ok, false, "out-of-range targets must not be selected")
    assert_equal(reason, "range", "range reason mismatch")

    ok, reason = select_target_nonblocking_mock({
        domain_combat_enabled = true,
        autotarget = true,
        now = 19.0,
        state = {},
        candidate = { target_id = 109, valid = true, hpp = 100, in_range = true, claim_ok = false },
    })
    assert_equal(ok, false, "unrelated claimed targets must not be selected")
    assert_equal(reason, "claim", "claim reason mismatch")

    io.stdout:write("selftest_target_acquire_nonblocking: OK\n")
end

main()
