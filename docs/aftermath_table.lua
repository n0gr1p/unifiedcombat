-- aftermath_weapons.lua
--
-- FFXI Ultimate Weapon Aftermath table for Windower / GearSwap-style usage.
--
-- Assumptions:
--   * Relic entries assume Level 119 III relics.
--   * Empyrean entries assume Level 119 III empyreans.
--   * Mythic / Ergon entries assume Level 119 III / modern final state.
--   * Prime entries assume Stage 3+ Prime weapons.
--   * Shields and instruments are excluded because they do not generate normal player Aftermath.
--
-- Windower buff IDs:
--   270 = Aftermath: Lv.1
--   271 = Aftermath: Lv.2
--   272 = Aftermath: Lv.3
--   273 = Aftermath
--
-- Important:
--   * TP Bonus does NOT affect aftermath tier, duration, or effect.
--   * Use real TP spent.
--   * Relic aftermath uses flat buff ID 273 with TP-varying duration.
--   * Mythic/Ergon, Empyrean, Aeonic, and Prime use tiered buff IDs 270/271/272.
--   * Mythic has the most per-weapon duration weirdness; see the special profiles below.

local M = {}

M.buff_ids = {
    aftermath_lv1 = 270,
    aftermath_lv2 = 271,
    aftermath_lv3 = 272,
    aftermath_flat = 273,
}

M.buff_names = {
    [270] = "Aftermath: Lv.1",
    [271] = "Aftermath: Lv.2",
    [272] = "Aftermath: Lv.3",
    [273] = "Aftermath",
}

M.tp_bonus_affects_aftermath = false

-- =====================================================================
-- Helper duration profiles
-- =====================================================================

M.aftermath_profiles = {
    -- Relic Level 119 III
    -- Flat buff ID 273. TP changes duration only.
    relic_119_iii = {
        family = "Relic",
        style = "flat",
        has_am_levels = false,
        buff_id = 273,
        buff_name = "Aftermath",
        duration_model = "formula",
        duration_formula = "math.floor(0.06 * real_tp_spent)",
        tp_bonus_affects_aftermath = false,

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                buff_id = 273,
                buff_name = "Aftermath",
                duration_seconds_at_floor = 60,
                duration_seconds_at_cap = 119,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                buff_id = 273,
                buff_name = "Aftermath",
                duration_seconds_at_floor = 120,
                duration_seconds_at_cap = 179,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                buff_id = 273,
                buff_name = "Aftermath",
                duration_seconds = 180,
            },
        },
    },

    -- Older relics, included in case you ever care about non-final relics.
    relic_75_to_119_ii = {
        family = "Relic",
        style = "flat",
        has_am_levels = false,
        buff_id = 273,
        buff_name = "Aftermath",
        duration_model = "formula",
        duration_formula = "math.floor(0.02 * real_tp_spent)",
        tp_bonus_affects_aftermath = false,

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                buff_id = 273,
                buff_name = "Aftermath",
                duration_seconds_at_floor = 20,
                duration_seconds_at_cap = 39,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                buff_id = 273,
                buff_name = "Aftermath",
                duration_seconds_at_floor = 40,
                duration_seconds_at_cap = 59,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                buff_id = 273,
                buff_name = "Aftermath",
                duration_seconds = 60,
            },
        },
    },

    -- Empyrean Level 119 III
    empyrean_119_iii = {
        family = "Empyrean",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 60,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 120,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },

    -- Older Empyreans, included for reference.
    empyrean_85_to_119_ii = {
        family = "Empyrean",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 30,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 60,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 90,
            },
        },
    },

    -- Aeonic
    -- All aftermath levels last 180 seconds.
    aeonic = {
        family = "Aeonic",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 180,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 180,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },

    -- Prime
    -- Community-tested current model: 60/120/180 seconds.
    prime = {
        family = "Prime",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 60,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 120,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },

    -- Standard Mythic / Ergon 119 III model.
    mythic_ergon_standard_119_iii = {
        family = "Mythic/Ergon",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,
        duration_confidence = "standard",

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 90,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 120,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },

    -- Mythic 119 III special profile:
    -- AM1 = 90s, AM2 = 270s, AM3 = 180s
    -- Known use: Tizona
    mythic_119_iii_am1_90_am2_270_am3_180 = {
        family = "Mythic",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,
        duration_confidence = "per_weapon_bg_wiki",

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 90,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 270,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },

    -- Mythic 119 III special profile:
    -- AM1 = 270s, AM2 = 120s, AM3 = 180s
    -- Known use: Yagrush, Carnwenhan
    mythic_119_iii_am1_270_am2_120_am3_180 = {
        family = "Mythic",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,
        duration_confidence = "per_weapon_bg_wiki",

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 270,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 120,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },

    -- Mythic 119 III special profile:
    -- AM1 = 270s, AM2 = 270s, AM3 = 180s
    -- Known use: Kenkonken, Murgleis, Nirvana, Tupsimati
    mythic_119_iii_am1_270_am2_270_am3_180 = {
        family = "Mythic",
        style = "levels",
        has_am_levels = true,
        tp_bonus_affects_aftermath = false,
        duration_confidence = "per_weapon_bg_wiki",

        tp = {
            [1] = {
                tp_min = 1000,
                tp_max = 1999,
                level = 1,
                buff_id = 270,
                buff_name = "Aftermath: Lv.1",
                duration_seconds = 270,
            },
            [2] = {
                tp_min = 2000,
                tp_max = 2999,
                level = 2,
                buff_id = 271,
                buff_name = "Aftermath: Lv.2",
                duration_seconds = 270,
            },
            [3] = {
                tp_min = 3000,
                tp_max = 3000,
                level = 3,
                buff_id = 272,
                buff_name = "Aftermath: Lv.3",
                duration_seconds = 180,
            },
        },
    },
}

local P = M.aftermath_profiles

-- =====================================================================
-- Complete aftermath weapon table
-- =====================================================================

M.weapons = {
    -- =================================================================
    -- Relic Weapons
    -- Flat buff ID 273. TP changes duration only.
    -- =================================================================

    ["Spharai"] = {
        category = "Relic",
        weapon_type = "Hand-to-Hand",
        weapon_skill = "Final Heaven",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Mandau"] = {
        category = "Relic",
        weapon_type = "Dagger",
        weapon_skill = "Mercy Stroke",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Excalibur"] = {
        category = "Relic",
        weapon_type = "Sword",
        weapon_skill = "Knights of Round",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Ragnarok"] = {
        category = "Relic",
        weapon_type = "Great Sword",
        weapon_skill = "Scourge",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Guttler"] = {
        category = "Relic",
        weapon_type = "Axe",
        weapon_skill = "Onslaught",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Bravura"] = {
        category = "Relic",
        weapon_type = "Great Axe",
        weapon_skill = "Metatron Torment",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Apocalypse"] = {
        category = "Relic",
        weapon_type = "Scythe",
        weapon_skill = "Catastrophe",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Gungnir"] = {
        category = "Relic",
        weapon_type = "Polearm",
        weapon_skill = "Geirskogul",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Kikoku"] = {
        category = "Relic",
        weapon_type = "Katana",
        weapon_skill = "Blade: Metsu",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Amanomurakumo"] = {
        category = "Relic",
        weapon_type = "Great Katana",
        weapon_skill = "Tachi: Kaiten",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Mjollnir"] = {
        category = "Relic",
        weapon_type = "Club",
        weapon_skill = "Randgrith",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Claustrum"] = {
        category = "Relic",
        weapon_type = "Staff",
        weapon_skill = "Gate of Tartarus",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Yoichinoyumi"] = {
        category = "Relic",
        weapon_type = "Archery",
        weapon_skill = "Namas Arrow",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    ["Annihilator"] = {
        category = "Relic",
        weapon_type = "Marksmanship",
        weapon_skill = "Coronach",
        aftermath_profile_key = "relic_119_iii",
        aftermath = P.relic_119_iii,
    },

    -- =================================================================
    -- Empyrean Weapons
    -- Buff IDs: 270 / 271 / 272
    -- Durations at 119 III: 60 / 120 / 180 seconds
    -- =================================================================

    ["Verethragna"] = {
        category = "Empyrean",
        weapon_type = "Hand-to-Hand",
        weapon_skill = "Victory Smite",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Twashtar"] = {
        category = "Empyrean",
        weapon_type = "Dagger",
        weapon_skill = "Rudra's Storm",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Almace"] = {
        category = "Empyrean",
        weapon_type = "Sword",
        weapon_skill = "Chant du Cygne",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Caladbolg"] = {
        category = "Empyrean",
        weapon_type = "Great Sword",
        weapon_skill = "Torcleaver",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Farsha"] = {
        category = "Empyrean",
        weapon_type = "Axe",
        weapon_skill = "Cloudsplitter",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Ukonvasara"] = {
        category = "Empyrean",
        weapon_type = "Great Axe",
        weapon_skill = "Ukko's Fury",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Redemption"] = {
        category = "Empyrean",
        weapon_type = "Scythe",
        weapon_skill = "Quietus",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Rhongomiant"] = {
        category = "Empyrean",
        weapon_type = "Polearm",
        weapon_skill = "Camlann's Torment",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Kannagi"] = {
        category = "Empyrean",
        weapon_type = "Katana",
        weapon_skill = "Blade: Hi",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Masamune"] = {
        category = "Empyrean",
        weapon_type = "Great Katana",
        weapon_skill = "Tachi: Fudo",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Gambanteinn"] = {
        category = "Empyrean",
        weapon_type = "Club",
        weapon_skill = "Dagan",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Hvergelmir"] = {
        category = "Empyrean",
        weapon_type = "Staff",
        weapon_skill = "Myrkr",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Gandiva"] = {
        category = "Empyrean",
        weapon_type = "Archery",
        weapon_skill = "Jishnu's Radiance",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    ["Armageddon"] = {
        category = "Empyrean",
        weapon_type = "Marksmanship",
        weapon_skill = "Wildfire",
        aftermath_profile_key = "empyrean_119_iii",
        aftermath = P.empyrean_119_iii,
    },

    -- =================================================================
    -- Aeonic Weapons
    -- Buff IDs: 270 / 271 / 272
    -- Duration: 180 seconds at every tier
    -- =================================================================

    ["Godhands"] = {
        category = "Aeonic",
        weapon_type = "Hand-to-Hand",
        weapon_skill = "Shijin Spiral",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Aeneas"] = {
        category = "Aeonic",
        weapon_type = "Dagger",
        weapon_skill = "Exenterator",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Sequence"] = {
        category = "Aeonic",
        weapon_type = "Sword",
        weapon_skill = "Requiescat",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Lionheart"] = {
        category = "Aeonic",
        weapon_type = "Great Sword",
        weapon_skill = "Resolution",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Tri-edge"] = {
        category = "Aeonic",
        weapon_type = "Axe",
        weapon_skill = "Ruinator",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Chango"] = {
        category = "Aeonic",
        weapon_type = "Great Axe",
        weapon_skill = "Upheaval",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Anguta"] = {
        category = "Aeonic",
        weapon_type = "Scythe",
        weapon_skill = "Entropy",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Trishula"] = {
        category = "Aeonic",
        weapon_type = "Polearm",
        weapon_skill = "Stardiver",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Heishi Shorinken"] = {
        category = "Aeonic",
        weapon_type = "Katana",
        weapon_skill = "Blade: Shun",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Dojikiri Yasutsuna"] = {
        category = "Aeonic",
        weapon_type = "Great Katana",
        weapon_skill = "Tachi: Shoha",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Tishtrya"] = {
        category = "Aeonic",
        weapon_type = "Club",
        weapon_skill = "Realmrazer",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Khatvanga"] = {
        category = "Aeonic",
        weapon_type = "Staff",
        weapon_skill = "Shattersoul",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Fail-Not"] = {
        category = "Aeonic",
        weapon_type = "Archery",
        weapon_skill = "Apex Arrow",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    ["Fomalhaut"] = {
        category = "Aeonic",
        weapon_type = "Marksmanship",
        weapon_skill = "Last Stand",
        aftermath_profile_key = "aeonic",
        aftermath = P.aeonic,
    },

    -- =================================================================
    -- Mythic / Ergon Weapons
    -- Buff IDs: 270 / 271 / 272
    --
    -- Standard modern profile:
    --   AM1 = 90s
    --   AM2 = 120s
    --   AM3 = 180s
    --
    -- Special profiles are assigned per weapon where BG Wiki lists
    -- nonstandard Level 119 III durations.
    -- =================================================================

    ["Conqueror"] = {
        category = "Mythic",
        job = "WAR",
        weapon_type = "Great Axe",
        weapon_skill = "King's Justice",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Glanzfaust"] = {
        category = "Mythic",
        job = "MNK",
        weapon_type = "Hand-to-Hand",
        weapon_skill = "Ascetic's Fury",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Yagrush"] = {
        category = "Mythic",
        job = "WHM",
        weapon_type = "Club",
        weapon_skill = "Mystic Boon",
        aftermath_profile_key = "mythic_119_iii_am1_270_am2_120_am3_180",
        aftermath = P.mythic_119_iii_am1_270_am2_120_am3_180,
    },

    ["Laevateinn"] = {
        category = "Mythic",
        job = "BLM",
        weapon_type = "Staff",
        weapon_skill = "Vidohunir",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Murgleis"] = {
        category = "Mythic",
        job = "RDM",
        weapon_type = "Sword",
        weapon_skill = "Death Blossom",
        aftermath_profile_key = "mythic_119_iii_am1_270_am2_270_am3_180",
        aftermath = P.mythic_119_iii_am1_270_am2_270_am3_180,
    },

    ["Vajra"] = {
        category = "Mythic",
        job = "THF",
        weapon_type = "Dagger",
        weapon_skill = "Mandalic Stab",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Burtgang"] = {
        category = "Mythic",
        job = "PLD",
        weapon_type = "Sword",
        weapon_skill = "Atonement",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Liberator"] = {
        category = "Mythic",
        job = "DRK",
        weapon_type = "Scythe",
        weapon_skill = "Insurgency",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Aymur"] = {
        category = "Mythic",
        job = "BST",
        weapon_type = "Axe",
        weapon_skill = "Primal Rend",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Carnwenhan"] = {
        category = "Mythic",
        job = "BRD",
        weapon_type = "Dagger",
        weapon_skill = "Mordant Rime",
        aftermath_profile_key = "mythic_119_iii_am1_270_am2_120_am3_180",
        aftermath = P.mythic_119_iii_am1_270_am2_120_am3_180,
    },

    ["Gastraphetes"] = {
        category = "Mythic",
        job = "RNG",
        weapon_type = "Crossbow",
        weapon_skill = "Trueflight",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Kogarasumaru"] = {
        category = "Mythic",
        job = "SAM",
        weapon_type = "Great Katana",
        weapon_skill = "Tachi: Rana",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Nagi"] = {
        category = "Mythic",
        job = "NIN",
        weapon_type = "Katana",
        weapon_skill = "Blade: Kamu",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Ryunohige"] = {
        category = "Mythic",
        job = "DRG",
        weapon_type = "Polearm",
        weapon_skill = "Drakesbane",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Nirvana"] = {
        category = "Mythic",
        job = "SMN",
        weapon_type = "Staff",
        weapon_skill = "Garland of Bliss",
        aftermath_profile_key = "mythic_119_iii_am1_270_am2_270_am3_180",
        aftermath = P.mythic_119_iii_am1_270_am2_270_am3_180,
    },

    ["Tizona"] = {
        category = "Mythic",
        job = "BLU",
        weapon_type = "Sword",
        weapon_skill = "Expiacion",
        aftermath_profile_key = "mythic_119_iii_am1_90_am2_270_am3_180",
        aftermath = P.mythic_119_iii_am1_90_am2_270_am3_180,
    },

    ["Death Penalty"] = {
        category = "Mythic",
        job = "COR",
        weapon_type = "Marksmanship",
        weapon_skill = "Leaden Salute",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Kenkonken"] = {
        category = "Mythic",
        job = "PUP",
        weapon_type = "Hand-to-Hand",
        weapon_skill = "Stringing Pummel",
        aftermath_profile_key = "mythic_119_iii_am1_270_am2_270_am3_180",
        aftermath = P.mythic_119_iii_am1_270_am2_270_am3_180,
    },

    ["Terpsichore"] = {
        category = "Mythic",
        job = "DNC",
        weapon_type = "Dagger",
        weapon_skill = "Pyrrhic Kleos",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Tupsimati"] = {
        category = "Mythic",
        job = "SCH",
        weapon_type = "Staff",
        weapon_skill = "Omniscience",
        aftermath_profile_key = "mythic_119_iii_am1_270_am2_270_am3_180",
        aftermath = P.mythic_119_iii_am1_270_am2_270_am3_180,
    },

    ["Idris"] = {
        category = "Ergon",
        job = "GEO",
        weapon_type = "Club",
        weapon_skill = "Exudation",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    ["Epeolatry"] = {
        category = "Ergon",
        job = "RUN",
        weapon_type = "Great Sword",
        weapon_skill = "Dimidiation",
        aftermath_profile_key = "mythic_ergon_standard_119_iii",
        aftermath = P.mythic_ergon_standard_119_iii,
    },

    -- =================================================================
    -- Prime Weapons
    -- Buff IDs: 270 / 271 / 272
    -- Duration: 60 / 120 / 180 seconds
    --
    -- Stage 3 WS is Sortie-only.
    -- Stage 4+ WS is usable anywhere.
    -- =================================================================

    ["Varga Purnikawa"] = {
        category = "Prime",
        weapon_type = "Hand-to-Hand",
        weapon_skill = "Maru Kala",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Mpu Gandring"] = {
        category = "Prime",
        weapon_type = "Dagger",
        weapon_skill = "Ruthless Stroke",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Caliburnus"] = {
        category = "Prime",
        weapon_type = "Sword",
        weapon_skill = "Imperator",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Helheim"] = {
        category = "Prime",
        weapon_type = "Great Sword",
        weapon_skill = "Fimbulvetr",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Spalirisos"] = {
        category = "Prime",
        weapon_type = "Axe",
        weapon_skill = "Blitz",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Laphria"] = {
        category = "Prime",
        weapon_type = "Great Axe",
        weapon_skill = "Disaster",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Foenaria"] = {
        category = "Prime",
        weapon_type = "Scythe",
        weapon_skill = "Origin",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Gae Buide"] = {
        category = "Prime",
        weapon_type = "Polearm",
        weapon_skill = "Diarmuid",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Dokoku"] = {
        category = "Prime",
        weapon_type = "Katana",
        weapon_skill = "Zesho Meppo",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Kusanagi"] = {
        category = "Prime",
        weapon_type = "Great Katana",
        weapon_skill = "Tachi: Mumei",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Lorg Mor"] = {
        category = "Prime",
        weapon_type = "Club",
        weapon_skill = "Dagda",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
        notes = "Prime Club has special aftermath behavior: cure power and magic damage.",
    },

    ["Opashoro"] = {
        category = "Prime",
        weapon_type = "Staff",
        weapon_skill = "Oshala",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
        notes = "Prime Staff has special aftermath behavior: magic attack bonus and magic damage.",
    },

    ["Pinaka"] = {
        category = "Prime",
        weapon_type = "Archery",
        weapon_skill = "Sarv",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },

    ["Earp"] = {
        category = "Prime",
        weapon_type = "Marksmanship",
        weapon_skill = "Terminus",
        minimum_aftermath_stage = 3,
        aftermath_profile_key = "prime",
        aftermath = P.prime,
    },
}

-- =====================================================================
-- Optional lookup helpers
-- =====================================================================

function M.get_weapon(name)
    return M.weapons[name]
end

function M.get_weapon_by_ws(weapon_skill_name)
    for weapon_name, weapon in pairs(M.weapons) do
        if weapon.weapon_skill == weapon_skill_name then
            return weapon_name, weapon
        end
    end

    return nil, nil
end

function M.get_tp_bucket(real_tp)
    real_tp = tonumber(real_tp) or 0

    if real_tp >= 3000 then
        return 3
    elseif real_tp >= 2000 then
        return 2
    elseif real_tp >= 1000 then
        return 1
    end

    return nil
end

function M.get_expected_aftermath_for_weapon(weapon_name, real_tp)
    local weapon = M.weapons[weapon_name]
    if not weapon or not weapon.aftermath then
        return nil
    end

    local profile = weapon.aftermath
    local bucket = M.get_tp_bucket(real_tp)

    if not bucket then
        return nil
    end

    local tp_info = profile.tp[bucket]
    if not tp_info then
        return nil
    end

    local duration_seconds = tp_info.duration_seconds

    if profile.duration_model == "formula" then
        if profile == P.relic_119_iii then
            duration_seconds = math.floor(0.06 * real_tp)
        elseif profile == P.relic_75_to_119_ii then
            duration_seconds = math.floor(0.02 * real_tp)
        end
    end

    return {
        weapon_name = weapon_name,
        weapon_skill = weapon.weapon_skill,
        category = weapon.category,
        aftermath_style = profile.style,
        level = tp_info.level,
        buff_id = tp_info.buff_id,
        buff_name = tp_info.buff_name,
        duration_seconds = duration_seconds,
        tp_bucket = bucket,
        real_tp = real_tp,
        tp_bonus_affects_aftermath = false,
    }
end

local function table_contains_value(tbl, value)
    if not tbl then
        return false
    end

    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end

    return false
end

function M.get_active_aftermath_from_buff_ids(buff_ids)
    if table_contains_value(buff_ids, 272) then
        return {
            active = true,
            style = "levels",
            level = 3,
            buff_id = 272,
            buff_name = "Aftermath: Lv.3",
        }
    end

    if table_contains_value(buff_ids, 271) then
        return {
            active = true,
            style = "levels",
            level = 2,
            buff_id = 271,
            buff_name = "Aftermath: Lv.2",
        }
    end

    if table_contains_value(buff_ids, 270) then
        return {
            active = true,
            style = "levels",
            level = 1,
            buff_id = 270,
            buff_name = "Aftermath: Lv.1",
        }
    end

    if table_contains_value(buff_ids, 273) then
        return {
            active = true,
            style = "flat",
            level = nil,
            buff_id = 273,
            buff_name = "Aftermath",
        }
    end

    return {
        active = false,
    }
end

function M.get_active_aftermath_from_windower()
    if not windower or not windower.ffxi or not windower.ffxi.get_player then
        return {
            active = false,
            error = "Windower player API is not available.",
        }
    end

    local player = windower.ffxi.get_player()
    if not player or not player.buffs then
        return {
            active = false,
            error = "Player buff list is not available.",
        }
    end

    return M.get_active_aftermath_from_buff_ids(player.buffs)
end

function M.has_any_aftermath_from_buff_ids(buff_ids)
    local active = M.get_active_aftermath_from_buff_ids(buff_ids)
    return active and active.active == true
end

function M.has_any_aftermath_from_windower()
    local active = M.get_active_aftermath_from_windower()
    return active and active.active == true
end

function M.has_aftermath_level_from_buff_ids(buff_ids, level)
    local wanted = ({
        [1] = 270,
        [2] = 271,
        [3] = 272,
    })[level]

    if not wanted then
        return false
    end

    return table_contains_value(buff_ids, wanted)
end

function M.has_flat_relic_aftermath_from_buff_ids(buff_ids)
    return table_contains_value(buff_ids, 273)
end

-- Convenience indexes.
M.weapons_by_weapon_skill = {}

for weapon_name, weapon in pairs(M.weapons) do
    M.weapons_by_weapon_skill[weapon.weapon_skill] = weapon_name
end

return M