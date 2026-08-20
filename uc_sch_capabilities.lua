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
	penury = { id = 215, name = 'Penury', recast_id = 231, buff_id = 360 },
	rapture = { id = 217, name = 'Rapture', recast_id = 231, buff_id = 364 },
	accession = { id = 218, name = 'Accession', recast_id = 231, buff_id = 366 },
	perpetuance = { id = 316, name = 'Perpetuance', recast_id = 231, buff_id = 469 },
	immanence = { id = 317, name = 'Immanence', recast_id = 231, buff_id = 470 },
	tabula_rasa = { id = 210, name = 'Tabula Rasa', recast_id = 0, buff_id = 377 },
}

local abilities_by_name = {}
for _, ability in pairs(M.abilities) do
	abilities_by_name[ability.name] = ability
end

function M.ability(name)
	if type(name) ~= 'string' then
		return nil
	end
	return abilities_by_name[name]
end

M.accession_maintenance_spells = {
	['Protect V'] = { id = 47, status_id = 40, base_duration_s = 1800, cast_time_s = 2, recast_id = 47, range = 12, anchor_policy = 'party' },
	['Shell V'] = { id = 52, status_id = 41, base_duration_s = 1800, cast_time_s = 2, recast_id = 52, range = 12, anchor_policy = 'party' },
	['Regen V'] = {
		id = 504,
		status_id = 42,
		base_duration_s = 60,
		cast_time_s = 2.5,
		recast_id = 504,
		range = 12,
		anchor_policy = 'party',
	},
	Refresh = { id = 109, status_id = 43, base_duration_s = 150, cast_time_s = 5, recast_id = 109, range = 12, anchor_policy = 'party' },
	Adloquium = { id = 495, status_id = 170, base_duration_s = 180, cast_time_s = 5, recast_id = 495, range = 12, anchor_policy = 'party' },
	Phalanx = { id = 106, status_id = 116, base_duration_s = 180, cast_time_s = 3, recast_id = 106, range = 12, anchor_policy = 'self' },
	Stoneskin = { id = 54, status_id = 37, base_duration_s = 300, cast_time_s = 7, recast_id = 54, range = 12, anchor_policy = 'self' },
	Blink = { id = 53, status_id = 36, base_duration_s = 300, cast_time_s = 6, recast_id = 53, range = 0, anchor_policy = 'self' },
	Aquaveil = { id = 55, status_id = 39, base_duration_s = 600, cast_time_s = 5, recast_id = 55, range = 0, anchor_policy = 'self' },
	Enfire = { id = 100, status_id = 94, base_duration_s = 180, cast_time_s = 3, recast_id = 100, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	Enblizzard = { id = 101, status_id = 95, base_duration_s = 180, cast_time_s = 3, recast_id = 101, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	Enaero = { id = 102, status_id = 96, base_duration_s = 180, cast_time_s = 3, recast_id = 102, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	Enstone = { id = 103, status_id = 97, base_duration_s = 180, cast_time_s = 3, recast_id = 103, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	Enthunder = { id = 104, status_id = 98, base_duration_s = 180, cast_time_s = 3, recast_id = 104, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	Enwater = { id = 105, status_id = 99, base_duration_s = 180, cast_time_s = 3, recast_id = 105, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	Barfire = { id = 60, status_id = 100, base_duration_s = 480, cast_time_s = 0.5, recast_id = 60, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	Barblizzard = { id = 61, status_id = 101, base_duration_s = 480, cast_time_s = 0.5, recast_id = 61, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	Baraero = { id = 62, status_id = 102, base_duration_s = 480, cast_time_s = 0.5, recast_id = 62, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	Barstone = { id = 63, status_id = 103, base_duration_s = 480, cast_time_s = 0.5, recast_id = 63, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	Barthunder = { id = 64, status_id = 104, base_duration_s = 480, cast_time_s = 0.5, recast_id = 64, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	Barwater = { id = 65, status_id = 105, base_duration_s = 480, cast_time_s = 0.5, recast_id = 65, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	Barsleep = { id = 72, status_id = 106, base_duration_s = 480, cast_time_s = 2.5, recast_id = 72, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Barpoison = { id = 73, status_id = 107, base_duration_s = 480, cast_time_s = 2.5, recast_id = 73, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Barparalyze = { id = 74, status_id = 108, base_duration_s = 480, cast_time_s = 2.5, recast_id = 74, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Barblind = { id = 75, status_id = 109, base_duration_s = 480, cast_time_s = 2.5, recast_id = 75, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Barsilence = { id = 76, status_id = 110, base_duration_s = 480, cast_time_s = 2.5, recast_id = 76, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Barpetrify = { id = 77, status_id = 111, base_duration_s = 480, cast_time_s = 2.5, recast_id = 77, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Barvirus = { id = 78, status_id = 112, base_duration_s = 480, cast_time_s = 2.5, recast_id = 78, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	Baramnesia = { id = 84, status_id = 286, base_duration_s = 480, cast_time_s = 2.5, recast_id = 84, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
}

for name, spell in pairs(M.accession_maintenance_spells) do
	spell.name = name
end

M.regen_spells = { ['Regen V'] = M.accession_maintenance_spells['Regen V'] }

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

function M.accession_maintenance_spell(name)
	if type(name) ~= 'string' then
		return nil
	end
	return M.accession_maintenance_spells[name]
end

function M.accession_ownership_family(name)
	local spell = M.accession_maintenance_spell(name)
	if spell == nil then
		return nil
	end
	return 'accession_' .. tostring(spell.status_id)
end

function M.storm_spell(name)
	if type(name) ~= 'string' then
		return nil
	end
	return M.storm_spells[name]
end

return M
