#!/usr/bin/env bash
#
# Print the contracts changed against a base ref that are in the mutation
# allowlist, one repo-relative path per line.
#
# The intersection with the allowlist happens here, before mewt is invoked, so
# a contract without a [[per_target]] mapping can never be mutated. Paths are
# emitted exactly as git reports them: mewt matches [[per_target]] globs against
# the path as supplied, so canonicalizing or prefixing with ./ would silently
# miss every rule.
#
# Usage:
#   script/mutation/changed-contracts.sh [base-ref]
#   BASE_REF=origin/master script/mutation/changed-contracts.sh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BASE="${1:-${BASE_REF:-origin/master}}"

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "error: base ref '$BASE' not found." >&2
    echo "Pass one explicitly: script/mutation/changed-contracts.sh <base-ref>" >&2
    exit 1
fi

changed="$(git diff --name-only --diff-filter=ACMR "$BASE...HEAD")"
contracts="$(printf '%s\n' "$changed" | grep -E '^src/.*\.sol$' || true)"

if [ -z "$contracts" ]; then
    exit 0
fi

printf '%s\n' "$contracts" | python3 script/mutation/scope.py filter
