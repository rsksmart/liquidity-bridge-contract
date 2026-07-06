# Task: Resolve the races

**Parent story:** S0.1 Peg-out escrow state machine spec (E0)
**Type:** Task

## Description

List each race and decide its resolution: user cancel against LP claim in the same block, LP claim against the pre-claim deadline, and slash trigger against a late delivery.

## Definition of done

- Each race has one chosen resolution and a one-line rationale.
- The cancel-versus-claim race states the tie-breaker (for example, first transaction mined wins, or a gas-price cap).

**Estimate:** 1. **Labels:** task, design, lbc.
