local function assert_true(value, message)
    if value ~= true then
        error(message or 'expected true')
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
    end
end

local MOCKED = {
    'resources',
    'uc_active_config',
    'uc_combat_extension_config',
    'uc_reaction_runtime',
    'unified_combat_core',
    'uc_targeting_common',
    'uc_combat_extensions',
}

local original_loaded = {}
local original_preload = {}
for i = 1, #MOCKED do
    local name = MOCKED[i]
    original_loaded[name] = package.loaded[name]
    original_preload[name] = package.preload[name]
    package.loaded[name] = nil
    package.preload[name] = nil
end

local function restore()
    for i = 1, #MOCKED do
        local name = MOCKED[i]
        package.loaded[name] = original_loaded[name]
        package.preload[name] = original_preload[name]
    end
end

local ok, err = xpcall(function()
    local configured_spell = 'Fire V'
    local ready_spells = {}
    local current_skillchain = {
        last_confirmed_result = 'Fusion',
        active_properties = { 'Fusion' },
        magic_burst_expires_at = 110,
    }

    package.preload.resources = function()
        local spells = {
            [1] = { id = 1, en = 'Fire V', element = 'Fire', range = 12 },
            [2] = { id = 2, en = 'Fire IV', element = 'Fire', range = 12 },
            [3] = { id = 3, en = 'Fire III', element = 'Fire', range = 12 },
            [4] = { id = 4, en = 'Fire II', element = 'Fire', range = 12 },
            [5] = { id = 5, en = 'Fire', element = 'Fire', range = 12 },
            [6] = { id = 6, en = 'Pyrohelix II', element = 'Fire', range = 12 },
            [7] = { id = 7, en = 'Pyrohelix', element = 'Fire', range = 12 },
        }
        function spells:with(key, value)
            if key ~= 'en' then return nil end
            for _, spell in pairs(self) do
                if type(spell) == 'table' and spell.en == value then
                    return spell
                end
            end
            return nil
        end
        return { spells = spells, elements = {} }
    end

    package.preload.uc_active_config = function()
        return {
            get_path = function(path)
                if path == 'config.spells' then
                    return {
                        magic_burst = true,
                        configured = configured_spell,
                    }
                end
                if path == 'config.reactions' then
                    return { enabled = false, rules = {} }
                end
                return nil
            end,
        }
    end

    package.preload.uc_reaction_runtime = function()
        return { get_action_lock = function() return nil end }
    end

    package.preload.unified_combat_core = function()
        return {
            get_skillchain_snapshot = function(target_id)
                if tonumber(target_id) == 900 then
                    return current_skillchain
                end
                return nil
            end,
        }
    end

    package.preload.uc_targeting_common = function()
        return {
            build_friendly_claims = function()
                return { 123 }, { [123] = true }
            end,
        }
    end

    local extension = require('uc_combat_extensions').new({
        action_ready = function(name)
            if ready_spells[name] == true then
                return true, 'OK', 'spell'
            end
            return false, 'RECAST', 'spell'
        end,
        action_effective_range = function()
            return 20.9
        end,
    })

    local ctx = {
        now = 100,
        settings = {},
        player = { main_job = 'SCH', buffs = { 359 } }, -- Dark Arts, not Addendum: Black.
        target_present = false,
        target = nil,
        party = {},
        mobs_by_id = {
            [900] = {
                id = 900,
                name = 'Zerde',
                hpp = 100,
                valid_target = true,
                spawn_type = 16,
                claim_id = 123,
                distance = 100,
            },
        },
    }

    -- First pass: use the configured ceiling when it is ready.
    ready_spells = { ['Fire V'] = true, ['Fire IV'] = true, ['Fire III'] = true }
    local out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'ready Fire V must produce burst proposal')
    assert_equal(#out, 1, 'first burst proposal count')
    assert_equal(out[1].action_name, 'Fire V', 'first burst must use configured top tier')
    assert_equal(out[1].reason_code, 'magic_burst_window', 'top-tier burst reason')
    assert_true(out[1].detail.burst_step_down == false, 'top-tier burst must not report step down')

    -- Same confirmed skillchain window after Fire V has been spent: the first
    -- spell is now on recast, so the second burst must use Fire IV rather than
    -- abandoning the remaining MB window.
    ctx.now = 104.5
    ready_spells['Fire V'] = false
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'same window must allow second burst')
    assert_equal(#out, 1, 'second burst proposal count')
    assert_equal(out[1].action_name, 'Fire IV', 'second burst must step down to Fire IV')
    assert_equal(out[1].reason_code, 'magic_burst_step_down', 'step-down burst reason')
    assert_equal(out[1].detail.configured_burst_spell, 'Fire V', 'step-down must retain configured ceiling')
    assert_equal(out[1].detail.selected_burst_spell, 'Fire IV', 'step-down selected spell detail')
    assert_true(out[1].detail.window_remaining_s > 5, 'second burst should use remaining original window')

    -- Successive skillchain while higher tiers are still cooling down: descend
    -- until the highest ready tier is found.
    ctx.now = 200
    current_skillchain = {
        last_confirmed_result = 'Fusion',
        active_properties = { 'Fusion' },
        magic_burst_expires_at = 210,
    }
    ready_spells = { ['Fire III'] = true, ['Fire II'] = true, ['Fire'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'third-tier fallback must still burst next chain')
    assert_equal(out[1].action_name, 'Fire III', 'must choose highest ready fallback tier')

    -- Configured spell is a ceiling: never step upward above Fire III.
    configured_spell = 'Fire III'
    ready_spells = { ['Fire V'] = true, ['Fire IV'] = true, ['Fire III'] = false, ['Fire II'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'lower configured ceiling must still fallback')
    assert_equal(out[1].action_name, 'Fire II', 'fallback must not step above configured Fire III ceiling')

    -- A configured Helix gets first priority while ready.
    configured_spell = 'Pyrohelix II'
    ready_spells = { ['Pyrohelix II'] = true, ['Fire V'] = true, ['Fire IV'] = true, ['Fire III'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'ready Helix II must be used first')
    assert_equal(out[1].action_name, 'Pyrohelix II', 'configured Helix II must have first burst priority')

    -- Once that Helix is unavailable, never fire the weaker non-stacking Helix I.
    -- Dark Arts alone cannot use Fire IV/V without first spending a stratagem on
    -- Addendum: Black, so the zero-stratagem fallback ceiling is Fire III.
    ready_spells = {
        ['Pyrohelix'] = true,
        ['Fire V'] = true,
        ['Fire IV'] = true,
        ['Fire III'] = true,
        ['Fire II'] = true,
    }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Helix II recast must fallback to direct nuke')
    assert_equal(out[1].action_name, 'Fire III', 'Dark-Arts Helix fallback must avoid Addendum-required tiers')
    assert_true(out[1].action_name ~= 'Pyrohelix', 'Helix fallback must never use weaker non-stacking Helix I')

    -- If Addendum: Black is already active, IV/V require no new stratagem and
    -- the fallback can use the strongest ready direct nuke.
    ctx.player.buffs = { 402 }
    ready_spells = { ['Pyrohelix'] = true, ['Fire V'] = true, ['Fire IV'] = true, ['Fire III'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'existing Addendum: Black must permit high-tier direct fallback')
    assert_equal(out[1].action_name, 'Fire V', 'Addendum-active Helix fallback must choose strongest ready direct nuke')

    -- If the top direct nuke is also cooling down, continue down the direct-nuke ladder.
    ready_spells = { ['Pyrohelix'] = true, ['Fire III'] = true, ['Fire II'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Helix fallback must continue down nuke ladder')
    assert_equal(out[1].action_name, 'Fire III', 'Helix fallback must choose highest ready direct nuke tier')

    -- If nothing in the configured family is ready, do not emit a doomed cast.
    configured_spell = 'Fire V'
    ready_spells = {}
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out) == false, 'all tiers on recast must suppress burst')
    assert_equal(#out, 0, 'all tiers on recast proposal count')

    -- Preserve a small landing guard at the end of the 10 second window.
    ready_spells = { ['Fire III'] = true }
    ctx.now = 207.6
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out) == false, 'sub-2.5-second window must not start late burst')
    assert_equal(#out, 0, 'late burst proposal count')
end, debug.traceback)

restore()
if not ok then
    error(err)
end

io.stdout:write('selftest_magic_burst_stepdown: OK\n')
