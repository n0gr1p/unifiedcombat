local M = {}

M.HOLY_WATER_NAME = 'Holy Water'
M.INVENTORY_BAG_ID = 0
M.ITEM_REUSE_S = 1.20
M.STAGE_TIMEOUT_S = 1.00

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function require_function(deps, name)
	local fn = deps[name]
	if type(fn) ~= 'function' then
		error('uc_doom_water requires function dependency: ' .. tostring(name))
	end
	return fn
end

local function log(deps, message)
	if type(deps.log) == 'function' then
		deps.log(message)
	end
end

function M.new_state()
	return {
		phase = 'idle',
		requested_at = 0,
		source_bag = 0,
		source_slot = 0,
		item_id = 0,
		last_item_at = -math.huge,
		last_reason = 'init',
	}
end

function M.reset(state, reason)
	state = require_table(state, 'doom water state')
	state.phase = 'idle'
	state.requested_at = 0
	state.source_bag = 0
	state.source_slot = 0
	state.item_id = 0
	state.last_reason = tostring(reason or 'reset')
end

local function holy_water_item_id(deps)
	local configured = tonumber(deps.holy_water_item_id)
	if configured and configured > 0 then
		return configured
	end
	for id, item in pairs(type(deps.item_resources) == 'table' and deps.item_resources or {}) do
		if type(item) == 'table'
			and tostring(item.en or ''):lower() == M.HOLY_WATER_NAME:lower() then
			return tonumber(item.id) or tonumber(id) or 0
		end
	end
	return 0
end

local function bag_api_name(bag)
	return tostring(type(bag) == 'table' and bag.api or ''):lower()
end

local function inventory_item_count(deps, item_id)
	local get_items = require_function(deps, 'get_items')
	local rows = get_items(M.INVENTORY_BAG_ID)
	if type(rows) ~= 'table' then
		return 0
	end
	local total = 0
	for _, row in ipairs(rows) do
		if tonumber(row and row.id) == item_id then
			total = total + math.max(0, tonumber(row.count) or 0)
		end
	end
	return total
end

local function inventory_has_space(deps)
	local get_bag_info = require_function(deps, 'get_bag_info')
	local info = get_bag_info(M.INVENTORY_BAG_ID)
	if type(info) ~= 'table' or info.enabled == false then
		return false
	end
	local max_count = tonumber(info.max) or 0
	local used_count = tonumber(info.count) or 0
	return max_count > used_count
end

local function accessible_source(deps, item_id)
	local get_items = require_function(deps, 'get_items')
	local get_bag_info = require_function(deps, 'get_bag_info')
	for key, bag in pairs(type(deps.bag_resources) == 'table' and deps.bag_resources or {}) do
		if type(bag) == 'table' then
			local bag_id = tonumber(bag.id) or tonumber(key) or -1
			local api = bag_api_name(bag)
			if bag_id >= 0
				and bag_id ~= M.INVENTORY_BAG_ID
				and api ~= 'inventory'
				and api ~= 'temporary' then
				local info = get_bag_info(bag_id)
				if type(info) == 'table' and info.enabled == true then
					local rows = get_items(bag_id)
					if type(rows) == 'table' then
						for _, row in ipairs(rows) do
							if tonumber(row and row.id) == item_id and (tonumber(row.count) or 0) > 0 then
								return {
									bag = bag_id,
									slot = tonumber(row.slot) or tonumber(row.index) or 0,
									count = tonumber(row.count) or 0,
									api = api,
								}
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local function active_and_doomed(deps)
	return require_function(deps, 'enabled')() == true
		and require_function(deps, 'player_has_doom')() == true
end

local function reserve_lane(deps, reason)
	local fn = require_function(deps, 'reserve_lane')
	fn(reason)
end

local function use_ready_water(state, deps, now_value, confirmed_count)
	local ready = tonumber(confirmed_count) or 0
	if ready <= 0 then
		ready = inventory_item_count(deps, state.item_id)
	end
	if ready <= 0 then
		M.reset(state, 'READY_ITEM_MISSING')
		log(deps, 'DOOM_WATER_UNAVAILABLE reason=READY_ITEM_MISSING fallback=STATUS_REMOVAL')
		return false, 'DOOM_WATER_READY_ITEM_MISSING'
	end
	reserve_lane(deps, 'DOOM_HOLY_WATER_READY')
	if (now_value - (tonumber(state.last_item_at) or -math.huge)) < M.ITEM_REUSE_S then
		state.last_reason = 'ITEM_REUSE_HOLD'
		return true, 'BLOCK_DOOM_WATER_HOLD'
	end
	local dispatched = require_function(deps, 'use_holy_water')()
	if dispatched == true then
		state.last_item_at = now_value
		state.phase = 'cooldown'
		state.last_reason = 'ITEM_DISPATCHED'
		log(deps, ('DOOM_WATER_DISPATCH inventory_count=%d'):format(ready))
		return true, 'BLOCK_DOOM_WATER'
	end
	M.reset(state, 'ITEM_DISPATCH_FAILED')
	log(deps, 'DOOM_WATER_UNAVAILABLE reason=ITEM_DISPATCH_FAILED fallback=STATUS_REMOVAL')
	return false, 'DOOM_WATER_ITEM_DISPATCH_FAILED'
end

function M.step(state, deps)
	state = require_table(state, 'doom water state')
	deps = require_table(deps, 'doom water dependencies')
	local now_value = require_function(deps, 'now')()

	if not active_and_doomed(deps) then
		if state.phase ~= 'idle' then
			M.reset(state, 'INACTIVE_OR_DOOM_GONE')
		end
		return false, 'DOOM_WATER_INACTIVE'
	end

	local item_id = holy_water_item_id(deps)
	if item_id <= 0 then
		M.reset(state, 'ITEM_RESOURCE_MISSING')
		log(deps, 'DOOM_WATER_UNAVAILABLE reason=ITEM_RESOURCE_MISSING fallback=STATUS_REMOVAL')
		return false, 'DOOM_WATER_ITEM_RESOURCE_MISSING'
	end
	state.item_id = item_id

	if state.phase == 'staging' then
		if (now_value - (tonumber(state.requested_at) or 0)) >= M.STAGE_TIMEOUT_S then
			local bag = tonumber(state.source_bag) or 0
			M.reset(state, 'STAGE_TIMEOUT')
			log(deps, ('DOOM_WATER_STAGE_TIMEOUT source_bag=%d fallback=STATUS_REMOVAL'):format(bag))
			return false, 'DOOM_WATER_STAGE_TIMEOUT'
		end
		reserve_lane(deps, 'DOOM_HOLY_WATER_STAGING')
		state.last_reason = 'STAGING'
		return true, 'BLOCK_DOOM_WATER_STAGING'
	end

	if state.phase == 'ready' then
		return use_ready_water(state, deps, now_value)
	end

	if state.phase == 'cooldown' then
		if (now_value - (tonumber(state.last_item_at) or -math.huge)) < M.ITEM_REUSE_S then
			reserve_lane(deps, 'DOOM_HOLY_WATER_REUSE')
			state.last_reason = 'ITEM_REUSE_HOLD'
			return true, 'BLOCK_DOOM_WATER_HOLD'
		end
		state.phase = 'idle'
		state.last_reason = 'REUSE_READY'
	end

	local inventory_count = inventory_item_count(deps, item_id)
	if inventory_count > 0 then
		state.phase = 'ready'
		state.last_reason = 'INVENTORY_READY'
		log(deps, ('DOOM_WATER_READY inventory_count=%d'):format(inventory_count))
		return use_ready_water(state, deps, now_value)
	end

	local source = accessible_source(deps, item_id)
	if source == nil then
		M.reset(state, 'NO_ACCESSIBLE_ITEM')
		log(deps, 'DOOM_WATER_UNAVAILABLE reason=NO_ACCESSIBLE_ITEM fallback=STATUS_REMOVAL')
		return false, 'DOOM_WATER_NO_ACCESSIBLE_ITEM'
	end

	if not inventory_has_space(deps) then
		M.reset(state, 'INVENTORY_FULL')
		log(deps, ('DOOM_WATER_UNAVAILABLE reason=INVENTORY_FULL source_bag=%d fallback=STATUS_REMOVAL'):format(source.bag))
		return false, 'DOOM_WATER_INVENTORY_FULL'
	end

	if source.slot <= 0 then
		M.reset(state, 'SOURCE_SLOT_INVALID')
		log(deps, ('DOOM_WATER_UNAVAILABLE reason=SOURCE_SLOT_INVALID source_bag=%d fallback=STATUS_REMOVAL'):format(source.bag))
		return false, 'DOOM_WATER_SOURCE_SLOT_INVALID'
	end

	local ok, result = pcall(require_function(deps, 'get_item'), source.bag, source.slot, 1)
	if not ok or result == false then
		M.reset(state, 'STAGE_REQUEST_FAILED')
		log(deps, ('DOOM_WATER_UNAVAILABLE reason=STAGE_REQUEST_FAILED source_bag=%d fallback=STATUS_REMOVAL'):format(source.bag))
		return false, 'DOOM_WATER_STAGE_REQUEST_FAILED'
	end

	reserve_lane(deps, 'DOOM_HOLY_WATER_STAGING')
	state.phase = 'staging'
	state.requested_at = now_value
	state.source_bag = source.bag
	state.source_slot = source.slot
	state.item_id = item_id
	state.last_reason = 'STAGE_REQUESTED'
	log(deps, ('DOOM_WATER_STAGE source_bag=%d source_slot=%d count=1'):format(source.bag, source.slot))
	return true, 'BLOCK_DOOM_WATER_STAGING'
end

function M.on_add_item(state, bag, index, item_id, count, deps)
	state = require_table(state, 'doom water state')
	deps = require_table(deps, 'doom water dependencies')
	if state.phase ~= 'staging' then
		return false, 'NOT_STAGING'
	end
	if tonumber(bag) ~= M.INVENTORY_BAG_ID or tonumber(item_id) ~= tonumber(state.item_id) then
		return false, 'UNRELATED_ITEM'
	end
	if not active_and_doomed(deps) then
		M.reset(state, 'DOOM_GONE_BEFORE_STAGE_CONFIRM')
		return false, 'DOOM_GONE_BEFORE_STAGE_CONFIRM'
	end

	state.phase = 'ready'
	state.last_reason = 'STAGE_CONFIRMED'
	log(deps, ('DOOM_WATER_STAGE_CONFIRMED inventory_slot=%d count=%d'):format(
		tonumber(index) or 0,
		tonumber(count) or 0
	))
	return use_ready_water(state, deps, require_function(deps, 'now')(), math.max(1, tonumber(count) or 0))
end

function M.status(state)
	state = require_table(state, 'doom water state')
	return {
		phase = tostring(state.phase or 'idle'),
		requested_at = tonumber(state.requested_at) or 0,
		source_bag = tonumber(state.source_bag) or 0,
		source_slot = tonumber(state.source_slot) or 0,
		item_id = tonumber(state.item_id) or 0,
		last_item_at = tonumber(state.last_item_at) or -math.huge,
		last_reason = tostring(state.last_reason or ''),
	}
end

M._test = {
	holy_water_item_id = holy_water_item_id,
	inventory_item_count = inventory_item_count,
	inventory_has_space = inventory_has_space,
	accessible_source = accessible_source,
}

return M
