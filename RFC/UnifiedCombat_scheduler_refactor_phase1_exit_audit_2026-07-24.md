# UnifiedCombat Scheduler Refactor Phase 1 Exit Audit

Date: 2026-07-24

Result: **PASS — Phase 1 complete in the current working tree**

Baseline: Phase 0 commit `3bd8d2355edb618d81bd2ef4a85f6dfa115d12a0`

Runtime behavior intent: mechanical extraction; action-selection and output
contracts unchanged. World state is now sampled once and shared within each
scheduler tick as required by the target architecture.

## Scope audited

The RFC defines Phase 1 as mechanical decomposition of
`unified_scheduler.lua`, in this order:

1. locks, pending, and action state;
2. proposal schema and helpers;
3. validation, scoring, and ranking;
4. observability and reject/top-candidate formatting;
5. enemy-effect state;
6. party IPC state if still large.

The resumed-work acceptance scope also required an explicit context builder and
one tick-stable context. Provider extraction is not a Phase 1 exit requirement;
the RFC assigns provider purity to Phase 3.

## Requirement-by-requirement result

| Requirement | Result | Evidence |
| --- | --- | --- |
| T1.1 action state, pending lifecycle, locks, and duplicate suppression | PASS | Existing extracted modules remain active: `uc_scheduler_action_state.lua`, `uc_scheduler_pending.lua`, `uc_scheduler_pending_record.lua`, and `uc_scheduler_locks.lua`. The aggregate suite exercises their fixtures and scheduler integration. |
| T1.2 proposal schema and normalization | PASS | `uc_scheduler_proposals.lua` owns identity validation, live-field normalization, created-age calculation, and engage-priority bypass policy. `selftest_scheduler_proposals.lua` pins defaults, expiry handling, normalization, and identity checks. |
| T1.3 validation, scoring, and ranking | PASS | `uc_scheduler_ranker.lua` owns proposal validation, score calculation, deterministic ordering, rejection capture/counting, and engage rank diagnostics. `selftest_scheduler_ranker.lua` pins score order, expiry/provider/proposal-id tie-breaks, score parts, rejection reasons, and engage debug output. |
| Explicit tick-context contract | PASS | `uc_scheduler_context.lua` samples time, player, self mob, target, party, and mob array through explicit dependencies and builds the mob-id index. `scheduler.process_tick` caches one context and shares it with target acquisition and dry-run collection/ranking. |
| Tick-stable provider reads | PASS | `selftest_scheduler_context.lua` proves each dependency is sampled once and derived values remain stable. `selftest_scheduler_tick_context_static.lua` proves the proposal-provider block contains no direct `windower.ffxi.get_*` or `now_s()` resampling. |
| T1.4 observability | PASS | `uc_scheduler_observability.lua` owns rank/reject formatting, dry-run publication, debug-overlay formatting, and enemy-effect overlay formatting. `selftest_scheduler_observability.lua` pins queued, rejected, buff, enemy-effect, and `_G.UC_*` publication shapes. |
| T1.5 enemy-effect state | PASS | `uc_scheduler_enemy_effect_state.lua` owns JSON catalog loading, membership/priority state, effect lifecycle, attempt throttling, raw `0x028` ingestion, removal/death classification, and unknown-effect dedupe. Focused dynamic and static tests pass. |
| Party IPC state | PASS | `uc_scheduler_party_state.lua` owns payload encoding, send throttling, receive parsing/order protection, TTL expiry, zone/name validation, and lookup. Focused dynamic and static tests pass. |
| Scheduler façade compatibility | PASS | Existing public scheduler entrypoints and compatibility wrappers remain. Runtime parsing succeeds for all 76 runtime Lua files. |

## Behavior-parity audit

### Rank order

PASS.

- `selftest_scheduler_ranker.lua` pins descending score order.
- Equal-score ordering remains earliest `expires_at`, then provider, then
  `proposal_id`.
- Existing defensive Cure, tank engage, engage dispatch, support-priority,
  skillchain, and other scheduler integration tests pass in the 109-suite
  aggregate run.

### Proposal keys

PASS.

A zero-context diff against the Phase 0 baseline found no added or removed
assignments for:

- `proposal_id`
- `family_id`
- `duplicate_suppression_key`
- `recast_key`

The existing proposal-key fixtures also pass. The extraction did not alter
provider proposal construction.

### Rejection reasons

PASS.

Focused ranker tests pin `malformed`, `settings_disabled`, `stale_snapshot`,
`pending_conflict`, `duplicate_suppressed`, and `reaction_hold`. Existing
integration coverage additionally pins engage retry, action-state, defensive,
reaction, pending, and lock rejection paths. No rejection reason was renamed by
the extraction.

### Debug and remote output

PASS.

Focused observability tests assert exact queued candidate, rejected candidate,
buff-source, enemy-effect table, dry-run global, and engage rank-loss output
strings. Existing rank-output, reject-history, and dry-run publication fixtures
also pass.

### Side-effect counts

PASS.

The repository-wide guard reports:

```text
runtime_files=125
allowlisted_files=20
pattern_checks=300
observed_hits=263
```

The observed hit total remains 263. The one scheduler party-state IPC send moved
from a direct call in `unified_scheduler.lua` to an explicitly injected call in
`uc_scheduler_party_state.lua`; the allowlist records that ownership transfer
without increasing the execution surface.

## Verification record

Passed:

- `luac -p` for the new Phase 1 modules, scheduler, and focused tests;
- `lua tests/replay/harness/selftest_runtime_parse.lua` — 76 runtime files;
- `lua tests/replay/harness/selftest_side_effect_inventory.lua`;
- focused proposal, ranker, context, enemy-state, observability, and party-state
  tests;
- affected legacy scheduler integration/static tests;
- `lua tests/replay/harness/selftest_all_replay_fixtures.lua` — 109/109 suites;
- `git diff --check`;
- diff-based proposal-key assignment audit against Phase 0.

Not performed:

- live in-game Windower soak/field testing.

## Exit decision and remaining risk

Phase 1 is complete. The current working tree meets the RFC mechanical
decomposition scope plus the explicit tick-stable-context requirement.

The primary residual risk is runtime integration under live Windower state:
sampling is intentionally consolidated to one per-tick snapshot, but automated
tests cannot reproduce every packet/timing interaction. A normal combat,
defensive, maintenance, enemy-dispel, and multi-character IPC soak is recommended
before promoting unrelated ownership or removing legacy execution paths.

Next RFC work should be selected from:

- Phase 2 dispatcher monopoly: remove remaining direct/indirect execution and
  fallback ownership paths in evidence-backed slices;
- Phase 3 provider purity: extract the still-local `p1_collect_*` providers now
  that context and ranker contracts are stable.
