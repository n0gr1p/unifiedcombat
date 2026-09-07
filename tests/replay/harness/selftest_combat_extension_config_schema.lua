local normalizer = require('uc_config_normalizer')

local function assert_true(condition, message)
    if not condition then
        error(message or 'assertion failed')
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'values are not equal') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
    end
end

local function assert_error_contains(fn, expected_text, message)
    local ok, err = pcall(fn)
    if ok then
        error(message or ('expected error containing: ' .. expected_text))
    end
    assert_true(
        tostring(err):find(expected_text, 1, true) ~= nil,
        (message or 'unexpected error') .. ': ' .. tostring(err)
    )
end

local defaults = normalizer.normalize({})
assert_equal(defaults.combat.auto_engage, true, 'auto_engage must default on for backward compatibility')
assert_equal(defaults.spells.magic_burst, false, 'magic burst must default off')

local flat = normalizer.normalize({
    auto_engage = false,
    magic_burst_enabled = true,
    spell = 'Fire V',
    reaction_enabled = true,
    reaction_rules = {
        {
            trigger = 'ability_window',
            name = 'Just Desserts',
            response = 'use_action',
            action_type = 'spell',
            action_name = 'Stun',
        },
    },
})

assert_equal(flat.combat.auto_engage, false, 'flat auto_engage must normalize')
assert_equal(flat.spells.magic_burst, true, 'flat magic_burst_enabled must normalize')
assert_equal(flat.spells.configured, 'Fire V', 'flat configured MB spell must normalize')
assert_equal(flat.reactions.enabled, true, 'flat reactions must remain enabled')
assert_equal(#flat.reactions.rules, 1, 'flat use_action rule must survive normalization')
assert_equal(flat.reactions.rules[1].response, 'use_action', 'flat use_action response mismatch')
assert_equal(flat.reactions.rules[1].action_type, 'spell', 'flat reaction action type mismatch')
assert_equal(flat.reactions.rules[1].action_name, 'Stun', 'flat reaction action name mismatch')

local structured = normalizer.normalize({
    combat = {
        auto_engage = false,
    },
    spells = {
        configured = 'Fire V',
        magic_burst = true,
    },
    reactions = {
        enabled = true,
        rules = {
            {
                trigger = 'ability_window',
                name = 'Just Desserts',
                response = 'use_action',
                action_type = 'spell',
                action_name = 'Stun',
            },
        },
    },
})

assert_equal(structured.combat.auto_engage, false, 'structured auto_engage must normalize')
assert_equal(structured.spells.magic_burst, true, 'structured magic burst must normalize')
assert_equal(structured.spells.configured, 'Fire V', 'structured configured MB spell mismatch')
assert_equal(#structured.reactions.rules, 1, 'structured use_action rule must survive normalization')
assert_equal(structured.reactions.rules[1].action_type, 'spell', 'structured reaction action type mismatch')
assert_equal(structured.reactions.rules[1].action_name, 'Stun', 'structured reaction action name mismatch')

assert_error_contains(function()
    normalizer.normalize({
        reactions = {
            enabled = true,
            rules = {
                {
                    trigger = 'ability_window',
                    name = 'Just Desserts',
                    response = 'use_action',
                    action_type = 'ja',
                    action_name = 'Provoke',
                },
            },
        },
    })
end, 'action_type must be spell', 'invalid use_action action type must be rejected')

print('selftest_combat_extension_config_schema: OK')
