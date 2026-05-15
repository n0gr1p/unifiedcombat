# UnifiedCombat Pathing + Hunter PRD

Last updated: 2026-04-23  
Owner: Peter + Codex  
Status: Draft for review

## 1) Purpose
Add a new pathing system for hunting routes with:
- Route recording to disk.
- Route-follow movement (loop or patrol behavior).
- Hunter-based engagement of configured mobs while on route.

This feature must be UI-configurable from a dedicated **Pathing** tab and must coexist safely with existing UC combat/movement controls.

## 2) User Goals
- Record a route once and reuse it.
- Know whether a route is a loop or a patrol before stopping recording.
- Move route-to-route with party cohesion controls.
- Hunt only desired mobs while pathing.
- Optionally use configured pull action when acting as puller.

## 3) Scope
### In Scope
- Record points at runtime while recording is enabled.
- Persist path files named by character/job/zone.
- Follow saved path with loop/patrol behavior.
- Pause/return behavior around combat interruptions.
- Hunter target filtering using per-path mob list.
- Pull-action config for puller role.
- Full UI controls in a new Pathing tab.

### Out of Scope (initial release)
- Advanced path smoothing/interpolation.
- Multi-zone continuous routes.
- Automatic route generation.
- Per-point action scripting.

## 4) File Naming + Storage
- Directory: `data/paths/`
- File format: Lua table return file (`.lua`) for consistency with addon data patterns.
- File name format:
  - `{Name}_{Job}_{Zone}_Path.lua`
  - Example: `ponponponponpon_COR_Escha_Zitah_Path.lua`
- Zone segment should use sanitized zone name (safe filename chars only).

## 5) Recording Requirements
- New toggle: `path_recording` (UI + setting).
- While `path_recording == true`, evaluate position every movement tick.
- Append new point only when distance from previous recorded point is `> 0.9 yalms`.
- Persist incrementally or buffered with safe flush behavior (design choice during implementation, but must survive normal reload/save flow).
- Expose real-time diagnostic in Pathing tab:
  - `distance_to_path_start` (from current position to first recorded point).
- This allows operator to know probable route type before stopping recording.

## 6) Route Type Rules
When recording is stopped / path finalized:
- If distance between first and last point is `<= 10 yalms`, classify as `loop`.
- Else classify as `patrol`.

### Behavior by Type
- `loop`: when final point is reached, continue from first point.
- `patrol`: when final point is reached, reverse traversal direction.

## 7) Path Follow Requirements
- New toggle: `path_follow_enabled`.
- Movement along route only when:
  - `path_follow_enabled == true`
  - `party_follow` is not actively following a member target
  - all party members are within `<= 3 yalms` (cohesion gate)
- If route-follow is interrupted (combat, manual displacement, etc.):
  - system should return to the last active path point/index before resuming normal progression.

## 8) Hunter Integration Requirements
- Add editable mob target list in Pathing tab:
  - `path_hunter_targets` (ordered list of names).
- Engagement decision remains gated by existing `hunter` boolean.
- While following path:
  - If `hunter == on`, only engage mobs matching configured path target list.
  - If `hunter == off`, no path-hunter engagements should be initiated by this subsystem.

### Puller Integration
- If `puller == on` and actor is the configured puller:
  - Use configured pull action to pull target mob.
- Add pull action selectors in Pathing tab:
  - `path_pull_action_type` (`spell` | `ja`)
  - `path_pull_action_name`

## 9) UI Requirements (New Pathing Tab)
Add a new tab next to Spacing Tuning / Scheduler:

### Controls
- Checkbox: `Record path`
- Checkbox: `Follow path`
- Read-only label: `Path file` (resolved file name)
- Read-only label: `Distance to start`
- Read-only label: `Route type` (`loop`/`patrol`/`unknown`)
- List editor: `Hunter target mobs`
  - Add by name
  - Remove selected
  - Reorder optional (nice-to-have, not required phase 1)
- Pull action controls:
  - Dropdown: action type
  - Dropdown/text: action name

### Behavior
- Follow existing WinForms anti-redraw standards:
  - Do not repopulate focused controls.
  - Only redraw on value change.
- Must sync across sessions like other tabs.

## 10) Runtime/Engine Integration
- Path recorder and follower should live in UC unified runtime path (no dd2/melee dependency).
- Path follower should coordinate with existing movement ownership logic to avoid command contention.
- Route-follow movement should defer when combat movement ownership has priority.
- Party cohesion gate must be checked before each path progression decision.

## 11) Data Model Additions (initial)
- `path_recording` (bool)
- `path_follow_enabled` (bool)
- `path_route_type` (`unknown|loop|patrol`)
- `path_current_index` (int runtime)
- `path_direction` (`forward|reverse` runtime)
- `path_file_name` (string)
- `path_points` (array of `{x,y,z}`)
- `path_hunter_targets` (string list)
- `path_pull_action_type` (string)
- `path_pull_action_name` (string)
- `path_distance_to_start` (runtime numeric/label)

## 12) Acceptance Criteria
### Recording
- Recording creates zone/job/character-scoped file.
- Stationary spam is prevented by 0.9y threshold.
- Distance-to-start updates in UI during recording.

### Movement
- Follow toggled on traverses path.
- Loop/patrol behavior matches <=10y endpoint rule.
- Path progression halts when party cohesion gate fails.
- If displaced by combat, actor returns to last path point and resumes.
- Path follow never runs while actively party-following target.

### Hunter
- Hunter path targets are editable in UI and persisted.
- Hunter engages only configured target names when enabled.
- Puller role uses configured pull action.

## 13) Risks
- Movement ownership conflicts with existing fight/spacing controllers.
- Party distance gate may need careful definition for offline/out-of-range party entries.
- Zone/entity edge cases can produce temporary invalid coordinates.
- Pull-action legality checks (recast/range/status) must avoid spam.

## 14) Implementation Order (Approved)
1. Recording
2. Moving along the path
3. Hunter enablement

