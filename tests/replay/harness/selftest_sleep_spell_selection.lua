local scheduler_path = "unified_scheduler.lua"
local settings_path = "UnifiedCombat.lua"
local bridge_path = "remote_bridge.lua"
local runtime_overrides_path = "uc_runtime_overrides.lua"
local ui_logic_path = "UnifiedCombatWinForms/MainForm.ParityLogic.cs"
local ui_store_path = "UnifiedCombatWinForms/MainForm.ProfileStore.cs"
local ui_layout_path = "UnifiedCombatWinForms/MainForm.ParityUi.cs"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local function sleep_spell_list_from_settings(settings)
    local out = {}
    local seen = {}
    local function append_spell(raw)
        local spell_name = tostring(raw or ""):match("^%s*(.-)%s*$") or ""
        if spell_name == "" then
            return
        end
        local key = spell_name:lower()
        if seen[key] == true then
            return
        end
        seen[key] = true
        out[#out + 1] = spell_name
    end
    local list = settings and settings.sleepspells or nil
    if type(list) == "table" then
        for i = 1, #list do
            append_spell(list[i])
        end
    elseif type(list) == "string" then
        append_spell(list)
    end
    if #out == 0 then
        append_spell(settings and settings.sleepspell or "")
    end
    return out
end

local function select_sleep_spell_for_target(settings, target, spell_state)
    local sleep_max_target_distance = 6.0
    if type(target) ~= "table" or (tonumber(target.id) or 0) <= 0 then
        return nil, "SLEEP_BAD_TARGET"
    end
    local dist = tonumber(target.dist) or 999
    if dist > sleep_max_target_distance then
        return nil, "SLEEP_NO_AVAILABLE_SPELL"
    end
    local sleep_spells = sleep_spell_list_from_settings(settings)
    for index, spell_name in ipairs(sleep_spells) do
        local state = spell_state[spell_name] or {}
        local ready = state.ready == true
        local range_max = tonumber(state.range_max) or 0
        local effective_max = math.min(range_max, sleep_max_target_distance)
        if ready and effective_max > 0 and dist <= effective_max then
            return {
                name = spell_name,
                index = index,
                range_max = effective_max,
                dist = dist,
            }, ""
        end
    end
    return nil, "SLEEP_NO_AVAILABLE_SPELL"
end

local function main()
    local scheduler_source = read_file(scheduler_path)
    local settings_source = read_file(settings_path)
    local bridge_source = read_file(bridge_path)
    local runtime_overrides_source = read_file(runtime_overrides_path)
    local ui_logic_source = read_file(ui_logic_path)
    local ui_store_source = read_file(ui_store_path)
    local ui_layout_source = read_file(ui_layout_path)

    assert_contains(settings_source, "sleepspells = { 'Horde Lullaby II' },", "settings defaults must persist a sleep spell list")
    assert_contains(settings_source, "local function uc_normalize_sleep_spell_list(s)", "settings must normalize ordered sleep spell lists")
    assert_contains(settings_source, "_G.UC_SleepSpell = uc_sleep_spell", "Sleep UI and commands must share one sleep spell helper surface")
    assert_contains(settings_source, "s.sleepspell = out[1] or ''", "legacy sleepspell field must mirror the primary list spell")
    assert_contains(scheduler_source, "function scheduler.sleep_spell_list_from_settings(settings)", "scheduler must read ordered sleep spell lists from settings")
    assert_contains(scheduler_source, "return runtime_overrides.sleep_spell_names(settings)", "scheduler sleep spell list must route through runtime overrides")
    assert_contains(runtime_overrides_source, "if #out == 0 then", "runtime override helper must keep legacy single-value migration path")
    assert_contains(runtime_overrides_source, "return normalize_name_list(rawget(s, 'sleepspells'), rawget(s, 'sleepspell'))", "runtime override helper must backfill from legacy sleepspell compatibility keys")
    assert_contains(scheduler_source, "scheduler.SLEEP_MAX_TARGET_DISTANCE = 6.0", "scheduler must document the hard 6-yalm Sleep boundary")
    assert_contains(scheduler_source, "function scheduler.select_sleep_spell_for_target(settings, target)", "scheduler must select the first available sleep spell per target")
    assert_contains(scheduler_source, "if effective_max_range <= 0 or effective_max_range > scheduler.SLEEP_MAX_TARGET_DISTANCE then", "Sleep spell selection must clamp cast range to the hard Sleep boundary")
    assert_contains(scheduler_source, "ready_reason = 'SLEEP_OUT_OF_RANGE'", "sleep selection must reject out-of-range spells before moving to the next choice")
    assert_contains(bridge_source, "op == 'sleep_replace_spells'", "remote bridge must support replacing the ordered Sleep spell list from the UI")
    assert_contains(bridge_source, "op == 'sleep_add_spell'", "remote bridge must support UI add-by-name Sleep edits")
    assert_contains(bridge_source, "op == 'sleep_remove_spell'", "remote bridge must support UI remove Sleep edits")
    assert_contains(bridge_source, "op == 'sleep_move_spell'", "remote bridge must support UI reordering Sleep edits")
    assert_contains(ui_layout_source, "Sleep spells — ordered list used for pre-engage and in-combat Sleep picks.", "UI must expose a visible ordered Sleep spell list")
    assert_contains(ui_logic_source, "Forward(sid, new Dictionary<string, object?> { [\"op\"] = \"sleep_replace_spells\"", "UI full-state pushes must write the ordered Sleep spell list")
    assert_contains(ui_logic_source, "private void SleepSpellMove(string direction)", "UI must support ordered Sleep spell reordering")
    assert_contains(ui_store_source, "[\"sleep_spell_entries\"]", "UI profile persistence must store Sleep spell list entries")

    local migrated = sleep_spell_list_from_settings({
        sleepspell = "Sleep II",
    })
    assert_equal(#migrated, 1, "legacy single sleep spell must migrate to a one-entry list")
    assert_equal(migrated[1], "Sleep II", "legacy sleep spell migration must preserve order")

    local deduped = sleep_spell_list_from_settings({
        sleepspells = { "Sleep II", "Sleep", "Sleep II", "Repose" },
        sleepspell = "Horde Lullaby II",
    })
    assert_equal(#deduped, 3, "sleep spell list must dedupe repeated entries")
    assert_equal(deduped[1], "Sleep II", "first configured sleep spell must stay first")
    assert_equal(deduped[2], "Sleep", "second configured sleep spell must stay second")
    assert_equal(deduped[3], "Repose", "third configured sleep spell must stay third")

    local target = { id = 77, dist = 5.5 }
    local chosen = select_sleep_spell_for_target({
        sleepspells = { "Sleep II", "Sleep", "Repose" },
    }, target, {
        ["Sleep II"] = { ready = false, range_max = 21 },
        ["Sleep"] = { ready = true, range_max = 21 },
        ["Repose"] = { ready = true, range_max = 21 },
    })
    assert_equal(chosen.name, "Sleep", "first unavailable spell must fall through to the next ready spell")

    chosen = select_sleep_spell_for_target({
        sleepspells = { "Sleep II", "Sleep" },
    }, { id = 78, dist = 5.5 }, {
        ["Sleep II"] = { ready = true, range_max = 5 },
        ["Sleep"] = { ready = true, range_max = 21 },
    })
    assert_equal(chosen.name, "Sleep", "out-of-range first spell must fall through to the next in-range spell")

    chosen = select_sleep_spell_for_target({
        sleepspells = { "Sleep II", "Sleep" },
    }, { id = 79, dist = 6.01 }, {
        ["Sleep II"] = { ready = true, range_max = 21 },
        ["Sleep"] = { ready = true, range_max = 21 },
    })
    assert_equal(chosen, nil, "target beyond 6 yalms must not select any Sleep spell even when spell range is longer")

    chosen = select_sleep_spell_for_target({
        sleepspells = { "Sleep II", "Repose" },
    }, { id = 80, dist = 5.5 }, {
        ["Sleep II"] = { ready = false, range_max = 21 },
        ["Repose"] = { ready = false, range_max = 21 },
    })
    assert_equal(chosen, nil, "no available configured sleep spell must produce no sleep cast")

    chosen = select_sleep_spell_for_target({
        sleepspell = "Sleep II",
    }, { id = 55, dist = 5 }, {
        ["Sleep II"] = { ready = true, range_max = 21 },
    })
    assert_true(type(chosen) == "table", "legacy single-value sleep spell must still be selectable")
    assert_equal(chosen.name, "Sleep II", "legacy single-value sleep spell must remain the chosen action")

    io.stdout:write("selftest_sleep_spell_selection: OK\n")
end

main()
