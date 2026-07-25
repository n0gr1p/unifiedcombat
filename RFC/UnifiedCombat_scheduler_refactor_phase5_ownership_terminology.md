# UnifiedCombat Scheduler Refactor — Phase 5 Ownership Terminology

Status date: 2026-07-24

## Decision

Domain ownership is now described in terms of enabled domains and their single
runtime owner:

| Domain | Runtime enablement | Runtime owner |
| --- | --- | --- |
| Combat | `domain_combat_enabled` | scheduler providers, ranking, and dispatcher |
| Defensive | `domain_defensive_enabled` plus defensive feature settings | scheduler defensive providers and dispatcher |
| Movement | `domain_movement_enabled` | scheduler movement coordinator; independent path decisions also honor this domain |
| Maintenance | `domain_maintenance_enabled` plus provider settings | scheduler maintenance provider and dispatcher |
| Party follow | `domain_follow_enabled` plus party-follow settings | independent party-follow decision owner through the shared movement dispatcher |

`uc_domain_ownership.lua` reads the four scheduler domain values from the
normalized active configuration. A missing or non-boolean value is fatal; it
does not select a legacy path.

## Retained setting keys

The following keys remain in defaults, the profile contract, normalized
configuration, projection/serialization, saved profiles, bridge snapshots, and
the WinForms UI:

- `scheduler_dark_launch_combat`
- `scheduler_dark_launch_defensive`
- `scheduler_dark_launch_movement`
- `scheduler_dark_launch_maintenance`

Before Phase 5 these keys selected scheduler-owned dispatch and, most
importantly, allowed the engine to fall back to the legacy core when combat
ownership was false. After Phase 5 they are compatibility-only markers. They do
not enable, disable, or route runtime work.

The keys are intentionally not renamed or deleted in this phase because doing
so requires an explicit profile-schema migration. Existing profiles contain a
mixture of true and false marker values. Using those values after removing the
legacy fallback would silently disable behavior on multiple characters, so the
normalized `domain_*_enabled` controls are now authoritative.

The WinForms Scheduler tab exposes the five authoritative domain controls and
displays the four legacy fields read-only as compatibility markers. Domain
changes require a profile save and reload/apply before they become active
configuration. Formation validation now requires the movement domain, not the
legacy movement marker. The serializer continues to preserve all four legacy
fields.

## Retained diagnostic names

Existing `_G.UC_SCHED_P1_DARKLAUNCH_*` diagnostics, block-reason strings, and
the public scheduler wrapper name `p1_try_dark_launch_dispatch` remain for
compatibility and field-debug continuity. They describe historical names, not
an alternate execution mode. Renaming or removing them is Phase 6 cleanup.

## Language rule

New RFC, audit, tracking, test, and UI prose uses:

- **domain enabled/disabled** for runtime participation;
- **scheduler-owned** for decision/dispatch ownership;
- **compatibility marker** for the retained `scheduler_dark_launch_*` fields;
- **legacy core** only for code that remains present but is not called by
  `unified_engine.lua`.
