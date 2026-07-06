# Task: Add the registered-LP set and registration block

**Parent:** E3.1 Registered-LP enumeration and registration block
**Type:** Task

## Inputs
- OpenZeppelin `EnumerableSet.AddressSet`; existing registration path in `CollateralManagement` / `FlyoverDiscovery`.

## Steps
1. Add an `EnumerableSet.AddressSet` of registered LPs to `CollateralManagement` storage (ERC-7201 namespace).
2. Add `mapping(address => uint256) registrationBlock`.
3. Add the LP to the set and set `registrationBlock[lp] = block.number` on the registration path; remove on resign or full withdrawal.

## Done when
`forge test --match-path test/collateral/Registry.t.sol` passes.
