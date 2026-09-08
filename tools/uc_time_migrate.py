from pathlib import Path
import re

root = Path('.')

uc_time = r'''local M = {}

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

function M.now()
    if type(M.gettime) ~= 'function' then
        error('uc_time requires LuaSocket socket.gettime')
    end
    return M.gettime()
end

return M
'''
(root / 'uc_time.lua').write_text(uc_time, encoding='utf-8')

runtime_parse = root / 'tests/replay/harness/selftest_runtime_parse.lua'
text = runtime_parse.read_text(encoding='utf-8')
if '"uc_time.lua"' not in text:
    marker = '    "skills.lua",\n'
    if marker not in text:
        raise SystemExit('runtime parse insertion marker not found')
    text = text.replace(marker, marker + '    "uc_time.lua",\n', 1)
    runtime_parse.write_text(text, encoding='utf-8')

raw_helper = re.compile(
    r"local function (?P<name>uc_now_s|now_s)\(\)\n"
    r"\tlocal s = rawget\(_G, 'socket'\)\n"
    r"\tif type\(s\) ~= 'table' or type\(s\.gettime\) ~= 'function' then\n"
    r"\t\tlocal ok, mod = pcall\(require, 'socket'\)\n"
    r"\t\tif ok then\n"
    r"\t\t\ts = mod\n"
    r"\t\tend\n"
    r"\tend\n"
    r"\tif type\(s\) ~= 'table' or type\(s\.gettime\) ~= 'function' then\n"
    r"\t\terror\('[^']*socket\.gettime[^']*'\)\n"
    r"\tend\n"
    r"\treturn s\.gettime\(\)\n"
    r"end"
)

runtime_source = runtime_parse.read_text(encoding='utf-8')
block = re.search(r'local RUNTIME_LUA_FILES\s*=\s*\{(.*?)\n\}', runtime_source, re.S)
if not block:
    raise SystemExit('could not parse runtime file list')
runtime_files = re.findall(r'["\']([^"\']+\.lua)["\']', block.group(1))

generic_changed = []
for rel in runtime_files:
    if rel == 'uc_time.lua':
        continue
    path = root / rel
    if not path.exists():
        continue
    src = path.read_text(encoding='utf-8')
    def repl(match):
        return "local function %s()\n\treturn require('uc_time').now()\nend" % match.group('name')
    new, count = raw_helper.subn(repl, src)
    if count:
        path.write_text(new, encoding='utf-8')
        generic_changed.append((rel, count))

socket_decl = re.compile(
    r"local socket_ok, socket_mod = pcall\(require, 'socket'\)\n"
    r"local socket_gettime = [^\n]*(?:\n\tor nil)?\n"
)
socket_decl_files = [
    'unified_engine.lua',
    'unified_scheduler.lua',
    'uc_geo_packet_trace.lua',
    'uc_hb_buff_maint.lua',
    'uc_party_follow.lua',
]
for rel in socket_decl_files:
    path = root / rel
    src = path.read_text(encoding='utf-8')
    replacement = "local uc_time = require('uc_time')\nlocal socket_gettime = uc_time.gettime\n"
    new, count = socket_decl.subn(replacement, src, count=1)
    if count != 1:
        raise SystemExit(f'{rel}: expected one socket_gettime declaration, got {count}')
    path.write_text(new, encoding='utf-8')

nyzul = root / 'uc_nyzul_runtime.lua'
src = nyzul.read_text(encoding='utf-8')
old = "local function next_token()\n\tlocal socket = require('socket')\n\treturn ('%s:%d'):format(name_key(player_name()), math.floor(socket.gettime() * 1000))\nend"
new = "local function next_token()\n\treturn ('%s:%d'):format(name_key(player_name()), math.floor(require('uc_time').now() * 1000))\nend"
if old not in src:
    raise SystemExit('uc_nyzul_runtime.lua next_token socket source not found')
nyzul.write_text(src.replace(old, new, 1), encoding='utf-8')

core = root / 'unified_combat_core.lua'
src = core.read_text(encoding='utf-8')
if "local uc_time = require('uc_time')" not in src:
    marker = "local uc_skillchain_state = require('uc_skillchain_state')\n"
    if marker not in src:
        raise SystemExit('unified_combat_core uc_skillchain_state marker not found')
    src = src.replace(marker, marker + "local uc_time = require('uc_time')\n", 1)
legacy_guard = "if type(os.clock) ~= 'function' then\n\terror('unified_combat_core requires monotonic os.clock for skillchain timing')\nend\n\n"
if legacy_guard not in src:
    raise SystemExit('unified_combat_core legacy os.clock guard not found')
src = src.replace(legacy_guard, '', 1)
if '\tnow = os.clock,\n' not in src:
    raise SystemExit('unified_combat_core skillchain os.clock injection not found')
src = src.replace('\tnow = os.clock,\n', '\tnow = uc_time.now,\n', 1)
src = src.replace("local function uc_now_s()\n\treturn require('uc_time').now()\nend", "local function uc_now_s()\n\treturn uc_time.now()\nend", 1)
core.write_text(src, encoding='utf-8')

sc_integration = root / 'tests/replay/harness/selftest_scheduler_skillchain_integration.lua'
src = sc_integration.read_text(encoding='utf-8')
old = "\tassert_contains(core, \"now = os.clock\", 'core skillchain runtime must use the approved monotonic clock')"
new = "\tassert_contains(core, \"local uc_time = require('uc_time')\", 'core must use the canonical UC runtime clock')\n\tassert_contains(core, \"now = uc_time.now\", 'core skillchain runtime must use the canonical socket-backed clock')\n\tassert_not_contains(core, \"now = os.clock\", 'skillchain runtime must not use a separate os.clock domain')"
if old not in src:
    raise SystemExit('skillchain integration old clock assertion not found')
sc_integration.write_text(src.replace(old, new, 1), encoding='utf-8')

time_test = r'''local function read_file(path)
    local f = assert(io.open(path, 'r'))
    local text = f:read('*a')
    f:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ('missing: ' .. tostring(needle)))
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ('unexpected: ' .. tostring(needle)))
    end
end

local runtime_parse = read_file('tests/replay/harness/selftest_runtime_parse.lua')
local block = runtime_parse:match('local RUNTIME_LUA_FILES%s*=%s*{(.-)\n}')
if not block then
    error('could not parse runtime file list')
end

assert_contains(block, '"uc_time.lua"', 'canonical runtime clock must be parse-checked')

for path in block:gmatch('["\']([^"\']+%.lua)["\']') do
    if path ~= 'uc_time.lua' then
        local source = read_file(path)
        assert_not_contains(source, 'os.clock(', path .. ' must not use os.clock for runtime timing')
        assert_not_contains(source, "require('socket')", path .. ' must acquire LuaSocket through uc_time')
        assert_not_contains(source, 'require("socket")', path .. ' must acquire LuaSocket through uc_time')
        assert_not_contains(source, "rawget(_G, 'socket')", path .. ' must acquire LuaSocket through uc_time')
        assert_not_contains(source, 'socket.gettime', path .. ' must acquire socket time through uc_time')
        assert_not_contains(source, 'socket_mod.gettime', path .. ' must acquire socket time through uc_time')
        assert_not_contains(source, 's.gettime', path .. ' must acquire socket time through uc_time')
    end
end

local clock = read_file('uc_time.lua')
assert_contains(clock, "pcall(require, 'socket')", 'uc_time must own LuaSocket acquisition')
assert_contains(clock, 'M.gettime', 'uc_time must expose availability-compatible gettime')
assert_contains(clock, 'function M.now()', 'uc_time must expose canonical now()')

local core = read_file('unified_combat_core.lua')
assert_contains(core, "local uc_time = require('uc_time')", 'core must import canonical clock')
assert_contains(core, 'now = uc_time.now', 'skillchain runtime must use canonical clock')
assert_not_contains(core, 'now = os.clock', 'skillchain runtime must not use os.clock')

local burst = read_file('uc_combat_extensions.lua')
assert_contains(burst, 'local remaining = mb_expires - (tonumber(ctx.now) or 0)', 'MB window must compare same-domain runtime timestamps')

io.stdout:write('selftest_time_source_contract: OK\n')
'''
(root / 'tests/replay/harness/selftest_time_source_contract.lua').write_text(time_test, encoding='utf-8')

aggregate = root / 'tests/replay/harness/selftest_all_replay_fixtures.lua'
src = aggregate.read_text(encoding='utf-8')
if 'selftest_time_source_contract.lua' not in src:
    marker = '    "tests/replay/harness/selftest_runtime_parse.lua",\n'
    if marker not in src:
        raise SystemExit('aggregate runtime parse marker not found')
    src = src.replace(marker, marker + '    "tests/replay/harness/selftest_time_source_contract.lua",\n', 1)
    aggregate.write_text(src, encoding='utf-8')

replacements = {
    'docs/TestResults/scheduler_owned_ws_skillchain_replay_results_2026-07-20.md': (
        "`os.clock` is the approved monotonic source for process-local skillchain observation, planning, and commit comparisons. The implementation fails fast if it is unavailable. LuaSocket wall-clock time remains limited to the existing cross-process coordination domain; deadlines are translated by remaining duration and clocks are not directly compared.",
        "**Superseded 2026-09-07:** UnifiedCombat runtime timing now uses the canonical socket-backed `uc_time` clock. The former process-local `os.clock` exception caused a real magic-burst failure when `magic_burst_expires_at` was compared directly with scheduler `ctx.now` from LuaSocket. Skillchain observation, planning, commit comparisons, and magic-burst deadlines now share the same `socket.gettime` domain; runtime code must not introduce a separate `os.clock` timing domain."
    ),
    'docs/scheduler_owned_ws_skillchain_compliance_audit.md': (
        '`os.clock`',
        '`uc_time.now` (LuaSocket `socket.gettime`)'
    ),
    'docs/scheduler_owned_ws_skillchain_implementation_plan.md': (
        '`os.clock`',
        '`uc_time.now` (LuaSocket `socket.gettime`)'
    ),
}
for rel, (old, new) in replacements.items():
    path = root / rel
    src = path.read_text(encoding='utf-8')
    if old not in src:
        raise SystemExit(f'{rel}: clock documentation marker not found')
    path.write_text(src.replace(old, new), encoding='utf-8')

audit = root / 'RFC/UnifiedCombat_scheduler_refactor_tracking_audit_2026-07-24.md'
src = audit.read_text(encoding='utf-8')
marker = '## Post-audit remediation\n\n'
note = ('**2026-09-07 clock resolution:** the previously documented scheduler/skillchain clock conflict is resolved. '
        'UnifiedCombat runtime timing is standardized on the socket-backed `uc_time` source, and a static replay guard rejects runtime `os.clock`/direct LuaSocket acquisition outside that module.\n\n')
if note not in src:
    if marker not in src:
        raise SystemExit('scheduler audit post-remediation marker not found')
    audit.write_text(src.replace(marker, marker + note, 1), encoding='utf-8')

runtime_source = runtime_parse.read_text(encoding='utf-8')
block = re.search(r'local RUNTIME_LUA_FILES\s*=\s*\{(.*?)\n\}', runtime_source, re.S)
runtime_files = re.findall(r'["\']([^"\']+\.lua)["\']', block.group(1))
failures = []
forbidden = ["os.clock(", "require('socket')", 'require("socket")', "rawget(_G, 'socket')", 'socket.gettime', 'socket_mod.gettime', 's.gettime']
for rel in runtime_files:
    if rel == 'uc_time.lua':
        continue
    src = (root / rel).read_text(encoding='utf-8')
    for token in forbidden:
        if token in src:
            failures.append(f'{rel}: {token}')
if failures:
    raise SystemExit('direct runtime clock sources remain:\n' + '\n'.join(failures))

core_src = core.read_text(encoding='utf-8')
if 'now = uc_time.now' not in core_src:
    raise SystemExit('skillchain runtime not migrated to canonical clock')
print('Clock migration source verification passed.')
print('Generic raw socket helpers migrated:', generic_changed)
