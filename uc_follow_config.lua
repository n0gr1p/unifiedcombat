local M = {}

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$') or ''
end

local function config_follow(config)
    local follow = type(config) == 'table' and config.follow or nil
    return type(follow) == 'table' and follow or nil
end

function M.from_config(config)
    return config_follow(config)
end

function M.enabled(config)
    local follow = config_follow(config)
    if type(follow) ~= 'table' then return false end
    if follow.enabled == nil then return true end
    return follow.enabled == true
end

function M.party(config)
    local follow = config_follow(config)
    local party = type(follow) == 'table' and follow.party or nil
    return type(party) == 'table' and party or nil
end

function M.fight(config)
    local follow = config_follow(config)
    local fight = type(follow) == 'table' and follow.fight or nil
    return type(fight) == 'table' and fight or nil
end

function M.partner(config)
    local follow = config_follow(config)
    local partner = type(follow) == 'table' and follow.partner or nil
    return type(partner) == 'table' and partner or nil
end

function M.nyzul(config)
    local follow = config_follow(config)
    local nyzul = type(follow) == 'table' and follow.nyzul or nil
    return type(nyzul) == 'table' and nyzul or nil
end

function M.resolve_party_member_id_by_name(name)
    local wanted = trim(name)
    if wanted == '' then return 0 end
    local ffxi = windower and windower.ffxi or nil
    if type(ffxi) ~= 'table' then return 0 end
    if type(ffxi.get_party) == 'function' then
        local ok, party = pcall(ffxi.get_party)
        if ok and type(party) == 'table' then
            for _, key in ipairs({ 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' }) do
                local entry = party[key]
                local mob = entry and entry.mob
                if mob and trim(mob.name) == wanted then
                    local id = tonumber(mob.id) or 0
                    if id > 0 then return id end
                end
            end
        end
    end
    return 0
end

local function configured_id(name, id)
    local durable_name = trim(name)
    if durable_name ~= '' then
        return M.resolve_party_member_id_by_name(durable_name)
    end
    return tonumber(id) or 0
end

function M.party_leader_id(config)
    local party = M.party(config)
    if type(party) ~= 'table' then return 0 end
    return configured_id(party.leader_name, party.leader_id)
end

function M.party_leader_name(config)
    local party = M.party(config)
    return type(party) == 'table' and trim(party.leader_name) or ''
end

function M.fight_leader_id(config)
    local fight = M.fight(config)
    if type(fight) ~= 'table' then return 0 end
    return configured_id(fight.leader_name, fight.leader_id)
end

function M.fight_leader_name(config)
    local fight = M.fight(config)
    return type(fight) == 'table' and trim(fight.leader_name) or ''
end

function M.partner_ids(config)
    local partner = M.partner(config)
    if type(partner) ~= 'table' then return {} end
    local out = {}
    local names = partner.names
    if type(names) == 'table' and #names > 0 then
        for _, name in ipairs(names) do
            local id = M.resolve_party_member_id_by_name(name)
            if id > 0 then out[#out + 1] = id end
        end
        return out
    end
    if type(partner.ids) == 'table' then
        for _, raw in ipairs(partner.ids) do
            local id = tonumber(raw) or 0
            if id > 0 then out[#out + 1] = id end
        end
    end
    return out
end

function M.puller_id(config)
    local partner = M.partner(config)
    if type(partner) ~= 'table' then return 0 end
    if tostring(partner.leash_source or 'player') == 'camp' then
        return 0
    end
    return configured_id(partner.puller_name, partner.puller_id)
end

function M.apply_runtime_view(view, config)
    if type(view) ~= 'table' then error('follow runtime view requires a table') end
    local follow = config_follow(config)
    if type(follow) ~= 'table' then return view end
    local party = M.party(config) or {}
    local fight = M.fight(config) or {}
    local partner = M.partner(config) or {}
    local partner_ids = M.partner_ids(config)

    view.domain_follow_enabled = M.enabled(config)
    view.party_follow = party.enabled == true
    view.party_follow_id = M.party_leader_id(config)
    view.party_follow_leader_name = trim(party.leader_name)
    view.party_follow_min = party.min
    view.party_follow_max = party.max

    view.fight_leader = fight.leader == true
    view.fight_leader_id = M.fight_leader_id(config)
    view.fight_leader_name = trim(fight.leader_name)
    view.fight_follow_min = fight.min
    view.fight_follow_hold_s = fight.hold_s

    view.partner = partner.enabled == true
    view.partner2 = partner.secondary_enabled == true
    view.partner_ids = partner_ids
    view.partner_id = partner_ids[1] or 0
    view.partner_id2 = partner_ids[2] or 0
    view.puller = partner.puller == true
    view.puller_name = trim(partner.puller_name)
    view.puller_id = M.puller_id(config)
    view.puller_leash_source = tostring(partner.leash_source or 'player')
    view.puller_engage_range = partner.engage_range
    view.puller_distance_only = partner.puller_distance_only == true
    return view
end

return M
