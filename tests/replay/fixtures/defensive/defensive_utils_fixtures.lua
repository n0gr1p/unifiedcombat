local function res_with_buffs(rows)
    return { buffs = rows or {} }
end

local function spell_resource_lookup(map)
    map = map or {}
    return function(name)
        return map[name]
    end
end

return {
    {
        fixture_id = "defensive_debuff_spell_known_mapping",
        helper = "debuff_spell_for_buff_id",
        description = "known debuff maps to na spell",
        input = { res_table = res_with_buffs({ [2] = { en = "Paralysis" } }), buff_id = 2 },
        expected = { result = "Paralyna" },
    },
    {
        fixture_id = "defensive_debuff_spell_petrification_id_7",
        helper = "debuff_spell_for_buff_id",
        description = "Windower Petrification buff id 7 maps directly to Stona",
        input = { res_table = res_with_buffs({ [7] = { en = "petrification" } }), buff_id = 7 },
        expected = { result = "Stona" },
    },
    {
        fixture_id = "defensive_debuff_spell_petrification_id_7_without_resource",
        helper = "debuff_spell_for_buff_id",
        description = "Petrification id 7 still maps to Stona when resource lookup is unavailable",
        input = { res_table = res_with_buffs({}), buff_id = 7 },
        expected = { result = "Stona" },
    },
    {
        fixture_id = "defensive_debuff_spell_unknown_returns_nil",
        helper = "debuff_spell_for_buff_id",
        description = "unknown debuff returns nil",
        input = { res_table = res_with_buffs({ [2] = { en = "Sleep" } }), buff_id = 2 },
        expected = { result = nil },
    },
    {
        fixture_id = "defensive_has_buff_present",
        helper = "has_buff",
        description = "buff list contains requested buff id",
        input = { buff_list = { 33, 34 }, buff_id = 33 },
        expected = { result = true },
    },
    {
        fixture_id = "defensive_has_buff_absent",
        helper = "has_buff",
        description = "buff list missing requested buff id",
        input = { buff_list = { 33, 34 }, buff_id = 35 },
        expected = { result = false },
    },
    {
        fixture_id = "defensive_estimate_missing_hp_from_max_hp",
        helper = "estimate_missing_hp",
        description = "uses exact max_hp and hp when available",
        input = { member = { hp = 700, hpp = 70, max_hp = 1000 } },
        expected = { result = 300 },
    },
    {
        fixture_id = "defensive_estimate_missing_hp_from_ratio",
        helper = "estimate_missing_hp",
        description = "derives max_hp from hp and hpp when max_hp missing",
        input = { member = { hp = 500, hpp = 50 } },
        expected = { result = 500 },
    },
    {
        fixture_id = "defensive_estimate_missing_hp_fallback_guess",
        helper = "estimate_missing_hp",
        description = "fallback estimate when hp unavailable",
        input = { member = { hp = 0, hpp = 60 } },
        expected = { result = 600 },
    },
    {
        fixture_id = "defensive_resolve_doom_buff_id_explicit_number",
        helper = "resolve_doom_buff_id",
        description = "explicit numeric doom id is preserved",
        input = { res_table = res_with_buffs({ [99] = { en = "Doom" } }), doom_buff_id = 77 },
        expected = { result = 77 },
    },
    {
        fixture_id = "defensive_resolve_doom_buff_id_from_resources",
        helper = "resolve_doom_buff_id",
        description = "resource doom entry overrides default",
        input = { res_table = res_with_buffs({ [15] = { en = "Poison" }, [42] = { en = "Doom" } }), doom_buff_id = nil },
        expected = { result = 42 },
    },
    {
        fixture_id = "defensive_resolve_doom_buff_id_default_15",
        helper = "resolve_doom_buff_id",
        description = "defaults to 15 when no doom entry found",
        input = { res_table = res_with_buffs({ [9] = { en = "Poison" } }), doom_buff_id = nil },
        expected = { result = 15 },
    },
    {
        fixture_id = "defensive_player_has_doom_true",
        helper = "player_has_doom",
        description = "player buffs contain resolved doom id",
        input = {
            resolve_fn = function() return 15 end,
            player = { buffs = { 1, 15, 33 } },
        },
        expected = { result = true },
    },
    {
        fixture_id = "defensive_player_has_doom_false",
        helper = "player_has_doom",
        description = "player buffs do not contain resolved doom id",
        input = {
            resolve_fn = function() return 15 end,
            player = { buffs = { 1, 2, 3 } },
        },
        expected = { result = false },
    },
    {
        fixture_id = "defensive_member_priority_self",
        helper = "member_priority",
        description = "self member gets highest priority",
        input = { member = { is_self = true, spawn_type = 14 } },
        expected = { result = 1 },
    },
    {
        fixture_id = "defensive_member_priority_spawn_type_14",
        helper = "member_priority",
        description = "spawn type 14 gets lower priority band",
        input = { member = { is_self = false, spawn_type = 14 } },
        expected = { result = 6 },
    },
    {
        fixture_id = "defensive_member_priority_default",
        helper = "member_priority",
        description = "default member priority is 5",
        input = { member = { is_self = false, spawn_type = 1 } },
        expected = { result = 5 },
    },
    {
        fixture_id = "defensive_pri_default_custom_action_prio",
        helper = "pri_default",
        description = "combines player prio with action prio tenth",
        input = { player_prio = 5, action_prio = 8 },
        expected = { result = 5.8 },
    },
    {
        fixture_id = "defensive_danger_level_edges",
        helper = "danger_level",
        description = "hpp edge of 20 maps to level 3",
        input = { hpp = 20 },
        expected = { result = 3 },
    },
    {
        fixture_id = "defensive_danger_level_safe",
        helper = "danger_level",
        description = "hpp above 60 maps to level 0",
        input = { hpp = 75 },
        expected = { result = 0 },
    },
    {
        fixture_id = "defensive_cure_better_when_second_nil",
        helper = "cure_better",
        description = "first candidate wins when second missing",
        input = {
            c1 = { member_prio = 5, danger = 1, target = { hpp = 70 } },
            c2 = nil,
        },
        expected = { result = true },
    },
    {
        fixture_id = "defensive_cure_better_same_prio_higher_danger",
        helper = "cure_better",
        description = "higher danger wins when priorities equal",
        input = {
            c1 = { member_prio = 5, danger = 3, target = { hpp = 40 } },
            c2 = { member_prio = 5, danger = 2, target = { hpp = 10 } },
        },
        expected = { result = true },
    },
    {
        fixture_id = "defensive_cure_tier_for_missing_hp_downshift",
        helper = "cure_tier_for_missing_hp",
        description = "drops tier when below threshold",
        input = {
            hp_missing = 140,
            max_tier = 3,
            cure_by_tier = {
                [1] = { potency = 100 },
                [2] = { potency = 200 },
                [3] = { potency = 300 },
            },
        },
        expected = { result = 1 },
    },
    {
        fixture_id = "defensive_cure_tier_for_missing_hp_keep_max",
        helper = "cure_tier_for_missing_hp",
        description = "keeps max tier when threshold met",
        input = {
            hp_missing = 260,
            max_tier = 3,
            cure_by_tier = {
                [1] = { potency = 100 },
                [2] = { potency = 200 },
                [3] = { potency = 300 },
            },
        },
        expected = { result = 3 },
    },
    {
        fixture_id = "defensive_is_bard_song_by_type",
        helper = "is_bard_song",
        description = "BardSong type returns true",
        input = {
            spell_name = "Mage's Ballad",
            lookup = spell_resource_lookup({
                ["Mage's Ballad"] = { type = "BardSong", skill = "Singing" },
            }),
        },
        expected = { result = true },
    },
    {
        fixture_id = "defensive_is_bard_song_by_skill",
        helper = "is_bard_song",
        description = "singing skill also returns true",
        input = {
            spell_name = "Custom Song",
            lookup = spell_resource_lookup({
                ["Custom Song"] = { type = "Magic", skill = "Singing" },
            }),
        },
        expected = { result = true },
    },
    {
        fixture_id = "defensive_is_bard_song_false",
        helper = "is_bard_song",
        description = "non-song spell returns false",
        input = {
            spell_name = "Cure",
            lookup = spell_resource_lookup({
                ["Cure"] = { type = "WhiteMagic", skill = "Healing Magic" },
            }),
        },
        expected = { result = false },
    },
}
