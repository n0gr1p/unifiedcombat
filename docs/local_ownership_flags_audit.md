# Local Ownership Flags Audit

> **Historical Phase 1 artifact (2026-07-24):** Phase 2 retired the local
> dispatcher ownership flags and direct fallbacks audited below. See
> `RFC/UnifiedCombat_scheduler_refactor_tracking.md`.

## Scope

- Path inspected: `C:\Program Files (x86)\Windower\addons\UnifiedCombat\local_ownership_flags.lua`
- File status: tracked in git, not gitignored, and intended to remain local-only
- Audit date: `2026-06-28`

## How the file is loaded

- `UnifiedCombat.lua` loads the file with `pcall(require, 'local_ownership_flags')`.
- The load happens during addon bootstrap before the runtime loop starts using scheduler globals.
- The module body mutates `_G`.
- Missing-file errors are ignored.
- Other load failures are reported through `windower.add_to_chat(...)`.
- The module remains active until Windower reloads the addon or a fresh session starts.

## Current baseline

- `local_ownership_flags.lua` is now reset to a clean baseline.
- No active ownership overrides remain.
- Source defaults are now the active behavior.
- The clean baseline still holds after the tank run-stop phase closure in `T3.6q`.
- `T3.6s` confirms the clean baseline remains the final scheduler ownership baseline.
- This file should stay mostly empty unless you are deliberately bisecting or collecting diagnostics.

## Current local flag inventory

| Line | Setting | Current value | Category | Recommended action | Reason |
| --- | --- | --- | --- | --- | --- |
| 4-16 | commented examples only | none | `promoted_default_on` / `debug_logging` examples | keep commented | Examples only; no active override remains. |
| 18-24 | commented examples only | none | `deferred_or_parked` / tank-bisect examples | keep commented | Examples only; no active override remains. |
| 26-27 | commented diagnostics only | none | `debug_logging` example | keep commented | Example-only diagnostics. |

## Suspicious or stale settings

- None active in the file now.
- The prior stale promoted-default-on false overrides were removed.
- The prior malformed bare assignment was removed.
- The file no longer contains a global promoted kill switch, tank experimental flag, Doom flag, vector flag, or debug probe assignment.

## Recommended normal config

Normal clean config is effectively empty:

```lua
-- Local-only ownership and diagnostic flags.
-- Leave this file mostly empty so source defaults are the normal behavior.
-- Use this file only for temporary local opt-outs, one-off experiments, or
-- diagnostic toggles while field testing.
```

## Recommended temporary tank bisect config

Use commented examples only until you intentionally need a live override:

```lua
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ACTION_SETTLE_RUN_STOP_OWNERSHIP = false
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_SPELL_SETTLE_RUN_STOP_OWNERSHIP = false
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_TARGET_RUN_STOP_OWNERSHIP = true
-- _G.UC_SCHED_P1_ENABLE_DISPATCHER_TANK_ENMITY_SPELL_SELF_RUN_STOP_OWNERSHIP = true
-- _G.UC_DEBUG_ACTION_TIMELINE = true
-- _G.UC_SPELL_LIFECYCLE_PROBE = true
```

## Could the prior local flags explain the tank behavior?

Yes, plausibly.

- The previous file version disabled several promoted default-on ownership paths that tank behavior depends on.
- Resetting the file removes those stale opt-outs, so the scheduler’s source defaults should now be the active baseline.
- If tank starvation persists after this reset, the next step is to field-test again before deeper action-economy diagnosis.

## Next recommended step

1. Reload the addon so the clean baseline takes effect.
2. Field-test tank behavior again with the local file left empty.
3. Only add temporary overrides if you are bisecting a specific tank seam or collecting diagnostics.
