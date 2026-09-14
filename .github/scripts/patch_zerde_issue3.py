from pathlib import Path

scheduler_path = Path('unified_scheduler.lua')
text = scheduler_path.read_text()
old = '''\t\t\tlocal spell_self_command = ('input /ma \\\"%s\\\" <me>'):format(spell)\n\t\t\tlocal intent = {\n\t\t\t\tkind = 'send_command',\n\t\t\t\tsource = 'unified_scheduler:T2.3h_darklaunch',\n\t\t\t\tcommand = spell_self_command,\n\t\t\t\tmeta = {\n\t\t\t\t\taction_type = tostring(action_type or ''),\n\t\t\t\t\taction_name = spell,\n\t\t\t\t\ttarget_kind = tostring(target_kind or ''),\n\t\t\t\t},\n\t\t\t}\n'''
new = '''\t\t\tlocal self_spell_target_id = tonumber((windower.ffxi.get_player() or {}).id) or 0\n\t\t\tif self_spell_target_id <= 0 then\n\t\t\t\tlog_combat_sched(('dispatch_drop reason=SPELL_SELF_TARGET_MISSING spell=\\\"%s\\\"'):format(tostring(spell)))\n\t\t\t\treturn false, nil\n\t\t\tend\n\t\t\tlocal spell_self_command = ('input /ma \\\"%s\\\" <me>'):format(spell)\n\t\t\tlocal intent = {\n\t\t\t\tkind = 'send_command',\n\t\t\t\tsource = 'unified_scheduler:T2.3h_darklaunch',\n\t\t\t\tcommand = spell_self_command,\n\t\t\t\tmeta = {\n\t\t\t\t\taction_type = tostring(action_type or ''),\n\t\t\t\t\taction_name = spell,\n\t\t\t\t\ttarget_id = self_spell_target_id,\n\t\t\t\t\ttarget_kind = tostring(target_kind or ''),\n\t\t\t\t\tprovider = tostring(selected.provider or 'combat'),\n\t\t\t\t},\n\t\t\t}\n'''
assert text.count(old) == 1, f'self-spell intent block count={text.count(old)}'
text = text.replace(old, new, 1)
marker = '_G.UC_SCHED_P1_DARKLAUNCH_SPELL_SELF_COMMAND_VALIDATE'
marker_at = text.find(marker)
assert marker_at >= 0
old_guard = '''\t\t\t\tfallback_used = command_ownership_status.fallback_used,\n\t\t\t}\n\t\t\taction_mark_sent('spell', {\n'''
new_guard = '''\t\t\t\tfallback_used = command_ownership_status.fallback_used,\n\t\t\t}\n\t\t\tif command_ownership_status.dispatch_ok ~= true then\n\t\t\t\tlog_combat_sched(('dispatch_drop reason=SPELL_SELF_DISPATCH_FAILED spell=\\\"%s\\\" dispatch_reason=%s'):format(\n\t\t\t\t\ttostring(spell), tostring(command_ownership_status.dispatch_reason or '')\n\t\t\t\t))\n\t\t\t\treturn false, nil\n\t\t\tend\n\t\t\taction_mark_sent('spell', {\n'''
guard_at = text.find(old_guard, marker_at)
assert guard_at >= 0
text = text[:guard_at] + text[guard_at:].replace(old_guard, new_guard, 1)
block_start = text.find('local self_spell_target_id', marker_at - 2000)
block_end = text.find("_G.UC_LAST_SCHED_ACTION = ('[p1]spell:", block_start)
assert block_start >= 0 and block_end >= 0
block = text[block_start:block_end]
block = block.replace("target_id = tonumber((windower.ffxi.get_player() or {}).id) or 0,", "target_id = self_spell_target_id,")
text = text[:block_start] + block + text[block_end:]
scheduler_path.write_text(text)

Path('tests/replay/harness/selftest_run_foil_dispatch.lua').write_text(r'''package.path = './?.lua;./?/?.lua;' .. package.path
local dispatcher = require('uc_scheduler_dispatcher')
local function assert_true(v,m) if v ~= true then error(m or 'expected true') end end
local function assert_equal(a,e,m) if a ~= e then error((m or 'values differ')..': expected='..tostring(e)..' actual='..tostring(a)) end end
local function assert_contains(h,n,m) if not tostring(h):find(tostring(n),1,true) then error((m or 'missing text')..': '..tostring(n)) end end
local source = assert(io.open('unified_scheduler.lua','r')):read('*a')
local s = assert(source:find('local self_spell_target_id',1,true))
local e = assert(source:find("_G.UC_LAST_SCHED_ACTION = ('[p1]spell:",s,true))
local block = source:sub(s,e)
assert_contains(block,"local self_spell_target_id = tonumber((windower.ffxi.get_player() or {}).id) or 0",'resolve player id')
assert_contains(block,'target_id = self_spell_target_id','structured self spell target id')
assert_contains(block,"provider = tostring(selected.provider or 'combat')",'provider identity')
local g = assert(block:find("if command_ownership_status.dispatch_ok ~= true then",1,true))
local m = assert(block:find("action_mark_sent('spell'",1,true))
assert_true(g < m,'dispatch failure guard precedes ownership')
local calls, command = 0, ''
local result = dispatcher.dispatch_intent({kind='send_command',source='test:run_foil',command='input /ma "Foil" <me>',meta={action_type='spell',action_name='Foil',target_id=560699,target_kind='self',provider='combat'}},{execute=true,send_command=function(v) calls=calls+1 command=v end})
assert_true(result.ok,'valid Foil intent')
assert_true(result.executed,'Foil executes')
assert_equal(calls,1,'Foil dispatch count')
assert_equal(command,'input /ma "Foil" <me>','Foil command target')
calls = 0
result = dispatcher.dispatch_intent({kind='send_command',command='input /ma "Foil" <me>',meta={action_type='spell',action_name='Foil',target_id=0,target_kind='self',provider='combat'}},{execute=true,send_command=function() calls=calls+1 end})
assert_equal(result.ok,false,'invalid target fails')
assert_equal(result.reason,'structured_spell_invalid_target_id','invalid target reason')
assert_equal(calls,0,'invalid target not dispatched')
print('RUN Foil dispatch self-test: ok')
''')

run_path = Path('tests/replay/harness/selftest_run_tank.lua')
run_test = run_path.read_text()
old_test = """assert_equal(out[1].action_name, 'Foil', 'Foil should follow core ward')\nassert_equal(out[1].action_type, 'spell', 'Foil action kind')\n\nplayer.buffs[#player.buffs + 1] = 7201\n"""
new_test = """assert_equal(out[1].action_name, 'Foil', 'Foil should follow core ward')\nassert_equal(out[1].action_type, 'spell', 'Foil action kind')\nassert_equal(out[1].target_kind, 'self', 'Foil must remain self-targeted')\nassert_equal(out[1].target_id, player.id, 'Foil self proposal must carry RUN player id')\n\nplayer.status = 0\nsettings.ability_allow_unengaged = true\nout = collect()\nassert_equal(out[1].action_name, 'Foil', 'unengaged RUN with a valid enemy may maintain Foil')\nassert_equal(out[1].target_id, player.id, 'unengaged Foil must still target RUN player id')\nplayer.status = 1\nsettings.ability_allow_unengaged = false\n\nready.Foil = false\nout = collect()\nassert_equal(out[1].action_name, 'Gambit', 'unavailable Foil must not starve Gambit')\nready.Foil = nil\n\nplayer.buffs[#player.buffs + 1] = 7201\n"""
assert run_test.count(old_test) == 1
run_path.write_text(run_test.replace(old_test,new_test,1))

wf_path = Path('.github/workflows/pr35-verify.yml')
wf = wf_path.read_text()
old_step = """      - name: RUN tank self-test\n        run: lua5.1 tests/replay/harness/selftest_run_tank.lua\n"""
new_step = old_step + """      - name: RUN Foil dispatch self-test\n        run: lua5.1 tests/replay/harness/selftest_run_foil_dispatch.lua\n"""
assert wf.count(old_step) == 1
wf_path.write_text(wf.replace(old_step,new_step,1))
