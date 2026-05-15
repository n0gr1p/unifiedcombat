local M = {}

function M.publish(
	scheduler,
	globals,
	ctx,
	selected,
	ranked,
	reject_counts,
	rejected,
	proposals,
	locks,
	plan,
	commit_reason,
	p1_format_top3,
	p1_format_top3_verbose,
	p1_format_topn_lines,
	p1_capture_topn_items,
	p1_push_recent_rejects,
	p1_reject_top,
	p1_set_pending_globals,
	p1_build_lock_summary
)
	local phase = scheduler.phase1
	phase.last_selected = selected
	phase.last_plan = plan
	phase.last_top3 = p1_format_top3(ranked)
	phase.last_top3_verbose = p1_format_top3_verbose(ranked)
	phase.last_top5_lines = p1_format_topn_lines(ranked, 5)
	phase.last_top5_items = p1_capture_topn_items(ranked, 5)
	p1_push_recent_rejects(ctx, rejected)
	phase.last_reject_top = p1_reject_top(reject_counts, #proposals)
	if selected then
		phase.last_noop_reason = ''
	else
		if commit_reason and commit_reason ~= '' then
			phase.last_noop_reason = 'commit_invalidated:' .. tostring(commit_reason)
		else
			phase.last_noop_reason = (#proposals == 0) and 'no_proposals' or 'all_rejected'
		end
	end
	globals.UC_SCHED_P1_TICK = ctx.tick
	globals.UC_SCHED_P1_SELECTED_PROPOSAL = selected and tostring(selected.proposal_id or '') or ''
	globals.UC_SCHED_P1_SELECTED_PROVIDER = selected and tostring(selected.provider or '') or ''
	globals.UC_SCHED_P1_SELECTED_FAMILY = selected and tostring(selected.family_id or '') or ''
	globals.UC_SCHED_P1_PLAN_PRELUDE = (plan and plan.prelude and tostring(plan.prelude.type or '')) or ''
	p1_set_pending_globals()
	globals.UC_SCHED_P1_LOCK_SUMMARY = p1_build_lock_summary(ctx, locks)
	globals.UC_SCHED_P1_REJECT_TOP = phase.last_reject_top or ''
	globals.UC_SCHED_P1_NOOP_REASON = phase.last_noop_reason or ''
	globals.UC_SCHED_P1_TOP3 = phase.last_top3 or ''
	globals.UC_SCHED_P1_TOP3_VERBOSE = phase.last_top3_verbose or ''
	globals.UC_SCHED_P1_TOP5 = table.concat(phase.last_top5_lines or {}, '\n')
	do
		local rr = phase.recent_rejects or {}
		local out = {}
		local start = math.max(1, #rr - 4)
		for i = start, #rr do
			out[#out + 1] = rr[i]
		end
		globals.UC_SCHED_P1_REJECT5 = table.concat(out, '\n')
	end
end

return M
