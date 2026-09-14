from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected exactly one match, found {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1))


def append_new(path, content):
    p = Path(path)
    if p.exists():
        raise SystemExit(f'{path}: already exists')
    p.write_text(content)


# RUN config: explicit default-off no-TP mode, structured + flat compatibility.
replace_once(
    'uc_run_config.lua',
    "        enabled = false,\n        runes = {",
    "        enabled = false,\n        no_tp_mode = false,\n        runes = {",
)
replace_once(
    'uc_run_config.lua',
    "        out.enabled = bool(structured.enabled, out.enabled, 'config.tank.run.enabled')\n        local runes = type(structured.runes) == 'table' and structured.runes or {}",
    "        out.enabled = bool(structured.enabled, out.enabled, 'config.tank.run.enabled')\n        out.no_tp_mode = bool(structured.no_tp_mode, out.no_tp_mode, 'config.tank.run.no_tp_mode')\n        local runes = type(structured.runes) == 'table' and structured.runes or {}",
)
replace_once(
    'uc_run_config.lua',
    "        out.enabled = bool(flat_value(flat_source, 'run_tank_enabled'), out.enabled, 'run_tank_enabled')\n        out.runes.maintain = bool(flat_value(flat_source, 'run_tank_runes_maintain'), out.runes.maintain, 'run_tank_runes_maintain')",
    "        out.enabled = bool(flat_value(flat_source, 'run_tank_enabled'), out.enabled, 'run_tank_enabled')\n        out.no_tp_mode = bool(flat_value(flat_source, 'run_tank_no_tp_mode'), out.no_tp_mode, 'run_tank_no_tp_mode')\n        out.runes.maintain = bool(flat_value(flat_source, 'run_tank_runes_maintain'), out.runes.maintain, 'run_tank_runes_maintain')",
)

# RUN provider: Gambit/Rayke are enemy-targeted Effusions that require actual engagement.
replace_once(
    'uc_provider_run_tank.lua',
    "        if #desired == 3 and enemy then\n            local magic = cfg.magic_support or {}\n            for _, entry in ipairs({",
    "        if #desired == 3 and enemy then\n            local magic = cfg.magic_support or {}\n            if (magic.gambit or magic.rayke) and not engaged then\n                publish('waiting', 'RUN_MAGIC_SUPPORT_REQUIRES_ENGAGED', '', desired, observed)\n                return\n            end\n            for _, entry in ipairs({",
)

# Separate engagement requirements from front-arc requirements. Gambit/Rayke require
# engagement, but are intentionally legal while facing away.
Path('uc_scheduler_action_predicates.lua').write_text("""local M = {}\n\nlocal function action_name(name)\n\treturn tostring(name or ''):lower()\nend\n\nfunction M.ja_targets_enemy(ja)\n\tlocal targets = ja and ja.targets\n\tif type(targets) == 'string' then\n\t\treturn targets:find('Enemy', 1, true) ~= nil\n\tend\n\tif type(targets) == 'number' then\n\t\tlocal n = math.floor(targets)\n\t\treturn (n % 64) >= 32\n\tend\n\tif type(targets) == 'table' then\n\t\treturn targets.Enemy == true or targets.enemy == true\n\tend\n\treturn false\nend\n\nfunction M.ja_requires_engaged_front(name, ja)\n\tif (tonumber(ja and ja.id) or 0) == 46 then -- Shield Bash\n\t\treturn true\n\tend\n\treturn action_name(name) == 'shield bash'\nend\n\nfunction M.ja_requires_engaged(name, ja)\n\tif M.ja_requires_engaged_front(name, ja) then\n\t\treturn true\n\tend\n\tlocal normalized = action_name(name)\n\treturn normalized == 'gambit' or normalized == 'rayke'\nend\n\nreturn M\n""")

# Testable no-TP policy. It owns only the facing decision; engagement remains with
# the existing engage lane/manual player control.
append_new('uc_run_no_tp.lua', """local run_config = require('uc_run_config')\nlocal scheduler_config = require('uc_scheduler_config')\n\nlocal M = {}\n\nlocal function truthy(value)\n\tif value == true or value == 1 then return true end\n\tif type(value) == 'string' then\n\t\tlocal lowered = value:lower()\n\t\treturn lowered == 'true' or lowered == 'on' or lowered == '1' or lowered == 'yes'\n\tend\n\treturn false\nend\n\nlocal function valid_enemy(target)\n\treturn type(target) == 'table'\n\t\tand target.valid_target == true\n\t\tand tonumber(target.spawn_type) == 16\n\t\tand (tonumber(target.hpp) or 0) > 0\n\t\tand (tonumber(target.id) or 0) > 0\nend\n\nfunction M.enabled(settings, player)\n\tif type(player) ~= 'table' or tostring(player.main_job or '') ~= 'RUN' then\n\t\treturn false\n\tend\n\tif tonumber(player.status) ~= 1 then\n\t\treturn false\n\tend\n\tif not truthy(scheduler_config.tank_enabled(settings)) then\n\t\treturn false\n\tend\n\tlocal cfg = run_config.active(settings)\n\treturn cfg.enabled == true and cfg.no_tp_mode == true\nend\n\nfunction M.target_id(settings, player, target)\n\tif not M.enabled(settings, player) or not valid_enemy(target) then\n\t\treturn 0\n\tend\n\treturn tonumber(target.id) or 0\nend\n\nreturn M\n""")

# Scheduler readiness: engagement and front arc are independent mechanics.
replace_once(
    'unified_scheduler.lua',
    "local function ja_requires_engaged_front(name, ja)\n\treturn require('uc_scheduler_action_predicates').ja_requires_engaged_front(name, ja)\nend\n",
    "local function ja_requires_engaged_front(name, ja)\n\treturn require('uc_scheduler_action_predicates').ja_requires_engaged_front(name, ja)\nend\n\nlocal function ja_requires_engaged(name, ja)\n\treturn require('uc_scheduler_action_predicates').ja_requires_engaged(name, ja)\nend\n",
)
replace_once(
    'unified_scheduler.lua',
    "\tlocal requires_engaged_front = ja_requires_engaged_front(name, ja)\n\tif requires_engaged_front and status ~= 1 then\n\t\treturn false, 'BLOCK_JA_REQUIRES_ENGAGED'\n\tend",
    "\tlocal requires_engaged = ja_requires_engaged(name, ja)\n\tlocal requires_engaged_front = ja_requires_engaged_front(name, ja)\n\tif requires_engaged and status ~= 1 then\n\t\treturn false, 'BLOCK_JA_REQUIRES_ENGAGED'\n\tend",
)

# Give no-TP turns a truthful source label without changing existing callers.
replace_once(
    'unified_scheduler.lua',
    "p1_apply_face_to_target = function(settings, target_id, turn_away, force_face)",
    "p1_apply_face_to_target = function(settings, target_id, turn_away, force_face, source_override)",
)
replace_once(
    'unified_scheduler.lua',
    "\t\t\tsource = turn_away == true and 'unified_scheduler:reaction_turn_away' or 'unified_scheduler:T2.3c_darklaunch',",
    "\t\t\tsource = tostring(source_override or '') ~= ''\n\t\t\t\tand tostring(source_override)\n\t\t\t\tor (turn_away == true and 'unified_scheduler:reaction_turn_away' or 'unified_scheduler:T2.3c_darklaunch'),",
)

# Persistent movement-coordinator facing: once engaged, no-TP mode wins over the
# generic face-target option, but reaction movement/facing remains higher priority.
replace_once(
    'unified_scheduler.lua',
    "\tdo\n\t\tlocal t = windower.ffxi.get_mob_by_target('t')\n\t\tlocal tid = tonumber(t and t.id) or 0\n\t\tif tid > 0 then\n\t\t\tp1_apply_face_to_target(s, tid)\n\t\tend\n\tend\n\tlocal freeze_prep_until",
    "\tdo\n\t\tlocal t = windower.ffxi.get_mob_by_target('t')\n\t\tlocal tid = tonumber(t and t.id) or 0\n\t\tif tid > 0 then\n\t\t\tlocal no_tp_tid = require('uc_run_no_tp').target_id(s, p, t)\n\t\t\tif no_tp_tid > 0 then\n\t\t\t\tp1_apply_face_to_target(s, no_tp_tid, true, true, 'unified_scheduler:run_no_tp')\n\t\t\telse\n\t\t\t\tp1_apply_face_to_target(s, tid)\n\t\t\tend\n\t\tend\n\tend\n\tlocal freeze_prep_until",
)

# Combat dispatch also honors no-TP facing so Gambit/Rayke cannot momentarily
# turn the RUN back toward the mob when generic facing is enabled.
replace_once(
    'unified_scheduler.lua',
    "\tif not domain_ownership.is_enabled('combat') then\n\t\treturn false, nil\n\tend\n\tp1_apply_face_to_target(settings, tonumber(selected.target_id) or 0)\n\tlog_combat_sched",
    "\tif not domain_ownership.is_enabled('combat') then\n\t\treturn false, nil\n\tend\n\tdo\n\t\tlocal player = windower.ffxi.get_player()\n\t\tlocal current_target = windower.ffxi.get_mob_by_target('t')\n\t\tlocal no_tp_tid = require('uc_run_no_tp').target_id(settings, player, current_target)\n\t\tif no_tp_tid > 0 then\n\t\t\tp1_apply_face_to_target(settings, no_tp_tid, true, true, 'unified_scheduler:run_no_tp')\n\t\telse\n\t\t\tp1_apply_face_to_target(settings, tonumber(selected.target_id) or 0)\n\t\tend\n\tend\n\tlog_combat_sched",
)

# RUN provider/config regressions.
replace_once(
    'tests/replay/harness/selftest_run_tank.lua',
    "local normalized = run_config.normalize({\n    enabled = true,\n    runes =",
    "local normalized = run_config.normalize({\n    enabled = true,\n    no_tp_mode = true,\n    runes =",
)
replace_once(
    'tests/replay/harness/selftest_run_tank.lua',
    "assert_equal(#normalized.runes.desired, 3, 'rune count')",
    "assert_equal(#normalized.runes.desired, 3, 'rune count')\nassert_true(normalized.no_tp_mode, 'structured no-TP mode normalization')",
)
replace_once(
    'tests/replay/harness/selftest_run_tank.lua',
    "        enabled = true,\n        runes = { maintain = true, desired = { 'Tenebrae', 'Tenebrae', 'Tenebrae' } },",
    "        enabled = true,\n        no_tp_mode = true,\n        runes = { maintain = true, desired = { 'Tenebrae', 'Tenebrae', 'Tenebrae' } },",
)
replace_once(
    'tests/replay/harness/selftest_run_tank.lua',
    "assert_true(projected.enabled, 'projected tank_run mirror must preserve enabled=true')",
    "assert_true(projected.enabled, 'projected tank_run mirror must preserve enabled=true')\nassert_true(projected.no_tp_mode, 'projected tank_run mirror must preserve no-TP mode')",
)
replace_once(
    'tests/replay/harness/selftest_run_tank.lua',
    "ready.Foil = nil\n\nplayer.buffs[#player.buffs + 1] = 7201\nout = collect()\nassert_equal(out[1].action_name, 'Gambit', 'Gambit should precede Rayke')",
    "ready.Foil = nil\n\nplayer.buffs[#player.buffs + 1] = 7201\nplayer.status = 0\nsettings.ability_allow_unengaged = true\nout = collect()\nassert_equal(#out, 0, 'Gambit/Rayke must not be proposed while RUN is disengaged')\nassert_equal(_G.UC_RUN_TANK_STATUS.reason, 'RUN_MAGIC_SUPPORT_REQUIRES_ENGAGED', 'disengaged magic-support diagnostic')\nplayer.status = 1\nsettings.ability_allow_unengaged = false\nout = collect()\nassert_equal(out[1].action_name, 'Gambit', 'Gambit should precede Rayke once engaged')",
)

append_new('tests/replay/harness/selftest_run_no_tp_mode.lua', """package.path = './?.lua;./?/?.lua;' .. package.path\n\nlocal function assert_true(value, message) if value ~= true then error(message or 'expected true') end end\nlocal function assert_false(value, message) if value ~= false then error(message or 'expected false') end end\nlocal function assert_equal(actual, expected, message)\n    if actual ~= expected then error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual)) end\nend\nlocal function assert_contains(haystack, needle, message)\n    if not tostring(haystack):find(tostring(needle), 1, true) then error((message or 'missing text') .. ': ' .. tostring(needle)) end\nend\n\npackage.loaded.uc_scheduler_config = {\n    tank_enabled = function(settings) return settings and settings.tank end,\n}\n\nlocal no_tp = require('uc_run_no_tp')\nlocal predicates = require('uc_scheduler_action_predicates')\nlocal settings = {\n    tank = true,\n    tank_run = {\n        enabled = true,\n        no_tp_mode = true,\n        runes = { maintain = true, desired = {} },\n        foil = { enabled = true },\n        wards = {},\n        magic_support = {},\n    },\n}\nlocal player = { main_job = 'RUN', status = 1 }\nlocal enemy = { id = 99, valid_target = true, spawn_type = 16, hpp = 100 }\n\nassert_true(no_tp.enabled(settings, player), 'engaged RUN no-TP mode must activate')\nassert_equal(no_tp.target_id(settings, player, enemy), 99, 'no-TP target id')\nplayer.status = 0\nassert_false(no_tp.enabled(settings, player), 'disengaged RUN must not own no-TP facing')\nassert_equal(no_tp.target_id(settings, player, enemy), 0, 'disengaged no-TP target')\nplayer.status = 1\nplayer.main_job = 'PLD'\nassert_false(no_tp.enabled(settings, player), 'non-RUN must not own no-TP facing')\nplayer.main_job = 'RUN'\nsettings.tank = false\nassert_false(no_tp.enabled(settings, player), 'disabled tank automation must disable no-TP facing')\nsettings.tank = true\nsettings.tank_run.no_tp_mode = false\nassert_false(no_tp.enabled(settings, player), 'no-TP option defaults/acts off')\nsettings.tank_run.no_tp_mode = true\nassert_equal(no_tp.target_id(settings, player, { id = 99, valid_target = true, spawn_type = 16, hpp = 0 }), 0, 'dead target must not own facing')\n\nassert_true(predicates.ja_requires_engaged('Gambit', {}), 'Gambit requires engagement')\nassert_true(predicates.ja_requires_engaged('Rayke', {}), 'Rayke requires engagement')\nassert_false(predicates.ja_requires_engaged_front('Gambit', {}), 'Gambit does not require front arc')\nassert_false(predicates.ja_requires_engaged_front('Rayke', {}), 'Rayke does not require front arc')\nassert_true(predicates.ja_requires_engaged('Shield Bash', { id = 46 }), 'front-required JA also requires engagement')\nassert_true(predicates.ja_requires_engaged_front('Shield Bash', { id = 46 }), 'Shield Bash retains front requirement')\n\nlocal scheduler_source = assert(io.open('unified_scheduler.lua', 'r')):read('*a')\nassert_contains(scheduler_source, "local requires_engaged = ja_requires_engaged(name, ja)", 'scheduler must enforce engaged-only JA predicate')\nassert_contains(scheduler_source, "require('uc_run_no_tp').target_id(s, p, t)", 'movement coordinator must apply persistent no-TP facing')\nassert_contains(scheduler_source, "p1_apply_face_to_target(s, no_tp_tid, true, true, 'unified_scheduler:run_no_tp')", 'movement coordinator must turn RUN away')\nassert_contains(scheduler_source, "require('uc_run_no_tp').target_id(settings, player, current_target)", 'combat dispatch must honor no-TP facing')\n\nprint('RUN no-TP mode self-test: ok')\n""")

# UI/profile persistence.
replace_once(
    'UnifiedCombatWinForms/MainForm.ParityUi.cs',
    "    private CheckBox _runTankEnabled = null!;\n    private CheckBox _runRunesMaintain = null!;",
    "    private CheckBox _runTankEnabled = null!;\n    private CheckBox _runNoTpMode = null!;\n    private CheckBox _runRunesMaintain = null!;",
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ParityUi.cs',
    "        _runTankEnabled = new CheckBox { Text = \"Enable RUN automation\", AutoSize = true };\n        tankFlow.Controls.Add(_runTankEnabled);\n        var runeRow",
    "        _runTankEnabled = new CheckBox { Text = \"Enable RUN automation\", AutoSize = true };\n        tankFlow.Controls.Add(_runTankEnabled);\n        _runNoTpMode = new CheckBox { Text = \"No-TP mode (engaged + face away)\", AutoSize = true };\n        tankFlow.Controls.Add(_runNoTpMode);\n        var runeRow",
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ProfileStore.cs',
    "            [\"run_tank_enabled\"] = _runTankEnabled.Checked,\n            [\"run_tank_runes_maintain\"]",
    "            [\"run_tank_enabled\"] = _runTankEnabled.Checked,\n            [\"run_tank_no_tp_mode\"] = _runNoTpMode.Checked,\n            [\"run_tank_runes_maintain\"]",
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ProfileStore.cs',
    "            [\"run_tank_enabled\"] = false,\n            [\"run_tank_runes_maintain\"]",
    "            [\"run_tank_enabled\"] = false,\n            [\"run_tank_no_tp_mode\"] = false,\n            [\"run_tank_runes_maintain\"]",
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ParityLogic.cs',
    "            _runTankEnabled.Checked = false;\n            _runRunesMaintain.Checked = true;",
    "            _runTankEnabled.Checked = false;\n            _runNoTpMode.Checked = false;\n            _runRunesMaintain.Checked = true;",
)
replace_once(
    'UnifiedCombatWinForms/MainForm.ParityLogic.cs',
    "            _runTankEnabled.Checked = SessionStateHelper.GetBool(s, \"run_tank_enabled\", false);\n            _runRunesMaintain.Checked",
    "            _runTankEnabled.Checked = SessionStateHelper.GetBool(s, \"run_tank_enabled\", false);\n            _runNoTpMode.Checked = SessionStateHelper.GetBool(s, \"run_tank_no_tp_mode\", false);\n            _runRunesMaintain.Checked",
)
replace_once(
    'UnifiedCombatWinForms/StructuredProfileV2Writer.cs',
    "            .Add(\"enabled\", ReadBool(flatProfile, \"run_tank_enabled\", false))\n            .Add(\"runes\"",
    "            .Add(\"enabled\", ReadBool(flatProfile, \"run_tank_enabled\", false))\n            .Add(\"no_tp_mode\", ReadBool(flatProfile, \"run_tank_no_tp_mode\", false))\n            .Add(\"runes\"",
)
replace_once(
    'UnifiedCombatWinForms/RuntimeProfileEditorAdapter.cs',
    "        profile[\"run_tank_enabled\"] = RequiredValue(run, \"enabled\", \"tank_run.enabled\");\n        profile[\"run_tank_runes_maintain\"]",
    "        profile[\"run_tank_enabled\"] = RequiredValue(run, \"enabled\", \"tank_run.enabled\");\n        profile[\"run_tank_no_tp_mode\"] = run.TryGetPropertyValue(\"no_tp_mode\", out var noTpMode) && noTpMode is not null\n            ? noTpMode.DeepClone()\n            : JsonValue.Create(false);\n        profile[\"run_tank_runes_maintain\"]",
)

# C# persistence regression.
replace_once(
    'UnifiedCombatWinForms/RunTankProfileTests.cs',
    "            [\"run_tank_enabled\"] = true,\n            [\"run_tank_runes_maintain\"]",
    "            [\"run_tank_enabled\"] = true,\n            [\"run_tank_no_tp_mode\"] = true,\n            [\"run_tank_runes_maintain\"]",
)
replace_once(
    'UnifiedCombatWinForms/RunTankProfileTests.cs',
    "        AssertContains(lua, \"run = {\", \"RUN block\");\n        AssertContains(lua, \"desired = {\", \"rune list\");",
    "        AssertContains(lua, \"run = {\", \"RUN block\");\n        AssertContains(lua, \"no_tp_mode = true\", \"RUN no-TP serialization\");\n        AssertContains(lua, \"desired = {\", \"rune list\");",
)
replace_once(
    'UnifiedCombatWinForms/RunTankProfileTests.cs',
    "                [\"enabled\"] = true,\n                [\"runes\"] = new JsonObject",
    "                [\"enabled\"] = true,\n                [\"no_tp_mode\"] = true,\n                [\"runes\"] = new JsonObject",
)
replace_once(
    'UnifiedCombatWinForms/RunTankProfileTests.cs',
    "        AssertEqual(profile[\"run_tank_enabled\"]?.GetValue<bool>(), true, \"runtime RUN enabled\");\n        AssertEqual(profile[\"run_tank_runes_maintain\"]",
    "        AssertEqual(profile[\"run_tank_enabled\"]?.GetValue<bool>(), true, \"runtime RUN enabled\");\n        AssertEqual(profile[\"run_tank_no_tp_mode\"]?.GetValue<bool>(), true, \"runtime RUN no-TP mode\");\n        AssertEqual(profile[\"run_tank_runes_maintain\"]",
)

# Correct documentation of disengaged behavior and document no-TP semantics.
Path('docs/run_tank_automation.md').write_text("""# Rune Fencer tank automation\n\nRune Fencer tank automation extends the existing `combat` tank lane; it does not create a new scheduler domain.\n\n## Ownership\n\n- Existing `tank.enmity.actions` owns reactive enemy-target hate recovery such as `Flash`.\n- `tank.run` owns Rune Enchantments, proactive `Foil`, enabled RUN wards, and Gambit/Rayke sequencing.\n- Generic defensive buff maintenance continues to own ordinary enhancing magic such as Crusade and Phalanx.\n- Reactions continue to own encounter-triggered Liement, Elemental Sforzo, and similar emergency actions.\n- When RUN automation owns a JA, the generic configured-JA lane filters that JA so only one policy source can propose it.\n\n## Configuration\n\n```lua\ntank = {\n    enabled = true,\n    enmity = {\n        actions = { 'Flash' },\n    },\n    run = {\n        enabled = true,\n        no_tp_mode = false,\n        runes = {\n            maintain = true,\n            desired = { 'Ignis', 'Ignis', 'Ignis' },\n        },\n        foil = { enabled = true },\n        wards = {\n            vallation = true,\n            valiance = false,\n            pflug = true,\n            swordplay = false,\n            battuta = true,\n            one_for_all = false,\n        },\n        magic_support = {\n            gambit = true,\n            rayke = true,\n        },\n    },\n}\n```\n\nThe desired rune list must be empty or contain exactly three runes. Vallation and Valiance cannot both be enabled.\n\n`ability_allow_unengaged` may allow self-target RUN maintenance such as runes, wards, and Foil while the player is disengaged. **Gambit and Rayke require the RUN to be engaged with the enemy.** Their engagement requirement is independent of facing direction: both remain usable while the RUN is facing away from the mob.\n\n### Optional no-TP mode\n\n`no_tp_mode = true` keeps an already-engaged RUN facing away from the current live enemy target. The movement coordinator reapplies that facing policy every tick, and the combat dispatcher preserves it when sending RUN actions. This suppresses normal melee swings and therefore avoids ordinary melee TP feed while still allowing Foil, Gambit, and Rayke according to their normal readiness rules.\n\nNo-TP mode does **not** engage or disengage the player. Existing Auto Engage behavior or manual control remains responsible for entering combat. It is default-off, so normal facing behavior is unchanged unless explicitly enabled. Because the RUN is facing away, parrying is not available while the mode is actively holding that facing.\n\n## Ordering\n\nThe provider emits at most one RUN proposal per scheduler tick. Routine RUN work is priority band 94, immediately below existing tank-enmity recovery at band 96.\n\nThe policy order is:\n\n1. converge the configured rune stack;\n2. establish Vallation/Valiance and configured wards;\n3. maintain Foil once combat has a valid enemy target (or while already engaged);\n4. once engaged, use Gambit, then rebuild consumed runes;\n5. once engaged, use Rayke, then rebuild consumed runes.\n\nLiement suppresses Vallation/Valiance restoration while Liement is active.\n\n## Deliberate v1 exclusions\n\nLunge and Swipe are not automated. Exact mixed-rune consumption ordering is therefore not part of the v1 contract. Rune convergence is based on observed player buff slots and fails closed if a configured rune status cannot be resolved.\n\nRuntime diagnostics are published at `_G.UC_RUN_TANK_STATUS`.\n""")

# Expand Zerde #3 rather than opening a new issue.
tracker = Path('docs/zerde_uc_issue_tracker.md')
text = tracker.read_text()
text = text.replace(
    "| 3 | RUN Foil dispatch/ack failure | READY FOR REVIEW | Root cause was invalid structured metadata for combat self-spells: Foil's player target id was dropped before dispatcher validation. |",
    "| 3 | RUN Foil dispatch + no-TP RUN mode | READY FOR REVIEW | Fixes Foil self-spell dispatch, corrects Gambit/Rayke engagement semantics, and adds optional engaged-facing-away no-TP mode. |",
)
text = text.replace(
    "## 3. RUN Foil dispatch/ack failure",
    "## 3. RUN Foil dispatch + no-TP RUN mode",
)
old_scope = """### In-game acceptance\n\nA small RUN validation against any normal target is sufficient; another full Zerde attempt is not required. Expected result: when Foil is missing and ready, Niightsiide sends one real self-targeted Foil cast with a normal cast-start/completion lifecycle, after which Gambit/Rayke remain reachable according to readiness and priority.\n"""
new_scope = """### Corrected RUN engagement/facing mechanics\n\nFollow-up in-game verification established that Gambit and Rayke cannot be used while the RUN is disengaged. The earlier RUN design and documentation incorrectly allowed those enemy-targeted Effusions whenever a valid enemy was selected. They **can**, however, be used while the RUN is engaged and facing away from the enemy.\n\nIssue #3 therefore also includes the smallest general correction:\n\n- Gambit and Rayke require true player engagement before readiness/proposal.\n- Their engagement requirement is separate from front-arc requirements; facing away must not block them.\n- Optional `tank.run.no_tp_mode` keeps an engaged RUN persistently facing away from the current live enemy, suppressing normal melee swings/TP feed.\n- No-TP mode does not own engagement; Auto Engage or manual control still enters combat.\n- No-TP mode is default-off and must not alter normal facing when disabled.\n- While facing away, the RUN cannot parry; no-TP mode intentionally trades that defensive benefit for reduced melee TP feed.\n\n### In-game acceptance\n\nA small RUN validation against any normal target is sufficient; another full Zerde attempt is not required. Expected results:\n\n1. missing/ready Foil produces one real self-targeted cast with a normal lifecycle;\n2. Gambit/Rayke are not proposed while Niightsiide is disengaged;\n3. with no-TP mode enabled and Niightsiide engaged, UC keeps him facing away;\n4. Gambit/Rayke still execute while that away-facing is held;\n5. disabling no-TP mode restores ordinary facing behavior.\n"""
if old_scope not in text:
    raise SystemExit('tracker in-game acceptance block not found')
text = text.replace(old_scope, new_scope, 1)
tracker.write_text(text)

print('Zerde issue #3 no-TP patch applied')
