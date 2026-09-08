# Scheduler Refactor RFC and Tracking Accuracy Audit

Date: 2026-07-24
Audited commit: `ff5a56ced0158b1bdabb9413c168de5c0be6b523`
Primary RFC: `RFC/UnifiedCombat_scheduler_refactor_RFC_for_Codex.md`
Historical tracker audited: `RFC/UnifiedCombat_scheduler_refactor_tracking_legacy_2026-05-25.md`
Canonical tracker audited: `RFC/UnifiedCombat_scheduler_refactor_tracking.md`

## Post-audit remediation

**2026-09-07 clock resolution:** the previously documented scheduler/skillchain clock conflict is resolved. UnifiedCombat runtime timing is standardized on the socket-backed `uc_time` source, and a static replay guard rejects runtime `os.clock` and direct `socket.gettime()` calls outside that module.

Phase 0 findings were resolved on 2026-07-24 after the point-in-time audit:

- `docs/side_effect_inventory.md` now records the current execution surface;
- `docs/side_effect_allowlist.md` now documents the executable guard policy;
- `docs/scheduler_responsibility_map.md` now maps the post-extraction scheduler;
- `tests/replay/harness/selftest_side_effect_inventory.lua` now discovers every
  non-test Lua file and checks 14 direct and indirect execution patterns against
  `tests/replay/fixtures/shared/side_effect_allowlist.lua`;
- `RFC/UnifiedCombat_scheduler_refactor_tracking.md` now begins with an
  authoritative phase board and marks historical snapshots explicitly.

The original audit findings below remain useful as a record of the state that
prompted remediation. The current Phase 0 status is `DONE`; later RFC phases retain
the audited statuses.

## Executive finding

The repository has advanced far beyond the named `RFC/` tracking document, but it has not completed the RFC architecture.

The current implementation is a mature hybrid:

- replay and static coverage are broad and currently green;
- action-state, pending, lock, dispatch-plan, dispatcher-contract, formatting, and ownership helper seams exist;
- many scheduler-side command, target, turn, and run-stop seams have been promoted to dispatcher-first execution;
- runtime parity and field-validation work extends well beyond the original RFC backlog;
- provider collection, proposal validation, scoring, ranking, enemy-effect state, movement execution, and significant observability logic remain in or behind `unified_scheduler.lua`;
- dispatcher monopoly is not complete because direct execution and direct fallback behavior remain;
- core fallback remains available and domain ownership settings still default off in source;
- the scheduler does not build one shared tick-stable context for the whole engine tick;
- the newer skillchain work deliberately uses `os.clock`, which conflicts with the RFC wall-clock invariant.

At the start of the audit, the named tracker was not accurate enough to resume
work from. The larger tracker then under `docs/` contained much more history, but
its summary board was internally contradictory and behind the current repository.
That larger tracker is now the corrected canonical tracker under `RFC/`.

## Repository and verification baseline

- Git status before the audit: clean.
- Current branch: `scheduler-refactor`.
- Current `unified_scheduler.lua`: 8,398 lines / 326,364 bytes.
- RFC observed `unified_scheduler.lua` at approximately 5,300 lines.
- Lua runtime: Lua 5.1.
- Runtime parse self-test: pass, 70 runtime files.
- Side-effect discovery guard after remediation: pass, 119 non-test Lua files
  scanned / 19 allowlisted files / 14 patterns / 266 exact file-pattern checks /
  263 observed hits.
- Aggregate replay self-test: pass, 99 suites.

Passing replay/static tests prove the current checked seams remain internally consistent. They do not prove that dispatcher monopoly, provider purity, movement monopoly, or legacy cutover is complete.

## RFC phase status

| RFC phase | Audited status | Evidence and qualification |
| --- | --- | --- |
| Phase 0 — Baseline and guardrails | `DONE after remediation` | The inventory, responsibility map, allowlist, canonical tracker, and repository-wide static discovery guard were refreshed on 2026-07-24. |
| Phase 1 — Mechanical decomposition | `PARTIAL` | Locks, pending, action state, dispatch-plan, rank-output, reject-history, numeric, metadata, command-builder, context, target, maintenance, defensive, and other helpers were extracted. Proposal validation/scoring/ranking, provider collection, enemy-effect state, much observability, context construction, and tick orchestration remain in `unified_scheduler.lua`. |
| Phase 2 — Dispatcher monopoly | `IN PROGRESS` | `uc_scheduler_dispatcher.lua` and command/target/turn/run/run-stop ownership helpers are live and tested. Many call sites are promoted default-on. Doom command/run-stop remain default-off and vector run remains dormant. Ownership helpers retain direct execution when disabled and direct fallback after dispatcher failure, so there is not one executor. |
| Phase 3 — Provider purity | `NOT STARTED structurally` | All primary `p1_collect_*` provider functions remain local to `unified_scheduler.lua`. The RFC provider modules do not exist. Scheduler ownership of a domain is not the same as provider extraction/purity. |
| Phase 4 — Movement ownership cleanup | `IN PROGRESS / FAR FROM COMPLETE` | Several scheduler run-stop seams use dispatcher ownership helpers. The main coordinator still delegates to `unified_combat_core.apply_movement_for_scheduler`, whose movement implementation calls Windower directly. `uc_party_follow.lua`, `uc_pathing.lua`, `uc_nyzul_runtime.lua`, and `UnifiedCombat.lua` also retain direct movement calls. |
| Phase 5 — Domain cutover | `PARTIAL` | Scheduler ownership paths and extensive field-test/promotion records exist. Source defaults for `scheduler_dark_launch_*` remain false, `unified_engine.lua` still permits the core combat tick when combat is not scheduler-owned, and legacy/direct paths remain. Exact RFC domain cutover checklist files were not created. |
| Phase 6 — Cleanup and simplification | `NOT STARTED` | No broad legacy fallback retirement or scheduler simplification has occurred. The scheduler is substantially larger than the RFC snapshot because new behavior was added while extraction remained incomplete. |

## RFC invariant audit

### One executor rule — not met

`uc_scheduler_dispatcher.lua` validates and executes injected dependencies, but it does not own all side-effect APIs.

Current exceptions include:

- ownership helpers call the injected direct function when ownership is disabled;
- ownership helpers call the direct function again when dispatcher execution fails;
- `unified_combat_core.lua` retains direct command, target, turn, and movement calls;
- `uc_party_follow.lua` and `uc_pathing.lua` retain direct movement;
- `uc_add_control.lua` retains direct attack/target command emission;
- `UnifiedCombat.lua` retains a direct movement stop;
- `uc_attack` side effects are invoked by scheduler target/engage paths outside `uc_scheduler_dispatcher.lua`;
- scheduler-owned skillchain WS dispatch sends from `unified_combat_core.lua`.

The current ownership helpers are dispatcher-first compatibility seams, not dispatcher monopoly.

This also conflicts with the current repository instruction not to use fallback patterns. Future implementation should not add more direct fallback seams. Existing fallback removal must be handled as an explicit, runtime-sensitive migration.

### Provider purity rule — not structurally met

The following collectors remain in `unified_scheduler.lua`:

- `p1_collect_defensive_internal`
- `p1_collect_defensive_healbot`
- `p1_collect_combat_offense`
- `p1_collect_enemy_buff_removal`
- `p1_collect_combat_engage`
- `p1_collect_target_control`
- `p1_collect_pull_control`
- `p1_collect_combat_tank_enmity`
- `p1_collect_combat_ja`
- `p1_collect_maintenance`

The collectors primarily emit proposals, which is directionally correct, but the RFC provider module boundary has not been created.

### One primary action per tick — mostly met inside ranked dispatch

The ranked scheduler selects one proposal and dispatches one primary path. Doom emergency, partner arbitration, target acquisition, Bard lane behavior, and movement are separate pre-ranked or adjacent paths, so the broader runtime still has multiple side-effect authorities around the ranked primary lane.

### No stale action rule — partially met, not fail-fast

Current proposals generally populate `created_at`, `expires_at`, `commit_deadline`, and duplicate keys. Commit revalidation rejects expired proposals.

However, `p1_validate_proposal` supplies defaults when `created_at`, `expires_at`, and `commit_deadline` are absent instead of rejecting the malformed proposal. This hides schema violations and does not satisfy the RFC wording that every candidate must carry the fields.

### Wall-clock rule — scheduler mostly compliant, skillchain exception conflicts

The scheduler, engine, core movement timing, and party-follow timing use LuaSocket wall time for their normal scheduling paths.

The scheduler-owned WS skillchain runtime deliberately uses `os.clock` in `unified_combat_core.lua`, and tests explicitly pin that choice. The later skillchain documents call this the approved monotonic local clock, while the scheduler RFC explicitly forbids new `os.clock` scheduler decisions.

This is a specification conflict, not an undocumented accident. Before claiming RFC completion, either:

1. amend the scheduler RFC with a narrowly scoped skillchain-clock exception, including why Lua 5.1 `os.clock` is safe in Windower; or
2. migrate skillchain timing to the RFC-approved clock after proving equivalent timing behavior.

### Tick-stable context target — not met

`unified_engine.lua` supplies a tick timestamp to `scheduler.process_tick`, but the scheduler does not use that value as the shared context time.

`p1_try_nonblocking_target_acquire` and `p1_run_dry` each call `p1_build_ctx`, which resamples player, party, mob array, and time and increments the phase tick. The selected proposal is then dispatched through additional live reads. The target `one tick-stable world/context snapshot` architecture is therefore not present.

### Compatibility invariants — substantially met

- Lua 5.1 parse validation passes.
- Existing `scheduler_dark_launch_*` keys remain.
- Source defaults remain available.
- `_G.UC_*` debug/ownership signals remain extensive.
- Engine cadence remains 0.20 seconds.

## Historical 2026-05-25 tracker accuracy

File: `RFC/UnifiedCombat_scheduler_refactor_tracking_legacy_2026-05-25.md`
Last repository update: 2026-05-25

| Claim | Verdict | Current evidence |
| --- | --- | --- |
| Current focus is non-runtime replay harness work | `FALSE / STALE` | Substantial runtime ownership, movement arbitration, defensive, engage, profile/config, Bard, skillchain, formation, partner arbitration, and camp-anchor work followed. |
| Harness foundation is done | `ACCURATE` | Files exist and current self-tests pass. |
| Listed parser/helper fixtures are done | `ACCURATE BUT INCOMPLETE` | Listed suites pass, and many more suites now exist. |
| Dispatcher ownership migration is not started | `FALSE` | Dispatcher and ownership helper modules are wired into live scheduler paths; many seams are promoted default-on. Correct status is `IN PROGRESS`. |
| Provider extraction/cutover is not started | `ACCURATE for extraction` | Provider collectors remain in the scheduler and RFC provider modules do not exist. Domain runtime ownership work did occur, so “cutover” should not be conflated with provider extraction. |
| Movement ownership runtime migration is not started | `FALSE` | Run-stop ownership helpers and promoted scheduler movement stop seams exist. Broader movement monopoly remains incomplete. Correct status is `IN PROGRESS`. |
| Domain cutover/fallback removal is not started | `PARTLY FALSE` | Ownership promotion and field-test work exists, but source defaults and fallback/direct paths remain. Correct status is `IN PROGRESS`, with fallback retirement incomplete. |
| Target/action-state/locks/rank-output/pending/reject-history fixtures are future opportunities | `FALSE / COMPLETED` | Those modules and fixture suites now exist and pass. |
| Update log is a living record | `FALSE` | It contains only the 2026-05-25 initial entry. |

Conclusion: retain this file only as a historical snapshot or replace it with a pointer to one canonical tracker. It should not remain a second living tracker.

## Canonical tracker accuracy

File: `RFC/UnifiedCombat_scheduler_refactor_tracking.md`
Last repository update: 2026-07-20

The newer tracker is much more useful as historical evidence, but it is not a reliable current status board.

Accurate content:

- it records the ownership helper and promotion sequence in considerable detail;
- it records replay, field-test, and runtime parity work;
- its latest WS skillchain completion summary is supported by dedicated audit and result documents;
- most per-task file and validation notes are plausible and are backed by present files/tests.

Material inaccuracies or contradictions:

1. The Progress Board says the dispatcher contract is not wired into scheduler side-effect execution, while later rows and live code show dispatcher execution ownership and promoted seams.
2. The same board says dispatcher ownership migration is `NOT STARTED`; it is clearly `IN PROGRESS`.
3. The same board says movement ownership migration is `NOT STARTED`; scheduler run-stop ownership migration is clearly in progress.
4. The board says domain cutover/fallback removal is `NOT STARTED`; ownership promotion and field acceptance exist, although fallback retirement is incomplete.
5. The WS skillchain section is marked field verified, but its embedded “Next step” still asks for the already completed post-reload capture.
6. The tracker records 67 parsed runtime files and 95 aggregate suites for its latest checkpoint. Current verification is 70 runtime files and 99 suites.
7. Commits dated 2026-07-22 and 2026-07-24 are not represented, including scheduler partner arbitration changes and shared camp-anchor work.
8. The document mixes current status, historical log, unrelated profile/config migration, runtime bug fixes, and field notes in one 2,430-line file. Old status rows were not retired when later work superseded them.

Conclusion: this file is valuable as an append-only history but needs a small authoritative status section regenerated from current code. Historical task notes should not double as the current progress board.

## Guardrail quality finding at audit start (resolved)

At the start of the audit, `tests/replay/harness/selftest_side_effect_inventory.lua`
was useful but narrower than its name suggested.

It:

- checks exact line-number baselines for known files;
- checks only literal `windower.send_command(`, `windower.ffxi.run(`, and `uc_settarget.select_by_id(` patterns;
- does not discover a new Lua file containing a side effect;
- does not check `windower.ffxi.turn(`;
- does not check `windower.send_ipc_message(`;
- does not identify indirect side effects through `uc_attack`;
- does not inspect direct `input /attack`, `/ma`, `/ja`, or `/ws` construction unless it also uses the tracked literal call.

That implementation did not complete a comprehensive side-effect guard. The
post-audit replacement resolves this Phase 0 finding through repository-wide
discovery, broader direct and indirect patterns, and an explicit exact-count
allowlist.

## Recommended resumption order

1. **Maintain one compact authoritative status board in `RFC/`.**
   - Keep `RFC/UnifiedCombat_scheduler_refactor_tracking.md` as the canonical tracker.
   - Preserve the larger task history there, but regenerate a compact current status board tied directly to RFC phases and invariants.
   - Keep the 2026-05-25 file clearly labeled as a historical snapshot.

2. **Resolve the clock specification conflict before more scheduler timing work.**
   - Record whether skillchain timing is an approved exception to the RFC wall-clock rule.
   - Do not leave both documents claiming incompatible invariants.

3. **Resume Phase 1 decomposition before adding scheduler behavior.**
   - Extract proposal schema/normalization without changing fields.
   - Extract validation/scoring/ranking unchanged.
   - Make strict missing-field rejection a separate behavior task with fixtures.
   - Extract enemy-effect state.
   - Build one explicit tick context contract before provider extraction.

4. **Finish dispatcher monopoly in small explicit slices.**
   - Inventory indirect executors, including `uc_attack` and skillchain WS send.
   - Remove direct fallback behavior only through separately field-tested slices.
   - Do not add new fallback patterns.

5. **Extract providers after the context and ranker contracts are stable.**
   - Defensive, combat, tank, maintenance, target/pull, and enemy-effect providers should emit proposals only.

6. **Treat movement as its own high-risk workstream.**
   - Decide ownership for coordinator, core movement, follow, pathing, Nyzul, formation, and lifecycle stops.
   - Migrate one reachable path at a time with run/stop side-effect counts and field evidence.

7. **Retire domain fallback only after ownership is default-on and proven.**
   - Keep combat, defensive, maintenance, and movement cutover evidence separate.

## Immediate recommended next task

Phase 0 is complete. The safest next code task is a behavior-preserving extraction
of proposal schema/normalization and proposal validation/scoring/ranking. Do not
combine that extraction with stricter validation, dispatcher fallback removal,
provider extraction, or new runtime behavior.

## Known limits of this audit

- No live Windower/FFXI field session was executed.
- Existing field-result documents were inspected as repository evidence, not independently reproduced.
- Replay/static success does not validate in-game timing, movement smoothness, packet ordering, or multibox behavior.
- The initial audit did not modify runtime code. Its Phase 0 remediation changed
  documentation and replay/static guard files only; addon runtime code remains
  unchanged.
