# Profile V2 Single-Source Migration Plan

Status: **Active working document**  
Branch: `refactor/profile-v2-single-source`  
Started: 2026-10-02  
Last updated: 2026-10-02

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
| `uc_pathing.lua` | Passes flat settings into follow/path policy | Medium/High |
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

Status: **NOT STARTED**

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

- [ ] selected leaf consumers no longer depend on flat durable fields;
- [ ] compatibility behavior is covered by tests at the boundary, not inside each consumer.

### Phase 3 — Migrate core scheduler/combat domains

Status: **NOT STARTED**

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

- [ ] scheduler action selection uses canonical durable config;
- [ ] core combat no longer requires flat durable settings;
- [ ] follow/pathing durable settings no longer require flat settings;
- [ ] runtime-only IDs and live state remain outside Profile V2;
- [ ] live behavior checks completed for each migrated domain.

### Phase 4 — Migrate job-specific configuration

Status: **NOT STARTED**

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

- [ ] SMN consumes canonical Profile V2 config;
- [ ] PUP consumes canonical Profile V2 config;
- [ ] SCH consumes canonical Profile V2 config;
- [ ] BRD/COR/GEO have no remaining durable flat dependencies.

### Phase 5 — Migrate UI/edit/write pipeline

Status: **NOT STARTED**

Goals:

- classify every WinForms `op=set` path as durable configuration or runtime command;
- route durable edits through Profile V2;
- retain explicit runtime commands for non-durable actions such as engine start/stop, camp capture, reload, and other action commands;
- eliminate the parallel "write flat live settings" durable-config path;
- reduce or remove flat editor intermediate translation where safe;
- preserve activity profile behavior and rollback semantics.

Exit criteria:

- [ ] durable UI edits are represented in Profile V2;
- [ ] addon bridge no longer mutates flat durable settings as an authority;
- [ ] runtime commands remain explicit and separate;
- [ ] activity apply still deploys canonical Profile V2 only;
- [ ] editor initialization still comes from canonical runtime config/transient working state.

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
