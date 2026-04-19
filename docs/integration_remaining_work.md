# UnifiedCombat Integration Remaining Work

Tracks remaining work to reach the target:
- one merged engine for former melee/dd2 behavior
- full HealBot feature/functionality parity inside UnifiedCombat

## Source Documents

- `docs/engine_feature_matrix.md`
- `docs/canonical_settings.md`

## Current Status Snapshot

- Unified scheduler scaffolding exists (`unified_engine.lua`, `unified_scheduler.lua`).
- Defensive preemption plumbing exists (internal + optional HealBot delegation provider).
- External UI exposes basic defensive toggles and scheduler diagnostics.
- Feature parity is **not complete** for merged engine or HealBot internals.

## Phase A - DD2 + Melee Engine Merge Completion

- [ ] Replace dual combat loops fully with one canonical tick path (remove legacy duplicated scheduling paths).
- [ ] Consolidate targeting logic into one implementation:
  - [ ] partner/puller/partner2/sub2 semantics
  - [ ] hunter/tank policy options
  - [ ] manual lock behavior
- [ ] Consolidate WS gate implementation:
  - [ ] unify range thresholds and checks
  - [ ] unify ally wait behavior
  - [ ] preserve explicit gate reason diagnostics
- [ ] Consolidate ability execution path:
  - [ ] remove duplicate job-branch JA logic where equivalent
  - [ ] keep job-specific strategy hooks only where behavior truly differs
- [ ] Consolidate sleep/debuff handling:
  - [ ] remove hardcoded spell-name assumptions
  - [ ] use configured spell/resource ids consistently
- [ ] Consolidate pet subsystems (BST/PUP/DRG/SMN) into strategy hooks with shared executor.
- [ ] Remove deprecated duplicate command variants after migration.

## Phase B - HealBot Defensive Parity (Internal Provider)

- [ ] Port cure queue scoring semantics (danger level, target priority, curaga logic).
- [ ] Port debuff-removal queue semantics (full NA/debuff mapping, retries, attempted timestamps).
- [ ] Port buff queue semantics (priority, overwrite behavior, throttling).
- [ ] Port BRD overwrite/token handling from HealBot buff subsystem.
- [ ] Port action gating semantics:
  - [ ] readiness/recast/MP-TP checks parity
  - [ ] casting/moving/acting delay gates parity
- [ ] Port defensive arbitration exactly:
  - [ ] overwrite > cure/debuff/buff tie-break rules
  - [ ] deterministic preemption over offense each tick
- [ ] Port monitored-target selection semantics (party, trust rules, ignore/watch lists as needed).

## Phase C - Command, UI, and Settings Parity

- [ ] Canonicalize settings writes to one key per concept (keep legacy read migration only).
- [ ] Add defensive scheduler state/debug surfaces to in-game status text.
- [ ] Expand external UI parity controls for defensive subsystem.
- [ ] Add explicit blocked-reason taxonomy coverage for all major gates.
- [ ] Add migration/version marker for profile schema upgrades.

## Phase D - Validation + Cutover

- [ ] Build scenario test matrix and execute:
  - [ ] SAM/DRK/WAR offensive parity
  - [ ] DD2-style jobs parity
  - [ ] critical-ally healing preemption over WS/JA
  - [ ] partner/puller edge cases
  - [ ] pet-job behavior parity
  - [ ] sleep/debuff control parity
- [ ] Validate no silent fallback behavior in all failure paths.
- [ ] Run soak period with explicit rollback toggle.
- [ ] Remove standalone HealBot dependency for UnifiedCombat users at final cutover.

## Definition of Done

- One merged engine runtime path is authoritative.
- Internal defensive provider reproduces HealBot defensive behavior with parity.
- All blocking conditions are explicit and diagnosable (no silent fallbacks).
- External UI and profiles persist canonical settings reliably across characters/jobs.
