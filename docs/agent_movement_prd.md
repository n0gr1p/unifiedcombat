# Product Requirements Document

## Dynamic Comfort-Band Slot Movement Algorithm

**Document Status:** Draft for implementation
**Intended Consumer:** Codex GPT-5.3 implementation agent
**Purpose:** Define an MVP movement algorithm for one locally controlled agent in a distributed multi-agent system around a single moving target.

---

## 1. Overview

This document defines a deterministic movement algorithm for a local agent operating around a single moving target while up to 5 peer agents may also be positioning themselves around that same target.

There are up to 6 total agents. Each agent runs the same logic independently. No direct coordination is assumed. Each agent must reconstruct the same slot layout and the same slot assignment from shared world-state inputs.

The goal is to position the local agent at a stable location around the target while:

* staying within a valid distance band around the target
* avoiding overlap with other agents
* reducing slot churn and ring rotation
* adapting to target movement
* remaining deterministic across all agents

This is a distributed formation-positioning problem, not simple “move to target” behavior.

---

## 2. Problem Statement

The system knows:

* the local agent’s current `(x, y)` position
* the target’s current `(x, y)` position
* the current `(x, y)` positions of up to 5 peer agents
* historical position samples for the local agent, and optionally for peers and target

The target may move. The system recalculates at **5 Hz**.

The local agent must not move directly into the target. Instead, it must occupy a stable position within a valid **comfort band** around the target, where the comfort band is defined by:

* `minRange`
* `maxRange`

All agents should spread around the target rather than collapse into the same nearby space. Since agents do not explicitly communicate ownership, they must all independently compute the same formation layout and slot assignment from the same rules.

---

## 3. Goals

### Primary Goals

* Keep the local agent within the comfort band whenever feasible
* Assign the local agent a deterministic slot around the target
* Ensure agents do not converge on the same slot
* Ensure all agents independently reproduce the same slot formation and slot ownership
* Minimize unstable “musical chairs” slot switching
* Support a moving target

### Secondary Goals

* Reduce unnecessary ring rotation
* Prefer smoothness and stability over perfect mathematical optimality
* Support easy debugging and tuning
* Keep the MVP implementation simple and deterministic

---

## 4. Non-Goals

For MVP, this system does **not** need to:

* solve general obstacle avoidance
* solve map-aware pathfinding
* perform perfect collision avoidance
* communicate directly with peers
* guarantee globally optimal assignment
* support more than 6 total agents
* support multiple simultaneous targets

This is a deterministic formation slotting algorithm, not a complete navigation framework.

---

## 5. Core Concepts

### 5.1 Comfort Band

A valid position must remain between a minimum and maximum distance from the target.

A position is valid if:

```text
minRange <= distance(position, target) <= maxRange
```

This defines an annulus around the target.

### 5.2 Preferred Radius

For MVP, all slot positions are generated on a fixed radius:

```text
preferredRadius = (minRange + maxRange) / 2
```

This keeps behavior stable and avoids freeform radial drift.

### 5.3 Slot Ring

Instead of moving to arbitrary points in the comfort band, agents occupy one of a fixed set of evenly spaced slots around the target.

For a 6-agent ring:

* slot count = 6
* angular spacing = 60 degrees

### 5.4 Sticky Anchor Orientation

The slot ring orientation is not recomputed from scratch every tick based only on whichever agent happens to be slightly closest.

Instead, slot orientation is owned by a sticky **anchor agent**.

Once an anchor is established, the ring orientation remains tied to that anchor until the anchor is materially invalid.

This reduces unnecessary ring spin and formation churn.

### 5.5 Deterministic Distributed Assignment

Each agent independently:

1. reconstructs the same ring layout
2. reconstructs the same slot assignment for all agents
3. uses only its own assigned slot as its movement target

No direct peer communication is used.

---

## 6. Assumptions

* There is only one active target at a time
* Maximum total agents is 6
* All agents run the same algorithm
* All agents use the same constants and deterministic rules
* Each agent has a unique stable numeric `agentId`
* Position input is `(x, y)` only for MVP
* World-state samples are approximately synchronized across agents
* Historical position samples are available for at least the local agent

---

## 7. Inputs

### Required Inputs Per Tick

* `localAgentId`
* `localAgentPosition(x, y)`
* `targetPosition(x, y)`
* `peerAgentPositions[]`
* `minRange`
* `maxRange`

### Recommended Inputs Per Tick

* `targetPositionHistory[]`
* `agentPositionHistory[]`
* `evaluationTickNumber` or `evaluationTime`

### Derived Inputs

* `allAgents[] = self + peers`
* `distance(agent, target)`
* `preferredRadius`
* optional `targetVelocity`
* optional `agentVelocity`
* current local persistent state

---

## 8. Outputs

Per evaluation tick, the system must output:

* `desiredSlotIndex`
* `desiredSlotPosition(x, y)`
* `desiredMovementGoal(x, y)`
* optional `movementMode`

Recommended `movementMode` values:

* `DIRECT_TO_SLOT`
* `RECOVERY_TO_BAND`
* `HOLD_POSITION`
* `ARC_TO_SLOT` if later implemented

The system must also update local persistent state.

---

## 9. Local Persistent State

Each local agent must maintain:

* `anchorAgentId`
* `anchorAngle`
* `anchorInvalidTickCount`
* `assignedSlotIndex`
* `lastSlotChangeTick`
* local position history
* optional target history
* optional prior slot assignments for all agents if useful

This state is local only, but because all agents run the same logic, inferred state should generally converge.

---

## 10. Deterministic Tie-Break Policy

This policy is mandatory.

All logic in this system must be deterministic across agents. Whenever two candidates compare equal or are within the same comparison tolerance, the system must apply deterministic tie-break rules.

### Agent-Level Tie-Break Rule

If two agents are otherwise tied, the agent with the **lower numeric `agentId` wins**.

### Slot-Level Tie-Break Rule

If two candidate slots are otherwise tied for the same agent, the slot with the **lower numeric `slotIndex` wins**.

### Required Scope

This tie-break policy must be applied consistently in:

* anchor acquisition
* anchor replacement
* agent ordering for slot assignment
* any cost or score comparison between agents
* any cost or score comparison between slots
* any floating-point near-equality condition that affects selection or ordering

If a comparison chain does not fully resolve a choice, the final deciding value must be:

* `agentId` for agent selection/order
* `slotIndex` for slot selection

---

## 11. High-Level Algorithm

At each tick, the algorithm will:

1. Query current world state
2. Predict the target position if prediction is enabled
3. Validate the current anchor
4. Reacquire a new anchor if needed
5. Generate slot positions from the anchor orientation
6. Simulate assignment of all agents to all slots
7. Extract the local agent’s slot
8. Apply local slot stickiness rules
9. Compute the movement goal
10. Persist local state for next tick

---

## 12. Tick Rate

The algorithm must recalculate at:

* **5 Hz**
* one evaluation every **200 ms**

---

## 13. Target Prediction

For MVP, the implementation may either:

* use the raw current target position, or
* use a short-horizon predicted target position

Recommended formula:

```text
predictedTarget = currentTarget + targetVelocity * lookaheadTime
```

Suggested initial value:

* `lookaheadTime = 0.25 seconds`

If target velocity cannot be reliably estimated, fall back to current target position.

---

## 14. Slot Count

For MVP, one of the following approaches is acceptable:

### Preferred

Build `N` slots where `N` equals the number of active participating agents, capped at 6.

### Simpler Acceptable MVP

Always build 6 slots and only assign the agents currently present.

The implementation should make slot count configurable for later tuning.

---

## 15. Anchor Orientation

### 15.1 Purpose

The anchor defines the orientation of the slot ring around the target.

### 15.2 Anchor Angle

The anchor angle is the direction from the target to the anchor agent:

```text
anchorAngle = atan2(anchor.y - target.y, anchor.x - target.x)
```

### 15.3 Sticky Orientation Rule

Once established, the ring orientation remains tied to the current anchor until that anchor becomes materially invalid.

This means:

* the ring translates with the moving target
* the ring does **not** reorient every tick merely because a different agent becomes slightly closer

---

## 16. Anchor Acquisition

If no current valid anchor exists, a new anchor must be selected deterministically.

### Recommended Anchor Acquisition Rule

1. Prefer agents currently inside the comfort band
2. Among those, prefer the agent whose target distance is closest to `preferredRadius`
3. If still tied, prefer the lower distance to target
4. If still tied, lower numeric `agentId` wins

### Simpler Acceptable MVP Rule

1. Prefer agents currently inside the comfort band
2. Among those, choose the closest to the target
3. If tied, lower numeric `agentId` wins

The preferred version is more aligned with a stable formation.

---

## 17. Anchor Retention and Revocation

### 17.1 Anchor Retention Rule

Once acquired, the anchor remains valid while it is not materially invalid.

### 17.2 Material Invalidation Rule

An anchor is materially invalid if either:

* it has remained outside the comfort band for **5 consecutive ticks**, or
* it exceeds an emergency invalid threshold in a single tick

### 17.3 Invalid Tick Counter

Each tick:

* if anchor is inside the comfort band, set `anchorInvalidTickCount = 0`
* if anchor is outside the comfort band, increment `anchorInvalidTickCount += 1`

If:

```text
anchorInvalidTickCount >= 5
```

then revoke the anchor.

At 5 Hz, 5 consecutive ticks equals **1 second** outside the comfort band.

### 17.4 Emergency Invalidation

The anchor should be immediately revoked if it is significantly outside the band.

Suggested rule:

```text
distance < minRange - emergencyMargin
or
distance > maxRange + emergencyMargin
```

Suggested initial value:

* `emergencyMargin = configurable`
* default may be based on 10% of band width or another tuning constant

### 17.5 Anchor Reacquisition

When the current anchor is revoked, a new anchor must be selected using the deterministic anchor acquisition rule.

---

## 18. Slot Generation

Once anchor orientation is known, generate slots around the predicted target at the preferred radius.

For slot `i`:

```text
slotAngle[i] = anchorAngle + i * (2π / slotCount)
slotPosition[i] = predictedTarget + polar(preferredRadius, slotAngle[i])
```

### Requirements

* all agents must use the same angular direction convention
* all agents must use the same normalization rules
* slot indices must be deterministic
* slot 0 is always the anchor-aligned slot

---

## 19. Slot Assignment

Each agent must independently simulate the same assignment of all agents to all slots.

### 19.1 Assignment Style

Use deterministic greedy assignment for MVP.

Process:

1. build the full list of active agents
2. sort agents by deterministic priority
3. for each agent in that order:

   * score all unclaimed slots
   * assign the lowest-cost remaining slot
4. store the result for all agents
5. use the local agent’s assigned slot as the local movement target

### 19.2 Agent Priority Order

Recommended:

1. agents already assigned to a valid slot from the prior tick first
2. then ascending distance to target
3. then lower numeric `agentId`

Simpler acceptable MVP:

1. ascending distance to target
2. then lower numeric `agentId`

### 19.3 Slot Cost Function

For MVP, use:

```text
slotCost = distance(agentPosition, slotPosition) + slotSwitchPenalty
```

Where:

* `distance(agentPosition, slotPosition)` is Euclidean distance
* `slotSwitchPenalty = 0` if this slot equals that agent’s previous slot
* `slotSwitchPenalty > 0` otherwise

This favors keeping the same slot when reasonable.

### 19.4 Slot Cost Tie Resolution

If two slots have equal cost for the same agent, the lower `slotIndex` wins.

---

## 20. Local Slot Stickiness

After global slot assignment is reconstructed, the local agent should apply additional hysteresis before switching away from its current slot.

### Rule

If the current local slot is still valid and the improvement from switching is small, keep the current slot.

Suggested logic:

```text
switch only if newSlotCost < currentSlotCost - slotSwitchMargin
```

This is separate from the general `slotSwitchPenalty` and provides local churn reduction.

### Purpose

This reduces:

* unnecessary local slot flipping
* noisy reassignment from tiny cost changes
* visible movement instability

---

## 21. Movement Goal

The local agent should move toward its assigned slot, not directly toward the target.

### Core Principle

* **distance to target** is a legality constraint
* **distance to assigned slot** is the movement objective

### Movement Priority

1. if severely outside the comfort band, recover toward a valid band position
2. otherwise move toward the assigned slot
3. if already sufficiently close to the assigned slot, hold position

### Movement Modes

Recommended modes:

* `RECOVERY_TO_BAND`
* `DIRECT_TO_SLOT`
* `HOLD_POSITION`

Optional future mode:

* `ARC_TO_SLOT`

---

## 22. Recovery Behavior

If the local agent is outside the comfort band:

### If Too Far From the Target

Move inward toward the assigned slot or nearest valid ring location.

### If Too Close To the Target

Move outward away from the target toward the assigned slot direction or nearest valid ring location.

### MVP Requirement

Direct linear recovery is acceptable for MVP.

### Future Enhancement

If direct movement to the slot would cut through the inner forbidden radius, later versions may use arc movement around the target.

---

## 23. Stability Requirements

The implementation must prioritize stability over aggressive reorientation.

### Required Stability Behavior

* the ring should not rotate every tick due to tiny rank changes
* the current anchor should remain active until materially invalid
* slots should remain stable when the world state changes only slightly
* local slot switching should be visibly reduced compared to naive nearest-slot selection

---

## 24. Determinism Requirements

This implementation must be deterministic enough that multiple agents running it independently on the same snapshot should infer the same result.

### Required Deterministic Inputs

* same positions
* same constants
* same thresholds
* same tie-break rules
* same slot generation logic
* same sorting order
* same cost formulas

### Required Deterministic Outcomes

* same anchor selection
* same anchor angle
* same slot coordinates
* same agent ordering
* same slot assignment

Any equality or near-equality branch that affects these outcomes must be resolved deterministically.

---

## 25. Edge Cases

The implementation must handle the following cases.

### 25.1 Missing Anchor

If the anchor agent is missing from the current query:

* revoke anchor immediately
* reacquire a new anchor deterministically

### 25.2 No Agent Inside the Comfort Band

If no agent is currently inside the comfort band:

* choose the best fallback anchor deterministically

Recommended fallback:

1. closest to `preferredRadius`
2. if tied, lower distance to target
3. if tied, lower numeric `agentId`

### 25.3 Single Agent Only

If only the local agent is present:

* anchor acquisition trivially resolves to the local agent
* slot assignment resolves to the local slot
* movement behaves as single-agent band positioning

### 25.4 Abrupt Target Movement

If the target teleports or moves abruptly:

* prediction may be incorrect for one tick
* recompute normally on the next tick
* recovery logic should remain valid

### 25.5 Floating-Point Near Equality

If values are extremely close:

* compare with consistent tolerance if needed
* if still effectively tied, use deterministic tie-breakers

---

## 26. Observability and Debug Output

The implementation must provide debug-friendly telemetry for testing and tuning.

Recommended per-tick debug output:

* current target position
* predicted target position
* current anchor agent id
* current anchor angle
* anchor invalid tick count
* generated slot positions
* agent ordering for assignment
* assigned slot per agent
* local current slot
* local chosen slot
* local movement goal
* current movement mode

This is important for verifying convergence and tuning penalties.

---

## 27. Suggested Configurable Parameters

All tuning values should be config-driven.

Recommended config fields:

* `tickRateHz`
* `minRange`
* `maxRange`
* `preferredRadiusMode`
* `lookaheadTimeSeconds`
* `anchorInvalidTicksRequired`
* `emergencyMargin`
* `slotSwitchPenalty`
* `slotSwitchMargin`
* `slotArrivalTolerance`
* `maxAgents`
* `useTargetPrediction`

Suggested defaults:

* `tickRateHz = 5`
* `preferredRadius = (minRange + maxRange) / 2`
* `lookaheadTimeSeconds = 0.25`
* `anchorInvalidTicksRequired = 5`

---

## 28. Acceptance Criteria

The MVP implementation is acceptable if all of the following are true.

### Functional Acceptance

* the local agent does not intentionally target the target center
* the local agent selects a slot around the target
* the local agent attempts to remain within `minRange` and `maxRange`
* slot positions are deterministic given the same inputs
* the algorithm supports up to 6 agents

### Stability Acceptance

* the ring orientation does not change merely because another agent becomes slightly closer
* the anchor is retained while valid
* the anchor is revoked only after 5 consecutive invalid ticks or emergency invalidation
* slot switching is reduced relative to naive nearest-slot behavior

### Determinism Acceptance

* if agents receive the same world-state snapshot, they reconstruct the same anchor
* if agents receive the same world-state snapshot, they reconstruct the same slot layout
* if agents receive the same world-state snapshot, they reconstruct the same slot assignment
* deterministic tie-break rules are applied consistently

### Performance Acceptance

* one full evaluation completes comfortably within the 200 ms tick window
* implementation is clear and maintainable

---

## 29. Implementation Guidance

The implementation should be modular.

Recommended separable functions:

* `predictTargetPosition()`
* `isAnchorMateriallyInvalid()`
* `acquireAnchor()`
* `computeAnchorAngle()`
* `generateSlots()`
* `scoreSlotForAgent()`
* `sortAgentsForAssignment()`
* `assignSlotsGreedy()`
* `applyLocalSlotStickiness()`
* `computeMovementGoal()`

Keep functions clear and deterministic. Prioritize readability and debuggability over optimization.

---

## 30. Test Expectations

Implementation should include tests for at least the following.

### Anchor Tests

* anchor acquisition when one agent is clearly valid
* anchor acquisition with multiple equal candidates
* anchor revocation after exactly 5 consecutive invalid ticks
* emergency anchor revocation

### Slot Generation Tests

* deterministic slot generation from fixed anchor angle
* correct slot indexing
* correct preferred radius

### Assignment Tests

* deterministic greedy assignment for fixed snapshots
* deterministic agent ordering
* deterministic slot tie resolution by `slotIndex`
* deterministic agent tie resolution by `agentId`

### Stickiness Tests

* local slot retained when new slot is only slightly better
* local slot changes when improvement exceeds margin

### Movement Goal Tests

* normal move to assigned slot
* recovery when too close to target
* recovery when too far from target
* hold behavior when already at slot

---

## 31. Pseudocode

```text
onTick():
    worldState = queryWorldState()

    agents = buildAgentList(worldState)
    target = worldState.targetPosition
    predictedTarget = predictTargetPosition(target, targetHistory)

    if currentAnchor is missing:
        anchorAgent = acquireAnchor(agents, predictedTarget)
        anchorAngle = computeAnchorAngle(predictedTarget, anchorAgent)
        anchorInvalidTickCount = 0
    else:
        if isOutsideComfortBand(currentAnchor, predictedTarget, minRange, maxRange):
            anchorInvalidTickCount += 1
        else:
            anchorInvalidTickCount = 0

        if isEmergencyInvalid(currentAnchor, predictedTarget, minRange, maxRange, emergencyMargin)
           or anchorInvalidTickCount >= anchorInvalidTicksRequired:
            anchorAgent = acquireAnchor(agents, predictedTarget)
            anchorAngle = computeAnchorAngle(predictedTarget, anchorAgent)
            anchorInvalidTickCount = 0

    slotCount = determineSlotCount(agents)
    slots = generateSlots(predictedTarget, anchorAngle, preferredRadius, slotCount)

    orderedAgents = sortAgentsForAssignment(agents, priorAssignments, predictedTarget)
    assignments = assignSlotsGreedy(orderedAgents, slots, priorAssignments)

    proposedLocalSlot = assignments[localAgentId]
    finalLocalSlot = applyLocalSlotStickiness(
        localAgentId,
        proposedLocalSlot,
        priorAssignedSlot,
        slots
    )

    movementGoal = computeMovementGoal(
        localAgentPosition,
        predictedTarget,
        finalLocalSlot,
        minRange,
        maxRange
    )

    persistState(
        anchorAgentId,
        anchorAngle,
        anchorInvalidTickCount,
        finalLocalSlot
    )

    return movementGoal
```

---

## 32. Future Enhancements

These are not required for MVP.

* arc pathing around the target
* peer velocity prediction
* stronger collision prediction
* dynamic slot count based on actual participation
* multi-ring fallback when 6 agents cannot comfortably fit
* obstacle-aware movement
* confidence scoring for stale peer positions

---

## 33. Final Notes for Codex

Implement the MVP exactly as a deterministic distributed system.

Do not optimize for cleverness. Optimize for:

* determinism
* stability
* traceability
* configurability
* testability

The key implementation priorities are:

1. stable sticky anchor ownership
2. deterministic slot generation
3. deterministic slot assignment
4. explicit tie-break behavior
5. local slot stickiness
6. movement toward slot, not toward target center

This PRD is intended to be sufficient for MVP implementation without requiring further design clarification.
