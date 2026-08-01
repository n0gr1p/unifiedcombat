# Alliance Target Scope Audit

## Current Behavior Summary

UnifiedCombat currently has several important targeting and combat-validity checks that semantically mean:

- claimed by us or our combat group,
- aggressive toward our combat group,
- or attacking a friendly combat-group member,

but those checks are implemented with party-only data.

In practice, the addon already has a strong central pattern:

- read `windower.ffxi.get_party()`,
- scan only `p0` through `p5`,
- build id sets or claim sets from those six slots,
- then use those sets for claim validity, aggressive-target inference, tank violation detection, fight-leader lookup, spacing, and party TP/target observation.

That means alliance support is not missing because of one single if-statement. It is missing because the existing “friendly combat group” concept is repeatedly represented as “current party only.”

## Alliance Data Availability

Alliance data appears likely available through the same `windower.ffxi.get_party()` structure, but the current runtime code does not inspect alliance slots at all.

Current observed usage:

- `windower.ffxi.get_party()` is used widely.
- Current loops only scan `p0` through `p5`.
- No current runtime scan in the audited files inspects alliance slots such as `a10`, `a11`, or similar.
- No central helper currently collects a friendly “party-or-alliance” member id set.

Because alliance slots are not currently read, alliance support is effectively absent even if Windower already exposes those ids in the same structure.

## Exact Code Paths Found

### Central Party-Only Claim Helper

`uc_targeting_common.lua`

- `build_party_claims()`
- Current scope: party only
- Mechanism:
  - reads `windower.ffxi.get_party()`
  - scans only `p0` through `p5`
  - returns `ids` and `set` keyed by party member mob ids

Current downstream impact:

- all claim-validity consumers that call `build_party_claims()` inherit party-only scope.

### Scheduler Party Member Snapshot

`unified_scheduler.lua`

- `get_party_members()`
- `p1_build_party_id_set()`
- `p1_prime_unclaimed_party_aggressive_ok(settings, mob, party_ids)`

Current scope:

- `get_party_members()` scans only `p0` through `p5`
- `p1_build_party_id_set()` builds a party-only id set from that list
- `p1_prime_unclaimed_party_aggressive_ok(...)` treats unclaimed aggressive mobs as valid only when recent packet target ids point at a party member id

Current semantic effect:

- scheduler engage/autotarget prime logic uses party-only aggressive-target inference.

### Scheduler Engage Claim / Prime Policy

`unified_scheduler.lua`

- `p1_collect_combat_engage(ctx, out)`

Current scope:

- claim validity uses `uc_targeting_common.build_party_claims()`
- aggressive prime fallback uses `p1_build_party_id_set()`

Current behavior:

- valid when claimed by local player or party, because local player is part of the `p0..p5` scan
- not valid for alliance-only claim/aggro unless the alliance member is also in the current party

### Scheduler Enemy Buff Removal Claim Validity

`unified_scheduler.lua`

- `p1_collect_enemy_buff_removal(ctx, out)`
- `enemy_dispel_claim_valid(claim_id, party_claim_set)`

Current scope:

- party-only claim set is passed into the enemy dispel claim validator

Current behavior:

- dispel/buff-removal candidate validity is currently party-claim scoped, not alliance-claim scoped.

### Core Party-Only Friendly Id Check

`unified_combat_core.lua`

- `is_party_member_id(id)`

Current scope:

- scans only `p0` through `p5`

Current downstream usage:

- `prime_unclaimed_party_aggressive_ok(mob)`
- `target_is_party_member_non_tank(target_id, me_id)`
- `resolve_mob_current_target(mob)` claim-owner resolution

This is one of the strongest centralizers in the current codebase.

### Core Prime / Autotarget Aggro Inference

`unified_combat_core.lua`

- `prime_unclaimed_party_aggressive_ok(mob)`

Current behavior:

- if Prime is enabled, an unclaimed engaged mob can be treated as valid when:
  - its resolved current target is a party member id,
  - and its `claim_id` is either zero or also a party member id

Current scope:

- party only

This is a direct alliance-expansion candidate because the semantics are clearly “aggressive to friendly combat group,” not “immediate party only.”

### Core Candidate Scan / Current Target Reuse

`unified_combat_core.lua`

- `find_candidate_target(settings)`

Current behavior:

- claim validity comes from `uc_targeting_common.build_party_claims()`
- prime aggressive fallback comes from `prime_unclaimed_party_aggressive_ok(mob)`
- current target reuse, nearest-target scan, hunter claim handling, and override selection all inherit those party-only checks

Current scope:

- local player or party claim
- party-only aggressive target inference
- not alliance-aware today

### Core Tank Violation Detection

`unified_combat_core.lua`

- `target_is_party_member_non_tank(target_id, me_id)`
- `pick_tank_violation_target(settings, player)`

Current behavior:

- scans mobs attacking a non-tank friendly victim
- victim is considered valid only if `target_is_party_member_non_tank(...)` returns true
- that helper currently just delegates to `is_party_member_id(tid)`

Current scope:

- party only

This is another strong candidate for alliance expansion, because “mob attacking a friendly non-tank ally” naturally extends to alliance combat partners in many real group settings.

### Core Current Target Resolution

`unified_combat_core.lua`

- `resolve_mob_current_target(mob)`

Current behavior:

- first prefers `claim_id` when that id is a party member
- then falls back to `target_index`
- then `mob.target`
- then recent packet-derived target ids

Current scope:

- claim-based friendly resolution is party only
- `target_index` / `mob.target` lookups themselves are broader, but the explicit “friendly claim owner” interpretation is party-only today

### Fight-Leader Name Lookup

`UnifiedCombat.lua`

- `uc_fight_leader_party_id_by_name(name)`

Current behavior:

- name lookup scans only `p0` through `p5`

Current scope:

- party only

If alliance fight-leader behavior is intended, this helper must broaden. If fight-leader is intentionally immediate-party-only, this should stay party-scoped and not be widened accidentally.

### Core Spacing / Friendly Agent Collection

`unified_combat_core.lua`

- `spacing_collect_agents(me, settings)`
- spacing repel scan inside combat approach logic

Current behavior:

- party-only collection of nearby friendly agents for spacing
- scans only `p0` through `p5`

Current scope:

- party only

This does not directly control claim validity, but it is a friendly-combat-group helper that could accidentally diverge if alliance-target validity is widened elsewhere.

### Party TP / WS Observation

`unified_combat_core.lua`

- `get_party_tp()`

Current behavior:

- reads only `p1` through `p5`
- captures id, target, TP, and status for party members

Current scope:

- party only

This affects ally WS observation logic and may matter if alliance combat context should influence assist/transition behavior. It is not necessarily a mandatory first-pass alliance expansion, but it must be called out.

## Party-Only Assumptions

The following party-only assumptions are currently hardcoded:

- friendly claim owners are only the current party
- friendly aggressive targets are only targets attacking the current party
- friendly victims for tank violation logic are only the current party
- scheduler engage prime/autotarget logic only trusts party member ids
- fight-leader lookup only resolves party names
- spacing/repel logic only sees party members
- allied TP/WS observation only sees party members

## Support Status by Category

| Category | Current support |
| --- | --- |
| local player claim | yes |
| party claim | yes |
| alliance claim | no |
| party member target / assist context | yes |
| alliance member target / assist context | no |
| party member aggro detection | yes |
| alliance member aggro detection | no |
| party member engagement / tank violation | yes |
| alliance member engagement / tank violation | no |
| current target reuse with alliance validity | indirect / incomplete |
| prime/autotarget alliance selection | no |
| fight-leader alliance lookup | no |
| Windower alliance slot exposure | unknown in this repo; likely available via `get_party()`, but not consumed here |

## Claim / Aggro Logic Inputs Currently Used

Current logic uses these inputs:

- mob `claim_id`
- mob `target_index`
- mob target id via `mob.target`
- recent packet-derived `UC_MOB_LAST_ACTION_TARGETS`
- party member observed targets via `get_mob_by_index(pm.target_index)`
- party member TP/engagement observation via `get_party_tp()`

Current logic does **not** rely on:

- name matching for combat target ownership, except fight-leader name lookup
- alliance slot scanning
- a centralized “friendly combat member ids” abstraction

## Recommended Centralized Helper Design

Preferred narrow implementation:

- add one central friendly-member collector that can read current party and alliance members by id
- then refactor existing party-only claim/validity helpers to consume it where the semantics truly mean “friendly combat group”

Recommended helper shape:

- `get_friendly_combat_member_ids(opts)` or
- `build_friendly_claims(opts)` plus
- `is_friendly_party_or_alliance_member_id(id, opts)`

Recommended behavior:

- id-based, not name-based
- tolerant of nil/offline/out-of-zone slots
- able to return both:
  - ordered id list
  - lookup set
- optionally expose immediate-party-only mode for callers that truly must stay party-scoped

Recommended first centralization point:

- `uc_targeting_common.lua`

Why:

- `build_party_claims()` already acts as a shared claim-set provider
- claim, engage, target scan, and scheduler logic already depend on it
- alliance support can be added once there rather than duplicating slot scans everywhere

Recommended second centralization point:

- a shared member-id helper used by:
  - `is_party_member_id()`
  - scheduler `get_party_members()` / `p1_build_party_id_set()`
  - fight-leader lookup if alliance scope is intended there

## Files Likely Requiring Runtime Changes

Most likely first-pass runtime change files:

- `uc_targeting_common.lua`
  - replace `build_party_claims()` with a friendly-combat-group-aware version or add a new alliance-capable helper
- `unified_combat_core.lua`
  - replace `is_party_member_id()`
  - widen `prime_unclaimed_party_aggressive_ok(mob)`
  - widen `target_is_party_member_non_tank(...)`
  - widen `resolve_mob_current_target(mob)` claim-owner preference
  - review `get_party_tp()` and spacing helpers separately
- `unified_scheduler.lua`
  - widen scheduler `get_party_members()` / `p1_build_party_id_set()`
  - widen `p1_prime_unclaimed_party_aggressive_ok(...)`
  - widen engage and enemy-buff-removal claim validity consumers
- `UnifiedCombat.lua`
  - only if fight-leader name lookup should include alliance members

Possible second-pass files, only if semantics require them:

- `uc_party_follow.lua`
- `uc_pathing.lua`

Current audit did not find evidence that follow/pathing ownership should automatically broaden to alliance. That needs separate semantic confirmation before changing non-combat movement behavior.

## Narrow Implementation Approach

Recommended implementation slice:

1. centralize friendly combat member id collection
2. switch claim/aggro/prime/engage/tank-violation checks from party-only to friendly-combat-group scope
3. leave clearly non-combat or intentionally immediate-party behaviors untouched unless proven necessary

Concretely:

- broaden claim validity
- broaden aggro/prime aggressive-target validity
- broaden tank victim detection
- broaden scheduler engage/autotarget/claim revalidation
- do **not** automatically broaden spacing/follow/pathing unless the desired semantics explicitly include alliance there

## Risks

### Risk 1: Pulling Alliance-Relevant But Locally Undesired Targets

If alliance claims are treated as globally valid everywhere, a character may select or chase a mob claimed by another alliance party member that should not be locally handled.

Mitigation:

- broaden only where semantics truly mean “friendly combat group”
- keep override/assist/puller ownership rules intact

### Risk 2: Off-Zone / Empty Alliance Slots

Alliance slots may be nil, stale, or represent members not present in-zone.

Mitigation:

- require valid mob ids
- ignore zero/nil ids
- prefer current in-zone mob lookups when needed

### Risk 3: Stale Alliance Data

If `get_party()` includes stale or lagged alliance entries, aggressive-target inference could become noisy.

Mitigation:

- keep using id-based checks plus existing `valid_target`, `hpp`, and packet-age guards

### Risk 4: Pets / Trusts / Fellows

Alliance-like friendly entities may not map cleanly to player member slots.

Mitigation:

- first-pass helper should stay member-id scoped, not infer pets or trusts unless already represented through the owning player id path

### Risk 5: Multibox / Multi-Party Alliance Behavior

Alliance expansion could cause characters to honor claims or victims from another alliance party when the intended behavior was only immediate party coordination.

Mitigation:

- audit each callsite semantically instead of globally replacing “party” with “alliance”

### Risk 6: Assist / Fight-Leader Scope Confusion

Fight-leader lookup by name might become too broad if alliance members share similar expectations differently than party members.

Mitigation:

- treat fight-leader lookup as a separate yes/no design decision, not an automatic alliance expansion

### Risk 7: Unintentional Non-Combat Broadening

Spacing, follow, or route logic could change behavior if alliance members are pulled into helpers that were designed only for immediate local formation.

Mitigation:

- keep non-combat helper expansion out of the first patch unless explicitly required

## Proposed Tests

Recommended test coverage after implementation:

- party-only ids remain valid
- alliance ids become valid
- claim_id matching an alliance member id is accepted where claim validity should mean friendly combat group
- aggro / target matching an alliance member id is accepted where prime/autotarget logic should mean friendly combat group
- unrelated player claim remains invalid
- zero-HP target remains invalid even if alliance-claimed
- normal party behavior remains unchanged

Recommended focused test buckets:

- `uc_targeting_common` helper fixtures for friendly id/claim set construction
- core target-scan fixtures:
  - alliance claim valid
  - alliance aggro target valid
  - unrelated player invalid
- scheduler engage/prime helper fixtures:
  - alliance target id accepted
  - party behavior unchanged
- tank violation fixtures:
  - alliance victim accepted
  - self/tank exclusion unchanged

## Field-Test Plan

After implementation:

1. alliance mate claims a mob while not in the immediate six-person party
2. confirm claim-valid targeting can still select/engage where appropriate
3. use an alliance-only aggro target scenario
4. confirm prime/autotarget can treat that mob as valid where intended
5. confirm unrelated external player claims remain ignored
6. confirm current party behavior is unchanged
7. confirm follow/pathing behavior has not unintentionally broadened unless explicitly requested

## Rollback / Feature-Flag Recommendation

Recommended first patch: no long-term feature flag unless the implementation must touch ambiguous non-combat behaviors.

If the first implementation stays narrow and centralized around claim/aggro/combat-validity helpers, rollback can simply be:

- revert the new friendly-member helper
- restore party-only helper consumers

If fight-leader or other ambiguous assist behavior is widened, consider a short-lived feature flag only for that ambiguous layer rather than for the whole alliance-scope change.

## Recommended Next Implementation Slice

Recommended next implementation task:

`T3.2b — Add a centralized friendly combat member id/claim helper, wire it into claim validity, prime/aggressive-target inference, scheduler engage validity, and tank violation target checks, while leaving follow/pathing and other non-combat party semantics unchanged unless explicitly required.`

## T3.2b Implementation Result

Implemented behind `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE == true`.

Default behavior remains unchanged when the flag is unset or any value other than literal `true`.

### New Helpers

`uc_targeting_common.lua`

- `get_friendly_combat_member_ids(opts)`
- `build_friendly_claims(opts)`
- `is_friendly_party_or_alliance_member_id(id, opts)`

Behavior:

- party ids always remain included
- alliance ids are included only when the flag is explicitly `true`
- zero/nil duplicate ids are ignored
- callers may force party-only behavior with `include_alliance = false`

### Guarded Runtime Paths

`unified_combat_core.lua`

- friendly-id combat predicate added through `is_friendly_combat_member_id(id)`
- widened prime aggressive-target validation
- widened claim-valid candidate scan inputs
- widened tank victim detection
- widened current-target claim-owner resolution

`unified_scheduler.lua`

- friendly id set for prime engage validation now comes from `get_friendly_combat_member_ids()`
- engage claim validity now comes from `build_friendly_claims()`
- enemy buff-removal claim validity now comes from `build_friendly_claims()`

### Intentionally Left Party-Only

The following behavior was not broadened in this task:

- `UnifiedCombat.lua` fight-leader name lookup
- follow/pathing behavior
- spacing helpers
- party TP / WS observation
- non-combat member-state logic that still uses `get_party_members()`

This keeps the first pass limited to combat target validity, claim validity, prime/aggressive inference, and tank victim selection.

### Test Coverage Added

`tests/replay/harness/selftest_alliance_target_scope.lua`

- flag off preserves party-only behavior
- flag on includes alliance claim ids and alliance aggro victims
- unrelated claims remain invalid
- zero-HP and recent-death target protections remain active
- source wiring checks pin the new helpers and the intentionally party-only WS observation path

### Field-Test Expectation

With `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true` in the local test flag file:

1. keep two characters in the same alliance but outside the same immediate party
2. let the alliance-only teammate claim or hold aggro from a combat-valid target
3. confirm claim-valid target selection / engage logic can treat that mob as friendly-group valid
4. confirm prime/autotarget can treat alliance-victim aggro as valid
5. confirm unrelated external player claims remain ignored
6. confirm follow/pathing and party TP/WS observation remain unchanged

### Rollback

Set `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false` or remove it from the local field-test flag file to restore current party-only behavior.

## T3.2c Field-Test Closure

T3.2b implementation has now been field-tested successfully with `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE == true`.

### Field-Tested Behaviors

Passed in live testing:

- alliance claim validity worked
- alliance aggro / victim validity worked
- unrelated non-party / non-alliance claim rejection remained intact
- zero-HP / death-animation safety remained intact
- flag-off party-only baseline behavior remained preserved
- no observable regressions were found

### Party-Only Paths Intentionally Preserved

These remain party-only by design after the successful field test:

- `UnifiedCombat.lua` fight-leader name lookup
- follow/pathing behavior
- spacing helpers
- party TP / WS observation
- non-combat member-state logic that still uses `get_party_members()`

### Current Recommendation

Keep `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE` optional for now.

Reason:

- the combat-validity expansion is field-validated and behaving correctly
- the flag still provides a clean rollback lever while alliance scope remains a targeted gameplay expansion rather than a universally required baseline
- no broader non-combat party semantics were changed in this slice

### Rollback Note

If needed, set `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = false` or remove it from the local field-test flag file to immediately restore party-only behavior without touching runtime code.
