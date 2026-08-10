local M = {}

local property_elements = {
	Liquefaction = { 'Fire' },
	Induration = { 'Ice' },
	Detonation = { 'Wind' },
	Scission = { 'Earth' },
	Impaction = { 'Lightning' },
	Reverberation = { 'Water' },
	Transfixion = { 'Light' },
	Compression = { 'Dark' },
	Fusion = { 'Fire', 'Light' },
	Fragmentation = { 'Wind', 'Lightning' },
	Distortion = { 'Ice', 'Water' },
	Gravitation = { 'Earth', 'Dark' },
	Light = { 'Fire', 'Wind', 'Lightning', 'Light' },
	Darkness = { 'Ice', 'Earth', 'Water', 'Dark' },
	Radiance = { 'Fire', 'Wind', 'Lightning', 'Light' },
	Umbra = { 'Ice', 'Earth', 'Water', 'Dark' },
}

local function copy_list(values)
	local out = {}
	for i = 1, #(values or {}) do
		out[i] = values[i]
	end
	return out
end

function M.elements(property)
	return copy_list(property_elements[tostring(property or '')])
end

function M.contains(property, element)
	local wanted = tostring(element or '')
	local elements = property_elements[tostring(property or '')]
	for i = 1, #(elements or {}) do
		if elements[i] == wanted then
			return true
		end
	end
	return false
end

return M
