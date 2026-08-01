local scheduler = require('unified_scheduler')
local core = require('unified_combat_core')
local texts_ok, texts = pcall(require, 'texts')
local socket_ok, socket_mod = pcall(require, 'socket')
local socket_gettime = (socket_ok and type(socket_mod) == 'table' and type(socket_mod.gettime) == 'function') and socket_mod.gettime
	or nil
local time_source_error_reported = false

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
local sched_overlay_enemy = nil

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
	if sched_overlay_enemy then
		pcall(function()
			sched_overlay_enemy:hide()
		end)
	end
end

local function ensure_sched_overlay()
	if not texts_ok or not texts then
		return false
	end
	if sched_overlay_q and sched_overlay_r and sched_overlay_enemy then
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
	local enemy = {
		pos = { x = 760, y = 100 },
		bg = { alpha = 180, red = 14, green = 26, blue = 18 },
		flags = { right = false, bottom = false, bold = false, draggable = true },
		padding = 6,
		text = { font = 'Consolas', size = 10, alpha = 255, red = 170, green = 255, blue = 170, stroke = { width = 1, alpha = 180 } },
	}
	sched_overlay_enemy = texts.new('', enemy)
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
	local buff_up = type(snap.buff_up) == 'table' and snap.buff_up or {}
	local qlines = { ('Scheduler Queue (tick %s)'):format(tostring(snap.tick or 0)) }
	local domain_enabled_fn = rawget(_G, 'UC_DomainEnabled')
	local function domain_live(name)
		if type(domain_enabled_fn) == 'function' then
			return domain_enabled_fn(s, name) == true
		end
		return false
	end
	qlines[#qlines + 1] = ('EngineEnabled: %s'):format(tostring(bool_setting(s.engine_enabled, false)))
	qlines[#qlines + 1] = ('DomainCombatLive: %s'):format(tostring(domain_live('combat')))
	qlines[#qlines + 1] = ('DomainMovementLive: %s'):format(tostring(domain_live('movement')))
	qlines[#qlines + 1] = ('DomainDefensiveLive: %s'):format(tostring(domain_live('defensive')))
	qlines[#qlines + 1] = ('DomainMaintenanceLive: %s'):format(tostring(domain_live('maintenance')))
	qlines[#qlines + 1] = ('DomainFollowLive: %s'):format(tostring(domain_live('follow')))
	local pf_op = tostring(rawget(_G, 'UC_LAST_PARTY_FOLLOW_OP') or '')
	if pf_op ~= '' then
		qlines[#qlines + 1] = ('PartyFollow: %s'):format(pf_op)
	else
		qlines[#qlines + 1] = 'PartyFollow: (none)'
	end
	qlines[#qlines + 1] = ('FollowRunActive: %s'):format(tostring(rawget(_G, 'UC_PARTY_FOLLOW_RUN_ACTIVE') == true))
	qlines[#qlines + 1] = ('FollowNeedsCatchup: %s'):format(tostring(rawget(_G, 'UC_PARTY_FOLLOW_NEEDS_CATCHUP') == true))
	local p1_provider = tostring(rawget(_G, 'UC_SCHED_P1_SELECTED_PROVIDER') or '')
	if p1_provider == '' then
		p1_provider = '(none)'
	end
	qlines[#qlines + 1] = ('P1Provider: %s'):format(p1_provider)
	local p1_family = tostring(rawget(_G, 'UC_SCHED_P1_SELECTED_FAMILY') or '')
	if p1_family == '' then
		p1_family = '(none)'
	end
	qlines[#qlines + 1] = ('P1Family: %s'):format(p1_family)
	local p1_pending = tostring(rawget(_G, 'UC_SCHED_P1_PENDING_STATE') or '')
	if p1_pending == '' then
		p1_pending = '(none)'
	end
	qlines[#qlines + 1] = ('P1Pending: %s'):format(p1_pending)
	local sched_block = tostring(rawget(_G, 'UC_LAST_BLOCK_REASON') or '')
	if sched_block == '' then
		sched_block = '(none)'
	end
	qlines[#qlines + 1] = ('SchedBlock: %s'):format(sched_block)
	local last_sched_action = tostring(rawget(_G, 'UC_LAST_SCHED_ACTION') or '')
	if last_sched_action == '' then
		last_sched_action = '(none)'
	end
	qlines[#qlines + 1] = ('LastSchedAction: %s'):format(last_sched_action)
	local charm_sleeper_status = tostring(rawget(_G, 'UC_CHARM_SLEEPER_STATUS') or '')
	if charm_sleeper_status == '' then
		charm_sleeper_status = '(none)'
	end
	qlines[#qlines + 1] = ('CharmSleeper: %s'):format(charm_sleeper_status)
	local spacing_diag = tostring(rawget(_G, 'UC_SPACING_DIAG') or '')
	if spacing_diag ~= '' then
		qlines[#qlines + 1] = ('Spacing: %s'):format(spacing_diag)
	else
		qlines[#qlines + 1] = 'Spacing: (none)'
	end
	local move_mode = tostring(rawget(_G, 'UC_MOVEMENT_MODE') or '')
	if move_mode == '' then
		move_mode = '(none)'
	end
	qlines[#qlines + 1] = ('MoveMode: %s'):format(move_mode)
	local move_block = tostring(rawget(_G, 'UC_MOVEMENT_BLOCK_REASON') or '')
	if move_block == '' then
		move_block = '(none)'
	end
	qlines[#qlines + 1] = ('MoveBlock: %s'):format(move_block)
	local freeze_remaining = 0
	local prep_until = tonumber(rawget(_G, 'UC_MOVE_FREEZE_PREP_UNTIL')) or 0
	local now = (socket_gettime and socket_gettime()) or 0
	if prep_until > now then
		freeze_remaining = math.max(0, prep_until - now)
	end
	local ast = scheduler and type(scheduler.get_action_state) == 'function' and scheduler.get_action_state() or {}
	local send_kind = tostring((ast and ast.last_send_kind) or '')
	local cooldown_until = tonumber((ast and ast.cooldown_until) or 0) or 0
	if send_kind == 'spell' and cooldown_until > now then
		local cr = math.max(0, cooldown_until - now)
		if cr > freeze_remaining then
			freeze_remaining = cr
		end
	end
	qlines[#qlines + 1] = ('MoveFreeze: %.2fs'):format(freeze_remaining)
	for i = 1, 5 do
		if i <= #queued then
			qlines[#qlines + 1] = queued[i]
		elseif i == 1 then
			qlines[#qlines + 1] = '(none)'
		else
			qlines[#qlines + 1] = ' '
		end
	end
	qlines[#qlines + 1] = 'Buffs Up (addon view)'
	for i = 1, math.max(1, #buff_up) do
		if i <= #buff_up then
			qlines[#qlines + 1] = tostring(buff_up[i] or '')
		elseif i == 1 then
			qlines[#qlines + 1] = '(none)'
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
	-- Dynamic vertical stacking: keep rejected panel clear of queue panel even when
	-- queue grows with extra debug sections (e.g., buff state table).
	local rendered_q_lines = 1
	do
		local _, c = qtext:gsub('\n', '')
		rendered_q_lines = math.max(1, c + 1)
	end
	local line_height = 16
	local panel_gap = 14
	local ry = qy + (rendered_q_lines * line_height) + panel_gap
	sched_overlay_q:text(qtext)
	sched_overlay_q:show()
	sched_overlay_r:pos(qx, ry)
	sched_overlay_r:text(rtext)
	sched_overlay_r:show()

	local enemy_lines = { 'Enemy Effect Table (effectiveTargets)', '(unavailable)' }
	if scheduler and type(scheduler.get_enemy_effect_table_overlay) == 'function' then
		local esnap = scheduler.get_enemy_effect_table_overlay() or {}
		if type(esnap.lines) == 'table' and #esnap.lines > 0 then
			enemy_lines = esnap.lines
		end
	end
	local etext = table.concat(enemy_lines, '\n')
	if sched_overlay_enemy then
		sched_overlay_enemy:text(etext)
		sched_overlay_enemy:show()
	end
end

local function assert_core_no_job_branch()
	if core and type(core.assert_no_job_branch) == 'function' then
		return core.assert_no_job_branch()
	end
	return true
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
	if not socket_gettime then
		if not time_source_error_reported then
			time_source_error_reported = true
			if windower and windower.add_to_chat then
				windower.add_to_chat(123, 'UnifiedCombat: fatal engine timing error: socket.gettime unavailable.')
			end
		end
		engine.processing = false
		engine.running = false
		_G.UC_LAST_BLOCK_REASON = 'FATAL_TIME_SOURCE'
		return
	end
	local zu = rawget(_G, 'UC_ZONE_SUSPEND_UNTIL')
	local now = socket_gettime()
	if type(zu) == 'number' and now < zu then
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
	now = socket_gettime()
	local blocked, reason = scheduler.process_tick({
		now = now,
		next_defensive_at = engine.next_defensive_at,
		next_maintenance_at = engine.next_maintenance_at,
	})
	if now >= (tonumber(engine.next_defensive_at) or 0) then
		engine.next_defensive_at = now + 0.50
	end
	if now >= (tonumber(engine.next_maintenance_at) or 0) then
		engine.next_maintenance_at = now + 1.00
	end
	if now >= (tonumber(engine.next_overlay_at) or 0) then
		render_sched_overlay()
		engine.next_overlay_at = now + 0.50
	end
	if blocked then
		_G.UC_LAST_BLOCK_REASON = reason or 'BLOCK_DEFENSIVE'
	else
		_G.UC_LAST_BLOCK_REASON = ''
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

function engine.seed_cached_status_snapshot()
	return scheduler.seed_cached_status_snapshot()
end

return engine
