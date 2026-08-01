local M = {}

function M.p1_push_recent_rejects(scheduler, ctx, rejected)
	local phase = scheduler.phase1
	if type(phase.recent_rejects) ~= 'table' then
		phase.recent_rejects = {}
	end
	if type(phase.recent_reject_items) ~= 'table' then
		phase.recent_reject_items = {}
	end
	if type(rejected) ~= 'table' or #rejected == 0 then
		return
	end
	for _, r in ipairs(rejected) do
		local line = ('t%s %s/%s %s :: %s'):format(
			tostring(ctx.tick or ''),
			tostring(r.provider or ''),
			tostring(r.family or ''),
			tostring(r.action or ''),
			tostring(r.reason or '')
		)
		phase.recent_rejects[#phase.recent_rejects + 1] = line
		phase.recent_reject_items[#phase.recent_reject_items + 1] = {
			tick = tostring(ctx.tick or ''),
			provider = tostring(r.provider or ''),
			family = tostring(r.family or ''),
			action = tostring(r.action or ''),
			reason = tostring(r.reason or ''),
		}
	end
	local max_keep = 25
	local drop = #phase.recent_rejects - max_keep
	if drop > 0 then
		for _ = 1, drop do
			table.remove(phase.recent_rejects, 1)
		end
	end
	local drop_items = #phase.recent_reject_items - max_keep
	if drop_items > 0 then
		for _ = 1, drop_items do
			table.remove(phase.recent_reject_items, 1)
		end
	end
end

return M
