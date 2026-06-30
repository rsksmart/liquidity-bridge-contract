# Task: Pin the derivation scheme (design)

**Parent:** E2.2 Address derivation from RSK address
**Type:** Task (design, human-reviewed)
**Status:** DECIDED 2026-06-29. Locked scheme recorded in the parent `story.md`.

## Scheme (locked, see story.md)
- `derivationValue = keccak256(abi.encodePacked(rskAddress))`
- `flyoverRedeemScript = OP_PUSHBYTES_32 <derivationValue> OP_DROP <activePowpegRedeemScript>`
- segwit P2SH wrap: `OP_0 OP_PUSHBYTES_32 sha256(flyoverRedeemScript)`

This mirrors `validatePegInDepositAddress` but replaces the quote-hash input with the RSK address.

## Done when
The scheme is reviewed by one engineer and written into the parent `story.md` under the design sub-decision.
