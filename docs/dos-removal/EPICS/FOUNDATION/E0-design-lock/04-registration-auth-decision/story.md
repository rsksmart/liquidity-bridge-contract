# S0.4 Registration-auth decision

**Epic:** E0 Design lock
**Story:** As a tech lead, I want a recorded decision on registration authorization, so that E10 has a chosen institutional path.

## Decision (locked 2026-06-28)

**Decision:** `registerAddress` is permissionless and deposit-gated. Any caller can register any RSK address, gated only by an SPV proof that BTC was paid to the derived address. No ECDSA signature from the RSK key is required.

**Rationale:** the deposit proof is the anti-spam gate; registering another address only adds it to the watch list, which is harmless because the call data lives in the BTC `OP_RETURN`, not the registry; and it works for every custody type including Safe contract-account multisigs.

**Tradeoff:** we give up cryptographic proof that the registrant owns the RSK address. This is acceptable because the deposit proof already gates spam and registering another's address causes no harm. The alternative, ECDSA-required, would add that ownership proof but block Safe contract-account multisigs from self-registering and force a signing or relay scheme onto the PoC critical path for little added protection.

**Consequences:**
- E2 `registerAddress` takes the deposit proof, not a signature.
- E10a serves every custody type. RIF Relay becomes a convenience for no-RBTC reimbursement, not an auth requirement.

## Output (the deliverable)

A decision record `decision-registration-auth.md` containing:

1. The decision: whether `registerAddress` requires an ECDSA signature from the RSK key or accepts any caller.
2. The rationale and the trade-offs considered.
3. A custody-type table mapping each option to the custody it serves.
4. The selected institutional path: Watchtower, RIF Relay, or both.

## Acceptance criteria

- The decision is stated plainly, with the reasoning behind it.
- The custody-type table distinguishes an externally owned custody account from a contract-account multisig.
- The record names which path each custody type takes, so E10a can start from a single chosen path.
- The record states whether E10b (Watchtower honest refund) is in scope, which holds only if the Watchtower path is chosen.

## Grounded in

Threat model section 9, residual institutional items: an externally owned custody account (Fireblocks, Fordefi) may register directly, but a contract-account multisig (a Safe) cannot produce a normal ECDSA signature, which is the case the RIF Relay smart-wallet path or a Watchtower is built for. Proposal "RIF Relay integration" section and the existing RIF Relay PoC on the `FLY-2355` branches.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Feeds

E10a (institutional registration path), and E10b (Watchtower honest refund) if the Watchtower path is chosen.

## Depends on (within E0)

None.

**Estimate:** 2. **Labels:** story, design.
