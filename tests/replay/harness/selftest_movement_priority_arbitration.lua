package.loaded['packets'] = {}
package.loaded['socket'] = {
    gettime = function()
        return (_G.__TEST_NOW or 0)
    end,
}
package.loaded['files'] = {
    new = function()
        return {}
    end,
    write = function()
        return true
    end,
    exists = function()
        return false
    end,
    read = function()
        return ''
    end,
}
package.loaded['resources'] = {
    zones = {},
}
package.loaded['uc_active_config'] = nil
package.loaded['uc_config_normalizer'] = nil

local active_config = require('uc_active_config')

local fake_target = nil
local fake_party = nil
local fake_player = { status = 0, id = 10, name = 'Tester' }
local fake_self_mob = { id = 10, x = 0, y = 0, z = 0 }
local run_calls = {}
local expected_path_file_name = 'tester_unknown_unknown_zone_Path.lua'

windower = {
    addon_path = '',
    dir_exists = function()
        return true
    end,
    create_dir = function()
    end,
    register_event = function()
    end,
    send_ipc_message = function()
    end,
    ffxi = {
        get_player = function()
            return fake_player
        end,
        get_mob_by_target = function(name)
            if name == 't' then
                return fake_target
            elseif name == 'me' then
                return fake_self_mob
            end
            return nil
        end,
        get_info = function()
            return { zone = 0 }
        end,
        get_party = function()
            return fake_party
        end,
        get_mob_by_id = function()
            return nil
        end,
        run = function(x, y)
            run_calls[#run_calls + 1] = { x = x, y = y }
        end,
    },
}

_G.UC_IsCombatParticipant = function(settings)
    return settings and settings.combat_participant == true
end

local follow = dofile('uc_party_follow.lua')

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

local function set_active_profile(config)
    local ok, err = active_config.set_active_profile({
        version = 2,
        profile = {
            schema_version = 2,
            engine = 'UC',
            source = 'selftest',
        },
        config = config or {},
    })
    if ok ~= true then
        error('failed to set active profile: ' .. tostring(err))
    end
end

local function set_state(tbl)
    _G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = tbl.flag
    _G.UC_COMBAT_INTENT_UNTIL = tbl.intent_until
    _G.UC_MOVEMENT_OWNER = tbl.owner
    _G.UC_MOVEMENT_LOCK_UNTIL = tbl.lock_until
    _G.UC_FIGHT_FOLLOW_ACTIVE_UNTIL = tbl.fight_follow_until
    _G.UC_PREENGAGE_APPROACH_ACTIVE = tbl.preengage
    _G.__TEST_NOW = tbl.now
    fake_player.status = tbl.player_status or 0
    fake_target = tbl.target
end

local function main()
    local settings = { combat_participant = true }

    set_state({
        flag = false,
        now = 10,
        intent_until = 20,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    local suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'flag off must preserve old behavior')
    assert_equal(reason, 'flag_off', 'flag off reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 20,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = {
            valid_target = true,
            spawn_type = 16,
            hpp = 100,
        },
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, true, 'combat intent active must suppress')
    assert_equal(reason, 'combat_intent_target', 'combat intent reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'core',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, true, 'core movement lock must suppress')
    assert_equal(reason, 'movement_lock', 'movement lock reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'scheduler_formation',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now({ combat_participant = false }, _G.__TEST_NOW)
    assert_equal(suppress, true, 'formation ownership must suppress follow even while disengaged')
    assert_equal(reason, 'formation_movement_lock', 'formation movement lock reason mismatch')

    set_state({
        flag = false,
        now = 10,
        intent_until = 0,
        owner = 'scheduler_formation',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now({ combat_participant = false }, _G.__TEST_NOW)
    assert_equal(suppress, true, 'formation ownership must suppress follow when transition arbitration is disabled')
    assert_equal(reason, 'formation_movement_lock', 'unconditional formation movement lock reason mismatch')

    set_state({
        flag = false,
        now = 10,
        intent_until = 0,
        owner = 'scheduler_reaction',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now({ combat_participant = false }, _G.__TEST_NOW)
    assert_equal(suppress, true, 'active or holding reaction range ownership must unconditionally suppress Party Follow')
    assert_equal(reason, 'reaction_movement_lock', 'reaction range movement lock reason mismatch')

    set_state({
        flag = false,
        now = 16,
        intent_until = 0,
        owner = 'scheduler_reaction',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now({ combat_participant = false }, _G.__TEST_NOW)
    assert_equal(suppress, false, 'expired reaction range ownership must allow normal movement to resume')
    assert_equal(reason, 'flag_off', 'expired reaction range ownership release reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'scheduler',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now({ combat_participant = false }, _G.__TEST_NOW)
    assert_equal(suppress, true, 'scheduler ownership must prevent party follow from starting during a Bard lane hold')
    assert_equal(reason, 'scheduler_movement_lock', 'scheduler movement lock reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'scheduler_brd',
        lock_until = 15,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now({ combat_participant = false }, _G.__TEST_NOW)
    assert_equal(suppress, true, 'Bard reposition ownership must prevent party follow from replacing its vector')
    assert_equal(reason, 'bard_reposition_movement_lock', 'Bard reposition movement lock reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 20,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'stale combat intent without target must release follow')
    assert_equal(reason, 'combat_intent_stale', 'stale combat intent reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'idle state must not suppress')
    assert_equal(reason, 'none', 'idle reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 20,
        preengage = false,
        target = {
            valid_target = true,
            spawn_type = 16,
            hpp = 100,
        },
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, true, 'fight follow hold with active target must suppress')
    assert_equal(reason, 'fight_follow_hold_target', 'fight follow hold reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 20,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'stale fight follow hold without target must release follow')
    assert_equal(reason, 'fight_follow_hold_stale', 'stale fight follow hold reason mismatch')

    set_state({
        flag = true,
        now = 25,
        intent_until = 20,
        owner = 'core',
        lock_until = 24,
        fight_follow_until = 24,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'suppression must expire when windows expire')
    assert_equal(reason, 'none', 'expiry reason mismatch')

    set_state({
        flag = true,
        now = 10,
        intent_until = 0,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 0,
        preengage = false,
        target = {
            valid_target = true,
            spawn_type = 16,
            hpp = 100,
        },
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'live target alone must not suppress after hardening')
    assert_equal(reason, 'none', 'live target fail-closed reason mismatch')

    set_state({
        flag = true,
        now = 30,
        intent_until = 50,
        owner = 'none',
        lock_until = 0,
        fight_follow_until = 40,
        preengage = false,
        target = nil,
    })
    suppress, reason = follow.should_suppress_follow_or_path_return_now(settings, _G.__TEST_NOW)
    assert_equal(suppress, false, 'combat ended with no target and no lock must not suppress')
    assert_equal(reason, 'combat_intent_stale', 'combat ended release reason mismatch')

    _G.UC_IsFollowParticipant = function()
        return true
    end
    _G.UC_SETTINGS = {
        camp_pulling = {
            enabled = false,
        },
        party_follow = false,
        party_follow_id = 0,
        party_follow_leader_name = '',
        party_follow_min = 0.5,
        party_follow_max = 50,
        fight_follow_min = 3.0,
    }
    set_active_profile({
        follow = {
            party = {
                enabled = true,
                leader_id = 77,
                leader_name = 'Leader',
                min = 1.25,
                max = 22,
            },
        },
    })
    _G.UC_MOVEMENT_OWNER = nil
    _G.UC_MOVEMENT_LOCK_UNTIL = nil
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'follow', 'party follow prerender must honor active config when flat settings differ')

    fake_party = {
        p1 = {
            mob = {
                id = 77,
                name = 'Leader',
                x = 12,
                y = 0,
            },
        },
    }
    _G.UC_SETTINGS = {
        camp_pulling = {
            enabled = false,
        },
        party_follow = false,
        party_follow_id = 0,
        party_follow_leader_name = 'Leader',
        party_follow_min = 1.25,
        party_follow_max = 22,
        fight_follow_min = 3.0,
    }
    set_active_profile({
        follow = {
            party = {
                enabled = false,
            },
        },
    })
    run_calls = {}
    _G.UC_MOVEMENT_OWNER = 'scheduler'
    _G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 5
    follow.prerender()
    assert_equal(#run_calls, 0, 'disabled party follow must not stop another movement owner')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'scheduler', 'disabled party follow must preserve another movement owner')

    run_calls = {}
    _G.UC_MOVEMENT_OWNER = 'follow'
    _G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 5
    follow.prerender()
    assert_equal(#run_calls, 1, 'disabled party follow must stop its own active vector once')
    assert_equal(run_calls[1].x, false, 'disabled party-follow stop call shape')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'none', 'disabled party follow must release its own ownership')

    set_active_profile({
        follow = {
            party = {
                enabled = true,
                leader_id = 0,
                leader_name = 'Leader',
                min = 1.25,
                max = 22,
            },
        },
    })
    run_calls = {}
    _G.UC_MOVEMENT_OWNER = nil
    _G.UC_MOVEMENT_LOCK_UNTIL = nil
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'follow', 'party follow prerender must resolve a named leader even when leader_id is runtime-owned')
    assert_true(#run_calls > 0, 'party follow prerender must issue movement for a named leader with no durable id')

    _G.Start_Engine = true
    _G.UC_SETTINGS.camp_pulling.enabled = false
    set_active_profile({
        combat = {
            pulling = { enabled = true },
        },
        follow = {
            party = {
                enabled = true,
                leader_id = 0,
                leader_name = 'Leader',
                min = 1.25,
                max = 22,
            },
        },
    })
    _G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
    _G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = _G.__TEST_NOW + 0.4
    follow.prerender()
    assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP, false,
        'canonical camp-puller ON + flat OFF must clear party-follow catch-up intent')
    assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL, 0,
        'canonical camp-puller ownership must clear the party-follow catch-up hold window')

    _G.UC_SETTINGS.camp_pulling.enabled = true
    set_active_profile({
        combat = {
            pulling = { enabled = false },
        },
        follow = {
            party = {
                enabled = true,
                leader_id = 0,
                leader_name = 'Leader',
                min = 1.25,
                max = 22,
            },
        },
    })
    run_calls = {}
    _G.UC_MOVEMENT_OWNER = nil
    _G.UC_MOVEMENT_LOCK_UNTIL = nil
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'follow',
        'canonical camp-puller OFF + flat ON must not suppress party follow')
    assert_true(#run_calls > 0,
        'canonical camp-puller OFF must allow party-follow movement despite flat ON')

    _G.UC_SETTINGS.camp_pulling.enabled = false
    _G.Start_Engine = false
    follow.prerender()

    run_calls = {}
    _G.UC_MOVEMENT_OWNER = 'scheduler'
    _G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 5
    follow.prerender()
    assert_equal(#run_calls, 1, 'active scheduler ownership must stop the existing party-follow vector')
    assert_equal(run_calls[1].x, false, 'scheduler ownership party-follow stop call shape')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'scheduler', 'party-follow suppression must preserve scheduler ownership')
    follow.prerender()
    assert_equal(#run_calls, 1, 'party follow must not start or repeatedly stop movement while scheduler ownership remains active')

    local generic_runtime = require('uc_generic_formation_runtime').build({
        solver = require('uc_generic_formation'),
        dispatcher = require('uc_scheduler_dispatcher'),
        run = windower.ffxi.run,
        source_prefix = 'formation_follow_regression',
    })
    local formation_config = {
        enabled = true,
        encounter = 'sortie_ghatjot',
        placement = {
            mode = 'radial_band',
            anchor = 'boss',
            preferred_radius = 2,
            minimum_radius = 2,
            maximum_radius = 2,
            radius_step = 1,
            angle_step_deg = 90,
        },
        hysteresis = {
            start_distance = 0.5,
            stop_distance = 0.25,
        },
        constraints = {
            avoid_encounter_hazards = false,
            hazard_margin = 0,
        },
    }
    set_active_profile({
        ownership = {
            domain_movement_enabled = true,
            domain_follow_enabled = true,
        },
        movement = {
            enabled = true,
            formation = formation_config,
        },
        follow = {
            party = {
                enabled = true,
                leader_id = 77,
                leader_name = 'Leader',
                min = 1.25,
                max = 22,
            },
        },
    })
    _G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = false
    _G.UC_MOVEMENT_OWNER = 'none'
    _G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW
    fake_player.status = 0
    fake_self_mob.x = 8
    fake_self_mob.y = 0
    run_calls = {}
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'follow', 'enabled Party Follow must establish the competing pre-formation vector')
    assert_equal(#run_calls, 1, 'enabled Party Follow regression setup must issue one leader vector')

    local formation_acted, formation_reason, formation_owns = generic_runtime.run_tick({
        config = formation_config,
        me = { id = 10, name = 'Tester', x = 8, y = 0 },
        boss = { id = 900, name = 'Apex Crab', x = 0, y = 0 },
        encounter_origin = nil,
        party_members = {},
        encounter_hazards = {},
        was_moving = false,
    })
    assert_equal(formation_acted, true, 'generic formation must dispatch its corrective vector with Party Follow enabled')
    assert_equal(formation_reason, 'FORMATION_REPOSITION', 'generic formation/Party Follow regression reason mismatch')
    assert_equal(formation_owns, true, 'generic formation must claim movement from Party Follow')
    assert_equal(#run_calls, 2, 'generic formation must replace the Party Follow vector exactly once')
    _G.UC_MOVEMENT_OWNER = 'scheduler_formation'
    _G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 0.4
	_G.UC_FORMATION_STATUS = {
		enabled = true,
		kind = 'generic',
		phase = 'active',
		reason = 'FORMATION_REPOSITION',
	}

    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'scheduler_formation',
        'Party Follow must not reclaim movement from generic formation when transition arbitration is disabled')
    assert_equal(#run_calls, 3, 'Party Follow must issue only its one-time transition stop under generic formation ownership')
    assert_equal(run_calls[3].x, false, 'generic formation ownership transition stop call shape')
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP, false,
		'active generic formation must clear Party Follow catch-up intent for defensive casting')
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL, 0,
		'active generic formation must clear the Party Follow catch-up hold window')

    formation_acted, formation_reason, formation_owns = generic_runtime.run_tick({
        config = formation_config,
        me = { id = 10, name = 'Tester', x = 8, y = 0 },
        boss = { id = 900, name = 'Apex Crab', x = 0, y = 0 },
        encounter_origin = nil,
        party_members = {},
        encounter_hazards = {},
        was_moving = true,
    })
    assert_equal(formation_acted, true, 'generic formation must resume after the Party Follow transition stop')
    assert_equal(formation_reason, 'FORMATION_REPOSITION', 'resumed generic formation reason mismatch')
    assert_equal(formation_owns, true, 'resumed generic formation must retain movement ownership')
    assert_equal(#run_calls, 4, 'generic formation must restore its vector after the transition stop')
    _G.UC_MOVEMENT_OWNER = 'scheduler_formation'
    _G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 0.4
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'scheduler_formation',
        'Party Follow must continue yielding to generic formation ownership')
    assert_equal(#run_calls, 4, 'Party Follow must not overwrite the restored generic formation vector')

	_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = true
	_G.UC_MOVEMENT_OWNER = 'scheduler_brd'
	_G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 0.4
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = _G.__TEST_NOW + 0.4
	follow.prerender()
	assert_equal(_G.UC_MOVEMENT_OWNER, 'scheduler_brd',
		'Bard reposition must retain movement ownership while formation is active')
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP, false,
		'active formation must keep Party Follow catch-up from suppressing Bard song coverage work')
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL, 0,
		'Bard reposition under active formation must not retain a Party Follow catch-up window')

	_G.UC_MOVEMENT_OWNER = 'scheduler'
	_G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 0.4
	_G.UC_MOVEMENT_MODE = 'CAST_FREEZE'
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = true
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = _G.__TEST_NOW + 0.4
	follow.prerender()
	assert_equal(_G.UC_MOVEMENT_OWNER, 'scheduler',
		'defensive/GEO cast settling must retain scheduler ownership while formation is active')
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP, false,
		'active formation must keep Party Follow catch-up from suppressing defensive and GEO spells')
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL, 0,
		'defensive/GEO casting under active formation must not retain a Party Follow catch-up window')

	_G.UC_FORMATION_STATUS = {
		enabled = true,
		kind = 'generic',
		phase = 'origin_captured',
		reason = 'FORMATION_WAITING_FOR_ENGAGE',
	}
	_G.UC_MOVEMENT_OWNER = 'scheduler_brd'
	_G.UC_MOVEMENT_LOCK_UNTIL = _G.__TEST_NOW + 0.4
	_G.UC_MOVEMENT_MODE = 'BRD_REPOSITION'
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP = false
	_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL = 0
	follow.prerender()
	assert_equal(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP, true,
		'Party Follow catch-up must remain active when formation is waiting rather than moving')
	assert_true(_G.UC_PARTY_FOLLOW_NEEDS_CATCHUP_UNTIL > _G.__TEST_NOW,
		'waiting formation must preserve the normal Party Follow catch-up window')
	_G.UC_FORMATION_STATUS = nil
	_G.UC_MOVEMENT_MODE = nil
    fake_self_mob.x = 0
    fake_self_mob.y = 0

    run_calls = {}
    _G.UC_ZONE_SUSPEND_UNTIL = _G.__TEST_NOW + 10
    _G.UC_MOVEMENT_OWNER = nil
    _G.UC_MOVEMENT_LOCK_UNTIL = nil
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'follow', 'party follow prerender must still own movement during zone grace')
    assert_true(#run_calls > 0, 'party follow prerender must still issue movement during zone grace')
    _G.UC_ZONE_SUSPEND_UNTIL = nil
    fake_party = nil

    _G.UC_SETTINGS.party_follow = true
    _G.UC_SETTINGS.party_follow_id = 77
    _G.UC_SETTINGS.party_follow_leader_name = 'Leader'
    set_active_profile({
        follow = {},
    })
    run_calls = {}
    _G.UC_MOVEMENT_OWNER = nil
    _G.UC_MOVEMENT_LOCK_UNTIL = nil
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER == 'follow', false,
        'party follow must fail closed when canonical follow.party is missing despite flat follow enabled')
    assert_equal(#run_calls, 0,
        'missing canonical follow.party must not issue flat-fallback movement')

    package.loaded['uc_party_follow'] = follow
    local pathing = dofile('uc_pathing.lua')
    if type(pathing) ~= 'table' then
        error('uc_pathing must load successfully with arbitration helper available')
    end

    local scheduler_source = assert(io.open('unified_scheduler.lua', 'rb')):read('*a')
    local formation_owner_block = scheduler_source:match("if formation_owns then(.-)return formation_acted, formation_reason")
    assert_true(type(formation_owner_block) == 'string', 'scheduler formation ownership block must be present')
    assert_true(formation_owner_block:find("UC_MOVEMENT_OWNER = 'scheduler_formation'", 1, true) ~= nil,
        'scheduler must refresh formation ownership even when the current proposal is hold')

    Start_Engine = true
    _G.UC_SETTINGS = {
        camp_pulling = {
            enabled = false,
        },
        path_recording = false,
        path_follow_enabled = false,
        path_file_name = expected_path_file_name,
        path_route_type = 'patrol',
        path_points = {
            { x = 5, y = 0, z = 0 },
        },
        path_party_gate_yalms = 3.0,
        path_resume_index_window = 12,
        path_distance_to_start = 0,
        party_follow = false,
        party_follow_id = 0,
    }
    run_calls = {}
    _G.__TEST_NOW = 100
    set_active_profile({
        ownership = {
            domain_movement_enabled = true,
        },
        movement = {
            path = {
                recording = false,
                follow_enabled = true,
                file_name = expected_path_file_name,
                route_type = 'patrol',
                party_gate_yalms = 3.0,
                resume_index_window = 12,
            },
        },
        follow = {
            party = {
                enabled = false,
                leader_id = 0,
            },
        },
    })
    pathing.tick()
    assert_true(#run_calls > 0, 'pathing tick must drive movement when active path-follow is enabled')
    assert_equal(run_calls[#run_calls].x, 1, 'pathing tick must use active path-follow enablement when flat value differs')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'path', 'active path run must claim path ownership')
    assert_true((tonumber(_G.UC_MOVEMENT_LOCK_UNTIL) or 0) > _G.__TEST_NOW,
        'active path run must publish a short movement lock')
    follow.prerender()
    assert_equal(_G.UC_MOVEMENT_OWNER, 'path',
        'disabled party follow prerender must preserve path ownership from the earlier frame pass')

    run_calls = {}
    _G.__TEST_NOW = 101
    _G.UC_SETTINGS.path_follow_enabled = true
    set_active_profile({
        ownership = {
            domain_movement_enabled = true,
        },
        movement = {
            path = {},
        },
        follow = {
            party = {
                enabled = false,
                leader_id = 0,
            },
        },
    })
    pathing.tick()
    assert_equal(#run_calls, 1, 'missing canonical path-follow policy must stop the prior path vector once')
    assert_equal(run_calls[1].x, false, 'missing canonical path-follow policy must fail closed despite flat follow enabled')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'none', 'canonical path-follow default OFF must release path ownership')

    run_calls = {}
    _G.__TEST_NOW = 101.5
    set_active_profile({
        ownership = {
            domain_movement_enabled = true,
        },
        movement = {
            path = {
                follow_enabled = true,
                party_gate_yalms = 3.0,
                resume_index_window = 12,
            },
        },
        follow = {
            party = {
                enabled = false,
                leader_id = 0,
            },
        },
    })
    pathing.tick()
    assert_true(#run_calls > 0, 'canonical path-follow enablement must reacquire path movement after fail-closed stop')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'path', 're-enabled canonical path follow must own movement before domain shutdown')

    run_calls = {}
    _G.__TEST_NOW = 102
    set_active_profile({
        ownership = {
            domain_movement_enabled = false,
        },
    })
    pathing.tick()
    assert_equal(#run_calls, 1, 'disabling movement domain must stop a path-owned vector once')
    assert_equal(run_calls[1].x, false, 'movement-domain stop call shape')
    assert_equal(_G.UC_MOVEMENT_OWNER, 'none', 'movement-domain stop must release path ownership')

    _G.__TEST_NOW = 103
    pathing.tick()
    assert_equal(#run_calls, 1, 'disabled movement domain must not repeat the released path stop')

    if rawget(_G, 'UC_SCHED_P1_ENABLE_DISPATCHER_RUN_VECTOR_OWNERSHIP') ~= nil then
        error('movement arbitration test must not require ownership flags')
    end

    io.stdout:write('selftest_movement_priority_arbitration: OK\n')
end

main()
