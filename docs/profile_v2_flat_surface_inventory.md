# Profile V2 Flat Surface Inventory

Status: **Phase 0 baseline**  
Branch: `refactor/profile-v2-single-source`  
Captured: 2026-10-02

## Scope and method

This audit freezes the current flat configuration surface before migration. It distinguishes mechanical source markers from semantic ownership: a literal `UC_SETTINGS` occurrence may be a real read/write, a compatibility projection, or only metadata text. The executable guardrail is `tests/replay/harness/selftest_profile_v2_flat_surface_guard.lua`; its allowlist records exact current source counts and fails if a new flat surface appears or an existing count changes without an intentional migration update.

The scan covers non-test `.lua`, `.cs`, and `.py` source while excluding docs, RFCs, build output, and generated `%TEMP%` WinForms artifacts.

## Flat producers and writers

| Producer | What it produces today | Classification | Migration destination |
| --- | --- | --- | --- |
| `UnifiedCombat.lua::uc_new_settings_defaults()` | Large flat bootstrap/default table | compatibility bootstrap containing both durable defaults and runtime-ish fields | split durable defaults into canonical Profile V2/domain defaults; keep runtime state elsewhere |
| `uc_active_config.lua::apply_structured_config_to_candidate()` / `project_flat_settings()` | Canonical Profile V2 -> legacy flat compatibility mirror | compatibility-only projection | shrink as consumers migrate; eventually no durable behavior should depend on it |
| `uc_active_config.lua::sync_flat_settings_in_place()` | Publishes projected flat candidate into existing settings table | compatibility publication | retire for durable config after all consumers migrate |
| `remote_bridge.lua::apply_set()` | Mutates flat settings from bridge `set` operations | mixed: many durable edits plus some compatibility/runtime-adjacent controls | durable edits must become Profile V2 edits; runtime commands remain explicit commands |
| `MainForm.ProfileStore.cs::BuildProfileFromUi()` | Flat editor `JsonObject` | UI compatibility model | migrate editor model toward structured Profile V2 |
| `StructuredProfileV2Writer.cs` | Reads `JsonObject flatProfile` and emits nested V2 | flat-to-canonical adapter | keep during migration, then narrow/remove flat translation |
| `RuntimeProfileEditorAdapter.cs` | Canonical active config -> flat editor fields | canonical-to-flat editor adapter | keep during migration; retire/narrow when editor becomes structured |
| `MainForm.ParityLogic.cs` | 81 current `op=set` flat live-write call sites | parallel live mutation path | classify each; durable writes move to Profile V2, runtime commands stay commands |
| `ActivityProfiles.cs` | Captures flat editor state and feeds V2 writer | activity compatibility adapter | activity snapshots should ultimately operate on structured V2 data |
| `build_dd2_module.py` | Generates a module proxying reads/writes through `UC_SETTINGS` | legacy code-generation compatibility | migrate or retire with DD2 ownership decision |

## Direct `UC_SETTINGS` source baseline

Literal counts are mechanical guardrail counts, not a claim that every occurrence is a live durable read.

| Source | `UC_SETTINGS` occurrences |
| --- | ---: |
| `UnifiedCombat.lua` | 79 |
| `build_dd2_module.py` | 3 |
| `dd2_module.lua` | 9 |
| `melee_engine.lua` | 11 |
| `remote_bridge.lua` | 44 |
| `uc_active_config.lua` | 4 |
| `uc_combat_extension_config.lua` | 1 |
| `uc_config_normalizer_base.lua` | 1 |
| `uc_config_runtime.lua` | 2 |
| `uc_geo_camp_placement.lua` | 1 |
| `uc_party_follow.lua` | 5 |
| `uc_pathing.lua` | 2 |
| `uc_raise_accept.lua` | 1 |
| `uc_recovery_hold.lua` | 1 |
| `uc_runtime_overrides.lua` | 1 |
| `uc_scheduler_action_state.lua` | 1 |
| `uc_scheduler_config.lua` | 1 |
| `uc_scheduler_context_utils.lua` | 1 |
| `unified_combat_core.lua` | 1 |
| `unified_engine.lua` | 1 |

Semantic notes:

- High-value live/global seams are `UnifiedCombat.lua`, `remote_bridge.lua`, `uc_scheduler_context_utils.lua`, `unified_combat_core.lua`, `unified_engine.lua`, `uc_pathing.lua`, `uc_party_follow.lua`, `uc_raise_accept.lua`, `uc_recovery_hold.lua`, `uc_geo_camp_placement.lua`, and `uc_combat_extension_config.lua`.
- `uc_active_config.lua` is intentionally both canonical owner and flat projector during migration.
- `UnifiedCombat.lua` currently invokes `sync_flat_settings_in_place(...)` three times during bootstrap/apply compatibility publication; the CI guard surfaced these existing seams and the Phase 0 baseline now records them explicitly.
- `uc_config_runtime.lua` and `uc_config_normalizer_base.lua` include compatibility/source metadata markers as well as migration helpers; literal counts alone are not consumer counts.
- `melee_engine.lua`, `dd2_module.lua`, and `build_dd2_module.py` are legacy-sensitive and should not be removed until active ownership/callers are proven.

## Scheduler/provider indirect flat-context baseline

These files receive the flat compatibility table indirectly as `ctx.settings`. This list is important because a direct-global-only audit would miss most active scheduler consumers.

| Source | `ctx.settings` occurrences |
| --- | ---: |
| `uc_camp_puller.lua` | 4 |
| `uc_combat_commitment.lua` | 3 |
| `uc_combat_extensions_base.lua` | 1 |
| `uc_geo_maintenance.lua` | 3 |
| `uc_provider_charm_sleeper.lua` | 2 |
| `uc_provider_combat.lua` | 28 |
| `uc_provider_defensive.lua` | 8 |
| `uc_provider_enemy_buff_removal.lua` | 5 |
| `uc_provider_enemy_debuff_maintenance.lua` | 3 |
| `uc_provider_food.lua` | 2 |
| `uc_provider_maintenance.lua` | 1 |
| `uc_provider_recurring_spells.lua` | 4 |
| `uc_provider_run_tank.lua` | 3 |
| `uc_provider_sch_maintenance.lua` | 1 |
| `uc_provider_sleep_waker.lua` | 2 |
| `uc_provider_tank_enmity.lua` | 3 |
| `uc_provider_target_control.lua` | 6 |
| `uc_pup_pet_combat_adapter.lua` | 1 |
| `uc_pup_runtime.lua` | 1 |
| `uc_scheduler_dispatch_plan.lua` | 2 |
| `uc_scheduler_ranker.lua` | 3 |
| `uc_smn_maintenance.lua` | 2 |
| `uc_smn_pet_combat_adapter.lua` | 1 |
| `unified_scheduler.lua` | 12 |

The highest-risk indirect clusters are `uc_provider_combat.lua` and `unified_scheduler.lua`. The job-specific adapters (`uc_smn_maintenance.lua`, `uc_pup_runtime.lua`, `uc_provider_sch_maintenance.lua`, and pet-combat adapters) are separate Phase 4 targets.

## Canonical-first but still flat-dependent readers

Every `active_value_or_flat(...)` reader is still a migration target because flat state can change the result when canonical data is missing.

| Source | `active_value_or_flat(` occurrences |
| --- | ---: |
| `uc_cor_maintenance.lua` | 8 |
| `uc_hb_buff_maint.lua` | 5 |
| `uc_party_follow.lua` | 7 |
| `uc_pathing.lua` | 9 |
| `uc_provider_charm_sleeper.lua` | 2 |
| `uc_provider_defensive.lua` | 9 |
| `uc_provider_enemy_buff_removal.lua` | 5 |
| `uc_provider_enemy_debuff_maintenance.lua` | 3 |
| `uc_provider_food.lua` | 2 |
| `uc_provider_recurring_spells.lua` | 2 |
| `uc_provider_sleep_waker.lua` | 2 |
| `uc_scheduler_config.lua` | 6 |
| `unified_scheduler.lua` | 32 |

## Flat-to-canonical durable field map

The exact leaf projection is implemented by `uc_active_config.lua::apply_structured_config_to_candidate()` and the exact UI authoring translation is implemented by `StructuredProfileV2Writer.cs`. The table below is the complete migration map by durable field family; individual legacy aliases are listed where they matter.

| Flat/legacy field family | Canonical Profile V2 path | Classification / notes |
| --- | --- | --- |
| `show_ingame_ui` | `config.ui.show_ingame_ui` | durable UI preference |
| `autotarget`, `auto_engage`, `spam`, `closer`, `manual`, `prime`, `static`, `face` | `config.combat.*` | durable combat policy |
| `weaponskill_active`, `weaponskill`, `ws_mode`, `weaponskill_min_tp`, `weaponskill_allow_aoe`, `fast_skillchain`, `weaponskill_no_skillchain_targets`, `skillchain_target`, `wait_ignore_names`, `aftermath_*` | `config.combat.weaponskill.*` | durable; `ws1` is a compatibility alias of primary WS |
| `recurring_spells_enabled`, `recurring_spells` | `config.combat.recurring_spells.*` | durable |
| `camp_pulling*` | `config.combat.pulling.*` | durable pull policy; live camp anchor itself is runtime state |
| `ability_active`, `ability_allow_unengaged`, `abilities`, `wsabilities` | `config.abilities.*` | durable |
| `ability1`..`ability6` | `config.abilities.legacy_slots` | compatibility aliases; migration should eliminate numbered consumers |
| `defensive_*`, `def_*` healing/status/buff/debuff controls | `config.defensive.*` | durable defensive policy |
| `encounter_*`, `kei_*` | `config.encounter.*` | durable encounter policy/tuning |
| `move`, `spacing*` | `config.movement.move`, `config.movement.spacing.*` | durable movement policy |
| `formation_*`, `named_formation_*` | `config.movement.formation.*`, `config.movement.named_formations.*` | durable formation policy |
| `path_recording`, `path_follow_enabled`, `path_file_name`, `path_route_type`, `path_distance_to_start`, `path_points`, `path_party_gate_yalms`, `path_resume_index_window`, `path_hunter_*`, `path_pull_*` | `config.movement.path.*` | durable route/policy fields; current route cursor/progress is runtime state |
| `party_follow*` names/distances | `config.follow.party.*` | durable names/policy; resolved IDs are runtime-derived |
| `fight_leader*` names/distances | `config.follow.fight.*` | durable name/policy; resolved leader ID is runtime-derived |
| `partner*`, `puller*` names/policy | `config.follow.partner.*` | durable names/policy; resolved IDs are runtime-derived |
| `nyzul_*` roster fields | `config.follow.nyzul.*` | durable roster; active run token/queue state is runtime |
| `add_control`, `add_priority_names`/`targets`, `target_ignore_names`, targetability fields | `config.targeting.*` | durable targeting policy |
| `reaction_enabled`, `reaction_rules` | `config.reactions.*` | durable rules; active reaction windows are runtime |
| `tank`, `tank_enmity_actions`, `tank_enmity_include_pets` | `config.tank.*` | durable tank policy |
| `run_tank_*` | `config.tank.run.*` | durable RUN policy |
| `sleep`, `sleepspells`, `sleep_max_target_range` | `config.sleep.*` | durable; `sleepspell` is a compatibility singleton alias |
| `spell_active`, `spell`, `magic_burst_*`, `dd2_spell_slots` | `config.spells.*` | durable spell policy |
| `cor_*` | `config.maintenance.cor.*` | durable COR maintenance |
| `brd_*`, `maintenance_brd` | `config.maintenance.brd.*` | durable BRD maintenance; `maintenance_brd` is a compatibility mirror |
| `maintenance_geo`, `geo_*` | `config.maintenance.geo.*` | durable GEO maintenance; live luopan/camp observations are runtime |
| `food_enabled`, `food_item` | `config.maintenance.food.*` | durable food maintenance |
| `summoner_*` | `config.summoner.*` | durable SMN policy; live avatar/pet state is runtime |
| `puppetmaster_*`, grouped `puppetmaster` | `config.puppetmaster.*` | durable PUP policy; burden/pet observations are runtime |
| `sch_*`, grouped `sch` | `config.sch.*` | durable SCH policy/state machine configuration |
| `debug`, `log_action_timeline`, `log_*_sched`, `log_ja_debug` | `config.debug.*` | durable diagnostics preferences |
| `domain_*_enabled` | `config.ownership.domain_*_enabled` and mirrored domain `.enabled` fields | durable ownership; duplication is itself cleanup debt and ownership should become single-valued |
| `auto_accept_raise`, `pause_automation_while_weakened` | `config.ownership.*` | durable ownership/policy |
| `sub`, `sub2`, `solo`, `aeonic`, `color`, `command`, `hunter`, `profiles` | `config.legacy.*` | compatibility-only/legacy durable surface pending retirement decisions |

## Runtime/transient state that must not migrate into Profile V2

- `_G.Start_Engine` / current engine running state;
- current target IDs, selected proposal, claim state, action locks, pending actions, cooldown ledgers, and cast/action lifecycle state;
- resolved `partner_id`, `puller_id`, `fight_leader_id`, `party_follow_id`, and similar live IDs;
- live camp anchor coordinates, camp journey state, current route cursor/index, and movement ownership;
- BRD observed song recipients/timers, COR roll observations, GEO luopan observations, pet identity/status, PUP burden, and SCH observed runtime state;
- bridge connection/session state and option lists derived from live job/resources;
- diagnostics/status snapshots that report state rather than configure behavior.

## Compatibility-only mirrors and aliases

- `ws1` mirrors the canonical primary weaponskill.
- `ability1`..`ability6` mirror legacy ability slots.
- `sleepspell` mirrors the first entry of canonical sleep order.
- `maintenance_brd`, `maintenance_geo`, grouped `puppetmaster`, grouped `sch`, and nested `follow` values exist as compatibility views for current consumers/UI.
- resolved ID mirrors are derived from durable names and must never become durable authority.
- flat list mirrors such as `add_priority_names`, `wait_ignore_names`, and serialized pipe strings exist because legacy consumers and WinForms still expect them.

## Explicit ambiguous/unmapped decisions

These are not missing from the audit; they are intentionally deferred ownership decisions:

| Surface | Current ambiguity | Required decision |
| --- | --- | --- |
| `engine_enabled` / `config.command.engine_enabled_default` | historical persisted/default value vs current runtime engine command state | keep current run state non-durable; decide whether a durable default is still useful or remove the command config domain |
| `engine_mode` | session/engine identity rather than ordinary profile option | keep as identity/session metadata, not a generic durable config leaf |
| `profiles` under `config.legacy` | historical profile tree compatibility | prove no active consumer before removal |
| legacy `sub`, `sub2`, `solo`, `aeonic`, `color`, `command`, `hunter` | historical behavior switches with unclear modern ownership | classify individually during consumer migration before deleting |
| DD2/melee legacy module settings proxy | may be inactive/legacy but still generated and public | prove runtime ownership/callers before retirement |
| WinForms option-list fields (`*_options`) | editor capability metadata, not behavior configuration | keep transient/editor-only; do not serialize as canonical behavior config |

## Known mixed-shape defect captured in Phase 0

`uc_config_normalizer_base.lua::normalize_maintenance()` currently chooses the entire maintenance representation based on whether any recognized nested maintenance child exists. Therefore an input containing nested `maintenance.food` plus legacy flat BRD fields enters the nested branch and silently defaults BRD to disabled/empty.

Phase 0 intentionally does **not** change runtime behavior. `tests/replay/fixtures/maintenance/mixed_profile_v2_food_flat_brd.lua` and `selftest_profile_v2_mixed_shape_characterization.lua` record the current defect plus a fully nested control case. When the migration fixes the normalizer boundary, that characterization must be inverted into a positive sibling-isolation regression.

## Phase 1 canonical scheduler read boundary

Phase 1 adds an explicit canonical configuration view to every scheduler tick context without changing any existing consumer semantics:

- `uc_scheduler_context_utils.get_config()` is the scheduler-side canonical accessor and delegates to `uc_active_config.get_config()`.
- `uc_scheduler_context.build(...)` receives that accessor as an injected dependency, samples it once per context build, and publishes the result as `ctx.config`.
- `ctx.settings` remains unchanged for every existing unmigrated consumer.
- No provider or scheduler decision reader is migrated in Phase 1; therefore the Phase 0 flat-surface allowlist does not shrink yet.
- Deterministic context tests prove canonical config identity, one-sample-per-context behavior, empty fallback when no active Profile V2 exists, and explicit scheduler wiring.

This establishes the seam for Phase 2: leaf providers can migrate from `ctx.settings` / `active_value_or_flat` to `ctx.config` one family at a time without adding new global config reads.

## Phase 2 flat-surface burn-down

The Phase 0 tables above remain a frozen historical baseline. Phase 2 removes the following allowlist entries entirely because these files no longer contain any guarded flat durable-config surface:

- `uc_provider_food.lua`
- `uc_provider_recurring_spells.lua`
- `uc_provider_defensive.lua`
- `uc_provider_enemy_buff_removal.lua`
- `uc_provider_enemy_debuff_maintenance.lua`
- `uc_provider_maintenance.lua` (the COR subordinate call now receives `ctx.config`)
- `uc_hb_buff_maint.lua`
- `uc_cor_maintenance.lua`
- `uc_geo_camp_placement.lua`
- `uc_raise_accept.lua`
- `uc_recovery_hold.lua`

That is a reduction of **11 allowlisted source files and 60 guarded literal hits** from the Phase 0 debt surface. Compatibility conversion remains centralized at the Profile V2/flat publication boundary; these leaf consumers no longer implement their own flat fallback.

`uc_scheduler_action_state.lua` still has one debug-only `UC_SETTINGS` read. It is intentionally retained for Phase 3 because that reader is embedded in core action-state/diagnostic behavior rather than a low-risk leaf provider.

## Phase 3 combat enablement/autotarget burn-down

The first Phase 3 slice removes four additional indirect flat-context reads from scheduler-owned combat gating:

- `uc_provider_target_control.lua`: `ctx.settings` count reduced from 6 to 4 by moving both autotarget gates to `ctx.config`.
- `uc_provider_combat.lua`: `ctx.settings` count reduced from 28 to 26 by moving autotarget and auto-engage gates to `ctx.config`.
- Core target selection, tank-enmity selection, death-switch revalidation, partner arbitration, and pre-engage combat-close movement now receive canonical tick config for autotarget/auto-engage decisions.
- Legacy compatibility helpers remain available for unmigrated callers, so this slice narrows the authoritative runtime surface without forcing unrelated Phase 3 domains to migrate early.

## Phase 0 conclusion

The flat surface is now mechanically frozen. Migration work can shrink the allowlist, but adding a new `UC_SETTINGS`, `ctx.settings`, `active_value_or_flat`, flat WinForms live-set, or flat-profile translation seam requires an explicit guardrail update and review. This converts the debt from an open-ended compatibility surface into a measurable burn-down list.
