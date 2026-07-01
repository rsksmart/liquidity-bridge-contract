# E11.2 Wire unclaimed peg-in to the global slash

**Epic:** E11 Peg-in refund & non-happy-path settlement (Peg-in track)
**Type:** Enabler · **Address impact:** none (RBTC rail)

## Statement

As the protocol, I want a valid registered peg-in that no LP claimed by the deadline to
trigger `globalSlash` at resolve time, so the network is incentivized to serve every peg-in.

> Realizes the spec already written in **E4.4** (`unclaimed-global-slash`): `globalSlash`
> exists in `CollateralManagement` (E3) but is **not wired** to the resolve deadline. This
> story implements and tests that wiring. Do not duplicate E4.4 — treat E4.4 as the spec and
> this as its build.

## Frozen inputs

- E3 `globalSlash(uint256)` and the grace window.
- E11.1 no-claimer settlement (the slash fires on the same no-claimer resolve).
- Proposal negative scenarios: unregistered address or below-Flyover-minimum amount is **not**
  penalizable; the slash deadline anchors to the **registration block**, not the deposit.

## Output

`resolvePegIn` (no-claimer path) triggers `globalSlash` when the peg-in is past its deadline
(anchored to registration block) and was serviceable (registered, above minimum), and skips
the slash for the non-penalizable cases.

## Acceptance criteria

- A serviceable, registered peg-in unclaimed past its deadline triggers `globalSlash`.
- An unregistered address or a below-minimum amount does **not** trigger a slash.
- The deadline is anchored to the registration block.
- An LP registered inside the grace window is not slashed.
- Foundry tests cover: slash fires, each non-penalizable case skips, grace-window boundary,
  and the few-LP bootstrap case.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E3, E11.1, E2. Independent of E11.5.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
