from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch(rel, old, new, count=1):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    found = text.count(old)
    if found != count:
        raise RuntimeError(f"{rel}: expected {count} match(es), found {found}")
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")
    print("patched", rel)


def write(rel, content):
    path = ROOT / rel
    if path.exists() and path.read_text(encoding="utf-8") != content:
        raise RuntimeError(f"{rel}: already exists with different content")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    print("wrote", rel)


policy = '''local M = {}

local aliases = {
    ['paralyze'] = 'paralysis',
    ['blindness'] = 'blind',
}

function M.normalize_key(value)
    local key = tostring(value or ''):lower():gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', '_')
    return aliases[key] or key
end

local function append_unique(policy, value)
    local key = M.normalize_key(value)
    if key == '' or policy.ranks[key] ~= nil then return end
    local rank = #policy.ordered
    policy.ordered[#policy.ordered + 1] = key
    policy.ranks[key] = rank
end

function M.build(enabled, raw)
    local policy = { enabled = enabled == true, ordered = {}, ranks = {} }
    if not policy.enabled then return policy end
    if type(raw) == 'table' then
        for i = 1, #raw do append_unique(policy, raw[i]) end
    elseif type(raw) == 'string' then
        for entry in raw:gmatch('[^|]+') do append_unique(policy, entry) end
    end
    return policy
end

function M.rank(policy, status_key)
    if type(policy) ~= 'table' or policy.enabled ~= true then return nil end
    return policy.ranks[M.normalize_key(status_key)]
end

function M.candidate_priority(policy, status_key, member_priority)
    local rank = M.rank(policy, status_key)
    if rank == nil then return nil end
    return (rank * 10) + (tonumber(member_priority) or 5)
end

return M
'''
write('uc_status_removal_policy.lua', policy)

# Runtime scheduler.
patch('unified_scheduler.lua',
"local sleep_status = require('uc_sleep_status')\nsleep_status.validate_resources(res.buffs)",
"local sleep_status = require('uc_sleep_status')\nlocal status_removal_policy = require('uc_status_removal_policy')\nsleep_status.validate_resources(res.buffs)")
patch('unified_scheduler.lua',
"\tlocal ignore_trusts = bool_setting(scheduler.active_value_or_flat('config.defensive.cure.ignore_trusts', s.def_heal_ignore_trusts), true)\n\n\tif bool_setting(scheduler.active_value_or_flat('config.defensive.buffs.enabled', s.defensive_buff_enabled), true) then",
"\tlocal ignore_trusts = bool_setting(scheduler.active_value_or_flat('config.defensive.cure.ignore_trusts', s.def_heal_ignore_trusts), true)\n\tlocal na_limit_policy = status_removal_policy.build(\n\t\tbool_setting(scheduler.active_value_or_flat('config.defensive.na.limit_enabled', s.defensive_na_limit_enabled), false),\n\t\tscheduler.active_value_or_flat('config.defensive.na.status_priority', s.defensive_na_status_priority)\n\t)\n\n\tif bool_setting(scheduler.active_value_or_flat('config.defensive.buffs.enabled', s.defensive_buff_enabled), true) then")
patch('unified_scheduler.lua',
"\t\t\t\t\t\tlocal key = normalize_status_removal_key(debuff)\n\t\t\t\t\t\tlocal action_prio = status_removal_priority[key] or 5\n\t\t\t\t\t\tif (not best) or action_prio < best.action_prio then\n\t\t\t\t\t\t\tbest = {\n\t\t\t\t\t\t\t\tspell = na_spell,\n\t\t\t\t\t\t\t\tbuff_id = buff_id,\n\t\t\t\t\t\t\t\taction_prio = action_prio,\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\tend",
"\t\t\t\t\t\tlocal key = normalize_status_removal_key(debuff)\n\t\t\t\t\t\tlocal action_prio = na_limit_policy.enabled\n\t\t\t\t\t\t\tand status_removal_policy.rank(na_limit_policy, key)\n\t\t\t\t\t\t\tor (status_removal_priority[key] or 5)\n\t\t\t\t\t\tif action_prio ~= nil and ((not best) or action_prio < best.action_prio) then\n\t\t\t\t\t\t\tbest = {\n\t\t\t\t\t\t\t\tspell = na_spell,\n\t\t\t\t\t\t\t\tbuff_id = buff_id,\n\t\t\t\t\t\t\t\taction_prio = action_prio,\n\t\t\t\t\t\t\t\tstatus_key = key,\n\t\t\t\t\t\t\t\tlimited_na = na_limit_policy.enabled,\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\tend")
patch('unified_scheduler.lua',
"\t\t\tif best then\n\t\t\t\tlocal p = member_priority(m)\n\t\t\t\tlocal d = {\n\t\t\t\t\ttype = 'debuff',\n\t\t\t\t\tspell = best.spell,\n\t\t\t\t\ttarget = m,\n\t\t\t\t\tbuff_id = best.buff_id,\n\t\t\t\t\tprio = pri_default(p, best.action_prio),\n\t\t\t\t}\n\t\t\t\tif not out.debuff or d.prio < out.debuff.prio then\n\t\t\t\t\tout.debuff = d\n\t\t\t\tend\n\t\t\tend",
"\t\t\tif best then\n\t\t\t\tlocal p = member_priority(m)\n\t\t\t\tlocal selected_prio = pri_default(p, best.action_prio)\n\t\t\t\tif na_limit_policy.enabled then\n\t\t\t\t\tselected_prio = status_removal_policy.candidate_priority(na_limit_policy, best.status_key, p)\n\t\t\t\tend\n\t\t\t\tlocal d = {\n\t\t\t\t\ttype = 'debuff',\n\t\t\t\t\tspell = best.spell,\n\t\t\t\t\ttarget = m,\n\t\t\t\t\tbuff_id = best.buff_id,\n\t\t\t\t\tstatus_key = best.status_key,\n\t\t\t\t\tstatus_priority = best.action_prio,\n\t\t\t\t\tlimited_na = best.limited_na == true,\n\t\t\t\t\tprio = selected_prio,\n\t\t\t\t}\n\t\t\t\tif not out.debuff or d.prio < out.debuff.prio then\n\t\t\t\t\tout.debuff = d\n\t\t\t\tend\n\t\t\tend")
patch('unified_scheduler.lua',
"\tif c.debuff and c.debuff.spell == 'Paralyna' and c.debuff.target.is_self then",
"\tif c.debuff and c.debuff.limited_na == true then\n\t\tif c.cure and cure_is_critical(c.cure) then\n\t\t\treturn c.cure, 'BLOCK_DEFENSIVE_CURE_CRITICAL'\n\t\tend\n\t\treturn c.debuff, 'BLOCK_DEFENSIVE_NA_LIMIT'\n\tend\n\tif c.debuff and c.debuff.spell == 'Paralyna' and c.debuff.target.is_self then")

# Canonical config and compatibility fields.
patch('uc_config_normalizer.lua',
"            na = {\n                enabled = false,\n            },",
"            na = {\n                enabled = false,\n                limit_enabled = false,\n                status_priority = {},\n            },")
patch('uc_config_normalizer.lua',
"        local na = is_table(nested.na) and nested.na or {}\n        defensive.na.enabled = normalize_boolean(na.enabled, defensive.na.enabled)",
"        local na = is_table(nested.na) and nested.na or {}\n        defensive.na.enabled = normalize_boolean(na.enabled, defensive.na.enabled)\n        defensive.na.limit_enabled = normalize_boolean(na.limit_enabled, defensive.na.limit_enabled)\n        defensive.na.status_priority = normalize_pipe_string_list(na.status_priority, defensive.na.status_priority)")
patch('uc_config_normalizer.lua',
"        defensive.na.enabled = normalize_boolean(first_path(source, { path('defensive_na_enabled') }), defensive.na.enabled)",
"        defensive.na.enabled = normalize_boolean(first_path(source, { path('defensive_na_enabled') }), defensive.na.enabled)\n        defensive.na.limit_enabled = normalize_boolean(first_path(source, { path('defensive_na_limit_enabled') }), defensive.na.limit_enabled)\n        defensive.na.status_priority = normalize_pipe_string_list(first_path(source, { path('defensive_na_status_priority') }), defensive.na.status_priority)")
patch('uc_active_config.lua',
"\t\tif type(config.defensive.na) == 'table' then\n\t\t\tcandidate.defensive_na_enabled = config.defensive.na.enabled\n\t\tend",
"\t\tif type(config.defensive.na) == 'table' then\n\t\t\tcandidate.defensive_na_enabled = config.defensive.na.enabled\n\t\t\tcandidate.defensive_na_limit_enabled = config.defensive.na.limit_enabled\n\t\t\tlocal status_priority = config.defensive.na.status_priority\n\t\t\tcandidate.defensive_na_status_priority = type(status_priority) == 'table' and table.concat(status_priority, '|') or tostring(status_priority or '')\n\t\tend")
patch('UnifiedCombat.lua',
"\t\tdefensive_na_enabled = false,\n\t\tdefensive_buff_enabled = false,",
"\t\tdefensive_na_enabled = false,\n\t\tdefensive_na_limit_enabled = false,\n\t\tdefensive_na_status_priority = '',\n\t\tdefensive_buff_enabled = false,")
patch('melee_engine.lua',
"default.defensive_na_enabled = true\ndefault.defensive_buff_enabled = true",
"default.defensive_na_enabled = true\ndefault.defensive_na_limit_enabled = false\ndefault.defensive_na_status_priority = ''\ndefault.defensive_buff_enabled = true")
patch('uc_profile_contract.lua',
"    defensive_na_enabled = \"profile_owned_by_ui\",\n    defensive_buff_enabled = \"profile_owned_by_ui\",",
"    defensive_na_enabled = \"profile_owned_by_ui\",\n    defensive_na_limit_enabled = \"profile_owned_by_ui\",\n    defensive_na_status_priority = \"profile_owned_by_ui\",\n    defensive_buff_enabled = \"profile_owned_by_ui\",")

# WinForms UI and profile-v2 serialization.
patch('UnifiedCombatWinForms/HubUiConstants.cs',
'        "defensive_na_enabled",\n        "defensive_buff_enabled",',
'        "defensive_na_enabled",\n        "defensive_na_limit_enabled",\n        "defensive_buff_enabled",', count=2)
patch('UnifiedCombatWinForms/HubUiConstants.cs',
'        ["defensive_na_enabled"] = "Allow NA/Status Removal",\n        ["defensive_buff_enabled"] = "Allow Buff Support",',
'        ["defensive_na_enabled"] = "Allow NA/Status Removal",\n        ["defensive_na_limit_enabled"] = "Limit NA/Status Removal",\n        ["defensive_buff_enabled"] = "Allow Buff Support",')
patch('UnifiedCombatWinForms/MainForm.ParityUi.cs',
'    private TextBox _defOverwrite = null!;\n    private TextBox _defBuffs = null!;',
'    private TextBox _defOverwrite = null!;\n    private TextBox _defNaStatusPriority = null!;\n    private TextBox _defBuffs = null!;')
patch('UnifiedCombatWinForms/MainForm.ParityUi.cs',
'        _defHealIgnoreTrusts.CheckedChanged += (_, _) => OnDefThresholdChanged();\n        rightCol.Controls.Add(_defHealIgnoreTrusts, 1, dr);\n        dr++;\n        rightCol.Controls.Add(new Label { Text = "Buff Refresh Interval", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);',
'        _defHealIgnoreTrusts.CheckedChanged += (_, _) => OnDefThresholdChanged();\n        rightCol.Controls.Add(_defHealIgnoreTrusts, 1, dr);\n        dr++;\n        rightCol.Controls.Add(new Label { Text = "NA Status Priority", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);\n        _defNaStatusPriority = new TextBox { Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top, MinimumSize = new Size(80, 23), PlaceholderText = "Poison|Paralyze|Dia" };\n        _defNaStatusPriority.Leave += (_, _) => OnDefThresholdChanged();\n        rightCol.Controls.Add(_defNaStatusPriority, 1, dr);\n        dr++;\n        rightCol.Controls.Add(new Label { Text = "Buff Refresh Interval", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);')
patch('UnifiedCombatWinForms/MainForm.ParityLogic.cs',
'            _defCrit.Text = "35";\n            _defMed.Text = "55";\n            _defOverwrite.Text = "150";',
'            _defCrit.Text = "35";\n            _defMed.Text = "55";\n            _defNaStatusPriority.Text = "";\n            _defOverwrite.Text = "150";')
patch('UnifiedCombatWinForms/MainForm.ParityLogic.cs',
'            _defHealIgnoreTrusts.Checked = SessionStateHelper.GetBool(s, "def_heal_ignore_trusts", true);\n            _defOverwrite.Text = SessionStateHelper.GetString(s, "defensive_overwrite_interval", "150");',
'            _defHealIgnoreTrusts.Checked = SessionStateHelper.GetBool(s, "def_heal_ignore_trusts", true);\n            _defNaStatusPriority.Text = SessionStateHelper.GetString(s, "defensive_na_status_priority");\n            _defOverwrite.Text = SessionStateHelper.GetString(s, "defensive_overwrite_interval", "150");')
patch('UnifiedCombatWinForms/MainForm.ParityLogic.cs',
'        var ignoreTrusts = _defHealIgnoreTrusts.Checked;\n\n        if (med < crit)',
'        var ignoreTrusts = _defHealIgnoreTrusts.Checked;\n        var naPriorityClean = string.Join("|", (_defNaStatusPriority.Text ?? "").Split(\'|\').Select(x => x.Trim()).Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase));\n\n        if (med < crit)')
patch('UnifiedCombatWinForms/MainForm.ParityLogic.cs',
'        _defHealMinMissingHp.Text = healMinMissingHp.ToString();\n        _defOverwrite.Text = overwrite.ToString();',
'        _defHealMinMissingHp.Text = healMinMissingHp.ToString();\n        _defNaStatusPriority.Text = naPriorityClean;\n        _defOverwrite.Text = overwrite.ToString();')
patch('UnifiedCombatWinForms/MainForm.ParityLogic.cs',
'        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_ignore_trusts", ["value"] = ignoreTrusts ? "on" : "off" });\n        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_overwrite_interval", ["value"] = overwrite });',
'        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_ignore_trusts", ["value"] = ignoreTrusts ? "on" : "off" });\n        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_na_status_priority", ["value"] = naPriorityClean });\n        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_overwrite_interval", ["value"] = overwrite });')
patch('UnifiedCombatWinForms/MainForm.ProfileStore.cs',
'            ["def_heal_ignore_trusts"] = _defHealIgnoreTrusts.Checked,\n            ["defensive_overwrite_interval"] = ParseInt(_defOverwrite.Text, 150),',
'            ["def_heal_ignore_trusts"] = _defHealIgnoreTrusts.Checked,\n            ["defensive_na_status_priority"] = _defNaStatusPriority.Text ?? "",\n            ["defensive_overwrite_interval"] = ParseInt(_defOverwrite.Text, 150),')
patch('UnifiedCombatWinForms/MainForm.ProfileStore.cs',
'            ["def_heal_ignore_trusts"] = true,\n            ["defensive_overwrite_interval"] = 150,',
'            ["def_heal_ignore_trusts"] = true,\n            ["defensive_na_status_priority"] = "",\n            ["defensive_overwrite_interval"] = 150,')
patch('UnifiedCombatWinForms/StructuredProfileV2Writer.cs',
'            .Add("na", new StructuredProfileNode().Add("enabled", ReadBool(flatProfile, "defensive_na_enabled", false)))',
'            .Add("na", new StructuredProfileNode()\n                .Add("enabled", ReadBool(flatProfile, "defensive_na_enabled", false))\n                .Add("limit_enabled", ReadBool(flatProfile, "defensive_na_limit_enabled", false))\n                .Add("status_priority", SplitPipeList(ReadString(flatProfile, "defensive_na_status_priority", ""))))')

# Focused runtime regression test.
test = '''local function ok(v, m) if not v then error(m or 'assertion failed') end end
local function eq(a, b, m) if a ~= b then error((m or 'not equal') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end end
local policy = dofile('uc_status_removal_policy.lua')
local p = policy.build(true, ' Poison | Paralyze | Dia | poison ')
eq(policy.rank(p, 'poison'), 0, 'Poison priority')
eq(policy.rank(p, 'paralysis'), 1, 'Paralyze alias')
eq(policy.rank(p, 'Dia'), 2, 'Dia priority')
eq(policy.rank(p, 'attack_down'), nil, 'unlisted Attack Down must be ignored')
ok(policy.candidate_priority(p, 'poison', 5) < policy.candidate_priority(p, 'paralysis', 1), 'status priority must outrank member priority')
local empty = policy.build(true, '')
eq(policy.rank(empty, 'poison'), nil, 'empty limited list removes nothing')
local src = assert(io.open('unified_scheduler.lua', 'r')):read('*a')
ok(src:find("action_prio = na_limit_policy.enabled", 1, true) ~= nil, 'scheduler allowlist integration missing')
ok(src:find("status_removal_policy.candidate_priority", 1, true) ~= nil, 'scheduler absolute status priority integration missing')
ok(src:find("BLOCK_DEFENSIVE_CURE_CRITICAL", 1, true) ~= nil, 'critical Cure override missing')
ok(src:find("BLOCK_DEFENSIVE_NA_LIMIT", 1, true) ~= nil, 'limited NA precedence missing')
io.stdout:write('selftest_defensive_na_status_limit: OK\\n')
'''
write('tests/replay/harness/selftest_defensive_na_status_limit.lua', test)
patch('tests/replay/harness/selftest_all_replay_fixtures.lua',
'    "tests/replay/harness/selftest_defensive_cure_priority.lua",\n\t"tests/replay/harness/selftest_charm_sleeper.lua",',
'    "tests/replay/harness/selftest_defensive_cure_priority.lua",\n    "tests/replay/harness/selftest_defensive_na_status_limit.lua",\n\t"tests/replay/harness/selftest_charm_sleeper.lua",')

print('status removal priority limiter applied')
