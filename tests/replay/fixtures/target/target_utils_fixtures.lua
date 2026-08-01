local function make_distance(value)
    return {
        sqrt = function()
            return value
        end,
    }
end

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
        fixture_id = "target_utils_tank_enmity_selected_true_family",
        helper = "p1_is_tank_enmity_selected",
        description = "selected family id marks tank enmity selection",
        input = {
            scheduler = {},
            selected = {
                family_id = "combat.tank_enmity.primary",
            },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "target_utils_tank_enmity_selected_true_detail_flag",
        helper = "p1_is_tank_enmity_selected",
        description = "selected detail tank_enmity true marks selection",
        input = {
            scheduler = {},
            selected = {
                family_id = "combat.other",
                detail = {
                    tank_enmity = true,
                },
            },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "target_utils_tank_enmity_selected_false_non_table",
        helper = "p1_is_tank_enmity_selected",
        description = "non-table selected input returns false",
        input = {
            scheduler = {},
            selected = false,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "target_utils_tank_enmity_selected_false_other",
        helper = "p1_is_tank_enmity_selected",
        description = "other family without detail flag returns false",
        input = {
            scheduler = {},
            selected = {
                family_id = "combat.other",
                detail = {
                    tank_enmity = false,
                },
            },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "target_utils_target_distance_to_id_found",
        helper = "p1_target_distance_to_id",
        description = "returns sqrt distance and mob when target exists",
        globals = {
            windower = make_windower({
                [1234] = {
                    id = 1234,
                    name = "Target",
                    distance = make_distance(10),
                },
            }),
        },
        input = {
            scheduler = {},
            target_id = 1234,
        },
        expected = {
            result = {
                distance = 10,
                mob_id = 1234,
            },
        },
    },
    {
        fixture_id = "target_utils_target_distance_to_id_missing_mob",
        helper = "p1_target_distance_to_id",
        description = "missing mob returns nil distance and nil mob",
        globals = {
            windower = make_windower({}),
        },
        input = {
            scheduler = {},
            target_id = 1234,
        },
        expected = {
            result = {
                distance = nil,
                mob_id = nil,
            },
        },
    },
    {
        fixture_id = "target_utils_target_distance_to_id_missing_distance",
        helper = "p1_target_distance_to_id",
        description = "mob without distance returns nil distance and nil mob",
        globals = {
            windower = make_windower({
                [1234] = {
                    id = 1234,
                    name = "Target",
                },
            }),
        },
        input = {
            scheduler = {},
            target_id = 1234,
        },
        expected = {
            result = {
                distance = nil,
                mob_id = nil,
            },
        },
    },
}
