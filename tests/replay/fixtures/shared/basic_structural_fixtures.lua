return {
    {
        fixture_id = "shared_equal_nested_pass",
        description = "old/new payloads are structurally equal with nested content",
        tags = { "shared", "structural", "pass" },
        input = {
            old_normalized = {
                state = {
                    mode = "engaged",
                    hp_ok = true,
                    counters = { pulls = 0, ticks = 3 },
                },
            },
            new_normalized = {
                state = {
                    mode = "engaged",
                    hp_ok = true,
                    counters = { pulls = 0, ticks = 3 },
                },
            },
        },
        expected = {
            same_structure = true,
            side_effects_forbidden = true,
            runner_ok = true,
        },
    },
    {
        fixture_id = "shared_nil_false_mismatch_expected",
        description = "old key absence vs new false value should mismatch structurally",
        tags = { "shared", "structural", "nil-vs-false" },
        input = {
            old_normalized = {
                guard = {
                    can_pull = true,
                },
            },
            new_normalized = {
                guard = {
                    can_pull = true,
                    has_claim = false,
                },
            },
        },
        expected = {
            same_structure = false,
            side_effects_forbidden = true,
            runner_ok = true,
        },
    },
    {
        fixture_id = "shared_numeric_string_key_mismatch_expected",
        description = "numeric key and string key with same digits should not match",
        tags = { "shared", "structural", "key-shape" },
        input = {
            old_normalized = {
                claimed = {
                    [123] = { hp = 100 },
                },
            },
            new_normalized = {
                claimed = {
                    ["123"] = { hp = 100 },
                },
            },
        },
        expected = {
            same_structure = false,
            side_effects_forbidden = true,
            runner_ok = true,
        },
    },
    {
        fixture_id = "shared_ordered_list_mismatch_expected",
        description = "list order changes should be detected as mismatch",
        tags = { "shared", "structural", "list-order" },
        input = {
            old_normalized = {
                queue = { "a", "b", "c" },
            },
            new_normalized = {
                queue = { "a", "c", "b" },
            },
        },
        expected = {
            same_structure = false,
            side_effects_forbidden = true,
            runner_ok = true,
        },
    },
    {
        fixture_id = "shared_side_effects_equal_zero_pass",
        description = "zero side-effect records with attempted=false on both sides",
        tags = { "shared", "side-effects", "zero" },
        input = {
            old_normalized = {
                side_effects = {
                    attempted = false,
                    send_command_count = 0,
                    run_count = 0,
                },
            },
            new_normalized = {
                side_effects = {
                    attempted = false,
                    send_command_count = 0,
                    run_count = 0,
                },
            },
        },
        expected = {
            same_structure = true,
            side_effects_forbidden = true,
            runner_ok = true,
        },
    },
    {
        fixture_id = "shared_side_effect_attempt_expected_fail",
        description = "side effects present and attempted should fail forbidden expectation",
        tags = { "shared", "side-effects", "expected_runner_fail" },
        input = {
            old_normalized = {
                side_effects = {
                    attempted = true,
                    send_command_count = 1,
                    run_count = 0,
                },
            },
            new_normalized = {
                side_effects = {
                    attempted = true,
                    send_command_count = 1,
                    run_count = 0,
                },
            },
        },
        expected = {
            same_structure = true,
            side_effects_forbidden = true,
            runner_ok = false,
        },
    },
}
