local scheduler = require('unified_scheduler')

local engine = {
	running = false,
	tick_interval = 0.25,
	processing = false,
	tick_seq = 0,
}

local function do_active_combat_tick()
	if _G.UC_ENGINE == 'melee' then
		if type(_G.uc_melee_combat_tick_once) == 'function' then
			_G.uc_melee_combat_tick_once()
		end
	elseif _G.UC_ENGINE == 'dd2' then
		local dd2 = rawget(_G, 'UC_DD2')
		if type(dd2) == 'table' and type(dd2.combat_tick) == 'function' then
			dd2.combat_tick()
		end
	end
end

local function tick()
	if engine.processing then
		return
	end
	engine.processing = true
	if not engine.running or not _G.Start_Engine then
		engine.running = false
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
	local blocked, reason = scheduler.process_tick()
	if blocked then
		_G.UC_LAST_BLOCK_REASON = reason or 'BLOCK_DEFENSIVE'
	else
		_G.UC_LAST_BLOCK_REASON = ''
		do_active_combat_tick()
	end
	engine.processing = false
	if engine.running and _G.Start_Engine then
		coroutine.schedule(tick, engine.tick_interval)
	end
end

function engine.start()
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
end

return engine
