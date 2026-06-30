# Task: Wire FlyoverConfigurations reads

**Parent:** E4.5 Config-sourced fees and confirmations
**Type:** Task

## Steps
1. Replace quote-sourced fee and confirmation reads with `configurations.calculatePegInFee(amount)` and `configurations.getRequiredPegInConfirmations(amount)`.

## Done when
`forge test --match-path test/pegin/ConfigFees.t.sol` passes.
