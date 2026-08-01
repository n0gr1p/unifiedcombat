local M = {}

function M.record_dispatch(scheduler, ctx, p1_number)
	local phase = scheduler.phase1
	local selected = phase.last_selected
	local plan = phase.last_plan
	if not selected or not plan then
		return
	end
	local duplicate_key = tostring(selected.duplicate_suppression_key or '')
	phase.pending = {
		pending_id = ('pend.%d.%d'):format(math.floor(ctx.now * 1000), math.floor(ctx.tick)),
		proposal_id = tostring(selected.proposal_id or ''),
		family_id = tostring(selected.family_id or ''),
		duplicate_suppression_key = duplicate_key,
		provider = tostring(selected.provider or ''),
		action_type = tostring(selected.action_type or ''),
		action_name = tostring(selected.action_name or ''),
		target_id = tonumber(selected.target_id) or 0,
		state = 'sent',
		selected_at = p1_number(selected.created_at, ctx.now),
		dispatched_at = ctx.now,
		ack_deadline = ctx.now + 0.6,
		effect_deadline = ctx.now + 2.5,
		completion_deadline = ctx.now + 3.0,
		expected_ack = tostring(selected.expected_ack or ''),
		expected_effect = tostring(selected.expected_effect or ''),
		result = '',
		lock_class = tostring(selected.lock_class or ''),
	}
	if duplicate_key ~= '' then
		phase.recent_duplicate_until[duplicate_key] = ctx.now + 0.75
	end
end

return M
