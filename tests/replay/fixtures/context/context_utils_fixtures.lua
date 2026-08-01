local function make_windower(stubs)
    stubs = stubs or {}
    local info = stubs.info
    local mobs_by_id = stubs.mobs_by_id or {}
    local mobs_by_index = stubs.mobs_by_index or {}
    return {
        ffxi = {
            get_info = function()
                return info
            end,
            get_mob_by_id = function(id)
                return mobs_by_id[id]
            end,
            get_mob_by_index = function(index)
                return mobs_by_index[index]
            end,
        },
    }
end

local function make_deps_for_partner(enabled, ordered_ids)
    return {
        bool_setting = function()
            return enabled
        end,
        uc_partner_list = {
            as_ordered_ids = function()
                return ordered_ids
            end,
        },
    }
end

local function make_deps_for_party(members)
    return {
        get_party_members = function()
            return members
        end,
    }
end

return {
    {
        fixture_id = "context_current_zone_id_reads_zone",
        helper = "current_zone_id",
        description = "returns numeric zone from windower info",
        globals = {
            windower = make_windower({ info = { zone = 245 } }),
        },
        expected = {
            result = 245,
        },
    },
    {
        fixture_id = "context_current_zone_id_missing_zone_defaults_zero",
        helper = "current_zone_id",
        description = "missing zone coerces to zero",
        globals = {
            windower = make_windower({ info = {} }),
        },
        expected = {
            result = 0,
        },
    },
    {
        fixture_id = "context_get_settings_reads_uc_settings",
        helper = "get_settings",
        description = "returns UC_SETTINGS when present",
        globals = {
            UC_SETTINGS = { partner = true, sample = "x" },
        },
        expected = {
            result = { partner = true, sample = "x" },
        },
    },
    {
        fixture_id = "context_get_settings_missing_returns_empty_table",
        helper = "get_settings",
        description = "returns empty table when UC_SETTINGS absent",
        globals = {
            UC_SETTINGS = nil,
        },
        expected = {
            result = {},
        },
    },
    {
        fixture_id = "context_city_zone_blocked_name_true",
        helper = "is_city_zone_for_maintenance",
        description = "blocked zone names table match returns true",
        globals = {
            windower = make_windower({ info = { zone = 230 } }),
            res = {
                zones = {
                    [230] = { en = "Western Adoulin" },
                },
            },
        },
        input = {
            maintenance_blocked_zone_names = { ["western adoulin"] = true },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "context_city_zone_mog_house_fallback_true",
        helper = "is_city_zone_for_maintenance",
        description = "mog house name fallback treated as blocked",
        globals = {
            windower = make_windower({ info = { zone = 1 } }),
            res = {
                zones = {
                    [1] = { en = "Bastok Markets [S] Mog House" },
                },
            },
        },
        input = {
            maintenance_blocked_zone_names = {},
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "context_city_zone_non_blocked_false",
        helper = "is_city_zone_for_maintenance",
        description = "non-blocked, non-fallback zone returns false",
        globals = {
            windower = make_windower({ info = { zone = 100 } }),
            res = {
                zones = {
                    [100] = { en = "Yuhtunga Jungle" },
                },
            },
        },
        input = {
            maintenance_blocked_zone_names = {},
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "context_partner_target_set_disabled_empty",
        helper = "build_partner_target_set",
        description = "disabled partner mode returns empty set",
        globals = {
            windower = make_windower({}),
        },
        input = {
            deps = make_deps_for_partner(false, { 1001, 1002 }),
            settings = { partner = false },
        },
        expected = {
            result = {},
        },
    },
    {
        fixture_id = "context_partner_target_set_collects_targets",
        helper = "build_partner_target_set",
        description = "partner ids resolve to targeted mob ids",
        globals = {
            windower = make_windower({
                mobs_by_id = {
                    [1001] = { target_index = 77 },
                    [1002] = { target_index = 88 },
                },
                mobs_by_index = {
                    [77] = { id = 2001 },
                    [88] = { id = 2002 },
                },
            }),
        },
        input = {
            deps = make_deps_for_partner(true, { 1001, 1002 }),
            settings = { partner = true },
        },
        expected = {
            result = { [2001] = true, [2002] = true },
        },
    },
    {
        fixture_id = "context_partner_target_set_skips_invalid_targets",
        helper = "build_partner_target_set",
        description = "invalid/zero target ids are ignored",
        globals = {
            windower = make_windower({
                mobs_by_id = {
                    [1001] = { target_index = 77 },
                    [1002] = { target_index = 88 },
                },
                mobs_by_index = {
                    [77] = { id = 0 },
                    [88] = nil,
                },
            }),
        },
        input = {
            deps = make_deps_for_partner(true, { 1001, 1002 }),
            settings = { partner = true },
        },
        expected = {
            result = {},
        },
    },
    {
        fixture_id = "context_p1_build_party_id_set_basic",
        helper = "p1_build_party_id_set",
        description = "builds set of positive numeric member ids",
        input = {
            deps = make_deps_for_party({
                { id = 101 },
                { id = "202" },
                { id = 0 },
                {},
            }),
        },
        expected = {
            result = { [101] = true, [202] = true },
        },
    },
    {
        fixture_id = "context_p1_build_party_id_set_empty_members",
        helper = "p1_build_party_id_set",
        description = "empty party list returns empty set",
        input = {
            deps = make_deps_for_party({}),
        },
        expected = {
            result = {},
        },
    },
}
