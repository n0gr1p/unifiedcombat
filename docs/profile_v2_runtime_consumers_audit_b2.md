# B2 - Profile v2 runtime consumer audit

This audit checks the live addon consumers against the UI-owned v2 profile source of truth after profilev2 autoload/reload was fixed.

Core rule used here:

- UI-authored v2 config is durable source of truth.
- `_G.UC_ACTIVE_PROFILE` is the addon active durable config.
- `_G.UC_SETTINGS` is compatibility projection only.
- Runtime/session state remains addon-owned.

## Audit summary

No proven reader mismatch was found that required a runtime code change in this pass.

The remaining flat-key reads fall into three buckets:

- intentional compatibility mirrors
- explicit runtime/legacy overrides
- fields that are not yet modeled as durable v2 profile config

## Consumer table

| Domain | UI v2 path | Active-config reader path | Remaining flat compatibility readers | Status |
| --- | --- | --- | --- | --- |
| COR maintenance | `config.maintenance.cor.roll_1`, `roll_2`, `crooked_roll_slot`, `elevens`, `luzaf_range_override`, `range_selected`, `range_require_ids` | `uc_cor_maintenance.lua` reads these through `uc_active_config.get_path(...)` via its local `active_value_or_flat(...)` helper | `cor_roll_1`, `cor_roll_2`, `cor_crooked_roll_slot`, `cor_elevens`, `cor_luzaf_range_override`, `cor_roll_range_selected`, `cor_roll_range_require_ids` | `migrated_active_config_reader` |
| BRD / defensive buff maintenance | `config.defensive.buffs.list`, `self_only`, `overwrite_enabled`, `overwrite_interval` | `uc_hb_buff_maint.lua` reads the active paths first through `active_value_or_flat(...)` | `defensive_targeted_buffs` remains a flat compatibility reader because no structured v2 path exists for targeted entries yet | `migrated_active_config_reader` for general buffs, `acceptable_compat_reader` for targeted buffs |
| GEO maintenance | `config.maintenance.geo` | `uc_active_config.lua` projects this durable domain into the active profile and flat compatibility mirror; the scheduler’s GEO proposal is job/buff driven and does not currently need a separate GEO config reader | `maintenance_geo` | `acceptable_compat_reader` |
| Defensive thresholds / buffs | `config.defensive.enabled`, `provider`, `thresholds.critical_hpp`, `thresholds.medium_hpp`, `buffs.enabled`, `buffs.self_only`, `buffs.list`, `buffs.overwrite_enabled`, `buffs.overwrite_interval`, `enemy_buffs.remove`, `cure.*`, `na.enabled`, `doom.holy_water_enabled` | `unified_scheduler.lua`, `uc_scheduler_config.lua`, and `uc_hb_buff_maint.lua` read active config first through `scheduler.active_value_or_flat(...)` / `uc_active_config.get_path(...)` | `defensive_targeted_buffs` only; general defensive buff fields are already active-first | `migrated_active_config_reader` |
| Combat toggles | `config.combat.autotarget`, `combat.prime`, `ownership.scheduler_dark_launch_combat`, `ownership.scheduler_dark_launch_defensive`, `ownership.scheduler_dark_launch_movement`, `ownership.scheduler_dark_launch_maintenance`, `config.defensive.provider` | `uc_scheduler_config.lua` and `unified_scheduler.lua` read active config first | Compatibility fallbacks remain on the flat mirror when the active path is missing | `migrated_active_config_reader` |
| Follow / movement durable settings | `config.movement.path.*`, `config.follow.party.*`, `config.follow.fight.*`, `config.follow.partner.*`, `config.ownership.domain_follow_enabled` | `uc_active_config.lua`, `uc_party_follow.lua`, `uc_pathing.lua`, and scheduler helpers read the active paths first where the settings are durable | `fight_leader`, `fight_leader_id`, `add_priority_names`, `sleep`, `sleepspells`, `sleepspell` are still explicit runtime/legacy override readers through `uc_runtime_overrides.lua`; `path_file_name` is a runtime/session mirror | `migrated_active_config_reader` plus `acceptable_compat_reader` for runtime overrides |
| Targeting / tank durable settings | `config.targeting.add_priority_names`, `config.targeting.targets`, `config.targeting.ignore`, `config.targeting.target_ignore_names`, `config.tank.enabled`, `config.tank.enmity.actions` | `uc_scheduler_config.lua`, `uc_runtime_overrides.lua`, and `uc_active_config.lua` read the active paths first | `add_priority_names` remains a runtime/legacy override reader; legacy slot mirrors such as `target1`/`target2`/`target3` remain compatibility-only | `migrated_active_config_reader` plus `acceptable_compat_reader` |

## Notes by domain

### COR

The COR maintenance path is already on the active-profile reader path. The addon uses the v2 maintenance values when they exist and only falls back to the flat compatibility keys when the active path is absent.

### BRD

The general buff list is active-first. Targeted buff entries are still read from the flat compatibility string because the v2 schema does not yet provide a structured targeted-buff path.

### GEO

The v2 maintenance GEO list is preserved in `_G.UC_ACTIVE_PROFILE` and projected into `_G.UC_SETTINGS` for compatibility. The live GEO maintenance proposal is driven by job/buff state, so there is no separate durable GEO selection reader to migrate in this pass.

### Defensive thresholds / buffs

The defensive maintenance consumers already prefer active config for thresholds, buff lists, overwrite settings, and cure/NA/doom toggles. The only remaining flat reader in the BRD/defensive buffer area is the targeted buff string noted above.

### Follow / movement / targeting / tank

These domains are already mostly on active config. The remaining flat reads are either runtime override readers or compatibility mirrors for legacy slot layouts.

## Conclusion

For this pass, the audit did not find a new durable reader mismatch that required changing runtime code.

The main remaining follow-up items are explicit compatibility seams, not source-of-truth regressions:

- `defensive_targeted_buffs`
- `path_file_name`
- `fight_leader` / `fight_leader_id`
- `add_priority_names`
- `sleep` / `sleepspells` / `sleepspell`

