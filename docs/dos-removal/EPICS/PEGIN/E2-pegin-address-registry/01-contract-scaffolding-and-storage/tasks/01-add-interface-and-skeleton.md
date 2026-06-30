# Task: Add the interface and contract skeleton

**Parent:** E2.1 Contract scaffolding and storage
**Type:** Task

## Inputs
- `IPegInAddressRegistry` exactly as frozen in `EPICS/FOUNDATION/E0-design-lock/outputs/contract-interfaces.md`.

## Steps
1. Add `lbc/src/interfaces/IPegInAddressRegistry.sol` with the frozen interface.
2. Add `lbc/src/PegInAddressRegistry.sol`, an upgradeable contract implementing it, with stubbed bodies (`revert NotImplemented()`), an initializer, and the admin role used by the other contracts.
3. Declare ERC-7201 namespaced storage with `mapping(address => uint256) registrationBlock`, `uint256 count`, and `bytes32 registrationRoot`.

## Done when
`forge build` compiles and `forge test --match-path test/pegin-registry/Scaffolding.t.sol` passes.
