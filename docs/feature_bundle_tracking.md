# UnifiedCombat Feature Bundle Tracking

Last updated: 2026-04-19
Owner: n0gr1p + Codex
Test environment: Windower multi-session + WinForms direct-connect
Baseline: `UnifiedCombat` (4:56 AM known-good restore)
Source reference: `UnifiedCombatBroken`

Purpose:
- track bundle-by-bundle implementation and validation
- prevent multi-feature merges without QA checkpoints

## Status Legend

- `NOT STARTED`
- `IN PROGRESS`
- `CODE COMPLETE`
- `TESTING`
- `PASS`
- `FAIL (ROLLBACK)`

## Master Bundle Tracker

| Bundle | Name | Status | Code Commit/Copy Ref | Implemented By | Tested By | Last Update | Notes |
|---|---|---|---|---|---|---|---|
| B1 | Unified Core Engine Skeleton + Entry Wiring | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | UC-only runtime path active; no dd2/melee dispatch in active flow |
| B2 | Packet-native Target/Attack Primitives | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Validated across normal aggro, pulled mobs, add-control/fight-leader on/off |
| B3 | Target Selection + Sticky + Death-switch | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Validated in live combat during recent targeting/engage pass |
| B4 | Movement/Facing Parity | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Pass with minor residual ping-pong noted for later refinement |
| B5 | Smart WS + JA Pipeline + WS Gate | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Core WS/JA behavior validated; `ws_diag` UI visibility accepted as non-blocking limitation |
| B6 | Incoming Action/Event Integration | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Live validation passed: death/action events influence runtime and malformed chunks do not crash addon |
| B7 | UI/Bridge State Contract Expansion | PASS | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Sessions, engine toggle, state refresh, UI reload reconnection validated |
| B8 | WinForms Parity Controls + Session Labeling | TESTING | 46f4f96 | Codex | n0gr1p | 2026-04-19 | Core controls + dropdown population validated; full parity checklist still open |
| B9 | Profile Schema/Storage Cutover | IN PROGRESS | 46f4f96 | Codex |  | 2026-04-19 | UC profile model active; cleanup/validation against edge profile data pending |
| B10 | Build/Packaging + Bundled libs | IN PROGRESS | 7d5ef1a | Codex |  | 2026-04-19 | Added ignore/untrack hygiene; build/publish doc and final packaging validation pending |

---

## Per-Bundle Checklists

### B1 Checklist

Code:
- [x] `unified_combat_core.lua` added and loading
- [x] `unified_engine.lua` calls `_G.UC_CoreCombatTickOnce`
- [x] start/stop wrappers call UC core path

Tests:
- [x] addon loads with no errors
- [x] `//uc start` begins UC tick
- [x] `//uc stop` cleanly halts tick

Result:
- Status: PASS
- Notes: Replaced wrapper with real `unified_combat_core.lua` UC tick path and required UC helper modules; removed dd2/melee runtime dispatch from UnifiedCombat event/combat flow. Engine on/off validated via UI start/stop path.

### B2 Checklist

Code:
- [x] `uc_settarget.lua` added
- [x] `uc_attack.lua` added
- [x] UC core uses packet primitives in target/engage path

Tests:
- [x] target+engage works with no command fallback
- [x] no attack on/off loop
- [x] switch target while engaged works in add-control case

Result:
- Status: PASS
- Notes: User validated target switching and engage mechanics under normal aggro, pulled mobs, fight-leader on/off, and add-control on/off.

### B3 Checklist

Code:
- [x] sticky target state added
- [x] candidate selection preserves current engaged target by default
- [x] death-event switch logic integrated

Tests:
- [x] no mid-fight closest-mob snap when add-control OFF
- [x] add-control ON can retarget
- [x] dead-target transition is prompt

Result:
- Status: PASS
- Notes: Passed in recent live-combat validation run together with targeting/engage mechanics.

### B4 Checklist

Code:
- [x] facing logic integrated
- [x] movement priority: close-in before spacing
- [x] follow-vs-engage conflict resolved in re-engage window

Tests:
- [x] close to fight distance reliably
- [x] spacing maintained without ping-pong
- [x] puller distance respected

Result:
- Status: PASS
- Notes: User validation pass complete. Minor residual ping-pong remains but is currently tolerable and deferred for later refinement.

### B5 Checklist

Code:
- [x] `uc_ws_gate.lua` integrated
- [x] `uc_ability_pipeline.lua` integrated
- [x] smart WS selector path integrated

Tests:
- [x] skillchain-aware WS selection visible
- [ ] `ws_diag` reflects gate reason (accepted limitation; non-blocking)
- [x] ability list executes in configured order

Result:
- Status: PASS
- Notes: User validated skillchain-aware WS behavior and ability execution order. `ws_diag` visibility remains inconsistent in UI and is accepted as a non-blocking limitation for now.

### B6 Checklist

Code:
- [x] incoming 0x029 handler forwards to UC core
- [x] `core.on_action_message` invoked safely

Tests:
- [x] death/action events affect runtime decisions
- [x] malformed chunks do not crash addon

Result:
- Status: PASS
- Notes: User validated both runtime reaction to death/action events and safe behavior under malformed incoming chunk conditions.

### B7 Checklist

Code:
- [x] bridge dirty-state signature dedupe enabled
- [x] request_state/start/stop/toggle paths stable
- [x] expanded payload fields included
- [x] target-ignore/add-priority ops included

Tests:
- [x] sessions appear after UI load without addon restart
- [x] engine toggle reflects quickly in session list
- [x] no excessive redundant redraw behavior

Result:
- Status: PASS
- Notes: Direct-connect WinForms hub + bridge/state flow validated by user tests (session discovery, reactivity, reload reconnection, dropdown hydration).

### B8 Checklist

Code:
- [ ] aftermath controls bound in WinForms
- [ ] add-priority and target-ignore controls connected
- [ ] session label shows `[UC]` when unified path active
- [ ] ability row overlap/layout bug fixed

Tests:
- [ ] UI can edit all retained configuration controls
- [ ] state reflects across multiple sessions
- [ ] no hidden slash-command-only controls for retained features

Result:
- Status: TESTING
- Notes: UI interactivity and dropdown data are validated; full retained-control parity sweep still pending.

### B9 Checklist

Code:
- [ ] new profile directory/schema activated
- [ ] unified-only settings model saved
- [ ] per-job config persists correctly in char file

Tests:
- [ ] fresh load produces clean defaults
- [ ] save/reload keeps settings
- [ ] no cross-job contamination in character profile

Result:
- Status: IN PROGRESS
- Notes: UC profile branch/model in place; remaining work is hardening and explicit validation across multi-job profile transitions.

### B10 Checklist

Code:
- [ ] csproj includes optional python hub rebuild + publish copy targets
- [ ] launcher points to hub EXE artifact path
- [ ] `lor` vendored with notices
- [ ] build commands doc updated

Tests:
- [ ] publish command produces expected fresh artifacts
- [ ] addon runs standalone in target folder

Result:
- Status: IN PROGRESS
- Notes: `.gitignore` + untrack commit completed; publish documentation/final packaging checks still open.

---

## Regression Log

| Date/Time | Bundle | Symptom | Repro Steps | Severity | Fix Ref | Retest Result |
|---|---|---|---|---|---|---|
| 2026-04-19 | B7 | WinForms non-reactive / sessions delayed or absent | UI reload + toggle + session discovery tests | High | 46f4f96 | PASS |
| 2026-04-19 | B7 | Settings type-mismatch warning spam on addon load | Reload addon with legacy settings.xml present | Medium | 46f4f96 | PASS |
| 2026-04-19 | B2 | Packet target/engage validation | Normal aggro + pulled mobs + add-control/fight-leader on/off | Medium | 46f4f96 | PASS |
| 2026-04-19 | B3 | Sticky target + death-switch validation | Same live targeting scenarios from B2 pass set | Medium | 46f4f96 | PASS |
| 2026-04-19 | B4/B7 (monitor) | Single-client lockup observed on MNK party leader when target acquired with fight-leader configured to WHM (`Niightsiide`) and 3 engines running / 2 off | 5-account run; FL enabled; party leader MNK manually targeted mob; one client locked once | High | N/A (tracking note) | NON-REPRO after relog/reload; monitor for recurrence |
| 2026-04-19 | B4 | Movement/facing validation | Close-to-target + spacing + puller-distance checks | Medium | 46f4f96 | PASS (minor tolerable ping-pong remains) |
| 2026-04-19 | B5 | `ws_diag` missing in UI/debug despite WS gate operation | Live B5 validation pass (`skillchain` and ability order pass, diag missing) | Medium | N/A | ACCEPTED LIMITATION (non-blocking) |

## Session QA Matrix (Multi-character)

| Character | Job | Engine Toggle | Targeting | Movement | WS/SC | Abilities | UI Sync | Save/Reload |
|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |

## Cutover Gate (Must all be checked)

- [ ] B1-B10 status all PASS
- [ ] No active crash regressions
- [ ] UI startup session visibility acceptable
- [ ] Engine toggle latency acceptable
- [ ] No legacy engine runtime dependency in normal path
- [ ] Packaging works from `UnifiedCombat` folder only

## Change Control Rules (Use this every time)

1. Implement one bundle only.
2. Mark status `CODE COMPLETE`.
3. Run tests and collect notes/screens/log lines.
4. Mark `PASS` or `FAIL (ROLLBACK)`.
5. If FAIL, revert bundle-only changes and log regression row.
6. Do not start next bundle until current bundle is `PASS`.
