local numeric = require('uc_scheduler_numeric_utils')
local rank_output = require('uc_scheduler_rank_output')
local reject_history = require('uc_scheduler_reject_history')
local dryrun_publish = require('uc_scheduler_dryrun_publish')

local M = {}

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_scheduler_observability requires function dependency: ' .. tostring(name))
	end
	return fn
end

function M.format_top3(scheduler, ranked)
	return rank_output.p1_format_top3(scheduler, ranked, numeric.p1_number)
end

function M.format_top3_verbose(scheduler, ranked)
	return rank_output.p1_format_top3_verbose(scheduler, ranked, numeric.p1_number)
end

function M.format_topn_lines(scheduler, ranked, count)
	return rank_output.p1_format_topn_lines(scheduler, ranked, count, numeric.p1_number)
end

function M.capture_topn_items(scheduler, ranked, count)
	return rank_output.p1_capture_topn_items(scheduler, ranked, count, numeric.p1_number)
end

function M.push_recent_rejects(scheduler, ctx, rejected)
	return reject_history.p1_push_recent_rejects(scheduler, ctx, rejected)
end

function M.reject_top(scheduler, reject_counts, proposal_count)
	return rank_output.p1_reject_top(scheduler, reject_counts, proposal_count)
end

function M.publish_dryrun(
	scheduler,
	globals,
	ctx,
	selected,
	ranked,
	reject_counts,
	rejected,
	proposal_list,
	locks,
	plan,
	commit_reason,
	deps
)
	return dryrun_publish.publish(
		scheduler,
		globals,
		ctx,
		selected,
		ranked,
		reject_counts,
		rejected,
		proposal_list,
		locks,
		plan,
		commit_reason,
		function(items)
			return M.format_top3(scheduler, items)
		end,
		function(items)
			return M.format_top3_verbose(scheduler, items)
		end,
		function(items, count)
			return M.format_topn_lines(scheduler, items, count)
		end,
		function(items, count)
			return M.capture_topn_items(scheduler, items, count)
		end,
		function(push_ctx, items)
			return M.push_recent_rejects(scheduler, push_ctx, items)
		end,
		function(counts, count)
			return M.reject_top(scheduler, counts, count)
		end,
		require_function(deps, 'set_pending_globals'),
		require_function(deps, 'build_lock_summary')
	)
end

local function buff_label(resources_buffs, buff_id)
	local id = tonumber(buff_id) or 0
	if id <= 0 then
		return ''
	end
	local buff = resources_buffs and resources_buffs[id] or nil
	local name = tostring((buff and buff.en) or ('id:' .. tostring(id)))
	return ('%s[%d]'):format(name, id)
end

local function buff_labels(resources_buffs, list)
	local out = {}
	for _, buff_id in ipairs(list or {}) do
		local label = buff_label(resources_buffs, buff_id)
		if label ~= '' then
			out[#out + 1] = label
		end
	end
	return out
end

local function pad_right(value, width)
	local text = tostring(value or '')
	local count = width - #text
	if count <= 0 then
		return text
	end
	return text .. string.rep(' ', count)
end

local function build_buff_up_lines(deps)
	local lines = {}
	local members = require_function(deps, 'get_party_members')()
	if type(members) ~= 'table' or #members == 0 then
		lines[#lines + 1] = 'self: (no party member view)'
		return lines
	end
	local self_member
	for _, member in ipairs(members) do
		if member and member.is_self == true then
			self_member = member
			break
		end
	end
	if not self_member then
		lines[#lines + 1] = 'self: (not found in scheduler member view)'
		return lines
	end
	local self_name = tostring(self_member.name or '')
	local self_source = tostring(self_member.source or 'unknown')
	local eval_buffs = self_member.buffs or {}
	local player = require_function(deps, 'get_player')()
	local self_local_buffs = player and player.buffs or {}
	local ipc_buffs = {}
	local ipc = require_function(deps, 'get_party_state_ipc_entry')(
		tonumber(self_member.id) or 0,
		self_name
	)
	if ipc and type(ipc.buffs) == 'table' then
		ipc_buffs = ipc.buffs
	end
	local party_buffs = {}
	local party = require_function(deps, 'get_party')() or {}
	for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
		local entry = party[key]
		if entry and entry.mob and tonumber(entry.mob.id) == tonumber(self_member.id) then
			party_buffs = entry.buffs or {}
			break
		end
	end
	local state = require_function(deps, 'ensure_maintenance_state_tables')()
	local snapshot = (state.status_snapshot or {})[self_name]
	local snapshot_count = 0
	if type(snapshot) == 'table' then
		for _ in pairs(snapshot) do
			snapshot_count = snapshot_count + 1
		end
	end
	lines[#lines + 1] = ('eval_source=%s self=%s snapshot_ids=%d'):format(
		self_source,
		self_name,
		snapshot_count
	)
	local resources_buffs = deps.resources_buffs
	local eval_labels = buff_labels(resources_buffs, eval_buffs)
	local self_labels = buff_labels(resources_buffs, self_local_buffs)
	local ipc_labels = buff_labels(resources_buffs, ipc_buffs)
	local party_labels = buff_labels(resources_buffs, party_buffs)
	local row_count = math.max(
		#eval_labels,
		#self_labels,
		#ipc_labels,
		#party_labels
	)
	local show_rows = math.max(1, row_count)
	local width_eval = 30
	local width_self = 30
	local width_ipc = 30
	lines[#lines + 1] = pad_right('eval(used)', width_eval) .. ' | '
		.. pad_right('self_local', width_self) .. ' | '
		.. pad_right('ipc', width_ipc) .. ' | party'
	for index = 1, show_rows do
		lines[#lines + 1] = pad_right(eval_labels[index] or '', width_eval) .. ' | '
			.. pad_right(self_labels[index] or '', width_self) .. ' | '
			.. pad_right(ipc_labels[index] or '', width_ipc) .. ' | '
			.. (party_labels[index] or '')
	end
	return lines
end

function M.build_debug_overlay(phase1, deps)
	local queued = {}
	for _, item in ipairs(phase1.last_top5_items or {}) do
		if require_function(deps, 'provider_enabled')(item.provider) then
			queued[#queued + 1] = ('%d) %.2f %s/%s %s u=%.2f rp=%.2f'):format(
				tonumber(item.idx) or 0,
				tonumber(item.score) or 0,
				tostring(item.provider or ''),
				tostring(item.family or ''),
				tostring(item.action or ''),
				tonumber(item.urgency_bonus) or 0,
				tonumber(item.risk_penalty) or 0
			)
		end
	end
	local accepted = {}
	for _, item in ipairs(phase1.recent_reject_items or {}) do
		if require_function(deps, 'provider_enabled')(item.provider) then
			accepted[#accepted + 1] = item
		end
	end
	local rejected = {}
	local start_at = math.max(1, #accepted - 4)
	for index = #accepted, start_at, -1 do
		local item = accepted[index]
		rejected[#rejected + 1] = ('t%s %s/%s %s :: %s'):format(
			tostring(item.tick or ''),
			tostring(item.provider or ''),
			tostring(item.family or ''),
			tostring(item.action or ''),
			tostring(item.reason or '')
		)
	end
	return {
		tick = numeric.p1_number(phase1.tick, 0),
		queued = queued,
		rejected = rejected,
		buff_up = build_buff_up_lines(deps),
	}
end

function M.build_enemy_effect_overlay(effect_map, deps)
	local lines = { 'Enemy Effect Table (effectiveTargets)' }
	local target_ids = {}
	for target_id, effects in pairs(effect_map) do
		if type(effects) == 'table' then
			target_ids[#target_ids + 1] = tonumber(target_id) or 0
		end
	end
	table.sort(target_ids)
	if #target_ids == 0 then
		lines[#lines + 1] = '(none)'
		return { lines = lines }
	end
	for _, target_id in ipairs(target_ids) do
		if target_id > 0 then
			local mob = require_function(deps, 'get_mob_by_id')(target_id)
			local name = tostring((mob and mob.name) or '?')
			local hpp = tonumber((mob and mob.hpp) or 0) or 0
			lines[#lines + 1] = ('%s[%d] hpp=%d'):format(name, target_id, hpp)
			local effects = effect_map[target_id] or effect_map[tostring(target_id)] or {}
			local effect_ids = {}
			for effect_id in pairs(effects) do
				local numeric_id = tonumber(effect_id) or 0
				if numeric_id > 0 then
					effect_ids[#effect_ids + 1] = numeric_id
				end
			end
			table.sort(effect_ids)
			if #effect_ids == 0 then
				lines[#lines + 1] = '  (no effects)'
			else
				for _, effect_id in ipairs(effect_ids) do
					local buff = deps.resources_buffs
						and deps.resources_buffs[effect_id]
						or nil
					local buff_name = tostring(
						(buff and buff.en) or ('id:' .. tostring(effect_id))
					)
					local record = effects[effect_id]
						or effects[tostring(effect_id)]
						or {}
					local source = tostring(record.source or '')
					if source ~= '' then
						lines[#lines + 1] =
							('  - %s(%d) src=%s'):format(
								buff_name,
								effect_id,
								source
							)
					else
						lines[#lines + 1] =
							('  - %s(%d)'):format(buff_name, effect_id)
					end
				end
			end
		end
	end
	return { lines = lines }
end

return M
