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

M.accession_perpetuance_spells = {
	['Protect'] = { id = 43, status_id = 40, base_duration_s = 1800, cast_time_s = 1, recast_id = 43, range = 12, anchor_policy = 'party', exclusive_group = 'protect' },
	['Protect II'] = { id = 44, status_id = 40, base_duration_s = 1800, cast_time_s = 1.25, recast_id = 44, range = 12, anchor_policy = 'party', exclusive_group = 'protect' },
	['Protect III'] = { id = 45, status_id = 40, base_duration_s = 1800, cast_time_s = 1.5, recast_id = 45, range = 12, anchor_policy = 'party', exclusive_group = 'protect' },
	['Protect IV'] = { id = 46, status_id = 40, base_duration_s = 1800, cast_time_s = 1.75, recast_id = 46, range = 12, anchor_policy = 'party', exclusive_group = 'protect' },
	['Protect V'] = { id = 47, status_id = 40, base_duration_s = 1800, cast_time_s = 2, recast_id = 47, range = 12, anchor_policy = 'party', exclusive_group = 'protect' },
	['Shell'] = { id = 48, status_id = 41, base_duration_s = 1800, cast_time_s = 1, recast_id = 48, range = 12, anchor_policy = 'party', exclusive_group = 'shell' },
	['Shell II'] = { id = 49, status_id = 41, base_duration_s = 1800, cast_time_s = 1.25, recast_id = 49, range = 12, anchor_policy = 'party', exclusive_group = 'shell' },
	['Shell III'] = { id = 50, status_id = 41, base_duration_s = 1800, cast_time_s = 1.5, recast_id = 50, range = 12, anchor_policy = 'party', exclusive_group = 'shell' },
	['Shell IV'] = { id = 51, status_id = 41, base_duration_s = 1800, cast_time_s = 1.75, recast_id = 51, range = 12, anchor_policy = 'party', exclusive_group = 'shell' },
	['Shell V'] = { id = 52, status_id = 41, base_duration_s = 1800, cast_time_s = 2, recast_id = 52, range = 12, anchor_policy = 'party', exclusive_group = 'shell' },
	['Regen'] = { id = 108, status_id = 42, base_duration_s = 75, cast_time_s = 1.5, recast_id = 108, range = 12, anchor_policy = 'party', exclusive_group = 'regen' },
	['Regen II'] = { id = 110, status_id = 42, base_duration_s = 60, cast_time_s = 1.75, recast_id = 110, range = 12, anchor_policy = 'party', exclusive_group = 'regen' },
	['Regen III'] = { id = 111, status_id = 42, base_duration_s = 60, cast_time_s = 2, recast_id = 111, range = 12, anchor_policy = 'party', exclusive_group = 'regen' },
	['Regen IV'] = { id = 477, status_id = 42, base_duration_s = 60, cast_time_s = 2.25, recast_id = 477, range = 12, anchor_policy = 'party', exclusive_group = 'regen' },
	['Regen V'] = { id = 504, status_id = 42, base_duration_s = 60, cast_time_s = 2.5, recast_id = 504, range = 12, anchor_policy = 'party', exclusive_group = 'regen' },
	['Refresh'] = { id = 109, status_id = 43, base_duration_s = 150, cast_time_s = 5, recast_id = 109, range = 12, anchor_policy = 'party' },
	['Adloquium'] = { id = 495, status_id = 170, base_duration_s = 180, cast_time_s = 5, recast_id = 495, range = 12, anchor_policy = 'party' },
	['Phalanx'] = { id = 106, status_id = 116, base_duration_s = 180, cast_time_s = 3, recast_id = 106, range = 12, anchor_policy = 'party' },
	['Stoneskin'] = { id = 54, status_id = 37, base_duration_s = 300, cast_time_s = 7, recast_id = 54, range = 12, anchor_policy = 'party' },
	['Blink'] = { id = 53, status_id = 36, base_duration_s = 300, cast_time_s = 6, recast_id = 53, range = 0, anchor_policy = 'self' },
	['Aquaveil'] = { id = 55, status_id = 39, base_duration_s = 600, cast_time_s = 5, recast_id = 55, range = 0, anchor_policy = 'self' },
	['Enfire'] = { id = 100, status_id = 94, base_duration_s = 180, cast_time_s = 3, recast_id = 100, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	['Enblizzard'] = { id = 101, status_id = 95, base_duration_s = 180, cast_time_s = 3, recast_id = 101, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	['Enaero'] = { id = 102, status_id = 96, base_duration_s = 180, cast_time_s = 3, recast_id = 102, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	['Enstone'] = { id = 103, status_id = 97, base_duration_s = 180, cast_time_s = 3, recast_id = 103, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	['Enthunder'] = { id = 104, status_id = 98, base_duration_s = 180, cast_time_s = 3, recast_id = 104, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	['Enwater'] = { id = 105, status_id = 99, base_duration_s = 180, cast_time_s = 3, recast_id = 105, range = 0, anchor_policy = 'self', exclusive_group = 'enspell' },
	['Barfire'] = { id = 60, status_id = 100, base_duration_s = 480, cast_time_s = 0.5, recast_id = 60, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	['Barblizzard'] = { id = 61, status_id = 101, base_duration_s = 480, cast_time_s = 0.5, recast_id = 61, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	['Baraero'] = { id = 62, status_id = 102, base_duration_s = 480, cast_time_s = 0.5, recast_id = 62, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	['Barstone'] = { id = 63, status_id = 103, base_duration_s = 480, cast_time_s = 0.5, recast_id = 63, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	['Barthunder'] = { id = 64, status_id = 104, base_duration_s = 480, cast_time_s = 0.5, recast_id = 64, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	['Barwater'] = { id = 65, status_id = 105, base_duration_s = 480, cast_time_s = 0.5, recast_id = 65, range = 0, anchor_policy = 'self', exclusive_group = 'bar_element' },
	['Barsleep'] = { id = 72, status_id = 106, base_duration_s = 480, cast_time_s = 2.5, recast_id = 72, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Barpoison'] = { id = 73, status_id = 107, base_duration_s = 480, cast_time_s = 2.5, recast_id = 73, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Barparalyze'] = { id = 74, status_id = 108, base_duration_s = 480, cast_time_s = 2.5, recast_id = 74, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Barblind'] = { id = 75, status_id = 109, base_duration_s = 480, cast_time_s = 2.5, recast_id = 75, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Barsilence'] = { id = 76, status_id = 110, base_duration_s = 480, cast_time_s = 2.5, recast_id = 76, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Barpetrify'] = { id = 77, status_id = 111, base_duration_s = 480, cast_time_s = 2.5, recast_id = 77, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Barvirus'] = { id = 78, status_id = 112, base_duration_s = 480, cast_time_s = 2.5, recast_id = 78, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Baramnesia'] = { id = 84, status_id = 286, base_duration_s = 480, cast_time_s = 2.5, recast_id = 84, range = 0, anchor_policy = 'self', exclusive_group = 'bar_status' },
	['Sandstorm'] = { id = 99, status_id = 181, base_duration_s = 180, cast_time_s = 2, recast_id = 99, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Rainstorm'] = { id = 113, status_id = 183, base_duration_s = 180, cast_time_s = 2, recast_id = 113, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Windstorm'] = { id = 114, status_id = 180, base_duration_s = 180, cast_time_s = 2, recast_id = 114, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Firestorm'] = { id = 115, status_id = 178, base_duration_s = 180, cast_time_s = 2, recast_id = 115, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Hailstorm'] = { id = 116, status_id = 179, base_duration_s = 180, cast_time_s = 2, recast_id = 116, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Thunderstorm'] = { id = 117, status_id = 182, base_duration_s = 180, cast_time_s = 2, recast_id = 117, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Voidstorm'] = { id = 118, status_id = 185, base_duration_s = 180, cast_time_s = 2, recast_id = 118, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Aurorastorm'] = { id = 119, status_id = 184, base_duration_s = 180, cast_time_s = 2, recast_id = 119, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Sandstorm II'] = { id = 857, status_id = 592, base_duration_s = 180, cast_time_s = 2, recast_id = 857, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Rainstorm II'] = { id = 858, status_id = 594, base_duration_s = 180, cast_time_s = 2, recast_id = 858, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Windstorm II'] = { id = 859, status_id = 591, base_duration_s = 180, cast_time_s = 2, recast_id = 859, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Firestorm II'] = { id = 860, status_id = 589, base_duration_s = 180, cast_time_s = 2, recast_id = 860, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Hailstorm II'] = { id = 861, status_id = 590, base_duration_s = 180, cast_time_s = 2, recast_id = 861, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Thunderstorm II'] = { id = 862, status_id = 593, base_duration_s = 180, cast_time_s = 2, recast_id = 862, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Voidstorm II'] = { id = 863, status_id = 596, base_duration_s = 180, cast_time_s = 2, recast_id = 863, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Aurorastorm II'] = { id = 864, status_id = 595, base_duration_s = 180, cast_time_s = 2, recast_id = 864, range = 12, anchor_policy = 'party', exclusive_group = 'storm', ownership_family = 'storm' },
	['Animus Augeo'] = { id = 308, status_id = 289, base_duration_s = 180, cast_time_s = 3, recast_id = 308, range = 12, anchor_policy = 'party', exclusive_group = 'animus' },
	['Animus Minuo'] = { id = 309, status_id = 171, base_duration_s = 180, cast_time_s = 3, recast_id = 309, range = 12, anchor_policy = 'party', exclusive_group = 'animus' },
	['Invisible'] = { id = 136, status_id = 69, cast_time_s = 3, recast_id = 136, range = 12, anchor_policy = 'party' },
	['Sneak'] = { id = 137, status_id = 71, cast_time_s = 3, recast_id = 137, range = 12, anchor_policy = 'party' },
	['Deodorize'] = { id = 138, status_id = 70, cast_time_s = 2, recast_id = 138, range = 12, anchor_policy = 'party' },
	['Embrava'] = { id = 478, status_id = 228, base_duration_s = 90, cast_time_s = 3, recast_id = 478, range = 12, anchor_policy = 'party', requires_tabula_rasa = true, requirements = 9 },
}

for name, spell in pairs(M.accession_perpetuance_spells) do
	spell.name = name
end

-- Backward-compatible alias for existing runtime/config call sites.
M.accession_maintenance_spells = M.accession_perpetuance_spells

M.regen_spells = { ['Regen V'] = M.accession_perpetuance_spells['Regen V'] }

-- The targeted-storm subsystem remains Storm II-only; Storm I is still available
-- through the generic Accession + Perpetuance maintenance path.
M.storm_spells = {
	['Sandstorm II'] = M.accession_perpetuance_spells['Sandstorm II'],
	['Rainstorm II'] = M.accession_perpetuance_spells['Rainstorm II'],
	['Windstorm II'] = M.accession_perpetuance_spells['Windstorm II'],
	['Firestorm II'] = M.accession_perpetuance_spells['Firestorm II'],
	['Hailstorm II'] = M.accession_perpetuance_spells['Hailstorm II'],
	['Thunderstorm II'] = M.accession_perpetuance_spells['Thunderstorm II'],
	['Voidstorm II'] = M.accession_perpetuance_spells['Voidstorm II'],
	['Aurorastorm II'] = M.accession_perpetuance_spells['Aurorastorm II'],
}

M.embrava = M.accession_perpetuance_spells['Embrava']

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
	return M.accession_perpetuance_spells[name]
end

function M.accession_ownership_family(name)
	local spell = M.accession_maintenance_spell(name)
	if spell == nil then
		return nil
	end
	return spell.ownership_family or ('accession_' .. tostring(spell.status_id))
end

function M.accession_exclusive_status_ids(name)
	local spell = M.accession_maintenance_spell(name)
	if spell == nil or spell.exclusive_group == nil then
		return {}
	end
	local seen = {}
	local out = {}
	for _, candidate in pairs(M.accession_perpetuance_spells) do
		if candidate.exclusive_group == spell.exclusive_group
			and seen[candidate.status_id] ~= true then
			seen[candidate.status_id] = true
			out[#out + 1] = candidate.status_id
		end
	end
	table.sort(out)
	return out
end

function M.storm_spell(name)
	if type(name) ~= 'string' then
		return nil
	end
	return M.storm_spells[name]
end

return M
