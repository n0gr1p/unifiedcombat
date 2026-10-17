# Profile V2 — Phase 7 Final Conformance and Live Acceptance

Status: **IN PROGRESS — planning and CI complete; live-game acceptance not yet started**  
PR: #73 (`refactor/profile-v2-single-source`)  
Entry: Phase 6 completed under five-criterion exit evidence in `docs/profile_v2_phase6_exit_assessment.md`.  
Implementation baseline: `d009155f4cb6bde3d10066f937be8d8b4a80d40b`, workflow [38986661407](https://github.com/n0gr1p/UnifiedCombat/actions/runs/38986661407) (Lua + WinForms PASS). Subsequent documentation-only commits do not change runtime code.

## Required Phase 7 deliverables

1. **Dead compatibility adapter cleanup**, limited to demonstrably unused source and obsolete source-contract tests. Do not remove supported direct/no-config caller interfaces or old engine implementations merely to reduce text markers.
2. **Architecture and README finalization** showing canonical Profile V2, transient action/session state, local WinForms translation, and bounded legacy compatibility.
3. **Full automated verification** of Lua parser/replay, contradictory-state authority tests, WinForms build and Profile V2/activity persistence after code cleanup.
4. **Live FFXI acceptance** across representative configured jobs and commands. An automated success alone is not sufficient to certify playable behavior.

## Safest verification order

- First establish a clean local worktree and back up existing character-specific Profile V2 files plus addon runtime files. Do not overwrite a known working `master` installation with the PR branch. Use a test copy of the addon directory and keep the current playable setup available as rollback.
- Confirm `//uc runtime` fingerprint, identity and profile status in a safe zone with combat/automation stopped. Check that the selected canonical profile is correct after reload, zoning and job/subjob change.
- Test profile apply, activity apply, in-game canonical command edits, explicit Profile V2 export/save, and reload before any live combat. An in-game edit modifies the **active profile**; saving is explicit, not automatic. Verify a different character/session does not inherit these changes.
- Run low-risk maintenance (food/BRD/COR/GEO) and defensive cast selection, then movement/follow/pull ownership, then combat/WS/RUN/pet/SCH action sequences. Observe both actions and diagnostic files rather than relying on in-game chat as a test log.
- Finally test mid-fight profile changes only in controlled encounters with defensive rollback available. Safety reactions, already-sent spell confirmations, cooldowns and pet/reaction evidence must survive relevant policy changes.

## Live-game acceptance matrix

| Domain | Controlled acceptance scenario | Expected behavior |
| --- | --- | --- |
| Profile identity/startup | Load, zone, switch main/subjob, load nonexistent profile | Canonical identity and defaults; no stale flat policy resurrected |
| WinForms activity profile | Edit A, switch session, edit B, apply/reconnect | Per-character isolation and canonical settings shown after reconnect |
| Save/reload | Edit active Profile V2, explicit export, reload | Same durable configuration; no transient target IDs, locks, observed buffs, or engine state serialized |
| In-game commands | `//uc fight_leader`, `//uc add_priority`, `//uc sleep` | Active canonical values change immediately; explicit export persists; legacy mirror cannot override |
| Food and BRD | Change food while songs configured; issue songs outside city gate | Food does not reset/disable BRD siblings; BRD state and observed timers consistent |
| COR | Roll maintenance and Dia→Light Shot target change | Current canonical selection and legal target; confirmed rolls/recasts retained |
| GEO | Indi/Geo/Entrust, camp placement, profile edit during Blaze sequence | New policy wins; abandoned atomic lane released; sent spell observations retained |
| SCH | Storm/arts support and Immanence chain; change recipe mid-sequence | Authorized commands only; obsolete sequence aborts without erasing skillchain evidence |
| SMN and PUP | Avatar/automaton maintenance, commands and target transitions | Canonical job config wins; pet packets, burden and cooldown history remain transient |
| Defensive support | Cure, Curaga, buff/enemy removal, Doom safety | Correct canonical enable/threshold; critical defensive actions and status observation unaffected |
| Tank/RUN | Runes, wards, Foil, no-TP facing with contradictory legacy state | Canonical RUN subdomain controls dispatch and facing; no stale flat override |
| Targeting, Sleep, recurring spells | Add priority, ignore list, Sleep order, target-claimed recurring spell | Only canonical lists and target-safety rules govern actions |
| Weapon skills and chains | Configured WS, TP gate, skillchain closer, burst | Correct configured action; policy edits invalidate obsolete proposals |
| Pull, follow and pathing | Camp pull, fight leader, partner/follow and path return | Names remain durable, IDs resolve live, session route state remains separate |
| Reaction locks and action confirmations | Disable one configured reaction/maintenance chain mid-flight | Retire future unapproved commands while preserving real confirmations and safety reactions |

## Exit gate

- [ ] Dead adapter cleanup limited to proven-unreferenced code and green tests
- [ ] Architecture docs and README reflect final normal runtime and compatibility separation
- [ ] Final-head Lua + WinForms CI green
- [ ] Controlled live-game matrix accepted, with captured evidence and zero critical regressions
- [ ] Reviewer approves PR #73 merge readiness; until then `master` remains unchanged

Failure to achieve the live matrix should create a **specific repro/bug**, not reopen endless Phase 6-style audits. The branch is not considered fully playable/merge-ready until this Phase 7 gate is completed.
