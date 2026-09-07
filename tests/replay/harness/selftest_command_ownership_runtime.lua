local ownership = require("uc_scheduler_command_ownership")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local previous_reaction_runtime = package.loaded["uc_reaction_runtime"]
    local reaction_lock = nil
    local cancel_calls = {}
    package.loaded["uc_reaction_runtime"] = {
        get_action_lock = function()
            return reaction_lock
        end,
        cancel = function(key, reason)
            cancel_calls[#cancel_calls + 1] = { key = key, reason = reason }
            if type(reaction_lock) ~= "table" or tostring(reaction_lock.key or "") ~= tostring(key or "") then
                return nil, reaction_lock
            end
            local released = reaction_lock
            reaction_lock = nil
            return released, nil
        end,
    }

    local sends = {}
    local dispatches = 0
    local send = function(command)
        sends[#sends + 1] = command
    end
    local dispatcher = {
        dispatch_intent = function(intent, deps)
            dispatches = dispatches + 1
            deps.send_command(intent.command)
            return { ok = true, executed = true, reason = "executed" }
        end,
    }
    local status = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = { kind = "send_command", command = "input /ja Test <me>" },
        command = "input /ja Test <me>",
    })
    assert_equal(dispatches, 1, "dispatcher call count")
    assert_equal(#sends, 1, "side-effect call count")
    assert_equal(status.dispatch_ok, true, "dispatch status")
    assert_equal(status.fallback_used, false, "fallback status")
    assert_equal(status.ownership_enabled, true, "ownership status")
    assert_equal(status.reaction_released, false, "ordinary command must not report a reaction release")

    reaction_lock = {
        key = "ability_window:903:just desserts",
        trigger = "ability_window",
        name = "Just Desserts",
        response = "use_action",
        actor_id = 903,
        action_type = "spell",
        action_name = "Stun",
    }
    status = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = {
            kind = "send_command",
            command = "input /ma \"Stun\" 903",
            meta = {
                action_type = "spell",
                action_name = "Stun",
                target_kind = "mob",
                target_id = 903,
            },
        },
        command = "input /ma \"Stun\" 903",
    })
    assert_equal(status.dispatch_ok, true, "reaction action dispatch status")
    assert_equal(status.reaction_released, true, "successful matching reaction action must release its one-shot lock")
    assert_equal(status.reaction_key, "ability_window:903:just desserts", "released reaction key")
    assert_equal(reaction_lock, nil, "successful matching reaction action must consume the authoritative lock")
    assert_equal(#cancel_calls, 1, "successful matching reaction action must cancel exactly once")
    assert_equal(cancel_calls[1].reason, "action_dispatched", "reaction release reason")

    reaction_lock = {
        key = "ability_window:904:just desserts",
        trigger = "ability_window",
        name = "Just Desserts",
        response = "use_action",
        actor_id = 904,
        action_type = "spell",
        action_name = "Stun",
    }
    status = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = {
            kind = "send_command",
            command = "input /ma \"Fire V\" 904",
            meta = {
                action_type = "spell",
                action_name = "Fire V",
                target_kind = "mob",
                target_id = 904,
            },
        },
        command = "input /ma \"Fire V\" 904",
    })
    assert_equal(status.reaction_released, false, "different action must not consume the armed reaction")
    assert_equal(type(reaction_lock), "table", "different action must leave the armed reaction intact")
    assert_equal(#cancel_calls, 1, "different action must not call reaction cancel")

    status = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = {
            kind = "send_command",
            command = "input /ma \"Stun\" 999",
            meta = {
                action_type = "spell",
                action_name = "Stun",
                target_kind = "mob",
                target_id = 999,
            },
        },
        command = "input /ma \"Stun\" 999",
    })
    assert_equal(status.reaction_released, false, "matching action on a different actor must not consume the reaction")
    assert_equal(type(reaction_lock), "table", "wrong-target action must leave the armed reaction intact")
    assert_equal(#cancel_calls, 1, "wrong-target action must not call reaction cancel")

    local ok = pcall(function()
        ownership.apply_command_ownership({
            dispatcher = { dispatch_intent = function()
                return { ok = false, executed = false, reason = "commit_rejected" }
            end },
            send_command = send,
            intent = {
                kind = "send_command",
                command = "input /ma \"Stun\" 904",
                meta = {
                    action_type = "spell",
                    action_name = "Stun",
                    target_kind = "mob",
                    target_id = 904,
                },
            },
            command = "input /ma \"Stun\" 904",
        })
    end)
    assert_equal(ok, false, "dispatcher rejection must fail fast")
    assert_equal(type(reaction_lock), "table", "failed dispatch must not consume the reaction lock")
    assert_equal(#cancel_calls, 1, "failed dispatch must not call reaction cancel")

    reaction_lock = nil
    local missing = ownership.apply_command_ownership({
        dispatcher = dispatcher,
        send_command = send,
        intent = { kind = "send_command", command = "" },
        command = "",
    })
    assert_equal(missing.dispatched, false, "missing command dispatch status")
    assert_equal(missing.dispatch_reason, "missing_command", "missing command reason")
    assert_equal(missing.reaction_released, false, "missing command must not release a reaction")

    package.loaded["uc_reaction_runtime"] = previous_reaction_runtime
    io.stdout:write("selftest_command_ownership_runtime: OK\n")
end

main()