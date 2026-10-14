local M = {}

function M.current_zone_id()
	local info = windower.ffxi.get_info()
	return tonumber(info and info.zone) or 0
end

function M.get_settings()
	return rawget(_G, 'UC_SETTINGS') or {}
end

function M.get_config()
	local config = require('uc_active_config').get_config()
	if type(config) == 'table' then
		return config
	end
	return {}
end

function M.is_city_zone_for_maintenance(maintenance_blocked_zone_names)
	local info = windower.ffxi.get_info()
	if not info then
		return false
	end
	local zid = tonumber(info.zone) or 0
	if zid <= 0 then
		return false
	end
	local z = res.zones and res.zones[zid] or nil
	local name = tostring((z and (z.en or z.name)) or ''):lower()
	if name == '' then
		return false
	end
	if maintenance_blocked_zone_names[name] then
		return true
	end
	-- Defensive fallback: treat mog house / residential names as non-maintenance zones.
	if name:find('mog house', 1, true) or name:find('residential area', 1, true) then
		return true
	end
	return false
end

-- Scheduler action/revalidation gates must not re-enable partner actions
-- using transient flat state after Profile V2 explicitly disables them.
function M.partner_enabled(settings, config)
    if type(config) == 'table' then
        local partner = require('uc_follow_config').partner(config)
        return type(partner) == 'table' and partner.enabled == true
    end
    local enabled = type(settings) == 'table' and settings.partner or nil
    if enabled == true or enabled == 1 then return true end
    if type(enabled) == 'string' then
        local value = enabled:lower()
        return value == 'true' or value == 'on' or value == '1' or value == 'yes'
    end
    return false
end

function M.build_partner_target_set(deps, settings)
	local out = {}
	if not deps.bool_setting(settings and settings.partner, false) then
		return out
	end
	local partner_ids = deps.uc_partner_list.as_ordered_ids(settings or {})
	for _, pid in ipairs(partner_ids or {}) do
		local pm = windower.ffxi.get_mob_by_id(tonumber(pid) or 0)
		if pm and pm.target_index then
			local tm = windower.ffxi.get_mob_by_index(pm.target_index)
			local tid = tonumber(tm and tm.id) or 0
			if tid > 0 then
				out[tid] = true
			end
		end
	end
	return out
end

function M.p1_build_party_id_set(deps)
	local ids = {}
	local members = deps.get_party_members()
	for _, m in ipairs(members) do
		local id = tonumber(m and m.id) or 0
		if id > 0 then
			ids[id] = true
		end
	end
	return ids
end

return M
