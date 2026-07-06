# E11.4 Permissionless resolve & peg-in watchtower incentive

**Epic:** E11 Peg-in refund & non-happy-path settlement (Peg-in track)
**Type:** Enabler · **Address impact:** none (RBTC rail)

## Statement

As the protocol, I want anyone (a watchtower, an LP, or the user) to be able to call
`registerAddress` and `resolvePegIn` and earn a reward, so a peg-in is never permanently
stuck when the serving LP or the user's own client is offline.

## Frozen inputs

- The one true failure mode: if nobody ever calls `resolvePegIn`, the coins stay stuck at the
  federation-controlled deposit address; nothing auto-refunds.
- Proposal "New role: Flyover Watchtower" — an incentivized third party (anyone can run,
  including the user privately, or via RIF Relay) that submits the RSK txs and earns a
  registration fee / reward. Acts on RSK, not a Bitcoin-signing entity.
- E4.3 already pays a registrant fee once per address on the first peg-in.
- Related peg-out work: E10b (`watchtower-refund`) — keep the incentive model consistent.

## Output

`registerAddress` and `resolvePegIn` are callable by any address (already permissionless in
the PoC — confirm and lock), and the caller earns the configured registrant/resolver reward.
A minimal off-chain watcher spec (or reuse of E5 discovery + E10b watchtower) so an
incentivized party reliably drives registration and resolution.

## Acceptance criteria

- `registerAddress` / `resolvePegIn` succeed when called by a non-LP, non-user address.
- The caller receives the configured reward (registration fee; resolver reward if defined).
- A peg-in the serving LP abandoned can be resolved by a third party, forwarding to the user
  (E11.1) and slashing LPs (E11.2).
- Foundry tests cover a third-party resolve and reward payout.

## Children

Tasks and tests to be broken down (droppable standard for the PoC).

## Depends on

E11.1, E11.2, E4.3; aligns with E10b. Independent of E11.5.

**Estimate:** 5. **Labels:** enabler, P1, lbc, lps.
