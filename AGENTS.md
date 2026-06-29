# AGENTS.md — UnifiedCombat

## Project identity

UnifiedCombat is a Windower Lua addon for Final Fantasy XI. Treat this as a runtime-sensitive addon, not a general Lua application.

Primary priorities:

1. Preserve live addon behavior.
2. Keep refactors small, reversible, and reviewable.
3. Maintain Lua 5.1 / Windower compatibility.
4. Avoid broad rewrites unless explicitly requested.
5. Prefer boring, obvious code over clever abstractions.

## Runtime and compatibility constraints

* Target runtime is Windower Lua / Lua 5.1.
* Do not use Lua 5.2+ or Lua 5.3+ language features.
* Do not assume modern Lua package behavior unless already present in the project.
* Do not introduce external dependencies unless explicitly approved.
* Preserve existing public globals, command names, file names, function names, and call signatures unless the task explicitly asks to change them.
* Be careful with load order, side effects, globals, and `require` behavior.
* Do not move initialization logic casually. In this addon, require-time and load-time side effects matter.

## Architecture guidance

UnifiedCombat has both runtime addon behavior and external UI/configuration surfaces. Treat architectural direction as task-specific unless it is already established in code or explicitly stated in the prompt.

General expectations:

* Preserve existing compatibility surfaces unless the task explicitly changes them.
* Keep runtime state, durable settings, UI-owned configuration, and addon execution concerns clearly separated.
* Do not introduce new synchronization paths, bridges, file contracts, or ownership models unless the task explicitly asks for them.
* When a task involves profiles, settings, or UI/addon contracts, inspect the current implementation first and call out any assumptions before changing behavior.
* Prefer incremental migration paths over large architecture shifts.

## Refactor rules

* Prefer extracting cohesive helper modules while keeping existing callers stable.
* Preserve existing wrapper functions when callers may rely on their names or signatures.
* Thin wrappers in the original file are acceptable when they preserve compatibility.
* Do not combine unrelated refactors.
* Do not rename functions, modules, keys, commands, settings, or docs unless explicitly requested.
* Do not change behavior while “cleaning up” unless the task explicitly asks for a behavior change.
* If behavior changes are necessary, call them out clearly before or in the final summary.
* Keep module boundaries practical. Avoid creating tiny abstractions that make runtime flow harder to follow.
* Avoid speculative architecture changes.

## Scheduler-specific expectations

The scheduler is high-risk runtime code.

When working on scheduler code:

* Preserve action selection semantics unless explicitly directed otherwise.
* Preserve lock, pending, cooldown, reject-history, and action-state behavior.
* Preserve target handling and geometry behavior unless the task is specifically about those areas.
* Preserve logging/dry-run output behavior unless explicitly requested.
* Do not alter rank ordering, proposal keys, or rejection behavior casually.
* Be especially cautious around nil handling, canonicalization, split/dedupe logic, and side-effect counts.
* Prefer small module extraction or local cleanup over large scheduler rewrites.

## Documentation expectations

* Put audits, migration notes, and tracking docs under `docs/`.
* Keep docs factual and tied to inspected code.
* Mark assumptions clearly.
* Prefer checklists and concrete findings over vague summaries.
* Do not claim a migration is complete unless code inspection supports it.
* Update existing tracking docs when a task completes work already tracked there.

## Working process

Before changing files:

1. Inspect the relevant files.
2. Check current git status.
3. Identify any pre-existing dirty files.
4. Avoid overwriting user changes.
5. Keep the task scope narrow.

During changes:

* Make the smallest safe change that satisfies the task.
* Prefer local edits over broad formatting.
* Avoid unrelated cleanup.
* Keep naming consistent with nearby code.
* Follow the existing project style, even when imperfect.

After changes:

* Review the diff.
* Re-check git status.
* Verify changed Lua files when possible.
* State exactly what was and was not verified.

## Verification

Use the best available verification for the task.

Preferred checks when applicable:

* Parse changed Lua files with `luac -p` if available.
* Run any existing project test or validation command if one is clearly available.
* Use targeted grep/search to confirm wrappers, requires, or renamed references are consistent.
* For docs-only changes, verify file paths and referenced module names.

If verification cannot be run, say so directly and explain why. Do not invent test results.

## Codex output requirements

Every final Codex response for this repo must include:

1. Completed task title.
2. Git status before changes, including any pre-existing dirty files.
3. Files changed.
4. Summary of changes.
5. Verification performed.
6. Git status after changes.
7. Commit information.
8. Known risks or follow-up notes.

For commit information, include:

* Whether a commit was created.
* Commit hash, if created.
* Commit message, if created.
* Rollback command, if safe and applicable.
* If no commit was created, state: `Commit created: no`.

Do not create a commit unless the user explicitly asks for one.
Prefer `git revert <commit_hash>` as the rollback command for created commits.
Do not suggest destructive rollback commands such as `git reset --hard` unless the user explicitly asks for that strategy.

## Prompt/task handling

For simple, well-scoped edits, proceed directly.

For architecture-impacting, runtime-sensitive, or ambiguous tasks:

* Inspect first.
* Present a brief plan.
* Prefer small phases.
* Avoid large migrations in one pass.
* Call out any assumptions that affect runtime behavior.

If a task appears to belong in a fresh Codex thread rather than the current thread, say so in the final notes. Good candidates for a new thread include independent audits, new subsystems, profile/settings redesign work, or anything unrelated to the current workstream.

## Safety rails

Do not:

* Introduce new external dependencies without approval.
* Rewrite the scheduler wholesale unless explicitly requested.
* Change public command behavior silently.
* Remove compatibility wrappers without proving all callers have migrated.
* Assume UI-owned settings are runtime state.
* Assume runtime state belongs in profile files.
* Make broad formatting-only changes mixed with logic changes.
* Modify files outside the requested scope without calling it out.
