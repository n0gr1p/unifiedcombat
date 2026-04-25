# Tank Enmity Rework Implementation Checklist

Last updated: 2026-04-25 (T7 validated and accepted)
Branch: current working branch
Owner: n0gr1p + Codex
Status values: `TODO`, `IN_PROGRESS`, `DONE`, `TESTING`, `PASS`, `FAIL`

## Goal
- Rework `tank` from passive/legacy behavior into active enmity control in UC core.
- Keep a single prioritized mixed action list (JA + spell) for enmity recovery.
- Preserve main-target policy: fight leader target first; otherwise highest-HPP target fallback.

## Scope Decisions (locked)
- One list: `tank_enmity_actions` (mixed JA and spell entries).
- Multi-violation priority: save lowest-HPP party member first.
- No "recover timeout" in this phase.
- Tank can move normally for engage/maintain, but off-target movement should only occur when needed for enmity violation action range.

---

## Phase T1 - Data Model + Persistence
Status: DONE

### Code
- [x] Add `tank_enmity_actions` to UC defaults (`UnifiedCombat.lua`).
- [x] Add `tank_enmity_actions` to profile save/load key set (`PROFILE_KEYS`).
- [x] Add compatibility normalization for list parsing (table + string forms).

### Validation
- [x] Fresh profile includes empty `tank_enmity_actions`.
- [x] Save/reload preserves list ordering and content.

---

## Phase T2 - Core Violation Detection + Priority
Status: DONE

### Code
- [x] Add aggressive-mob scan for "mob targets non-tank party member" violations.
- [x] Deterministic prioritization:
  - [x] lowest victim HPP first
  - [x] then closest violating mob
  - [x] then highest violating mob HPP
  - [x] then lowest mob id
- [x] Add debug diagnostics for selected violation target and victim.

### Validation
- [x] Single violation: chosen mob is correct.
- [x] Multi violation: picks mob targeting lowest-HPP party member.
- [x] Deterministic tie behavior observed in logs.

---

## Phase T3 - Enmity Action Resolver + Dispatch
Status: DONE

### Code
- [x] Parse ordered mixed list entries (`ja:<name>`, `spell:<name>`, tolerant legacy names).
- [x] Select first valid non-cooldown action each tick.
- [x] Execute on violation mob target id.
- [x] Respect action-block status and cast/JA lock guards.
- [x] Spell handling:
  - [x] stop-and-settle before cast
  - [x] wait for spell lifecycle packet updates
  - [x] avoid movement during active cast wait

### Validation
- [x] JA enmity entry executes on violation mob.
- [x] Spell enmity entry executes and does not self-interrupt.
- [x] Cooldown behavior skips to next valid list item.

---

## Phase T4 - Movement Gating Semantics
Status: DONE

### Code
- [x] Allow normal engage/maintain movement for main target.
- [x] When violation exists, only override movement for range-to-enmity-action needs.
- [x] Do not allow movement to break spell enmity action in progress.

### Validation
- [x] No off-target wandering when no violation.
- [x] Moves toward violation mob only when action is out of range.
- [x] Casting stability preserved while resolving violation.

---

## Phase T5 - Main Target Policy Alignment
Status: DONE

### Code
- [x] Keep fight leader target priority unchanged.
- [x] When no fight leader override, tank fallback target select = highest HPP candidate.
- [x] Keep existing target-ignore/add-control guardrails intact.

### Validation
- [x] Fight leader target remains main target anchor.
- [x] No leader: highest-HPP fallback selection observed.

---

## Phase T6 - WinForms UI Surface (single mixed list)
Status: DONE

### Code
- [x] Add "Tank enmity actions" editor (add/remove/up/down) under General settings.
- [x] Provide JA/spell pickers filtered by current job/session options.
- [x] Persist list in UI local profile model.
- [x] Push list to addon via dedicated op (ordered, lossless).

### Validation
- [x] UI edits persist across reload.
- [x] Order in UI equals order used by runtime dispatch.
- [x] No redraw/focus regressions in editor controls.

---

## Phase T7 - Scheduler Ownership for Tank Enmity (Combat Dark Launch)
Status: PASS

### Code
- [x] Emit high-priority combat scheduler proposals for tank enmity actions.
- [x] Prioritize tank-enmity proposals over normal combat WS/JA by score band.
- [x] Scheduler dispatch handles tank target prep (set/switch target) without falling back to core.
- [x] Scheduler dispatch handles tank out-of-range approach movement for enmity actions.
- [x] Scheduler dispatch applies spell settle + pending/lock-safe cast flow for tank spells.
- [x] Core tick suppresses legacy tank enmity dispatch when `scheduler_dark_launch_combat` is enabled.

### Validation
- [x] With combat dark launch on: tank enmity JA/spell dispatch occurs via scheduler path only.
- [x] Out-of-range violation causes scheduler-driven approach, then action dispatch.
- [x] Tank spell does not self-interrupt due to movement while pending.
- [x] No duplicate tank action sends from mixed core+scheduler ownership.

---

## Test Matrix (execution)
- [x] Tank with JA-only list
- [x] Tank with spell-only list
- [x] Mixed JA/spell list with cooldown fallthrough
- [x] Fight leader on/off
- [x] 3+ simultaneous violating mobs
- [x] While engaged and while idle re-engage windows

## Current Work Slice
Status: PASS
- [x] T1 through T6 integrated and validated.
- [x] T7 scheduler-ownership cut-in (code + focused gameplay validation).

### Acceptance Note
- User acceptance: tank enmity implementation testing looks good; remaining issues will be handled as case-by-case bug fixes.
