# UnifiedCombat Engine Feature Matrix

This matrix defines canonical behavior for the single merged engine.

Legend:
- `keep`: preserve behavior as-is
- `modernize`: preserve intent, refactor/normalize implementation
- `remove`: deprecate and migrate away

## Targeting

| Feature | melee | dd2 | Decision | Notes |
|---|---|---|---|---|
| `autotarget` nearest valid target | yes | yes | keep | one shared implementation |
| `prime` aggro/claimed fallback | yes | yes | keep | preserve parity gating |
| `partner` exclusion | yes | yes | keep | shared helper |
| `partner2` / `sub2` exclusion | yes | no | modernize | keep capability, unify behavior |
| `puller` distance gate | yes | yes | keep | one range constant |
| `hunter` unclaimed hunt mode | no | yes | modernize | move to optional target policy |
| `tank` highest HP targeting | no | yes | modernize | move to optional target policy |
| `manual` target lock semantics | yes | yes | keep | enforce deterministic lock rules |

## Weaponskills

| Feature | melee | dd2 | Decision | Notes |
|---|---|---|---|---|
| WS enable toggle | `weaponskill_active` | `weaponskill_active` | keep | same key |
| WS key storage | `ws1` | `weaponskill` | modernize | canonicalize to one key in runtime, migrate old keys |
| WS gate reason diagnostics | richer | partial | modernize | required for troubleshooting |
| WS range gate | differs | differs | modernize | standardize threshold |
| Ally TP wait logic | yes | yes | keep | shared logic |
| Silent WS fallback | previously added | mixed | remove | explicit `NO_VALID_WS` only |

## Abilities / Buffing

| Feature | melee | dd2 | Decision | Notes |
|---|---|---|---|---|
| Ordered configured abilities | yes | yes | keep | shared list semantics |
| Ability active toggle | yes | yes | keep | same key |
| Skip JA if status buff already active | partial | partial | modernize | shared generic check |
| Job-specific hardcoded JA branches | many | many | modernize | move into strategy hooks |

## Sleep / Debuff

| Feature | melee | dd2 | Decision | Notes |
|---|---|---|---|---|
| Sleep mode / sleepspell | mostly unused | implemented | modernize | keep for all jobs where valid |
| Debuff tracking map | minimal | stronger | modernize | use one shared tracker |
| Hardcoded sleep spell name assumptions | n/a | present | remove | use configured spell/resource ids |

## Pet / Summon

| Feature | melee | limited | broad dd2 | modernize | keep job hooks for BST/PUP/SMN/DRG |

## UI / Diagnostics

| Feature | melee | dd2 | Decision | Notes |
|---|---|---|---|---|
| In-game overlay status | yes | yes | keep | shared renderer gating by `show_ingame_ui` |
| Skillchain helper overlay | active | partial | modernize | unify behavior and controls |
| Explicit block reasons surfaced | partial | partial | modernize | required by project rule |

## Commands / Config

| Feature | melee | dd2 | Decision | Notes |
|---|---|---|---|---|
| Overlapping toggles (`autotarget`, `prime`, etc.) | yes | yes | keep | one handler |
| Duplicate engine-specific command variants | yes | yes | modernize | one command contract |
| Obsolete legacy aliases | present | present | remove | maintain migration map only |
