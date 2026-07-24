# UnifiedCombat Scheduler Refactor Documents

Use this folder as the single home for the scheduler refactor RFC, its current
tracking, and RFC-level audits.

## Start here

1. `UnifiedCombat_scheduler_refactor_RFC_for_Codex.md` — governing refactor plan.
2. `UnifiedCombat_scheduler_refactor_tracking.md` — canonical living tracker and
   detailed task history.
3. `UnifiedCombat_scheduler_refactor_phase1_exit_audit_2026-07-24.md` — Phase 1
   exit decision and behavior-parity evidence.
4. `UnifiedCombat_scheduler_refactor_phase2_exit_audit_2026-07-24.md` — Phase 2
   dispatcher-monopoly exit decision and evidence.
5. `UnifiedCombat_scheduler_refactor_phase3_exit_audit_2026-07-24.md` — Phase 3
   provider-purity exit decision and evidence.
6. `UnifiedCombat_scheduler_refactor_tracking_audit_2026-07-24.md` — Phase 0
   implementation and tracking-accuracy audit.

## Phase 0 baselines

- `../docs/side_effect_inventory.md` — exhaustive direct and indirect execution
  surface recorded at Phase 0 closeout.
- `../docs/side_effect_allowlist.md` — human-readable guard policy and exceptions.
- `../docs/scheduler_responsibility_map.md` — current post-extraction scheduler
  ownership and responsibility map.
- `../tests/replay/harness/selftest_side_effect_inventory.lua` — repository-wide
  discovery guard.
- `../tests/replay/fixtures/shared/side_effect_allowlist.lua` — machine-readable
  exact-count allowlist.

## Historical

- `UnifiedCombat_scheduler_refactor_tracking_legacy_2026-05-25.md` — preserved
  early tracker snapshot; do not use it as the current status source.

RFC tracking and RFC-level audit documents should remain in this folder. Detailed
feature designs, field-test results, and implementation-specific audits may remain
under `docs/` when they are not the top-level RFC status source.
