# Task: Skip non-penalizable cases

**Parent:** E4.4 Unclaimed peg-in global slash
**Type:** Task

## Steps
1. Do not slash when the address was not registered or the amount is below the Flyover minimum.

## Done when
`forge test --match-path test/pegin/UnclaimedSlash.t.sol` covers both skip cases and passes.
