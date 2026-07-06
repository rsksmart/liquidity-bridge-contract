# Task: Make the grace window configurable

**Parent:** E3.3 Grace window config and bootstrap safety
**Type:** Task

## Steps
1. Source `graceWindow` from configuration (or a `CollateralManagement` param) with a time-locked setter consistent with E1.5.

## Done when
`forge test --match-path test/collateral/Grace.t.sol` passes.
