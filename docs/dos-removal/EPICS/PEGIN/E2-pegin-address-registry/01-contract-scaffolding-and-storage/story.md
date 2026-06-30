# E2.1 Contract scaffolding and storage

**Epic:** E2 PegInAddressRegistry (Peg-in track)
**Type:** Enabler

## Statement

As an LBC engineer, I want the `PegInAddressRegistry` skeleton with its storage, so the derivation, running-hash, and registration work has a place to land.

## Frozen inputs

- Interface: `EPICS/FOUNDATION/E0-design-lock/outputs/contract-interfaces.md` (`IPegInAddressRegistry`).
- LBC patterns: upgradeable (`AccessControlDefaultAdminRulesUpgradeable`), ERC-7201 namespaced storage, Solidity 0.8.25, Foundry.

## Acceptance criteria

- The contract deploys, initializes once, and implements the `IPegInAddressRegistry` surface (stubbed where later items fill it in).
- Storage uses an ERC-7201 namespace holding the registration-block mapping, the registration count, and the `registrationRoot`.

## Children

Tasks: see `tasks/`. Tests: see `tests/`.

## Depends on

E0 (frozen interface). No dependency on E1 or E3.

**Estimate:** 3. **Labels:** enabler, P0, lbc.
