local fixtures = require("tests.replay.fixtures.command_builder.command_builder_fixtures")
local runner = require("tests.replay.harness.command_builder_fixture_runner")

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

local function find_entry(entries, fixture_id)
    for _, entry in ipairs(entries) do
        if entry.fixture_id == fixture_id then
            return entry
        end
    end
    return nil
end

local function main()
    local result = runner.run_suite(fixtures, {
        suite_id = "command_builder",
    })

    assert_true(result.ok, "command builder suite should fully pass")
    assert_equal(result.suite_id, "command_builder", "suite id mismatch")
    assert_equal(result.total, 13, "fixture count mismatch")
    assert_equal(result.passed, 13, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local name_entry = find_entry(result.entries, "command_builder_spell_target_name")
    assert_true(name_entry ~= nil, "spell target name fixture missing")
    assert_equal(name_entry.actual.result, "input /ma \"Cure IV\" \"Alice\"", "spell target name mismatch")

    local id_entry = find_entry(result.entries, "command_builder_ja_mob_id_target")
    assert_true(id_entry ~= nil, "ja mob id fixture missing")
    assert_equal(id_entry.actual.result, "input /ja \"Animated Flourish\" 789", "ja mob id mismatch")

    local entrust_entry = find_entry(result.entries, "command_builder_spell_self_only_explicit_entity_id")
    assert_true(entrust_entry ~= nil, "Entrust entity-id fixture missing")
    assert_equal(
        entrust_entry.actual.result,
        "input /ma \"Indi-Refresh\" 400018",
        "Entrust entity-id target mismatch"
    )

    local quote_entry = find_entry(result.entries, "command_builder_spell_target_name_quotes_stripped")
    assert_true(quote_entry ~= nil, "quote stripping fixture missing")
    assert_equal(quote_entry.actual.result, "input /ma \"Cure\" \"Alice\"", "quote stripping mismatch")

    io.stdout:write("selftest_command_builder_fixtures: OK\n")
end

main()
