# HealBot Buff Maintenance Parity Spec (UC)

## Goal
Implement full functional parity with HealBot buff maintenance behavior in UnifiedCombat defensive scheduler.

Parity means UC must match HealBot behavior for:
- self buffs
- targeted ally buffs
- buff prioritization and queue arbitration
- duplicate buff families (songs/roll-like families)
- overwrite timing logic
- attempt throttles and retry behavior
- active-buff state tracking and reconciliation
- IPC-assisted state sync

## Source Audit
Primary source files reviewed:
- `healbot/HealBot_buffHandling.lua`
- `healbot/HB_Actions.lua`
- `healbot/HealBot_queues.lua`
- `healbot/data/priorities.lua`
- `healbot/HealBot.lua` (IPC behavior)

## HealBot Buff Maintenance Feature Set

## 1) Buff tracking model
- Per-target buff registry keyed by target name and action name.
- Each tracked buff entry stores:
  - resolved action resource
  - resolved buff resource
  - `maintain` flag
  - `attempted` timestamp
  - `landed` timestamp
  - overwrite metadata
- Separate per-target debuff registry with similar attempt/landed semantics.

## 2) Active buff state reconciliation
- Pulls active buffs from:
  - local API state
  - IPC updates from other loaded HealBot clients
  - packet status snapshots (including duration/endtime tokens where available)
- Reconciles tracked desired buffs against active buffs each pass.

## 3) Queue generation and arbitration
- Buff queue built from current tracked desired buffs, filtered by:
  - maintain flag
  - current active state (missing vs present)
  - overwrite mode when enabled
  - attempt throttle window
- Queue ordering uses:
  - player priority (`getPlayerPriority`)
  - buff priority (`priorities.buffs`)
  - queue comparator rules in `HealBot_queues.lua`
- Final action chooser arbitration in `HB_Actions.lua`:
  - overwrite > cure/debuff/buff interplay by priority
  - buffs can be preempted by higher-urgency cure/debuff actions

## 4) Buff priority model
- `priorities.lua` defines named buff priorities.
- Lower number = higher priority.
- Fallback/default priority used for unlisted buffs.

## 5) Targeting model
- Buffs are target-specific (`hb buff target action` semantics).
- Supports self-only and ally-targeted actions.
- Action dispatch uses resolved action metadata and readiness checks.

## 6) Readiness model
- Uses `healer:ready_to_use(action)` for both spells and JAs.
- Applies cast-range checks before action is selected.
- Applies global actor actionability checks (disabled statuses, etc.).

## 7) Attempt throttling and anti-spam
- Tracks attempt times per target+buff/debuff.
- Prevents rapid re-attempt loops.
- Retries only after throttle windows or fresh missing-state reconciliation.

## 8) Multi-buff family handling (critical)
- Tracks per-target per-buff-family cast order.
- Maintains token maps for same-family effects.
- Supports recent-gain bias.
- Reconciles token/state drift over time.

## 9) BRD overwrite behavior
- Explicit cluster overwrite model:
  - cluster songs whose remaining durations are within configured window
  - schedule overwrite before expiry using lead+safety margins
- Uses status snapshot token timing where available to estimate remaining duration.

## 10) IPC enhancement model
- Periodic IPC GET/POST exchange of `buff_ids`.
- Healer instance updates remote active buff/debuff state from IPC replies.
- Improves remote certainty vs local party snapshot-only approaches.

## 11) Debug/observability
- Detailed buff debug log stream:
  - state transitions
  - overwrite decisions
  - queue and attempt tracing
  - token map diagnostics

## UC Current State vs HealBot Parity

## Present in UC (partial)
- Basic defensive buff list (`defensive_buffs`) and toggles.
- Basic priority arbitration with cure/debuff/buff categories.
- Attempt throttles.
- IPC party state (hp/mp/buffs) cache added.
- Some song-family inference and same-name buff-id handling added.

## Missing or not-parity
- No full per-target tracked buff registry with HealBot-equivalent `landed/attempted/maintain` state model.
- No full cast-order/token reconciliation equivalent to HealBot family model.
- No parity-level BRD overwrite scheduling behavior wired to token snapshots.
- No explicit per-target buff maintenance UI/model equivalent to HealBot command model.
- No strict queue comparator parity with HealBot `ActionQueue` for buff actions.
- Debug output does not yet match HealBot-level decision trace depth.

## Parity Implementation Plan (Ordered)

## P1: Port core tracking model
- Add UC defensive tracked structures equivalent to HealBot:
  - target->buff entries with attempted/landed/maintain/action/buff metadata
  - target->debuff entries
- Use these structures as source-of-truth for maintenance decisions.

## P2: Port reconciliation pipeline
- Port/replicate HealBot-style `review_active_buffs` and reconciliation logic:
  - missing/present transitions
  - landed clearing/setting
  - stale cleanup

## P3: Port queue builder/comparators
- Build buff queue with same comparator semantics as `ActionQueue`/`compFunc.buff`.
- Preserve overwrite queue precedence behavior.

## P4: Port family/token model
- Implement per-target family cast order/token mapping parity:
  - cast order persistence
  - recent gain bias
  - nearest token matching
  - token drift reconciliation

## P5: Port BRD overwrite cluster logic
- Implement full overwrite cluster logic equivalent:
  - cluster window
  - lead/safety trigger
  - remaining-time computation

## P6: Unify dispatch/readiness parity
- Ensure action selection/dispatch readiness checks are parity-equivalent:
  - known/usable
  - range
  - can-act status
  - resource/recast checks

## P7: Observability parity
- Add structured debug traces for every buff decision stage:
  - candidate seen
  - present/missing evaluation
  - rejected reason
  - queue position
  - dispatch
  - landed confirmation

## Implementation Status (2026-05-05)
- [x] P1: Core tracking model in scheduler runtime (`maintenance_state.buffs/debuffs`, attempted/landed/seen fields).
- [x] P2: Reconciliation pipeline for present/missing + landed windows + stale prune.
- [x] P3: Queue builder/comparator implemented (overwrite precedence, then priority/value tie-breaks).
- [x] P4: Family/token model integrated (family order/tokens/recent-gain reconciliation).
- [x] P5: BRD overwrite cluster logic integrated (cluster + lead/safety windows).
- [x] P6: Dispatch/readiness parity improvements (known/usable/range/can-act/recast/mp checks, action-kind dispatch).
- [x] P7: Observability pass (BUFF_EVAL/REJECT/ACCEPT traces + queue summary signal).
- Notes:
  - Implementation is complete for this pass and ready for your single acceptance soak.
  - Remaining edge tuning (if any) will be bugfix-driven from your test outcomes.

## Acceptance Criteria (Parity Gates)
- Single self-buff (e.g. Haste) never recasts while present.
- Multi-buff list (e.g. `Honor March|Mage's Ballad III`) rotates/maintains both correctly.
- Mixed self/ally buff sets maintain per target correctly.
- BRD overwrite mode matches HealBot timing behavior.
- No cooldown spam loops.
- Decision logs explicitly explain every skip and cast.
