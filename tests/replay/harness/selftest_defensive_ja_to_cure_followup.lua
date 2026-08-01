package.loaded['uc_scheduler_action_state'] = nil
local action_state = dofile('uc_scheduler_action_state.lua')
local scheduler_source_path = 'unified_scheduler.lua'

local now_value = 0
local scheduler = {}

local function now_s()
    return now_value
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    if not value then
        error(message or 'assert_true failed')
    end
end

local function read_file(file_path)
    local fh, err = io.open(file_path, 'r')
    if not fh then
        error('failed to open ' .. tostring(file_path) .. ': ' .. tostring(err))
    end
    local text = fh:read('*a')
    fh:close()
    return text
end

local function set_context(tbl)
    if tbl then
        _G.UC_DEFENSIVE_CHAIN_ACTION = tbl
    else
        _G.UC_DEFENSIVE_CHAIN_ACTION = nil
    end
end

local function main()
    local globals = {
        UC_SETTINGS = {},
    }
    local scheduler_source = read_file(scheduler_source_path)
    local provider_block = scheduler_source:match("if provider == 'defensive_internal' then(.-)\n\tend")
    assert_true(type(provider_block) == 'string', 'failed to capture defensive_internal provider block')
    local context_at = provider_block:find("_G%.UC_DEFENSIVE_CHAIN_ACTION = {", 1)
    local blocked_at = provider_block:find("local blocked, b_reason = action_dispatch_blocked%(%)", 1)
    local clear_at = provider_block:find("_G%.UC_DEFENSIVE_CHAIN_ACTION = nil", 1)
    assert_true(type(context_at) == 'number' and type(blocked_at) == 'number' and context_at < blocked_at,
        'ranked defensive path must set chain context before action_dispatch_blocked')
    assert_true(type(clear_at) == 'number' and clear_at > blocked_at,
        'ranked defensive path must clear chain context after action_dispatch_blocked')

    now_value = 10
    action_state.action_mark_sent_with_meta(scheduler, 'ja', now_s, {
        action_name = 'Majesty',
        provider = 'defensive_internal',
        def_action_type = 'buff',
    })

    set_context({
        provider = 'defensive_internal',
        action_kind = 'spell',
        def_action_type = 'cure',
        action_name = 'Cure IV',
    })
    globals.UC_DEFENSIVE_CHAIN_ACTION = _G.UC_DEFENSIVE_CHAIN_ACTION
    local blocked, reason = action_state.action_dispatch_blocked(scheduler, now_s, globals)
    assert_equal(blocked, false, 'Majesty -> defensive Cure follow-up must bypass generic JA block')
    assert_equal(reason, nil, 'Majesty -> defensive Cure follow-up must not return block reason')

    set_context({
        provider = 'defensive_internal',
        action_kind = 'ja',
        def_action_type = 'buff',
        action_name = 'Protectra',
    })
    globals.UC_DEFENSIVE_CHAIN_ACTION = _G.UC_DEFENSIVE_CHAIN_ACTION
    blocked, reason = action_state.action_dispatch_blocked(scheduler, now_s, globals)
    assert_equal(blocked, true, 'non-Cure follow-up must remain blocked after Majesty JA')
    assert_equal(reason, 'BLOCK_ACTION_ACTING', 'non-Cure follow-up acting reason mismatch')

    set_context({
        provider = 'combat',
        action_kind = 'spell',
        def_action_type = 'cure',
        action_name = 'Cure IV',
    })
    globals.UC_DEFENSIVE_CHAIN_ACTION = _G.UC_DEFENSIVE_CHAIN_ACTION
    blocked, reason = action_state.action_dispatch_blocked(scheduler, now_s, globals)
    assert_equal(blocked, true, 'offensive/unrelated provider must not gain Majesty bypass')
    assert_equal(reason, 'BLOCK_ACTION_ACTING', 'offensive provider acting reason mismatch')

    now_value = 10.8
    set_context({
        provider = 'defensive_internal',
        action_kind = 'spell',
        def_action_type = 'cure',
        action_name = 'Cure IV',
    })
    globals.UC_DEFENSIVE_CHAIN_ACTION = _G.UC_DEFENSIVE_CHAIN_ACTION
    blocked, reason = action_state.action_dispatch_blocked(scheduler, now_s, globals)
    assert_equal(blocked, true, 'Majesty follow-up bypass must stay bounded in time')
    assert_equal(reason, 'BLOCK_ACTION_ACTING', 'expired Majesty follow-up should revert to normal block')

    now_value = 20
    scheduler = {}
    action_state.action_mark_sent_with_meta(scheduler, 'ja', now_s, {
        action_name = 'Provoke',
        provider = 'combat',
        def_action_type = 'ja',
    })
    set_context({
        provider = 'defensive_internal',
        action_kind = 'spell',
        def_action_type = 'cure',
        action_name = 'Cure IV',
    })
    globals.UC_DEFENSIVE_CHAIN_ACTION = _G.UC_DEFENSIVE_CHAIN_ACTION
    blocked, reason = action_state.action_dispatch_blocked(scheduler, now_s, globals)
    assert_equal(blocked, true, 'non-Majesty JA must not gain defensive Cure bypass')
    assert_equal(reason, 'BLOCK_ACTION_ACTING', 'non-Majesty JA reason mismatch')

    set_context(nil)
    globals.UC_DEFENSIVE_CHAIN_ACTION = nil
    io.stdout:write('selftest_defensive_ja_to_cure_followup: OK\n')
end

main()
