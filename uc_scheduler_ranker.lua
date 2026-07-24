local numeric = require('uc_scheduler_numeric_utils')
local proposals = require('uc_scheduler_proposals')

local M = {}

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_scheduler_ranker requires function dependency: ' .. tostring(name))
	end
	return fn
end

local function require_value(deps, name)
	local value = deps[name]
	if value == nil then
		error('uc_scheduler_ranker requires dependency: ' .. tostring(name))
	end
	return value
end

function M.validate_proposal(ctx, proposal, deps)
	local identity_ok, identity_reason = proposals.validate_identity(proposal)
	if not identity_ok then
		return false, identity_reason
	end

	local bool_setting = require_function(deps, 'bool_setting')
	local required_setting = tostring(proposal.required_setting or '')
	if required_setting ~= '' and not bool_setting(ctx.settings[required_setting], false) then
		return false, 'settings_disabled'
	end
	if proposals.created_age(ctx, proposal) > 0.8 then
		return false, 'stale_snapshot'
	end

	local phase = require_value(deps, 'phase1')
	local pending_engage_live = require_function(deps, 'pending_engage_live')
	if pending_engage_live(phase, ctx.now) then
		local provider = tostring(proposal.provider or '')
		local action_type = tostring(proposal.action_type or '')
		if provider ~= 'target_control' then
			if action_type == 'engage' then
				local pending = require_function(deps, 'pending_engage_state')(phase)
				local retry_ready_at = tonumber(pending and pending.retry_ready_at) or 0
				if retry_ready_at > ctx.now then
					require_function(deps, 'timeline_log')('ENGAGE_DISPATCH_BLOCKED', {
						tid = tonumber(proposal.target_id) or 0,
						name = tostring(proposal.target_name or ''),
						reason = 'pending_engage_retry_wait',
						retry_in_s = ('%.2f'):format(math.max(0, retry_ready_at - ctx.now)),
						retry_count = tonumber(pending and pending.retry_count) or 0,
						pending_engage = 'retry_wait',
						dispatch_method = tostring(require_value(deps, 'engage_dispatch_method')),
					}, ('engage_retry_wait:%d'):format(tonumber(proposal.target_id) or 0), 0.25)
					return false, 'pending_engage_retry_wait'
				end
			elseif not require_function(deps, 'priority_bypasses_engage')(proposal) then
				require_function(deps, 'timeline_log')('PENDING_ENGAGE_BLOCK_NONCRITICAL', {
					tid = tonumber(proposal.target_id) or 0,
					name = tostring(proposal.target_name or ''),
					action = tostring(proposal.action_name or ''),
					provider = provider,
				}, ('pending_engage_block:%s:%s'):format(provider, tostring(proposal.action_name or '')), 0.25)
				return false, 'pending_engage_block_noncritical'
			end
		end
	end

	if type(phase.pending) == 'table'
		and require_function(deps, 'pending_is_live_state')(tostring(phase.pending.state or '')) then
		local pending_lock_class = tostring(phase.pending.lock_class or '')
		local proposal_lock_class = tostring(proposal.lock_class or '')
		if pending_lock_class ~= '' and proposal_lock_class ~= ''
			and pending_lock_class ~= proposal_lock_class then
			local action_type = tostring(proposal.action_type or '')
			if action_type == 'spell' or action_type == 'ja'
				or action_type == 'ws' or action_type == 'move' then
				return false, 'pending_conflict'
			end
		end
	end

	local normalized, normalize_reason = proposals.normalize_live_fields(ctx, proposal)
	if not normalized then
		return false, normalize_reason
	end

	local engage_duplicate_mode, engage_duplicate_fields =
		require_function(deps, 'validate_engage_duplicate_retry')(ctx, proposal)
	if engage_duplicate_mode == 'suppressed' then
		proposal._engage_duplicate_log_fields = engage_duplicate_fields
		return false, 'duplicate_suppressed'
	end
	if engage_duplicate_mode ~= 'skip_generic'
		and require_function(deps, 'duplicate_suppressed')(ctx, proposal) then
		proposal._engage_duplicate_log_fields = engage_duplicate_fields
		return false, 'duplicate_suppressed'
	end
	return true, ''
end

function M.score(proposal)
	local priority_band = math.floor(numeric.p1_number(proposal.priority_band, 0))
	local urgency_bonus = numeric.p1_clamp_urgency(proposal.urgency) * 9.9
	local starvation_bonus = 0
	local sticky_bonus = 0
	local risk_penalty = 0
	local score = priority_band + urgency_bonus + starvation_bonus + sticky_bonus - risk_penalty
	proposal._score = score
	proposal._score_parts = {
		priority_band = priority_band,
		urgency_bonus = urgency_bonus,
		starvation_bonus = starvation_bonus,
		sticky_bonus = sticky_bonus,
		risk_penalty = risk_penalty,
	}
	return score
end

local function add_reject(ctx, rejected, proposal, reason, deps)
	local p = proposal or {}
	if tostring(p.family_id or '') == 'combat.engage.primary'
		and tostring(reason or '') == 'duplicate_suppressed' then
		local fields = type(p._engage_duplicate_log_fields) == 'table'
			and p._engage_duplicate_log_fields
			or {
				tid = tonumber(p.target_id) or 0,
				name = tostring(p.target_name or ''),
				reason = 'BLOCK_DUPLICATE',
				status = tonumber(ctx and ctx.player_status) or 0,
				dispatch_method = tostring(require_value(deps, 'engage_dispatch_method')),
			}
		require_function(deps, 'timeline_log')(
			'ENGAGE_DUPLICATE_SUPPRESSED',
			fields,
			('engage_dup:%d'):format(tonumber(p.target_id) or 0),
			0.50
		)
	end
	rejected[#rejected + 1] = {
		provider = tostring(p.provider or ''),
		family = tostring(p.family_id or ''),
		action = tostring(p.action_name or ''),
		reason = tostring(reason or ''),
	}
end

local function compare_ranked(ctx, a, b)
	local score_a = numeric.p1_number(a._score, -1e9)
	local score_b = numeric.p1_number(b._score, -1e9)
	if score_a ~= score_b then
		return score_a > score_b
	end
	local expires_a = numeric.p1_number(a.expires_at, ctx.now + 999)
	local expires_b = numeric.p1_number(b.expires_at, ctx.now + 999)
	if expires_a ~= expires_b then
		return expires_a < expires_b
	end
	local provider_a = tostring(a.provider or '')
	local provider_b = tostring(b.provider or '')
	if provider_a ~= provider_b then
		return provider_a < provider_b
	end
	return tostring(a.proposal_id or '') < tostring(b.proposal_id or '')
end

local function publish_engage_rank_debug(ctx, valid, deps)
	if not require_function(deps, 'debug_enabled')(ctx and ctx.settings) then
		return
	end
	local seen_engage = false
	local won_engage = false
	local top_provider = ''
	local top_family = ''
	local top_action = ''
	local top_score = 0
	if #valid > 0 then
		top_provider = tostring(valid[1].provider or '')
		top_family = tostring(valid[1].family_id or '')
		top_action = tostring(valid[1].action_type or '')
		top_score = tonumber(valid[1]._score) or 0
	end
	for _, proposal in ipairs(valid) do
		if tostring(proposal.family_id or '') == 'combat.engage.primary' then
			seen_engage = true
			if proposal == valid[1] then
				won_engage = true
			end
			break
		end
	end
	if seen_engage and not won_engage then
		require_function(deps, 'publish_last_action')(
			('[p1]engage:rank_lost top=%s/%s/%s score=%.2f'):format(
				top_provider,
				top_family,
				top_action,
				top_score
			)
		)
		local top = valid[1]
		local block_reason = 'BLOCK_UNKNOWN'
		if require_function(deps, 'is_critical_defensive_proposal')(
			ctx and ctx.settings or nil,
			top
		) then
			block_reason = 'BLOCK_CRITICAL_CURE'
		elseif require_function(deps, 'priority_bypasses_engage')(top) then
			block_reason = 'BLOCK_HIGH_PRIORITY'
		end
		require_function(deps, 'timeline_log')('ENGAGE_DISPATCH_BLOCKED', {
			tid = tonumber(valid[1] and valid[1].target_id) or 0,
			name = tostring(valid[1] and valid[1].target_name or ''),
			reason = block_reason,
			provider = top_provider,
			action = top_action,
		}, ('engage_rank_lost:%s:%s'):format(top_provider, top_action), 0.50)
	elseif seen_engage and won_engage then
		require_function(deps, 'publish_last_action')('[p1]engage:rank_win')
	end
end

function M.rank(ctx, proposal_list, deps)
	local locks = require_function(deps, 'get_locks')(ctx)
	local valid = {}
	local reject_counts = {}
	local rejected = {}
	for _, proposal in ipairs(proposal_list) do
		local ok, reject_reason = M.validate_proposal(ctx, proposal, deps)
		if require_function(deps, 'reaction_blocks_proposal')(
			require_function(deps, 'get_reaction_lock')(),
			proposal
		) then
			ok = false
			reject_reason = 'reaction_hold'
		end
		if ok then
			local lock_reject = require_function(deps, 'hard_lock_reject')(locks, proposal)
			if lock_reject ~= '' then
				reject_counts[lock_reject] = (reject_counts[lock_reject] or 0) + 1
				add_reject(ctx, rejected, proposal, lock_reject, deps)
			else
				M.score(proposal)
				valid[#valid + 1] = proposal
			end
		else
			local reason = reject_reason ~= '' and tostring(reject_reason) or 'invalid'
			reject_counts[reason] = (reject_counts[reason] or 0) + 1
			add_reject(ctx, rejected, proposal, reason, deps)
		end
	end
	table.sort(valid, function(a, b)
		return compare_ranked(ctx, a, b)
	end)
	publish_engage_rank_debug(ctx, valid, deps)
	return valid, reject_counts, locks, rejected
end

return M
