# UnifiedCombat

UnifiedCombat is a Windower addon + WinForms desktop UI for multibox combat automation in FFXI.

Current runtime is centered on a single UC combat path (`unified_engine` + `unified_combat_core`) with direct WinForms-to-addon connectivity (no Python middleware required for normal operation).

## Table of Contents

1. Overview
2. Architecture
3. Core Functionality
4. Runtime Flow
5. Configuration and Profiles
6. Installation
7. Running the UI
8. Build and Release
9. Commands
10. Dependencies
11. Repository Layout
12. Troubleshooting
13. Additional Docs

## Overview

UnifiedCombat provides:

- Single UC engine execution path for combat tick logic.
- Party-claim-aware targeting with fight leader and add-control support.
- Spacing + close-range movement with puller gating support.
- Smart WS selection and skillchain-aware WS behavior.
  - Aftermath hold logic is weapon-table driven via `docs/aftermath_table.lua` and validates `aftermath_ws` against mapped ultimate-weapon WS entries.
  - In scheduler combat ownership mode, `AM_READY` aftermath WS intents are prioritized above defensive buffs/non-critical cures, while critical cures and doom emergency still preempt.
- Ordered JA execution pipeline.
- Party-follow with zone replay behavior.
- Ordered Nyzul lamp parking with a persistent exit anchor and one-command regroup.
- Defensive scheduler integration path.
  - Majesty is treated as a high-priority defensive buff and is cast before non-critical cures.
  - Defensive spell casts are deferred while pre-engage combat approach movement is active.
  - In scheduler combat ownership mode, target selection dispatch is lane-separated from action-block gates and is prioritized above engage dispatch.
- Real-time multi-session WinForms control and state sync.

## Architecture

### High-level Components

- `UnifiedCombat.lua`
  - Addon entrypoint, event registration, profile load/save, command parsing.
- `unified_engine.lua`
  - UC engine loop (`tick_interval = 0.25`), scheduler + core combat orchestration.
- `unified_scheduler.lua`
  - Scheduler layer (defensive arbitration / blocking decisions before combat tick).
- `unified_combat_core.lua`
  - Primary combat logic: target selection, engage/switch, movement, abilities, WS.
- `uc_party_follow.lua`
  - Party-follow movement in prerender loop + IPC position/zone replay.
- `uc_nyzul_runtime.lua`
  - Runtime-only Nyzul parking queue, IPC targeting, and movement holds.
- `remote_bridge.lua`
  - UI hub endpoint and settings/state bridge between addon and WinForms app.
- `UnifiedCombatWinForms/`
  - Desktop UI (direct connect to addon hub).

### Runtime Split (Important)

- Engine tick loop (every ~0.25s): scheduler + core combat (`unified_engine`).
- Prerender loop (frame-level): party-follow updates + bridge servicing.

The system explicitly coordinates these loops with shared state flags (for example, combat intent and puller-gated movement handoff).

### Legacy Files

`dd2_engine.lua`, `dd2_module.lua`, and `melee_engine.lua` are kept in-repo as legacy/reference material.  
Active runtime uses UC engine path from `UnifiedCombat.lua` and does not require those files for normal operation.

## Core Functionality

### Targeting and Engagement

- Party claim aware target eligibility.
- Prime mode behavior for unclaimed aggressive targets.
- Fight leader target preference (`fight_leader` + `fight_leader_id`).
- Add-control lane for controlled engaged retarget behavior.
- Target-ignore list support (name-based exclusion).
- Sticky engaged target behavior to prevent mid-fight churn.
- Death-event-assisted switch-target flow for faster post-kill transitions.

### Movement

- Approach/retreat comfort band around target.
- Optional spacing behavior against nearby party members.
- Puller distance gate:
  - Blocks approach movement when configured conditions fail.
  - Hands movement back to party-follow while puller gate is active to prevent orphan/stale run-vector behavior.
- Party-follow min/max + fight-follow min override window after combat activity.

### Combat Actions

- Ordered JA execution (`uc_ability_pipeline.lua`).
- WS gate logic (`uc_ws_gate.lua`) and remembered valid WS fallback (`uc_ws_memory.lua`).
- Smart WS candidate selection with skillchain timing support.
- Party WS-ready hold behavior to reduce cross-party WS overlap.
- Aftermath support via UI-configurable WS selection and buff-state checks.

### UI / Bridge

- Direct WinForms connectivity to addon hub (`127.0.0.1:27182` by default).
- Session list and per-session settings/state.
- Dirty-state/signature style update flow to reduce redundant redraw churn.
- Request/reply + push-update model via `remote_bridge.lua`.

## Runtime Flow

1. Addon load:
  - Initialize settings defaults, load profile, register events/listeners.
2. Engine start:
  - `unified_engine.start()` schedules tick loop.
3. Each engine tick:
  - Run scheduler (`unified_scheduler.process_tick()`).
  - If not blocked, run core combat tick (`UC_CoreCombatTickOnce`).
4. Each prerender frame:
  - Broadcast own follow IPC position.
  - Tick remote bridge.
  - Run party-follow movement pass.
5. State/events:
  - Action packets + action messages feed combat memory and retarget/WS timing behavior.

## Configuration and Profiles

Profiles are character-scoped files with job sub-profiles:

- Path: `data/profiles/<character>.lua`
- Structure: `return { version = 1, profiles = { UC = { JOB = {...} } } }`

Notes:

- New/canonical UC settings are persisted under UC profile tree.
- Durable UI edits remain local until Save writes the profile files.
- The addon consumes saved v2 changes through profile reload, startup autoload, or opt-in file-change auto-reload.
- In-game command `//uc save` writes active profile.

## Installation

1. Place addon folder at:
   - `Windower/addons/UnifiedCombat`
2. In Windower:
   - `//lua load UnifiedCombat`
3. Start engine when desired:
   - `//uc start`

## Running the UI

Use WinForms desktop UI (direct hub):

- Build/publish output executable:
  - `UnifiedCombatWinForms\bin\Release\net9.0-windows\win-x64\publish\UnifiedCombatWinForms.exe`

Important:

- Python middleware is not required for normal operation.
- `unified_combat_ui.py` remains in repo for historical/dev utility context only.

## Build and Release

From repo root (`.../addons/UnifiedCombat`):

Release build:

```powershell
dotnet build .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Release
```

Release publish (`win-x64`, single-file, framework-dependent):

```powershell
dotnet publish .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

See also:

- [build_commands.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\build_commands.md)

## Commands

Primary addon commands:

- `//uc start` - start engine
- `//uc stop` - stop engine
- `//uc save` - save active profile
- `//uc reload` - reload active profile
- `//uc host <ip>` - set bridge host
- `//uc port <port>` - set bridge port
- `//uc engine` - print active engine label

Fight leader:

- `//uc fight_leader on|off|clear|<party name>`

Add priority list:

Only listed mobs are eligible for add-control overrides. When no listed mob is valid, combat stays on the fight leader's target.

- `//uc add_priority add <mob name>`
- `//uc add_priority remove <index>`
- `//uc add_priority list`
- `//uc add_priority clear`

Nyzul lamp parking:

Configure the coordinator, persistent anchor, and ordered parker names in the coordinator character's UI profile. The durable profile stores names only at `config.follow.nyzul`; the active run, queue position, and movement holds are runtime state.

- `//uc nyzul begin` - start a run and park the configured anchor
- `//uc nyzul park` - park the next present character in configured order
- `//uc nyzul regroup` - release lamp parkers, reset the queue, and keep the anchor parked
- `//uc nyzul undo` - release the most recently parked lamp character
- `//uc nyzul status` - show local role and coordinator queue state
- `//uc nyzul end` - release the anchor and all lamp parkers

Typical flow:

1. Run `//uc nyzul begin` once at the start of the investigation.
2. Run `//uc nyzul park` once at each lamp; no character name is required.
3. Run `//uc nyzul regroup` after completing the lamp objective.
4. Run `//uc nyzul end` when the investigation ends.

Parking blocks UnifiedCombat party-follow, path, formation, and combat movement without changing durable follow settings or starting/stopping the engine.

Most settings should be managed in WinForms UI for consistency and discoverability.

## Dependencies

### Windower / Lua-side

- Standard Windower runtime APIs/events.
- `ActionPacket` listener usage from Windower environment.
- Vendored `lor` library in `./lor` (addon-local path preferred at startup).

### External addon dependencies

UnifiedCombat does not require GearSwap or SetTarget for core targeting/engage behavior in current UC runtime path.

## Repository Layout

- `UnifiedCombat.lua` - entrypoint, events, command parsing, profile handling.
- `remote_bridge.lua` - bridge protocol/state mapping for UI.
- `unified_engine.lua` - UC engine loop and scheduler hook.
- `unified_scheduler.lua` - scheduler logic.
- `unified_combat_core.lua` - targeting/combat/movement/action core.
- `uc_*` modules - focused helpers (attack, targeting, follow, ignore, add control, etc.).
- `UnifiedCombatWinForms/` - C# desktop UI.
- `docs/` - architecture notes, feature bundles, build commands, legal notices.
- `data/` - runtime persisted profiles/settings.
- `lor/` - vendored third-party library.

## Troubleshooting

### UI opens but sessions do not appear immediately

- Wait briefly after UI startup; session snapshots depend on addon bridge heartbeat/state flow.
- Verify addon is loaded on characters (`//lua load UnifiedCombat`).
- Verify bridge host/port are consistent (`//uc host`, `//uc port`).

### Session appears but controls seem stale

- Trigger a profile reload for that character (`//uc reload`).
- Toggle engine and confirm status reflects in session list.
- Check that UI is connected to correct local hub endpoint.

### Character engages but does not move to target

- Verify puller settings and puller-distance gate behavior.
- If puller gate blocks approach, UC now allows follow movement handoff to avoid orphaned/stale movement behavior.

### WS or ability behavior seems gated unexpectedly

- Check:
  - `weaponskill` / `weaponskill_active`
  - TP threshold and range conditions
  - WS hold conditions (party readying behavior)
  - `abilities` order and `ability_active`

### Profile value type warnings in chat

- Occur when old or mismatched profile value types are loaded.
- Save from current UI/settings to normalize profile schema (`//uc save`).

## Additional Docs

- [canonical_settings.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\canonical_settings.md)
- [engine_feature_matrix.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\engine_feature_matrix.md)
- [feature_bundle_tracking.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\feature_bundle_tracking.md)
- [build_commands.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\build_commands.md)
- [THIRD_PARTY_NOTICES.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\THIRD_PARTY_NOTICES.md)

Scheduler design drafts:

- [unified_scheduler_design.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_design.md)
- [unified_scheduler_rfc.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_rfc.md)
- [unified_scheduler_phase1_amendment.md](C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\unified_scheduler_phase1_amendment.md)
