local M = {}

function M.p1_build_dispatch_plan(scheduler, ctx, selected, p1_number)
	if not selected then
		return nil
	end
	local prelude_type = 'none'
	if tostring(selected.movement_policy or '') == 'must_stop' then
		prelude_type = 'stop'
	end
	local plan = {
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
		skillchain_plan = selected.skillchain_plan,
		commit_deadline = p1_number(selected.commit_deadline, ctx.now + 0.25),
		created_at = ctx.now,
	}
	if selected.smart_aoe_guard == true then
		plan.smart_aoe_guard = true
	end
	return plan
end

-- Packet completion can advance a copied reaction sequence after the
-- originating rule has been disabled or edited. Before issuing a follow-up
-- command, confirm that both the live lock and its original canonical rule
-- still authorize the exact current step.
local function sequence_step_still_configured(ctx, selected)
    local detail = type(selected.detail) == 'table' and selected.detail or {}
    local runtime = require('uc_reaction_runtime')
    local lock = runtime.get_action_lock()
    if type(lock) ~= 'table' or tostring(lock.response or '') ~= 'use_sequence'
        or tostring(lock.key or '') ~= tostring(detail.reaction_key or '')
        or (tonumber(lock.step_index) or 0) ~= (tonumber(detail.reaction_step_index) or -1)
        or tostring(lock.action_type or '') ~= tostring(selected.action_type or '')
        or tostring(lock.action_name or '') ~= tostring(selected.action_name or '') then
        return false
    end

    local rules
    if type(ctx.config) == 'table' then
        local reactions = ctx.config.reactions
        if type(reactions) ~= 'table' or reactions.enabled ~= true then
            return false
        end
        rules = reactions.rules
    else
        -- The scheduler normally has a v2 config snapshot. Keep legacy
        -- behavior for genuine pre-profile callers only.
        rules = require('uc_combat_extension_config').reaction_rules()
    end
    local index = tonumber(lock.rule_index) or 0
    local rule = type(rules) == 'table' and index > 0 and rules[index] or nil
    if type(rule) ~= 'table'
        or tostring(rule.trigger or '') ~= tostring(lock.trigger or '')
        or tostring(rule.response or '') ~= 'use_sequence'
        or tostring(rule.name or ''):lower() ~= tostring(lock.name or ''):lower() then
        return false
    end
    if rule.trigger == 'party_action_complete'
        and (tostring(rule.source_name or ''):lower() ~= tostring(lock.event_actor_name or ''):lower()
        or tostring(rule.action_type or ''):lower() ~= tostring(lock.completed_action_type or ''):lower()) then
        return false
    end
    local configured_steps = rule.steps
    local captured_steps = lock.steps
    if type(configured_steps) ~= 'table' or type(captured_steps) ~= 'table'
        or #configured_steps ~= #captured_steps then
        return false
    end
    for i = 1, #captured_steps do
        local original, current = captured_steps[i], configured_steps[i]
        if type(original) ~= 'table' or type(current) ~= 'table'
            or tostring(original.action_type or ''):lower() ~= tostring(current.action_type or ''):lower()
            or tostring(original.action_name or '') ~= tostring(current.action_name or '')
            or tostring(original.target or ''):lower() ~= tostring(current.target or ''):lower()
            or (original.optional == true) ~= (current.optional == true) then
            return false
        end
    end
    return true
end

function M.p1_revalidate_plan_commit(scheduler, ctx, selected, plan, p1_number, windower, combat_core)
	if not selected or not plan then
		return false, 'invalid_plan'
	end
	if p1_number(selected.expires_at, 0) <= ctx.now then
		return false, 'expired'
	end
	if p1_number(plan.commit_deadline, 0) < ctx.now then
		return false, 'commit_deadline'
	end
	if tostring(selected.family_id or '') == 'combat.reaction.sequence'
		and not sequence_step_still_configured(ctx, selected) then
		return false, 'reaction_policy_changed'
	end
	-- Rank-time enablement can change before commit. Recheck the same
	-- canonical-only required-setting contract at the action boundary;
	-- neither transient flat values nor unknown settings may revive a plan.
	local required_setting = tostring(selected.required_setting or '')
	if required_setting ~= '' then
		local enabled = require('uc_scheduler_config').required_setting_value_from_config(
			ctx.config, required_setting
		)
		if enabled ~= true then
			return false, 'settings_disabled'
		end
	end
	if plan.smart_aoe_guard == true then
		if type(combat_core) ~= 'table' or type(combat_core.revalidate_smart_ws_aoe) ~= 'function' then
			error('Smart WS dispatch plan requires AoE commit revalidation')
		end
		local aoe_allowed, aoe_reason = combat_core.revalidate_smart_ws_aoe(
			ctx.settings or {},
			selected.action_name,
			ctx.config
		)
		if not aoe_allowed then
			return false, aoe_reason
		end
	end
	if type(plan.skillchain_plan) == 'table' then
		if type(combat_core) ~= 'table' or type(combat_core.revalidate_skillchain_plan) ~= 'function' then
			error('skillchain dispatch plan requires core commit revalidation')
		end
		return combat_core.revalidate_skillchain_plan(
			plan.skillchain_plan,
			ctx.settings or {},
			selected.target_id,
			selected.action_name,
			'rank_commit',
			ctx.config
		)
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
