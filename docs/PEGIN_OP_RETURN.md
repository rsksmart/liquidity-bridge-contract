# Peg-in OP_RETURN

This document records the layout of the OP_RETURN output that a BTC deposit can carry to ask for a contract call, and how `BtcTransactionReader` reads it. The SDK builds this output and the LPS parses it, so both must follow this layout.

An OP_RETURN output is a Bitcoin output whose script starts with `0x6a`. It can never be spent, so it only carries data.

The user must sign the deposit with `SIGHASH_ALL`, the default in wallets. Then the signature covers every output, so nobody can change the OP_RETURN after the user signs. Other signature types do not give this guarantee: `SIGHASH_NONE` covers no output, and `SIGHASH_SINGLE` covers only the output at the same index as the input. The SDK must build the deposit with `SIGHASH_ALL`.

## Layout

The OP_RETURN pushes one payload:

| Offset | Size | Field          | Value                                         |
| ------ | ---- | -------------- | --------------------------------------------- |
| 0      | 1    | `magic`        | `0xF0`                                        |
| 1      | 1    | `version`      | `1`                                           |
| 2      | 20   | `destContract` | The RSK address to call; not the zero address |
| 22     | 4    | `maxGasLimit`  | `uint32`, big-endian: the gas for the call    |
| 26     | any  | `callData`     | The data for the call; can be empty           |

The fixed part is 26 bytes (`BtcTransactionReader.FLYOVER_CALL_DATA_OFFSET`). With only an address and no call data, the payload is exactly 26 bytes.

Example script for a 26-byte payload: `6a 1a f0 01 <20-byte destContract> <4-byte maxGasLimit>`. Here `0x1a` is the push opcode: "26 bytes follow".

## Rules

1. **Only the first OP_RETURN output is read.** It can be at any position in the transaction, because the user's wallet chooses the output order. Any later OP_RETURN output is ignored.
2. **The script must be OP_RETURN followed by exactly one push.** The push is either a direct push (`0x01`–`0x4b`, where the opcode is the data length) or `OP_PUSHDATA1` (`0x4c` followed by a 1-byte length). The pushed length must end exactly at the end of the script. Any other script is `BadPush`: a bare OP_RETURN, `OP_0`, `OP_PUSHDATA2`, `OP_PUSHDATA4`, a second push, or a wrong length. So the payload is at most 255 bytes, and `callData` at most 229 bytes.
3. **The payload must have a valid header.** `BtcTransactionReader.readFlyoverOpReturn` checks, in this order, and returns the first fault:

   | Fault             | When                                 |
   | ----------------- | ------------------------------------ |
   | `BadPush`         | Rule 2 fails                         |
   | `TooShort`        | The payload is shorter than 26 bytes |
   | `WrongMagic`      | The first byte is not `0xF0`         |
   | `WrongVersion`    | The second byte is not `1`           |
   | `ZeroDestination` | `destContract` is the zero address   |

4. **Any first OP_RETURN counts as a Flyover OP_RETURN.** An OP_RETURN from another protocol, such as the bridge's own `RSKT` format, usually returns `WrongMagic`.
5. **The reader does not check the range of `maxGasLimit`.** The allowed range is a contract rule, so `PegInContract` checks it.

## Why the first OP_RETURN, and not a fixed position

Peg-out reads its OP_RETURN at a fixed position (output 1), because the LP builds that transaction itself. A peg-in deposit is built by the user's wallet, which decides the output order. Some wallets sort outputs (BIP69), so the position can change between transactions. Reading the first OP_RETURN, wherever it is, works with any wallet.

## Why the push opcode is checked

In a Bitcoin script, a push opcode states how many bytes follow. `BtcUtils.parseNullDataScript` removes only the `0x6a` byte, so the push opcode would be read as the first payload byte, and every valid payload would fail the magic check. The reader strips the push opcode first and accepts only the two push forms a payload of up to 255 bytes needs.

## The contract call

`requestPegIn` checks the payload with the deposit rules, then makes the call. Without an OP_RETURN, nothing changes: the LP pays `rskAddr`.

1. **`maxGasLimit` must be greater than 0 and at most `PegInConfiguration.maxCallGas`.** Otherwise `requestPegIn` reverts with `CallGasOutOfRange`. `maxCallGas = 0` turns contract calls off.
2. **The call gets `maxGasLimit` gas.** The LP cannot change it. When the call sends value, Rootstock adds a 2,300-gas stipend on top; the LP pays for that extra gas, not the user. If the LP's transaction has too little gas left to forward all of it, `requestPegIn` reverts with `InsufficientCallGas`, and the LP can retry with more gas.
3. **The user pays `callGasFee = maxGasLimit * tx.gasprice`.** This is the gas forwarded, not the gas used, because the value sent must be fixed before the call. If `callGasFee` is more than the amount the LP fronts, `requestPegIn` reverts with `CallGasFeeTooHigh`.
4. **The destination receives `netToUser = expected - callGasFee`**, where `expected` is what the LP fronts without a call. The LP gets the unforwarded `callGasFee` back in its balance at once, and is repaid the usual amount at settlement.
5. **If the call fails, the LP keeps all it fronted.** The claim is marked failed, and settlement repays the LP only its fees: the service fee, `claimGasFee` and `callGasFee`. The rest of the release goes to `rskAddr`, the refund address.
6. **An unclaimed deposit makes no call.** `resolvePegIn` pays `rskAddr`.

## Why `maxGasLimit` has limits

- **0 is rejected.** With "0 means no cap", the call would get all the gas left in the LP's transaction. The LP sets that gas limit, and the user pays for all gas forwarded, so the LP would choose the user's fee.
- **`maxCallGas` is the maximum.** A deposit that asks for more gas than an LP can send cannot be claimed. The deposit rules reject it, so its unclaimed settlement does not slash LPs. Without the maximum, one such deposit could slash all peg-in LPs.

The maximum protects LPs; the call still gets the gas the user signed. Governance must keep `maxCallGas` well below the Rootstock block gas limit, and `maxCallGas` times the minimum gas price below the smallest amount an LP fronts.

## Why an invalid OP_RETURN is not slashable

A deposit whose first OP_RETURN is invalid, or asks for gas outside `1..maxCallGas`, fails the deposit rules. LPs cannot claim it, so `resolvePegIn` does not slash them for it. The deposit still settles, and `rskAddr` gets the release.
