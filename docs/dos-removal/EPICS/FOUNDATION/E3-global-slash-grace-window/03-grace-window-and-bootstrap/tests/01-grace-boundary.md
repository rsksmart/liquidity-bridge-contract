# Test: Grace boundary

**Parent:** E3.3 Grace window config and bootstrap safety
**Type:** Foundry test

## Asserts
- An LP at exactly `registrationBlock + graceWindow` is treated per the documented boundary, and one block later is eligible.

Path: `test/collateral/Grace.t.sol`.
