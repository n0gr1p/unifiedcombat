return {
    {
        fixture_id = "reject_history_basic_append",
        helper = "p1_push_recent_rejects",
        description = "appends reject text/items for one rejection",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = {},
                    recent_reject_items = {},
                },
            },
            ctx = {
                tick = 42,
            },
            rejected = {
                {
                    provider = "defensive",
                    family = "combat.defense",
                    action = "Stoneskin",
                    reason = "not_ready",
                },
            },
        },
        expected = {
            result = nil,
            phase1_recent_rejects = {
                "t42 defensive/combat.defense Stoneskin :: not_ready",
            },
            phase1_recent_reject_items = {
                {
                    tick = "42",
                    provider = "defensive",
                    family = "combat.defense",
                    action = "Stoneskin",
                    reason = "not_ready",
                },
            },
        },
    },
    {
        fixture_id = "reject_history_initializes_tables_on_empty_input",
        helper = "p1_push_recent_rejects",
        description = "initializes storage tables even when rejected list is empty",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = nil,
                    recent_reject_items = nil,
                },
            },
            ctx = {
                tick = "",
            },
            rejected = {},
        },
        expected = {
            result = nil,
            phase1_recent_rejects = {},
            phase1_recent_reject_items = {},
        },
    },
    {
        fixture_id = "reject_history_coercion_defaults",
        helper = "p1_push_recent_rejects",
        description = "coerces nil and false fields with current tostring-or-empty behavior",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = {},
                    recent_reject_items = {},
                },
            },
            ctx = {
                tick = nil,
            },
            rejected = {
                {
                    provider = false,
                    family = nil,
                    action = 77,
                    reason = nil,
                },
            },
        },
        expected = {
            result = nil,
            phase1_recent_rejects = {
                "t / 77 :: ",
            },
            phase1_recent_reject_items = {
                {
                    tick = "",
                    provider = "",
                    family = "",
                    action = "77",
                    reason = "",
                },
            },
        },
    },
    {
        fixture_id = "reject_history_trims_to_25",
        helper = "p1_push_recent_rejects",
        description = "drops oldest entries when list exceeds max keep",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = {
                        "old.1", "old.2", "old.3", "old.4", "old.5", "old.6", "old.7", "old.8", "old.9", "old.10",
                        "old.11", "old.12", "old.13", "old.14", "old.15", "old.16", "old.17", "old.18", "old.19", "old.20",
                        "old.21", "old.22", "old.23", "old.24",
                    },
                    recent_reject_items = {
                        { tick = "old.1" }, { tick = "old.2" }, { tick = "old.3" }, { tick = "old.4" }, { tick = "old.5" }, { tick = "old.6" },
                        { tick = "old.7" }, { tick = "old.8" }, { tick = "old.9" }, { tick = "old.10" }, { tick = "old.11" }, { tick = "old.12" },
                        { tick = "old.13" }, { tick = "old.14" }, { tick = "old.15" }, { tick = "old.16" }, { tick = "old.17" }, { tick = "old.18" },
                        { tick = "old.19" }, { tick = "old.20" }, { tick = "old.21" }, { tick = "old.22" }, { tick = "old.23" }, { tick = "old.24" },
                    },
                },
            },
            ctx = {
                tick = 99,
            },
            rejected = {
                {
                    provider = "p1",
                    family = "f1",
                    action = "a1",
                    reason = "r1",
                },
                {
                    provider = "p2",
                    family = "f2",
                    action = "a2",
                    reason = "r2",
                },
            },
        },
        expected = {
            result = nil,
            phase1_recent_rejects = {
                "old.2", "old.3", "old.4", "old.5", "old.6", "old.7", "old.8", "old.9", "old.10", "old.11",
                "old.12", "old.13", "old.14", "old.15", "old.16", "old.17", "old.18", "old.19", "old.20", "old.21",
                "old.22", "old.23", "old.24", "t99 p1/f1 a1 :: r1", "t99 p2/f2 a2 :: r2",
            },
            phase1_recent_reject_items = {
                { tick = "old.2" }, { tick = "old.3" }, { tick = "old.4" }, { tick = "old.5" }, { tick = "old.6" }, { tick = "old.7" },
                { tick = "old.8" }, { tick = "old.9" }, { tick = "old.10" }, { tick = "old.11" }, { tick = "old.12" }, { tick = "old.13" },
                { tick = "old.14" }, { tick = "old.15" }, { tick = "old.16" }, { tick = "old.17" }, { tick = "old.18" }, { tick = "old.19" },
                { tick = "old.20" }, { tick = "old.21" }, { tick = "old.22" }, { tick = "old.23" }, { tick = "old.24" },
                { tick = "99", provider = "p1", family = "f1", action = "a1", reason = "r1" },
                { tick = "99", provider = "p2", family = "f2", action = "a2", reason = "r2" },
            },
        },
    },
}
