# E1.1 Contract scaffolding and storage

**Epic:** E1 FlyoverConfigurations (Foundation track)
**Type:** Enabler
**Story:** As an LBC engineer, I want the `FlyoverConfigurations` contract skeleton with its storage and access control, so that the fee, tier, deadline, and setter work has a place to land.

## Output (the deliverable)

- `src/FlyoverConfigurations.sol`, an upgradeable contract implementing `IFlyoverConfigurations`.
- `src/interfaces/IFlyoverConfigurations.sol`, the interface frozen in S0.2.
- The `PegConfiguration` and `ConfirmationTier` structs and the namespaced storage that holds one `PegConfiguration` for peg-in and one for peg-out.
- `script/deployment/DeployFlyoverConfigurations.s.sol`.

## Acceptance criteria

- The contract deploys and initializes once, with admin access control in place.
- Storage uses an ERC-7201 namespace, matching the existing split contracts.
- The interface matches the S0.2 freeze exactly.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal `IFlyoverConfigurations` (structs `PegConfiguration`, `ConfirmationTier`, with `percentageFee` where `10_000 = 100%`). LBC map: contracts are upgradeable (`AccessControlDefaultAdminRulesUpgradeable`, `EIP712Upgradeable`) and use ERC-7201 namespaced storage. S0.2 contract-interface freeze.

## Consumed by (downstream)

E4 (peg-in claim flow) and E7 (peg-out escrow) read this contract. The read wiring lives in those epics, not here.

## Depends on (within foundation)

S0.2 (interface freeze), S0.3 (parameter set, for default values).

**Estimate:** 3. **Labels:** enabler, P0, lbc.
