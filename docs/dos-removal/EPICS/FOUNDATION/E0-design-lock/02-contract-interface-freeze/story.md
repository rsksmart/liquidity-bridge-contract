# S0.2 Contract interface freeze

**Epic:** E0 Design lock
**Story:** As an LBC engineer, I want the three PoC interfaces signed off, so that E1, E2, and E7 build against stable signatures.

## Decisions (locked)

### callTime vs expireTime (2026-06-28)

**Decision:** keep `callTime` and `expireTime` (with `expireBlocks`) as separate fields in `PegConfiguration` for the PoC, with `expireTime` strictly later than `callTime` by an overlap buffer.

**Rationale:** they bound different parties, the LP's action deadline versus the user's refund-enable time. The gap between them is a safety margin that stops a user from refunding while an honest LP is still delivering. This mirrors the existing `pauseOverlap` logic and fits treating LPs gently.

**Tradeoff:** one extra parameter to configure and reason about, versus a single combined deadline. We accept it to preserve the buffer that prevents a refund mid-delivery. Merging is a later optimization once the timing model is proven.

## Output (the deliverable)

A markdown document `contract-interfaces.md` containing:

1. Finalized Solidity interface stubs for `IFlyoverConfigurations`, `IPegInAddressRegistry`, and `IPegOutEscrow`, scoped to what the PoC needs.
2. A header on each interface marking it PoC-frozen, with a note that later iterations may change it.
3. A reconciliation table mapping each interface to the contract that will implement it and to the current split contracts it touches.

## Acceptance criteria

- Each interface lists its functions and events with parameter and return types.
- Anything in the proposal's draft interfaces that the PoC does not need is dropped, with a one-line reason.
- The reconciliation table names how each interface sits against `PegInContract`, `PegOutContract`, `CollateralManagement`, and `FlyoverDiscovery`.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal "Suggested contracts" section, which gives draft `IPegInAddressRegistry`, `IPegOutEscrow`, and `IFlyoverConfigurations` verbatim (marked as reference, not final). Current split-contract layout mapped in LBC: `PegInContract`, `PegOutContract`, `CollateralManagement`, `FlyoverDiscovery`, `PauseRegistry` (Foundry, Solidity 0.8.25).

## Feeds

E1 (FlyoverConfigurations), E2 (PegInAddressRegistry), E7 (PegOutEscrow).

## Depends on (within E0)

S0.1 for the escrow interface, since `IPegOutEscrow` must match the state machine.

**Estimate:** 3. **Labels:** story, design, lbc.
