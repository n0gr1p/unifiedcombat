local M = {}

M.JOB_ID = 20
M.JOB_SHORT_NAME = 'SCH'
M.STRATAGEM_RECAST_ID = 231

M.abilities = {
	light_arts = { id = 211, name = 'Light Arts', recast_id = 228, buff_id = 358 },
	dark_arts = { id = 212, name = 'Dark Arts', recast_id = 232, buff_id = 359 },
	sublimation = {
		id = 233,
		name = 'Sublimation',
		recast_id = 234,
		activated_buff_id = 187,
		complete_buff_id = 188,
	},
	addendum_white = { id = 234, name = 'Addendum: White', recast_id = 231, buff_id = 401 },
	addendum_black = { id = 235, name = 'Addendum: Black', recast_id = 231, buff_id = 402 },
	accession = { id = 218, name = 'Accession', recast_id = 231, buff_id = 366 },
	perpetuance = { id = 316, name = 'Perpetuance', recast_id = 231, buff_id = 469 },
	immanence = { id = 317, name = 'Immanence', recast_id = 231, buff_id = 470 },
	tabula_rasa = { id = 210, name = 'Tabula Rasa', recast_id = 0, buff_id = 377 },
}

M.regen_spells = {
	['Regen V'] = {
		id = 504,
		name = 'Regen V',
		status_id = 42,
		base_duration_s = 60,
		cast_time_s = 2.5,
		recast_id = 504,
		range = 12,
	},
}

M.storm_spells = {
	['Sandstorm II'] = { id = 857, name = 'Sandstorm II', status_id = 592, element = 'Earth' },
	['Rainstorm II'] = { id = 858, name = 'Rainstorm II', status_id = 594, element = 'Water' },
	['Windstorm II'] = { id = 859, name = 'Windstorm II', status_id = 591, element = 'Wind' },
	['Firestorm II'] = { id = 860, name = 'Firestorm II', status_id = 589, element = 'Fire' },
	['Hailstorm II'] = { id = 861, name = 'Hailstorm II', status_id = 590, element = 'Ice' },
	['Thunderstorm II'] = { id = 862, name = 'Thunderstorm II', status_id = 593, element = 'Lightning' },
	['Voidstorm II'] = { id = 863, name = 'Voidstorm II', status_id = 596, element = 'Dark' },
	['Aurorastorm II'] = { id = 864, name = 'Aurorastorm II', status_id = 595, element = 'Light' },
}

for _, spell in pairs(M.storm_spells) do
	spell.base_duration_s = 180
	spell.cast_time_s = 2.0
	spell.recast_id = spell.id
	spell.range = 12
end

M.embrava = {
	id = 478,
	name = 'Embrava',
	status_id = 228,
	base_duration_s = 90,
	requirements = 9,
}

function M.regen_spell(name)
	if type(name) ~= 'string' then
		return nil
	end
	return M.regen_spells[name]
end

function M.storm_spell(name)
	if type(name) ~= 'string' then
		return nil
	end
	return M.storm_spells[name]
end

return M
