local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a')
    f:close()
    return s
end

local function assert_contains(haystack, needle, message)
    if not haystack:find(needle, 1, true) then
        error(message .. ': missing ' .. needle)
    end
end

local cor = read('uc_cor_maintenance.lua')
local ownership = read('uc_scheduler_command_ownership.lua')
local normalizer = read('uc_config_normalizer_cor.lua')
local normalizer_entry = read('uc_config_normalizer.lua')

assert_contains(cor, '[23] = 60', 'Dia I must be supported')
assert_contains(cor, '[24] = 120', 'Dia II must be supported')
assert_contains(cor, '[25] = 180', 'Dia III must be supported')
assert_contains(cor, "get_mob_by_target('t')", 'utility must use the current selected target')
assert_contains(cor, "player.main_job or '') ~= 'COR'", 'utility must require main-job COR')
assert_contains(cor, "state.light_shot_handled[tid] == generation", 'utility must suppress repeat shots for one Dia generation')
assert_contains(cor, 'state.pending_light_shot = {', 'utility must preserve target/generation through scheduler arbitration')
assert_contains(cor, "action_id == LIGHT_SHOT_ID", 'manual or automated Light Shot must be observed')
assert_contains(cor, "windower.ffxi.get_ability_recasts()", 'utility must wait for a Quick Draw charge')
assert_contains(cor, "reason_code = reason_code", 'targeted utility action must flow through COR maintenance proposals')

assert_contains(ownership, "meta.action_name or '') ~= 'Light Shot'", 'command ownership must scope target rewrite to Light Shot')
assert_contains(ownership, "resolve_pending_light_shot_target", 'dispatch must revalidate the current target/Dia generation')
assert_contains(ownership, "intent.command = 'input /ja \"Light Shot\" <t>'", 'Light Shot must target the selected enemy, not self')
assert_contains(ownership, "cor_light_shot_target_stale", 'stale target must become a safe no-op')

assert_contains(normalizer, 'light_shot_dia', 'canonical COR utility config must include Light Shot Dia')
assert_contains(normalizer, 'value = true', 'COR Dia Light Shot must default on')
assert_contains(normalizer_entry, "require('uc_config_normalizer_cor').wrap(sequence)", 'COR config wrapper must be installed')

io.stdout:write('selftest_cor_dia_lightshot_static: OK\n')
