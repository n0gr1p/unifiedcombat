return {
    {
        fixture_id = "dryrun_publish_selected_sets_phase_and_globals",
        helper = "publish",
        description = "selected proposal populates phase cache, globals, and callback outputs",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = {
                        "old-a",
                        "old-b",
                    },
                },
            },
            globals = {
                UC_SCHED_P1_TOP3 = "stale",
            },
            ctx = {
                tick = 77,
            },
            selected = {
                proposal_id = "proposal-7",
                provider = "provider.alpha",
                family_id = "family.heal",
            },
            ranked = {
                { id = "r1" },
                { id = "r2" },
            },
            reject_counts = {
                out_of_range = 2,
            },
            rejected = {
                "rej-1",
                "rej-2",
            },
            proposals = {
                { id = "p1" },
                { id = "p2" },
                { id = "p3" },
            },
            locks = {
                movement = true,
            },
            plan = {
                id = "plan-1",
                prelude = {
                    type = "face_target",
                },
            },
            commit_reason = "",
            helper_returns = {
                top3 = "TOP3",
                top3_verbose = "TOP3_VERBOSE",
                top5_lines = {
                    "L1",
                    "L2",
                    "L3",
                    "L4",
                    "L5",
                    "L6",
                },
                top5_items = {
                    "I1",
                    "I2",
                },
                reject_top = "reject-summary",
                lock_summary = "lock-summary",
            },
            recent_rejects_after_push = {
                "rr-1",
                "rr-2",
                "rr-3",
                "rr-4",
                "rr-5",
                "rr-6",
            },
        },
        expected = {
            result = nil,
            scheduler_phase1 = {
                last_selected = {
                    proposal_id = "proposal-7",
                    provider = "provider.alpha",
                    family_id = "family.heal",
                },
                last_plan = {
                    id = "plan-1",
                    prelude = {
                        type = "face_target",
                    },
                },
                last_top3 = "TOP3",
                last_top3_verbose = "TOP3_VERBOSE",
                last_top5_lines = {
                    "L1",
                    "L2",
                    "L3",
                    "L4",
                    "L5",
                    "L6",
                },
                last_top5_items = {
                    "I1",
                    "I2",
                },
                last_reject_top = "reject-summary",
                last_noop_reason = "",
                recent_rejects = {
                    "rr-1",
                    "rr-2",
                    "rr-3",
                    "rr-4",
                    "rr-5",
                    "rr-6",
                },
            },
            globals = {
                UC_SCHED_P1_TICK = 77,
                UC_SCHED_P1_SELECTED_PROPOSAL = "proposal-7",
                UC_SCHED_P1_SELECTED_PROVIDER = "provider.alpha",
                UC_SCHED_P1_SELECTED_FAMILY = "family.heal",
                UC_SCHED_P1_PLAN_PRELUDE = "face_target",
                UC_SCHED_P1_LOCK_SUMMARY = "lock-summary",
                UC_SCHED_P1_REJECT_TOP = "reject-summary",
                UC_SCHED_P1_NOOP_REASON = "",
                UC_SCHED_P1_TOP3 = "TOP3",
                UC_SCHED_P1_TOP3_VERBOSE = "TOP3_VERBOSE",
                UC_SCHED_P1_TOP5 = "L1\nL2\nL3\nL4\nL5\nL6",
                UC_SCHED_P1_REJECT5 = "rr-2\nrr-3\nrr-4\nrr-5\nrr-6",
            },
            calls = {
                p1_format_top3 = {
                    {
                        { id = "r1" },
                        { id = "r2" },
                    },
                },
                p1_format_top3_verbose = {
                    {
                        { id = "r1" },
                        { id = "r2" },
                    },
                },
                p1_format_topn_lines = {
                    {
                        ranked = {
                            { id = "r1" },
                            { id = "r2" },
                        },
                        n = 5,
                    },
                },
                p1_capture_topn_items = {
                    {
                        ranked = {
                            { id = "r1" },
                            { id = "r2" },
                        },
                        n = 5,
                    },
                },
                p1_push_recent_rejects = {
                    {
                        ctx = { tick = 77 },
                        rejected = {
                            "rej-1",
                            "rej-2",
                        },
                    },
                },
                p1_reject_top = {
                    {
                        reject_counts = {
                            out_of_range = 2,
                        },
                        proposal_count = 3,
                    },
                },
                p1_set_pending_globals = 1,
                p1_build_lock_summary = {
                    {
                        ctx = { tick = 77 },
                        locks = {
                            movement = true,
                        },
                    },
                },
            },
        },
    },
    {
        fixture_id = "dryrun_publish_no_selected_with_commit_reason",
        helper = "publish",
        description = "missing selected with commit reason sets commit_invalidated noop reason",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = {
                        "seed-1",
                    },
                },
            },
            globals = {},
            ctx = {
                tick = 900,
            },
            selected = nil,
            ranked = {},
            reject_counts = {},
            rejected = {},
            proposals = {
                { id = "p10" },
            },
            locks = {},
            plan = nil,
            commit_reason = "revalidate_failed",
            helper_returns = {
                top3 = "",
                top3_verbose = "",
                top5_lines = {},
                top5_items = {},
                reject_top = "",
                lock_summary = "",
            },
            recent_rejects_after_push = {
                "seed-1",
            },
        },
        expected = {
            result = nil,
            scheduler_phase1 = {
                last_plan = nil,
                last_noop_reason = "commit_invalidated:revalidate_failed",
                last_selected = nil,
                last_top3 = "",
                last_top3_verbose = "",
                last_top5_items = {},
                last_top5_lines = {},
                last_reject_top = "",
                recent_rejects = {
                    "seed-1",
                },
            },
            globals = {
                UC_SCHED_P1_TICK = 900,
                UC_SCHED_P1_SELECTED_PROPOSAL = "",
                UC_SCHED_P1_SELECTED_PROVIDER = "",
                UC_SCHED_P1_SELECTED_FAMILY = "",
                UC_SCHED_P1_PLAN_PRELUDE = "",
                UC_SCHED_P1_LOCK_SUMMARY = "",
                UC_SCHED_P1_REJECT_TOP = "",
                UC_SCHED_P1_NOOP_REASON = "commit_invalidated:revalidate_failed",
                UC_SCHED_P1_TOP3 = "",
                UC_SCHED_P1_TOP3_VERBOSE = "",
                UC_SCHED_P1_TOP5 = "",
                UC_SCHED_P1_REJECT5 = "seed-1",
            },
            calls = {
                p1_format_top3 = {
                    {},
                },
                p1_format_top3_verbose = {
                    {},
                },
                p1_format_topn_lines = {
                    {
                        ranked = {},
                        n = 5,
                    },
                },
                p1_capture_topn_items = {
                    {
                        ranked = {},
                        n = 5,
                    },
                },
                p1_push_recent_rejects = {
                    {
                        ctx = { tick = 900 },
                        rejected = {},
                    },
                },
                p1_reject_top = {
                    {
                        reject_counts = {},
                        proposal_count = 1,
                    },
                },
                p1_set_pending_globals = 1,
                p1_build_lock_summary = {
                    {
                        ctx = { tick = 900 },
                        locks = {},
                    },
                },
            },
        },
    },
    {
        fixture_id = "dryrun_publish_no_selected_no_proposals",
        helper = "publish",
        description = "no selected and zero proposals sets no_proposals noop reason",
        input = {
            scheduler = {
                phase1 = {
                    recent_rejects = {},
                },
            },
            globals = {},
            ctx = {
                tick = 5,
            },
            selected = nil,
            ranked = {},
            reject_counts = {
                stale = 9,
            },
            rejected = {
                "rej-x",
            },
            proposals = {},
            locks = {
                hard_lock = false,
            },
            plan = {
                prelude = {},
            },
            commit_reason = nil,
            helper_returns = {
                top3 = "A",
                top3_verbose = "B",
                top5_lines = { "only" },
                top5_items = {},
                reject_top = "rt",
                lock_summary = "ls",
            },
            recent_rejects_after_push = {},
        },
        expected = {
            result = nil,
            scheduler_phase1 = {
                last_noop_reason = "no_proposals",
                last_plan = {
                    prelude = {},
                },
                last_selected = nil,
                last_top3 = "A",
                last_top3_verbose = "B",
                last_top5_items = {},
                last_top5_lines = { "only" },
                last_reject_top = "rt",
                recent_rejects = {},
            },
            globals = {
                UC_SCHED_P1_TICK = 5,
                UC_SCHED_P1_SELECTED_PROPOSAL = "",
                UC_SCHED_P1_SELECTED_PROVIDER = "",
                UC_SCHED_P1_SELECTED_FAMILY = "",
                UC_SCHED_P1_PLAN_PRELUDE = "",
                UC_SCHED_P1_LOCK_SUMMARY = "ls",
                UC_SCHED_P1_REJECT_TOP = "rt",
                UC_SCHED_P1_NOOP_REASON = "no_proposals",
                UC_SCHED_P1_TOP3 = "A",
                UC_SCHED_P1_TOP3_VERBOSE = "B",
                UC_SCHED_P1_TOP5 = "only",
                UC_SCHED_P1_REJECT5 = "",
            },
            calls = {
                p1_format_top3 = {
                    {},
                },
                p1_format_top3_verbose = {
                    {},
                },
                p1_format_topn_lines = {
                    {
                        ranked = {},
                        n = 5,
                    },
                },
                p1_capture_topn_items = {
                    {
                        ranked = {},
                        n = 5,
                    },
                },
                p1_push_recent_rejects = {
                    {
                        ctx = { tick = 5 },
                        rejected = { "rej-x" },
                    },
                },
                p1_reject_top = {
                    {
                        reject_counts = {
                            stale = 9,
                        },
                        proposal_count = 0,
                    },
                },
                p1_set_pending_globals = 1,
                p1_build_lock_summary = {
                    {
                        ctx = { tick = 5 },
                        locks = { hard_lock = false },
                    },
                },
            },
        },
    },
}
