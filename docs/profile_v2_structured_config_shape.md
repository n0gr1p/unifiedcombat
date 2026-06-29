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

## Compatibility Boundary

- Structured profile/config read compatibility exists in `uc_config_normalizer.lua` and direct contract tests only.
- Current live profile files still use v1 payloads at `data/profiles/<safe character>.lua`.
- Current live profile load/save behavior is unchanged.
- Current profile save format remains `return { version = 1, profiles = { UC = ... } }`.
- `remote_bridge.lua` remains the live UI write path.
- No profile polling or live apply behavior exists.
- Scheduler/provider/action-decision reads still use current runtime settings, not structured profile files.

## Next Step

The next task can either wire this structured read compatibility into the live profile load path in fail-safe/read-only mode, or add a sample/generated v2 profile fixture before any live load-path wiring.
