# UnifiedCombat Profile V2 — Runtime Architecture (PR #73)

Status: **Phase 7 conformance, pending controlled live FFXI acceptance**. This document describes the `refactor/profile-v2-single-source` branch, **not** a claim that the draft PR has been merged or field-certified.

## Authority boundary

```text
WinForms session view (read-only active_config snapshots)
    └── local canonical-to-editor projection
          └── local per-session working changes / activity profile capture
                └── StructuredProfileV2Writer → data/profiles_v2/<character>_<main>_<sub>.lua
                                                 │
Windower addon startup → canonical default Profile V2
                                                 │
Exact character/main/sub identity → validate → apply / auto-reload
                                                 │
                            _G.UC_ACTIVE_PROFILE
                                ├── version = 2
                                ├── profile = exact identity + metadata
                                └── config = sole durable authority
                                          │
                             uc_active_config.get_config()
                                          │
                               scheduler tick ctx.config
                                          │
             domain owners / scheduler policy / per-job providers
                                          │
                      selected action → revalidation → dispatch
                                          │
                 packet, cooldown, pending, lock and movement state
                            (owned by runtime, NOT config)
```

## Canonical ingress and publication

- `UnifiedCombat.lua` builds a canonical Profile V2 default with `uc_active_config.build_default_active_profile` and publishes it through `uc_active_config.set_active_profile`. Startup is **not** reconstructed from the legacy `_G.UC_SETTINGS`.
- `uc_profile_v2.lua` provides structured parsing, validation, exact identity, inspection, diff and active apply. `uc_active_config.lua` owns the active canonical profile and in-place update of its configuration.
- The addon auto-load/auto-reload uses exact character/main/sub identity. Configured names remain durable; dynamically observed party/actor/target IDs are resolved at runtime.
- `uc_domain_ownership.lua` resolves canonical `config.ownership.domain_*` participation. The unified scheduler builds tick-stable `ctx.config`; legacy `ctx.settings` carries non-authoritative runtime/compatibility view values.
- Missing leaves in an existing canonical domain use canonical defaults, not stale flat toggles. Contradictory-state regressions cover combat, follow, defensive support, job domains, and RUN `config.tank.run`.

## Editor, transport, and persistence

- `remote_bridge.lua` sends the active Profile V2 as `active_config` in session state. Live transport commands for engine on/off and other runtime requests are separate from durable profile changes.
- WinForms `CanonicalRuntimeEditorProjection.cs` creates editor-oriented fields locally from canonical `active_config`. An editor field with a legacy-looking name is not a second runtime authority.
- Session edits and activity-profile capture are per-session local UI state. The generic bridge `set` operation no longer writes durable configuration into addon flat settings.
- `UnifiedCombatWinForms/StructuredProfileV2Writer.cs` serializes an exact character/main/sub structured Profile V2 file. Save in the UI is the durable boundary; selecting a form control alone is not.
- In-game commands `//uc fight_leader`, `//uc add_priority`, and `//uc sleep` edit **active canonical Profile V2** via `uc_profile_v2_command_edits.lua`. They perform runtime edits immediately, but **persistence is explicit** through Profile V2 export/save, not implicit.
- The legacy flat `UC_SETTINGS` table is not the canonical profile and must never be republished as such. It remains present for bounded legacy/no-config APIs, transient state and diagnostics.

## Runtime action and evidence ownership

`unified_scheduler.lua` is the primary scheduler-owned selection and dispatch path. `uc_provider_*.lua`, `uc_geo_maintenance.lua`, `uc_sch_skillchain_runtime.lua`, pet-command coordinators, and follow/pathing owners propose or own transient work. These are **not durable profile documents**.

| Kind of state | Owner / boundary | On policy change |
| --- | --- | --- |
| Configured priorities, action lists, jobs, thresholds, follow names, schedule gates | Profile V2 `config` | Canonical config wins; pending proposal must revalidate |
| Selected but unsent reaction/maintenance plan, atomic lane, target lock | Scheduler/provider runtime | Retire if no longer authorized |
| Already-dispatched commands, cooldowns, retry history, packet-confirmed buffs/songs/pet state | Runtime packet/observation owners | Preserve confirmed evidence and existing bookkeeping |
| Resolved party member IDs, current mob ID, camp geometry, route execution, formation position | Current FFXI/session runtime | Re-resolve from live world; do not save as durable identity |
| Emergency defense / forced reaction turn and restoration | Defensive reaction runtime | Preserve valid safety actions independently of discretionary durable policy |
| Engine started/stopped / bridge connection | Session/runtime | Do not confuse with durable engine-enable default in Profile V2 |

Explicitly preserving observations avoids false negatives when a profile is changed while a previously issued spell or pet command is still completing.

## Bounded compatibility inventory

- All remaining source-file flat identifiers were classified in `docs/profile_v2_phase6_residual_flat_classification.md`; the tracked source-count guard fails if the allowed compatibility footprint unexpectedly grows.
- `melee_engine.lua` and `dd2_module.lua` retain their legacy APIs but are **not active unified scheduler choices**. Removing them is not necessary to prove canonical behavior.
- Local flat-name editor intermediates and the legacy profile-file import support still exist because they serve compatibility; they must not become active durable authority.
- The **unreachable** flat-profile capture/apply functions and their exclusive normalizers were removed in Phase 7. No active-profile file reader/export/write lifecycle is removed by that cleanup.
- Obsolete `uc_active_config.project_flat_settings` and `sync_flat_settings_in_place` APIs were removed in Phase 6; tests enforce that boundary.

## Verification and merge contract

1. CI: full Lua sequence (parser, replay, source guard, canonical-authority regressions), WinForms build, Profile V2 persistence and activity-profile suites.
2. Controlled field acceptance: exact startup/identity and profile save/reload, then low-risk maintenance and support, followed by movement and combat/provider sequencing. Capture real packet/action diagnostics rather than relying only on in-game chat.
3. Rollback: maintain a separate known-working `master` addon installation and backed-up character profiles. Do not deploy PR #73 in place over the active setup merely because CI passes.
4. PR #73 stays draft/unmerged until the full Phase 7 live acceptance matrix in `docs/profile_v2_phase7_acceptance_plan.md` is completed and the reviewer signs off.

**Phase 6 completion and code correctness do not alone certify playable behavior.** File all field regressions as specific testable defects instead of expanding the migration into unlimited audits.
