# T3.3a — Bard song identity tracking audit

## Observed bug

- Defensive buff maintenance can be configured with multiple Bard songs from the same family, such as `Honor March|Victory March`.
- Incoming gain/effect state only reports the generic family effect, such as `March`.
- When `Honor March` is cast with `Marsyas`, the temporary loss of `Daurdabla` +song capacity can overwrite an existing song slot.
- After that overwrite, the scheduler can still see a live `March` family buff but cannot tell whether the refreshed `March` was `Honor March` or another March-family song.
- Result before this patch: maintenance could keep selecting `Honor March` again because exact song identity was lost.

## Current song maintenance behavior before patch

- `uc_hb_buff_maint.lua` normalizes Bard songs into shared families through `buff_map`.
- `uc_hb_buff_maint.choose(...)` counts live family effects with `count_existing_family_buffs(...)`.
- For multi-song Bard families, the chooser decided by family count only:
  - if live family count was below the configured need, it cast another song;
  - if live family count met the configured need, it considered the family satisfied.
- The chooser did not have a bounded exact-song success cache, so `Honor March` and `Victory March` collapsed into the same `March` family view.

## Root cause

- Exact Bard song identity was not preserved after local cast success.
- The game-reported effect layer only exposed `March`, not `Honor March` versus `Victory March`.
- The scheduler knew the intended spell name at send/success time, but that identity was not fed back into maintenance.
- Because of that, the chooser could not distinguish:
  - “one live March and it is the just-landed `Honor March`”
  - from “one live March and `Honor March` is still missing”.

## Implemented identity tracking strategy

- The scheduler now records exact Bard song identity only after confirmed local defensive spell success.
- The pending spell name already tracked by `scheduler.defensive_pending_action` is used as the intended song identity.
- On confirmed local success, `unified_scheduler.lua` calls `uc_hb_buff_maint.mark_bard_song_success(target_name, action_name, now, expires_at)`.
- `uc_hb_buff_maint.lua` stores confirmed exact-song identity per:
  - target/member name
  - song family
  - exact song name
- The cache is time-bounded with an expiry based on the existing action-duration helper.
- Interrupted or failed songs are not recorded because the identity write happens only in the defensive spell success path.

## How generic family effects map back to exact songs now

- Maintenance still uses live generic family count from the active buff list as the source of truth for how many family effects currently exist.
- Exact-song identity is only used to decide which configured same-family songs those live family slots most likely correspond to.
- The chooser clips confirmed same-family identities to the current live family count and keeps the most recent confirmed identities first.
- Example:
  - live family count is `1`
  - confirmed exact identities are `Victory March` then `Honor March`
  - maintenance treats the most recent one (`Honor March`) as the active March identity
  - it then requests `Victory March`, instead of recasting `Honor March`

## Daurdabla / Marsyas caveat

- This is still not a full song-slot simulator.
- The patch does not try to predict every slot overwrite rule caused by instrument swaps.
- Instead, it fixes the specific identity gap:
  - if `Honor March` is just confirmed successfully
  - and the game only reports a generic `March` effect
  - maintenance now treats that exact `Honor March` as satisfied until the bounded cache expires or live family count drops out from under it.

## Risks / limits

- If exact identity cannot be confirmed, maintenance falls back to the prior generic-family behavior.
- Same-family identity is inferred from recent confirmed local successes plus current live family count; it is not packet-perfect song-slot reconstruction.
- The cache is local-player success scoped and does not intentionally attribute another character’s song to the local Bard.

## Field-test instructions

1. Configure a Bard maintenance set with same-family songs, such as `Honor March|Victory March`.
2. Use a scenario where `Honor March` requires `Marsyas` while other maintained songs rely on `Daurdabla` song-capacity behavior.
3. Confirm:
   - `Honor March` lands successfully,
   - the game reports only the generic `March` effect,
   - maintenance does not immediately try to recast `Honor March`,
   - the next same-family maintenance action, if one is still needed, is `Victory March`.
4. Also confirm interruption behavior:
   - interrupt `Honor March`,
   - verify it is still eligible afterward and is not marked satisfied by the failed cast.
