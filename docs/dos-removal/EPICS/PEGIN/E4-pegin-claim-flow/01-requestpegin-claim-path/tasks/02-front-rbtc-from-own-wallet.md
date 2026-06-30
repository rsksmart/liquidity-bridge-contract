# Task: LP fronts RBTC from its own wallet

**Parent:** E4.1 requestPegIn claim path
**Type:** Task

## Steps
1. Replace the `_balances` spend with a transfer of the LP's own RBTC to the user for `amount - gasFee - callFee`.
2. Remove the claim path's dependence on `deposit()` / contract `_balances`.

## Done when
`forge test --match-path test/pegin/RequestPegIn.t.sol` asserts the user receives `amount - fees` and the LP wallet is debited, and passes.
