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
| B2 | Packet-native Target/Attack Primitives | CODE COMPLETE | 46f4f96 | Codex |  | 2026-04-19 | Added/integrated `uc_settarget.lua` + `uc_attack.lua`; combat behavior soak pending |
| B3 | Target Selection + Sticky + Death-switch | CODE COMPLETE | 46f4f96 | Codex |  | 2026-04-19 | Sticky/death-switch logic present in unified core; dedicated regression pass pending |
| B4 | Movement/Facing Parity | CODE COMPLETE | 46f4f96 | Codex |  | 2026-04-19 | Unified movement/facing logic present; in-combat tuning pass pending |
| B5 | Smart WS + JA Pipeline + WS Gate | CODE COMPLETE | 46f4f96 | Codex |  | 2026-04-19 | Integrated in UC core; combat-chain validation pending |
| B6 | Incoming Action/Event Integration | CODE COMPLETE | 46f4f96 | Codex |  | 2026-04-19 | 0x029 forwarding + action handlers wired; live-combat verification pending |
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
- [ ] `uc_settarget.lua` added
- [ ] `uc_attack.lua` added
- [ ] UC core uses packet primitives in target/engage path

Tests:
- [ ] target+engage works with no command fallback
- [ ] no attack on/off loop
- [ ] switch target while engaged works in add-control case

Result:
- Status: CODE COMPLETE
- Notes: `uc_settarget.lua` and `uc_attack.lua` integrated and used by unified core target/engage path.

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
- Status: CODE COMPLETE
- Notes: Sticky target and death-triggered switch logic implemented in unified core; requires focused in-combat regression QA.

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
- Status: CODE COMPLETE
- Notes: Unified facing/movement path implemented; follow/spacing/close-in interplay still needs dedicated tuning validation.

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
- Status: CODE COMPLETE
- Notes: Smart WS selection + JA pipeline + ws gate integrated in UC core path.

### B6 Checklist

Code:
- [ ] incoming 0x029 handler forwards to UC core
- [ ] `core.on_action_message` invoked safely

Tests:
- [ ] death/action events affect runtime decisions
- [ ] malformed chunks do not crash addon

Result:
- Status: CODE COMPLETE
- Notes: 0x029 forwarding and action/death processing wired into UC core.

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
