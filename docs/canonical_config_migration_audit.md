# Canonical Config Migration Audit

Task: `T3.7d`

## Current conclusion

A canonical validated `config` object is worth adding, but it should start as a pure adapter over the current flat `_G.UC_SETTINGS` shape. The current runtime has enough large scheduler and bridge functions that grouped domain subtables would reduce Lua 5.1 local/register pressure and make profile/UI ownership easier to reason about. It should not replace existing profile keys, bridge message paths, or save/load behavior yet.

## Current settings and config surface

`UnifiedCombat.lua` initializes `_G.UC_SETTINGS` through `uc_new_settings_defaults()`. The current object is flat, with a few table-valued fields.

| Area | Current fields |
| --- | --- |
| Profile root | `profiles` |
| Combat and WS | `engine_mode`, `ability_active`, `abilities`, `ability1` through `ability6`, `wsabilities`, `weaponskill`, `ws1`, `weaponskill_active`, `ws_mode`, `aftermath_enabled`, `aftermath_ws`, `autotarget`, `spam`, `closer`, `manual`, `prime`, `static`, `face` |
| Movement and spacing | `move`, `spacing`, `spacing_band_min`, `spacing_band_max`, `spacing_model_size_floor`, `spacing_use_prediction`, `spacing_lookahead_s`, `spacing_repel_hold_ticks`, `spacing_overlap_deadband`, `spacing_repel_weight`, `spacing_band_deadband` |
| Follow and party roles | `partner`, `partner2`, `puller`, `puller_distance_only`, `partner_id`, `partner_id2`, `partner_ids`, `puller_id`, `fight_leader`, `fight_leader_id`, `party_follow`, `party_follow_id`, `party_follow_leader_name`, `party_follow_min`, `party_follow_max`, `fight_follow_min`, `fight_follow_hold_s` |
| Add control and targeting | `add_control`, `add_priority_names`, `target1`, `target2`, `target3`, `targets`, `targetability`, `targetability_active`, `ignore`, `target_ignore_names` |
| Legacy toggles | `sub`, `sub2`, `solo`, `aeonic`, `color`, `command`, `hunter` |
| Debug and UI | `debug`, `log_combat_sched`, `log_ja_sched`, `log_ja_debug`, `log_def_sched`, `log_tank_sched`, `show_ingame_ui` |
| Tank | `tank`, `tank_enmity_actions` |
| Sleep | `sleep`, `sleepspell`, `sleepspells` |
| Defensive | `defensive_enabled`, `defensive_provider`, `defensive_cure_enabled`, `defensive_doom_water`, `def_remove_enemy_buffs`, `def_heal_min_tier_cure`, `def_heal_max_tier_cure`, `def_heal_min_missing_hp`, `def_heal_ignore_trusts`, `defensive_na_enabled`, `defensive_buff_enabled`, `defensive_critical_hpp`, `defensive_medium_hpp`, `defensive_overwrite_enabled`, `defensive_overwrite_interval`, `defensive_buff_self_only`, `defensive_buffs` |
| Domains and ownership toggles | `engine_enabled`, `domain_combat_enabled`, `domain_defensive_enabled`, `domain_movement_enabled`, `domain_maintenance_enabled`, `domain_follow_enabled`, `scheduler_dark_launch_combat`, `scheduler_dark_launch_defensive`, `scheduler_dark_launch_movement`, `scheduler_dark_launch_maintenance` |
| Maintenance | `cor_roll_1`, `cor_roll_2`, `cor_crooked_roll_slot`, `cor_elevens`, `cor_luzaf_range_override`, `cor_roll_range_selected`, `cor_roll_range_require_ids`, plus BRD/GEO fields accepted by profile contract classification even when they are not all present in defaults |
| Pathing and hunter | `path_recording`, `path_follow_enabled`, `path_file_name`, `path_route_type`, `path_distance_to_start`, `path_points`, `path_party_gate_yalms`, `path_resume_index_window`, `path_hunter_targets`, `path_hunter_max_z_delta`, `path_hunter_max_target_range`, `path_hunter_claim_timeout_s`, `path_hunter_ignore_cooldown_s`, `path_pull_action_type`, `path_pull_action_name` |
| Spells | `spell`, `spell_active`, `dd2_spell_slots` |

`PROFILE_KEYS` controls what is captured and saved into character profile files. Most default fields are persisted, but `def_heal_min_tier_cure`, `def_heal_max_tier_cure`, `def_heal_min_missing_hp`, `def_heal_ignore_trusts`, and some runtime/default-only fields are not currently included in `PROFILE_KEYS`.

`remote_bridge.lua` remains the live UI mutation path. Its generic `apply_set(path, value)` can create nested tables from dotted paths, but current callers mostly target flat keys. It also has special validation/coercion branches for follow ranges, spacing controls, path hunter settings, path pull action selectors, COR roll slot, `def_heal_min_missing_hp`, and `def_remove_enemy_buffs`.

`uc_profile_contract.lua` classifies fields into `profile_owned_by_ui`, `command_owned`, `status_output_owned_by_addon`, `runtime_owned_by_addon`, and `legacy_or_ambiguous`. `engine_enabled` is already classified as command-owned even though it is currently persisted.

## Persisted, editable, and ambiguous fields

| Class | Fields |
| --- | --- |
| Profile-persisted fields | The fields in `PROFILE_KEYS`, including combat toggles, defensive toggles, domain toggles, ownership toggles, COR/path/follow/target/tank/sleep/spell/debug fields |
| Bridge-editable fields | Any path accepted by `apply_set`, with special handling for follow, spacing, path, COR, and selected defensive fields |
| Debug/config fields | `debug`, `log_combat_sched`, `log_ja_sched`, `log_ja_debug`, `log_def_sched`, `log_tank_sched`, scheduler dark-launch toggles |
| Runtime-looking but currently persisted | `engine_enabled`, scheduler dark-launch toggles, some debug flags, profile-domain enable flags |
| Ambiguous legacy fields | `sub`, `sub2`, `solo`, `aeonic`, `color`, `command`, `hunter`, legacy sleep singleton `sleepspell`, old numbered ability/target slots |

Recommendation: the compatibility adapter should preserve all of these fields as source inputs, but the canonical `config` object should classify them into stable domains and mark command/status/runtime concerns separately.

## Local-variable pressure hotspots

| File / function | Static size | Why it is risky | Would config help? | Better long-term action |
| --- | ---: | --- | --- | --- |
| `unified_scheduler.lua` / `p1_try_dark_launch_combat_dispatch` | about 721 lines, 80 `local` tokens | Handles WS, JA, spell, tank enmity, sleep, action-state, and target dispatch in one function | Yes, especially `config.tank`, `config.sleep`, `config.debug`, and `config.combat` | Decompose after config exists; config alone is not enough |
| `remote_bridge.lua` / `process_line` | about 648 lines, 144 `local` tokens, many settings refs | Owns live UI commands, list edits, engine commands, and snapshot requests | Partly, but the main gain is moving path-specific validation into a pure schema/adapter | Decompose command handlers after bridge/file contract migration |
| `remote_bridge.lua` / `apply_set` | about 419 lines | Generic dotted-path mutation plus many numeric/boolean special cases | Yes, a config schema can centralize coercion rules later | Keep current bridge behavior until compatibility tests exist |
| `unified_scheduler.lua` / `p1_collect_maintenance` | about 247 lines | Mixes COR, BRD, GEO, throttle diagnostics, and top-proposal details | Yes, `config.maintenance` would reduce repeated settings interpretation | Split provider collectors by domain |
| `unified_scheduler.lua` / `p1_collect_combat_engage` | about 207 lines | Reads targeting, tank, fight-leader, debug, claim policy, and pull-owner state | Yes, `config.targeting`, `config.tank`, and `config.debug` help | Keep behavior stable; decompose only after config parity |
| `unified_scheduler.lua` / `build_defensive_candidates` | about 198 lines | Builds cures, debuffs, buffs, overwrite candidates from many defensive fields | Yes, `config.defensive` gives a narrower input surface | Provider split is likely worthwhile |
| `unified_scheduler.lua` / `try_internal_defensive_action` | about 182 lines | Duplicates defensive checks and dispatch preparation | Yes, but function decomposition is still needed | Eventually route through proposal path only |
| `UnifiedCombat.lua` / profile load/apply helpers | about 97 lines in `uc_load_profiles_for_character` plus profile key loops | Owns defaults, validation status, normalization, save/apply compatibility | A config normalizer should live beside this, not inside it | Keep load/save unchanged until normalizer is proven |

Subtable caching is enough for medium functions that repeatedly read one domain, for example `local tank_cfg = config.tank`. The largest scheduler and bridge functions should still be decomposed because they mix unrelated domains and side-effect preparation.

## Proposed canonical config shape

The first canonical shape should be built from the current flat table and should be read-only by convention.

```lua
config = {
  profile = {
    schema_version = 1,
    engine = "UC",
    character = nil,
    main_job = nil,
    sub_job = nil,
    source = "UC_SETTINGS",
  },
  ui = {
    show_ingame_ui = false,
  },
  command = {
    engine_enabled_default = false,
  },
  combat = {
    enabled = true,
    autotarget = false,
    spam = false,
    closer = false,
    manual = false,
    prime = false,
    static = false,
    face = false,
    weaponskill = {
      enabled = false,
      primary = "",
      mode = "smart",
      aftermath_enabled = false,
      aftermath_ws = "",
    },
  },
  abilities = {
    enabled = false,
    configured = {},
    legacy_slots = {},
    wsabilities = nil,
  },
  defensive = {
    enabled = false,
    provider = "internal",
    cure = { enabled = false, min_tier = 3, max_tier = 4, min_missing_hp = 250, ignore_trusts = true },
    doom = { holy_water_enabled = false },
    na = { enabled = false },
    enemy_buffs = { remove = false },
    buffs = { enabled = false, self_only = true, list = "", overwrite_enabled = false, overwrite_interval = 150 },
    thresholds = { critical_hpp = 35, medium_hpp = 55 },
  },
  movement = {
    enabled = true,
    move = false,
    spacing = {
      enabled = false,
      band_min = -0.9,
      band_max = 0.4,
      model_size_floor = 0.9,
      use_prediction = true,
      lookahead_s = 0.25,
      repel_hold_ticks = 5,
      overlap_deadband = 0.10,
      repel_weight = 0.35,
      band_deadband = 0.20,
    },
    path = {
      recording = false,
      follow_enabled = false,
      file_name = "",
      route_type = "unknown",
      distance_to_start = 0,
      points = {},
      party_gate_yalms = 3.0,
      resume_index_window = 12,
      hunter_targets = {},
      hunter_max_z_delta = 2.0,
      hunter_max_target_range = 20.0,
      hunter_claim_timeout_s = 4.0,
      hunter_ignore_cooldown_s = 20.0,
      pull_action_type = "ja",
      pull_action_name = "",
    },
  },
  follow = {
    enabled = true,
    party = { enabled = false, leader_id = 0, leader_name = "", min = 0.5, max = 50 },
    fight = { leader = false, leader_id = 0, min = 3.0, hold_s = 8.0 },
    partner = { enabled = false, secondary_enabled = false, ids = {}, puller = false, puller_id = 0, puller_distance_only = false },
  },
  targeting = {
    add_control = false,
    add_priority_names = {},
    targets = {},
    targetability = { enabled = false, action = "" },
    ignore = {},
    target_ignore_names = {},
  },
  tank = {
    enabled = false,
    enmity = { actions = {} },
  },
  sleep = {
    enabled = false,
    order = {},
    legacy_primary = "",
  },
  spells = {
    enabled = false,
    configured = "",
    dd2_slots = nil,
  },
  maintenance = {
    enabled = true,
    cor = { roll_1 = "", roll_2 = "", crooked_roll_slot = 0, elevens = false, luzaf_range_override = false, range_selected = "", range_require_ids = {} },
    brd = {},
    geo = {},
  },
  debug = {
    enabled = false,
    combat_sched = false,
    ja_sched = false,
    ja_debug = false,
    def_sched = false,
    tank_sched = false,
  },
  ownership = {
    scheduler_dark_launch_combat = false,
    scheduler_dark_launch_defensive = false,
    scheduler_dark_launch_movement = false,
    scheduler_dark_launch_maintenance = false,
  },
  legacy = {
    sub = false,
    sub2 = false,
    solo = false,
    aeonic = false,
    color = false,
    command = false,
    hunter = false,
  },
}
```

## Config vs runtime vs status vs command

Keep these out of canonical config:

- Scheduler action state, pending state, lock state, selected proposal, selected target, casting token state, cooldown ledgers, movement locks, zone suspend state, and live `Start_Engine`.
- Addon-owned status such as current profile key, current runtime action, validation errors, and scheduler summaries. These belong in status snapshots.
- One-shot commands such as start, stop, save, reload, addon reload, and future profile switch commands. These belong in command handling, not config.

Ambiguous current fields:

- `engine_enabled`: currently persisted and mirrored when engine commands run, but it is command-owned in the profile contract. Canonical config should expose only an `engine_enabled_default` or compatibility mirror until runtime command state is separated.
- `scheduler_dark_launch_*`: persisted debug/ownership toggles. Keep under `config.ownership` until the ownership promotion work removes or demotes them.
- `debug` and `log_*`: profile-editable diagnostics, not runtime state. Keep under `config.debug`.
- Legacy numbered slots such as `ability1` through `ability6` and `target1` through `target3`: keep in compatibility input, normalize into arrays, preserve old keys for save compatibility.

## Compatibility strategy

- Add a pure `uc_config_normalizer.lua` that accepts an existing flat settings/profile table and returns a canonical config table.
- Do not rename persisted keys, bridge paths, or profile file fields in the first implementation.
- Do not change `remote_bridge.lua` set/apply behavior; continue writing `_G.UC_SETTINGS`.
- Do not change `UnifiedCombat.lua` profile load/save behavior; build config from the already-loaded settings/profile object.
- Add tests that compare the canonical output shape against current defaults and representative profile settings.
- Expose a read-only config status/debug snapshot only after the normalizer is proven.
- Migrate runtime readers one domain at a time through `ctx.config`, with fixture coverage for each migrated domain.
- Version the profile file format only after the adapter has read compatibility for old flat profiles and new structured profiles.

## Lua 5.1 local-count guidance

- Pass one `config` table through scheduler context where it reduces repeated flat settings reads.
- Cache domain subtables inside hot functions, for example `local tank_cfg = config.tank` or `local def_cfg = config.defensive`.
- Cache scalar values only when they are repeatedly used or inside tight loops.
- Do not explode the whole config into dozens of locals.
- Avoid repeated deep lookups inside loops; cache the closest stable subtable.
- If a function still approaches local/register limits after subtable caching, split it by provider/action family instead of adding more locals.

## Implementation phases

1. Audit only. Complete in `T3.7d`.
2. Add pure `uc_config_normalizer.lua` with no `_G` mutation and no runtime caller migration.
3. Add focused tests for normalized default shape, representative profile shape, bridge-style nested input, and legacy slot normalization.
4. Build config from validated profile/settings during load or tick setup, but keep all runtime callers on `_G.UC_SETTINGS`.
5. Expose a read-only config debug/status snapshot.
6. Migrate one low-risk domain to consume `ctx.config`, preferably debug or sleep selection after parity tests are pinned.
7. Migrate additional domains one at a time.
8. Reduce direct `_G.UC_SETTINGS` reads in scheduler/provider paths once each domain has coverage.
9. Consider versioned profile migration only after compatibility reads are field-proven.

## Risks

- A too-large initial config migration could change scheduler behavior by accident because many fields have legacy defaults and loose boolean coercion.
- `apply_set` can create nested paths today, so the normalizer must tolerate unexpected nested user data without turning it into an implicit protocol migration.
- `engine_enabled` currently crosses profile, command, and runtime state boundaries.
- BRD/GEO maintenance fields are partially contract-recognized but not all visible in `uc_new_settings_defaults()`, so first tests should include representative maintenance profiles.
- A config object reduces local pressure only when callers keep it grouped; flattening it into locals would recreate the same Lua 5.1 problem.

## Recommended next implementation task

Create `uc_config_normalizer.lua`.

Requirements for the next task:

- Input: existing flat `_G.UC_SETTINGS` / profile table.
- Output: canonical config table matching this audit.
- No `_G` mutation.
- No runtime behavior changes.
- No caller migration.
- No profile save/load behavior changes.
- Tests only assert shape, default normalization, legacy slot handling, and representative field placement.
