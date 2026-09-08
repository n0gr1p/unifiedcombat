local function assert_true(value, message)
    if value ~= true then error(message or 'expected true') end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected=%s actual=%s'):format(message or 'values differ', tostring(expected), tostring(actual)))
    end
end

local MOCKED = {
    'resources',
    'uc_active_config',
    'uc_reaction_runtime',
    'unified_combat_core',
    'uc_targeting_common',
    'uc_sch_skillchain',
    'uc_sch_capabilities',
    'uc_combat_extension_config',
    'uc_magic_burst_auto',
    'uc_combat_extensions',
}

local original_loaded, original_preload = {}, {}
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
    local burst_mode = 'auto'
    local burst_family = 'spell'
    local burst_max_tier = 0
    local configured_spell = 'Fire V'
    local readiness = {}
    local current_skillchain = {
        last_confirmed_result = 'Fragmentation',
        active_properties = { 'Fragmentation' },
        magic_burst_expires_at = 110,
    }

    local names = {
        'Fire','Fire II','Fire III','Fire IV','Fire V',
        'Blizzard','Blizzard II','Blizzard III','Blizzard IV','Blizzard V',
        'Aero','Aero II','Aero III','Aero IV','Aero V',
        'Stone','Stone II','Stone III','Stone IV','Stone V',
        'Thunder','Thunder II','Thunder III','Thunder IV','Thunder V',
        'Water','Water II','Water III','Water IV','Water V',
        'Fira','Fira II','Fira III','Blizzara','Blizzara II','Blizzara III',
        'Aerora','Aerora II','Aerora III','Stonera','Stonera II','Stonera III',
        'Thundara','Thundara II','Thundara III','Watera','Watera II','Watera III',
        'Pyrohelix','Pyrohelix II','Cryohelix','Cryohelix II',
        'Anemohelix','Anemohelix II','Geohelix','Geohelix II',
        'Ionohelix','Ionohelix II','Hydrohelix','Hydrohelix II',
        'Luminohelix','Luminohelix II','Noctohelix','Noctohelix II',
    }
    local elements = {
        Fire='Fire', Blizzard='Ice', Aero='Wind', Stone='Earth', Thunder='Lightning', Water='Water',
        Fira='Fire', Blizzara='Ice', Aerora='Wind', Stonera='Earth', Thundara='Lightning', Watera='Water',
        Pyrohelix='Fire', Cryohelix='Ice', Anemohelix='Wind', Geohelix='Earth', Ionohelix='Lightning', Hydrohelix='Water',
        Luminohelix='Light', Noctohelix='Dark',
    }
    local function base_name(name)
        return name:gsub(' V$', ''):gsub(' IV$', ''):gsub(' III$', ''):gsub(' II$', '')
    end
    package.preload.resources = function()
        local spells = {}
        for i = 1, #names do
  local name = names[i]
  spells[i] = { id = i, en = name, element = elements[base_name(name)], range = 12 }
        end
        function spells:with(key, value)
  if key ~= 'en' then return nil end
  for _, spell in pairs(self) do
      if type(spell) == 'table' and spell.en == value then return spell end
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
              magic_burst_mode = burst_mode,
              magic_burst_family = burst_family,
              magic_burst_max_tier = burst_max_tier,
          }
      end
      if path == 'config.reactions' then return { enabled = false, rules = {} } end
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
      return tonumber(target_id) == 900 and current_skillchain or nil
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
    package.preload.uc_sch_skillchain = function()
        return {
  requires_addendum_black = function(name)
      return name:find(' IV$', 1) ~= nil or name:find(' V$', 1) ~= nil
  end,
        }
    end
    package.preload.uc_sch_capabilities = function()
        return { abilities = { addendum_black = { buff_id = 402 } } }
    end

    local extension = require('uc_combat_extensions').new({
        action_ready = function(name)
  local value = readiness[name]
  if value == true then return true, 'OK', 'spell' end
  if type(value) == 'string' then return false, value, 'spell' end
  return false, 'BLOCK_DEFENSIVE_NOT_LEARNED', 'spell'
        end,
        action_effective_range = function() return 20.9 end,
    })

    local ctx = {
        now = 100,
        settings = {},
        player = { main_job = 'GEO', buffs = {} },
        target_present = false,
        target = nil,
        party = {},
        mobs_by_id = {
  [900] = {
      id = 900, name = 'Target', hpp = 100, valid_target = true,
      spawn_type = 16, claim_id = 123, distance = 100,
  },
        },
    }

    -- Fragmentation supports Wind + Lightning. Same tier means Thunder is the
    -- stronger direct-nuke family, so Auto Spell should choose Thunder V.
    readiness = { ['Thunder V'] = true, ['Aero V'] = true }
    local out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Auto Spell must produce a Fragmentation burst')
    assert_equal(out[1].action_name, 'Thunder V', 'Auto Spell must choose strongest compatible tier-V nuke')
    assert_equal(out[1].reason_code, 'magic_burst_auto', 'Auto Spell reason mismatch')
    assert_equal(out[1].detail.magic_burst_family, 'spell', 'Auto Spell family detail mismatch')

    -- Tier ceiling is a maximum, not an exact requirement.
    burst_max_tier = 3
    readiness = { ['Thunder V'] = true, ['Thunder IV'] = true, ['Thunder III'] = true, ['Aero III'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'tier-III ceiling must still burst')
    assert_equal(out[1].action_name, 'Thunder III', 'tier ceiling must suppress IV/V')

    -- With no tier ceiling, another compatible same-tier element beats stepping
    -- down when the preferred element is on recast.
    burst_max_tier = 0
    readiness = { ['Thunder V'] = 'BLOCK_DEFENSIVE_RECAST', ['Aero V'] = true, ['Thunder IV'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Auto Spell must use another ready compatible top-tier element')
    assert_equal(out[1].action_name, 'Aero V', 'Auto Spell must prefer ready Aero V over tier-IV fallback')

    -- GEO -ra mode stays in its family and honors its III ceiling.
    current_skillchain.last_confirmed_result = 'Fusion'
    current_skillchain.active_properties = { 'Fusion' }
    burst_family = 'ra'
    burst_max_tier = 0
    readiness = { ['Fira III'] = true, ['Fire V'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Auto -ra must burst Fusion')
    assert_equal(out[1].action_name, 'Fira III', 'Auto -ra must remain in -ra family')
    burst_max_tier = 2
    readiness = { ['Fira III'] = true, ['Fira II'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Auto -ra II ceiling must burst')
    assert_equal(out[1].action_name, 'Fira II', 'Auto -ra ceiling must cap at II')

    -- Auto Helix uses one preferred compatible Helix family and never steps down
    -- merely because Helix II is on recast; nor does it cross into direct nukes.
    burst_family = 'helix'
    burst_max_tier = 0
    readiness = { ['Pyrohelix II'] = true, ['Pyrohelix'] = true, ['Fire V'] = true, ['Luminohelix II'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Auto Helix must use ready Helix II')
    assert_equal(out[1].action_name, 'Pyrohelix II', 'Fusion Auto Helix must prefer Pyrohelix II')
    readiness = { ['Pyrohelix II'] = 'BLOCK_DEFENSIVE_RECAST', ['Pyrohelix'] = true, ['Luminohelix II'] = true, ['Fire V'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out) == false, 'Auto Helix must not replace a cooling Helix with weaker/alternate spell')
    assert_equal(#out, 0, 'Auto Helix recast must emit no fallback')

    -- Tier I is valid when II is not actually learned/usable by the character.
    readiness = { ['Pyrohelix II'] = 'BLOCK_DEFENSIVE_NOT_LEARNED', ['Pyrohelix'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Auto Helix must use learned tier I when tier II is unavailable-to-character')
    assert_equal(out[1].action_name, 'Pyrohelix', 'Auto Helix learned-tier fallback mismatch')

    -- Auto Spell on SCH must not implicitly spend another stratagem just to gain
    -- Addendum: Black. In Dark Arts alone, IV/V are skipped and III is selected.
    burst_family = 'spell'
    burst_max_tier = 0
    ctx.player = { main_job = 'SCH', buffs = { 359 } }
    readiness = { ['Fire V'] = true, ['Fire IV'] = true, ['Fire III'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'SCH Auto Spell must find a zero-stratagem direct nuke')
    assert_equal(out[1].action_name, 'Fire III', 'SCH Auto Spell must avoid Addendum-required IV/V')
    ctx.player.buffs = { 402 }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'Addendum-active SCH Auto Spell must burst')
    assert_equal(out[1].action_name, 'Fire V', 'Addendum-active SCH must regain tier-V ceiling')

    -- Existing exact spell semantics remain intact.
    burst_mode = 'exact'
    configured_spell = 'Fire V'
    readiness = { ['Fire V'] = 'BLOCK_DEFENSIVE_RECAST', ['Fire IV'] = true }
    out = {}
    assert_true(extension.collect_priority_offense(ctx, out), 'exact mode must retain existing step-down behavior')
    assert_equal(out[1].action_name, 'Fire IV', 'exact mode regression: Fire V must step down to Fire IV')
end, debug.traceback)

restore()
if not ok then error(err) end
io.stdout:write('selftest_magic_burst_auto_family: OK\n')
