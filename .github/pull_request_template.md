## What

Briefly describe the change in plain language.

## Why

Explain the motivation, bug, risk, or product/security need behind this PR.

## Type of Change

- [ ] Bug fix (non-breaking change)
- [ ] New feature (non-breaking change)
- [ ] Breaking change
- [ ] Refactor (no intended behavior change)
- [ ] Security hardening
- [ ] Tests only
- [ ] Build/CI/Tooling
- [ ] Documentation

## Affected Areas

- [ ] PegIn flow (`registerPegIn`, `callForUser`, quote validation)
- [ ] PegOut flow (`depositPegout`, `refundPegOut`, `refundUserPegOut`)
- [ ] Liquidity Provider lifecycle (register/update/status/resign/collateral/withdraw)
- [ ] Pause/operational controls
- [ ] Quote hashing/signature logic
- [ ] Bitcoin tx / PMT / merkle validation
- [ ] Deployment or upgrade scripts / Makefile targets
- [ ] CI workflows (`ci`, `fuzz`, `slither`, `codeql`)
- [ ] Docs

## Risk & Security Review

- [ ] Access control and authorization paths reviewed
- [ ] Reentrancy and external call paths reviewed
- [ ] Storage layout / upgrade safety reviewed (if upgradeable code changed)
- [ ] Time/block/confirmation assumptions reviewed
- [ ] BTC tx output/index assumptions reviewed (if pegout validation touched)
- [ ] No secrets or sensitive values added

## Test Plan

List what you ran locally and the outcome:

- [ ] `npm run lint:sol`
- [ ] `npm run lint:ts`
- [ ] `npm run compile`
- [ ] `npm test`
- [ ] `npm run test:fuzz` (if logic/state transitions changed)
- [ ] `npm run test:invariant` (if invariant-sensitive logic changed)
- [ ] `npm run test:integration` (if integration paths changed)
- [ ] `npm run test:e2e` (if deployment/ownership flows changed)

Additional notes on test coverage, edge cases, and any tests intentionally skipped:

## Deployment & Ops Impact

- [ ] No deployment impact
- [ ] Requires deployment
- [ ] Requires upgrade
- [ ] Env/config changes required (`.env`, network RPCs, verification, etc.)
- [ ] Runbook/update instructions added to PR description

If deployment/upgrade is needed, include target network(s), simulation command(s), and rollback considerations.

## Related Issues

- Jira: [FLY-XXXX](<insert URL>)
- GitHub Issue: #(if applicable)

## Reviewer Notes

Anything reviewers should focus on (critical functions, invariants, assumptions, known limitations).

## Screenshots / Logs (if applicable)

For scripts, CI, or behavior changes, include relevant output snippets or links.
