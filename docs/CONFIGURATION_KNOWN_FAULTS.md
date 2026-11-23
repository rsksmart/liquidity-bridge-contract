# Known configuration faults

This document lists configuration changes that can harm users or liquidity providers (LPs), and the check to do before each one. Every fault here was found in review or in the code and is marked WONTFIX: the team chose an operational rule instead of a code change, for the reason given.

All peg-in values live in `FlyoverConfigurations` and change in two steps: `queueChange`, then `applyChange` after the timelock delay. The delay makes every change public before it applies, so the checks below can be done in that time.

## Before every change

1. Read the pending change with `getPendingChange` and confirm it is the one that was reviewed (fault 6).
2. For each changed field, find it in the table and do its check.
3. Repeat the checks just before `applyChange`, against the deposits pending at that moment.

| Field changed                                      | Faults |
| -------------------------------------------------- | ------ |
| `minAmount` (lower)                                | 1, 5   |
| `fixedFee`, `percentageFee`, `claimGasFee` (lower) | 1      |
| `maxCallGas` (raise)                               | 1, 4   |
| `confirmationTiers`                                | 2, 3   |
| `claimWindow` (shorter), `penaltyFee` (higher)     | 2      |
| `registrantFee`                                    | 7      |
| any (a second `queueChange`)                       | 6      |

Peg-out is not affected by these faults: `PegOutEscrow` copies the fee, the confirmations and the windows into each request when it is made, so a later change does not reach it.

Peg-in cannot copy the values the same way. The user's BTC deposit is the only commitment, and the contract first sees it when an LP calls `requestPegIn` or someone calls `resolvePegIn`, so an unclaimed deposit has no record on Rootstock to copy the values into. Registration happens once per address, not per deposit, so copying there would tie every future deposit to that address to old values. A claim does copy its fees: `requestPegIn` stores `feeAtClaim` and `gasFeeAtClaim`, so a fee change does not affect a claimed deposit.

## 1. Loosening a deposit rule makes old deposits slashable at once

**What happens.** When nobody claims a deposit, `resolvePegIn` slashes the peg-in LPs only if they could have claimed it. It checks the deposit against the deposit rules of the configuration active at settlement, but it counts the claim window from the deposit's own confirmation (or registration) time. A deposit that the old rules rejected can pass the new rules with its claim window already over. Anyone can then settle it, and all peg-in LPs are slashed although they never had a chance to claim it.

**Example.** `maxCallGas` is 0, so every deposit with an OP_RETURN is rejected. A user makes such a deposit and does not settle it. Ten days later governance raises `maxCallGas`. Right after the change, the user settles the old deposit, and the LPs are slashed. The same happens when `minAmount` or a fee is lowered.

**Status.** WONTFIX. Fixing it needs a record of when each rule changed, read by the slash check. Configuration changes are rare and public in advance, so the check below covers it.

**Check.** Find the unsettled deposits to registered addresses that the new values make claimable. Settle them, or pause, before `applyChange`. Pending deposits are not stored on-chain until they are settled, so this needs a scan of Bitcoin.

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

**What happens.** The LP pays the call gas fee, `maxGasLimit * tx.gasprice`, out of the amount it fronts. If that fee is larger than the amount, `requestPegIn` reverts with `CallGasFeeTooHigh`, and no LP can claim the deposit. The same happens when `maxGasLimit` is more gas than a Rootstock block can hold. In both cases the deposit rules still accept the deposit, so its unclaimed settlement slashes the LPs.

**Example.** `minAmount` is 0.005 RBTC and the fixed fee is 0.00499999 RBTC, so the LP fronts 1 satoshi. A 500,000-gas call at 0.06 gwei costs about 3,000 satoshi.

**Status.** WONTFIX. An on-chain check needs a gas-price floor in the configuration, because miners set the Rootstock minimum gas price and it can change.

**Check.** `maxCallGas` times the Rootstock minimum gas price is below what an LP fronts for `minAmount` (`minAmount` minus its fee and `claimGasFee`), with a margin. `maxCallGas` is also well below the Rootstock block gas limit.

Source: [#600](https://github.com/rsksmart/liquidity-bridge-contract/pull/600#discussion_r4664303476).

## 5. `minAmount` below the bridge minimum

**What happens.** `PegInContract` holds the bridge minimum as an immutable value, and `requestPegIn` rejects any deposit output below it. `PegInAddressRegistry` checks only `minAmount`. If `minAmount` is below the bridge minimum, the registry accepts registration deposits that `requestPegIn` then rejects.

**Status.** WONTFIX. A change of the bridge minimum ships as one release that updates `FlyoverConfigurations`, the registry and `PegInContract` together.

**Check.** `minAmount` is at least `getBridgeMinDepositSats()` times 10^10.

Source: [#581](https://github.com/rsksmart/liquidity-bridge-contract/pull/581#discussion_r4411226861).

## 6. A second `queueChange` replaces the pending one

**What happens.** `queueChange` overwrites the pending configuration and restarts the delay, with no warning. The same holds for `queueBoundsChange`. A change applied after a later queue may not be the one that was reviewed.

**Status.** WONTFIX here. Who may queue and apply changes is handled in FLY-2613.

**Check.** Before `applyChange`, read `getPendingChange` and compare it with the reviewed values.

Source: [#519](https://github.com/rsksmart/liquidity-bridge-contract/pull/519#issuecomment-5294507854).

## 7. `registrantFee` is read at settlement

**What happens.** Settlement pays the registrant `min(registrantFee, feeAtClaim)`, with `registrantFee` from the configuration active at settlement. A change therefore also applies to claims already made, within the fee those claims recorded.

**Status.** WONTFIX. The fee is capped by what each claim recorded, so a change cannot take more than the LP was charged.

**Check.** Confirm that the new value is intended for claims that are not settled yet.

Source: found in the code (`PegInContract._payRegistrantOnce`), not raised in review.
