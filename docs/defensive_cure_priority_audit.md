# Defensive Cure Priority Audit

## Observed Behavior

- In field use, party members at yellow or red HP were present.
- Cure-capable characters chose self-buffs instead of curing those injured allies.
- Buff overwrite was disabled on the affected characters, so the overwrite branch alone does not explain the behavior.

## Defensive Candidate Flow

### Candidate generation

Source:

- `build_defensive_candidates()` in `unified_scheduler.lua:1998`
- `choose_defensive_action(...)` in `unified_scheduler.lua:2214`
- defensive proposal emission in `unified_scheduler.lua:2491`

Flow:

1. `build_defensive_candidates()` scans maintenance/self-buff options first through `uc_hb_buff_maint.choose(...)`.
2. It stores at most one selected normal buff candidate in `out.buff` and at most one overwrite candidate in `out.overwrite`.
3. It then scans party members for Cure candidates and stores the best one in `out.cure`.
4. `choose_defensive_action(...)` receives the assembled candidate set and picks a single final defensive action before the scheduler ranks that proposal.

Important implication:

- The scheduler does **not** rank Cure-vs-buff independently from raw proposals.
- The pre-selector chooses one defensive action first.
- If the pre-selector returns a buff, the ranked scheduler never compares Cure against that buff directly.

## Cure Candidate Rules

Source:

- Cure generation in `unified_scheduler.lua:2080`

### Eligible cure targets

- Iterates `get_party_members()`.
- Trusts can be excluded via `def_heal_ignore_trusts`.
- Candidate must satisfy:
  - `m.hpp > 0`
  - `m.hpp < 95`
  - `defensive_cure_enabled == true`
  - `in_party_cast_range(m) == true`

### HP and missing-HP requirements

- Range gate: `in_party_cast_range(...)` requires self, or party member within HealBot-style cast range.
- Missing HP gate:
  - `estimate_missing_hp(m)`
  - must be `>= def_heal_min_missing_hp` (default 250)

### Availability checks

- `choose_cure_spell(...)` finds a usable Cure tier based on missing HP and configured min/max Cure tier.
- `spell_ready(spell)` enforces:
  - spell exists
  - learned / job-usable
  - spell recast ready
  - enough MP

### Duplicate / throttle

- `attempt_allowed('cure', m.name, spell, now, 2.5)` throttles repeat Cure attempts.

### Rejection risk

- Yellow/red HP targets can be excluded if:
  - they are out of range
  - estimated missing HP is below the configured minimum gate
  - Cure spell is unavailable/recast/MP-blocked
  - attempt throttle is active

In the audited bug, however, the stronger problem was **not** missing Cure generation.

## Buff / Self-Buff Candidate Rules

Source:

- `uc_hb_buff_maint.choose(...)` selects at most one buff/overwrite candidate.
- Buff priority is constructed in `uc_hb_buff_maint.lua:347` using:
  - `helpers.pri_default(helpers.member_priority(m), helpers.buff_priority[action_name] or 5)`

### Member priority baseline

Source:

- `uc_scheduler_defensive_utils.lua:68`

Behavior:

- self => `member_priority = 1`
- allies => `member_priority = 5`
- trusts => `member_priority = 6`

That means a self-buff naturally receives a much better raw `prio` than an ally-directed Cure candidate.

## Exact Selection Rule Causing Cure to Lose

Source before fix:

- `unified_scheduler.lua:2238`

Problematic rule:

- In the `elseif c.cure then` branch, the chooser previously allowed:
  - `elseif c.buff and ((c.buff.prio + 2) < c.cure.prio) then return c.buff`

Combined with:

- self buff `prio` around `1.x`
- ally Cure `prio` around `5`

Result:

- Self-buffs could beat valid yellow/red ally Cure candidates before the scheduler ever emitted the defensive proposal.

Separate setup behavior:

- Majesty is a self-buff JA with high defensive value because it enables a stronger Cure immediately after the JA.
- The original bug was **not** that Majesty existed; it was that ordinary self-buffs could win over a valid Cure candidate.

## Finding

- Cure candidates were **present**, not missing.
- The observed issue was primarily: **valid Cure candidate losing to normal self-buff selection in `choose_defensive_action(...)`**.
- Overwrite-disabled context is consistent with this finding because the losing branch was the normal `c.buff` path, not overwrite alone.

## T3.1g Overcorrection

T3.1g correctly removed ordinary self-buff preemption, but it also over-tightened the chooser:

- Majesty was changed to lose whenever any Cure candidate existed.
- Field use showed that policy was too aggressive.
- The practical problem was not Majesty priority itself; it was that the follow-up Cure after Majesty was being blocked by the generic JA acting/cooldown window.

## Action-State Finding

Source:

- `uc_scheduler_action_state.lua`

Observed scheduler behavior after Majesty:

1. `action_mark_sent(...)` records the JA as an in-flight action.
2. JA sends use the shorter JA timeout path, but still mark:
   - `action_start`
   - `last_action`
   - `action_delay = 0.6`
   - `cooldown_until = now + 0.6`
   - `last_send_kind = 'ja'`
3. `action_dispatch_blocked(...)` then blocks subsequent actions through:
   - `BLOCK_ACTION_ACTING`
   - `BLOCK_ACTION_COOLDOWN`

That generic JA lock is normally correct, but it was too broad for the specific defensive chain:

- last action = Majesty
- provider = `defensive_internal`
- next action = defensive Cure spell

Without a narrow exception, the follow-up Cure could be delayed long enough to erase the value of choosing Majesty first.

## T3.1h Fix Applied

T3.1h applies two narrow changes:

### Defensive chooser policy

- Majesty is restored as a special setup action that can beat an available Cure candidate.
- Ordinary self-buffs still do **not** beat a valid Cure candidate.
- Self-Paralyna / urgent debuff priority remains preserved.
- Solo/self-buff behavior when no Cure candidate exists remains preserved.
- Overwrite behavior remains preserved.

Net chooser policy after T3.1h:

- `Majesty` may beat Cure.
- ordinary `c.buff` may not beat Cure.
- self-Paralyna can still outrank Cure.

### Defensive JA-to-Cure follow-up allowance

- `uc_scheduler_action_state.lua` now records light metadata for the last sent action:
  - `last_action_name`
  - `last_action_provider`
  - `last_def_action_type`
- The defensive scheduler path publishes a transient `_G.UC_DEFENSIVE_CHAIN_ACTION` context around `action_dispatch_blocked()`.
- `action_dispatch_blocked(...)` now allows a bounded bypass only when all of these are true:
  - current provider is `defensive_internal`
  - current action is a `spell`
  - current defensive action type is `cure`
  - last sent action kind is `ja`
  - last action name is `Majesty`
  - last provider is `defensive_internal`
  - last defensive action type is `buff`
  - the follow-up is within a short bounded window (`<= 0.75s`)

That keeps the change narrow:

- no offensive JA bypass
- no tank-action bypass
- no arbitrary JA-to-anything bypass
- no change to range/recast/MP/throttle/validity checks
- no ownership-policy change

## Diagnostics

- No new runtime diagnostics flag was added in T3.1g.
- Cause was clear from the existing chooser rule and was safe to fix narrowly.

## T3.1i Cure Starvation Finding

Field behavior after T3.1h showed a different issue:

- once defensive Cure remained needed, the scheduler could repeatedly select Cure again and again
- eligible instant WS/JA actions were often starved out
- this was not primarily an action-block issue

Primary cause:

- defensive Cure proposals are emitted at `priority_band = 100`
- critical Cure can rise to `priority_band = 110`
- ordinary combat WS/JA proposals usually sit around `priority_band = 70`

That means once a non-critical Cure stays available, ranked selection naturally keeps choosing Cure unless a special high-priority combat case already beats it.

## T3.1i Bounded JA/WS Weave Policy

T3.1i adds a narrow final-selection weave policy rather than rewriting broad proposal scores:

- after a successful defensive Cure send, action-state arms a bounded weave window
- if the next ranked winner is another non-critical defensive Cure
- and a ready/commit-valid combat JA or combat WS is also available
- the scheduler may select exactly one such instant action before returning to Cure

After that one weave:

- the next Cure wins again unless and until another Cure send re-arms the window

### Eligible weave actions

- combat WS proposals
- combat JA proposals

Excluded from the weave policy:

- ordinary self-buffs
- Doom paths
- tank run-stop ownership paths
- movement/vector ownership paths
- unrelated ownership/deferred branches

### Safety rules

- no weave on critical/emergency Cure
- no weave without a recent bounded defensive Cure chain
- no weave for invalid combat targets
- no weave unless the candidate also passes final commit-time revalidation
- no unlimited JA/WS chain between Cures
- Majesty behavior from T3.1h remains unchanged

## T3.1i Action-State Change

`uc_scheduler_action_state.lua` now keeps a bounded recent-defensive-Cure weave window:

- defensive Cure send arms the window
- the next non-spell JA/WS send naturally consumes it because the last-send kind is no longer the defensive spell
- the window also expires on timeout if no safe weave occurs

This keeps the policy local and bounded without changing global ownership or broad scheduler ranking contracts.

## T3.1i Upstream Majesty Candidate Finding

Field follow-up showed another issue remained even after the chooser-level T3.1h fix:

- multiple Cure casts could still happen in a row without Majesty being put back up first
- that pointed upstream of `choose_defensive_action(...)`

Confirmed cause:

- `build_defensive_candidates()` only receives a single `c.buff` candidate from `uc_hb_buff_maint.choose(...)`
- `uc_hb_buff_maint.choose(...)` previously returned the first eligible missing ready buff in listed order
- it did not preferentially surface Majesty before other ordinary defensive buffs

That meant:

- Majesty could only beat Cure if `hb_buff_maint.choose(...)` had already chosen Majesty
- if another listed missing buff was encountered first, the chooser never saw Majesty at all

## T3.1i hb_buff_maint Majesty Preference Fix

The fix stays local to `uc_hb_buff_maint.choose(...)`:

- evaluate buff eligibility exactly as before
- remember the first eligible non-Majesty buff
- if an eligible missing ready Majesty candidate is found, return Majesty immediately
- otherwise return the first eligible non-Majesty buff

Important limits:

- Majesty does **not** bypass readiness
- Majesty does **not** bypass recast
- Majesty does **not** bypass missing-buff checks
- Majesty does **not** bypass attempt/throttle gates
- if Majesty is already active, not ready, gated, or otherwise ineligible, previous first-eligible non-Majesty behavior remains

This closes the upstream gap without broadly reordering all buff maintenance behavior.

## Test Coverage

- Added `tests/replay/harness/selftest_defensive_cure_priority.lua`
- Added `tests/replay/harness/selftest_defensive_ja_to_cure_followup.lua`
- Added `tests/replay/harness/selftest_defensive_cure_weave_policy.lua`
- Added `tests/replay/harness/selftest_hb_buff_maint_majesty_priority.lua`
- Covered:
  - red HP ally Cure beats self-buff
  - yellow HP ally Cure beats self-buff
  - Majesty beats available Cure
  - self-buff still wins when no Cure candidate exists
  - self Paralyna still outranks Cure
  - defensive proposal path still emits through `defensive_internal`
  - Majesty immediate defensive Cure follow-up bypasses the generic JA block narrowly
  - unrelated/non-Cure/offensive follow-ups remain blocked normally
  - ranked defensive scheduler path sets and clears chain context around `action_dispatch_blocked()`
  - repeated non-critical Cure can allow one eligible WS weave
  - repeated non-critical Cure can allow one eligible JA weave
  - after one weave, Cure priority resumes
  - critical Cure blocks non-defensive weave
  - invalid JA/WS targets do not weave over Cure
  - bounded weave state arms on Cure send and expires on timeout
  - Majesty beats an earlier eligible non-Majesty buff inside `hb_buff_maint.choose(...)`
  - non-Majesty first-eligible behavior remains when Majesty is not ready, already present, or attempt-gated
  - chooser-level Majesty-over-Cure behavior remains intact after the upstream fix

## Field-Test Instructions

1. Reproduce the original scenario with:
  - buff overwrite disabled
   - one or more allies at yellow/red HP
   - at least one Cure-capable character with defensive Cure enabled
2. Confirm:
   - Majesty is still chosen as the setup action when appropriate.
   - an immediate Cure can follow Majesty without waiting out the full generic JA block.
   - ordinary self-buffs do **not** beat a valid ally Cure candidate.
3. Recheck:
   - solo/self-buff behavior still works when no injured ally exists
   - self Paralyna / urgent debuff removal still takes priority when applicable
   - ordinary buff maintenance still resumes when no Cure candidate exists
   - unrelated JA lock behavior remains normal outside the Majesty -> defensive Cure chain
4. For T3.1i specifically:
   - keep one ally injured enough to sustain repeated non-critical Cure opportunities
   - confirm one eligible instant WS or JA can slip between repeated Cure casts
   - confirm only one instant action weaves before Cure resumes
   - confirm critical/near-emergency Cure still suppresses that weave
5. For the upstream Majesty candidate fix:
   - keep Majesty absent while another ordinary defensive buff is also missing
   - confirm Majesty is chosen first when it is ready and missing
   - confirm ordinary buffs resume normal selection only when Majesty is unavailable, already active, or gated
