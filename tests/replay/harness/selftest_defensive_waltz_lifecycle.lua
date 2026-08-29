local function read_file(path)
	local file = assert(io.open(path, 'rb'))
	local content = file:read('*a')
	file:close()
	return content
end

local function assert_contains(content, needle, message)
	if not content:find(needle, 1, true) then error(message .. ': missing ' .. needle) end
end

local function assert_not_contains(content, needle, message)
	if content:find(needle, 1, true) then error(message .. ': found ' .. needle) end
end

local scheduler = read_file('unified_scheduler.lua')
local provider = read_file('uc_provider_defensive.lua')
local action_state = read_file('uc_scheduler_action_state.lua')

assert_contains(provider, "recast_key = ('ja:%s'):format(action_name)", 'Waltz proposals must use JA recast identity')
assert_contains(provider, "duplicate_key = ('ja:%s:%d'):format(action_name, target_id)", 'Waltz proposals must use JA duplicate identity')
assert_contains(provider, "movement_policy = action_kind == 'spell' and 'must_stop' or 'requires_range'", 'Waltz proposals must preserve JA movement behavior')
assert_contains(provider, "expected_effect = action_kind == 'ja' and 'ja_effect' or 'buff_gain'", 'Waltz proposals must expect a JA effect')
assert_contains(scheduler, "action_kind == 'spell'", 'defensive spell wait must remain kind-gated')
assert_contains(scheduler, "scheduler.begin_defensive_spell_wait", 'defensive spell wait call missing')
assert_not_contains(scheduler, "action_kind == 'ja' and scheduler.begin_defensive_spell_wait", 'Waltzes must never enter defensive spell-wait state')
assert_contains(scheduler, "if action_kind == 'ja' and detail.waltz_action == true then", 'Waltz TP/Amnesia state must be revalidated at dispatch')
assert_contains(scheduler, "if not (ignore_trusts and tonumber(m.spawn_type) == 14) then", 'AoE healing must retain trust-ignore scope')
assert_contains(scheduler, "elseif (tonumber(m.hpp) or 0) > 0 then", 'AoE healing must exclude dead members')
assert_contains(scheduler, "if cure_enabled and m.charmed ~= true", 'AoE healing recipients must exclude charmed members')
assert_contains(action_state, "if send_kind == 'ja' then", 'Waltzes must use the existing bounded JA action lifecycle')
assert_contains(action_state, "timeout = tonumber(st.ja_lag_timeout) or 1.0", 'Waltz JA lifecycle timeout must remain bounded')

io.stdout:write('selftest_defensive_waltz_lifecycle: OK\n')
