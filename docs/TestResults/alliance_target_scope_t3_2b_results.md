# Alliance Target Scope Field Test Results — T3.2b

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-14
**Task:** T3.2b — Implement alliance-aware friendly combat target scope behind a feature flag

## Feature Flag

```lua
_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE = true
```

## Scenario

Tested alliance-aware target validity with an alliance member outside the immediate party acting as claimant / victim / aggro target.

The goal was to verify that UnifiedCombat can treat alliance-related mobs as valid combat targets while preserving safety behavior for unrelated claims and dead targets.

## Expected Behavior

With alliance target scope enabled:

* mobs claimed by alliance members should be valid,
* mobs aggroed on alliance members should be valid,
* alliance victim / combat context should be considered valid where friendly combat group targeting is appropriate,
* unrelated non-party / non-alliance claims should remain invalid,
* zero-HP / recent-death targets should remain invalid,
* flag-off behavior should preserve old party-only behavior.

## Observed Behavior

All tests passed.

* Alliance claim validity worked.
* Alliance aggro / victim validity worked.
* Unrelated claim rejection still worked.
* Zero-HP / death-animation safety remained intact.
* Flag-off party-only baseline behavior remained preserved.
* No observable regressions were found.

## Result

**PASS**

## Rollback Needed

**Rollback needed:** No

## Conclusion

T3.2b successfully added alliance-aware friendly combat target scope behind `_G.UC_ENABLE_ALLIANCE_TARGET_SCOPE`.

The feature is field-validated with the flag enabled and preserves existing behavior when the flag is disabled.

## Next Recommended Action

T3.2c documentation closure is complete.

Resume the paused scheduler ownership work with `T3.1b` replay/mock coverage for the remaining default-off Doom and combat-spell `run_stop` ownership branches.
