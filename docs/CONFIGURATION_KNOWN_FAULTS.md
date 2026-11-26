# Known configuration faults

This document lists configuration changes that can harm users or liquidity providers (LPs), and the check to do before each one. Every fault here was found in review or in the code and is marked WONTFIX: the team chose an operational rule instead of a code change, for the reason given.

All peg-in values live in `FlyoverConfigurations` and change in two steps: `queueChange`, then `applyChange` after the timelock delay. The delay makes every change public before it applies, so the checks below can be done in that time.

## Before every change

1. Read the pending change with `getPendingChange` and confirm it is the one that was reviewed (fault 6).
2. For each changed field, find it in the table and do its check.
3. Repeat the checks just before `applyChange`, against the deposits pending at that moment.

| Field changed                                      | Faults  |
| -------------------------------------------------- | ------- |
| `minAmount` (lower)                                | 1, 4, 5 |
| `maxAmount` (lower)                                | 4       |
| `fixedFee`, `percentageFee`, `claimGasFee` (raise) | 4       |
| `maxCallGas` (raise)                               | 1, 4    |
| `confirmationTiers`                                | 2, 3    |
| `claimWindow` (shorter), `penaltyFee` (higher)     | 2       |
| `registrantFee`                                    | 7       |
| any (a second `queueChange`)                       | 6       |

Peg-out is not affected by these faults: `PegOutEscrow` copies the fee, the confirmations and the windows into each request when it is made, so a later change does not reach it.

Peg-in cannot copy the values the same way. The user's BTC deposit is the only commitment, and the contract first sees it when an LP calls `requestPegIn` or someone calls `resolvePegIn`, so an unclaimed deposit has no record on Rootstock to copy the values into. Registration happens once per address, not per deposit, so copying there would tie every future deposit to that address to old values. A claim does copy its fees: `requestPegIn` stores `feeAtClaim` and `gasFeeAtClaim`, so a fee change does not affect a claimed deposit.

## 1. Loosening a deposit rule makes old deposits slashable at once

**What happens.** When nobody claims a deposit, `resolvePegIn` slashes the peg-in LPs only if they could have claimed it. It checks the deposit against the deposit rules of the configuration active at settlement, but it counts the claim window from the deposit's own confirmation (or registration) time. A deposit that the old rules rejected can pass the new rules with its claim window already over. Anyone can then settle it, and all peg-in LPs are slashed although they never had a chance to claim it.

**Example.** `maxCallGas` is 0, so every deposit with an OP_RETURN is rejected. A user makes such a deposit and does not settle it. Ten days later governance raises `maxCallGas`. Right after the change, the user settles the old deposit, and the LPs are slashed. The same happens when `minAmount` is lowered.

Lowering a fee does not cause this fault. The configuration rules make every deposit of at least `minAmount` cover its fees, so no valid configuration rejects a deposit for its fees.

**Status.** WONTFIX. Fixing it needs a record of when each rule changed, read by the slash check. Configuration changes are rare and public in advance, so the check below covers it.

**Check.** Find the unsettled deposits to registered addresses that the new values make claimable, and settle them under the old rules before `applyChange`. Pending deposits are not stored on-chain until they are settled, so this needs a scan of Bitcoin.

A pause does not replace this step. A soft pause still allows settlement. A hard pause blocks settlement only while it lasts, and it extends a claim window by the pause length, so a window that had already ended stays ended after the pause.

Sources: [#596](https://github.com/rsksmart/liquidity-bridge-contract/pull/596#discussion_r4625436229), [#598](https://github.com/rsksmart/liquidity-bridge-contract/pull/598#discussion_r4663326177).

## 2. Window and penalty values are read at settlement

**What happens.** The slash check reads `claimWindow`, `penaltyFee` and `confirmationTiers` from the configuration active at settlement. A shorter `claimWindow`, or a lower confirmation count in a tier, shortens the time LPs have for deposits already in flight. A higher `penaltyFee` raises the penalty for them.

**Status.** WONTFIX, for the same reason as fault 1.

**Check.** Confirm that no pending deposit loses its claim window, or gets a higher penalty than LPs could expect when it arrived. Otherwise settle or wait for those deposits first.

Source: found in the code (`PegInContract._isSlashableUnclaimedPegIn`), not raised in review.

## 3. Confirmation tiers have no limits

**What happens.** `_validateTiers` checks only that the tiers are not empty and that `maxAmount` goes up. It accepts any confirmation count:

- A count at or above the bridge's own confirmation depth gives LPs no claim window: the deposit can be settled as soon as it can be claimed.
- A very large count makes `height + tier - 1` overflow in the slash check. That revert happens outside the `try`, so `resolvePegIn` fails and the user is not paid until the tiers are fixed.
- A count of 0, or counts that go down as the amount goes up, are also accepted.

**Status.** WONTFIX. The team treats tiers as an admin decision behind the timelock, and the bridge depth differs between networks.

**Check.** Every count is greater than 0, does not go down as the amount goes up, and stays below the bridge's confirmation depth on that network.

Sources: [#509](https://github.com/rsksmart/liquidity-bridge-contract/pull/509#pullrequestreview-4732477456), [#586](https://github.com/rsksmart/liquidity-bridge-contract/pull/586#discussion_r4515077041), [#596](https://github.com/rsksmart/liquidity-bridge-contract/pull/596#discussion_r4625436190).

## 4. `maxCallGas` too high for what LPs can front or send

`maxCallGas` is the configured upper limit for the `maxGasLimit` that a deposit's OP_RETURN requests.

**What happens.** The call gas fee is `(maxGasLimit + 2300) * gasPrice`, where 2,300 is the gas that Rootstock adds when a call sends RBTC. `gasPrice` is `tx.gasprice`, capped at `maxGasPriceAboveBaseFee` above `block.basefee`. A plain payment to `rskAddr` also pays a fee, for 2,300 + 2,300 gas. The fee must fit in the amount that is left after the fee and `claimGasFee`. If it does not fit, `requestPegIn` reverts with `CallGasFeeTooHigh`, and no LP can claim the deposit. The same happens when `maxGasLimit` is more gas than a Rootstock block can hold. In both cases the deposit rules still accept the deposit, so its unclaimed settlement slashes the LPs.

The fault can appear without any change to `maxCallGas`. Raising a fee, or lowering `maxAmount` or `minAmount`, makes the amount left after these fees smaller, so the same call gas fee can become larger than it.

**Example.** `minAmount` is 0.005 RBTC and the fixed fee is 0.00499999 RBTC, so 1 satoshi is left after the fee. A 500,000-gas call at 0.06 gwei costs about 3,000 satoshi. A plain payment, 4,600 gas, costs about 28 satoshi, so it also reverts.

**Status.** WONTFIX. An on-chain check needs a gas-price floor in the configuration, because miners set the Rootstock minimum gas price and it can change.

**Check.** Do this check for every change to `maxCallGas`, `maxGasPriceAboveBaseFee`, a fee, `minAmount` or `maxAmount`:

1. Calculate the largest gas fee: `(maxCallGas + 2300) * Rootstock minimum gas price * (10,000 + maxGasPriceAboveBaseFee) / 10,000`.
2. Calculate what is left of the smallest deposit: `minAmount - fee - claimGasFee`.
3. Make sure that the result of step 1 is much smaller than the result of step 2. Miners can raise the minimum gas price, so keep a margin.
4. Make sure that `maxCallGas` is much smaller than the Rootstock block gas limit of 10,000,000 gas.

Source: [#600](https://github.com/rsksmart/liquidity-bridge-contract/pull/600#discussion_r4664303476).

## 5. `minAmount` below a bridge minimum

**What happens.** Two contracts each hold their own copy of the bridge minimum:

- `PegInContract` holds it as an immutable value (`getBridgeMinDepositSats()`). `requestPegIn` rejects any deposit output below it.
- `PegInAddressRegistry` stores its own copy, set when the registry is initialized. Registration reverts with `ConfigMinBelowBridge` when `minAmount` is below that copy.

This gives two cases:

- **`minAmount` is below the registry's copy.** Every registration fails, even for large deposits.
- **The registry's copy is lower than `PegInContract`'s, and `minAmount` is between them.** The registry accepts registration deposits that `requestPegIn` then rejects.

**Status.** WONTFIX. A change of the bridge minimum ships as one release that updates `FlyoverConfigurations`, the registry and `PegInContract` together.

**Check.** The two copies are equal, and `minAmount` is at least that value in wei. Both copies are in satoshis and `minAmount` is in wei, so multiply by 10^10 (1 satoshi = 10^10 wei, `Flyover.SAT_TO_WEI_CONVERSION`). Read the registry's copy from its current storage: the admin can change it after deployment with `setMinDepositSats`, so the deployment value is current only together with every later `MinDepositSatsSet` event. No getter returns it: `getMinDepositSats()` returns `minAmount` and reverts in the first case.

Source: [#581](https://github.com/rsksmart/liquidity-bridge-contract/pull/581#discussion_r4411226861).

## 6. A second `queueChange` replaces the pending one

**What happens.** `queueChange` overwrites the pending configuration and restarts the delay, with no warning. The same holds for `queueBoundsChange`. A change applied after a later queue may not be the one that was reviewed.

**Status.** WONTFIX here. Who may queue and apply changes is a separate access-control change.

**Check.** Before `applyChange`, read `getPendingChange` and compare it with the reviewed values.

Source: [#519](https://github.com/rsksmart/liquidity-bridge-contract/pull/519#issuecomment-5294507854).

## 7. `registrantFee` is read at settlement

**What happens.** Settlement pays the registrant `min(registrantFee, feeAtClaim)`, with `registrantFee` from the configuration active at settlement. A change therefore also applies to claims already made, within the fee those claims recorded.

**Status.** WONTFIX. The fee is capped by what each claim recorded, so a change cannot take more than the LP was charged.

**Check.** Confirm that the new value is intended for claims that are not settled yet.

Source: found in the code (`PegInContract._payRegistrantOnce`), not raised in review.
