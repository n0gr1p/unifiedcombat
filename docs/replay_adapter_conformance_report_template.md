# Replay Adapter Conformance Report Template

## 1. Purpose

This document is the required template for future replay adapter conformance evidence reports.

No runtime code is changed by this document.

This document does not permit provider extraction.

This document does not create harness code.

This document is a template only.

Future adapter conformance claims must include a filled-out copy of this report.

A conformance report cannot approve runtime extraction unless all required gates pass.

## 2. Report metadata

```markdown
# Replay Adapter Conformance Report

- Report ID:
- Date:
- Author:
- Branch / commit:
- Adapter lane:
- Adapter pair:
  - Old adapter:
  - New adapter:
- Interface version:
- Fixture schema version:
- Comparator policy version:
- Side-effect guard policy version:
- Fixture set ID:
- Final decision:
  - CONFORMANCE_APPROVED
  - CONFORMANCE_REJECTED
```

## 3. Adapter metadata

```markdown
## Adapter Metadata

### Old adapter
- Adapter name:
- Adapter ID:
- Lane:
- Interface version:
- Entrypoints:
  - run(fixture, deps, options):
  - Lane-specific entrypoint:
- Implementation reference (path/module):

### New adapter
- Adapter name:
- Adapter ID:
- Lane:
- Interface version:
- Entrypoints:
  - run(fixture, deps, options):
  - Lane-specific entrypoint:
- Implementation reference (path/module):

### Shared contract confirmation
- Signature parity confirmed: PASS/FAIL
- Dependency contract parity confirmed: PASS/FAIL
- Result-shape contract parity confirmed: PASS/FAIL
- Error taxonomy parity confirmed: PASS/FAIL
```

## 4. Fixture set metadata

```markdown
## Fixture Set Metadata

- Fixture set ID:
- Lane:
- Schema version:
- Fixture source location:
- Fixture count:
- Fixture names:
  1.
  2.
  3.
- Deterministic time source (`fixture.now` / `deps.now_s`) confirmed: PASS/FAIL
- Schema validation status:
  - Passed:
  - Failed:
- Notes:
```

## 5. Checklist pass/fail matrix

```markdown
## Checklist Matrix

### Shared interface checklist (`S1`-`S10`)
| ID | Status (PASS/FAIL) | Evidence ref | Notes |
|---|---|---|---|
| S1 |  |  |  |
| S2 |  |  |  |
| S3 |  |  |  |
| S4 |  |  |  |
| S5 |  |  |  |
| S6 |  |  |  |
| S7 |  |  |  |
| S8 |  |  |  |
| S9 |  |  |  |
| S10 |  |  |  |

### Maintenance checklist (`M1`-`M10`) when lane is `maintenance`
| ID | Status (PASS/FAIL/N-A) | Evidence ref | Notes |
|---|---|---|---|
| M1 |  |  |  |
| M2 |  |  |  |
| M3 |  |  |  |
| M4 |  |  |  |
| M5 |  |  |  |
| M6 |  |  |  |
| M7 |  |  |  |
| M8 |  |  |  |
| M9 |  |  |  |
| M10 |  |  |  |

### Enemy-effect checklist (`E1`-`E10`) when lane is `enemy_effect`
| ID | Status (PASS/FAIL/N-A) | Evidence ref | Notes |
|---|---|---|---|
| E1 |  |  |  |
| E2 |  |  |  |
| E3 |  |  |  |
| E4 |  |  |  |
| E5 |  |  |  |
| E6 |  |  |  |
| E7 |  |  |  |
| E8 |  |  |  |
| E9 |  |  |  |
| E10 |  |  |  |
```

Checklist gate rule:

- Any required item marked `FAIL` rejects conformance.

## 6. Side-effect guard summary

```markdown
## Side-Effect Guard Summary

- Guard mode: strict / diagnostic
- Prohibited API attempt detected: YES/NO
- First violation (if any):
  - violation_code:
  - api:
  - fixture_name:
  - adapter_id:
  - phase:
- Count by API:
  - windower.send_command:
  - windower.ffxi.run:
  - windower.ffxi.turn:
  - uc_settarget.select_by_id:
  - windower.send_ipc_message:
  - io.open.write_or_append:
- Guard contract status: PASS/FAIL
- Notes:
```

Guard gate rule:

- Any unexpected prohibited side-effect attempt rejects conformance.

## 7. Comparator summary

```markdown
## Comparator Summary

- Comparator profile: maintenance / enemy_effect
- Compared fixtures:
  1.
  2.
  3.
- Total comparisons:
- Matches:
- Mismatches:
- First mismatch (if any):
  - fixture_name:
  - section:
  - mismatch_path:
  - reason:
  - expected:
  - actual:
- Comparator contract status: PASS/FAIL
- Notes:
```

Comparator gate rule:

- Unapproved mismatches in required strict sections reject conformance.

## 8. Failure detail section

```markdown
## Failure Details

### Failure 1
- Checklist ID:
- Failure code:
- Fixture name:
- Adapter ID:
- Lane:
- Error/message:
- Mismatch path (if comparator-related):
- Side-effect violation (if guard-related):
- Root cause hypothesis:
- Required remediation:
- Re-run required: YES/NO

### Failure 2
- Checklist ID:
- Failure code:
- Fixture name:
- Adapter ID:
- Lane:
- Error/message:
- Mismatch path (if comparator-related):
- Side-effect violation (if guard-related):
- Root cause hypothesis:
- Required remediation:
- Re-run required: YES/NO
```

Failure reporting rule:

- Preserve first failure details and do not mask with fallback behavior.

## 9. Evidence package inventory

```markdown
## Evidence Package Inventory

- Report artifact:
  - path:
  - checksum (optional):
- Fixture manifest:
  - path:
  - schema version:
- Old adapter run outputs:
  - path:
  - count:
- New adapter run outputs:
  - path:
  - count:
- Comparator outputs:
  - path:
  - count:
- Side-effect guard logs:
  - path:
  - count:
- Checklist matrix artifact:
  - path:
- Failure artifacts (if any):
  - path(s):
- Reproduction command set / runner invocation:
  - command(s):
```

Inventory rule:

- Evidence must be reproducible, deterministic, and lane-scoped.

## 10. Approval or rejection decision

```markdown
## Decision

- Final decision: CONFORMANCE_APPROVED / CONFORMANCE_REJECTED
- Decision rationale:
- Required gates status:
  - Shared interface gate (`S1`-`S10`): PASS/FAIL
  - Maintenance gate (`M1`-`M10`): PASS/FAIL/N-A
  - Enemy-effect gate (`E1`-`E10`): PASS/FAIL/N-A
  - Side-effect guard gate: PASS/FAIL
  - Comparator strict-section gate: PASS/FAIL
- Runtime extraction eligibility from this report: ELIGIBLE / NOT_ELIGIBLE
- Follow-up actions:
  1.
  2.
```

Decision rule:

- `CONFORMANCE_APPROVED` is valid only when every required gate is `PASS`.

## 11. Reviewer signoff checklist

```markdown
## Reviewer Signoff Checklist

- [ ] Report metadata is complete and unambiguous.
- [ ] Adapter metadata matches implementation under review.
- [ ] Fixture set metadata and fixture names are complete.
- [ ] Checklist matrix includes all required IDs for lane and shared gates.
- [ ] Side-effect guard summary confirms zero unexpected prohibited calls.
- [ ] Comparator summary is deterministic and path-precise.
- [ ] Failure details are complete for every failed item.
- [ ] Evidence package inventory is complete and reproducible.
- [ ] Final decision matches gate outcomes.
- [ ] Report does not claim runtime extraction approval when any required gate failed.

Reviewer:
- Name:
- Date:
- Signoff:
```

## 12. Stop conditions

This template does not permit moving:

- `p1_collect_maintenance`
- `p1_collect_enemy_buff_removal`
- `ingest_enemy_effects_from_raw_action_028`
- enemy-effect state mutators
- maintenance state mutators
- `p1_collect_proposals`
- `p1_validate_proposal`
- `p1_score`
- `p1_rank`
- `action_ready`
- `spell_ready`
- `ja_ready`
- `p1_run_dry`
- `p1_try_dark_launch_dispatch`
- `run_movement_coordinator_tick`
- any direct side-effect owner

No immediate provider extraction is allowed.

No harness runtime code is created by this task.

## 13. Template usage notes

- Create a new filled-out copy per conformance run; do not edit the base template.
- Use exact checklist IDs and failure codes from `docs/replay_adapter_conformance_checklist.md`.
- Keep all paths and fixture identifiers exact for reproducibility.
- If the run is rejected, include remediation and rerun requirements before closure.
