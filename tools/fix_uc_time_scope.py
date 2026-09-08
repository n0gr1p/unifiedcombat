from pathlib import Path

root = Path('.')

for rel in ('unified_combat_core.lua', 'remote_bridge.lua'):
    path = root / rel
    src = path.read_text(encoding='utf-8')
    old = "local function uc_now_s()\n\treturn uc_time.now()\nend"
    new = "local function uc_now_s()\n\treturn require('uc_time').now()\nend"
    if old not in src:
        raise SystemExit(f'{rel}: early uc_now_s scope marker not found')
    path.write_text(src.replace(old, new, 1), encoding='utf-8')

test = root / 'tests/replay/harness/selftest_time_source_contract.lua'
src = test.read_text(encoding='utf-8')
marker = "assert_not_contains(core, 'os.clock(', 'skillchain runtime must not use os.clock')\n"
addition = """assert_contains(core, "local function uc_now_s()\\n\\treturn require('uc_time').now()\\nend", 'core early time helper must not capture a later local')

local bridge = read_file('remote_bridge.lua')
assert_contains(bridge, "local function uc_now_s()\\n\\treturn require('uc_time').now()\\nend", 'remote bridge early time helper must not capture a later local')
"""
if marker not in src:
    raise SystemExit('time-source contract core marker not found')
if 'core early time helper must not capture a later local' not in src:
    src = src.replace(marker, marker + addition, 1)
test.write_text(src, encoding='utf-8')

# Source-level verification for the exact lexical-scope regression caught during review.
for rel in ('unified_combat_core.lua', 'remote_bridge.lua'):
    src = (root / rel).read_text(encoding='utf-8')
    expected = "local function uc_now_s()\n\treturn require('uc_time').now()\nend"
    if expected not in src:
        raise SystemExit(f'{rel}: canonical early helper not installed')

print('uc_time lexical scope correction verified')
