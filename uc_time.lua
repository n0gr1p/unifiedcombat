local M = {}

local socket_mod = rawget(_G, 'socket')
if type(socket_mod) ~= 'table' or type(socket_mod.gettime) ~= 'function' then
    local ok, loaded = pcall(require, 'socket')
    if ok then
        socket_mod = loaded
    end
end

if type(socket_mod) == 'table' and type(socket_mod.gettime) == 'function' then
    M.gettime = socket_mod.gettime
else
    M.gettime = nil
end

function M.available()
    return type(M.gettime) == 'function'
end

function M.now()
    if not M.available() then
        error('uc_time requires LuaSocket socket.gettime')
    end
    return M.gettime()
end

return M
