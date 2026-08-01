local M = {}

local BRD_JOB_ID = 10

function M.is_self_target(targets)
	if type(targets) == 'number' then
		return targets == 1
	end
	if type(targets) == 'string' then
		return targets:find('Self', 1, true) ~= nil
	end
	if type(targets) ~= 'table' then
		return false
	end
	if targets.Self == true then
		return true
	end
	for key, value in pairs(targets) do
		if (key == 'Self' and value == true) or value == 'Self' then
			return true
		end
	end
	return false
end

function M.collect(resources, known_spells, player)
	assert(type(resources) == 'table' and type(resources.spells) == 'table', 'BRD options require spell resources')
	assert(type(known_spells) == 'table', 'BRD options require the learned-spell table')
	assert(type(player) == 'table', 'BRD options require player state')

	local bard_level = nil
	if tostring(player.main_job or '') == 'BRD' then
		bard_level = tonumber(player.main_job_level)
	elseif tostring(player.sub_job or '') == 'BRD' then
		bard_level = tonumber(player.sub_job_level)
	else
		return {}
	end
	assert(bard_level ~= nil, 'BRD options require the current Bard job level')

	local names = {}
	local seen = {}
	local resource_song_count = 0
	local learned_song_count = 0
	for id, spell in pairs(resources.spells) do
		if type(spell) == 'table' and tostring(spell.type or '') == 'BardSong' then
			resource_song_count = resource_song_count + 1
		end
		local learned = known_spells[tonumber(id)]
		if learned == true or learned == 1 or learned == 'true' then
			if type(spell) == 'table' and tostring(spell.type or '') == 'BardSong' then
				learned_song_count = learned_song_count + 1
			end
			local required_level = type(spell) == 'table' and type(spell.levels) == 'table'
				and tonumber(spell.levels[BRD_JOB_ID]) or nil
			if required_level and bard_level >= required_level and tostring(spell.type or '') == 'BardSong'
				and M.is_self_target(spell.targets) and type(spell.en) == 'string' and spell.en ~= ''
				and not seen[spell.en] then
				names[#names + 1] = spell.en
				seen[spell.en] = true
			end
		end
	end
	table.sort(names)
	return names, {
		bard_level = bard_level,
		resource_song_count = resource_song_count,
		learned_song_count = learned_song_count,
	}
end

return M
