# Task: Bootstrap scenario test

**Parent:** E3.3 Grace window config and bootstrap safety
**Type:** Task

## Steps
1. Add `test/collateral/Grace.t.sol` modeling two LPs where one is offline and the other is freshly registered (in grace), and assert the fresh LP is not slashed.

## Done when
`forge test --match-path test/collateral/Grace.t.sol` passes.
