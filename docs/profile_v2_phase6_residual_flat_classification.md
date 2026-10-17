# Phase 6 — Residual Flat-Reference Disposition

Scope: PR #73, verified against the Phase 6 five-point exit contract on 2026-10-16. This is a **finite classification of the remaining non-test source files** listed in `tests/replay/fixtures/shared/profile_v2_flat_surface_allowlist.lua`, not an attempt to remove every textual legacy marker.

## Read this classification correctly

- **C** = canonical normal-run path; flat argument is a compatibility signature, session observation, or diagnostic, and does not select durable policy when `ctx.config` exists.
- **S** = runtime/session mutable state, intentionally non-durable.
- **L** = legacy/no-config compatibility owner; not the unified scheduler's normal Profile V2 durable policy source.
- **E** = editor-local compatibility shape; serializes structured Profile V2 instead of publishing the flat intermediate into the addon.
- **M** = metadata string or source label only.
- **R** = retained runtime gate/bridge that must remain non-authoritative; already constrained by the canonical tests cited below.

Every allowlisted source is assigned below. A literal count alone is not proof of live dependency.

| Source | Classification | Rationale and disposition |
| --- | --- | --- |
| `UnifiedCombat.lua` | C/S/L/M | Publishes canonical startup `UC_ACTIVE_PROFILE.config`; active profile V2 apply/save runs from canonical. Remaining global references are legacy profile tree normalization/capture helpers, availability checks, status/source labels, runtime recovery/participation plumbing and explicit Profile V2 compatibility arguments. Local `uc_capture_active_profile` and `uc_apply_active_profile` have no callers in this file. The formerly flat-only fight-leader/add-priority/Sleep slash mutations now call `uc_profile_v2_command_edits`; authoritative edits do not write the global mirror. |
| `uc_active_config.lua` | M/C | The two `UC_SETTINGS` strings are metadata/source labels. Retired canonical→flat projection and flat sync APIs stay absent under Phase 6 tests. |
| `uc_config_runtime.lua` | M | Source-label literals in diagnostic defaults, not global policy reads. |
| `uc_config_normalizer_base.lua` | M/L | Legacy source name default inside a normalizer; normal Profile V2 apply uses structured canonical payload, not mixed flat context. |
| `uc_combat_extension_config.lua` | L/C | Global fallback exists for explicit no-profile compatibility readers. Scheduler extension path passes canonical `ctx.config` into `auto_engage_enabled_from_config`/`magic_burst_from_config`. |
| `uc_runtime_overrides.lua` | L/C | Public no-profile compatibility fallback. With a canonical active config, fight leader and targeting/Sleep reads use `config.follow.fight`, `config.targeting.targets`, `config.sleep.*`; slash commands now write those leaves directly. |
| `uc_scheduler_config.lua` | L/C | Legacy wrappers retain no-config fallback but check active canonical domain first; ordinary scheduler providers use `*_from_config(ctx.config)` helpers. Canonical false/missing-leaf regressions cover the boundary. |
| `uc_scheduler_context_utils.lua` | S/C | `get_settings()` remains a session/legacy snapshot accessor. `get_config()` returns applied canonical config; targeting/facing gates explicitly accept canonical config and fail closed on durable false. |
| `unified_engine.lua` | S/C | `get_settings()` retained for runtime engine/overlay state; overlay durable visibility uses active debug policy. |
| `unified_combat_core.lua` | S/C/L | Legacy accessors and scheduler settings views carry live/session coordinates, range and route state. Scheduler-facing movement, facing, WS and pull calls receive explicit canonical `config`. Do not remove runtime state just to eliminate an identifier. |
| `uc_party_follow.lua` | S/C | Flat handle is used for legacy signatures/session presence and telemetry. `party_follow_enabled(_)` ignores its flat argument; `active_follow_config()` reads canonical. Configured durable names are resolved to live IDs separately. |
| `uc_pathing.lua` | S/C | Global `UC_SETTINGS` provides path recording/route-file/session/UI machinery and follow-suppression legacy signature. Movement ownership and configured path/follow policy come from canonical config. Route points/files are not Profile V2 durable configuration. |
| `unified_scheduler.lua` | S/C | Two `ctx.settings` tokens and the `get_settings()` accessor remain, mainly for context/session and compat helper signatures; scheduler context samples `ctx.config` from Profile V2. Dispatch-plan/revalidation gates pass the canonical config; debug/turn/recovery observations remain runtime state. |
| `uc_combat_commitment.lua` | C | Single `ctx.settings` pass-through to dependency injection for prime/unclaimed target check; canonical `ctx.config` owns the live prime/fight-leader policy in the injected scheduler implementation. |
| `uc_combat_extensions_base.lua` | C/L | Skillchain burst collection uses `magic_burst_from_config(ctx.config)` whenever scheduler supplies canonical context; only explicit no-config callers get legacy fallback. |
| `uc_provider_combat.lua` | C/S | Remaining `ctx.settings` is passed alongside `ctx.config` to WS/partner/pull helpers or diagnostics. Generic RUN JA exclusion now explicitly passes `ctx.config`. Provider durable gates use canonical config. |
| `uc_provider_run_tank.lua` | C | RUN automation now calls `run_config.active(ctx.settings, ctx.config)`, so stale flat `tank_run` cannot override `config.tank.run`; RUN contradicted-state suite is in CI. |
| `uc_provider_tank_enmity.lua` | C | Calls pet/normal enmity selectors with `ctx.config`; active policy is canonical `config.tank.enmity` and generic ownership. |
| `uc_provider_target_control.lua` | C | Calls target/pull selectors with `ctx.config` and uses canonical engagement/autotarget gates. |
| `uc_scheduler_dispatch_plan.lua` | C | WS safety/skillchain revalidation passes both legacy settings for helper interface compatibility and `ctx.config` for durable policy. |
| `uc_scheduler_ranker.lua` | C/S | Two surviving settings arguments go to canonical-aware debug and critical-defensive classifiers; prioritization cannot acquire a durable setting from a bare `ctx.settings` missing a canonical contract. |
| `melee_engine.lua` | L | Legacy engine with direct global flat proxy and old config save/reload actions. Outside the unified engine's owned scheduler path; separately legacy-sensitive and not converted into Profile V2 during Phase 6. |
| `dd2_module.lua` | L | Same legacy module/proxy semantics; not promoted as active unified scheduler authority. |
| `build_dd2_module.py` | L | Source generator for legacy DD2 flat proxy, not a runtime Profile V2 reader. |
| `UnifiedCombatWinForms/MainForm.ActivityProfiles.cs` | E | Editor-local BuildProfileFromUi capture; activity profile persistence uses structured Profile V2. |
| `UnifiedCombatWinForms/MainForm.ParityLogic.cs` | E | Legacy local UI `op=set` events are intercepted locally and capture structured working Profile V2; the bridge never receives generic durable set messages. |
| `UnifiedCombatWinForms/MainForm.ProfileStore.cs` | E | Flat-named intermediate editor shape, structured persistence writer and canonical profile apply. |
| `UnifiedCombatWinForms/StructuredProfileV2Writer.cs` | E | Converts editor intermediate to structured Profile V2 on the only durable save boundary. Does not publish an alternate live flat configuration source. |

## Source and behavioral checks

- `selftest_profile_v2_flat_surface_guard.lua`: exact per-file residue inventory; new or expanded flat surface fails CI. Addon global-marker baseline is reduced from **50 to 47** following slash-command conversion.
- `selftest_phase6_initial_canonical_bootstrap.lua`, `selftest_phase6_flat_projection_api_retirement.lua`, `selftest_phase6_profile_apply_publication_retirement.lua`: canonical startup/apply and retired publication.
- `selftest_phase6_bridge_generic_set_retirement.lua`, `selftest_phase6_canonical_editor_wire.lua`: UI/bridge canonical write path.
- `selftest_phase2_canonical_authority.lua`, Phase 3 and 4 authority suites: intentionally contradictory canonical-vs-flat runtime behavior.
- `selftest_run_tank.lua` and `selftest_run_no_tp_mode.lua`: RUN canonical policy now beats a contradictory flat mirror.
- `selftest_phase6_slash_command_authority.lua`: in-game configuration commands now change canonical policy and never mutate the legacy flat mirror.

## Explicitly out of Phase 6

- Retiring legacy melee/DD2 engines or converting route-file/session state to profiles.
- Rewriting WinForms' local intermediate representation solely because it has flat-looking field names.
- Generic scheduler reservation, combat AI, action arbitration, or movement optimization audits unrelated to durable source-of-truth.
- Live game acceptance, which remains a separate **Phase 7** merge prerequisite.

Classification is based on the active production call paths and existing canonical-authority regression coverage, not on removal of all compatibility code. If a failing test demonstrates a flat value can override canonical policy on the unified runtime path, it reopens that **specific** Phase 6 blocker; it does not reopen unlimited audits.
