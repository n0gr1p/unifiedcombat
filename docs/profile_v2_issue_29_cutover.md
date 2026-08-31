# Issue #29 Profile V2 cutover

## Result

Profile V2 is the sole automatic durable configuration source. The exact
identity path is:

```text
data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua
```

The old `profile_v2_autoload` and
`profile_v2_auto_reload_on_change` fields are obsolete compatibility input.
They do not control behavior, survive canonicalization, appear in the UI, get
written, or participate in durable diffs.

## Lifecycle matrix

| Event | Resolution | Failure state | Engine ordering |
| --- | --- | --- | --- |
| Addon load | Queue exact Profile V2 identity and resolve on the first prerender | Safe normalized defaults | Resolution runs before recovery, pathing, bridge, follow, and watcher work |
| Login | Same as load | Safe normalized defaults | Same as load |
| Main-job change | Stop a running engine, publish defaults, wait for the reported main job, resolve exact identity | Safe normalized defaults | Restart only after resolution |
| Subjob change | Stop a running engine, publish defaults, resolve the new exact identity on prerender | Safe normalized defaults | Restart only after resolution |
| Stable file edit | Validate and apply through the shared Profile V2 apply helper | Retain last-known-good config | Engine running state is not changed |
| Missing file created later | Detect, debounce, validate, and apply automatically | Existing safe/LKG config until valid creation stabilizes | Engine running state is not changed |

Neither missing nor invalid new-identity resolution reads
`data/profiles/<character>.lua`, retains prior-identity durable values, or
silently chooses a nearby identity.

## Watcher contract

- Poll interval: one second.
- Stable-content window: one second.
- Content hash suppresses unchanged reapplication.
- A changed hash restarts the stable-content window, covering temp/promote and
  rapid repeated saves.
- An invalid stable hash is reported once and retained as the last error.
- Repeated polls of the same invalid hash do not repeat the chat error.
- A corrected hash is independently debounced and applied automatically.
- Automatic and manual application share validation, canonical active-profile
  publication, in-place compatibility projection, and post-apply status logic.

## WinForms ownership

- Durable Save writes only the exact Profile V2 file using the existing
  temp/promote/restore writer.
- The editor initializes from transient working state when present, otherwise
  from the bridge's canonical active-config projection.
- Historical `data/ui_profiles/*.json` files are ignored by normal editor load
  and Save flows. The old helper methods remain private dead compatibility code
  with no call sites and do not define a configuration source.
- Activity bundles may contain `ui_profiles/*.json` as explicit, checksum-paired
  editor snapshots. Apply deploys only Profile V2 files and moves the editor
  snapshots into transient memory after successful acknowledged reload.
- The bridge exposes nested active config for editor initialization; it does not
  become a second durable store.

## Compatibility and manual commands

- `_G.UC_ACTIVE_PROFILE` remains the canonical applied runtime config.
- `_G.UC_SETTINGS` remains the in-place compatibility projection consumed by
  existing providers and scheduler code.
- `//uc profilev2 reload`, `apply`, `validate`, `diff`, and `status` remain
  explicit diagnostic/recovery tools.
- `//uc save` and `//uc reload` remain public compatibility commands, but now
  target Profile V2 rather than `data/profiles`.
- Legacy profile reader/writer helpers remain defined for compatibility and
  inspection only. Targeted source-contract tests enforce that their only
  occurrences are their definitions.

## Acceptance checklist

- [x] `profile_v2_autoload` is semantically inert.
- [x] `profile_v2_auto_reload_on_change` is semantically inert.
- [x] Both lifecycle controls are removed from WinForms labels, boolean keys,
  and UI tabs.
- [x] Both lifecycle fields are omitted by Lua canonicalization, active config,
  flat projection, and the C# writer.
- [x] Addon load and login automatically resolve exact Profile V2 identity.
- [x] Main-job and subjob transitions automatically resolve exact Profile V2
  identity.
- [x] Automation is stopped and safe defaults are published before a new
  identity is resolved.
- [x] Missing new-identity files remain on safe defaults without legacy
  fallback.
- [x] Invalid new-identity files remain on safe defaults without stale prior
  configuration.
- [x] The watcher is unconditional and detects creation after absence.
- [x] The watcher debounces rapid writes and suppresses unchanged hashes.
- [x] Invalid live edits retain last-known-good config and report once per hash.
- [x] Corrected live edits apply automatically.
- [x] WinForms durable Save writes only Profile V2.
- [x] Normal editor initialization uses runtime active config or transient
  working state, not per-identity UI JSON.
- [x] Activity activation deploys and rolls back only canonical Profile V2
  files; bundle JSON is explicit editor snapshot data.

## Remaining live acceptance

Automated tests and builds cover the contracts above. Final in-game acceptance
still requires observing a real Windower session across load, login, main-job
change, subjob change, missing-file creation, rapid Save, invalid edit, and
corrected edit while checking chat/status and engine continuity.
