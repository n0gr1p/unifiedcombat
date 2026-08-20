local M = {}

local aliases = {
    ['paralyze'] = 'paralysis',
    ['blindness'] = 'blind',
}

function M.normalize_key(value)
    local key = tostring(value or '')
        :lower()
        :gsub('^%s+', '')
        :gsub('%s+$', '')
        :gsub('%s+', '_')
    return aliases[key] or key
end

local function append_unique(policy, value)
    local key = M.normalize_key(value)
    if key == '' or policy.ranks[key] ~= nil then
        return
    end
    local rank = #policy.ordered
    policy.ordered[#policy.ordered + 1] = key
    policy.ranks[key] = rank
end

function M.build(enabled, raw)
    local policy = {
        enabled = enabled == true,
        ordered = {},
        ranks = {},
    }
    if not policy.enabled then
        return policy
    end

    if type(raw) == 'table' then
        for i = 1, #raw do
            append_unique(policy, raw[i])
        end
    elseif type(raw) == 'string' then
        for entry in raw:gmatch('[^|]+') do
            append_unique(policy, entry)
        end
    end

    return policy
end

function M.rank(policy, status_key)
    if type(policy) ~= 'table' or policy.enabled ~= true then
        return nil
    end
    return policy.ranks[M.normalize_key(status_key)]
end

function M.candidate_priority(policy, status_key, member_priority)
    local rank = M.rank(policy, status_key)
    if rank == nil then
        return nil
    end
    return (rank * 10) + (tonumber(member_priority) or 5)
end

return M
