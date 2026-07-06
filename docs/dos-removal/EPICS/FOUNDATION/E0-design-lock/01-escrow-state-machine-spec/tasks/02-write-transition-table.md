# Task: Write the transition table

**Parent story:** S0.1 Peg-out escrow state machine spec (E0)
**Type:** Task

## Description

Write the transition table with columns: from-state, event or function, to-state, guard condition, who can call.

## Definition of done

- Every permitted transition has a row.
- Each row names the function (`requestPegOut`, `claimPegOut`, `cancelPegOut`, `refundPegOut`) and the caller.
- Transitions not in the table are rejected by default.

**Estimate:** 1. **Labels:** task, design, lbc.
