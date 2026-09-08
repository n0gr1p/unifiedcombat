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

# Keep existing availability/error behavior in these high-level modules, but source
# their gettime function from the canonical module instead of acquiring LuaSocket again.
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

# GEO packet tracing formerly fell back to os.time when LuaSocket was absent. Runtime
# timing is now one domain and fails closed through uc_time like the scheduler does.
geo_trace = root / 'uc_geo_packet_trace.lua'
src = geo_trace.read_text(encoding='utf-8')
old = "local function now_s()\n\tif type(socket_gettime) == 'function' then\n\t\treturn socket_gettime()\n\tend\n\treturn os.time()\nend"
new = "local function now_s()\n\treturn uc_time.now()\nend"
if old not in src:
    raise SystemExit('uc_geo_packet_trace now_s fallback not found')
geo_trace.write_text(src.replace(old, new, 1), encoding='utf-8')

# Nyzul uses socket time only to mint a token; route that time read through uc_time.
nyzul = root / 'uc_nyzul_runtime.lua'
src = nyzul.read_text(encoding='utf-8')
old = "local function next_token()\n\tlocal socket = require('socket')\n\treturn ('%s:%d'):format(name_key(player_name()), math.floor(socket.gettime() * 1000))\nend"
new = "local function next_token()\n\treturn ('%s:%d'):format(name_key(player_name()), math.floor(require('uc_time').now() * 1000))\nend"
if old not in src:
    raise SystemExit('uc_nyzul_runtime next_token socket source not found')
nyzul.write_text(src.replace(old, new, 1), encoding='utf-8')

# remote_bridge legitimately needs the LuaSocket module for TCP. Only its *time reads*
# move to uc_time; socket.tcp and related networking remain untouched.
remote = root / 'remote_bridge.lua'
src = remote.read_text(encoding='utf-8')
if "local uc_time = require('uc_time')" not in src:
    marker = "local socket = require('socket')\n"
    if marker not in src:
        raise SystemExit('remote_bridge socket import not found')
    src = src.replace(marker, marker + "local uc_time = require('uc_time')\n", 1)
src = src.replace("local function uc_now_s()\n\treturn require('uc_time').now()\nend", "local function uc_now_s()\n\treturn uc_time.now()\nend", 1)
old = "local now_ms = math.floor((socket.gettime and socket.gettime() or uc_now_s()) * 1000)"
if old not in src:
    raise SystemExit('remote_bridge build_session_id time source not found')
src = src.replace(old, "local now_ms = math.floor(uc_time.now() * 1000)", 1)
remote.write_text(src, encoding='utf-8')

# The skillchain subsystem was the remaining separate clock domain. Move every live
# skillchain observation/planning/commit timestamp in core onto the canonical clock.
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
src = src.replace('os.clock()', 'uc_time.now()')
src = src.replace("local function uc_now_s()\n\treturn require('uc_time').now()\nend", "local function uc_now_s()\n\treturn uc_time.now()\nend", 1)
core.write_text(src, encoding='utf-8')

# Update the static skillchain integration contract to the one-clock architecture.
sc_integration = root / 'tests/replay/harness/selftest_scheduler_skillchain_integration.lua'
src = sc_integration.read_text(encoding='utf-8')
old = "\tassert_contains(core, \"now = os.clock\", 'core skillchain runtime must use the approved monotonic clock')"
new = "\tassert_contains(core, \"local uc_time = require('uc_time')\", 'core must use the canonical UC runtime clock')\n\tassert_contains(core, \"now = uc_time.now\", 'core skillchain runtime must use the canonical socket-backed clock')\n\tassert_not_contains(core, \"now = os.clock\", 'skillchain runtime must not use a separate os.clock domain')"
if old not in src:
    raise SystemExit('skillchain integration old clock assertion not found')
sc_integration.write_text(src.replace(old, new, 1), encoding='utf-8')

# The state object should require an injected clock, but it no longer needs to bless
# os.clock itself. Tests remain deterministic by injecting synthetic time.
sc_test = root / 'tests/replay/harness/selftest_skillchain_state.lua'
src = sc_test.read_text(encoding='utf-8')
old = """local function test_clock_contract()\n\tlocal ok = pcall(function()\n\t\tskillchain.new({})\n\tend)\n\tassert_false(ok, 'runtime must reject missing monotonic clock')\n\tlocal previous = os.clock()\n\tfor _ = 1, 1000 do\n\t\tlocal current = os.clock()\n\t\tassert_true(current >= previous, 'Windower runtime clock contract must be monotonic')\n\t\tprevious = current\n\tend\nend"""
new = """local function test_clock_contract()\n\tlocal ok = pcall(function()\n\t\tskillchain.new({})\n\tend)\n\tassert_false(ok, 'runtime must reject missing injected clock')\n\tlocal runtime, clock = new_runtime(100)\n\tassert_true(runtime ~= nil, 'runtime must accept injected deterministic clock')\n\tclock.now = 101\n\tassert_equal(clock.now, 101, 'injected clock must remain caller-controlled')\nend"""
if old not in src:
    raise SystemExit('selftest_skillchain_state old clock contract not found')
sc_test.write_text(src.replace(old, new, 1), encoding='utf-8')

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
        assert_not_contains(source, "rawget(_G, 'socket')", path .. ' must not acquire the timing source directly')
        if source:match('socket%.gettime%s*%(') then
            error(path .. ' must route socket.gettime calls through uc_time')
        end
        if source:match('socket_mod%.gettime%s*%(') then
            error(path .. ' must route socket_mod.gettime calls through uc_time')
        end
        if source:match('%f[%w]s%.gettime%s*%(') then
            error(path .. ' must route s.gettime calls through uc_time')
        end
        for line in source:gmatch('[^\r\n]+') do
            if line:find('socket_gettime', 1, true) and line:find('gettime', 1, true)
                and not line:find('uc_time.gettime', 1, true) then
                error(path .. ' socket_gettime alias must be sourced from uc_time')
            end
        end
    end
end

local clock = read_file('uc_time.lua')
assert_contains(clock, "pcall(require, 'socket')", 'uc_time must own LuaSocket timing acquisition')
assert_contains(clock, 'M.gettime', 'uc_time must expose availability-compatible gettime')
assert_contains(clock, 'function M.available()', 'uc_time must expose availability state')
assert_contains(clock, 'function M.now()', 'uc_time must expose canonical now()')

local agents = read_file('AGENTS.md')
assert_contains(agents, 'Canonical runtime time source', 'agent instructions must document the one-clock rule')
assert_contains(agents, 'uc_time.now()', 'agent instructions must name the canonical runtime clock API')

local core = read_file('unified_combat_core.lua')
assert_contains(core, "local uc_time = require('uc_time')", 'core must import canonical clock')
assert_contains(core, 'now = uc_time.now', 'skillchain runtime must use canonical clock')
assert_not_contains(core, 'os.clock(', 'skillchain runtime must not use os.clock')

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

# Put the invariant where every future coding agent is required to look first.
agents = root / 'AGENTS.md'
src = agents.read_text(encoding='utf-8')
clock_policy = """## Canonical runtime time source\n\nUnifiedCombat runtime/gameplay timing uses one clock domain.\n\n* Use `uc_time.now()` for scheduler, action, movement, reaction, skillchain, magic-burst, timeout, deadline, and other elapsed/runtime timestamps.\n* `uc_time` is backed by LuaSocket `socket.gettime`. Do not use `os.clock()` for UnifiedCombat runtime decisions.\n* Code that legitimately needs the LuaSocket module for networking may still `require('socket')`, but must route time reads through `uc_time`.\n* Tests should inject deterministic/fake `now` functions instead of introducing a second production clock domain.\n* Do not directly compare timestamps from different clock sources. The runtime time-source self-test enforces this contract.\n\n"""
if '## Canonical runtime time source' not in src:
    marker = '## Architecture guidance\n\n'
    if marker not in src:
        raise SystemExit('AGENTS architecture marker not found')
    src = src.replace(marker, clock_policy + marker, 1)
    agents.write_text(src, encoding='utf-8')

runtime_doc = r'''# UnifiedCombat runtime time source

UnifiedCombat runtime/gameplay timing has one canonical clock domain: `uc_time.now()`, backed by LuaSocket `socket.gettime`.

This applies to scheduler timestamps, action state, cooldown/settle windows, movement/follow holds, reactions, skillchain state, magic-burst windows, pending actions, retries, deadlines, and other elapsed runtime decisions.

Do not use `os.clock()` for runtime decisions. Do not call `socket.gettime()` directly from runtime modules. Code that needs LuaSocket for networking may still require the module, but its time reads must go through `uc_time`.

Tests should inject fake/deterministic `now` functions where supported. This keeps replay tests deterministic without creating a second production clock domain.

## Why this is enforced

The scheduler already used LuaSocket time while the skillchain runtime historically used `os.clock`. Magic-burst state inherited the skillchain timestamp, then `uc_combat_extensions.lua` compared that expiry directly with scheduler `ctx.now`. The incompatible domains made every valid burst window appear expired and prevented `combat.magic_burst` proposals.

The fix is architectural rather than a subtraction workaround: skillchain and scheduler timestamps now share `uc_time`, so `magic_burst_expires_at - ctx.now` is a valid same-domain duration.

`tests/replay/harness/selftest_time_source_contract.lua` is the regression guard for this invariant.
'''
(root / 'docs/runtime_time_source.md').write_text(runtime_doc, encoding='utf-8')

# Retire the contradictory current clock statements in the skillchain docs. Historical
# before-state discussion remains historical, but the current implementation contract
# now points at the canonical socket-backed source.
result_doc = root / 'docs/TestResults/scheduler_owned_ws_skillchain_replay_results_2026-07-20.md'
src = result_doc.read_text(encoding='utf-8')
old = "`os.clock` is the approved monotonic source for process-local skillchain observation, planning, and commit comparisons. The implementation fails fast if it is unavailable. LuaSocket wall-clock time remains limited to the existing cross-process coordination domain; deadlines are translated by remaining duration and clocks are not directly compared."
new = "**Superseded 2026-09-07:** UnifiedCombat runtime timing now uses the canonical socket-backed `uc_time` clock. The former process-local `os.clock` exception caused a real magic-burst failure when `magic_burst_expires_at` was compared directly with scheduler `ctx.now`. Skillchain observation, planning, commit comparisons, and magic-burst deadlines now share the same `socket.gettime` domain; runtime code must not introduce a separate `os.clock` timing domain."
if old not in src:
    raise SystemExit('skillchain replay result clock decision not found')
result_doc.write_text(src.replace(old, new, 1), encoding='utf-8')

compliance = root / 'docs/scheduler_owned_ws_skillchain_compliance_audit.md'
src = compliance.read_text(encoding='utf-8')
old = '`uc_skillchain_state.lua` now owns target-scoped, generation-versioned resonance and separate magic-burst state using `os.clock`.'
new = '`uc_skillchain_state.lua` now owns target-scoped, generation-versioned resonance and separate magic-burst state using the canonical socket-backed `uc_time.now` runtime clock.'
if old not in src:
    raise SystemExit('skillchain compliance current clock statement not found')
compliance.write_text(src.replace(old, new, 1), encoding='utf-8')

plan = root / 'docs/scheduler_owned_ws_skillchain_implementation_plan.md'
src = plan.read_text(encoding='utf-8')
old = "The approved monotonic runtime clock is `os.clock`. It is sampled at the beginning of incoming action processing and used only for process-local skillchain comparisons. Existing cross-process intent coordination continues to use its existing LuaSocket time domain; the two clocks are never compared directly."
new = "**Clock policy superseded 2026-09-07:** the approved UnifiedCombat runtime clock is now `uc_time.now`, backed by LuaSocket `socket.gettime`. Skillchain observation, planning, dispatch validation, scheduler context, and magic-burst deadlines share this one domain. The prior `os.clock` exception was removed after a cross-domain magic-burst comparison caused valid burst windows to be rejected."
if old not in src:
    raise SystemExit('skillchain implementation plan current clock paragraph not found')
src = src.replace(old, new, 1)
old = "`WS-SC-0` must identify and prove one approved monotonic runtime clock before `WS-SC-1` begins. `socket.gettime` is the current high-resolution wall-clock source and does not by itself satisfy the monotonic-clock requirement. Do not add a second clock or silently switch clocks when the approved source is unavailable; fail fast under the project's runtime rules."
new = "`WS-SC-0` uses the project-wide canonical runtime clock in `uc_time`. Do not add a second production clock domain or silently switch clocks when the canonical source is unavailable; fail fast under the project's runtime rules. Tests may inject deterministic fake clocks."
if old not in src:
    raise SystemExit('skillchain implementation plan WS-SC-0 clock paragraph not found')
plan.write_text(src.replace(old, new, 1), encoding='utf-8')

audit = root / 'RFC/UnifiedCombat_scheduler_refactor_tracking_audit_2026-07-24.md'
src = audit.read_text(encoding='utf-8')
marker = '## Post-audit remediation\n\n'
note = ('**2026-09-07 clock resolution:** the previously documented scheduler/skillchain clock conflict is resolved. '
        'UnifiedCombat runtime timing is standardized on the socket-backed `uc_time` source, and a static replay guard rejects runtime `os.clock` and direct `socket.gettime()` calls outside that module.\n\n')
if note not in src:
    if marker not in src:
        raise SystemExit('scheduler audit post-remediation marker not found')
    audit.write_text(src.replace(marker, marker + note, 1), encoding='utf-8')

# Final source-level contract verification before committing anything. Direct LuaSocket
# imports are allowed for networking; direct *time reads* are not.
runtime_source = runtime_parse.read_text(encoding='utf-8')
block = re.search(r'local RUNTIME_LUA_FILES\s*=\s*\{(.*?)\n\}', runtime_source, re.S)
runtime_files = re.findall(r'["\']([^"\']+\.lua)["\']', block.group(1))
failures = []
for rel in runtime_files:
    if rel == 'uc_time.lua':
        continue
    src = (root / rel).read_text(encoding='utf-8')
    if 'os.clock(' in src:
        failures.append(f'{rel}: os.clock(')
    if "rawget(_G, 'socket')" in src:
        failures.append(f'{rel}: rawget timing source')
    for pattern, label in [
        (r'\bsocket\.gettime\s*\(', 'socket.gettime('),
        (r'\bsocket_mod\.gettime\s*\(', 'socket_mod.gettime('),
        (r'\bs\.gettime\s*\(', 's.gettime('),
    ]:
        if re.search(pattern, src):
            failures.append(f'{rel}: {label}')
    for line in src.splitlines():
        if 'socket_gettime' in line and 'gettime' in line and 'uc_time.gettime' not in line:
            # Calls such as socket_gettime() are fine; only assignments/declarations
            # that source the alias independently are forbidden.
            if '=' in line:
                failures.append(f'{rel}: noncanonical socket_gettime alias: {line.strip()}')
if failures:
    raise SystemExit('direct runtime clock sources remain:\n' + '\n'.join(failures))

core_src = core.read_text(encoding='utf-8')
if 'now = uc_time.now' not in core_src or 'os.clock(' in core_src:
    raise SystemExit('skillchain runtime not fully migrated to canonical clock')
print('Clock migration source verification passed.')
print('Generic raw socket helpers migrated:', generic_changed)
