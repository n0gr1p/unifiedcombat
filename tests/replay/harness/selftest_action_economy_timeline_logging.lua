local scheduler_path = "unified_scheduler.lua"
local action_state_path = "uc_scheduler_action_state.lua"
local unifiedcombat_path = "UnifiedCombat.lua"

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

local function assert_close(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error((message or "assert_close failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function event_present_after(events, start_index, wanted)
    for i = start_index, #events do
        if events[i] == wanted then
            return true
        end
    end
    return false
end

local function assert_event_after(events, start_index, wanted, message)
    if not event_present_after(events, start_index, wanted) then
        error(message or ("missing event: " .. tostring(wanted)))
    end
end

local function assert_no_event_after(events, start_index, unwanted, message)
    if event_present_after(events, start_index, unwanted) then
        error(message or ("unexpected event: " .. tostring(unwanted)))
    end
end

local function find_record_after(records, start_index, wanted)
    for i = start_index, #records do
        if records[i].event == wanted then
            return records[i]
        end
    end
    return nil
end

local function assert_record_after(records, start_index, wanted, message)
    local record = find_record_after(records, start_index, wanted)
    if not record then
        error(message or ("missing record: " .. tostring(wanted)))
    end
    return record
end

local function install_scheduler_stubs()
    local stub_names = {
        "resources",
        "uc_ability_pipeline",
        "unified_combat_core",
        "uc_targeting_common",
        "uc_cor_maintenance",
        "uc_settarget",
        "uc_attack",
        "uc_partner_list",
        "uc_fight_leader",
        "uc_hb_buff_maint",
        "uc_enemy_effect_tracker",
        "lor/lor_packets",
        "json",
        "uc_tb_effect_table",
        "uc_scheduler_locks",
        "uc_scheduler_pending",
    }
    local old_loaded = {}
    for i = 1, #stub_names do
        old_loaded[stub_names[i]] = package.loaded[stub_names[i]]
    end
    local function resource_set(entries)
        entries = entries or {}
        return setmetatable(entries, {
            __index = {
                with = function(self, key, value)
                    for _, item in pairs(self) do
                        if type(item) == "table" and item[key] == value then
                            return item
                        end
                    end
                    return nil
                end,
            },
        })
    end
    package.loaded["resources"] = {
        spells = resource_set({
            [1] = { id = 1, en = "Haste", status = 33 },
            [2] = { id = 2, en = "Sleep II" },
            [3] = { id = 3, en = "Mage's Ballad III", status = 214 },
        }),
        job_abilities = resource_set({}),
        buffs = resource_set({
            [33] = { id = 33, en = "Haste" },
            [214] = { id = 214, en = "Ballad" },
        }),
    }
    package.loaded["uc_ability_pipeline"] = {
        collect_ordered = function() return {} end,
    }
    package.loaded["unified_combat_core"] = {
        on_action_message = function() end,
        add_control_enabled_for_scheduler = function() return false end,
        select_ws_plan_for_scheduler = function() return nil end,
        is_live_actionable_combat_target = function() return false end,
        select_pull_for_scheduler = function() return nil end,
        select_tank_enmity_for_scheduler = function() return nil end,
        select_target_for_scheduler = function() return nil end,
    }
    package.loaded["uc_targeting_common"] = {
        build_friendly_claims = function() return {}, {} end,
        mob_targets_friendly_member = function() return false end,
    }
    package.loaded["uc_cor_maintenance"] = {
        propose = function() return nil end,
    }
    package.loaded["uc_settarget"] = {}
    package.loaded["uc_attack"] = {}
    package.loaded["uc_partner_list"] = {}
    package.loaded["uc_fight_leader"] = {
        leader_target_id = function() return 0 end,
    }
    package.loaded["uc_hb_buff_maint"] = {}
    package.loaded["uc_enemy_effect_tracker"] = {
        on_action = function() return {} end,
        on_action_message = function() return {} end,
        list_targets = function() return {} end,
        get_effects = function() return {} end,
    }
    package.loaded["lor/lor_packets"] = {}
    package.loaded["json"] = {}
    package.loaded["uc_tb_effect_table"] = { apply_from_action = function() end }
    package.loaded["uc_scheduler_locks"] = { p1_pending_is_live_state = function() return false end }
    package.loaded["uc_scheduler_pending"] = {
        p1_pending_mark_complete = function() return true end,
        p1_pending_mark_failed = function() return true end,
        p1_update_pending_state = function() end,
        p1_set_pending_globals = function() end,
    }
    return stub_names, old_loaded
end

local function restore_scheduler_stubs(stub_names, old_loaded)
    for i = 1, #stub_names do
        package.loaded[stub_names[i]] = old_loaded[stub_names[i]]
    end
    package.loaded["unified_scheduler"] = nil
    package.loaded["uc_scheduler_action_state"] = nil
end

local function assert_old_bloat_absent(runtime_source)
    local old_events = {
        "SPELL_COMPLETION_PATH_ENTER",
        "SPELL_COMPLETION_PATH_EXIT",
        "SPELL_COMPLETION_CANDIDATE_IGNORED",
        "SPELL_COMPLETION_CLASSIFIER_NOT_RUN",
        "SPELL_COMPLETION_SILENT_RETURN_BUG",
        "SPELL_OBSERVED_STATE_CHECK",
        "SPELL_OBSERVED_STATE_COMPLETION",
        "SPELL_COMPLETION_STALE_TOKEN_IGNORED",
    }
    for i = 1, #old_events do
        assert_not_contains(runtime_source, old_events[i], "old completion diagnostic event must be absent from runtime code: " .. old_events[i])
    end
    assert_not_contains(runtime_source, "classify_spell_completion_message", "effect-result completion classifier must be removed")
    assert_not_contains(runtime_source, "buff_result_206_status", "206 status-result completion must not release action economy")
    assert_not_contains(runtime_source, "erase_result_206_status", "Erase 206 completion must not release action economy")
    assert_not_contains(runtime_source, "magic_finale_result_206_status", "Finale 206 completion must not release action economy")
    assert_not_contains(runtime_source, "observed_song_count_increased", "observed song state must not release action economy")
end

local function run_action_state_timeout_test(action_state)
    local events = {}
    local old_sink = rawget(_G, "UC_ACTION_TIMELINE_LOG")
    _G.UC_ACTION_TIMELINE_LOG = function(event_code)
        events[#events + 1] = tostring(event_code or "")
        return true
    end
    local clock = 10
    local function now_s()
        return clock
    end
    local scheduler = { action_state = {} }
    scheduler.spell_lifecycle_probe_enabled = function()
        return true
    end
    scheduler.emit_spell_lifecycle_timeout_candidate_summary = function(scheduler_obj, now_s_fn, st)
        local fn = rawget(_G, "UC_ACTION_TIMELINE_LOG")
        if type(fn) == "function" then
            fn("SPELL_LIFECYCLE_TIMEOUT_CANDIDATE_SUMMARY", {
                action_token = tostring(tonumber(st.action_token) or 0),
                active_spell = tostring(st.last_action_name or ""),
            })
        end
    end
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 123,
        target_name = "Redrogue",
        target_kind = "self",
    })
    clock = 19
    local before_timeout = #events + 1
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "timeout fallback must release an uncompleted spell cast")
    assert_event_after(events, before_timeout, "SPELL_TIMEOUT_RELEASE", "timeout fallback must emit timeout release")
    assert_event_after(events, before_timeout, "SPELL_LIFECYCLE_TIMEOUT_CANDIDATE_SUMMARY", "timeout fallback must emit probe candidate summary")
    assert_event_after(events, before_timeout, "SPELL_ACTION_STATE_RELEASE", "timeout fallback must emit action-state release")
    assert_no_event_after(events, before_timeout, "POST_SPELL_TAIL_START", "timeout fallback must not start post-spell tail")
    _G.UC_ACTION_TIMELINE_LOG = old_sink
end

local function run_scheduler_lifecycle_tests()
    local stub_names, old_loaded = install_scheduler_stubs()
    local old_windower = rawget(_G, "windower")
    local old_socket = rawget(_G, "socket")
    local old_settings = rawget(_G, "UC_SETTINGS")
    local old_sink = rawget(_G, "UC_ACTION_TIMELINE_LOG")
    local old_probe = rawget(_G, "UC_SPELL_LIFECYCLE_PROBE")
    local old_test_now = rawget(_G, "__TEST_NOW")
    local old_movement_lock_until = rawget(_G, "UC_MOVEMENT_LOCK_UNTIL")
    local mobs = {
        [123] = { id = 123, name = "Redrogue" },
        [888] = { id = 888, name = "Tank" },
        [999] = { id = 999, name = "Other" },
    }
    _G.windower = {
        addon_path = "C:\\Program Files (x86)\\Windower\\addons\\UnifiedCombat\\",
        add_to_chat = function() end,
        send_ipc_message = function() end,
        packets = { parse_action = function() return {} end },
        ffxi = {
            get_player = function()
                return {
                    id = 123,
                    name = "Redrogue",
                    status = 0,
                    main_job_id = 1,
                    sub_job_id = 2,
                    main_job_level = 99,
                    sub_job_level = 49,
                    vitals = { mp = 500 },
                    job_points = {},
                    buffs = {},
                }
            end,
            get_mob_by_id = function(id)
                return mobs[id]
            end,
            get_spells = function()
                return { [1] = true, [2] = true, [3] = true }
            end,
            get_spell_recasts = function()
                return {}
            end,
            get_mjob_data = function()
                return { spells = {} }
            end,
            get_sjob_data = function()
                return { spells = {} }
            end,
        },
    }
    _G.socket = {
        gettime = function()
            return _G.__TEST_NOW or 0
        end,
    }
    _G.UC_SETTINGS = {}
    _G.UC_SPELL_LIFECYCLE_PROBE = true
    _G.UC_MOVEMENT_LOCK_UNTIL = 200
    package.loaded["unified_scheduler"] = nil
    package.loaded["uc_scheduler_action_state"] = nil
    local scheduler = require("unified_scheduler")
    local action_state = require("uc_scheduler_action_state")
    local events = {}
    local records = {}
    local function capture_timeline(event_code, fields)
        events[#events + 1] = tostring(event_code or "")
        records[#records + 1] = {
            event = tostring(event_code or ""),
            fields = type(fields) == "table" and fields or {},
        }
        return true
    end
    scheduler.action_timeline_log = capture_timeline
    _G.UC_ACTION_TIMELINE_LOG = capture_timeline
    local clock = 100
    local function now_s()
        _G.__TEST_NOW = clock
        return clock
    end

    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_start = #events + 1
    local before_start_record = #records + 1
    scheduler.on_action({ actor_id = 123, category = 8 })
    local st = action_state.action_state(scheduler)
    assert_equal(st.last_send_kind, "spell", "cast start must keep spell action-state")
    assert_equal(st.last_action_name, "Haste", "cast start must preserve active spell name")
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "cast start must leave token acting")
    assert_event_after(events, before_start, "SPELL_CAST_START_DETECTED", "local spell start must emit cast-start event")
    local start_probe = assert_record_after(records, before_start_record, "SPELL_LIFECYCLE_PROBE_LOCAL_EVENT", "active local action must emit probe event")
    assert_equal(start_probe.fields.source, "action_packet", "action probe must record source hook")
    assert_equal(tostring(start_probe.fields.category), "8", "action probe must record category")
    assert_equal(tostring(start_probe.fields.action_token), tostring(st.action_token), "action probe must record active token")

    clock = 101
    scheduler.on_action({
        actor_id = 123,
        category = 4,
        param = 2,
        targets = {
            {
                id = 888,
                actions = {
                    { message = 7, param = 250 },
                },
            },
        },
    })
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "different spell result packet must not release active spell")

    scheduler.on_action({
        actor_id = 123,
        category = 4,
        param = 1,
        targets = {
            {
                id = 999,
                actions = {
                    { message = 7, param = 250 },
                },
            },
        },
    })
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "different target result packet must not release active spell")

    clock = 101.5
    local before_packet_complete = #events + 1
    scheduler.on_action({
        actor_id = 123,
        category = 4,
        param = 1,
        targets = {
            {
                id = 888,
                actions = {
                    { message = 7, param = 250 },
                },
            },
        },
    })
    assert_event_after(events, before_packet_complete, "SPELL_CAST_COMPLETE_DETECTED", "matching local magic-result packet must emit cast-complete event")
    assert_event_after(events, before_packet_complete, "SPELL_ACTION_STATE_RELEASE", "matching local magic-result packet must release action-state")
    assert_event_after(events, before_packet_complete, "POST_SPELL_TAIL_START", "matching local magic-result packet must start post-spell tail")
    assert_no_event_after(events, before_packet_complete, "SPELL_TIMEOUT_RELEASE", "matching local magic-result packet must avoid timeout release")
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "matching local magic-result packet must end acting state")
    st = action_state.action_state(scheduler)
    assert_equal(st.terminal_outcome, "cast_complete", "magic-result packet terminal outcome must be cast_complete")
    assert_close(
        (tonumber(st.cooldown_until) or 0) - (tonumber(st.action_end) or 0),
        3.0,
        0.0001,
        "magic-result packet must retain a three-second animation-lock tail"
    )

    clock = 105
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_complete = #events + 1
    scheduler.on_action_message({ actor_id = 123, target_id = 888, message_id = 2, param_1 = 0, spell_name = "Haste" })
    assert_event_after(events, before_complete, "SPELL_CAST_COMPLETE_DETECTED", "cast-complete message must emit cast-complete event")
    assert_event_after(events, before_complete, "SPELL_ACTION_STATE_RELEASE", "cast-complete message must release action-state")
    assert_event_after(events, before_complete, "POST_SPELL_TAIL_START", "cast-complete message must start post-spell tail")
    assert_no_event_after(events, before_complete, "SPELL_TIMEOUT_RELEASE", "cast-complete message must avoid timeout release")
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "cast-complete message must end acting state")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_complete", "terminal outcome must be cast_complete")

    clock = 120
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_interrupt = #events + 1
    scheduler.on_action_message({ actor_id = 123, target_id = 888, message_id = 16, param_1 = 0 })
    assert_event_after(events, before_interrupt, "SPELL_CAST_INTERRUPTED_DETECTED", "cast-interrupted message must emit interrupted event")
    assert_event_after(events, before_interrupt, "SPELL_ACTION_STATE_RELEASE", "cast-interrupted message must release action-state")
    assert_no_event_after(events, before_interrupt, "POST_SPELL_TAIL_START", "cast-interrupted message must not start post-spell tail")
    assert_no_event_after(events, before_interrupt, "SPELL_TIMEOUT_RELEASE", "cast-interrupted message must avoid timeout release")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_interrupted", "terminal outcome must be cast_interrupted")

    clock = 140
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_target_mismatch = #events + 1
    scheduler.on_action_message({ actor_id = 123, target_id = 999, message_id = 2, param_1 = 0, spell_name = "Haste" })
    assert_event_after(events, before_target_mismatch, "SPELL_CAST_COMPLETE_DETECTED", "target mismatch must not block cast-complete release")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_complete", "target mismatch release must still complete cast")

    clock = 160
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_no_effect_state = #events + 1
    scheduler.on_action_message({ actor_id = 123, target_id = 888, message_id = 2, param_1 = 0, spell_name = "Haste" })
    assert_event_after(events, before_no_effect_state, "SPELL_CAST_COMPLETE_DETECTED", "cast completion must not require buff/status/song state changes")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_complete", "effect state must not control action economy release")

    clock = 160
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_effect_result = #events + 1
    local before_effect_record = #records + 1
    scheduler.on_action_message({ actor_id = 123, target_id = 888, message_id = 206, param_1 = 33, spell_name = "Haste" })
    local effect_probe = assert_record_after(records, before_effect_record, "SPELL_LIFECYCLE_PROBE_LOCAL_EVENT", "active local action-message must emit probe event")
    assert_equal(effect_probe.fields.source, "action_message", "message probe must record source hook")
    assert_equal(tonumber(effect_probe.fields.message_id) or 0, 206, "message probe must record message id")
    assert_equal(tonumber(effect_probe.fields.param) or 0, 33, "message probe must record message param")
    assert_equal(effect_probe.fields.spell_name, "Haste", "message probe must record spell name when available")
    assert_no_event_after(events, before_effect_result, "SPELL_CAST_COMPLETE_DETECTED", "206 effect/status result must not release action economy")
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "206 effect/status result must leave spell token acting")

    clock = 170
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_text_record = #records + 1
    local before_text_event = #events + 1
    scheduler.on_incoming_text("Redrogue casts Haste.", "Redrogue casts Haste.", 121, false)
    local text_probe = assert_record_after(records, before_text_record, "SPELL_LIFECYCLE_PROBE_TEXT", "incoming text lifecycle match must emit text probe")
    assert_equal(text_probe.fields.matched_pattern, "casts_spell", "text probe must identify casts-spell pattern")
    assert_equal(text_probe.fields.parsed_actor, "Redrogue", "text probe must parse actor")
    assert_equal(text_probe.fields.parsed_spell, "Haste", "text probe must parse spell")
    assert_event_after(events, before_text_event, "SPELL_CAST_COMPLETE_DETECTED", "cast-complete text must emit cast-complete lifecycle")
    assert_event_after(events, before_text_event, "SPELL_ACTION_STATE_RELEASE", "cast-complete text must release action-state")
    assert_event_after(events, before_text_event, "POST_SPELL_TAIL_START", "cast-complete text must start post-spell tail")
    assert_no_event_after(events, before_text_event, "SPELL_TIMEOUT_RELEASE", "cast-complete text must avoid timeout release")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_complete", "cast-complete text must terminate the spell token")
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "cast-complete text must end acting state")

    clock = 180
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Magic Finale",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_suffix_record = #records + 1
    local before_suffix_event = #events + 1
    scheduler.on_incoming_text("Redrogue casts Magic Finale. The effect wears off.", "Redrogue casts Magic Finale. The effect wears off.", 121, false)
    local suffix_probe = assert_record_after(records, before_suffix_record, "SPELL_LIFECYCLE_PROBE_TEXT", "cast text with suffix must emit probe text")
    assert_contains(tostring(suffix_probe.fields.parsed_spell or ""), "Magic Finale", "text probe must still capture the cast spell name")
    assert_event_after(events, before_suffix_event, "SPELL_CAST_COMPLETE_DETECTED", "suffix text must still complete the cast")
    assert_event_after(events, before_suffix_event, "SPELL_ACTION_STATE_RELEASE", "suffix text must still release the action-state")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_complete", "suffix text must terminate the spell token")

    clock = 190
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_target_suffix_record = #records + 1
    local before_target_suffix_event = #events + 1
    scheduler.on_incoming_text("Redrogue casts Haste on Tank.", "Redrogue casts Haste on Tank.", 121, false)
    local target_suffix_probe = assert_record_after(records, before_target_suffix_record, "SPELL_LIFECYCLE_PROBE_TEXT", "target suffix text must emit probe text")
    assert_equal(target_suffix_probe.fields.parsed_spell, "Haste on Tank", "probe text must record the full suffix text")
    assert_event_after(events, before_target_suffix_event, "SPELL_CAST_COMPLETE_DETECTED", "target suffix text must still complete the cast")
    assert_event_after(events, before_target_suffix_event, "SPELL_ACTION_STATE_RELEASE", "target suffix text must still release the action-state")

    clock = 200
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_interrupt_record = #records + 1
    local before_interrupt_event = #events + 1
    scheduler.on_incoming_text("Redrogue's casting is interrupted.", "Redrogue's casting is interrupted.", 121, false)
    local interrupt_probe = assert_record_after(records, before_interrupt_record, "SPELL_LIFECYCLE_PROBE_TEXT", "interrupt text must emit probe text")
    assert_equal(interrupt_probe.fields.matched_pattern, "casting_interrupted", "interrupt probe must identify interrupted text")
    assert_event_after(events, before_interrupt_event, "SPELL_CAST_INTERRUPTED_DETECTED", "interrupt text must emit interrupted lifecycle")
    assert_event_after(events, before_interrupt_event, "SPELL_ACTION_STATE_RELEASE", "interrupt text must release action-state")
    assert_no_event_after(events, before_interrupt_event, "SPELL_TIMEOUT_RELEASE", "interrupt text must avoid timeout release")
    assert_equal(action_state.action_state(scheduler).terminal_outcome, "cast_interrupted", "interrupt text must terminate the spell token")

    clock = 210
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_other_actor_event = #events + 1
    scheduler.on_incoming_text("Other casts Haste.", "Other casts Haste.", 121, false)
    assert_no_event_after(events, before_other_actor_event, "SPELL_CAST_COMPLETE_DETECTED", "non-local actor text must not release action-state")
    assert_no_event_after(events, before_other_actor_event, "SPELL_CAST_INTERRUPTED_DETECTED", "non-local actor text must not interrupt action-state")
    assert_equal(action_state.action_is_acting(scheduler, now_s), true, "non-local actor text must leave the spell acting")

    clock = 220
    action_state.action_mark_sent_with_meta(scheduler, "spell", now_s, {
        action_name = "Haste",
        provider = "defensive_internal",
        def_action_type = "buff",
        target_id = 888,
        target_name = "Tank",
        target_kind = "player",
    })
    local before_timeout = #events + 1
    local before_timeout_record = #records + 1
    clock = clock + 8.2
    assert_equal(action_state.action_is_acting(scheduler, now_s), false, "timeout must still release when no cast-complete or interrupt text arrives")
    assert_event_after(events, before_timeout, "SPELL_TIMEOUT_RELEASE", "timeout fallback must emit timeout release")
    assert_event_after(events, before_timeout, "SPELL_ACTION_STATE_RELEASE", "timeout fallback must emit action-state release")
    assert_no_event_after(events, before_timeout, "POST_SPELL_TAIL_START", "timeout fallback must not start post-spell tail")
    local summary = assert_record_after(records, before_timeout_record, "SPELL_LIFECYCLE_TIMEOUT_CANDIDATE_SUMMARY", "timeout must emit candidate summary")
    assert_equal(summary.fields.candidate_cast_complete, "0", "timeout summary must not invent a cast-complete candidate")
    assert_equal(summary.fields.candidate_cast_interrupted, "0", "timeout summary must not invent an interrupt candidate")

    _G.UC_ACTION_TIMELINE_LOG = old_sink
    _G.windower = old_windower
    _G.socket = old_socket
    _G.UC_SETTINGS = old_settings
    _G.UC_SPELL_LIFECYCLE_PROBE = old_probe
    _G.__TEST_NOW = old_test_now
    _G.UC_MOVEMENT_LOCK_UNTIL = old_movement_lock_until
    restore_scheduler_stubs(stub_names, old_loaded)
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local action_state_source = read_file(action_state_path)
    local unifiedcombat_source = read_file(unifiedcombat_path)
    local runtime_source = scheduler_source .. action_state_source

    assert_old_bloat_absent(runtime_source)
    assert_contains(scheduler_source, "function scheduler.is_spell_cast_complete_message_id(message_id)", "cast-complete message matcher must be centralized")
    assert_contains(scheduler_source, "return mid == 2 or mid == 230 or mid == 236 or mid == 252", "cast-complete matcher must use the pinned cast-finish message ids")
    assert_contains(scheduler_source, "function scheduler.is_spell_cast_interrupted_message_id(message_id)", "cast-interrupted matcher must be centralized")
    assert_contains(scheduler_source, "return mid == 16", "cast-interrupted matcher must use the pinned interruption message id")
    assert_contains(scheduler_source, "function scheduler.match_active_spell_token_to_cast_finish(msg, st)", "active token matching must be centralized")
    assert_contains(scheduler_source, "message_spell ~= '' and active_spell ~= message_spell", "spell-name mismatch must block cast-complete release when both names are available")
    assert_contains(scheduler_source, "function scheduler.handle_local_spell_finish_action(act, player_id, observed_at)", "local magic-result packet completion handler must exist")
    assert_contains(scheduler_source, "completion_reason = 'cast_complete_action_packet'", "local magic-result packet must use an explicit completion reason")
    assert_not_contains(scheduler_source, "\t\t[4] = true,", "magic-result category 4 must not be treated as a cast-start signal")
    assert_not_contains(scheduler_source, "and not scheduler.is_spell_cast_start_message_id(message_id)\n\t\t\tand not scheduler.is_spell_cast_complete_message_id(message_id)", "broad defensive interrupt rule must remain absent")
    assert_contains(action_state_source, "SPELL_CAST_START_DETECTED", "cast-start lifecycle event must exist")
    assert_contains(action_state_source, "SPELL_CAST_COMPLETE_DETECTED", "cast-complete lifecycle event must exist")
    assert_contains(action_state_source, "SPELL_CAST_INTERRUPTED_DETECTED", "cast-interrupted lifecycle event must exist")
    assert_contains(action_state_source, "mark_terminal_outcome(st, now, 'cast_complete'", "cast-complete terminal outcome must be explicit")
    assert_contains(action_state_source, "mark_terminal_outcome(st, now, 'cast_interrupted'", "cast-interrupted terminal outcome must be explicit")
    assert_contains(action_state_source, "local timeout = tonumber(st.lag_timeout) or 8.0", "timeout duration must remain unchanged")
    assert_contains(scheduler_source, "function scheduler.spell_lifecycle_probe_enabled()", "probe flag helper must exist")
    assert_contains(scheduler_source, "UC_SPELL_LIFECYCLE_PROBE", "probe flag must be named explicitly")
    assert_contains(scheduler_source, "SPELL_LIFECYCLE_PROBE_LOCAL_EVENT", "active local event probe must exist")
    assert_contains(scheduler_source, "SPELL_LIFECYCLE_PROBE_RECENT_EVENT", "recent local event probe must exist")
    assert_contains(scheduler_source, "SPELL_LIFECYCLE_PROBE_TEXT", "text lifecycle probe must exist")
    assert_contains(scheduler_source, "SPELL_LIFECYCLE_TIMEOUT_CANDIDATE_SUMMARY", "timeout candidate summary probe must exist")
    assert_contains(unifiedcombat_source, "windower.register_event('incoming text'", "UnifiedCombat must forward incoming text to the scheduler probe")

    package.loaded["uc_scheduler_action_state"] = nil
    local action_state = dofile(action_state_path)
    run_action_state_timeout_test(action_state)
    run_scheduler_lifecycle_tests()

    io.stdout:write("selftest_action_economy_timeline_logging: OK\n")
end

main()
