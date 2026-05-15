local M = {}

function M.p1_build_dispatch_plan(scheduler, ctx, selected, p1_number)
	if not selected then
		return nil
	end
	local prelude_type = 'none'
	if tostring(selected.movement_policy or '') == 'must_stop' then
		prelude_type = 'stop'
	end
	return {
		plan_id = ('plan.%d.%d'):format(math.floor(ctx.now * 1000), math.floor(ctx.tick)),
		selected_proposal_id = tostring(selected.proposal_id or ''),
		prelude = {
			type = prelude_type,
			target_id = tonumber(selected.target_id) or 0,
			timeout_s = 0.20,
		},
		primary = {
			action_type = tostring(selected.action_type or ''),
			action_name = tostring(selected.action_name or ''),
			target_id = tonumber(selected.target_id) or 0,
			target_name = tostring(selected.target_name or ''),
		},
		commit_deadline = p1_number(selected.commit_deadline, ctx.now + 0.25),
		created_at = ctx.now,
	}
end

function M.p1_revalidate_plan_commit(scheduler, ctx, selected, plan, p1_number, windower)
	if not selected or not plan then
		return false, 'invalid_plan'
	end
	if p1_number(selected.expires_at, 0) <= ctx.now then
		return false, 'expired'
	end
	if p1_number(plan.commit_deadline, 0) < ctx.now then
		return false, 'commit_deadline'
	end
	local target_kind = tostring(selected.target_kind or 'none')
	if target_kind == 'self' then
		return true, ''
	end
	local target_id = tonumber(selected.target_id) or 0
	if target_kind == 'ally' then
		if target_id <= 0 then
			return false, 'invalid_target'
		end
		local m = windower.ffxi.get_mob_by_id(target_id)
		if not m then
			return false, 'invalid_target'
		end
		return true, ''
	end
	if target_kind == 'mob' then
		if target_id <= 0 then
			return false, 'invalid_target'
		end
		local mob = windower.ffxi.get_mob_by_id(target_id)
		if not mob or not mob.valid_target or (tonumber(mob.hpp) or 0) <= 0 then
			return false, 'invalid_target'
		end
		return true, ''
	end
	return true, ''
end

return M
