# Test: Oversized OP_RETURN handled

**Parent:** E4.2 OP_RETURN smart-contract call
**Type:** Foundry test

## Asserts
- A malformed or oversized OP_RETURN is handled per `../constraints.md` (rejected or treated as plain, per the breakdown decision).

Path: `test/pegin/OpReturnParse.t.sol`.
