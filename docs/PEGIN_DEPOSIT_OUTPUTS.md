# Peg-in deposit outputs

This document records how `PegInContract.requestPegIn` reads a BTC deposit transaction that has one or more outputs to the deposit address. The deposit address is the address derived for the user's RSK address (`PegInDerivation.depositPkScript`).

## Rules

1. **Every output to the deposit address must be at least the bridge minimum.** If any such output is below `getBridgeMinDepositSats()`, `requestPegIn` reverts with `DepositBelowBridgeMinimum`. The error reports the smallest output.
2. **The peg-in amount is the value of the first output to the deposit address.** The other outputs to the deposit address do not add to the amount.
3. **Outputs to other addresses are not checked.** For example, a small change output does not block the peg-in.

`BtcTransactionReader.findOutputsPaying` reads all outputs in one pass and returns both values: the first one (rule 2) and the smallest one (rule 1).

## Why every output is checked

The RSK bridge checks every output, not only the first. `registerFlyoverBtcTransaction` calls `BridgeUtils.validateFlyoverPeginValue`, which calls `PegUtils.allUTXOsToFedAreAboveMinimumPeginValue` (rskj). If one output is below the minimum, the bridge rejects the whole transaction and the BTC stays locked.

`requestPegIn` pays the user before the bridge sees the transaction. If the contract checked only the first output, this transaction would pass:

| Output                    | Value (sats) |
| ------------------------- | ------------ |
| 1, to the deposit address | 530,135      |
| 2, to the deposit address | 468,269      |

The provider would pay the user for 530,135 sats. Then the bridge would reject the transaction at `resolvePegIn`, and the provider could not recover the payment.

## Why the amount is the first output

The amount is the first output so that one value per transaction is simple to read and to check. This is a deliberate choice, not a bridge rule.

The user does not lose the other outputs. If a transaction pays the deposit address twice, for example 1 BTC + 1 BTC, the provider pays the user for 1 BTC upfront. At `resolvePegIn` the bridge sends 2 BTC to the contract. The provider gets back its payment and fee, and the user gets the remaining 1 BTC.

## The registry

`PegInAddressRegistry.registerAddress` reads only the first output (`findFirstOutputPaying`) and compares it with the protocol minimum. It does not check the other outputs. No funds move at registration, and the bridge locks the BTC whether the registry accepts the transaction or not. So `requestPegIn` is the place where the check protects the provider.
