# Task: Registrant fee payout (first peg-in only)

**Parent:** E4.3 resolvePegIn settlement
**Type:** Task

## Steps
1. On the first peg-in for an address, subtract the registrant fee from `callFee` and pay the registrant.

## Done when
`forge test --match-path test/pegin/ResolvePegIn.t.sol` covers the once-only registrant payout and passes.
