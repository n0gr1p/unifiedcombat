local function deps_with_mode(mode)
    return {
        action_target_mode = function(_, _)
            return mode
        end,
    }
end

return {
    {
        fixture_id = "command_builder_spell_target_name",
        helper = "build_action_command",
        description = "spell command targets named member",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Cure IV",
            action_kind = "spell",
            target_member = { name = "Alice" },
        },
        expected = {
            result = "input /ma \"Cure IV\" \"Alice\"",
        },
    },
    {
        fixture_id = "command_builder_spell_self_only_forces_me",
        helper = "build_action_command",
        description = "self_only mode always targets me",
        input = {
            deps = deps_with_mode("self_only"),
            action_name = "Stoneskin",
            action_kind = "spell",
            target_member = { name = "Alice", id = 123, is_mob = true },
        },
        expected = {
            result = "input /ma \"Stoneskin\" <me>",
        },
    },
    {
        fixture_id = "command_builder_spell_self_only_explicit_entity_id",
        helper = "build_action_command",
        description = "explicit entity id bypasses self-only metadata for Entrust-enabled Indi",
        input = {
            deps = deps_with_mode("self_only"),
            action_name = "Indi-Refresh",
            action_kind = "spell",
            target_member = { name = "Terrasjr", id = 400018, use_entity_id = true },
        },
        expected = {
            result = "input /ma \"Indi-Refresh\" 400018",
        },
    },
    {
        fixture_id = "command_builder_spell_target_self_flag",
        helper = "build_action_command",
        description = "explicit self target uses me",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Cure",
            action_kind = "spell",
            target_member = { is_self = true, name = "Alice" },
        },
        expected = {
            result = "input /ma \"Cure\" <me>",
        },
    },
    {
        fixture_id = "command_builder_spell_target_mob_id",
        helper = "build_action_command",
        description = "mob id target emits numeric token",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Dispel",
            action_kind = "spell",
            target_member = { id = 3456, is_mob = true, name = "Enemy" },
        },
        expected = {
            result = "input /ma \"Dispel\" 3456",
        },
    },
    {
        fixture_id = "command_builder_spell_target_name_quotes_stripped",
        helper = "build_action_command",
        description = "target name has embedded quotes stripped",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Cure",
            action_kind = "spell",
            target_member = { name = "Al\"ice" },
        },
        expected = {
            result = "input /ma \"Cure\" \"Alice\"",
        },
    },
    {
        fixture_id = "command_builder_spell_fallback_me_no_target",
        helper = "build_action_command",
        description = "missing target member falls back to me",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Protect",
            action_kind = "spell",
            target_member = nil,
        },
        expected = {
            result = "input /ma \"Protect\" <me>",
        },
    },
    {
        fixture_id = "command_builder_spell_fallback_me_empty_name",
        helper = "build_action_command",
        description = "empty name without valid mob id falls back to me",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Haste",
            action_kind = "spell",
            target_member = { name = "", id = 0, is_mob = false },
        },
        expected = {
            result = "input /ma \"Haste\" <me>",
        },
    },
    {
        fixture_id = "command_builder_ja_target_name",
        helper = "build_action_command",
        description = "ja uses ja command prefix and name target",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Provoke",
            action_kind = "ja",
            target_member = { name = "Bob" },
        },
        expected = {
            result = "input /ja \"Provoke\" \"Bob\"",
        },
    },
    {
        fixture_id = "command_builder_ja_self_target",
        helper = "build_action_command",
        description = "ja self target uses me",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Berserk",
            action_kind = "ja",
            target_member = { is_self = true },
        },
        expected = {
            result = "input /ja \"Berserk\" <me>",
        },
    },
    {
        fixture_id = "command_builder_ja_mob_id_target",
        helper = "build_action_command",
        description = "ja with mob id target uses numeric token",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Animated Flourish",
            action_kind = "ja",
            target_member = { id = "789", is_mob = true },
        },
        expected = {
            result = "input /ja \"Animated Flourish\" 789",
        },
    },
    {
        fixture_id = "command_builder_non_ja_defaults_to_ma",
        helper = "build_action_command",
        description = "non-ja kinds default to ma command prefix",
        input = {
            deps = deps_with_mode("normal"),
            action_name = "Random Ability",
            action_kind = "ws",
            target_member = { name = "Target" },
        },
        expected = {
            result = "input /ma \"Random Ability\" \"Target\"",
        },
    },
    {
        fixture_id = "command_builder_action_name_tostring",
        helper = "build_action_command",
        description = "action name is stringified in format output",
        input = {
            deps = deps_with_mode("normal"),
            action_name = 12345,
            action_kind = "spell",
            target_member = { name = "Alice" },
        },
        expected = {
            result = "input /ma \"12345\" \"Alice\"",
        },
    },
}
