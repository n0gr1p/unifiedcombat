# Kei encounter runtime

## Durable configuration

Kei uses the existing Profile V2 `config.encounter` domain:

```lua
encounter = {
    enabled = true,
    id = 'kei',
    kei = {
        elemental_damage = {
            dealer_name = 'Nyoo',
            water = {
                probe_spell = 'Water',
                damage_spell = 'Water III',
            },
            ice = {
                probe_spell = 'Blizzard',
                damage_spell = 'Blizzard III',
            },
            sustain_interval_s = 2.5,
            probe_timeout_s = 3.0,
        },
        fullers = {
            target_distance = 12.0,
            prearm_hpp_margin = 1.0,
        },
    },
}
```

`fullers.target_distance` is presented to `uc_reaction_runtime` as the normal generic rule `ability_window / Dancing Fullers / move_to_range`. The reaction runtime and movement coordinator retain execution ownership. A duplicate hand-authored Dancing Fullers rule is rejected by configuration normalization so two durable sources cannot disagree. Profiles written with the earlier `fullers.run_away_distance` or flat `kei_fullers_run_away_distance` name normalize to the canonical target-distance field; conflicting old and new values fail validation.

Runtime state (boss actor ID, inferred or confirmed element, pending spell correlation, hit cadence, Fullers history, and Benediction observations) is never written to the profile.

## Runtime ownership

- `uc_kei_encounter.lua` observes Kei, packet evidence, elemental state, and Fullers threshold history.
- `uc_provider_kei.lua` decides whether to propose a probe, damage spell, or cheap keepalive.
- `unified_scheduler.lua` ranks, validates, dispatches, and correlates the selected spell through its existing action economy.
- `uc_reaction_runtime.lua` owns the Dancing Fullers Ability Window lifecycle.
- The existing movement coordinator owns `move_to_range` movement under `scheduler_reaction`.

The provider sends no commands. It emits ordinary enemy-targeted `spell` proposals with target-ID dispatch explicitly allowed through the existing combat dispatcher.

Normal ranged/support formation may hold a character outside approximately 15 yalms. During Dancing Fullers, `move_to_range(12)` moves a ranged character inward or a melee character outward and keeps reevaluating Kei's live position. While the character is within 0.15 yalms of 12, physical movement stops but reaction ownership continues to suppress formation and follow. Category-11 Fullers completion releases the reaction so normal formation can resume.

## Structured action evidence

Elemental evidence uses the incoming high-level Windower action object:

- `act.category == 4` identifies a completed spell action.
- `act.actor_id` must equal the local player ID for player elemental evidence, or the bound Kei actor ID for Kei mode inference.
- `act.param` must equal the exact configured spell resource ID.
- A matching `act.targets[n].id` must equal the bound Kei actor ID for player evidence.
- Each `target.actions[n].message` resolves through `resources.action_messages`.
- A resource template containing `${target} takes ${number} points of damage` with a positive `action.param` is damage evidence.
- A resource template containing `${target} recovers ${number} HP` or `${target} recovers ${number} hit points` with a positive `action.param` is explicit absorption/healing evidence.
- Action message 16 is the scheduler's existing pinned cast-interruption result.

Zero amount, resist templates, missing targets, malformed actions, unknown messages, and timeouts are ambiguous. They do not confirm or contradict an element. Rendered chat text is not parsed.

Kei Fire-element spell completion infers Blaze Spikes and Water weakness. Kei Wind-element spell completion infers Wind Spikes and Ice weakness. Inference requires positive damage or explicit recovery evidence from the completed spell packet. A later correlated player damage result becomes authoritative confirmation; explicit recovery from the attempted element contradicts it and selects the opposite candidate.

## Scheduler priority and timing

- Deadline probes, deadline damage, and cheap keepalive spells reuse priority band 131, the existing skillchain-continuation band. Critical Cure at 153 remains higher.
- Opportunistic configured damage reuses routine offense band 70.
- Doom remains the scheduler hard prepass.
- An active reaction rejects or suppresses Kei enemy-targeted proposals.
- Fullers prearm suppresses Kei elemental proposals before the Ability Window begins; it does not move the character early.

The provider begins considering the preferred configured damage spell 1.25 seconds before the sustain deadline. At 0.5 seconds or less, the proposal uses the keepalive band. If the preferred spell is not ready, the configured cheap probe spell is proposed as the keepalive. The scheduler's existing `action_ready` implementation remains authoritative for job availability, MP, recast, and action economy.

## Fullers and Benediction

The runtime tracks 75, 50, 25, and 10 percent thresholds independently. The next threshold is consumed by actual Dancing Fullers ready/completion evidence. When the addon binds to a fight already in progress, thresholds below which Kei has already moved beyond the configured pre-arm margin are initialized as skipped so a reload cannot permanently pre-arm a past Fullers. After that one-time bind initialization, only real Dancing Fullers evidence advances threshold history. HP increases do not restore consumed thresholds, so Benediction cannot re-arm 75 after that Fullers has occurred. Benediction is recorded but does not clear confirmed elemental state.

## Existing status handling and current gaps

Existing defensive status removal already includes Curse/Cursna, Bio/Erase, Slow/Erase, and Magic Defense Down/Erase. These proposals retain scheduler ownership and are not blocked by Kei automation. Existing maintenance providers remain eligible to rebuild buffs removed by Interference after reaction ownership releases.

Current gaps:

- Amnesia is not present in the current defensive removal map.
- No new shield/skillchain or magic-burst orchestration was added.
- Diagnostics expose local-pet presence while a Fullers threshold is armed, but do not calculate pet distance or enumerate every alliance pet or GEO luopan.
- Live field validation must confirm the exact recovery action-message template emitted by Kei's elemental absorption and the observed Benediction category/resource ID. Unknown evidence fails closed until then.

Use `//uc encounter status` for boss, dealer, elemental, pending-spell, sustain deadline, Fullers, reaction, Benediction, and local-pet diagnostics.
