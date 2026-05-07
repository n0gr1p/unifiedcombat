# Enemy Buff Removal Implementation Checklist

## Goal
Add scheduler-driven enemy buff removal (e.g., Dispel / Magic Finale) that works even when the character is not engaged.

## Scope (Phase 1)
- Add enemy-buff tracking from incoming packets.
- Add a defensive UI toggle to enable/disable enemy buff removal.
- Add a scheduler provider that proposes dispel/finale actions.
- Candidate targets are any **party-claimed hostile mobs** with tracked dispellable buffs.
- Works for backline casters that are not engaged in melee.

## Out of Scope (Phase 1)
- Current-target-only mode.
- Custom per-buff priority editor in UI.
- Non-party-claimed target handling.
- Deep enemy-buff duration estimation beyond practical recency gates.

## Functional Requirements

### R1. UI Control
- Add checkbox under Healer / Defensive:
  - Label: `Remove enemy buffs`
  - Backing setting key: `def_remove_enemy_buffs`
  - Default: `false`
- Persist in profile and apply to addon runtime.

### R2. Enemy Effect Tracker
Create a module (recommended file: `uc_enemy_effect_tracker.lua`) that:
- Tracks hostile mob buffs from incoming action/message packets.
- Maintains per-target state:
  - `target_id`
  - `effect_id`
  - `seen_at`
  - optional `expires_at` if reliable
  - optional `source_action` metadata for debugging
- Clears state when:
  - mob death message
  - effect removal message
  - zone change
  - target despawn/invalidation sweep

### R3. Packet Sources
- Parse incoming `0x028` action packets for observed buff applications.
- Parse incoming `0x029` action message packets for buff-wear/removal/death cleanup.
- Reuse existing packet handling flow in scheduler where possible (do not duplicate parser paths).

### R4. Dispellable Effect Policy
- Add static policy table mapping dispellable effect IDs.
- Include a pragmatic starter set for common removable enemy self-buffs.
- Must be easy to expand later.

### R5. Target Eligibility
A target is eligible only if all are true:
- Hostile NPC (`spawn_type == 16`), alive.
- `claim_id` belongs to party/alliance side (party-claimed).
- Tracker has at least one active dispellable effect for that target.

### R6. Provider / Proposal Logic
Add provider in defensive/maintenance scheduler path that:
- Runs when `def_remove_enemy_buffs == true`.
- Can run while not engaged.
- Selects one eligible target by deterministic priority:
  1. highest-priority tracked dispellable effect,
  2. nearest target distance,
  3. lowest target id tie-break.
- Chooses action by character capability:
  - Prefer `Magic Finale` if available/ready (BRD path).
  - Else prefer `Dispel` if available/ready.
- Emits a single proposal with target id + action name.

### R7. Dispatch and Gating
- Respect acting lock / cast lock model (no cast while action-in-flight).
- Respect existing spell readiness gates (learned, recast, MP, valid target).
- Movement coordination:
  - Allow move-into-range behavior when needed (spell cast range),
  - hold movement while casting per current movement coordinator rules.

### R8. Anti-Spam / Retry Controls
- Per `(target_id, effect_id, action_name)` cooldown gate to avoid spam.
- Mark attempt timestamps and block immediate retries.
- Clear/retry allowed after cooldown or state change.

### R9. Debug / Observability
When debug is enabled:
- Log tracker updates:
  - buff detected, buff removed, target cleared.
- Log provider decisions:
  - selected target/effect/action,
  - skip reason (`NO_ELIGIBLE_TARGET`, `NOT_READY`, `RANGE`, `ATTEMPT_GATE`, etc.).
- Add compact in-game debug line showing:
  - top dispel candidate target,
  - effect id/name,
  - selected action or skip reason.

## Integration Tasks
- [x] Add setting key in canonical settings defaults.
- [x] Add WinForms checkbox and bind to setting.
- [x] Add remote bridge key passthrough for `def_remove_enemy_buffs`.
- [x] Implement `uc_enemy_effect_tracker.lua`.
- [x] Wire tracker updates from scheduler incoming packet handlers.
- [x] Add dispellable policy table.
- [x] Add provider selection logic.
- [x] Add dispatch integration for Dispel/Magic Finale intents.
- [x] Add attempt gate/cooldown state.
- [x] Add debug logging + overlay line.

## Acceptance Checklist
- [ ] Toggle visible and persists correctly.
- [ ] With toggle OFF: no enemy buff removal intents/actions.
- [ ] With toggle ON: caster removes tracked buffs from party-claimed enemies while not engaged.
- [ ] Action respects readiness/recast/MP and does not spam.
- [ ] Multiple valid mobs: deterministic target selection is stable.
- [ ] Zone/death/removal events clear stale tracker state.
- [ ] No regressions in cure/debuff removal/maintenance behavior.

## Test Plan (Manual)
1. Enable debug + enemy buff removal on one backline caster.
2. Spawn/fight party-claimed mob with known self-buff.
3. Verify tracker logs buff detection.
4. Verify dispel/finale proposal appears and casts without melee engagement.
5. Verify anti-spam gate prevents rapid recast.
6. Verify tracker clears on buff removal and mob death.
7. Repeat with toggle OFF and confirm no action.

## Notes
- This phase intentionally favors correctness and determinism over aggressive optimization.
- Future phases can add richer policy controls (per-buff priorities, current-target-only mode, stricter range/party strategy settings).
