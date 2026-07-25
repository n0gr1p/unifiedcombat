# Side-Effect Allowlist

Status: **Phase 5 domain cutover complete**
Verified: 2026-07-24 by replay/static validation and multibox field acceptance;
live path-follow remains an explicitly accepted risk.
Runtime behavior intent: enabled UnifiedCombat domains have scheduler/shared
dispatcher execution and no engine core fallback. Dormant legacy core effects
remain allowlisted for Phase 6 deletion.

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
| `unified_scheduler.lua` | Action command construction only | Scheduler builds intents but no longer directly invokes tracked executors | Retain while command construction remains scheduler-owned |
| `uc_scheduler_party_state.lua` | Injected party-state IPC send | Explicit owner for scheduler party-state IPC encoding, throttling, send, receive, and lookup | Retain while scheduler party-state IPC remains part of the runtime contract |
| `unified_combat_core.lua` | Dormant legacy commands, movement, turn, target selection, IPC, and attack wrappers | The active engine no longer calls the legacy core tick; scheduler pull, skillchain WS, and movement require injected dispatcher-backed executors | Delete unreachable direct paths in Phase 6; retain scheduler-facing helpers and IPC only by explicit decision |
| `uc_attack.lua` | Action packet injection | Dispatcher-owned low-level adapter for scheduler engage/switch/disengage; dormant legacy core code also calls it directly | Retain as adapter, then remove unreachable legacy direct callers during Phase 6 cleanup |
| `uc_settarget.lua` | Target packet injection | Dispatcher-owned low-level adapter for scheduler target selection; dormant legacy core code also calls it directly | Retain as adapter, then remove unreachable legacy direct callers during Phase 6 cleanup |
| `uc_add_control.lua` | Attack-off, select-target, and attack command sequence | Behavior-sensitive add retarget flow | Migrate the full ordered sequence atomically |
| `uc_party_follow.lua` | IPC and zone packet injection | Independent follow position sharing and zone replay; movement itself is migrated | Retain IPC/injection under the Phase 4 ownership decision |
| `uc_nyzul_runtime.lua` | IPC | Nyzul coordination behavior; movement stop is migrated | Retain while Nyzul remains its IPC state owner |
| `uc_camp_anchor.lua` | IPC | Camp-anchor synchronization | Expected to remain if camp-anchor remains the state owner |
| `uc_provider_combat.lua` | `/ma`, `/ja`, and `/ws` proposal command strings | Pure construction of compatibility fields; the provider never executes them | Retain only while proposal compatibility requires `legacy_command` |
| `uc_provider_tank_enmity.lua` | `/ma` and `/ja` proposal command strings | Pure construction of compatibility fields; the provider never executes them | Retain only while proposal compatibility requires `legacy_command` |
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
runtime_files=135
allowlisted_files=19
pattern_checks=285
observed_hits=236
```
