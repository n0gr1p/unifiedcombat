# Side-Effect Inventory

Status: **Phase 0 guardrail maintained through Phase 1**
Verified: 2026-07-24 in the working tree based on
`3bd8d2355edb618d81bd2ef4a85f6dfa115d12a0`
Runtime behavior intent: unchanged; scheduler party-state IPC ownership moved to
an extracted module.

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
| `UnifiedCombat.lua` | `run`: 418 | Lifecycle stop | Movement dispatcher/facade |
| `unified_scheduler.lua` | `/ws`: 3799; `/ma`: 3942, 4560, 6680, 6788; `/ja`: 4561, 4646, 4647, 5831, 6352, 6432; `engage`: 5730; `switch_target`: 1508, 5392; `disengage`: 1518, 1936 | Intent construction and indirect attack execution | Dispatcher monopoly |
| `uc_scheduler_party_state.lua` | injected `send_ipc_message`: 91 | Scheduler party-state IPC encoding, throttling, send, receive, and lookup | Retain as the explicit party-state IPC owner |
| `unified_combat_core.lua` | `send_command`: 2020, 2041, 2207, 2218, 3245, 3259, 4009; `run`: 1626, 1635, 1640, 1993, 2012, 2095, 2121, 2130, 2181, 2286, 2409, 2428, 2442, 2448, 2482, 2520, 2540, 2545, 2579, 3502, 3518; `turn`: 2313, 2348; `select_by_id`: 2119, 2255; `send_ipc`: 352, 363; indirect attack wrappers: 2246, 2275, 3608, 3618, 3685, 3775; action command strings at the matching send sites | Legacy/core combat, pull, tank, movement, and scheduler-owned skillchain WS send | Dispatcher and movement facade; preserve only explicitly approved IPC ownership |
| `uc_attack.lua` | `packets.inject`: 54, 74, 101 | Engage, switch-target, and disengage packet executor | Dispatcher-owned attack adapter |
| `uc_settarget.lua` | `packets.inject`: 31 | Target selection packet executor | Dispatcher-owned target adapter |
| `uc_add_control.lua` | `send_command`: 433, 474, 476; `/attack`: 433 | Add-control retarget sequence | Dispatcher-owned target/attack sequence |
| `uc_party_follow.lua` | `run`: 916, 943, 953, 966, 971, 976; `send_ipc`: 563, 635, 643; `packets.inject`: 431 | Follow movement and zone replay | Movement facade; keep IPC/zone replay only by explicit ownership decision |
| `uc_pathing.lua` | `run`: 896, 906 | Path movement | Movement facade |
| `uc_nyzul_runtime.lua` | `run`: 51; `send_ipc`: 158, 168 | Nyzul movement hold and IPC | Movement facade; Nyzul-owned IPC if retained |
| `uc_lilith_easy_formation_runtime.lua` | `run`: 209 | Formation movement | Movement facade |
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

The verification scan currently discovers 125 non-test Lua files. Twenty
contain one or more tracked patterns. The other 105 files are still scanned and
must remain free of tracked side-effect surfaces unless the allowlist and this
inventory are deliberately updated.

## Ownership findings

1. `unified_scheduler.lua` has no literal `windower.send_command(...)`,
   `windower.ffxi.run(...)`, `windower.ffxi.turn(...)`, or
   `uc_settarget.select_by_id(...)` call. It still injects several of those
   function references into compatibility ownership helpers, invokes indirect
   packet executors, and constructs action commands.
2. Dispatcher monopoly is not complete. Core, movement modules, attack/target
   packet adapters, add control, and lifecycle code remain executors.
3. Movement authority remains distributed across core, follow, pathing, Nyzul,
   formation, and addon lifecycle code.
4. Scheduler-owned skillchain WS execution currently occurs through the direct
   core `send_command` site at `unified_combat_core.lua:4009`.
5. IPC is intentionally tracked but is not automatically assumed to belong to
   the combat dispatcher. Scheduler party-state IPC is owned by
   `uc_scheduler_party_state.lua`.

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
