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

Status: **IN PROGRESS — all listed Phase 3 runtime domain slices are implemented and CI-proven; automated exit audit implemented with CI proof pending; live behavior verification remains**

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
- [x] follow/pathing durable settings no longer require flat settings;
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
- Durable names remain the source of truth; party/fight/partner/puller IDs are resolved from the live party at runtime. Legacy configured IDs are used only when the corresponding canonical name is absent/unresolvable, and camp leash mode intentionally resolves no player puller ID.
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
- Automated CI proof is pending on the implementation head. Live-game smoke verification remains required before Phase 3 live acceptance is complete.

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
