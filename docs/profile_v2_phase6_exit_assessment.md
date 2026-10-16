# Profile V2 Phase 6 — Bounded Exit Assessment

Status: **OPEN — migration-specific blockers only**  
Assessment date: 2026-10-16  
Branch/PR: `refactor/profile-v2-single-source` / #73  
Contract: `docs/profile_v2_single_source_migration_plan.md` Phase 6 exit criteria.

## Scope and stopping rule

Phase 6 is **not** an unlimited scheduler state/lifecycle audit. It ends when its five existing configuration-authority exit criteria have evidence and any **demonstrated** violations are resolved. Pure scheduler coordination, combat heuristics, optimization, and speculative future failure modes go to a separate backlog unless they directly violate Profile V2 durable authority.

A test or source hit is not automatically a migration blocker. Identify the actual production consumer, whether canonical config is supplied, whether conflicting flat state can affect real dispatch, and whether the caller is deliberately no-config/legacy.

## Exit-criteria matrix

| Criterion | Assessment | Evidence / remaining proof |
| --- | --- | --- |
| 1. No durable runtime behavior depends on `_G.UC_SETTINGS` | **PROVISIONAL — demonstrated RUN blocker patched; verification in progress** | Scheduler/core, follow/path, BRD/COR/GEO/SCH/SMN/PUP and other migrated domains have prior contradictory-state suites. The RUN-specific remaining flat-first path was found in `uc_run_config.active(ctx.settings)`; this also affected generic ability filtering and RUN no-TP facing. Runtime calls now pass explicit `ctx.config` so canonical false/missing leaves cannot revive `tank_run`. Source allowlist still contains mostly legacy and runtime-shape plumbing; finish semantic classification rather than simply deleting occurrences. |
| 2. No durable UI write mutates `_G.UC_SETTINGS` as truth | **PASS — automated contract, live reconnect still Phase 7** | Phase 5 structured writer/editor capture; Phase 6 bridge generic `op=set` retired, no `UC_SETTINGS` reads or writes in `remote_bridge.lua`; `selftest_phase6_bridge_generic_set_retirement.lua` and `selftest_phase6_canonical_editor_wire.lua` freeze the boundary. |
| 3. Canonical config is the only durable authority | **PROVISIONAL — RUN fix needs CI proof** | Canonical startup, identity/defaults, apply/save, active Profile V2, canonical editor wire and domain authority regression suites exist. The RUN contradictory-state regression was added to the CI-wired RUN tests. This criterion passes when focused/full CI confirms the fix and no other proven production flat-first path remains. |
| 4. Normal runtime has no mixed flat/nested normalizer ambiguity | **PASS — source-contract and existing CI evidence, live validation Phase 7** | Startup builds canonical defaults and publishes the canonical active profile; Profile V2 apply validates a structured payload rather than publishing or normalizing a projected flat settings table. `uc_active_config.build_active_profile_from_v2_payload` still normalizes a bounded nested `compatibility_source` for pulling/WS/recurring/GEO, not a mixed flat-vs-nested live runtime snapshot. Do not mistake legacy export/normalizer compatibility for a second runtime authority. |
| 5. Compatibility surfaces are documented and bounded | **OPEN — finish explicit contract classification** | The frozen and CI-enforced `profile_v2_flat_surface_allowlist.lua` prevents accidental new `UC_SETTINGS`, `ctx.settings`, or flat write seams but counts alone do not prove authority. Classify residual direct references by actual call sites and disposition; treat old slash-command handlers explicitly below. |

## Confirmed Phase 6 blocker — RUN subdomain authority

Production code read `run_config.active(ctx.settings)` in the RUN provider and `uc_run_no_tp.enabled`; generic JA filtering read `uc_run_ownership.filter_generic_abilities(ctx.settings, ...)`. Because `uc_run_config.active` gave `settings.tank_run` priority, a stale flat mirror could override the live `config.tank.run` subtree, even while shared `tank.enabled` was canonical. This is genuine durable config competition.

Correction on PR #73: `run_config.active(settings, config)` uses only `config.tank.run` and canonical defaults **when an explicit config is supplied**. Three scheduler consumers now provide their tick-stable canonical config (RUN primary provider, generic JA ownership, and RUN no-TP facing). Genuine no-config direct/legacy callers retain the old behavior. CI-wired `selftest_run_tank.lua` and `selftest_run_no_tp_mode.lua` now oppose canonical/flat RUN enablement and no-TP state.

Status: **implementation committed; CI validation required before exit**. No new action ranking, target geometry, cooldown semantics, or pet/reaction behavior was intended.

## Bounded residual compatibility disposition

| Surface | Current classification | Exit action |
| --- | --- | --- |
| `remote_bridge.lua`, WinForms local editor/structured-writer translation | Canonical Profile V2 transport, editor-local compatibility (no addon flat republishing) | Retain; verify existing tests/WinForms CI. |
| `uc_active_config.lua`, `uc_profile_v2.lua`, canonical bootstrap | Canonical ownership, legacy export/status/build helpers | Retain if outside normal durable authority path; tests already reject retired projection/sync APIs. |
| `uc_scheduler_context_utils.get_settings`, core/scheduler `get_settings` | Contains session state, debug compatibility, legacy entrypoints | Classify remaining concrete consumers; no blanket deletion. |
| `melee_engine.lua`, `dd2_module.lua`, `build_dd2_module.py` | Legacy-sensitive engines, not the active unified scheduler path | Bound behind proven engine ownership; leave separate legacy refactor/Phase 7 unless reachable while unified ownership is active. |
| WinForms `BuildProfileFromUi` and `JsonObject flatProfile` | Editor-local intermediate translated to structured V2 at save/apply | Not a second durable store; Phase 7 architecture cleanup only. |
| Addon slash commands `//uc fight_leader`, `//uc add_priority`, `//uc sleep` | **Potential user-visible compatibility regression**: still mutate/list flat settings while live owners are canonical | Validate documented public command contract; either migrate commands to canonical Profile V2 editing or explicitly deprecate/replace them before final live acceptance. Do not count their flat-only writes as functional Profile V2 edits. |

## Limited remaining Phase 6 tasks

1. Verify current-head Lua and WinForms CI including both RUN contradictory-state suites.
2. Complete **one bounded** residual flat-read/writer disposition table with explicit normal scheduler versus legacy/no-config caller proof. Correct only reproducible canonical-authority conflicts.
3. Resolve the exposed slash-command compatibility question by contract/reachability, without launching unrelated scheduler audits.
4. When all five exit criteria are backed by evidence, mark Phase 6 complete and begin Phase 7. Do not add new open-ended provider audits merely because cached state exists.

## Phase 7 handoff (not new Phase 6 work)

Final source-contract audit, remaining adapter cleanup, architecture docs, complete Lua + WinForms validation, then live acceptance: profile apply/save/reload, job identity, BRD/COR/GEO/SCH/SMN/PUP, RUN/tank, healing, WS, follow/path/pull. Prior Phase 3 live checks roll into this acceptance. PR #73 remains unmerged and is **not yet a proven playable branch**.
