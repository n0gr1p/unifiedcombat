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
local tracker = read('uc_enemy_effect_tracker.lua')
local normalizer = read('uc_config_normalizer_cor.lua')
local normalizer_entry = read('uc_config_normalizer.lua')

assert_contains(cor, '[23] = 60', 'Dia I must be supported')
assert_contains(cor, '[24] = 120', 'Dia II must be supported')
assert_contains(cor, '[25] = 180', 'Dia III must be supported')
assert_contains(cor, "get_mob_by_target('t')", 'utility must use the current selected target')
assert_contains(cor, "player.main_job or '') ~= 'COR'", 'utility must require main-job COR')
assert_contains(cor, 'state.pending_light_shot = {', 'utility must preserve target/generation through scheduler arbitration')
assert_contains(cor, 'windower.ffxi.get_ability_recasts()', 'utility must wait for a Quick Draw charge')
assert_contains(cor, 'reason_code = reason_code', 'targeted utility action must flow through COR maintenance proposals')

assert_contains(tracker, '[134] = true', 'Dia must always enter the existing enemy-effect tracker')
assert_contains(ownership, "require('uc_enemy_effect_tracker')", 'Light Shot authority must use existing enemy-effect tracking')
assert_contains(ownership, 'effect.effect_id) == 134', 'Light Shot authority must require tracked Dia status 134')
assert_contains(ownership, 'cor_light_shot_dia_not_tracked', 'untracked/non-Dia proposals must become safe no-ops')
assert_contains(ownership, 'cor_light_shot_dia_already_handled', 'one Dia generation must not fire twice')
assert_contains(ownership, 'meta.cor_dia_generation = generation', 'dispatch must carry the authoritative Dia generation')
assert_contains(ownership, 'cor_light_shot_handled[target_id] = generation', 'successful dispatch must consume the Dia generation')
assert_contains(ownership, "meta.action_name or '') ~= 'Light Shot'", 'command ownership must scope target rewrite to Light Shot')
assert_contains(ownership, 'resolve_pending_light_shot_target', 'dispatch must revalidate the current target')
assert_contains(ownership, 'intent.command = \'input /ja "Light Shot" <t>\'', 'Light Shot must target the selected enemy, not self')
assert_contains(ownership, 'cor_light_shot_target_stale', 'stale target must become a safe no-op')

assert_contains(normalizer, 'light_shot_dia', 'canonical COR utility config must include Light Shot Dia')
assert_contains(normalizer, 'value = true', 'COR Dia Light Shot must default on')
assert_contains(normalizer_entry, "require('uc_config_normalizer_cor').wrap(once)", 'COR config wrapper must be installed after once-per-instance normalization')

io.stdout:write('selftest_cor_dia_lightshot_static: OK\n')
