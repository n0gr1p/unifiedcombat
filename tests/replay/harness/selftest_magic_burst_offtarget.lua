local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. ': expected=' .. tostring(expected) .. ', actual=' .. tostring(actual))
    end
end

local function assert_true(value, message)
    if value ~= true then
        error(message or 'expected true')
    end
end

local mocked = {
    'resources',
    'uc_combat_extension_config',
    'uc_reaction_runtime',
    'unified_combat_core',
    'uc_targeting_common',
    'uc_combat_extensions',
}
local old_loaded = {}
local old_preload = {}
for i = 1, #mocked do
    local name = mocked[i]
    old_loaded[name] = package.loaded[name]
    old_preload[name] = package.preload[name]
    package.loaded[name] = nil
    package.preload[name] = nil
end

local function restore()
    for i = 1, #mocked do
        local name = mocked[i]
        package.loaded[name] = old_loaded[name]
        package.preload[name] = old_preload[name]
    end
end

local ok, err = xpcall(function()
    package.preload.resources = function()
        local spells = {
            [1] = { id = 1, en = 'Fire V', element = 'Fire', range = 12 },
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

    package.preload.uc_combat_extension_config = function()
        return {
            reaction_rules = function() return {} end,
            magic_burst = function()
                return { enabled = true, spell = 'Fire V' }
            end,
            auto_engage_enabled = function() return false end,
        }
    end

    package.preload.uc_reaction_runtime = function()
        return { get_action_lock = function() return nil end }
    end

    local states = {}
    package.preload.unified_combat_core = function()
        return {
            get_skillchain_snapshot = function(target_id)
                return states[tonumber(target_id)]
            end,
        }
    end

    local friendly_claim = 123
    package.preload.uc_targeting_common = function()
        return {
            build_friendly_claims = function()
                return { friendly_claim }, { [friendly_claim] = true }
            end,
        }
    end

    local extension = require('uc_combat_extensions').new({
        action_ready = function(name, target_id)
            if name == 'Fire V' and tonumber(target_id) and tonumber(target_id) > 0 then
                return true, 'OK', 'spell'
            end
            return false, 'NOT_READY', 'spell'
        end,
        action_effective_range = function()
            return 20.9
        end,
    })

    local burst_mob = {
        id = 900,
        name = 'Zerde',
        hpp = 100,
        valid_target = true,
        spawn_type = 16,
        claim_id = friendly_claim,
        distance = 100,
    }
    local selected_mob = {
        id = 901,
        name = 'Other Mob',
        hpp = 100,
        valid_target = true,
        spawn_type = 16,
        claim_id = friendly_claim,
        distance = 25,
    }
    local ctx = {
        now = 100,
        settings = {},
        target_present = true,
        target = selected_mob,
        mobs_by_id = {
            [burst_mob.id] = burst_mob,
            [selected_mob.id] = selected_mob,
        },
    }

    states[900] = {
        last_confirmed_result = 'Fusion',
        active_properties = { 'Fusion' },
        magic_burst_expires_at = 110,
    }

    local proposals = {}
    assert_true(extension.collect_priority_offense(ctx, proposals), 'off-target Fusion must produce a burst proposal')
    assert_equal(#proposals, 1, 'off-target burst proposal count')
    assert_equal(proposals[1].target_id, 900, 'burst must target skillchain mob instead of selected mob')
    assert_equal(proposals[1].detail.off_target, true, 'off-target diagnostic flag')
    assert_equal(proposals[1].detail.selected_target_id, 901, 'selected target diagnostic id')

    ctx.target_present = false
    ctx.target = nil
    proposals = {}
    assert_true(extension.collect_priority_offense(ctx, proposals), 'missing UI target must not suppress burst')
    assert_equal(proposals[1].target_id, 900, 'targetless burst must use skillchain target id')

    -- The freshest compatible burst window wins even if an older window is on <t>.
    ctx.target_present = true
    ctx.target = selected_mob
    states[901] = {
        last_confirmed_result = 'Fusion',
        active_properties = { 'Fusion' },
        magic_burst_expires_at = 108,
    }
    proposals = {}
    assert_true(extension.collect_priority_offense(ctx, proposals), 'competing burst windows must still produce a proposal')
    assert_equal(proposals[1].target_id, 900, 'freshest burst window must outrank selected older window')

    -- A newer selected window wins when it is actually the newest relevant skillchain.
    states[901].magic_burst_expires_at = 111
    proposals = {}
    assert_true(extension.collect_priority_offense(ctx, proposals), 'newest selected burst window must produce a proposal')
    assert_equal(proposals[1].target_id, 901, 'newest skillchain event must own burst target')

    -- Foreign claims are never valid burst targets.
    states[901] = nil
    burst_mob.claim_id = 999
    proposals = {}
    assert_equal(extension.collect_priority_offense(ctx, proposals), false, 'foreign-claimed skillchain must not burst')
    assert_equal(#proposals, 0, 'foreign-claimed burst proposal count')

    -- Restore claim but move the skillchain target outside spell range.
    burst_mob.claim_id = friendly_claim
    burst_mob.distance = 22 * 22
    proposals = {}
    assert_equal(extension.collect_priority_offense(ctx, proposals), false, 'out-of-range skillchain must not burst')
    assert_equal(#proposals, 0, 'out-of-range burst proposal count')

    -- Restore range but use an incompatible result for Fire.
    burst_mob.distance = 100
    states[900] = {
        last_confirmed_result = 'Distortion',
        active_properties = { 'Distortion' },
        magic_burst_expires_at = 110,
    }
    proposals = {}
    assert_equal(extension.collect_priority_offense(ctx, proposals), false, 'element mismatch must not burst')
    assert_equal(#proposals, 0, 'element mismatch burst proposal count')
end, debug.traceback)

restore()
if not ok then
    error(err)
end

io.stdout:write('selftest_magic_burst_offtarget: OK\n')
