from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    p.write_text(text.replace(old, new, 1))


replace_once(
    'uc_reaction_sequence_runtime.lua',
    """    function base.blocks_movement(lock)\n        if type(lock) == 'table' and tostring(lock.response or '') == 'use_sequence' then\n            return false\n        end\n        return base_blocks_movement(lock)\n    end\n""",
    """    function base.blocks_movement(lock)\n        if type(lock) == 'table' and tostring(lock.response or '') == 'use_sequence' then\n            -- Freeze ordinary movement as soon as an atomic action sequence\n            -- activates.  A setup JA such as Elemental Seal can execute while\n            -- moving, but its required spell must not lose the ability window\n            -- waiting for formation/follow movement to settle afterwards.\n            return true\n        end\n        return base_blocks_movement(lock)\n    end\n""",
)

replace_once(
    'unified_scheduler.lua',
    """\tif response == 'run_away' or response == 'move_to_range' then\n\t\trequire('uc_reaction_runtime').mark_turn_applied(lock.key)\n\t\tlock.turn_applied = true\n\t\treturn true\n\tend\n\tif response ~= 'stop_attacking' then\n\t\terror('unified_scheduler received unsupported reaction response: ' .. response)\n\tend\n""",
    """\tif response == 'run_away' or response == 'move_to_range' then\n\t\trequire('uc_reaction_runtime').mark_turn_applied(lock.key)\n\t\tlock.turn_applied = true\n\t\treturn true\n\tend\n\tif response == 'use_action' or response == 'use_sequence' then\n\t\t-- Action-bearing reactions are executed by the combat proposal path.\n\t\t-- Activation itself has no immediate facing/disengage side effect.\n\t\treturn true\n\tend\n\tif response ~= 'stop_attacking' then\n\t\terror('unified_scheduler received unsupported reaction response: ' .. response)\n\tend\n""",
)

replace_once(
    'uc_combat_extensions_sequence.lua',
    """local function ja_resource(name)\n    local res = require('resources')\n    if type(res.job_abilities) ~= 'table' or type(res.job_abilities.with) ~= 'function' then\n        return nil\n    end\n    return res.job_abilities:with('en', tostring(name or ''))\nend\n\nlocal function append_sequence_action""",
    """local function ja_resource(name)\n    local res = require('resources')\n    if type(res.job_abilities) ~= 'table' or type(res.job_abilities.with) ~= 'function' then\n        return nil\n    end\n    return res.job_abilities:with('en', tostring(name or ''))\nend\n\nlocal function mob_name_by_id(id)\n    local windower_ref = rawget(_G, 'windower')\n    local ffxi = type(windower_ref) == 'table' and windower_ref.ffxi or nil\n    local get_mob_by_id = type(ffxi) == 'table' and ffxi.get_mob_by_id or nil\n    if type(get_mob_by_id) ~= 'function' then\n        return ''\n    end\n    local ok, mob = pcall(get_mob_by_id, tonumber(id) or 0)\n    if not ok or type(mob) ~= 'table' then\n        return ''\n    end\n    return tostring(mob.name or '')\nend\n\nlocal function append_sequence_action""",
)

replace_once(
    'uc_combat_extensions_sequence.lua',
    """    elseif action_target == 'actor' then\n        target_id = tonumber(action_lock.actor_id) or 0\n        target_name = tostring(action_lock.actor_name or action_lock.name or '')\n        target_kind = 'mob'\n""",
    """    elseif action_target == 'actor' then\n        target_id = tonumber(action_lock.actor_id) or 0\n        target_name = tostring(action_lock.actor_name or '')\n        if target_name == '' then\n            target_name = mob_name_by_id(target_id)\n        end\n        if target_name == '' then\n            target_name = tostring(target_id)\n        end\n        target_kind = 'mob'\n""",
)

p = Path('tests/replay/harness/selftest_reaction_action_sequence.lua')
text = p.read_text()
anchor = """assert_equal(ready.activated.step_index, 1, 'first sequence step index')\n\nassert_true(reactions.blocks_proposal"""
replacement = """assert_equal(ready.activated.step_index, 1, 'first sequence step index')\nassert_true(reactions.blocks_movement(ready.activated), 'atomic sequence must freeze normal movement immediately')\n\nassert_true(reactions.blocks_proposal"""
if text.count(anchor) != 1:
    raise SystemExit('sequence movement assertion anchor mismatch')
text = text.replace(anchor, replacement, 1)

anchor = """local out = {}\nlocal claimed = api.collect_priority_offense({\n    now = 40.0,\n    player = { id = 1, name = 'Etamame' },\n}, out)\n"""
replacement = """local old_windower = rawget(_G, 'windower')\n_G.windower = {\n    ffxi = {\n        get_mob_by_id = function(id)\n            if tonumber(id) == 900 then\n                return { id = 900, name = 'Zerde' }\n            end\n            return nil\n        end,\n    },\n}\nlocal out = {}\nlocal claimed = api.collect_priority_offense({\n    now = 40.0,\n    player = { id = 1, name = 'Etamame' },\n}, out)\n"""
if text.count(anchor) != 1:
    raise SystemExit('provider collection anchor mismatch')
text = text.replace(anchor, replacement, 1)

anchor = """assert_equal(out[1].action_name, 'Stun', 'required terminal action after optional skip')\nassert_equal(out[1].family_id, 'combat.reaction.sequence', 'sequence proposal family')\n\n-- Normalizer wrapper"""
replacement = """assert_equal(out[1].action_name, 'Stun', 'required terminal action after optional skip')\nassert_equal(out[1].target_name, 'Zerde', 'actor-targeted sequence proposal must name the actor, not the triggering ability')\nassert_equal(out[1].family_id, 'combat.reaction.sequence', 'sequence proposal family')\n_G.windower = old_windower\n\nlocal scheduler_source = assert(io.open('unified_scheduler.lua', 'rb')):read('*a')\nassert_true(\n    scheduler_source:find(\"if response == 'use_action' or response == 'use_sequence' then\", 1, true) ~= nil,\n    'scheduler activation handler must accept action-bearing reaction responses'\n)\n\n-- Normalizer wrapper"""
if text.count(anchor) != 1:
    raise SystemExit('provider assertion anchor mismatch')
text = text.replace(anchor, replacement, 1)
p.write_text(text)
