local fixtures = require("tests.replay.fixtures.dispatch_plan.dispatch_plan_fixtures")
local runner = require("tests.replay.harness.dispatch_plan_fixture_runner")

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

local function test_canonical_required_setting_commit()
    local dispatch = require('uc_scheduler_dispatch_plan')
    local config = {
        combat = { weaponskill = { enabled = true }, autotarget = true },
        abilities = { enabled = false },
    }
    local ctx = {
        now = 20,
        settings = { weaponskill_active = true, ability_active = true, autotarget = true },
        config = config,
    }
    local selected = {
        expires_at = 21,
        target_kind = 'self',
        required_setting = 'weaponskill_active',
    }
    local plan = { commit_deadline = 21 }
    local function commit()
        return dispatch.p1_revalidate_plan_commit(
            {}, ctx, selected, plan,
            function(v, default_value) return tonumber(v) or default_value end,
            { ffxi = { get_mob_by_id = function() return nil end } },
            {}
        )
    end

    local allowed = commit()
    assert_equal(allowed, true, 'canonical WS enabled permits final commit')
    -- Same ranked proposal, but policy changed before the send boundary.
    config.combat.weaponskill.enabled = false
    local rejected, reason = commit()
    assert_equal(rejected, false, 'canonical disabled must reject previously ranked WS')
    assert_equal(reason, 'settings_disabled', 'canonical disabled commit reason')
    ctx.settings.weaponskill_active = false
    config.combat.weaponskill.enabled = true
    allowed = commit()
    assert_equal(allowed, true, 'stale flat WS false cannot defeat canonical enabled')
    config.combat.weaponskill = {}
    ctx.settings.weaponskill_active = true
    rejected = commit()
    assert_equal(rejected, false, 'canonical missing leaf must reject stale flat WS true')

    selected.required_setting = 'ability_active'
    rejected = commit()
    assert_equal(rejected, false, 'canonical disabled abilities must reject stale flat enabled')
    config.abilities.enabled = true
    ctx.settings.ability_active = false
    allowed = commit()
    assert_equal(allowed, true, 'canonical enabled abilities beat flat disabled')

    selected.required_setting = 'unknown_legacy_key'
    ctx.settings.unknown_legacy_key = true
    rejected, reason = commit()
    assert_equal(rejected, false, 'unknown required setting must fail closed')
    assert_equal(reason, 'settings_disabled', 'unknown setting commit reason')
    selected.required_setting = 'autotarget'
    ctx.config = nil
    rejected = commit()
    assert_equal(rejected, false, 'missing canonical config cannot fall back to flat')
    ctx.config = config
    selected.required_setting = nil
    allowed = commit()
    assert_equal(allowed, true, 'unrestricted legacy proposal keeps target validation')
end

local function main()
    test_canonical_required_setting_commit()

    local result = runner.run_suite(fixtures, {
        suite_id = "dispatch_plan",
    })

    assert_true(result.ok, "dispatch plan suite should fully pass")
    assert_equal(result.suite_id, "dispatch_plan", "suite id mismatch")
    assert_equal(result.total, 12, "fixture count mismatch")
    assert_equal(result.passed, 12, "all fixtures should pass")
    assert_equal(result.failed, 0, "no fixtures should fail")

    local basic = find_entry(result.entries, "dispatch_plan_build_basic")
    assert_true(basic ~= nil, "build basic fixture missing")
    assert_equal(basic.actual.result.plan_id, "plan.123450.7", "plan id mismatch")

    local invalid = find_entry(result.entries, "dispatch_plan_revalidate_invalid_plan")
    assert_true(invalid ~= nil, "invalid-plan fixture missing")
    assert_equal(invalid.actual.result[2], "invalid_plan", "invalid-plan reason mismatch")

    local ally = find_entry(result.entries, "dispatch_plan_revalidate_ally_valid")
    assert_true(ally ~= nil, "ally fixture missing")
    assert_true(ally.actual.result[1] == true, "ally should pass")

    io.stdout:write("selftest_dispatch_plan_fixtures: OK\n")
end

main()
