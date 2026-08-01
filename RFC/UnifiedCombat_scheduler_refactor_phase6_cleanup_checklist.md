# UnifiedCombat Scheduler Refactor — Phase 6 Cleanup Checklist

Status date: 2026-07-24
Status: **DONE / FIELD VERIFIED WITH ACCEPTED PATH-FOLLOW RISK**

## RFC requirements

- [x] Delete unreachable legacy scheduler branches.
- [x] Remove duplicate and newly unreachable helpers.
- [x] Collapse obsolete profile/UI ownership markers.
- [x] Rename active scheduler dispatch functions away from dark-launch
  terminology.
- [x] Retain historical debug globals until a bridge/UI replacement exists, as
  required by the RFC.
- [x] Refresh current architecture documents and mark material pre-cutover
  documents superseded.

## Runtime cleanup

- [x] Remove `_G.UC_CoreCombatTickOnce`, `core.combat_tick_once()`, and
  `run_unified_combat()`.
- [x] Remove `core.legacy_pull_executor` and
  `core.legacy_movement_executor`.
- [x] Remove the unused `_G.UC_ENABLE_LEGACY_JOB_ADAPTERS` global.
- [x] Remove the empty legacy status-change event hook.
- [x] Remove scheduler-local `try_delegate_healbot()` and
  `try_internal_defensive_action()` fallback execution.
- [x] Remove core helpers that became unreachable with the legacy loop.
- [x] Remove runtime imports used only by deleted legacy paths.
- [x] Keep scheduler-facing core selectors and state helpers that still have
  proven callers.
- [x] Rename the active pending-ledger helper from
  `p1_record_legacy_dispatch()` to `record_dispatch()`.
- [x] Keep command, target, attack, turn, and movement execution
  dispatcher-backed and fail-fast.

## Configuration and profile cleanup

- [x] Remove `scheduler_dark_launch_combat`,
  `scheduler_dark_launch_defensive`, `scheduler_dark_launch_movement`, and
  `scheduler_dark_launch_maintenance` from defaults, normalization, active
  projection, domain ownership, scheduler config readers, profile contracts,
  WinForms controls, and profile serialization.
- [x] Complete the final marker sweep across all 42 local v2 profiles and six
  local legacy profiles after restarting the published UI.
- [x] Revalidate all 42 v2 profiles after the published UI restart.
- [x] Preserve `domain_combat_enabled`, `domain_defensive_enabled`,
  `domain_movement_enabled`, `domain_maintenance_enabled`, and
  `domain_follow_enabled` as the only durable ownership controls.

The live profile directories are gitignored runtime data. Their marker removal
was applied and validated locally but is not part of the tracked Git diff.

## Diagnostic contract disposition

The `_G.UC_SCHED_P1_DARKLAUNCH_*` validation payloads and
`BLOCK_SCHED_P1_DARKLAUNCH_*` reason strings remain. No bridge/UI replacement
for those payloads exists, so deleting or renaming them would violate the RFC's
explicit condition. Active function names are now
`scheduler.dispatch_selected_plan()` and `p1_dispatch_combat()`.

## Automated acceptance

- [x] Phase 6 focused cleanup contract: pass.
- [x] Runtime Lua parse: 86/86 files.
- [x] Aggregate replay/static suite: 119/119 suites.
- [x] Side-effect discovery guard: 135 runtime files, 19 allowlisted files,
  285 pattern checks, 205 observed hits.
- [x] WinForms build: zero warnings, zero errors after dead UI helper removal.
- [x] WinForms structured-profile writer self-test: pass.
- [x] Structured-profile writer regression: retired marker keys seeded into stale
  flat input are omitted from the saved v2 profile.
- [x] Final post-restart local profile validation: 42 loadable v2 profiles,
  five boolean domains present, and no retired marker.

## Live acceptance

- [x] Reload UnifiedCombat on all active profiles.
- [x] Complete live testing with the established tank, DPS, Bard maintenance,
  COR maintenance, defensive-casting, and passive GEO/camp-setter profiles.
- [x] Observe no regression after reload during the completed live session.
- [x] Retain live path-follow as the previously accepted untested risk; focused
  execution, arbitration, and domain-stop coverage remains green.
- [x] Reload UnifiedCombat on Ponponponponpon after the clean v2 profile
  deployment and confirm Spam uses only Savage Blade.

User-reported result on 2026-07-24: all active profiles were reloaded and
testing completed with no noticed regression.

## Live UI deployment note

The UI process used during field acceptance was started from the published
8:03 PM binary, before the Phase 6 writer cleanup was made at 8:34 PM. A save
from that already-running process reintroduced the four retired markers into
the Ponponponponpon COR/DNC profile. The generated profile was cleaned again,
and the writer self-test now explicitly seeds all four stale keys and proves
that the current writer omits them.

The current WinForms UI was published and restarted at 10:00 PM. The
replacement process is responsive, its embedded structured-profile self-test
passes, and the post-restart marker scan remains clean. This also confirms that
the old-process rewrite issue is closed.

The earlier Ponponponponpon addon reload occurred while the v2 profile still
contained retired ownership markers. Its Windower log records v2 conversion
failure on `config.ownership.scheduler_dark_launch_combat`, leaving the runtime
on the legacy COR profile where `spam = false`. The clean v2 profile has
`spam = true` and primary WS `Savage Blade`. After the clean deployment, the
user reloaded UnifiedCombat on Ponponponponpon and confirmed that Weaponskill
Spam again uses Savage Blade as configured.
