local M = {}

function M.wrap(base)
    if type(base) ~= 'table' or type(base.new) ~= 'function' then
        error('uc_combat_extensions_once requires combat extensions')
    end
    local wrapped = {}
    for key, value in pairs(base) do
        wrapped[key] = value
    end
    local original_new = base.new

    function wrapped.new(deps)
        local api = original_new(deps)
        local original_collect = api.collect_priority_offense
        if type(original_collect) ~= 'function' then
            error('combat extensions missing collect_priority_offense')
        end

        function api.collect_priority_offense(ctx, out)
            local reaction_runtime = require('uc_reaction_runtime')
            local before = reaction_runtime.get_action_lock()
            local out_count = #out
            local handled = original_collect(ctx, out)

            if type(before) == 'table'
                and tostring(before.response or '') == 'use_sequence'
                and (tonumber(before.step_index) or 1) == 1
                and before.action_optional ~= true
                and tostring(before.step_state or '') == 'pending'
                and #out == out_count then
                reaction_runtime.cancel(before.key, 'required_opener_unavailable')
                return original_collect(ctx, out)
            end

            return handled
        end

        return api
    end

    return wrapped
end

return M
