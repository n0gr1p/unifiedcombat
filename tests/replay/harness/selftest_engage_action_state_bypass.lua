local scheduler_path = "unified_scheduler.lua"
local action_state_path = "uc_scheduler_action_state.lua"
local ranker_path = "uc_scheduler_ranker.lua"

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

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

package.loaded["uc_scheduler_action_state"] = nil
local action_state = dofile(action_state_path)

local now_value = 0

local function now_s()
    return now_value
end

local function capture_timeline()
    local events = {}
    local function log(event_code, fields)
        events[#events + 1] = {
            code = tostring(event_code or ""),
            fields = type(fields) == "table" and fields or {},
        }
    end
    return events, log
end

local function find_event(events, code)
    for i = 1, #events do
        if events[i].code == code then
            return events[i]
        end
    end
    return nil
end

local function engage_meta(target_id)
    return {
        explicit_attack_on = true,
        player_status = 0,
        target_selected = true,
        target_valid = true,
        target_id = tonumber(target_id) or 0,
        target_name = "Apex_Bat",
        dispatch_method = "attack_on",
    }
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local action_state_source = read_file(action_state_path)
    local ranker_source = read_file(ranker_path)

    assert_contains(action_state_source, "function M.engage_attack_on_action_state_gate", "action-state module must define explicit attack-on engage gate")
    assert_contains(action_state_source, "ENGAGE_ACTION_STATE_BYPASS", "engage action-state bypass must be logged")
    assert_contains(action_state_source, "if send_kind == 'engage' then", "engage retry debounce must remain blocking")
    assert_contains(scheduler_source, "engage_attack_on_action_state_gate({", "scheduler engage dispatch must use the explicit attack-on action-state gate")
    assert_contains(scheduler_source, "scheduler.p1_maybe_release_stale_spell_lock_for_target_transition(selected, now_s())", "scheduler must still attempt stale spell release before engage send")
    assert_contains(ranker_source, "reason = 'pending_engage_retry_wait'", "ranker retry cadence holds must log their exact blocker")
    assert_contains(scheduler_source, "reason = 'BLOCK_PLAYER_DEAD'", "dead-player engage holds must log their exact blocker")

    local ws_scheduler = {}
    now_value = 10.00
    action_state.action_mark_sent_with_meta(ws_scheduler, "ws", now_s, {
        action_name = "Savage Blade",
        provider = "combat",
        target_id = 1001,
        target_kind = "mob",
    })
    local ws_events, ws_log = capture_timeline()
    local blocked, reason = action_state.engage_attack_on_action_state_gate(ws_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = ws_log,
    }, engage_meta(2001))
    assert_equal(blocked, false, "explicit attack-on must bypass stale WS action-state")
    assert_equal(reason, nil, "WS bypass should not return a block reason")
    local bypass_event = assert(find_event(ws_events, "ENGAGE_ACTION_STATE_BYPASS"), "WS bypass must emit a bypass event")
    assert_equal(bypass_event.fields.kind, "weaponskill", "WS bypass must report the stale action kind")

    local ja_scheduler = {}
    now_value = 20.00
    action_state.action_mark_sent_with_meta(ja_scheduler, "ja", now_s, {
        action_name = "Provoke",
        provider = "combat",
        target_id = 1002,
        target_kind = "mob",
    })
    local ja_events, ja_log = capture_timeline()
    blocked, reason = action_state.engage_attack_on_action_state_gate(ja_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = ja_log,
    }, engage_meta(2002))
    assert_equal(blocked, false, "explicit attack-on must bypass stale JA action-state")
    assert_equal(reason, nil, "JA bypass should not return a block reason")
    bypass_event = assert(find_event(ja_events, "ENGAGE_ACTION_STATE_BYPASS"), "JA bypass must emit a bypass event")
    assert_equal(bypass_event.fields.kind, "job_ability", "JA bypass must report the stale action kind")

    local spell_scheduler = {}
    now_value = 30.00
    action_state.action_mark_sent_with_meta(spell_scheduler, "spell", now_s, {
        action_name = "Flash",
        provider = "combat",
        target_id = 3001,
        target_kind = "mob",
    })
    local spell_events, spell_log = capture_timeline()
    blocked, reason = action_state.engage_attack_on_action_state_gate(spell_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = spell_log,
    }, engage_meta(3002))
    assert_equal(blocked, false, "explicit attack-on must bypass spell action-state while status is 0")
    assert_equal(reason, nil, "spell bypass should not return a block reason")
    bypass_event = assert(find_event(spell_events, "ENGAGE_ACTION_STATE_BYPASS"), "spell bypass must emit a bypass event")
    assert_equal(bypass_event.fields.kind, "spell", "spell bypass must report spell kind")

    local stale_spell = {}
    now_value = 40.00
    action_state.action_mark_sent_with_meta(stale_spell, "spell", now_s, {
        action_name = "Flash",
        provider = "combat",
        target_id = 4001,
        target_kind = "mob",
    })
    local cleared = action_state.clear_stale_combat_spell_lock(stale_spell, now_s, {
        old_target_invalid = true,
        player_status_zero = true,
        new_target_id = 4002,
    })
    assert_equal(cleared, true, "stale mob-target combat spell should clear immediately on proven target transition")
    local stale_events, stale_log = capture_timeline()
    blocked, reason = action_state.engage_attack_on_action_state_gate(stale_spell, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = stale_log,
    }, engage_meta(4002))
    assert_equal(blocked, false, "engage should pass once stale spell state is cleared immediately")
    assert_equal(reason, nil, "cleared stale spell should not keep an engage block")

    local post_tail_scheduler = {}
    now_value = 45.00
    action_state.action_mark_sent_with_meta(post_tail_scheduler, "spell", now_s, {
        action_name = "Flash",
        provider = "combat",
        target_id = 4501,
        target_kind = "mob",
    })
    action_state.clear_local_spell_success(post_tail_scheduler, now_s)
    local post_tail_events, post_tail_log = capture_timeline()
    blocked, reason = action_state.engage_attack_on_action_state_gate(post_tail_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = post_tail_log,
    }, engage_meta(4502))
    assert_equal(blocked, false, "explicit attack-on must bypass post-spell tail while status is 0")
    assert_equal(reason, nil, "post-spell tail bypass should not return a block reason")
    bypass_event = assert(find_event(post_tail_events, "ENGAGE_ACTION_STATE_BYPASS"), "post-spell tail bypass must emit a bypass event")
    assert_equal(bypass_event.fields.kind, "post_spell_tail", "post-spell tail bypass must report post_spell_tail kind")

    local cooldown_scheduler = {}
    now_value = 47.00
    local cooldown_state = action_state.action_state(cooldown_scheduler)
    cooldown_state.action_start = now_value - 1.00
    cooldown_state.action_end = now_value - 0.50
    cooldown_state.last_action = now_value - 0.50
    cooldown_state.cooldown_until = now_value + 0.25
    cooldown_state.last_send_kind = "move"
    cooldown_state.post_spell_tail_started_at = 0
    cooldown_state.post_spell_tail_until = 0
    local cooldown_events, cooldown_log = capture_timeline()
    blocked, reason = action_state.engage_attack_on_action_state_gate(cooldown_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = cooldown_log,
    }, engage_meta(4702))
    assert_equal(blocked, false, "explicit attack-on must bypass generic action cooldown while status is 0")
    assert_equal(reason, nil, "generic cooldown bypass should not return a block reason")
    bypass_event = assert(find_event(cooldown_events, "ENGAGE_ACTION_STATE_BYPASS"), "generic cooldown bypass must emit a bypass event")
    assert_equal(bypass_event.fields.kind, "cooldown", "generic cooldown bypass must report cooldown kind")

    local engage_scheduler = {}
    now_value = 50.00
    action_state.action_mark_engage_sent(engage_scheduler, now_s)
    local engage_events, engage_log = capture_timeline()
    blocked, reason = action_state.engage_attack_on_action_state_gate(engage_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
        UC_ACTION_TIMELINE_LOG = engage_log,
    }, engage_meta(5001))
    assert_equal(blocked, true, "engage retry debounce must remain intact")
    assert_equal(reason, "BLOCK_ACTION_COOLDOWN", "engage retry debounce must stay cooldown-based")
    assert_true(find_event(engage_events, "ENGAGE_ACTION_STATE_BYPASS") == nil, "engage debounce must not be bypassed")

    local dead_scheduler = {}
    now_value = 60.00
    action_state.action_mark_sent_with_meta(dead_scheduler, "ws", now_s, {
        action_name = "Savage Blade",
        provider = "combat",
        target_id = 6001,
        target_kind = "mob",
    })
    local dead_meta = engage_meta(6002)
    dead_meta.player_dead = true
    blocked, reason = action_state.engage_attack_on_action_state_gate(dead_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
    }, dead_meta)
    assert_equal(blocked, true, "player death must still block engage")
    assert_equal(reason, "BLOCK_PLAYER_DEAD", "player death block reason mismatch")

    local invalid_target_scheduler = {}
    now_value = 70.00
    action_state.action_mark_sent_with_meta(invalid_target_scheduler, "ja", now_s, {
        action_name = "Provoke",
        provider = "combat",
        target_id = 7001,
        target_kind = "mob",
    })
    local invalid_meta = engage_meta(7002)
    invalid_meta.target_valid = false
    blocked, reason = action_state.engage_attack_on_action_state_gate(invalid_target_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
    }, invalid_meta)
    assert_equal(blocked, true, "invalid targets must still block engage")
    assert_equal(reason, "BLOCK_INVALID_TARGET", "invalid target block reason mismatch")

    local engaged_scheduler = {}
    now_value = 80.00
    action_state.action_mark_sent_with_meta(engaged_scheduler, "ws", now_s, {
        action_name = "Savage Blade",
        provider = "combat",
        target_id = 8001,
        target_kind = "mob",
    })
    local engaged_meta = engage_meta(8002)
    engaged_meta.player_status = 1
    blocked, reason = action_state.engage_attack_on_action_state_gate(engaged_scheduler, now_s, {
        UC_ACTION_TIMELINE_CURRENT_ACTION = "engage",
    }, engaged_meta)
    assert_equal(blocked, true, "status=1 must still avoid redundant explicit engage")
    assert_equal(reason, "BLOCK_ALREADY_ENGAGED", "status=1 block reason mismatch")

    io.stdout:write("selftest_engage_action_state_bypass: OK\n")
end

main()
