local dispatcher = require("uc_scheduler_dispatcher")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function main()
    local order = {}
    local result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = "input /ws Test 1001",
    }, {
        execute = true,
        send_command = function(command)
            order[#order + 1] = "execute:" .. command
        end,
    }, {
        revalidate = function()
            order[#order + 1] = "revalidate"
            return true
        end,
        on_executed = function(_, dispatch_result)
            order[#order + 1] = "mark"
            assert_equal(dispatch_result.executed, true, "mark hook execution state")
            return true
        end,
    })
    assert_equal(result.ok, true, "hooked dispatch status")
    assert_equal(result.executed, true, "hooked dispatch execution status")
    assert_equal(#order, 3, "hooked dispatch call count")
    assert_equal(order[1], "revalidate", "commit validation order")
    assert_equal(order[2], "execute:input /ws Test 1001", "execution order")
    assert_equal(order[3], "mark", "action mark order")

    local command_calls = 0
    local packet_calls = 0
    result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = 'input /ma "Fire" 1001',
        meta = {
            action_type = "spell",
            action_name = "Fire",
            target_id = 1001,
            target_name = "Locus Camelopard",
            provider = "maintenance_sch",
        },
    }, {
        execute = true,
        send_command = function() command_calls = command_calls + 1 end,
        cast_spell_packet = function(spell_name, target_id)
            packet_calls = packet_calls + 1
            assert_equal(spell_name, "Fire", "packet spell name")
            assert_equal(target_id, 1001, "packet target id")
            return true, "OK"
        end,
    })
    assert_equal(result.ok, true, "structured spell packet status")
    assert_equal(result.executed, true, "structured spell packet execution")
    assert_equal(result.dispatch_method, "spell_packet", "structured spell dispatch method")
    assert_equal(packet_calls, 1, "structured spell packet count")
    assert_equal(command_calls, 0, "structured spell must never use text command")

    result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = 'input /ma "Fire" 1001',
        meta = { action_type = "spell", action_name = "Fire", target_id = 1001 },
    }, {
        execute = true,
        cast_spell_packet = function()
            return false, "TARGET_NOT_FOUND"
        end,
    })
    assert_equal(result.ok, false, "packet spell rejection status")
    assert_equal(result.reason, "TARGET_NOT_FOUND", "packet spell rejection reason")
    assert_equal(result.executed, false, "packet spell rejection execution state")

    result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = 'input /ma "Fire" <t>',
        meta = { action_type = "spell", action_name = "Fire", target_id = 0 },
    }, { execute = false })
    assert_equal(result.ok, false, "structured spell missing target status")
    assert_equal(result.reason, "structured_spell_invalid_target_id", "structured spell missing target reason")

    local immanence_calls = 0
    result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = 'input /ja "Immanence" <me>',
        meta = {
            action_type = "ja",
            action_name = "Immanence",
            provider = "maintenance_sch",
        },
    }, {
        execute = true,
        send_command = function() immanence_calls = immanence_calls + 1 end,
        validate_sch_skillchain_target = function()
            return true, "OK"
        end,
    })
    assert_equal(result.ok, true, "valid bound-target Immanence status")
    assert_equal(result.executed, true, "valid bound-target Immanence execution")
    assert_equal(immanence_calls, 1, "valid Immanence dispatch count")

    result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = 'input /ja "Immanence" <me>',
        meta = {
            action_type = "ja",
            action_name = "Immanence",
            provider = "maintenance_sch",
        },
    }, {
        execute = true,
        send_command = function() immanence_calls = immanence_calls + 100 end,
        validate_sch_skillchain_target = function()
            return false, "target_not_party_claimed"
        end,
    })
    assert_equal(result.ok, false, "invalid bound-target Immanence status")
    assert_equal(result.reason, "sch_immanence_target_invalid:target_not_party_claimed", "invalid Immanence target reason")
    assert_equal(result.executed, false, "invalid bound-target Immanence execution")
    assert_equal(immanence_calls, 1, "invalid Immanence must not dispatch")

    local blocked_calls = 0
    result = dispatcher.dispatch_intent({
        kind = "send_command",
        command = "input /ja Blocked <me>",
    }, {
        execute = true,
        send_command = function() blocked_calls = blocked_calls + 1 end,
    }, {
        revalidate = function() return false, "stale_commit" end,
        on_executed = function() blocked_calls = blocked_calls + 100 end,
    })
    assert_equal(result.ok, false, "rejected commit status")
    assert_equal(result.reason, "stale_commit", "rejected commit reason")
    assert_equal(result.executed, false, "rejected commit execution state")
    assert_equal(blocked_calls, 0, "rejected commit side-effect count")

    local calls = { engage = 0, switch = 0, disengage = 0 }
    local deps = {
        execute = true,
        engage_target = function(target_id)
            calls.engage = calls.engage + 1
            assert_equal(target_id, 1001, "engage target")
            return true, "OK"
        end,
        switch_target = function(target_id)
            calls.switch = calls.switch + 1
            assert_equal(target_id, 1002, "switch target")
            return true, "OK"
        end,
        disengage = function()
            calls.disengage = calls.disengage + 1
            return true, "OK"
        end,
    }
    assert_equal(dispatcher.dispatch_intent({ kind = "engage", target_id = 1001 }, deps).executed, true, "engage dispatch")
    assert_equal(dispatcher.dispatch_intent({ kind = "switch_target", target_id = 1002 }, deps).executed, true, "switch dispatch")
    assert_equal(dispatcher.dispatch_intent({ kind = "disengage" }, deps).executed, true, "disengage dispatch")
    assert_equal(calls.engage, 1, "engage exactly-once count")
    assert_equal(calls.switch, 1, "switch exactly-once count")
    assert_equal(calls.disengage, 1, "disengage exactly-once count")

    result = dispatcher.dispatch_intent({ kind = "engage", target_id = 1001 }, {
        execute = true,
        engage_target = function()
            return false, "PACKET_REJECTED"
        end,
    })
    assert_equal(result.ok, false, "adapter rejection status")
    assert_equal(result.reason, "PACKET_REJECTED", "adapter rejection reason")
    assert_equal(result.executed, false, "adapter rejection execution state")

    result = dispatcher.dispatch_intent({ kind = "switch_target", target_id = 1002 }, { execute = true })
    assert_equal(result.ok, false, "missing adapter status")
    assert_equal(result.reason, "missing_dep:switch_target", "missing adapter reason")

    io.stdout:write("selftest_scheduler_dispatcher_phase2: OK\n")
end

main()
