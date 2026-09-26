local M = {}

M.mechanics = {
	curaga = {
		target_range = 20.0,
		radius = 15.0,
		max_coordinate_age_s = 1.0,
	},
	divine_waltz = {
		target_range = 10.6,
		radius = 9.9,
		max_coordinate_age_s = 1.0,
	},
	curing_waltz_ranges = {
		['Curing Waltz'] = 20.6,
		['Curing Waltz II'] = 20.6,
		['Curing Waltz III'] = 20.7,
		['Curing Waltz IV'] = 20.7,
		['Curing Waltz V'] = 20.7,
	},
	healing_waltz_range = 24.9,
}

local unsupported_healing_waltz_keys = {
	amnesia = true,
	doom = true,
	elegy = true,
	helix = true,
	kaustra = true,
	lullaby = true,
	mute = true,
	nocturne = true,
	petrification = true,
	requiem = true,
	stun = true,
	terror = true,
}

local supported_healing_waltz_spells = {
	Blindna = true,
	Cursna = true,
	Erase = true,
	Paralyna = true,
	Poisona = true,
	Silena = true,
	Viruna = true,
}

local function require_table(value, name)
	if type(value) ~= 'table' then
		error(name .. ' must be a table')
	end
	return value
end

local function horizontal_distance(left, right)
	if type(left.x) ~= 'number' or type(left.y) ~= 'number'
		or type(right.x) ~= 'number' or type(right.y) ~= 'number' then
		return nil
	end
	local dx = left.x - right.x
	local dy = left.y - right.y
	return math.sqrt((dx * dx) + (dy * dy))
end

function M.horizontal_distance(left, right)
	return horizontal_distance(require_table(left, 'left member'), require_table(right, 'right member'))
end

local function candidate_better(candidate, best)
	if best == nil then
		return true
	end
	if candidate.coverage_count ~= best.coverage_count then
		return candidate.coverage_count > best.coverage_count
	end
	if candidate.aggregate_missing_hp ~= best.aggregate_missing_hp then
		return candidate.aggregate_missing_hp > best.aggregate_missing_hp
	end
	if candidate.lowest_covered_hpp ~= best.lowest_covered_hpp then
		return candidate.lowest_covered_hpp < best.lowest_covered_hpp
	end
	if candidate.member_priority ~= best.member_priority then
		return candidate.member_priority < best.member_priority
	end
	if candidate.party_order ~= best.party_order then
		return candidate.party_order < best.party_order
	end
	return candidate.anchor_id < best.anchor_id
end

function M.plan_aoe(input)
	input = require_table(input, 'defensive AoE input')
	local members = require_table(input.members, 'defensive AoE members')
	local injured_ids = require_table(input.injured_recipient_ids, 'defensive AoE injured ids')
	local mechanics = require_table(input.mechanics, 'defensive AoE mechanics')
	local minimum_targets = tonumber(input.minimum_targets)
	if minimum_targets == nil or minimum_targets < 2 or minimum_targets > 6 or minimum_targets % 1 ~= 0 then
		error('defensive AoE minimum_targets must be an integer from 2 through 6')
	end
	local target_range = tonumber(mechanics.target_range)
	local radius = tonumber(mechanics.radius)
	local max_coordinate_age_s = tonumber(mechanics.max_coordinate_age_s)
	local now = tonumber(input.now)
	if target_range == nil or target_range <= 0 or radius == nil or radius <= 0
		or max_coordinate_age_s == nil or max_coordinate_age_s < 0 or now == nil or now < 0 then
		error('defensive AoE mechanics require positive ranges, non-negative coordinate age, and current time')
	end

	local by_id = {}
	local party_order = {}
	local self_member = nil
	for index = 1, #members do
		local member = require_table(members[index], 'defensive AoE member')
		local id = tonumber(member.id)
		if id == nil or id <= 0 or id % 1 ~= 0 or by_id[id] ~= nil then
			error('defensive AoE members require unique positive integer ids')
		end
		by_id[id] = member
		party_order[id] = index
		if member.is_self == true then
			if self_member ~= nil then
				error('defensive AoE members contain more than one self member')
			end
			self_member = member
		end
	end
	if self_member == nil then
		return { state = 'blocked', blocker = 'AOE_GEOMETRY_UNKNOWN' }
	end

	local injured = {}
	for index = 1, #injured_ids do
		local id = tonumber(injured_ids[index])
		local member = id and by_id[id] or nil
		if member == nil or injured[id] ~= nil then
			error('defensive AoE injured ids must be unique party member ids')
		end
		injured[id] = member
	end

	for index = 1, #members do
		local member = members[index]
		local observed_at = tonumber(member.coordinate_observed_at)
		if horizontal_distance(self_member, member) == nil or observed_at == nil
			or observed_at > now or now - observed_at > max_coordinate_age_s then
			return {
				state = 'blocked',
				blocker = 'AOE_GEOMETRY_UNKNOWN',
				missing_coordinate_id = member.id,
			}
		end
	end

	local best = nil
	local in_range_anchor_count = 0
	for index = 1, #members do
		local anchor = members[index]
		local anchor_distance = horizontal_distance(self_member, anchor)
		if anchor_distance <= target_range then
			in_range_anchor_count = in_range_anchor_count + 1
			local candidate = {
				anchor = anchor,
				anchor_id = anchor.id,
				anchor_name = anchor.name,
				anchor_distance = anchor_distance,
				party_order = party_order[anchor.id],
				member_priority = tonumber(input.member_priority(anchor)) or 99,
				covered_ids = {},
				covered_names = {},
				coverage_count = 0,
				aggregate_missing_hp = 0,
				lowest_covered_hpp = 101,
				maximum_missing_hp = 0,
				radius = radius,
				target_range = target_range,
			}
			for recipient_index = 1, #members do
				local recipient = members[recipient_index]
				if injured[recipient.id] and horizontal_distance(anchor, recipient) <= radius then
					local missing_hp = math.max(0, tonumber(input.estimate_missing_hp(recipient)) or 0)
					candidate.covered_ids[#candidate.covered_ids + 1] = recipient.id
					candidate.covered_names[#candidate.covered_names + 1] = recipient.name
					candidate.coverage_count = candidate.coverage_count + 1
					candidate.aggregate_missing_hp = candidate.aggregate_missing_hp + missing_hp
					candidate.lowest_covered_hpp = math.min(candidate.lowest_covered_hpp, tonumber(recipient.hpp) or 100)
					candidate.maximum_missing_hp = math.max(candidate.maximum_missing_hp, missing_hp)
				end
			end
			if candidate.coverage_count >= minimum_targets and candidate_better(candidate, best) then
				best = candidate
			end
		end
	end

	if best == nil then
		return {
			state = 'blocked',
			blocker = in_range_anchor_count == 0 and 'ANCHOR_OUT_OF_RANGE' or 'AOE_COVERAGE_BELOW_MINIMUM',
		}
	end
	return { state = 'ready', selected = best }
end

function M.healing_waltz_supports(status_key, mapped_spell)
	local key = tostring(status_key or ''):lower()
	if unsupported_healing_waltz_keys[key] then
		return false
	end
	return supported_healing_waltz_spells[tostring(mapped_spell or '')] == true
end

function M.should_admit_aoe(current, candidate, critical_hpp)
	if type(candidate) ~= 'table' then return false, 'NO_AOE_ACTION' end
	local critical_multicure = candidate.critical_multicure == true
		and (tonumber(candidate.critical_coverage_count) or 0) >= 2
	if type(current) == 'table' and current.aoe ~= true
		and (tonumber(current.target and current.target.hpp) or 100) <= tonumber(critical_hpp) then
		if critical_multicure then
			return true, 'CRITICAL_MULTICURE_OVERRIDE'
		end
		return false, 'CRITICAL_SINGLE_TARGET_PRESERVED'
	end
	if type(current) ~= 'table' or current.aoe ~= true then return true, '' end
	if candidate.coverage_count ~= current.coverage_count then
		if candidate.coverage_count > current.coverage_count then return true, '' end
		return false, 'AOE_NOT_STRICTLY_BETTER'
	end
	if candidate.aggregate_missing_hp ~= current.aggregate_missing_hp then
		if candidate.aggregate_missing_hp > current.aggregate_missing_hp then return true, '' end
		return false, 'AOE_NOT_STRICTLY_BETTER'
	end
	if candidate.lowest_covered_hpp ~= current.lowest_covered_hpp then
		if candidate.lowest_covered_hpp < current.lowest_covered_hpp then return true, '' end
		return false, 'AOE_NOT_STRICTLY_BETTER'
	end
	return false, 'AOE_NOT_STRICTLY_BETTER'
end

function M.evaluate_waltz_resource_gate(input)
	input = require_table(input, 'Waltz resource gate input')
	if input.action_kind ~= 'ja' or input.action_ready ~= true then
		local reason = tostring(input.action_reason or 'WALTZ_NOT_READY')
		if reason:find('RECAST', 1, true) then reason = 'WALTZ_RECAST' end
		return { ready = false, reason = reason }
	end
	local player_buffs = require_table(input.player_buffs, 'Waltz actor buffs')
	local buff_resources = require_table(input.buff_resources, 'Waltz buff resources')
	for _, buff_id in ipairs(player_buffs) do
		local buff = buff_resources[tonumber(buff_id) or 0]
		if buff and tostring(buff.en or ''):lower() == 'amnesia' then
			return { ready = false, reason = 'WALTZ_AMNESIA' }
		end
	end
	local ja = require_table(input.ja_resource, 'Waltz job ability resource')
	local tp_cost = tonumber(ja.tp_cost)
	if tp_cost == nil or tp_cost < 0 then
		error('Waltz job ability resource requires a non-negative tp_cost')
	end
	local recast_id = tonumber(ja.recast_id)
	if recast_id == nil or recast_id < 0 or recast_id % 1 ~= 0 then
		error('Waltz job ability resource requires a non-negative integer recast_id')
	end
	local resource_range = tonumber(ja.range)
	if resource_range == nil or resource_range < 0 then
		error('Waltz job ability resource requires a non-negative range')
	end
	local current_tp = tonumber(input.current_tp)
	if current_tp == nil or current_tp < 0 or current_tp > 3000 then
		error('Waltz current TP must be from 0 through 3000')
	end
	local reserve = tonumber(input.tp_reserve)
	if reserve == nil or reserve < 0 or reserve > 3000 or reserve % 1 ~= 0 then
		error('Waltz TP reserve must be an integer from 0 through 3000')
	end
	if current_tp < tp_cost + reserve then
		return { ready = false, reason = 'WALTZ_INSUFFICIENT_TP', tp_cost = tp_cost, tp_reserve = reserve }
	end
	return {
		ready = true,
		reason = '',
		tp_cost = tp_cost,
		tp_reserve = reserve,
		current_tp = current_tp,
		recast_id = recast_id,
		resource_range = resource_range,
	}
end

return M
