return {
    {
        fixture_id = "enemy_utils_normalize_nil_returns_empty",
        helper = "normalize_status_removal_key",
        description = "nil buff resource returns empty key",
        input = {
            buff_res = nil,
        },
        expected = {
            result = "",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_missing_en_returns_empty",
        helper = "normalize_status_removal_key",
        description = "missing en field returns empty key",
        input = {
            buff_res = {},
        },
        expected = {
            result = "",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_spaces_to_underscores",
        helper = "normalize_status_removal_key",
        description = "multiple words normalize to lower snake style",
        input = {
            buff_res = { en = "Magic Defense Boost" },
        },
        expected = {
            result = "magic_defense_boost",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_existing_underscore_behavior",
        helper = "normalize_status_removal_key",
        description = "existing underscore is preserved while lowercased",
        input = {
            buff_res = { en = "Magic_Shield" },
        },
        expected = {
            result = "magic_shield",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_blindness_to_blind",
        helper = "normalize_status_removal_key",
        description = "blindness normalizes to blind",
        input = {
            buff_res = { en = "Blindness" },
        },
        expected = {
            result = "blind",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_whitespace_and_case",
        helper = "normalize_status_removal_key",
        description = "spaces become underscores and case lowers",
        input = {
            buff_res = { en = "Slow II" },
        },
        expected = {
            result = "slow_ii",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_missing_name_empty",
        helper = "normalize_status_removal_key",
        description = "missing buff name returns empty key",
        input = {
            buff_res = {},
        },
        expected = {
            result = "",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_petrification",
        helper = "normalize_status_removal_key",
        description = "Windower Petrification resource name normalizes to the canonical key",
        input = {
            buff_res = { en = "petrification" },
            buff_id = 7,
        },
        expected = {
            result = "petrification",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_petrified_alias",
        helper = "normalize_status_removal_key",
        description = "petrified resource aliases normalize to Petrification",
        input = {
            buff_res = { en = "Petrified" },
            buff_id = 7,
        },
        expected = {
            result = "petrification",
        },
    },
    {
        fixture_id = "enemy_utils_normalize_petrification_id_fallback",
        helper = "normalize_status_removal_key",
        description = "buff id 7 remains recognizable even if the resource row is unavailable",
        input = {
            buff_res = nil,
            buff_id = 7,
        },
        expected = {
            result = "petrification",
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_nil_priority_72",
        helper = "danger_weight_to_priority",
        description = "nil weight maps through tonumber fallback to priority 72",
        input = {
            w = nil,
        },
        expected = {
            result = 72,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_2_priority_76",
        helper = "danger_weight_to_priority",
        description = "weight 2 maps to priority 76",
        input = {
            w = 2,
        },
        expected = {
            result = 76,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_3_priority_82",
        helper = "danger_weight_to_priority",
        description = "weight 3 maps to priority 82",
        input = {
            w = 3,
        },
        expected = {
            result = 82,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_5_priority_94",
        helper = "danger_weight_to_priority",
        description = "weight 5 maps to default top priority 94",
        input = {
            w = 5,
        },
        expected = {
            result = 94,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_string_numeric_3_priority_82",
        helper = "danger_weight_to_priority",
        description = "numeric string weight is converted and mapped",
        input = {
            w = "3",
        },
        expected = {
            result = 82,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_non_numeric_priority_72",
        helper = "danger_weight_to_priority",
        description = "non-numeric string falls back to zero then priority 72",
        input = {
            w = "abc",
        },
        expected = {
            result = 72,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_priority_low",
        helper = "danger_weight_to_priority",
        description = "weight <=1 maps to priority 72",
        input = {
            w = 1,
        },
        expected = {
            result = 72,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_priority_mid_high",
        helper = "danger_weight_to_priority",
        description = "weight 4 maps to priority 88",
        input = {
            w = 4,
        },
        expected = {
            result = 88,
        },
    },
    {
        fixture_id = "enemy_utils_danger_weight_priority_default_top",
        helper = "danger_weight_to_priority",
        description = "weight above range maps to fallback 94",
        input = {
            w = 9,
        },
        expected = {
            result = 94,
        },
    },
    {
        fixture_id = "enemy_utils_claim_valid_string_numeric_claim",
        helper = "enemy_dispel_claim_valid",
        description = "string numeric claim id is converted and validated",
        input = {
            claim_id = "1234",
            party_claim_set = { [1234] = true },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "enemy_utils_claim_invalid_zero",
        helper = "enemy_dispel_claim_valid",
        description = "zero claim id is always invalid",
        input = {
            claim_id = 0,
            party_claim_set = { [0] = true },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "enemy_utils_claim_invalid_nil_set",
        helper = "enemy_dispel_claim_valid",
        description = "nil party claim set is invalid",
        input = {
            claim_id = 1234,
            party_claim_set = nil,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "enemy_utils_claim_invalid_string_key_in_set",
        helper = "enemy_dispel_claim_valid",
        description = "string key does not satisfy numeric claim lookup strictness",
        input = {
            claim_id = 1234,
            party_claim_set = { ["1234"] = true },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "enemy_utils_claim_valid_true",
        helper = "enemy_dispel_claim_valid",
        description = "positive claim id present in party set is valid",
        input = {
            claim_id = 101,
            party_claim_set = { [101] = true },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "enemy_utils_claim_valid_false_missing_or_bad",
        helper = "enemy_dispel_claim_valid",
        description = "missing claim entry returns false",
        input = {
            claim_id = 101,
            party_claim_set = { [202] = true },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "enemy_utils_label_nil_id",
        helper = "enemy_effect_log_label",
        description = "nil effect id falls back to id:0",
        input = {
            deps = { buffs = {} },
            effect_id = nil,
        },
        expected = {
            result = "id:0",
        },
    },
    {
        fixture_id = "enemy_utils_label_unknown_buff_fallback",
        helper = "enemy_effect_log_label",
        description = "unknown buff id falls back to id label",
        input = {
            deps = { buffs = {} },
            effect_id = 9999,
        },
        expected = {
            result = "id:9999",
        },
    },
    {
        fixture_id = "enemy_utils_label_known_buff_empty_name_fallback",
        helper = "enemy_effect_log_label",
        description = "known buff row with empty name still falls back to id label",
        input = {
            deps = {
                buffs = {
                    [77] = { en = "" },
                },
            },
            effect_id = 77,
        },
        expected = {
            result = "id:77",
        },
    },
    {
        fixture_id = "enemy_utils_label_string_numeric_id",
        helper = "enemy_effect_log_label",
        description = "string numeric effect id is converted before lookup and formatting",
        input = {
            deps = {
                buffs = {
                    [13] = { en = "Slow" },
                },
            },
            effect_id = "13",
        },
        expected = {
            result = "Slow(13)",
        },
    },
    {
        fixture_id = "enemy_utils_log_label_named_effect",
        helper = "enemy_effect_log_label",
        description = "named buff label includes name and id",
        input = {
            deps = {
                buffs = {
                    [13] = { en = "Slow" },
                },
            },
            effect_id = 13,
        },
        expected = {
            result = "Slow(13)",
        },
    },
    {
        fixture_id = "enemy_utils_log_label_unknown_or_nonpositive",
        helper = "enemy_effect_log_label",
        description = "unknown/invalid effects fall back to id label",
        input = {
            deps = { buffs = {} },
            effect_id = 0,
        },
        expected = {
            result = "id:0",
        },
    },
}
