local M = {}

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_cure_target_safety requires function dependency: ' .. tostring(name))
	end
	return fn
end

function M.validate(selected, deps)
	if type(selected) ~= 'table' then
		return false, 'BLOCK_DEFENSIVE_CURE_INVALID_PROPOSAL'
	end
	if type(deps) ~= 'table' then
		error('uc_cure_target_safety requires dependencies')
	end
	local detail = type(selected.detail) == 'table' and selected.detail or {}
	if tostring(selected.action_type or '') ~= 'spell' or tostring(detail.def_action_type or '') ~= 'cure' then
		return true, ''
	end
	local cure_intent = tostring(detail.cure_intent or '')
	local target_kind = tostring(selected.target_kind or '')
	if target_kind == 'self' then
		if cure_intent == 'sleep_wake' then
			return false, 'BLOCK_SLEEP_WAKE_SELF_TARGET'
		end
		return true, ''
	end
	local target_id = tonumber(selected.target_id) or 0
	if target_kind ~= 'ally' or target_id <= 0 then
		return false, 'BLOCK_DEFENSIVE_CURE_INVALID_TARGET'
	end
	local get_mob_by_id = require_function(deps, 'get_mob_by_id')
	local mob = get_mob_by_id(target_id)
	if type(mob) ~= 'table' then
		return false, 'BLOCK_DEFENSIVE_CURE_INVALID_TARGET'
	end
	if mob.charmed == true then
		return false, 'BLOCK_DEFENSIVE_CURE_CHARMED_TARGET'
	end
	if cure_intent ~= 'sleep_wake' then
		return true, ''
	end
	if mob.charmed ~= false then
		return false, 'BLOCK_SLEEP_WAKE_CHARM_STATE_UNKNOWN'
	end
	local get_party_member_by_id = require_function(deps, 'get_party_member_by_id')
	local member = get_party_member_by_id(target_id)
	if type(member) ~= 'table' or type(member.buffs) ~= 'table' then
		return false, 'BLOCK_SLEEP_WAKE_BUFF_STATE_UNKNOWN'
	end
	local sleep_status = deps.sleep_status
	if type(sleep_status) ~= 'table' or type(sleep_status.has_sleep) ~= 'function' then
		error('uc_cure_target_safety requires sleep_status.has_sleep')
	end
	if not sleep_status.has_sleep(member.buffs) then
		return false, 'BLOCK_SLEEP_WAKE_TARGET_AWAKE'
	end
	return true, ''
end

return M
