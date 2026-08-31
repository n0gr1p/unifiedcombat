# Issue #29 pre-change profile architecture

## Inspection baseline

- Inspected commit: `0dd23b6381dbe58841c247f4f94288b59d676f8f`
- Branch: `master`
- Pre-change `git status --short`: clean
- GitHub issue #29 is open with the title `UPDATE QOL: Auto load and auto reloaad profile v2 should be default behavior`; the issue body and comments are empty.

## Verified pre-change lifecycle

1. `UnifiedCombat.lua` initializes `_G.UC_SETTINGS` from in-code defaults and builds an initial active-config projection.
2. Addon load and login call `uc_reload_startup_profile_once()`. That delegates to `UC_ReloadActiveProfile`, whose normal path reads `data/profiles/<character>.lua`, applies main-job defaults, overlays the legacy main-job profile, and republishes active config.
3. Load and login then call `uc_queue_profile_v2_autoload()`. The queued work does not run until `prerender`.
4. `uc_autoload_profile_v2_file()` validates the exact `character + main job + subjob` Profile V2 file, but applies it only when `config.ownership.profile_v2_autoload == true`.
5. Job change resets several runtime modules, reloads the legacy character profile, queues Profile V2, and calls `uc_start_active_engine_if_running()` before the queued Profile V2 work runs. This permits automation to resume under transitional legacy or previous-identity settings.
6. The prerender watcher polls once per second and waits for one second of stable content. It hashes content, suppresses duplicate applies and duplicate rejected-content reports, validates before applying, and preserves the last-known-good active configuration after an invalid live edit. Its entire polling path is disabled unless `profile_v2_auto_reload_on_change == true` in active ownership config.
7. A missing Profile V2 leaves the legacy profile overlay active. Creation after absence is detectable only when the profile-owned auto-reload switch is enabled.

## Verified durable stores

- `data/profiles/<character>.lua` is both read and written by the addon and is a normal runtime fallback beneath Profile V2.
- `data/profiles_v2/<character>_<MAIN_JOB>_<SUB_JOB>.lua` is exact-identity structured configuration, but pre-change it is optional and switch-gated.
- `data/ui_profiles/<character>_<MAIN_JOB>_<SUB_JOB>.json` is loaded by WinForms to initialize the editor and is written on every Save alongside Profile V2. Because WinForms rebuilds Profile V2 from this JSON/editor representation, stale UI JSON can become durable configuration again on a later Save.
- Activity bundles contain explicit Profile V2 snapshots plus UI editor snapshots. Applying an activity writes both the exact Profile V2 file and the per-identity UI JSON file, then requests the existing manual Profile V2 reload acknowledgement.

## Verified contracts and projections

- `profile_v2_autoload` and `profile_v2_auto_reload_on_change` are present in Lua normalization defaults/ownership, active-config projection, Profile V2 diff canonicalization, profile ownership classification, WinForms boolean keys/labels/toggles, and the structured writer.
- Old false values are canonicalized away as optional-true fields, while true values remain durable and affect lifecycle policy.
- Runtime providers consume `_G.UC_SETTINGS` and the active-config compatibility projection; providers do not parse Profile V2 directly.
- Profile V2 writes in both Lua and WinForms use temporary-file promotion/replacement behavior and are atomic at the final path.

## Cutover constraints derived from inspection

- Preserve the current Profile V2 validator/application path and watcher state machine.
- Establish safe in-memory defaults before resolving a new identity and keep automation stopped until exact-identity resolution completes.
- Treat missing and invalid new-identity files differently from invalid edits to an already healthy identity.
- Make legacy lifecycle keys accepted but inert.
- Retain public reload/save compatibility functions, but remove normal runtime reads/writes of legacy `data/profiles` files.
- Make WinForms durable Save write only Profile V2. Per-identity editor data must come from runtime active-config state or transient working state, not `data/ui_profiles`.

