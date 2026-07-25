# UnifiedCombat Scheduler Refactor — Phase 6 Exit Audit

Audit date: 2026-07-24
Baseline commit: `853bed49f9482a13a3918bbc8a15fc6288efa9a5`
Verdict: **DONE / FIELD VERIFIED WITH ACCEPTED PATH-FOLLOW RISK**

## Scope

This audit checks the current working tree against Phase 6 of
`UnifiedCombat_scheduler_refactor_RFC_for_Codex.md`: remove unreachable legacy
scheduler code, remove duplicate helpers, collapse debug globals only after a
replacement exists, and archive or mark old documents superseded.

## Findings

| Requirement | Result | Evidence |
| --- | --- | --- |
| Delete unreachable legacy scheduler branches | `PASS` | The legacy core tick global, core tick wrapper, monolithic legacy combat loop, legacy pull/movement executors, unused legacy-job-adapter global, and scheduler-local direct defensive/HealBot fallbacks are absent. |
| Remove duplicate helpers | `PASS` | Helpers and imports reachable only from deleted legacy paths were removed. A static occurrence audit found no remaining unreferenced local function or top-level import in `unified_combat_core.lua`. The scheduler's unused JSON import, the WinForms read-only checkbox factory, and the empty legacy status-change event hook were also deleted. The apparent `lor/lor_packets` import was retained explicitly because its require-time initialization is consumed by lazy `lor/lor_actor` loading. |
| Retire obsolete ownership schema | `PASS` | The four `scheduler_dark_launch_*` settings are absent from runtime defaults, normalization, active config, ownership/config readers, profile contracts, WinForms controls/writer, fixtures, and all local profiles. The current published UI was restarted and a post-restart marker scan remains clean. |
| Use scheduler-only ownership | `PASS` | The five `domain_*_enabled` values remain authoritative. No profile marker or engine fallback can select a non-scheduler combat path. |
| Rename active legacy/dark-launch helpers | `PASS` | Active dispatch is named `scheduler.dispatch_selected_plan()` and `p1_dispatch_combat()`; the active pending-ledger helper is `record_dispatch()`. Local validation variables use intent terminology. |
| Collapse debug globals only after replacement exists | `PASS — RETAINED BY CONDITION` | `_G.UC_SCHED_P1_DARKLAUNCH_*` validation payloads and matching block reasons remain because no bridge/UI replacement exists. The focused Phase 6 test pins this deliberate exception. |
| Archive or supersede old docs | `PASS` | Current side-effect, responsibility, replay-design, and readiness documents use current dispatch/domain names. Material pre-cutover audits/maps have explicit historical/superseded notices; the Phase 5 terminology document points here. Existing `docs/old/` content remains archived. |

## Side-effect delta

`unified_combat_core.lua` no longer directly sends commands, moves, turns,
selects targets, or invokes attack wrappers. Its tracked surface is reduced to
two WS coordination IPC sends and pure `/ma`, `/ja`, and `/ws` intent
construction. Repository-wide observed tracked hits fell from 236 at Phase 5
closeout to 205.

The active scheduler still injects Windower and low-level adapter functions into
the dispatcher. Those are explicit executor dependencies, not direct execution
fallbacks.

## Document disposition

Current architecture sources refreshed for Phase 6:

- `docs/side_effect_inventory.md`;
- `docs/side_effect_allowlist.md`;
- `docs/scheduler_responsibility_map.md`;
- active enemy-effect, maintenance, readiness, replay-adapter, and formation
  design documents that referenced the old dispatch/domain names.

Pre-cutover snapshots explicitly marked historical or superseded:

- `docs/active_config_consumer_migration_audit.md`;
- `docs/canonical_config_migration_audit.md`;
- `docs/cure_cast_movement_stop_audit.md`;
- `docs/profile_v2_runtime_consumers_audit_b2.md`;
- `docs/scheduler_extraction_checkpoint.md`;
- `docs/scheduler_state_provider_boundary_runbook.md`;
- `docs/scheduler_wrapper_owned_map.md`;
- `docs/vector_run_reachability_decision.md`;
- `RFC/UnifiedCombat_scheduler_refactor_phase5_ownership_terminology.md`.

The existing `docs/old/` directory remains the archive for earlier documents.

## Profile audit

All 42 local `data/profiles_v2/*.lua` files were loaded with Lua and checked for:

- a `config.ownership` table;
- boolean values for all five `domain_*_enabled` keys;
- absence of every `scheduler_dark_launch_*` key.

All 42 passed. The profiles directory is gitignored runtime data, so these
local profile edits do not appear in the tracked working-tree diff.

During final post-field verification, the still-running published UI rewrote
the Ponponponponpon COR/DNC profile with the retired markers. Process and file
timestamps proved that UI instance was built and started at 8:03 PM, before
the Phase 6 writer cleanup at 8:34 PM. The generated file was cleaned again.
The writer self-test now seeds all four stale flat keys and proves the current
source writer omits them. After closing the old process, the current UI was
published and restarted. All 42 v2 profiles passed the final validation before
launch, and the post-restart marker scan remained clean with the replacement
UI running.

## Automated verification

- `lua tests/replay/harness/selftest_phase6_cleanup.lua` — pass.
- `lua tests/replay/harness/selftest_all_replay_fixtures.lua` — 119/119 pass.
- Aggregate runtime parse — 86/86 files pass.
- Aggregate side-effect guard — 135 runtime files, 19 allowlisted files,
  285 pattern checks, 205 observed hits.
- `dotnet build UnifiedCombatWinForms/UnifiedCombatWinForms.csproj --no-restore`
  — pass after removal of the unused UI helper; zero warnings and zero errors.
- `dotnet run --project UnifiedCombatWinForms/UnifiedCombatWinForms.csproj --no-build -- --selftest-profile-v2`
  — pass, including stale retired-marker input omission.

## Exit decision

The code and documentation satisfy the static and replay-verifiable Phase 6
requirements. The established active party was used for final field acceptance:

- Nyoourke PLD/WAR;
- Terrasjr MNK/WAR;
- Niightsiide GEO/RDM as the passive external-GEO participant/camp setter;
- Redrogue BRD/WHM;
- Ponponponponpon COR/DNC.

On 2026-07-24 the user reloaded UnifiedCombat on all active profiles and
completed live testing with no noticed regression. This closes the
runtime-sensitive reload/profile-schema gate. Live path-follow was not newly
isolated and remains the explicitly accepted risk carried from Phases 4 and 5;
its focused automated coverage remains green.

After the completion decision, live evidence showed Ponponponponpon using
Detonator despite its v2 profile specifying Spam and Savage Blade. The Windower
log proves its earlier v2 reload failed while a pre-Phase-6 UI had restored the
retired ownership markers, leaving the runtime on the legacy COR profile where
`spam = false`. The writer/profile deployment is now repaired and the current
v2 file is clean with `spam = true`. The user then reloaded UnifiedCombat on
Ponponponponpon and confirmed that Weaponskill Spam again uses Savage Blade as
configured. The deployment regression is closed, and Phase 6 is complete with
only the previously accepted live path-follow risk outstanding.
