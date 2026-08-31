# UnifiedCombat

UnifiedCombat is a Windower 4 addon and .NET WinForms desktop UI for coordinating multibox combat automation in Final Fantasy XI.

The current runtime has one engine and one scheduler-owned action path. The scheduler arbitrates combat, defensive support, maintenance, and coordinated movement; the former `melee`/`dd2` loops and the transitional scheduler dark-launch settings are no longer runtime choices. The desktop UI hosts a local TCP server and writes durable profile-v2 configuration without requiring Python middleware.

## Current status

Status of the current checkout (`3f78bf5`, 2026-07-31):

### Complete and established

- The six-phase scheduler refactor is complete. Phase 6 removed the legacy core combat loop, retired the four `scheduler_dark_launch_*` settings, and made the five `domain_*_enabled` settings authoritative.
- The scheduler owns target/action selection and dispatch. `unified_combat_core.lua` remains a side-effect-light combat policy and intent helper; it is not a second tick loop.
- Combat, defensive support, COR/BRD maintenance, movement coordination, profile-v2 consumption, reactions, and scheduler diagnostics have broad replay/self-test coverage.
- The scheduler cutover was field-tested on a five-character party on 2026-07-24 with no reported regression. Party follow, combat movement/casting, and lifecycle stop were included in that acceptance pass.
- Structured Profile V2 is the sole durable UI-authored configuration source. The addon validates and consumes the exact identity automatically at startup and on stable file changes; manual reload remains diagnostic/recovery tooling.

### Implemented, with field acceptance still open

- Summoner v1 is implemented through its six RFC phases: avatar convergence, Avatar's Favor, one Ward, Assault, Rage, pet-command serialization, optional target-HP and pet-TP gates, diagnostics, and profile/UI support. Automated coverage is extensive; further live packet/command validation is still recommended.
- GEO maintenance and independent camp pulling are code-complete, default-off, and covered by focused automated tests. GEO/Indi, Entrust, luopan replacement/enhancement, optional Life Cycle/Ecliptic Attrition, Bolster arming, pull quotas, breadcrumbs, recovery, and return-to-camp are awaiting a clean field-acceptance pass.
- Maiden of the Dusk (Easy) encounter formation and reaction handling are implemented and tested in isolation. Their live encounter checklist is still open.
- Nyzul ordered lamp parking has focused runtime coverage but no recorded live acceptance result.
- Route/path following retains an accepted live-validation risk from the scheduler cutover; focused path execution and movement-arbitration tests pass.
- The defensive domain includes an opt-in highest-priority charmed-party-member sleeper, backed by the checked-in safe-spell policy and confirmed Sleep-state tracking.
- The defensive domain includes an opt-in sleeping-party-member waker that casts `Cure` only after authoritative Sleep detection and explicit non-Charm validation; all internal and HealBot allied Cure dispatches reject currently charmed targets.

See the [scheduler RFC index](RFC/README.md), [phase-6 exit audit](RFC/UnifiedCombat_scheduler_refactor_phase6_exit_audit_2026-07-24.md), [Summoner implementation guide](SMN_RFC/summoner_v1_implementation.md), and [GEO/camp-puller tracker](GEO_PULLER_RFC/implementation_tracking.md) for detailed evidence and remaining field work.

## Architecture

### Main runtime components

- `UnifiedCombat.lua` — addon entrypoint, defaults, Windower events, commands, profile lifecycle, and domain predicates.
- `unified_engine.lua` — 0.20-second engine loop, cadence control, and scheduler debug overlay.
- `unified_scheduler.lua` — proposal collection, ranking, dispatch, pending/action state, locks, defensive arbitration, maintenance integration, and movement coordination.
- `unified_combat_core.lua` — combat policy, target/WS/tank/pull selection, skillchain state, and scheduler-facing intent helpers.
- `uc_provider_*.lua` — extracted combat, target-control, tank-enmity, defensive, enemy-dispel, and maintenance proposal providers.
- `uc_scheduler_*.lua` — scheduler context, proposal, ranker, dispatcher, pending, lock, ownership, observability, and utility modules.
- `uc_movement_dispatcher.lua` — shared movement side-effect boundary used by scheduler, formation, party follow, pathing, Nyzul, and lifecycle stops.
- `uc_party_follow.lua` / `uc_pathing.lua` — frame-level party follow, zone replay, route recording, and route traversal.
- `remote_bridge.lua` — TCP client that connects each addon session to the WinForms hub.
- `UnifiedCombatWinForms/` — .NET 9 desktop UI, profile writer, and loopback session hub.

### Runtime flow

1. On addon load, UnifiedCombat initializes compatibility settings and canonical active config, loads the character profile, queues optional profile-v2 autoload, seeds packet-derived state, and registers events.
2. `//uc start` starts the unified engine. Every 0.20 seconds the engine calls `unified_scheduler.process_tick()`.
3. The scheduler builds one tick-stable world snapshot, collects enabled-domain proposals, ranks and revalidates the selected plan, dispatches through the owned executor boundary, and updates pending/action state from packet and text evidence.
4. Combat proposals run at engine cadence, defensive collection is throttled to 2 Hz, and most maintenance collection is throttled to 1 Hz. BRD sequencing can participate every engine tick while its action lane is reserved.
5. The movement coordinator runs after action selection subject to action, cast, BRD, camp-puller, reaction, formation, and domain ownership rules.
6. The prerender event services route traversal/recording, party-position IPC, the UI bridge, party follow, profile-v2 autoload, and optional file-change reload.

`domain_combat_enabled`, `domain_defensive_enabled`, `domain_movement_enabled`, `domain_maintenance_enabled`, and `domain_follow_enabled` determine participation. The engine must be running for combat, defensive, movement, and maintenance domains; party follow is independently domain-gated and can operate with the engine stopped.

### Legacy/reference files

`dd2_engine.lua`, `dd2_module.lua`, and `melee_engine.lua` remain for compatibility/reference and parse coverage. They are not active engine choices. `unified_combat_ui.py` is historical development material; the normal UI path is the WinForms application.

## Functionality

### Combat and target control

- Party/alliance-claim-aware target selection, prime behavior, sticky targets, death transitions, manual mode, fight-leader preference, partner exclusions, and name-based target ignores.
- Add control restricted to configured priority targets; when no configured add is eligible, fight-leader combat remains on the leader target.
- Scheduler-owned engage retry/debounce, stale action-state release, zero-HP target rejection, and packet-confirmed transitions.
- Smart or primary-only weaponskill selection, skillchain planning/revalidation, party WS holds, aftermath handling, and ordered configured job abilities.
- Tank enmity recovery using a prioritized mixed list of job abilities and spells.
- Configured sleep spell ordering for eligible hostile adds, including active-sleep suppression and range checks.

### Defensive support and reactions

- Internal defensive provider for cures, status removal, configured buffs, overwrite timing, Doom water, and Majesty-aware ordering.
- Optional HealBot provider adapter within scheduler arbitration.
- Packet-fed enemy-effect tracking and Dispel/Magic Finale proposals for eligible party/alliance-claimed enemies.
- Profile-defined reactions:
  - `ability_window` + `turn_away` for actions such as Cold Stare or Fatal Allure.
  - `ability_window` + `run_away` with a positive raw-coordinate target distance for bounded AoE escape movement.
  - `ability_window` + `move_to_range` to continuously maintain a raw radial distance by moving inward or outward while the window remains active.
  - `enemy_buff` + `stop_attacking` for effects such as Dread Spikes.
- Reaction holds preserve self/party support work while suppressing conflicting enemy-facing combat work.

### Job maintenance

- COR: two-roll maintenance, Double-Up/Eleven handling, Fold, Crooked Cards selection, Luzaf range override, and required-member range policy.
- BRD: exact song-identity tracking, packet/timer-driven refresh, dummy-song capacity setup/recovery, Nightingale/Troubadour, Soul Voice, Clarion Call, Marcato, Pianissimo-targeted songs, and optional party-coverage repositioning before group-song cycles. Repositioning finds a shared in-range casting point, waits when full coverage is unavailable, permits an urgent largest-cluster cast, and never spends dummy/Clarion capacity work on a partial cluster.
- GEO: Geo/Indi upkeep, character and optional enemy camp-radius requirements, Entrust sequencing, Full Circle replacement, Blaze of Glory, optional Ecliptic Attrition/Life Cycle, luopan positioning, and explicitly armed Bolster.
- SMN: desired-avatar convergence, Favor, one Ward, Assault-on-combat-start, one configured Rage, per-command backoff, and shared pet-command coordination.

### Movement and special workflows

- Target approach/retreat, predictive spacing, facing, puller distance/leash policy, shared camp anchors, and cast movement freezes.
- Party-follow min/max distance, combat hold windows, IPC position sharing, and zone replay.
- Route recording, loop/patrol traversal, party-cohesion gating, hunter filters, and spell/JA route pulling.
- Independent camp pulling with target matching, quota/replenishment policy, camp leash, direct entity-ID actions, breadcrumbs, bounded recovery, cooldowns, and return-to-camp.
- Nyzul lamp parking with coordinator, persistent anchor, ordered parkers, undo, regroup, and runtime-only movement holds.
- Maiden of the Dusk (Easy) formation roles for tank center tether, DPS flank positioning, and healer safety/coverage geometry.
- Profile-scoped, role-free formations keyed by exact named-mob or boss name, selected automatically when that enemy is the engaged current target. See [named mob formations](docs/named_mob_formations.md).

## Installation

1. Place this directory at `Windower/addons/UnifiedCombat`.
2. Load the addon on each character:

   ```text
   //lua load UnifiedCombat
   ```

3. Configure and save the selected character/job profile in the desktop UI.
4. Apply the saved v2 profile with `//uc profilev2 reload`, or enable profile-v2 autoload/auto-reload in the profile.
5. Start the engine when ready:

   ```text
   //uc start
   ```

Automation features are default-off or require explicit configuration. The five runtime domains default enabled, but the engine and feature-specific behavior toggles do not.

## Desktop UI

The UI is a .NET 9 Windows application. Its local TCP server listens on `127.0.0.1:27182`; addon sessions reconnect every two seconds when disconnected. The UI can be started before or after the addon.

Build:

```powershell
dotnet build .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Release
```

Publish a framework-dependent, single-file `win-x64` executable:

```powershell
dotnet publish .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

Published executable:

```text
UnifiedCombatWinForms\bin\Release\net9.0-windows\win-x64\publish\UnifiedCombatWinForms.exe
```

The published build requires the .NET 9 Desktop Runtime. Building requires the .NET 9 SDK.

The UI exposes general combat/defensive settings plus spacing, encounter formation, pathing, reactions, scheduler domains, camp pulling, and job-relevant COR/BRD/GEO/SMN configuration. Durable edits remain local until Save. Despite the current button label `Save (XML)`, Save writes only the structured Lua Profile V2 file; it does not push form fields over the runtime bridge.

## Configuration and profiles

### Structured profile v2

The UI-owned durable runtime configuration is stored per character/main-job/sub-job:

```text
data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua
```

Its top-level shape is:

```lua
return {
  version = 2,
  profile = {
    schema_version = 2,
    source = "ui",
    character = "Character",
    main_job = "PLD",
    sub_job = "WAR",
  },
  config = {
    -- durable ownership, combat, defensive, movement, follow,
    -- maintenance, tank, reactions, summoner, and UI policy
  },
}
```

The UI is the normal v2 writer. The addon is the consumer and keeps the applied canonical profile in `_G.UC_ACTIVE_PROFILE`; `_G.UC_SETTINGS` is a compatibility projection. Runtime state—engine running state, selected targets, resolved IDs, locks, pending actions, current path file, camp journey, pet state, song timers, and Nyzul queue progress—is deliberately not durable.

Profile V2 is the sole automatic and durable configuration source. Addon load, login, and every main-job or subjob identity transition resolve the exact file automatically. The file watcher is always active: it polls at low frequency, waits for stable content, ignores unchanged hashes, and applies valid edits through the same validation path. The old `profile_v2_autoload` and `profile_v2_auto_reload_on_change` keys are accepted as obsolete input but have no effect and are not written.

Normal workflow:

1. Edit a profile in WinForms.
2. Click Save to atomically write only `data/profiles_v2/...lua`.
3. Let the addon detect and apply the stable file automatically.
4. Use `//uc profilev2 status` or `//uc profilev2 diff detail` to inspect the result. `//uc profilev2 reload` remains a manual diagnostic/recovery action, not a normal lifecycle requirement.

### Version-1 compatibility profile

The addon retains the character-scoped compatibility format:

```text
data/profiles/<lowercase-character>.lua
```

```lua
return { version = 1, profiles = { UC = { JOB = { } } } }
```

These files may remain for historical inspection or explicit migration tooling, but normal addon lifecycle and UI Save do not read, write, or fall back to them. Compatibility commands `//uc save` and `//uc reload` now write/reload the exact Profile V2 identity. `//uc profilev2 export` remains a manual bootstrap/export tool.

When an exact Profile V2 file is missing or invalid during a new identity transition, UnifiedCombat publishes safe normalized defaults and does not reuse configuration from the prior identity or a legacy file. An invalid edit to an already active identity leaves the last-known-good runtime configuration in place; correcting the file applies it automatically.

### Activity profiles

The WinForms sidebar has one global activity selector for all connected
sessions. Create and Update capture every active session's exact
character/main-job/sub-job profile. An activity can retain multiple job
variants for the same character, and activation selects the exact variant that
matches each session's current jobs. Dropdown selection is management-only;
**Apply to all sessions** is the explicit activation action.

Activity activation is cohort-wide: every active session must have a valid
exact variant. Running engines do not block an explicitly confirmed change;
the confirmation warns that changes take effect immediately and already-issued
actions are not cancelled. The UI stages canonical exact-identity Profile V2
files, requests an acknowledged profile-v2 reload from every
session, verifies zero durable differences, and rolls those files back if the
cohort does not complete successfully. The JSON inside an activity bundle is
an explicit editor snapshot for that bundle; it is never deployed as a
per-identity configuration source. After success, the selected session editor
immediately reflects the applied activity. See
[Activity profiles](docs/activity_profiles.md).

## Commands

The addon accepts both `//uc` and `//unifiedcombat` prefixes.

### Engine and connection

- `//uc start` — start the unified scheduler engine.
- `//uc stop` — stop the engine and release runtime movement/action state.
- `//uc engine` — print the active engine label (`UC`).
- `//uc host <ip>` — change the UI server host for the current session.
- `//uc port <port>` — change the UI server port for the current session.
- `//uc save` / `//uc reload` — compatibility aliases that save or reload the exact Profile V2 identity.

### Profile v2 and config diagnostics

- `//uc profilev2 status`
- `//uc profilev2 validate`
- `//uc profilev2 diff [detail]`
- `//uc profilev2 reload`
- `//uc profilev2 apply`
- `//uc profilev2 export`
- `//uc profilev2 autoreload status`
- `//uc configstatus export`

### Runtime controls

- `//uc fight_leader on|off|clear|<party name>`
- `//uc add_priority add <mob name>|remove <index>|list|clear`
- `//uc sleep on|off|list|clear|set <spell>|add <spell>|remove <index>|move <index> up|down`
- `//uc camp set|clear|status|pullstatus`
- `//uc reactions status`
- `//uc formation status`
- `//uc geo status|reseed|bolster arm|bolster disarm`
- `//uc smn pettarget start|status|stop`
- `//uc brd status|options|trace once|capture once|log start|stop|status`
- `//uc nyzul begin|park|regroup|undo|status|end`

Most durable settings should be edited in WinForms. Slash commands primarily control runtime/session state or provide diagnostics.

## Verification

Run the aggregate Lua replay/self-test suite:

```powershell
lua .\tests\replay\harness\selftest_all_replay_fixtures.lua
```

Build and test the profile-v2 writer:

```powershell
dotnet build .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Debug --no-restore
dotnet run --project .\UnifiedCombatWinForms\UnifiedCombatWinForms.csproj -c Debug --no-build -- --selftest-profile-v2
```

Current checkout result:

- Runtime Lua parse: 99/99 files pass.
- Aggregate replay/self-test: 131/131 suites pass.
- WinForms Debug build: pass with zero warnings and zero errors.
- Structured profile-v2 writer self-test: pass.

Automated tests cannot reproduce all Windower packet timing, server responses, collision, or multi-client behavior. Consult the feature trackers before enabling functionality whose field acceptance is still pending.

## Dependencies

### Runtime

- Windower 4 with Lua 5.1-compatible addon runtime.
- Windower `resources`, `files`, `actions`, `ActionPacket`, socket, packet, and text APIs used by the addon.
- Vendored `lor` modules under `lor/`.
- .NET 9 Desktop Runtime for the framework-dependent WinForms UI.

GearSwap, SetTarget, Python, and the legacy `dd2`/`melee` engines are not required by the active runtime.

### Development

- Lua 5.1 to run the replay/self-test harness.
- .NET 9 SDK to build and run WinForms tests.
- Git for change review and release workflows.

## Repository layout

- `UnifiedCombat.lua` — entrypoint, events, profiles, commands, and lifecycle.
- `unified_engine.lua` — engine cadence and overlay.
- `unified_scheduler.lua` — scheduler orchestration and active dispatch path.
- `unified_combat_core.lua` — combat policy and scheduler-facing intent helpers.
- `uc_provider_*.lua` — action proposal providers.
- `uc_scheduler_*.lua` — scheduler subsystems.
- `uc_brd_*`, `uc_cor_maintenance.lua`, `uc_geo_maintenance.lua`, `uc_smn_*`, and `uc_pet_*` — job maintenance and pet systems.
- `uc_camp_*`, `uc_pathing.lua`, `uc_party_follow.lua`, `uc_nyzul_runtime.lua`, and `uc_*formation*` — movement and special workflows.
- `UnifiedCombatWinForms/` — desktop UI and structured profile writer.
- `tests/replay/` — deterministic fixtures, runners, and integration self-tests.
- `docs/` — current design, audit, field packet, and test-result documents.
- `docs/old/` — superseded pre-cutover documentation.
- `RFC/`, `SMN_RFC/`, and `GEO_PULLER_RFC/` — architecture and feature RFC records.
- `data/` — static catalogs plus ignored runtime profiles, paths, status exports, and logs.
- `TargetBar/` — bundled target-bar code and assets.
- `lor/` — vendored third-party Lua library.

## Troubleshooting

### The UI shows no sessions

- Confirm the UI is running and listening on `127.0.0.1:27182`.
- Confirm UnifiedCombat is loaded on each character.
- Confirm the session's `host` and `port` match the UI server.
- Allow a few seconds for the addon's reconnect interval and initial state snapshot.

### Saved UI settings are not active in game

- Save writes files only; it does not mutate the running durable config.
- Run `//uc profilev2 reload`, or confirm v2 autoload/auto-reload is enabled.
- Run `//uc profilev2 status`; use `//uc profilev2 diff detail` to locate remaining durable differences.
- Verify the selected UI session has the expected character, main job, and subjob because those values determine the v2 filename.

### A domain does not run

- Confirm the engine is running for combat, defensive, movement, and maintenance work.
- Check the matching `domain_*_enabled` setting on the Scheduler tab.
- Confirm the feature-level toggle and configuration are valid.
- Use the scheduler overlay/logs and feature status command to inspect rejection, pending, lock, and ownership reasons.

### A character does not move

- Check the movement domain plus `move`, spacing, puller, party-follow, path, formation, and camp-puller settings relevant to that character.
- Inspect movement owner/mode/block diagnostics for cast freeze, reaction hold, BRD lane reservation, camp-puller ownership, Nyzul parking, zone suspension, or an invalid target/camp.

### A WS, spell, JA, or pet command does not fire

- Verify the configured action exists for the current job/avatar and is enabled.
- Check recast, MP/TP, target/range, action-state, pending, duplicate-suppression, and domain gates.
- For WS, inspect skillchain/party-hold diagnostics; for SMN use `//uc smn pettarget status`; for BRD/GEO use their status/trace commands.
- Prefer the explicit rejection/block reason over adding an implicit fallback action.

### Camp pulling behaves unexpectedly

- Keep it disabled until the pending field-acceptance work is complete.
- Use `//uc camp status` and `//uc camp pullstatus` plus action-timeline logging to capture the journey state, target, quota, geometry, retry, and cooldown evidence.

## Documentation

- [Scheduler RFC index](RFC/README.md)
- [Active scheduler tracking log](RFC/UnifiedCombat_scheduler_refactor_tracking.md)
- [Phase-6 scheduler exit audit](RFC/UnifiedCombat_scheduler_refactor_phase6_exit_audit_2026-07-24.md)
- [Scheduler responsibility map](docs/scheduler_responsibility_map.md)
- [Profile runtime ownership contract](docs/profile_runtime_ownership_contract.md)
- [Profile-v2 structured shape](docs/profile_v2_structured_config_shape.md)
- [Summoner implementation and operations](SMN_RFC/summoner_v1_implementation.md)
- [GEO and camp-pulling implementation tracker](GEO_PULLER_RFC/implementation_tracking.md)
- [Bard maintenance design](docs/bard_song_maintenance_design.md)
- [Reaction runtime design](docs/reaction_runtime_design.md)
- [Maiden of the Dusk formation design](docs/lilith_easy_formation_design.md)
- [Movement coordinator checklist](docs/movement_coordinator_implementation_checklist.md)
- [Enemy buff removal checklist](docs/enemy_buff_removal_implementation_checklist.md)
- [Charm sleeper checklist](docs/charm_sleeper_implementation_checklist.md)
- [Sleep waker checklist](docs/sleep_waker_implementation_checklist.md)
- [Third-party notices (archived location)](docs/old/THIRD_PARTY_NOTICES.md)
