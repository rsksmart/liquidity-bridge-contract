# Task: Trigger global slash on unclaimed deadline

**Parent:** E4.4 Unclaimed peg-in global slash
**Type:** Task

## Steps
1. Determine the claim deadline anchored to `registrationBlock`.
2. When a valid registered peg-in is unclaimed past the deadline, call `CollateralManagement.globalSlash`.

## Done when
`forge test --match-path test/pegin/UnclaimedSlash.t.sol` passes.
