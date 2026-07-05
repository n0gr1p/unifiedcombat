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
- Output path: `data/profiles_v2/<safe_character>_<MAIN_JOB>_<SUB_JOB>.lua`
- Shape: `return { version = 2, profile = {...}, config = {...} }`
- The `profile` metadata includes `character`, `main_job`, `sub_job`, `source`, `exported_at`, and an optional `profile_key` when available.
- The write path now uses a best-effort temp-file write in the same directory followed by promotion to the final path only after the temp write closes successfully.
- Existing final files are preserved when the temp write fails.
- On Windows, replacement is not claimed to be atomic; when the final file already exists, the helper uses a best-effort backup/promote/restore flow so the final path is not overwritten by a partial write.

The export helper builds the structured payload from the current loaded settings/profile state and canonical normalized config, but it does not change live profile loading, live profile saving, or bridge write behavior.

## Compatibility Boundary

- Structured profile/config read compatibility exists in `uc_config_normalizer.lua` and direct contract tests only.
- Current live profile files still use v1 payloads at `data/profiles/<safe character>.lua`.
- Current live profile load/save behavior is unchanged.
- Current profile save format remains `return { version = 1, profiles = { UC = ... } }`.
- `remote_bridge.lua` remains the live UI write path.
- `//uc profilev2 export` is explicit-command-only and writes the new structured v2 artifact to `data/profiles_v2/`.
- No profile polling or live apply behavior exists.
- Scheduler/provider/action-decision reads still use current runtime settings, not structured profile files.

## Next Step

The next task can either wire this structured read compatibility into the live profile load path in fail-safe/read-only mode, or add a sample/generated v2 profile fixture before any live load-path wiring.
