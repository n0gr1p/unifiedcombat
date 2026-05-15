local M = {}

function M.p1_is_tank_enmity_selected(_scheduler, selected)
    if type(selected) ~= 'table' then
        return false
    end
    if tostring(selected.family_id or '') == 'combat.tank_enmity.primary' then
        return true
    end
    return selected.detail and selected.detail.tank_enmity == true
end

function M.p1_target_distance_to_id(_scheduler, target_id)
    local mob = windower.ffxi.get_mob_by_id(tonumber(target_id) or 0)
    if not mob or mob.distance == nil then
        return nil, nil
    end
    return mob.distance:sqrt(), mob
end

return M
