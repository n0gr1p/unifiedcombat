# FastFollow Zone Parity Map (UC)

## Scope
This map covers only the **zone handoff path**:
- IPC zone broadcast on outgoing 0x05E
- IPC zone receive dispatch
- zone replay/inject routine

It does **not** cover general follow movement, combat, pathing, or UI.

## Sources
- FastFollow: `C:\Program Files (x86)\Windower\addons\FastFollow\FastFollow.lua`
- UC: `C:\Program Files (x86)\Windower\addons\UnifiedCombat\uc_party_follow.lua`

## Parity Table

| Behavior Block | FastFollow Lines | UC Lines | Verdict | Notes |
|---|---:|---:|---|---|
| Outgoing zone broadcast trigger (`id == REQUEST_ZONE`) | 270-282 | 244-279 | MATCH (core) | Same 0x05E gate and suppress concept with `last_zone` + `zone_suppress`. |
| Broadcaster emits `zone <name> <line> <type>` | 271-276 | 267-276 | MATCH (wire format) | Same message format. UC wraps "who may broadcast" via `party_follow` mode. |
| Suppress outgoing request while following | 278-282 | 254-263 | MATCH (core) | FastFollow: `following && within suppress -> return true`; UC mirrors this when `party_follow == true`. |
| Zone IPC receive gating to selected leader | 198-204 | 158-188 | MATCH (core) | Both require follower-mode + leader-name match before replay call. |
| Zone replay entry delay | 358 | 106 | MATCH | Same `sleep(0.2 + random*2.5)`. |
| Zone replay zone guard (`info.zone == source zone`) | 362 | 113-116 | MATCH (semantic) | UC uses `zones_equivalent(...)`; equivalent for numeric/string zone ids. |
| Build outgoing 0x05E packet with line/type | 364-367 | 117-122 | MATCH | Same packet fields. |
| Distance wait loop (`<=12`, `sleep 0.25`) | 371-378 | 127-138 | MATCH | Same loop limits/timing and self refresh. |
| Inject only if within zone_min distance | 380-383 | 139-150 | MATCH | Same threshold behavior and `last_zone` update on success. |

## UC Wrapper Differences (Intentional, Outside Core Parity)
These are outside the FastFollow core algorithm and exist for UC observability/integration:

1. `pf_set_op(...)` diagnostics and last-5 op history logging.
2. `pcall(...)` wrappers around packet build/inject for safer error visibility.
3. UC leader resolution path uses `party_follow_id/name` + `ipc_pos` cache (instead of FastFollow `following` + `target` object), but feeds equivalent `(zone,x,y)` into the same replay algorithm.

## Proof Summary
For the zone handoff algorithm itself (send/receive/replay), UC now mirrors FastFollow control flow and timing, with UC-specific wrappers only for:
- selecting who is "following"/"broadcasting"
- diagnostics

If a future change touches these mapped blocks, this file must be updated before claiming parity.
