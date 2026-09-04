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

local function deep_clone(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for key, inner_value in pairs(value) do
        out[key] = deep_clone(inner_value)
    end
    return out
end

local function deep_equal(actual, expected, seen)
    if actual == expected then
        return true
    end
    if type(actual) ~= type(expected) then
        return false
    end
    if type(actual) ~= 'table' then
        return actual == expected
    end

    local pair_seen = seen or {}
    local seen_key = actual
    pair_seen[seen_key] = pair_seen[seen_key] or {}
    if pair_seen[seen_key][expected] then
        return true
    end
    pair_seen[seen_key][expected] = true

    local actual_count = 0
    for key, actual_value in pairs(actual) do
        actual_count = actual_count + 1
        if not deep_equal(actual_value, expected[key], pair_seen) then
            return false
        end
    end

    local expected_count = 0
    for _ in pairs(expected) do
        expected_count = expected_count + 1
    end

    return actual_count == expected_count
end

local function assert_deep_equal(actual, expected, message)
    if not deep_equal(actual, expected) then
        error(message or 'tables are not deeply equal')
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

local function snapshot_globals()
    local snapshot = {}
    for key in pairs(_G) do
        snapshot[key] = true
    end
    return snapshot
end

local function assert_same_globals(before, after)
    for key in pairs(before) do
        assert_true(after[key] == true, 'global key disappeared: ' .. tostring(key))
    end
    for key in pairs(after) do
        assert_true(before[key] == true, 'module introduced unexpected _G key: ' .. tostring(key))
    end
end

local function build_flat_settings()
    return {
        engine_mode = 'DD2',
        show_ingame_ui = true,
        engine_enabled = true,
        ability_active = true,
        abilities = { 'Savage Blade', 'Fast Blade' },
        ability1 = 'Hasso',
        ability2 = 'Third Eye',
        ability3 = 'Berserk',
        ability4 = 'Aggressor',
        ability5 = 'Meditate',
        ability6 = 'Consume Mana',
        wsabilities = { 'Leaden Salute', 'Wildfire' },
        weaponskill = 'Leaden Salute',
        ws1 = 'Wildfire',
        weaponskill_active = true,
        weaponskill_allow_aoe = false,
		fast_skillchain = true,
        skillchain_target = 'darkness',
        ws_mode = 'always',
        aftermath_enabled = true,
        aftermath_ws = 'Aftermath WS',
        autotarget = true,
        spam = true,
        closer = true,
        manual = true,
        prime = true,
        static = true,
        face = true,
        defensive_enabled = true,
        defensive_provider = 'external',
        defensive_cure_enabled = true,
        def_heal_min_tier_cure = 2,
        def_heal_max_tier_cure = 5,
        def_heal_min_missing_hp = 300,
        def_heal_ignore_trusts = false,
		defensive_curaga_enabled = true,
		defensive_curaga_min_targets = 9,
		defensive_waltz_enabled = true,
		defensive_waltz_tp_reserve = 3500,
		defensive_divine_waltz_min_targets = 1,
        defensive_doom_water = true,
        def_charm_sleeper_enabled = true,
        def_sleep_waker_enabled = true,
        def_remove_enemy_buffs = true,
        def_maintain_enemy_debuffs = true,
        defensive_enemy_debuffs = 'Dia III|Distract III',
        defensive_na_enabled = true,
        defensive_na_limit_enabled = true,
        defensive_na_priority = 'Poison|Paralyze|Dia',
        defensive_buff_enabled = true,
        defensive_critical_hpp = 40,
        defensive_medium_hpp = 60,
        defensive_overwrite_enabled = true,
        defensive_overwrite_interval = 99,
        defensive_buff_self_only = false,
        defensive_buffs = 'Haste',
        defensive_targeted_buffs = 'Terrasjr:Honor March|Nyoourke:Valor Minuet V',
        encounter_enabled = true,
        encounter_id = 'sortie_ghatjot',
        encounter_water_damage = 'enforce',
        encounter_water_skillchain = 'warn',
        encounter_repeat_action_wall = 'off',
        encounter_repeat_action_guard_s = 12.5,
        move = true,
        spacing = true,
        spacing_band_min = -1.2,
        spacing_band_max = 0.5,
        spacing_model_size_floor = 1.1,
        spacing_use_prediction = false,
        spacing_lookahead_s = 0.75,
        spacing_repel_hold_ticks = 7,
        spacing_overlap_deadband = 0.11,
        spacing_repel_weight = 0.45,
        spacing_band_deadband = 0.22,
        partner = true,
        partner2 = true,
        puller = true,
        puller_engage_range = 9.5,
        puller_distance_only = true,
        puller_name = 'Niightsiide',
		nyzul_coordinator_name = 'Redrogue',
		nyzul_anchor_name = 'Terrasjr',
		nyzul_parking_order = 'Nyoourke|Ponponponponp',
        partner_id = 11,
        partner_id2 = 22,
        partner_ids = { 11, 22 },
        puller_id = 33,
        fight_leader = true,
        fight_leader_id = 44,
        party_follow = true,
        party_follow_id = 55,
        party_follow_leader_name = 'Leader',
        party_follow_min = 1.5,
        party_follow_max = 40,
        fight_follow_min = 4.5,
        fight_follow_hold_s = 9.5,
        add_control = true,
        add_priority_names = { 'Mob A', 'Mob B' },
        target1 = 'Mob One',
        target2 = 'Mob Two',
        target3 = 'Mob Three',
        targets = { 'Alpha', 'Beta' },
        targetability = 'Claim',
        targetability_active = true,
        ignore = { 101, 202 },
        target_ignore_names = { 'Ignore Me' },
        tank = true,
        tank_enmity_actions = { 'Provoke', 'Flash' },
        sleep = true,
        sleepspells = { 'Sleep II', 'Sleepga' },
        sleepspell = 'Sleep II',
        sleep_max_target_range = 14.0,
        spell = 'Dia',
        spell_active = true,
        dd2_spell_slots = { { spell = 'Dia' } },
        cor_roll_1 = 'Chaos Roll',
        cor_roll_2 = 'Samurai Roll',
        cor_crooked_roll_slot = 2,
        cor_elevens = true,
        cor_luzaf_range_override = true,
        cor_roll_range_selected = 'Apex',
        cor_roll_range_require_ids = { 1, 2 },
        brd_maintenance_enabled = true,
        brd_songs = 'Honor March|Victory March',
        brd_dummy_songs = "Army's Paeon|Army's Paeon II",
        brd_use_nitro = true,
		brd_use_soul_voice = true,
        brd_use_clarion_call = false,
        brd_use_marcato = true,
        brd_marcato_song = 'Honor March',
		brd_targeted_songs = "Tankone,Tanktwo:Mage's Ballad III,Mage's Ballad II",
		brd_recovery_range_yalms = 12.4,
		brd_reposition_for_party_songs = true,
        path_recording = true,
        path_follow_enabled = true,
        path_file_name = 'route.json',
        path_route_type = 'loop',
        path_distance_to_start = 12.5,
        path_points = { { x = 1, y = 2 } },
        path_party_gate_yalms = 4.5,
        path_resume_index_window = 10,
        path_hunter_targets = { 'Target A' },
        path_hunter_max_z_delta = 3.0,
        path_hunter_max_target_range = 25.0,
        path_hunter_claim_timeout_s = 6.0,
        path_hunter_ignore_cooldown_s = 30.0,
        path_pull_action_type = 'spell',
        path_pull_action_name = 'Dia',
        debug = true,
        log_combat_sched = true,
        log_ja_sched = true,
        log_ja_debug = true,
        log_def_sched = true,
        log_tank_sched = true,
        domain_combat_enabled = false,
        domain_defensive_enabled = false,
        domain_movement_enabled = false,
        domain_maintenance_enabled = false,
        domain_follow_enabled = false,
        pause_automation_while_weakened = true,
        sub = true,
        sub2 = true,
        solo = true,
        aeonic = true,
        color = true,
        command = true,
        hunter = true,
        profiles = {
            UC = {
                WAR = {
                    flag = true,
                },
            },
        },
    }
end

local function build_nested_settings()
    return {
        profile = {
            engine = 'UC',
            character = 'Neo',
            main_job = 'BRD',
            sub_job = 'WHM',
            source = 'profile-file',
        },
        ui = {
            show_ingame_ui = true,
        },
        command = {
            engine_enabled_default = true,
        },
        combat = {
            enabled = false,
            autotarget = true,
            spam = true,
            closer = true,
            manual = false,
            prime = true,
            static = false,
            face = true,
            weaponskill = {
                enabled = true,
                primary = 'Savage Blade',
                mode = 'smart',
                allow_aoe = false,
				fast_skillchain = true,
                aftermath_enabled = true,
                aftermath_ws = 'Aftermath WS',
            },
        },
        abilities = {
            enabled = true,
            configured = { 'Geo Frazzle' },
            legacy_slots = { 'Hasso', 'Third Eye' },
            wsabilities = { 'Wildfire' },
        },
        defensive = {
            enabled = true,
            provider = 'internal',
            cure = {
                enabled = true,
                min_tier = 5,
                max_tier = 6,
                min_missing_hp = 400,
                ignore_trusts = false,
				curaga = { enabled = true, min_targets = 4 },
            },
			waltz = { enabled = true, tp_reserve = 1200, divine_min_targets = 2 },
            doom = {
                holy_water_enabled = true,
            },
            charm_sleeper = {
                enabled = true,
            },
            sleep_waker = {
                enabled = true,
            },
            na = {
                enabled = true,
                limit_enabled = true,
                priority = 'Poison|Paralyze',
            },
            enemy_buffs = {
                remove = true,
            },
            enemy_debuffs = {
                enabled = true,
                list = 'Dia III|Frazzle III',
            },
            buffs = {
                enabled = true,
                self_only = false,
                list = 'Haste',
                targeted = {
                    { character = 'Terrasjr', buff = 'Honor March' },
                    { character = 'Nyoourke', buff = 'Valor Minuet V' },
                },
                overwrite_enabled = true,
                overwrite_interval = 10,
            },
            thresholds = {
                critical_hpp = 20,
                medium_hpp = 30,
            },
        },
        encounter = {
            enabled = true,
            id = 'sortie_ghatjot',
            policy = {
                water_damage = 'enforce',
                water_skillchain = 'enforce',
                repeat_action_wall = 'off',
            },
            tuning = {
                repeat_action_guard_s = 10.0,
            },
        },
        movement = {
            enabled = true,
            move = true,
            formation = {
                enabled = true,
                encounter = 'lilith_easy',
                role = 'HEALER',
                tank_name = 'Terrasjr',
                required_party_names = { 'Terrasjr', 'Etamame' },
                safe_radius = 15,
                tank = {
                    accept_radius = 1,
                    return_radius = 2.5,
                },
                dps = {
                    flank_angle_deg = 100,
                    melee_radius = 3.5,
                    position_tolerance = 2,
                },
                healer = {
                    preferred_radius = 11,
                    minimum_boss_distance = 7,
                    maximum_party_range = 17,
                    cone_half_angle_deg = 45,
                    cone_safety_margin_deg = 20,
                    sample_step_deg = 5,
                },
            },
            spacing = {
                enabled = true,
                band_min = -1,
                band_max = 1,
                model_size_floor = 2,
                use_prediction = false,
                lookahead_s = 0.5,
                repel_hold_ticks = 4,
                overlap_deadband = 0.2,
                repel_weight = 0.4,
                band_deadband = 0.3,
            },
            path = {
                recording = true,
                follow_enabled = true,
                file_name = 'route',
                route_type = 'line',
                distance_to_start = 5,
                points = { { x = 1, y = 2 } },
                party_gate_yalms = 6,
                resume_index_window = 7,
                hunter_targets = { 'Hunter Target' },
                hunter_max_z_delta = 1,
                hunter_max_target_range = 10,
                hunter_claim_timeout_s = 2,
                hunter_ignore_cooldown_s = 3,
                pull_action_type = 'ja',
                pull_action_name = 'Provoke',
            },
        },
        follow = {
            enabled = true,
            party = {
                enabled = true,
                leader_id = 55,
                leader_name = 'Leader',
                min = 1.5,
                max = 40,
            },
            fight = {
                leader = true,
                leader_id = 44,
                min = 4.5,
                hold_s = 9.5,
            },
            partner = {
                enabled = true,
                secondary_enabled = true,
                names = { 'Ponponponponpon', 'Nyoourke' },
                ids = { 11, 22 },
                puller = true,
                puller_name = 'Niightsiide',
                puller_id = 33,
                engage_range = 8.5,
                puller_distance_only = true,
            },
			nyzul = {
				coordinator_name = 'Redrogue',
				anchor_name = 'Terrasjr',
				parking_order = { 'Nyoourke', 'Ponponponponp' },
			},
        },
        targeting = {
            add_control = true,
            add_priority_names = { 'Mob A', 'Mob B' },
            legacy_slots = { 'Mob One', 'Mob Two', 'Mob Three' },
            targets = { 'Alpha', 'Beta' },
            targetability = {
                enabled = true,
                action = 'Claim',
            },
            ignore = { 101, 202 },
            target_ignore_names = { 'Ignore Me' },
        },
        tank = {
            enabled = true,
            enmity = {
                actions = { 'Provoke', 'Flash' },
            },
        },
        sleep = {
            enabled = true,
            order = { 'Sleep II', 'Sleepga' },
            legacy_primary = 'Sleep II',
            max_target_range = 12.0,
        },
        spells = {
            enabled = true,
            configured = 'Dia',
            dd2_slots = {
                { spell = 'Dia' },
            },
        },
        maintenance = {
            enabled = true,
            cor = {
                roll_1 = 'Chaos Roll',
                roll_2 = 'Samurai Roll',
                crooked_roll_slot = 2,
                elevens = true,
                luzaf_range_override = true,
                range_selected = 'Apex',
                range_require_ids = { 1, 2 },
            },
            brd = {
                enabled = true,
                songs = { 'Honor March', 'Victory March' },
                dummy_songs = { "Army's Paeon", "Army's Paeon II" },
                use_nitro = true,
				use_soul_voice = true,
                use_clarion_call = false,
                use_marcato = true,
                marcato_song = 'Honor March',
				targeted_songs = {
					{ recipients = { 'Tankone', 'Tanktwo' }, priority_songs = { "Mage's Ballad III", "Mage's Ballad II" } },
				},
				recovery_range_yalms = 17.5,
				reposition_for_party_songs = true,
            },
            geo = {
                enabled = true,
                geo_spell = 'Geo-Frailty',
                geo_target = {
                    kind = 'current_enemy',
                },
                indi_spell = 'Indi-Haste',
                ordering = 'geo_first',
                require_camp = true,
                camp_tolerance_yalms = 1.5,
                enemy_geo_requires_camp_radius = true,
                unknown_existing_policy = 'wait_for_clear',
                entrust = {
                    enabled = false,
                },
                luopan = {
                    placement = 'camp',
                    use_blaze_of_glory = true,
                    use_ecliptic_attrition = false,
                    use_life_cycle = true,
                    life_cycle_hpp = 45,
                    replace_out_of_position = true,
                    max_camp_distance_yalms = 7.0,
                },
            },
        },
        debug = {
            enabled = true,
            combat_sched = true,
            ja_sched = true,
            ja_debug = true,
            def_sched = true,
            tank_sched = true,
        },
        ownership = {
            domain_combat_enabled = false,
            domain_defensive_enabled = false,
            domain_movement_enabled = false,
            domain_maintenance_enabled = false,
            domain_follow_enabled = false,
            pause_automation_while_weakened = true,
        },
        legacy = {
            sub = true,
            sub2 = true,
            solo = true,
            aeonic = true,
            color = true,
            command = true,
            hunter = true,
        },
        profiles = {
            UC = {
                WAR = {
                    flag = true,
                },
            },
        },
    }
end

local function main()
    local before_globals = snapshot_globals()
    package.loaded['uc_config_normalizer'] = nil
    local normalizer = require('uc_config_normalizer')
    local after_globals = snapshot_globals()

    assert_same_globals(before_globals, after_globals)
    assert_equal(normalizer.version(), 1, 'normalizer version mismatch')

    local meta = {
        character = 'Peter',
        main_job = 'BRD',
        sub_job = 'WHM',
        source = 'profile-file',
    }

    local default_from_normalize = normalizer.normalize(nil, meta)
    local default_from_builder = normalizer.default_config(meta)
    assert_deep_equal(default_from_normalize, default_from_builder, 'nil input should match default config')
    assert_equal(default_from_normalize.profile.character, 'Peter', 'default profile character mismatch')
    assert_equal(default_from_normalize.profile.main_job, 'BRD', 'default profile main_job mismatch')
    assert_equal(default_from_normalize.profile.sub_job, 'WHM', 'default profile sub_job mismatch')
    assert_equal(default_from_normalize.profile.source, 'profile-file', 'default profile source mismatch')
    assert_true(type(default_from_normalize.combat) == 'table', 'combat domain missing')
    assert_true(type(default_from_normalize.abilities) == 'table', 'abilities domain missing')
    assert_true(type(default_from_normalize.defensive) == 'table', 'defensive domain missing')
    assert_true(type(default_from_normalize.encounter) == 'table', 'encounter domain missing')
    assert_equal(default_from_normalize.encounter.enabled, false, 'encounter must default disabled')
    assert_equal(default_from_normalize.defensive.na.limit_enabled, false, 'status-removal limiting must default disabled')
    assert_equal(default_from_normalize.defensive.na.priority, '', 'status-removal priority must default empty')
    assert_true(type(default_from_normalize.movement) == 'table', 'movement domain missing')
    assert_true(type(default_from_normalize.follow) == 'table', 'follow domain missing')
    assert_true(type(default_from_normalize.targeting) == 'table', 'targeting domain missing')
    assert_true(type(default_from_normalize.tank) == 'table', 'tank domain missing')
    assert_true(type(default_from_normalize.sleep) == 'table', 'sleep domain missing')
    assert_equal(default_from_normalize.follow.partner.engage_range, 6.0, 'default puller engage range mismatch')
	assert_equal(default_from_normalize.follow.partner.leash_source, 'player', 'default puller leash source mismatch')
    assert_equal(default_from_normalize.sleep.max_target_range, 6.0, 'default sleep target range mismatch')
    assert_true(type(default_from_normalize.spells) == 'table', 'spells domain missing')
    assert_true(type(default_from_normalize.maintenance) == 'table', 'maintenance domain missing')
    assert_equal(default_from_normalize.maintenance.geo.enabled, false, 'default GEO maintenance must be disabled')
    assert_equal(default_from_normalize.maintenance.geo.ordering, 'geo_first', 'default GEO ordering mismatch')
    assert_equal(default_from_normalize.maintenance.geo.luopan.placement, 'target', 'default GEO placement mismatch')
    assert_equal(default_from_normalize.maintenance.geo.unknown_existing_policy, 'wait_for_clear', 'default GEO ownership policy mismatch')
    assert_equal(default_from_normalize.combat.pulling.enabled, false, 'default camp pulling must be disabled')
	assert_equal(default_from_normalize.combat.weaponskill.allow_aoe, true, 'Smart WS AoE preference must default true')
	assert_equal(default_from_normalize.combat.weaponskill.fast_skillchain, false, 'Fast Skillchain must default off')
    assert_equal(default_from_normalize.combat.pulling.mode, 'camp', 'default camp pulling mode mismatch')
    assert_true(type(default_from_normalize.debug) == 'table', 'debug domain missing')
    assert_true(type(default_from_normalize.ownership) == 'table', 'ownership domain missing')
    assert_equal(default_from_normalize.ownership.pause_automation_while_weakened, false, 'recovery hold must default off')
    assert_true(type(default_from_normalize.legacy) == 'table', 'legacy domain missing')

    local flat_settings = build_flat_settings()
    local flat_snapshot = deep_clone(flat_settings)
    local flat_config = normalizer.normalize(flat_settings, meta)
    assert_deep_equal(flat_settings, flat_snapshot, 'flat input should not be mutated')
    assert_equal(flat_config.profile.engine, 'DD2', 'flat profile engine mismatch')
    assert_equal(flat_config.ui.show_ingame_ui, true, 'ui flag mismatch')
    assert_equal(flat_config.command.engine_enabled_default, true, 'command default mismatch')
    assert_equal(flat_config.combat.enabled, false, 'combat domain flag mismatch')
    assert_equal(flat_config.combat.autotarget, true, 'combat autotarget mismatch')
    assert_equal(flat_config.combat.weaponskill.primary, 'Leaden Salute', 'combat ws primary mismatch')
    assert_equal(flat_config.combat.weaponskill.enabled, true, 'combat ws enabled mismatch')
	assert_equal(flat_config.combat.weaponskill.allow_aoe, false, 'flat Smart WS AoE preference mismatch')
	assert_equal(flat_config.combat.weaponskill.fast_skillchain, true, 'flat Fast Skillchain preference mismatch')
    assert_equal(flat_config.combat.weaponskill.skillchain_target, 'darkness', 'skillchain target normalization')
    assert_equal(flat_config.abilities.enabled, true, 'abilities enabled mismatch')
    assert_equal(flat_config.abilities.configured[1], 'Savage Blade', 'abilities list mismatch')
    assert_equal(flat_config.abilities.legacy_slots[6], 'Consume Mana', 'legacy ability slot mismatch')
    assert_equal(flat_config.targeting.legacy_slots[2], 'Mob Two', 'legacy target slot mismatch')
    assert_equal(flat_config.targeting.targets[1], 'Alpha', 'targets list mismatch')
    assert_equal(flat_config.defensive.provider, 'external', 'defensive provider mismatch')
    assert_equal(flat_config.defensive.cure.min_tier, 2, 'defensive cure min tier mismatch')
    assert_equal(flat_config.defensive.cure.max_tier, 5, 'defensive cure max tier mismatch')
    assert_equal(flat_config.defensive.cure.min_missing_hp, 300, 'defensive cure missing hp mismatch')
	assert_equal(flat_config.defensive.cure.curaga.enabled, true, 'flat Curaga enabled mismatch')
	assert_equal(flat_config.defensive.cure.curaga.min_targets, 6, 'flat Curaga minimum must clamp to six')
	assert_equal(flat_config.defensive.waltz.enabled, true, 'flat Waltz enabled mismatch')
	assert_equal(flat_config.defensive.waltz.tp_reserve, 3000, 'flat Waltz reserve must clamp to 3000')
	assert_equal(flat_config.defensive.waltz.divine_min_targets, 2, 'flat Divine Waltz minimum must clamp to two')
    assert_equal(flat_config.defensive.charm_sleeper.enabled, true, 'flat charm sleeper mismatch')
    assert_equal(flat_config.defensive.sleep_waker.enabled, true, 'flat sleep waker mismatch')
    assert_equal(flat_config.defensive.enemy_buffs.remove, true, 'defensive enemy buffs mismatch')
    assert_equal(flat_config.defensive.enemy_debuffs.enabled, true, 'flat enemy debuff maintenance mismatch')
    assert_equal(flat_config.defensive.enemy_debuffs.list, 'Dia III|Distract III', 'flat enemy debuff list mismatch')
    assert_equal(flat_config.defensive.na.limit_enabled, true, 'flat status-removal limit mismatch')
    assert_equal(flat_config.defensive.na.priority, 'Poison|Paralyze|Dia', 'flat status-removal priority mismatch')
    assert_equal(flat_config.defensive.buffs.list, 'Haste', 'defensive buffs mismatch')
    assert_equal(flat_config.defensive.buffs.targeted[1].character, 'Terrasjr', 'defensive targeted buff character mismatch')
    assert_equal(flat_config.defensive.buffs.targeted[1].buff, 'Honor March', 'defensive targeted buff name mismatch')
    assert_equal(flat_config.encounter.enabled, true, 'flat encounter enabled mismatch')
    assert_equal(flat_config.encounter.id, 'sortie_ghatjot', 'flat encounter ID mismatch')
    assert_equal(flat_config.encounter.policy.water_skillchain, 'warn', 'flat encounter policy mismatch')
    assert_equal(flat_config.encounter.tuning.repeat_action_guard_s, 12.5, 'flat encounter tuning mismatch')
    assert_equal(flat_config.movement.spacing.band_min, -1.2, 'spacing band min mismatch')
    assert_equal(flat_config.movement.path.file_name, 'route.json', 'path file mismatch')
    assert_equal(flat_config.movement.path.hunter_targets[1], 'Target A', 'path hunter targets mismatch')
    assert_equal(flat_config.follow.party.leader_name, 'Leader', 'party follow leader mismatch')
    assert_equal(flat_config.follow.partner.secondary_enabled, true, 'partner2 mismatch')
    assert_equal(flat_config.follow.partner.puller_name, 'Niightsiide', 'flat puller name mismatch')
	assert_equal(flat_config.follow.partner.leash_source, 'player', 'flat puller leash source mismatch')
    assert_equal(flat_config.follow.partner.engage_range, 9.5, 'flat puller engage range mismatch')
	assert_equal(flat_config.follow.nyzul.coordinator_name, 'Redrogue', 'flat Nyzul coordinator mismatch')
	assert_equal(flat_config.follow.nyzul.anchor_name, 'Terrasjr', 'flat Nyzul anchor mismatch')
	assert_equal(flat_config.follow.nyzul.parking_order[1], 'Nyoourke', 'flat Nyzul parking order mismatch')
    assert_equal(flat_config.tank.enabled, true, 'tank mismatch')
    assert_equal(flat_config.tank.enmity.actions[2], 'Flash', 'tank enmity actions mismatch')
    assert_equal(flat_config.sleep.order[2], 'Sleepga', 'sleep order mismatch')
    assert_equal(flat_config.sleep.legacy_primary, 'Sleep II', 'sleep legacy primary mismatch')
    assert_equal(flat_config.sleep.max_target_range, 14.0, 'flat sleep target range mismatch')
    assert_equal(flat_config.spells.configured, 'Dia', 'spell configured mismatch')
    assert_equal(flat_config.spells.dd2_slots[1].spell, 'Dia', 'dd2 slots mismatch')
    assert_equal(flat_config.maintenance.cor.roll_1, 'Chaos Roll', 'cor roll 1 mismatch')
    assert_equal(flat_config.maintenance.cor.range_require_ids[2], 2, 'cor range requirement mismatch')
    assert_equal(flat_config.maintenance.brd.enabled, true, 'flat BRD maintenance enabled mismatch')
    assert_equal(flat_config.maintenance.brd.songs[2], 'Victory March', 'flat BRD song list mismatch')
    assert_equal(flat_config.maintenance.brd.dummy_songs[2], "Army's Paeon II", 'flat BRD dummy song list mismatch')
    assert_equal(flat_config.maintenance.brd.use_nitro, true, 'flat BRD NITRO mismatch')
	assert_equal(flat_config.maintenance.brd.use_soul_voice, true, 'flat BRD Soul Voice mismatch')
	assert_equal(flat_config.maintenance.brd.targeted_songs[1].recipients[2], 'Tanktwo', 'flat BRD targeted recipient mismatch')
	assert_equal(flat_config.maintenance.brd.targeted_songs[1].priority_songs[2], "Mage's Ballad II", 'flat BRD targeted priority mismatch')
	local malformed_targeted_config = normalizer.normalize({ brd_targeted_songs = 'TargetWithoutSongs' })
	assert_equal(#malformed_targeted_config.maintenance.brd.targeted_songs, 1, 'malformed BRD targeted config must remain visible to runtime validation')
	assert_equal(#malformed_targeted_config.maintenance.brd.targeted_songs[1].recipients, 0, 'malformed BRD targeted config must not normalize into a valid empty policy')
    assert_equal(flat_config.maintenance.brd.marcato_song, 'Honor March', 'flat BRD Marcato song mismatch')
	assert_equal(flat_config.maintenance.brd.recovery_range_yalms, 12.4, 'flat BRD recovery range mismatch')
	assert_equal(flat_config.maintenance.brd.reposition_for_party_songs, true, 'flat BRD reposition policy mismatch')
    assert_equal(flat_config.debug.ja_debug, true, 'debug flag mismatch')
    assert_equal(flat_config.ownership.domain_maintenance_enabled, false, 'maintenance domain mismatch')
    assert_equal(flat_config.ownership.pause_automation_while_weakened, true, 'flat recovery hold mismatch')
    assert_equal(flat_config.legacy.command, true, 'legacy ambiguous flag mismatch')
    assert_equal(flat_config.legacy.profiles.UC.WAR.flag, true, 'legacy profiles mismatch')

    local nested_settings = build_nested_settings()
    local nested_snapshot = deep_clone(nested_settings)
    local nested_config = normalizer.normalize(nested_settings, {
        character = 'Neo',
        main_job = 'BRD',
        sub_job = 'WHM',
        source = 'bridge',
    })

    assert_equal(nested_config.profile.character, 'Neo', 'nested profile character mismatch')
    assert_equal(nested_config.profile.main_job, 'BRD', 'nested profile main_job mismatch')
    assert_equal(nested_config.profile.source, 'bridge', 'nested profile source mismatch')
    assert_equal(nested_config.combat.enabled, false, 'nested combat enabled mismatch')
    assert_equal(nested_config.combat.weaponskill.enabled, true, 'nested combat ws enabled mismatch')
	assert_equal(nested_config.combat.weaponskill.allow_aoe, false, 'nested Smart WS AoE preference mismatch')
	assert_equal(nested_config.combat.weaponskill.fast_skillchain, true, 'nested Fast Skillchain preference mismatch')
	assert_equal(nested_config.ownership.pause_automation_while_weakened, true, 'nested recovery hold mismatch')
    assert_equal(nested_config.defensive.cure.min_tier, 5, 'nested defensive cure min tier mismatch')
	assert_equal(nested_config.defensive.cure.curaga.enabled, true, 'nested Curaga enabled mismatch')
	assert_equal(nested_config.defensive.cure.curaga.min_targets, 4, 'nested Curaga minimum mismatch')
	assert_equal(nested_config.defensive.waltz.enabled, true, 'nested Waltz enabled mismatch')
	assert_equal(nested_config.defensive.waltz.tp_reserve, 1200, 'nested Waltz reserve mismatch')
	assert_equal(nested_config.defensive.waltz.divine_min_targets, 2, 'nested Divine Waltz minimum mismatch')
    assert_equal(nested_config.defensive.charm_sleeper.enabled, true, 'nested charm sleeper mismatch')
    assert_equal(nested_config.defensive.sleep_waker.enabled, true, 'nested sleep waker mismatch')
    assert_equal(nested_config.defensive.enemy_debuffs.enabled, true, 'nested enemy debuff maintenance mismatch')
    assert_equal(nested_config.defensive.enemy_debuffs.list, 'Dia III|Frazzle III', 'nested enemy debuff list mismatch')
    assert_equal(nested_config.defensive.na.limit_enabled, true, 'nested status-removal limit mismatch')
    assert_equal(nested_config.defensive.na.priority, 'Poison|Paralyze', 'nested status-removal priority mismatch')
    assert_equal(nested_config.defensive.buffs.targeted[2].character, 'Nyoourke', 'nested targeted buff character mismatch')
    assert_equal(nested_config.defensive.buffs.targeted[2].buff, 'Valor Minuet V', 'nested targeted buff name mismatch')
    assert_equal(nested_config.encounter.enabled, true, 'nested encounter enabled mismatch')
    assert_equal(nested_config.encounter.id, 'sortie_ghatjot', 'nested encounter ID mismatch')
    assert_equal(nested_config.encounter.policy.water_damage, 'enforce', 'nested encounter policy mismatch')
    assert_equal(nested_config.movement.formation.enabled, true, 'nested formation enabled mismatch')
    assert_equal(nested_config.movement.formation.role, 'healer', 'nested formation role mismatch')
    assert_equal(nested_config.movement.formation.tank_name, 'Terrasjr', 'nested formation tank name mismatch')
    assert_equal(nested_config.movement.formation.required_party_names[2], 'Etamame', 'nested formation required party mismatch')
    assert_equal(nested_config.movement.formation.healer.sample_step_deg, 5, 'nested formation healer sample mismatch')
    assert_equal(nested_config.movement.path.points[1].x, 1, 'nested path points mismatch')
    assert_equal(nested_config.maintenance.brd.enabled, true, 'nested maintenance BRD enabled mismatch')
    assert_equal(nested_config.maintenance.brd.songs[2], 'Victory March', 'nested maintenance BRD song mismatch')
    assert_equal(nested_config.maintenance.brd.dummy_songs[1], "Army's Paeon", 'nested maintenance BRD dummy mismatch')
    assert_equal(nested_config.maintenance.brd.use_nitro, true, 'nested maintenance BRD NITRO mismatch')
	assert_equal(nested_config.maintenance.brd.use_soul_voice, true, 'nested maintenance BRD Soul Voice mismatch')
	assert_equal(nested_config.maintenance.brd.targeted_songs[1].priority_songs[1], "Mage's Ballad III", 'nested BRD targeted song mismatch')
    assert_equal(nested_config.maintenance.brd.marcato_song, 'Honor March', 'nested maintenance BRD Marcato mismatch')
	assert_equal(nested_config.maintenance.brd.recovery_range_yalms, 17.5, 'nested maintenance BRD recovery range mismatch')
	assert_equal(nested_config.maintenance.brd.reposition_for_party_songs, true, 'nested BRD reposition policy mismatch')
    assert_equal(nested_config.maintenance.geo.enabled, true, 'nested maintenance GEO enabled mismatch')
    assert_equal(nested_config.maintenance.geo.geo_spell, 'Geo-Frailty', 'nested maintenance GEO spell mismatch')
    assert_equal(nested_config.maintenance.geo.indi_spell, 'Indi-Haste', 'nested maintenance Indi spell mismatch')
    assert_equal(nested_config.maintenance.geo.enemy_geo_requires_camp_radius, true, 'nested enemy Geo camp-radius policy mismatch')
    assert_equal(nested_config.maintenance.geo.luopan.placement, 'camp', 'nested GEO placement mismatch')
    assert_equal(nested_config.maintenance.geo.luopan.life_cycle_hpp, 45, 'nested GEO Life Cycle threshold mismatch')
    assert_equal(nested_config.follow.partner.puller_name, 'Niightsiide', 'nested puller name mismatch')
	assert_equal(nested_config.follow.partner.leash_source, 'player', 'nested puller leash source mismatch')
	assert_equal(nested_config.follow.partner.names[1], 'Ponponponponpon', 'nested primary partner name mismatch')
	assert_equal(nested_config.follow.partner.names[2], 'Nyoourke', 'nested secondary partner name mismatch')
    assert_equal(nested_config.follow.partner.engage_range, 8.5, 'nested puller engage range mismatch')
	assert_equal(nested_config.follow.nyzul.coordinator_name, 'Redrogue', 'nested Nyzul coordinator mismatch')
	assert_equal(nested_config.follow.nyzul.anchor_name, 'Terrasjr', 'nested Nyzul anchor mismatch')
	assert_equal(nested_config.follow.nyzul.parking_order[2], 'Ponponponponp', 'nested Nyzul parking order mismatch')
    assert_equal(nested_config.sleep.max_target_range, 12.0, 'nested sleep target range mismatch')

    local legacy_na = normalizer.normalize({ defensive_na_enabled = true }, meta).defensive.na
    assert_equal(legacy_na.enabled, true, 'legacy NA enablement mismatch')
    assert_equal(legacy_na.limit_enabled, false, 'older profiles must retain unrestricted NA behavior')
    assert_equal(legacy_na.priority, '', 'older profiles must default to an empty status-removal priority')

    assert_error_contains(function()
        normalizer.normalize({ encounter = { enabled = true, id = '' } }, meta)
    end, 'requires config.encounter.id', 'enabled encounter without identity must fail')

    assert_error_contains(function()
        normalizer.normalize({ encounter = { enabled = true, id = 'ghatjot' } }, meta)
    end, 'must be sortie_ghatjot, sortie_dhartok, or kei', 'unsupported encounter identity must fail')

    assert_error_contains(function()
        normalizer.normalize({
            encounter = {
                enabled = true,
                id = 'sortie_ghatjot',
                policy = { water_damage = 'maybe' },
            },
        }, meta)
    end, 'must be enforce, warn, or off', 'invalid encounter policy mode must fail')

    assert_error_contains(function()
        normalizer.normalize({
            encounter = {
                enabled = true,
                id = 'sortie_ghatjot',
                tuning = { repeat_action_guard_s = 0 },
            },
        }, meta)
    end, 'must be a positive number', 'invalid encounter tuning must fail')

    local camp_config = normalizer.normalize({ puller_leash_source = 'camp' }, meta)
    assert_equal(camp_config.follow.partner.leash_source, 'camp', 'camp puller leash source mismatch')

    local migrated_geo = normalizer.normalize({
        maintenance_geo = { 'Geo-Frailty', 'Indi-Haste' },
    }, meta).maintenance.geo
    assert_equal(migrated_geo.enabled, false, 'legacy GEO list migration must not enable execution')
    assert_equal(migrated_geo.geo_spell, 'Geo-Frailty', 'legacy GEO spell migration mismatch')
    assert_equal(migrated_geo.indi_spell, 'Indi-Haste', 'legacy Indi spell migration mismatch')
    assert_equal(migrated_geo.luopan.placement, 'target', 'legacy GEO placement must default to target')

    local old_replace_geo = normalizer.normalize({
        maintenance = {
            geo = {
                luopan = {
                    replace_out_of_position = true,
                },
            },
        },
    }, meta).maintenance.geo
    assert_equal(old_replace_geo.luopan.placement, 'target', 'old replacement setting must not enable camp placement')

    local explicit_target_geo = normalizer.normalize({
        maintenance = {
            geo = {
                luopan = {
                    placement = 'target',
                },
            },
        },
    }, meta).maintenance.geo
    assert_equal(explicit_target_geo.luopan.placement, 'target', 'explicit target placement mismatch')

    local explicit_camp_geo = normalizer.normalize({
        maintenance = {
            geo = {
                require_camp = true,
                luopan = {
                    placement = 'camp',
                },
            },
        },
    }, meta).maintenance.geo
    assert_equal(explicit_camp_geo.luopan.placement, 'camp', 'explicit camp placement mismatch')

    assert_error_contains(function()
        normalizer.normalize({
            maintenance = {
                geo = {
                    luopan = {
                        placement = 'caster',
                    },
                },
            },
        }, meta)
    end, 'maintenance.geo.luopan.placement', 'unsupported GEO placement must fail')

    local remote_camp_geo = normalizer.normalize({
        maintenance = {
            geo = {
                require_camp = false,
                luopan = {
                    placement = 'camp',
                },
            },
        },
    }, meta).maintenance.geo
    assert_equal(remote_camp_geo.luopan.placement, 'camp', 'camp placement must remain enabled independently')
    assert_equal(remote_camp_geo.require_camp, false, 'camp placement must not force require_camp')

    assert_error_contains(function()
        normalizer.normalize({
            maintenance = {
                geo = {
                    enabled = true,
                    geo_spell = 'Geo-Frailty',
                },
            },
        }, meta)
    end, 'maintenance.geo.indi_spell', 'enabled GEO config must require an Indi spell')

    assert_error_contains(function()
        normalizer.normalize({
            maintenance_geo = { 'Geo-Frailty', 'Geo-Fury' },
        }, meta)
    end, 'more than one Geo-', 'ambiguous legacy GEO lists must fail')

    assert_error_contains(function()
        normalizer.normalize({
            maintenance = {
                geo = {
                    enabled = false,
                    camp_tolerance_yalms = 0 / 0,
                },
            },
        }, meta)
    end, 'finite number', 'non-finite GEO distances must fail')

    local camp_pulling = normalizer.normalize({
        combat = {
            pulling = {
                enabled = true,
                mode = 'camp',
                action = {
                    type = 'spell',
                    name = 'Dia II',
                },
                targets = {
                    { name = 'Apex Crab', priority = 20 },
                    { name = 'Apex Pugil', priority = 10 },
                },
                match_mode = 'exact',
                max_active_mobs = 2,
                replenish_below_hpp = 25,
                leash_yalms = 40.0,
                max_z_delta = 3.0,
                cast_range_ratio = 0.85,
                settle_seconds = 0.5,
                reaction_timeout_seconds = 5.0,
                retry_limit = 3,
                retry_window_seconds = 3.0,
                target_cooldown_seconds = 25.0,
                camp_arrival_yalms = 1.0,
            },
        },
    }, meta).combat.pulling
    assert_equal(camp_pulling.enabled, true, 'camp pulling enabled mismatch')
    assert_equal(camp_pulling.action.name, 'Dia II', 'camp pulling action mismatch')
    assert_equal(camp_pulling.targets[1].priority, 20, 'camp pulling target priority mismatch')
    assert_equal(camp_pulling.max_active_mobs, 2, 'camp pulling quota mismatch')

    assert_error_contains(function()
        normalizer.normalize({
            combat = {
                pulling = {
                    enabled = true,
                    action = {
                        type = 'ranged',
                        name = 'Longbow',
                    },
                    targets = {
                        { name = 'Apex Crab', priority = 1 },
                    },
                },
            },
        }, meta)
    end, 'combat.pulling.action.type', 'invalid pull action type must fail')

    nested_config.abilities.configured[1] = 'Changed'
    nested_config.targeting.targets[1] = 'Changed'
    nested_config.movement.path.points[1].x = 99
    nested_config.maintenance.cor.range_require_ids[1] = 99
    nested_config.maintenance.brd.songs[1] = 'Changed'
    nested_config.legacy.profiles.UC.WAR.flag = false

    assert_deep_equal(nested_settings, nested_snapshot, 'nested input should not be mutated by output edits')

    io.stdout:write('selftest_config_normalizer: OK\n')
end

main()
