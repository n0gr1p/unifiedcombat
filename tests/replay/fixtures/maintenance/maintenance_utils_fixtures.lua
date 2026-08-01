local function contains_set(values)
    local lookup = {}
    for _, v in ipairs(values or {}) do
        lookup[v] = true
    end
    return {
        contains = function(self, value)
            return lookup[value] == true
        end,
    }
end

return {
    {
        fixture_id = "maintenance_utils_set_has_table_true",
        helper = "set_has",
        description = "plain table set contains value",
        input = {
            set = { foo = true },
            value = "foo",
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "maintenance_utils_set_has_table_false",
        helper = "set_has",
        description = "plain table set missing value returns false",
        input = {
            set = { foo = true },
            value = "bar",
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "maintenance_utils_set_has_contains_method",
        helper = "set_has",
        description = "contains method is used when available",
        input = {
            set = contains_set({ "x", "y" }),
            value = "y",
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "maintenance_utils_set_has_non_table",
        helper = "set_has",
        description = "non-table set returns false",
        input = {
            set = "not-a-table",
            value = "foo",
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "maintenance_utils_dedupe_numeric_ids_basic",
        helper = "dedupe_numeric_ids",
        description = "dedupe keeps first positive numeric occurrences",
        input = {
            ids = { 5, "5", 3, 5, "3", 2 },
        },
        expected = {
            result = { 5, 3, 2 },
        },
    },
    {
        fixture_id = "maintenance_utils_dedupe_numeric_ids_filters_non_positive",
        helper = "dedupe_numeric_ids",
        description = "non-positive and invalid values are ignored",
        input = {
            ids = { 0, -1, "abc", nil, "4" },
        },
        expected = {
            result = {},
        },
    },
    {
        fixture_id = "maintenance_utils_dedupe_numeric_ids_nil_input",
        helper = "dedupe_numeric_ids",
        description = "nil ids input returns empty list",
        input = {
            ids = nil,
        },
        expected = {
            result = {},
        },
    },
    {
        fixture_id = "maintenance_utils_split_actions_string_delimiters",
        helper = "split_actions",
        description = "string input splits on comma and pipe and normalizes tokens",
        input = {
            raw = " cure 2 | boost-str,  protect   ix ",
        },
        expected = {
            result = { "cure II", "boost-str", "protect IX" },
        },
    },
    {
        fixture_id = "maintenance_utils_split_actions_table_input",
        helper = "split_actions",
        description = "table input normalizes each non-empty entry",
        input = {
            raw = { "Haste 2", "", false, "Mage’s Ballad" },
        },
        expected = {
            result = { "Haste II", "Mage'''s Ballad" },
        },
    },
    {
        fixture_id = "maintenance_utils_split_actions_empty_string",
        helper = "split_actions",
        description = "empty raw string yields empty list",
        input = {
            raw = "",
        },
        expected = {
            result = {},
        },
    },
    {
        fixture_id = "maintenance_utils_canon_name_trim_and_quotes",
        helper = "canon_name",
        description = "canon_name trims whitespace and normalizes apostrophes",
        input = {
            value = "  Mage’s   Ballad  ",
        },
        expected = {
            result = "Mage'''s Ballad",
        },
    },
    {
        fixture_id = "maintenance_utils_canon_name_json_escape_ascii",
        helper = "canon_name",
        description = "canon_name decodes ascii json escapes",
        input = {
            value = "\\u0048aste",
        },
        expected = {
            result = "Haste",
        },
    },
    {
        fixture_id = "maintenance_utils_count_matching_buffs_basic",
        helper = "count_matching_buffs",
        description = "counts occurrences in buff list that exist in id set",
        input = {
            buff_list = { 1, 2, 2, 3, 4 },
            id_set = { [2] = true, [4] = true },
        },
        expected = {
            result = 3,
        },
    },
    {
        fixture_id = "maintenance_utils_count_matching_buffs_invalid_inputs",
        helper = "count_matching_buffs",
        description = "invalid input types return 0",
        input = {
            buff_list = "not-a-table",
            id_set = { [1] = true },
        },
        expected = {
            result = 0,
        },
    },
    {
        fixture_id = "maintenance_utils_count_buff_occurrences_basic",
        helper = "count_buff_occurrences",
        description = "counts each buff id occurrence",
        input = {
            buffs = { 3, 3, 2, 3, 2, 9 },
        },
        expected = {
            result = { [3] = 3, [2] = 2, [9] = 1 },
        },
    },
    {
        fixture_id = "maintenance_utils_count_buff_occurrences_nil_input",
        helper = "count_buff_occurrences",
        description = "nil input returns empty map",
        input = {
            buffs = nil,
        },
        expected = {
            result = {},
        },
    },
}
