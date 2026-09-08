local capabilities = require('uc_sch_capabilities')
local skillchain = require('uc_sch_skillchain')
local skillchain_target = require('uc_sch_skillchain_target')

local M = {}

local DARK_ARTS_BUFF_ID = capabilities.abilities.dark_arts.buff_id
local ADDENDUM_BLACK_BUFF_ID = capabilities.abilities.addendum_black.buff_id
local IMMANENCE_BUFF_ID = capabilities.abilities.immanence.buff_id
local SEQUENCE_TIMEOUT_S = 18.0
local EVIDENCE_TIMEOUT_S = 4.0
local CLOSER_PREP_LEAD_S = 1.0
local RESTART_FALLBACK_S = 8.0

local function clone_value(value, seen)
	if type(value) ~= 'table' then
		return value
	end
	local visited = seen or {}
	if visited[value] then
		error('Scholar skillchain runtime state must not contain cycles')
	end
	visited[value] = true
	local out = {}
	for key, inner in pairs(value) do
		out[clone_value(key, visited)] = clone_value(inner, visited)
	end
	visited[value] = nil
	return out
end

local function has_buff(buffs, id)
	for i = 1, #(buffs or {}) do
		if tonumber(buffs[i]) == tonumber(id) then
			return true
		end
	end
	return false
end

local function contains(values, wanted)
	for i = 1, #(values or {}) do
		if tostring(values[i]) == tostring(wanted) then
			return true
		end
	end
	return false
end

local Runtime = {}
Runtime.__index = Runtime

function M.new()
	return setmetatable({
		generation = 0,
		active = nil,
		next_start_at = 0,
		last_result = '',
		last_blocker = 'idle',
	}, Runtime)
end

function Runtime:_abort(reason, now)
	skillchain_target.clear()
	self.active = nil
	self.next_start_at = math.max(tonumber(self.next_start_at) or 0, (tonumber(now) or 0) + 1.0)
	self.last_result = 'aborted:' .. tostring(reason or 'unknown')
	self.last_blocker = tostring(reason or 'unknown')
	return false, self.last_blocker
end

function Runtime:_complete(snapshot, now)
	local restart = tonumber(snapshot and snapshot.magic_burst_expires_at)
	if restart == nil or restart <= now then
		restart = now + RESTART_FALLBACK_S
	end
	skillchain_target.clear()
	self.active = nil
	self.next_start_at = restart
	self.last_result = 'completed'
	self.last_blocker = 'magic_burst_window'
	return true, ''
end

function Runtime:_start(plan, target, skillchain_snapshot, now)
	self.generation = self.generation + 1
	self.active = {
		generation = self.generation,
		phase = 'ensure_dark_arts',
		plan = clone_value(plan),
		target_id = tonumber(target.id) or 0,
		target_name = tostring(target.name or ''),
		started_at = now,
		deadline = now + SEQUENCE_TIMEOUT_S,
		phase_deadline = now + EVIDENCE_TIMEOUT_S,
		baseline_generation = tonumber(skillchain_snapshot and skillchain_snapshot.generation) or 0,
		opener_generation = 0,
		closer_execute_at = 0,
		closer_latest_safe_at = 0,
		pending = false,
	}
	local bound, bind_reason = skillchain_target.bind(target)
	if not bound then
		self.active = nil
		self.last_result = 'aborted:' .. tostring(bind_reason or 'target_bind_failed')
		self.last_blocker = tostring(bind_reason or 'target_bind_failed')
		return false
	end
	self.last_result = 'started:' .. tostring(plan.result)
	self.last_blocker = ''
	return true
end

local function dark_arts_active(buffs)
	return has_buff(buffs, DARK_ARTS_BUFF_ID) or has_buff(buffs, ADDENDUM_BLACK_BUFF_ID)
end

function Runtime:_advance(input)
	local active = self.active
	if active == nil then
		return
	end
	local now = input.now
	if now > active.deadline then
		self:_abort('sequence_deadline_expired', now)
		return
	end
	local target = input.target
	if type(target) ~= 'table'
		or tonumber(target.id) ~= active.target_id
		or target.valid_target ~= true
		or (tonumber(target.hpp) or 0) <= 0 then
		self:_abort('target_changed_or_invalid', now)
		return
	end
	if input.standard_sequence_active == true then
		self:_abort('standard_sch_sequence_started', now)
		return
	end
	local buffs = input.player_buffs or {}
	local snapshot = input.skillchain_snapshot

	if active.phase == 'ensure_dark_arts' and dark_arts_active(buffs) then
		active.phase = 'use_immanence_opener'
		active.phase_deadline = now + EVIDENCE_TIMEOUT_S
		return
	end
	if active.phase == 'wait_dark_arts' then
		if dark_arts_active(buffs) then
			active.phase = 'use_immanence_opener'
			active.pending = false
			active.phase_deadline = now + EVIDENCE_TIMEOUT_S
		elseif now > active.phase_deadline then
			self:_abort('dark_arts_confirmation_timeout', now)
		end
		return
	end
	if active.phase == 'wait_immanence_opener' then
		if has_buff(buffs, IMMANENCE_BUFF_ID) then
			active.phase = 'cast_opener'
			active.pending = false
			active.phase_deadline = now + EVIDENCE_TIMEOUT_S
		elseif now > active.phase_deadline then
			self:_abort('opener_immanence_confirmation_timeout', now)
		end
		return
	end
	if active.phase == 'wait_opener_result' then
		local generation = tonumber(snapshot and snapshot.generation) or 0
		local properties = snapshot and snapshot.active_properties or {}
		if generation > active.baseline_generation
			and contains(properties, active.plan.opener_property) then
			active.opener_generation = generation
			active.closer_execute_at = tonumber(snapshot.preferred_execute_at)
				or tonumber(snapshot.earliest_close_at) or now
			active.closer_latest_safe_at = tonumber(snapshot.latest_safe_at)
				or tonumber(snapshot.expires_at) or (now + 5.0)
			active.phase = 'wait_closer_timing'
			active.pending = false
			active.phase_deadline = active.closer_latest_safe_at
		elseif now > active.phase_deadline then
			self:_abort('opener_skillchain_evidence_timeout', now)
		end
		return
	end
	if active.phase == 'wait_closer_timing' then
		if now > active.closer_latest_safe_at then
			self:_abort('closer_window_expired', now)
			return
		end
		if now >= math.max(0, active.closer_execute_at - CLOSER_PREP_LEAD_S) then
			active.phase = 'use_immanence_closer'
			active.phase_deadline = active.closer_latest_safe_at
		end
		return
	end
	if active.phase == 'wait_immanence_closer' then
		if has_buff(buffs, IMMANENCE_BUFF_ID) then
			active.phase = 'cast_closer'
			active.pending = false
			active.phase_deadline = active.closer_latest_safe_at
		elseif now > active.phase_deadline then
			self:_abort('closer_immanence_confirmation_timeout', now)
		end
		return
	end
	if active.phase == 'wait_result' then
		local generation = tonumber(snapshot and snapshot.generation) or 0
		local properties = snapshot and snapshot.active_properties or {}
		if generation > active.opener_generation
			and contains(properties, active.plan.result) then
			self:_complete(snapshot, now)
		elseif now > active.phase_deadline then
			self:_abort('skillchain_result_timeout', now)
		end
	end
end

function Runtime:update(input)
	if type(input) ~= 'table' then
		error('Scholar skillchain runtime update requires input')
	end
	local now = tonumber(input.now)
	if now == nil then
		error('Scholar skillchain runtime update requires numeric now')
	end
	self:_advance(input)
	if self.active ~= nil then
		return true
	end
	local config = input.config
	local sc_config = type(config) == 'table'
		and type(config.offense) == 'table'
		and type(config.offense.skillchain) == 'table'
		and config.offense.skillchain or nil
	if type(config) ~= 'table' or config.enabled ~= true then
		self.last_blocker = 'sch_disabled'
		return false
	end
	if type(sc_config) ~= 'table' or sc_config.enabled ~= true then
		self.last_blocker = 'skillchain_disabled'
		return false
	end
	if input.engine_enabled ~= true or input.maintenance_enabled ~= true then
		self.last_blocker = 'engine_or_maintenance_disabled'
		return false
	end
	if input.critical_cure_present == true then
		self.last_blocker = 'critical_defense_present'
		return false
	end
	if input.standard_sequence_active == true then
		self.last_blocker = 'standard_sch_sequence_active'
		return false
	end
	if now < (tonumber(self.next_start_at) or 0) then
		self.last_blocker = 'skillchain_restart_hold'
		return false
	end
	local target = input.target
	if type(target) ~= 'table' or target.valid_target ~= true
		or (tonumber(target.id) or 0) <= 0 or (tonumber(target.hpp) or 0) <= 0 then
		self.last_blocker = 'no_valid_enemy_target'
		return false
	end
	local existing_burst_until = tonumber(input.skillchain_snapshot and input.skillchain_snapshot.magic_burst_expires_at) or 0
	if existing_burst_until > now then
		self.next_start_at = math.max(self.next_start_at, existing_burst_until)
		self.last_blocker = 'existing_magic_burst_window'
		return false
	end
	local charge = input.charge_snapshot or {}
	if charge.confidence ~= 'confirmed' then
		self.last_blocker = 'charge_confidence_unknown'
		return false
	end
	if (tonumber(charge.estimated_available) or 0) < 2 then
		self.last_blocker = 'insufficient_confirmed_charges'
		return false
	end
	local plans = skillchain.plans(config)
	if #plans == 0 then
		self.last_blocker = 'no_valid_skillchain_plan'
		return false
	end
	if not self:_start(plans[1], target, input.skillchain_snapshot, now) then
		return false
	end
	self:_advance(input)
	return true
end

function Runtime:next_step(now)
	local active = self.active
	if active == nil then
		return nil, self.last_blocker
	end
	if active.pending == true then
		return nil, 'skillchain_action_pending'
	end
	local action_type
	local action_name
	local target_id = 0
	local target_name = '<me>'
	local uses_charge = false
	local required_available_charges = 0

	if active.phase == 'ensure_dark_arts' then
		action_type = 'job_ability'
		action_name = 'Dark Arts'
	elseif active.phase == 'use_immanence_opener' then
		action_type = 'job_ability'
		action_name = 'Immanence'
		uses_charge = true
		required_available_charges = 2
	elseif active.phase == 'cast_opener' then
		action_type = 'spell'
		action_name = active.plan.opener
		target_id = active.target_id
		target_name = active.target_name
	elseif active.phase == 'use_immanence_closer' then
		action_type = 'job_ability'
		action_name = 'Immanence'
		uses_charge = true
		required_available_charges = 1
	elseif active.phase == 'cast_closer' then
		action_type = 'spell'
		action_name = active.plan.closer
		target_id = active.target_id
		target_name = active.target_name
	else
		return nil, 'skillchain_waiting_for_evidence'
	end

	return {
		provider = 'maintenance_sch',
		domain = 'maintenance',
		action_type = action_type,
		action_name = action_name,
		target_id = target_id,
		target_name = target_name,
		target_kind = action_type == 'spell' and 'enemy' or 'self',
		sequence_id = 'sch_skillchain:' .. tostring(active.generation),
		sequence_generation = active.generation,
		phase = active.phase,
		deadline = active.deadline,
		sch_skillchain = true,
		uses_reserved_charge = uses_charge,
		sch_skillchain_charge = uses_charge,
		required_available_charges = required_available_charges,
		spell_mp_multiplier = 1.0,
		duplicate_suppression_key = table.concat({
			'sch_skillchain', tostring(active.generation), tostring(active.phase),
		}, ':'),
		reason_code = 'sch_immanence_' .. tostring(active.phase),
	}, ''
end

function Runtime:note_dispatched(step, now)
	if type(step) ~= 'table' then
		return false, 'skillchain_step_required'
	end
	local active = self.active
	if active == nil then
		return false, 'no_active_skillchain'
	end
	if tonumber(step.sequence_generation) ~= active.generation
		or tostring(step.phase or '') ~= active.phase then
		return false, 'stale_skillchain_step'
	end
	active.pending = true
	active.phase_deadline = math.min(active.deadline, (tonumber(now) or 0) + EVIDENCE_TIMEOUT_S)
	if active.phase == 'ensure_dark_arts' then
		active.phase = 'wait_dark_arts'
	elseif active.phase == 'use_immanence_opener' then
		active.phase = 'wait_immanence_opener'
	elseif active.phase == 'cast_opener' then
		active.phase = 'wait_opener_result'
	elseif active.phase == 'use_immanence_closer' then
		active.phase = 'wait_immanence_closer'
	elseif active.phase == 'cast_closer' then
		active.phase = 'wait_result'
	else
		return false, 'unsupported_skillchain_dispatch_phase'
	end
	return true, ''
end

function Runtime:snapshot()
	return clone_value({
		generation = self.generation,
		active = self.active,
		next_start_at = self.next_start_at,
		last_result = self.last_result,
		last_blocker = self.last_blocker,
	})
end

function M.install_charge_bridge(runtime)
	if type(runtime) ~= 'table'
		or type(runtime.reserved_charge_step_ready) ~= 'function'
		or type(runtime.snapshot) ~= 'function' then
		error('Scholar skillchain charge bridge requires Scholar runtime')
	end
	if runtime._sch_skillchain_charge_bridge_installed == true then
		return
	end
	local original = runtime.reserved_charge_step_ready
	runtime.reserved_charge_step_ready = function(step)
		if type(step) == 'table' and step.sch_skillchain_charge == true then
			local snapshot = runtime.snapshot()
			if snapshot.active_sequence ~= nil or snapshot.pending ~= nil then
				return false, 'standard_sch_sequence_active'
			end
			local charge = snapshot.stratagem or {}
			if charge.confidence ~= 'confirmed' then
				return false, 'charge_confidence_unknown'
			end
			local required = tonumber(step.required_available_charges) or 1
			if (tonumber(charge.estimated_available) or 0) < required then
				return false, 'insufficient_confirmed_charges'
			end
			return true, ''
		end
		return original(step)
	end
	runtime._sch_skillchain_charge_bridge_installed = true
end

return M
