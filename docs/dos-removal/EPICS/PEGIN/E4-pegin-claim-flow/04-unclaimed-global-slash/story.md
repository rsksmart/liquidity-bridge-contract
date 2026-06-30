# E4.4 Unclaimed peg-in global slash

**Epic:** E4 Peg-in claim flow (Peg-in track)
**Type:** Enabler

## Statement

As the protocol, I want a valid registered peg-in that no LP claims by the deadline to trigger the global slash, so the network is incentivized to serve every peg-in.

## Frozen inputs

- E3 `globalSlash`.
- Proposal negative scenarios: "No LP advances the payment" triggers global slash; an unregistered address or a below-Flyover-minimum amount is not penalizable; the slash deadline anchors to the registration block, not the deposit.

## Acceptance criteria

- A valid registered peg-in unclaimed past its deadline triggers `globalSlash`.
- An unregistered address or a below-minimum amount does not trigger a slash.
- The deadline is anchored to the registration block.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E3, E4.1, E2.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
