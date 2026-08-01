local function p1_number(v, default_value)
    local n = tonumber(v)
    if n == nil then
        return default_value
    end
    return n
end

return {
    {
        fixture_id = "rank_output_format_top3_empty",
        helper = "p1_format_top3",
        description = "empty ranked list returns empty string",
        input = {
            scheduler = {},
            ranked = {},
            p1_number = p1_number,
        },
        expected = {
            result = "",
        },
    },
    {
        fixture_id = "rank_output_format_top3_basic",
        helper = "p1_format_top3",
        description = "formats up to top 3 compact entries",
        input = {
            scheduler = {},
            p1_number = p1_number,
            ranked = {
                { provider = "combat", _score = 10.1, action_name = "Provoke" },
                { provider = "defensive", _score = 9, action_name = "Cure IV" },
                { provider = "maintenance", _score = 3.5, action_name = "Chaos Roll" },
                { provider = "extra", _score = 1.0, action_name = "Ignored" },
            },
        },
        expected = {
            result = "1)combat 10.10 Provoke | 2)defensive 9.00 Cure IV | 3)maintenance 3.50 Chaos Roll",
        },
    },
    {
        fixture_id = "rank_output_format_top3_verbose_basic",
        helper = "p1_format_top3_verbose",
        description = "verbose top3 includes score-part fields with defaults",
        input = {
            scheduler = {},
            p1_number = p1_number,
            ranked = {
                {
                    provider = "combat",
                    _score = 10.25,
                    action_name = "Provoke",
                    _score_parts = {
                        priority_band = 84,
                        urgency_bonus = 1.5,
                        starvation_bonus = 0.5,
                        sticky_bonus = 0,
                        risk_penalty = 0.25,
                    },
                },
            },
        },
        expected = {
            result = "1)combat score=10.25 pb=84 u=1.50 st=0.50 sk=0.00 rp=0.25 Provoke",
        },
    },
    {
        fixture_id = "rank_output_format_topn_lines_n2",
        helper = "p1_format_topn_lines",
        description = "returns formatted lines limited by n",
        input = {
            scheduler = {},
            p1_number = p1_number,
            n = 2,
            ranked = {
                {
                    provider = "combat",
                    family_id = "combat.main",
                    action_name = "Provoke",
                    _score = 10.25,
                    _score_parts = { urgency_bonus = 1.5, risk_penalty = 0.25 },
                },
                {
                    provider = "defensive",
                    family_id = "def.heal",
                    action_name = "Cure IV",
                    _score = 8,
                    _score_parts = { urgency_bonus = 0.75, risk_penalty = 0.1 },
                },
                {
                    provider = "extra",
                    family_id = "extra",
                    action_name = "Ignored",
                    _score = 1,
                    _score_parts = { urgency_bonus = 0, risk_penalty = 0 },
                },
            },
        },
        expected = {
            result = {
                "1) 10.25 combat/combat.main Provoke u=1.50 rp=0.25",
                "2) 8.00 defensive/def.heal Cure IV u=0.75 rp=0.10",
            },
        },
    },
    {
        fixture_id = "rank_output_capture_topn_items_default_n5",
        helper = "p1_capture_topn_items",
        description = "captures top items with normalized fields",
        input = {
            scheduler = {},
            p1_number = p1_number,
            ranked = {
                {
                    provider = "combat",
                    family_id = "combat.main",
                    action_name = "Provoke",
                    _score = 10.25,
                    _score_parts = { urgency_bonus = 1.5, risk_penalty = 0.25 },
                },
                {
                    provider = "defensive",
                    family_id = "def.heal",
                    action_name = "Cure IV",
                    _score = 8,
                    _score_parts = { urgency_bonus = 0.75, risk_penalty = 0.1 },
                },
            },
        },
        expected = {
            result = {
                {
                    idx = 1,
                    score = 10.25,
                    provider = "combat",
                    family = "combat.main",
                    action = "Provoke",
                    urgency_bonus = 1.5,
                    risk_penalty = 0.25,
                },
                {
                    idx = 2,
                    score = 8,
                    provider = "defensive",
                    family = "def.heal",
                    action = "Cure IV",
                    urgency_bonus = 0.75,
                    risk_penalty = 0.1,
                },
            },
        },
    },
    {
        fixture_id = "rank_output_reject_top_no_proposals",
        helper = "p1_reject_top",
        description = "proposal_count <= 0 returns no_proposals",
        input = {
            scheduler = {},
            reject_counts = { out_of_range = 2 },
            proposal_count = 0,
        },
        expected = {
            result = "no_proposals",
        },
    },
    {
        fixture_id = "rank_output_reject_top_best_reason",
        helper = "p1_reject_top",
        description = "returns reason with highest count",
        input = {
            scheduler = {},
            reject_counts = { out_of_range = 4, locked = 1 },
            proposal_count = 5,
        },
        expected = {
            result = "out_of_range:4",
        },
    },
    {
        fixture_id = "rank_output_reject_top_empty_counts",
        helper = "p1_reject_top",
        description = "positive proposals with empty reject table returns empty string",
        input = {
            scheduler = {},
            reject_counts = {},
            proposal_count = 3,
        },
        expected = {
            result = "",
        },
    },
}
