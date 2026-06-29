# Bridge Read-Only Config Consumer Audit

Task: `T3.7k`, updated by `T3.8a`

## Scope

This is a docs/static audit only. No runtime behavior, bridge behavior, profile load/save behavior, scheduler behavior, action selection, movement, targeting, cure, tank, defensive, maintenance, sleep, WS, JA, or spell dispatch behavior changed.

`T3.7j` live sanity passed before this audit: addon reload succeeded, no Lua errors were reported, the external UI still connected/loaded, `//uc configstatus export` succeeded, the exported status looked sane, and a short combat loop showed no weirdness.

`T3.8a` adds structured profile/config read compatibility in `uc_config_normalizer.lua` and contract tests only. It does not change bridge state/options payload fields, `set`, `apply_set(...)`, `cfg_version`, bridge commands, profile save/reload triggers, or any live UI write behavior.

## Bridge Read/Write Surface Summary

Inspected files:

- `remote_bridge.lua`
- `uc_config_runtime.lua`
- `uc_config_normalizer.lua`
- `uc_config_status_export.lua`
- `UnifiedCombat.lua`
- `docs/active_config_consumer_migration_audit.md`
- bridge/status/config replay selftests

Active bridge read surfaces:

| Path | Role | Config migration assessment |
| --- | --- | --- |
| `remote_bridge.lua` / `try_connect` hello payload | Sends session, character/job, and current engine identity after socket connection. | Runtime/player identity status, not durable config. |
| `remote_bridge.lua` / `send_options_snapshot` | Sends read-only UI option lists plus profile/config status. | Only `config_contract_status` is config-status owned and already migrated in `T3.7j`; option lists are derived runtime/player/job metadata. |
| `remote_bridge.lua` / `uc_remote_tick` state snapshot | Sends live status fields every throttle interval or after explicit request. | Only `config_contract_status` is config-status owned and already migrated in `T3.7j`; remaining fields are runtime/player/status owned. |

Active bridge write/edit surfaces:

| Path | Role | Protection |
| --- | --- | --- |
| `process_line` / `op == 'set'` | Flat key edit protocol with `cfg_version` ordering and `apply_set(path, value)`. | Do not migrate yet. This is the live UI write contract. |
| `apply_set(path, value)` | Writes `_G.UC_SETTINGS`, including generic dotted-path mutation and special coercion/validation for follow, spacing, path hunter, path pull, COR, and defensive settings. | Do not change source, semantics, coercion, validation, or side effects in a read migration. |
| List/name edit ops | Mutate settings-backed lists for partner, ignore, target ignore, add priority, sleep, path hunter, tank enmity, COR range, abilities. | Do not migrate; these are UI edit/write protocol values and several are action-affecting. |
| Runtime commands | `toggle Start_Engine`, `start_engine`, `stop_engine`, `save`, `reload`, `addon_reload`, `request_state`, `request_options`. | Command state and profile triggers, not durable config reads. |

## State/Options Field Inventory

| Snapshot | Field | Source today | Source kind | Read-only display/status | UI edit/write protocol | Source-change write/cfg risk | Classification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `hello` | `op` | Literal `'hello'` | derived data | Yes | No | No | `runtime_status_owned_by_addon` |
| `hello` | `session` | Bridge `session_id` | runtime status | Yes | No | No | `runtime_status_owned_by_addon` |
| `hello` | `char` | `windower.ffxi.get_player().name` or `'unknown'` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `hello` | `job` | `windower.ffxi.get_player().main_job` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `hello` | `sub_job` | `windower.ffxi.get_player().sub_job` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `hello` | `engine` | `_G.UC_ENGINE` or `'melee'` | `_G` runtime state | Yes | No | Possible display only | `runtime_status_owned_by_addon` |
| `options` | `op` | Literal `'options'` | derived data | Yes | No | No | `runtime_status_owned_by_addon` |
| `options` | `session` | Bridge `session_id` | runtime status | Yes | No | No | `runtime_status_owned_by_addon` |
| `options` | `char` | `windower.ffxi.get_player().name` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `options` | `job` | `windower.ffxi.get_player().main_job` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `options` | `sub_job` | `windower.ffxi.get_player().sub_job` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `options` | `engine` | `_G.UC_ENGINE` | `_G` runtime state | Yes | No | Possible display only | `runtime_status_owned_by_addon` |
| `options` | `profile_contract_status` | `_G.UC_PROFILE_CONTRACT_STATUS` | profile contract status | Yes | No | No | `profile_status_owned_by_addon` |
| `options` | `config_contract_status` | `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)` | config contract status | Yes | No | No; already migrated | `config_status_owned_by_addon` |
| `options` | `ability_options` | `uc_get_cached_ability_options()` from resource/job ability names | derived player/job data | Yes | Used to populate edit choices | Yes if option identity changes | `bridge_edit_protocol_value` |
| `options` | `weaponskill_options` | `uc_get_weaponskill_names()` joined with `|` | derived player/job data | Yes | Used to populate edit choices | Yes if option identity changes | `bridge_edit_protocol_value` |
| `options` | `path_pull_ja_options` | `uc_get_cached_pull_action_options()` JA side | derived player/job data | Yes | Used to populate edit choices | Yes if option identity changes | `bridge_edit_protocol_value` |
| `options` | `path_pull_spell_options` | `uc_get_cached_pull_action_options()` spell side | derived player/job data | Yes | Used to populate edit choices | Yes if option identity changes | `bridge_edit_protocol_value` |
| `options` | `cor_roll_options` | `uc_get_roll_ability_names()` joined with `|` | derived player/job data | Yes | Used to populate edit choices | Yes if option identity changes | `bridge_edit_protocol_value` |
| `options` | `party_options` | `uc_get_party_name_maps(false)` names joined with `|` | player/job/party data | Yes | Used to populate edit choices | Yes if option identity changes | `bridge_edit_protocol_value` |
| `state` | `op` | Literal `'state'` | derived data | Yes | No | No | `runtime_status_owned_by_addon` |
| `state` | `session` | Bridge `session_id` | runtime status | Yes | No | No | `runtime_status_owned_by_addon` |
| `state` | `char` | `windower.ffxi.get_player().name` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `state` | `job` | `windower.ffxi.get_player().main_job` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `state` | `sub_job` | `windower.ffxi.get_player().sub_job` | player/job data | Yes | No | No | `runtime_status_owned_by_addon` |
| `state` | `engine` | `_G.UC_ENGINE` | `_G` runtime state | Yes | No | Possible display only | `runtime_status_owned_by_addon` |
| `state` | `Start_Engine` | Global `Start_Engine` runtime flag | command state | Yes | Command/toggle related | Yes; tied to engine commands and `engine_enabled` mirror | `command_state` |
| `state` | `zone_suspend_active` | `_G.UC_ZONE_SUSPEND_UNTIL` compared with current time | zone-suspend runtime state | Yes | No | No | `runtime_status_owned_by_addon` |
| `state` | `profile_contract_status` | `_G.UC_PROFILE_CONTRACT_STATUS` | profile contract status | Yes | No | No | `profile_status_owned_by_addon` |
| `state` | `config_contract_status` | `uc_config_runtime.config_contract_status(_G.UC_SETTINGS)` | config contract status | Yes | No | No; already migrated | `config_status_owned_by_addon` |

No state/options field currently publishes a long-lived editable setting value from canonical config except the already-migrated compact `config_contract_status` status snapshot. The option fields are read-only payloads, but they feed the UI's current edit controls and are not canonical config values.

## Protected Bridge Write/Edit Protocol Areas

Do not migrate these in the next bridge task:

- `set`
- `apply_set(...)`
- `cfg_version`
- `toggle Start_Engine`
- `start_engine`
- `stop_engine`
- `save`
- `reload`
- `addon_reload`
- profile load/save triggers
- `set_partner`
- `set_fight_leader`
- `set_party_follow`
- partner/ignore/target-ignore/add-priority/sleep/path-hunter list mutations
- `set_abilities`
- `tank_enmity_replace_actions`
- `cor_roll_range_replace_names`
- path pull action fields
- any field the UI expects to echo/edit through the current flat key protocol
- any value that would change how UI writes are interpreted

## Safe Candidate List

| Candidate | Status | Reason |
| --- | --- | --- |
| `remote_bridge.lua` `config_contract_status` in `send_options_snapshot` and `uc_remote_tick` state snapshot | Complete in `T3.7j` | Active, read-only, compact, no full config or `_G.UC_SETTINGS` exposure. |

No additional active bridge read-only settings consumer is recommended for migration now. The remaining bridge read payloads are runtime/player/status values or option lists used by the existing UI edit protocol.

## Rejected/Deferred Candidate List

| Candidate | Classification | Reason |
| --- | --- | --- |
| `options.ability_options` | `bridge_edit_protocol_value` | Derived option list used by UI editing; not a durable config read. |
| `options.weaponskill_options` | `bridge_edit_protocol_value`, `high_risk_action_affecting` | Feeds action selection edits; changing source could alter UI writes. |
| `options.path_pull_ja_options` / `path_pull_spell_options` | `bridge_edit_protocol_value`, `high_risk_action_affecting` | Feeds path pull action choices; pathing/claim behavior is out of scope. |
| `options.cor_roll_options` | `bridge_edit_protocol_value`, `high_risk_action_affecting` | Feeds maintenance action choices; not a read-only config publication. |
| `options.party_options` | `bridge_edit_protocol_value` | Party-derived names used by edit commands; not canonical config. |
| `state.Start_Engine` | `command_state` | Live command state mirrored into `engine_enabled`; migration would risk command/profile semantics. |
| `state.engine` / `options.engine` / `hello.engine` | `runtime_status_owned_by_addon` | Runtime identity/status, not durable config. |
| `profile_contract_status` | `profile_status_owned_by_addon` | Addon-owned status snapshot, not canonical config. |
| All `op == 'set'` and list mutation handlers | `bridge_edit_protocol_value` | Live UI write protocol. |
| Combat/tank/defensive/movement/targeting/sleep/maintenance scheduler reads | `high_risk_action_affecting` | Explicitly out of scope for this bridge audit. |

## Recommendation

Pause bridge read migration after `T3.7j`. The active bridge has no remaining low-risk read-only settings publication that is both independent of the UI edit/write protocol and a good canonical config parity target.

`T3.8a` does not change this recommendation. Structured profile/config compatibility is available below the bridge at the pure normalizer layer, but the bridge remains the live UI write path until a separate file-owned profile task changes that contract.

Recommended next migration candidate outside the bridge:

| Item | Value |
| --- | --- |
| Candidate | `unified_scheduler.lua` enemy-dispel diagnostic gating helpers |
| Exact functions | `enemy_dispel_diag(msg)` and `enemy_dispel_log(msg)` |
| Old source path | `rawget(_G, 'UC_SETTINGS').debug` and `rawget(_G, 'UC_SETTINGS').log_def_sched` |
| Proposed new runtime helper path | Add a small `uc_config_runtime` debug accessor group, for example `debug_enabled(settings, meta, normalizer)` and `defensive_scheduler_log_enabled(settings, meta, normalizer)`, or one `debug_flags(settings, meta, normalizer)` helper returning compact booleans from `config.debug.enabled` and `config.debug.def_sched`. |
| Expected parity behavior | Preserve current loose boolean behavior for `true`, `1`, and string `'true'`; preserve off behavior for missing/false values; only diagnostic logging/status text changes should be observable. |
| Why not bridge | Bridge migration should stop for now because remaining bridge setting-touching paths are write/edit protocol or command state. |

This candidate is active and low-risk relative to action behavior because it gates diagnostic output only. It still lives inside `unified_scheduler.lua`, so the follow-up task should keep the migration narrow and explicitly avoid scheduler/provider action-decision reads.

## Proposed Tests For Follow-Up Migration

- Add focused selftest coverage for the new `uc_config_runtime` debug accessor(s), including flat legacy settings and nested canonical-style debug input.
- Assert `debug=true`, `debug=1`, and `debug='true'` preserve `enemy_dispel_diag` enabled behavior.
- Assert `log_def_sched=true`, `log_def_sched=1`, and `log_def_sched='true'` preserve `enemy_dispel_log` enabled behavior.
- Assert missing/false values preserve disabled behavior.
- Add a static guard that only `enemy_dispel_diag(msg)` and `enemy_dispel_log(msg)` are migrated in `unified_scheduler.lua`.
- Keep `tests/replay/harness/selftest_bridge_config_status_consumer.lua` asserting bridge `config_contract_status` remains compact and bridge write protocol remains `cfg_version`/`apply_set(...)` based.

## No Runtime Change Statement

`T3.7k` changed documentation only. It did not change runtime code, bridge payload shape, bridge write behavior, profile load/save behavior, config normalization behavior, scheduler/provider action-decision reads, or replay tests.
