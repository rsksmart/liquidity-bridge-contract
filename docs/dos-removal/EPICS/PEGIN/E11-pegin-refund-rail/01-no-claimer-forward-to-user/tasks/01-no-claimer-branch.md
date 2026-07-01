# Task E11.1.1 — Add the no-claimer branch to resolvePegIn

## Do

- In `PegInContract._reimburseClaim` (or a sibling called from `resolvePegIn`), branch on
  whether a claim exists for the peg-in id:
  - claim exists → current behavior (credit `claim.claimer` with `fronted + feeToClaimer`).
  - no claim → compute `netToUser = amount − fee` from `FlyoverConfigurations`, and deliver
    it to the user via the same `_deliver(rskAddr, netToUser, opReturn)` used at front time,
    so plain vs SC-call routing is shared with E4.2/E11.3.
- Pay the registrant/watchtower fee once per address (reuse the E4.3 first-peg-in rule).
- Mark the peg-in processed before external calls (reentrancy: the function already runs
  under `nonReentrant`, keep checks-effects-interactions).

## Notes

- The bridge-released RBTC is in the contract at this point (`0 → amount`); the forward is a
  local transfer, not a new bridge call.
- Do not read or change any derivation input — this task is address-neutral.
