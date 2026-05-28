return {
    {
        fixture_id = "dispatcher_normalize_defaults",
        helper = "normalize_intent",
        description = "normalize applies empty defaults",
        input = {
            intent = nil,
        },
        expected = {
            result = {
                kind = "none",
                reason = "",
                meta = {
                    heading = nil,
                },
                payload = {
                    command = "",
                    run_x = nil,
                    run_y = nil,
                    heading = nil,
                    target_id = 0,
                },
            },
        },
    },
    {
        fixture_id = "dispatcher_normalize_preserves_meta_heading",
        helper = "normalize_intent",
        description = "normalize keeps meta.heading while canonicalizing run vector",
        input = {
            intent = {
                kind = "run",
                run_x = "0.5",
                run_y = "-0.25",
                meta = {
                    heading = "1.5708",
                },
            },
        },
        expected = {
            result = {
                kind = "run",
                reason = "",
                meta = {
                    heading = 1.5708,
                },
                payload = {
                    command = "",
                    run_x = 0.5,
                    run_y = -0.25,
                    heading = nil,
                    target_id = 0,
                },
            },
        },
    },
    {
        fixture_id = "dispatcher_validate_send_command_missing",
        helper = "validate_intent",
        description = "send_command requires command payload",
        input = {
            intent = {
                kind = "send_command",
                payload = {},
            },
        },
        expected = {
            result = { false, "missing_command" },
        },
    },
    {
        fixture_id = "dispatcher_validate_set_target_ok",
        helper = "validate_intent",
        description = "set_target accepts positive target id",
        input = {
            intent = {
                kind = "set_target",
                payload = {
                    target_id = "1234",
                },
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_validate_run_vector_ok",
        helper = "validate_intent",
        description = "run accepts numeric vector fields",
        input = {
            intent = {
                kind = "run",
                run_x = 1.25,
                run_y = -0.75,
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_validate_run_vector_string_numeric_ok",
        helper = "validate_intent",
        description = "run accepts numeric-string vector fields",
        input = {
            intent = {
                kind = "run",
                run_x = "1.5",
                run_y = "-2.0",
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_validate_run_missing_run_x",
        helper = "validate_intent",
        description = "run rejects missing run_x",
        input = {
            intent = {
                kind = "run",
                run_y = 1,
            },
        },
        expected = {
            result = { false, "missing_run_x" },
        },
    },
    {
        fixture_id = "dispatcher_validate_run_missing_run_y",
        helper = "validate_intent",
        description = "run rejects missing run_y",
        input = {
            intent = {
                kind = "run",
                run_x = 1,
            },
        },
        expected = {
            result = { false, "missing_run_y" },
        },
    },
    {
        fixture_id = "dispatcher_validate_run_invalid_run_x",
        helper = "validate_intent",
        description = "run rejects nonnumeric run_x",
        input = {
            intent = {
                kind = "run",
                run_x = "abc",
                run_y = 1,
            },
        },
        expected = {
            result = { false, "invalid_run_x" },
        },
    },
    {
        fixture_id = "dispatcher_validate_run_invalid_run_y",
        helper = "validate_intent",
        description = "run rejects nonnumeric run_y",
        input = {
            intent = {
                kind = "run",
                run_x = 1,
                run_y = "abc",
            },
        },
        expected = {
            result = { false, "invalid_run_y" },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_dryrun_valid_vector_no_calls",
        helper = "dispatch_intent",
        description = "valid run vector dry-run performs no side-effect calls",
        input = {
            intent = {
                kind = "run",
                run_x = 0,
                run_y = 1,
                meta = {
                    heading = 1.5708,
                },
            },
            deps = {
                execute = false,
            },
        },
        expected = {
            result = {
                ok = true,
                reason = "dry_run",
                executed = false,
                normalized_intent = {
                    kind = "run",
                    reason = "",
                    meta = {
                        heading = 1.5708,
                    },
                    payload = {
                        command = "",
                        run_x = 0,
                        run_y = 1,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {},
        },
    },
    {
        fixture_id = "dispatcher_dispatch_invalid_vector_no_calls",
        helper = "dispatch_intent",
        description = "invalid run vector fails before execution and makes no calls",
        input = {
            intent = {
                kind = "run",
                run_x = "bad",
                run_y = 1,
            },
            deps = {
                execute = true,
            },
        },
        expected = {
            result = {
                ok = false,
                reason = "invalid_run_x",
                executed = false,
                normalized_intent = {
                    kind = "run",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = 1,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {},
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_run_calls_deps",
        helper = "dispatch_intent",
        description = "dispatch execute run uses injected deps.run with normalized vector",
        input = {
            intent = {
                kind = "run",
                payload = {
                    run_x = "1.5",
                    run_y = -2,
                },
            },
            deps = {
                execute = true,
            },
        },
        expected = {
            result = {
                ok = true,
                reason = "executed",
                executed = true,
                normalized_intent = {
                    kind = "run",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = 1.5,
                        run_y = -2,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {
                run = {
                    { 1.5, -2 },
                },
            },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_missing_dep",
        helper = "dispatch_intent",
        description = "execute true without required dep fails fast",
        input = {
            intent = {
                kind = "turn",
                payload = {
                    heading = 2.2,
                },
            },
            deps = {
                execute = true,
                missing = "turn",
            },
        },
        expected = {
            result = {
                ok = false,
                reason = "missing_dep:turn",
                executed = false,
                normalized_intent = {
                    kind = "turn",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = nil,
                        heading = 2.2,
                        target_id = 0,
                    },
                },
            },
            calls = {},
        },
    },
}
