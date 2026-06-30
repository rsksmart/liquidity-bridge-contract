# E1.3 Confirmation tiers

**Epic:** E1 FlyoverConfigurations (Foundation track)
**Type:** Enabler
**Story:** As an LP, I want the required confirmations to depend on the amount, so that larger transfers wait for more confirmations without a negotiated quote.

## Output (the deliverable)

- A sorted `ConfirmationTier[]` per flow in storage.
- `getRequiredPegInConfirmations(amount)` and `getRequiredPegOutConfirmations(amount)`.

## Acceptance criteria

- The lookup returns the confirmations for the tier the amount falls into.
- The tiers are kept sorted ascending by `maxAmount`, and a setter rejects an unsorted list.
- Peg-in and peg-out keep separate tier lists.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Grounded in

Proposal `IFlyoverConfigurations`: `ConfirmationTier { maxAmount, confirmations }`, "sorted ascending by maxAmount", `getRequiredPegInConfirmations`, `getRequiredPegOutConfirmations`. LBC map: today `depositConfirmations` is a single per-quote field, so tiering is new.

## Depends on (within E1)

E1.1 (scaffolding and storage).

**Estimate:** 3. **Labels:** enabler, P0, lbc.
