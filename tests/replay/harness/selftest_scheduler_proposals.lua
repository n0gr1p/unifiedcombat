local proposals = require('uc_scheduler_proposals')

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(('%s expected=%s actual=%s'):format(label, tostring(expected), tostring(actual)))
	end
end

local function assert_close(actual, expected, label)
	if math.abs(actual - expected) > 0.000001 then
		error(('%s expected=%.6f actual=%.6f'):format(label, expected, actual))
	end
end

local ok, reason = proposals.validate_identity(nil)
assert_equal(ok, false, 'nil proposal rejected')
assert_equal(reason, 'malformed', 'nil proposal reason')

ok, reason = proposals.validate_identity({ proposal_id = 'p1' })
assert_equal(ok, false, 'missing provider rejected')
assert_equal(reason, 'malformed', 'missing provider reason')

ok, reason = proposals.validate_identity({ proposal_id = 'p1', provider = 'combat' })
assert_equal(ok, true, 'valid identity accepted')
assert_equal(reason, '', 'valid identity reason')

local ctx = { now = 50 }
local proposal = {
	proposal_id = 'p1',
	provider = 'combat',
	priority_band = 70.9,
	urgency = 1.4,
}
ok, reason = proposals.normalize_live_fields(ctx, proposal)
assert_equal(ok, true, 'defaulted proposal accepted')
assert_equal(reason, '', 'defaulted proposal reason')
assert_close(proposal.expires_at, 50.40, 'default expires_at')
assert_close(proposal.commit_deadline, 50.25, 'default commit_deadline')
assert_equal(proposal.priority_band, 70, 'priority band floor')
assert_equal(proposal.urgency, 1, 'urgency clamp')

local expired = {
	proposal_id = 'expired',
	provider = 'combat',
	expires_at = 50,
	priority_band = '70',
}
ok, reason = proposals.normalize_live_fields(ctx, expired)
assert_equal(ok, false, 'expired proposal rejected')
assert_equal(reason, 'expired', 'expired proposal reason')
assert_equal(expired.priority_band, '70', 'expired proposal remains unnormalized')

assert_close(
	proposals.created_age({ now = 10 }, { created_at = 9.25 }),
	0.75,
	'created age'
)
assert_equal(
	proposals.priority_bypasses_engage({ priority_band = 90 }, 90),
	true,
	'engage bypass at threshold'
)
assert_equal(
	proposals.priority_bypasses_engage({ priority_band = '90' }, 90),
	false,
	'engage bypass requires normalized number'
)

io.stdout:write('selftest_scheduler_proposals: OK\n')
