local M = {}

function M.parse_status_snapshot_063(data)
	if type(data) ~= 'string' or #data < 80 then
		return nil
	end
	if data:byte(5) ~= 9 then
		return nil
	end
	local status_by_id = {}
	for n = 1, 32 do
		local buff_id = data:unpack('H', n * 2 + 7)
		if buff_id == 255 then
			break
		end
		local endtime = data:unpack('I', n * 4 + 69)
		status_by_id[buff_id] = status_by_id[buff_id] or { count = 0, endtimes = {} }
		status_by_id[buff_id].count = status_by_id[buff_id].count + 1
		if endtime and endtime > 0 then
			status_by_id[buff_id].endtimes[#status_by_id[buff_id].endtimes + 1] = endtime
		end
	end
	for _, v in pairs(status_by_id) do
		table.sort(v.endtimes, function(a, b)
			return (tonumber(a) or 0) < (tonumber(b) or 0)
		end)
	end
	return status_by_id
end

return M
