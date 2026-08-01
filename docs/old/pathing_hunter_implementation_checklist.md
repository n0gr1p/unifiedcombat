# Pathing + Hunter Implementation Checklist

Last updated: 2026-04-23  
Branch: `feature/unified-scheduler-design-clean`  
Status: Phase 1 complete; Phase 2 complete; Phase 3 implemented and soak-validated for current scope

## Rules
- Implement and test in this order:
1. Recording
2. Path movement
3. Hunter enablement
- Update this checklist after each code + test pass.

---

## Phase 1 - Recording

### Code
- [x] Add settings defaults/profile persistence:
1. `path_recording`
2. `path_file_name`
3. `path_points`
4. `path_route_type`
5. `path_distance_to_start`
- [x] Add file helpers for path files in `data/paths/`.
- [x] Implement filename builder `{Name}_{Job}_{Zone}_Path.lua` with sanitization.
- [x] Implement recorder hook:
1. runs on prerender cadence (0.2s) so it does not depend on engine running.
2. appends a point only if distance from prior point is `> 0.9`.
- [x] Implement route type classification on stop (`<=10y` loop else patrol).
- [x] Wire remote snapshot fields for UI.
- [x] Add Pathing tab controls for recording diagnostics.

### Tests
- [x] Start recording, walk route, stop recording -> file exists with points.
- [x] Stay mostly stationary while recording -> no point spam.
- [x] Confirm filename changes by char/job/zone.
- [x] Confirm route type detection loop/patrol by endpoint distance.
- [x] Confirm UI distance-to-start updates while recording.

### Exit Criteria
- [x] Recording pass complete and stable.

---

## Phase 2 - Move Along Path

### Code
- [x] Add settings:
1. `path_follow_enabled`
2. `path_party_gate_yalms` (UI tunable)
3. `path_resume_index_window` (UI tunable)
- [x] Implement traversal core:
1. forward progression by index
2. loop wrap behavior
3. patrol reverse behavior
- [x] Add path movement gating:
1. blocked when actively party-following a member.
2. blocked unless all party members are within configured cohesion distance.
- [x] Implement interruption recovery:
1. pause while combat/party gate/follow suppression active.
2. resume to closest point near where we left off (bounded by `path_resume_index_window`).
3. loop-safe wrapped index distance for resume windows.
- [x] Implement follow toggle safety:
1. toggling follow off immediately stops movement vector.
2. auto-load path points on enable/reload if file exists.
- [x] Add debug overlay for party cohesion distances (debug mode only; IPC-first position source).

### Tests
- [x] Loop path continuously cycles from end to start.
- [x] Patrol path reverses at ends.
- [x] With party member outside gate, progression pauses.
- [x] With party follow active, path follow remains suppressed.
- [x] After combat/displacement, resumes path without cross-jumping distant figure-8 segments.

### Exit Criteria
- [x] Path movement pass complete and stable (first pass accepted).

---

## Phase 3 - Hunter Enablement

### Code
- [x] Add hunter settings:
1. `path_hunter_targets`
2. `path_hunter_max_z_delta`
3. `path_hunter_max_target_range`
4. `path_hunter_claim_timeout_s`
5. `path_hunter_ignore_cooldown_s`
- [x] Add Pathing tab hunter controls:
1. target list add/remove
2. max z delta
3. max target range
4. claim timeout
5. ignore cooldown
- [x] Implement hunter filter integration:
1. only path-listed names are eligible when `hunter == on` and path-follow is active.
2. case-insensitive fuzzy substring matching (`elemental` style token support).
3. non-aggressive unclaimed idle mobs are valid for hunter mode (`status == idle`, `claim_id == 0`).
4. tunable vertical viability gate (`path_hunter_max_z_delta`).
5. tunable max target range gate (`path_hunter_max_target_range`).
6. timeout-driven drop of unclaimable targets (`path_hunter_claim_timeout_s`).
7. temporary cooldown blacklist after timeout (`path_hunter_ignore_cooldown_s`).
8. return-to-path behavior after hunter claim timeout.
- [x] Pull-action layer:
1. `path_pull_action_type`
2. `path_pull_action_name`
3. pull dispatch + anti-spam for puller actors
4. move-into-range coordination for selected pull action (JA/spell) before dispatch

### Tests
- [x] Hunter off -> no hunter-name filtering applied.
- [x] Hunter on + list populated -> only matched names are considered.
- [x] Fuzzy matching validated in live test (`elemental` style behavior).
- [x] Timeout + cooldown prevents repeated immediate retries on unreachable targets.
- [x] Pull action usage tests (soak pass for implemented spell/JA pull flow).

### Exit Criteria
- [x] Hunter phase complete for implemented scope.

---

## Final Integration / Regression Sweep

### Code Hygiene
- [x] Pathing tab controls use focus-safe, change-driven update behavior.
- [x] No dd2/melee fallback dependency introduced for pathing/hunter logic.
- [x] Documentation updated for implemented scope in this branch (`PRD` + checklist).

### Regression
- [x] Existing combat behavior unaffected when pathing toggles are off.
- [x] Existing party follow behavior preserved when path follow is off.
- [x] Existing scheduler debug/status overlays remain stable.

### Ship
- [x] Commit pathing/hunter feature checkpoint.
- [x] Run final build check.
- [ ] Capture release notes for pathing feature.
