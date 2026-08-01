local function make_jobs(rows)
    return {
        with = function(_, key, value)
            if key ~= "english_short" then
                return nil
            end
            return rows[value]
        end,
    }
end

local function make_deps(opts)
    opts = opts or {}
    local spells = opts.spells or {}
    local jas = opts.jas or {}
    return {
        jobs = opts.jobs or make_jobs({}),
        get_spell_resource = function(name)
            return spells[name]
        end,
        get_ja_resource = function(name)
            return jas[name]
        end,
        SCHED_RANGE_MULT = opts.SCHED_RANGE_MULT or {},
    }
end

return {
    {
        fixture_id = "action_meta_spell_known_true_boolean",
        helper = "spell_known_flag",
        description = "true boolean is known",
        input = { value = true },
        expected = { result = true },
    },
    {
        fixture_id = "action_meta_spell_known_one_number",
        helper = "spell_known_flag",
        description = "numeric 1 is known",
        input = { value = 1 },
        expected = { result = true },
    },
    {
        fixture_id = "action_meta_spell_known_true_string",
        helper = "spell_known_flag",
        description = "string true is known",
        input = { value = "true" },
        expected = { result = true },
    },
    {
        fixture_id = "action_meta_spell_known_false_cases",
        helper = "spell_known_flag",
        description = "other values are not known",
        input = { value = "1" },
        expected = { result = false },
    },
    {
        fixture_id = "action_meta_job_id_by_short_found",
        helper = "job_id_by_short",
        description = "english short lookup returns numeric id",
        input = {
            deps = make_deps({
                jobs = make_jobs({
                    WHM = { id = "3" },
                }),
            }),
            short_name = "WHM",
        },
        expected = { result = 3 },
    },
    {
        fixture_id = "action_meta_job_id_by_short_missing",
        helper = "job_id_by_short",
        description = "missing short name returns 0",
        input = {
            deps = make_deps({ jobs = make_jobs({}) }),
            short_name = "XYZ",
        },
        expected = { result = 0 },
    },
    {
        fixture_id = "action_meta_action_status_spell_precedence",
        helper = "action_status_id",
        description = "spell status is returned when numeric",
        input = {
            deps = make_deps({
                spells = { Cure = { status = 11 } },
                jas = { Cure = { status = 77 } },
            }),
            name = "Cure",
        },
        expected = { result = 11 },
    },
    {
        fixture_id = "action_meta_action_status_spell_non_numeric_falls_to_ja",
        helper = "action_status_id",
        description = "non numeric spell status falls back to ja numeric status",
        input = {
            deps = make_deps({
                spells = { Waltz = { status = "11" } },
                jas = { Waltz = { status = 22 } },
            }),
            name = "Waltz",
        },
        expected = { result = 22 },
    },
    {
        fixture_id = "action_meta_action_status_missing_nil",
        helper = "action_status_id",
        description = "missing statuses return nil",
        input = {
            deps = make_deps({}),
            name = "Unknown",
        },
        expected = { result = nil },
    },
    {
        fixture_id = "action_meta_action_duration_spell_positive",
        helper = "action_duration_seconds",
        description = "positive spell duration overrides default",
        input = {
            deps = make_deps({
                spells = { Haste = { duration = 180 } },
            }),
            name = "Haste",
            default_seconds = 30,
        },
        expected = { result = 180 },
    },
    {
        fixture_id = "action_meta_action_duration_spell_zero_default",
        helper = "action_duration_seconds",
        description = "zero spell duration uses default",
        input = {
            deps = make_deps({
                spells = { Buff = { duration = 0 } },
            }),
            name = "Buff",
            default_seconds = 45,
        },
        expected = { result = 45 },
    },
    {
        fixture_id = "action_meta_action_duration_missing_default",
        helper = "action_duration_seconds",
        description = "missing spell uses default",
        input = {
            deps = make_deps({}),
            name = "Missing",
            default_seconds = 60,
        },
        expected = { result = 60 },
    },
    {
        fixture_id = "action_meta_effective_range_non_positive_zero",
        helper = "action_effective_range",
        description = "non positive range returns zero",
        input = {
            deps = make_deps({}),
            raw_range = 0,
        },
        expected = { result = 0 },
    },
    {
        fixture_id = "action_meta_effective_range_multiplier_applied",
        helper = "action_effective_range",
        description = "SCHED_RANGE_MULT entry is applied",
        input = {
            deps = make_deps({
                SCHED_RANGE_MULT = { [20] = 1.5 },
            }),
            raw_range = 20,
        },
        expected = { result = 30 },
    },
    {
        fixture_id = "action_meta_effective_range_gt20_scaled",
        helper = "action_effective_range",
        description = "range over 20 scales by 0.01 without multiplier",
        input = {
            deps = make_deps({}),
            raw_range = 25,
        },
        expected = { result = 0.25 },
    },
    {
        fixture_id = "action_meta_effective_range_default_identity",
        helper = "action_effective_range",
        description = "positive <=20 with no multiplier returns raw",
        input = {
            deps = make_deps({}),
            raw_range = 7,
        },
        expected = { result = 7 },
    },
    {
        fixture_id = "action_meta_target_mode_self_only_spell",
        helper = "action_target_mode",
        description = "spell with only Self target is self_only",
        input = {
            deps = make_deps({
                spells = {
                    Stoneskin = { targets = "Self" },
                },
            }),
            action_name = "Stoneskin",
            action_kind = "spell",
        },
        expected = { result = "self_only" },
    },
    {
        fixture_id = "action_meta_target_mode_numeric_self_only_spell",
        helper = "action_target_mode",
        description = "Windower numeric target mask 1 is self_only",
        input = {
            deps = make_deps({
                spells = {
                    Barwatera = { targets = 1 },
                },
            }),
            action_name = "Barwatera",
            action_kind = "spell",
        },
        expected = { result = "self_only" },
    },
    {
        fixture_id = "action_meta_target_mode_numeric_other_spell",
        helper = "action_target_mode",
        description = "Windower numeric non-self target masks remain normal",
        input = {
            deps = make_deps({
                spells = {
                    Cure = { targets = 3 },
                },
            }),
            action_name = "Cure",
            action_kind = "spell",
        },
        expected = { result = "normal" },
    },
    {
        fixture_id = "action_meta_target_mode_spell_other_player_normal",
        helper = "action_target_mode",
        description = "spell with Player target is normal",
        input = {
            deps = make_deps({
                spells = {
                    Cure = { targets = "Player" },
                },
            }),
            action_name = "Cure",
            action_kind = "spell",
        },
        expected = { result = "normal" },
    },
    {
        fixture_id = "action_meta_target_mode_ja_self_and_party_normal",
        helper = "action_target_mode",
        description = "ja with Self and Party remains normal due to other-target access",
        input = {
            deps = make_deps({
                jas = {
                    Ability = { targets = "Self,Party" },
                },
            }),
            action_name = "Ability",
            action_kind = "ja",
        },
        expected = { result = "normal" },
    },
    {
        fixture_id = "action_meta_target_mode_unknown_kind_normal",
        helper = "action_target_mode",
        description = "unknown action kind defaults to normal",
        input = {
            deps = make_deps({}),
            action_name = "Unknown",
            action_kind = "ws",
        },
        expected = { result = "normal" },
    },
}
