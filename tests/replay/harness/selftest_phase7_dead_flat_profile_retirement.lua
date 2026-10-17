local function read_all(path)
    local f = assert(io.open(path, 'r'))
    local text = f:read('*a')
    f:close()
    return text
end

local function contains(source, text, context)
    assert(source:find(text, 1, true), context or ('missing required source: ' .. text))
end

local function absent(source, text, context)
    assert(not source:find(text, 1, true), context or ('retired flat source survived: ' .. text))
end

local addon = read_all('UnifiedCombat.lua')
for _, name in ipairs({
    'local PROFILE_KEYS = {',
    'local function uc_capture_active_profile(',
    'local function uc_apply_active_profile(',
    'local function uc_get_active_profile_coords',
    'local function uc_table_has_any(',
    'local uc_normalize_settings_table',
    'uc_normalize_settings_table = function(',
    'local function uc_normalize_active_settings(',
    'local function uc_normalize_abilities(',
    'local function uc_normalize_targets(',
    'local function uc_normalize_ws_for_engine(',
    'local function uc_normalize_domain_settings(',
}) do
    absent(addon, name)
end

-- Avoid deleting public migration, profile handling, identity, or save/reload
-- functionality simply because its caller still accepts flat compatibility.
contains(addon, 'local function uc_save_active_profile()', 'explicit canonical export must remain')
contains(addon, 'uc_profile_v2.build_structured_profile_from_active_profile',
    'Profile V2 export must derive from canonical active config')
contains(addon, 'uc_active_config.build_default_active_profile({',
    'startup must build canonical defaults')
contains(addon, 'uc_active_config.set_active_profile(uc_startup_active_profile)',
    'startup must publish the canonical profile')
contains(addon, 'local function uc_read_profiles_file(char_name)',
    'legacy profile reader retained for explicit compatibility')
contains(addon, 'local function uc_load_profiles_for_character(char_name)',
    'separate legacy profile import path untouched by this safe cleanup')

print('selftest_phase7_dead_flat_profile_retirement: OK')
