return {
    {
        fixture_id = "pending_record_basic_spell",
        helper = "p1_record_legacy_dispatch",
        description = "builds pending record and duplicate suppression entry for normal dispatch",
        input = {
            scheduler = {
                phase1 = {
                    last_selected = {
                        proposal_id = "prop.1",
                        family_id = "family.heal",
                        duplicate_suppression_key = "dup.heal.alice",
                        provider = "provider.heal",
                        action_type = "spell",
                        action_name = "Cure IV",
                        target_id = 1001,
                        created_at = 90,
                        expected_ack = "0x1A",
                        expected_effect = "0x28",
                        lock_class = "casting",
                    },
                    last_plan = {
                        action = "send",
                    },
                    recent_duplicate_until = {},
                },
            },
            ctx = {
                now = 123.45,
                tick = 7.9,
            },
            p1_number = function(value, fallback)
                if value == nil then
                    return fallback
                end
                return value + 0.25
            end,
        },
        expected = {
            result = nil,
            phase1_pending = {
                pending_id = "pend.123450.7",
                proposal_id = "prop.1",
                family_id = "family.heal",
                duplicate_suppression_key = "dup.heal.alice",
                provider = "provider.heal",
                action_type = "spell",
                action_name = "Cure IV",
                target_id = 1001,
                state = "sent",
                selected_at = 90.25,
                dispatched_at = 123.45,
                ack_deadline = 124.05,
                effect_deadline = 125.95,
                completion_deadline = 126.45,
                expected_ack = "0x1A",
                expected_effect = "0x28",
                result = "",
                lock_class = "casting",
            },
            phase1_recent_duplicate_until = {
                ["dup.heal.alice"] = 124.2,
            },
        },
    },
    {
        fixture_id = "pending_record_empty_duplicate_key_not_recorded",
        helper = "p1_record_legacy_dispatch",
        description = "empty duplicate key does not update recent_duplicate_until",
        input = {
            scheduler = {
                phase1 = {
                    last_selected = {
                        proposal_id = "prop.2",
                        family_id = "family.buff",
                        duplicate_suppression_key = "",
                        provider = "provider.buff",
                        action_type = "ability",
                        action_name = "Sentinel",
                        target_id = 2002,
                        created_at = nil,
                        expected_ack = nil,
                        expected_effect = nil,
                        lock_class = nil,
                    },
                    last_plan = {
                        action = "send",
                    },
                    recent_duplicate_until = {
                        ["existing"] = 50,
                    },
                },
            },
            ctx = {
                now = 11,
                tick = 3,
            },
            p1_number = function(value, fallback)
                if value == nil then
                    return fallback
                end
                return value
            end,
        },
        expected = {
            result = nil,
            phase1_pending = {
                pending_id = "pend.11000.3",
                proposal_id = "prop.2",
                family_id = "family.buff",
                duplicate_suppression_key = "",
                provider = "provider.buff",
                action_type = "ability",
                action_name = "Sentinel",
                target_id = 2002,
                state = "sent",
                selected_at = 11,
                dispatched_at = 11,
                ack_deadline = 11.6,
                effect_deadline = 13.5,
                completion_deadline = 14,
                expected_ack = "",
                expected_effect = "",
                result = "",
                lock_class = "",
            },
            phase1_recent_duplicate_until = {
                ["existing"] = 50,
            },
        },
    },
    {
        fixture_id = "pending_record_missing_selected_noop",
        helper = "p1_record_legacy_dispatch",
        description = "missing selected proposal leaves phase unchanged",
        input = {
            scheduler = {
                phase1 = {
                    last_selected = nil,
                    last_plan = {
                        action = "send",
                    },
                    pending = {
                        keep = true,
                    },
                    recent_duplicate_until = {
                        keep = 1,
                    },
                },
            },
            ctx = {
                now = 20,
                tick = 5,
            },
            p1_number = function(value, fallback)
                return value or fallback
            end,
        },
        expected = {
            result = nil,
            phase1_pending = {
                keep = true,
            },
            phase1_recent_duplicate_until = {
                keep = 1,
            },
        },
    },
    {
        fixture_id = "pending_record_missing_plan_noop",
        helper = "p1_record_legacy_dispatch",
        description = "missing last_plan leaves phase unchanged",
        input = {
            scheduler = {
                phase1 = {
                    last_selected = {
                        proposal_id = "prop.4",
                    },
                    last_plan = nil,
                    pending = {
                        keep = "pending",
                    },
                    recent_duplicate_until = {
                        keep = 2,
                    },
                },
            },
            ctx = {
                now = 40,
                tick = 6,
            },
            p1_number = function(value, fallback)
                return value or fallback
            end,
        },
        expected = {
            result = nil,
            phase1_pending = {
                keep = "pending",
            },
            phase1_recent_duplicate_until = {
                keep = 2,
            },
        },
    },
    {
        fixture_id = "pending_record_field_coercions",
        helper = "p1_record_legacy_dispatch",
        description = "coerces nil and numeric fields using module defaults",
        input = {
            scheduler = {
                phase1 = {
                    last_selected = {
                        proposal_id = 777,
                        family_id = false,
                        duplicate_suppression_key = nil,
                        provider = nil,
                        action_type = nil,
                        action_name = nil,
                        target_id = "bad",
                        created_at = nil,
                        expected_ack = nil,
                        expected_effect = nil,
                        lock_class = nil,
                    },
                    last_plan = {
                        action = "send",
                    },
                    recent_duplicate_until = {},
                },
            },
            ctx = {
                now = 1.2,
                tick = 9.99,
            },
            p1_number = function(value, fallback)
                if value == nil then
                    return fallback + 5
                end
                return value
            end,
        },
        expected = {
            result = nil,
            phase1_pending = {
                pending_id = "pend.1200.9",
                proposal_id = "777",
                family_id = "",
                duplicate_suppression_key = "",
                provider = "",
                action_type = "",
                action_name = "",
                target_id = 0,
                state = "sent",
                selected_at = 6.2,
                dispatched_at = 1.2,
                ack_deadline = 1.2 + 0.6,
                effect_deadline = 1.2 + 2.5,
                completion_deadline = 1.2 + 3.0,
                expected_ack = "",
                expected_effect = "",
                result = "",
                lock_class = "",
            },
            phase1_recent_duplicate_until = {},
        },
    },
}
