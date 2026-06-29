# Tank Configured JA Starvation Diagnostic

## What we confirmed

- The scheduler has two separate job-ability lanes:
  - generic configured JAs in `p1_collect_combat_ja`
  - tank-enmity JAs/spells in `p1_collect_combat_tank_enmity`
- Generic configured JAs are gated by `ability_active` and built from `ability_pipeline.collect_ordered(ctx.settings, 6)`.
- Tank-enmity actions are gated by `tank` + `autotarget`, sourced from `tank_enmity_actions`, and do not depend on `ability_active`.
- `p1_collect_proposals` evaluates `p1_collect_combat_tank_enmity(ctx, out)` before `p1_collect_combat_ja(ctx, out)`, and the tank-enmity lane uses `priority_band = 96` while generic configured JAs use `priority_band = 70`.
- `uc_new_settings_defaults()` still sets `ability_active = false`, so a clean baseline leaves the generic configured-JA lane off unless the user explicitly enables it.
- `T3.6o` raised tank-mode configured JAs to `priority_band = 99` while leaving the non-tank baseline at `70`, so the tank lane now has a fairer scheduling window without changing the DPS baseline.
- `T3.6p` promoted the remaining tank-enmity spell self run-stop seam default-on; that ownership change is separate from the configured-JA tuning.
- `T3.6q` closed the tank run-stop promotion phase without changing the configured-JA tuning.
- `T3.6s` keeps that tuning as part of the final scheduler ownership baseline.

## What that means

- Tank mode is not automatically expected to reuse the generic configured-JA lane.
- The current scheduler contract is "tank-enmity actions first, generic configured JAs only when `ability_active` is explicitly on."
- So the observed starvation is consistent with settings/priority separation, not a missing tank-specific dispatch seam.
- The tank-mode weighting fix narrows that gap without changing the ownership surface.

## Coverage gap

- Existing tank tests cover engage priority and run-stop ownership, but none assert that a tank with `ability_active = true` still competes its normal configured JAs against the separate tank-enmity lane.
- There is no focused replay/runtime proof yet for the combined case:
  - `ability_active = true`
  - configured generic JAs present
  - `tank_enmity_actions` also present
  - both lanes visible in one scheduler pass

## Current diagnosis

- Normal configured JAs are not starved by a broken scheduler-owned runtime seam.
- They are simply behind a separate, higher-priority tank-enmity lane and can also be disabled entirely by the clean `ability_active = false` baseline.
- The observed sporadic tank configured-JA behavior now looks like a priority/weighting issue, and that tuning remains intentionally deferred.
- `T3.6o` applies that tuning so the tank-mode configured-JA lane now competes in the expected window.

## Recommended next step

- Pause any tank-family ownership promotion until we confirm whether the user wants generic configured JAs enabled for tank mode, or whether the tank-enmity list is meant to be the only tank JA source.
- If we continue diagnosis, add a narrow replay/static test that proves the generic JA lane still exists and only runs when `ability_active` is on.
- Do not use this diagnosis to change tank JA priority or weighting in later ownership work unless a new regression appears.

## No runtime change

- This document records the current contract only.
- No scheduler behavior changed.
