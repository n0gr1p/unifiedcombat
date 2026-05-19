return {
    {
        fixture_id = "proposal_keys_family_basic",
        helper = "family_key",
        description = "family key uses member name and buff id",
        input = {
            member_name = "Alice",
            buff_id = 33,
        },
        expected = {
            result = "Alice:33",
        },
    },
    {
        fixture_id = "proposal_keys_family_numeric_member",
        helper = "family_key",
        description = "numeric member values are stringified",
        input = {
            member_name = 101,
            buff_id = 55,
        },
        expected = {
            result = "101:55",
        },
    },
    {
        fixture_id = "proposal_keys_family_nil_values",
        helper = "family_key",
        description = "nil values stringify via tostring",
        input = {
            member_name = nil,
            buff_id = nil,
        },
        expected = {
            result = "nil:nil",
        },
    },
    {
        fixture_id = "proposal_keys_family_empty_name",
        helper = "family_key",
        description = "empty member name still preserves delimiter",
        input = {
            member_name = "",
            buff_id = 77,
        },
        expected = {
            result = ":77",
        },
    },
    {
        fixture_id = "proposal_keys_family_string_buff_id",
        helper = "family_key",
        description = "string buff id is used as-is after tostring",
        input = {
            member_name = "Bob",
            buff_id = "88",
        },
        expected = {
            result = "Bob:88",
        },
    },
    {
        fixture_id = "proposal_keys_attempt_basic",
        helper = "attempt_key",
        description = "attempt key joins kind/member/action with double colon",
        input = {
            kind = "buff_refresh",
            member_name = "Alice",
            action_name = "Cure IV",
        },
        expected = {
            result = "buff_refresh::Alice::Cure IV",
        },
    },
    {
        fixture_id = "proposal_keys_attempt_numeric_kind",
        helper = "attempt_key",
        description = "numeric kind is stringified",
        input = {
            kind = 1,
            member_name = "Alice",
            action_name = "Haste",
        },
        expected = {
            result = "1::Alice::Haste",
        },
    },
    {
        fixture_id = "proposal_keys_attempt_nil_fields",
        helper = "attempt_key",
        description = "nil fields stringify to literal nil",
        input = {
            kind = nil,
            member_name = nil,
            action_name = nil,
        },
        expected = {
            result = "nil::nil::nil",
        },
    },
    {
        fixture_id = "proposal_keys_attempt_empty_action_name",
        helper = "attempt_key",
        description = "empty action field preserves separators",
        input = {
            kind = "kind",
            member_name = "member",
            action_name = "",
        },
        expected = {
            result = "kind::member::",
        },
    },
    {
        fixture_id = "proposal_keys_attempt_member_contains_separator",
        helper = "attempt_key",
        description = "existing separator text in member is preserved",
        input = {
            kind = "k",
            member_name = "A::B",
            action_name = "Act",
        },
        expected = {
            result = "k::A::B::Act",
        },
    },
}
