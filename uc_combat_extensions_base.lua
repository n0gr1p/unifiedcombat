local M = {}

-- A confirmed skillchain exposes a 10 second MB window. Keep evaluating burst
-- opportunities until the observed window actually expires. A spell that lands
-- after expiry is still useful as a normal nuke, so there is no artificial
-- pre-expiry landing guard.
local REACTION_PRIORITY_BAND = 240
local MAGIC_BURST_PRIORITY_BAND = 170

-- A configured elemental nuke is a ceiling, not an all-or-nothing choice.
-- Walk downward until the highest currently ready spell is found. This both
-- preserves damage on successive skillchains while the top tier is on recast
-- and naturally enables a second burst in the same window after the first spell
-- puts itself on recast. GEO -ra spells keep their own III -> II -> I ladders
-- rather than crossing over to the normal single-target nuke family.
--
-- Helix spells are different: a lower-tier Helix is not a useful follow-up
-- because Helix effects do not stack. For the six normal elements, a configured
-- Helix therefore falls back to the highest ready direct-damage single-target
-- nuke of the same element. Light/Dark Helix have no corresponding normal SCH
-- elemental nuke ladder, so they do not fall back to a weaker Helix.
local BURST_SPELL_LADDERS = {
    { 'Fire V', 'Fire IV', 'Fire III', 'Fire II', 'Fire' },
    { 'Blizzard V', 'Blizzard IV', 'Blizzard III', 'Blizzard II', 'Blizzard' },
    { 'Aero V', 'Aero IV', 'Aero III', 'Aero II', 'Aero' },
    { 'Stone V', 'Stone IV', 'Stone III', 'Stone II', 'Stone' },
    { 'Thunder V', 'Thunder IV', 'Thunder III', 'Thunder II', 'Thunder' },
    { 'Water V', 'Water IV', 'Water III', 'Water II', 'Water' },
    { 'Fira III', 'Fira II', 'Fira' },
    { 'Blizzara III', 'Blizzara II', 'Blizzara' },
    { 'Aerora III', 'Aerora II', 'Aerora' },
    { 'Stonera III', 'Stonera II', 'Stonera' },
    { 'Thundara III', 'Thundara II', 'Thundara' },
    { 'Watera III', 'Watera II', 'Watera' },
    { 'Pyrohelix II', 'Fire V', 'Fire IV', 'Fire III', 'Fire II', 'Fire' },
    { 'Pyrohelix', 'Fire V', 'Fire IV', 'Fire III', 'Fire II', 'Fire' },
    { 'Cryohelix II', 'Blizzard V', 'Blizzard IV', 'Blizzard III', 'Blizzard II', 'Blizzard' },
    { 'Cryohelix', 'Blizzard V', 'Blizzard IV', 'Blizzard III', 'Blizzard II', 'Blizzard' },
    { 'Anemohelix II', 'Aero V', 'Aero IV', 'Aero III', 'Aero II', 'Aero' },
    { 'Anemohelix', 'Aero V', 'Aero IV', 'Aero III', 'Aero II', 'Aero' },
    { 'Geohelix II', 'Stone V', 'Stone IV', 'Stone III', 'Stone II', 'Stone' },
    { 'Geohelix', 'Stone V', 'Stone IV', 'Stone III', 'Stone II', 'Stone' },
    { 'Ionohelix II', 'Thunder V', 'Thunder IV', 'Thunder III', 'Thunder II', 'Thunder' },
    { 'Ionohelix', 'Thunder V', 'Thunder IV', 'Thunder III', 'Thunder II', 'Thunder' },
    { 'Hydrohelix II', 'Water V', 'Water IV', 'Water III', 'Water II', 'Water' },
    { 'Hydrohelix', 'Water V', 'Water IV', 'Water III', 'Water II', 'Water' },
    { 'Luminohelix II' },
    { 'Luminohelix' },
    { 'Noctohelix II' },
    { 'Noctohelix' },
}

local function require_function(deps, name)
    local value = deps[name]
    if type(value) ~= 'function' then
        error(('uc_combat_extensions deps.%s must be a function'):format(name))
    end
    return value
end

local function extension_config()
    return require('uc_combat_extension_config')
end

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

local function burst_spell_candidates(configured_name)
    local configured = tostring(configured_name or '')
    if configured == '' then
        return {}
    end
    for ladder_index = 1, #BURST_SPELL_LADDERS do
        local ladder = BURST_SPELL_LADDERS[ladder_index]
        for spell_index = 1, #ladder do
            if ladder[spell_index] == configured then
                local out = {}
                for fallback_index = spell_index, #ladder do
                    out[#out + 1] = ladder[fallback_index]
                end
                return out
            end
        end
    end
    return { configured }
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

local function is_helix_spell(name)
    return tostring(name or ''):lower():find('helix', 1, true) ~= nil
end

local function helix_fallback_requires_new_stratagem(ctx, configured_name, candidate_name)
    if not is_helix_spell(configured_name) then
        return false
    end
    local player = type(ctx) == 'table' and ctx.player or nil
    if type(player) ~= 'table' or tostring(player.main_job or '') ~= 'SCH' then
        return false
    end
    local sch_skillchain = require('uc_sch_skillchain')
    if sch_skillchain.requires_addendum_black(candidate_name) ~= true then
        return false
    end
    local capabilities = require('uc_sch_capabilities')
    local addendum_black = capabilities.abilities and capabilities.abilities.addendum_black or nil
    return not player_has_buff(ctx, addendum_black and addendum_black.buff_id)
end

local function select_ready_burst_spell(configured_name, target_id, action_ready, ctx)
    local candidates = burst_spell_candidates(configured_name)
    for index = 1, #candidates do
        local name = candidates[index]
        local spell = spell_resource(name)
        if spell and not helix_fallback_requires_new_stratagem(ctx, configured_name, name) then
            local ready, reason, kind = action_ready(name, target_id)
            if ready == true and kind == 'spell' then
                return {
                    name = name,
                    spell = spell,
                    configured = tostring(configured_name or ''),
                    stepped_down = name ~= tostring(configured_name or ''),
                    step_index = index,
                    checked_count = index,
                    readiness_reason = tostring(reason or ''),
                }
            end
        end
    end
    return nil
end

local function valid_target(target)
    return type(target) == 'table'
        and target.valid_target == true
        and tonumber(target.spawn_type) == 16
        and (tonumber(target.hpp) or 0) > 0
        and (tonumber(target.id) or 0) > 0
end

local function target_distance(target)
    local squared = tonumber(target and target.distance)
    if squared == nil or squared < 0 then
        return nil
    end
    return math.sqrt(squared)
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

local function magic_burst_target(ctx, spell, element, action_effective_range)
    if element == '' then
        return nil
    end
    local combat_core = require('unified_combat_core')
    local skillchain_elements = require('uc_skillchain_elements')
    local targeting_common = require('uc_targeting_common')
    local party_snapshot = type(ctx.party) == 'table' and ctx.party or {}
    local _claim_ids, claims_set = targeting_common.build_friendly_claims({ party = party_snapshot })
    if type(claims_set) ~= 'table' then
        return nil
    end

    local max_range = tonumber(action_effective_range(spell.range)) or 0
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
        if distance == nil or max_range <= 0 or distance > max_range then
            return
        end
        local state = combat_core.get_skillchain_snapshot(target_id)
        if type(state) ~= 'table' then
            return
        end
        local mb_expires = tonumber(state.magic_burst_expires_at) or 0
        local remaining = mb_expires - (tonumber(ctx.now) or 0)
        if remaining <= 0 then
            return
        end
        local property = skillchain_property(state)
        if property == '' or not skillchain_elements.contains(property, element) then
            return
        end
        local candidate = {
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

local function copy_detail(detail)
    local out = { allow_target_id_send = true }
    for key, value in pairs(type(detail) == 'table' and detail or {}) do
        out[key] = value
    end
    return out
end

local function append_spell(out, ctx, options)
    local spell = spell_resource(options.spell_name)
    if not spell then
        return false
    end
    local ok_ready, _, kind = options.action_ready(options.spell_name, options.target_id)
    if ok_ready ~= true or kind ~= 'spell' then
        return false
    end
    local max_range = options.action_effective_range(spell.range)
    out[#out + 1] = {
        proposal_id = ('combat.%s.%s.%d.%d'):format(
            options.id_prefix,
            tostring(options.spell_name),
            tonumber(options.target_id) or 0,
            math.floor((tonumber(ctx.now) or 0) * 1000)
        ),
        family_id = options.family_id,
        provider = 'combat',
        action_type = 'spell',
        action_name = tostring(options.spell_name),
        target_kind = 'mob',
        target_id = tonumber(options.target_id) or 0,
        target_name = tostring(options.target_name or ''),
        priority_band = options.priority_band,
        urgency = options.urgency or 1.0,
        starvation_eligible = false,
        created_at = ctx.now,
        expires_at = ctx.now + 0.30,
        commit_deadline = ctx.now + 0.20,
        movement_policy = 'must_stop',
        range_policy = { min = 0.0, max = max_range, los_required = true },
        recast_key = ('spell:%s'):format(tostring(options.spell_name)),
        duplicate_suppression_key = ('%s:%s:%d'):format(
            options.id_prefix,
            tostring(options.spell_name),
            tonumber(options.target_id) or 0
        ),
        lock_class = 'offense_action',
        expected_ack = 'action_start',
        expected_effect = 'spell_effect',
        sticky = false,
        can_preempt_movement = true,
        can_preempt_same_band = true,
        reason_code = options.reason_code,
        detail = copy_detail(options.detail),
        legacy_command = ('input /ma \"%s\" %d'):format(
            tostring(options.spell_name),
            tonumber(options.target_id) or 0
        ),
    }
    return true
end

local function action_reaction_configured(rules)
    if type(rules) ~= 'table' then
        return false
    end
    for i = 1, #rules do
        local rule = rules[i]
        if type(rule) == 'table' and rule.response == 'use_action' then
            return true
        end
    end
    return false
end

function M.new(deps)
    local action_ready = require_function(deps, 'action_ready')
    local action_effective_range = require_function(deps, 'action_effective_range')
    local api = {}

    function api.auto_engage_enabled_from_config(config)
        return extension_config().auto_engage_enabled_from_config(config)
    end

    function api.auto_engage_enabled(settings)
        return extension_config().auto_engage_enabled(settings)
    end

    function api.collect_priority_offense(ctx, out)
        local config = extension_config()
        local reaction_rules = config.reaction_rules()
        if action_reaction_configured(reaction_rules) then
            local reaction_runtime = require('uc_reaction_runtime')
            local action_lock = reaction_runtime.get_action_lock()
            if type(action_lock) == 'table' then
                local action_type = tostring(action_lock.action_type or ''):lower()
                local action_name = tostring(action_lock.action_name or '')
                if action_type == 'spell' and action_name ~= '' then
                    if append_spell(out, ctx, {
                        action_ready = action_ready,
                        action_effective_range = action_effective_range,
                        spell_name = action_name,
                        target_id = tonumber(action_lock.actor_id) or 0,
                        target_name = tostring(action_lock.actor_name or action_lock.name or ''),
                        family_id = 'combat.reaction.action',
                        id_prefix = 'reaction',
                        priority_band = REACTION_PRIORITY_BAND,
                        urgency = 1.0,
                        reason_code = 'reaction_action',
                        detail = {
                            reaction_name = tostring(action_lock.name or ''),
                            reaction_key = tostring(action_lock.key or ''),
                        },
                    }) then
                        return true
                    end
                end
            end
        end

        -- The scheduler's tick-stable Profile V2 config is the sole durable
        -- burst policy. Only legacy callers without a config snapshot use
        -- the compatibility reader.
        local burst
        if type(ctx.config) == 'table' then
            burst = config.magic_burst_from_config(ctx.config)
        else
            burst = config.magic_burst(ctx.settings)
        end
        if burst.enabled ~= true then
  return false
        end

        if burst.mode == 'auto' then
  local auto_choice = require('uc_magic_burst_auto').select(ctx, burst, {
      action_ready = action_ready,
      action_effective_range = action_effective_range,
  })
  if auto_choice == nil then
      return false
  end
  return append_spell(out, ctx, {
      action_ready = action_ready,
      action_effective_range = action_effective_range,
      spell_name = auto_choice.name,
      target_id = auto_choice.target_id,
      target_name = auto_choice.target_name,
      family_id = 'combat.magic_burst',
      id_prefix = 'magic_burst',
      priority_band = MAGIC_BURST_PRIORITY_BAND,
      urgency = 1.0 - math.min(1.0, auto_choice.remaining / 10.0),
      reason_code = 'magic_burst_auto',
      detail = {
          skillchain_property = auto_choice.property,
          spell_element = auto_choice.element,
          magic_burst_mode = 'auto',
          magic_burst_family = auto_choice.family,
          magic_burst_max_tier = burst.max_tier,
          selected_burst_spell = auto_choice.name,
          selected_burst_tier = auto_choice.tier,
          auto_burst = true,
          magic_burst_expires_at = auto_choice.mb_expires,
          window_remaining_s = auto_choice.remaining,
          selected_target_id = ctx.target_present == true and tonumber(ctx.target and ctx.target.id) or 0,
          off_target = auto_choice.selected ~= true,
      },
  })
        end

        if burst.spell == '' then
  return false
        end
        local configured_spell = spell_resource(burst.spell)
        if not configured_spell then
  return false
        end
        local element = spell_element(configured_spell)
        local burst_target = magic_burst_target(ctx, configured_spell, element, action_effective_range)
        if burst_target == nil then
  return false
        end
        local burst_choice = select_ready_burst_spell(
  burst.spell,
  burst_target.target_id,
  action_ready,
  ctx
        )
        if burst_choice == nil then
  return false
        end
        local chosen_element = spell_element(burst_choice.spell)
        if chosen_element == '' or chosen_element ~= element then
  return false
        end
        return append_spell(out, ctx, {
  action_ready = action_ready,
  action_effective_range = action_effective_range,
  spell_name = burst_choice.name,
  target_id = burst_target.target_id,
  target_name = burst_target.target_name,
  family_id = 'combat.magic_burst',
  id_prefix = 'magic_burst',
  priority_band = MAGIC_BURST_PRIORITY_BAND,
  urgency = 1.0 - math.min(1.0, burst_target.remaining / 10.0),
  reason_code = burst_choice.stepped_down and 'magic_burst_step_down' or 'magic_burst_window',
  detail = {
      skillchain_property = burst_target.property,
      spell_element = chosen_element,
      configured_burst_spell = burst_choice.configured,
      selected_burst_spell = burst_choice.name,
      burst_step_down = burst_choice.stepped_down,
      burst_step_index = burst_choice.step_index,
      magic_burst_expires_at = burst_target.mb_expires,
      window_remaining_s = burst_target.remaining,
      selected_target_id = ctx.target_present == true and tonumber(ctx.target and ctx.target.id) or 0,
      off_target = burst_target.selected ~= true,
  },
        })
    end

    return api
end

return M