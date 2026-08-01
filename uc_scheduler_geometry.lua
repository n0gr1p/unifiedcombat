local M = {}

function M.normalize_angle_rad(a)
	local two_pi = math.pi * 2
	while a > math.pi do
		a = a - two_pi
	end
	while a < -math.pi do
		a = a + two_pi
	end
	return a
end

function M.target_is_in_front_arc(target, arc)
	local me = windower.ffxi.get_mob_by_target('me')
	if not me or not target or me.x == nil or me.y == nil or target.x == nil or target.y == nil or me.facing == nil then
		return false
	end
	local heading = math.atan2(target.y - me.y, target.x - me.x)
	local delta = math.abs(M.normalize_angle_rad(heading - tonumber(me.facing)))
	return delta <= (tonumber(arc) or (math.pi / 2))
end

return M
