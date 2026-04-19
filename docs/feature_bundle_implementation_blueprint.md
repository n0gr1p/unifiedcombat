# UnifiedCombat Feature Bundle Implementation Blueprint

Last updated: 2026-04-18

Purpose:
- rebuild the post-4:56 AM feature set on top of the known-good baseline in `UnifiedCombat`
- apply one feature bundle at a time with explicit file/function-level change targets
- test each bundle before moving to the next
- avoid another large all-at-once merge that hides regressions

Scope:
- Source of truth for transplant targets is `C:\Program Files (x86)\Windower\addons\UnifiedCombatBroken`
- Destination is `C:\Program Files (x86)\Windower\addons\UnifiedCombat`

Non-goals:
- preserving backward compatibility with old profile schemas
- preserving dd2/melee legacy fallbacks
- implementing everything in one pass without validation gates

## Implementation Strategy

1. Create a staging branch/copy from current good baseline.
2. Apply Bundle 1 only. Build + in-game test.
3. If PASS, tag/copy checkpoint.
4. Repeat for each bundle in order.
5. Only proceed when bundle-level acceptance criteria are PASS.

## Bundle Order (Recommended)

1. B1: Unified Core Engine Skeleton + Entry Wiring
2. B2: Packet-native Target/Attack Primitives
3. B3: Target Selection + Sticky Target + Death-driven Switch
4. B4: Movement/Facing Parity (close range + spacing)
5. B5: Smart WS + JA Pipeline + WS Gate
6. B6: Incoming Action/Event Integration (0x029 path)
7. B7: UI/Bridge State Contract Expansion
8. B8: WinForms Parity Controls + Session Labeling
9. B9: Profile Schema/Storage Cutover (new profile namespace)
10. B10: Build/Packaging + Bundled Third-party libs

---

## B1 - Unified Core Engine Skeleton + Entry Wiring

Goal:
- establish a single UC core tick function and stop routing combat behavior through dd2/melee runtime logic.

Source files/functions (UnifiedCombatBroken):
- `unified_combat_core.lua`
  - `core.combat_tick_once` (line 918)
  - `core.register_adapter` (line 906)
  - `core.get_adapter` (line 914)
  - `core.assert_no_job_branch` (line 952)
  - `run_unified_combat` (line 807)
- `unified_engine.lua`
  - `assert_core_no_job_branch` (line 12)
  - `_G.UC_CoreCombatTickOnce` dispatch path (line 26)

Destination edits (UnifiedCombat):
1. Add new file `unified_combat_core.lua` exactly as in broken baseline first, then trim fallback code after QA.
2. In `unified_engine.lua`:
   - wire engine tick to call `_G.UC_CoreCombatTickOnce()` as primary path.
   - retain temporary guard logging only while migrating.
3. In `UnifiedCombat.lua`:
   - ensure start/stop wrappers call unified engine start/stop entrypoints.

Validation:
- UC loads with no syntax/runtime errors.
- `//uc start` triggers UC tick execution.
- No immediate nil-function errors in chat log.

Stop/rollback criteria:
- any load crash or nil function in core tick.

---

## B2 - Packet-native Target/Attack Primitives

Goal:
- move target and attack controls to explicit packet sends used by UC core; remove command-driven targeting dependency.

Source files/functions:
- `uc_settarget.lua`
  - `M.select_by_id` (line 7)
- `uc_attack.lua`
  - `M.engage_target` (line 42)
  - `M.switch_target` (line 62)
  - `M.engage_current_target` (line 82)
  - `M.disengage` (line 90)

Destination edits:
1. Add new files:
   - `uc_settarget.lua`
   - `uc_attack.lua`
2. In `unified_combat_core.lua` ensure `ensure_target_and_attack` (line 279 in source) uses:
   - `uc_settarget.select_by_id`
   - `uc_attack.switch_target` when already engaged and retargeting
   - `uc_attack.engage_target` when not engaged
3. Remove command fallbacks in UC path (`/attack`, `st <id>`) for core logic.

Validation:
- character can target and engage without SetTarget/GearSwap fallback.
- no repeated attack toggle loops.
- target switch while engaged is possible in add-control scenario.

Stop criteria:
- toggling attack off/on in a loop.

---

## B3 - Target Selection + Sticky Target + Death-driven Switch

Goal:
- prevent mid-fight retarget churn; only switch when intended conditions are met.

Source functions in `unified_combat_core.lua`:
- `find_candidate_target` (line 165)
- sticky state fields (`sticky_target_id`, `sticky_hold_until`) lines 24-25
- death helpers:
  - `death_event_active_for_id` (line 146)
  - `core.on_action_message` (line 670)
- target/engage path:
  - `ensure_target_and_attack` (line 279)
  - retarget call sites around lines 851-854

Destination edits:
1. Port sticky-target state and selection preference logic.
2. Preserve currently engaged target unless explicit retarget condition is true:
   - add-control enabled
   - fight leader intent override
   - current target invalid/dead
3. Port death-event assisted switching logic.

Validation:
- no switch to closer party-claimed mob mid-fight when add-control is OFF.
- with add-control ON, valid retarget occurs.
- after target death, switch-to-next is faster and mostly avoids disengage delay.

---

## B4 - Movement/Facing Parity

Goal:
- restore player-like close/far movement and spacing behavior without ping-pong stutter.

Source functions in `unified_combat_core.lua`:
- `apply_facing` (line 341)
- `apply_movement` (line 351)
- distance helpers:
  - `target_distance` (line 111)
  - `target_real_distance` (line 118)
  - `mob_distance` (line 129)
  - `mob_real_distance` (line 138)

Also depends on:
- `uc_party_follow.lua`
- `uc_follow_adapter.lua` (`update`, line 5)

Destination edits:
1. Port facing call while engaged.
2. Port movement priorities:
   - close to fight distance first
   - spacing acts after close-in satisfied
   - follow target movement should not fight puller/engage close-in during re-engage window
3. Keep movement tick interval tuned for smoothness (match prior effective cadence).

Validation:
- engages and moves into melee range reliably.
- no severe ping-pong around party members.
- spacing still respected once at fight distance.
- puller distance gates respected.

---

## B5 - Smart WS + JA Pipeline + WS Gate

Goal:
- make UC choose WS intelligently (skillchains) and execute JA list pipeline with proper busy gating.

Source files:
- `unified_combat_core.lua`
  - action handlers + SC model:
    - `core.on_action` (line 608)
    - `rebuild_ws_candidates` (line 582)
    - `select_smart_ws` (line 731)
  - run loop action section in `run_unified_combat` (line 807)
- `uc_ws_gate.lua`
  - `M.busy_for_gate` (line 3)
  - `M.evaluate` (line 9)
- `uc_ability_pipeline.lua`
  - `collect_ordered` (line 3)
  - `execute_ordered_abilities` (line 46)

Destination edits:
1. Add `uc_ws_gate.lua` and `uc_ability_pipeline.lua`.
2. Port ws precheck diagnostics (`ws_diag`) and busy evaluation.
3. Port smart WS selector and SC property tracking.
4. Ensure ability order list executes deterministically and respects recast/buff checks.

Validation:
- WS no longer repeats blindly when SC opportunities exist.
- `ws_diag` reflects gate reasons correctly.
- JA sequence triggers in configured order.

---

## B6 - Incoming Action/Event Integration (0x029)

Goal:
- feed live combat messages into UC core for death/SC timing decisions.

Source files:
- `UnifiedCombat.lua`
  - incoming chunk handler forwarding 0x029 to core (line 590)
- `unified_combat_core.lua`
  - `core.on_action_message` (line 670)
  - `core.on_action` (line 608)

Destination edits:
1. Add/confirm `windower.register_event('incoming chunk', ...)` in `UnifiedCombat.lua`.
2. Forward parsed action messages to UC core handler.
3. Guard parser usage to avoid crash on malformed chunks.

Validation:
- action/death events update UC target/SC state in real time.
- no crash when incoming chunk is malformed or parser unavailable.

---

## B7 - UI/Bridge State Contract Expansion

Goal:
- send only meaningful state changes, but with full UC-specific fields needed by WinForms controls.

Source file:
- `remote_bridge.lua`

Critical source anchors:
- dirty state model:
  - `state_dirty`, `force_state_push` (lines 147-148)
  - `mark_state_dirty` (line 152)
- request handling:
  - `request_state` op (line 840)
  - `toggle Start_Engine` op (line 795)
- state payload fields:
  - `engine_display`, `core_tick_mode` (lines 929-930)
  - `Start_Engine` (line 931)
  - `aftermath_enabled`, `aftermath_ws` (lines 935-936)
  - target ignore/add priority entries (lines 1005-1008)

Destination edits:
1. Port dirty-state push logic with signature dedupe.
2. Port new ops:
   - target ignore add/remove/add-current
   - add priority add/remove/move/add-current
   - explicit start/stop engine ops
3. Port expanded state fields used by UI parity controls.
4. Keep periodic fallback heartbeat minimal (deduped payload only).

Validation:
- UI session states sync quickly after user actions.
- no unnecessary redraw churn from identical snapshots.
- state appears for sessions whether engine is on or off.

---

## B8 - WinForms Parity Controls + Session Labeling

Goal:
- full UI editability for retained controls (caveat requirement), and clear session engine display (`[UC]` when unified).

Source files:
- `UnifiedCombatWinForms/HubUiConstants.cs`
- `UnifiedCombatWinForms/MainForm.cs`
- `UnifiedCombatWinForms/MainForm.ParityUi.cs`
- `UnifiedCombatWinForms/MainForm.ParityLogic.cs`
- `UnifiedCombatWinForms/SessionStateHelper.cs`

Key anchors:
- `aftermath_enabled` in `ContextBoolKeys` (`HubUiConstants.cs` line 5 in source)
- Start_Engine mapping (`HubUiConstants.cs` lines 16, 56)
- aftermath controls UI creation (`MainForm.ParityUi.cs` lines 168-178)
- session row uses engine display (`MainForm.cs` around lines 179-194)
- set/toggle forwarding for Start_Engine and aftermath fields (`MainForm.ParityLogic.cs` around 743, 771, 849)

Destination edits:
1. Port aftermath checkbox + dropdown binding.
2. Port target ignore and add-priority UI actions.
3. Ensure session list uses `engine_display`/`core_tick_mode` from snapshot.
4. Fix layout issue where ability toggle overlapped WS row.

Validation:
- all controls from D5/D7/D8 are editable in UI.
- sessions show `[UC]` when running unified tick.
- no hidden setting only available via slash command.

---

## B9 - Profile Schema/Storage Cutover

Goal:
- clean cutover to new profile namespace without old compatibility baggage.

Source anchors in `UnifiedCombat.lua`:
- `_G.UC_PROFILE_SCHEMA_VERSION = 3` (line 31)
- defaults include `aftermath_enabled`, `aftermath_ws` (lines 55-56)
- `UC_PROFILE_DIR = 'data/profiles_uc_v3/'` (line 226)
- schema version write/read checks (lines 283-284, 313, 378, 392)

Destination edits:
1. Create new profile storage root (for clean reprofile).
2. Remove dual-engine profile branches (`melee`/`dd2`) from runtime config model.
3. Ensure defaults initialize only unified settings.
4. Save/load must remain character file with job subsections as currently expected by user.

Validation:
- new profile file writes to new location.
- session defaults start clean on first load.
- per-job settings persist correctly inside character file.

---

## B10 - Build/Packaging + Bundled Third-party libs

Goal:
- reproducible release build and self-contained addon folder.

Source files:
- `UnifiedCombatWinForms/UnifiedCombatWinForms.csproj`
  - `BuildPythonHub` property (line 14)
  - `BuildPythonHubExe` target (line 24)
  - `CopyPythonHubExeToPublish` target (line 31)
- `lor/*` directory (vendored)
- `THIRD_PARTY_NOTICES.md`
- `docs/build_commands.md`

Destination edits:
1. Port csproj targets that optionally rebuild/copy `unified_combat_ui.exe`.
2. Ensure WinForms launcher uses hub EXE path.
3. Vendor non-standard libs (`lor`) into addon folder with attribution.
4. Keep `build_commands.md` up to date with exact publish command variants.

Validation:
- publish produces fresh `UnifiedCombatWinForms.exe` and hub exe when requested.
- addon folder runs without external `lor` dependency.

---

## Cross-Bundle Dependency Map

- B1 required before all others.
- B2 and B3 are tightly linked (target acquisition and attack semantics).
- B4 depends on B3 target stability.
- B5 depends on B6 for best SC/death responsiveness.
- B7 and B8 can be done in parallel after B1 but should be validated against B5/B6 runtime.
- B9 should happen after B7/B8 state contract stabilization.
- B10 can start anytime but finalize last.

## Suggested Test Pass After Every Bundle

Smoke test set:
1. UI starts and discovers sessions.
2. Toggle engine on/off in two sessions, verify list reflects state quickly.
3. Autotarget ON + prime ON:
   - target acquire
   - move to mob
   - engage
   - WS/JA operate
4. Kill target and verify next-target behavior.
5. Save profile, reload addon, confirm settings retained.

## Risk Hotspots (Highest Regression Probability)

1. `remote_bridge.lua` state dirty/signature gating.
2. `UnifiedCombat.lua` incoming chunk integration.
3. `unified_combat_core.lua` target switching branches.
4. WinForms parity state hydration vs outgoing set/toggle messages.
5. profile cutover path and save/load assumptions.

## Quick Diff Commands (for each bundle)

From `C:\Program Files (x86)\Windower\addons`:

```powershell
# Show only source-code file diffs for a specific file
fc /n UnifiedCombat\unified_engine.lua UnifiedCombatBroken\unified_engine.lua

# Find feature markers
rg -n "aftermath_enabled|core_tick_mode|engine_display|switch_target|on_action_message" UnifiedCombat UnifiedCombatBroken
```

## Definition of Done (Full Migration)

- single UC engine file path is authoritative for combat logic.
- dd2/melee are retired to legacy archive, not runtime dependency.
- UI exposes all retained controls (including rollback/follow/add-control related gates if still present).
- profile storage is clean and only stores unified model.
- build produces deterministic artifacts and packaged addon is self-contained.
