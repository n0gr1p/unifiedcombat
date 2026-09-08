from pathlib import Path

bridge = Path('remote_bridge.lua')
s = bridge.read_text(encoding='utf-8')

old_sig = """\tlocal main_job = p.main_job or ''
\tlocal sub_job = p.sub_job or ''
\tlocal level_sync = info and info.level_sync and tostring(info.level_sync) or ''
\treturn table.concat({ main_job, sub_job, level_sync }, '|')
"""
new_sig = """\tlocal main_job = p.main_job or ''
\tlocal sub_job = p.sub_job or ''
\tlocal level_sync = info and info.level_sync and tostring(info.level_sync) or ''
\tlocal jp = type(p.job_points) == 'table' and p.job_points or nil
\tlocal jp_row = jp and jp[tostring(main_job):lower()] or nil
\tlocal jp_spent = tonumber(jp_row and jp_row.jp_spent) or 0
\treturn table.concat({ main_job, sub_job, level_sync, tostring(jp_spent) }, '|')
"""
if old_sig not in s:
    raise SystemExit('ability signature marker not found')
s = s.replace(old_sig, new_sig, 1)

old_gate = """\t\tlocal main_lvl = tonumber(p.main_job_level) or tonumber(p.main_job_lv) or 99
\t\tlocal sub_lvl = tonumber(p.sub_job_level) or tonumber(p.sub_job_lv) or 49
\t\tlocal jobs = sp.jobs or sp.levels
\t\tif type(jobs) ~= 'table' then
\t\t\t-- If resource does not expose per-job requirements, do not over-filter.
\t\t\treturn true
\t\tend
\t\tlocal req_main = tonumber(jobs[main_id] or jobs[tostring(main_id)])
\t\tif req_main and req_main > 0 and main_lvl >= req_main then
\t\t\treturn true
\t\tend
"""
new_gate = """\t\tlocal main_lvl = tonumber(p.main_job_level) or tonumber(p.main_job_lv) or 99
\t\tlocal sub_lvl = tonumber(p.sub_job_level) or tonumber(p.sub_job_lv) or 49
\t\tlocal jp_spent = 0
\t\tdo
\t\t\tlocal jp = type(p.job_points) == 'table' and p.job_points or nil
\t\t\tlocal mj = tostring(p.main_job or ''):lower()
\t\t\tlocal row = jp and jp[mj] or nil
\t\t\tjp_spent = tonumber(row and row.jp_spent) or 0
\t\tend
\t\tlocal jobs = sp.jobs or sp.levels
\t\tif type(jobs) ~= 'table' then
\t\t\t-- If resource does not expose per-job requirements, do not over-filter.
\t\t\treturn true
\t\tend
\t\tlocal req_main = tonumber(jobs[main_id] or jobs[tostring(main_id)])
\t\tif req_main and req_main > 0 and (main_lvl >= req_main or jp_spent >= req_main) then
\t\t\treturn true
\t\tend
"""
if old_gate not in s:
    raise SystemExit('spell job gate marker not found')
s = s.replace(old_gate, new_gate, 1)
bridge.write_text(s, encoding='utf-8')

test_path = Path('tests/replay/harness/selftest_remote_bridge_spell_options.lua')
test_path.write_text(r'''local function read_file(path)
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

local bridge = read_file('remote_bridge.lua')
local scheduler = read_file('unified_scheduler.lua')

assert_contains(bridge, "local jp = type(p.job_points) == 'table' and p.job_points or nil", 'bridge must read job points for spell capability')
assert_contains(bridge, "jp_spent = tonumber(row and row.jp_spent) or 0", 'bridge must read current main-job JP spent')
assert_contains(bridge, "main_lvl >= req_main or jp_spent >= req_main", 'bridge must admit main-job JP-gift spells')
assert_contains(bridge, "sub_lvl >= req_sub", 'bridge must keep subjob eligibility level-only')
assert_contains(bridge, "table.concat({ main_job, sub_job, level_sync, tostring(jp_spent) }, '|')", 'spell option cache signature must change when main-job JP spent changes')

assert_contains(scheduler, "main_lvl >= req_main or jp_spent >= req_main", 'scheduler and bridge spell capability semantics must stay aligned')
assert_contains(scheduler, "sub_lvl >= req_sub", 'scheduler and bridge subjob semantics must stay aligned')

io.stdout:write('selftest_remote_bridge_spell_options: OK\n')
''', encoding='utf-8')

aggregate = Path('tests/replay/harness/selftest_all_replay_fixtures.lua')
a = aggregate.read_text(encoding='utf-8')
marker = '    "tests/replay/harness/selftest_time_source_contract.lua",\n'
entry = '    "tests/replay/harness/selftest_remote_bridge_spell_options.lua",\n'
if entry not in a:
    if marker not in a:
        raise SystemExit('aggregate insertion marker not found')
    a = a.replace(marker, marker + entry, 1)
    aggregate.write_text(a, encoding='utf-8')

print('JP spell option patch applied.')
