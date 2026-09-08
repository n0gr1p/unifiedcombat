from pathlib import Path

p = Path('tools/uc_time_migrate.py')
s = p.read_text(encoding='utf-8')

old_lua = """        for line in source:gmatch('[^\\r\\n]+') do
            if line:find('socket_gettime', 1, true) and line:find('gettime', 1, true)
                and not line:find('uc_time.gettime', 1, true) then
                error(path .. ' socket_gettime alias must be sourced from uc_time')
            end
        end"""
new_lua = """        for line in source:gmatch('[^\\r\\n]+') do
            local alias_assignment = line:match('^%s*local%s+socket_gettime%s*=')
                or line:match('^%s*socket_gettime%s*=')
            if alias_assignment and not line:find('uc_time.gettime', 1, true) then
                error(path .. ' socket_gettime alias must be sourced from uc_time')
            end
        end"""
if old_lua not in s:
    raise SystemExit('Lua alias guard patch marker not found')
s = s.replace(old_lua, new_lua, 1)

old_py = """    for line in src.splitlines():
        if 'socket_gettime' in line and 'gettime' in line and 'uc_time.gettime' not in line:
            # Calls such as socket_gettime() are fine; only assignments/declarations
            # that source the alias independently are forbidden.
            if '=' in line:
                failures.append(f'{rel}: noncanonical socket_gettime alias: {line.strip()}')"""
new_py = """    for line in src.splitlines():
        if re.match(r'\\s*(?:local\\s+)?socket_gettime\\s*=', line) and 'uc_time.gettime' not in line:
            failures.append(f'{rel}: noncanonical socket_gettime alias: {line.strip()}')"""
if old_py not in s:
    raise SystemExit('Python alias guard patch marker not found')

p.write_text(s.replace(old_py, new_py, 1), encoding='utf-8')
