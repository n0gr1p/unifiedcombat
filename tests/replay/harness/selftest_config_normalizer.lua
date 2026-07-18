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
        defensive_doom_water = true,
        def_remove_enemy_buffs = true,
        defensive_na_enabled = true,
        defensive_buff_enabled = true,
        defensive_critical_hpp = 40,
        defensive_medium_hpp = 60,
        defensive_overwrite_enabled = true,
        defensive_overwrite_interval = 99,
        defensive_buff_self_only = false,
        defensive_buffs = 'Haste',
        defensive_targeted_buffs = 'Terrasjr:Honor March|Nyoourke:Valor Minuet V',
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
        brd_use_clarion_call = false,
        brd_use_marcato = true,
        brd_marcato_song = 'Honor March',
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
        scheduler_dark_launch_combat = true,
        scheduler_dark_launch_defensive = true,
        scheduler_dark_launch_movement = true,
        scheduler_dark_launch_maintenance = true,
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
            },
            doom = {
                holy_water_enabled = true,
            },
            na = {
                enabled = true,
            },
            enemy_buffs = {
                remove = true,
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
        movement = {
            enabled = true,
            move = true,
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
                ids = { 11, 22 },
                puller = true,
                puller_name = 'Niightsiide',
                puller_id = 33,
                engage_range = 8.5,
                puller_distance_only = true,
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
                use_clarion_call = false,
                use_marcato = true,
                marcato_song = 'Honor March',
            },
            geo = {
                bubble = 'Entrust',
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
            scheduler_dark_launch_combat = true,
            scheduler_dark_launch_defensive = true,
            scheduler_dark_launch_movement = true,
            scheduler_dark_launch_maintenance = true,
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
    assert_true(type(default_from_normalize.movement) == 'table', 'movement domain missing')
    assert_true(type(default_from_normalize.follow) == 'table', 'follow domain missing')
    assert_true(type(default_from_normalize.targeting) == 'table', 'targeting domain missing')
    assert_true(type(default_from_normalize.tank) == 'table', 'tank domain missing')
    assert_true(type(default_from_normalize.sleep) == 'table', 'sleep domain missing')
    assert_equal(default_from_normalize.follow.partner.engage_range, 6.0, 'default puller engage range mismatch')
    assert_equal(default_from_normalize.sleep.max_target_range, 6.0, 'default sleep target range mismatch')
    assert_true(type(default_from_normalize.spells) == 'table', 'spells domain missing')
    assert_true(type(default_from_normalize.maintenance) == 'table', 'maintenance domain missing')
    assert_true(type(default_from_normalize.debug) == 'table', 'debug domain missing')
    assert_true(type(default_from_normalize.ownership) == 'table', 'ownership domain missing')
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
    assert_equal(flat_config.abilities.enabled, true, 'abilities enabled mismatch')
    assert_equal(flat_config.abilities.configured[1], 'Savage Blade', 'abilities list mismatch')
    assert_equal(flat_config.abilities.legacy_slots[6], 'Consume Mana', 'legacy ability slot mismatch')
    assert_equal(flat_config.targeting.legacy_slots[2], 'Mob Two', 'legacy target slot mismatch')
    assert_equal(flat_config.targeting.targets[1], 'Alpha', 'targets list mismatch')
    assert_equal(flat_config.defensive.provider, 'external', 'defensive provider mismatch')
    assert_equal(flat_config.defensive.cure.min_tier, 2, 'defensive cure min tier mismatch')
    assert_equal(flat_config.defensive.cure.max_tier, 5, 'defensive cure max tier mismatch')
    assert_equal(flat_config.defensive.cure.min_missing_hp, 300, 'defensive cure missing hp mismatch')
    assert_equal(flat_config.defensive.enemy_buffs.remove, true, 'defensive enemy buffs mismatch')
    assert_equal(flat_config.defensive.buffs.list, 'Haste', 'defensive buffs mismatch')
    assert_equal(flat_config.defensive.buffs.targeted[1].character, 'Terrasjr', 'defensive targeted buff character mismatch')
    assert_equal(flat_config.defensive.buffs.targeted[1].buff, 'Honor March', 'defensive targeted buff name mismatch')
    assert_equal(flat_config.movement.spacing.band_min, -1.2, 'spacing band min mismatch')
    assert_equal(flat_config.movement.path.file_name, 'route.json', 'path file mismatch')
    assert_equal(flat_config.movement.path.hunter_targets[1], 'Target A', 'path hunter targets mismatch')
    assert_equal(flat_config.follow.party.leader_name, 'Leader', 'party follow leader mismatch')
    assert_equal(flat_config.follow.partner.secondary_enabled, true, 'partner2 mismatch')
    assert_equal(flat_config.follow.partner.puller_name, 'Niightsiide', 'flat puller name mismatch')
    assert_equal(flat_config.follow.partner.engage_range, 9.5, 'flat puller engage range mismatch')
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
    assert_equal(flat_config.maintenance.brd.marcato_song, 'Honor March', 'flat BRD Marcato song mismatch')
    assert_equal(flat_config.debug.ja_debug, true, 'debug flag mismatch')
    assert_equal(flat_config.ownership.scheduler_dark_launch_maintenance, true, 'ownership flag mismatch')
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
    assert_equal(nested_config.defensive.cure.min_tier, 5, 'nested defensive cure min tier mismatch')
    assert_equal(nested_config.defensive.buffs.targeted[2].character, 'Nyoourke', 'nested targeted buff character mismatch')
    assert_equal(nested_config.defensive.buffs.targeted[2].buff, 'Valor Minuet V', 'nested targeted buff name mismatch')
    assert_equal(nested_config.movement.path.points[1].x, 1, 'nested path points mismatch')
    assert_equal(nested_config.maintenance.brd.enabled, true, 'nested maintenance BRD enabled mismatch')
    assert_equal(nested_config.maintenance.brd.songs[2], 'Victory March', 'nested maintenance BRD song mismatch')
    assert_equal(nested_config.maintenance.brd.dummy_songs[1], "Army's Paeon", 'nested maintenance BRD dummy mismatch')
    assert_equal(nested_config.maintenance.brd.use_nitro, true, 'nested maintenance BRD NITRO mismatch')
    assert_equal(nested_config.maintenance.brd.marcato_song, 'Honor March', 'nested maintenance BRD Marcato mismatch')
    assert_equal(nested_config.maintenance.geo.bubble, 'Entrust', 'nested maintenance GEO mismatch')
    assert_equal(nested_config.follow.partner.puller_name, 'Niightsiide', 'nested puller name mismatch')
    assert_equal(nested_config.follow.partner.engage_range, 8.5, 'nested puller engage range mismatch')
    assert_equal(nested_config.sleep.max_target_range, 12.0, 'nested sleep target range mismatch')

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
