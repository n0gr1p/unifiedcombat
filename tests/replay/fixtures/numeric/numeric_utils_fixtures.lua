return {
    {
        fixture_id = "numeric_p1_number_string_numeric",
        helper = "p1_number",
        description = "numeric string converts to number",
        input = {
            value = "12.5",
            default = 0,
        },
        expected = {
            result = 12.5,
        },
    },
    {
        fixture_id = "numeric_p1_number_number_passthrough",
        helper = "p1_number",
        description = "numeric input passes through",
        input = {
            value = 42,
            default = 0,
        },
        expected = {
            result = 42,
        },
    },
    {
        fixture_id = "numeric_p1_number_invalid_returns_default",
        helper = "p1_number",
        description = "invalid numeric input returns default",
        input = {
            value = "abc",
            default = 7,
        },
        expected = {
            result = 7,
        },
    },
    {
        fixture_id = "numeric_p1_number_nil_returns_default",
        helper = "p1_number",
        description = "nil input returns default",
        input = {
            value = nil,
            default = -3,
        },
        expected = {
            result = -3,
        },
    },
    {
        fixture_id = "numeric_p1_clamp_urgency_mid",
        helper = "p1_clamp_urgency",
        description = "mid-range urgency is unchanged",
        input = {
            value = 0.25,
        },
        expected = {
            result = 0.25,
        },
    },
    {
        fixture_id = "numeric_p1_clamp_urgency_low_clamped",
        helper = "p1_clamp_urgency",
        description = "negative urgency clamps to zero",
        input = {
            value = -2,
        },
        expected = {
            result = 0,
        },
    },
    {
        fixture_id = "numeric_p1_clamp_urgency_high_clamped",
        helper = "p1_clamp_urgency",
        description = "urgency above one clamps to one",
        input = {
            value = 9,
        },
        expected = {
            result = 1,
        },
    },
    {
        fixture_id = "numeric_p1_clamp_urgency_string_numeric",
        helper = "p1_clamp_urgency",
        description = "numeric string urgency converts then clamps",
        input = {
            value = "0.75",
        },
        expected = {
            result = 0.75,
        },
    },
    {
        fixture_id = "numeric_p1_clamp_urgency_invalid_to_zero",
        helper = "p1_clamp_urgency",
        description = "invalid urgency value falls back to zero",
        input = {
            value = "not-a-number",
        },
        expected = {
            result = 0,
        },
    },
    {
        fixture_id = "numeric_bool_setting_nil_uses_default_true",
        helper = "bool_setting",
        description = "nil value returns true when default true",
        input = {
            value = nil,
            default = true,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "numeric_bool_setting_nil_uses_default_false",
        helper = "bool_setting",
        description = "nil value returns false when default false",
        input = {
            value = nil,
            default = false,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "numeric_bool_setting_true_boolean",
        helper = "bool_setting",
        description = "true boolean is true",
        input = {
            value = true,
            default = false,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "numeric_bool_setting_numeric_one",
        helper = "bool_setting",
        description = "numeric one is true",
        input = {
            value = 1,
            default = false,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "numeric_bool_setting_string_yes",
        helper = "bool_setting",
        description = "yes string is true",
        input = {
            value = "yes",
            default = false,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "numeric_bool_setting_string_on_upper",
        helper = "bool_setting",
        description = "case-insensitive on string is true",
        input = {
            value = "ON",
            default = false,
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "numeric_bool_setting_string_zero_false",
        helper = "bool_setting",
        description = "string zero is false",
        input = {
            value = "0",
            default = true,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "numeric_bool_setting_numeric_zero_false",
        helper = "bool_setting",
        description = "numeric zero is false",
        input = {
            value = 0,
            default = true,
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "numeric_bool_setting_unknown_string_false",
        helper = "bool_setting",
        description = "unknown string is false",
        input = {
            value = "maybe",
            default = true,
        },
        expected = {
            result = false,
        },
    },
}
