local scheduler = require('unified_scheduler')
local core = require('unified_combat_core')
local texts_ok, texts = pcall(require, 'texts')

local engine = {
	running = false,
	tick_interval = 0.20,
	processing = false,
	tick_seq = 0,
	job_guard_ok = nil,
	next_defensive_at = 0,
	next_maintenance_at = 0,
	next_overlay_at = 0,
}

local sched_overlay_q = nil
local sched_overlay_r = nil

local function bool_setting(v, default_value)
	if v == nil then
		return default_value == true
	end
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function get_settings()
	return rawget(_G, 'UC_SETTINGS') or {}
end

local function hide_sched_overlay()
	if sched_overlay_q then
		pcall(function()
			sched_overlay_q:hide()
		end)
	end
	if sched_overlay_r then
		pcall(function()
			sched_overlay_r:hide()
		end)
	end
end

local function ensure_sched_overlay()
	if not texts_ok or not texts then
		return false
	end
	if sched_overlay_q and sched_overlay_r then
		return true
	end
	local base = {
		pos = { x = 100, y = 100 },
		bg = { alpha = 180, red = 20, green = 20, blue = 20 },
		flags = { right = false, bottom = false, bold = false, draggable = true },
		padding = 6,
		text = { font = 'Consolas', size = 10, alpha = 255, red = 255, green = 255, blue = 255, stroke = { width = 1, alpha = 180 } },
	}
	local red = {
		pos = { x = 100, y = 220 },
		bg = { alpha = 180, red = 20, green = 20, blue = 20 },
		flags = { right = false, bottom = false, bold = false, draggable = true },
		padding = 6,
		text = { font = 'Consolas', size = 10, alpha = 255, red = 255, green = 120, blue = 120, stroke = { width = 1, alpha = 180 } },
	}
	sched_overlay_q = texts.new('', base)
	sched_overlay_r = texts.new('', red)
	return true
end

local function render_sched_overlay()
	local s = get_settings()
	if not bool_setting(s.debug, false) then
		hide_sched_overlay()
		return
	end
	if not ensure_sched_overlay() then
		return
	end
	local snap = {}
	if scheduler and type(scheduler.get_debug_overlay) == 'function' then
		snap = scheduler.get_debug_overlay() or {}
	end
	local queued = type(snap.queued) == 'table' and snap.queued or {}
	local rejected = type(snap.rejected) == 'table' and snap.rejected or {}
	local qlines = { ('Scheduler Queue (tick %s)'):format(tostring(snap.tick or 0)) }
	local pf_op = tostring(rawget(_G, 'UC_LAST_PARTY_FOLLOW_OP') or '')
	if pf_op ~= '' then
		qlines[#qlines + 1] = ('PartyFollow: %s'):format(pf_op)
	else
		qlines[#qlines + 1] = 'PartyFollow: (none)'
	end
	local spacing_diag = tostring(rawget(_G, 'UC_SPACING_DIAG') or '')
	if spacing_diag ~= '' then
		qlines[#qlines + 1] = ('Spacing: %s'):format(spacing_diag)
	else
		qlines[#qlines + 1] = 'Spacing: (none)'
	end
	for i = 1, 5 do
		if i <= #queued then
			qlines[#qlines + 1] = queued[i]
		elseif i == 1 then
			qlines[#qlines + 1] = '(none)'
		else
			qlines[#qlines + 1] = ' '
		end
	end
	local rlines = { 'Scheduler Discarded (last 5)' }
	for i = 1, 5 do
		if i <= #rejected then
			rlines[#rlines + 1] = rejected[i]
		elseif i == 1 then
			rlines[#rlines + 1] = '(none)'
		else
			rlines[#rlines + 1] = ' '
		end
	end
	local qtext = table.concat(qlines, '\n')
	local rtext = table.concat(rlines, '\n')
	local qx, qy = 100, 100
	if sched_overlay_q and sched_overlay_q.pos then
		local okx, ox = pcall(function()
			return sched_overlay_q:pos_x()
		end)
		local oky, oy = pcall(function()
			return sched_overlay_q:pos_y()
		end)
		if okx and tonumber(ox) then
			qx = tonumber(ox)
		end
		if oky and tonumber(oy) then
			qy = tonumber(oy)
		end
	end
	local ry = qy + (#qlines * 14) + 8
	sched_overlay_q:text(qtext)
	sched_overlay_q:show()
	sched_overlay_r:pos(qx, ry)
	sched_overlay_r:text(rtext)
	sched_overlay_r:show()
end

local function assert_core_no_job_branch()
	if core and type(core.assert_no_job_branch) == 'function' then
		return core.assert_no_job_branch()
	end
	return true
end

local function do_active_combat_tick()
	if type(_G.UC_CoreCombatTickOnce) == 'function' then
		_G.UC_CoreCombatTickOnce()
	else
		_G.UC_LAST_BLOCK_REASON = 'CORE_TICK_MISSING'
	end
end

local function truthy(v)
	if v == true or v == 1 then
		return true
	end
	if type(v) == 'string' then
		local s = v:lower()
		return s == 'true' or s == 'on' or s == '1' or s == 'yes'
	end
	return false
end

local function scheduler_owns_all_domains()
	local s = rawget(_G, 'UC_SETTINGS') or {}
	return truthy(s.scheduler_dark_launch_combat)
		and truthy(s.scheduler_dark_launch_defensive)
		and truthy(s.scheduler_dark_launch_movement)
		and truthy(s.scheduler_dark_launch_maintenance)
end

local function domain_enabled(v)
	return truthy(v)
end

local function scheduler_owns_any_domain()
	local s = rawget(_G, 'UC_SETTINGS') or {}
	return domain_enabled(s.scheduler_dark_launch_combat)
		or domain_enabled(s.scheduler_dark_launch_defensive)
		or domain_enabled(s.scheduler_dark_launch_movement)
		or domain_enabled(s.scheduler_dark_launch_maintenance)
end

local function core_tick_allowed_for_domain(s)
	-- Domain short-circuiting:
	-- if scheduler owns combat, avoid running heavy core combat loop;
	-- keep core as fallback only when combat is not scheduler-owned.
	return not domain_enabled(s and s.scheduler_dark_launch_combat)
end

local function tick()
	if engine.processing then
		return
	end
	engine.processing = true
	if not engine.running or not _G.Start_Engine then
		engine.running = false
		hide_sched_overlay()
		engine.processing = false
		return
	end
	local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	if type(zu) == 'number' and os.clock() < zu then
		engine.tick_seq = engine.tick_seq + 1
		_G.UC_SCHED_TICK_SEQ = engine.tick_seq
		_G.UC_LAST_BLOCK_REASON = 'ZONE_SUSPEND'
		engine.processing = false
		if engine.running and _G.Start_Engine then
			coroutine.schedule(tick, engine.tick_interval)
		end
		return
	end
	engine.tick_seq = engine.tick_seq + 1
	_G.UC_SCHED_TICK_SEQ = engine.tick_seq
	local s = get_settings()
	local now = os.clock()
	local blocked, reason = scheduler.process_tick({
		now = now,
		next_defensive_at = engine.next_defensive_at,
		next_maintenance_at = engine.next_maintenance_at,
	})
	engine.next_defensive_at = now + 0.50
	engine.next_maintenance_at = now + 1.00
	if now >= (tonumber(engine.next_overlay_at) or 0) then
		render_sched_overlay()
		engine.next_overlay_at = now + 0.50
	end
	if blocked then
		_G.UC_LAST_BLOCK_REASON = reason or 'BLOCK_DEFENSIVE'
	else
		_G.UC_LAST_BLOCK_REASON = ''
		if core_tick_allowed_for_domain(s) and not scheduler_owns_all_domains() then
			do_active_combat_tick()
		end
	end
	engine.processing = false
	if engine.running and _G.Start_Engine then
		coroutine.schedule(tick, engine.tick_interval)
	end
end

function engine.start()
	engine.job_guard_ok = assert_core_no_job_branch()
	if not engine.job_guard_ok then
		_G.UC_LAST_BLOCK_REASON = 'CORE_JOB_BRANCH_GUARD'
		windower.add_to_chat(123, 'UnifiedCombat: core guard failed (job branch detected in core tick path).')
		return
	end
	if engine.running then
		return
	end
	_G.UC_USE_UNIFIED_ENGINE = true
	engine.running = true
	tick()
end

function engine.stop()
	engine.running = false
	engine.processing = false
	hide_sched_overlay()
end

return engine
