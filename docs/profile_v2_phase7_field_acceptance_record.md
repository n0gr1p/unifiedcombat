# Profile V2 Phase 7 — Live Field-Acceptance Evidence

Status: **NOT STARTED**. This is the required field-evidence record for draft PR #73, not an automated test result. Do not mark any line PASS without real FFXI observations.

## Preflight and rollback

1. Preserve a known-working `master` addon directory and back up the exact character/subjob `data/profiles_v2` files before testing. Put the PR branch in a **separate test addon copy**; do not overwrite the live installation.
2. In a safe zone, stop the engine and identify the client/session. Check addon source fingerprint with `//uc runtime` and inspect active profile using `//uc profilev2 status`. Use `//uc profilev2 diff detail` to compare the active file with runtime policy when needed.
3. Keep the active profile unchanged unless testing a planned edit. For each profile edit, record **before** and **after**, then explicitly export/save when the step requires persistence. Save is not implicit for slash-command edits.
4. Capture timestamped diagnostic files and optional action packet evidence for the test window; chat messages alone are insufficient proof. Record the exact tested PR commit and role.
5. On failure: stop the test engine, collect the diagnostic evidence, restore the original addon folder and profile backup, then restart the known-working version. Do not use destructive writes, deleted profiles, or broad multi-client reloads as troubleshooting shortcuts.

## Test manifest

| Field | Record |
| --- | --- |
| PR head SHA | PENDING |
| Addon runtime fingerprint | PENDING |
| FFXI characters/jobs tested | PENDING |
| Test addon directory and backup verified | PENDING |
| Profile V2 character/main/sub key | PENDING |
| UI build version / process | PENDING |
| Diagnostic-log directory / bundle | PENDING |
| Time window / timezone | PENDING |
| Final rollback check | PENDING |

## Staged acceptance (not yet executed)

| ID | Domain / trigger | Expected observation | Result | Evidence |
| --- | --- | --- | --- | --- |
| A01 | Startup/reload in safe zone; engine stopped | Exact canonical character/main/sub identity; no unintended action | NOT RUN | — |
| A02 | Switch character/job and reload; missing profile case | Safe defaults, separate identity, no stale previous job | NOT RUN | — |
| A03 | UI edit session A, switch to B, return to A | Session-specific values stay isolated | NOT RUN | — |
| A04 | Apply activity, explicit export/save, reload and diff | Persisted canonical values match, no transient IDs serialized | NOT RUN | — |
| A05 | `//uc fight_leader`, `//uc add_priority`, `//uc sleep` while engine stopped | Correct canonical live values and list order; explicit save retains edit | NOT RUN | — |
| B01 | Food and BRD in allowed non-city zone | Independent maintenance; song ownership and timers remain accurate | NOT RUN | — |
| B02 | COR rolls and Dia → Light Shot target change | Legal current target and packet-confirmed rolls retained | NOT RUN | — |
| B03 | GEO Indi/Geo/Entrust and staged Blaze policy edit | New policy wins; obsolete sequence releases its lane; prior spell evidence preserved | NOT RUN | — |
| B04 | SCH storms/arts, Immanence; policy edit during sequence | Old recipe cannot dispatch further; packet observations remain | NOT RUN | — |
| B05 | SMN/PUP pet control, target changes | Canonical maintenance and per-command ownership; no duplicate pet actions | NOT RUN | — |
| C01 | WHM/defensive cure/status handling and emergency reaction | Canonical thresholds, safety actions, confirmed buffs and cooldowns | NOT RUN | — |
| C02 | RUN/tank runes, Foil, no-TP facing | `config.tank.run` controls behavior even against stale flat mirror | NOT RUN | — |
| C03 | Target priority, Sleep, claimed-target recurring spells | Only configured list/claimed target can receive actions | NOT RUN | — |
| C04 | WS/skillchain and target change | Correct WS, action revalidation and sequence integrity | NOT RUN | — |
| D01 | Camp pulling and stopping automation | No stale move/engage ownership; camp return safely gated | NOT RUN | — |
| D02 | Party follow, fight leader, partner, path | Configured names re-resolve to live IDs and movement ownership | NOT RUN | — |
| D03 | Safe mid-sequence profile disable and reaction-lock completion | Retire unsent commands while preserving confirmed evidence and emergency defense | NOT RUN | — |

## Evidence requirement for each PASS

Record character, job, canonical config snapshot or exported diff, action/packet or diagnostic CSV timestamps, precise repro steps, and the successful observed outcome. CI-only test results **cannot** replace this record.

When failures occur, file one bounded regression entry per behavior: exact SHA, test ID, expected vs observed, source profile diff, reproducible setup, log window, and whether rollback succeeded. Keep Phase 7 focused on concrete defects; do not reopen open-ended scheduler audits.

## Closeout

- [ ] All critical A/C/D scenarios passed with dated evidence
- [ ] All enabled job-specific B scenarios passed (or explicitly documented as unavailable, with reviewer decision)
- [ ] No unresolved critical regression
- [ ] Known-working rollback verified
- [ ] Reviewer approves merge readiness

**No live tests have been run as part of the repository-only migration work.**
