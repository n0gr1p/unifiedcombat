# UnifiedCombat Buff and Debuff Tracking Lifecycle Audit

## Scope

This audit records whether buff/debuff observation continues while the UnifiedCombat
engine is stopped. It separates tracking from proposal, dispatch, sequencing, and
movement ownership. The implementation rule is:

> Engine and domain switches gate actuation. Tracking remains active for the addon
> session and is invalidated only by an authoritative lifecycle or contradictory
> observation.

## Findings

| State | Observation source | Engine-off behavior | Invalidation | Result |
|---|---|---|---|---|
| Local player buffs and endtimes | Incoming type-9 `0x063`; `windower.ffxi.get_player().buffs` | `0x063` continues through `scheduler.on_incoming_chunk(...)`; live buffs are read when a consumer resumes | Zone, job/character change, logout/unload as appropriate | Tracking is outside actuation |
| Party-member buffs | Incoming `0x076`, with IPC used only when packet state is unavailable | `uc_party_buff_tracker.ingest(...)` continues while stopped | Zone packet resets the cache; missing evidence remains unknown | Tracking is outside actuation |
| Exact Bard song identity and duration | Serialized local cast evidence from `0x028` plus local `0x063`; confirmed recipients from action results | Engine stop now suspends controller state while preserving snapshots, owners, recipient effects, potency metadata, and dispatched-cast correlation | Zone, job/character change, K.O., logout/unload, incompatible config, or contradictory evidence | Fixed by the Bard lifecycle change |
| Corsair roll values | Raw `0x028` action data and local `0x063` buff list | `UC_COR_MAINT_OnIncomingChunk` is called from the addon incoming-chunk event regardless of engine state | Local `0x063` removes roll values no longer present; module unload ends state | Tracking is outside actuation |
| Enemy buffs/debuffs | Raw/parsed `0x028`, `0x029`, and TargetBar-derived effect catalogs | Both enemy-effect stores are updated by scheduler event handlers without an engine/domain gate | Death/removal messages, invalid/dead mob sweep, duration pruning where known, and zone clear | Tracking is outside actuation |
| General defensive friendly buffs | Current local/party buff arrays supplied to defensive collection | No durable effect ledger is required; the next enabled collection reads current buff observations | Current packet/live state is authoritative | No lifecycle move required |

## Bard pause contract

A normal engine stop preserves observation-owned state:

- local status snapshot and server-clock calibration;
- exact song owners and absolute endtimes;
- confirmed recipients and per-recipient effect state;
- Soul Voice, Troubadour, Pianissimo, dummy/final, normalization, and alignment
  metadata attached to confirmed effects;
- character/job/config identity; and
- an already-dispatched song correlation until its passive packet evidence resolves.

It clears actuation-owned state:

- scheduler action lane and Bard positioning;
- NITRO/forced-refresh and Soul Voice generation sequencing;
- Marcato and Clarion reservations;
- undispatched targeted/Pianissimo controller transactions;
- party recovery control; and
- scheduler failure state.

Resume prunes preserved local owners against the latest `0x063` snapshot. The first
normal Bard collection reconciles recipient identities against the latest party buff
observations before proposing an action.

## Evidence limitations

- `0x076` contains party buff IDs but no expiration times. Recipient duration remains
  correlated evidence from confirmed casts; it must not be recreated from a default.
- Multiple exact Bard songs may share one status ID. A bare `0x063` snapshot cannot
  reconstruct identity after the correlation ledger has been discarded.
- A manual or external song cast with no active correlation can invalidate a prior
  exact owner when its timer changes. That uncertainty is preferable to inventing an
  identity or duration. Passive identity acquisition for arbitrary manual or external
  casts is a separate feature and is not silently approximated here.
- Enemy effect durations are authoritative only where the observed catalog supplies a
  duration. Otherwise removal/death/invalid-target evidence owns cleanup.

## Regression coverage

- `selftest_brd_maintenance.lua` covers preserved ten-minute/Soul Voice metadata,
  cleared controller state, no rebuild after resume, and passive completion of a cast
  dispatched immediately before engine stop.
- `selftest_tracking_lifecycle_static.lua` guards always-on packet/action routing,
  centralized engine stop/start behavior, and full zone invalidation.
- `selftest_party_buff_tracker.lua`, enemy-effect suites, COR coverage in the replay
  harness, and the complete replay suite cover the individual consumers.
