# Canonical Settings and Migration Map

This document defines runtime-canonical keys for the merged UnifiedCombat engine.

## Canonical Keys

- `engine_mode`: runtime-selected strategy bucket (`melee`, `dd2`, `support`)
- `weaponskill`: canonical WS name used by runtime
- `weaponskill_active`: WS enable toggle
- `ability_active`: configured JA enable toggle
- `abilities`: ordered JA list
- `autotarget`, `prime`, `manual`, `face`, `spacing`, `static`, `move`, `solo`
- `partner`, `partner2`, `puller`
- `partner_id`, `partner_id2`, `puller_id`
- `targets`: preferred target names list
- `sleep`, `sleepspell`
- `hunter`, `tank`, `closer`, `command`, `spam`
- `show_ingame_ui`
- `ignore`

## Legacy-to-Canonical Migration

| Legacy Key | Canonical Key | Rule |
|---|---|---|
| `ws1` | `weaponskill` | for old melee profiles, copy to canonical if canonical is empty |
| `weaponskill` (dd2) | `weaponskill` | keep |
| `ability1..ability6` | `abilities` | merge non-empty ordered values into list when list missing |
| `target1..target3` | `targets` | merge non-empty ordered values into list when list missing |
| uppercase `DD2` profile bucket | lowercase `dd2` | normalize bucket name |
| top-level job profile tables | `profiles.melee.<JOB>` or `profiles.dd2.<JOB>` | relocate by job mapping |

## Deprecated Keys (migrate then stop writing)

- `ability1..ability6` (write-compat only)
- `target1..target3` (write-compat only)
- mixed profile roots outside `profiles.melee` / `profiles.dd2`

## Rules

- No silent defaulting during combat decisions.
- Invalid or missing config must produce explicit gate/block reason.
- Migration runs at load/reload and save boundaries only.
