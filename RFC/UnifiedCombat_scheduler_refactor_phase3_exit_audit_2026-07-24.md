# UnifiedCombat Scheduler Refactor Phase 3 Exit Audit

Audit date: 2026-07-24
RFC: `RFC/UnifiedCombat_scheduler_refactor_RFC_for_Codex.md`
Base commit: `1060c2724878316c153626c636fc7286f0a5c4da`
Decision: **PASS — Phase 3 provider purity is complete, replay verified, and multibox field accepted**

## Scope

This audit covers RFC tasks T3.1 through T3.5 and the Phase 3 overview's
enemy-buff-removal provider requirement. The intended behavior change is none:
the work moves existing proposal collection behind dependency-injected provider
factories while leaving scheduler ranking, locks, pending state, dispatch, and
movement behavior in their established owners.

Phase 4 movement ownership and Phase 5 legacy domain cutover are outside this
audit.

## Requirement-by-requirement result

| Requirement | Result | Authoritative evidence |
| --- | --- | --- |
| T3.1 defensive provider | PASS | `uc_provider_defensive.lua` owns internal and HealBot collection through `collect_internal` and `collect_healbot`. It appends proposal records and contains no dispatch or lock call. |
| T3.2 combat provider | PASS | `uc_provider_combat.lua` owns WS, Sleep, engage, and configured-JA collection. Existing proposal identities, priority inputs, settings gates, dark-launch ownership, skillchain metadata, and action fields remain represented. |
| T3.3 tank enmity provider | PASS | `uc_provider_tank_enmity.lua` calls the existing `select_tank_enmity_for_scheduler` dependency, preserves readiness gating and proposal fields, and contains no command, movement, turn, target, or attack execution. |
| T3.4 maintenance provider | PASS | `uc_provider_maintenance.lua` owns the existing COR, BRD, and GEO proposal paths, including BRD lifecycle-failure consumption and action-lane proposal behavior. No maintenance command is dispatched by the provider. |
| T3.5 target/pull/add-control adapters | PASS | `uc_provider_target_control.lua` owns target acquisition, engaged add-control retarget proposals, and pull proposals. It does not invoke `uc_add_control.execute_add_retarget`, target selection, attack, movement, or dispatch helpers. |
| Enemy-buff-removal provider | PASS | `uc_provider_enemy_buff_removal.lua` reads the authoritative tracker through injected `list_targets`/`get_effects` functions and emits the established dispel proposal without executing it. |
| Provider purity | PASS | The Phase 3 contract suite rejects provider references to direct command, run, turn, target, attack, dispatcher, ownership-execution, and scheduler-lock APIs. |
| Dispatch remains centralized | PASS | `unified_scheduler.lua` retains dispatch selection and all Phase 2 dispatcher seams. Provider modules do not call the dispatcher or concrete executors. |
| Behavior and order preserved | PASS | `p1_collect_proposals` calls extracted providers in the established target → engage → pull → tank → Sleep → offense → JA → enemy dispel → defensive → maintenance order. Existing focused parity suites and the aggregate suite pass. |

## Extracted module boundary

| Module | Proposal responsibility |
| --- | --- |
| `uc_provider_defensive.lua` | Internal defensive and HealBot |
| `uc_provider_combat.lua` | Weaponskill, Sleep, engage, configured job ability |
| `uc_provider_tank_enmity.lua` | Tank enmity |
| `uc_provider_enemy_buff_removal.lua` | Enemy buff removal |
| `uc_provider_maintenance.lua` | COR, BRD, and GEO maintenance |
| `uc_provider_target_control.lua` | Target acquisition, add-control retarget, and pull |

`unified_scheduler.lua` is 6,196 lines after extraction, down from the 7,470-line
Phase 2 baseline. The six provider modules total 1,673 lines. Provider
construction is intentionally at the end of the scheduler module so every
injected scheduler helper has been defined before the fail-fast factories run.

## Purity and side-effect audit

No provider contains a call to:

- `windower.send_command`;
- `windower.ffxi.run` or `windower.ffxi.turn`;
- `uc_settarget.select_by_id`;
- `uc_attack.engage_target`, `switch_target`, or `disengage`;
- `uc_add_control.execute_add_retarget`;
- the dispatcher or ownership execution helpers;
- scheduler lock acquisition or dispatch-record helpers.

`uc_provider_combat.lua` and `uc_provider_tank_enmity.lua` retain `/ma`, `/ja`,
and `/ws` strings solely as the pre-existing `legacy_command` proposal field.
Those construction-only occurrences are separately pinned in the side-effect
allowlist. The repository-wide observed-hit total remains 250.

Provider factories validate their required dependencies immediately and fail
fast when an interface is incomplete. No fallback executor was introduced.

## Behavior-parity evidence

The extraction preserves:

- proposal IDs and family IDs;
- provider and action-type values;
- target kinds and target IDs;
- priority bands and urgency rules;
- recast and duplicate-suppression keys;
- lock classes, acknowledgement/effect metadata, and movement/range policy;
- settings ownership gates and collection order;
- Sleep suppression/range rules;
- critical-Cure, tank, engage, Bard, aftermath, and skillchain priority bands;
- skillchain continuation metadata and action timeline logging;
- authoritative enemy-effect tracker use;
- BRD lifecycle-failure handling;
- nonblocking target acquisition through the same target proposal adapter.

The focused static tests that previously inspected collector bodies inside the
scheduler now inspect the provider that owns each body while continuing to
verify scheduler wiring and dispatch behavior separately.

## Verification performed

Commands:

```powershell
lua tests/replay/harness/selftest_scheduler_providers_phase3.lua
lua tests/replay/harness/selftest_spacing_cast_movement_lock.lua
lua tests/replay/harness/selftest_side_effect_inventory.lua
lua tests/replay/harness/selftest_runtime_parse.lua
lua tests/replay/harness/selftest_all_replay_fixtures.lua
git diff --check
```

Results:

- Phase 3 provider contract: PASS;
- spacing/cast movement-lock regression: PASS;
- runtime parse: PASS for 83 runtime Lua files;
- aggregate replay/static validation: PASS, 114/114 suites;
- side-effect discovery guard: PASS across 132 non-test Lua files, 22
  allowlisted files, 330 exact file-pattern checks, and 250 observed hits;
- whitespace/error-marker validation: PASS.

## Live verification

A live Windower DPS session was performed with Terrasjr on MNK/WAR. Targeting,
engage, and the observed combat actions remained functional. An initial report
that the character no longer approached the mob was traced to addon reload
clearing the runtime camp location while the UI continued to display its
previous persisted value. The movement/leash behavior therefore matched the
actual runtime state and did not identify a scheduler/provider regression.

The RFC does not define a Phase 3 field gate, and this extraction changes module
ownership rather than action selection or execution behavior. Additional role
soak covering defensive, tank, Sleep, enemy-dispel, and maintenance paths
remains prudent before promoting this work as a new stable baseline.

The initial BRD maintenance soak exposed a pre-existing execution-safety gap:
reserving the Bard action lane suppressed future scheduler movement ticks but
did not stop an already-active run vector. Bard setup and song dispatch now
issue a dispatcher-owned `run_stop` before the command, and the reserved lane
refreshes a bounded scheduler movement lock so follow/pathing cannot restart
movement during the sequence.

The first retest exposed a second Bard state-machine gap. Live timeline evidence
showed Pianissimo dispatch and consumed recast followed by the 0.5-second
confirmation retry, transaction abandonment, target selection, and engage
movement before the paired targeted song. A dispatched Pianissimo transaction
now retains the action lane for a bounded two-second late-confirmation window
when its recast is consumed. Active Pianissimo transactions also run before
ordinary Bard planning, and normal planner blockers cannot directly release a
lane still required by an active sequence. Focused and aggregate replay/static
validation passed.

The second retest exposed the remaining retry-phase seam. The scheduler generated
a Pianissimo retry proposal while the original JA was still in flight, but the
retry did not dispatch. When the original JA then consumed its recast, the
`awaiting_pianissimo` branch lacked evidence of the earlier real dispatch,
abandoned the transaction, and admitted Erase. The transaction now records its
last actual Pianissimo dispatch independently of retry proposal state, so a
retry that loses dispatch cannot release the lane while the original dispatch
remains inside the bounded confirmation window. Focused and aggregate
replay/static validation passed.

The same field-test pass exposed an analogous spacing/cast gap. The movement
coordinator recognized casting status, spell cooldown, and active spell state,
but returned without cancelling an already-active spacing run vector. All three
cast-freeze branches now issue dispatcher-owned `run_stop`, refresh a bounded
scheduler movement lock, and publish `CAST_MOVEMENT_HOLD` before returning.
Spacing geometry and selection behavior are unchanged. Focused and aggregate
replay/static validation passed.

The final multibox acceptance session passed with Bard maintenance, tank, COR
maintenance, and defensive spell casting active together. No further
Pianissimo interleave, Bard movement-safety, tank, COR, or defensive-casting
failure was reported. This closes the Phase 3 field gate.

## Residual risks and follow-up

- Lua module load order is runtime-sensitive. Factories initialize after all
  scheduler dependencies are defined. Runtime parse and scheduler-load fixtures
  pass, and the Terrasjr field session confirmed addon reload and DPS combat.
- COR, GEO, HealBot, tank, Sleep, and enemy-dispel paths depend on real game
  state that replay/static tests model but cannot fully reproduce.
- Bard maintenance, tank, COR maintenance, and defensive spell casting passed
  the final multibox acceptance session. Continued soak remains useful, but no
  Phase 3 field blocker is open.
- The UI can display a stale persisted camp location after addon reload has
  cleared the corresponding runtime camp anchor. That UI/runtime-state mismatch
  is a separate follow-up and is not part of the Phase 3 provider extraction.
- Independent follow, pathing, Nyzul, lifecycle, and legacy-core movement
  remain Phase 4/5 work and are still explicitly inventoried.
- This phase does not remove legacy compatibility executors or tighten proposal
  validation.

## Exit decision

Every explicit Phase 3 provider family is extracted, proposal dispatch remains
centralized, provider execution surfaces are absent, collection order and
proposal contracts are pinned, and the complete replay/static suite passes.
The provider extraction remains complete, the full Phase 3 working tree is
field accepted, and Phase 4 movement ownership cleanup remains the next RFC
phase.
