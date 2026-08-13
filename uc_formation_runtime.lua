local M = {}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(value, name)
	if type(value) ~= 'function' then
		error(name .. ' must be a function')
	end
	return value
end

local function require_reason(value, name)
	if type(value) ~= 'string' or value == '' then
		error(name .. ' must be a non-empty string')
	end
	return value
end

local function copy_table(value)
	if type(value) ~= 'table' then
		return value
	end
	local out = {}
	for key, item in pairs(value) do
		out[key] = copy_table(item)
	end
	return out
end

function M.build(opts)
	opts = require_table(opts, 'uc_formation_runtime opts')
	local get_config = require_function(opts.get_config, 'opts.get_config')
	local encounter_runtime = require_table(opts.encounter_runtime, 'opts.encounter_runtime')
	require_function(encounter_runtime.snapshot, 'opts.encounter_runtime.snapshot')
	local encounter_registry = require_table(opts.encounter_registry, 'opts.encounter_registry')
	require_function(encounter_registry.get, 'opts.encounter_registry.get')
	local lilith_runtime = require_table(opts.lilith_runtime, 'opts.lilith_runtime')
	require_function(lilith_runtime.observe, 'opts.lilith_runtime.observe')
	require_function(lilith_runtime.run_tick, 'opts.lilith_runtime.run_tick')
	require_function(lilith_runtime.stop, 'opts.lilith_runtime.stop')
	require_function(lilith_runtime.reset, 'opts.lilith_runtime.reset')
	local generic_runtime = require_table(opts.generic_runtime, 'opts.generic_runtime')
	require_function(generic_runtime.run_tick, 'opts.generic_runtime.run_tick')
	require_function(generic_runtime.stop, 'opts.generic_runtime.stop')
	require_function(generic_runtime.reset, 'opts.generic_runtime.reset')
	require_function(generic_runtime.status, 'opts.generic_runtime.status')
	local mock_runtime = require_table(opts.mock_runtime, 'opts.mock_runtime')
	require_function(mock_runtime.observe, 'opts.mock_runtime.observe')
	require_function(mock_runtime.reset, 'opts.mock_runtime.reset')
	local get_me = require_function(opts.get_me, 'opts.get_me')
	local get_party_members = require_function(opts.get_party_members, 'opts.get_party_members')
	local publish_status = require_function(opts.publish_status, 'opts.publish_status')

	local selected_kind = 'disabled'
	local selected_source = 'disabled'
	local status = {
		enabled = false,
		kind = 'disabled',
		phase = 'disabled',
		reason = 'FORMATION_DISABLED',
	}
	local runtime = {}

	local function publish(value)
		status = copy_table(require_table(value, 'formation runtime status'))
		publish_status(copy_table(status))
	end

	local function stop_kind(kind, reason)
		if kind == 'lilith' then
			return lilith_runtime.stop(reason)
		end
		if kind == 'generic' then
			return generic_runtime.stop(reason)
		end
		return false, 'FORMATION_NOT_MOVING'
	end

	local function transition_to(kind)
		if kind == selected_kind then
			return
		end
		stop_kind(selected_kind, 'FORMATION_SELECTION_CHANGED')
		selected_kind = kind
	end

	local function transition_source(source)
		if source == selected_source then
			return
		end
		if selected_source == 'mock' then
			mock_runtime.reset('FORMATION_MOCK_SOURCE_CHANGED')
		end
		selected_source = source
	end

	local function selected_config()
		local config = get_config()
		if config == nil then
			return { enabled = false }
		end
		require_table(config, 'config.movement.formation')
		if type(config.enabled) ~= 'boolean' then
			error('config.movement.formation.enabled must be boolean')
		end
		return config
	end

	local function selection_kind(config)
		if config.enabled ~= true then
			return 'disabled'
		end
		local encounter_id = tostring(config.encounter or '')
		if encounter_id == 'lilith_easy' then
			return 'lilith'
		end
		if encounter_registry.get(encounter_id) ~= nil then
			return 'generic'
		end
		error('enabled formation has unsupported encounter: ' .. encounter_id)
	end

	function runtime.observe(now)
		if tonumber(now) == nil then
			error('uc_formation_runtime.observe requires now')
		end
		local config = selected_config()
		local kind = selection_kind(config)
		transition_to(kind)
		if kind == 'disabled' then
			transition_source('disabled')
			publish({
				enabled = false,
				kind = kind,
				phase = 'disabled',
				reason = 'FORMATION_DISABLED',
			})
			return { kind = kind, config = config }
		end
		if kind == 'lilith' then
			transition_source('lilith')
			return {
				kind = kind,
				config = config,
				observation = lilith_runtime.observe(now),
			}
		end

		local mock_config = config.mock
		if mock_config ~= nil and type(mock_config) ~= 'table' then
			error('config.movement.formation.mock must be a table')
		end
		if mock_config ~= nil and type(mock_config.enabled) ~= 'boolean' then
			error('config.movement.formation.mock.enabled must be boolean')
		end
		local source = mock_config ~= nil and mock_config.enabled == true and 'mock' or 'encounter'
		transition_source(source)
		local snapshot
		if source == 'mock' then
			snapshot = mock_runtime.observe(now, {
				enabled = true,
				encounter = config.encounter,
				mob_name = mock_config.mob_name,
			})
		else
			snapshot = encounter_runtime.snapshot()
		end
		require_table(snapshot, 'uc_encounter_runtime.snapshot result')
		publish({
			enabled = true,
			kind = kind,
			source = source,
			mock_mob_name = source == 'mock' and tostring(mock_config.mob_name) or '',
			encounter = config.encounter,
			phase = tostring(snapshot.phase or ''),
			reason = tostring(snapshot.error or ''),
			boss_id = snapshot.boss and snapshot.boss.id or nil,
			origin = snapshot.origin,
			active_hazard_count = 0,
		})
		return {
			kind = kind,
			config = config,
			snapshot = snapshot,
			source = source,
		}
	end

	local function stop_generic_for(reason, owns)
		local stopped = generic_runtime.stop(reason)
		return stopped, reason, stopped or owns == true
	end

	local function run_generic(observation)
		local config = require_table(observation.config, 'generic formation observation.config')
		local snapshot = require_table(observation.snapshot, 'generic formation observation.snapshot')
		if snapshot.enabled ~= true or tostring(snapshot.configured_id or '') ~= tostring(config.encounter) then
			return stop_generic_for('FORMATION_ENCOUNTER_CONFIG_MISMATCH', true)
		end
		local boss = snapshot.boss
		if tostring(snapshot.resolved_id or '') == '' or type(boss) ~= 'table' then
			return stop_generic_for(tostring(snapshot.error or 'FORMATION_AWAITING_BOSS'), false)
		end
		if tostring(snapshot.resolved_id) ~= tostring(config.encounter) then
			return stop_generic_for('FORMATION_ENCOUNTER_ID_MISMATCH', true)
		end
		local boss_hpp = tonumber(boss.hpp)
		local boss_status = tonumber(boss.status)
		if boss_hpp == nil or boss_status == nil then
			return stop_generic_for('FORMATION_BOSS_STATE_UNAVAILABLE', true)
		end
		if boss_hpp <= 0 then
			return stop_generic_for('FORMATION_ENCOUNTER_COMPLETE', false)
		end
		if boss_status == 0 then
			return stop_generic_for('FORMATION_WAITING_FOR_ENGAGE', false)
		end

		local me = get_me()
		if type(me) ~= 'table' or tonumber(me.x) == nil or tonumber(me.y) == nil then
			return stop_generic_for('FORMATION_PLAYER_POSITION_UNAVAILABLE', true)
		end
		local members, members_reason = get_party_members()
		if type(members) ~= 'table' then
			return stop_generic_for(tostring(members_reason), true)
		end
		local generic_status = generic_runtime.status()
		local acted, reason, owns = generic_runtime.run_tick({
			config = config,
			me = me,
			boss = boss,
			encounter_origin = snapshot.origin,
			party_members = members,
			-- Dhartok hazard candidates remain telemetry-only until the field gate is complete.
			encounter_hazards = {},
			was_moving = generic_status.moving == true,
		})
		local runtime_status = generic_runtime.status()
		publish({
			enabled = true,
			kind = 'generic',
			source = tostring(observation.source or 'encounter'),
			mock_mob_name = observation.source == 'mock'
				and tostring(config.mock and config.mock.mob_name or '') or '',
			encounter = config.encounter,
			phase = tostring(snapshot.phase or ''),
			reason = reason,
			boss_id = boss.id,
			origin = snapshot.origin,
			active_hazard_count = 0,
			proposal = runtime_status.proposal,
		})
		return acted, reason, owns
	end

	function runtime.run_tick(observation)
		observation = require_table(observation, 'formation runtime observation')
		local kind = tostring(observation.kind or '')
		if kind ~= selected_kind then
			error('formation runtime observation selection is stale')
		end
		if kind == 'disabled' then
			return false, 'FORMATION_DISABLED', false
		end
		if kind == 'lilith' then
			return lilith_runtime.run_tick(observation.observation)
		end
		if kind == 'generic' then
			return run_generic(observation)
		end
		error('formation runtime observation has unsupported kind: ' .. kind)
	end

	function runtime.stop(reason)
		reason = require_reason(reason, 'uc_formation_runtime.stop reason')
		return stop_kind(selected_kind, reason)
	end

	function runtime.reset(reason)
		reason = require_reason(reason, 'uc_formation_runtime.reset reason')
		stop_kind(selected_kind, reason)
		lilith_runtime.reset(reason)
		generic_runtime.reset(reason)
		mock_runtime.reset(reason)
		selected_kind = 'disabled'
		selected_source = 'disabled'
		publish({
			enabled = false,
			kind = 'disabled',
			phase = 'reset',
			reason = reason,
		})
	end

	function runtime.status()
		return copy_table(status)
	end

	return runtime
end

local function default_party_members()
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

local default_runtime = nil

local function get_default_runtime()
	if default_runtime == nil then
		if type(rawget(_G, 'windower')) ~= 'table' or type(windower.ffxi) ~= 'table' then
			error('default formation runtime requires windower.ffxi')
		end
		default_runtime = M.build({
			get_config = function()
				return require('uc_active_config').get_path('config.movement.formation')
			end,
			encounter_runtime = require('uc_encounter_runtime'),
			encounter_registry = require('uc_encounter_registry'),
			lilith_runtime = require('uc_lilith_easy_formation_runtime'),
			generic_runtime = require('uc_generic_formation_runtime'),
			mock_runtime = require('uc_formation_mock_state'),
			get_me = function()
				return windower.ffxi.get_mob_by_target('me')
			end,
			get_party_members = default_party_members,
			publish_status = function(value)
				_G.UC_FORMATION_STATUS = value
			end,
		})
	end
	return default_runtime
end

function M.observe(now)
	return get_default_runtime().observe(now)
end

function M.run_tick(observation)
	return get_default_runtime().run_tick(observation)
end

function M.stop(reason)
	return get_default_runtime().stop(reason)
end

function M.reset(reason)
	return get_default_runtime().reset(reason)
end

function M.status()
	return get_default_runtime().status()
end

return M
