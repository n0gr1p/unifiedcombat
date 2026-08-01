local deep_copy = require("tests.replay.harness.deep_copy")
local side_effect_guard = require("tests.replay.harness.side_effect_guard")
local structural_compare = require("tests.replay.harness.structural_compare")

local function assert_true(condition, message)
    if not condition then
        error(message or "assertion failed")
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values are not equal") .. ": expected=" .. tostring(expected) .. ", actual=" .. tostring(actual))
    end
end

local function run_deep_copy_test()
    local src = {
        [1] = "one",
        ["1"] = "string-one",
        flag = false,
        inner = {
            [2] = "",
            label = "ok",
        },
    }

    local dst = deep_copy.copy(src)
    assert_true(dst ~= src, "deep_copy should return a distinct table")
    assert_true(dst.inner ~= src.inner, "nested table should be copied")
    assert_equal(dst[1], "one", "numeric key should remain numeric")
    assert_equal(dst["1"], "string-one", "string key should remain string")
    assert_equal(dst.flag, false, "false should be preserved")
    assert_equal(dst.inner[2], "", "empty string should be preserved")
end

local function run_structural_compare_test()
    local a = {
        [1] = "one",
        ["1"] = "string-one",
        bool_false = false,
        empty = "",
    }
    local b = deep_copy.copy(a)

    local ok_equal, mismatches_equal = structural_compare.compare(a, b)
    assert_true(ok_equal, "structural compare should match identical structures")
    assert_equal(#mismatches_equal, 0, "identical structures should have zero mismatches")

    local c = deep_copy.copy(a)
    c.bool_false = nil
    local ok_nil_vs_false, mismatches_nil_vs_false = structural_compare.compare(a, c)
    assert_true(not ok_nil_vs_false, "missing key should not equal false value")
    assert_true(#mismatches_nil_vs_false > 0, "missing key mismatch expected")

    local d = deep_copy.copy(a)
    d[1] = nil
    d["1"] = "one"
    local ok_num_vs_string_key, mismatches_num_vs_string_key = structural_compare.compare(a, d)
    assert_true(not ok_num_vs_string_key, "numeric-key and string-key layout differences must be detected")
    assert_true(#mismatches_num_vs_string_key > 0, "key-shape mismatch expected")
end

local function run_side_effect_guard_test()
    local env = {}
    local guard = side_effect_guard.new({
        "windower.send_command",
        "windower.ffxi.run",
    })

    guard:install(env)

    local ok1 = pcall(function()
        env.windower.send_command("input /echo hello")
    end)
    assert_true(not ok1, "forbidden side effect should raise error")

    local ok2 = pcall(function()
        env.windower.ffxi.run(false)
    end)
    assert_true(not ok2, "second forbidden side effect should raise error")

    local calls = guard:get_calls()
    assert_equal(#calls, 2, "guard should record forbidden calls")
    assert_equal(calls[1].path, "windower.send_command", "first call path mismatch")
    assert_equal(calls[2].path, "windower.ffxi.run", "second call path mismatch")

    local ok_clean, err_clean = pcall(function()
        guard:assert_clean()
    end)
    assert_true(not ok_clean, "assert_clean should fail when calls exist")
    assert_true(type(err_clean) == "string", "assert_clean should return error text")

    guard:restore()
    assert_true(env.windower == nil, "restore should remove created path scaffolding")
end

local function main()
    run_deep_copy_test()
    run_structural_compare_test()
    run_side_effect_guard_test()
    io.stdout:write("selftest_replay_harness: OK\n")
end

main()
