local M = {}

local dec2roman = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI' }

function M.to_roman_numeral(val)
	local n = tonumber(val)
	if not n then
		return nil
	end
	return dec2roman[n]
end

function M.ucfirst(s)
	local t = tostring(s or '')
	if t == '' then
		return t
	end
	return t:sub(1, 1):upper() .. t:sub(2):lower()
end

function M.decode_json_escapes(s)
	local t = tostring(s or '')
	if t == '' then
		return ''
	end
	t = t:gsub('\\u(%x%x%x%x)', function(h)
		local code = tonumber(h, 16)
		if not code then
			return ''
		end
		if code < 128 then
			return string.char(code)
		end
		-- Keep non-ASCII codepoints unchanged in this lightweight decoder.
		return '\\u' .. h
	end)
	t = t:gsub('\\"', '"')
	t = t:gsub("\\'", "'")
	t = t:gsub('\\\\', '\\')
	return t
end

function M.normalize_action_name_like_healbot(text)
	if type(text) ~= 'string' or #text < 1 then
		return ''
	end
	local raw = M.decode_json_escapes(tostring(text))
	raw = raw:gsub('[\226\128\153\226\128\152`´]', "'")
	raw = raw:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if raw == '' then
		return ''
	end
	local parts = {}
	for part in raw:gmatch('%S+') do
		parts[#parts + 1] = part
	end
	if #parts == 0 then
		return ''
	end
	local out = {}
	for _, part in ipairs(parts) do
		local rn = M.to_roman_numeral(part)
		local upper = tostring(part):upper()
		if rn then
			out[#out + 1] = rn
		elseif upper:match('^[IVX]+$') then
			out[#out + 1] = upper
		else
			-- Preserve internal punctuation/casing (ex: Boost-STR, Mage's) to avoid
			-- breaking spell/resource lookups while still normalizing whitespace/roman numerals.
			out[#out + 1] = part
		end
	end
	return table.concat(out, ' ')
end

function M.split_pipe(msg)
	local out = {}
	local s = tostring(msg or '')
	for token in (s .. '|'):gmatch('(.-)|') do
		out[#out + 1] = token
	end
	return out
end

function M.split_csv_numbers(s)
	local out = {}
	local txt = tostring(s or '')
	if txt == '' then
		return out
	end
	for part in string.gmatch(txt, '([^,]+)') do
		local n = tonumber(part)
		if n and n > 0 then
			out[#out + 1] = n
		end
	end
	return out
end

return M
