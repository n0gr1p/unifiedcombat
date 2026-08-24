package.path = './?.lua;' .. package.path

local commitment = require('uc_combat_commitment')

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
	end
end

local function base_ctx()
	return { now = 10, settings = {}, player = { status = 0 } }
end

local function base_target()
	return {
		id = 300,
		name = 'Enemy',
		valid_target = true,
		spawn_type = 16,
		hpp = 100,
		status = 0,
		claim_id = 0,
	}
end

local function deps(overrides)
	local d = {
		build_friendly_claims = function() return {}, {} end,
		build_party_id_set = function() return {} end,
		camp_pull_order = function() return nil end,
		prime_unclaimed_party_aggressive_ok = function() return false end,
		force_target_id = 0,
		allow_player_engaged = true,
	}
	for key, value in pairs(overrides or {}) do
		d[key] = value
	end
	return d
end

local ctx = base_ctx()
local target = base_target()
local result = commitment.evaluate(ctx, target, deps())
assert_equal(result.committed, false, 'mere selection is not combat commitment')
assert_equal(result.reason, 'selection_only', 'selection-only reason')

result = commitment.evaluate(ctx, target, deps({
	build_friendly_claims = function() return {}, { [100] = true } end,
}))
assert_equal(result.committed, false, 'unclaimed target is not party combat')

target.claim_id = 100
result = commitment.evaluate(ctx, target, deps({
	build_friendly_claims = function() return {}, { [100] = true } end,
}))
assert_equal(result.committed, true, 'party-claimed target is combat commitment')
assert_equal(result.reason, 'party_claimed', 'party claim reason')

target = base_target()
result = commitment.evaluate(ctx, target, deps({ camp_pull_order = function() return 2 end }))
assert_equal(result.committed, true, 'tracked camp pull is combat commitment')
assert_equal(result.reason, 'camp_pull', 'camp pull reason')

target.status = 1
result = commitment.evaluate(ctx, target, deps({
	prime_unclaimed_party_aggressive_ok = function() return true end,
}))
assert_equal(result.committed, true, 'Prime-detected aggressor is combat commitment')
assert_equal(result.reason, 'prime_aggressive', 'Prime aggression reason')

target = base_target()
result = commitment.evaluate(ctx, target, deps({ force_target_id = 300 }))
assert_equal(result.committed, true, 'fight-leader target is combat commitment')
assert_equal(result.reason, 'fight_leader', 'fight leader reason')

ctx.player.status = 1
target.status = 1
result = commitment.evaluate(ctx, target, deps())
assert_equal(result.committed, true, 'engaged hostile target covers claim propagation lag')
assert_equal(result.reason, 'player_engaged', 'engaged target reason')

target.status = 0
result = commitment.evaluate(ctx, target, deps())
assert_equal(result.committed, false, 'engaged player cursoring a non-combat mob does not commit it')

print('selftest_combat_commitment: OK')
