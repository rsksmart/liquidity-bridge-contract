# Formal Verification — Property Catalog

This document is the **specification** for the symbolic proofs that live in
`test/formal/`. Each property here is intended to stand on its own as a
security claim that can be reviewed, debated, and extended without reading the
Solidity. The implementation in `test/formal/` is one specific encoding of the
claim; the claim itself lives here.

For tooling setup, pinned versions, and how to run the proofs locally, see
[`FOUNDRY_MAKEFILE_GUIDE.md`](./FOUNDRY_MAKEFILE_GUIDE.md#formal-verification-halmos).

---

## Conventions

Every property is described with the same five fields:

- **Property** — the claim in English. This is the line a non-Solidity
  reviewer should be able to read and agree (or disagree) with.
- **Assumptions / bounds** — preconditions that constrain the symbolic inputs.
  These narrow the proof's reach; weakening them is an explicit design choice.
- **Why it matters** — what concrete failure mode the property rules out.
- **Implementation** — pointer to the `check_*` function that encodes the
  property.
- **Status** — `Proven` (Halmos discharges it across all explored paths),
  `TODO` (claim documented but not yet encoded), or `Limited` (proven under
  stricter-than-ideal assumptions; explanation provided).

All references below are against the contracts in `src/CollateralManagement.sol`
and the interface in `src/interfaces/ICollateralManagement.sol`.

---

## Properties — `CollateralManagement`

### 1. Slash conservation (peg-in)

- **Property.** When a peg-in provider is slashed, the punisher's reward plus
  the protocol's penalty remainder equals the *effective penalty* taken from
  the provider's collateral. No value is created or destroyed by the slashing
  operation.

  Formally, letting `Δreward`, `Δpenalty`, and `Δcollateral` denote the changes
  in `rewards[punisher]`, `penalties`, and `pegInCollateral[lp]` respectively,
  the property is:

  ```
  Δreward + Δpenalty == -Δcollateral == min(penaltyFee, collateralBefore)
  ```

- **Assumptions / bounds.**
  - `0 < collateral ≤ 100 ether`
  - `0 < penaltyFee ≤ 100 ether`
  - `rewardPercentage ∈ [0, TOTAL_REWARD_PERCENTAGE]` (symbolic; covers
    the full configurable range, including values that don't divide
    `penalty * r` evenly — see "Why it matters")
  - The slasher holds `COLLATERAL_SLASHER`; the adder holds `COLLATERAL_ADDER`.

- **Why it matters.** Slashing is the only path that splits a provider's
  funds between two destinations (`rewards` and `penalties`). The arithmetic
  is `punisherReward = (penalty * rewardPercentage) / TOTAL_REWARD_PERCENTAGE`
  with integer division, so for non-divisor combinations a wei can be "lost"
  to rounding if the remainder isn't credited. This property proves the
  remainder is correctly captured in `penalties`, which prevents a class of
  silent-shortfall bugs.

- **Implementation.**
  [`check_SlashPegInConservation`](../test/formal/CollateralManagement.check.t.sol#L22)

- **Status.** Proven.

### 2. Slash conservation (peg-out)

- **Property.** Mirror of (1) for peg-out slashing: when a peg-out provider is
  slashed, `Δreward + Δpenalty == -Δpegoutcollateral == min(penaltyFee, collateralBefore)`.

- **Assumptions / bounds.** Same as (1), with peg-out collateral and quote.

- **Why it matters.** Peg-out slashing uses the same arithmetic and the same
  rounding risk; the property has to hold symmetrically.

- **Implementation.**
  [`check_SlashPegOutConservation`](../test/formal/CollateralManagement.check.t.sol#L73)

- **Status.** Proven.

### 3. Collateral sufficiency threshold (peg-in)

- **Property.** For any peg-in provider that has not resigned,
  `isCollateralSufficient(PegIn, lp)` returns `true` if and only if
  `pegInCollateral[lp] >= minCollateral`.

- **Assumptions / bounds.**
  - `0 < collateral ≤ 100 ether`
  - Provider has not resigned (resignation handled separately in property 4).

- **Why it matters.** The sufficiency check gates whether a provider can
  service quotes. A wrong threshold (off-by-one, wrong comparison) would let
  under-collateralized providers operate or block well-funded providers.

- **Implementation.**
  [`check_CollateralSufficiencyPegIn`](../test/formal/CollateralManagement.check.t.sol#L128)

- **Status.** Proven.

### 4. Resigned providers are never sufficient

- **Property.** Once a provider calls `resign()`, `isCollateralSufficient(...)`
  returns `false` regardless of the collateral amount held.

- **Assumptions / bounds.**
  - `MIN_COLLATERAL ≤ collateral ≤ 100 ether` (the property is only
    interesting in the regime where sufficiency would otherwise hold).
  - `block.number > 0` (enforced by `FormalBase.setUp`), because `resign()`
    stores `block.number` as the resignation marker and a value of `0` would
    collide with the "not resigned" sentinel.

- **Why it matters.** Resignation is the wind-down path. Allowing a resigned
  provider to be treated as sufficient would let them accept new quotes after
  signalling exit, which breaks the resignation contract with users.

- **Implementation.**
  [`check_ResignedProviderNeverSufficient`](../test/formal/CollateralManagement.check.t.sol#L153)

- **Status.** Proven.

### 5. Withdraw without resign reverts

- **Property.** `withdrawCollateral()` reverts with the exact error
  `ICollateralManagement.NotResigned` for any caller that holds collateral but
  has not called `resign()`, regardless of the caller's collateral amount or
  the current block number.

- **Assumptions / bounds.**
  - `0 < collateral ≤ 100 ether`

- **Why it matters.** Withdraw is a fund-moving call. Allowing it before
  resignation would let providers reclaim their stake while still active,
  bypassing the slashing window. Asserting the **exact** revert selector
  (rather than "any revert") prevents the proof from silently passing if the
  call reverts for an unrelated reason (panic, access control, future bug).

- **Implementation.**
  [`check_WithdrawRevertsIfNotResigned`](../test/formal/CollateralManagement.check.t.sol#L186)

- **Status.** Proven, with a tooling caveat: Halmos 0.3.x does not support
  `vm.expectRevert`, so the test decodes the revert data inside `catch (bytes
  memory revertData)` and asserts `bytes4(revertData) == NotResigned.selector`.
  This catches the selector but not the encoded `(address from)` argument.
  Arg-matching is left as a follow-up if/when Halmos adds `vm.expectRevert`
  support.

### 6. Withdraw before resign delay reverts

- **Property.** After a provider has resigned, `withdrawCollateral()` reverts
  with `ICollateralManagement.ResignationDelayNotMet` for any block number
  earlier than `resignationBlock + resignDelayInBlocks`.

- **Assumptions / bounds.**
  - `0 < collateral ≤ 100 ether`
  - `blocksAfterResign < RESIGN_DELAY` (symbolic across the entire pre-delay
    range, including `0`).

- **Why it matters.** The resign delay is the window in which a provider can
  still be slashed for prior misbehaviour. Allowing withdrawal during this
  window would let a misbehaving provider exit before their misbehaviour is
  noticed and slashed.

- **Implementation.**
  [`check_WithdrawRevertsBeforeDelay`](../test/formal/CollateralManagement.check.t.sol#L212)

- **Status.** Proven, with the same selector-vs-argument tooling caveat as (5).

---

## Scope and known limitations

The proofs above are deliberately PoC-scoped. The following are out of scope
for the current pass and are flagged so reviewers don't expect them:

- **Bounded inputs.** `collateral` and `penaltyFee` are bounded at `100 ether`
  in every proof. The bound exists to keep symbolic execution tractable and
  to match realistic provider stakes; properties are not guaranteed to hold
  for unbounded values without re-verifying. Widening the bounds (and
  measuring runtime impact) is a natural follow-up.
- **Revert argument matching.** Properties (5) and (6) match only the
  4-byte error selector, not the encoded arguments. See the tooling caveat
  on each.
- **Cross-contract flows.** Only `CollateralManagement` is exercised. The
  bridge contract, discovery flows, and quote registry are out of scope.
- **Invariant tests are not reproduced here.** The Foundry invariant tests
  in `test/invariant/` exercise overlapping properties via random-sequence
  testing and have their own NatSpec documentation in-file; a future
  iteration may consolidate them into this catalog if the team wants a
  single source of truth.
- **Halmos limitations.** Loops, unbounded memory, and certain external-call
  patterns can cause Halmos to fall back to bounded exploration. The proofs
  above were chosen to avoid these patterns; new properties should be
  evaluated for compatibility.

## Changing or adding properties

When adding a property:

1. Write the **property statement** here first, in plain English, before
   touching Solidity. The statement is the artifact reviewers will discuss.
2. List **assumptions** explicitly. If a proof requires assumptions that
   wouldn't hold in production (e.g. a fixed configuration value), prefer
   making that input symbolic — see property (1) for the symbolic
   `rewardPercentage` pattern.
3. Encode the property as a `check_*` function in `test/formal/`.
4. Run `make test-formal` and confirm the proof discharges.
5. Add the function reference and set **Status** to `Proven`.

When changing a property, update the statement here in the same PR as the
test edit so the spec and the encoding don't drift.
