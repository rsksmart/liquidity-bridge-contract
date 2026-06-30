# Test: Walk every transition

**Parent story:** S0.1 Peg-out escrow state machine spec (E0)
**Type:** Review gate (design)

## Validates

No state is unreachable and no non-terminal state is stuck.

## Pass condition

A reviewer walks the transition table from `REQUESTED` and reaches every state, and every non-terminal state has an outgoing transition.

**Labels:** test, design.
