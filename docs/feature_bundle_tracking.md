# UnifiedCombat Feature Bundle Tracking

Last updated: 2026-04-18
Owner: <fill>
Test environment: <fill>
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
| B1 | Unified Core Engine Skeleton + Entry Wiring | CODE COMPLETE | local changes (uncommitted) | Codex |  | 2026-04-18 | Awaiting in-game B1 validation |
| B2 | Packet-native Target/Attack Primitives | NOT STARTED |  |  |  |  |  |
| B3 | Target Selection + Sticky + Death-switch | NOT STARTED |  |  |  |  |  |
| B4 | Movement/Facing Parity | NOT STARTED |  |  |  |  |  |
| B5 | Smart WS + JA Pipeline + WS Gate | NOT STARTED |  |  |  |  |  |
| B6 | Incoming Action/Event Integration | NOT STARTED |  |  |  |  |  |
| B7 | UI/Bridge State Contract Expansion | NOT STARTED |  |  |  |  |  |
| B8 | WinForms Parity Controls + Session Labeling | NOT STARTED |  |  |  |  |  |
| B9 | Profile Schema/Storage Cutover | NOT STARTED |  |  |  |  |  |
| B10 | Build/Packaging + Bundled libs | NOT STARTED |  |  |  |  |  |

---

## Per-Bundle Checklists

### B1 Checklist

Code:
- [x] `unified_combat_core.lua` added and loading
- [x] `unified_engine.lua` calls `_G.UC_CoreCombatTickOnce`
- [x] start/stop wrappers call UC core path

Tests:
- [ ] addon loads with no errors
- [ ] `//uc start` begins UC tick
- [ ] `//uc stop` cleanly halts tick

Result:
- Status: CODE COMPLETE
- Notes: Replaced wrapper with real `unified_combat_core.lua` UC tick path and required UC helper modules; removed dd2/melee runtime dispatch from UnifiedCombat event/combat flow.

### B2 Checklist

Code:
- [ ] `uc_settarget.lua` added
- [ ] `uc_attack.lua` added
- [ ] UC core uses packet primitives in target/engage path

Tests:
- [ ] target+engage works with no command fallback
- [ ] no attack on/off loop
- [ ] switch target while engaged works in add-control case

Result:
- Status: NOT STARTED
- Notes:

### B3 Checklist

Code:
- [ ] sticky target state added
- [ ] candidate selection preserves current engaged target by default
- [ ] death-event switch logic integrated

Tests:
- [ ] no mid-fight closest-mob snap when add-control OFF
- [ ] add-control ON can retarget
- [ ] dead-target transition is prompt

Result:
- Status: NOT STARTED
- Notes:

### B4 Checklist

Code:
- [ ] facing logic integrated
- [ ] movement priority: close-in before spacing
- [ ] follow-vs-engage conflict resolved in re-engage window

Tests:
- [ ] close to fight distance reliably
- [ ] spacing maintained without ping-pong
- [ ] puller distance respected

Result:
- Status: NOT STARTED
- Notes:

### B5 Checklist

Code:
- [ ] `uc_ws_gate.lua` integrated
- [ ] `uc_ability_pipeline.lua` integrated
- [ ] smart WS selector path integrated

Tests:
- [ ] skillchain-aware WS selection visible
- [ ] `ws_diag` reflects gate reason
- [ ] ability list executes in configured order

Result:
- Status: NOT STARTED
- Notes:

### B6 Checklist

Code:
- [ ] incoming 0x029 handler forwards to UC core
- [ ] `core.on_action_message` invoked safely

Tests:
- [ ] death/action events affect runtime decisions
- [ ] malformed chunks do not crash addon

Result:
- Status: NOT STARTED
- Notes:

### B7 Checklist

Code:
- [ ] bridge dirty-state signature dedupe enabled
- [ ] request_state/start/stop/toggle paths stable
- [ ] expanded payload fields included
- [ ] target-ignore/add-priority ops included

Tests:
- [ ] sessions appear after UI load without addon restart
- [ ] engine toggle reflects quickly in session list
- [ ] no excessive redundant redraw behavior

Result:
- Status: NOT STARTED
- Notes:

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
- Status: NOT STARTED
- Notes:

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
- Status: NOT STARTED
- Notes:

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
- Status: NOT STARTED
- Notes:

---

## Regression Log

| Date/Time | Bundle | Symptom | Repro Steps | Severity | Fix Ref | Retest Result |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

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
