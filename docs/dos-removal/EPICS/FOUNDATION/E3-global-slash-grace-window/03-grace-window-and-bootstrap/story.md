# E3.3 Grace window config and bootstrap safety

**Epic:** E3 Global slash and grace window (Foundation track)
**Type:** Enabler

## Statement

As the protocol owner, I want the grace window to be configurable and the few-LP bootstrap case to be safe, so a freshly registered LP is never global-slashed during onboarding.

## Frozen inputs

- Grace window provisional value 100 blocks (S0.3), adjustable via the E1.5 time-locked setters.
- The skip logic from E3.2.

## Acceptance criteria

- The grace window length is a configurable parameter with a time-locked setter.
- A freshly registered LP within the window is not slashed even when it is the only non-failing LP.
- The individual slash for the post-claim case is unchanged.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E3.2.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
