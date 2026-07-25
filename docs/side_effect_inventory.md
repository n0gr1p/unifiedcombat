# Side-Effect Inventory

Status: **Phase 5 domain cutover complete**
Verified: 2026-07-24 by replay/static validation and multibox field acceptance;
live path-follow remains an explicitly accepted risk.
Runtime behavior intent: active UnifiedCombat domains are scheduler-owned when
enabled, with no engine core fallback. Legacy core side effects remain
inventoried as unreachable Phase 6 cleanup scope.

## Purpose

This is the current repository-wide inventory for command, movement, target,
packet, IPC, and action-command side-effect surfaces. It replaces the
2026-05-15 draft inventory.

The machine-enforced baseline is:

- `tests/replay/fixtures/shared/side_effect_allowlist.lua`
- `tests/replay/harness/selftest_side_effect_inventory.lua`

The guard discovers every non-test Lua file with `rg --files`; a new Lua file
containing a tracked pattern fails unless it is explicitly classified.

## Tracked patterns

Direct execution:

- `windower.send_command(...)`
- `windower.ffxi.run(...)`
- `windower.ffxi.turn(...)`
- `uc_settarget.select_by_id(...)`
- `windower.send_ipc_message(...)`
- injected `send_ipc_message(...)` execution through an explicit dependency
- `packets.inject(...)`

Command construction:

- `input /attack`
- `input /ma`
- `input /ja`
- `input /ws`

Indirect execution wrappers:

- `uc_attack.engage_target(...)`
- `uc_attack.switch_target(...)`
- `uc_attack.disengage(...)`
- `uc_add_control.execute_add_retarget(...)`

Command construction is inventoried separately from command execution. A file
that only constructs an intent is not thereby classified as a direct executor.

## Active UnifiedCombat runtime

| File | Current call sites | Domain / responsibility | Migration target |
| --- | --- | --- | --- |
| `unified_scheduler.lua` | `/ma`: 5277, 5375; `/ja`: 4471, 4984, 5054 | Dispatch-stage intent construction only; tracked action, target, turn, and movement execution is dispatcher-owned | Retain pure dispatch construction; no direct executor may return |
| `uc_provider_combat.lua` | `/ws`: 183; `/ma`: 326; `/ja`: 622, 623 | Proposal `legacy_command` construction only; no execution | Retain only while proposal compatibility requires the field |
| `uc_provider_tank_enmity.lua` | `/ma`: 125; `/ja`: 126 | Proposal `legacy_command` construction only; no execution | Retain only while proposal compatibility requires the field |
| `uc_scheduler_party_state.lua` | injected `send_ipc_message`: 91 | Scheduler party-state IPC encoding, throttling, send, receive, and lookup | Retain as the explicit party-state IPC owner |
| `unified_combat_core.lua` | `send_command`: 2020, 2041, 2340, 3336, 3350; `run`: 1626, 1635, 1640, 1993, 2012, 2328, 2331, 2348, 2351, 2354, 3593, 3609; `turn`: 2357, 2395; `select_by_id`: 2298, 2334; `send_ipc`: 352, 363; indirect attack wrappers remain; `/ws` construction: 4109 | Dormant legacy combat/tank/movement plus scheduler-facing decision helpers. Scheduler pull, skillchain WS, and movement require injected dispatcher-backed executors | Delete unreachable legacy execution in Phase 6; preserve scheduler helpers and explicitly approved IPC ownership |
| `uc_attack.lua` | `packets.inject`: 54, 74, 101 | Engage, switch-target, and disengage packet executor | Dispatcher-owned attack adapter |
| `uc_settarget.lua` | `packets.inject`: 31 | Target selection packet executor | Dispatcher-owned target adapter |
| `uc_add_control.lua` | `send_command`: 433, 474, 476; `/attack`: 433 | Add-control retarget sequence | Dispatcher-owned target/attack sequence |
| `uc_movement_dispatcher.lua` | Injected run/turn/mover execution through `uc_scheduler_dispatcher.lua` | Single active UnifiedCombat movement execution API | Retain as the movement adapter; domain owners must not bypass it |
| `UnifiedCombat.lua` | No tracked movement call | Lifecycle reset decision owner | Uses `uc_movement_dispatcher.lua`; retain lifecycle decision ownership |
| `uc_party_follow.lua` | `send_ipc`: 568, 640, 648; `packets.inject`: 436 | Follow movement decisions, position IPC, and zone replay | Movement uses `uc_movement_dispatcher.lua`; retain IPC/zone replay by the Phase 4 ownership decision |
| `uc_pathing.lua` | No tracked side-effect call | Path movement decisions | Movement uses `uc_movement_dispatcher.lua`; retain independent path decision ownership |
| `uc_nyzul_runtime.lua` | `send_ipc`: 163, 173 | Nyzul movement-hold decisions and IPC | Stop uses `uc_movement_dispatcher.lua`; retain Nyzul IPC ownership |
| `uc_lilith_easy_formation_runtime.lua` | No tracked side-effect call | Formation movement decisions | Movement uses `uc_movement_dispatcher.lua`; retain formation decision ownership |
| `uc_camp_anchor.lua` | `send_ipc`: 92, 108 | Camp-anchor synchronization | Camp-anchor IPC owner |
| `uc_scheduler_command_builder.lua` | `/ja`: 17; `/ma`: 19 | Pure command construction | Keep pure; execution remains outside this module |
| `remote_bridge.lua` | `send_command`: 1607 | Explicit addon reload operation | Bridge-owned exception unless separately migrated |

## Legacy and secondary runtime

These files are outside the initial active scheduler cutover but remain guarded.

| File | Current surface | Classification |
| --- | --- | --- |
| `melee_engine.lua` | 24 `send_command`, 3 `run`, 2 `turn`, 15 attack strings, 3 magic strings, 2 ability strings, 2 WS strings, 1 add-retarget wrapper | Legacy engine |
| `dd2_engine.lua` | 32 `send_command`, 10 `run`, 2 `turn`, 7 attack strings, 3 ability strings, 1 WS string, 1 add-retarget wrapper | Legacy engine |
| `dd2_module.lua` | 32 `send_command`, 10 `run`, 2 `turn`, 7 attack strings, 3 ability strings, 1 WS string, 1 add-retarget wrapper | Legacy module |
| `lor/lor_actor.lua` | `send_command`: 86; `run`: 194, 205 | Shared library executor |
| `lor/lor_chat.lua` | `send_command`: 131 | Shared chat/echo helper |
| `TargetBar/TargetBar.lua` | `Packets.inject`: 379 | Separate TargetBar packet behavior |

Detailed per-pattern counts for every row are pinned in the machine allowlist.

## Zero-match coverage

The verification scan currently discovers 135 non-test Lua files. Nineteen
contain one or more tracked patterns. The other 116 files are still scanned and
must remain free of tracked side-effect surfaces unless the allowlist and this
inventory are deliberately updated.

## Ownership findings

1. `unified_scheduler.lua` has no tracked direct call expression, including
   command, movement, turn, target, engage, switch, or disengage execution.
2. Active scheduler, formation, follow, pathing, Nyzul, and lifecycle movement
   reaches the injected Windower/mover adapter through
   `uc_movement_dispatcher.lua` and `uc_scheduler_dispatcher.lua`.
3. Follow and pathing remain independent movement decision owners, but their
   direct-run exceptions are removed. Pathing now also honors the movement
   domain; follow honors the follow domain.
4. `unified_engine.lua` has no call to `_G.UC_CoreCombatTickOnce`; the legacy
   core side effects are not reachable through the active engine.
5. Scheduler pull requires `uc_scheduler_pull_executor.lua`, so the core pull
   decision helper cannot select an implicit direct executor.
6. Scheduler-owned skillchain WS execution uses dispatcher commit validation
   and exactly-once post-send generation marking; core retains only command
   construction for that path.
5. IPC is intentionally tracked but is not automatically assumed to belong to
   the combat dispatcher. Scheduler party-state IPC is owned by
   `uc_scheduler_party_state.lua`.
6. Phase 3 providers do not execute commands, movement, targeting, attack, or
   packet operations. The combat and tank providers retain only the exact
   legacy command strings carried by their proposal records.
7. The direct-pattern inventory does not treat injected local function calls as
   direct `windower.ffxi.run(...)` expressions. The focused
   `selftest_movement_dispatcher_phase4.lua` contract pins the adapter wiring and
   prohibits direct run calls from migrated owners.

## Maintenance rule

Any change that adds, removes, or relocates a tracked pattern must update, in
the same task:

1. `tests/replay/fixtures/shared/side_effect_allowlist.lua`;
2. this inventory;
3. `docs/side_effect_allowlist.md` when ownership or removal conditions change.

Run:

```powershell
lua tests/replay/harness/selftest_side_effect_inventory.lua
```

The check fails on new unlisted files, missing allowlisted files, and per-pattern
count drift. It does not silently accept new side effects.
