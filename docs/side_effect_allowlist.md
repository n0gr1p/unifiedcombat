# Side-Effect Allowlist (Scheduler Ownership Migration Guardrail)

Status: Draft (documentation-only)
Scope: Guardrail for scheduler ownership refactor tasks
Date: 2026-05-15
Related:
- `docs/side_effect_inventory.md`
- `docs/scheduler_responsibility_map.md`
- `docs/unified_scheduler_rfc.md`
- `docs/unified_scheduler_phase1_amendment.md`
- `docs/scheduler_work_tracking.md`

## 1. Purpose

This allowlist is a migration guardrail for the UnifiedCombat scheduler ownership refactor.

It exists to prevent accidental expansion of side-effect execution while code is being mechanically extracted. During migration, this file is the source of truth for where direct runtime side effects are currently allowed and what module should own them in the target architecture.

## 2. Side effects covered

This allowlist covers direct runtime side-effect APIs:

- `windower.send_command(...)`
- `windower.ffxi.run(...)`
- `windower.ffxi.turn(...)`
- `uc_settarget.select_by_id(...)`
- Windower IPC send/broadcast calls present in current code:
  - `windower.send_ipc_message(...)`

## 3. Current allowed active-runtime side-effect locations

Conservative rule: listed locations are allowed for current behavior parity during migration, but no new locations may be introduced outside this allowlist.

| File path | Side-effect API used | Current reason it is allowed | Temporary or expected to remain | Target future owner |
| --- | --- | --- | --- | --- |
| `unified_scheduler.lua` | `windower.send_command`, `windower.ffxi.run`, `windower.ffxi.turn`, `uc_settarget.select_by_id`, `windower.send_ipc_message` | Current scheduler tick path still executes dark-launch dispatch (`p1_try_dark_launch_dispatch`), movement coordinator tick (`run_movement_coordinator_tick`), doom emergency action (`try_doom_water_emergency`), and party-state IPC broadcast (`maybe_broadcast_party_state_ipc`). | Mostly temporary for command/target/movement execution; IPC ownership is mixed/uncertain during Phase 1. | `uc_scheduler_dispatcher.lua` for command/target/action execution; movement via dispatcher or dispatcher-owned movement facade; IPC ownership uncertain (likely scheduler context path). |
| `unified_combat_core.lua` | `windower.send_command`, `windower.ffxi.run`, `windower.ffxi.turn`, `uc_settarget.select_by_id`, `windower.send_ipc_message` | Core still contains legacy and partial dark-launch-adjacent direct execution paths, plus WS intent/hold IPC emission. Work tracking notes scheduler ownership is partial while legacy paths remain operational. | Temporary for direct command/target/movement execution; IPC use is expected to remain but final owner boundary is uncertain. | `uc_scheduler_dispatcher.lua` for runtime execution; IPC ownership uncertain between core and scheduler context modules. |
| `UnifiedCombat.lua` | `windower.ffxi.run` | Entrypoint has direct stop-movement call site (`run(false)`) used in lifecycle control. | Temporary. | Dispatcher-owned movement facade (or dispatcher direct movement path) after extraction. |
| `uc_party_follow.lua` | `windower.ffxi.run`, `windower.send_ipc_message` | Follow module currently owns follow run/stop behavior and follow/zone IPC messages (`ucpf_up`, `zone ...`) for multibox behavior. | Temporary for direct movement; IPC location may remain module-local or be routed, uncertain. | Movement side effects should be routed through dispatcher-owned movement facade; IPC ownership uncertain. |
| `uc_pathing.lua` | `windower.ffxi.run` | Pathing helper currently issues direct movement vectors and stop. | Temporary. | Dispatcher-owned movement facade (or dispatcher direct movement path). |
| `uc_add_control.lua` | `windower.send_command` | Add-control retarget flow intentionally does `/attack off` -> wait idle -> `st` -> attack command sequence. | Temporary in scheduler refactor context; behavior-sensitive path. | `uc_scheduler_dispatcher.lua` should eventually own target/attack command execution when under scheduler authority. |
| `remote_bridge.lua` | `windower.send_command` | UI-triggered explicit reload path (`lua reload unifiedcombat`). | Expected to remain for bridge UI control; not a scheduler provider dispatch path. | `remote_bridge.lua` (remain) unless explicit RFC/task later rehomes bridge operations. |

## 4. Legacy / out-of-initial-scope side-effect locations

These known paths contain side effects but are out of initial scheduler ownership extraction scope:

- `melee_engine.lua`
- `dd2_engine.lua`
- `dd2_module.lua`
- `lor/lor_actor.lua`
- `lor/lor_chat.lua`

Rule for migration tasks: do not modify these files or move side-effect logic in these files unless an explicit task asks for it.

## 5. Target future side-effect ownership model

Target rule (explicit):

Providers may propose.  
Scheduler may select.  
Only dispatcher may execute side effects.

Target owner details:

- `uc_scheduler_dispatcher.lua` should own command dispatch, target selection, and action execution.
- Movement side effects should eventually be routed through dispatcher or a dispatcher-owned movement facade.
- Provider modules must not directly call:
  - `windower.send_command`
  - `windower.ffxi.run`
  - `windower.ffxi.turn`
  - `uc_settarget.select_by_id`

## 6. Temporary exceptions

These exceptions are allowed during migration and must be removed/rerouted by targeted follow-up tasks.

| Exception | Why it exists today | Future task to remove or route it | Risk level |
| --- | --- | --- | --- |
| Dark-launch dispatch side effects in `unified_scheduler.lua` | Scheduler currently executes selected proposals in `p1_try_dark_launch_dispatch` to support incremental cutover while legacy paths still exist. | Mechanical extraction that moves dispatch-plan execution + action send + target prep into `uc_scheduler_dispatcher.lua` without changing semantics. | High |
| Movement calls in `uc_party_follow.lua` and `uc_pathing.lua` | Movement is still directly controlled in follow/pathing modules; scheduler movement ownership is partial and not yet fully centralized. | Introduce dispatcher-owned movement facade and route module calls through it without changing movement timing/threshold semantics. | High |
| Core fallback direct dispatch in `unified_combat_core.lua` | Work tracking and code comments indicate legacy/core paths remain active while scheduler dark-launch is opt-in/partial. | Mechanical extraction of core direct send/target/movement execution behind dispatcher entrypoints, preserving command strings and gate conditions. | High |
| Reload command path in `remote_bridge.lua` | Explicit UI operation for full addon reload; intentionally separate from scheduler dispatch pipeline. | Optional follow-up only if RFC explicitly re-scopes bridge command ownership; otherwise remain as bridge-owned operation. | Low |

## 7. Rules for future Codex tasks

- Do not add new direct side-effect calls outside this allowlist.
- Do not move side-effect calls into provider modules.
- Do not create a new dispatcher-like module unless the RFC explicitly asks for it.
- Do not replace `send_command` strings with inferred equivalents unless explicitly instructed.
- Do not alter command strings while moving code.
- Do not change timing, lock, duplicate, pending, or movement semantics during mechanical extraction.
- Any new side-effect call site must be documented in this allowlist in the same commit.

## 8. Suggested static grep checks

Run from repo root:

```powershell
Select-String -Path *.lua, .\lor\*.lua -Pattern 'windower\.send_command' -CaseSensitive:$false
Select-String -Path *.lua, .\lor\*.lua -Pattern 'windower\.ffxi\.run' -CaseSensitive:$false
Select-String -Path *.lua, .\lor\*.lua -Pattern 'windower\.ffxi\.turn' -CaseSensitive:$false
Select-String -Path *.lua, .\lor\*.lua -Pattern 'uc_settarget\.select_by_id' -CaseSensitive:$false
Select-String -Path *.lua, .\lor\*.lua -Pattern 'windower\.send_ipc_message' -CaseSensitive:$false
```

## 9. Recommended next task

Recommended smallest runtime-safe next step:

- Create `uc_scheduler_locks.lua` and copy lock/duplicate/pending-lock helper logic only (mechanical extraction), with `unified_scheduler.lua` calling through unchanged interfaces.

Why this is the next smallest safe slice:

- `docs/scheduler_responsibility_map.md` already identifies lock semantics as a discrete boundary.
- This can be done without moving dispatch strings, movement execution, or provider behavior.
- It reduces extraction risk before any side-effect execution relocation.

