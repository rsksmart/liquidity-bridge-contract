# E1.5 Time-locked setters, change events, and immutable bounds

**Epic:** E1 FlyoverConfigurations (Foundation track)
**Type:** Enabler
**Story:** As the protocol owner, I want every configuration change time-locked and bounded, so that a parameter change cannot land mid-operation or move outside safe limits.

## Output (the deliverable)

- A time lock on every setter: a change is queued, then applied after a delay.
- The `*Changed` events from the interface, emitted on apply.
- `getPegInConfigurationBounds()` and `getPegOutConfigurationBounds()` returning the deployment-time minimum and maximum, with setters validating against them.

## Acceptance criteria

- A queued change does not take effect before the delay elapses, and does take effect after.
- Each apply emits the matching `*Changed` event with old and new values.
- A setter rejects a value outside the immutable bounds.
- The bounds are set at deployment and cannot be changed afterward.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal "Clarifications on diagrams": changes in the configuration should be time-locked to avoid messing with the economics of a peg-in or peg-out in the middle of the operation. Proposal `IFlyoverConfigurations` events (`PegInFixedFeeChanged`, `PegInLimitsChanged`, and the peg-out equivalents) and the immutable `getPegInConfigurationBounds` / `getPegOutConfigurationBounds`. LBC map: current setters (`setDustThreshold`, `setMinPegIn`) apply immediately, so the time lock is new.

## Depends on (within E1)

E1.2, E1.3, E1.4 (the setters cover the fields those add).

**Estimate:** 5. **Labels:** enabler, P0, lbc.
