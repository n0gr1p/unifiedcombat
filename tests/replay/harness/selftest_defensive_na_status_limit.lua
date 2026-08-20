local function assert_true(value, message)
    if value ~= true then
        error(message or 'assert_true failed')
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed')
            .. ': expected=' .. tostring(expected)
            .. ' actual=' .. tostring(actual))
    end
end

local policy = dofile('uc_status_removal_policy.lua')

local limited = policy.build(true, ' Poison | Paralyze | Dia | poison ')
assert_true(limited.enabled, 'limited policy must be enabled')
assert_equal(policy.rank(limited, 'poison'), 0, 'Poison must be first priority')
assert_equal(policy.rank(limited, 'paralysis'), 1, 'Paralyze alias must map to paralysis')
assert_equal(policy.rank(limited, 'Dia'), 2, 'Dia must be third priority')
assert_equal(#limited.ordered, 3, 'duplicates must collapse while preserving first occurrence')
assert_equal(policy.rank(limited, 'attack_down'), nil, 'unlisted Attack Down must not be eligible')

local ally_poison = policy.candidate_priority(limited, 'poison', 5)
local self_paralyze = policy.candidate_priority(limited, 'paralysis', 1)
assert_true(
    ally_poison < self_paralyze,
    'configured status priority must outrank member priority across the party'
)

local empty = policy.build(true, '')
assert_true(empty.enabled, 'empty allowlist still means limited mode is enabled')
assert_equal(policy.rank(empty, 'poison'), nil, 'empty allowlist must remove nothing')

local unrestricted = policy.build(false, 'Poison|Paralyze')
assert_true(unrestricted.enabled == false, 'limiter off must preserve unrestricted mode')
assert_equal(policy.rank(unrestricted, 'poison'), nil, 'disabled policy must not inject configured ranking')

io.stdout:write('selftest_defensive_na_status_limit: OK\n')
