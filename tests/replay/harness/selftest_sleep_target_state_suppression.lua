local scheduler_path = "unified_scheduler.lua"

local function read_file(file_path)
    local fh, err = io.open(file_path, "r")
    if not fh then
        error("failed to open " .. tostring(file_path) .. ": " .. tostring(err))
    end
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assert_contains(text, needle, message)
    if not text:find(needle, 1, true) then
        error(message or ("missing expected text: " .. needle))
    end
end

local function assert_not_contains(text, needle, message)
    if text:find(needle, 1, true) then
        error(message or ("unexpected text present: " .. needle))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or "assert_true failed")
    end
end

local function sleep_effect_id_set_from_settings(settings, spell_status)
    local out = {}
    for _, spell_name in ipairs(settings.sleep_spells or {}) do
        local eid = tonumber(spell_status[spell_name]) or 0
        if eid > 0 then
            out[eid] = true
        end
    end
    return out
end

local function mark_sleep_target_suppressed(state, target_id, spell_name, now, timeout_s)
    state.sleep_targets[target_id] = {
        spell_name = spell_name,
        seen_at = now,
        expires_at = now + timeout_s,
    }
end

local function clear_sleep_target_suppression(state, target_id)
    state.sleep_targets[target_id] = nil
end

local function prune_sleep_target_state(state, settings, now, spell_status)
    local effect_ids = sleep_effect_id_set_from_settings(settings, spell_status)
    for tid, row in pairs(state.sleep_targets) do
        local remove = false
        if type(row) ~= "table" then
            remove = true
        else
            local mob = state.mobs[tid]
            if (tonumber(row.expires_at) or 0) <= now then
                remove = true
            elseif not mob or mob.live ~= true or (tonumber(mob.hpp) or 0) <= 0 then
                remove = true
            else
                local effects = state.enemy_effects[tid] or {}
                for effect_id, _ in pairs(effect_ids) do
                    if effects[effect_id] == true then
                        remove = true
                        break
                    end
                end
            end
        end
        if remove then
            state.sleep_targets[tid] = nil
        end
    end
end

local function target_sleep_suppressed(state, settings, target_id, now, spell_status)
    prune_sleep_target_state(state, settings, now, spell_status)
    local effect_ids = sleep_effect_id_set_from_settings(settings, spell_status)
    local effects = state.enemy_effects[target_id] or {}
    for effect_id, _ in pairs(effect_ids) do
        if effects[effect_id] == true then
            return true, "effect"
        end
    end
    if type(state.sleep_targets[target_id]) == "table" then
        return true, "local"
    end
    return false, ""
end

local function select_sleep_spell_for_target(settings, target, spell_state)
    local sleep_max_target_distance = tonumber(settings and settings.sleep_max_target_range) or 6.0
    if type(target) ~= "table" or (tonumber(target.id) or 0) <= 0 then
        return nil
    end
    local dist = tonumber(target.dist) or 999
    if dist > sleep_max_target_distance then
        return nil
    end
    for index, spell_name in ipairs(settings.sleep_spells or {}) do
        local state = spell_state[spell_name] or {}
        local ready = state.ready == true
        local range_max = math.min(tonumber(state.range_max) or 0, sleep_max_target_distance)
        if ready and range_max > 0 and dist <= range_max then
            return { name = spell_name, index = index }
        end
    end
    return nil
end

local function collect_sleep_mock(input)
    local settings = {
        sleep = input.sleep,
        sleep_spells = input.sleep_spells or {},
        sleep_max_target_range = input.sleep_max_target_range,
    }
    if input.engine_on ~= true or input.domain_combat_enabled ~= true or settings.sleep ~= true then
        return nil
    end
    if #settings.sleep_spells == 0 then
        return nil
    end
    local best = nil
    for _, candidate in ipairs(input.candidates or {}) do
        local suppressed = target_sleep_suppressed(input.state, settings, candidate.target_id, input.now, input.spell_status)
        if candidate.eligible == true and not suppressed then
            local picked = select_sleep_spell_for_target(settings, {
                id = candidate.target_id,
                dist = candidate.dist,
            }, input.spell_state or {})
            if picked then
                if not best
                    or candidate.dist < best.dist
                    or (candidate.dist == best.dist and candidate.target_id < best.target_id) then
                    best = {
                        target_id = candidate.target_id,
                        action_name = picked.name,
                        dist = candidate.dist,
                    }
                end
            end
        end
    end
    return best
end

local function main()
    local source = read_file(scheduler_path)
    local combat_provider = read_file("uc_provider_combat.lua")

    assert_contains(source, "scheduler.SLEEP_TARGET_SUPPRESSION_TIMEOUT_S = 45.0", "Sleep suppression must use a bounded timeout")
    assert_contains(source, "function scheduler.sleep_spell_effect_id_set_from_config(config)", "Sleep suppression must derive sleep-family effect ids from configured spells")
    assert_contains(source, "function scheduler.target_sleep_suppressed(config, target_id, at)", "Sleep suppression must expose a target-id suppression gate")
    assert_contains(source, "target_sleep_suppressed = scheduler.target_sleep_suppressed", "scheduler must inject the suppression gate into the combat provider")
    assert_contains(combat_provider, "if target_sleep_suppressed(ctx.config, tid, ctx.now) then", "Sleep target eligibility must consult the suppression gate")
    assert_contains(source, "function scheduler.observe_local_sleep_action(act, player_id, at)", "local Sleep action observation must expose a successful-recipient tracker")
    assert_contains(source, "if scheduler.spell_effect_gain_messages[message_id] == true then", "local Sleep tracking must require a successful effect message")
    assert_contains(source, "scheduler.mark_sleep_target_suppressed(tid, spell_name, now)", "confirmed local combat Sleep success must mark each successful target suppressed")
    assert_contains(source, "require('uc_scheduler_enemy_effect_state').spell_effect_id(", "Sleep effect ids must come from the extracted TargetBar-backed enemy effect state")
    assert_not_contains(source, "message_id == 204 and message_param == 2", "Sleep tracking must not treat effect removal as successful application")
    assert_not_contains(source, "local eid = tonumber(sp and sp.status) or 0", "Sleep suppression must not use generic resource status ids for Bard Lullaby")
    assert_contains(source, "scheduler.clear_sleep_target_suppression(tid)", "sleep suppression must clear on death or effect removal")
    assert_contains(source, "action_mark_sent('spell', {", "combat spell sends must preserve action metadata for success confirmation")
    assert_contains(source, "provider = 'combat'", "Sleep suppression success confirmation must stay scoped to combat provider sends")
    assert_not_contains(source, "hb off", "Sleep suppression must not reintroduce legacy hb off toggling")
    assert_not_contains(source, "hb on", "Sleep suppression must not reintroduce legacy hb on toggling")

    local spell_status = {
        ["Sleep"] = 2,
        ["Sleep II"] = 2,
        ["Repose"] = 2,
        ["Horde Lullaby II"] = 193,
    }
    local targetbar_spells = dofile("TargetBar/spells.lua")
    assert_equal(targetbar_spells[253][1], 2, "TargetBar Sleep effect id mismatch")
    assert_equal(targetbar_spells[259][1], 2, "TargetBar Sleep II effect id mismatch")
    assert_equal(targetbar_spells[376][1], 193, "TargetBar Horde Lullaby effect id mismatch")
    assert_equal(targetbar_spells[377][1], 193, "TargetBar Horde Lullaby II effect id mismatch")
    assert_equal(targetbar_spells[463][1], 193, "TargetBar Foe Lullaby effect id mismatch")
    assert_equal(targetbar_spells[471][1], 193, "TargetBar Foe Lullaby II effect id mismatch")
    local spell_state = {
        ["Sleep II"] = { ready = false, range_max = 21 },
        ["Sleep"] = { ready = true, range_max = 21 },
        ["Repose"] = { ready = true, range_max = 21 },
    }
    local state = {
        sleep_targets = {},
        enemy_effects = {},
        mobs = {
            [100] = { live = true, hpp = 100 },
            [101] = { live = true, hpp = 100 },
        },
    }

    mark_sleep_target_suppressed(state, 100, "Sleep II", 10, 45)
    local suppressed, reason = target_sleep_suppressed(state, { sleep_spells = { "Sleep II", "Sleep" } }, 100, 10, spell_status)
    assert_equal(suppressed, true, "successful Sleep on target A must mark that target suppressed")
    assert_equal(reason, "local", "suppression should be local when only the bounded local cache is active")

    local picked = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II", "Sleep" },
        now = 10,
        state = state,
        spell_status = spell_status,
        spell_state = spell_state,
        candidates = {
            { eligible = true, target_id = 100, dist = 4.5 },
            { eligible = true, target_id = 101, dist = 5.0 },
        },
    })
    assert_true(type(picked) == "table", "scheduler must still emit Sleep when another unslept target is available")
    assert_equal(picked.target_id, 101, "scheduler must not cast a second Sleep spell on already-slept target A")
    assert_equal(picked.action_name, "Sleep", "first-available spell fallback must remain intact for an unslept target")

    state.enemy_effects[100] = { [2] = true }
    clear_sleep_target_suppression(state, 100)
    suppressed, reason = target_sleep_suppressed(state, { sleep_spells = { "Sleep II", "Sleep" } }, 100, 12, spell_status)
    assert_equal(suppressed, true, "real enemy effect tracking must suppress already-slept targets")
    assert_equal(reason, "effect", "real effect tracking must take precedence over the local cache")

    local never_marked = {
        sleep_targets = {},
        enemy_effects = {},
        mobs = { [102] = { live = true, hpp = 100 } },
    }
    suppressed = target_sleep_suppressed(never_marked, { sleep_spells = { "Sleep II" } }, 102, 20, spell_status)
    assert_equal(suppressed, false, "failed or resisted Sleep must not mark a target slept unless success is confirmed")

    local timed = {
        sleep_targets = {},
        enemy_effects = {},
        mobs = { [103] = { live = true, hpp = 100 } },
    }
    mark_sleep_target_suppressed(timed, 103, "Sleep II", 0, 45)
    suppressed = target_sleep_suppressed(timed, { sleep_spells = { "Sleep II" } }, 103, 30, spell_status)
    assert_equal(suppressed, true, "sleep suppression must remain active before the timeout expires")
    suppressed = target_sleep_suppressed(timed, { sleep_spells = { "Sleep II" } }, 103, 46, spell_status)
    assert_equal(suppressed, false, "sleep suppression must expire after the bounded timeout")

    local dead = {
        sleep_targets = {},
        enemy_effects = {},
        mobs = { [104] = { live = false, hpp = 0 } },
    }
    mark_sleep_target_suppressed(dead, 104, "Sleep II", 0, 45)
    clear_sleep_target_suppression(dead, 104)
    suppressed = target_sleep_suppressed(dead, { sleep_spells = { "Sleep II" } }, 104, 10, spell_status)
    assert_equal(suppressed, false, "target death must clear or ignore sleep suppression")

    picked = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = { "Sleep II", "Sleep" },
        now = 50,
        state = {
            sleep_targets = {},
            enemy_effects = {},
            mobs = { [105] = { live = true, hpp = 100 } },
        },
        spell_status = spell_status,
        spell_state = spell_state,
        candidates = {
            { eligible = true, target_id = 105, dist = 6.01 },
        },
    })
    assert_equal(picked, nil, "target beyond 6 yalms must still be rejected")

    picked = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = false,
        sleep_spells = { "Sleep II", "Sleep" },
        now = 60,
        state = {
            sleep_targets = {},
            enemy_effects = {},
            mobs = { [106] = { live = true, hpp = 100 } },
        },
        spell_status = spell_status,
        spell_state = spell_state,
        candidates = {
            { eligible = true, target_id = 106, dist = 5.0 },
        },
    })
    assert_equal(picked, nil, "Sleep off must still emit no proposal")

    picked = collect_sleep_mock({
        engine_on = true,
        domain_combat_enabled = true,
        sleep = true,
        sleep_spells = {},
        now = 70,
        state = {
            sleep_targets = {},
            enemy_effects = {},
            mobs = { [107] = { live = true, hpp = 100 } },
        },
        spell_status = spell_status,
        spell_state = spell_state,
        candidates = {
            { eligible = true, target_id = 107, dist = 5.0 },
        },
    })
    assert_equal(picked, nil, "no configured or available Sleep spell must emit no proposal")

    io.stdout:write("selftest_sleep_target_state_suppression: OK\n")
end

main()
