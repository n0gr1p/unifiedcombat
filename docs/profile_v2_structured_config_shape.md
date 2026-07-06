# Profile V2 Structured Config Shape

Task: `T3.8a`

## Supported Read-Compatible Shape

The config normalizer now accepts a future structured profile/config payload as pure input:

```lua
return {
  version = 2,
  profile = {
    schema_version = 2,
    engine = "UC",
    character = "Redrogue",
    main_job = "PLD",
    sub_job = "WAR",
  },
  config = {
    ui = { show_ingame_ui = true },
    combat = {
      enabled = true,
      weaponskill = {
        enabled = true,
        primary = "Savage Blade",
        mode = "smart",
      },
    },
    defensive = {
      enabled = true,
      cure = {
        enabled = true,
        min_tier = 3,
        max_tier = 4,
        min_missing_hp = 250,
        ignore_trusts = true,
      },
    },
    tank = {
      enabled = true,
      enmity = { actions = {} },
    },
    maintenance = {
      cor = {
        roll_1 = "Chaos Roll",
        roll_2 = "Samurai Roll",
      },
    },
  },
}
```

`profile` is metadata about the profile file and selected job identity. `config` owns durable grouped settings that map into the canonical config domains already produced by `uc_config_normalizer.lua`.

The normalizer also accepts direct canonical-domain input, such as `{ combat = ..., defensive = ... }`, for focused tests and future bridge/file adapters.

## Explicit Export

`T3.8b` adds an explicit command-only export path that writes this structured payload for inspection:

- Command: `//uc profilev2 export`
- Validation command: `//uc profilev2 validate`
- Diff command: `//uc profilev2 diff`
- Diff detail command: `//uc profilev2 diff detail`
- Status command: `//uc profilev2 status`
- Apply command: `//uc profilev2 apply`
- Reload command: `//uc profilev2 reload`
- Output path: `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua`
- Shape: `return { version = 2, profile = {...}, config = {...} }`
- The `profile` metadata includes `character`, `main_job`, `sub_job`, and `source`. UI-authored files may use `source = "ui"`; addon-exported bootstrap files may use `source = "exported_from_v1_settings"`.
- `profile.exported_at` and `profile.profile_key` are optional metadata. They may be present on addon-exported bootstrap files, but the consumer contract does not require them for UI-authored v2 files.
- The export command is a manual migration/bootstrap seed utility only. The addon is not the normal v2 profile writer/editor; external UI/tooling owns profile editing and writes.
- In live Windower, the command resolves this path under `windower.addon_path` and creates only the expected `data/profiles_v2` directory when it is missing.
- Export failures are reported in chat as `UC profile v2 export failed: <short reason>`, with detailed helper failure data kept in result tables for tests.
- The write path now uses a best-effort temp-file write in the same directory followed by promotion to the final path only after the temp write closes successfully.
- Existing final files are preserved when the temp write fails.
- On Windows, replacement is not claimed to be atomic; when the final file already exists, the helper uses a best-effort backup/promote/restore flow so the final path is not overwritten by a partial write.
- The validation command reads only the expected v2 file for the current character/main/sub, parses the returned Lua table, checks `version`, `profile`, and `config`, and runs contract validation when available.
- The validation command is dry-run only: it does not apply the file to runtime settings, does not mutate `_G.UC_SETTINGS`, and does not write anything back to disk.
- The diff command reads and validates that same file, builds the current durable canonical config from loaded runtime settings, and compares only `payload.config` durable domains.
- The diff helper now also returns structured detail entries for each difference, including the diff path, file-side value, runtime-side value, and the value types, so the detail command can print the exact remaining mismatch.
- The durable comparison intentionally ignores the legacy compatibility mirrors that the live normalizer rebuilds after reload: `abilities.legacy_slots`, `follow.party.leader_id`, `follow.fight.leader_id`, `targeting.legacy_slots`, `targeting.add_priority_names`, and the legacy `sleep` mirrors (`sleep`, `sleepspells`, `sleepspell`) because those fields stay outside the UI-owned durable contract.
- The durable comparison also ignores the runtime engine mirror exposed through `command.engine_enabled_default`, because engine running state is addon runtime state, not durable profile config.
- The diff command ignores `profile` metadata such as `exported_at`, `source`, `character`, `main_job`, `sub_job`, and `profile_key`, and reports only a terse difference count in chat.
- The status command is read-only: it resolves the same expected file path, validates the file when it can be read, compares only durable `config` domains against the current runtime config, and reports a terse summary.
- The apply command reads and validates that same file, compares it against the current durable canonical config, then applies only durable `payload.config` domains back onto the flat runtime compatibility surface when a full candidate settings table can be built and verified first.
- The apply command is explicit-command-only and runtime-only: it does not write v1 or v2 profile files back to disk.
- The reload command reuses that same safe apply path and mutations, but reports reload-oriented chat so the addon remains a consumer of the UI-owned v2 file instead of becoming a general writer/editor.
- `T3.8l` exposes the read-only v2 file status inside the compact config status export payload as `profile_v2`, so UI consumers can see `missing`, `invalid`, `valid_match`, `valid_diff`, or `error` without applying, writing, or mutating settings.

The canonical helper module `uc_profile_v2.lua` builds and consumes the structured payload for export, validate, diff, status inspection, and apply behavior, while the compatibility shim `uc_profile_v2_export.lua` simply returns that same module. This does not change live profile loading, live profile saving, or bridge write behavior.

## Compatibility Boundary

- Structured profile/config read compatibility exists in `uc_config_normalizer.lua` and direct contract tests only.
- Current live profile files still use v1 payloads at `data/profiles/<safe character>.lua`.
- Current live profile load/save behavior is unchanged.
- Current profile save format remains `return { version = 1, profiles = { UC = ... } }`.
- `remote_bridge.lua` remains the live UI write path.
- `//uc profilev2 export` is explicit-command-only and writes the new structured v2 artifact to `data/profiles_v2/` only when a user manually asks for a migration/bootstrap seed.
- The WinForms UI save path now writes the same structured v2 artifact shape to `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua` as the durable UI-owned profile file.
- The UI writer intentionally leaves runtime/session-only or legacy command-mutated fields out of the durable v2 file, including `fight_leader`, `fight_leader_id`, `add_priority_names`, `sleep`, `sleepspells`, `sleepspell`, and the engine runtime mirror `command.engine_enabled_default`.
- Normal v2 profile editing and saving remain owned by external UI/tooling, not by the addon export command.
- No profile polling or live apply behavior exists.
- Scheduler/provider/action-decision reads still use current runtime settings, not structured profile files.

## Next Step

The next task can either wire this structured read compatibility into the live profile load path in fail-safe/read-only mode, or add a sample/generated v2 profile fixture before any live load-path wiring.
