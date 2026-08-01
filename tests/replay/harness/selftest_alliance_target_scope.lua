package.loaded['socket'] = {
    gettime = function()
        return (_G.__TEST_NOW or 0)
    end,
}
_G.socket = package.loaded['socket']

local function make_resource_list(rows)
    local list = rows or {}
    function list:with(field, value)
        for _, row in pairs(self) do
            if type(row) == 'table' and row[field] == value then
                return row
            end
        end
        return nil
    end
    return list
end

package.loaded['resources'] = {
    weapon_skills = make_resource_list({}),
    job_abilities = make_resource_list({
        [5] = {
            id = 5,
            en = 'Provoke',
            recast_id = 5,
            targets = 'Enemy',
            range = 10,
        },
    }),
    spells = make_resource_list({}),
    buffs = {},
    items = {},
    monster_abilities = {},
}
package.loaded['skills'] = {}
package.loaded['uc_ability_pipeline'] = {}
package.loaded['uc_ws_gate'] = {}
package.loaded['uc_ws_memory'] = {}
package.loaded['uc_ignore'] = {}
package.loaded['uc_target_ignore'] = {
    is_mob_blocked = function()
        return false
    end,
}
package.loaded['uc_partner_list'] = {
    as_ordered_ids = function()
        return {}
    end,
}
package.loaded['uc_fight_leader'] = {
    resolve_mid_override = function()
        return 0
    end,
}
package.loaded['uc_add_control'] = {
    enabled = function()
        return false
    end,
    pick = function()
        return 0
    end,
}
package.loaded['uc_settarget'] = {
    select_by_id = function()
        return true
    end,
}
package.loaded['uc_attack'] = {
    switch_target = function()
        return true
    end,
    engage_target = function()
        return true
    end,
}
package.loaded['uc_path_hunter'] = {
    matches_mob = function()
        return false
    end,
}

local party_data = {}
local mob_by_id = {}
local mob_array = {}
local run_calls = {}

local function set_party(data)
    party_data = data or {}
end

local function set_mob_by_id(data)
    mob_by_id = data or {}
end

local function set_mob_array(data)
    mob_array = data or {}
end

windower = {
    addon_path = '',
    register_event = function()
    end,
    send_ipc_message = function()
    end,
    dir_exists = function()
        return true
    end,
    create_dir = function()
    end,
    send_command = function()
    end,
    ffxi = {
        get_player = function()
            return {
				name = 'Self',
                status = 0,
                id = 101,
                vitals = {
                    tp = 1000,
                    hp = 1000,
                    hpp = 100,
                    mp = 100,
                    mpp = 100,
                    max_mp = 100,
                },
            }
        end,
        get_mob_by_target = function(name)
            if name == 'me' then
                return _G.__TEST_ME
            end
            if name == 't' then
                return _G.__TEST_TARGET
            end
            return nil
        end,
        get_mob_by_id = function(id)
            return mob_by_id[tonumber(id) or 0]
        end,
        get_mob_by_index = function(index)
            return mob_by_id[tonumber(index) or 0]
        end,
        get_mob_array = function()
            return mob_array
        end,
        get_party = function()
            return party_data
        end,
        get_info = function()
			return { zone = _G.__TEST_ZONE or 0 }
        end,
        get_ability_recasts = function()
            return {}
        end,
        get_spell_recasts = function()
            return {}
        end,
        get_abilities = function()
            return {
                job_abilities = { 5 },
            }
        end,
        get_spells = function()
            return {}
        end,
        run = function(direction)
            run_calls[#run_calls + 1] = direction
            return true
        end,
    },
}

package.loaded['uc_targeting_common'] = nil
package.loaded['unified_combat_core'] = nil
local targeting_common = dofile('uc_targeting_common.lua')
package.loaded['uc_targeting_common'] = targeting_common
local core = dofile('unified_combat_core.lua')
local camp_pull_registry = require('uc_camp_pull_registry')

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'assert_equal failed') .. ': expected=' .. tostring(expected) .. ' actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    assert_equal(value, true, message)
end

local function assert_false(value, message)
    assert_equal(value, false, message)
end

local function read_file(path)
    local fh, err = io.open(path, 'r')
    if not fh then
        error('failed to open ' .. tostring(path) .. ': ' .. tostring(err))
    end
    local text = fh:read('*a')
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ('missing expected text: ' .. needle))
    end
end

local function make_party_fixture()
    return {
        p0 = { mob = { id = 101, name = 'Self' } },
        p1 = { mob = { id = 202, name = 'PartyMate' } },
        a10 = { mob = { id = 303, name = 'AllianceMate' } },
        a11 = { mob = { id = 0, name = '' } },
        a12 = {},
    }
end

local function make_distance(value)
    return setmetatable({
        value = value,
    }, {
        __index = {
            sqrt = function(self)
                return math.sqrt(self.value)
            end,
        },
    })
end

local function make_mob(tbl)
    local mob = {
        id = 7001,
        valid_target = true,
        spawn_type = 16,
        hpp = 100,
        status = 0,
        claim_id = 0,
        distance = make_distance(4),
        name = 'TestMob',
    }
    if tbl then
        for key, value in pairs(tbl) do
            mob[key] = value
        end
    end
    if type(mob.distance) == 'number' then
        mob.distance = make_distance(mob.distance)
    end
    return mob
end

local function test_helper_flag_off_and_on()
    set_party(make_party_fixture())

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false
    local ids, set = targeting_common.get_friendly_combat_member_ids()
    assert_true(set[101] == true, 'flag-off self id should be present')
    assert_true(set[202] == true, 'flag-off party id should be present')
    assert_false(set[303] == true, 'flag-off alliance id should not be present')
    local _, claim_set = targeting_common.build_party_claims()
    assert_true(claim_set[202] == true, 'compat claim builder should preserve party ids')
    assert_false(claim_set[303] == true, 'compat claim builder should exclude alliance when flag off')
    assert_true(targeting_common.is_friendly_party_or_alliance_member_id(202) == true, 'flag-off party member should be valid')
    assert_false(targeting_common.is_friendly_party_or_alliance_member_id(303) == true, 'flag-off alliance member should be invalid')

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
    ids, set = targeting_common.get_friendly_combat_member_ids()
    assert_true(set[101] == true, 'flag-on self id should be present')
    assert_true(set[202] == true, 'flag-on party id should be present')
    assert_true(set[303] == true, 'flag-on alliance id should be present')
    assert_false(set[0] == true, 'nil/off-zone alliance slots must be ignored')
    _, claim_set = targeting_common.build_party_claims()
    assert_true(claim_set[303] == true, 'compat claim builder should include alliance when flag on')
    assert_true(targeting_common.is_friendly_party_or_alliance_member_id(303) == true, 'flag-on alliance member should be valid')
end

local function test_claim_validity_scope()
    set_party(make_party_fixture())
    _G.__TEST_ME = { id = 101, x = 0, y = 0 }
    _G.__TEST_TARGET = nil
    set_mob_by_id({})

    local target = make_mob({
        id = 7001,
        claim_id = 303,
        status = 0,
    })
    set_mob_array({ target })

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false
    local selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
    assert_equal(selected, nil, 'flag-off should reject alliance-only claim')

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
    selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
    assert_true(type(selected) == 'table' and selected.target_id == 7001, 'flag-on should accept alliance claim')

    target.claim_id = 909
    selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
    assert_equal(selected, nil, 'unrelated player claim must remain invalid')
end

local function test_prime_aggressive_scope()
    set_party(make_party_fixture())
    _G.__TEST_ME = { id = 101, x = 0, y = 0 }
    _G.__TEST_TARGET = nil
    local alliance_victim = { id = 303, name = 'AllianceMate' }
    set_mob_by_id({
        [303] = alliance_victim,
    })
    set_mob_array({
        make_mob({
            id = 7002,
            claim_id = 0,
            status = 1,
            target = 303,
        }),
    })

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false
    local selected = core.select_target_for_scheduler({ autotarget = true, prime = true, hunter = false, path_follow_enabled = false })
    assert_equal(selected, nil, 'flag-off should not treat alliance aggro target as prime-valid')

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
    selected = core.select_target_for_scheduler({ autotarget = true, prime = true, hunter = false, path_follow_enabled = false })
	assert_true(type(selected) == 'table' and selected.target_id == 7002, 'flag-on should treat alliance aggro target as prime-valid')
end

local function test_camp_pull_cleanup_order()
	set_party(make_party_fixture())
	_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
	_G.__TEST_ME = { id = 101, x = 0, y = 0 }
	_G.__TEST_TARGET = nil
	local older = make_mob({
		id = 7200,
		name = 'Older Pull',
		claim_id = 0,
		status = 1,
		distance = 100,
	})
	local newer = make_mob({
		id = 7201,
		name = 'Newer Pull',
		claim_id = 101,
		status = 1,
		distance = 1,
	})
	local _, friendly_claims = targeting_common.build_friendly_claims()
	camp_pull_registry.reset('alliance_target_scope_camp_pull_order')
	camp_pull_registry.register_reacted(older, friendly_claims, 50, function()
	end)
	camp_pull_registry.register_reacted(newer, friendly_claims, 50, function()
	end)
	set_mob_array({ newer, older })
	set_mob_by_id({ [older.id] = older, [newer.id] = newer })
	local selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
	assert_true(type(selected) == 'table' and selected.target_id == older.id,
		'oldest tracked camp pull must outrank a nearer newly claimed pull')

	older.claim_id = 909
	camp_pull_registry.observe({ newer, older }, friendly_claims, 50, function()
	end)
	selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
	assert_true(type(selected) == 'table' and selected.target_id == newer.id,
		'foreign-claimed older pull must yield to an eligible friendly pull')

	older.claim_id = 0
	camp_pull_registry.observe({ newer, older }, friendly_claims, 50, function()
	end)
	selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
	assert_true(type(selected) == 'table' and selected.target_id == older.id,
		'orphaned hostile must resume its original cleanup order without Prime')
	camp_pull_registry.reset('alliance_target_scope_camp_pull_complete')
end

local function test_friendly_aggression_evidence()
    set_party(make_party_fixture())
    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
    _G.__TEST_NOW = 100
    set_mob_by_id({
        [44] = { id = 202, name = 'PartyMate' },
        [45] = { id = 909, name = 'UnrelatedPlayer' },
    })
    local _, friendly_ids = targeting_common.get_friendly_combat_member_ids()

    local mob = make_mob({ id = 7100, claim_id = 0, status = 1, target_index = 44 })
    local aggressive, source = targeting_common.mob_targets_friendly_member(mob, friendly_ids, _G.__TEST_NOW)
    assert_true(aggressive, 'live mob target_index aimed at a party member must be friendly aggression evidence')
    assert_equal(source, 'target_index', 'live target-index evidence source mismatch')

    mob.target_index = 0
    mob.target = 303
    aggressive, source = targeting_common.mob_targets_friendly_member(mob, friendly_ids, _G.__TEST_NOW)
    assert_true(aggressive, 'live direct mob target aimed at an alliance member must be friendly aggression evidence')
    assert_equal(source, 'target_id', 'live direct-target evidence source mismatch')

    mob.target_index = 45
    mob.target = 0
    _G.UC_MOB_LAST_ACTION_TARGETS = {
        [7100] = { target_id = 202, at = 99.5 },
    }
    aggressive, source = targeting_common.mob_targets_friendly_member(mob, friendly_ids, _G.__TEST_NOW)
    assert_true(aggressive, 'recent hostile action against party must remain authoritative when target_index is stale')
    assert_equal(source, 'recent_action', 'recent-action evidence source mismatch')

    _G.UC_MOB_LAST_ACTION_TARGETS[7100].at = 94.9
    aggressive = targeting_common.mob_targets_friendly_member(mob, friendly_ids, _G.__TEST_NOW)
    assert_false(aggressive, 'expired action evidence and unrelated live target must not qualify an unclaimed mob')

    mob.target_index = 0
    mob.target = 909
    _G.UC_MOB_LAST_ACTION_TARGETS = {}
    aggressive = targeting_common.mob_targets_friendly_member(mob, friendly_ids, _G.__TEST_NOW)
    assert_false(aggressive, 'unclaimed mob targeting an unrelated entity must not qualify')
end

local function test_tank_victim_scope()
    set_party(make_party_fixture())
    _G.__TEST_ME = { id = 101, x = 0, y = 0 }
    _G.__TEST_TARGET = nil
    local mob = make_mob({
        id = 7003,
        status = 1,
        target = 303,
        distance = 4,
        name = 'AggroMob',
    })
    set_mob_by_id({
        [303] = { id = 303, name = 'AllianceMate', hpp = 40 },
        [7003] = mob,
    })
    set_mob_array({ mob })

    local settings = {
        tank = true,
        autotarget = true,
        tank_enmity_actions = { 'ja:Provoke' },
    }

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false
    local pick = core.select_tank_enmity_for_scheduler(settings)
    assert_equal(pick, nil, 'flag-off should not pick alliance victim for tank violation')

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
    pick = core.select_tank_enmity_for_scheduler(settings)
    assert_true(type(pick) == 'table' and pick.target_id == 7003, 'flag-on should pick alliance victim for tank violation')
end

local function test_zero_hp_and_recent_death_preserved()
    set_party(make_party_fixture())
    _G.__TEST_ME = { id = 101, x = 0, y = 0 }
    _G.__TEST_TARGET = nil
    set_mob_by_id({})

    _G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
    local target = make_mob({
        id = 7004,
        claim_id = 303,
        hpp = 0,
    })
    set_mob_array({ target })
    local selected = core.select_target_for_scheduler({ autotarget = true, prime = false, hunter = false, path_follow_enabled = false })
    assert_equal(selected, nil, 'zero-hp target must remain invalid even when alliance-claimed')

    _G.__TEST_NOW = 100
    core.last_death_target_id = 7005
    core.last_death_at = 99.5
    assert_false(core.is_live_actionable_combat_target(make_mob({
        id = 7005,
        claim_id = 303,
        hpp = 50,
    }), _G.__TEST_NOW, true), 'recent-death target must remain invalid even when alliance-claimed')
end

local function test_puller_range_gate_uses_live_puller_geometry()
    local movement_executor = {
        stop = function() windower.ffxi.run(false) end,
        run_heading = function(heading) windower.ffxi.run(heading) end,
        run_forward = function() windower.ffxi.run() end,
        turn = function(heading) windower.ffxi.turn(heading) end,
        move_towards = function(mover, target_id) mover:move_towards(target_id) end,
        move_away_from = function(mover, target_id) mover:move_away_from(target_id) end,
    }
    local puller = { id = 202, name = 'PartyMate', x = 0, y = 0 }
    local target = make_mob({
        id = 7010,
        claim_id = 202,
        x = 12,
        y = 0,
        hpp = 100,
    })
    set_party({
        p0 = { mob = { id = 101, name = 'Self' } },
        p1 = { mob = puller },
    })
    set_mob_by_id({
        [202] = puller,
        [7010] = target,
    })
    set_mob_array({ target })
    _G.__TEST_ME = { id = 101, x = 20, y = 0 }
    _G.__TEST_TARGET = target

    local settings = {
        autotarget = true,
        prime = false,
        hunter = false,
        path_follow_enabled = false,
        puller = true,
        puller_name = 'PartyMate',
        puller_engage_range = 8,
        puller_distance_only = false,
    }
    local allowed, reason, distance, max_range = core.puller_engage_allowed_for_scheduler(settings, target)
    assert_false(allowed, 'full-health mob outside puller range must be blocked')
    assert_equal(reason, 'PULLER_OUT_OF_RANGE', 'out-of-range gate reason mismatch')
    assert_equal(distance, 12, 'gate must measure mob-to-puller distance')
    assert_equal(max_range, 8, 'gate must use configured engage range')
    local selected = core.select_target_for_scheduler(settings)
    assert_true(type(selected) == 'table' and selected.target_id == 7010, 'target acquisition must remain allowed outside puller range')
    run_calls = {}
    core.last_run_active = true
    local moved = core.apply_movement_for_scheduler(settings, movement_executor)
    assert_false(moved, 'combat-close movement must not run toward a mob outside puller range')
    assert_equal(run_calls[#run_calls], false, 'out-of-range movement gate must stop the current run vector')

    target.x = 7
    allowed, reason = core.puller_engage_allowed_for_scheduler(settings, target)
    assert_true(allowed, 'mob inside puller range must be allowed')
    assert_equal(reason, 'PULLER_IN_RANGE', 'in-range gate reason mismatch')
    selected = core.select_target_for_scheduler(settings)
    assert_true(type(selected) == 'table' and selected.target_id == 7010, 'scheduler target acquisition must allow mob inside puller range')

    target.x = 12
    target.hpp = 98
    allowed, reason = core.puller_engage_allowed_for_scheduler(settings, target)
    assert_true(allowed, 'configured damaged-mob bypass must remain available')
    assert_equal(reason, 'PULLER_HPP_BYPASS', 'damaged-mob bypass reason mismatch')

    target.hpp = 100
    settings.puller_name = 'MissingPuller'
    allowed, reason = core.puller_engage_allowed_for_scheduler(settings, target)
    assert_false(allowed, 'configured unresolved puller must fail closed')
    assert_equal(reason, 'PULLER_UNRESOLVED', 'unresolved puller reason mismatch')

    settings.puller_name = 'PartyMate'
    set_mob_by_id({
        [7010] = target,
    })
    allowed, reason = core.puller_engage_allowed_for_scheduler(settings, target)
    assert_false(allowed, 'configured unavailable puller entity must fail closed')
    assert_equal(reason, 'PULLER_UNAVAILABLE', 'unavailable puller reason mismatch')
end

local function test_camp_range_gate_uses_shared_runtime_geometry()
	local camp = require('uc_camp_anchor')
	camp.clear()
	_G.__TEST_ZONE = 100
	local consumed, installed = camp.on_ipc_message('uc_camp_anchor_v1|set|100|5|5|Setter')
	assert_true(consumed and installed, 'camp test point must install')
	local target = make_mob({
		id = 7020,
		claim_id = 202,
		x = 14,
		y = 5,
		hpp = 100,
	})
	local settings = {
		puller = true,
		puller_leash_source = 'camp',
		puller_engage_range = 8,
		puller_distance_only = true,
	}
	local allowed, reason, distance = core.puller_engage_allowed_for_scheduler(settings, target)
	assert_false(allowed, 'mob outside camp range must be blocked')
	assert_equal(reason, 'CAMP_OUT_OF_RANGE', 'camp out-of-range reason mismatch')
	assert_equal(distance, 9, 'camp gate must measure mob-to-camp distance')

	target.x = 13
	allowed, reason, distance = core.puller_engage_allowed_for_scheduler(settings, target)
	assert_true(allowed, 'mob on camp boundary must be allowed')
	assert_equal(reason, 'CAMP_IN_RANGE', 'camp in-range reason mismatch')
	assert_equal(distance, 8, 'camp boundary distance mismatch')

	_G.__TEST_ZONE = 101
	allowed, reason = core.puller_engage_allowed_for_scheduler(settings, target)
	assert_false(allowed, 'camp from another zone must fail closed')
	assert_equal(reason, 'CAMP_ZONE_MISMATCH', 'camp zone mismatch reason mismatch')

	camp.clear()
	allowed, reason = core.puller_engage_allowed_for_scheduler(settings, target)
	assert_false(allowed, 'unset camp must fail closed')
	assert_equal(reason, 'CAMP_UNSET', 'unset camp reason mismatch')
	_G.__TEST_ZONE = nil
end

local function test_source_wiring()
    local targeting_source = read_file('uc_targeting_common.lua')
    local core_source = read_file('unified_combat_core.lua')
    local scheduler_source = read_file('unified_scheduler.lua')
    local combat_provider_source = read_file('uc_provider_combat.lua')

    assert_contains(targeting_source, "_G, 'UC_ENABLE_ALLIANCE_TARGET_SCOPE'", 'feature flag must be read in targeting helper')
    assert_contains(targeting_source, "function M.get_friendly_combat_member_ids(opts)", 'friendly member helper must exist')
    assert_contains(targeting_source, "function M.build_friendly_claims(opts)", 'friendly claims helper must exist')
    assert_contains(targeting_source, "function M.is_friendly_party_or_alliance_member_id(id, opts)", 'friendly id predicate must exist')
	assert_contains(targeting_source, "function M.mob_targets_friendly_member(mob, friendly_id_set, now)", 'shared friendly aggression predicate must exist')

    assert_contains(core_source, "local function is_friendly_combat_member_id(id)", 'core friendly combat helper must exist')
	assert_contains(core_source, "uc_targeting_common.mob_targets_friendly_member(mob, friendly_id_set, uc_now_s())", 'core Prime target check must use shared live-or-action aggression evidence')
    assert_contains(core_source, "not is_friendly_combat_member_id(claim_id)", 'core prime claim check must use friendly helper')
    assert_contains(core_source, "return is_friendly_combat_member_id(tid)", 'tank victim helper must use friendly helper')
    assert_contains(core_source, "if claim_tid > 0 and is_friendly_combat_member_id(claim_tid) then", 'current-target claim resolution must use friendly helper')
    assert_contains(core_source, "build_friendly_claims()", 'core claim-validity paths must use friendly claim builder')
    assert_contains(core_source, "if is_ws_action and actor ~= my_id and is_party_member_id(actor)", 'party TP/WS observation must remain party-only')

    assert_contains(scheduler_source, "local _, id_set = require('uc_targeting_common').get_friendly_combat_member_ids()", 'scheduler party id set must use friendly ids')
    assert_contains(scheduler_source, "return id_set", 'scheduler party id helper must return the friendly id set')
    assert_contains(scheduler_source, "build_friendly_claims = uc_targeting_common.build_friendly_claims", 'scheduler must inject friendly claims into providers')
    assert_contains(combat_provider_source, "local _, claims_set = build_friendly_claims()", 'combat provider claim-validity paths must use friendly claims')
    assert_contains(combat_provider_source, "local party_ids = build_party_id_set()", 'combat provider engage prime path must still build the id set through the helper')
	assert_contains(scheduler_source, "return uc_targeting_common.mob_targets_friendly_member(mob, party_ids, now_s())", 'scheduler Prime must accept live target or recent action evidence')
	assert_contains(combat_provider_source, "local unclaimed_friendly_aggressor = claim_id == 0", 'combat provider Sleep must distinguish the unclaimed friendly-aggressor path')
	assert_contains(combat_provider_source, "and mob_targets_friendly_member(mob, claims_set, ctx.now)", 'combat provider Sleep must use the shared friendly aggression predicate')
end

local function main()
    test_helper_flag_off_and_on()
    test_claim_validity_scope()
    test_prime_aggressive_scope()
	test_camp_pull_cleanup_order()
	test_friendly_aggression_evidence()
    test_tank_victim_scope()
    test_zero_hp_and_recent_death_preserved()
    test_puller_range_gate_uses_live_puller_geometry()
	test_camp_range_gate_uses_shared_runtime_geometry()
    test_source_wiring()
    io.stdout:write('selftest_alliance_target_scope: OK\n')
end

main()
