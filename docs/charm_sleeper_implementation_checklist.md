# Charmed Player Sleeper Implementation Checklist

## Goal
Add a highest-priority emergency feature that detects charmed party members and keeps them slept until charm clears.

## Scope (Phase 1)
- Add a scheduler-driven `charm_sleeper` emergency lane.
- Detection signal: player/member `charmed == true`.
- Sleep strategy: strongest available sleep spell first (option 2).
- Continuously retry only while target is charmed and not slept.
- Track projected sleep wear-off to pre-clear and re-sleep promptly.

## Out of Scope (Phase 1)
- Tier-1 then tier-2 overwrite ladder strategy.
- Per-job custom sleep policy editor.
- Per-zone behavior differences.
- Crowd-control logic for non-charm scenarios.

## Functional Requirements

### R1. Settings + UI
- Add toggle under Defensive:
  - Label: `Charm sleeper`
  - Setting key: `def_charm_sleeper_enabled`
  - Default: `false`
- Persist to profile and runtime state.
- Must be wired in all runtime/UI key bridges (`KEYS`/parity mappings, remote bridge passthrough, UI hydrate/apply path), not profile-only.

### R2. Detection Rules
- Candidate target is any monitored party member where:
  - `member.charmed == true` (from Windower mob/player data charmed boolean)
  - member is alive and valid
  - member is in cast range
- Source alignment requirement:
  - read charm state from the same mob/player structures shown in debug metadata (`mob.charmed` / player charmed boolean), not inferred from claim/target state.
- Self handling:
  - if local player is charmed, skip dispatch (cannot reliably act).

### R3. Sleep State Rules
- Only attempt sleep when target is:
  - charmed, and
  - not currently slept (based on active sleep/lullaby buff ids tracked in member buffs/status snapshot).
- If target is charmed and sleep breaks early, retry immediately (subject to minimal anti-spam gate).

### R4. Spell Selection (Strongest-First)
- Load spell policy from:
  - `C:\Program Files (x86)\Windower\addons\UnifiedCombat\docs\ffxi_charmed_player_sleep_spells.json`
- Build ordered candidate list from highest to lowest strength.
- Pick first spell that passes:
  - known/usable check
  - recast ready
  - MP check
  - valid targeting/castability checks

### R5. Priority and Arbitration
- Introduce a new proposal family, e.g. `emergency.charm_sleep.primary`.
- Priority must outrank all other actions:
  - higher than doom-water emergency
  - higher than critical cure
- If charm-sleep proposal exists and is valid, it wins selection unless action dispatch is globally blocked.

### R6. Duration Projection + Re-Sleep Scheduling
- On successful sleep dispatch/ack, record projected wear-off for target:
  - keyed by `(target_id, spell_name)`
  - includes `projected_end_at`
- Pre-clear window:
  - shortly before projected end (small lead time) clear “satisfied/asleep” state so scheduler can re-attempt.
- Preserve “attempt only while charmed and not slept” rule:
  - if still slept, wait
  - if charm cleared, immediately stop and clear state

### R7. Anti-Spam Controls
- Add short per-target attempt throttle to prevent packet spam while still urgent.
- Suggested keys:
  - `(target_id, action_name)` for dispatch cooldown
  - optional global emergency cadence guard
- Throttle must not block post-break immediate retry beyond minimal guard.

### R8. Dispatch Integration
- Use existing spell dispatch path and movement/cast freeze coordination.
- Target by member id where possible for deterministic control.
- Respect current action locks but do not lower priority.

### R9. Debug / Observability
- Defensive scheduler logs should include:
  - candidate charmed targets
  - selected sleep spell
  - skip reasons (`NO_CHARMED_TARGET`, `TARGET_ALREADY_SLEPT`, `NOT_READY`, `OUT_OF_RANGE`, `ATTEMPT_GATE`)
  - projected sleep end and pre-clear events
- Add concise debug line in overlay state for active charm-sleeper decision.

## Integration Tasks
- [ ] Add `def_charm_sleeper_enabled` to settings defaults and profile keys.
- [ ] Add WinForms toggle + remote bridge key passthrough.
- [ ] Add explicit `KEYS`/parity mapping so runtime receives UI state updates (prevent stale/unrecognized toggle state).
- [ ] Add spell policy loader for `ffxi_charmed_player_sleep_spells.json`.
- [ ] Add helper to detect “currently slept” state from member buffs/status snapshot.
- [ ] Add phase-1 collector for charm sleeper proposals.
- [ ] Add top-priority scoring band for charm sleeper proposal.
- [ ] Add projected wear-off tracking and pre-clear handling.
- [ ] Add retry throttles and stale-state cleanup.
- [ ] Add defensive debug logging lines for charm sleeper.

## Acceptance Checklist
- [ ] Toggle persists and controls behavior correctly.
- [ ] With toggle OFF: no charm-sleeper proposals/actions.
- [ ] With toggle ON and charmed target present: immediate sleep attempt occurs.
- [ ] Charm sleeper outranks doom and critical cures.
- [ ] While charmed + not slept: retries continue.
- [ ] While charmed + slept: no spam recasts until break/pre-clear point.
- [ ] On charm clear: sleeper logic stops immediately and clears state.
- [ ] No regressions to existing defensive/maintenance scheduling.

## Test Plan (Manual)
1. Enable `Debug` + `Log: defensive scheduler` + `Charm sleeper`.
2. Reproduce charm on party member in sortie scenario.
3. Confirm immediate highest-priority sleep proposal and cast.
4. Confirm retries on early sleep break while charm remains.
5. Confirm projected wear-off pre-clear triggers re-sleep timing behavior.
6. Confirm no actions after charm clears.
7. Verify doom/critical cure are preempted when active charm-sleep condition exists.

## Notes
- Phase 1 intentionally implements strongest-first only (agreed strategy).
- Ladder overwrite strategy can be added later as optional mode if needed.
