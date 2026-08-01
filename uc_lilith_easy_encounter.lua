local M = {}

local state = {
	phase = 'idle',
	boss_id = 0,
	center = nil,
	candidate = nil,
	candidate_since = 0,
	error = '',
	last_reset_reason = 'initial',
}

local function copy_point(point)
	if type(point) ~= 'table' then
		return nil
	end
	return { x = point.x, y = point.y, z = point.z }
end

local function distance_2d(left, right)
	local dx = left.x - right.x
	local dy = left.y - right.y
	return math.sqrt((dx * dx) + (dy * dy))
end

local function clear_runtime(reason)
	state.phase = 'idle'
	state.boss_id = 0
	state.center = nil
	state.candidate = nil
	state.candidate_since = 0
	state.error = ''
	state.last_reset_reason = tostring(reason)
end

function M.reset(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('uc_lilith_easy_encounter.reset requires a non-empty reason')
	end
	clear_runtime(reason)
end

local function invalid_config(reason)
	state.phase = 'error'
	state.error = reason
	return false, reason
end

function M.observe(opts)
	if type(opts) ~= 'table' then
		error('uc_lilith_easy_encounter.observe requires opts')
	end
	if opts.enabled ~= true then
		if state.phase ~= 'idle' or state.center ~= nil or state.candidate ~= nil then
			clear_runtime('disabled')
		end
		return false, 'DISABLED'
	end
	if opts.encounter ~= 'lilith_easy' then
		return invalid_config('UNSUPPORTED_ENCOUNTER')
	end
	local stable_s = tonumber(opts.capture_stable_s)
	local tolerance = tonumber(opts.capture_tolerance)
	local now = tonumber(opts.now)
	if stable_s == nil or stable_s <= 0 or tolerance == nil or tolerance <= 0 or now == nil then
		return invalid_config('INVALID_CAPTURE_CONFIG')
	end
	local boss = opts.boss
	if boss == nil then
		if state.center ~= nil then
			state.phase = 'complete'
			return true, 'BOSS_GONE'
		end
		state.candidate = nil
		state.candidate_since = 0
		state.phase = 'awaiting_boss'
		return false, 'AWAITING_BOSS'
	end
	if type(boss) ~= 'table' or tostring(boss.name) ~= 'Lady Lilith' then
		return invalid_config('INVALID_BOSS_ACTOR')
	end
	local boss_id = tonumber(boss.id)
	local boss_x = tonumber(boss.x)
	local boss_y = tonumber(boss.y)
	local boss_z = tonumber(boss.z)
	local boss_hpp = tonumber(boss.hpp)
	local boss_status = tonumber(boss.status)
	if boss_id == nil or boss_id <= 0 or boss_x == nil or boss_y == nil or boss_hpp == nil or boss_status == nil then
		return invalid_config('INCOMPLETE_BOSS_ACTOR')
	end
	if boss_hpp <= 0 then
		state.phase = 'complete'
		return state.center ~= nil, 'BOSS_DEFEATED'
	end
	if state.boss_id ~= 0 and state.boss_id ~= boss_id then
		clear_runtime('new_boss_actor')
	end
	state.boss_id = boss_id
	if state.center ~= nil then
		if boss_status == 0 then
			state.phase = 'center_captured'
		else
			state.phase = 'active'
		end
		return true, 'CENTER_READY'
	end
	if boss_status ~= 0 then
		state.phase = 'error'
		state.error = 'CENTER_CAPTURE_MISSED'
		state.candidate = nil
		state.candidate_since = 0
		return false, state.error
	end
	local observed = { x = boss_x, y = boss_y, z = boss_z }
	if state.candidate == nil or distance_2d(state.candidate, observed) > tolerance then
		state.candidate = observed
		state.candidate_since = now
		state.phase = 'capturing_center'
		state.error = ''
		return false, 'CAPTURE_STABILIZING'
	end
	if (now - state.candidate_since) < stable_s then
		state.phase = 'capturing_center'
		return false, 'CAPTURE_STABILIZING'
	end
	state.center = copy_point(state.candidate)
	state.candidate = nil
	state.candidate_since = 0
	state.phase = 'center_captured'
	state.error = ''
	return true, 'CENTER_CAPTURED'
end

function M.center()
	return copy_point(state.center)
end

function M.status()
	return {
		phase = state.phase,
		boss_id = state.boss_id,
		center = copy_point(state.center),
		candidate = copy_point(state.candidate),
		candidate_since = state.candidate_since,
		error = state.error,
		last_reset_reason = state.last_reset_reason,
	}
end

return M
