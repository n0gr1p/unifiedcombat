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
        fixture_id = "dispatcher_validate_send_command_ok",
        helper = "validate_intent",
        description = "send_command accepts nonempty command payload",
        input = {
            intent = {
                kind = "send_command",
                payload = {
                    command = "input /ja Provoke <t>",
                },
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_dryrun_send_command_no_calls",
        helper = "dispatch_intent",
        description = "send_command dry-run performs no side-effect calls",
        input = {
            intent = {
                kind = "send_command",
                command = "input /ja Provoke <t>",
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
                    kind = "send_command",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "input /ja Provoke <t>",
                        run_x = nil,
                        run_y = nil,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {},
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_send_command_calls_deps",
        helper = "dispatch_intent",
        description = "dispatch execute send_command uses injected deps.send_command",
        input = {
            intent = {
                kind = "send_command",
                payload = {
                    command = "input /ma Flash <t>",
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
                    kind = "send_command",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "input /ma Flash <t>",
                        run_x = nil,
                        run_y = nil,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {
                send_command = {
                    { "input /ma Flash <t>" },
                },
            },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_send_command_missing_dep",
        helper = "dispatch_intent",
        description = "send_command execute true without deps.send_command fails fast",
        input = {
            intent = {
                kind = "send_command",
                command = "input /item Holy Water <me>",
            },
            deps = {
                execute = true,
                missing = "send_command",
            },
        },
        expected = {
            result = {
                ok = false,
                reason = "missing_dep:send_command",
                executed = false,
                normalized_intent = {
                    kind = "send_command",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "input /item Holy Water <me>",
                        run_x = nil,
                        run_y = nil,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {},
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
        fixture_id = "dispatcher_validate_run_stop_ok",
        helper = "validate_intent",
        description = "run_stop accepts stop movement intent without vector fields",
        input = {
            intent = {
                kind = "run_stop",
                source = "t2_4b_fixture",
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_validate_select_target_ok",
        helper = "validate_intent",
        description = "select_target accepts positive target id used by scheduler dark-launch",
        input = {
            intent = {
                kind = "select_target",
                target_id = "1234",
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_validate_select_target_invalid_target_id",
        helper = "validate_intent",
        description = "select_target rejects missing or nonpositive target id",
        input = {
            intent = {
                kind = "select_target",
                payload = {},
            },
        },
        expected = {
            result = { false, "invalid_target_id" },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_dryrun_select_target_no_calls",
        helper = "dispatch_intent",
        description = "select_target dry-run performs no side-effect calls",
        input = {
            intent = {
                kind = "select_target",
                payload = {
                    target_id = "5678",
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
                    kind = "select_target",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = nil,
                        heading = nil,
                        target_id = 5678,
                    },
                },
            },
            calls = {},
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_select_target_calls_deps",
        helper = "dispatch_intent",
        description = "dispatch execute select_target uses injected deps.set_target",
        input = {
            intent = {
                kind = "select_target",
                target_id = 5678,
            },
            deps = {
                execute = true,
                set_target_return = true,
            },
        },
        expected = {
            result = {
                ok = true,
                reason = "executed",
                executed = true,
                dep_result = true,
                normalized_intent = {
                    kind = "select_target",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = nil,
                        heading = nil,
                        target_id = 5678,
                    },
                },
            },
            calls = {
                set_target = {
                    { 5678 },
                },
            },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_select_target_missing_dep",
        helper = "dispatch_intent",
        description = "select_target execute true without deps.set_target fails fast",
        input = {
            intent = {
                kind = "select_target",
                target_id = 5678,
            },
            deps = {
                execute = true,
                missing = "set_target",
            },
        },
        expected = {
            result = {
                ok = false,
                reason = "missing_dep:set_target",
                executed = false,
                normalized_intent = {
                    kind = "select_target",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = nil,
                        heading = nil,
                        target_id = 5678,
                    },
                },
            },
            calls = {},
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
        fixture_id = "dispatcher_dispatch_dryrun_run_stop_no_calls",
        helper = "dispatch_intent",
        description = "run_stop dry-run performs no side-effect calls",
        input = {
            intent = {
                kind = "run_stop",
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
                    kind = "run_stop",
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
        fixture_id = "dispatcher_dispatch_execute_run_missing_dep",
        helper = "dispatch_intent",
        description = "run execute true without deps.run fails fast",
        input = {
            intent = {
                kind = "run",
                run_x = 1,
                run_y = 0,
            },
            deps = {
                execute = true,
                missing = "run",
            },
        },
        expected = {
            result = {
                ok = false,
                reason = "missing_dep:run",
                executed = false,
                normalized_intent = {
                    kind = "run",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = 1,
                        run_y = 0,
                        heading = nil,
                        target_id = 0,
                    },
                },
            },
            calls = {},
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_run_stop_calls_deps",
        helper = "dispatch_intent",
        description = "dispatch execute run_stop uses injected deps.run(false)",
        input = {
            intent = {
                kind = "run_stop",
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
                    kind = "run_stop",
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
            calls = {
                run = {
                    { false },
                },
            },
        },
    },
    {
        fixture_id = "dispatcher_validate_turn_ok",
        helper = "validate_intent",
        description = "turn accepts numeric heading",
        input = {
            intent = {
                kind = "turn",
                heading = "2.2",
            },
        },
        expected = {
            result = { true, "" },
        },
    },
    {
        fixture_id = "dispatcher_validate_turn_missing_heading",
        helper = "validate_intent",
        description = "turn requires heading",
        input = {
            intent = {
                kind = "turn",
                payload = {},
            },
        },
        expected = {
            result = { false, "missing_heading" },
        },
    },
    {
        fixture_id = "dispatcher_dispatch_dryrun_turn_no_calls",
        helper = "dispatch_intent",
        description = "turn dry-run performs no side-effect calls",
        input = {
            intent = {
                kind = "turn",
                payload = {
                    heading = "1.25",
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
                    kind = "turn",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = nil,
                        heading = 1.25,
                        target_id = 0,
                    },
                },
            },
            calls = {},
        },
    },
    {
        fixture_id = "dispatcher_dispatch_execute_turn_calls_deps",
        helper = "dispatch_intent",
        description = "dispatch execute turn uses injected deps.turn",
        input = {
            intent = {
                kind = "turn",
                heading = 1.25,
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
                    kind = "turn",
                    reason = "",
                    meta = {
                        heading = nil,
                    },
                    payload = {
                        command = "",
                        run_x = nil,
                        run_y = nil,
                        heading = 1.25,
                        target_id = 0,
                    },
                },
            },
            calls = {
                turn = {
                    { 1.25 },
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
    {
        fixture_id = "dispatcher_dispatch_execute_run_stop_missing_run_dep",
        helper = "dispatch_intent",
        description = "run_stop execute true without deps.run fails fast",
        input = {
            intent = {
                kind = "run_stop",
            },
            deps = {
                execute = true,
                missing = "run",
            },
        },
        expected = {
            result = {
                ok = false,
                reason = "missing_dep:run",
                executed = false,
                normalized_intent = {
                    kind = "run_stop",
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
            calls = {},
        },
    },
}
