# Profile V2 Phase 6 — Bounded Exit Assessment

Status: **COMPLETE — all five Phase 6 exit criteria satisfied by source-contract evidence and CI; live acceptance belongs to Phase 7**  
Assessment date: 2026-10-16  
Branch/PR: `refactor/profile-v2-single-source` / #73  
Contract: `docs/profile_v2_single_source_migration_plan.md` Phase 6 exit criteria.

## Scope and stopping rule

Phase 6 is **not** an unlimited scheduler state/lifecycle audit. It ends when its five existing configuration-authority exit criteria have evidence and any **demonstrated** violations are resolved. Pure scheduler coordination, combat heuristics, optimization, and speculative future failure modes go to a separate backlog unless they directly violate Profile V2 durable authority.

A test or source hit is not automatically a migration blocker. Identify the actual production consumer, whether canonical config is supplied, whether conflicting flat state can affect real dispatch, and whether the caller is deliberately no-config/legacy.

## Exit-criteria matrix

| Criterion | Assessment | Evidence / remaining proof |
| --- | --- | --- |
| 1. No durable runtime behavior depends on `_G.UC_SETTINGS` | **PASS — verified RUN authority and bounded residuals** | Scheduler/core, follow/path, BRD/COR/GEO/SCH/SMN/PUP and other migrated domains have prior contradictory-state suites. The RUN-specific remaining flat-first path was found in `uc_run_config.active(ctx.settings)`; this also affected generic ability filtering and RUN no-TP facing. Runtime calls now pass explicit `ctx.config` so canonical false/missing leaves cannot revive `tank_run`. Source allowlist still contains mostly legacy and runtime-shape plumbing; Residual production surfaces are classified individually in `docs/profile_v2_phase6_residual_flat_classification.md`; legacy/no-config and transient state are explicitly bounded. Full implementation-head workflow `38986661407` passed. |
| 2. No durable UI write mutates `_G.UC_SETTINGS` as truth | **PASS — automated contract, live reconnect still Phase 7** | Phase 5 structured writer/editor capture; Phase 6 bridge generic `op=set` retired, no `UC_SETTINGS` reads or writes in `remote_bridge.lua`; `selftest_phase6_bridge_generic_set_retirement.lua` and `selftest_phase6_canonical_editor_wire.lua` freeze the boundary. |
| 3. Canonical config is the only durable authority | **PASS — canonical authority regression proven** | Canonical startup, identity/defaults, apply/save, active Profile V2, canonical editor wire and domain authority regression suites exist. The RUN contradictory-state regression was added to the CI-wired RUN tests. Full Lua and WinForms verification `38986661407` proved the RUN contradictory-state regressions alongside existing Profile V2/domain-authority coverage. |
| 4. Normal runtime has no mixed flat/nested normalizer ambiguity | **PASS — source-contract and existing CI evidence, live validation Phase 7** | Startup builds canonical defaults and publishes the canonical active profile; Profile V2 apply validates a structured payload rather than publishing or normalizing a projected flat settings table. `uc_active_config.build_active_profile_from_v2_payload` still normalizes a bounded nested `compatibility_source` for pulling/WS/recurring/GEO, not a mixed flat-vs-nested live runtime snapshot. Do not mistake legacy export/normalizer compatibility for a second runtime authority. |
| 5. Compatibility surfaces are documented and bounded | **PASS — 28 residual source files classified** | The frozen and CI-enforced `profile_v2_flat_surface_allowlist.lua` prevents accidental new `UC_SETTINGS`, `ctx.settings`, or flat write seams but counts alone do not prove authority. Every remaining allowlisted source has a disposition in `docs/profile_v2_phase6_residual_flat_classification.md`; the three live slash-command writers were migrated and tested against contradictory flat state. |

## Confirmed Phase 6 blocker — RUN subdomain authority

Production code read `run_config.active(ctx.settings)` in the RUN provider and `uc_run_no_tp.enabled`; generic JA filtering read `uc_run_ownership.filter_generic_abilities(ctx.settings, ...)`. Because `uc_run_config.active` gave `settings.tank_run` priority, a stale flat mirror could override the live `config.tank.run` subtree, even while shared `tank.enabled` was canonical. This is genuine durable config competition.

Correction on PR #73: `run_config.active(settings, config)` uses only `config.tank.run` and canonical defaults **when an explicit config is supplied**. Three scheduler consumers now provide their tick-stable canonical config (RUN primary provider, generic JA ownership, and RUN no-TP facing). Genuine no-config direct/legacy callers retain the old behavior. CI-wired `selftest_run_tank.lua` and `selftest_run_no_tp_mode.lua` now oppose canonical/flat RUN enablement and no-TP state.

Status: **CI proven in workflow `38986661407`**. No new action ranking, target geometry, cooldown semantics, or pet/reaction behavior was intended.

## Bounded residual compatibility disposition

| Surface | Current classification | Exit action |
| --- | --- | --- |
| `remote_bridge.lua`, WinForms local editor/structured-writer translation | Canonical Profile V2 transport, editor-local compatibility (no addon flat republishing) | Retain; verify existing tests/WinForms CI. |
| `uc_active_config.lua`, `uc_profile_v2.lua`, canonical bootstrap | Canonical ownership, legacy export/status/build helpers | Retain if outside normal durable authority path; tests already reject retired projection/sync APIs. |
| `uc_scheduler_context_utils.get_settings`, core/scheduler `get_settings` | Contains session state, debug compatibility, legacy entrypoints | Classify remaining concrete consumers; no blanket deletion. |
| `melee_engine.lua`, `dd2_module.lua`, `build_dd2_module.py` | Legacy-sensitive engines, not the active unified scheduler path | Bound behind proven engine ownership; leave separate legacy refactor/Phase 7 unless reachable while unified ownership is active. |
| WinForms `BuildProfileFromUi` and `JsonObject flatProfile` | Editor-local intermediate translated to structured V2 at save/apply | Not a second durable store; Phase 7 architecture cleanup only. |
| Addon slash commands `//uc fight_leader`, `//uc add_priority`, `//uc sleep` | **Resolved**: all three edit active Profile V2 using `uc_profile_v2_command_edits.lua` | Preserved command entrypoints and spell/party validation; all normal runtime values come from canonical config. `selftest_phase6_slash_command_authority.lua` exercises actual canonical edits against contradictory legacy mirrors. User-triggered changes affect the active profile; explicit Profile V2 export/save remains the persistence step. |

## Exit decision and verification

**Phase 6 COMPLETE.** The five original exit criteria now pass under the agreed bounded interpretation. No unlimited pet/scheduler/reaction lifecycle audits are required to close this phase. Confirmed flat-authority conflicts (RUN and slash commands) are resolved and protected by CI. `tests/replay/fixtures/shared/profile_v2_flat_surface_allowlist.lua` allows **47** addon global-marker occurrences after retiring three slash-command flat reads; the full repository guard passed with **28** allowlisted files.

- Implementation proof (before documentation-only exit commits): [full Lua + WinForms workflow 38986661407](https://github.com/n0gr1p/UnifiedCombat/actions/runs/38986661407), commit `d009155f4cb6bde3d10066f937be8d8b4a80d40b`: **both jobs successful**.
- The source-level classification and per-file disposition are in `docs/profile_v2_phase6_residual_flat_classification.md`. Deliberately retained compatibility no longer determines normal unified runtime durable policy.
- Manual live-game acceptance and final architecture cleanup remain **Phase 7 requirements**, not retroactive Phase 6 blockers.
- Do not merge PR #73 merely because the Phase 6 code and CI are green; this PR is still unmerged and has not passed its complete live smoke suite.

## Phase 7 handoff (not new Phase 6 work)

Final source-contract audit, remaining adapter cleanup, architecture docs, complete Lua + WinForms validation, then live acceptance: profile apply/save/reload, job identity, BRD/COR/GEO/SCH/SMN/PUP, RUN/tank, healing, WS, follow/path/pull. Prior Phase 3 live checks roll into this acceptance. PR #73 remains unmerged and is **not yet a proven playable branch**.
