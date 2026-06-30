# Task: State the no-release-path rule

**Parent story:** S0.1 Peg-out escrow state machine spec (E0)
**Type:** Task

## Description

Write the rule that a claim is a hard commitment: once an LP claims, there is no release path, so it must fulfill or be slashed.

## Definition of done

- The rule is stated in the spec.
- The transition table has no path from `CLAIMED` back to `REQUESTED` or to `CANCELLED`.

**Estimate:** 1. **Labels:** task, design, lbc.
