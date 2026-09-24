#!/usr/bin/env python3
"""Mutation scope helper.

mewt.toml is the single source of truth for which contracts are eligible for
mutation testing: the [[per_target]] globs are the allowlist. This module reads
that allowlist back out so the shell entry points never restate it.

Subcommands:
  allowlist  Print the [[per_target]] globs, one per line.
  active     Print the active contracts discovered under src/, one per line.
  filter     Read candidate paths on stdin, print the allowlisted ones on stdout
             and report the rest on stderr.
  check      Fail when the allowlist has drifted from the contracts on disk.
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

CONFIG = Path("mewt.toml")

# Directories excluded from mutation testing. Kept in the same shape as the
# [targets].ignore substrings in mewt.toml.
EXCLUDED_PREFIXES = (
    "src/interfaces/",
    "src/legacy/",
    "src/test-contracts/",
    "src/test/",
)


def _load_config() -> dict:
    if not CONFIG.is_file():
        sys.exit(f"{CONFIG} not found; run from the repository root")
    with CONFIG.open("rb") as handle:
        return tomllib.load(handle)


def allowlist() -> list[str]:
    config = _load_config()
    globs = [rule["glob"] for rule in config.get("per_target", []) if "glob" in rule]
    if not globs:
        sys.exit(f"{CONFIG} declares no [[per_target]] globs; mutation scope is empty")
    return globs


def include() -> list[str]:
    return _load_config().get("targets", {}).get("include", [])


def _glob_token(pattern: str, index: int) -> tuple[str, int]:
    """Return (regex fragment, next index) for the glob token at pattern[index]."""
    length = len(pattern)

    if pattern.startswith("**", index):
        next_index = index + 2
        if next_index < length and pattern[next_index] == "/":
            return "(?:.*/)?", next_index + 1
        return ".*", next_index

    char = pattern[index]
    if char == "*":
        return "[^/]*", index + 1
    if char == "?":
        return "[^/]", index + 1

    if char == "[":
        end = pattern.find("]", index)
        if end != -1:
            return pattern[index : end + 1], end + 1

    return re.escape(char), index + 1


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Translate a glob to a regex using globset's separator rules.

    `*` and `?` never cross `/`, `**/` matches zero or more directories. Brace
    alternation is rejected rather than silently mistranslated, since a wrong
    translation here would widen the mutation scope.
    """
    if "{" in pattern or "}" in pattern:
        sys.exit(
            f"unsupported brace alternation in glob '{pattern}'; "
            "use one [[per_target]] entry per contract"
        )

    parts = ["^"]
    index = 0
    while index < len(pattern):
        fragment, index = _glob_token(pattern, index)
        parts.append(fragment)
    parts.append("$")
    return re.compile("".join(parts))


def matchers(patterns: list[str]) -> list[tuple[str, re.Pattern[str]]]:
    return [(pattern, glob_to_regex(pattern)) for pattern in patterns]


def is_allowed(path: str, compiled: list[tuple[str, re.Pattern[str]]]) -> bool:
    return any(regex.match(path) for _, regex in compiled)


def active_contracts() -> list[str]:
    """Every contract under src/ that is eligible for mutation testing."""
    paths = [path.as_posix() for path in sorted(Path("src").rglob("*.sol"))]
    ignore = tuple(_load_config().get("targets", {}).get("ignore", [])) or EXCLUDED_PREFIXES
    return [path for path in paths if not any(substr in path for substr in ignore)]


def cmd_filter() -> int:
    compiled = matchers(allowlist())
    candidates = [line.strip() for line in sys.stdin if line.strip()]
    kept, dropped = [], []
    for candidate in candidates:
        (kept if is_allowed(candidate, compiled) else dropped).append(candidate)

    for path in dropped:
        print(f"out of mutation scope: {path}", file=sys.stderr)
    for path in kept:
        print(path)
    return 0


def cmd_check() -> int:
    patterns = allowlist()
    compiled = matchers(patterns)
    contracts = active_contracts()
    problems = []

    unmapped = [path for path in contracts if not is_allowed(path, compiled)]
    for path in unmapped:
        problems.append(
            f"no [[per_target]] mapping for {path} "
            "(it would be skipped by mutation testing)"
        )

    for pattern, regex in compiled:
        if not any(regex.match(path) for path in contracts):
            problems.append(
                f"[[per_target]] glob '{pattern}' matches no active contract "
                "(stale mapping)"
            )

    include_patterns = include()
    if not include_patterns:
        problems.append("[targets].include is empty; a bare `mewt run` would fail")
    else:
        include_compiled = matchers(include_patterns)
        allow_set = {path for path in contracts if is_allowed(path, compiled)}
        include_set = {path for path in contracts if is_allowed(path, include_compiled)}
        for path in sorted(include_set - allow_set):
            problems.append(f"{path} is in [targets].include but has no [[per_target]] mapping")
        for path in sorted(allow_set - include_set):
            problems.append(f"{path} has a [[per_target]] mapping but is missing from [targets].include")

    if problems:
        print("Mutation scope drift detected:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nUpdate mewt.toml so [[per_target]] and [targets].include cover "
            "exactly the active contracts under src/.",
            file=sys.stderr,
        )
        return 1

    print(f"Mutation scope OK: {len(contracts)} contracts mapped.")
    return 0


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "allowlist":
        print("\n".join(allowlist()))
        return 0
    if command == "active":
        print("\n".join(active_contracts()))
        return 0
    if command == "filter":
        return cmd_filter()
    if command == "check":
        return cmd_check()
    sys.exit(f"usage: {Path(sys.argv[0]).name} (allowlist|active|filter|check)")


if __name__ == "__main__":
    raise SystemExit(main())
