# Peg-in OP_RETURN

This document records the layout of the OP_RETURN output that a BTC deposit can carry to ask for a contract call, and how `BtcTransactionReader` reads it (FLY-2870). The SDK builds this output and the LPS parses it, so both must follow this layout.

An OP_RETURN output is a Bitcoin output whose script starts with `0x6a`. It can never be spent, so it only carries data. The user signs the deposit transaction, and the signature covers every output, so nobody can change the OP_RETURN after the user signs.

## Layout

The OP_RETURN pushes one payload:

| Offset | Size | Field          | Value                                          |
| ------ | ---- | -------------- | ---------------------------------------------- |
| 0      | 1    | `magic`        | `0xF0`                                         |
| 1      | 1    | `version`      | `1`                                            |
| 2      | 20   | `destContract` | The RSK address to call; not the zero address  |
| 22     | 4    | `maxGasLimit`  | `uint32`, big-endian: the exact gas for the call |
| 26     | any  | `callData`     | The data for the call; can be empty            |

The fixed part is 26 bytes (`BtcTransactionReader.FLYOVER_CALL_DATA_OFFSET`). With only an address and no call data, the payload is exactly 26 bytes.

Example script for a 26-byte payload: `6a 1a f0 01 <20-byte destContract> <4-byte maxGasLimit>`. Here `0x1a` is the push opcode: "26 bytes follow".

## Rules

1. **Only the first OP_RETURN output is read.** It can be at any position in the transaction, because the user's wallet chooses the output order. Any later OP_RETURN output is ignored.
2. **The script must be OP_RETURN followed by exactly one push.** The push is either a direct push (`0x01`–`0x4b`, where the opcode is the data length) or `OP_PUSHDATA1` (`0x4c` followed by a 1-byte length). The pushed length must end exactly at the end of the script. Any other script is `BadPush`: a bare OP_RETURN, `OP_0`, `OP_PUSHDATA2`, `OP_PUSHDATA4`, a second push, or a wrong length. So the payload is at most 255 bytes, and `callData` at most 229 bytes.
3. **The payload must have a valid header.** `BtcTransactionReader.readFlyoverOpReturn` checks, in this order, and returns the first fault:

   | Fault             | When                                    |
   | ----------------- | --------------------------------------- |
   | `BadPush`         | Rule 2 fails                            |
   | `TooShort`        | The payload is shorter than 26 bytes    |
   | `WrongMagic`      | The first byte is not `0xF0`            |
   | `WrongVersion`    | The second byte is not `1`              |
   | `ZeroDestination` | `destContract` is the zero address      |

4. **Any first OP_RETURN counts as a Flyover OP_RETURN.** An OP_RETURN from another protocol, such as the bridge's own `RSKT` format, usually returns `WrongMagic`.
5. **The reader does not check the range of `maxGasLimit`.** The allowed range is a contract rule, so `PegInContract` checks it.

## Why the first OP_RETURN, and not a fixed position

Peg-out reads its OP_RETURN at a fixed position (output 1), because the LP builds that transaction itself. A peg-in deposit is built by the user's wallet, which decides the output order. Some wallets sort outputs (BIP69), so the position can change between transactions. Reading the first OP_RETURN, wherever it is, works with any wallet.

## Why the push opcode is checked

In a Bitcoin script, a push opcode states how many bytes follow. `BtcUtils.parseNullDataScript` removes only the `0x6a` byte, so the push opcode would be read as the first payload byte, and every valid payload would fail the magic check. The reader strips the push opcode first and accepts only the two push forms a payload of up to 255 bytes needs.
