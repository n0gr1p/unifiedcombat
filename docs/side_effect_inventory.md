# Side-Effect Inventory (T0.1)

Status: Draft  
Scope: Inventory only (no runtime changes)  
Date: 2026-05-15  
Branch note: Revalidated on clean scheduler-refactor branch per T0.1 redo request.

## Purpose

This document inventories direct side-effect call sites in the UnifiedCombat repository to support scheduler ownership refactor work.

Side effects tracked here:

- `windower.send_command(...)`
- `windower.ffxi.run(...)`
- `uc_settarget.select_by_id(...)`

## Active Runtime Path (Priority Inventory)

These files are in the active UnifiedCombat runtime path and are primary migration targets.

| File | Side-effect types observed | Notes |
| --- | --- | --- |
| `unified_scheduler.lua` | `send_command`, `ffxi.run`, `uc_settarget.select_by_id` | Scheduler currently both arbitrates and executes side effects in multiple paths (doom emergency, dark-launch dispatch, movement coordinator support, retarget). |
| `unified_combat_core.lua` | `send_command`, `ffxi.run`, `uc_settarget.select_by_id` | Core contains direct movement, direct spell/JA/WS dispatch helpers, and target set operations. |
| `unified_engine.lua` | none (direct) | Engine currently orchestrates tick/fallback; no direct side-effect calls found in this inventory scan. |
| `UnifiedCombat.lua` | `ffxi.run` | Entrypoint contains a direct movement stop call site (`run(false)`). |
| `uc_party_follow.lua` | `ffxi.run` | Follow path owns direct run/stop side effects. |
| `uc_pathing.lua` | `ffxi.run` | Pathing path owns direct run/stop side effects. |
| `uc_add_control.lua` | `send_command` | Add-control includes direct attack/target command emission. |
| `remote_bridge.lua` | `send_command` | Contains direct `lua reload unifiedcombat` command path. |

## Legacy / Secondary Paths (Out of Initial Scheduler Cutover Scope)

These files also contain direct side effects but are not first-line targets for the Phase 1 scheduler ownership work.

| File | Side-effect types observed | Notes |
| --- | --- | --- |
| `melee_engine.lua` | `send_command`, `ffxi.run` | Legacy engine path. |
| `dd2_engine.lua` | `send_command`, `ffxi.run` | Legacy engine path. |
| `dd2_module.lua` | `send_command`, `ffxi.run` | Legacy module path. |
| `lor/lor_actor.lua` | `send_command`, `ffxi.run` | Shared helper/library behavior with direct actor control calls. |
| `lor/lor_chat.lua` | `send_command` | Chat utility emits `echo` via command. |

## Observed Hotspot Summary

The highest concentration of active-path side effects is in:

1. `unified_scheduler.lua`
2. `unified_combat_core.lua`
3. movement-adjacent modules (`uc_party_follow.lua`, `uc_pathing.lua`)

This matches the scheduler RFC and amendment direction: scheduler ownership is partial, with direct execution still distributed across scheduler, core, and movement-related modules.

## Inventory Method

Static grep-style scan over `*.lua` for:

- `windower.send_command(`
- `windower.ffxi.run(`
- `uc_settarget.select_by_id(`

This is a call-site inventory, not a behavior/ownership adjudication. Some call sites may be gated, dead under current settings, or legacy-only.

Revalidation result for this branch: call-site categories and file grouping remained unchanged versus the prior draft.

## Known Limits

- This document does not classify every call site by runtime reachability.
- This document does not split by domain toggle state (`scheduler_dark_launch_*`, `domain_*_enabled`).
- This document does not yet define temporary allowlist vs forbidden paths (that belongs in a dedicated allowlist doc).

## Next Doc Dependencies

- `docs/side_effect_allowlist.md` (planned by later task)
- `docs/scheduler_responsibility_map.md` (planned by later task)
