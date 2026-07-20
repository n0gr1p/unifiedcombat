local function make_windower(mobs_by_id)
    mobs_by_id = mobs_by_id or {}
    return {
        ffxi = {
            get_mob_by_id = function(id)
                return mobs_by_id[id]
            end,
        },
    }
end

return {
    {
        fixture_id = "dispatch_plan_build_nil_selected",
        helper = "p1_build_dispatch_plan",
        description = "nil selected returns nil plan",
        input = {
            scheduler = {},
            ctx = { now = 12.5, tick = 4.2 },
            selected = nil,
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = nil,
        },
    },
    {
        fixture_id = "dispatch_plan_build_basic",
        helper = "p1_build_dispatch_plan",
        description = "builds plan with defaults and coercions",
        input = {
            scheduler = {},
            ctx = { now = 123.45, tick = 7.9 },
            selected = {
                proposal_id = "prop.1",
                movement_policy = "none",
                action_type = "spell",
                action_name = "Cure IV",
                target_id = "1001",
                target_name = "Bob",
                commit_deadline = nil,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = {
                plan_id = "plan.123450.7",
                selected_proposal_id = "prop.1",
                prelude = {
                    type = "none",
                    target_id = 1001,
                    timeout_s = 0.20,
                },
                primary = {
                    action_type = "spell",
                    action_name = "Cure IV",
                    target_id = 1001,
                    target_name = "Bob",
                },
                commit_deadline = 123.70,
                created_at = 123.45,
            },
        },
    },
    {
        fixture_id = "dispatch_plan_build_must_stop_and_custom_deadline",
        helper = "p1_build_dispatch_plan",
        description = "must_stop sets stop prelude and honors commit_deadline through p1_number",
        input = {
            scheduler = {},
            ctx = { now = 40, tick = 3 },
            selected = {
                proposal_id = 99,
                movement_policy = "must_stop",
                action_type = "ja",
                action_name = "Provoke",
                target_id = 2002,
                target_name = nil,
                commit_deadline = "44.5",
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
        },
        expected = {
            result = {
                plan_id = "plan.40000.3",
                selected_proposal_id = "99",
                prelude = {
                    type = "stop",
                    target_id = 2002,
                    timeout_s = 0.20,
                },
                primary = {
                    action_type = "ja",
                    action_name = "Provoke",
                    target_id = 2002,
                    target_name = "",
                },
                commit_deadline = 44.5,
                created_at = 40,
            },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_invalid_plan",
        helper = "p1_revalidate_plan_commit",
        description = "missing selected/plan returns invalid_plan",
        input = {
            scheduler = {},
            ctx = { now = 10 },
            selected = nil,
            plan = nil,
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({}),
        },
        expected = {
            result = { false, "invalid_plan" },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_expired",
        helper = "p1_revalidate_plan_commit",
        description = "expired selected proposal is rejected",
        input = {
            scheduler = {},
            ctx = { now = 50 },
            selected = {
                expires_at = 49,
                target_kind = "self",
            },
            plan = {
                commit_deadline = 60,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({}),
        },
        expected = {
            result = { false, "expired" },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_commit_deadline",
        helper = "p1_revalidate_plan_commit",
        description = "expired commit_deadline is rejected",
        input = {
            scheduler = {},
            ctx = { now = 50 },
            selected = {
                expires_at = 55,
                target_kind = "self",
            },
            plan = {
                commit_deadline = 49.9,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({}),
        },
        expected = {
            result = { false, "commit_deadline" },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_self_ok",
        helper = "p1_revalidate_plan_commit",
        description = "self target kind bypasses mob checks",
        input = {
            scheduler = {},
            ctx = { now = 20 },
            selected = {
                expires_at = 25,
                target_kind = "self",
                target_id = 0,
            },
            plan = {
                commit_deadline = 30,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({}),
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_ally_valid",
        helper = "p1_revalidate_plan_commit",
        description = "ally target requires positive id and existing mob",
        input = {
            scheduler = {},
            ctx = { now = 20 },
            selected = {
                expires_at = 25,
                target_kind = "ally",
                target_id = 3003,
            },
            plan = {
                commit_deadline = 30,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({ [3003] = { id = 3003, name = "Ally" } }),
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_mob_invalid_hpp",
        helper = "p1_revalidate_plan_commit",
        description = "mob target requires valid_target and positive hpp",
        input = {
            scheduler = {},
            ctx = { now = 20 },
            selected = {
                expires_at = 25,
                target_kind = "mob",
                target_id = 4004,
            },
            plan = {
                commit_deadline = 30,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({ [4004] = { id = 4004, valid_target = true, hpp = 0 } }),
        },
        expected = {
            result = { false, "invalid_target" },
        },
    },
    {
        fixture_id = "dispatch_plan_revalidate_other_kind_ok",
        helper = "p1_revalidate_plan_commit",
        description = "unhandled target kind returns ok",
        input = {
            scheduler = {},
            ctx = { now = 20 },
            selected = {
                expires_at = 25,
                target_kind = "none",
                target_id = 0,
            },
            plan = {
                commit_deadline = 30,
            },
            p1_number = function(v, fallback) return tonumber(v) or fallback end,
            windower = make_windower({}),
        },
        expected = {
            result = { true, "" },
        },
    },
	{
		fixture_id = "dispatch_plan_build_skillchain",
		helper = "p1_build_dispatch_plan",
		description = "structured skillchain plan is carried into the dispatch plan",
		input = {
			scheduler = {},
			ctx = { now = 25, tick = 9 },
			selected = {
				proposal_id = "sc.1",
				action_type = "ws",
				action_name = "Tachi: Fudo",
				target_id = 5005,
				target_name = "Target",
				skillchain_plan = {
					kind = "skillchain_continuation",
					resonance_generation = 7,
				},
			},
			p1_number = function(v, fallback) return tonumber(v) or fallback end,
		},
		expected = {
			result = {
				plan_id = "plan.25000.9",
				selected_proposal_id = "sc.1",
				prelude = { type = "none", target_id = 5005, timeout_s = 0.20 },
				primary = { action_type = "ws", action_name = "Tachi: Fudo", target_id = 5005, target_name = "Target" },
				skillchain_plan = { kind = "skillchain_continuation", resonance_generation = 7 },
				commit_deadline = 25.25,
				created_at = 25,
			},
		},
	},
	{
		fixture_id = "dispatch_plan_revalidate_skillchain_core_reason",
		helper = "p1_revalidate_plan_commit",
		description = "skillchain commit delegates to the core atomic validator",
		input = {
			scheduler = {},
			ctx = { now = 25, settings = { weaponskill_active = true } },
			selected = { expires_at = 26, target_id = 5005, action_name = "Tachi: Fudo" },
			plan = {
				commit_deadline = 25.2,
				skillchain_plan = { kind = "skillchain_continuation", resonance_generation = 7 },
			},
			p1_number = function(v, fallback) return tonumber(v) or fallback end,
			windower = make_windower({}),
			combat_core = {
				revalidate_skillchain_plan = function(plan, settings, target_id, ws_name)
					if plan.resonance_generation == 7 and settings.weaponskill_active and target_id == 5005 and ws_name == "Tachi: Fudo" then
						return false, "SC_RESONANCE_CHANGED"
					end
					error("unexpected skillchain revalidation inputs")
				end,
			},
		},
		expected = {
			result = { false, "SC_RESONANCE_CHANGED" },
		},
	},
}
