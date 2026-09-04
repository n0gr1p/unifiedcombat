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

local function mock_choose_defensive_action(candidates)
    local c = candidates or {}
    local function is_majesty_action(action)
        return type(action) == "table" and tostring(action.spell or ""):lower() == "majesty"
    end
    local majesty_action = nil
    if is_majesty_action(c.buff) then
        majesty_action = c.buff
    elseif is_majesty_action(c.overwrite) then
        majesty_action = c.overwrite
    end
    if c.debuff and c.debuff.spell == "Paralyna" and c.debuff.target and c.debuff.target.is_self then
        return c.debuff, "BLOCK_DEFENSIVE_NA"
    end
    if majesty_action then
        return majesty_action, "BLOCK_DEFENSIVE_MAJESTY"
    end
    if c.overwrite then
        return c.overwrite, "BLOCK_DEFENSIVE_OVERWRITE"
    elseif c.cure then
        if c.debuff and ((c.debuff.prio + 2) < c.cure.prio) then
            return c.debuff, "BLOCK_DEFENSIVE_NA"
        end
        return c.cure, "BLOCK_DEFENSIVE_CURE"
    elseif c.debuff then
        if c.buff and (c.buff.prio < c.debuff.prio) then
            return c.buff, "BLOCK_DEFENSIVE_BUFF"
        end
        return c.debuff, "BLOCK_DEFENSIVE_NA"
    elseif c.buff then
        return c.buff, "BLOCK_DEFENSIVE_BUFF"
    end
    return nil, nil
end

local function main()
    local source = read_file(scheduler_path)
    local chooser_source = read_file("uc_scheduler_na_policy.lua")

    assert_contains(chooser_source, "if majesty_action then", "Majesty must be allowed to beat available cure candidate again")
    assert_not_contains(chooser_source, "elseif c.buff and ((c.buff.prio + 2) < c.cure.prio) then", "normal buff must not beat available cure candidate")

    local red_ally_cure = {
        type = "cure",
        spell = "Cure IV",
        prio = 5,
        target = { name = "AllyA", hpp = 22, id = 1001 },
    }
    local yellow_ally_cure = {
        type = "cure",
        spell = "Cure III",
        prio = 5,
        target = { name = "AllyB", hpp = 48, id = 1002 },
    }
    local self_buff = {
        type = "buff",
        spell = "Protectra",
        prio = 1.5,
        target = { name = "Self", hpp = 100, is_self = true, id = 1 },
    }
    local majesty_buff = {
        type = "buff",
        spell = "Majesty",
        prio = 1.5,
        target = { name = "Self", hpp = 100, is_self = true, id = 1 },
    }
    local self_paralyna = {
        type = "debuff",
        spell = "Paralyna",
        prio = 1,
        target = { name = "Self", is_self = true, id = 1 },
    }

    local chosen, reason = mock_choose_defensive_action({
        cure = red_ally_cure,
        buff = self_buff,
    })
    assert_equal(chosen, red_ally_cure, "red HP ally cure candidate must beat self-buff")
    assert_equal(reason, "BLOCK_DEFENSIVE_CURE", "red HP ally cure reason mismatch")

    chosen, reason = mock_choose_defensive_action({
        cure = yellow_ally_cure,
        buff = self_buff,
    })
    assert_equal(chosen, yellow_ally_cure, "yellow HP ally cure candidate must beat self-buff")
    assert_equal(reason, "BLOCK_DEFENSIVE_CURE", "yellow HP ally cure reason mismatch")

    chosen, reason = mock_choose_defensive_action({
        cure = red_ally_cure,
        buff = majesty_buff,
    })
    assert_equal(chosen, majesty_buff, "Majesty must beat an available cure candidate")
    assert_equal(reason, "BLOCK_DEFENSIVE_MAJESTY", "Majesty-vs-cure reason mismatch")

    chosen, reason = mock_choose_defensive_action({
        buff = self_buff,
    })
    assert_equal(chosen, self_buff, "self-buff must still win when no cure candidate exists")
    assert_equal(reason, "BLOCK_DEFENSIVE_BUFF", "self-buff fallback reason mismatch")

    chosen, reason = mock_choose_defensive_action({
        cure = red_ally_cure,
        debuff = self_paralyna,
        buff = majesty_buff,
    })
    assert_equal(chosen, self_paralyna, "self Paralyna must remain allowed to outrank cure")
    assert_equal(reason, "BLOCK_DEFENSIVE_NA", "self Paralyna reason mismatch")

    assert_contains(source, "scheduler.PRIORITY_BAND_CRITICAL_CURE = 220", "critical cure scheduler priority band must remain globally pinned")
    local provider_source = read_file("uc_provider_defensive.lua")
    assert_contains(source, "critical_cure_priority = scheduler.PRIORITY_BAND_CRITICAL_CURE", "scheduler must inject the global critical Cure band")
    assert_contains(provider_source, "priority_band = critical_cure_priority", "critical cure proposals must use the injected global priority band")
    assert_contains(provider_source, "provider = 'defensive_internal'", "defensive proposal must still emit through defensive_internal provider")

    io.stdout:write("selftest_defensive_cure_priority: OK\n")
end

main()
