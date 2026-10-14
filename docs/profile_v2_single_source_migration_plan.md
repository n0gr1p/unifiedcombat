# Profile V2 Single-Source Migration Plan

Status: **Active working document**  
Branch: `refactor/profile-v2-single-source`  
Started: 2026-10-02  
Last updated: 2026-10-04

## Purpose

UnifiedCombat already treats Profile V2 as the durable profile format and `_G.UC_ACTIVE_PROFILE.config` as the canonical applied configuration, but a large amount of runtime and UI compatibility plumbing still relies on the legacy flat `_G.UC_SETTINGS` shape.

The goal of this migration is to make Profile V2 the single authoritative durable configuration model end-to-end, while preserving runtime behavior and keeping runtime-only state out of durable profiles.

This is a controlled migration, not a wholesale rewrite. Each phase should remain small, reversible, testable, and reviewable.

## Why this work exists

The food/Bard investigation exposed a structural weakness in the current compatibility model: one part of the system can be represented as nested Profile V2 while another part is still represented as flat compatibility fields. Normalization then has to guess which representation is authoritative.

That mixed-shape model allows unrelated configuration domains to interfere with each other. A concrete example is maintenance normalization: introducing a nested `maintenance.food` subtree can cause legacy flat BRD fields to be ignored if the normalizer treats the whole maintenance domain as nested.

The target architecture must make that class of failure impossible.

## Target architecture

The intended configuration flow is:

```text
WinForms editor / activity source
        |
        v
Profile V2 structured config
        |
        v
validation + canonical apply
        |
        v
_G.UC_ACTIVE_PROFILE.config
        |
        +--> runtime consumers
        |
        +--> read-only diagnostics/editor projection as needed
```

There should not be a second durable configuration source.

The long-term model is:

- `data/profiles_v2/*.lua` is the durable configuration source.
- `_G.UC_ACTIVE_PROFILE.config` is the authoritative applied runtime configuration.
- Runtime consumers read canonical nested config directly.
- Runtime-only state remains separate from Profile V2.
- UI edits to durable configuration flow through Profile V2 rather than a parallel flat live-write path.
- `_G.UC_SETTINGS` is retired as a durable configuration authority.
- Compatibility wrappers may remain temporarily, but they must not influence durable configuration semantics after their consumers are migrated.

## Non-goals

This migration must not accidentally absorb runtime state into Profile V2.

Examples of state that must remain non-durable include:

- engine running/stopped state;
- current target IDs and snapshots;
- resolved partner/follow/puller IDs;
- action locks, pending actions, cooldown state, and scheduler ownership;
- live camp coordinates and camp journey state;
- path progress and current route cursor;
- BRD observed song timers/recipients;
- current pet state and observed burden;
- transient reaction windows;
- temporary diagnostics and log state.

The migration is also not an excuse to rewrite scheduler behavior, ranking, action ownership, movement semantics, or combat logic.

## Migration rules

1. **Canonical-first is not the finish line.** A reader that uses canonical config but silently falls back to flat config is still a migration target.
2. **No mixed-domain guessing.** Normalizers should not choose between "flat domain" and "nested domain" based on the presence of one child.
3. **One durable source.** Persistent UI changes must ultimately materialize as Profile V2.
4. **Runtime state stays runtime state.**
5. **One cohesive consumer family per change.** Avoid broad cross-domain rewrites.
6. **Preserve behavior during read migrations.** Where practical, add equivalence tests before removing compatibility reads.
7. **Do not remove compatibility surfaces until all callers are proven migrated.**
8. **Add guardrails early.** New flat durable consumers should be prevented while the existing allowlist shrinks.
9. **Lua 5.1 / Windower compatibility remains mandatory.**
10. **Update this document after every migration slice.**

## Current architecture inventory

### Canonical / desired surfaces

| Surface | Current role | Target |
| --- | --- | --- |
| `data/profiles_v2/<character>_<MAIN>_<SUB>.lua` | Durable Profile V2 file | Keep as sole durable profile source |
| `_G.UC_ACTIVE_PROFILE.config` | Canonical applied config | Make authoritative for all durable runtime reads |
| `uc_active_config.get_path(...)` | Canonical runtime accessor | Keep / standardize where appropriate |
| WinForms Profile V2 writer | Produces structured profile files | Keep, then reduce reliance on flat intermediate editor objects |

### Major flat producers / compatibility writers

| Producer | Current behavior | Migration direction |
| --- | --- | --- |
| `UnifiedCombat.lua::uc_new_settings_defaults()` | Creates a large flat settings table | Separate true runtime defaults from durable config defaults |
| `uc_active_config.lua` | Projects canonical config back into flat `_G.UC_SETTINGS` | Shrink projection as consumers migrate; eventually retire durable projection |
| `remote_bridge.lua::apply_set()` | Mutates flat `_G.UC_SETTINGS` fields from UI messages | Durable edits should route through Profile V2; keep runtime commands separate |
| WinForms `BuildProfileFromUi()` | Builds a flat editor `JsonObject` | Replace incrementally with structured editor model or structured write adapters |
| `StructuredProfileV2Writer.cs` | Converts flat editor state to nested V2 | Preserve initially; later reduce flat translation responsibility |
| `RuntimeProfileEditorAdapter.cs` | Converts canonical active config back to flat editor state | Preserve initially; later narrow/remove as editor model becomes structured |
| `MainForm.ParityLogic.cs` live `op=set` calls | Sends many flat field edits directly to addon | Classify each as durable config vs runtime command and migrate durable edits |

### Known runtime flat consumers / mixed consumers

The Phase 0 baseline is frozen in `docs/profile_v2_flat_surface_inventory.md`; the table below remains the higher-level migration view.

| Consumer / family | Current pattern | Initial risk |
| --- | --- | --- |
| `uc_scheduler_context_utils.get_settings()` | Returns `_G.UC_SETTINGS` into scheduler context | High architectural leverage |
| `unified_scheduler.lua` | Scheduler context still carries flat `settings` | High |
| `unified_combat_core.lua` | Heavy flat settings usage | High |
| `uc_provider_combat.lua` | Reads flat combat fields through `ctx.settings` | Medium |
| `uc_scheduler_config.lua` | Canonical-first helpers with flat fallback | Medium |
| `uc_runtime_overrides.lua` | Canonical-first/mixed flat fallback | Medium |
| `uc_provider_food.lua` | Canonical with flat fallback | Low |
| `uc_provider_recurring_spells.lua` | Canonical with flat fallback | Low |
| Defensive providers | Canonical with flat fallback in multiple helpers | Low/Medium |
| Enemy buff/debuff providers | Canonical with flat fallback | Low |
| `uc_cor_maintenance.lua` | Canonical plus compatibility fallback | Low |
| `uc_provider_maintenance.lua` BRD | Direct canonical `config.maintenance.brd` | Already near target |
| `uc_geo_camp_placement.lua` | Canonical then `UC_SETTINGS.maintenance_geo` fallback | Low |
| `uc_party_follow.lua` | Mixed canonical/flat reads | Medium |
| `uc_pathing.lua` | Canonical path/follow policy; flat table retained only for live route/session state and compatibility plumbing | Medium/High |
| `uc_raise_accept.lua` | Direct flat config read | Low |
| `uc_recovery_hold.lua` | Canonical plus flat fallback | Low |
| `uc_smn_runtime.lua` | Reconstructs SMN config from flat `summoner_*` fields | Medium/High |
| `uc_pup_runtime.lua` | Reads `settings.puppetmaster` | Medium |
| `uc_provider_sch_maintenance.lua` | Reads `settings.sch` | Medium |
| `unified_engine.lua` | Direct `UC_SETTINGS` access for some values | Needs classification |
| `melee_engine.lua` | Legacy flat settings ownership | High / legacy-sensitive |
| `dd2_module.lua` | Proxies reads/writes through `UC_SETTINGS` | Needs classification |
| `uc_scheduler_action_state.lua` | Reads flat debug/log settings | Low, but still compatibility debt |

## Phase plan

### Phase 0 — Inventory and guardrails

Status: **COMPLETE — baseline frozen; Phase 1 is next**

Goals:

- produce an exhaustive list of flat durable producers;
- produce an exhaustive list of flat durable consumers;
- classify each setting as:
  - durable Profile V2 config;
  - runtime/transient state;
  - compatibility-only surface;
- map each flat key to its canonical Profile V2 path where one exists;
- identify flat keys with no canonical home;
- identify canonical fields still reconstructed from flat inputs;
- add a source-contract test/allowlist that prevents new durable `UC_SETTINGS` consumers from being added during migration;
- add regression coverage for mixed nested/flat sibling domains, including the food + BRD case.

Exit criteria:

- [x] flat producer inventory complete;
- [x] flat consumer inventory complete;
- [x] field classification complete;
- [x] flat-to-canonical path map complete;
- [x] unknown/unmapped fields explicitly listed;
- [x] guardrail test added;
- [x] mixed maintenance characterization/regression fixture added;
- [x] no runtime behavior intentionally changed.

### Phase 1 — Establish the canonical runtime read boundary

Status: **COMPLETE — canonical scheduler context seam established**

Goals:

- make canonical config explicit in scheduler/runtime context, e.g. `ctx.config`;
- preserve `ctx.settings` only for unmigrated callers during transition;
- define a small canonical accessor boundary rather than ad hoc global reads;
- ensure providers can consume canonical config without reparsing Profile V2 files;
- avoid changing ranking, scheduling, target selection, or action semantics.

Exit criteria:

- [x] scheduler context carries canonical config explicitly;
- [x] canonical context has deterministic tests;
- [x] unmigrated flat callers remain behaviorally unchanged;
- [x] no new flat runtime readers introduced.

### Phase 2 — Migrate low-risk leaf consumers

Status: **COMPLETE — canonical leaf migration implemented and CI green; live-game smoke verification remains before merge**

Candidate order:

1. food maintenance;
2. recurring combat spells;
3. raise acceptance;
4. recovery-hold configuration;
5. defensive leaf helpers;
6. enemy buff removal;
7. enemy debuff maintenance;
8. COR maintenance;
9. GEO placement/config helpers;
10. simple debug/log configuration readers where appropriate.

For each slice:

- migrate canonical read;
- remove that consumer's flat fallback;
- add/adjust equivalence tests;
- update the Phase 0 allowlist;
- update this document.

Exit criteria:

- [x] selected leaf consumers no longer depend on flat durable fields;
- [x] compatibility behavior is covered by tests at the boundary, not inside each consumer.

### Phase 3 — Migrate core scheduler/combat domains

Status: **IN PROGRESS — all listed Phase 3 runtime domain slices and the automated exit audit are CI-proven; live behavior verification remains**

Domains to treat separately:

- combat enablement and autotarget;
- weaponskill configuration;
- abilities;
- target-control and ignore/priority lists;
- tank/enmity configuration;
- pulling;
- spacing;
- follow;
- pathing;
- movement-owned durable settings.

This is the highest-risk runtime phase. Each domain should be migrated independently.

Exit criteria:

- [x] scheduler action selection uses canonical durable config;
- [x] core combat no longer requires flat durable settings;
- [x] follow/pathing durable settings no longer require flat settings;
- [x] runtime-only IDs and live state remain outside Profile V2;
- [ ] live behavior checks completed for each migrated domain.

### Phase 4 — Migrate job-specific configuration

Status: **COMPLETE — SMN, PUP, SCH, GEO, BRD, and COR canonical runtime authority is CI-proven**

Targets:

- SMN;
- PUP;
- SCH;
- any remaining BRD/COR/GEO compatibility reads.

Goals:

- consume canonical job subtrees directly;
- stop reconstructing typed job config from flat compatibility fields;
- keep observed job runtime state separate from durable config.

Exit criteria:

- [x] SMN consumes canonical Profile V2 config;
- [x] PUP consumes canonical Profile V2 config;
- [x] SCH consumes canonical Profile V2 config;
- [x] GEO maintenance consumes canonical Profile V2 config;
- [x] BRD maintenance consumes the tick-stable canonical Profile V2 config;
- [x] COR has no remaining durable runtime compatibility dependency;
- [x] automated Phase 4 exit audit freezes the combined job-runtime authority boundary.

### 2026-10-04 — Phase 4 SMN runtime cutover implemented

- `config.summoner` is now the only durable runtime authority for Summoner maintenance and Summoner pet combat.
- `uc_smn_runtime.config_from_config(config)` validates and exposes the canonical Summoner subtree directly. The existing flat `config_from_settings(settings)` parser is retained only as an explicit compatibility/migration-test helper.
- `uc_smn_maintenance.lua` collect and revalidation paths now consume `ctx.config` directly; both prior `ctx.settings` reads are removed.
- `uc_smn_pet_combat_adapter.lua` snapshot/configuration now consumes `ctx.config` directly; its prior `ctx.settings` read is removed.
- Durable policy remains separated from observed runtime state: live avatar/pet identity, recasts, MP, pet TP, target state, combat generation, and reaction holds remain scheduler/runtime observations and are not written into Profile V2.
- Added `tests/replay/harness/selftest_phase4_smn_authority.lua` with deliberately contradictory canonical-vs-flat state covering disabled/enabled authority, avatar selection, revalidation, Assault enablement, and Rage enablement/action selection.
- Existing SMN maintenance, pet-combat, integration, and replay fixtures were updated to provide canonical `config.summoner` while retaining flat settings only as compatibility/test state.
- Flat-surface burn-down: `uc_smn_maintenance.lua` `ctx.settings` 2→0; `uc_smn_pet_combat_adapter.lua` 1→0. Both files are removed from the Profile V2 flat-surface allowlist.
- Dedicated Phase 4 SMN CI coverage is wired into the PR workflow. Implementation head `4541f3b9212fbd97281c410af79b4e2c2be2d470` is proven by workflow `37209447842`: Phase 4 SMN canonical-authority PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms PASS.

### 2026-10-04 — Phase 4 PUP runtime cutover implemented

- `config.puppetmaster` is now the only durable runtime authority for Puppetmaster automaton maintenance and pet-combat policy.
- `uc_pup_runtime.config_from_config(config)` validates/copies the canonical Puppetmaster subtree directly. `config_from_settings(settings)` remains only as a bounded compatibility/direct-caller helper.
- `uc_pup_runtime.observe()` no longer falls back to `ctx.settings.puppetmaster`; its implicit config path is canonical `ctx.config`.
- `uc_pup_pet_combat_adapter.lua` snapshot policy now consumes canonical config directly.
- Durable PUP policy includes automation enablement, Activate-if-missing, Deploy-on-combat-start, Maneuver enablement/pattern, post-activation recovery duration, and safe burden ceiling.
- Observed automaton identity, pet lifecycle transitions, Maneuver buffs, estimated burden, recasts, target state, combat generation, and current zone remain runtime state outside Profile V2.
- Added `tests/replay/harness/selftest_phase4_pup_authority.lua` with intentionally contradictory canonical and compatibility-mirror state across every durable PUP setting.
- Existing PUP profile and automaton-control tests now provide canonical scheduler config explicitly while continuing to characterize compatibility conversion separately.
- Flat-surface burn-down: `uc_pup_runtime.lua` `ctx.settings` 1→0; `uc_pup_pet_combat_adapter.lua` 1→0. Both files are removed from the flat-surface allowlist.
- Dedicated Phase 4 PUP CI coverage is wired into the PR workflow. Implementation head `4825e797f998a52fadae59273a1c5754c6a0a823` is proven by workflow `37212592184`: Phase 4 PUP canonical-authority PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms PASS.

### 2026-10-04 — Phase 4 SCH runtime cutover implemented

- `config.sch` is now the only durable Scholar runtime authority at the scheduler/provider boundary.
- `uc_provider_sch_maintenance.config_from_context(ctx)` copies and validates the canonical Scholar subtree from `ctx.config`; the provider no longer reads `ctx.settings.sch`.
- Scholar provider generation/signature tracking, runtime configuration, maintenance planning, defensive planning, Sublimation, Storm/Regen maintenance, and skillchain runtime all receive that canonical subtree.
- Shared defensive inputs used by Scholar are canonical too: trust filtering, critical-cure classification, and the critical-HPP threshold now come from the explicit canonical root config instead of flat defensive mirrors.
- Durable Scholar policy remains separate from observed runtime state: Arts/buffs, stratagem recast/charge evidence, party roster/buffs/vitals, owned-buff evidence, active sequence state, skillchain target state, and action-result observations remain runtime-owned.
- Added `tests/replay/harness/selftest_phase4_sch_authority.lua` with canonical and compatibility Scholar trees intentionally opposed across Arts, Sublimation, Regen, Storms, defensive stratagem policies, and skillchain configuration.
- Existing Scholar provider integration coverage now supplies `ctx.config.sch` explicitly; the first live provider case deliberately leaves the compatibility mirror disabled while canonical Scholar policy remains enabled.
- Flat-surface burn-down: `uc_provider_sch_maintenance.lua` `ctx.settings` 1→0; the file is removed from the Profile V2 flat-surface allowlist.
- Dedicated Phase 4 SCH CI coverage is wired into the PR workflow. Implementation head `cb79e69a421bff49b65a3e70bd6d405b28e83ecf` is proven by workflow `37217954383`: Phase 4 SCH canonical-authority PASS, Scholar configuration/maintenance/runtime/duration/action-result suites PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms PASS.

### 2026-10-04 — Phase 4 GEO runtime cutover implemented

- `config.maintenance.geo` is now the sole durable runtime authority for GEO maintenance policy in `uc_geo_maintenance.lua`.
- `uc_geo_maintenance.config_from_context(ctx)` reads the canonical scheduler root at `ctx.config.maintenance.geo`; the provider no longer reads `ctx.settings` or the nested compatibility mirror at `settings.config.maintenance.geo`.
- GEO enemy revalidation now passes canonical `ctx.config` into target-ignore evaluation. The scheduler wiring projects `config.targeting.target_ignore_names` explicitly, so stale flat `target_ignore_names` can no longer change GEO target eligibility.
- Durable GEO policy remains separate from observed runtime state: current Luopan identity/HPP/position, owned Geo/Indi/Entrust evidence, current enemy identity/claim state, pending actions, sequence state, retry/backoff timing, Bolster arm state, camp/player geometry, and action-result observations remain runtime-owned.
- Existing GEO maintenance and sequence suites now provide canonical `ctx.config.maintenance.geo` explicitly while retaining deliberately disabled/conflicting compatibility state so they fail if flat authority returns.
- Added `tests/replay/harness/selftest_phase4_geo_authority.lua` with contradictory canonical-vs-compatibility coverage for GEO enablement in both directions and target-ignore authority in both directions, plus static boundary assertions.
- Flat-surface burn-down: `uc_geo_maintenance.lua` `ctx.settings` 3→0; the file is removed from the Profile V2 flat-surface allowlist.
- Dedicated Phase 4 GEO CI coverage is wired into the PR workflow together with the existing GEO maintenance and sequence suites. Implementation head `7d14ebef5c6ec94c4415f4bc340746206cf3cc29` is proven by workflow `37244333785`: Phase 4 GEO canonical-authority PASS, GEO maintenance/sequence suites PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- No intentional Luopan/Indi/Entrust ordering, placement geometry, Blaze/Ecliptic/Life Cycle sequencing, retry timing, camp restriction, target ranking, or dispatch semantics changed; this slice changes durable authority only.
- Live-game smoke verification remains required for target-placed and camp-placed Luopans, enemy target-ignore behavior, Entrust, optional Luopan abilities, and replacement/recovery behavior before final migration acceptance.

### 2026-10-04 — Phase 4 BRD runtime cutover implemented

- BRD maintenance now consumes the scheduler tick's canonical `ctx.config.maintenance.brd` subtree directly in `uc_provider_maintenance.lua`.
- Removed both BRD-side global active-config resamples from the maintenance provider: `config.maintenance.brd` and the positioning dependency `config.combat.pulling`. Bard positioning now uses the same tick-stable `ctx.config.combat.pulling` snapshot as the rest of the scheduler.
- `uc_brd_maintenance.lua` itself remains a pure typed-policy/state machine: it receives the canonical BRD subtree as an explicit argument and still owns only observed song identity/duration, pending transactions, Nitro/Soul Voice/Clarion/Marcato sequence state, targeted-song delivery evidence, failure/retry state, and diagnostics.
- Added `tests/replay/harness/selftest_phase4_brd_authority.lua`. The regression makes any `uc_active_config.get_path()` call fail immediately, opposes canonical BRD enablement/range/reposition policy against compatibility state in both directions, and proves the canonical pulling leash reaches positioning.
- Existing BRD maintenance, movement-safety, positioning, and song-identity suites are included in the dedicated Phase 4 BRD CI step.
- This slice has no flat-surface allowlist count change because the BRD provider was not reading `ctx.settings` or `UC_SETTINGS`; the removed seam was a global canonical resample that bypassed the scheduler context rather than a flat read.
- Implementation head `c5a7f66d12d303f70ba0de6715c9e7c0b614c4ed` is proven by workflow `37244782699`: Phase 4 BRD canonical-authority PASS, BRD maintenance/movement-safety/positioning/song-identity suites PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS. The run also exposed and fixed a pre-existing replay-harness assumption by making the BRD diagnostic-log fixture create its scratch `data/logs` directory before use.
- No intentional song ordering, dummy-song capacity logic, Nitro/Soul Voice/Clarion/Marcato sequencing, Pianissimo targeting, recovery-range geometry, positioning algorithm, or dispatch behavior changed; the change is authority/snapshot consistency only.
- Live-game smoke verification remains required for ordinary song maintenance, targeted/Pianissimo songs, Nitro/Soul Voice/Clarion/Marcato sequencing, and reposition-for-party-songs behavior before final migration acceptance.

### 2026-10-04 — Phase 4 COR authority audit implemented

- The COR scheduler/runtime path was already canonical from the earlier maintenance migration, so this slice intentionally makes no production decision-logic rewrite.
- `uc_provider_maintenance.lua` passes the tick-stable canonical root to COR by identity through `cor_propose(ctx.config)`.
- `uc_cor_maintenance.propose(config)` derives COR roll selection, Crooked Cards slot, Elevens policy, Luzaf/range policy, Light Shot-on-Dia enablement, and configured-ability roll fallback only from the explicit canonical config argument. It has no `ctx.settings`, `UC_SETTINGS`, `uc_active_config`, or `active_value_or_flat` runtime reader.
- Remaining `cor_*` flat names are compatibility/edit/projection inputs in `UnifiedCombat.lua`, `uc_active_config.lua`, WinForms, the remote bridge, and normalization. They do not feed the COR action-decision path after canonical config has been built.
- `uc_config_normalizer_cor.lua` is explicitly classified as an input/migration compatibility adapter: it accepts legacy/mixed input shapes to materialize canonical `config.maintenance.cor.light_shot_dia`, but `uc_cor_maintenance.lua` never invokes that normalizer at action time.
- Added `tests/replay/harness/selftest_phase4_cor_authority.lua`. It installs deliberately conflicting flat COR globals plus a fail-fast fake `uc_active_config`, proves canonical roll/Crooked/Luzaf/range/ability-fallback decisions, proves the maintenance provider passes `ctx.config` by identity, and freezes the static no-flat/no-resample runtime boundary.
- Dedicated Phase 4 COR CI also runs the existing Dia/Light Shot static and runtime suites plus the earlier active-config maintenance regression.
- No flat-surface allowlist change is expected in this slice because COR's remaining flat names are producer/normalizer/editor compatibility surfaces rather than scheduler runtime consumers.
- Audit head `07f4f743a43f2c1c43758c75020090f55f2a4e19` is proven by workflow `37244992663`: Phase 4 COR canonical-authority PASS, Dia/Light Shot static and runtime suites PASS, the active-config maintenance regression PASS, all prior Phase 4 job suites PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- No intentional roll selection, Double-Up/Snake Eye/Fold logic, Crooked Cards behavior, Luzaf range semantics, Dia/Light Shot behavior, or incoming-chunk state tracking changed.

### 2026-10-04 — Phase 4 automated exit audit added

- Added `tests/replay/harness/selftest_phase4_exit_audit.lua` to freeze the combined job-runtime authority boundary after the six independent job slices.
- The audit requires SMN maintenance/pet combat, PUP runtime/pet combat, SCH, GEO, the shared BRD/COR maintenance provider, BRD maintenance, and COR maintenance to remain free of `ctx.settings`, `UC_SETTINGS`, `uc_active_config`, and `active_value_or_flat` runtime reads.
- It also asserts the positive canonical wiring for every job family: SMN/PUP config adapters, SCH/GEO canonical context adapters, BRD's canonical maintenance + pulling subtrees, and COR's `cor_propose(ctx.config)` route plus configured-ability fallback.
- Input normalizers, editor/bridge compatibility fields, canonical-to-flat projection, and runtime observation state remain outside this Phase 4 action-authority boundary and are handled by later UI/projection cleanup phases.
- Exit-audit head `3eff4da4c5fa35eef963ebea239bceb5672f7cb0` is proven by workflow `37245104164`: Phase 4 automated exit audit PASS, SMN/PUP/SCH/GEO/BRD/COR authority suites PASS, BRD and COR focused runtime suites PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS. Phase 4 is complete; live-game smoke validation remains part of the final acceptance work rather than runtime-authority migration.

### Phase 5 — Migrate UI/edit/write pipeline

Status: **COMPLETE — durable WinForms edits are canonical/local, runtime commands remain explicit, and the final partner/follow identity write pipeline is CI-proven**

Goals:

- classify every WinForms `op=set` path as durable configuration or runtime command;
- route durable edits through Profile V2;
- retain explicit runtime commands for non-durable actions such as engine start/stop, camp capture, reload, and other action commands;
- eliminate the parallel "write flat live settings" durable-config path;
- reduce or remove flat editor intermediate translation where safe;
- preserve activity profile behavior and rollback semantics.

Exit criteria:

- [x] durable UI edits are represented in Profile V2 (generic scalar `op=set` now updates per-session working Profile V2 state);
- [x] addon bridge no longer mutates flat durable settings as an authority (target-ignore/add-priority now edit active Profile V2 first and only reproject flat compatibility state);
- [x] runtime commands remain explicit and separate;
- [x] activity apply still deploys canonical Profile V2 only;
- [x] editor initialization still comes from canonical runtime config/transient working state.

### 2026-10-05 — Phase 5 generic scalar edit channel implemented

- The WinForms outbound boundary already allowed only explicit runtime/session operations: engine start/stop, addon reload, camp set/clear, and state/options requests. Legacy generic `op=set` calls therefore never reached the addon bridge, but many older handlers still called `Forward(... set ...)` and some did not separately capture their unsaved working profile.
- `MainForm.Forward` now classifies generic `op=set` explicitly as a durable editor mutation. It calls `CaptureWorkingProfileFromUi(sid)` and returns before the mirror enqueue boundary.
- This preserves existing live behavior: generic scalar edits still do not mutate the running addon's flat settings and do not become runtime commands. The change makes their durable/local effect explicit and prevents older scalar controls from losing unsaved state when the editor is rebuilt from the per-session working profile.
- Explicit runtime commands remain separate and continue through `IsRuntimeSessionOutboundOp`: `start_engine`, `stop_engine`, `addon_reload`, `camp_set`, `camp_clear`, `request_state`, and `request_options`.
- Profile persistence remains explicit-only through Save; this slice does not turn a UI edit into an automatic file write.
- Added `tests/replay/harness/selftest_phase5_ui_write_pipeline.lua` to prove `set` is excluded from runtime traffic, durable edits capture the working profile before the live enqueue boundary, and existing Profile V2 file-only Save contracts remain intact.
- The legacy `remote_bridge.lua` `op=set` / `apply_set` path remains for compatibility and is intentionally not removed in this slice. It is now provably unreachable from the normal WinForms `Forward` path and will be addressed as a later Phase 5 addon-bridge cutover.
- Legacy list/edit operations such as target-ignore, hunter, partner, COR range, Sleep ordering, and ability replacement remain to be classified/migrated independently.
- Implementation head `4c4b0a927eb5fd60cbed70ac84d82caf976c5e56` is proven by workflow `37296952941`: Phase 5 UI write-pipeline authority PASS, Phase 4 exit audit PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.

### 2026-10-05 — Phase 5 targeting-list write pipeline implemented

- The first bespoke list slice covers target-ignore and add-priority policy.
- Durable target-ignore policy is edited at `config.targeting.target_ignore_names`.
- Durable add-priority policy is edited at `config.targeting.targets`. The legacy `config.targeting.add_priority_names` field remains compatibility-only and is intentionally not used as the durable edit target.
- Added canonical active-profile list editor helpers in `uc_active_config.lua`: replace, append, remove-by-index, and ordered move. These mutate the existing canonical list in place, preserving runtime table identity.
- `remote_bridge.lua` target-ignore/add-priority replace/add/add-current/remove/move handlers now edit canonical active Profile V2 first. After a successful canonical edit, the bridge refreshes `_G.UC_SETTINGS` only through `project_flat_settings` + `sync_flat_settings_in_place` as a compatibility projection.
- The bridge no longer requires `uc_target_ignore` or `uc_add_priority`, and no longer assigns `s.target_ignore_names` or `s.add_priority_names`.
- WinForms target-ignore/add-priority add/remove/reorder actions no longer emit live bridge mutations. They update the local editor rows and immediately call `CaptureWorkingProfileFromUi(sid)`.
- The two Add Current Target actions now consume runtime observation instead of issuing a durable bridge mutation. `remote_bridge.lua` exposes `current_target_name` / `current_target_id` in the state snapshot; WinForms copies the observed name into the local working profile.
- `PushFullFormState` no longer emits target-ignore or add-priority replace operations.
- Added `tests/replay/harness/selftest_phase5_targeting_list_write_pipeline.lua` covering canonical list mutation semantics, compatibility projection, no-flat bridge ownership, local-only WinForms edits, Add Current runtime observation, and removal of full-form target-list pushes.
- Remaining bespoke list domains include wait-ignore/partner/no-skillchain, abilities, tank enmity, Sleep ordering, path-hunter targets, COR range participants, and related identity-bearing operations.
- Implementation head `b1940027994f3af942e2d6a5fb06b682e0585a09` is proven by workflow `37300224572`: Phase 5 targeting-list write-pipeline PASS, Phase 5 generic UI write-pipeline PASS, Phase 4 exit audit PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS. The guard baseline intentionally burns `remote_bridge.lua` direct `UC_SETTINGS` references from 44 to 36; the new `project_flat_settings`/`sync_flat_settings_in_place` counts represent compatibility reprojection after canonical mutation, not flat authority.

### 2026-10-05 — Phase 5 no-skillchain target write pipeline implemented

- Migrated the no-skillchain target editor/write channel to canonical `config.combat.weaponskill.no_skillchain_targets`.
- `remote_bridge.lua` replace/add/add-current/remove compatibility handlers now reuse the canonical active-profile list editor API and no longer require `uc_no_skillchain_targets` or mutate `weaponskill_no_skillchain_targets` directly.
- After a successful canonical edit, the existing bridge compatibility projection refreshes flat runtime state; the flat field is output compatibility only, not edit authority.
- WinForms no-skillchain add/remove operations now update local rows and call `CaptureWorkingProfileFromUi(sid)` without emitting bridge mutations.
- Add Current Target reuses the runtime-observed `current_target_name` introduced in the prior targeting-list slice, keeping live observation separate from durable policy.
- `PushFullFormState` no longer emits `no_skillchain_target_replace_names`.
- The structured Profile V2 writer already maps `no_skillchain_target_entries` to `config.combat.weaponskill.no_skillchain_targets`; this slice therefore removes the parallel live-write path without changing serialization shape.
- Added `tests/replay/harness/selftest_phase5_no_skillchain_write_pipeline.lua` covering canonical list mutation, compatibility projection, no-flat bridge ownership, local-only WinForms editing, Add Current runtime observation, writer mapping, and removal of the full-form replace push.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 36→32.
- The existing `selftest_no_skillchain_targets.lua` remains because `uc_no_skillchain_targets.lua` is still a runtime matching/gating helper even though it is no longer a bridge writer.
- Implementation head `e29d8106df2d308b929f6a32023b099deb86b130` is proven by workflow `37304464552`: Phase 5 no-skillchain write-pipeline PASS, existing no-skillchain runtime gate PASS, Phase 5 targeting-list pipeline PASS, Phase 5 generic UI pipeline PASS, Profile V2 flat-surface guard PASS, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS. The first WinForms run exposed a stale writer-contract assertion that still required the retired live `no_skillchain_target_replace_names` emit; that contract was updated to require local working-profile capture plus no live bridge mutation.

### 2026-10-05 — Phase 5 wait-ignore write pipeline implemented

- Migrated wait-ignore durable editing to canonical `config.combat.weaponskill.wait_ignore_names`.
- Preserved the intended identity split: durable policy is a case-insensitive ordered name list; legacy runtime `ignore` IDs are derived from the currently resolvable party roster during compatibility projection and are never written as durable authority.
- Added `uc_active_config.remove_string_list_value(path, value)` so the legacy `ignore_remove(mob_id)` compatibility operation can translate the live party ID back to its current name and remove that canonical durable name.
- `remote_bridge.lua` `ignore_replace_names`, `ignore_add`, `ignore_add_current`, and `ignore_remove` now edit canonical Profile V2 first through the active-profile list editor API. The bridge no longer requires `uc_ignore`, no longer assigns `s.wait_ignore_names`, and no longer mutates `s.ignore`.
- `uc_active_config.project_flat_settings()` remains the single compatibility derivation point: `wait_ignore_names` is copied from canonical policy and `ignore` is rebuilt from names that resolve to current party-member IDs. Offline/unresolved durable names remain in Profile V2 but produce no transient ID until resolvable.
- WinForms wait-ignore add/remove operations now edit local rows and call `CaptureWorkingProfileFromUi(sid)` only. Add Current consumes the runtime-observed `current_target_name`; it does not send a durable mutation command to the addon.
- `PushFullFormState` no longer emits `ignore_replace_names`.
- The existing structured writer remains unchanged: `ignore_entries` serializes to canonical `config.combat.weaponskill.wait_ignore_names`.
- Added `tests/replay/harness/selftest_phase5_wait_ignore_write_pipeline.lua` covering durable-name editing, case-insensitive dedupe/remove, offline-name persistence, current-party name→ID compatibility projection, legacy remove-ID→name translation, no-flat bridge ownership, local-only WinForms editing, and removal of the full-form push.
- The WinForms Profile V2 round-trip contract now explicitly requires wait-ignore editing to stay local and forbids the retired live `ignore_*` operations.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 32→28.
- Runtime WS coordination remains name-based through `uc_ignore.is_name_blocked(settings, value.name)`; this slice changes write authority only.
- Implementation head `59aaed1144f051c8b029f66b983f1e9e51579496` is proven by workflow `37307864263`: Phase 5 wait-ignore write-pipeline PASS, prior Phase 5 write-pipeline suites PASS, Phase 4 exit audit PASS, Profile V2 flat-surface guard PASS at the 28-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS. The first implementation run also exposed a pre-existing BRD timer-jitter fixture that depended on an aging absolute captured server timestamp; the fixture now anchors the same jitter delta to the test's synthetic current server clock without changing BRD production logic.

### 2026-10-05 — Phase 5 path-hunter target write pipeline implemented

- Migrated path-hunter durable editing to canonical `config.movement.path.hunter_targets`.
- `remote_bridge.lua` `path_hunter_replace_names`, `path_hunter_add`, and `path_hunter_remove` now reuse the canonical active-profile list editor API. The bridge no longer requires `uc_path_hunter` for editing and no longer assigns `s.path_hunter_targets`.
- After successful canonical edits, the existing compatibility projection refreshes flat `path_hunter_targets`; the projected list is compatibility output only.
- WinForms path-hunter add/remove already captured the per-session working profile; this slice removes their remaining live bridge emits. `PushFullFormState` no longer emits `path_hunter_replace_names`.
- The structured writer remains unchanged: `path_hunter_entries` persists to `config.movement.path.hunter_targets`.
- `RuntimeProfileEditorAdapter` continues to reconstruct editor rows from canonical `path_hunter_targets`.
- Runtime hunter matching remains unchanged in `uc_path_hunter.matches_mob`; Phase 3 canonical path authority already ensures runtime policy comes from `config.movement.path`.
- Added `tests/replay/harness/selftest_phase5_path_hunter_write_pipeline.lua` covering canonical list mutation, case-insensitive dedupe, compatibility projection, no-flat bridge ownership, local-only WinForms editing, structured writer/adapter mapping, canonical path adapter wiring, and removal of the full-form push.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 28→25.
- Implementation head `045223fe226e177325d86ea16f16d2725f572cf0` is proven by workflow `37337795481`: Phase 5 path-hunter write-pipeline PASS, prior Phase 5 write-pipeline suites PASS, Phase 3 pathing authority PASS, Profile V2 flat-surface guard PASS at the 25-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.

### 2026-10-06 — Phase 5 Sleep ordering write pipeline implemented

- Migrated Sleep ordering edits to canonical `config.sleep.order`.
- Preserved the coupled compatibility field: every canonical Sleep order replace/add/remove/move now automatically synchronizes `config.sleep.legacy_primary` to the first ordered spell, or clears it when the list becomes empty.
- Exposed `UC_SleepSpell.validate_names(names)` as a validation-only surface. Bridge compatibility edits still validate spell names against FFXI spell resources and reject unknown entries before canonical mutation; validation no longer requires mutating flat `sleepspells`.
- `remote_bridge.lua` `sleep_replace_spells`, `sleep_add_spell`, `sleep_remove_spell`, and `sleep_move_spell` now edit canonical Profile V2 through the active-profile list editor API. The bridge no longer reads `_G.UC_SETTINGS` in these handlers.
- After successful canonical edits, the existing compatibility projection refreshes flat `sleepspells` / `sleepspell`; those fields are compatibility output only.
- WinForms Sleep Set Only, Add, Remove, Clear, and Move operations now edit local rows and call `CaptureWorkingProfileFromUi(sid)`; no Sleep ordering operation is emitted to the addon bridge.
- `PushFullFormState` no longer emits `sleep_replace_spells`.
- The existing structured writer remains canonical: `sleep_spell_entries` serializes to `config.sleep.order`, and `legacy_primary` is derived from the first ordered entry.
- `RuntimeProfileEditorAdapter` continues reconstructing Sleep editor rows from projected canonical `sleepspells`.
- Runtime Sleep selection remains unchanged and canonical through `scheduler.sleep_spell_list_from_config(config)` / `uc_scheduler_config.sleep_order_from_config(config)`.
- Added `tests/replay/harness/selftest_phase5_sleep_order_write_pipeline.lua` covering ordered-list mutation, case-insensitive dedupe, `legacy_primary` coupling, compatibility projection, validation-before-edit bridge behavior, local-only WinForms editing, writer/adapter mapping, and canonical scheduler consumption.
- Updated `selftest_sleep_spell_selection.lua` to require the new local-only UI contract rather than the retired live Sleep edit operations.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 25→21.
- Implementation head `ec0f200f70fcfd0c73d3bc00a1b235bcf54282e7` is proven by workflow `37426656092`: Phase 5 Sleep ordering write-pipeline PASS, existing Sleep spell selection PASS, prior Phase 5 write-pipeline suites PASS, Profile V2 flat-surface guard PASS at the 21-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.

### 2026-10-06 — Phase 5 tank-enmity action write pipeline implemented

- Migrated tank-enmity durable editing to canonical `config.tank.enmity.actions`.
- Preserved the existing entry contract: ordered strings may be explicit `ja:Name` / `spell:Name` entries or legacy bare names. Canonical list dedupe is case-insensitive over the complete entry, so explicit type prefixes remain semantically distinct from bare compatibility entries.
- `remote_bridge.lua` `tank_enmity_replace_actions` now uses the canonical active-profile list editor API and no longer reads or mutates `_G.UC_SETTINGS`.
- After successful canonical mutation, the existing compatibility projection refreshes flat `tank_enmity_actions`; the projected list is compatibility output only.
- Removed the WinForms `PushTankEnmityActions` live bridge helper. Add, Remove, and Move now update `_tankEnmityRows` and call `CaptureWorkingProfileFromUi(sid)`.
- `PushFullFormState` no longer emits `tank_enmity_replace_actions`.
- The structured writer remains unchanged: `tank_enmity_actions` persists to `config.tank.enmity.actions`.
- `RuntimeProfileEditorAdapter` continues reconstructing the editor pipe list from canonical projected `tank_enmity_actions`.
- Runtime parsing/selection is unchanged: `unified_combat_core.lua` preserves explicit `type:name` parsing and legacy bare-name JA/spell inference, while `uc_provider_tank_enmity.lua` consumes `scheduler_config.tank_enmity_actions_from_config(config)`.
- Added `tests/replay/harness/selftest_phase5_tank_enmity_write_pipeline.lua` covering canonical ordered mutation, full-entry case-insensitive dedupe, typed-vs-bare compatibility semantics, compatibility projection, no-flat bridge ownership, local-only WinForms editing, writer/adapter mapping, and canonical runtime consumption.
- Dedicated Phase 5 tank-enmity CI also runs the existing tank pet-enmity config and provider suites.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 21→20.
- Implementation head `c4fa5130879e3239ce20c003d430c1a8d6b34d10` is proven by workflow `37427996454`: Phase 5 tank-enmity write-pipeline PASS, tank pet-enmity config/provider suites PASS, prior Phase 5 write-pipeline suites PASS, Profile V2 flat-surface guard PASS at the 20-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.

### 2026-10-06 — Phase 5 abilities write pipeline implemented

- Migrated ability-list editing to canonical `config.abilities.configured`.
- `remote_bridge.lua` `set_abilities` now uses the canonical active-profile list editor API and no longer reads or mutates `_G.UC_SETTINGS`.
- Compatibility projection now derives flat `ability1`…`ability6` from canonical `config.abilities.configured` when that list is non-empty. Canonical `legacy_slots` are used only as fallback for older profiles whose configured list is empty.
- This removes the previous duplicate-write behavior where `set_abilities` manually wrote both flat `abilities` and six numbered slots. New Profile V2 serialization continues to leave `legacy_slots` empty instead of duplicating configured policy.
- Flat `abilities` preserves the complete canonical configured list; the numbered compatibility slots expose only the first six entries and explicitly clear unused slots.
- WinForms `SendAbilitiesUpdate` is now local-only: it captures the selected session's working Profile V2 and emits no `set_abilities` bridge operation. Add, Remove, Move Up, Move Down, and full-form capture therefore share the same local durable-edit path.
- The structured writer remains unchanged: `abilities_selected` persists to `config.abilities.configured`, while `legacy_slots` remains empty for new profiles.
- `RuntimeProfileEditorAdapter` continues rebuilding `abilities_selected` from projected canonical `abilities`.
- Runtime semantics remain unchanged: `uc_ability_pipeline.collect_ordered_from_config` consumes canonical configured abilities first and retains canonical legacy-slot fallback when configured is empty; the scheduler-facing core view also uses canonical configured abilities.
- Added `tests/replay/harness/selftest_phase5_abilities_write_pipeline.lua` covering canonical mutation/dedupe, full-list projection, first-six compatibility slot derivation, old-profile legacy-slot fallback, no-flat bridge ownership, local-only WinForms editing, writer/adapter mapping, and canonical runtime consumption.
- The focused Phase 5 CI step also reruns `selftest_phase3_abilities_authority.lua`.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 20→19.
- Implementation head `7480827f867d8f67717101c4099db080a1188599` is proven by workflow `37451144564`: Phase 5 abilities write-pipeline PASS, Phase 3 abilities authority PASS, prior Phase 5 write-pipeline suites PASS, Profile V2 flat-surface guard PASS at the 19-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.

### 2026-10-06 — Phase 5 COR range participant write pipeline implemented

- Migrated COR roll-range participant editing to canonical durable `config.maintenance.cor.range_selected`.
- Preserved the intended identity split: durable policy is a pipe-delimited, case-insensitively deduplicated participant-name selection; live party IDs are derived from the current roster and are not durable authority.
- Added `uc_active_config.replace_pipe_string_list(path, values)` for canonical pipe-delimited name policy. For `config.maintenance.cor.range_selected`, every edit explicitly clears canonical `range_require_ids` so stale runtime IDs cannot survive a durable-name edit.
- Compatibility projection now derives flat `cor_roll_range_require_ids` from currently resolvable names in canonical `range_selected`. If no durable names are configured, old canonical `range_require_ids` remain a legacy fallback.
- `remote_bridge.lua` `cor_roll_range_replace_names` now edits canonical participant names and no longer writes flat `cor_roll_range_selected` or `cor_roll_range_require_ids`.
- WinForms COR range checkbox edits now call `CaptureWorkingProfileFromUi(sid)` and emit no live bridge mutation. `PushFullFormState` no longer emits `cor_roll_range_replace_names`.
- The structured writer remains unchanged and expresses the durable/runtime split directly: `range_selected` is persisted from `cor_roll_range_selected`, while new profiles always write `range_require_ids = {}`.
- `uc_cor_maintenance.lua` now resolves `range_selected` names against the current party at proposal time. Only currently resolvable names produce live required IDs; offline/unresolved durable names remain policy but create no transient requirement until present. If `range_selected` is empty, legacy `range_require_ids` remain supported.
- Runtime range semantics are otherwise unchanged: a resolved required member still blocks rolling when missing/dead/outside the current roll radius.
- Added `tests/replay/harness/selftest_phase5_cor_range_write_pipeline.lua` covering canonical name editing/dedupe, clearing stale IDs, live compatibility projection, offline-name persistence, behavioral current-party name→ID range gating, legacy-ID fallback, no-flat bridge ownership, local-only WinForms editing, and writer persistence.
- The focused Phase 5 CI step also reruns `selftest_phase4_cor_authority.lua`.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references 19→18.
- Implementation head `d433c90bb72dcfae74a0df511edb95206474a9dc` is proven by workflow `37467292638`: Phase 5 COR range participant write-pipeline PASS, Phase 4 COR authority PASS, prior Phase 5 write-pipeline suites PASS, Profile V2 flat-surface guard PASS at the 18-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS. Two initial verification runs failed at Lua parse time because JavaScript `String.replace` treated the dollar-apostrophe text inside Lua's trim pattern as replacement syntax and duplicated the file tail. `uc_cor_maintenance.lua` was rebuilt from the last immutable green version and the intended change was reapplied with literal-safe replacement; these were tooling/parse failures, not design/runtime failures.

### 2026-10-07 — Phase 5 partner/follow identity write pipeline implemented

- Migrated the final bespoke Phase 5 identity group to canonical durable names: `config.follow.party.leader_name`, `config.follow.fight.leader_name`, `config.follow.partner.names`, and `config.follow.partner.puller_name`.
- Tightened the durable/runtime identity contract. When a durable name is configured, runtime IDs are derived only from the current party roster. An offline/unresolved durable name remains in Profile V2 but produces runtime ID `0` (or no partner ID); a stale legacy ID can no longer substitute for that configured name. Legacy IDs remain compatibility fallback only when the corresponding durable name/list is absent.
- Removed the residual `get_mob_by_name` fallback from follow identity resolution, so a visible/non-party entity with the same configured name cannot masquerade as a current party member.
- Added `uc_active_config.replace_name(path, value)` for canonical scalar identity editing. Editing party leader, fight leader, or puller names clears the matching legacy ID, and partner-name list edits clear legacy `partner.ids`.
- Reworked `remote_bridge.lua` compatibility operations `set_partner`, `set_fight_leader`, `set_party_follow`, `partner_add`, `partner_add_current`, `partner_remove`, and `partner_replace_names` to edit active Profile V2 first and refresh flat state only through compatibility projection. The bridge no longer requires `uc_partner_list` for these writes.
- WinForms partner/puller/fight-leader/party-follow identity controls are now local-only durable edits. They call `CaptureWorkingProfileFromUi(sid)` and emit no live identity mutation; partner Add Current consumes the runtime-observed target name. `PushFullFormState` no longer sends any of the retired partner/follow identity operations.
- The structured writer already had the correct persistence contract and remains unchanged: names are durable; partner IDs, puller ID, fight-leader ID, and party-follow leader ID are not written into new Profile V2 files.
- Added `tests/replay/harness/selftest_phase5_follow_identity_write_pipeline.lua`. It proves scalar-name editing, partner-name dedupe, stale-ID clearing, current-party name→ID derivation, offline-name persistence, non-party rejection, legacy-ID fallback only when names are absent, camp-leash behavior, no-flat bridge authority, local-only WinForms editing, full-form push removal, and writer persistence.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references **18→11**.
- Implementation head `d08248c52dedbbe4a7b831f74ce7a20aa08786ab` is proven by workflow `37639924219`: Phase 5 partner/follow identity pipeline PASS, Phase 3 follow authority PASS, all prior Phase 5 pipelines PASS, Profile V2 flat-surface guard PASS at the 11-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The immediately preceding workflow `37639773362` reached and passed every earlier Lua gate through the COR Phase 5 slice, then failed only in the new focused test because the test passed the `follow` subtree to an adapter whose public API expects the root canonical config. The regression call site was corrected; no production-code rollback or behavior change was required.
- Phase 5 is complete. Live-game smoke verification remains required for party follow, fight-leader handoff, partner coordination, player/camp puller behavior, offline/rejoin identity resolution, and UI save/reload round trips before final live acceptance.

### Phase 6 — Retire the durable flat projection

Status: **IN PROGRESS — canonical startup, identity transition, apply/save/status, bridge, and UI wire paths no longer derive durable authority from flat settings; orphaned flat→canonical conversion and bounded runtime flat-read compatibility surfaces remain**

Goals:

- remove remaining durable projections from canonical config into `_G.UC_SETTINGS`;
- shrink `uc_new_settings_defaults()` to true runtime/compatibility needs or replace it with better-scoped state owners;
- remove mixed-shape normalization for normal runtime paths;
- retain compatibility wrappers only where an external/public contract still requires them;
- make any surviving `UC_SETTINGS` usage explicitly non-authoritative.

Exit criteria:

- [ ] no durable runtime behavior depends on `_G.UC_SETTINGS`;
- [ ] no durable UI write mutates `_G.UC_SETTINGS` as source of truth;
- [ ] canonical config is the only durable authority;
- [ ] mixed flat/nested normalizer ambiguity is removed from normal runtime;
- [ ] compatibility surfaces are documented and intentionally bounded.

### 2026-10-07 — Phase 6 bridge post-edit projection retired

- Retired the bridge's canonical-edit → flat-writeback loop. `uc_apply_active_list_edit(...)` now mutates active Profile V2 through the existing canonical editor API, invalidates the next bridge state snapshot, and returns; it no longer calls `project_flat_settings` or `sync_flat_settings_in_place`.
- Removed `uc_sync_active_config_flat_projection()` from `remote_bridge.lua`. Compatibility edit operations retained from Phase 5 therefore cannot republish durable policy into the legacy flat settings table.
- This cut is intentionally narrower than removing all bridge flat state. The remaining bridge `UC_SETTINGS` references are separately classified as the legacy generic `op=set` writer, config-status observation, and runtime `Start_Engine` compatibility mirroring. The read-only `active_config` state snapshot still uses one `project_flat_settings(active_profile, {})` translation for the existing WinForms/editor wire shape; it does not publish into runtime settings.
- Added `tests/replay/harness/selftest_phase6_bridge_projection_retirement.lua`. It proves canonical edits leave contradictory flat settings untouched while canonical follow runtime behavior immediately observes the edits; statically it requires the bridge edit helper to contain no `project_flat_settings`, `sync_flat_settings_in_place`, or direct flat-settings access.
- The Phase 6 CI gate reruns every Phase 5 write-pipeline suite after the new regression, freezing the assumption that migrated runtime domains do not require post-edit flat publication.
- Flat-surface burn-down in `remote_bridge.lua`: direct `UC_SETTINGS` references **11→10**; `project_flat_settings` calls **2→1**; `sync_flat_settings_in_place` calls **1→0**.
- Workflow `37691665746` initially failed in the older Phase 5 targeting-list static contract because that test still required the just-retired bridge projection helper. Its dynamic canonical behavior had passed. The stale assertion was inverted to require no flat publication; no production rollback was needed.
- Implementation head `fa9b3673c23548ec997542e67120a20ffd8ec30f` is proven by workflow `37691933955`: Phase 6 bridge projection-retirement PASS, every Phase 5 write-pipeline suite PASS, Profile V2 flat-surface guard PASS at the 10-reference / one-read-only-projection bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The next independent Phase 6 slice is the generic legacy bridge `op=set` path. Normal WinForms durable edits have been unable to send it since Phase 5, but `remote_bridge.lua` still accepts that compatibility message and writes `_G.UC_SETTINGS` directly through `apply_set(...)`; retiring or canonicalizing that latent flat writer is the next clean authority cut.

### 2026-10-07 — Phase 6 generic bridge `op=set` writer retired

- Removed the generic bridge `op == 'set'` receiver and the entire `apply_set(path, value)` flat mutation subsystem from `remote_bridge.lua`.
- Removed `last_cfg_version` / `cfg_version`; version gating existed only for the retired generic set protocol.
- Removed the generic setter's path-specific coercion/validation/diagnostic branches for follow distances, spacing, pathing selectors/ranges, COR crooked-roll slot, `def_heal_min_missing_hp`, and `def_remove_enemy_buffs`. Those code paths were unreachable from supported WinForms because Phase 5 `Forward(...)` consumes generic `op=set` locally and returns before mirror enqueue.
- The WinForms internal `op=set` messages intentionally remain as a local durable-edit signal: `Forward(...)` captures the per-session working Profile V2 and never sends them to the addon. Explicit runtime/session operations remain separately allowlisted.
- Updated historical config-status/first-consumer tests that previously froze `apply_set` and `cfg_version` as protected bridge behavior; they now assert those retired surfaces stay absent.
- Added `tests/replay/harness/selftest_phase6_bridge_generic_set_retirement.lua`, proving the bridge no longer accepts generic set messages or contains a generic flat writer/version gate, while WinForms still treats local `op=set` as a working-Profile-V2 capture signal before the outbound boundary.
- Flat-surface burn-down in `remote_bridge.lua`: direct `UC_SETTINGS` references **10→9**; `bridge_apply_set` allowance **2→0**; the sole read-only `project_flat_settings(active_profile, {})` editor snapshot remains; flat sync remains **0**.
- Workflow `37693099436` first exposed a stale Phase 5 follow regression marker because deleting the preceding generic-set branch changed `set_partner` from `elseif` to the first `if` branch. After correcting that static marker, workflow `37693237235` reached the Phase 6 gates and exposed only the earlier Phase 6 regression's expected baseline of 10 versus the new 9 references. The baseline was lowered; neither failure required a production-code rollback.
- Implementation head `38c97c63b576512a019ceb490b27cef7813d37d9` is proven by workflow `37693486987`: generic bridge set retirement PASS, bridge projection-retirement PASS, all Phase 5 pipelines PASS, flat-surface guard PASS at 9 bridge references, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The next bridge flat-read slice is config-status publication. Both bridge snapshots currently pass `_G.UC_SETTINGS` into `uc_config_runtime.config_contract_status(...)`, but the accessor returns the already-published cloned `_G.UC_CONFIG_CONTRACT_STATUS` first; the flat settings argument is therefore inert coupling in normal runtime.

### 2026-10-07 — Phase 6 bridge config-status flat read decoupled

- Removed the two inert `_G.UC_SETTINGS` arguments from bridge config-status publication. Both options/state snapshots now call `uc_config_runtime.config_contract_status(nil, nil, nil, _G.UC_CONFIG_CONTRACT_STATUS)`, preserving the accessor's clone semantics while making the already-published status object explicit.
- This does not change normal runtime status behavior: `config_contract_status(...)` has always returned a clone of the supplied/current published status before invoking the normalizer, so the previous flat-settings argument was unreachable in the supported bridge lifecycle.
- Updated config-status consumer tests to require the published-status accessor call and prohibit `config_contract_status(_G.UC_SETTINGS)`.
- Added `tests/replay/harness/selftest_phase6_bridge_status_decoupling.lua`. It proves status can be cloned with no settings input, nested status data is cloned rather than aliased, both bridge snapshots use the settings-free publication path, and no flat settings are republished.
- Flat-surface burn-down in `remote_bridge.lua`: direct `UC_SETTINGS` references **9→7**; the sole read-only editor `project_flat_settings(active_profile, {})` projection remains; flat sync remains **0**.
- Historical Phase 6 bridge regressions were lowered to the new seven-reference baseline so each prior cut remains enforced at the current tighter boundary.
- Implementation head `868a900ce9126cc08153aba6b96a09821771ac6a` is proven by workflow `37700397358`: bridge status decoupling PASS, generic-set retirement PASS, bridge projection-retirement PASS, all Phase 5 pipelines PASS, flat-surface guard PASS at seven references, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The remaining bridge flat references are now the header's compatibility note plus the runtime `Start_Engine` → `UC_SETTINGS.engine_enabled` mirrors. Those are command/runtime state rather than durable policy and require a separate consumer audit before retirement.

### 2026-10-07 — Phase 6 live engine command mirror retired

- Made global `Start_Engine` the sole live engine start/stop command state. Bridge `toggle`, `start_engine`, and `stop_engine` operations no longer mirror their result into `_G.UC_SETTINGS.engine_enabled`.
- Removed the corresponding flat engine mirror writes from addon slash commands `//uc start` and `//uc stop`, so UI and slash-command control now share the same runtime-state contract.
- `uc_domain_enabled(...)` now gates non-follow live domains from `Start_Engine` instead of `settings.engine_enabled`; follow keeps its established independent canonical ownership semantics.
- Profile contract status now reports `engine_enabled = Start_Engine == true`, and the scheduler debug overlay reports `Start_Engine` directly, eliminating the two visible consumers that could otherwise become stale after removing the mirror.
- The initialization/default compatibility fields `engine_enabled` and `command.engine_enabled_default` are intentionally not removed in this slice; they remain part of legacy normalization/profile compatibility rather than live command authority.
- Added `tests/replay/harness/selftest_phase6_engine_command_authority.lua`, proving bridge commands, slash commands, domain gating, profile-status reporting, and scheduler diagnostics all use live `Start_Engine`, while the bridge contains no direct flat-settings access.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references **7→0**. The bridge allowlist now permits only its single read-only `project_flat_settings(active_profile, {})` editor-wire translation. `UnifiedCombat.lua` direct `UC_SETTINGS` references also fell **77→71**.
- Verification surfaced only expected test/guard maintenance: workflow `37700954876` caught the addon flat-surface count reduction; `37701105233` and `37701209317` exposed two source-marker mistakes in the new static regression; `37701327180` proved the engine regression itself green but then failed an unrelated extra direct Linux invocation of an older Windows-path test. The focused gate was corrected without any production rollback.
- Final implementation/test head `fedfaa4668694b9613c2ee6bcfb79e29089af116` is proven by workflow `37701437816`: engine command-authority PASS, all prior Phase 6 gates PASS, every Phase 5 pipeline PASS, flat-surface guard PASS with zero bridge `UC_SETTINGS` references, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The bridge now has one remaining flat compatibility mechanism: its **read-only** `active_config` payload is built through `project_flat_settings(active_profile, {})` because `RuntimeProfileEditorAdapter` still expects the projected editor shape. Retiring that projection is an isolated UI wire-format migration, not a runtime-authority cut.

### 2026-10-08 — Phase 6 canonical runtime editor wire completed

- Removed the final bridge-side canonical→flat editor projection. `remote_bridge.lua` now sends the active Profile V2 object directly as `state.active_config`; it contains **zero** direct `UC_SETTINGS` references and **zero** `project_flat_settings(...)` calls.
- Runtime/session state remains outside canonical configuration. In particular, `Start_Engine` and runtime option catalogs stay on the surrounding session snapshot rather than being injected into `active_config`.
- Added `UnifiedCombatWinForms/CanonicalRuntimeEditorProjection.cs` as the sole canonical Profile V2 → flat editor-model translation boundary. The existing WinForms control model and `StructuredProfileV2Writer` persistence contract remain unchanged; only the source wire shape changed from addon-projected flat state to canonical `config.*`.
- `RuntimeProfileEditorAdapter.Build(...)` now invokes the canonical projector and then hydrates only live/session-owned fields such as `engine`, `Start_Engine`, ability/WS/action catalogs, and party option lists from the session snapshot.
- The projector covers durable combat/WS/recurring/pulling, abilities, defensive support, encounters, spacing/pathing/formations, follow/partner/Nyzul identities, targeting/reactions/tank/RUN/sleep/spells, COR/BRD/GEO/food, SMN/PUP/SCH, debug, ownership, and legacy editor fields. Durable names/lists remain names/lists; runtime party IDs are not reintroduced into the editor contract.
- Kept a bounded transitional fallback for an older addon snapshot that still sends the already-projected editor object. This compatibility path is local to WinForms and does not restore addon flat authority.
- Reworked `RuntimeProfileEditorAdapterTests.cs` around a full canonical Profile V2 reconnect fixture and retained a legacy-projected-snapshot compatibility case. The canonical fixture round-trips through `StructuredProfileV2Writer` and explicitly covers runtime engine hydration, follow identities, durable partner names, defensive targeted buffs, formation roster/geometry, targeting/sleep lists, tank pet-enmity policy, food, path fallback, and ownership gates.
- Added `tests/replay/harness/selftest_phase6_canonical_editor_wire.lua`, proving the bridge publishes `active_profile` directly, the adapter performs the local canonical projection, session command state stays outside canonical config, and the durable writer remains the save boundary.
- Removed `remote_bridge.lua` from `profile_v2_flat_surface_allowlist.lua` entirely. All earlier Phase 6 bridge regressions now require both direct `UC_SETTINGS` and `project_flat_settings` counts to remain **0**.
- Initial workflow `37857205931` caught two test-contract issues rather than production regressions: the WinForms source-contract test itself introduced the guard literal `project_flat_settings(`, and the new canonical reconnect fixture used invalid generic-formation values. Workflow `37857272652` retained the formation-fixture failure after the guard assertion was made guard-neutral. The fixture was corrected to a valid Sortie generic formation with matching canonical encounter policy, `polar_band` placement, valid boss anchoring/axis, and a required-party constraint.
- Implementation head `d4440e684012d96046f86f49ff195f18f7326131` is proven by workflow `37857378221`: Phase 6 canonical editor wire PASS, all prior Phase 6 gates PASS, every Phase 5 pipeline PASS, flat-surface guard PASS with no bridge allowlist entry, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The next independent Phase 6 slice is **Profile V2 apply publication**. `uc_profile_v2.apply_result_to_active_profile(...)` still creates a flat `candidate` through `uc_active_config.project_flat_settings(...)` for conversion verification, and `UnifiedCombat.lua::uc_apply_profile_v2_file(...)` then publishes that candidate into `_G.UC_SETTINGS` through `sync_flat_settings_in_place(...)`. Separating conversion validation from flat runtime publication is the next clean authority cut.

### 2026-10-09 — Phase 6 Profile V2 apply publication retired

- Retired the full-profile canonical→flat publication performed during Profile V2 apply/reload. `UnifiedCombat.lua::uc_apply_profile_v2_file(...)` now builds and validates the canonical active profile, publishes it through `uc_active_config.set_active_profile(...)`, and stops; it no longer calls `sync_flat_settings_in_place(...)` or normalizes a projected flat mirror afterward.
- Refactored `uc_profile_v2` conversion proof so `apply_result_to_active_profile(...)` compares the built `active_profile.config` directly against the file's canonical `payload.config`. The module no longer calls `project_flat_settings(...)` anywhere.
- Added canonical file comparison/apply APIs: `diff_structured_profile_file_against_config(...)`, `inspect_structured_profile_file_against_config(...)`, `inspect_structured_profile_status_against_config(...)`, and `apply_structured_profile_file_to_active_config(...)`. Existing settings-based helpers remain as bounded compatibility wrappers that first normalize their input and delegate to the canonical path.
- The transitional `build_settings_candidate_from_structured_profile(...)` name remains for callers/tests, but it no longer builds a flat candidate. Successful conversion returns `active_profile` plus `candidate_config`; `candidate` and `projected_settings` are absent.
- Moved post-apply status, diff, auto-reload verification, config-contract status, and identity-load inspection onto the active canonical config. A successful reload therefore reports file/runtime equality without requiring `_G.UC_SETTINGS` to be rewritten.
- Moved addon Save and explicit `//uc profilev2 export` onto `build_structured_profile_from_active_profile(...)`. Saving immediately after a reload now serializes the authoritative active Profile V2 rather than a potentially stale flat settings shadow.
- Flat/transient state is intentionally not overwritten by a Profile V2 apply. This preserves session-owned route identity/points and other compatibility state while migrated runtime policy continues to read canonical config.
- Added `tests/replay/harness/selftest_phase6_profile_apply_publication_retirement.lua`. It deliberately opposes stale flat combat/food state to canonical Profile V2, proves conversion leaves the flat table untouched, proves canonical runtime readers observe the applied policy, proves save/export sources active Profile V2, and statically prohibits flat publication from the addon apply block.
- Converted the PUP, Scholar, legacy-food, recurring-spell, source-of-truth, config-status, and comprehensive Profile V2 export/apply regressions from projected-flat post-apply assertions to canonical `candidate_config`/active-profile assertions. The live extracted addon apply regression now explicitly requires the flat settings table to remain byte-for-byte unchanged while the canonical active profile changes.
- Flat-surface burn-down: `uc_profile_v2.lua` `project_flat_settings(...)` calls **1→0** and is removed from the flat-surface allowlist; `UnifiedCombat.lua` direct `UC_SETTINGS` references **71→61** and `sync_flat_settings_in_place(...)` references **3→2**.
- The first verification after the production cut exposed one stale config-status static assertion that still required `UC_CONFIG_NORMALIZER.normalize(settings, meta)`. It was updated to require canonical `uc_current_profile_v2_config(...)`; no production rollback was needed.
- Implementation/test head `921e1a160b195bdcea1b1cc217d6fcee0f4d1efd` is proven by workflow `37917685735`: the new apply-publication retirement gate PASS, every prior Phase 6 gate PASS, every Phase 5 pipeline PASS, Profile V2 flat-surface guard PASS at the reduced baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The next independent Phase 6 slice is **safe identity/default bootstrap**. `uc_initialize_safe_profile_v2_identity(...)` still resets the entire `_G.UC_SETTINGS` table from `uc_new_settings_defaults()`, applies job defaults there, normalizes it, and only then builds the canonical active profile. That is now the only live full-table `sync_flat_settings_in_place(...)` publication in the addon. The other addon sync literal is an uncalled local compatibility alias, and `uc_active_config.project_flat_settings(...)` itself has no production callers; once bootstrap is canonicalized those orphaned compatibility surfaces can be retired cleanly.

### 2026-10-09 — Phase 6 safe identity/default bootstrap canonicalized

- Replaced the identity-transition default path that previously rebuilt `_G.UC_SETTINGS` from `uc_new_settings_defaults()`, applied legacy job defaults into that global table, normalized it in place, and then derived a new active profile from the flat result.
- Added `uc_active_config.build_default_active_profile(...)`. It starts from `uc_config_normalizer.default_config(meta)`, applies the current engine state only to the compatibility command default, applies the legacy per-job WS/ability defaults directly to canonical `config.combat.weaponskill.primary` and `config.abilities`, and returns a validated Profile V2 active profile.
- Preserved the exact old ability-default semantics: sparse legacy job slots are compacted in order before becoming `config.abilities.configured`, matching the old `uc_normalize_abilities(...)` behavior; the compact list is also retained in `legacy_slots` strictly as compatibility data. Job default WS/abilities remain configured but disabled by default, as before.
- `uc_initialize_safe_profile_v2_identity(...)` now requires only exact identity, builds canonical safe defaults through `build_default_active_profile(...)`, and publishes them with `set_active_profile(...)`. It contains no `UC_SETTINGS` access, no `uc_new_settings_defaults()`, no flat normalizer pass, no `build_active_profile_from_settings(...)`, and no flat sync.
- Removed the now-unused `uc_apply_job_defaults(...)` global-flat mutator. Numeric job IDs are still resolved through the new pure `uc_job_default_key(...)` helper before canonical defaults are selected.
- Removed the dead addon-local `uc_sync_table_in_place` alias. `UnifiedCombat.lua` now contains **zero** `sync_flat_settings_in_place(...)` calls.
- Added `tests/replay/harness/selftest_phase6_safe_identity_bootstrap.lua`. It proves exact Profile V2 identity/source/profile-key construction, current engine compatibility default, WAR/SAM/DRG job-default behavior including sparse DRG ability compaction, no-default-job behavior, canonical publish, and—critically—that a deliberately contradictory/stale `_G.UC_SETTINGS` table is left byte-for-byte untouched.
- The regression also statically freezes the authority boundary: the safe identity helper may call only the canonical default builder/publisher and is prohibited from touching the flat settings table, flat default builder, flat normalizer, flat sync, or flat→canonical active-profile builder.
- Flat-surface burn-down in `UnifiedCombat.lua`: direct `UC_SETTINGS` references **61→54** and `sync_flat_settings_in_place(...)` literals **2→0**.
- Implementation/test head `62ef3f3e416a12530cf9d7b9cd213780e81d5c71` is proven by workflow `37985299481`: safe identity bootstrap PASS, all prior Phase 6 gates PASS, every Phase 5 write pipeline PASS, flat-surface guard PASS at the reduced baseline, full Lua sequence PASS, and WinForms/Profile V2/RUN/reaction/Activity Profile tests PASS.
- Post-cut direct source audit confirms `UnifiedCombat.lua`, `uc_profile_v2.lua`, and `remote_bridge.lua` all contain **zero** `project_flat_settings(...)` and **zero** `sync_flat_settings_in_place(...)` calls. The only remaining definitions live in `uc_active_config.lua`, and they have no production callers.
- The next independent Phase 6 slice is therefore **orphaned flat projection/sync API retirement**: remove `uc_active_config.project_flat_settings(...)` and `sync_flat_settings_in_place(...)`, then convert or delete regressions that exist only to preserve those retired canonical→flat compatibility contracts. Keep the separate initial addon-load flat→canonical `initialize_active_profile(_G.UC_SETTINGS, ...)` seam explicitly tracked for a later bootstrap cut rather than conflating the two directions of compatibility.

### 2026-10-10 — Phase 6 orphaned flat projection/sync API retired

- Removed `uc_active_config.project_flat_settings(...)` and `sync_flat_settings_in_place(...)` completely. No production module retains either canonical→flat API.
- Deleted the private canonical→flat implementation rather than leaving dead serialization code behind: `apply_structured_config_to_candidate(...)`, durable-name→runtime-ID projection helpers, defensive targeted-buff serialization, BRD targeted-song serialization, SCH storm serialization, Summoner flat-gate projection, and related compatibility-only helpers are gone.
- `uc_active_config.lua` shrank from **1,787 lines / 67,816 bytes** at the preceding verified head to **857 lines / 25,441 bytes** after this cut.
- Preserved the opposite-direction compatibility intentionally: `build_active_profile_from_settings(...)` and `initialize_active_profile(...)` remain because initial addon startup still performs one flat→canonical bootstrap. They are explicitly not part of the retired canonical→flat contract.
- Converted projection-dependent domain regressions to assert canonical state directly: Kei, generic/named formations, PUP, configurable puller/Sleep ranges, SCH, reaction runtime, Summoner, active-config coverage, runtime consumers, and Profile V2 source-of-truth tests.
- Projection-only round trips were removed rather than recreated through a test-only adapter. Runtime-ID behavior remains covered by the dedicated Phase 5 follow/COR identity suites, where live name→ID resolution now actually belongs.
- Added `tests/replay/harness/selftest_phase6_flat_projection_api_retirement.lua`. It requires both retired module members to be nil, prohibits the old serializer/helper graph from returning, requires addon/bridge/Profile V2 production sources to contain no projection/publication calls, and explicitly freezes the separate initial flat→canonical bootstrap seam for the next cut.
- Tightened `profile_v2_flat_surface_allowlist.lua`: `uc_active_config.lua` now has **0 allowed `project_flat_settings`** and **0 allowed `sync_flat_settings`** hits; only its four still-tracked `UC_SETTINGS` compatibility references remain.
- Exact PR-head source audit confirms `UnifiedCombat.lua`, `remote_bridge.lua`, `uc_profile_v2.lua`, and `uc_active_config.lua` each contain **0** `project_flat_settings(...)` calls and **0** `sync_flat_settings_in_place(...)` calls.
- Initial workflow `38096450801` (and its rerun) failed before either job produced a single step because GitHub Actions billing blocked runner startup; the same occurred on the first documentation-head run. After the repository was made public, hosted runners executed normally and exposed two **test-only** cleanup regressions from deleting the projection API: `selftest_profile_v2_runtime_consumers.lua` normalized an identity-preserved active-profile table after installing a second profile, and several Phase 5 write-pipeline regressions still called the retired `project_flat_settings(...)` API. The runtime-consumer test now normalizes the original profile before replacement, and all ten Phase 5 write-pipeline files were audited so no real projection calls remain; meaningful live identity coverage was moved to the runtime adapters that own it.
- Final implementation/test head `c39abc4dcc22fc45087115e2a7b65a549b1359be` is **CI-proven** by workflow `38167177476`: full Lua sequence PASS, Phase 6 flat-projection API retirement PASS, every prior Phase 6 gate PASS, every Phase 5 write pipeline PASS, WinForms build PASS, full Profile V2 self-test PASS, RUN/reaction persistence PASS, and Activity Profile tests PASS.
- The next independent Phase 6 slice is **initial addon flat→canonical bootstrap**: replace `uc_active_config.initialize_active_profile(_G.UC_SETTINGS, { source = 'UC_SETTINGS' })` at addon load with a canonical default bootstrap, while retaining `_G.UC_SETTINGS` only for truly transient/legacy compatibility state.

### 2026-10-11 — Phase 6 initial addon bootstrap canonicalized

- Retired the final live startup call to `uc_active_config.initialize_active_profile(_G.UC_SETTINGS, ...)`. `_G.UC_SETTINGS = uc_new_settings_defaults()` still creates the transient/legacy runtime table, but it is no longer an input to startup durable configuration.
- Startup now builds `uc_startup_active_profile` directly through `uc_active_config.build_default_active_profile({ source = 'UC_DEFAULTS', engine_enabled = Start_Engine == true })` and publishes it with `set_active_profile(...)`.
- Startup intentionally does **not** pass `UC_JOB_DEFAULTS`. This preserves the old pre-identity behavior: even when `windower.ffxi.get_player()` already exposes a SAM/DRG/etc. identity, job-specific WS/ability defaults remain deferred to the exact Profile V2 identity transition.
- Removed the now-orphaned `uc_active_config.initialize_active_profile(...)` wrapper and the dead addon-local `uc_sync_active_profile_from_settings(...)` helper. No production code now performs generic flat-settings → active-profile publication.
- Added `tests/replay/harness/selftest_phase6_initial_canonical_bootstrap.lua`. It dynamically extracts the old `uc_new_settings_defaults()` table, builds the historical flat-normalized active profile, compares it with the new canonical startup profile, and statically freezes the no-flat-input startup boundary.
- That equivalence test surfaced exactly one intentional historical leak: the old flat bootstrap imported transient v1 storage `profiles = { UC = {} }` into `config.legacy.profiles.UC`. Canonical startup keeps `config.legacy.profiles = {}`. After excluding that transient profile-storage tree, the old and new durable startup configs diff at **0** paths.
- The focused test also proves a visible SAM identity at startup still receives no `Tachi: Kasha` or job-default ability list until the later exact-identity bootstrap.
- Updated the preceding flat-projection retirement gate so the old startup wrapper is now required to remain absent while the lower-level `build_active_profile_from_settings(...)` compatibility converter remains temporarily isolated for a separate cleanup.
- Flat-surface burn-down in `UnifiedCombat.lua`: direct `UC_SETTINGS` references **54→50**. Production occurrences of `initialize_active_profile(...)` are now **0**; production calls to `build_active_profile_from_settings(...)` are also **0**.
- Workflow `38181543720` first proved every earlier Phase 5/6 gate green and failed only in the new equivalence test because it initially required literal zero differences. The test was tightened to characterize the single transient `config.legacy.profiles.UC` leak instead of preserving it.
- Final implementation/test head `f67eafeb8fc7531ade2acd8ed9ccc691e4845263` is **CI-proven** by workflow `38181741718`: initial canonical bootstrap PASS, every prior Phase 6 gate PASS, every Phase 5 write pipeline PASS, full Lua sequence PASS, WinForms build PASS, full Profile V2 self-test PASS, RUN/reaction persistence PASS, and Activity Profile tests PASS.
- Post-cut direct source audit confirms `UnifiedCombat.lua`, `uc_profile_v2.lua`, and `remote_bridge.lua` contain **0** calls to both `initialize_active_profile(...)` and `build_active_profile_from_settings(...)`. `uc_active_config.lua` retains only the latter function definition; its private party-ID→name/wait-ignore recovery helpers are now referenced only by that orphaned converter.
- The next independent Phase 6 slice is therefore **orphaned flat→canonical active-profile conversion retirement**: remove `uc_active_config.build_active_profile_from_settings(...)` and its now-private compatibility helper graph, then convert the small set of tests that still use it as legacy fixture construction. Keep the broader settings normalizer/Profile V2 import/export compatibility APIs separately scoped until their own consumer audit.

### 2026-10-12 — Phase 6 orphaned flat-to-canonical profile converter retired

- Removed `uc_active_config.build_active_profile_from_settings(...)` and the private party-ID-to-name / wait-ignore recovery helpers used only by that obsolete conversion.
- Converted legacy startup equivalence and active-config regression construction into test-local normalization fixtures; the legacy food-apply regression now constructs its active profile canonically, without resurrecting the removed production API.
- Strengthened Phase 6 flat projection and startup guards to require the converter to remain absent.
- Tightened `uc_active_config.lua` `UC_SETTINGS` flat-surface allowlist from **4 to 2**, preserving the source-burn-down guard.
- Retained `uc_config_normalizer.normalize(...)` and Profile V2 import/export compatibility, pending their separately scoped consumer audit.
- CI workflow `38297021964`: full Lua sequence **PASS**, including phase guards and converted regressions; WinForms verification was in progress at the time of this ledger update.
- The next Phase 6 work is the remaining bounded runtime flat-read / compatibility surface audit, not another startup or generic flat-to-canonical profile converter.

### 2026-10-13 — Phase 6 bounded flat-read audit: tank pet-enmity precedence

- Inspected the remaining compatibility surfaces in `uc_scheduler_config.lua`, `uc_runtime_overrides.lua`, `uc_config_runtime.lua`, and `uc_combat_extension_config.lua`.
- Found a concrete flat-first durable authority leak: `uc_scheduler_config.tank_enmity_include_pets(settings)` preferred `settings.tank_enmity_include_pets` over an explicitly configured `config.tank.enmity.include_pets`.
- Corrected the reader to honor canonical true **and** canonical false; flat compatibility is consulted only if the canonical leaf is missing.
- Added contradictory-state coverage to the Phase 3 exit regression and updated the older tank-pet-enmity config regression that previously enshrined flat-first behavior.
- Broader runtime compatibility remains tracked for separate cuts, especially `uc_runtime_overrides` flat-first target-control / Sleep helper paths and reaction-rule merging in `uc_combat_extension_config`; the latter needs a specific reaction/UI workflow audit before removal.
- CI workflow `38410315350` is the verification for the final implementation/test head `d6c7c71d97e04bf2af0d554f475c52da0d69f6f8` (pending at this documentation update).

### 2026-10-13 — Phase 6 runtime-override targeting and Sleep authority cut

- Audited `uc_runtime_overrides.lua` and its legacy callers/tests. The targeting priority and Sleep readers still chose flat settings even when canonical Profile V2 explicitly disagreed.
- `add_priority_names(...)` now reads durable `config.targeting.targets` first (with the old canonical `add_priority_names` alias only if needed). Explicit empty canonical lists stay empty.
- `sleep_enabled(...)` now honors canonical `config.sleep.enabled` first, including false. `sleep_spell_names(...)` honors canonical `config.sleep.order` / `legacy_primary` and never resurrects flat spells when canonical Sleep is present but empty.
- Flat fallback remains only when the corresponding canonical domain/leaf is absent for pre-profile compatibility. Fight-leader adapters were left untouched.
- Updated `selftest_runtime_overrides.lua` with deliberately contradictory flat/canonical state, empty-list cases, and pre-profile fallback. Updated Sleep selection source guard to freeze the canonical-first read.
- Verification workflow `38516094428` validates this implementation (pending at ledger authoring).
- Next audit target remains reaction-rule merging in `uc_combat_extension_config.lua`, which requires identifying legitimate UI/workflow paths before cutting flat influence.

### 2026-10-13 — Phase 6 canonical reaction-rule collection

- Removed `uc_combat_extension_config.reaction_rules()` merging flat `party_action_complete` rules into canonical Profile V2 rules. Previously stale flat state could silently add a party-action trigger or resurrect action/sequence rules after the user disabled/removed them canonically.
- An existing `config.reactions` domain now owns the complete ruleset: enabled=true returns canonical rules unchanged; disabled or empty canonical rules return an empty collection. Legacy flat `reaction_enabled`/`reaction_rules` are read only when the entire canonical reactions domain is absent for pre-profile compatibility.
- Removed private action-rule identity/merge helpers used only by the retired flat merge. Left action/sequence validation and all runtime dispatch behavior unchanged.
- Extended `selftest_combat_extensions.lua` with contradictory canonical/flat party-action sequence rules, canonical-disabled and canonical-empty cases, and pre-profile fallback coverage.
- Verification workflow `38518033226` runs full Lua and WinForms gates for implementation/test head `2910cbaf72e4e27ee22150c7852bc09bd8e35359`.

### 2026-10-13 — Phase 6 combat-extension auto-engage/Magic Burst cutover

- Audited `uc_combat_extension_config.lua`, `uc_combat_extensions_base.lua`, and `uc_provider_combat.lua`. The primary auto-engage provider already invokes `auto_engage_enabled_from_config(ctx.config)`, while the Magic Burst proposal collector still passed `ctx.settings` through a global/flat-compatible reader.
- Added `uc_combat_extension_config.magic_burst_from_config(config)` and routed scheduler Magic Burst collection through the explicit tick-stable `ctx.config` snapshot. A legacy/no-config caller can still invoke `magic_burst(settings)`, but it cannot affect normal canonical scheduler proposals.
- Sealed missing-leaf flat fallbacks: canonical `config.spells` with no `magic_burst` flag defaults disabled rather than consulting stale flat `magic_burst_enabled`; canonical `config.combat` without `auto_engage` defaults enabled rather than consulting stale flat `auto_engage`. Flat fallback remains only when the corresponding canonical domain is absent.
- Centralized burst normalization so canonical and legacy paths consistently interpret exact/auto mode, spell/ra/helix family, configured spell, and 0–5 maximum tier.
- Expanded `selftest_combat_extensions.lua` with contrary canonical-vs-flat settings, missing-leaf cases, normalization checks, and Magic Burst proposals proving the tick config wins over stale live/global state.
- Implementation and test head `31f97c014f00d9bbe0010065773dbe42a10ba5c3` is **CI-proven** by workflow `38518439374`: full Lua sequence PASS, WinForms build/Profile V2 and Activity Profile tests PASS.
- Next Phase 6 work: audit and retire remaining bounded legacy flat read surfaces, especially no-canonical-config entrypoints and status/debug compatibility paths, without weakening valid startup or explicit legacy caller behavior.

### 2026-10-13 — Phase 6 config-runtime canonical UI/status fallback cut

- Audited `uc_config_runtime.lua` and its live callers. `melee_engine.lua` and `dd2_module.lua` call `ingame_ui_enabled(_G.UC_SETTINGS)` during rendering; `remote_bridge.lua` already provides the published `_G.UC_CONFIG_CONTRACT_STATUS` to `config_contract_status(...)`.
- Added an explicit read-only check for the published `UC_ACTIVE_PROFILE` Version 2 envelope. In-game UI visibility now uses `config.ui.show_ingame_ui` directly when canonical state exists; an absent canonical UI/domain defaults hidden instead of resurrecting stale flat settings. The old legacy normalizer/visibility fallback remains only when no canonical profile exists.
- The compact status accessor still returns a cloned explicit/published status first. When neither status snapshot exists but an active Profile V2 is present, it now validates/enumerates that active config and reports canonical profile identity/source without invoking the flat settings normalizer. Existing no-active-profile diagnostic normalization remains a legacy fallback.
- Retained the independent `normalize_current_config(...)` normalization API for intentional import/tests; no arbitrary full normalized config is published to the bridge.
- Expanded `selftest_config_first_consumer.lua` and `selftest_bridge_config_status_consumer.lua` with contradictory canonical/flat state, missing canonical UI leaf/domain, active-status identity/source, no-flat-normalization checks, and no-normalizer canonical availability.
- Implementation and test head `eae62f64527d671e2fe04f4fb9f6405f3eea9483` is **CI-proven** by workflow `38519010323`: full Lua sequence PASS and WinForms build/Profile V2/Activity Profile self-tests PASS.
- Remaining separate Phase 6 targets: classify `uc_scheduler_config.lua` canonical-first flat fallback accessors and `uc_scheduler_context_utils.get_settings()` / legacy core no-config entrypoints by actual runtime consumers. Keep transient/runtime settings distinct from durable authority.

### 2026-10-14 — Phase 6 scheduler-domain fallback authority and no-config seam audit

- Audited `uc_scheduler_config.lua`, `unified_scheduler.lua`, `unified_combat_core.lua`, `uc_scheduler_context_utils.lua`, and `unified_engine.lua` for canonical-vs-flat ownership.
- Replaced the generic exported `active_value_or_flat(...)` facade with private, domain-aware `canonical_or_legacy(...)`. A missing leaf under an existing canonical debug/combat/tank/defensive domain now uses the canonical default (false or empty action list) instead of stale flat settings. Explicit canonical true/false continues to win; entirely absent canonical domains retain legacy fallback for actual no-profile callers.
- Hardened all scheduler debug controls (enabled, combat/JA/defensive/tank logs, and action timeline), autotarget/Prime, tank enabled/actions/pet inclusion, and defensive enemy-buff removal against the missing-leaf fallback leak. The action-timeline process-global override `UC_DEBUG_ACTION_TIMELINE` remains effective only in a no-canonical-debug-domain compatibility context.
- Fixed `unified_combat_core.scheduler_settings_view(settings, config)` so an explicit `config.combat.prime` is read directly from its supplied canonical snapshot instead of global active/flat state. Its no-config path stays compatibility-only.
- Added contradictory canonical-vs-flat and missing-leaf cases to `selftest_phase3_exit_audit.lua`, including all debug gates, Prime, autotarget, tank settings, pet inclusion, defensive buff-removal, empty actions, and genuine no-profile legacy fallback; core Prime explicit wiring is statically guarded.
- Tightened `profile_v2_flat_surface_allowlist.lua`: generic `active_value_or_flat(` occurrences in `uc_scheduler_config.lua` **6 → 0**. The remaining `UC_SETTINGS` occurrence is the intentionally bounded pre-profile compatibility accessor.
- **No-config consumer classification:** `uc_scheduler_context_utils.get_settings()` is consumed by `unified_scheduler.lua` for mixed session/runtime state, including cadence `_sched_next_*`, Doom item-event handling, movement/action mechanics, and diagnostics. It is **not** itself an authoritative Profile V2 policy API and cannot yet be deleted or naively replaced with a canonical config table. `get_config()` remains the separate canonical accessor. `unified_combat_core.lua` retains explicit no-config movement, pull, and legacy-facing fallbacks; its scheduler-facing calls use canonical `config` where supplied.
- **Outstanding classified debt:** `unified_engine.lua`'s scheduler-overlay gate and `unified_combat_core.lua` diagnostic log helpers still inspect legacy `settings.debug` via their own `get_settings()`. These need a focused diagnostic-output audit before retirement. The remaining transient scheduler settings fields require consumer-specific treatment rather than wholesale removal.
- Workflow `38587669736` on implementation/test head `88d4e5533986ba8f93621c51e9e8eebb1deddbe8`: full Lua sequence **PASS**; WinForms verification was running when this entry was authored.

### 2026-10-14 — Phase 6 canonical diagnostic gates for engine overlay and core logs

- Audited `unified_engine.lua` scheduler-overlay gating and `unified_combat_core.lua` JA/tank diagnostic log gates. Both used `UC_SETTINGS.debug` even when canonical Profile V2 debug was explicitly disabled or enabled, so stale flats could wrongly suppress or trigger diagnostics and file creation.
- The engine overlay now checks `uc_scheduler_config.debug_enabled(s)`; `s` is deliberately retained only for transient/session domain-state diagnostics passed to `UC_DomainEnabled(s, name)`. The stale flat debug boolean and orphaned local boolean parser were removed.
- Core's `debug_log_channel` and `debug_tank` use a shared `core_debug_enabled()` adapter backed by `uc_scheduler_config.debug_enabled()`. The core's sole `get_settings()` compatibility accessor remains for pull/movement/runtime state; no generic flat-settings retirement was attempted.
- The scheduler-config facade already enforces canonical true/false and missing-leaf defaults; its no-profile flat fallback remains for genuine legacy callers. This cut routes the last two independent diagnostic gates through that proven contract rather than inventing new configuration authority.
- Expanded `selftest_phase3_exit_audit.lua` with executable `unified_engine` render gating under opposing canonical/flat values: canonical false suppresses overlay creation, canonical true shows all three panels despite flat false, later canonical false hides them, and no-profile flat true still works. Source guards freeze both core file-log gates and prohibit direct flat debug checks; the pre-existing contradictory scheduler-debug matrix remains in force.
- Flat-surface guard remains unchanged at one `UC_SETTINGS` literal in `unified_engine.lua` and exactly one `rawget(_G, 'UC_SETTINGS')` accessor in `unified_combat_core.lua`. A first CI run `38616136393` caught only a redundant source comment literal; this was removed rather than weakening the allowlist.
- Implementation/test head `ba055f5378f5c51088aee5271742f2b71f4be501` passed the full Lua sequence in workflow `38616222412`; WinForms validation was in progress when this ledger entry was committed.
- Next Phase 6 work: continue bounded inspection of legacy/no-config consumers and flat-versus-transient settings in core and scheduler; preserve session-only cadence, movement, and item-event fields until independent consumers are proven canonical.

### 2026-10-14 — Phase 6 canonical pull dispatch

- Core and scheduler caller audit separated durable pull policy from transient session state (cadence, Doom item handling, movement and domain diagnostics).
- Fixed pull dispatch: the scheduler now passes its active Profile V2 configuration to the core; the core dispatch handler uses the same canonical runtime view as pull proposal selection. No-profile callers preserve legacy compatibility.
- Added conflicting-state regression proving canonical action selection at dispatch, canonical-disabled behavior, and explicit no-profile fallback; updated the dispatcher source-contract test.
- Full Lua sequence passed in verification workflow 38619063878 on commit 1326ec1c; WinForms validation pending at the time of this note.
- Remaining Phase 6 work: audit event and revalidation entrypoints with explicit no-config behavior before changing transient settings accessors.

### 2026-10-14 — Phase 6 partner-arbitration revalidation authority cut

- Audited scheduler event handlers and action revalidation entrypoints against flat session state. Item-add/Doom confirmation, incoming action/message observations, and scheduler cadence remain intentionally transient. Weaponskill plan revalidation already takes the canonical config snapshot.
- Found a Lua and/or false-fallthrough in `scheduler.try_partner_tiebreak(settings, config)`: canonical `follow.partner.enabled=false` could be overridden by legacy `settings.partner=true`, enabling unintended partner arbitration/disengagement. The related `build_partner_target_set(settings, config)` would also consult flats if a canonical partner domain was absent.
- Added `uc_scheduler_context_utils.partner_enabled(settings, config)` as a shared canonical-first helper. Any supplied canonical config makes disabled or missing partner policy false; only genuine no-config callers use the previous legacy truthy toggle forms. Both scheduler partner arbitration and partner-target-set collection now share this gate.
- Updated `selftest_scheduler_partner_arbitration.lua` with direct contradictory-state and missing-domain behavior, pre-profile fallback, and source-contract checks requiring both scheduler consumers use the shared helper.
- Implementation and regression head `d0df452e11a9f94bca94ee1d2a0457fcad75e57d`; workflow `38620996677` full Lua sequence PASS (WinForms pending when recorded).
- The explicit reaction/face-to-target movement helper also has a canonical-false/flat-true fallthrough candidate; audit its event, forced-turn, and normal-facing consumers separately before changing that contract. Preserve the transient settings surface for movement and inventory events.

### 2026-10-14 — Phase 6 canonical ordinary facing vs. forced safety turns

- Audited every `p1_apply_face_to_target(...)` caller in `unified_scheduler.lua`: ordinary movement-tick and combat-dispatch facing are unforced, whereas RUN no-TP turning and reaction turn-away/restore requests are explicitly forced. Reaction facing does not supply a durable config snapshot but already deliberately passes `force_face=true`; that emergency path must not depend on the user's routine face preference.
- Removed the Lua `and ... or ...` false-fallthrough from the scheduler facing gate. Previously, `config.combat.face=false` followed by stale flat `settings.face=true` enabled unintended routine turns. Both normal caller paths now use a shared `uc_scheduler_context_utils.face_turn_allowed(settings, config, turn_away, force_face)` gate.
- The gate checks forced turn-away or explicit force first. Otherwise any supplied canonical Profile V2 config owns ordinary face enablement through `uc_movement_config.face_enabled(config)`, including disabled/missing canonical leaves; flat `settings.face` remains consulted only by genuine no-config legacy callers using the existing boolean parser.
- Expanded the already CI-wired `selftest_run_no_tp_mode.lua` to prove opposed canonical-vs-flat values, absent canonical face leaf/combat domain, no-profile compatibility, and safety bypasses for reaction turn-away, restoration, RUN no-TP turning, and explicit force. Updated `selftest_phase3_movement_authority.lua` to freeze the delegated source contract and retire its inline legacy flat-face expectation.
- Initial workflow `38650875426` found a stale static Phase 3 guard expecting the prior inline expression; the guard was updated without reverting the behavior or loosening any flat-surface allowance. Corrected code/test head `d7e1e91ae7adf983b03851d934d8b545d7dfac26` passed the full Lua sequence in workflow `38650971122`; WinForms verification was running when this entry was recorded.
- Next independent Phase 6 audit: identify other scheduler action/revalidation decisions with canonical-false/flat-true fallthrough or implicit no-config policy, especially reaction completion and movement/event entrypoint boundaries, without changing transient state owners.

### Phase 7 — Final cleanup and conformance

Status: **NOT STARTED**

Goals:

- remove dead compatibility adapters;
- remove obsolete flat field projections and tests that only preserve retired behavior;
- update architecture docs and README;
- run full Lua and WinForms test suites;
- perform targeted live-game acceptance across representative jobs and domains.

Required live acceptance should include at least:

- BRD maintenance;
- COR maintenance;
- GEO maintenance;
- defensive healing/buffs;
- recurring combat spells;
- tank/RUN behavior;
- WS/skillchain behavior;
- pulling;
- follow/pathing;
- SMN;
- PUP;
- SCH;
- activity profile apply;
- profile Save/reload;
- job/subjob identity transition.

Exit criteria:

- [ ] source-contract audit shows no unintended flat durable reads/writes;
- [ ] automated suites green;
- [ ] targeted live acceptance completed;
- [ ] architecture docs describe the final ownership model accurately.

## Regression scenarios that must survive the migration

These are architecture acceptance cases, not merely unit tests.

### Food and Bard sibling isolation

Given:

```lua
config.maintenance = {
    brd = {
        enabled = true,
        songs = { 'Honor March', 'Victory March' },
    },
    food = {
        enabled = true,
        item = 'Grape Daifuku',
    },
}
```

Changing `maintenance.food` must never alter, disable, default, or reinterpret `maintenance.brd`.

### Canonical false values remain authoritative

A canonical explicit `false` must not fall through to a legacy flat `true`.

### Missing canonical subtree behavior is explicit

A missing optional subtree must use canonical defaults, not resurrect stale flat compatibility values.

### Runtime state cannot become durable

Engine state, current IDs, live locks, target state, and similar transient values must never be serialized merely because they previously lived in `UC_SETTINGS`.

### UI/runtime round trip

Canonical Profile V2 -> runtime active config -> editor -> save must preserve durable semantics without requiring flat compatibility state to fill missing fields.

## Progress log

### 2026-10-02 — Migration branch created

- Created `refactor/profile-v2-single-source` from current `master`.
- Confirmed Profile V2 is already the intended durable source.
- Confirmed `_G.UC_ACTIVE_PROFILE.config` is already the intended canonical applied config.
- Identified `_G.UC_SETTINGS` as the major compatibility surface still feeding runtime consumers.
- Identified major flat producers in addon startup, active-config projection, bridge live writes, and WinForms editor/write adapters.
- Identified initial consumer families for Phase 0 inventory.
- No gameplay behavior changed.

### 2026-10-02 — Rabao BRD investigation clarified

- Confirmed BRD song maintenance is intentionally blocked in configured city zones, including Rabao.
- Confirmed the observed "BRD never sings" case in Rabao was expected city-zone behavior, not evidence of a current BRD config regression.
- The configuration migration remains necessary because the mixed flat/nested model is still structural technical debt.

### 2026-10-02 — Phase 0 inventory and guardrails completed

- Added `docs/profile_v2_flat_surface_inventory.md` as the detailed producer/consumer and field-ownership baseline.
- Added a repository-wide source guardrail that freezes direct `UC_SETTINGS`, indirect `ctx.settings`, `active_value_or_flat`, canonical-to-flat projection, bridge flat mutation, and WinForms flat write/translation seams.
- Added a machine-readable allowlist with exact current source occurrence counts. Future migration slices should shrink it; new flat seams fail the guardrail unless explicitly reviewed.
- Classified durable field families, runtime/transient state, compatibility-only aliases, and explicit ambiguous ownership decisions.
- Added the mixed nested-food + flat-BRD maintenance characterization fixture. It records the current known normalizer defect without changing runtime behavior.
- Phase 0 made documentation/test-only changes; no scheduler/provider/gameplay behavior changed.

### 2026-10-02 — Phase 1 canonical runtime read boundary completed

- Added `uc_scheduler_context_utils.get_config()` as the scheduler-owned canonical accessor over the applied `_G.UC_ACTIVE_PROFILE.config`.
- Scheduler tick contexts now expose `ctx.config` alongside the unchanged compatibility `ctx.settings` surface.
- Canonical config is sampled once when the tick context is built and passed by identity; providers do not reparse Profile V2 files.
- The context builder remains dependency-injected and does not directly require `uc_active_config`.
- Added deterministic fixture/static coverage for active-config lookup, missing-config fallback, one-sample-per-context behavior, and scheduler wiring.
- No proposal provider, ranking rule, dispatch path, or durable config consumer changed in this phase; the Phase 0 flat allowlist is intentionally unchanged.
- PR verification now runs the flat-surface guard, mixed-shape characterization, scheduler canonical-context tests, and context-utils fixtures on every migration PR update.
- Draft PR #73 is the long-lived migration/CI surface. Verification run 36981070413 passed both `lua-sequence` and `winforms` after the guardrail baseline and fixture-count expectations were corrected.
- The new guardrail immediately found three pre-existing `UnifiedCombat.lua` flat-sync call sites that the initial mechanical audit had missed; they are now explicitly baselined rather than silently ignored.

### 2026-10-02 — Mainline legacy-food compatibility hotfix incorporated

- Mainline PR #74 fixed Activity/Profile V2 apply failures for profiles created before `maintenance.food` existed.
- Legacy Profile V2 maintenance domains now materialize `food = { enabled = false, item = '' }` before canonical-to-flat compatibility projection, preventing stale live food settings from leaking into conversion validation.
- The focused regression reproduces the Etamame SAM/DRG Activity Apply failure shape and asserts the exact structured conversion path returns zero mismatch.
- The hotfix was merged to `master` as `c8a084b9a29dd412e99fa3cf5dec4e0e90cf1b3f` and has been incorporated into this migration branch before Phase 2.

### 2026-10-02 — Phase 2 low-risk leaf migration implemented

- Food maintenance and recurring combat spells now consume only the canonical scheduler snapshot at `ctx.config`; stale `ctx.settings` values are deliberately ignored.
- Defensive provider gates/resurrection, enemy-buff removal, and enemy-debuff maintenance now consume `ctx.config.defensive.*` directly.
- Raise acceptance and weakened recovery-hold now read only `uc_active_config`; their direct `UC_SETTINGS` fallback paths were removed.
- GEO camp placement now reads only `config.maintenance.geo` from active Profile V2 state.
- Defensive buff maintenance now receives canonical config explicitly from the scheduler, including structured targeted buffs and BRD ownership state; its hidden active-config/global fallback was removed.
- COR maintenance now receives canonical config explicitly from the maintenance provider. Roll policy, range requirements, Light Shot-on-Dia policy, and ability-derived roll fallback stay inside canonical `config.maintenance.cor` / `config.abilities.configured`.
- The Phase 0 allowlist shrank by 11 source-file entries / 60 literal flat-surface hits. The remaining `uc_scheduler_action_state.lua` debug-only `UC_SETTINGS` reader is intentionally deferred with the core scheduler work in Phase 3 rather than widening this leaf migration.
- Deterministic tests include intentionally conflicting stale flat values so a migrated leaf fails if flat compatibility regains authority.
- Full PR CI passed at Phase 2 verification head `a396671884229447f10ea85d5399e69a58003275` (workflow run `36992724235`): both Lua and WinForms jobs succeeded, including the flat-surface guard and the dedicated Phase 2 canonical-leaf suite.
- Added `tests/replay/harness/selftest_phase2_canonical_authority.lua`: a dedicated 21-case contradictory-state matrix whose only purpose is to prove canonical Profile V2 values beat deliberately opposite flat compatibility values across every Phase 2 consumer family.
- The matrix covers food, recurring spells, defensive provider/critical threshold, resurrection, enemy buff removal, enemy debuff maintenance, COR routing, defensive buff maintenance, COR roll selection, GEO placement, Raise acceptance, and weakened recovery hold. Both enable/disable directions are exercised where a boolean gate exists.
- Workflow run `37016053323` passed both `lua-sequence` and `winforms`; the canonical-authority matrix reported `21/21 PASS`.
- Live-game smoke verification remains before merge, especially food, recurring spells, defensive maintenance, COR upkeep, raise acceptance, recovery hold, and GEO camp placement.
- Phase 2 implementation began with `0f707e1863846dcc74d0dd56cb791cbbf8bbb0ed`; the verified Phase 2 head is `a396671884229447f10ea85d5399e69a58003275`.

### 2026-10-02 — Phase 3 combat enablement/autotarget slice implemented

- Began Phase 3 with the smallest core domain: combat enablement/target acquisition gates, specifically canonical `config.combat.autotarget` and `config.combat.auto_engage`.
- Added canonical-only scheduler helpers for autotarget and auto-engage while retaining compatibility helpers for unmigrated non-scheduler callers.
- Migrated scheduler-owned target acquisition and engage gates to `ctx.config`; contradictory flat `ctx.settings.autotarget` / `auto_engage` values can no longer change those provider decisions.
- Passed canonical tick config through core target selection, tank-enmity selection, death-switch revalidation, partner arbitration, and pre-engage combat-close movement so hidden flat autotarget fallbacks do not survive behind provider boundaries.
- Added `tests/replay/harness/selftest_phase3_combat_enablement_authority.lua` with contradictory canonical-vs-flat cases for autotarget and auto-engage plus static wiring assertions.
- Added the new Phase 3 proof to PR CI and the aggregate replay suite.
- Reduced the flat-surface guard by four `ctx.settings` hits: two from `uc_provider_target_control.lua` and two from `uc_provider_combat.lua`.
- Existing combat-extension provider coverage now supplies canonical combat config explicitly; legacy helper fallback tests remain intact for callers that have not migrated yet.
- No weaponskill, ability, pulling, target-priority, tank-policy, ranking, or dispatch semantics are intentionally changed by this slice.
- During contradictory-state proof, the first canonical auto-engage implementation exposed a Lua false-value bug: `condition and value or nil` collapsed explicit canonical `false` to `nil`, incorrectly restoring the default `true`. The canonical accessor was corrected to preserve explicit false, and the regression now proves both directions.
- Automated proof on branch head `cf827cd87f0eafe8b9917743d97ed7a2015944b2`: workflow `37023674659` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 2 canonical-authority coverage PASS, the new Phase 3 combat enablement canonical-authority test PASS, and the flat-surface guard PASS.
- Live-game smoke verification remains required before the Phase 3 core migration is considered complete.

### 2026-10-02 — Phase 3 weaponskill configuration slice implemented

- Migrated the full scheduler-owned weaponskill decision path to canonical Profile V2 authority.
- Canonical WS policy now covers `config.combat.weaponskill.enabled`, primary WS, mode, minimum TP, AoE permission, Fast Skillchain, no-skillchain target names, skillchain target preference, ally-wait ignore names, aftermath enablement, and aftermath WS.
- Included canonical `config.combat.spam` and `config.legacy.solo` in the WS view because both directly alter weaponskill arbitration/bypass behavior.
- Deliberately left `ability_active` as a compatibility input for Chivalry reservation; that belongs to the next Phase 3 abilities slice.
- Proposal collection now gates WS enablement from `ctx.config`; the core planner receives canonical config and overlays all WS-owned durable fields before selecting an action.
- Canonical config is carried through rank-commit Smart-AoE/skillchain revalidation and final WS intent dispatch, preventing a canonical proposal from being revalidated against stale flat WS policy.
- Added `tests/replay/harness/selftest_phase3_weaponskill_authority.lua` to prove canonical WS enablement beats opposite flat state and to statically require every WS-owned field at the canonical boundary.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory-state cases proving canonical primary WS, minimum TP, AoE policy in both directions, Smart vs primary-only mode, aftermath policy, and Fast Skillchain false/true behavior.
- Added the weaponskill authority suite to normal PR CI and the aggregate replay suite.
- Reduced `uc_provider_combat.lua` flat-context guard count from 26 to 25 by removing the flat `weaponskill_active` provider gate. The remaining `ctx.settings` handoff exists for explicitly unmigrated non-WS inputs such as Chivalry's ability gate.
- Automated proof on branch head `7191d7a550dcb467e3e1166f787c2f3ba719dde4`: workflow `37027431136` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill canonical-authority PASS, WS maintenance/skillchain precedence PASS, and the flat-surface guard PASS.
- No intentional weaponskill ranking, timing, TP threshold semantics, skillchain planning semantics, or dispatch behavior changed except that canonical Profile V2 now wins when flat compatibility state conflicts.
- Live-game smoke verification remains required for representative Smart WS, spam/solo, primary-no-SC, aftermath, and Fast Skillchain configurations before Phase 3 is complete.

### 2026-10-02 — Phase 3 abilities slice implemented

- Migrated scheduler-owned generic configured-JA authority to canonical `config.abilities`: enablement, allow-unengaged policy, configured ability ordering, and legacy-slot fallback.
- Added `uc_ability_pipeline.collect_ordered_from_config`; scheduler generic JA collection now chooses the ability list from Profile V2 before applying unrelated RUN ownership filtering.
- Migrated the shared allow-unengaged policy in `uc_provider_tank_enmity.lua` to canonical `config.abilities.allow_unengaged`.
- Closed the deferred Chivalry dependency from the WS slice: the scheduler WS settings view now overlays canonical ability enablement, configured abilities, and legacy slots before Chivalry TP-reservation logic runs.
- Discovered a hidden post-proposal authority leak in `uc_scheduler_ranker.lua`: proposals carrying `required_setting` were rechecked directly against `ctx.settings`. This could silently override canonical `autotarget`, `weaponskill_active`, and `ability_active` decisions after a proposal had already been built.
- Added `uc_scheduler_config.required_setting_value_from_config` and migrated ranker validation so those three already-migrated settings revalidate against canonical config; unknown/unmigrated required settings such as Sleep intentionally retain the flat fallback.
- Added `tests/replay/harness/selftest_phase3_abilities_authority.lua` covering canonical ability enable/disable, configured-list precedence, legacy-slot fallback, unengaged policy, required-setting resolution, and static scheduler/core/ranker wiring.
- Strengthened `selftest_unengaged_abilities.lua` so generic and tank lanes both test canonical OFF + flat ON and canonical ON + flat OFF.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory Chivalry cases: canonical enabled/list beats flat disabled/empty, canonical disable beats flat enabled, canonical configured list beats flat Chivalry, and canonical legacy-slot fallback still reserves TP.
- Extended `selftest_scheduler_ranker.lua` with contradictory canonical required-setting cases.
- Reduced the flat-surface guard by four more hits: `uc_provider_combat.lua` from 25 to 22 `ctx.settings` reads and `uc_provider_tank_enmity.lua` from 3 to 2.
- `config.abilities.wsabilities` is not consumed by the scheduler configured-JA path; it remains projected for legacy-engine compatibility and is not being misrepresented as part of this scheduler-domain cutover.
- Automated proof on implementation head `eda088b075eee3084d23728fa7d529ac4435314c`: workflow `37045140212` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, contradictory unengaged tests PASS, ranker authority PASS, Chivalry/WS precedence PASS, and the flat-surface guard PASS.
- No intentional JA priority, readiness, targeting, range, or dispatch semantics changed; the behavioral change is authority only—canonical Profile V2 wins over conflicting flat compatibility state.
- Live-game smoke verification remains required for configured self/enemy JAs, unengaged override behavior, tank-enmity unengaged actions, and Chivalry TP reservation before Phase 3 is complete.

### 2026-10-02 — Phase 3 target-control and ignore/priority slice implemented

- Migrated scheduler-owned targeting authority for `config.targeting.add_control`, the ordered target/add priority list, and `config.targeting.target_ignore_names`.
- Added canonical targeting accessors in `uc_scheduler_config.lua`.
- The scheduler priority rule is now explicit: `config.targeting.targets` is authoritative when non-empty; normalized `config.targeting.add_priority_names` remains only the compatibility fallback.
- `unified_combat_core.lua` overlays canonical Add Control, priority names, and target-ignore names into the scheduler settings view before target selection, tank target selection, death-switch revalidation, and Add Control evaluation.
- `uc_provider_target_control.lua` now passes `ctx.config` into Add Control enablement as well as target selection.
- `uc_provider_combat.lua` fight-leader engage arbitration now consults the same canonical Add Control gate, preventing engage and target-control lanes from disagreeing when flat compatibility state conflicts.
- Added `tests/replay/harness/selftest_phase3_targeting_authority.lua` proving canonical Add Control ON + flat OFF permits engaged retarget, canonical OFF + flat ON blocks it, canonical target ordering wins over conflicting flat priority order, and canonical target-ignore names win over conflicting flat ignore state.
- Updated the existing Add Control priority contract test for the canonical-context helper signatures.
- Added the targeting authority suite to normal PR CI and the aggregate replay suite.
- Flat-surface counts intentionally do not drop in this slice: Add Control still receives `ctx.settings` because fight-leader enablement is a separate follow/fight-leader domain that has not migrated yet. Target-owned fields within that mixed view are canonical.
- `config.targeting.targetability` and `config.targeting.ignore` are not scheduler target-selection inputs today; they remain legacy-engine/UI compatibility fields and are not being falsely claimed as migrated scheduler consumers.
- Automated proof on implementation head `51a8d1ddc62ef75b0c771ba0aefb7c241cd8e629`: workflow `37085163385` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, Phase 3 targeting authority PASS, Add Control priority eligibility PASS, and the flat-surface guard PASS.
- No intentional target ranking, claim policy, death-switch, Add Control eligibility, or engage-dispatch semantics changed except canonical Profile V2 now wins when targeting compatibility state conflicts.
- Live-game smoke verification remains required for Add Control retargeting, ordered add selection, target-ignore behavior, and fight-leader handoff before Phase 3 is complete.

### 2026-10-02 — Phase 3 tank/enmity configuration slice implemented

- Migrated common scheduler-owned tank authority to canonical Profile V2: `config.tank.enabled`, ordered `config.tank.enmity.actions`, and `config.tank.enmity.include_pets`.
- Added canonical tank/enmity accessors and an exact configured-action matcher in `uc_scheduler_config.lua`.
- `unified_combat_core.lua` now overlays canonical tank enablement and enmity actions into the scheduler settings view before tank violation selection.
- Combat engage weighting, generic-JA tank weighting, and target-acquire tank weighting now read `tank.enabled` from `ctx.config`.
- `uc_provider_tank_enmity.lua` now fails closed when canonical tank mode is disabled, uses canonical include-pets and enmity actions, and overlays canonical target-ignore names into pet-enmity violation selection.
- Fixed a real pre-existing authority/safety gap: the pet-enmity branch did not independently gate on tank enabled, so a pet recovery proposal could bypass the normal player-enmity path's tank gate. The provider now applies the canonical tank gate before either path.
- Tank-enmity and RUN-tank proposals now carry `required_setting = 'tank'`; the scheduler ranker resolves that dependency from canonical config.
- Final tank-enmity dispatch revalidates both canonical tank enablement and whether the selected recovery action is still present in the canonical enmity list, preventing a stale proposal from dispatching after a profile change.
- The shared top-level tank gate in `uc_provider_run_tank.lua` now reads canonical config. RUN-specific rune/ward/Foil policy under `config.tank.run` remains a separate subsystem and was not otherwise migrated in this slice.
- Fixed a cross-domain leak from the completed abilities slice: RUN tank's unengaged gate now uses canonical `config.abilities.allow_unengaged`.
- Fixed a movement/dispatch authority leak: RUN no-TP facing now receives canonical tank config in both the movement coordinator and combat dispatcher, so stale flat `tank=true` cannot keep no-TP facing active after canonical tank disable.
- Added `tests/replay/harness/selftest_phase3_tank_enmity_authority.lua` proving canonical tank ON + flat OFF, canonical tank OFF + flat ON, canonical action-list precedence, include-pets precedence, canonical pet target-ignore projection, ranker tank resolution, and dispatch-time canonical revalidation wiring.
- Strengthened the existing pet-enmity, RUN tank, RUN no-TP, tank priority/starvation, provider-shape, and migration-contract fixtures for the new canonical boundary.
- Reduced flat-context guard counts: `uc_provider_combat.lua` 22→20, `uc_provider_target_control.lua` 4→3, and `uc_provider_run_tank.lua` 3→1. `uc_provider_tank_enmity.lua` remains at 2 because it still passes compatibility context into separately owned target/friendly-selection helpers while all tank-owned fields are canonical.
- Automated proof on implementation head `447767bf7a8370e1e16b8949bd611a23f348ea7a`: workflow `37086243234` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 tank-enmity authority PASS, pet-enmity provider/config PASS, RUN tank PASS, RUN no-TP PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional tank priority bands, victim ranking, action readiness, range, dispatch method, RUN rune/ward policy, or engage semantics changed except canonical Profile V2 now wins over conflicting flat tank/enmity state and stale tank proposals fail closed.
- Live-game smoke verification remains required for PLD/RUN tank target acquisition, player and pet enmity recovery, canonical tank disable, configured recovery-action changes, and RUN no-TP facing before Phase 3 is complete.

### 2026-10-02 — Phase 3 pulling slice implemented

- Migrated the modern camp-puller domain, `config.combat.pulling`, to canonical Profile V2 authority across lane acquisition, proposal collection, candidate revalidation, movement ownership, action-result handling, and final dispatch revalidation.
- Added `uc_scheduler_config.combat_pulling_from_config` as the canonical accessor.
- `uc_camp_puller.lua` now reads `ctx.config.combat.pulling` directly and has zero `ctx.settings` reads.
- Camp-puller candidate ignore checks now receive canonical `ctx.config` and reuse canonical `config.targeting.target_ignore_names`; stale flat ignore state can no longer alter pull candidate selection.
- `unified_scheduler.lua` now resolves camp-pulling configuration from `uc_scheduler_context_utils.get_config()` for movement reservation and asynchronous action-result paths, and final camp-puller dispatch revalidates against the fresh canonical tick config.
- Party-follow and route/path movement ownership checks now read `config.combat.pulling` from `uc_active_config`, so stale flat `camp_pulling.enabled` cannot make movement consumers disagree with the scheduler. Missing canonical pull config fails closed as disabled rather than falling back to flat state.
- Strengthened `selftest_camp_puller.lua` so its full state-machine run uses canonical pulling enabled while the flat compatibility mirror is disabled.
- Added `tests/replay/harness/selftest_phase3_pulling_authority.lua` covering canonical ON + flat OFF lane acquisition, canonical OFF + flat ON fail-closed behavior, canonical target-ignore authority, and static scheduler/follow/pathing wiring.
- Strengthened `selftest_movement_priority_arbitration.lua` with both contradictory directions for cross-domain movement ownership: canonical pull ON + flat OFF suppresses follow, while canonical pull OFF + flat ON does not.
- Added the pulling authority suite to normal PR CI and the aggregate replay suite.
- Reduced the flat-surface guard further: `uc_camp_puller.lua` from 4 to 0 `ctx.settings` hits and `unified_scheduler.lua` from 12 to 11.
- Final branch audit found no remaining runtime reads of the flat `camp_pulling` mirror in `uc_camp_puller.lua`, `unified_scheduler.lua`, `uc_party_follow.lua`, or `uc_pathing.lua`; remaining appearances are compatibility projection/default surfaces and canonical helper names.
- The older hunter/path pull action (`path_pull_action_type`, `path_pull_action_name`, hunter/path-follow gates) belongs to `config.movement.path` and is intentionally deferred to the later pathing slice rather than being mixed into this pulling cutover.
- Automated proof on implementation head `a9967ee43f09d27f382df13867dd15cb441bcc40`: workflow `37086936986` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 pulling authority PASS, full camp-puller state machine PASS, camp-puller policy PASS, movement-priority arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional pull candidate ranking, quota policy, leash geometry, action readiness/range, retry policy, lane priority, or dispatch semantics changed except that canonical Profile V2 now wins over conflicting flat camp-pulling state.
- Live-game smoke verification remains required for camp lane acquisition, pull action execution, canonical disable during an active journey, target-ignore filtering, return-to-camp behavior, and movement handoff before Phase 3 is complete.

### 2026-10-03 — Phase 3 spacing slice implemented

- Migrated the unified scheduler/core spacing domain to canonical `config.movement.spacing` authority.
- Added `uc_scheduler_config.movement_spacing_from_config` as the canonical spacing accessor.
- `unified_combat_core.lua` now resolves one spacing view per movement tick from the canonical config passed by `unified_scheduler.lua`.
- Canonical authority covers the complete spacing subtree: `enabled`, `band_min`, `band_max`, `model_size_floor`, `use_prediction`, `lookahead_s`, `repel_hold_ticks`, `overlap_deadband`, `repel_weight`, and `band_deadband`.
- The migration intentionally includes `band_min`, `band_max`, and `model_size_floor` even when spacing is disabled because those values also define ordinary combat-close stop distance and model-size compensation.
- When canonical config is present but `movement.spacing` is absent, combat movement uses the normalized spacing defaults rather than falling back to conflicting flat spacing state.
- Direct no-config compatibility callers retain the old flat spacing projection through one centralized `movement_spacing_config(settings, config)` fallback. A regression asserts every legacy `settings.spacing*` token in core appears exactly once, inside that compatibility projection.
- Added `tests/replay/harness/selftest_phase3_spacing_authority.lua` proving canonical spacing ON + flat OFF executes the spacing solver, canonical spacing OFF + flat ON does not execute flat spacing behavior, canonical `band_max` wins while spacing is disabled, and canonical `model_size_floor` changes combat-close stopping distance despite conflicting flat values.
- The regression also proves the scheduler continues passing the tick-stable canonical config into `core.apply_movement_for_scheduler`.
- Updated the movement-facade and spacing cast-lock contract fixtures to the current canonical-config call/dispatcher signatures while preserving their original movement ownership and cast-freeze ordering assertions.
- No flat-surface guard count drops in this slice because the compatibility-only flat spacing projection remains intentionally present for direct legacy callers; the new spacing regression mechanically prevents those flat reads from spreading elsewhere in unified core movement.
- Source audit found no additional unified scheduler/core consumers of the spacing tuning fields outside `unified_combat_core.lua`.
- `melee_engine.lua`, `dd2_module.lua`, and the generated/legacy DD2 engine retain flat spacing reads. They are already classified in the migration ledger as legacy-sensitive engines and explicitly short-circuit when the unified engine owns execution; they are not being falsely claimed as migrated by this Phase 3 scheduler/core slice.
- Automated proof on implementation head `460db4c695e93be08a14a664e3c30e1e78d6f5a6`: workflow `37121903528` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 spacing authority PASS, scheduler movement facade PASS, spacing cast-lock PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional spacing geometry, prediction, repel weighting, deadband, cast-freeze, movement ownership, or combat-close semantics changed except canonical Profile V2 now wins over conflicting flat spacing state on the unified scheduler path.
- Live-game smoke verification remains required for spacing enable/disable, close/retreat band behavior, party overlap repulsion, moving-target prediction, and spacing interaction with cast freezes before Phase 3 is complete.

### 2026-10-03 — Phase 3 follow slice implemented

- Migrated the unified follow domain to canonical Profile V2 authority across party follow, fight-follow timing/leader selection, partner coordination, puller leash policy, and path-vs-follow movement ownership.
- Added `uc_follow_config.lua` as the canonical follow runtime adapter for `config.follow.party`, `config.follow.fight`, `config.follow.partner`, and `config.follow.nyzul`.
- Durable names remain the source of truth; party/fight/partner/puller IDs are resolved from the live party at runtime. Legacy configured IDs are used only when the corresponding canonical durable name is absent, and camp leash mode intentionally resolves no player puller ID.
- `uc_party_follow.lua` no longer contains any `active_value_or_flat` follow readers. Party enablement, leader identity/name, follow min/max, and fight-follow minimum now read canonical follow config directly.
- `config.follow.enabled` is part of the party-follow gate. Partial canonical profiles that omit the parent flag preserve the normalizer's default of enabled=true rather than accidentally disabling follow.
- Follow participation now honors both canonical `config.ownership.domain_follow_enabled` and canonical `config.follow.enabled` / `config.follow.party.enabled`.
- `uc_pathing.lua` now uses canonical follow policy when deciding whether party follow owns movement, while its own `config.movement.path` settings remain deferred to the next pathing slice.
- `uc_runtime_overrides.lua` fight-leader accessors are now canonical-first. Conflicting flat `fight_leader`, `fight_leader_name`, and `fight_leader_id` state can no longer override Profile V2.
- `unified_combat_core.lua` overlays canonical follow partner policy into its scheduler runtime view, so partner target ownership, fight-leader targeting, and puller/camp leash movement consume canonical `config.follow.partner` values.
- `unified_scheduler.lua` partner tiebreak arbitration now uses canonical partner enablement/IDs and canonical target-ignore policy; fight-follow hold duration now comes from canonical `config.follow.fight.hold_s`.
- Combat-provider partner target-set calls now pass `ctx.config`, so WS/sleep/ability partner exclusions use canonical partner state.
- Nyzul follow policy was already canonical: `uc_nyzul_runtime.lua` reads `config.follow.nyzul.*` directly, so no runtime churn was required there.
- Added `tests/replay/harness/selftest_phase3_follow_authority.lua` proving live canonical name→ID resolution, canonical party/fight/partner/puller projection over contradictory flat state, canonical fight-leader ON/OFF precedence, and camp-leash runtime-ID behavior.
- Strengthened `selftest_movement_priority_arbitration.lua` so canonical party-follow behavior is proven both against conflicting flat state and with missing canonical follow policy failing closed instead of falling back to flat.
- Updated runtime-overrides, active-config-consumer, configurable-control-range, and partner-arbitration contracts for the new authority boundary.
- Flat-surface guard burn-down: `uc_party_follow.lua` `active_value_or_flat` count 7→0; `uc_pathing.lua` 9→7 by removing its two follow-related fallback readers.
- Legacy-sensitive `melee_engine.lua` / `dd2_module.lua` retain their own flat follow/partner settings and remain separately classified compatibility debt outside the unified scheduler follow slice.
- Automated proof on implementation head `272149baa442a03b65b0e1757fadf2a73a926281`: workflow `37143116074` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 follow authority PASS, movement-priority arbitration PASS, runtime-overrides PASS, partner-arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional party-follow geometry, zone replay, combat transition suppression, partner arbitration ranking, puller leash geometry, or fight-follow timing semantics changed except canonical Profile V2 now wins over conflicting flat follow state.
- Live-game smoke verification remains required for same-zone party follow, zone replay, fight-follow distance changes, partner target coordination, player/camp puller leash modes, and follow/path movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 pathing slice implemented

- Migrated unified route-follow and path-hunter policy to canonical Profile V2 authority.
- Added `uc_path_config.lua` as the canonical runtime adapter for durable `config.movement.path` policy plus the existing canonical `config.legacy.hunter` gate.
- `uc_pathing.lua` now reads recording enablement, path-follow enablement, party gate distance, and resume-index window only from canonical path policy. Its `active_value_or_flat` count is 7 → 0.
- Route identity/progress is explicitly runtime-owned: selected path filename, classified route type, distance-to-start, and recorded point list stay on live/session state and are not projected from Profile V2 over the runtime.
- Profile V2 durable comparison ignores those four route/session fields, and canonical-to-flat apply preserves the live values already present in the runtime settings table. Existing Profile V2 files may still carry route-state compatibility fields; this slice does not rewrite the file schema.
- The existing Profile V2/WinForms route-state fields remain compatibility schema debt for now. Runtime authority is removed without changing their serialized compatibility shape in this slice.
- Unified target selection overlays canonical path/hunter policy before evaluating hunter enablement, target names, vertical tolerance, and target range.
- Scheduler pull selection overlays canonical path/hunter policy for hunter enablement, path-follow gate, target list, pull action type/name, and attack fallback. Both target-control and combat providers pass `ctx.config` into pull selection.
- Missing canonical path policy uses canonical defaults/fails closed rather than reviving contradictory flat path-follow or hunter state.
- Added `tests/replay/harness/selftest_phase3_pathing_authority.lua` covering canonical-vs-flat route/hunter/pull policy, canonical OFF precedence, default fail-closed behavior, and preservation of live route/session state.
- Strengthened movement arbitration and added a focused Profile V2 durable-diff regression so stale flat path-follow state and route-session placeholders cannot regain authority.
- Flat-surface guard burn-down: `uc_pathing.lua` `active_value_or_flat` count 7 → 0.
- No intentional route geometry, pause/resume arbitration, hunter candidate ranking, pull readiness/range, or movement-dispatch semantics changed except that canonical Profile V2 now wins for durable path policy.
- Live-game smoke verification remains required for path recording start/stop, route-file rebinding, route follow, hunter target filtering, configured pull action/fallback, and follow/path/camp-pull movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 movement-owned durable settings slice implemented

- Added `uc_movement_config.lua` as the canonical adapter for movement-owned durable policy.
- The remaining scheduler movement controls now come from canonical Profile V2: `config.movement.move`, `config.combat.manual`, `config.combat.static`, and `config.combat.face`.
- `unified_combat_core.lua` uses one canonical movement-control view when a scheduler config snapshot is supplied. Flat `move`/`manual`/`static` reads remain only as an explicit compatibility path for callers that omit canonical config entirely.
- Scheduler ordinary facing now receives canonical config explicitly and uses canonical `config.combat.face`; forced turn-away behavior remains force-owned and is unchanged.
- `run_movement_coordinator_tick` now receives the tick-stable canonical config explicitly instead of reaching for the process-local `get_tick_ctx()` symbol from outside its lexical scope.
- The same explicit snapshot is reused for RUN no-TP facing, fight-follow hold timing, ordinary facing, and core combat-close movement.
- Removed the movement coordinator's residual flat `fight_follow_hold_s` fallback. Missing canonical fight timing uses the established 8-second default rather than stale flat state.
- `UC_IsCombatParticipant` and `UC_IsMovementParticipant` now classify participation from canonical Profile V2 through `uc_movement_config`, while current engine-running state remains runtime-owned through `Start_Engine`.
- Canonical participation covers autotarget, explicit move, base/named formations, tank, hunter+path-follow, puller, add-control, and spacing (movement participation only). Formation/named-formation runtime itself was already canonical and required no rewrite.
- Added `tests/replay/harness/selftest_phase3_movement_authority.lua` proving contradictory canonical-vs-flat authority for move/manual/static, canonical participant/domain behavior, face policy, explicit coordinator config plumbing, and protection against hidden `get_tick_ctx` fallback.
- The contradictory-state movement test exposed a pre-existing core authority leak in the earlier combat-enable cutover: Lua's `a and canonical_false or flat_value` idiom caused canonical `autotarget=false` / `auto_engage=false` to fall through to conflicting flat `true`. Core movement now uses explicit canonical-vs-compatibility branches, so canonical false is authoritative.
- Automated proof on implementation head `367201f60d99156133bea2726813e6f3ebad7a02`: workflow `37200907676` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 movement authority PASS, formation activation PASS, spacing cast-lock PASS, RUN no-TP PASS, defensive/support movement-lock tests PASS, all earlier Phase 2/3 authority suites PASS, and the flat-surface guard PASS.
- Flat-surface guard burn-down: `UnifiedCombat.lua` literal `UC_SETTINGS` count 79 → 77 by removing the two participant helpers' flat settings dependency.
- Existing legacy DD2/melee engine movement controls remain separately classified compatibility debt and are not claimed as migrated by this unified scheduler/core slice.
- Live-game smoke verification remains required for explicit Move mode, Manual/Static movement suppression, ordinary Face on/off, formation participation, and coordinator mode transitions before Phase 3 live acceptance is complete.


### 2026-10-04 — Phase 3 automated exit audit implemented

- Audited the common scheduler/core durable-authority boundary after all listed Phase 3 domain slices.
- Scheduler proposal revalidation is now canonical/fail-closed: `uc_scheduler_ranker.lua` no longer falls back to `ctx.settings[required_setting]` when a proposal dependency is unmapped.
- Added canonical `sleep` required-setting resolution through `config.sleep.enabled`; production `required_setting` tokens are now enumerated by the exit regression so future unmapped proposal dependencies fail CI.
- Added explicit canonical `config.combat.prime` access and moved combat-commitment fight-leader evaluation to the tick's `ctx.config` / `uc_follow_config` snapshot. Contradictory flat Prime/fight state can no longer influence runtime commitment.
- Migrated the common charm-sleeper and sleep-waker feature gates to `ctx.config.defensive.*` directly. Their focused tests now deliberately oppose canonical and flat values on every collection pass.
- Removed the Phase 2-deferred direct `UC_SETTINGS.log_combat_sched` read from `uc_scheduler_action_state.lua`; core action-state diagnostics now use canonical `config.debug.combat_sched`.
- Added `tests/replay/harness/selftest_phase3_exit_audit.lua` to freeze the common authority contract: every production scheduler `required_setting` must have a canonical mapping, common defensive providers may not receive flat fallback authority, combat commitment must use explicit canonical config, and core's sole direct `UC_SETTINGS` accessor remains the explicit no-config compatibility seam.
- Flat-surface burn-down in this audit: `uc_combat_commitment.lua` `ctx.settings` 3→1; `uc_scheduler_ranker.lua` 3→2; `uc_provider_charm_sleeper.lua` and `uc_provider_sleep_waker.lua` drop their `ctx.settings` / `active_value_or_flat` surfaces entirely; `uc_scheduler_action_state.lua` drops its final direct `UC_SETTINGS` read.
- Expanded exit-audit tracing proved several canonical-first fallbacks were still on the live common path. The unified scheduler now has **zero** `active_value_or_flat(` calls (32→0) and its `ctx.settings` surface falls 11→2; the remaining two are runtime/cross-domain plumbing rather than durable common policy.
- Common defensive Cure/Curaga/Waltz/Na/buff selection, critical-cure classification, Doom-water eligibility, and shared SCH defensive tuning now consume the explicit canonical config snapshot.
- Sleep collection is canonical end-to-end: enablement, ordered spell list, range, effect suppression, and spell selection all consume `ctx.config`; stale flat `sleep` / `sleepspells` state can no longer drive scheduler collection.
- Combat Prime and fight-leader collection now consume canonical `ctx.config` as well as the earlier commitment path. `uc_provider_combat.lua` flat-context markers fall 20→11; survivors are partner/pull/WS/job-runtime seams tracked separately rather than Sleep/Prime/fight durable authority.
- Remaining flat scheduler/provider surfaces are explicitly outside this common Phase 3 authority boundary: RUN/SCH/SMN/PUP job configuration moves to Phase 4, scheduler cadence fields such as `_sched_next_*` are runtime state, diagnostic helpers are non-action authority, and explicit no-config core/legacy callers remain compatibility-only.
- The prior follow/pathing tests continue to prove configured names are durable while resolved party/fight/partner/puller IDs are live-derived; path route/session state remains non-authoritative compatibility schema debt rather than scheduler policy.
- Automated proof on implementation head `a3670fa83a055ad582be0b5ff6bab7821f4a2950`: workflow `37205168055` completed successfully with `lua-sequence` PASS, the Phase 3 automated exit audit PASS, flat-surface guard PASS, all earlier Phase 2/3 authority suites PASS, and `winforms` PASS. Live-game smoke verification remains required before Phase 3 live acceptance is complete.

## Working checklist

When completing any migration slice:

- [ ] inspect current callers and writers;
- [ ] classify durable config vs runtime state;
- [ ] identify exact canonical path(s);
- [ ] add or update tests before removing fallback;
- [ ] migrate the smallest cohesive consumer set;
- [ ] verify changed Lua with Lua 5.1 tooling where available;
- [ ] run targeted tests;
- [ ] update flat-consumer allowlist/guardrail;
- [ ] update this document's phase status and progress log;
- [ ] note live-game verification still required, if applicable;
- [ ] keep rollback straightforward.

## Completion definition

This migration is complete only when Profile V2 is the single durable configuration authority from editor/save through runtime consumption, and flat compatibility state can no longer change durable automation semantics.
`) inside the Lua trim pattern duplicated the file tail during repository editing; the COR module was rebuilt from the last green immutable source and only the intended live name-to-ID range-resolution block was reapplied.

### Phase 6 — Retire the durable flat projection

Status: **NOT STARTED**

Goals:

- remove remaining durable projections from canonical config into `_G.UC_SETTINGS`;
- shrink `uc_new_settings_defaults()` to true runtime/compatibility needs or replace it with better-scoped state owners;
- remove mixed-shape normalization for normal runtime paths;
- retain compatibility wrappers only where an external/public contract still requires them;
- make any surviving `UC_SETTINGS` usage explicitly non-authoritative.

Exit criteria:

- [ ] no durable runtime behavior depends on `_G.UC_SETTINGS`;
- [ ] no durable UI write mutates `_G.UC_SETTINGS` as source of truth;
- [ ] canonical config is the only durable authority;
- [ ] mixed flat/nested normalizer ambiguity is removed from normal runtime;
- [ ] compatibility surfaces are documented and intentionally bounded.

### Phase 7 — Final cleanup and conformance

Status: **NOT STARTED**

Goals:

- remove dead compatibility adapters;
- remove obsolete flat field projections and tests that only preserve retired behavior;
- update architecture docs and README;
- run full Lua and WinForms test suites;
- perform targeted live-game acceptance across representative jobs and domains.

Required live acceptance should include at least:

- BRD maintenance;
- COR maintenance;
- GEO maintenance;
- defensive healing/buffs;
- recurring combat spells;
- tank/RUN behavior;
- WS/skillchain behavior;
- pulling;
- follow/pathing;
- SMN;
- PUP;
- SCH;
- activity profile apply;
- profile Save/reload;
- job/subjob identity transition.

Exit criteria:

- [ ] source-contract audit shows no unintended flat durable reads/writes;
- [ ] automated suites green;
- [ ] targeted live acceptance completed;
- [ ] architecture docs describe the final ownership model accurately.

## Regression scenarios that must survive the migration

These are architecture acceptance cases, not merely unit tests.

### Food and Bard sibling isolation

Given:

```lua
config.maintenance = {
    brd = {
        enabled = true,
        songs = { 'Honor March', 'Victory March' },
    },
    food = {
        enabled = true,
        item = 'Grape Daifuku',
    },
}
```

Changing `maintenance.food` must never alter, disable, default, or reinterpret `maintenance.brd`.

### Canonical false values remain authoritative

A canonical explicit `false` must not fall through to a legacy flat `true`.

### Missing canonical subtree behavior is explicit

A missing optional subtree must use canonical defaults, not resurrect stale flat compatibility values.

### Runtime state cannot become durable

Engine state, current IDs, live locks, target state, and similar transient values must never be serialized merely because they previously lived in `UC_SETTINGS`.

### UI/runtime round trip

Canonical Profile V2 -> runtime active config -> editor -> save must preserve durable semantics without requiring flat compatibility state to fill missing fields.

## Progress log

### 2026-10-02 — Migration branch created

- Created `refactor/profile-v2-single-source` from current `master`.
- Confirmed Profile V2 is already the intended durable source.
- Confirmed `_G.UC_ACTIVE_PROFILE.config` is already the intended canonical applied config.
- Identified `_G.UC_SETTINGS` as the major compatibility surface still feeding runtime consumers.
- Identified major flat producers in addon startup, active-config projection, bridge live writes, and WinForms editor/write adapters.
- Identified initial consumer families for Phase 0 inventory.
- No gameplay behavior changed.

### 2026-10-02 — Rabao BRD investigation clarified

- Confirmed BRD song maintenance is intentionally blocked in configured city zones, including Rabao.
- Confirmed the observed "BRD never sings" case in Rabao was expected city-zone behavior, not evidence of a current BRD config regression.
- The configuration migration remains necessary because the mixed flat/nested model is still structural technical debt.

### 2026-10-02 — Phase 0 inventory and guardrails completed

- Added `docs/profile_v2_flat_surface_inventory.md` as the detailed producer/consumer and field-ownership baseline.
- Added a repository-wide source guardrail that freezes direct `UC_SETTINGS`, indirect `ctx.settings`, `active_value_or_flat`, canonical-to-flat projection, bridge flat mutation, and WinForms flat write/translation seams.
- Added a machine-readable allowlist with exact current source occurrence counts. Future migration slices should shrink it; new flat seams fail the guardrail unless explicitly reviewed.
- Classified durable field families, runtime/transient state, compatibility-only aliases, and explicit ambiguous ownership decisions.
- Added the mixed nested-food + flat-BRD maintenance characterization fixture. It records the current known normalizer defect without changing runtime behavior.
- Phase 0 made documentation/test-only changes; no scheduler/provider/gameplay behavior changed.

### 2026-10-02 — Phase 1 canonical runtime read boundary completed

- Added `uc_scheduler_context_utils.get_config()` as the scheduler-owned canonical accessor over the applied `_G.UC_ACTIVE_PROFILE.config`.
- Scheduler tick contexts now expose `ctx.config` alongside the unchanged compatibility `ctx.settings` surface.
- Canonical config is sampled once when the tick context is built and passed by identity; providers do not reparse Profile V2 files.
- The context builder remains dependency-injected and does not directly require `uc_active_config`.
- Added deterministic fixture/static coverage for active-config lookup, missing-config fallback, one-sample-per-context behavior, and scheduler wiring.
- No proposal provider, ranking rule, dispatch path, or durable config consumer changed in this phase; the Phase 0 flat allowlist is intentionally unchanged.
- PR verification now runs the flat-surface guard, mixed-shape characterization, scheduler canonical-context tests, and context-utils fixtures on every migration PR update.
- Draft PR #73 is the long-lived migration/CI surface. Verification run 36981070413 passed both `lua-sequence` and `winforms` after the guardrail baseline and fixture-count expectations were corrected.
- The new guardrail immediately found three pre-existing `UnifiedCombat.lua` flat-sync call sites that the initial mechanical audit had missed; they are now explicitly baselined rather than silently ignored.

### 2026-10-02 — Mainline legacy-food compatibility hotfix incorporated

- Mainline PR #74 fixed Activity/Profile V2 apply failures for profiles created before `maintenance.food` existed.
- Legacy Profile V2 maintenance domains now materialize `food = { enabled = false, item = '' }` before canonical-to-flat compatibility projection, preventing stale live food settings from leaking into conversion validation.
- The focused regression reproduces the Etamame SAM/DRG Activity Apply failure shape and asserts the exact structured conversion path returns zero mismatch.
- The hotfix was merged to `master` as `c8a084b9a29dd412e99fa3cf5dec4e0e90cf1b3f` and has been incorporated into this migration branch before Phase 2.

### 2026-10-02 — Phase 2 low-risk leaf migration implemented

- Food maintenance and recurring combat spells now consume only the canonical scheduler snapshot at `ctx.config`; stale `ctx.settings` values are deliberately ignored.
- Defensive provider gates/resurrection, enemy-buff removal, and enemy-debuff maintenance now consume `ctx.config.defensive.*` directly.
- Raise acceptance and weakened recovery-hold now read only `uc_active_config`; their direct `UC_SETTINGS` fallback paths were removed.
- GEO camp placement now reads only `config.maintenance.geo` from active Profile V2 state.
- Defensive buff maintenance now receives canonical config explicitly from the scheduler, including structured targeted buffs and BRD ownership state; its hidden active-config/global fallback was removed.
- COR maintenance now receives canonical config explicitly from the maintenance provider. Roll policy, range requirements, Light Shot-on-Dia policy, and ability-derived roll fallback stay inside canonical `config.maintenance.cor` / `config.abilities.configured`.
- The Phase 0 allowlist shrank by 11 source-file entries / 60 literal flat-surface hits. The remaining `uc_scheduler_action_state.lua` debug-only `UC_SETTINGS` reader is intentionally deferred with the core scheduler work in Phase 3 rather than widening this leaf migration.
- Deterministic tests include intentionally conflicting stale flat values so a migrated leaf fails if flat compatibility regains authority.
- Full PR CI passed at Phase 2 verification head `a396671884229447f10ea85d5399e69a58003275` (workflow run `36992724235`): both Lua and WinForms jobs succeeded, including the flat-surface guard and the dedicated Phase 2 canonical-leaf suite.
- Added `tests/replay/harness/selftest_phase2_canonical_authority.lua`: a dedicated 21-case contradictory-state matrix whose only purpose is to prove canonical Profile V2 values beat deliberately opposite flat compatibility values across every Phase 2 consumer family.
- The matrix covers food, recurring spells, defensive provider/critical threshold, resurrection, enemy buff removal, enemy debuff maintenance, COR routing, defensive buff maintenance, COR roll selection, GEO placement, Raise acceptance, and weakened recovery hold. Both enable/disable directions are exercised where a boolean gate exists.
- Workflow run `37016053323` passed both `lua-sequence` and `winforms`; the canonical-authority matrix reported `21/21 PASS`.
- Live-game smoke verification remains before merge, especially food, recurring spells, defensive maintenance, COR upkeep, raise acceptance, recovery hold, and GEO camp placement.
- Phase 2 implementation began with `0f707e1863846dcc74d0dd56cb791cbbf8bbb0ed`; the verified Phase 2 head is `a396671884229447f10ea85d5399e69a58003275`.

### 2026-10-02 — Phase 3 combat enablement/autotarget slice implemented

- Began Phase 3 with the smallest core domain: combat enablement/target acquisition gates, specifically canonical `config.combat.autotarget` and `config.combat.auto_engage`.
- Added canonical-only scheduler helpers for autotarget and auto-engage while retaining compatibility helpers for unmigrated non-scheduler callers.
- Migrated scheduler-owned target acquisition and engage gates to `ctx.config`; contradictory flat `ctx.settings.autotarget` / `auto_engage` values can no longer change those provider decisions.
- Passed canonical tick config through core target selection, tank-enmity selection, death-switch revalidation, partner arbitration, and pre-engage combat-close movement so hidden flat autotarget fallbacks do not survive behind provider boundaries.
- Added `tests/replay/harness/selftest_phase3_combat_enablement_authority.lua` with contradictory canonical-vs-flat cases for autotarget and auto-engage plus static wiring assertions.
- Added the new Phase 3 proof to PR CI and the aggregate replay suite.
- Reduced the flat-surface guard by four `ctx.settings` hits: two from `uc_provider_target_control.lua` and two from `uc_provider_combat.lua`.
- Existing combat-extension provider coverage now supplies canonical combat config explicitly; legacy helper fallback tests remain intact for callers that have not migrated yet.
- No weaponskill, ability, pulling, target-priority, tank-policy, ranking, or dispatch semantics are intentionally changed by this slice.
- During contradictory-state proof, the first canonical auto-engage implementation exposed a Lua false-value bug: `condition and value or nil` collapsed explicit canonical `false` to `nil`, incorrectly restoring the default `true`. The canonical accessor was corrected to preserve explicit false, and the regression now proves both directions.
- Automated proof on branch head `cf827cd87f0eafe8b9917743d97ed7a2015944b2`: workflow `37023674659` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 2 canonical-authority coverage PASS, the new Phase 3 combat enablement canonical-authority test PASS, and the flat-surface guard PASS.
- Live-game smoke verification remains required before the Phase 3 core migration is considered complete.

### 2026-10-02 — Phase 3 weaponskill configuration slice implemented

- Migrated the full scheduler-owned weaponskill decision path to canonical Profile V2 authority.
- Canonical WS policy now covers `config.combat.weaponskill.enabled`, primary WS, mode, minimum TP, AoE permission, Fast Skillchain, no-skillchain target names, skillchain target preference, ally-wait ignore names, aftermath enablement, and aftermath WS.
- Included canonical `config.combat.spam` and `config.legacy.solo` in the WS view because both directly alter weaponskill arbitration/bypass behavior.
- Deliberately left `ability_active` as a compatibility input for Chivalry reservation; that belongs to the next Phase 3 abilities slice.
- Proposal collection now gates WS enablement from `ctx.config`; the core planner receives canonical config and overlays all WS-owned durable fields before selecting an action.
- Canonical config is carried through rank-commit Smart-AoE/skillchain revalidation and final WS intent dispatch, preventing a canonical proposal from being revalidated against stale flat WS policy.
- Added `tests/replay/harness/selftest_phase3_weaponskill_authority.lua` to prove canonical WS enablement beats opposite flat state and to statically require every WS-owned field at the canonical boundary.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory-state cases proving canonical primary WS, minimum TP, AoE policy in both directions, Smart vs primary-only mode, aftermath policy, and Fast Skillchain false/true behavior.
- Added the weaponskill authority suite to normal PR CI and the aggregate replay suite.
- Reduced `uc_provider_combat.lua` flat-context guard count from 26 to 25 by removing the flat `weaponskill_active` provider gate. The remaining `ctx.settings` handoff exists for explicitly unmigrated non-WS inputs such as Chivalry's ability gate.
- Automated proof on branch head `7191d7a550dcb467e3e1166f787c2f3ba719dde4`: workflow `37027431136` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill canonical-authority PASS, WS maintenance/skillchain precedence PASS, and the flat-surface guard PASS.
- No intentional weaponskill ranking, timing, TP threshold semantics, skillchain planning semantics, or dispatch behavior changed except that canonical Profile V2 now wins when flat compatibility state conflicts.
- Live-game smoke verification remains required for representative Smart WS, spam/solo, primary-no-SC, aftermath, and Fast Skillchain configurations before Phase 3 is complete.

### 2026-10-02 — Phase 3 abilities slice implemented

- Migrated scheduler-owned generic configured-JA authority to canonical `config.abilities`: enablement, allow-unengaged policy, configured ability ordering, and legacy-slot fallback.
- Added `uc_ability_pipeline.collect_ordered_from_config`; scheduler generic JA collection now chooses the ability list from Profile V2 before applying unrelated RUN ownership filtering.
- Migrated the shared allow-unengaged policy in `uc_provider_tank_enmity.lua` to canonical `config.abilities.allow_unengaged`.
- Closed the deferred Chivalry dependency from the WS slice: the scheduler WS settings view now overlays canonical ability enablement, configured abilities, and legacy slots before Chivalry TP-reservation logic runs.
- Discovered a hidden post-proposal authority leak in `uc_scheduler_ranker.lua`: proposals carrying `required_setting` were rechecked directly against `ctx.settings`. This could silently override canonical `autotarget`, `weaponskill_active`, and `ability_active` decisions after a proposal had already been built.
- Added `uc_scheduler_config.required_setting_value_from_config` and migrated ranker validation so those three already-migrated settings revalidate against canonical config; unknown/unmigrated required settings such as Sleep intentionally retain the flat fallback.
- Added `tests/replay/harness/selftest_phase3_abilities_authority.lua` covering canonical ability enable/disable, configured-list precedence, legacy-slot fallback, unengaged policy, required-setting resolution, and static scheduler/core/ranker wiring.
- Strengthened `selftest_unengaged_abilities.lua` so generic and tank lanes both test canonical OFF + flat ON and canonical ON + flat OFF.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory Chivalry cases: canonical enabled/list beats flat disabled/empty, canonical disable beats flat enabled, canonical configured list beats flat Chivalry, and canonical legacy-slot fallback still reserves TP.
- Extended `selftest_scheduler_ranker.lua` with contradictory canonical required-setting cases.
- Reduced the flat-surface guard by four more hits: `uc_provider_combat.lua` from 25 to 22 `ctx.settings` reads and `uc_provider_tank_enmity.lua` from 3 to 2.
- `config.abilities.wsabilities` is not consumed by the scheduler configured-JA path; it remains projected for legacy-engine compatibility and is not being misrepresented as part of this scheduler-domain cutover.
- Automated proof on implementation head `eda088b075eee3084d23728fa7d529ac4435314c`: workflow `37045140212` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, contradictory unengaged tests PASS, ranker authority PASS, Chivalry/WS precedence PASS, and the flat-surface guard PASS.
- No intentional JA priority, readiness, targeting, range, or dispatch semantics changed; the behavioral change is authority only—canonical Profile V2 wins over conflicting flat compatibility state.
- Live-game smoke verification remains required for configured self/enemy JAs, unengaged override behavior, tank-enmity unengaged actions, and Chivalry TP reservation before Phase 3 is complete.

### 2026-10-02 — Phase 3 target-control and ignore/priority slice implemented

- Migrated scheduler-owned targeting authority for `config.targeting.add_control`, the ordered target/add priority list, and `config.targeting.target_ignore_names`.
- Added canonical targeting accessors in `uc_scheduler_config.lua`.
- The scheduler priority rule is now explicit: `config.targeting.targets` is authoritative when non-empty; normalized `config.targeting.add_priority_names` remains only the compatibility fallback.
- `unified_combat_core.lua` overlays canonical Add Control, priority names, and target-ignore names into the scheduler settings view before target selection, tank target selection, death-switch revalidation, and Add Control evaluation.
- `uc_provider_target_control.lua` now passes `ctx.config` into Add Control enablement as well as target selection.
- `uc_provider_combat.lua` fight-leader engage arbitration now consults the same canonical Add Control gate, preventing engage and target-control lanes from disagreeing when flat compatibility state conflicts.
- Added `tests/replay/harness/selftest_phase3_targeting_authority.lua` proving canonical Add Control ON + flat OFF permits engaged retarget, canonical OFF + flat ON blocks it, canonical target ordering wins over conflicting flat priority order, and canonical target-ignore names win over conflicting flat ignore state.
- Updated the existing Add Control priority contract test for the canonical-context helper signatures.
- Added the targeting authority suite to normal PR CI and the aggregate replay suite.
- Flat-surface counts intentionally do not drop in this slice: Add Control still receives `ctx.settings` because fight-leader enablement is a separate follow/fight-leader domain that has not migrated yet. Target-owned fields within that mixed view are canonical.
- `config.targeting.targetability` and `config.targeting.ignore` are not scheduler target-selection inputs today; they remain legacy-engine/UI compatibility fields and are not being falsely claimed as migrated scheduler consumers.
- Automated proof on implementation head `51a8d1ddc62ef75b0c771ba0aefb7c241cd8e629`: workflow `37085163385` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, Phase 3 targeting authority PASS, Add Control priority eligibility PASS, and the flat-surface guard PASS.
- No intentional target ranking, claim policy, death-switch, Add Control eligibility, or engage-dispatch semantics changed except canonical Profile V2 now wins when targeting compatibility state conflicts.
- Live-game smoke verification remains required for Add Control retargeting, ordered add selection, target-ignore behavior, and fight-leader handoff before Phase 3 is complete.

### 2026-10-02 — Phase 3 tank/enmity configuration slice implemented

- Migrated common scheduler-owned tank authority to canonical Profile V2: `config.tank.enabled`, ordered `config.tank.enmity.actions`, and `config.tank.enmity.include_pets`.
- Added canonical tank/enmity accessors and an exact configured-action matcher in `uc_scheduler_config.lua`.
- `unified_combat_core.lua` now overlays canonical tank enablement and enmity actions into the scheduler settings view before tank violation selection.
- Combat engage weighting, generic-JA tank weighting, and target-acquire tank weighting now read `tank.enabled` from `ctx.config`.
- `uc_provider_tank_enmity.lua` now fails closed when canonical tank mode is disabled, uses canonical include-pets and enmity actions, and overlays canonical target-ignore names into pet-enmity violation selection.
- Fixed a real pre-existing authority/safety gap: the pet-enmity branch did not independently gate on tank enabled, so a pet recovery proposal could bypass the normal player-enmity path's tank gate. The provider now applies the canonical tank gate before either path.
- Tank-enmity and RUN-tank proposals now carry `required_setting = 'tank'`; the scheduler ranker resolves that dependency from canonical config.
- Final tank-enmity dispatch revalidates both canonical tank enablement and whether the selected recovery action is still present in the canonical enmity list, preventing a stale proposal from dispatching after a profile change.
- The shared top-level tank gate in `uc_provider_run_tank.lua` now reads canonical config. RUN-specific rune/ward/Foil policy under `config.tank.run` remains a separate subsystem and was not otherwise migrated in this slice.
- Fixed a cross-domain leak from the completed abilities slice: RUN tank's unengaged gate now uses canonical `config.abilities.allow_unengaged`.
- Fixed a movement/dispatch authority leak: RUN no-TP facing now receives canonical tank config in both the movement coordinator and combat dispatcher, so stale flat `tank=true` cannot keep no-TP facing active after canonical tank disable.
- Added `tests/replay/harness/selftest_phase3_tank_enmity_authority.lua` proving canonical tank ON + flat OFF, canonical tank OFF + flat ON, canonical action-list precedence, include-pets precedence, canonical pet target-ignore projection, ranker tank resolution, and dispatch-time canonical revalidation wiring.
- Strengthened the existing pet-enmity, RUN tank, RUN no-TP, tank priority/starvation, provider-shape, and migration-contract fixtures for the new canonical boundary.
- Reduced flat-context guard counts: `uc_provider_combat.lua` 22→20, `uc_provider_target_control.lua` 4→3, and `uc_provider_run_tank.lua` 3→1. `uc_provider_tank_enmity.lua` remains at 2 because it still passes compatibility context into separately owned target/friendly-selection helpers while all tank-owned fields are canonical.
- Automated proof on implementation head `447767bf7a8370e1e16b8949bd611a23f348ea7a`: workflow `37086243234` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 tank-enmity authority PASS, pet-enmity provider/config PASS, RUN tank PASS, RUN no-TP PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional tank priority bands, victim ranking, action readiness, range, dispatch method, RUN rune/ward policy, or engage semantics changed except canonical Profile V2 now wins over conflicting flat tank/enmity state and stale tank proposals fail closed.
- Live-game smoke verification remains required for PLD/RUN tank target acquisition, player and pet enmity recovery, canonical tank disable, configured recovery-action changes, and RUN no-TP facing before Phase 3 is complete.

### 2026-10-02 — Phase 3 pulling slice implemented

- Migrated the modern camp-puller domain, `config.combat.pulling`, to canonical Profile V2 authority across lane acquisition, proposal collection, candidate revalidation, movement ownership, action-result handling, and final dispatch revalidation.
- Added `uc_scheduler_config.combat_pulling_from_config` as the canonical accessor.
- `uc_camp_puller.lua` now reads `ctx.config.combat.pulling` directly and has zero `ctx.settings` reads.
- Camp-puller candidate ignore checks now receive canonical `ctx.config` and reuse canonical `config.targeting.target_ignore_names`; stale flat ignore state can no longer alter pull candidate selection.
- `unified_scheduler.lua` now resolves camp-pulling configuration from `uc_scheduler_context_utils.get_config()` for movement reservation and asynchronous action-result paths, and final camp-puller dispatch revalidates against the fresh canonical tick config.
- Party-follow and route/path movement ownership checks now read `config.combat.pulling` from `uc_active_config`, so stale flat `camp_pulling.enabled` cannot make movement consumers disagree with the scheduler. Missing canonical pull config fails closed as disabled rather than falling back to flat state.
- Strengthened `selftest_camp_puller.lua` so its full state-machine run uses canonical pulling enabled while the flat compatibility mirror is disabled.
- Added `tests/replay/harness/selftest_phase3_pulling_authority.lua` covering canonical ON + flat OFF lane acquisition, canonical OFF + flat ON fail-closed behavior, canonical target-ignore authority, and static scheduler/follow/pathing wiring.
- Strengthened `selftest_movement_priority_arbitration.lua` with both contradictory directions for cross-domain movement ownership: canonical pull ON + flat OFF suppresses follow, while canonical pull OFF + flat ON does not.
- Added the pulling authority suite to normal PR CI and the aggregate replay suite.
- Reduced the flat-surface guard further: `uc_camp_puller.lua` from 4 to 0 `ctx.settings` hits and `unified_scheduler.lua` from 12 to 11.
- Final branch audit found no remaining runtime reads of the flat `camp_pulling` mirror in `uc_camp_puller.lua`, `unified_scheduler.lua`, `uc_party_follow.lua`, or `uc_pathing.lua`; remaining appearances are compatibility projection/default surfaces and canonical helper names.
- The older hunter/path pull action (`path_pull_action_type`, `path_pull_action_name`, hunter/path-follow gates) belongs to `config.movement.path` and is intentionally deferred to the later pathing slice rather than being mixed into this pulling cutover.
- Automated proof on implementation head `a9967ee43f09d27f382df13867dd15cb441bcc40`: workflow `37086936986` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 pulling authority PASS, full camp-puller state machine PASS, camp-puller policy PASS, movement-priority arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional pull candidate ranking, quota policy, leash geometry, action readiness/range, retry policy, lane priority, or dispatch semantics changed except that canonical Profile V2 now wins over conflicting flat camp-pulling state.
- Live-game smoke verification remains required for camp lane acquisition, pull action execution, canonical disable during an active journey, target-ignore filtering, return-to-camp behavior, and movement handoff before Phase 3 is complete.

### 2026-10-03 — Phase 3 spacing slice implemented

- Migrated the unified scheduler/core spacing domain to canonical `config.movement.spacing` authority.
- Added `uc_scheduler_config.movement_spacing_from_config` as the canonical spacing accessor.
- `unified_combat_core.lua` now resolves one spacing view per movement tick from the canonical config passed by `unified_scheduler.lua`.
- Canonical authority covers the complete spacing subtree: `enabled`, `band_min`, `band_max`, `model_size_floor`, `use_prediction`, `lookahead_s`, `repel_hold_ticks`, `overlap_deadband`, `repel_weight`, and `band_deadband`.
- The migration intentionally includes `band_min`, `band_max`, and `model_size_floor` even when spacing is disabled because those values also define ordinary combat-close stop distance and model-size compensation.
- When canonical config is present but `movement.spacing` is absent, combat movement uses the normalized spacing defaults rather than falling back to conflicting flat spacing state.
- Direct no-config compatibility callers retain the old flat spacing projection through one centralized `movement_spacing_config(settings, config)` fallback. A regression asserts every legacy `settings.spacing*` token in core appears exactly once, inside that compatibility projection.
- Added `tests/replay/harness/selftest_phase3_spacing_authority.lua` proving canonical spacing ON + flat OFF executes the spacing solver, canonical spacing OFF + flat ON does not execute flat spacing behavior, canonical `band_max` wins while spacing is disabled, and canonical `model_size_floor` changes combat-close stopping distance despite conflicting flat values.
- The regression also proves the scheduler continues passing the tick-stable canonical config into `core.apply_movement_for_scheduler`.
- Updated the movement-facade and spacing cast-lock contract fixtures to the current canonical-config call/dispatcher signatures while preserving their original movement ownership and cast-freeze ordering assertions.
- No flat-surface guard count drops in this slice because the compatibility-only flat spacing projection remains intentionally present for direct legacy callers; the new spacing regression mechanically prevents those flat reads from spreading elsewhere in unified core movement.
- Source audit found no additional unified scheduler/core consumers of the spacing tuning fields outside `unified_combat_core.lua`.
- `melee_engine.lua`, `dd2_module.lua`, and the generated/legacy DD2 engine retain flat spacing reads. They are already classified in the migration ledger as legacy-sensitive engines and explicitly short-circuit when the unified engine owns execution; they are not being falsely claimed as migrated by this Phase 3 scheduler/core slice.
- Automated proof on implementation head `460db4c695e93be08a14a664e3c30e1e78d6f5a6`: workflow `37121903528` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 spacing authority PASS, scheduler movement facade PASS, spacing cast-lock PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional spacing geometry, prediction, repel weighting, deadband, cast-freeze, movement ownership, or combat-close semantics changed except canonical Profile V2 now wins over conflicting flat spacing state on the unified scheduler path.
- Live-game smoke verification remains required for spacing enable/disable, close/retreat band behavior, party overlap repulsion, moving-target prediction, and spacing interaction with cast freezes before Phase 3 is complete.

### 2026-10-03 — Phase 3 follow slice implemented

- Migrated the unified follow domain to canonical Profile V2 authority across party follow, fight-follow timing/leader selection, partner coordination, puller leash policy, and path-vs-follow movement ownership.
- Added `uc_follow_config.lua` as the canonical follow runtime adapter for `config.follow.party`, `config.follow.fight`, `config.follow.partner`, and `config.follow.nyzul`.
- Durable names remain the source of truth; party/fight/partner/puller IDs are resolved from the live party at runtime. Legacy configured IDs are used only when the corresponding canonical durable name is absent, and camp leash mode intentionally resolves no player puller ID.
- `uc_party_follow.lua` no longer contains any `active_value_or_flat` follow readers. Party enablement, leader identity/name, follow min/max, and fight-follow minimum now read canonical follow config directly.
- `config.follow.enabled` is part of the party-follow gate. Partial canonical profiles that omit the parent flag preserve the normalizer's default of enabled=true rather than accidentally disabling follow.
- Follow participation now honors both canonical `config.ownership.domain_follow_enabled` and canonical `config.follow.enabled` / `config.follow.party.enabled`.
- `uc_pathing.lua` now uses canonical follow policy when deciding whether party follow owns movement, while its own `config.movement.path` settings remain deferred to the next pathing slice.
- `uc_runtime_overrides.lua` fight-leader accessors are now canonical-first. Conflicting flat `fight_leader`, `fight_leader_name`, and `fight_leader_id` state can no longer override Profile V2.
- `unified_combat_core.lua` overlays canonical follow partner policy into its scheduler runtime view, so partner target ownership, fight-leader targeting, and puller/camp leash movement consume canonical `config.follow.partner` values.
- `unified_scheduler.lua` partner tiebreak arbitration now uses canonical partner enablement/IDs and canonical target-ignore policy; fight-follow hold duration now comes from canonical `config.follow.fight.hold_s`.
- Combat-provider partner target-set calls now pass `ctx.config`, so WS/sleep/ability partner exclusions use canonical partner state.
- Nyzul follow policy was already canonical: `uc_nyzul_runtime.lua` reads `config.follow.nyzul.*` directly, so no runtime churn was required there.
- Added `tests/replay/harness/selftest_phase3_follow_authority.lua` proving live canonical name→ID resolution, canonical party/fight/partner/puller projection over contradictory flat state, canonical fight-leader ON/OFF precedence, and camp-leash runtime-ID behavior.
- Strengthened `selftest_movement_priority_arbitration.lua` so canonical party-follow behavior is proven both against conflicting flat state and with missing canonical follow policy failing closed instead of falling back to flat.
- Updated runtime-overrides, active-config-consumer, configurable-control-range, and partner-arbitration contracts for the new authority boundary.
- Flat-surface guard burn-down: `uc_party_follow.lua` `active_value_or_flat` count 7→0; `uc_pathing.lua` 9→7 by removing its two follow-related fallback readers.
- Legacy-sensitive `melee_engine.lua` / `dd2_module.lua` retain their own flat follow/partner settings and remain separately classified compatibility debt outside the unified scheduler follow slice.
- Automated proof on implementation head `272149baa442a03b65b0e1757fadf2a73a926281`: workflow `37143116074` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 follow authority PASS, movement-priority arbitration PASS, runtime-overrides PASS, partner-arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional party-follow geometry, zone replay, combat transition suppression, partner arbitration ranking, puller leash geometry, or fight-follow timing semantics changed except canonical Profile V2 now wins over conflicting flat follow state.
- Live-game smoke verification remains required for same-zone party follow, zone replay, fight-follow distance changes, partner target coordination, player/camp puller leash modes, and follow/path movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 pathing slice implemented

- Migrated unified route-follow and path-hunter policy to canonical Profile V2 authority.
- Added `uc_path_config.lua` as the canonical runtime adapter for durable `config.movement.path` policy plus the existing canonical `config.legacy.hunter` gate.
- `uc_pathing.lua` now reads recording enablement, path-follow enablement, party gate distance, and resume-index window only from canonical path policy. Its `active_value_or_flat` count is 7 → 0.
- Route identity/progress is explicitly runtime-owned: selected path filename, classified route type, distance-to-start, and recorded point list stay on live/session state and are not projected from Profile V2 over the runtime.
- Profile V2 durable comparison ignores those four route/session fields, and canonical-to-flat apply preserves the live values already present in the runtime settings table. Existing Profile V2 files may still carry route-state compatibility fields; this slice does not rewrite the file schema.
- The existing Profile V2/WinForms route-state fields remain compatibility schema debt for now. Runtime authority is removed without changing their serialized compatibility shape in this slice.
- Unified target selection overlays canonical path/hunter policy before evaluating hunter enablement, target names, vertical tolerance, and target range.
- Scheduler pull selection overlays canonical path/hunter policy for hunter enablement, path-follow gate, target list, pull action type/name, and attack fallback. Both target-control and combat providers pass `ctx.config` into pull selection.
- Missing canonical path policy uses canonical defaults/fails closed rather than reviving contradictory flat path-follow or hunter state.
- Added `tests/replay/harness/selftest_phase3_pathing_authority.lua` covering canonical-vs-flat route/hunter/pull policy, canonical OFF precedence, default fail-closed behavior, and preservation of live route/session state.
- Strengthened movement arbitration and added a focused Profile V2 durable-diff regression so stale flat path-follow state and route-session placeholders cannot regain authority.
- Flat-surface guard burn-down: `uc_pathing.lua` `active_value_or_flat` count 7 → 0.
- No intentional route geometry, pause/resume arbitration, hunter candidate ranking, pull readiness/range, or movement-dispatch semantics changed except that canonical Profile V2 now wins for durable path policy.
- Live-game smoke verification remains required for path recording start/stop, route-file rebinding, route follow, hunter target filtering, configured pull action/fallback, and follow/path/camp-pull movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 movement-owned durable settings slice implemented

- Added `uc_movement_config.lua` as the canonical adapter for movement-owned durable policy.
- The remaining scheduler movement controls now come from canonical Profile V2: `config.movement.move`, `config.combat.manual`, `config.combat.static`, and `config.combat.face`.
- `unified_combat_core.lua` uses one canonical movement-control view when a scheduler config snapshot is supplied. Flat `move`/`manual`/`static` reads remain only as an explicit compatibility path for callers that omit canonical config entirely.
- Scheduler ordinary facing now receives canonical config explicitly and uses canonical `config.combat.face`; forced turn-away behavior remains force-owned and is unchanged.
- `run_movement_coordinator_tick` now receives the tick-stable canonical config explicitly instead of reaching for the process-local `get_tick_ctx()` symbol from outside its lexical scope.
- The same explicit snapshot is reused for RUN no-TP facing, fight-follow hold timing, ordinary facing, and core combat-close movement.
- Removed the movement coordinator's residual flat `fight_follow_hold_s` fallback. Missing canonical fight timing uses the established 8-second default rather than stale flat state.
- `UC_IsCombatParticipant` and `UC_IsMovementParticipant` now classify participation from canonical Profile V2 through `uc_movement_config`, while current engine-running state remains runtime-owned through `Start_Engine`.
- Canonical participation covers autotarget, explicit move, base/named formations, tank, hunter+path-follow, puller, add-control, and spacing (movement participation only). Formation/named-formation runtime itself was already canonical and required no rewrite.
- Added `tests/replay/harness/selftest_phase3_movement_authority.lua` proving contradictory canonical-vs-flat authority for move/manual/static, canonical participant/domain behavior, face policy, explicit coordinator config plumbing, and protection against hidden `get_tick_ctx` fallback.
- The contradictory-state movement test exposed a pre-existing core authority leak in the earlier combat-enable cutover: Lua's `a and canonical_false or flat_value` idiom caused canonical `autotarget=false` / `auto_engage=false` to fall through to conflicting flat `true`. Core movement now uses explicit canonical-vs-compatibility branches, so canonical false is authoritative.
- Automated proof on implementation head `367201f60d99156133bea2726813e6f3ebad7a02`: workflow `37200907676` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 movement authority PASS, formation activation PASS, spacing cast-lock PASS, RUN no-TP PASS, defensive/support movement-lock tests PASS, all earlier Phase 2/3 authority suites PASS, and the flat-surface guard PASS.
- Flat-surface guard burn-down: `UnifiedCombat.lua` literal `UC_SETTINGS` count 79 → 77 by removing the two participant helpers' flat settings dependency.
- Existing legacy DD2/melee engine movement controls remain separately classified compatibility debt and are not claimed as migrated by this unified scheduler/core slice.
- Live-game smoke verification remains required for explicit Move mode, Manual/Static movement suppression, ordinary Face on/off, formation participation, and coordinator mode transitions before Phase 3 live acceptance is complete.


### 2026-10-04 — Phase 3 automated exit audit implemented

- Audited the common scheduler/core durable-authority boundary after all listed Phase 3 domain slices.
- Scheduler proposal revalidation is now canonical/fail-closed: `uc_scheduler_ranker.lua` no longer falls back to `ctx.settings[required_setting]` when a proposal dependency is unmapped.
- Added canonical `sleep` required-setting resolution through `config.sleep.enabled`; production `required_setting` tokens are now enumerated by the exit regression so future unmapped proposal dependencies fail CI.
- Added explicit canonical `config.combat.prime` access and moved combat-commitment fight-leader evaluation to the tick's `ctx.config` / `uc_follow_config` snapshot. Contradictory flat Prime/fight state can no longer influence runtime commitment.
- Migrated the common charm-sleeper and sleep-waker feature gates to `ctx.config.defensive.*` directly. Their focused tests now deliberately oppose canonical and flat values on every collection pass.
- Removed the Phase 2-deferred direct `UC_SETTINGS.log_combat_sched` read from `uc_scheduler_action_state.lua`; core action-state diagnostics now use canonical `config.debug.combat_sched`.
- Added `tests/replay/harness/selftest_phase3_exit_audit.lua` to freeze the common authority contract: every production scheduler `required_setting` must have a canonical mapping, common defensive providers may not receive flat fallback authority, combat commitment must use explicit canonical config, and core's sole direct `UC_SETTINGS` accessor remains the explicit no-config compatibility seam.
- Flat-surface burn-down in this audit: `uc_combat_commitment.lua` `ctx.settings` 3→1; `uc_scheduler_ranker.lua` 3→2; `uc_provider_charm_sleeper.lua` and `uc_provider_sleep_waker.lua` drop their `ctx.settings` / `active_value_or_flat` surfaces entirely; `uc_scheduler_action_state.lua` drops its final direct `UC_SETTINGS` read.
- Expanded exit-audit tracing proved several canonical-first fallbacks were still on the live common path. The unified scheduler now has **zero** `active_value_or_flat(` calls (32→0) and its `ctx.settings` surface falls 11→2; the remaining two are runtime/cross-domain plumbing rather than durable common policy.
- Common defensive Cure/Curaga/Waltz/Na/buff selection, critical-cure classification, Doom-water eligibility, and shared SCH defensive tuning now consume the explicit canonical config snapshot.
- Sleep collection is canonical end-to-end: enablement, ordered spell list, range, effect suppression, and spell selection all consume `ctx.config`; stale flat `sleep` / `sleepspells` state can no longer drive scheduler collection.
- Combat Prime and fight-leader collection now consume canonical `ctx.config` as well as the earlier commitment path. `uc_provider_combat.lua` flat-context markers fall 20→11; survivors are partner/pull/WS/job-runtime seams tracked separately rather than Sleep/Prime/fight durable authority.
- Remaining flat scheduler/provider surfaces are explicitly outside this common Phase 3 authority boundary: RUN/SCH/SMN/PUP job configuration moves to Phase 4, scheduler cadence fields such as `_sched_next_*` are runtime state, diagnostic helpers are non-action authority, and explicit no-config core/legacy callers remain compatibility-only.
- The prior follow/pathing tests continue to prove configured names are durable while resolved party/fight/partner/puller IDs are live-derived; path route/session state remains non-authoritative compatibility schema debt rather than scheduler policy.
- Automated proof on implementation head `a3670fa83a055ad582be0b5ff6bab7821f4a2950`: workflow `37205168055` completed successfully with `lua-sequence` PASS, the Phase 3 automated exit audit PASS, flat-surface guard PASS, all earlier Phase 2/3 authority suites PASS, and `winforms` PASS. Live-game smoke verification remains required before Phase 3 live acceptance is complete.

## Working checklist

When completing any migration slice:

- [ ] inspect current callers and writers;
- [ ] classify durable config vs runtime state;
- [ ] identify exact canonical path(s);
- [ ] add or update tests before removing fallback;
- [ ] migrate the smallest cohesive consumer set;
- [ ] verify changed Lua with Lua 5.1 tooling where available;
- [ ] run targeted tests;
- [ ] update flat-consumer allowlist/guardrail;
- [ ] update this document's phase status and progress log;
- [ ] note live-game verification still required, if applicable;
- [ ] keep rollback straightforward.

## Completion definition

This migration is complete only when Profile V2 is the single durable configuration authority from editor/save through runtime consumption, and flat compatibility state can no longer change durable automation semantics.
` trim-pattern text as a replacement token and duplicated the file tail. `uc_cor_maintenance.lua` was rebuilt from the last immutable green version and the intended change was reapplied with literal-safe replacement; these were tooling/parse failures, not design/runtime failures.\n\n### 2026-10-07 — Phase 5 partner/follow identity write pipeline implemented

- Migrated the final bespoke Phase 5 identity group to canonical durable names: `config.follow.party.leader_name`, `config.follow.fight.leader_name`, `config.follow.partner.names`, and `config.follow.partner.puller_name`.
- Tightened the durable/runtime identity contract. When a durable name is configured, runtime IDs are derived only from the current party roster. An offline/unresolved durable name remains in Profile V2 but produces runtime ID `0` (or no partner ID); a stale legacy ID can no longer substitute for that configured name. Legacy IDs remain compatibility fallback only when the corresponding durable name/list is absent.
- Removed the residual `get_mob_by_name` fallback from follow identity resolution, so a visible/non-party entity with the same configured name cannot masquerade as a current party member.
- Added `uc_active_config.replace_name(path, value)` for canonical scalar identity editing. Editing party leader, fight leader, or puller names clears the matching legacy ID, and partner-name list edits clear legacy `partner.ids`.
- Reworked `remote_bridge.lua` compatibility operations `set_partner`, `set_fight_leader`, `set_party_follow`, `partner_add`, `partner_add_current`, `partner_remove`, and `partner_replace_names` to edit active Profile V2 first and refresh flat state only through compatibility projection. The bridge no longer requires `uc_partner_list` for these writes.
- WinForms partner/puller/fight-leader/party-follow identity controls are now local-only durable edits. They call `CaptureWorkingProfileFromUi(sid)` and emit no live identity mutation; partner Add Current consumes the runtime-observed target name. `PushFullFormState` no longer sends any of the retired partner/follow identity operations.
- The structured writer already had the correct persistence contract and remains unchanged: names are durable; partner IDs, puller ID, fight-leader ID, and party-follow leader ID are not written into new Profile V2 files.
- Added `tests/replay/harness/selftest_phase5_follow_identity_write_pipeline.lua`. It proves scalar-name editing, partner-name dedupe, stale-ID clearing, current-party name→ID derivation, offline-name persistence, non-party rejection, legacy-ID fallback only when names are absent, camp-leash behavior, no-flat bridge authority, local-only WinForms editing, full-form push removal, and writer persistence.
- Flat-surface burn-down: `remote_bridge.lua` direct `UC_SETTINGS` references **18→11**.
- Implementation head `d08248c52dedbbe4a7b831f74ce7a20aa08786ab` is proven by workflow `37639924219`: Phase 5 partner/follow identity pipeline PASS, Phase 3 follow authority PASS, all prior Phase 5 pipelines PASS, Profile V2 flat-surface guard PASS at the 11-reference bridge baseline, full Lua sequence PASS, and WinForms/Profile V2/Activity Profile tests PASS.
- The immediately preceding workflow `37639773362` reached and passed every earlier Lua gate through the COR Phase 5 slice, then failed only in the new focused test because the test passed the `follow` subtree to an adapter whose public API expects the root canonical config. The regression call site was corrected; no production-code rollback or behavior change was required.
- Phase 5 is complete. Live-game smoke verification remains required for party follow, fight-leader handoff, partner coordination, player/camp puller behavior, offline/rejoin identity resolution, and UI save/reload round trips before final live acceptance.

### Phase 6 — Retire the durable flat projection

Status: **NOT STARTED**

Goals:

- remove remaining durable projections from canonical config into `_G.UC_SETTINGS`;
- shrink `uc_new_settings_defaults()` to true runtime/compatibility needs or replace it with better-scoped state owners;
- remove mixed-shape normalization for normal runtime paths;
- retain compatibility wrappers only where an external/public contract still requires them;
- make any surviving `UC_SETTINGS` usage explicitly non-authoritative.

Exit criteria:

- [ ] no durable runtime behavior depends on `_G.UC_SETTINGS`;
- [ ] no durable UI write mutates `_G.UC_SETTINGS` as source of truth;
- [ ] canonical config is the only durable authority;
- [ ] mixed flat/nested normalizer ambiguity is removed from normal runtime;
- [ ] compatibility surfaces are documented and intentionally bounded.

### Phase 7 — Final cleanup and conformance

Status: **NOT STARTED**

Goals:

- remove dead compatibility adapters;
- remove obsolete flat field projections and tests that only preserve retired behavior;
- update architecture docs and README;
- run full Lua and WinForms test suites;
- perform targeted live-game acceptance across representative jobs and domains.

Required live acceptance should include at least:

- BRD maintenance;
- COR maintenance;
- GEO maintenance;
- defensive healing/buffs;
- recurring combat spells;
- tank/RUN behavior;
- WS/skillchain behavior;
- pulling;
- follow/pathing;
- SMN;
- PUP;
- SCH;
- activity profile apply;
- profile Save/reload;
- job/subjob identity transition.

Exit criteria:

- [ ] source-contract audit shows no unintended flat durable reads/writes;
- [ ] automated suites green;
- [ ] targeted live acceptance completed;
- [ ] architecture docs describe the final ownership model accurately.

## Regression scenarios that must survive the migration

These are architecture acceptance cases, not merely unit tests.

### Food and Bard sibling isolation

Given:

```lua
config.maintenance = {
    brd = {
        enabled = true,
        songs = { 'Honor March', 'Victory March' },
    },
    food = {
        enabled = true,
        item = 'Grape Daifuku',
    },
}
```

Changing `maintenance.food` must never alter, disable, default, or reinterpret `maintenance.brd`.

### Canonical false values remain authoritative

A canonical explicit `false` must not fall through to a legacy flat `true`.

### Missing canonical subtree behavior is explicit

A missing optional subtree must use canonical defaults, not resurrect stale flat compatibility values.

### Runtime state cannot become durable

Engine state, current IDs, live locks, target state, and similar transient values must never be serialized merely because they previously lived in `UC_SETTINGS`.

### UI/runtime round trip

Canonical Profile V2 -> runtime active config -> editor -> save must preserve durable semantics without requiring flat compatibility state to fill missing fields.

## Progress log

### 2026-10-02 — Migration branch created

- Created `refactor/profile-v2-single-source` from current `master`.
- Confirmed Profile V2 is already the intended durable source.
- Confirmed `_G.UC_ACTIVE_PROFILE.config` is already the intended canonical applied config.
- Identified `_G.UC_SETTINGS` as the major compatibility surface still feeding runtime consumers.
- Identified major flat producers in addon startup, active-config projection, bridge live writes, and WinForms editor/write adapters.
- Identified initial consumer families for Phase 0 inventory.
- No gameplay behavior changed.

### 2026-10-02 — Rabao BRD investigation clarified

- Confirmed BRD song maintenance is intentionally blocked in configured city zones, including Rabao.
- Confirmed the observed "BRD never sings" case in Rabao was expected city-zone behavior, not evidence of a current BRD config regression.
- The configuration migration remains necessary because the mixed flat/nested model is still structural technical debt.

### 2026-10-02 — Phase 0 inventory and guardrails completed

- Added `docs/profile_v2_flat_surface_inventory.md` as the detailed producer/consumer and field-ownership baseline.
- Added a repository-wide source guardrail that freezes direct `UC_SETTINGS`, indirect `ctx.settings`, `active_value_or_flat`, canonical-to-flat projection, bridge flat mutation, and WinForms flat write/translation seams.
- Added a machine-readable allowlist with exact current source occurrence counts. Future migration slices should shrink it; new flat seams fail the guardrail unless explicitly reviewed.
- Classified durable field families, runtime/transient state, compatibility-only aliases, and explicit ambiguous ownership decisions.
- Added the mixed nested-food + flat-BRD maintenance characterization fixture. It records the current known normalizer defect without changing runtime behavior.
- Phase 0 made documentation/test-only changes; no scheduler/provider/gameplay behavior changed.

### 2026-10-02 — Phase 1 canonical runtime read boundary completed

- Added `uc_scheduler_context_utils.get_config()` as the scheduler-owned canonical accessor over the applied `_G.UC_ACTIVE_PROFILE.config`.
- Scheduler tick contexts now expose `ctx.config` alongside the unchanged compatibility `ctx.settings` surface.
- Canonical config is sampled once when the tick context is built and passed by identity; providers do not reparse Profile V2 files.
- The context builder remains dependency-injected and does not directly require `uc_active_config`.
- Added deterministic fixture/static coverage for active-config lookup, missing-config fallback, one-sample-per-context behavior, and scheduler wiring.
- No proposal provider, ranking rule, dispatch path, or durable config consumer changed in this phase; the Phase 0 flat allowlist is intentionally unchanged.
- PR verification now runs the flat-surface guard, mixed-shape characterization, scheduler canonical-context tests, and context-utils fixtures on every migration PR update.
- Draft PR #73 is the long-lived migration/CI surface. Verification run 36981070413 passed both `lua-sequence` and `winforms` after the guardrail baseline and fixture-count expectations were corrected.
- The new guardrail immediately found three pre-existing `UnifiedCombat.lua` flat-sync call sites that the initial mechanical audit had missed; they are now explicitly baselined rather than silently ignored.

### 2026-10-02 — Mainline legacy-food compatibility hotfix incorporated

- Mainline PR #74 fixed Activity/Profile V2 apply failures for profiles created before `maintenance.food` existed.
- Legacy Profile V2 maintenance domains now materialize `food = { enabled = false, item = '' }` before canonical-to-flat compatibility projection, preventing stale live food settings from leaking into conversion validation.
- The focused regression reproduces the Etamame SAM/DRG Activity Apply failure shape and asserts the exact structured conversion path returns zero mismatch.
- The hotfix was merged to `master` as `c8a084b9a29dd412e99fa3cf5dec4e0e90cf1b3f` and has been incorporated into this migration branch before Phase 2.

### 2026-10-02 — Phase 2 low-risk leaf migration implemented

- Food maintenance and recurring combat spells now consume only the canonical scheduler snapshot at `ctx.config`; stale `ctx.settings` values are deliberately ignored.
- Defensive provider gates/resurrection, enemy-buff removal, and enemy-debuff maintenance now consume `ctx.config.defensive.*` directly.
- Raise acceptance and weakened recovery-hold now read only `uc_active_config`; their direct `UC_SETTINGS` fallback paths were removed.
- GEO camp placement now reads only `config.maintenance.geo` from active Profile V2 state.
- Defensive buff maintenance now receives canonical config explicitly from the scheduler, including structured targeted buffs and BRD ownership state; its hidden active-config/global fallback was removed.
- COR maintenance now receives canonical config explicitly from the maintenance provider. Roll policy, range requirements, Light Shot-on-Dia policy, and ability-derived roll fallback stay inside canonical `config.maintenance.cor` / `config.abilities.configured`.
- The Phase 0 allowlist shrank by 11 source-file entries / 60 literal flat-surface hits. The remaining `uc_scheduler_action_state.lua` debug-only `UC_SETTINGS` reader is intentionally deferred with the core scheduler work in Phase 3 rather than widening this leaf migration.
- Deterministic tests include intentionally conflicting stale flat values so a migrated leaf fails if flat compatibility regains authority.
- Full PR CI passed at Phase 2 verification head `a396671884229447f10ea85d5399e69a58003275` (workflow run `36992724235`): both Lua and WinForms jobs succeeded, including the flat-surface guard and the dedicated Phase 2 canonical-leaf suite.
- Added `tests/replay/harness/selftest_phase2_canonical_authority.lua`: a dedicated 21-case contradictory-state matrix whose only purpose is to prove canonical Profile V2 values beat deliberately opposite flat compatibility values across every Phase 2 consumer family.
- The matrix covers food, recurring spells, defensive provider/critical threshold, resurrection, enemy buff removal, enemy debuff maintenance, COR routing, defensive buff maintenance, COR roll selection, GEO placement, Raise acceptance, and weakened recovery hold. Both enable/disable directions are exercised where a boolean gate exists.
- Workflow run `37016053323` passed both `lua-sequence` and `winforms`; the canonical-authority matrix reported `21/21 PASS`.
- Live-game smoke verification remains before merge, especially food, recurring spells, defensive maintenance, COR upkeep, raise acceptance, recovery hold, and GEO camp placement.
- Phase 2 implementation began with `0f707e1863846dcc74d0dd56cb791cbbf8bbb0ed`; the verified Phase 2 head is `a396671884229447f10ea85d5399e69a58003275`.

### 2026-10-02 — Phase 3 combat enablement/autotarget slice implemented

- Began Phase 3 with the smallest core domain: combat enablement/target acquisition gates, specifically canonical `config.combat.autotarget` and `config.combat.auto_engage`.
- Added canonical-only scheduler helpers for autotarget and auto-engage while retaining compatibility helpers for unmigrated non-scheduler callers.
- Migrated scheduler-owned target acquisition and engage gates to `ctx.config`; contradictory flat `ctx.settings.autotarget` / `auto_engage` values can no longer change those provider decisions.
- Passed canonical tick config through core target selection, tank-enmity selection, death-switch revalidation, partner arbitration, and pre-engage combat-close movement so hidden flat autotarget fallbacks do not survive behind provider boundaries.
- Added `tests/replay/harness/selftest_phase3_combat_enablement_authority.lua` with contradictory canonical-vs-flat cases for autotarget and auto-engage plus static wiring assertions.
- Added the new Phase 3 proof to PR CI and the aggregate replay suite.
- Reduced the flat-surface guard by four `ctx.settings` hits: two from `uc_provider_target_control.lua` and two from `uc_provider_combat.lua`.
- Existing combat-extension provider coverage now supplies canonical combat config explicitly; legacy helper fallback tests remain intact for callers that have not migrated yet.
- No weaponskill, ability, pulling, target-priority, tank-policy, ranking, or dispatch semantics are intentionally changed by this slice.
- During contradictory-state proof, the first canonical auto-engage implementation exposed a Lua false-value bug: `condition and value or nil` collapsed explicit canonical `false` to `nil`, incorrectly restoring the default `true`. The canonical accessor was corrected to preserve explicit false, and the regression now proves both directions.
- Automated proof on branch head `cf827cd87f0eafe8b9917743d97ed7a2015944b2`: workflow `37023674659` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 2 canonical-authority coverage PASS, the new Phase 3 combat enablement canonical-authority test PASS, and the flat-surface guard PASS.
- Live-game smoke verification remains required before the Phase 3 core migration is considered complete.

### 2026-10-02 — Phase 3 weaponskill configuration slice implemented

- Migrated the full scheduler-owned weaponskill decision path to canonical Profile V2 authority.
- Canonical WS policy now covers `config.combat.weaponskill.enabled`, primary WS, mode, minimum TP, AoE permission, Fast Skillchain, no-skillchain target names, skillchain target preference, ally-wait ignore names, aftermath enablement, and aftermath WS.
- Included canonical `config.combat.spam` and `config.legacy.solo` in the WS view because both directly alter weaponskill arbitration/bypass behavior.
- Deliberately left `ability_active` as a compatibility input for Chivalry reservation; that belongs to the next Phase 3 abilities slice.
- Proposal collection now gates WS enablement from `ctx.config`; the core planner receives canonical config and overlays all WS-owned durable fields before selecting an action.
- Canonical config is carried through rank-commit Smart-AoE/skillchain revalidation and final WS intent dispatch, preventing a canonical proposal from being revalidated against stale flat WS policy.
- Added `tests/replay/harness/selftest_phase3_weaponskill_authority.lua` to prove canonical WS enablement beats opposite flat state and to statically require every WS-owned field at the canonical boundary.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory-state cases proving canonical primary WS, minimum TP, AoE policy in both directions, Smart vs primary-only mode, aftermath policy, and Fast Skillchain false/true behavior.
- Added the weaponskill authority suite to normal PR CI and the aggregate replay suite.
- Reduced `uc_provider_combat.lua` flat-context guard count from 26 to 25 by removing the flat `weaponskill_active` provider gate. The remaining `ctx.settings` handoff exists for explicitly unmigrated non-WS inputs such as Chivalry's ability gate.
- Automated proof on branch head `7191d7a550dcb467e3e1166f787c2f3ba719dde4`: workflow `37027431136` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill canonical-authority PASS, WS maintenance/skillchain precedence PASS, and the flat-surface guard PASS.
- No intentional weaponskill ranking, timing, TP threshold semantics, skillchain planning semantics, or dispatch behavior changed except that canonical Profile V2 now wins when flat compatibility state conflicts.
- Live-game smoke verification remains required for representative Smart WS, spam/solo, primary-no-SC, aftermath, and Fast Skillchain configurations before Phase 3 is complete.

### 2026-10-02 — Phase 3 abilities slice implemented

- Migrated scheduler-owned generic configured-JA authority to canonical `config.abilities`: enablement, allow-unengaged policy, configured ability ordering, and legacy-slot fallback.
- Added `uc_ability_pipeline.collect_ordered_from_config`; scheduler generic JA collection now chooses the ability list from Profile V2 before applying unrelated RUN ownership filtering.
- Migrated the shared allow-unengaged policy in `uc_provider_tank_enmity.lua` to canonical `config.abilities.allow_unengaged`.
- Closed the deferred Chivalry dependency from the WS slice: the scheduler WS settings view now overlays canonical ability enablement, configured abilities, and legacy slots before Chivalry TP-reservation logic runs.
- Discovered a hidden post-proposal authority leak in `uc_scheduler_ranker.lua`: proposals carrying `required_setting` were rechecked directly against `ctx.settings`. This could silently override canonical `autotarget`, `weaponskill_active`, and `ability_active` decisions after a proposal had already been built.
- Added `uc_scheduler_config.required_setting_value_from_config` and migrated ranker validation so those three already-migrated settings revalidate against canonical config; unknown/unmigrated required settings such as Sleep intentionally retain the flat fallback.
- Added `tests/replay/harness/selftest_phase3_abilities_authority.lua` covering canonical ability enable/disable, configured-list precedence, legacy-slot fallback, unengaged policy, required-setting resolution, and static scheduler/core/ranker wiring.
- Strengthened `selftest_unengaged_abilities.lua` so generic and tank lanes both test canonical OFF + flat ON and canonical ON + flat OFF.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory Chivalry cases: canonical enabled/list beats flat disabled/empty, canonical disable beats flat enabled, canonical configured list beats flat Chivalry, and canonical legacy-slot fallback still reserves TP.
- Extended `selftest_scheduler_ranker.lua` with contradictory canonical required-setting cases.
- Reduced the flat-surface guard by four more hits: `uc_provider_combat.lua` from 25 to 22 `ctx.settings` reads and `uc_provider_tank_enmity.lua` from 3 to 2.
- `config.abilities.wsabilities` is not consumed by the scheduler configured-JA path; it remains projected for legacy-engine compatibility and is not being misrepresented as part of this scheduler-domain cutover.
- Automated proof on implementation head `eda088b075eee3084d23728fa7d529ac4435314c`: workflow `37045140212` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, contradictory unengaged tests PASS, ranker authority PASS, Chivalry/WS precedence PASS, and the flat-surface guard PASS.
- No intentional JA priority, readiness, targeting, range, or dispatch semantics changed; the behavioral change is authority only—canonical Profile V2 wins over conflicting flat compatibility state.
- Live-game smoke verification remains required for configured self/enemy JAs, unengaged override behavior, tank-enmity unengaged actions, and Chivalry TP reservation before Phase 3 is complete.

### 2026-10-02 — Phase 3 target-control and ignore/priority slice implemented

- Migrated scheduler-owned targeting authority for `config.targeting.add_control`, the ordered target/add priority list, and `config.targeting.target_ignore_names`.
- Added canonical targeting accessors in `uc_scheduler_config.lua`.
- The scheduler priority rule is now explicit: `config.targeting.targets` is authoritative when non-empty; normalized `config.targeting.add_priority_names` remains only the compatibility fallback.
- `unified_combat_core.lua` overlays canonical Add Control, priority names, and target-ignore names into the scheduler settings view before target selection, tank target selection, death-switch revalidation, and Add Control evaluation.
- `uc_provider_target_control.lua` now passes `ctx.config` into Add Control enablement as well as target selection.
- `uc_provider_combat.lua` fight-leader engage arbitration now consults the same canonical Add Control gate, preventing engage and target-control lanes from disagreeing when flat compatibility state conflicts.
- Added `tests/replay/harness/selftest_phase3_targeting_authority.lua` proving canonical Add Control ON + flat OFF permits engaged retarget, canonical OFF + flat ON blocks it, canonical target ordering wins over conflicting flat priority order, and canonical target-ignore names win over conflicting flat ignore state.
- Updated the existing Add Control priority contract test for the canonical-context helper signatures.
- Added the targeting authority suite to normal PR CI and the aggregate replay suite.
- Flat-surface counts intentionally do not drop in this slice: Add Control still receives `ctx.settings` because fight-leader enablement is a separate follow/fight-leader domain that has not migrated yet. Target-owned fields within that mixed view are canonical.
- `config.targeting.targetability` and `config.targeting.ignore` are not scheduler target-selection inputs today; they remain legacy-engine/UI compatibility fields and are not being falsely claimed as migrated scheduler consumers.
- Automated proof on implementation head `51a8d1ddc62ef75b0c771ba0aefb7c241cd8e629`: workflow `37085163385` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, Phase 3 targeting authority PASS, Add Control priority eligibility PASS, and the flat-surface guard PASS.
- No intentional target ranking, claim policy, death-switch, Add Control eligibility, or engage-dispatch semantics changed except canonical Profile V2 now wins when targeting compatibility state conflicts.
- Live-game smoke verification remains required for Add Control retargeting, ordered add selection, target-ignore behavior, and fight-leader handoff before Phase 3 is complete.

### 2026-10-02 — Phase 3 tank/enmity configuration slice implemented

- Migrated common scheduler-owned tank authority to canonical Profile V2: `config.tank.enabled`, ordered `config.tank.enmity.actions`, and `config.tank.enmity.include_pets`.
- Added canonical tank/enmity accessors and an exact configured-action matcher in `uc_scheduler_config.lua`.
- `unified_combat_core.lua` now overlays canonical tank enablement and enmity actions into the scheduler settings view before tank violation selection.
- Combat engage weighting, generic-JA tank weighting, and target-acquire tank weighting now read `tank.enabled` from `ctx.config`.
- `uc_provider_tank_enmity.lua` now fails closed when canonical tank mode is disabled, uses canonical include-pets and enmity actions, and overlays canonical target-ignore names into pet-enmity violation selection.
- Fixed a real pre-existing authority/safety gap: the pet-enmity branch did not independently gate on tank enabled, so a pet recovery proposal could bypass the normal player-enmity path's tank gate. The provider now applies the canonical tank gate before either path.
- Tank-enmity and RUN-tank proposals now carry `required_setting = 'tank'`; the scheduler ranker resolves that dependency from canonical config.
- Final tank-enmity dispatch revalidates both canonical tank enablement and whether the selected recovery action is still present in the canonical enmity list, preventing a stale proposal from dispatching after a profile change.
- The shared top-level tank gate in `uc_provider_run_tank.lua` now reads canonical config. RUN-specific rune/ward/Foil policy under `config.tank.run` remains a separate subsystem and was not otherwise migrated in this slice.
- Fixed a cross-domain leak from the completed abilities slice: RUN tank's unengaged gate now uses canonical `config.abilities.allow_unengaged`.
- Fixed a movement/dispatch authority leak: RUN no-TP facing now receives canonical tank config in both the movement coordinator and combat dispatcher, so stale flat `tank=true` cannot keep no-TP facing active after canonical tank disable.
- Added `tests/replay/harness/selftest_phase3_tank_enmity_authority.lua` proving canonical tank ON + flat OFF, canonical tank OFF + flat ON, canonical action-list precedence, include-pets precedence, canonical pet target-ignore projection, ranker tank resolution, and dispatch-time canonical revalidation wiring.
- Strengthened the existing pet-enmity, RUN tank, RUN no-TP, tank priority/starvation, provider-shape, and migration-contract fixtures for the new canonical boundary.
- Reduced flat-context guard counts: `uc_provider_combat.lua` 22→20, `uc_provider_target_control.lua` 4→3, and `uc_provider_run_tank.lua` 3→1. `uc_provider_tank_enmity.lua` remains at 2 because it still passes compatibility context into separately owned target/friendly-selection helpers while all tank-owned fields are canonical.
- Automated proof on implementation head `447767bf7a8370e1e16b8949bd611a23f348ea7a`: workflow `37086243234` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 tank-enmity authority PASS, pet-enmity provider/config PASS, RUN tank PASS, RUN no-TP PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional tank priority bands, victim ranking, action readiness, range, dispatch method, RUN rune/ward policy, or engage semantics changed except canonical Profile V2 now wins over conflicting flat tank/enmity state and stale tank proposals fail closed.
- Live-game smoke verification remains required for PLD/RUN tank target acquisition, player and pet enmity recovery, canonical tank disable, configured recovery-action changes, and RUN no-TP facing before Phase 3 is complete.

### 2026-10-02 — Phase 3 pulling slice implemented

- Migrated the modern camp-puller domain, `config.combat.pulling`, to canonical Profile V2 authority across lane acquisition, proposal collection, candidate revalidation, movement ownership, action-result handling, and final dispatch revalidation.
- Added `uc_scheduler_config.combat_pulling_from_config` as the canonical accessor.
- `uc_camp_puller.lua` now reads `ctx.config.combat.pulling` directly and has zero `ctx.settings` reads.
- Camp-puller candidate ignore checks now receive canonical `ctx.config` and reuse canonical `config.targeting.target_ignore_names`; stale flat ignore state can no longer alter pull candidate selection.
- `unified_scheduler.lua` now resolves camp-pulling configuration from `uc_scheduler_context_utils.get_config()` for movement reservation and asynchronous action-result paths, and final camp-puller dispatch revalidates against the fresh canonical tick config.
- Party-follow and route/path movement ownership checks now read `config.combat.pulling` from `uc_active_config`, so stale flat `camp_pulling.enabled` cannot make movement consumers disagree with the scheduler. Missing canonical pull config fails closed as disabled rather than falling back to flat state.
- Strengthened `selftest_camp_puller.lua` so its full state-machine run uses canonical pulling enabled while the flat compatibility mirror is disabled.
- Added `tests/replay/harness/selftest_phase3_pulling_authority.lua` covering canonical ON + flat OFF lane acquisition, canonical OFF + flat ON fail-closed behavior, canonical target-ignore authority, and static scheduler/follow/pathing wiring.
- Strengthened `selftest_movement_priority_arbitration.lua` with both contradictory directions for cross-domain movement ownership: canonical pull ON + flat OFF suppresses follow, while canonical pull OFF + flat ON does not.
- Added the pulling authority suite to normal PR CI and the aggregate replay suite.
- Reduced the flat-surface guard further: `uc_camp_puller.lua` from 4 to 0 `ctx.settings` hits and `unified_scheduler.lua` from 12 to 11.
- Final branch audit found no remaining runtime reads of the flat `camp_pulling` mirror in `uc_camp_puller.lua`, `unified_scheduler.lua`, `uc_party_follow.lua`, or `uc_pathing.lua`; remaining appearances are compatibility projection/default surfaces and canonical helper names.
- The older hunter/path pull action (`path_pull_action_type`, `path_pull_action_name`, hunter/path-follow gates) belongs to `config.movement.path` and is intentionally deferred to the later pathing slice rather than being mixed into this pulling cutover.
- Automated proof on implementation head `a9967ee43f09d27f382df13867dd15cb441bcc40`: workflow `37086936986` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 pulling authority PASS, full camp-puller state machine PASS, camp-puller policy PASS, movement-priority arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional pull candidate ranking, quota policy, leash geometry, action readiness/range, retry policy, lane priority, or dispatch semantics changed except that canonical Profile V2 now wins over conflicting flat camp-pulling state.
- Live-game smoke verification remains required for camp lane acquisition, pull action execution, canonical disable during an active journey, target-ignore filtering, return-to-camp behavior, and movement handoff before Phase 3 is complete.

### 2026-10-03 — Phase 3 spacing slice implemented

- Migrated the unified scheduler/core spacing domain to canonical `config.movement.spacing` authority.
- Added `uc_scheduler_config.movement_spacing_from_config` as the canonical spacing accessor.
- `unified_combat_core.lua` now resolves one spacing view per movement tick from the canonical config passed by `unified_scheduler.lua`.
- Canonical authority covers the complete spacing subtree: `enabled`, `band_min`, `band_max`, `model_size_floor`, `use_prediction`, `lookahead_s`, `repel_hold_ticks`, `overlap_deadband`, `repel_weight`, and `band_deadband`.
- The migration intentionally includes `band_min`, `band_max`, and `model_size_floor` even when spacing is disabled because those values also define ordinary combat-close stop distance and model-size compensation.
- When canonical config is present but `movement.spacing` is absent, combat movement uses the normalized spacing defaults rather than falling back to conflicting flat spacing state.
- Direct no-config compatibility callers retain the old flat spacing projection through one centralized `movement_spacing_config(settings, config)` fallback. A regression asserts every legacy `settings.spacing*` token in core appears exactly once, inside that compatibility projection.
- Added `tests/replay/harness/selftest_phase3_spacing_authority.lua` proving canonical spacing ON + flat OFF executes the spacing solver, canonical spacing OFF + flat ON does not execute flat spacing behavior, canonical `band_max` wins while spacing is disabled, and canonical `model_size_floor` changes combat-close stopping distance despite conflicting flat values.
- The regression also proves the scheduler continues passing the tick-stable canonical config into `core.apply_movement_for_scheduler`.
- Updated the movement-facade and spacing cast-lock contract fixtures to the current canonical-config call/dispatcher signatures while preserving their original movement ownership and cast-freeze ordering assertions.
- No flat-surface guard count drops in this slice because the compatibility-only flat spacing projection remains intentionally present for direct legacy callers; the new spacing regression mechanically prevents those flat reads from spreading elsewhere in unified core movement.
- Source audit found no additional unified scheduler/core consumers of the spacing tuning fields outside `unified_combat_core.lua`.
- `melee_engine.lua`, `dd2_module.lua`, and the generated/legacy DD2 engine retain flat spacing reads. They are already classified in the migration ledger as legacy-sensitive engines and explicitly short-circuit when the unified engine owns execution; they are not being falsely claimed as migrated by this Phase 3 scheduler/core slice.
- Automated proof on implementation head `460db4c695e93be08a14a664e3c30e1e78d6f5a6`: workflow `37121903528` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 spacing authority PASS, scheduler movement facade PASS, spacing cast-lock PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional spacing geometry, prediction, repel weighting, deadband, cast-freeze, movement ownership, or combat-close semantics changed except canonical Profile V2 now wins over conflicting flat spacing state on the unified scheduler path.
- Live-game smoke verification remains required for spacing enable/disable, close/retreat band behavior, party overlap repulsion, moving-target prediction, and spacing interaction with cast freezes before Phase 3 is complete.

### 2026-10-03 — Phase 3 follow slice implemented

- Migrated the unified follow domain to canonical Profile V2 authority across party follow, fight-follow timing/leader selection, partner coordination, puller leash policy, and path-vs-follow movement ownership.
- Added `uc_follow_config.lua` as the canonical follow runtime adapter for `config.follow.party`, `config.follow.fight`, `config.follow.partner`, and `config.follow.nyzul`.
- Durable names remain the source of truth; party/fight/partner/puller IDs are resolved from the live party at runtime. Legacy configured IDs are used only when the corresponding canonical durable name is absent, and camp leash mode intentionally resolves no player puller ID.
- `uc_party_follow.lua` no longer contains any `active_value_or_flat` follow readers. Party enablement, leader identity/name, follow min/max, and fight-follow minimum now read canonical follow config directly.
- `config.follow.enabled` is part of the party-follow gate. Partial canonical profiles that omit the parent flag preserve the normalizer's default of enabled=true rather than accidentally disabling follow.
- Follow participation now honors both canonical `config.ownership.domain_follow_enabled` and canonical `config.follow.enabled` / `config.follow.party.enabled`.
- `uc_pathing.lua` now uses canonical follow policy when deciding whether party follow owns movement, while its own `config.movement.path` settings remain deferred to the next pathing slice.
- `uc_runtime_overrides.lua` fight-leader accessors are now canonical-first. Conflicting flat `fight_leader`, `fight_leader_name`, and `fight_leader_id` state can no longer override Profile V2.
- `unified_combat_core.lua` overlays canonical follow partner policy into its scheduler runtime view, so partner target ownership, fight-leader targeting, and puller/camp leash movement consume canonical `config.follow.partner` values.
- `unified_scheduler.lua` partner tiebreak arbitration now uses canonical partner enablement/IDs and canonical target-ignore policy; fight-follow hold duration now comes from canonical `config.follow.fight.hold_s`.
- Combat-provider partner target-set calls now pass `ctx.config`, so WS/sleep/ability partner exclusions use canonical partner state.
- Nyzul follow policy was already canonical: `uc_nyzul_runtime.lua` reads `config.follow.nyzul.*` directly, so no runtime churn was required there.
- Added `tests/replay/harness/selftest_phase3_follow_authority.lua` proving live canonical name→ID resolution, canonical party/fight/partner/puller projection over contradictory flat state, canonical fight-leader ON/OFF precedence, and camp-leash runtime-ID behavior.
- Strengthened `selftest_movement_priority_arbitration.lua` so canonical party-follow behavior is proven both against conflicting flat state and with missing canonical follow policy failing closed instead of falling back to flat.
- Updated runtime-overrides, active-config-consumer, configurable-control-range, and partner-arbitration contracts for the new authority boundary.
- Flat-surface guard burn-down: `uc_party_follow.lua` `active_value_or_flat` count 7→0; `uc_pathing.lua` 9→7 by removing its two follow-related fallback readers.
- Legacy-sensitive `melee_engine.lua` / `dd2_module.lua` retain their own flat follow/partner settings and remain separately classified compatibility debt outside the unified scheduler follow slice.
- Automated proof on implementation head `272149baa442a03b65b0e1757fadf2a73a926281`: workflow `37143116074` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 follow authority PASS, movement-priority arbitration PASS, runtime-overrides PASS, partner-arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional party-follow geometry, zone replay, combat transition suppression, partner arbitration ranking, puller leash geometry, or fight-follow timing semantics changed except canonical Profile V2 now wins over conflicting flat follow state.
- Live-game smoke verification remains required for same-zone party follow, zone replay, fight-follow distance changes, partner target coordination, player/camp puller leash modes, and follow/path movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 pathing slice implemented

- Migrated unified route-follow and path-hunter policy to canonical Profile V2 authority.
- Added `uc_path_config.lua` as the canonical runtime adapter for durable `config.movement.path` policy plus the existing canonical `config.legacy.hunter` gate.
- `uc_pathing.lua` now reads recording enablement, path-follow enablement, party gate distance, and resume-index window only from canonical path policy. Its `active_value_or_flat` count is 7 → 0.
- Route identity/progress is explicitly runtime-owned: selected path filename, classified route type, distance-to-start, and recorded point list stay on live/session state and are not projected from Profile V2 over the runtime.
- Profile V2 durable comparison ignores those four route/session fields, and canonical-to-flat apply preserves the live values already present in the runtime settings table. Existing Profile V2 files may still carry route-state compatibility fields; this slice does not rewrite the file schema.
- The existing Profile V2/WinForms route-state fields remain compatibility schema debt for now. Runtime authority is removed without changing their serialized compatibility shape in this slice.
- Unified target selection overlays canonical path/hunter policy before evaluating hunter enablement, target names, vertical tolerance, and target range.
- Scheduler pull selection overlays canonical path/hunter policy for hunter enablement, path-follow gate, target list, pull action type/name, and attack fallback. Both target-control and combat providers pass `ctx.config` into pull selection.
- Missing canonical path policy uses canonical defaults/fails closed rather than reviving contradictory flat path-follow or hunter state.
- Added `tests/replay/harness/selftest_phase3_pathing_authority.lua` covering canonical-vs-flat route/hunter/pull policy, canonical OFF precedence, default fail-closed behavior, and preservation of live route/session state.
- Strengthened movement arbitration and added a focused Profile V2 durable-diff regression so stale flat path-follow state and route-session placeholders cannot regain authority.
- Flat-surface guard burn-down: `uc_pathing.lua` `active_value_or_flat` count 7 → 0.
- No intentional route geometry, pause/resume arbitration, hunter candidate ranking, pull readiness/range, or movement-dispatch semantics changed except that canonical Profile V2 now wins for durable path policy.
- Live-game smoke verification remains required for path recording start/stop, route-file rebinding, route follow, hunter target filtering, configured pull action/fallback, and follow/path/camp-pull movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 movement-owned durable settings slice implemented

- Added `uc_movement_config.lua` as the canonical adapter for movement-owned durable policy.
- The remaining scheduler movement controls now come from canonical Profile V2: `config.movement.move`, `config.combat.manual`, `config.combat.static`, and `config.combat.face`.
- `unified_combat_core.lua` uses one canonical movement-control view when a scheduler config snapshot is supplied. Flat `move`/`manual`/`static` reads remain only as an explicit compatibility path for callers that omit canonical config entirely.
- Scheduler ordinary facing now receives canonical config explicitly and uses canonical `config.combat.face`; forced turn-away behavior remains force-owned and is unchanged.
- `run_movement_coordinator_tick` now receives the tick-stable canonical config explicitly instead of reaching for the process-local `get_tick_ctx()` symbol from outside its lexical scope.
- The same explicit snapshot is reused for RUN no-TP facing, fight-follow hold timing, ordinary facing, and core combat-close movement.
- Removed the movement coordinator's residual flat `fight_follow_hold_s` fallback. Missing canonical fight timing uses the established 8-second default rather than stale flat state.
- `UC_IsCombatParticipant` and `UC_IsMovementParticipant` now classify participation from canonical Profile V2 through `uc_movement_config`, while current engine-running state remains runtime-owned through `Start_Engine`.
- Canonical participation covers autotarget, explicit move, base/named formations, tank, hunter+path-follow, puller, add-control, and spacing (movement participation only). Formation/named-formation runtime itself was already canonical and required no rewrite.
- Added `tests/replay/harness/selftest_phase3_movement_authority.lua` proving contradictory canonical-vs-flat authority for move/manual/static, canonical participant/domain behavior, face policy, explicit coordinator config plumbing, and protection against hidden `get_tick_ctx` fallback.
- The contradictory-state movement test exposed a pre-existing core authority leak in the earlier combat-enable cutover: Lua's `a and canonical_false or flat_value` idiom caused canonical `autotarget=false` / `auto_engage=false` to fall through to conflicting flat `true`. Core movement now uses explicit canonical-vs-compatibility branches, so canonical false is authoritative.
- Automated proof on implementation head `367201f60d99156133bea2726813e6f3ebad7a02`: workflow `37200907676` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 movement authority PASS, formation activation PASS, spacing cast-lock PASS, RUN no-TP PASS, defensive/support movement-lock tests PASS, all earlier Phase 2/3 authority suites PASS, and the flat-surface guard PASS.
- Flat-surface guard burn-down: `UnifiedCombat.lua` literal `UC_SETTINGS` count 79 → 77 by removing the two participant helpers' flat settings dependency.
- Existing legacy DD2/melee engine movement controls remain separately classified compatibility debt and are not claimed as migrated by this unified scheduler/core slice.
- Live-game smoke verification remains required for explicit Move mode, Manual/Static movement suppression, ordinary Face on/off, formation participation, and coordinator mode transitions before Phase 3 live acceptance is complete.


### 2026-10-04 — Phase 3 automated exit audit implemented

- Audited the common scheduler/core durable-authority boundary after all listed Phase 3 domain slices.
- Scheduler proposal revalidation is now canonical/fail-closed: `uc_scheduler_ranker.lua` no longer falls back to `ctx.settings[required_setting]` when a proposal dependency is unmapped.
- Added canonical `sleep` required-setting resolution through `config.sleep.enabled`; production `required_setting` tokens are now enumerated by the exit regression so future unmapped proposal dependencies fail CI.
- Added explicit canonical `config.combat.prime` access and moved combat-commitment fight-leader evaluation to the tick's `ctx.config` / `uc_follow_config` snapshot. Contradictory flat Prime/fight state can no longer influence runtime commitment.
- Migrated the common charm-sleeper and sleep-waker feature gates to `ctx.config.defensive.*` directly. Their focused tests now deliberately oppose canonical and flat values on every collection pass.
- Removed the Phase 2-deferred direct `UC_SETTINGS.log_combat_sched` read from `uc_scheduler_action_state.lua`; core action-state diagnostics now use canonical `config.debug.combat_sched`.
- Added `tests/replay/harness/selftest_phase3_exit_audit.lua` to freeze the common authority contract: every production scheduler `required_setting` must have a canonical mapping, common defensive providers may not receive flat fallback authority, combat commitment must use explicit canonical config, and core's sole direct `UC_SETTINGS` accessor remains the explicit no-config compatibility seam.
- Flat-surface burn-down in this audit: `uc_combat_commitment.lua` `ctx.settings` 3→1; `uc_scheduler_ranker.lua` 3→2; `uc_provider_charm_sleeper.lua` and `uc_provider_sleep_waker.lua` drop their `ctx.settings` / `active_value_or_flat` surfaces entirely; `uc_scheduler_action_state.lua` drops its final direct `UC_SETTINGS` read.
- Expanded exit-audit tracing proved several canonical-first fallbacks were still on the live common path. The unified scheduler now has **zero** `active_value_or_flat(` calls (32→0) and its `ctx.settings` surface falls 11→2; the remaining two are runtime/cross-domain plumbing rather than durable common policy.
- Common defensive Cure/Curaga/Waltz/Na/buff selection, critical-cure classification, Doom-water eligibility, and shared SCH defensive tuning now consume the explicit canonical config snapshot.
- Sleep collection is canonical end-to-end: enablement, ordered spell list, range, effect suppression, and spell selection all consume `ctx.config`; stale flat `sleep` / `sleepspells` state can no longer drive scheduler collection.
- Combat Prime and fight-leader collection now consume canonical `ctx.config` as well as the earlier commitment path. `uc_provider_combat.lua` flat-context markers fall 20→11; survivors are partner/pull/WS/job-runtime seams tracked separately rather than Sleep/Prime/fight durable authority.
- Remaining flat scheduler/provider surfaces are explicitly outside this common Phase 3 authority boundary: RUN/SCH/SMN/PUP job configuration moves to Phase 4, scheduler cadence fields such as `_sched_next_*` are runtime state, diagnostic helpers are non-action authority, and explicit no-config core/legacy callers remain compatibility-only.
- The prior follow/pathing tests continue to prove configured names are durable while resolved party/fight/partner/puller IDs are live-derived; path route/session state remains non-authoritative compatibility schema debt rather than scheduler policy.
- Automated proof on implementation head `a3670fa83a055ad582be0b5ff6bab7821f4a2950`: workflow `37205168055` completed successfully with `lua-sequence` PASS, the Phase 3 automated exit audit PASS, flat-surface guard PASS, all earlier Phase 2/3 authority suites PASS, and `winforms` PASS. Live-game smoke verification remains required before Phase 3 live acceptance is complete.

## Working checklist

When completing any migration slice:

- [ ] inspect current callers and writers;
- [ ] classify durable config vs runtime state;
- [ ] identify exact canonical path(s);
- [ ] add or update tests before removing fallback;
- [ ] migrate the smallest cohesive consumer set;
- [ ] verify changed Lua with Lua 5.1 tooling where available;
- [ ] run targeted tests;
- [ ] update flat-consumer allowlist/guardrail;
- [ ] update this document's phase status and progress log;
- [ ] note live-game verification still required, if applicable;
- [ ] keep rollback straightforward.

## Completion definition

This migration is complete only when Profile V2 is the single durable configuration authority from editor/save through runtime consumption, and flat compatibility state can no longer change durable automation semantics.
`) inside the Lua trim pattern duplicated the file tail during repository editing; the COR module was rebuilt from the last green immutable source and only the intended live name-to-ID range-resolution block was reapplied.

### Phase 6 — Retire the durable flat projection

Status: **NOT STARTED**

Goals:

- remove remaining durable projections from canonical config into `_G.UC_SETTINGS`;
- shrink `uc_new_settings_defaults()` to true runtime/compatibility needs or replace it with better-scoped state owners;
- remove mixed-shape normalization for normal runtime paths;
- retain compatibility wrappers only where an external/public contract still requires them;
- make any surviving `UC_SETTINGS` usage explicitly non-authoritative.

Exit criteria:

- [ ] no durable runtime behavior depends on `_G.UC_SETTINGS`;
- [ ] no durable UI write mutates `_G.UC_SETTINGS` as source of truth;
- [ ] canonical config is the only durable authority;
- [ ] mixed flat/nested normalizer ambiguity is removed from normal runtime;
- [ ] compatibility surfaces are documented and intentionally bounded.

### Phase 7 — Final cleanup and conformance

Status: **NOT STARTED**

Goals:

- remove dead compatibility adapters;
- remove obsolete flat field projections and tests that only preserve retired behavior;
- update architecture docs and README;
- run full Lua and WinForms test suites;
- perform targeted live-game acceptance across representative jobs and domains.

Required live acceptance should include at least:

- BRD maintenance;
- COR maintenance;
- GEO maintenance;
- defensive healing/buffs;
- recurring combat spells;
- tank/RUN behavior;
- WS/skillchain behavior;
- pulling;
- follow/pathing;
- SMN;
- PUP;
- SCH;
- activity profile apply;
- profile Save/reload;
- job/subjob identity transition.

Exit criteria:

- [ ] source-contract audit shows no unintended flat durable reads/writes;
- [ ] automated suites green;
- [ ] targeted live acceptance completed;
- [ ] architecture docs describe the final ownership model accurately.

## Regression scenarios that must survive the migration

These are architecture acceptance cases, not merely unit tests.

### Food and Bard sibling isolation

Given:

```lua
config.maintenance = {
    brd = {
        enabled = true,
        songs = { 'Honor March', 'Victory March' },
    },
    food = {
        enabled = true,
        item = 'Grape Daifuku',
    },
}
```

Changing `maintenance.food` must never alter, disable, default, or reinterpret `maintenance.brd`.

### Canonical false values remain authoritative

A canonical explicit `false` must not fall through to a legacy flat `true`.

### Missing canonical subtree behavior is explicit

A missing optional subtree must use canonical defaults, not resurrect stale flat compatibility values.

### Runtime state cannot become durable

Engine state, current IDs, live locks, target state, and similar transient values must never be serialized merely because they previously lived in `UC_SETTINGS`.

### UI/runtime round trip

Canonical Profile V2 -> runtime active config -> editor -> save must preserve durable semantics without requiring flat compatibility state to fill missing fields.

## Progress log

### 2026-10-02 — Migration branch created

- Created `refactor/profile-v2-single-source` from current `master`.
- Confirmed Profile V2 is already the intended durable source.
- Confirmed `_G.UC_ACTIVE_PROFILE.config` is already the intended canonical applied config.
- Identified `_G.UC_SETTINGS` as the major compatibility surface still feeding runtime consumers.
- Identified major flat producers in addon startup, active-config projection, bridge live writes, and WinForms editor/write adapters.
- Identified initial consumer families for Phase 0 inventory.
- No gameplay behavior changed.

### 2026-10-02 — Rabao BRD investigation clarified

- Confirmed BRD song maintenance is intentionally blocked in configured city zones, including Rabao.
- Confirmed the observed "BRD never sings" case in Rabao was expected city-zone behavior, not evidence of a current BRD config regression.
- The configuration migration remains necessary because the mixed flat/nested model is still structural technical debt.

### 2026-10-02 — Phase 0 inventory and guardrails completed

- Added `docs/profile_v2_flat_surface_inventory.md` as the detailed producer/consumer and field-ownership baseline.
- Added a repository-wide source guardrail that freezes direct `UC_SETTINGS`, indirect `ctx.settings`, `active_value_or_flat`, canonical-to-flat projection, bridge flat mutation, and WinForms flat write/translation seams.
- Added a machine-readable allowlist with exact current source occurrence counts. Future migration slices should shrink it; new flat seams fail the guardrail unless explicitly reviewed.
- Classified durable field families, runtime/transient state, compatibility-only aliases, and explicit ambiguous ownership decisions.
- Added the mixed nested-food + flat-BRD maintenance characterization fixture. It records the current known normalizer defect without changing runtime behavior.
- Phase 0 made documentation/test-only changes; no scheduler/provider/gameplay behavior changed.

### 2026-10-02 — Phase 1 canonical runtime read boundary completed

- Added `uc_scheduler_context_utils.get_config()` as the scheduler-owned canonical accessor over the applied `_G.UC_ACTIVE_PROFILE.config`.
- Scheduler tick contexts now expose `ctx.config` alongside the unchanged compatibility `ctx.settings` surface.
- Canonical config is sampled once when the tick context is built and passed by identity; providers do not reparse Profile V2 files.
- The context builder remains dependency-injected and does not directly require `uc_active_config`.
- Added deterministic fixture/static coverage for active-config lookup, missing-config fallback, one-sample-per-context behavior, and scheduler wiring.
- No proposal provider, ranking rule, dispatch path, or durable config consumer changed in this phase; the Phase 0 flat allowlist is intentionally unchanged.
- PR verification now runs the flat-surface guard, mixed-shape characterization, scheduler canonical-context tests, and context-utils fixtures on every migration PR update.
- Draft PR #73 is the long-lived migration/CI surface. Verification run 36981070413 passed both `lua-sequence` and `winforms` after the guardrail baseline and fixture-count expectations were corrected.
- The new guardrail immediately found three pre-existing `UnifiedCombat.lua` flat-sync call sites that the initial mechanical audit had missed; they are now explicitly baselined rather than silently ignored.

### 2026-10-02 — Mainline legacy-food compatibility hotfix incorporated

- Mainline PR #74 fixed Activity/Profile V2 apply failures for profiles created before `maintenance.food` existed.
- Legacy Profile V2 maintenance domains now materialize `food = { enabled = false, item = '' }` before canonical-to-flat compatibility projection, preventing stale live food settings from leaking into conversion validation.
- The focused regression reproduces the Etamame SAM/DRG Activity Apply failure shape and asserts the exact structured conversion path returns zero mismatch.
- The hotfix was merged to `master` as `c8a084b9a29dd412e99fa3cf5dec4e0e90cf1b3f` and has been incorporated into this migration branch before Phase 2.

### 2026-10-02 — Phase 2 low-risk leaf migration implemented

- Food maintenance and recurring combat spells now consume only the canonical scheduler snapshot at `ctx.config`; stale `ctx.settings` values are deliberately ignored.
- Defensive provider gates/resurrection, enemy-buff removal, and enemy-debuff maintenance now consume `ctx.config.defensive.*` directly.
- Raise acceptance and weakened recovery-hold now read only `uc_active_config`; their direct `UC_SETTINGS` fallback paths were removed.
- GEO camp placement now reads only `config.maintenance.geo` from active Profile V2 state.
- Defensive buff maintenance now receives canonical config explicitly from the scheduler, including structured targeted buffs and BRD ownership state; its hidden active-config/global fallback was removed.
- COR maintenance now receives canonical config explicitly from the maintenance provider. Roll policy, range requirements, Light Shot-on-Dia policy, and ability-derived roll fallback stay inside canonical `config.maintenance.cor` / `config.abilities.configured`.
- The Phase 0 allowlist shrank by 11 source-file entries / 60 literal flat-surface hits. The remaining `uc_scheduler_action_state.lua` debug-only `UC_SETTINGS` reader is intentionally deferred with the core scheduler work in Phase 3 rather than widening this leaf migration.
- Deterministic tests include intentionally conflicting stale flat values so a migrated leaf fails if flat compatibility regains authority.
- Full PR CI passed at Phase 2 verification head `a396671884229447f10ea85d5399e69a58003275` (workflow run `36992724235`): both Lua and WinForms jobs succeeded, including the flat-surface guard and the dedicated Phase 2 canonical-leaf suite.
- Added `tests/replay/harness/selftest_phase2_canonical_authority.lua`: a dedicated 21-case contradictory-state matrix whose only purpose is to prove canonical Profile V2 values beat deliberately opposite flat compatibility values across every Phase 2 consumer family.
- The matrix covers food, recurring spells, defensive provider/critical threshold, resurrection, enemy buff removal, enemy debuff maintenance, COR routing, defensive buff maintenance, COR roll selection, GEO placement, Raise acceptance, and weakened recovery hold. Both enable/disable directions are exercised where a boolean gate exists.
- Workflow run `37016053323` passed both `lua-sequence` and `winforms`; the canonical-authority matrix reported `21/21 PASS`.
- Live-game smoke verification remains before merge, especially food, recurring spells, defensive maintenance, COR upkeep, raise acceptance, recovery hold, and GEO camp placement.
- Phase 2 implementation began with `0f707e1863846dcc74d0dd56cb791cbbf8bbb0ed`; the verified Phase 2 head is `a396671884229447f10ea85d5399e69a58003275`.

### 2026-10-02 — Phase 3 combat enablement/autotarget slice implemented

- Began Phase 3 with the smallest core domain: combat enablement/target acquisition gates, specifically canonical `config.combat.autotarget` and `config.combat.auto_engage`.
- Added canonical-only scheduler helpers for autotarget and auto-engage while retaining compatibility helpers for unmigrated non-scheduler callers.
- Migrated scheduler-owned target acquisition and engage gates to `ctx.config`; contradictory flat `ctx.settings.autotarget` / `auto_engage` values can no longer change those provider decisions.
- Passed canonical tick config through core target selection, tank-enmity selection, death-switch revalidation, partner arbitration, and pre-engage combat-close movement so hidden flat autotarget fallbacks do not survive behind provider boundaries.
- Added `tests/replay/harness/selftest_phase3_combat_enablement_authority.lua` with contradictory canonical-vs-flat cases for autotarget and auto-engage plus static wiring assertions.
- Added the new Phase 3 proof to PR CI and the aggregate replay suite.
- Reduced the flat-surface guard by four `ctx.settings` hits: two from `uc_provider_target_control.lua` and two from `uc_provider_combat.lua`.
- Existing combat-extension provider coverage now supplies canonical combat config explicitly; legacy helper fallback tests remain intact for callers that have not migrated yet.
- No weaponskill, ability, pulling, target-priority, tank-policy, ranking, or dispatch semantics are intentionally changed by this slice.
- During contradictory-state proof, the first canonical auto-engage implementation exposed a Lua false-value bug: `condition and value or nil` collapsed explicit canonical `false` to `nil`, incorrectly restoring the default `true`. The canonical accessor was corrected to preserve explicit false, and the regression now proves both directions.
- Automated proof on branch head `cf827cd87f0eafe8b9917743d97ed7a2015944b2`: workflow `37023674659` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 2 canonical-authority coverage PASS, the new Phase 3 combat enablement canonical-authority test PASS, and the flat-surface guard PASS.
- Live-game smoke verification remains required before the Phase 3 core migration is considered complete.

### 2026-10-02 — Phase 3 weaponskill configuration slice implemented

- Migrated the full scheduler-owned weaponskill decision path to canonical Profile V2 authority.
- Canonical WS policy now covers `config.combat.weaponskill.enabled`, primary WS, mode, minimum TP, AoE permission, Fast Skillchain, no-skillchain target names, skillchain target preference, ally-wait ignore names, aftermath enablement, and aftermath WS.
- Included canonical `config.combat.spam` and `config.legacy.solo` in the WS view because both directly alter weaponskill arbitration/bypass behavior.
- Deliberately left `ability_active` as a compatibility input for Chivalry reservation; that belongs to the next Phase 3 abilities slice.
- Proposal collection now gates WS enablement from `ctx.config`; the core planner receives canonical config and overlays all WS-owned durable fields before selecting an action.
- Canonical config is carried through rank-commit Smart-AoE/skillchain revalidation and final WS intent dispatch, preventing a canonical proposal from being revalidated against stale flat WS policy.
- Added `tests/replay/harness/selftest_phase3_weaponskill_authority.lua` to prove canonical WS enablement beats opposite flat state and to statically require every WS-owned field at the canonical boundary.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory-state cases proving canonical primary WS, minimum TP, AoE policy in both directions, Smart vs primary-only mode, aftermath policy, and Fast Skillchain false/true behavior.
- Added the weaponskill authority suite to normal PR CI and the aggregate replay suite.
- Reduced `uc_provider_combat.lua` flat-context guard count from 26 to 25 by removing the flat `weaponskill_active` provider gate. The remaining `ctx.settings` handoff exists for explicitly unmigrated non-WS inputs such as Chivalry's ability gate.
- Automated proof on branch head `7191d7a550dcb467e3e1166f787c2f3ba719dde4`: workflow `37027431136` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill canonical-authority PASS, WS maintenance/skillchain precedence PASS, and the flat-surface guard PASS.
- No intentional weaponskill ranking, timing, TP threshold semantics, skillchain planning semantics, or dispatch behavior changed except that canonical Profile V2 now wins when flat compatibility state conflicts.
- Live-game smoke verification remains required for representative Smart WS, spam/solo, primary-no-SC, aftermath, and Fast Skillchain configurations before Phase 3 is complete.

### 2026-10-02 — Phase 3 abilities slice implemented

- Migrated scheduler-owned generic configured-JA authority to canonical `config.abilities`: enablement, allow-unengaged policy, configured ability ordering, and legacy-slot fallback.
- Added `uc_ability_pipeline.collect_ordered_from_config`; scheduler generic JA collection now chooses the ability list from Profile V2 before applying unrelated RUN ownership filtering.
- Migrated the shared allow-unengaged policy in `uc_provider_tank_enmity.lua` to canonical `config.abilities.allow_unengaged`.
- Closed the deferred Chivalry dependency from the WS slice: the scheduler WS settings view now overlays canonical ability enablement, configured abilities, and legacy slots before Chivalry TP-reservation logic runs.
- Discovered a hidden post-proposal authority leak in `uc_scheduler_ranker.lua`: proposals carrying `required_setting` were rechecked directly against `ctx.settings`. This could silently override canonical `autotarget`, `weaponskill_active`, and `ability_active` decisions after a proposal had already been built.
- Added `uc_scheduler_config.required_setting_value_from_config` and migrated ranker validation so those three already-migrated settings revalidate against canonical config; unknown/unmigrated required settings such as Sleep intentionally retain the flat fallback.
- Added `tests/replay/harness/selftest_phase3_abilities_authority.lua` covering canonical ability enable/disable, configured-list precedence, legacy-slot fallback, unengaged policy, required-setting resolution, and static scheduler/core/ranker wiring.
- Strengthened `selftest_unengaged_abilities.lua` so generic and tank lanes both test canonical OFF + flat ON and canonical ON + flat OFF.
- Extended `selftest_ws_maintenance_precedence.lua` with real-core contradictory Chivalry cases: canonical enabled/list beats flat disabled/empty, canonical disable beats flat enabled, canonical configured list beats flat Chivalry, and canonical legacy-slot fallback still reserves TP.
- Extended `selftest_scheduler_ranker.lua` with contradictory canonical required-setting cases.
- Reduced the flat-surface guard by four more hits: `uc_provider_combat.lua` from 25 to 22 `ctx.settings` reads and `uc_provider_tank_enmity.lua` from 3 to 2.
- `config.abilities.wsabilities` is not consumed by the scheduler configured-JA path; it remains projected for legacy-engine compatibility and is not being misrepresented as part of this scheduler-domain cutover.
- Automated proof on implementation head `eda088b075eee3084d23728fa7d529ac4435314c`: workflow `37045140212` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, contradictory unengaged tests PASS, ranker authority PASS, Chivalry/WS precedence PASS, and the flat-surface guard PASS.
- No intentional JA priority, readiness, targeting, range, or dispatch semantics changed; the behavioral change is authority only—canonical Profile V2 wins over conflicting flat compatibility state.
- Live-game smoke verification remains required for configured self/enemy JAs, unengaged override behavior, tank-enmity unengaged actions, and Chivalry TP reservation before Phase 3 is complete.

### 2026-10-02 — Phase 3 target-control and ignore/priority slice implemented

- Migrated scheduler-owned targeting authority for `config.targeting.add_control`, the ordered target/add priority list, and `config.targeting.target_ignore_names`.
- Added canonical targeting accessors in `uc_scheduler_config.lua`.
- The scheduler priority rule is now explicit: `config.targeting.targets` is authoritative when non-empty; normalized `config.targeting.add_priority_names` remains only the compatibility fallback.
- `unified_combat_core.lua` overlays canonical Add Control, priority names, and target-ignore names into the scheduler settings view before target selection, tank target selection, death-switch revalidation, and Add Control evaluation.
- `uc_provider_target_control.lua` now passes `ctx.config` into Add Control enablement as well as target selection.
- `uc_provider_combat.lua` fight-leader engage arbitration now consults the same canonical Add Control gate, preventing engage and target-control lanes from disagreeing when flat compatibility state conflicts.
- Added `tests/replay/harness/selftest_phase3_targeting_authority.lua` proving canonical Add Control ON + flat OFF permits engaged retarget, canonical OFF + flat ON blocks it, canonical target ordering wins over conflicting flat priority order, and canonical target-ignore names win over conflicting flat ignore state.
- Updated the existing Add Control priority contract test for the canonical-context helper signatures.
- Added the targeting authority suite to normal PR CI and the aggregate replay suite.
- Flat-surface counts intentionally do not drop in this slice: Add Control still receives `ctx.settings` because fight-leader enablement is a separate follow/fight-leader domain that has not migrated yet. Target-owned fields within that mixed view are canonical.
- `config.targeting.targetability` and `config.targeting.ignore` are not scheduler target-selection inputs today; they remain legacy-engine/UI compatibility fields and are not being falsely claimed as migrated scheduler consumers.
- Automated proof on implementation head `51a8d1ddc62ef75b0c771ba0aefb7c241cd8e629`: workflow `37085163385` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 combat-enable authority PASS, Phase 3 weaponskill authority PASS, Phase 3 abilities authority PASS, Phase 3 targeting authority PASS, Add Control priority eligibility PASS, and the flat-surface guard PASS.
- No intentional target ranking, claim policy, death-switch, Add Control eligibility, or engage-dispatch semantics changed except canonical Profile V2 now wins when targeting compatibility state conflicts.
- Live-game smoke verification remains required for Add Control retargeting, ordered add selection, target-ignore behavior, and fight-leader handoff before Phase 3 is complete.

### 2026-10-02 — Phase 3 tank/enmity configuration slice implemented

- Migrated common scheduler-owned tank authority to canonical Profile V2: `config.tank.enabled`, ordered `config.tank.enmity.actions`, and `config.tank.enmity.include_pets`.
- Added canonical tank/enmity accessors and an exact configured-action matcher in `uc_scheduler_config.lua`.
- `unified_combat_core.lua` now overlays canonical tank enablement and enmity actions into the scheduler settings view before tank violation selection.
- Combat engage weighting, generic-JA tank weighting, and target-acquire tank weighting now read `tank.enabled` from `ctx.config`.
- `uc_provider_tank_enmity.lua` now fails closed when canonical tank mode is disabled, uses canonical include-pets and enmity actions, and overlays canonical target-ignore names into pet-enmity violation selection.
- Fixed a real pre-existing authority/safety gap: the pet-enmity branch did not independently gate on tank enabled, so a pet recovery proposal could bypass the normal player-enmity path's tank gate. The provider now applies the canonical tank gate before either path.
- Tank-enmity and RUN-tank proposals now carry `required_setting = 'tank'`; the scheduler ranker resolves that dependency from canonical config.
- Final tank-enmity dispatch revalidates both canonical tank enablement and whether the selected recovery action is still present in the canonical enmity list, preventing a stale proposal from dispatching after a profile change.
- The shared top-level tank gate in `uc_provider_run_tank.lua` now reads canonical config. RUN-specific rune/ward/Foil policy under `config.tank.run` remains a separate subsystem and was not otherwise migrated in this slice.
- Fixed a cross-domain leak from the completed abilities slice: RUN tank's unengaged gate now uses canonical `config.abilities.allow_unengaged`.
- Fixed a movement/dispatch authority leak: RUN no-TP facing now receives canonical tank config in both the movement coordinator and combat dispatcher, so stale flat `tank=true` cannot keep no-TP facing active after canonical tank disable.
- Added `tests/replay/harness/selftest_phase3_tank_enmity_authority.lua` proving canonical tank ON + flat OFF, canonical tank OFF + flat ON, canonical action-list precedence, include-pets precedence, canonical pet target-ignore projection, ranker tank resolution, and dispatch-time canonical revalidation wiring.
- Strengthened the existing pet-enmity, RUN tank, RUN no-TP, tank priority/starvation, provider-shape, and migration-contract fixtures for the new canonical boundary.
- Reduced flat-context guard counts: `uc_provider_combat.lua` 22→20, `uc_provider_target_control.lua` 4→3, and `uc_provider_run_tank.lua` 3→1. `uc_provider_tank_enmity.lua` remains at 2 because it still passes compatibility context into separately owned target/friendly-selection helpers while all tank-owned fields are canonical.
- Automated proof on implementation head `447767bf7a8370e1e16b8949bd611a23f348ea7a`: workflow `37086243234` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 tank-enmity authority PASS, pet-enmity provider/config PASS, RUN tank PASS, RUN no-TP PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional tank priority bands, victim ranking, action readiness, range, dispatch method, RUN rune/ward policy, or engage semantics changed except canonical Profile V2 now wins over conflicting flat tank/enmity state and stale tank proposals fail closed.
- Live-game smoke verification remains required for PLD/RUN tank target acquisition, player and pet enmity recovery, canonical tank disable, configured recovery-action changes, and RUN no-TP facing before Phase 3 is complete.

### 2026-10-02 — Phase 3 pulling slice implemented

- Migrated the modern camp-puller domain, `config.combat.pulling`, to canonical Profile V2 authority across lane acquisition, proposal collection, candidate revalidation, movement ownership, action-result handling, and final dispatch revalidation.
- Added `uc_scheduler_config.combat_pulling_from_config` as the canonical accessor.
- `uc_camp_puller.lua` now reads `ctx.config.combat.pulling` directly and has zero `ctx.settings` reads.
- Camp-puller candidate ignore checks now receive canonical `ctx.config` and reuse canonical `config.targeting.target_ignore_names`; stale flat ignore state can no longer alter pull candidate selection.
- `unified_scheduler.lua` now resolves camp-pulling configuration from `uc_scheduler_context_utils.get_config()` for movement reservation and asynchronous action-result paths, and final camp-puller dispatch revalidates against the fresh canonical tick config.
- Party-follow and route/path movement ownership checks now read `config.combat.pulling` from `uc_active_config`, so stale flat `camp_pulling.enabled` cannot make movement consumers disagree with the scheduler. Missing canonical pull config fails closed as disabled rather than falling back to flat state.
- Strengthened `selftest_camp_puller.lua` so its full state-machine run uses canonical pulling enabled while the flat compatibility mirror is disabled.
- Added `tests/replay/harness/selftest_phase3_pulling_authority.lua` covering canonical ON + flat OFF lane acquisition, canonical OFF + flat ON fail-closed behavior, canonical target-ignore authority, and static scheduler/follow/pathing wiring.
- Strengthened `selftest_movement_priority_arbitration.lua` with both contradictory directions for cross-domain movement ownership: canonical pull ON + flat OFF suppresses follow, while canonical pull OFF + flat ON does not.
- Added the pulling authority suite to normal PR CI and the aggregate replay suite.
- Reduced the flat-surface guard further: `uc_camp_puller.lua` from 4 to 0 `ctx.settings` hits and `unified_scheduler.lua` from 12 to 11.
- Final branch audit found no remaining runtime reads of the flat `camp_pulling` mirror in `uc_camp_puller.lua`, `unified_scheduler.lua`, `uc_party_follow.lua`, or `uc_pathing.lua`; remaining appearances are compatibility projection/default surfaces and canonical helper names.
- The older hunter/path pull action (`path_pull_action_type`, `path_pull_action_name`, hunter/path-follow gates) belongs to `config.movement.path` and is intentionally deferred to the later pathing slice rather than being mixed into this pulling cutover.
- Automated proof on implementation head `a9967ee43f09d27f382df13867dd15cb441bcc40`: workflow `37086936986` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 pulling authority PASS, full camp-puller state machine PASS, camp-puller policy PASS, movement-priority arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional pull candidate ranking, quota policy, leash geometry, action readiness/range, retry policy, lane priority, or dispatch semantics changed except that canonical Profile V2 now wins over conflicting flat camp-pulling state.
- Live-game smoke verification remains required for camp lane acquisition, pull action execution, canonical disable during an active journey, target-ignore filtering, return-to-camp behavior, and movement handoff before Phase 3 is complete.

### 2026-10-03 — Phase 3 spacing slice implemented

- Migrated the unified scheduler/core spacing domain to canonical `config.movement.spacing` authority.
- Added `uc_scheduler_config.movement_spacing_from_config` as the canonical spacing accessor.
- `unified_combat_core.lua` now resolves one spacing view per movement tick from the canonical config passed by `unified_scheduler.lua`.
- Canonical authority covers the complete spacing subtree: `enabled`, `band_min`, `band_max`, `model_size_floor`, `use_prediction`, `lookahead_s`, `repel_hold_ticks`, `overlap_deadband`, `repel_weight`, and `band_deadband`.
- The migration intentionally includes `band_min`, `band_max`, and `model_size_floor` even when spacing is disabled because those values also define ordinary combat-close stop distance and model-size compensation.
- When canonical config is present but `movement.spacing` is absent, combat movement uses the normalized spacing defaults rather than falling back to conflicting flat spacing state.
- Direct no-config compatibility callers retain the old flat spacing projection through one centralized `movement_spacing_config(settings, config)` fallback. A regression asserts every legacy `settings.spacing*` token in core appears exactly once, inside that compatibility projection.
- Added `tests/replay/harness/selftest_phase3_spacing_authority.lua` proving canonical spacing ON + flat OFF executes the spacing solver, canonical spacing OFF + flat ON does not execute flat spacing behavior, canonical `band_max` wins while spacing is disabled, and canonical `model_size_floor` changes combat-close stopping distance despite conflicting flat values.
- The regression also proves the scheduler continues passing the tick-stable canonical config into `core.apply_movement_for_scheduler`.
- Updated the movement-facade and spacing cast-lock contract fixtures to the current canonical-config call/dispatcher signatures while preserving their original movement ownership and cast-freeze ordering assertions.
- No flat-surface guard count drops in this slice because the compatibility-only flat spacing projection remains intentionally present for direct legacy callers; the new spacing regression mechanically prevents those flat reads from spreading elsewhere in unified core movement.
- Source audit found no additional unified scheduler/core consumers of the spacing tuning fields outside `unified_combat_core.lua`.
- `melee_engine.lua`, `dd2_module.lua`, and the generated/legacy DD2 engine retain flat spacing reads. They are already classified in the migration ledger as legacy-sensitive engines and explicitly short-circuit when the unified engine owns execution; they are not being falsely claimed as migrated by this Phase 3 scheduler/core slice.
- Automated proof on implementation head `460db4c695e93be08a14a664e3c30e1e78d6f5a6`: workflow `37121903528` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 spacing authority PASS, scheduler movement facade PASS, spacing cast-lock PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional spacing geometry, prediction, repel weighting, deadband, cast-freeze, movement ownership, or combat-close semantics changed except canonical Profile V2 now wins over conflicting flat spacing state on the unified scheduler path.
- Live-game smoke verification remains required for spacing enable/disable, close/retreat band behavior, party overlap repulsion, moving-target prediction, and spacing interaction with cast freezes before Phase 3 is complete.

### 2026-10-03 — Phase 3 follow slice implemented

- Migrated the unified follow domain to canonical Profile V2 authority across party follow, fight-follow timing/leader selection, partner coordination, puller leash policy, and path-vs-follow movement ownership.
- Added `uc_follow_config.lua` as the canonical follow runtime adapter for `config.follow.party`, `config.follow.fight`, `config.follow.partner`, and `config.follow.nyzul`.
- Durable names remain the source of truth; party/fight/partner/puller IDs are resolved from the live party at runtime. Legacy configured IDs are used only when the corresponding canonical durable name is absent, and camp leash mode intentionally resolves no player puller ID.
- `uc_party_follow.lua` no longer contains any `active_value_or_flat` follow readers. Party enablement, leader identity/name, follow min/max, and fight-follow minimum now read canonical follow config directly.
- `config.follow.enabled` is part of the party-follow gate. Partial canonical profiles that omit the parent flag preserve the normalizer's default of enabled=true rather than accidentally disabling follow.
- Follow participation now honors both canonical `config.ownership.domain_follow_enabled` and canonical `config.follow.enabled` / `config.follow.party.enabled`.
- `uc_pathing.lua` now uses canonical follow policy when deciding whether party follow owns movement, while its own `config.movement.path` settings remain deferred to the next pathing slice.
- `uc_runtime_overrides.lua` fight-leader accessors are now canonical-first. Conflicting flat `fight_leader`, `fight_leader_name`, and `fight_leader_id` state can no longer override Profile V2.
- `unified_combat_core.lua` overlays canonical follow partner policy into its scheduler runtime view, so partner target ownership, fight-leader targeting, and puller/camp leash movement consume canonical `config.follow.partner` values.
- `unified_scheduler.lua` partner tiebreak arbitration now uses canonical partner enablement/IDs and canonical target-ignore policy; fight-follow hold duration now comes from canonical `config.follow.fight.hold_s`.
- Combat-provider partner target-set calls now pass `ctx.config`, so WS/sleep/ability partner exclusions use canonical partner state.
- Nyzul follow policy was already canonical: `uc_nyzul_runtime.lua` reads `config.follow.nyzul.*` directly, so no runtime churn was required there.
- Added `tests/replay/harness/selftest_phase3_follow_authority.lua` proving live canonical name→ID resolution, canonical party/fight/partner/puller projection over contradictory flat state, canonical fight-leader ON/OFF precedence, and camp-leash runtime-ID behavior.
- Strengthened `selftest_movement_priority_arbitration.lua` so canonical party-follow behavior is proven both against conflicting flat state and with missing canonical follow policy failing closed instead of falling back to flat.
- Updated runtime-overrides, active-config-consumer, configurable-control-range, and partner-arbitration contracts for the new authority boundary.
- Flat-surface guard burn-down: `uc_party_follow.lua` `active_value_or_flat` count 7→0; `uc_pathing.lua` 9→7 by removing its two follow-related fallback readers.
- Legacy-sensitive `melee_engine.lua` / `dd2_module.lua` retain their own flat follow/partner settings and remain separately classified compatibility debt outside the unified scheduler follow slice.
- Automated proof on implementation head `272149baa442a03b65b0e1757fadf2a73a926281`: workflow `37143116074` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 follow authority PASS, movement-priority arbitration PASS, runtime-overrides PASS, partner-arbitration PASS, all earlier Phase 3 authority suites PASS, and the flat-surface guard PASS.
- No intentional party-follow geometry, zone replay, combat transition suppression, partner arbitration ranking, puller leash geometry, or fight-follow timing semantics changed except canonical Profile V2 now wins over conflicting flat follow state.
- Live-game smoke verification remains required for same-zone party follow, zone replay, fight-follow distance changes, partner target coordination, player/camp puller leash modes, and follow/path movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 pathing slice implemented

- Migrated unified route-follow and path-hunter policy to canonical Profile V2 authority.
- Added `uc_path_config.lua` as the canonical runtime adapter for durable `config.movement.path` policy plus the existing canonical `config.legacy.hunter` gate.
- `uc_pathing.lua` now reads recording enablement, path-follow enablement, party gate distance, and resume-index window only from canonical path policy. Its `active_value_or_flat` count is 7 → 0.
- Route identity/progress is explicitly runtime-owned: selected path filename, classified route type, distance-to-start, and recorded point list stay on live/session state and are not projected from Profile V2 over the runtime.
- Profile V2 durable comparison ignores those four route/session fields, and canonical-to-flat apply preserves the live values already present in the runtime settings table. Existing Profile V2 files may still carry route-state compatibility fields; this slice does not rewrite the file schema.
- The existing Profile V2/WinForms route-state fields remain compatibility schema debt for now. Runtime authority is removed without changing their serialized compatibility shape in this slice.
- Unified target selection overlays canonical path/hunter policy before evaluating hunter enablement, target names, vertical tolerance, and target range.
- Scheduler pull selection overlays canonical path/hunter policy for hunter enablement, path-follow gate, target list, pull action type/name, and attack fallback. Both target-control and combat providers pass `ctx.config` into pull selection.
- Missing canonical path policy uses canonical defaults/fails closed rather than reviving contradictory flat path-follow or hunter state.
- Added `tests/replay/harness/selftest_phase3_pathing_authority.lua` covering canonical-vs-flat route/hunter/pull policy, canonical OFF precedence, default fail-closed behavior, and preservation of live route/session state.
- Strengthened movement arbitration and added a focused Profile V2 durable-diff regression so stale flat path-follow state and route-session placeholders cannot regain authority.
- Flat-surface guard burn-down: `uc_pathing.lua` `active_value_or_flat` count 7 → 0.
- No intentional route geometry, pause/resume arbitration, hunter candidate ranking, pull readiness/range, or movement-dispatch semantics changed except that canonical Profile V2 now wins for durable path policy.
- Live-game smoke verification remains required for path recording start/stop, route-file rebinding, route follow, hunter target filtering, configured pull action/fallback, and follow/path/camp-pull movement handoff before Phase 3 is complete.


### 2026-10-04 — Phase 3 movement-owned durable settings slice implemented

- Added `uc_movement_config.lua` as the canonical adapter for movement-owned durable policy.
- The remaining scheduler movement controls now come from canonical Profile V2: `config.movement.move`, `config.combat.manual`, `config.combat.static`, and `config.combat.face`.
- `unified_combat_core.lua` uses one canonical movement-control view when a scheduler config snapshot is supplied. Flat `move`/`manual`/`static` reads remain only as an explicit compatibility path for callers that omit canonical config entirely.
- Scheduler ordinary facing now receives canonical config explicitly and uses canonical `config.combat.face`; forced turn-away behavior remains force-owned and is unchanged.
- `run_movement_coordinator_tick` now receives the tick-stable canonical config explicitly instead of reaching for the process-local `get_tick_ctx()` symbol from outside its lexical scope.
- The same explicit snapshot is reused for RUN no-TP facing, fight-follow hold timing, ordinary facing, and core combat-close movement.
- Removed the movement coordinator's residual flat `fight_follow_hold_s` fallback. Missing canonical fight timing uses the established 8-second default rather than stale flat state.
- `UC_IsCombatParticipant` and `UC_IsMovementParticipant` now classify participation from canonical Profile V2 through `uc_movement_config`, while current engine-running state remains runtime-owned through `Start_Engine`.
- Canonical participation covers autotarget, explicit move, base/named formations, tank, hunter+path-follow, puller, add-control, and spacing (movement participation only). Formation/named-formation runtime itself was already canonical and required no rewrite.
- Added `tests/replay/harness/selftest_phase3_movement_authority.lua` proving contradictory canonical-vs-flat authority for move/manual/static, canonical participant/domain behavior, face policy, explicit coordinator config plumbing, and protection against hidden `get_tick_ctx` fallback.
- The contradictory-state movement test exposed a pre-existing core authority leak in the earlier combat-enable cutover: Lua's `a and canonical_false or flat_value` idiom caused canonical `autotarget=false` / `auto_engage=false` to fall through to conflicting flat `true`. Core movement now uses explicit canonical-vs-compatibility branches, so canonical false is authoritative.
- Automated proof on implementation head `367201f60d99156133bea2726813e6f3ebad7a02`: workflow `37200907676` completed successfully with `lua-sequence` PASS, `winforms` PASS, Phase 3 movement authority PASS, formation activation PASS, spacing cast-lock PASS, RUN no-TP PASS, defensive/support movement-lock tests PASS, all earlier Phase 2/3 authority suites PASS, and the flat-surface guard PASS.
- Flat-surface guard burn-down: `UnifiedCombat.lua` literal `UC_SETTINGS` count 79 → 77 by removing the two participant helpers' flat settings dependency.
- Existing legacy DD2/melee engine movement controls remain separately classified compatibility debt and are not claimed as migrated by this unified scheduler/core slice.
- Live-game smoke verification remains required for explicit Move mode, Manual/Static movement suppression, ordinary Face on/off, formation participation, and coordinator mode transitions before Phase 3 live acceptance is complete.


### 2026-10-04 — Phase 3 automated exit audit implemented

- Audited the common scheduler/core durable-authority boundary after all listed Phase 3 domain slices.
- Scheduler proposal revalidation is now canonical/fail-closed: `uc_scheduler_ranker.lua` no longer falls back to `ctx.settings[required_setting]` when a proposal dependency is unmapped.
- Added canonical `sleep` required-setting resolution through `config.sleep.enabled`; production `required_setting` tokens are now enumerated by the exit regression so future unmapped proposal dependencies fail CI.
- Added explicit canonical `config.combat.prime` access and moved combat-commitment fight-leader evaluation to the tick's `ctx.config` / `uc_follow_config` snapshot. Contradictory flat Prime/fight state can no longer influence runtime commitment.
- Migrated the common charm-sleeper and sleep-waker feature gates to `ctx.config.defensive.*` directly. Their focused tests now deliberately oppose canonical and flat values on every collection pass.
- Removed the Phase 2-deferred direct `UC_SETTINGS.log_combat_sched` read from `uc_scheduler_action_state.lua`; core action-state diagnostics now use canonical `config.debug.combat_sched`.
- Added `tests/replay/harness/selftest_phase3_exit_audit.lua` to freeze the common authority contract: every production scheduler `required_setting` must have a canonical mapping, common defensive providers may not receive flat fallback authority, combat commitment must use explicit canonical config, and core's sole direct `UC_SETTINGS` accessor remains the explicit no-config compatibility seam.
- Flat-surface burn-down in this audit: `uc_combat_commitment.lua` `ctx.settings` 3→1; `uc_scheduler_ranker.lua` 3→2; `uc_provider_charm_sleeper.lua` and `uc_provider_sleep_waker.lua` drop their `ctx.settings` / `active_value_or_flat` surfaces entirely; `uc_scheduler_action_state.lua` drops its final direct `UC_SETTINGS` read.
- Expanded exit-audit tracing proved several canonical-first fallbacks were still on the live common path. The unified scheduler now has **zero** `active_value_or_flat(` calls (32→0) and its `ctx.settings` surface falls 11→2; the remaining two are runtime/cross-domain plumbing rather than durable common policy.
- Common defensive Cure/Curaga/Waltz/Na/buff selection, critical-cure classification, Doom-water eligibility, and shared SCH defensive tuning now consume the explicit canonical config snapshot.
- Sleep collection is canonical end-to-end: enablement, ordered spell list, range, effect suppression, and spell selection all consume `ctx.config`; stale flat `sleep` / `sleepspells` state can no longer drive scheduler collection.
- Combat Prime and fight-leader collection now consume canonical `ctx.config` as well as the earlier commitment path. `uc_provider_combat.lua` flat-context markers fall 20→11; survivors are partner/pull/WS/job-runtime seams tracked separately rather than Sleep/Prime/fight durable authority.
- Remaining flat scheduler/provider surfaces are explicitly outside this common Phase 3 authority boundary: RUN/SCH/SMN/PUP job configuration moves to Phase 4, scheduler cadence fields such as `_sched_next_*` are runtime state, diagnostic helpers are non-action authority, and explicit no-config core/legacy callers remain compatibility-only.
- The prior follow/pathing tests continue to prove configured names are durable while resolved party/fight/partner/puller IDs are live-derived; path route/session state remains non-authoritative compatibility schema debt rather than scheduler policy.
- Automated proof on implementation head `a3670fa83a055ad582be0b5ff6bab7821f4a2950`: workflow `37205168055` completed successfully with `lua-sequence` PASS, the Phase 3 automated exit audit PASS, flat-surface guard PASS, all earlier Phase 2/3 authority suites PASS, and `winforms` PASS. Live-game smoke verification remains required before Phase 3 live acceptance is complete.

## Working checklist

When completing any migration slice:

- [ ] inspect current callers and writers;
- [ ] classify durable config vs runtime state;
- [ ] identify exact canonical path(s);
- [ ] add or update tests before removing fallback;
- [ ] migrate the smallest cohesive consumer set;
- [ ] verify changed Lua with Lua 5.1 tooling where available;
- [ ] run targeted tests;
- [ ] update flat-consumer allowlist/guardrail;
- [ ] update this document's phase status and progress log;
- [ ] note live-game verification still required, if applicable;
- [ ] keep rollback straightforward.

## Completion definition

This migration is complete only when Profile V2 is the single durable configuration authority from editor/save through runtime consumption, and flat compatibility state can no longer change durable automation semantics.
