# Scheduler Sleep Toggle Parity

## Current issue

The scheduler path did not previously consume the existing `sleep` toggle or the legacy `sleepspell` setting. Legacy DD2 paths still owned Sleep behavior, so enabling Sleep in UnifiedCombat settings had no effect once scheduler combat ownership was active.

## Legacy DD2 Sleep behavior summary

- Legacy DD2 checks `settings.sleep` directly in `dd2_engine.lua` and `dd2_module.lua`.
- Legacy DD2 stores a single configured spell in `settings.sleepspell`.
- Legacy DD2 scans nearby mobs and only considers live `spawn_type == 16`, `status == 1`, valid-target mobs within 6 yalms.
- Legacy DD2 only considers full-HP (`hpp > 99`) candidates and picks the nearest eligible mob.
- Legacy DD2 briefly toggles `hb off` when a sleep target exists and `hb on` when none exists.
- Legacy DD2 casts by target id with `Cast_Spell_Target(settings.sleepspell, sleepid)`.

## Hard-coded and single-spell limitation

Legacy Sleep selection is effectively single-value and tied to a hard-coded `Horde Lullaby II` assumption in target eligibility checks. That makes the scheduler path unusable for jobs that need an alternate spell order, and it prevents first-available selection across multiple configured spells.

## T3.4b UI integration summary

- The real desktop UI path is the WinForms profile editor plus `remote_bridge.lua`; T3.4b wires Sleep list edits into that existing bridge-owned settings flow.
- The Sleep checkbox remains the existing `sleep` toggle.
- The UI now shows a dedicated **Sleep spells** ordered list with `Set only`, `Add`, `Remove selected`, `Clear list`, `Move up`, and `Move down`.
- The UI text explicitly calls out that the list is used for both pre-engage and in-combat Sleep picks, so Sleep remains usable while not engaged.

## Configurable Sleep boundary

- Scheduler Sleep reads the UI-owned `config.sleep.max_target_range` value for both pre-engage and engaged add-control Sleep.
- Existing profiles retain the prior `6.0`-yalm behavior when the value is missing.
- The scheduler rejects Sleep targets beyond the configured range before emitting a proposal.

## T3.4d already-slept target suppression summary

- Scheduler Sleep now suppresses repeated Sleep casts on the same target after a confirmed local combat Sleep success.
- Suppression is scoped by target id, so one already-slept mob does not block Sleep use on other eligible awake adds.
- The scheduler first prefers real enemy-effect tracking by checking configured Sleep-family status ids already present in the scheduler enemy-effect map.
- When exact live effect state is not yet present, the scheduler also uses a bounded local success cache keyed by target id.
- The local cache only marks after a confirmed local-player combat Sleep success action message; interrupted, failed, or resisted casts do not mark the target.
- The bounded local cache expires after `SLEEP_TARGET_SUPPRESSION_TIMEOUT_S = 45.0` seconds unless a real effect entry is observed or the target dies/despawns sooner.
- Death, despawn, invalid-target sweep, zoning, and known sleep-effect removal clear or ignore the bounded local suppression cache.

## T3.4e nil-helper hotfix summary

- Field testing exposed a runtime crash from a bare `p1_target_distance_to_id(...)` call inside the shared combat spell target-id dispatch path.
- Root cause: T3.4b moved spell-target helpers onto the shared `p1_combat_helpers` table, but one later combat-spell range recheck branch still referenced the old bare helper name.
- The hotfix corrects that callsite to `p1_combat_helpers.target_distance_to_id(...)`.
- No new global helper was introduced.
- The configured Sleep boundary and selected spell range checks both apply, so effective max range is `min(selected spell range, config.sleep.max_target_range)`.
- T3.4d slept-target suppression remains intact, including per-target scope, confirmed-success marking only, and bounded local suppression expiration.

## New UI-owned configurable Sleep spell list behavior

- `UnifiedCombat.lua` persists `settings.sleepspells` as an ordered list and exposes shared list helpers through `_G.UC_SleepSpell`.
- The existing `settings.sleepspell` field remains as the backward-compatible first-entry mirror.
- `remote_bridge.lua` now accepts `sleep_replace_spells`, `sleep_add_spell`, `sleep_remove_spell`, and `sleep_move_spell` so the real UI and slash commands write the same backing setting.
- `UnifiedCombatWinForms` now persists the ordered list as `sleep_spell_entries` in per-session UI profiles and pushes the full ordered list back through the bridge on Save.
- `//uc sleep list|set <spell>|add <spell>|remove <n>|move <n> up|down|clear` remains available for command-line editing.
- The scheduler does not own a hidden hard-coded Sleep list; it reads only the configured settings list.

## First-available spell selection rules

The scheduler now walks the configured Sleep spell list in order and selects the first spell that is:

- learned and usable by the current job,
- off recast,
- affordable with current MP,
- in range for the chosen target,
- and within the configured Sleep target boundary.

If the first configured spell fails any of those checks, the scheduler tries the next configured spell. If none pass, no Sleep proposal is emitted.

## Exact range rule

- A Sleep target must be at or under `config.sleep.max_target_range`.
- The selected spell must also be in its own valid cast range.
- The effective Sleep proposal range is therefore `min(selected spell cast range, configured target range)`.
- Increasing the configured range never extends a spell beyond its native cast range.

## Backward compatibility and migration

- If `settings.sleepspells` is missing or empty and legacy `settings.sleepspell` is present, the runtime treats the legacy field as a one-entry ordered list.
- Normalization deduplicates ordered entries and mirrors the first configured spell back into `settings.sleepspell`.
- Clearing the Sleep list clears both the ordered list and the legacy mirror so existing configs are not silently repopulated.
- Existing WinForms UI profiles migrate forward by creating `sleep_spell_entries` from legacy `sleepspells` or `sleepspell` when present; otherwise the UI default stays `Horde Lullaby II`.

## Scheduler implementation summary

- `unified_scheduler.lua` now builds a dedicated Sleep proposal under the `combat` provider.
- Sleep proposal collection remains behind the existing `sleep` toggle and the existing scheduler combat ownership gate.
- Sleep proposals are spell actions that use the existing combat spell command ownership seam and existing scheduler action-state blocking.
- Sleep casts now dispatch by target id without forcing a current-target hijack, so Sleep can work while not engaged and while preserving the current kill target.

## Target eligibility rules

Scheduler Sleep proposals currently require:

- live actionable mob target,
- no recent-death target,
- friendly party/alliance claim validity, or an unclaimed combat mob whose live target or recent action target is a party/alliance member,
- non-partner target,
- not the current live selected target,
- `status == 1`,
- `hpp > 99`,
- distance `<= config.sleep.max_target_range`,
- target not already marked asleep / controlled,
- in range for the selected spell.

This preserves the closest evidence-backed DD2 add-control semantics while keeping scheduler safety checks.

## Priority and ranking decision

Sleep proposals use `priority_band = 94`.

- This keeps Sleep above lower-priority maintenance and ordinary offense setup.
- This keeps Sleep below tank enmity recovery (`96`) and below defensive Cure bands (`100`/`110`).
- Sleep therefore remains timely for add control without outranking critical defensive actions.

## Movement lock behavior

Sleep uses the existing generic combat-spell scheduler prep/settle movement-stop flow:

- bounded pre-cast stop,
- bounded prep wait,
- existing spell command ownership send,
- normal scheduler movement resumption after the existing combat-spell lifecycle completes.

No new unbounded movement lock or new `run_stop` ownership path was introduced.

## Legacy `hb off` / `hb on` decision

Legacy `hb off` / `hb on` toggling was intentionally not copied.

The scheduler-owned version already runs inside scheduler proposal/action-state arbitration and does not need to toggle HealBot globally to protect the cast window. Reintroducing those direct commands would also violate the scheduler ownership direction for this slice.

## Risks

- The scheduler currently preserves DD2’s full-HP and `status == 1` gating, which may be stricter than some field situations where users expect broader Sleep use.
- Idle unclaimed mobs and unclaimed mobs fighting unrelated entities remain ineligible; only friendly-target aggression extends eligibility beyond friendly claims.
- The desktop UI remains profile-authoritative between explicit Save/reload cycles, so slash-command edits made outside the UI are not automatically redrawn into already-open list widgets until the next profile refresh.
- Existing side-effect inventory line pins need maintenance whenever shared runtime source line numbers shift.

## Validation blocker resolution

- `unified_scheduler.lua` no longer trips Lua 5.1’s top-level local limit; the added Sleep and spell-dispatch helpers now live on a shared `p1_combat_helpers` table instead of separate chunk locals.
- `selftest_side_effect_inventory.lua` needed only line-pin maintenance:
  - `UnifiedCombat.lua | windower.ffxi.run(` moved from line `354` to `355`
  - `remote_bridge.lua | windower.send_command(` moved from line `1538` to `1572`
- No new direct scheduler side-effect call expressions were introduced.

## Field-test instructions

1. Open the WinForms UI for a live session and confirm the existing `Sleep` checkbox is visible.
2. In the new **Sleep spells** list, use `Set only` or `Add` to create an ordered spell list, then use `Move up` / `Move down` to reorder if needed.
3. Save the profile from the UI so the full ordered list is pushed back through `remote_bridge.lua`.
4. Optionally verify command parity with `//uc sleep list`, `//uc sleep add <spell>`, and `//uc sleep move <n> up|down`.
5. Enable scheduler combat ownership as you normally do for local field testing.
6. Verify the scheduler emits Sleep only when a live eligible add exists.
7. Set **Eligible mob range** in the Sleep panel and Save the profile.
8. Verify a target inside the configured range can produce Sleep when a configured spell is ready.
9. Verify a target beyond the configured range does not produce Sleep even if the spell would normally cast farther.
10. Sleep target one eligible add, then verify the scheduler does not immediately spend another Sleep spell on that same slept mob while the mob remains controlled.
11. While target A remains slept, bring in target B and verify the scheduler can still spend the first available configured Sleep spell on target B.
12. Verify Sleep can still cast while not engaged and while preserving the current selected kill target without any runtime nil-helper error.
13. Verify increasing the configured range does not permit a cast beyond the selected spell's native range.
14. Verify critical Cure behavior still beats Sleep when both are possible.

## Rollback note

Rollback is localized to `UnifiedCombat.lua`, `unified_scheduler.lua`, and the new test/doc files. The runtime feature remains gated behind the existing `sleep` toggle and scheduler combat ownership gate; disabling either returns behavior to the prior no-scheduler-Sleep state.
