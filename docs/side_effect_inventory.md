# Side-Effect Inventory

Status: **Phase 3 provider-purity baseline**
Verified: 2026-07-24 in the Phase 3 working tree.
Runtime behavior intent: scheduler-owned execution is dispatcher-only; legacy
and independent subsystems remain explicitly inventoried.

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
| `unified_scheduler.lua` | `/ma`: 5187, 5285; `/ja`: 4388, 4894, 4964 | Dispatch-stage intent construction only; tracked action, target, turn, and movement execution is dispatcher-owned | Retain pure dispatch construction; no direct executor may return |
| `uc_provider_combat.lua` | `/ws`: 183; `/ma`: 326; `/ja`: 622, 623 | Proposal `legacy_command` construction only; no execution | Retain only while proposal compatibility requires the field |
| `uc_provider_tank_enmity.lua` | `/ma`: 125; `/ja`: 126 | Proposal `legacy_command` construction only; no execution | Retain only while proposal compatibility requires the field |
| `uc_scheduler_party_state.lua` | injected `send_ipc_message`: 91 | Scheduler party-state IPC encoding, throttling, send, receive, and lookup | Retain as the explicit party-state IPC owner |
| `unified_combat_core.lua` | `send_command`: 2020, 2041, 2207, 2218, 3266, 3280; `run`: 1626, 1635, 1640, 1993, 2012, 2095, 2121, 2130, 2181, 2287, 2290, 2293, 3523, 3539; `turn`: 2296, 2334; `select_by_id`: 2119, 2255; `send_ipc`: 352, 363; indirect attack wrappers: 2246, 2275, 3629, 3639, 3706, 3796; `/ws` construction: 4039 | Legacy/core combat, pull, tank, and movement; scheduler-owned skillchain WS and movement use injected dispatcher facades | Phase 5 legacy domain cutover; preserve only explicitly approved IPC ownership |
| `uc_attack.lua` | `packets.inject`: 54, 74, 101 | Engage, switch-target, and disengage packet executor | Dispatcher-owned attack adapter |
| `uc_settarget.lua` | `packets.inject`: 31 | Target selection packet executor | Dispatcher-owned target adapter |
| `uc_add_control.lua` | `send_command`: 433, 474, 476; `/attack`: 433 | Add-control retarget sequence | Dispatcher-owned target/attack sequence |
| `uc_party_follow.lua` | `run`: 916, 943, 953, 966, 971, 976; `send_ipc`: 563, 635, 643; `packets.inject`: 431 | Follow movement and zone replay | Movement facade; keep IPC/zone replay only by explicit ownership decision |
| `uc_pathing.lua` | `run`: 896, 906 | Path movement | Movement facade |
| `uc_nyzul_runtime.lua` | `run`: 51; `send_ipc`: 158, 168 | Nyzul movement hold and IPC | Movement facade; Nyzul-owned IPC if retained |
| `uc_lilith_easy_formation_runtime.lua` | injected `run`: 209 | Dispatcher-owned formation movement adapter | Retain or consolidate during Phase 4 |
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

The verification scan currently discovers 132 non-test Lua files. Twenty-two
contain one or more tracked patterns. The other 110 files are still scanned and
must remain free of tracked side-effect surfaces unless the allowlist and this
inventory are deliberately updated.

## Ownership findings

1. `unified_scheduler.lua` has no tracked direct call expression, including
   command, movement, turn, target, engage, switch, or disengage execution.
2. Scheduler-owned execution reaches concrete Windower/packet adapters only
   through `uc_scheduler_dispatcher.lua` and the dispatcher movement facade.
3. Legacy core execution and independent follow, pathing, Nyzul, and lifecycle
   movement remain outside Phase 2 and stay explicitly allowlisted. Formation
   movement already uses dispatcher intents.
4. Scheduler-owned skillchain WS execution uses dispatcher commit validation
   and exactly-once post-send generation marking; core retains only command
   construction for that path.
5. IPC is intentionally tracked but is not automatically assumed to belong to
   the combat dispatcher. Scheduler party-state IPC is owned by
   `uc_scheduler_party_state.lua`.
6. Phase 3 providers do not execute commands, movement, targeting, attack, or
   packet operations. The combat and tank providers retain only the exact
   legacy command strings carried by their proposal records.

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
