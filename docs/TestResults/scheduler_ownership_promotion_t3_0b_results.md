# Scheduler Ownership Promotion Field Test Results — T3.0b

## Test Metadata

**Tester:** Peter
**Date:** 2026-06-13
**Task:** T3.0b — Promote low-risk field-tested scheduler ownership flags to default-on

## Configuration

Promoted scheduler ownership paths were tested as **default-on**.

The 11 promoted ownership flags were left unset in `local_ownership_flags.lua` so the test validated default-on behavior rather than explicit flag enablement.

Global promoted ownership kill switch remained disabled:

```lua
_G.UC_SCHED_P1_DISABLE_PROMOTED_OWNERSHIP = false
```

Movement cleanup remained enabled as part of the current stable local test build:

```lua
_G.UC_ENABLE_COMBAT_TRANSITION_MOVEMENT_ARBITRATION = true
```

No Doom, tank run-stop, combat spell settle/prep-wait run-stop, or vector-run ownership flags were enabled.

## Promoted Paths Under Test

The following scheduler ownership paths were promoted to default-on and field tested:

* target ownership
* turn ownership
* defensive internal command ownership
* internal dispatch command ownership
* maintenance COR command ownership
* combat WS command ownership
* combat JA command ownership
* combat spell command ownership
* movement coordinator cast-freeze-prep run_stop ownership
* movement coordinator pull-cast-hold run_stop ownership
* movement coordinator pull-spell-wait run_stop ownership

## Field Test Summary

The promoted default-on scheduler ownership paths were tested through the practical previously passing scenarios:

* reload / startup sanity
* target + turn behavior
* isolated command behavior
* combat command behavior
* movement-coordinator run_stop behavior
* normal play sanity including target transition, follow return, and WS kill behavior

## Observed Behavior

No observable regressions were found.

No startup freeze occurred.

No promoted ownership rollback was needed.

The global kill switch was not required.

No individual promoted flag opt-out was required.

## Result

**PASS**

## Rollback Needed

**Rollback needed:** No

## Conclusion

T3.0b promoted default-on scheduler ownership behavior passed field testing.

The 11 low-risk, field-tested scheduler ownership paths are accepted as default-on with the temporary global kill switch and per-flag false opt-outs retained for rollback safety.

No global rollback was required, and no individual promoted-path opt-out was needed during field testing.

Deferred, partially covered, Doom, tank run-stop, combat spell settle/prep-wait run-stop, and vector-run ownership paths remain outside this promotion and stay on explicit default-off policy.

## Next Recommended Action

Proceed to T3.0c.

T3.0c should document the successful promotion result and define the final policy for remaining default-off paths:

* keep Doom ownership paths default-off unless a safe replay/mock test is created,
* keep partially covered tank/combat spell run-stop paths default-off until targeted coverage exists,
* keep vector run ownership dormant/unreachable unless intentionally rewired,
* preserve the global promotion kill switch through at least one additional normal-play regression window.
