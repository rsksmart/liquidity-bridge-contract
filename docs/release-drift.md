# Release Branch Drift Detection

Scheduled CI job that flags commits which landed on an older release branch but
were never carried forward to newer ones.

The job is **detection-only**. No branches are modified. The output is a
markdown report kept as a workflow artifact.

This is phase 1 of a planned three-phase rollout. The workflow originated in the
[liquidity-provider-server][lps] repo under [FLY-2292][fly2292]; this LBC adoption
is tracked by [FLY-2319][fly2319].

## What it does

For every adjacent pair of release branches (sorted by semver) **and** for
every release branch against trunk, the script lists commits present on the
older side but missing from the newer side. Patch-id matching is used (via
`git log --cherry-pick`) so cherry-picked backports with different SHAs are
not flagged.

The trunk comparisons can be narrowed to just "newest release vs trunk" by
setting `COMPARE_ALL_VS_TRUNK=0` if the broader output is noisy.

Two extra filters run on top of the patch-id check:

- Commits whose subject starts with `Revert "` are dropped (the revert itself
  is not interesting drift).
- Commits that are reverted later on the same older branch — detected by a
  matching `This reverts commit <sha>` line in a later commit on that branch —
  are dropped.

## Files

- `scripts/check-release-drift.mjs` — the detector. Self-contained Node
  script; only needs `git` and Node 20+. No npm dependencies. Safe to copy
  into other repos.
- `.github/workflows/release-drift.yml` — scheduled + manual workflow. Pins
  Node to `20.15.1` (matching the rest of LBC's CI), runs the script, and
  uploads `drift-report.md` + `merge-status.json` as the `release-drift-report`
  artifact.

## LBC branch naming note

LBC release branches are semver-named (e.g. `v2.5.2`, `v2.6.0`). The repo also
has a few non-release branches that happen to start with a version prefix —
`v2.5.0-fixes`, `v2.5.0-testnet-deploy`. The default glob
`v[0-9]*.[0-9]*.[0-9]*` matches these too, so they appear as additional
"release branches" in the report. This is intentional and accepted: keeping the
standard pattern guarantees no real release branch is ever silently excluded,
and stays in sync with the LPS workflow. The `semver`-aware comparator sorts
`v2.5.0-fixes` as a pre-release of `2.5.0`, so ordering stays sensible.

If these branches become noisy, override `RELEASE_BRANCH_PATTERN` at dispatch
time (or change the workflow default) to a tighter glob — for example
`v[0-9]*.[0-9]*.[0-9]` (no trailing `*`) excludes the suffixed branches, at the
cost of not matching two-digit patch versions like `v2.5.10`.

## Configuration

All knobs are environment variables on the script:

| Variable                 | Default                 | What it does                                                                                                                                                                         |
| ------------------------ | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `RELEASE_BRANCH_PATTERN` | `v[0-9]*.[0-9]*.[0-9]*` | Git glob used against `refs/remotes/$REMOTE/`. Anything matching is treated as a release branch and sorted by semver.                                                                |
| `RELEASE_TAG_PATTERN`    | `v[0-9]*`               | Git glob for release tags. The script uses this to determine the "Released in" column (earliest tag containing each drifted commit) and the "Latest release" column for each branch. |
| `TRUNK_BRANCH`           | `master`                | The trunk to compare release branches against. If absent on the remote, trunk comparisons are skipped.                                                                               |
| `REMOTE`                 | `origin`                | Remote name to query.                                                                                                                                                                |
| `REPORT_FILE`            | `drift-report.md`       | Markdown report output path.                                                                                                                                                         |
| `MERGE_STATUS_FILE`      | `merge-status.json`     | Machine-readable mergeability output path (see [Merge feasibility](#merge-feasibility)).                                                                                             |
| `COMPARE_ALL_VS_TRUNK`   | `1`                     | When `1`, every release branch is compared against trunk in addition to the adjacent-pair comparisons. When `0`, only the newest release is compared against trunk.                  |
| `EXIT_NONZERO_ON_DRIFT`  | `0`                     | Set to `1` to make the workflow fail (exit 2) when drift is found. Default is to always succeed — drift is reported, not enforced.                                                   |
| `SKIP_FETCH`             | `0`                     | Set to `1` to skip `git fetch` (useful for local runs against already-fetched refs).                                                                                                 |

In the GitHub workflow, `RELEASE_BRANCH_PATTERN`, `TRUNK_BRANCH`,
`COMPARE_ALL_VS_TRUNK`, and `RELEASE_TAG_PATTERN` are exposed as
`workflow_dispatch` inputs so you can override them ad hoc.

## How to read the report

The report has six sections:

1. **Configuration** — every knob the script used (pattern, trunk, scope, etc.).
2. **Summary** — total drifted commits, pairs with drift, **released vs
   unreleased** counts, and oldest / newest drifting commit dates.
3. **Release branches** — semver-sorted, with the **Latest release** tag
   reachable from each branch tip (linked to the GitHub release page). The
   release marked **★ latest** is whichever GitHub considers the current
   "latest" release, as reported by `gh release list`.
4. **Top contributors to drift** — global authors rolled up across all pairs.
5. **Merge feasibility** — for each pair, whether the forward-merge would
   apply cleanly. See [Merge feasibility](#merge-feasibility) below.
6. **Findings by branch pair**, split into two subsections:

   - **Adjacent release pairs** — older release → next release.
   - **Release branches vs trunk** — every release branch (or just the newest
     depending on `COMPARE_ALL_VS_TRUNK`) compared against trunk.

   Each pair links to a GitHub compare view and, when drift exists, includes a
   commit table with **SHA, date, author, PR (if extractable from the
   subject), Released in tag, and subject**. The "Released in" column shows
   the earliest release tag whose history contains the commit, or
   `_unreleased_` when no tag contains it yet.

The CI job also writes the report to the GitHub Actions job summary, so you
can read it without downloading the artifact.

### Merge feasibility

For every branch pair the report also includes a virtual forward-merge result,
answering: **if you tried to merge `older` into `newer` right now, would it
apply cleanly?** This uses `git merge-tree`, which performs the merge in
memory — no branches, refs, or working trees are touched.

The markdown table shows, per pair:

- **✅ clean** — the forward-merge would apply without conflicts.
- **⚠️ N conflict(s)** — followed by the first 5 conflicting paths
  (more are summarised as _"and N more"_).
- **❔ unknown** — the merge probe failed (e.g. no common ancestor, or git
  too old; see below). The reason is shown inline.

The same data is emitted in machine-readable form as `merge-status.json`
(uploaded as part of the `release-drift-report` artifact alongside the
markdown). Shape:

```json
{
  "generated_at": "2026-05-14T22:57:21Z",
  "summary": { "total_pairs": 7, "clean": 6, "conflicting": 1, "unknown": 0 },
  "pairs": [
    {
      "older": "v2.5.2",
      "newer": "master",
      "kind": "trunk",
      "clean": false,
      "conflicts": [".github/workflows/ci.yml", "..."]
    }
  ]
}
```

#### Git version

Modern `git merge-tree --write-tree` (Git ≥ 2.38) is used when available; it
returns conflicting paths directly. On older git, the script falls back to
the legacy 3-arg form and parses its output for conflict markers inside
`changed in both` / `added in both` sections. Both code paths produce the
same JSON shape. The CI runner (`ubuntu-latest`) has Git ≥ 2.43, so the
modern path is taken there.

### Release tag markers

When the workflow runs in CI (or locally with an authenticated `gh` CLI), the
script enriches release tags with GitHub Release metadata:

- **★ latest** — the GitHub Release marked as "Latest".
- **(pre)** — flagged as a pre-release on GitHub.

### What if I don't have `gh` access?

The `gh` CLI is **optional**. The script auto-detects whether it can use it
and falls back cleanly when it can't. Three things can go wrong:

| Situation                                                     | What the script does                                                                             |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `gh` not on PATH                                              | Logs `gh CLI unavailable or unauthenticated — tag-only release info`, skips the enrichment step. |
| `gh` installed but not authenticated (`gh auth status` fails) | Same — silent fallback to tag-only mode.                                                         |
| `gh release list` fails (network / auth / API error)          | Logs a warning, continues without release markers.                                               |

In every fallback path you still get:

- The **Released in** column (computed from local git tags via `git tag --contains`).
- The **Latest release** column for each branch (computed from `git tag --merged`).
- Clickable links to each tag's GitHub release page (just URL templating — no API needed).

What you lose without `gh`: only the **★ latest** and **(pre)** marker
decorations on those tag links. The data itself is unchanged.

In the CI workflow, `gh` is preinstalled on `ubuntu-latest` runners and
authenticated via `GITHUB_TOKEN` (already provided to the workflow), so
enrichment Just Works. For local runs without `gh`, simply
`brew install gh && gh auth login` if you want the markers, otherwise skip
it.

## Running on PRs

The workflow also fires on `pull_request` events with `types: [opened]` —
meaning every time a PR is opened, the drift report is generated once.
Subsequent pushes to the PR do **not** re-run the check (use a manual
dispatch or wait for the Monday schedule if you want a refresh).

The report appears under the PR's **Checks** tab as a Job Summary and as the
`release-drift-report` artifact, identical to a scheduled run.

Scheduled (Monday) and manual-dispatch runs are unaffected — they always run.

## Adopting in another repo

1. Copy `scripts/check-release-drift.mjs` into the target repo (any path is
   fine; the workflow references it by relative path).
2. Copy `.github/workflows/release-drift.yml`.
3. If your release branches do not match `v[0-9]*.[0-9]*.[0-9]*`, edit the
   default for `RELEASE_BRANCH_PATTERN` in the workflow (and/or override at
   dispatch time). Common alternatives:
   - `release/*`
   - `release-[0-9]*`
4. If trunk is not `master`, update `TRUNK_BRANCH` similarly.
5. Commit and push. The first scheduled run will produce the first report; you
   can also trigger one immediately via **Actions → Release Branch Drift
   Detection → Run workflow**.

## Running locally

From a clone with all release branches available:

```bash
git fetch --prune origin
node scripts/check-release-drift.mjs
cat drift-report.md
```

Override config inline (e.g. skip the fetch against already-local refs):

```bash
SKIP_FETCH=1 RELEASE_BRANCH_PATTERN='v[0-9]*.[0-9]*.[0-9]*' \
  node scripts/check-release-drift.mjs
```

`drift-report.md` and `merge-status.json` are build artifacts — they are
git-ignored, so a local run won't leave anything tracked.

## Known limitations

- **Patch-id is content-based.** A commit whose change is later reapplied with
  a substantive edit (not a clean cherry-pick) will still show as drift —
  that's usually the right call, but worth knowing.
- **Reverts are detected by message text.** The filter relies on the standard
  `This reverts commit <sha>` line that `git revert` produces. Hand-written
  reverts that omit that line will not be filtered.
- **Allowlist not implemented.** If a commit is intentionally not being
  forward-merged, today it will keep appearing. Adding an allowlist is in the
  out-of-scope list for phase 1 — revisit if reports get noisy.

## Phase 2 / 3 (not in this change)

- Phase 2: open automated forward-merge PRs between release branches.
- Phase 3: trunk-based development with explicit backport tooling.

[lps]: https://github.com/rsksmart/liquidity-provider-server
[fly2292]: https://rsklabs.atlassian.net/browse/FLY-2292
[fly2319]: https://rsklabs.atlassian.net/browse/FLY-2319
