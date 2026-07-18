return {
    {
        fixture_id = "pending_update_non_table_clears",
        helper = "p1_update_pending_state",
        description = "non-table pending is cleared",
        input = {
            scheduler = {
                phase1 = {
                    pending = false,
                    recent_duplicate_until = {},
                },
            },
            ctx = { now = 10 },
            p1_pending_is_live_state = function(_) return false end,
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = nil,
            pending = nil,
            recent_duplicate_until = {},
        },
    },
    {
        fixture_id = "pending_update_live_effect_timeout",
        helper = "p1_update_pending_state",
        description = "live pending past effect_deadline times out and sets duplicate window",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "sent",
                        result = "",
                        effect_deadline = 20,
                        completion_deadline = 40,
                        duplicate_suppression_key = "dup.k1",
                    },
                    recent_duplicate_until = {},
                },
            },
            ctx = { now = 25 },
            p1_pending_is_live_state = function(state) return state == "sent" end,
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = nil,
            pending = {
                state = "timed_out",
                result = "effect_timeout",
                effect_deadline = 20,
                completion_deadline = 40,
                duplicate_suppression_key = "dup.k1",
            },
            recent_duplicate_until = {
                ["dup.k1"] = 25.75,
            },
        },
    },
    {
        fixture_id = "pending_update_terminal_clears_after_completion_deadline",
        helper = "p1_update_pending_state",
        description = "failed/timed_out/canceled clears after completion_deadline",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "failed",
                        completion_deadline = 20,
                    },
                    recent_duplicate_until = {},
                },
            },
            ctx = { now = 21 },
            p1_pending_is_live_state = function(_) return false end,
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = nil,
            pending = nil,
            recent_duplicate_until = {},
        },
    },
    {
        fixture_id = "pending_update_complete_clears_after_deadline",
        helper = "p1_update_pending_state",
        description = "complete state clears after completion_deadline",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "complete",
                        completion_deadline = 5,
                    },
                    recent_duplicate_until = {},
                },
            },
            ctx = { now = 6 },
            p1_pending_is_live_state = function(_) return false end,
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = nil,
            pending = nil,
            recent_duplicate_until = {},
        },
    },
    {
        fixture_id = "pending_set_globals_blank_when_none",
        helper = "p1_set_pending_globals",
        description = "sets global pending state blank when no pending table",
        input = {
            scheduler = {
                phase1 = {
                    pending = nil,
                },
            },
            globals = {
                UC_SCHED_P1_PENDING_STATE = "old",
            },
        },
        expected = {
            result = nil,
            global_state = "",
        },
    },
    {
        fixture_id = "pending_set_globals_from_pending_state",
        helper = "p1_set_pending_globals",
        description = "publishes pending.state string to globals",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "acknowledged",
                    },
                },
            },
            globals = {},
        },
        expected = {
            result = nil,
            global_state = "acknowledged",
        },
    },
    {
        fixture_id = "pending_mark_complete_no_pending_noop",
        helper = "p1_pending_mark_complete",
        description = "no pending table returns without mutation",
        input = {
            scheduler = {
                phase1 = {
                    pending = nil,
                    recent_duplicate_until = {
                        keep = 1,
                    },
                },
            },
            now = 30,
            result_code = "ok",
        },
        expected = {
            result = nil,
            pending = nil,
            recent_duplicate_until = {
                keep = 1,
            },
        },
    },
    {
        fixture_id = "pending_mark_complete_sets_fields_and_duplicate_window",
        helper = "p1_pending_mark_complete",
        description = "marks complete and sets effect/completion + duplicate window",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "sent",
                        result = "",
                        duplicate_suppression_key = "dup.k2",
                    },
                    recent_duplicate_until = {},
                },
            },
            now = 50,
            result_code = "ack",
        },
        expected = {
            result = nil,
            pending = {
                state = "complete",
                result = "ack",
                duplicate_suppression_key = "dup.k2",
                effect_at = 50,
                completion_deadline = 50.75,
            },
            recent_duplicate_until = {
                ["dup.k2"] = 50.75,
            },
        },
    },
    {
        fixture_id = "pending_mark_failed_no_pending_noop",
        helper = "p1_pending_mark_failed",
        description = "no pending table returns without mutation",
        input = {
            scheduler = {
                phase1 = {
                    pending = nil,
                    recent_duplicate_until = {
                        keep = 1,
                    },
                },
            },
            now = 60,
            result_code = "server_reject",
            retry_delay = 0.75,
        },
        expected = {
            result = nil,
            pending = nil,
            recent_duplicate_until = {
                keep = 1,
            },
        },
    },
    {
        fixture_id = "pending_mark_failed_sets_retry_window",
        helper = "p1_pending_mark_failed",
        description = "marks failed and applies the scheduler retry window",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "sent",
                        result = "",
                        duplicate_suppression_key = "dup.brd",
                    },
                    recent_duplicate_until = {},
                },
            },
            now = 70,
            result_code = "spell_server_reject_17",
            retry_delay = 0.75,
        },
        expected = {
            result = nil,
            pending = {
                state = "failed",
                result = "spell_server_reject_17",
                duplicate_suppression_key = "dup.brd",
                effect_at = 70,
                completion_deadline = 70.75,
            },
            recent_duplicate_until = {
                ["dup.brd"] = 70.75,
            },
        },
    },
}
