# Sleeping Party Member Waker Implementation Checklist

## Status

Implementation, automated validation, and manual in-game acceptance completed on 2026-08-09.

## Goal

Detect a sleeping, uncharmed party member and wake that player with `Cure` without waking a charmed sleeper.

## Runtime Contract

- Durable configuration is `config.defensive.sleep_waker.enabled`.
- `def_sleep_waker_enabled` is the flat runtime/UI compatibility mirror.
- The feature requires the defensive domain, Defensive master toggle, and `Sleep waker` toggle.
- Ordinary HP-based Cure enablement is independent; the waker remains available when normal Cures are disabled.
- Party scope is the local six-person party (`p0` through `p5`), not alliance members.
- Sleep is authoritative only when the local, IPC, or `0x076` party buff snapshot contains Windower buff id `2` or `19`.
- The target mob must report `charmed == false`. Missing Charm state fails closed.
- The local player, trusts/NPCs, dead members, missing mobs, and out-of-range targets are rejected.
- The provider casts only `Cure`; it does not select a fallback spell.

## Safety and Arbitration

- Proposal family: `emergency.sleep_wake.primary`.
- Priority band: `149` with urgency `1.0`; the resulting rank is immediately below critical Cure (`153` with urgency `0.70`) and above GEO maintenance, ordinary Cure, and normal combat Sleep.
- The first eligible Sleep observation is held for `0.35` seconds so Charm state can converge before a wake proposal is emitted.
- A successful dispatch starts a `2.5` second per-target attempt gate.
- Disabling the feature, Defensive master, or defensive domain, and changing zones clear observation and attempt state.
- Commit validation rechecks that the target still exists, Charm is explicitly false, and Sleep is still present.
- Internal dispatch repeats the same validation immediately before sending the command.
- Every scheduler-owned allied Cure, including ordinary internal and HealBot-originated Cures, is rejected when the current target mob reports `charmed == true`.
- Internal and HealBot proposal collection also exclude currently charmed Cure targets so a rejected Cure cannot starve unrelated proposals.

## Observability

- Defensive logs emit `SLEEP_WAKE_CANDIDATE`, `SLEEP_WAKE_ACCEPT`, `SLEEP_WAKE_REJECT`, and `SLEEP_WAKE_CLEAR` records.
- Rejection reasons include self, invalid target, charmed target, unknown Charm state, range, observation gate, attempt gate, unavailable Cure, missing buff state, and an already-awake target at commit.
- Action-timeline events include `SLEEP_WAKE_PROPOSED` and `SLEEP_WAKE_DISPATCHED`.
- The in-game overlay includes `SleepWaker:` backed by `UC_SLEEP_WAKER_STATUS`.

## Automated Acceptance

- [x] Both Windower Sleep ids `2` and `19` are recognized and resource-validated.
- [x] The toggle defaults off and disabled mode emits no proposal.
- [x] Full-HP, sleeping, uncharmed party members emit `Cure` after the observation gate.
- [x] The wake path remains independent of the ordinary Cure toggle.
- [x] Charmed targets emit no wake proposal and clear pending wake state.
- [x] Unknown Charm state fails closed.
- [x] Self Sleep never dispatches locally.
- [x] Cleared Sleep removes wake state.
- [x] The attempt gate suppresses repeated Cure spam and later permits retry if Sleep remains.
- [x] Commit validation rejects Charm appearing after proposal creation.
- [x] Commit validation rejects Sleep clearing after proposal creation.
- [x] Ordinary internal and HealBot Cure paths share the central charmed-target veto.
- [x] Structured and flat profile configuration round-trip through Lua and WinForms paths.

## Manual In-Game Acceptance

- [x] Enable `Debug`, `Log: defensive scheduler`, Defensive, and `Sleep waker`.
- [x] Disable ordinary Cures and confirm an enemy Sleep still produces `Cure` after the observation gate.
- [x] Confirm `Cure` wakes a full-HP player when the result restores zero HP.
- [x] Confirm a sleeping charmed player is never cured by internal or HealBot provider selection.
- [x] Break Charm while Sleep remains and confirm the player is cured after the observation gate.
- [x] Clear Sleep before commit and confirm dispatch is cancelled.
- [x] Confirm no duplicate Cure inside the `2.5` second attempt gate.
- [x] Repeat with buff snapshots sourced from `0x076` and from another UnifiedCombat IPC client.

## Known Boundary

Once final dispatch-time revalidation has completed, a Charm effect arriving in the remaining command-send window cannot be recalled. The observation gate and proposal/commit/dispatch revalidation minimize this unavoidable race.
