# Scholar Automated Field Capture

## Purpose

The Scholar field-evidence workflow is unattended. The operator starts one Windower script and UnifiedCombat persists the complete labeled session under `data/sch_captures/`. The operator is not expected to arm, display, copy, or label individual traces.

The capture recorder itself is passive. Scholar production automation is now live; disable
`sch.enabled` in the active profile before running another manual action script so the
scheduler does not compete with that script. The recorder still never issues actions.

## Installed scripts

- `sch_capture_solo.txt`: safe solo Phase 1 action, charge, Sublimation, storm, and duration evidence. Runtime is approximately 26 minutes, dominated by the intentional Sublimation wait.
- `sch_capture_party_ranges.txt`: three Accession + Perpetuance + Regen V casts against party slots `p1`, `p2`, and `p3`. Runtime is approximately 22 minutes, dominated by two intentional Regen-expiration waits.

Repository copies live under `addons/UnifiedCombat/scripts/`. Install matching copies under `Windower/scripts/` so they are executable through `//exec`.

## Common preflight

1. Use main-job Scholar in a safe outdoor zone where spells and abilities are permitted.
2. Load and start UnifiedCombat.
3. Enable the maintenance domain and a valid Scholar profile.
4. Disable combat and defensive automation for the controlled run.
5. Begin out of combat with no target and enough inventory/equipment stability to leave the character unattended.
6. Run `//uc sch status` once and correct any job, job-point, recast, party-buff, or configuration error before starting.

The capture command fails instead of silently changing requirements when the player is not main-job SCH, the engine is stopped, the maintenance domain is disabled, the output directory cannot be created, or the capture label is invalid.

## Solo capture

Run once:

```text
//exec sch_capture_solo
```

Do not issue additional actions until the script reports completion. The script:

- opens one durable `solo_phase1` session;
- marks and records Light Arts, Addendum: White, Accession, Perpetuance, and Regen V transitions;
- records rapid shared-charge consumption followed by a fixed recovery window;
- records Sublimation activation, early release, reactivation, a long completion window, and final release;
- records all eight Storm II actions and a repeated exact storm;
- writes every changing buff, recast, party, coordinate, job-level, and job-point sample throughout the long waits;
- closes the session and prints the exact output path.

The script does not spend Tabula Rasa and does not deliberately create combat, death, or invalid-target conditions.

## Party range capture

Build a stable party with the Scholar in `p0` and valid members in `p1`, `p2`, and `p3`. Six members are preferred.

Before launching, arrange the party at staggered distances and keep everyone stationary. A useful initial layout relative to `p1` is approximately:

| Slot | Distance from `p1` |
| --- | ---: |
| `p0` | 3 yalms |
| `p2` | 6 yalms |
| `p3` | 9 yalms |
| `p4` | 12 yalms |
| `p5` | 15 yalms |

The recorder stores authoritative XYZ observations and actual action-packet recipients; these operator-facing distances are only for spreading members across the unknown boundary.

Run once:

```text
//exec sch_capture_party_ranges
```

The script performs labeled group Regen transactions targeting `p1`, `p2`, and `p3`, with ten-minute expiration/recovery windows between casts. Do not move or change party slots until it reports completion.

## Output contract

Capture files are written to:

```text
addons/UnifiedCombat/data/sch_captures/<character>_<label>_<UTC timestamp>.lua.log
```

Each line is an independently loadable Lua record beginning with `return `. Records include:

- session start/stop metadata;
- script marks;
- every changed long-running sample;
- every completed bounded raw trace;
- exact raw target/action message and parameter data;
- party coordinates and coordinate observation times;
- job level, job-point presence/value, buffs, shared recast, planner candidate, and blocker.

Writes are flushed after every record. A completed trace is associated with the current script mark. `//uc sch capture status` reports the active file, current mark, and persisted trace count.

## Operator handoff

After each script completes, provide the resulting `.lua.log` file. Offline analysis derives the evidence catalog and reports any genuinely missing live condition. Additional live work must be a focused automated runner for those missing conditions, not a manual per-action matrix.
