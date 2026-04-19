local scheduler = require('unified_scheduler')
local core = require('unified_combat_core')

local engine = {
	running = false,
	tick_interval = 0.25,
	processing = false,
	tick_seq = 0,
	job_guard_ok = nil,
}

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
end

return engine
