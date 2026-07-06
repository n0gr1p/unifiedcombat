# UnifiedCombat Profile / Runtime Ownership Contract

## Purpose

This document defines the ownership boundary between:

- UI-owned durable profile/settings data
- addon-owned runtime/session state
- flat compatibility mirrors
- bridge/status reporting
- migration/bootstrap tooling

This contract exists to prevent scope drift while migrating UnifiedCombat from many flat `_G.UC_SETTINGS` reads toward a structured active runtime profile.

## Core Rule

Durable settings and runtime state are not the same thing.

The UI owns durable profile/settings files.

The addon owns runtime combat behavior and live/session state.

The addon consumes the UI-owned profile file into `_G.UC_ACTIVE_PROFILE`.

`_G.UC_SETTINGS` remains a flat compatibility projection during migration. The existence of a value in `_G.UC_SETTINGS` does not automatically make that value durable profile configuration.

## Current Target Architecture

### Durable profile source of truth

The long-term durable source of truth is one structured v2 profile file per character/main-job/sub-job combination:

    data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua

The UI writes this file.

The addon reads/validates/diffs/reloads this file.

### Active runtime durable config

The addon consumes the v2 profile into:

    _G.UC_ACTIVE_PROFILE

Expected shape:

    _G.UC_ACTIVE_PROFILE = {
      version = 2,
      profile = {
        schema_version = 2,
        character = "...",
        main_job = "...",
        sub_job = "...",
        source = "ui",
      },
      config = {
        ui = {},
        combat = {},
        abilities = {},
        defensive = {},
        movement = {},
        follow = {},
        targeting = {},
        tank = {},
        sleep = {},
        spells = {},
        maintenance = {},
        debug = {},
        ownership = {},
        legacy = {},
      },
    }

### Flat compatibility projection

`_G.UC_SETTINGS` remains a compatibility surface for old consumers and legacy flows.

It may contain:

- projected durable settings
- runtime/session state
- legacy mirrors
- command-mutated compatibility values
- bridge-facing compatibility fields

A flat key is not durable solely because it exists in `_G.UC_SETTINGS`.

## Ownership Categories

### 1. Durable Profile Config

Durable profile config is UI-owned and file-backed.

Examples:

- combat preferences
- targeting preferences
- tank settings
- defensive thresholds
- maintenance settings
- follow/movement/pathing preferences that are profile material
- debug config

Durable config may be loaded into `_G.UC_ACTIVE_PROFILE`.

Durable config may be projected into `_G.UC_SETTINGS` for compatibility.

Durable config should be compared by `profilev2 status` and `profilev2 diff`.

Durable config may be applied by `profilev2 reload`.

### 2. Runtime / Session State

Runtime/session state is addon-owned and not durable profile config.

Examples:

- engine currently running/stopped
- current target
- current selected action
- pending action state
- scheduler locks
- movement-owner state
- live path points being recorded or mutated
- target snapshots
- party/mob snapshots
- bridge protocol state
- combat execution state

Runtime/session state must not be written into the UI-owned v2 profile file.

Runtime/session state must not be required for v2 profile validation.

Runtime/session state must not produce durable profile drift after reload.

Runtime/session state may be reported through status/bridge surfaces.

### 3. Runtime / Legacy Overrides

Some existing addon commands mutate flat `_G.UC_SETTINGS` keys. These are not automatically durable profile edits.

Known runtime/session or legacy override fields:

- `fight_leader`
- `fight_leader_id`
- `add_priority_names`
- `sleep`
- `sleepspells`
- `sleepspell`

These should be treated as runtime/session overrides or legacy compatibility overrides unless explicitly reclassified.

Reader code should use `uc_runtime_overrides.lua` for these fields where practical.

These fields should not be silently promoted into durable UI-owned profile config.

### 4. Compatibility Mirrors

Compatibility mirrors exist to support old readers or old flat contracts.

Known compatibility/runtime mirror fields that should not define durable drift:

- `engine_enabled`
- `command.engine_enabled_default`
- `abilities.legacy_slots`
- `targeting.legacy_slots`
- `targeting.add_priority_names`
- `follow.party.leader_id`
- `follow.fight.leader_id`
- `sleep`
- `sleepspells`
- `sleepspell`

Compatibility mirrors may be rebuilt by normalization/projection.

Compatibility mirrors should not cause `profilev2 status` or `profilev2 diff` to report drift if the durable UI-owned data has been successfully applied.

## Engine State Rule

Engine running state is runtime state.

The following is runtime/session state:

    engine_enabled

It means whether the addon engine is currently running.

It must not be treated as durable profile config.

It must not be written by the UI as a durable profile setting.

It must not be added as:

    engine_enabled_default

unless a separate, explicit autostart feature is designed and approved.

Future autoload/autostart work must keep these separate:

- profile v2 autoload: whether the addon should consume the profile file on startup
- engine autostart: whether the combat engine should start running automatically

These are different features and must not be conflated.

## Addon Commands

### Profile v2 commands

The addon may expose profile consumer commands:

- `//uc profilev2 status`
- `//uc profilev2 diff`
- `//uc profilev2 reload`
- `//uc profilev2 validate`
- `//uc profilev2 apply`

These are consumer/diagnostic commands.

`profilev2 reload` consumes a UI-authored durable file and updates `_G.UC_ACTIVE_PROFILE` plus the flat compatibility projection.

### Migration/bootstrap command

The addon may expose:

- `//uc profilev2 export`

This is migration/bootstrap only.

It seeds an initial structured v2 file from currently loaded compatibility settings.

It is not the normal save path.

It must not become the primary profile editor.

### Runtime commands

Runtime commands may mutate addon-owned session state.

Examples:

- `//uc start`
- `//uc stop`

These must not be treated as durable profile edits.

### Legacy flat-write commands

Existing commands that mutate durable-looking `_G.UC_SETTINGS` keys are legacy compatibility behavior unless explicitly reclassified.

Do not add generic sync-from-command-mutation into `_G.UC_ACTIVE_PROFILE`.

Do not make addon slash commands the normal durable profile editing path.

## UI Responsibilities

The UI owns durable settings editing and writes.

The UI should write structured v2 files at:

    data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua

The UI-authored profile should use:

    profile.source = "ui"

The UI must not require the addon to be running to save the file.

The UI must not call addon commands as the primary durable save mechanism.

The UI must not write runtime-only addon state into the durable profile.

The UI should emit stable, deterministic Lua output.

The UI should use safe temp-write/promote behavior where practical.

## Addon Responsibilities

The addon owns runtime behavior.

The addon consumes the UI-authored profile file.

The addon validates, diffs, and reloads the file.

The addon maintains `_G.UC_ACTIVE_PROFILE` as the structured active durable config.

The addon maintains `_G.UC_SETTINGS` as a compatibility projection.

The addon must not make runtime state durable by accident.

The addon must not write profile files except for explicit migration/bootstrap export.

## Bridge / Status Responsibilities

Bridge/status surfaces may report both durable config state and runtime/session state.

They must keep categories clear.

Examples of bridge/status data:

- profile v2 file state
- profile v2 validity
- profile v2 diff count
- engine currently running/stopped
- current runtime status

Reporting runtime state does not make it durable profile config.

## Profile v2 Diff / Status Rules

`profilev2 status` and `profilev2 diff` compare durable profile config only.

They should ignore runtime/session state and compatibility mirrors.

After a successful `profilev2 reload`, the expected happy path is:

    UC profile v2 status: valid, runtime matches file
    UC profile v2 diff: no config differences

If a post-reload diff remains, the first step is to identify the exact diff path.

Do not guess new exclusions.

Do not broadly weaken durable diff.

Fix the mismatch at the correct boundary:

- UI writer shape
- addon projection
- normalizer
- durable compare filter
- runtime/compatibility classification

## Autoload Policy

Startup autoload is not currently part of the base contract.

Autoload may be added later only as an explicit opt-in feature.

Autoload means:

    On addon startup, consume the UI-authored v2 profile file automatically.

Autoload does not mean:

    Start the combat engine automatically.

Autoload must not imply engine autostart.

Autoload must not write profile files.

Autoload must not watch/poll files unless a separate file-watch feature is explicitly designed.

## File Watching Policy

File watching/polling is out of scope unless explicitly designed.

Current expected workflow:

1. UI writes profile file.
2. User runs `//uc profilev2 reload`, or future explicit autoload consumes it on startup.
3. Addon applies durable config into `_G.UC_ACTIVE_PROFILE`.
4. Runtime/session state remains addon-owned.

## Schema Change Policy

Do not change v2 schema casually.

Schema changes require:

- docs update
- fixture update
- UI writer test update
- addon validator test update
- reload/apply test update
- migration note if existing files are affected

Compatibility mirrors should not be added to durable schema just because old flat settings contain them.

## Testing Requirements

Any task touching profile ownership must include tests for the relevant boundary.

### UI writer tests

Should prove:

- emitted file has `version = 2`
- emitted file has `profile.source = "ui"`
- emitted file has correct character/main/sub metadata
- emitted file has deterministic domain order
- runtime-only fields are excluded
- safe write behavior works

### Addon profile consumer tests

Should prove:

- UI-authored file validates
- UI-authored file diffs
- UI-authored file reloads
- post-reload diff is zero
- runtime/session mirrors do not create durable drift
- detailed diff paths are available for diagnostics

### Runtime ownership tests

Should prove:

- runtime override accessors do not mutate `_G.UC_ACTIVE_PROFILE`
- engine running state is not durable profile config
- command-mutated legacy fields do not become profile edits by accident

## Hard No List

Do not do these without a dedicated design task:

- Do not make `engine_enabled` durable.
- Do not add `engine_enabled_default`.
- Do not make start/stop profile edits.
- Do not make addon slash commands the primary durable profile editor.
- Do not add generic sync-after-command-mutation into `_G.UC_ACTIVE_PROFILE`.
- Do not write scheduler state into profile files.
- Do not write pending/lock/current-action/target snapshot state into profile files.
- Do not treat `_G.UC_SETTINGS` as the durability source of truth.
- Do not weaken diff/apply safety checks to hide mapping bugs.
- Do not add startup autoload and engine autostart as one combined behavior.

## Current Accepted Direction

The accepted direction is:

    UI writes durable v2 profile file.
    Addon consumes durable v2 profile file.
    Addon stores durable config in _G.UC_ACTIVE_PROFILE.
    Addon owns runtime state separately.
    _G.UC_SETTINGS remains a compatibility projection.
    Bridge/status reports both durable and runtime state without mixing ownership.
