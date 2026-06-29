# Tank Run-Stop Ownership Phase Closure

## Completed sequence

- `T3.6h` promoted tank action-settle run-stop ownership default-on.
- `T3.6i` promoted tank enmity JA self run-stop ownership default-on.
- `T3.6j` promoted tank spell-settle run-stop ownership default-on.
- `T3.6k` audited local ownership flag overrides and found stale tank opt-outs.
- `T3.6l` reset `local_ownership_flags.lua` to a clean baseline.
- `T3.6m` diagnosed tank configured JA starvation as a priority-band issue.
- `T3.6o` fixed tank configured JA starvation by raising tank-mode configured JA priority to `99`.
- `T3.6p` promoted tank enmity spell self run-stop ownership default-on.
- `T3.6q` closed the tank run-stop promotion phase and audited the remaining ownership surface.

## Field-test summary

- Tank configured JAs are working again after `T3.6o`.
- Tank Cures, WS, and enmity spells still behave normally after the final tank run-stop promotion.
- The final tank-enmity spell self run-stop promotion in `T3.6p` field-tested cleanly.
- No obvious tank-side regression has surfaced after the tank-family promotion sequence.

## Current ownership baseline

| Surface | Status | Notes |
| --- | --- | --- |
| Tank action-settle run-stop | Promoted default-on | Explicit `false` opt-out and shared promoted kill switch still apply. |
| Tank enmity JA self run-stop | Promoted default-on | Explicit `false` opt-out and shared promoted kill switch still apply. |
| Tank spell-settle run-stop | Promoted default-on | Explicit `false` opt-out and shared promoted kill switch still apply. |
| Tank enmity spell target run-stop | Promoted default-on | Explicit `false` opt-out and shared promoted kill switch still apply. |
| Tank enmity spell self run-stop | Promoted default-on | Explicit `false` opt-out and shared promoted kill switch still apply. |
| Doom command / run-stop | Default-off | Emergency behavior; remains intentionally conservative. |
| Vector run | Deferred / dormant | Still not treated as live-reachable promotion work. |

## Remaining risks

- Doom still needs a separate explicit promotion plan if it is ever reconsidered.
- T3.6r confirmed Doom remains default-off, and its audit stays separate from tank closure.
- Vector run remains parked until runtime reachability is intentionally revisited.
- No tank-family run-stop seam remains on the default-off path.

## Recommended next task

- Audit the remaining non-tank ownership surface, starting with Doom and then vector only if a separate plan calls for it.
- Do not reopen tank-family promotion work unless a new field regression appears.
