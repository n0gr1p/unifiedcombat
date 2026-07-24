# Side-Effect Allowlist

Status: **Phase 0 guardrail complete**
Verified: 2026-07-24 at `ff5a56ced0158b1bdabb9413c168de5c0be6b523`
Runtime behavior change: none

## Purpose

This allowlist makes the current hybrid execution surface explicit. An
allowlisted call site is tolerated for the current migration baseline; it is not
an endorsement of the final architecture.

The executable source of truth is:

`tests/replay/fixtures/shared/side_effect_allowlist.lua`

The human call-site inventory is:

`docs/side_effect_inventory.md`

## Active runtime exceptions

| File | Allowed surface | Why it remains | Removal or retention condition |
| --- | --- | --- | --- |
| `UnifiedCombat.lua` | Lifecycle `run(false)` | Stops movement during addon lifecycle control | Route through the chosen movement facade |
| `unified_scheduler.lua` | Scheduler IPC, action command construction, indirect `uc_attack` calls | Scheduler remains a hybrid coordinator/executor | Remove indirect attack execution under dispatcher monopoly; decide IPC ownership explicitly |
| `unified_combat_core.lua` | Commands, movement, turn, target selection, IPC, attack wrappers | Core remains the legacy/runtime helper owner and owns the current skillchain WS send | Migrate each active domain with parity evidence; retain IPC only by explicit decision |
| `uc_attack.lua` | Action packet injection | Central packet implementation for engage/switch/disengage | Make it a dispatcher-owned dependency or move packet execution into dispatcher |
| `uc_settarget.lua` | Target packet injection | Central packet implementation for target selection | Make it a dispatcher-owned dependency or move packet execution into dispatcher |
| `uc_add_control.lua` | Attack-off, select-target, and attack command sequence | Behavior-sensitive add retarget flow | Migrate the full ordered sequence atomically |
| `uc_party_follow.lua` | Run/stop, IPC, zone packet injection | Independent follow and zone-replay behavior | Route movement through the selected facade; retain IPC/injection only by explicit movement/follow decision |
| `uc_pathing.lua` | Run/stop | Independent path movement | Route through movement facade |
| `uc_nyzul_runtime.lua` | Stop and IPC | Nyzul coordination behavior | Route stop through movement facade; retain IPC only if Nyzul remains its owner |
| `uc_lilith_easy_formation_runtime.lua` | Run | Formation movement | Route through movement facade |
| `uc_camp_anchor.lua` | IPC | Camp-anchor synchronization | Expected to remain if camp-anchor remains the state owner |
| `uc_scheduler_command_builder.lua` | `/ma` and `/ja` construction only | Pure intent construction, not execution | Expected to remain pure |
| `remote_bridge.lua` | Explicit addon reload command | User/UI control operation outside combat arbitration | Expected bridge exception unless a later task changes it |

## Legacy and separate-subsystem exceptions

| File | Reason |
| --- | --- |
| `melee_engine.lua` | Legacy engine; do not expand its side-effect surface |
| `dd2_engine.lua` | Legacy engine; do not expand its side-effect surface |
| `dd2_module.lua` | Legacy module; do not expand its side-effect surface |
| `lor/lor_actor.lua` | Shared actor-control library |
| `lor/lor_chat.lua` | Shared chat/echo library |
| `TargetBar/TargetBar.lua` | Separate TargetBar packet behavior |

## Guard behavior

`tests/replay/harness/selftest_side_effect_inventory.lua`:

1. uses `rg --files` to discover every non-test Lua file, including untracked
   files;
2. scans all discovered files for the tracked direct, construction, packet, IPC,
   and wrapper patterns;
3. fails if a file with a match is not allowlisted;
4. fails if an allowlisted file disappears;
5. fails if any per-file/per-pattern count changes.

The test has no alternate discovery path. Missing `rg`, unreadable files, an
invalid allowlist schema, or an empty discovery set are fatal errors.

## Rules for future work

- Do not add a direct side-effect site without an explicit ownership decision.
- Do not add provider-side execution.
- Do not add a new fallback executor when migrating a path.
- Keep command strings and side-effect counts stable during mechanical moves.
- Update the machine allowlist and both human documents in the same task.
- Remove an allowlist entry as soon as its last tracked surface is migrated.
- Treat a passing guard as proof of inventory consistency, not proof that
  dispatcher monopoly has been achieved.

## Verification

```powershell
lua tests/replay/harness/selftest_side_effect_inventory.lua
```

Current expected result:

```text
runtime_files=119
allowlisted_files=19
pattern_checks=266
observed_hits=263
```
