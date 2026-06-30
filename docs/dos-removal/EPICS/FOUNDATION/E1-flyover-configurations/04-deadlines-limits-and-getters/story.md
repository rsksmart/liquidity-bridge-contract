# E1.4 Deadlines, limits, and aggregate getters

**Epic:** E1 FlyoverConfigurations (Foundation track)
**Type:** Enabler
**Story:** As an LBC engineer, I want deadlines and limits in configuration with one getter per flow, so that the claim and escrow contracts read a single source.

## Output (the deliverable)

- Storage for `timeForDeposit`, `callTime`, `expireTime`, `expireBlocks`, `minAmount`, and `maxAmount` per flow.
- `getPegInConfiguration()` and `getPegOutConfiguration()` returning the full `PegConfiguration`.

## Acceptance criteria

- Each getter returns the values currently set for its flow.
- `minAmount` and `maxAmount` are exposed so the flows can validate an operation against limits.
- The open question on merging `callTime` and `expireTime` is resolved per the S0.2 freeze and reflected here.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal `IFlyoverConfigurations`: `timeForDeposit`, `callTime`, `expireTime`, `expireBlocks`, `minAmount`, `maxAmount`, `getPegInConfiguration`, `getPegOutConfiguration`, and the open question "should we consider merging callTime and expireTime". LBC map: these live per-quote today (`timeForDeposit`, `callTime`, `expireDate`, `expireBlock`).

## Depends on (within E1)

E1.1 (scaffolding), and the S0.2 decision on `callTime` versus `expireTime`.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
