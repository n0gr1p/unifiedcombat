return {
    {
        fixture_id = "action_state_creates_table",
        helper = "action_state",
        description = "creates scheduler.action_state table when missing",
        input = {
            scheduler = {},
        },
        expected = {
            result = {},
            scheduler_action_state = {},
        },
    },
    {
        fixture_id = "action_mark_sent_sets_fields_and_cooldown",
        helper = "action_mark_sent",
        description = "marks send timestamps, delay, cooldown, and send kind",
        input = {
            scheduler = {
                action_state = {
                    cooldown_until = 10,
                },
            },
            kind = "spell",
            now_s = function()
                return 100
            end,
        },
        expected = {
            result = nil,
            scheduler_action_state = {
                accepted_completion_after_timeout = false,
                action_start = 100,
                action_end = 99.999,
                action_token = 1,
                action_delay = 0.6,
                cooldown_until = 100.6,
                high_level_spell_sent_at = 0,
                high_level_spell_sent_logged = false,
                last_action = 100,
                last_completion_ignore_reason = "",
                last_send_kind = "spell",
                last_sent_at = 100,
                packet_start_at = 0,
                post_spell_tail_started_at = 0,
                post_spell_tail_until = 0,
                spell_sent_log_missing_emitted = false,
                terminal_action_token = "",
                terminal_at = 0,
                terminal_message_id = 0,
                terminal_message_param = 0,
                terminal_outcome = "",
                terminal_since_sent_s = 0,
                timeout_release_at = 0,
            },
        },
    },
    {
        fixture_id = "action_mark_sent_preserves_higher_cooldown",
        helper = "action_mark_sent",
        description = "cooldown_until keeps higher existing value",
        input = {
            scheduler = {
                action_state = {
                    cooldown_until = 200,
                },
            },
            kind = nil,
            now_s = function()
                return 100
            end,
        },
        expected = {
            result = nil,
            scheduler_action_state = {
                accepted_completion_after_timeout = false,
                action_start = 100,
                action_end = 99.999,
                action_token = 1,
                action_delay = 0.6,
                cooldown_until = 200,
                high_level_spell_sent_at = 0,
                high_level_spell_sent_logged = false,
                last_action = 100,
                last_completion_ignore_reason = "",
                last_send_kind = "",
                last_sent_at = 100,
                packet_start_at = 0,
                post_spell_tail_started_at = 0,
                post_spell_tail_until = 0,
                spell_sent_log_missing_emitted = false,
                terminal_action_token = "",
                terminal_at = 0,
                terminal_message_id = 0,
                terminal_message_param = 0,
                terminal_outcome = "",
                terminal_since_sent_s = 0,
                timeout_release_at = 0,
            },
        },
    },
    {
        fixture_id = "action_mark_packet_start_end",
        helper = "action_mark_packet_pair",
        description = "packet start/end update timestamps",
        input = {
            scheduler = {
                action_state = {},
            },
            start_now_s = function()
                return 50
            end,
            end_now_s = function()
                return 55
            end,
        },
        expected = {
            result = nil,
            scheduler_action_state = {
                packet_start_at = 50,
                action_start = 50,
                action_end = 55,
            },
        },
    },
    {
        fixture_id = "action_is_acting_true_in_progress",
        helper = "action_is_acting",
        description = "returns true when end is less than start and not timed out",
        input = {
            scheduler = {
                action_state = {
                    action_start = 10,
                    action_end = 9,
                    last_send_kind = "spell",
                    lag_timeout = 8,
                    last_acting_state = false,
                },
            },
            now_s = function()
                return 12
            end,
        },
        expected = {
            result = true,
            scheduler_action_state = {
                action_start = 10,
                action_end = 9,
                last_send_kind = "spell",
                lag_timeout = 8,
                last_acting_state = true,
                action_delay = 0.6,
            },
        },
    },
    {
        fixture_id = "action_is_acting_timeout_spell",
        helper = "action_is_acting",
        description = "times out acting for non-ja send kind using lag_timeout",
        input = {
            scheduler = {
                action_state = {
                    action_start = 10,
                    action_end = 9,
                    last_send_kind = "spell",
                    lag_timeout = 8,
                    last_acting_state = false,
                    cooldown_until = 0,
                },
            },
            now_s = function()
                return 19
            end,
        },
        expected = {
            result = false,
            scheduler_action_state = {
                action_start = 10,
                action_end = 19,
                terminal_action_token = "0",
                terminal_at = 19,
                terminal_message_id = 0,
                terminal_message_param = 0,
                terminal_outcome = "timeout",
                terminal_since_sent_s = 0,
                last_send_kind = "spell",
                lag_timeout = 8,
                last_acting_state = false,
                cooldown_until = 0,
                spell_sent_log_missing_emitted = true,
                timeout_release_at = 19,
            },
        },
    },
    {
        fixture_id = "action_is_acting_transition_to_not_acting_updates_cooldown",
        helper = "action_is_acting",
        description = "transition from acting to not acting updates delay/last_action/cooldown",
        input = {
            scheduler = {
                action_state = {
                    action_start = 10,
                    action_end = 10,
                    last_acting_state = true,
                    cooldown_until = 12,
                },
            },
            now_s = function()
                return 20
            end,
        },
        expected = {
            result = false,
            scheduler_action_state = {
                action_start = 10,
                action_end = 10,
                last_acting_state = false,
                cooldown_until = 20.5,
                action_delay = 0.5,
                last_action = 20,
            },
        },
    },
    {
        fixture_id = "action_dispatch_blocked_acting_with_log",
        helper = "action_dispatch_blocked",
        description = "acting blocks dispatch and emits diag when combat log enabled",
        input = {
            scheduler = {
                action_state = {
                    action_start = 10,
                    action_end = 9,
                    last_send_kind = "ja",
                    ja_lag_timeout = 1.0,
                    last_acting_state = false,
                },
            },
            now_s = function()
                return 10.5
            end,
            active_profile = {
                version = 2,
                profile = {},
                config = { debug = { combat_sched = true } },
            },
            globals = {
                UC_LOG_DIAG = function(topic, msg)
                    local sink = _G.__diag_sink
                    sink[#sink + 1] = {
                        topic = topic,
                        msg = msg,
                    }
                end,
            },
        },
        expected = {
            result = {
                true,
                "BLOCK_ACTION_ACTING",
            },
            scheduler_action_state = {
                action_start = 10,
                action_end = 9,
                last_send_kind = "ja",
                ja_lag_timeout = 1.0,
                last_acting_state = true,
                action_delay = 0.6,
            },
            diag_calls = {
                {
                    topic = "combat_sched",
                    contains = "action_block acting=1 kind=ja",
                },
            },
        },
    },
    {
        fixture_id = "action_dispatch_blocked_cooldown_no_log",
        helper = "action_dispatch_blocked",
        description = "cooldown blocks dispatch with no diag when logging disabled",
        input = {
            scheduler = {
                action_state = {
                    action_start = 1,
                    action_end = 1,
                    cooldown_until = 30,
                    last_send_kind = "spell",
                },
            },
            now_s = function()
                return 20
            end,
            active_profile = {
                version = 2,
                profile = {},
                config = { debug = { combat_sched = false } },
            },
            globals = {},
        },
        expected = {
            result = {
                true,
                "BLOCK_ACTION_COOLDOWN",
            },
            scheduler_action_state = {
                action_start = 1,
                action_end = 1,
                cooldown_until = 30,
                last_send_kind = "spell",
                last_acting_state = false,
                timeline_last_block_reason = "BLOCK_POST_SPELL_TAIL",
            },
            diag_calls = {},
        },
    },
    {
        fixture_id = "action_dispatch_not_blocked",
        helper = "action_dispatch_blocked",
        description = "returns not blocked when not acting and cooldown elapsed",
        input = {
            scheduler = {
                action_state = {
                    action_start = 1,
                    action_end = 2,
                    cooldown_until = 5,
                    last_acting_state = false,
                },
            },
            now_s = function()
                return 20
            end,
            globals = {},
        },
        expected = {
            result = {
                false,
                nil,
            },
            scheduler_action_state = {
                action_start = 1,
                action_end = 2,
                cooldown_until = 5,
                last_acting_state = false,
            },
            diag_calls = {},
        },
    },
}
