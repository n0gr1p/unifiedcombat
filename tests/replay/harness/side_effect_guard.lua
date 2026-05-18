local M = {}

local function split_path(path)
    local out = {}
    for part in string.gmatch(path, "[^%.]+") do
        out[#out + 1] = part
    end
    return out
end

local function resolve_parent(root, parts)
    local node = root
    local created_nodes = {}
    for i = 1, #parts - 1 do
        local part = parts[i]
        local next_node = rawget(node, part)
        if next_node == nil then
            next_node = {}
            rawset(node, part, next_node)
            created_nodes[#created_nodes + 1] = { parent = node, key = part }
        elseif type(next_node) ~= "table" then
            error("side_effect_guard: non-table path segment at '" .. part .. "'")
        end
        node = next_node
    end
    return node, created_nodes
end

local function make_forbidden_stub(path, calls)
    return function(...)
        calls[#calls + 1] = { path = path, argc = select("#", ...) }
        error("forbidden side effect: " .. path)
    end
end

function M.new(forbidden_paths)
    if type(forbidden_paths) ~= "table" then
        error("side_effect_guard.new expects a table of dotted paths")
    end

    local guard = {
        _forbidden_paths = forbidden_paths,
        _installed = false,
        _calls = {},
        _restore_ops = {},
    }

    function guard:install(root_env)
        if self._installed then
            error("side_effect_guard already installed")
        end
        if type(root_env) ~= "table" then
            error("side_effect_guard.install expects a table root_env")
        end

        for _, dotted_path in ipairs(self._forbidden_paths) do
            local parts = split_path(dotted_path)
            if #parts == 0 then
                error("side_effect_guard: invalid empty path")
            end

            local parent, created_nodes = resolve_parent(root_env, parts)
            local leaf_key = parts[#parts]
            local had_leaf = rawget(parent, leaf_key) ~= nil
            local previous_leaf = rawget(parent, leaf_key)

            rawset(parent, leaf_key, make_forbidden_stub(dotted_path, self._calls))
            self._restore_ops[#self._restore_ops + 1] = {
                parent = parent,
                key = leaf_key,
                had_value = had_leaf,
                previous = previous_leaf,
                created_nodes = created_nodes,
            }
        end

        self._installed = true
    end

    function guard:restore()
        if not self._installed then
            return
        end

        for i = #self._restore_ops, 1, -1 do
            local op = self._restore_ops[i]
            if op.had_value then
                rawset(op.parent, op.key, op.previous)
            else
                rawset(op.parent, op.key, nil)
            end

            for j = #op.created_nodes, 1, -1 do
                local created = op.created_nodes[j]
                rawset(created.parent, created.key, nil)
            end
        end

        self._restore_ops = {}
        self._installed = false
    end

    function guard:get_calls()
        return self._calls
    end

    function guard:assert_clean()
        if #self._calls > 0 then
            error("forbidden side effects observed: " .. tostring(#self._calls))
        end
    end

    return guard
end

return M
