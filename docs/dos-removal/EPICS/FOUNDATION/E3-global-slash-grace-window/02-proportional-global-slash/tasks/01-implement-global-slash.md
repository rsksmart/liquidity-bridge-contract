# Task: Implement globalSlash

**Parent:** E3.2 Proportional global slash
**Type:** Task

## Inputs
- E3.1 set and `registrationBlock`; `graceWindow` and total-penalty from config (S0.3).

## Steps
1. Add `globalSlash(uint256 total)` gated to `COLLATERAL_SLASHER`.
2. Compute the eligible set: LPs with `block.number > registrationBlock[lp] + graceWindow`.
3. Sum eligible collateral; for each eligible LP reduce its collateral by `total * lpCollateral / sumEligible`.
4. Distribute per the existing reward and penalty split; emit `Penalized` per LP.

## Done when
`forge test --match-path test/collateral/GlobalSlash.t.sol` passes.
