return {
    {
        fixture_id = "action_pred_ja_targets_enemy_target_string_enemy",
        helper = "ja_targets_enemy",
        description = "string targets containing Enemy returns true",
        input = {
            ja = { targets = "Enemy|Self" },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_string_no_enemy",
        helper = "ja_targets_enemy",
        description = "string targets without Enemy returns false",
        input = {
            ja = { targets = "Self|Party" },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_number_enemy_bit",
        helper = "ja_targets_enemy",
        description = "numeric targets with enemy bit set return true",
        input = {
            ja = { targets = 32 },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_number_no_enemy_bit",
        helper = "ja_targets_enemy",
        description = "numeric targets without enemy bit return false",
        input = {
            ja = { targets = 31 },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_table_enemy_true",
        helper = "ja_targets_enemy",
        description = "table targets with Enemy true return true",
        input = {
            ja = { targets = { Enemy = true } },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_table_enemy_lower_true",
        helper = "ja_targets_enemy",
        description = "table targets with lowercase enemy true return true",
        input = {
            ja = { targets = { enemy = true } },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_table_enemy_false",
        helper = "ja_targets_enemy",
        description = "table targets with enemy false returns false",
        input = {
            ja = { targets = { Enemy = false } },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "action_pred_ja_targets_enemy_target_missing",
        helper = "ja_targets_enemy",
        description = "missing targets returns false",
        input = {
            ja = {},
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "action_pred_ja_requires_engaged_front_id_46",
        helper = "ja_requires_engaged_front",
        description = "id 46 always requires engaged front",
        input = {
            name = "Anything",
            ja = { id = 46 },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "action_pred_ja_requires_engaged_front_name_shield_bash",
        helper = "ja_requires_engaged_front",
        description = "shield bash name match (case-insensitive) returns true",
        input = {
            name = "ShIeLd BaSh",
            ja = { id = 1 },
        },
        expected = {
            result = true,
        },
    },
    {
        fixture_id = "action_pred_ja_requires_engaged_front_false",
        helper = "ja_requires_engaged_front",
        description = "non-shield-bash and non-46 id returns false",
        input = {
            name = "Provoke",
            ja = { id = 5 },
        },
        expected = {
            result = false,
        },
    },
    {
        fixture_id = "action_pred_ja_requires_engaged_front_nil_name_id_string_46",
        helper = "ja_requires_engaged_front",
        description = "string numeric id 46 is coerced and returns true",
        input = {
            name = nil,
            ja = { id = "46" },
        },
        expected = {
            result = true,
        },
    },
}
