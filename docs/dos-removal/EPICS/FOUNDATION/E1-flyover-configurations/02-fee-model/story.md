# E1.2 Fee model (fixed floor plus percentage)

**Epic:** E1 FlyoverConfigurations (Foundation track)
**Type:** Enabler
**Story:** As an LP, I want the service fee computed from on-chain configuration, so that fees no longer come from a negotiated quote.

## Output (the deliverable)

- `calculatePegInFee(amount)` and `calculatePegOutFee(amount)` returning fixed floor plus a percentage of the amount.
- Storage and getters for `fixedFee` and `percentageFee` on each peg configuration.

## Acceptance criteria

- The fee equals `fixedFee + (amount * percentageFee / 10_000)` for each flow.
- Rounding follows the existing SAT and WEI convention so peg-in and peg-out agree with the bridge.
- Peg-in and peg-out fees are computed independently from their own configuration.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal `IFlyoverConfigurations`: `fixedFee`, `percentageFee` (`10_000 = 100%`), `calculatePegInFee`, `calculatePegOutFee`. Proposal peg-in change 1: fee is a fixed floor plus a percentage of the amount, set by the contract owner. LBC map: `Quotes.checkAgreedAmount` adjusts for SAT and WEI rounding.

## Depends on (within E1)

E1.1 (scaffolding and storage).

**Estimate:** 5. **Labels:** enabler, P0, lbc.
