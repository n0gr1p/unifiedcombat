return {
    {
        fixture_id = "locks_pending_live_state_true_selected",
        helper = "p1_pending_is_live_state",
        description = "selected state is treated as live",
        input = {
            state_name = "selected",
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "locks_pending_live_state_false_done",
        helper = "p1_pending_is_live_state",
        description = "non-live state returns false",
        input = {
            state_name = "done",
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "locks_duplicate_suppressed_by_pending",
        helper = "p1_duplicate_suppressed",
        description = "pending live matching key suppresses duplicate",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        duplicate_suppression_key = "dup.1",
                        state = "sent",
                    },
                    recent_duplicate_until = {
                        ["dup.1"] = 0,
                    },
                },
            },
            ctx = { now = 100 },
            proposal = { duplicate_suppression_key = "dup.1" },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "locks_duplicate_suppressed_by_recent_until",
        helper = "p1_duplicate_suppressed",
        description = "recent duplicate window suppresses when future timestamp",
        input = {
            scheduler = {
                phase1 = {
                    pending = nil,
                    recent_duplicate_until = {
                        ["dup.2"] = 150,
                    },
                },
            },
            ctx = { now = 100 },
            proposal = { duplicate_suppression_key = "dup.2" },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "locks_duplicate_not_suppressed_no_key",
        helper = "p1_duplicate_suppressed",
        description = "empty duplicate key is never suppressed",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        duplicate_suppression_key = "dup.3",
                        state = "sent",
                    },
                    recent_duplicate_until = {},
                },
            },
            ctx = { now = 100 },
            proposal = {},
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "locks_get_locks_pending_live_and_zone_guard",
        helper = "p1_get_locks",
        description = "pending live and zone suspend drive hard locks",
        input = {
            scheduler = {
                phase1 = {
                    pending = {
                        state = "dispatching",
                    },
                    recent_duplicate_until = {
                        a = 90,
                        b = 130,
                    },
                },
            },
            ctx = { now = 100 },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            globals = {
                UC_ZONE_SUSPEND_UNTIL = 120,
            },
        },
        expected = {
            result = {
                zone_guard_lock = { hard = true },
                cast_lock = { hard = true },
                movement_lock = { hard = true },
                target_lock = { hard = false },
                duplicate_lock = { hard = true, until_ts = 130 },
            },
        },
    },
    {
        fixture_id = "locks_hard_lock_reject_reasons",
        helper = "p1_hard_lock_reject",
        description = "returns zone_guard then hard_locked per action type",
        input = {
            calls = {
                {
                    locks = {
                        zone_guard_lock = { hard = true },
                        cast_lock = { hard = true },
                        movement_lock = { hard = true },
                    },
                    proposal = { action_type = "spell" },
                },
                {
                    locks = {
                        zone_guard_lock = { hard = false },
                        cast_lock = { hard = true },
                        movement_lock = { hard = false },
                    },
                    proposal = { action_type = "ja" },
                },
                {
                    locks = {
                        zone_guard_lock = { hard = false },
                        cast_lock = { hard = false },
                        movement_lock = { hard = true },
                    },
                    proposal = { action_type = "move" },
                },
                {
                    locks = {
                        zone_guard_lock = { hard = false },
                        cast_lock = { hard = false },
                        movement_lock = { hard = false },
                    },
                    proposal = { action_type = "item" },
                },
            },
        },
        expected = {
            result = {
                "zone_guard",
                "hard_locked",
                "hard_locked",
                "",
            },
        },
    },
    {
        fixture_id = "locks_build_lock_summary_from_input",
        helper = "p1_build_lock_summary",
        description = "builds ordered summary string from lock table",
        input = {
            ctx = {},
            locks = {
                zone_guard_lock = { hard = true },
                cast_lock = { hard = false },
                movement_lock = { hard = true },
                duplicate_lock = { hard = true },
            },
            p1_get_locks = function(_) return {} end,
        },
        expected = {
            result = "zone_guard_lock|movement_lock|duplicate_lock",
        },
    },
    {
        fixture_id = "locks_build_lock_summary_uses_provider_when_nil",
        helper = "p1_build_lock_summary",
        description = "calls provider when locks input is nil",
        input = {
            ctx = { x = 1 },
            locks = nil,
            p1_get_locks = function(ctx)
                if ctx.x == 1 then
                    return {
                        zone_guard_lock = { hard = false },
                        cast_lock = { hard = true },
                        movement_lock = { hard = false },
                        duplicate_lock = { hard = false },
                    }
                end
                return {}
            end,
        },
        expected = {
            result = "cast_lock",
        },
    },
    {
        fixture_id = "locks_reset_runtime_locks",
        helper = "reset_runtime_locks",
        description = "resets movement freeze globals and action state fields",
        input = {
            globals = {
                UC_MOVE_FREEZE_PREP_KEY = "abc",
                UC_MOVE_FREEZE_PREP_UNTIL = 99,
            },
            state = {
                action_start = 10,
                action_end = 9,
                last_send_kind = "ja",
                cooldown_until = 100,
                action_delay = 0.6,
                last_action = 80,
                last_acting_state = true,
            },
        },
        expected = {
            result = nil,
            globals = {
                UC_MOVE_FREEZE_PREP_KEY = "",
                UC_MOVE_FREEZE_PREP_UNTIL = 0,
            },
            state = {
                action_start = 0,
                action_end = 0,
                last_send_kind = "",
                cooldown_until = 0,
                action_delay = 0,
                last_action = 0,
                last_acting_state = false,
            },
        },
    },
}
