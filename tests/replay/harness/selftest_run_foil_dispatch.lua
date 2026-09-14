package.path = './?.lua;./?/?.lua;' .. package.path
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
