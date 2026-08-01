local uc_active_config = require('uc_active_config')
local combat_formation = require('uc_combat_formation')
local lilith_easy_encounter = require('uc_lilith_easy_encounter')
local movement_dispatcher = require('uc_movement_dispatcher').build({
	dispatcher = require('uc_scheduler_dispatcher'),
	run = windower.ffxi.run,
	source_prefix = 'lilith_formation',
})

local M = {}

local formation_run_active = false

function M.reset(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('uc_lilith_easy_formation_runtime.reset requires a non-empty reason')
	end
	formation_run_active = false
end

local function formation_config()
	local config = uc_active_config.get_path('config.movement.formation')
	if type(config) ~= 'table' then
		return nil
	end
	return config
end

local function find_lady_lilith()
	local mobs = windower.ffxi.get_mob_array()
	if type(mobs) ~= 'table' then
		return nil, 'MOB_ARRAY_UNAVAILABLE'
	end
	local found = nil
	local count = 0
	for _, mob in pairs(mobs) do
		if type(mob) == 'table' and tostring(mob.name) == 'Lady Lilith' then
			local hpp = tonumber(mob.hpp)
			if hpp == nil then
				return nil, 'LADY_LILITH_HPP_UNAVAILABLE'
			end
			if hpp > 0 then
				found = mob
				count = count + 1
			end
		end
	end
	if count > 1 then
		return nil, 'MULTIPLE_LADY_LILITH_ACTORS'
	end
	return found, ''
end

function M.observe(now)
	local config = formation_config()
	if config == nil or config.enabled ~= true then
		lilith_easy_encounter.observe({ enabled = false })
		_G.UC_FORMATION_STATUS = {
			enabled = false,
			phase = 'disabled',
			reason = 'FORMATION_DISABLED',
		}
		return nil
	end
	local boss, find_reason = find_lady_lilith()
	if find_reason ~= '' then
		_G.UC_FORMATION_STATUS = {
			enabled = true,
			phase = 'error',
			reason = find_reason,
		}
		return { config = config, boss = nil, ready = false, reason = find_reason }
	end
	local ready, reason = lilith_easy_encounter.observe({
		enabled = true,
		encounter = config.encounter,
		capture_stable_s = config.capture_stable_s,
		capture_tolerance = config.capture_tolerance,
		now = now,
		boss = boss,
	})
	local encounter_status = lilith_easy_encounter.status()
	_G.UC_FORMATION_STATUS = {
		enabled = true,
		role = config.role,
		phase = encounter_status.phase,
		reason = reason,
		boss_id = encounter_status.boss_id,
		center = encounter_status.center,
		error = encounter_status.error,
	}
	return {
		config = config,
		boss = boss,
		ready = ready,
		reason = reason,
		center = encounter_status.center,
	}
end

local function formation_party_members()
	local party = windower.ffxi.get_party()
	if type(party) ~= 'table' then
		return nil, 'PARTY_UNAVAILABLE'
	end
	local members = {}
	local keys = { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }
	for i = 1, #keys do
		local entry = party[keys[i]]
		if type(entry) == 'table' and type(entry.mob) == 'table' then
			local mob = entry.mob
			if (tonumber(mob.x) == nil or tonumber(mob.y) == nil) and tonumber(mob.id) ~= nil then
				mob = windower.ffxi.get_mob_by_id(tonumber(mob.id))
			end
			if type(mob) == 'table' and tonumber(mob.x) ~= nil and tonumber(mob.y) ~= nil then
				members[#members + 1] = {
					id = tonumber(mob.id),
					name = tostring(mob.name),
					x = tonumber(mob.x),
					y = tonumber(mob.y),
				}
			end
		end
	end
	return members, ''
end

local function formation_boss_target(boss)
	local target_index = tonumber(boss and boss.target_index)
	if target_index == nil or target_index <= 0 then
		return nil
	end
	local target = windower.ffxi.get_mob_by_index(target_index)
	if type(target) ~= 'table' or tonumber(target.x) == nil or tonumber(target.y) == nil then
		return nil
	end
	return target
end

local function formation_heading(me, goal)
	local dx = goal.x - me.x
	local dy = goal.y - me.y
	if ((dx * dx) + (dy * dy)) < 0.000001 then
		return nil
	end
	return math.atan2(dx, dy) - 1.5708
end

local function dispatch_formation_stop(reason)
	local ok, dispatch_error = pcall(function()
		movement_dispatcher.stop({ reason = reason })
	end)
	if not ok then
		return false, 'FORMATION_STOP_DISPATCH_FAILED:' .. tostring(dispatch_error)
	end
	formation_run_active = false
	return true, reason
end

function M.stop(reason)
	if type(reason) ~= 'string' or reason == '' then
		error('uc_lilith_easy_formation_runtime.stop requires a non-empty reason')
	end
	if formation_run_active ~= true then
		return false, 'FORMATION_NOT_MOVING'
	end
	local stopped, stop_reason = dispatch_formation_stop(reason)
	if stopped ~= true then
		error(stop_reason)
	end
	return stopped, stop_reason
end

local function dispatch_formation_move(me, proposal)
	local heading = formation_heading(me, proposal.goal)
	if heading == nil then
		return false, 'FORMATION_MOVE_ZERO_VECTOR'
	end
	local ok, dispatch_error = pcall(function()
		movement_dispatcher.run_heading(heading, {
			reason = proposal.reason,
			heading = heading,
			goal_x = proposal.goal.x,
			goal_y = proposal.goal.y,
		})
	end)
	if not ok then
		return false, 'FORMATION_MOVE_DISPATCH_FAILED:' .. tostring(dispatch_error)
	end
	formation_run_active = true
	return true, proposal.reason
end

function M.run_tick(observation)
	if type(observation) ~= 'table' or type(observation.config) ~= 'table' then
		if formation_run_active then
			local stopped, stop_reason = dispatch_formation_stop('FORMATION_INACTIVE')
			return stopped, stop_reason, true
		end
		return false, 'FORMATION_INACTIVE', false
	end
	if tostring(observation.config.role) == 'disabled' then
		if formation_run_active then
			local stopped, stop_reason = dispatch_formation_stop('FORMATION_ROLE_DISABLED')
			return stopped, stop_reason, true
		end
		return false, 'FORMATION_ROLE_DISABLED', false
	end
	local boss = observation.boss
	if observation.ready ~= true or type(observation.center) ~= 'table' then
		local boss_status = nil
		if type(boss) == 'table' then
			boss_status = tonumber(boss.status)
		end
		local boss_active = boss_status ~= nil and boss_status ~= 0
		if boss_active then
			if formation_run_active then
				dispatch_formation_stop('FORMATION_CAPTURE_ERROR')
			end
			return false, 'FORMATION_CAPTURE_ERROR:' .. tostring(observation.reason), true
		end
		return false, tostring(observation.reason), false
	end
	if type(boss) ~= 'table' then
		if formation_run_active then
			local stopped, stop_reason = dispatch_formation_stop('FORMATION_ENCOUNTER_COMPLETE')
			return stopped, stop_reason, true
		end
		return false, 'FORMATION_ENCOUNTER_COMPLETE', false
	end
	local boss_hpp = tonumber(boss.hpp)
	local boss_status = tonumber(boss.status)
	if boss_hpp == nil or boss_status == nil then
		return false, 'FORMATION_BOSS_STATE_UNAVAILABLE', true
	end
	if boss_hpp <= 0 then
		if formation_run_active then
			local stopped, stop_reason = dispatch_formation_stop('FORMATION_ENCOUNTER_COMPLETE')
			return stopped, stop_reason, true
		end
		return false, 'FORMATION_ENCOUNTER_COMPLETE', false
	end
	if boss_status == 0 then
		return false, 'FORMATION_WAITING_FOR_ENGAGE', false
	end
	local me = windower.ffxi.get_mob_by_target('me')
	if type(me) ~= 'table' or tonumber(me.x) == nil or tonumber(me.y) == nil then
		return false, 'FORMATION_PLAYER_POSITION_UNAVAILABLE', true
	end
	local members, members_reason = formation_party_members()
	if members == nil then
		return false, members_reason, true
	end
	local proposal = combat_formation.evaluate({
		config = observation.config,
		center = observation.center,
		boss = boss,
		boss_target = formation_boss_target(boss),
		me = me,
		party_members = members,
		was_moving = formation_run_active,
	})
	_G.UC_FORMATION_STATUS.proposal = proposal
	if proposal.action == 'error' then
		if formation_run_active then
			dispatch_formation_stop('FORMATION_ERROR')
		end
		_G.UC_FORMATION_STATUS.error = proposal.reason
		return false, proposal.reason, true
	end
	if proposal.action == 'hold' then
		if formation_run_active then
			local stopped, stop_reason = dispatch_formation_stop(proposal.reason)
			return stopped, stop_reason, true
		end
		return false, proposal.reason, true
	end
	if proposal.action ~= 'move' or type(proposal.goal) ~= 'table' then
		error('formation evaluator returned an invalid proposal')
	end
	local moved, move_reason = dispatch_formation_move(me, proposal)
	if moved ~= true then
		_G.UC_FORMATION_STATUS.error = move_reason
	end
	return moved, move_reason, true
end

return M
