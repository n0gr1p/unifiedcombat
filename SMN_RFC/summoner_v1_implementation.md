# Summoner Automation v1 — Implementation and Operations

Status: implemented through RFC phases 1–6 on the `scheduler-refactor` branch.

This document is the implementation companion to `SMN_RFC.md`. The pre-change repository findings remain in `summoner_phase1_repository_audit.md`.

## Configuration and UI

The durable profile-v2 domain is:

```lua
summoner = {
    enabled = true,
    avatar = "Ifrit",
    maintenance = {
        avatar_favor = true,
        ward = {
            enabled = true,
            actions = { "Crimson Howl", "Hastega II" },
        },
    },
    pet_combat = {
        engage_on_combat_start = true,
        offensive_action = {
            enabled = true,
            action = "Flaming Crush",
            usage = "on_cooldown",
        },
    },
}
```

The WinForms Summoner tab is always available, including while the addon is disconnected, the player is not on Summoner, and no pet exists. Its avatar, maintainable Ward, and Rage choices come from `data/summoner_capabilities.tsv`. Ward rows with empty effect lists remain cataloged but are not offered for maintained-buff rotation.

Changing the desired avatar does not replace an incompatible Ward or Rage. The stored choice remains visible, the UI diagnoses the incompatibility, and runtime suppresses only that invalid behavior.

Enabled Summoner configuration requires a supported desired avatar. A missing or unsupported avatar disables Summoner automation while leaving unrelated profile domains structurally loadable.

## Runtime architecture

### Static and configuration modules

- `uc_smn_capabilities.lua` loads and validates the shared capability catalog.
- `uc_smn_config.lua` validates the complete Summoner shape and avatar/action compatibility.
- `uc_smn_runtime.lua` provides runtime constants, flat-setting projection, buff checks, recast checks, and pet-to-target distance.

Malformed Summoner structures fail validation or normalization explicitly. Runtime does not substitute a different avatar, Ward, or Rage.

### Summoner maintenance

`uc_smn_maintenance.lua` owns:

1. Desired-avatar convergence.
2. Avatar's Favor.
3. An ordered rotation of maintained Ward effects across supported avatars.

The convergence state machine is observation-driven:

```text
No pet
  -> summon the configured avatar

Wrong pet
  -> Release the captured pet instance
  -> observe disappearance
  -> summon the configured avatar

Correct pet
  -> evaluate Favor and Ward
```

Wrong-avatar mismatch is a hard dependency. Favor, Ward, Assault, and Rage are not generated for the unintended pet, including during combat.

Summoning uses the normal spell readiness and lifecycle path. Avatar appearance can complete a pending summon. Release completes only after the captured pet disappears or is replaced.

Favor uses the normal player job-ability lifecycle and is considered satisfied when buff ID `431` is present.

Ward is self-targeted. It is eligible only when at least one effect in its configured maintained-effect set is absent, Blood Pact: Ward recast `174` is ready, and MP is sufficient. The scheduler temporarily converges on the Ward's owning avatar, then returns to the configured primary avatar. V1 does not pre-refresh.

### Shared pet-command channel

`uc_pet_commands.lua` classifies and serializes:

- Release
- Assault
- Blood Pact: Ward
- Blood Pact: Rage

`uc_pet_command_coordinator.lua` provides one serialized pet-command channel for maintenance and combat providers. Each pending command captures the identities it depends on:

- Pet server ID.
- Target server ID where applicable.
- Combat generation where applicable.
- Action and recast identity.
- Expected Ward effect where applicable.

Completion is based on runtime evidence:

- Release: captured pet disappears or changes.
- Assault: captured pet is observed targeting the captured enemy, or performs an action on it.
- Ward: every configured effect appears or the matching pet action completes. Ward recast consumption acknowledges dispatch but does not permit Release before action resolution.
- Rage: Rage recast is consumed or the matching pet action completes.

Pet disappearance, target invalidation, server failure messages, interruption, and the centralized 2.5-second watchdog resolve pending state. Failures use exponential per-command backoff starting at one second and capped at eight seconds.

Pet pending state keeps the scheduler action channel serialized but does not assert a player movement lock. Pet commands use `movement_policy = "none"` and do not stop, face, or reposition the player.

### Reusable pet combat

`uc_pet_combat_provider.lua` is the common provider. `uc_smn_pet_combat_adapter.lua` supplies Summoner-specific Assault and Rage behavior.

`uc_pet_combat_state.lua` increments combat generation when:

- A valid hostile target is established after no active combat target.
- The hostile target changes.
- Combat ends and later resumes, including against the same target.

Assault satisfaction is keyed by:

```text
combat generation + pet server ID
```

Pet status `1` is treated as observable engagement when no pet-action target has been observed. Ordinary pet melee action packets retain the last target ID for the current pet instance. When that stronger evidence exists, it determines whether the avatar is fighting the current combat target or a different target. Once satisfied, v1 does not continuously resend Assault. A new pet server ID during the same combat generation creates a new key and permits a new Assault.

Rage captures and revalidates target ID, combat generation, pet ID, desired avatar, configured action, recast, MP, and pet-to-target range immediately before dispatch. It never redirects to a replacement target.

## Scheduler priorities

Summoner's internal proposal bands preserve the RFC dependency order without overriding global emergency work:

| Behavior | Priority band |
|---|---:|
| Summon desired avatar | 120 |
| Release wrong avatar | 149 |
| Avatar's Favor | 149 |
| Ward | 148 |
| Assault | 147 |
| Rage | 146 |

Dependent actions are omitted during avatar mismatch; Release does not merely win by numeric rank.

The scheduler adds up to `9.9` urgency points to each priority band. With their configured urgencies, all Summoner pet actions rank above maximum-urgency Sleep and ordinary scheduler actions while remaining below critical cures. Doom handling remains the hard emergency prepass ahead of scheduler ranking.

Backoff is scoped to the failed command. For example, Ward backoff does not block Assault or Rage, and Assault backoff does not block Ward.

## Diagnostics

Runtime publishes compact diagnostic state in:

- `UC_SMN_MAINTENANCE_STATUS`
- `UC_SMN_PET_COMMAND_STATE`
- `UC_SMN_PET_COMBAT_STATUS`

These expose convergence state, desired/current pet identity, Favor/Ward state, the last pet-command outcome, captured identities, retry delay, combat generation, engagement satisfaction, and current Assault/Rage eligibility.

Summoner pet-command and combat identity state is cleared on zone transition.

## Verification coverage

The replay/self-test suite covers:

- Missing, disabled, malformed, valid, and incompatible configuration.
- UI/profile round trips and offline/static option ownership.
- No-pet summon, wrong-pet Release, correct-pet convergence, and correction during combat inputs.
- Favor and Ward satisfaction.
- Ward effect application/removal without pre-refresh.
- Pet command serialization, interruption, failure, timeout, and exponential backoff.
- Combat generation and per-pet engagement keys.
- Manual engagement satisfaction and no continuous Assault maintenance.
- Rage recast, MP, range, stale target, stale pet, target death, and target-generation changes.
- Cross-provider priority, serialization, and starvation behavior.
- No movement lock for pending pet commands.

Primary commands:

```text
lua tests\replay\harness\selftest_all_replay_fixtures.lua
dotnet build UnifiedCombatWinForms\UnifiedCombatWinForms.csproj --no-restore
dotnet run --project UnifiedCombatWinForms\UnifiedCombatWinForms.csproj --no-build -- --selftest-profile-v2
```

## Live-runtime validation note

Automated tests validate command generation and lifecycle handling, but they cannot reproduce a live FFXI server session. Initial in-game QA should confirm:

- Numeric target serialization for `/pet` commands in the installed Windower build.
- Observed action packet `param` values for selected Wards and Rages.
- Pet `target_index` visibility for manual Assault.
- Live failure-message coverage for range, pet-busy, and unavailable-command cases.

The coordinator also has state/recast/buff evidence and a watchdog, so packet observation is not the only completion signal.

### Live pet-target diagnostic

Use the opt-in probe to validate whether Windower exposes a usable target for an engaged avatar:

```text
//uc smn pettarget start
//uc smn pettarget status
//uc smn pettarget stop
```

Start the probe while the UnifiedCombat engine is running, let the avatar fight normally, then request status or stop it. The output distinguishes:

- nonzero raw `pet.target_index` observations;
- target IDs resolved directly through `windower.ffxi.get_mob_by_index`;
- exact pet/current-target index matches;
- samples where pet status is engaged but no target index or resolved target ID exists.

The counters reset on `start` and remain available after `stop` until the addon is reloaded or another probe is started.
When combat status is available, the command also reports the last target ID inferred from a category-1 pet melee action and whether it matches the current combat target.

The initial live probe captured 131 samples with Ifrit present. Ifrit reported engaged status in 100 samples, while `pet.target_index` remained zero and no target ID resolved in every sample. Pet-target fields are therefore diagnostic only for this Windower build; operational engagement uses pet status plus target IDs inferred from pet melee action packets.
