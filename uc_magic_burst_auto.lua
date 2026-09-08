local M = {}

local ELEMENT_PRIORITY = {
    'Lightning',
    'Ice',
    'Fire',
    'Wind',
    'Water',
    'Earth',
    'Light',
    'Dark',
}

local FAMILY_MAX_TIER = {
    spell = 5,
    ra = 3,
    helix = 2,
}

local FAMILY_SPELLS = {
    spell = {
        Fire = { 'Fire', 'Fire II', 'Fire III', 'Fire IV', 'Fire V' },
        Ice = { 'Blizzard', 'Blizzard II', 'Blizzard III', 'Blizzard IV', 'Blizzard V' },
        Wind = { 'Aero', 'Aero II', 'Aero III', 'Aero IV', 'Aero V' },
        Earth = { 'Stone', 'Stone II', 'Stone III', 'Stone IV', 'Stone V' },
        Lightning = { 'Thunder', 'Thunder II', 'Thunder III', 'Thunder IV', 'Thunder V' },
        Water = { 'Water', 'Water II', 'Water III', 'Water IV', 'Water V' },
    },
    ra = {
        Fire = { 'Fira', 'Fira II', 'Fira III' },
        Ice = { 'Blizzara', 'Blizzara II', 'Blizzara III' },
        Wind = { 'Aerora', 'Aerora II', 'Aerora III' },
        Earth = { 'Stonera', 'Stonera II', 'Stonera III' },
        Lightning = { 'Thundara', 'Thundara II', 'Thundara III' },
        Water = { 'Watera', 'Watera II', 'Watera III' },
    },
    helix = {
        Fire = { 'Pyrohelix', 'Pyrohelix II' },
        Ice = { 'Cryohelix', 'Cryohelix II' },
        Wind = { 'Anemohelix', 'Anemohelix II' },
        Earth = { 'Geohelix', 'Geohelix II' },
        Lightning = { 'Ionohelix', 'Ionohelix II' },
        Water = { 'Hydrohelix', 'Hydrohelix II' },
        Light = { 'Luminohelix', 'Luminohelix II' },
        Dark = { 'Noctohelix', 'Noctohelix II' },
    },
}

local HELIX_TIER_UNAVAILABLE = {
    BLOCK_DEFENSIVE_UNKNOWN_SPELL = true,
    BLOCK_DEFENSIVE_NOT_LEARNED = true,
    BLOCK_DEFENSIVE_JOB_CANNOT_USE_SPELL = true,
}

local function spell_resource(name)
    local res = require('resources')
    if type(res.spells) ~= 'table' or type(res.spells.with) ~= 'function' then
        return nil
    end
    return res.spells:with('en', tostring(name or ''))
end

local function spell_element(spell)
    if type(spell) ~= 'table' then
        return ''
    end
    if type(spell.element) == 'string' then
        return spell.element
    end
    local res = require('resources')
    local element_id = tonumber(spell.element)
    local element = element_id and res.elements and res.elements[element_id] or nil
    return tostring(element and element.en or '')
end

local function target_distance(target)
    local squared = tonumber(target and target.distance)
    if squared == nil or squared < 0 then
        return nil
    end
    return math.sqrt(squared)
end

local function valid_target(target)
    return type(target) == 'table'
        and target.valid_target == true
        and tonumber(target.spawn_type) == 16
        and (tonumber(target.hpp) or 0) > 0
        and (tonumber(target.id) or 0) > 0
end

local function skillchain_property(state)
    if type(state) ~= 'table' then
        return ''
    end
    local property = tostring(state.last_confirmed_result or '')
    if property == '' and type(state.active_properties) == 'table' then
        property = tostring(state.active_properties[1] or '')
    end
    return property
end

local function player_has_buff(ctx, buff_id)
    local wanted = tonumber(buff_id) or 0
    if wanted <= 0 then
        return false
    end
    local player = type(ctx) == 'table' and ctx.player or nil
    for _, observed in pairs(type(player) == 'table' and type(player.buffs) == 'table' and player.buffs or {}) do
        if tonumber(observed) == wanted then
  return true
        end
    end
    return false
end

local function would_spend_sch_stratagem(ctx, family, spell_name)
    if family ~= 'spell' then
        return false
    end
    local player = type(ctx) == 'table' and ctx.player or nil
    if type(player) ~= 'table' or tostring(player.main_job or '') ~= 'SCH' then
        return false
    end
    local sch_skillchain = require('uc_sch_skillchain')
    if sch_skillchain.requires_addendum_black(spell_name) ~= true then
        return false
    end
    local capabilities = require('uc_sch_capabilities')
    local addendum_black = capabilities.abilities and capabilities.abilities.addendum_black or nil
    return not player_has_buff(ctx, addendum_black and addendum_black.buff_id)
end

local function compatible_elements(property)
    local skillchain_elements = require('uc_skillchain_elements')
    local out = {}
    local list = skillchain_elements.elements(property)
    for i = 1, #list do
        out[tostring(list[i])] = true
    end
    return out
end

local function resolved_ceiling(family, configured)
    local family_max = FAMILY_MAX_TIER[family]
    if family_max == nil then
        return nil
    end
    local ceiling = tonumber(configured) or 0
    ceiling = math.floor(ceiling)
    if ceiling <= 0 then
        return family_max
    end
    if ceiling > family_max then
        return family_max
    end
    return ceiling
end

local function in_range(spell, distance, action_effective_range)
    if type(spell) ~= 'table' or distance == nil then
        return false
    end
    local max_range = tonumber(action_effective_range(spell.range)) or 0
    return max_range > 0 and distance <= max_range
end

local function ready_choice(name, tier, family, target_id, distance, ctx, action_ready, action_effective_range)
    local spell = spell_resource(name)
    if not spell or not in_range(spell, distance, action_effective_range) then
        return nil, 'unavailable'
    end
    if would_spend_sch_stratagem(ctx, family, name) then
        return nil, 'stratagem'
    end
    local ready, reason, kind = action_ready(name, target_id)
    if ready == true and kind == 'spell' then
        return {
  name = name,
  spell = spell,
  element = spell_element(spell),
  tier = tier,
  readiness_reason = tostring(reason or ''),
        }, nil
    end
    return nil, tostring(reason or '')
end

local function choose_nonhelix(property, family, ceiling, target_id, distance, ctx, action_ready, action_effective_range)
    local compatible = compatible_elements(property)
    local table_for_family = FAMILY_SPELLS[family] or {}
    for tier = ceiling, 1, -1 do
        for i = 1, #ELEMENT_PRIORITY do
  local element = ELEMENT_PRIORITY[i]
  local ladder = table_for_family[element]
  local name = compatible[element] and ladder and ladder[tier] or nil
  if name then
      local choice = ready_choice(name, tier, family, target_id, distance, ctx, action_ready, action_effective_range)
      if choice then
          return choice
      end
  end
        end
    end
    return nil
end

local function choose_helix(property, ceiling, target_id, distance, ctx, action_ready, action_effective_range)
    local compatible = compatible_elements(property)
    local table_for_family = FAMILY_SPELLS.helix
    for i = 1, #ELEMENT_PRIORITY do
        local element = ELEMENT_PRIORITY[i]
        local ladder = compatible[element] and table_for_family[element] or nil
        if ladder then
  local element_has_known_spell = false
  for tier = ceiling, 1, -1 do
      local name = ladder[tier]
      if name then
          local spell = spell_resource(name)
          if spell and in_range(spell, distance, action_effective_range) then
              local ready, reason, kind = action_ready(name, target_id)
              if ready == true and kind == 'spell' then
                  return {
                      name = name,
                      spell = spell,
                      element = spell_element(spell),
                      tier = tier,
                      readiness_reason = tostring(reason or ''),
                  }
              end
              local reason_text = tostring(reason or '')
              if HELIX_TIER_UNAVAILABLE[reason_text] then
                  -- This tier is not actually available to the current job/character.
                  -- It is safe to try the lower learned tier, or another compatible
                  -- element if neither tier exists for this character.
              else
                  -- Recast/MP/other runtime blocks mean a Helix of this element is
                  -- already unavailable right now. Never throw a weaker or alternate
                  -- Helix into the window just to replace a non-stacking Helix effect.
                  return nil
              end
              element_has_known_spell = true
          end
      end
  end
  if element_has_known_spell then
      -- Both tiers existed as resources but were unavailable-to-character. Continue
      -- to another compatible element only for that permanent capability case.
  end
        end
    end
    return nil
end

local function choose_for_target(property, family, max_tier, target_id, distance, ctx, action_ready, action_effective_range)
    local ceiling = resolved_ceiling(family, max_tier)
    if ceiling == nil then
        return nil
    end
    if family == 'helix' then
        return choose_helix(property, ceiling, target_id, distance, ctx, action_ready, action_effective_range)
    end
    return choose_nonhelix(property, family, ceiling, target_id, distance, ctx, action_ready, action_effective_range)
end

function M.select(ctx, burst, deps)
    local action_ready = assert(deps and deps.action_ready, 'auto burst requires action_ready')
    local action_effective_range = assert(deps and deps.action_effective_range, 'auto burst requires action_effective_range')
    local family = tostring(burst and burst.family or 'spell'):lower()
    if FAMILY_MAX_TIER[family] == nil then
        return nil
    end

    local combat_core = require('unified_combat_core')
    local targeting_common = require('uc_targeting_common')
    local party_snapshot = type(ctx.party) == 'table' and ctx.party or {}
    local _claim_ids, claims_set = targeting_common.build_friendly_claims({ party = party_snapshot })
    if type(claims_set) ~= 'table' then
        return nil
    end

    local now = tonumber(ctx.now) or 0
    local selected_id = ctx.target_present == true and tonumber(ctx.target and ctx.target.id) or 0
    local best = nil
    local seen = {}

    local function consider(target)
        if not valid_target(target) then
  return
        end
        local target_id = tonumber(target.id) or 0
        if target_id <= 0 or seen[target_id] then
  return
        end
        seen[target_id] = true
        local claim_id = tonumber(target.claim_id) or 0
        if claim_id <= 0 or claims_set[claim_id] ~= true then
  return
        end
        local distance = target_distance(target)
        if distance == nil then
  return
        end
        local state = combat_core.get_skillchain_snapshot(target_id)
        if type(state) ~= 'table' then
  return
        end
        local mb_expires = tonumber(state.magic_burst_expires_at) or 0
        local remaining = mb_expires - now
        if remaining <= 0 then
  return
        end
        local property = skillchain_property(state)
        if property == '' then
  return
        end
        local choice = choose_for_target(
  property,
  family,
  burst.max_tier,
  target_id,
  distance,
  ctx,
  action_ready,
  action_effective_range
        )
        if choice == nil or choice.element == '' then
  return
        end
        local candidate = {
  name = choice.name,
  spell = choice.spell,
  element = choice.element,
  tier = choice.tier,
  family = family,
  target = target,
  target_id = target_id,
  target_name = tostring(target.name or ''),
  property = property,
  mb_expires = mb_expires,
  remaining = remaining,
  distance = distance,
  selected = target_id == selected_id,
        }
        if best == nil
  or candidate.mb_expires > best.mb_expires
  or (candidate.mb_expires == best.mb_expires and candidate.selected and not best.selected)
  or (candidate.mb_expires == best.mb_expires and candidate.selected == best.selected
      and candidate.distance < best.distance)
  or (candidate.mb_expires == best.mb_expires and candidate.selected == best.selected
      and candidate.distance == best.distance and candidate.target_id < best.target_id) then
  best = candidate
        end
    end

    for _, mob in pairs(type(ctx.mobs_by_id) == 'table' and ctx.mobs_by_id or {}) do
        consider(mob)
    end
    if ctx.target_present == true then
        consider(ctx.target)
    end
    return best
end

return M
