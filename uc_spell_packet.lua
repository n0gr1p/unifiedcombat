local packets = require('packets')
local res = require('resources')

local M = {}

local ACTION_PACKET_ID = 0x01A
local MAGIC_CATEGORY = 0x03

local function spell_by_name(name)
    local spell_name = tostring(name or '')
    if spell_name == '' or type(res.spells) ~= 'table' then
        return nil
    end
    if type(res.spells.with) == 'function' then
        local spell = res.spells:with('en', spell_name)
        if spell ~= nil then
            return spell
        end
    end
    for _, spell in pairs(res.spells) do
        if type(spell) == 'table' and tostring(spell.en or '') == spell_name then
            return spell
        end
    end
    return nil
end

local function target_by_id(target_id)
    local id = tonumber(target_id)
    if id == nil or id <= 0 then
        return nil, 'INVALID_TARGET_ID'
    end
    if type(windower) ~= 'table' or type(windower.ffxi) ~= 'table'
        or type(windower.ffxi.get_mob_by_id) ~= 'function' then
        return nil, 'TARGET_LOOKUP_UNAVAILABLE'
    end
    local ok, target = pcall(windower.ffxi.get_mob_by_id, id)
    if not ok or type(target) ~= 'table' then
        return nil, 'TARGET_NOT_FOUND'
    end
    if (tonumber(target.id) or 0) ~= id or (tonumber(target.index) or 0) <= 0 then
        return nil, 'TARGET_IDENTITY_INVALID'
    end
    return target, 'OK'
end

function M.cast_spell(spell_name, target_id)
    local spell = spell_by_name(spell_name)
    if type(spell) ~= 'table' or (tonumber(spell.id) or -1) < 0 then
        return false, 'SPELL_NOT_FOUND'
    end

    local target, target_reason = target_by_id(target_id)
    if target == nil then
        return false, target_reason
    end

    local ok_build, packet = pcall(packets.new, 'outgoing', ACTION_PACKET_ID, {
        ['Target'] = tonumber(target.id) or 0,
        ['Target Index'] = tonumber(target.index) or 0,
        ['Category'] = MAGIC_CATEGORY,
        ['Param'] = tonumber(spell.id) or 0,
        ['_unknown1'] = 0,
        ['X Offset'] = 0,
        ['Z Offset'] = 0,
        ['Y Offset'] = 0,
    })
    if not ok_build or packet == nil then
        return false, 'PACKET_BUILD_FAIL'
    end

    local ok_inject = pcall(packets.inject, packet)
    if not ok_inject then
        return false, 'PACKET_INJECT_FAIL'
    end
    return true, 'OK'
end

return M
