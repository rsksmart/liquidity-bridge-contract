# Test E11.1 + E11.2 — the no-claimer refund path, end to end

The refund rail: a registered peg-in that **no LP fronted** is settled by `resolvePegIn`, which
forwards `amount − fee` to the user and — past the claim deadline — global-slashes the network on
the *same* call. Each case below traces to an acceptance-criterion line in the two story.md files and
names the Foundry test that realizes it (in `test/pegin/`). The live regtest proof is
`lbc/script/regtest-pegin/08-test-refund-path.sh` (see the regtest note).

## Cases

1. **No-claimer forward + slash on the same resolve.**
   Register + confirm a deposit; do NOT call `requestPegIn`; advance past the LP grace window and the
   claim deadline; call `resolvePegIn`. Assert: the bridge released the amount to the LBC; the user's
   `rskAddr` balance rose by `amount − fee`; total LP collateral dropped (global slash); the peg-in is
   marked processed.
   → E11.1 AC "a registered … peg-in that no LP fronted settles … forwarding amount − fee to the user";
   E11.2 AC "unclaimed past its deadline triggers `globalSlash`".
   → `ResolvePegIn.t.sol::test_ResolveUnclaimed_ForwardsToUserAndSlashes`,
   `UnclaimedSlash.t.sol::test_UnclaimedValid_ForwardsToUserAndSlashes`.

2. **Claimer path unchanged.**
   Front via `requestPegIn`, then `resolvePegIn`. The LP (claimer) is credited `fronted + fee`; the
   user is not paid twice; no slash.
   → E11.1 AC "the claimer path (E4.3) is unchanged when a claim exists".
   → `ResolvePegIn.t.sol::test_ClaimerRecoversFrontedPlusFee` (+ the E4.3 suite).

3. **Idempotent — double resolve reverts.**
   Resolve an unclaimed peg-in, then resolve the same id again → reverts `PegInAlreadyProcessed`.
   → E11.1 AC "re-resolving reverts `PegInAlreadyProcessed`".
   → `UnclaimedSlash.t.sol::test_ResolveTwice_Reverts`.

4. **Non-penalizable: unregistered address (failure/edge).**
   Resolve for an address never registered → reverts `AddressNotRegistered`; no slash.
   → E11.2 AC "an unregistered address … does not trigger a slash".
   → `UnclaimedSlash.t.sol::test_Unregistered_Reverts`.

5. **Non-penalizable: below-minimum amount (edge).**
   A released amount below the Flyover minimum is still refunded to the user, but the network is NOT
   slashed (total collateral unchanged).
   → E11.2 AC "a below-minimum amount does not trigger a slash".
   → `UnclaimedSlash.t.sol::test_BelowMinimum_ForwardsButNoSlash`.

6. **Deadline anchored to the registration block (edge).**
   Resolve before the deadline (registration block + `claimDeadlineBlocks`): the user is still
   forwarded, but no slash fires.
   → E11.2 AC "the deadline is anchored to the registration block".
   → `UnclaimedSlash.t.sol::test_BeforeDeadline_ForwardsNoSlash`.

7. **E11.4 failure mode — nobody calls `resolvePegIn` → coins stuck (documented, not automated).**
   The deposit sits at the flyover-derived address, which is **federation-controlled** and redeemable
   ONLY via `resolvePegIn` → `registerFastBridgeBtcTransaction`. If no LP, watchtower, or user ever
   calls `resolvePegIn`, the coins are never released and stay stuck at the federation address —
   nothing auto-refunds. There is no on-chain assertion for "someone never acted"; the mitigation is
   the incentivized watchtower (E11.4). This case is the boundary of the refund rail: the rail
   guarantees recovery *once someone resolves*, not that someone will.
   → constraints.md "The one true failure mode"; E11.4 story.

## Regtest note

Case 1 is proven live by `lbc/script/regtest-pegin/08-test-refund-path.sh` against a real regtest
stack (rskj 9.0.2, real powpeg bridge). The script orchestrates steps `01`→`05` (derive → fund BTC →
advance bridge → build SPV proof → register), **skips step `06` (`requestPegIn`)** so no LP fronts,
advances the RSK chain past the claim deadline (anchored to the registration block) so `globalSlash`
fires, then calls `resolvePegIn` and asserts the user's `rskAddr` balance rose by `amount − fee`, the
registered LP was slashed, and the peg-in is marked processed. It exits non-zero on any failed
assertion and is re-runnable (each run uses a fresh BTC deposit / txid).
