# Task E11.2.1 — Wire globalSlash to the resolve deadline

## Do

- Compute the claim deadline from the **registration block** (E2 `registrationBlock[addr]`)
  plus the configured peg-in claim deadline (`FlyoverConfigurations`).
- In the no-claimer `resolvePegIn` path (E11.1), after confirming the peg-in is serviceable
  (registered, amount ≥ Flyover minimum) and past deadline, call
  `CollateralManagement.globalSlash(total)` for the configured amount.
- Skip the slash for the non-penalizable cases: unregistered address, below-minimum amount,
  and any LP inside its grace window (E3 already tracks `_registrationBlock`/`_graceWindow`).
- Ensure `PegInContract` holds `COLLATERAL_SLASHER` on `CollateralManagement` (already granted
  during wiring; add a guard/assert).

## Notes

- Address-neutral: no derivation input is read or changed.
- Keep the slash idempotent per peg-in (fires once, on the settling resolve).
