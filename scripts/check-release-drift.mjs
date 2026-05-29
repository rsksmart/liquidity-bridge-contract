#!/usr/bin/env node
// scripts/check-release-drift.mjs
//
// Detects commits present on older release branches but missing from newer
// ones. Detection-only — no branches are modified. See docs/release-drift.md.
//
// Exit codes:
//   0  success (drift may or may not have been found)
//   1  fatal error
//   2  drift detected AND EXIT_NONZERO_ON_DRIFT=1

import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const cfg = {
  branchPattern:      process.env.RELEASE_BRANCH_PATTERN ?? 'v[0-9]*.[0-9]*.[0-9]*',
  tagPattern:         process.env.RELEASE_TAG_PATTERN    ?? 'v[0-9]*',
  trunk:              process.env.TRUNK_BRANCH           ?? 'master',
  remote:             process.env.REMOTE                 ?? 'origin',
  reportFile:         process.env.REPORT_FILE            ?? 'drift-report.md',
  mergeStatusFile:    process.env.MERGE_STATUS_FILE      ?? 'merge-status.json',
  compareAllVsTrunk:  (process.env.COMPARE_ALL_VS_TRUNK ?? '1') === '1',
  exitNonzeroOnDrift: process.env.EXIT_NONZERO_ON_DRIFT === '1',
  skipFetch:          process.env.SKIP_FETCH === '1',
};

// ---------------------------------------------------------------------------
// Pretty logging (color only when stderr is a TTY)
// ---------------------------------------------------------------------------

const tty = process.stderr.isTTY;
const c = tty
  ? { reset: '\x1b[0m', bold: '\x1b[1m', blue: '\x1b[34m', green: '\x1b[32m', yellow: '\x1b[33m', red: '\x1b[31m' }
  : { reset: '', bold: '', blue: '', green: '', yellow: '', red: '' };

const log = {
  info: (m) => process.stderr.write(`${c.blue}[info]${c.reset} ${m}\n`),
  ok:   (m) => process.stderr.write(`${c.green}[ok]${c.reset}   ${m}\n`),
  warn: (m) => process.stderr.write(`${c.yellow}[warn]${c.reset} ${m}\n`),
  err:  (m) => process.stderr.write(`${c.red}[err]${c.reset}  ${m}\n`),
  step: (m) => process.stderr.write(`\n${c.blue}==>${c.reset} ${c.bold}${m}${c.reset}\n`),
};

// ---------------------------------------------------------------------------
// Thin git wrapper
// ---------------------------------------------------------------------------

function git(...args) {
  return execFileSync('git', args, {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function gitOk(...args) {
  try { return git(...args); } catch { return ''; }
}

const gitLines = (...args) => gitOk(...args).split('\n').filter((l) => l.length > 0);

// ---------------------------------------------------------------------------
// Semver-aware comparator: stable > pre-release.
// git's --sort=v:refname puts `v2.5.0-rc` AFTER `v2.5.0`, which is the
// opposite of semver where pre-releases precede the stable version.
// ---------------------------------------------------------------------------

function semverCmp(a, b) {
  const parse = (v) => {
    const stripped = v.replace(/^v/, '');
    const dash = stripped.indexOf('-');
    const core = dash >= 0 ? stripped.slice(0, dash) : stripped;
    const pre  = dash >= 0 ? stripped.slice(dash + 1) : '';
    const nums = core.split('.').map((n) => Number(n) || 0);
    return { nums, pre };
  };
  const pa = parse(a), pb = parse(b);
  const n = Math.max(pa.nums.length, pb.nums.length);
  for (let i = 0; i < n; i++) {
    const diff = (pa.nums[i] ?? 0) - (pb.nums[i] ?? 0);
    if (diff !== 0) return diff;
  }
  if (pa.pre === pb.pre) return 0;
  if (!pa.pre) return 1;
  if (!pb.pre) return -1;
  return pa.pre < pb.pre ? -1 : 1;
}

// ---------------------------------------------------------------------------
// Preflight
// ---------------------------------------------------------------------------

try { git('--version'); } catch { log.err('git is required'); process.exit(1); }

if (cfg.skipFetch) {
  log.info('Skipping fetch (SKIP_FETCH=1)');
} else {
  log.step(`Fetching from remote '${cfg.remote}'`);
  git('fetch', '--quiet', '--prune', cfg.remote);
  log.ok('Fetched');
}

// ---------------------------------------------------------------------------
// Detect github.com repo (owner/name) from the remote URL.
// Empty when the remote isn't on github.com.
// ---------------------------------------------------------------------------

function detectGithubSlug() {
  const url = gitOk('remote', 'get-url', cfg.remote).trim();
  const m = url.match(/^(?:git@github\.com:|https:\/\/github\.com\/)(.+?)(?:\.git)?$/);
  return m?.[1] ?? '';
}

const ghSlug = detectGithubSlug();
if (ghSlug) log.info(`GitHub remote detected: ${ghSlug} (compare links will be rendered)`);
else log.info('Non-GitHub remote: compare links will be omitted');

// ---------------------------------------------------------------------------
// Discover release branches
// ---------------------------------------------------------------------------

log.step(`Discovering release branches matching '${cfg.branchPattern}'`);

const generatedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

const remotePrefix = `${cfg.remote}/`;
const releaseBranches = gitLines(
  'for-each-ref', '--format=%(refname:short)',
  `refs/remotes/${cfg.remote}/${cfg.branchPattern}`,
)
  .map((b) => (b.startsWith(remotePrefix) ? b.slice(remotePrefix.length) : b))
  .sort(semverCmp);

if (releaseBranches.length === 0) {
  log.warn('No release branches matched');
  writeFileSync(cfg.reportFile, `# Release Branch Drift Report

_Generated: ${generatedAt}_

No release branches matched the pattern \`${cfg.branchPattern}\` on remote \`${cfg.remote}\`.
`);
  process.exit(0);
}

log.ok(`Found ${releaseBranches.length} branch(es): ${releaseBranches.join(' ')}`);

// ---------------------------------------------------------------------------
// Build comparison pairs: older → newer (kind = adjacent | trunk)
// ---------------------------------------------------------------------------

const pairs = [];
for (let i = 0; i < releaseBranches.length - 1; i++) {
  pairs.push({ older: releaseBranches[i], newer: releaseBranches[i + 1], kind: 'adjacent' });
}

const trunkPresent = (() => {
  try { git('show-ref', '--quiet', `refs/remotes/${cfg.remote}/${cfg.trunk}`); return true; }
  catch { return false; }
})();

if (trunkPresent) {
  if (cfg.compareAllVsTrunk) {
    for (const b of releaseBranches) {
      if (b !== cfg.trunk) pairs.push({ older: b, newer: cfg.trunk, kind: 'trunk' });
    }
  } else {
    const newest = releaseBranches.at(-1);
    if (newest !== cfg.trunk) pairs.push({ older: newest, newer: cfg.trunk, kind: 'trunk' });
  }
} else {
  log.warn(`Trunk '${cfg.trunk}' not found on remote — skipping trunk comparisons`);
}

log.info(`Will compare ${pairs.length} pair(s) (COMPARE_ALL_VS_TRUNK=${cfg.compareAllVsTrunk ? '1' : '0'})`);

// ---------------------------------------------------------------------------
// Release tags + optional `gh` enrichment for "latest" / "(pre)" markers
// ---------------------------------------------------------------------------

const releaseTags = gitLines('tag', '--list', cfg.tagPattern, '--sort=v:refname');
log.info(`Found ${releaseTags.length} release tag(s) matching '${cfg.tagPattern}'`);

let ghLatestTag = '';
const ghPrereleases = new Set();

if (ghSlug) {
  let ghAvailable = false;
  try { execFileSync('gh', ['auth', 'status'], { stdio: 'ignore' }); ghAvailable = true; } catch {}
  if (ghAvailable) {
    try {
      const raw = execFileSync('gh', [
        'release', 'list', '--repo', ghSlug, '--limit', '200',
        '--json', 'tagName,isLatest,isPrerelease',
      ], { encoding: 'utf8' });
      const releases = JSON.parse(raw);
      ghLatestTag = releases.find((r) => r.isLatest)?.tagName ?? '';
      for (const r of releases) if (r.isPrerelease) ghPrereleases.add(r.tagName);
      log.info(`gh release info: latest='${ghLatestTag}'`);
    } catch {
      log.info('gh release list failed (auth or network) — continuing without release marks');
    }
  } else {
    log.info('gh CLI unavailable or unauthenticated — tag-only release info');
  }
} else {
  log.info('gh CLI unavailable or unauthenticated — tag-only release info');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function wasRevertedOn(branch, sha) {
  const out = gitLines(
    'log', '--no-merges', `--grep=This reverts commit ${sha}`,
    '--pretty=%H', `${sha}..${cfg.remote}/${branch}`,
  );
  return out.length > 0;
}

const extractPrNumber = (subject) => subject.match(/\(#(\d+)\)\s*$/)?.[1] ?? '';

const mdEscapeCell = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');

function renderSha(sha) {
  const short = sha.slice(0, 12);
  return ghSlug
    ? `[\`${short}\`](https://github.com/${ghSlug}/commit/${sha})`
    : `\`${short}\``;
}

function renderPr(pr) {
  if (!pr) return '';
  return ghSlug
    ? `[#${pr}](https://github.com/${ghSlug}/pull/${pr})`
    : `#${pr}`;
}

function renderCompareLink(older, newer) {
  if (!ghSlug) return '';
  return `https://github.com/${ghSlug}/compare/${newer}...${older}`;
}

// Earliest semver tag containing $sha; prefers stable over pre-release.
function releasedInForSha(sha) {
  const tags = gitLines('tag', '--contains', sha, '--list', cfg.tagPattern);
  if (tags.length === 0) return '';
  const stable = tags.filter((t) => !t.includes('-'));
  const pick = stable.length ? stable : tags;
  return [...pick].sort(semverCmp)[0] ?? '';
}

// Latest semver tag merged into $branch; same stable-then-pre preference.
function latestReleaseForBranch(branch) {
  const tags = gitLines('tag', '--merged', `${cfg.remote}/${branch}`, '--list', cfg.tagPattern);
  if (tags.length === 0) return '';
  const stable = tags.filter((t) => !t.includes('-'));
  const pick = stable.length ? stable : tags;
  return [...pick].sort(semverCmp).at(-1) ?? '';
}

function renderReleaseTag(tag) {
  if (!tag) return '_unreleased_';
  const link = ghSlug
    ? `[\`${tag}\`](https://github.com/${ghSlug}/releases/tag/${tag})`
    : `\`${tag}\``;
  let marker = '';
  if (ghLatestTag && tag === ghLatestTag) marker = ' **★ latest**';
  else if (ghPrereleases.has(tag)) marker = ' _(pre)_';
  return `${link}${marker}`;
}

function counts(items) {
  const m = new Map();
  for (const x of items) m.set(x, (m.get(x) ?? 0) + 1);
  return [...m.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
}

// Detect git version once — `merge-tree --write-tree` requires git >= 2.38.
const gitVersion = (() => {
  const m = gitOk('--version').match(/(\d+)\.(\d+)(?:\.(\d+))?/);
  return m ? { major: +m[1], minor: +m[2] } : null;
})();
const hasModernMergeTree =
  !!gitVersion && (gitVersion.major > 2 || (gitVersion.major === 2 && gitVersion.minor >= 38));

// Dry-run the forward-merge `older → newer` without touching the working
// tree or HEAD. Modern path (git >= 2.38): `merge-tree --write-tree
// --name-only` exits 1 on conflict with the path list on stdout. Legacy
// path (git < 2.38): use the 3-arg form and scan its output for
// `<<<<<<<` markers, attributing each to the most recent metadata line's
// path.
function checkMergeability(older, newer) {
  const olderRef = `${cfg.remote}/${older}`;
  const newerRef = `${cfg.remote}/${newer}`;

  if (hasModernMergeTree) {
    try {
      execFileSync('git', ['merge-tree', '--write-tree', '--name-only', newerRef, olderRef], {
        encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024,
      });
      return { clean: true, conflicts: [] };
    } catch (err) {
      if (err.status === 1 && typeof err.stdout === 'string') {
        const lines = err.stdout.split('\n').filter((l) => l.length > 0);
        return { clean: false, conflicts: lines.slice(1) };
      }
      return { clean: null, error: (err.stderr || err.message || '').toString().trim() };
    }
  }

  try {
    const base = execFileSync('git', ['merge-base', newerRef, olderRef], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
    if (!base) return { clean: null, error: 'no common ancestor' };
    const out = execFileSync('git', ['merge-tree', base, newerRef, olderRef], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 16 * 1024 * 1024,
    });

    // Only `changed in both` / `added in both` sections carry real merge
    // conflicts. Conflict markers appear as `+<<<<<<<` lines in the
    // unified diff. A `<<<<<<<` substring inside an `added in <branch>`
    // section is just file content (e.g. docs explaining merge markers)
    // and must be ignored.
    const conflicts = new Set();
    let inConflictSection = false;
    let currentPath = null;
    for (const line of out.split('\n')) {
      if (line === 'changed in both' || line === 'added in both') {
        inConflictSection = true;
        currentPath = null;
        continue;
      }
      if (/^(added|removed) in /.test(line)) {
        inConflictSection = false;
        currentPath = null;
        continue;
      }
      const meta = line.match(/^  (?:our|their|base)\s+\d+\s+[0-9a-f]+\s+(.+)$/);
      if (meta) {
        if (inConflictSection) currentPath = meta[1];
        continue;
      }
      if (inConflictSection && currentPath && /^\+<<<<<<< /.test(line)) {
        conflicts.add(currentPath);
      }
    }
    return { clean: conflicts.size === 0, conflicts: [...conflicts] };
  } catch (err) {
    return { clean: null, error: (err.stderr || err.message || '').toString().trim() };
  }
}

// ---------------------------------------------------------------------------
// Analyse each pair
// ---------------------------------------------------------------------------

log.step('Analysing pairs');

const results = [];
for (const { older, newer, kind } of pairs) {
  const olderRef = `${cfg.remote}/${older}`;
  const newerRef = `${cfg.remote}/${newer}`;

  const raw = gitLines(
    'log', '--cherry-pick', '--left-only', '--no-merges',
    '--pretty=format:%H\t%an\t%ae\t%aI\t%s',
    `${olderRef}...${newerRef}`,
  );

  const commits = [];
  for (const line of raw) {
    // Subjects may contain tabs; only the first 4 fields are fixed.
    const parts = line.split('\t');
    if (parts.length < 5) continue;
    const [sha, author, email, date, ...rest] = parts;
    const subject = rest.join('\t');
    if (subject.startsWith('Revert "')) continue;
    if (wasRevertedOn(older, sha)) continue;
    commits.push({
      sha, author, email, date, subject,
      pr: extractPrNumber(subject),
      releasedIn: releasedInForSha(sha),
    });
  }

  const merge = checkMergeability(older, newer);
  const mergeLabel = merge.clean === true
    ? 'clean'
    : merge.clean === false
      ? `${merge.conflicts.length} conflict(s)`
      : 'unknown';
  log.info(`  ${older} → ${newer}: ${commits.length} drifted commit(s), merge ${mergeLabel}`);
  results.push({ older, newer, kind, commits, merge });
}

// ---------------------------------------------------------------------------
// Aggregate stats
// ---------------------------------------------------------------------------

const totalDrift        = results.reduce((n, r) => n + r.commits.length, 0);
const pairsWithDrift    = results.filter((r) => r.commits.length > 0).length;
const adjacentPairCount = results.filter((r) => r.kind === 'adjacent').length;
const trunkPairCount    = results.filter((r) => r.kind === 'trunk').length;
const totalReleased     = results.reduce((n, r) => n + r.commits.filter((c) => c.releasedIn).length, 0);
const totalUnreleased   = totalDrift - totalReleased;

const allDriftCommits = results.flatMap((r) =>
  r.commits.map((c) => ({ ...c, pair: `${r.older} → ${r.newer}` })),
);
const oldestDrift = allDriftCommits.length
  ? allDriftCommits.reduce((a, b) => (a.date < b.date ? a : b))
  : null;
const newestDrift = allDriftCommits.length
  ? allDriftCommits.reduce((a, b) => (a.date > b.date ? a : b))
  : null;

// ---------------------------------------------------------------------------
// Render report
// ---------------------------------------------------------------------------

log.step('Writing report');

function renderPair({ older, newer, commits }) {
  const lines = [];
  lines.push(`### \`${older}\` → \`${newer}\``);
  lines.push('');
  const compareUrl = renderCompareLink(older, newer);
  if (compareUrl) {
    lines.push(`[Compare on GitHub →](${compareUrl})`);
    lines.push('');
  }

  if (commits.length === 0) {
    lines.push('_No drift detected._');
    lines.push('');
    return lines.join('\n');
  }

  const dates = commits.map((c) => c.date);
  const oldest = dates.reduce((a, b) => (a < b ? a : b));
  const newest = dates.reduce((a, b) => (a > b ? a : b));
  const released = commits.filter((c) => c.releasedIn).length;
  const unreleased = commits.length - released;
  const authors = counts(commits.map((c) => c.author));

  lines.push(`**${commits.length}** commit(s) present on \`${older}\` but missing from \`${newer}\`.`);
  lines.push('');
  lines.push(`- **Date range:** ${oldest.slice(0, 10)} → ${newest.slice(0, 10)}`);
  lines.push(`- **Distinct authors:** ${authors.length}`);
  lines.push(`- **Released / unreleased:** ${released} / ${unreleased}`);
  lines.push('');
  lines.push('<details>');
  lines.push('<summary>Top authors</summary>');
  lines.push('');
  lines.push('| Commits | Author |');
  lines.push('| ---: | --- |');
  for (const [name, count] of authors.slice(0, 5)) {
    lines.push(`| ${count} | ${mdEscapeCell(name)} |`);
  }
  lines.push('');
  lines.push('</details>');
  lines.push('');
  lines.push('| # | SHA | Date | Author | PR | Released in | Subject |');
  lines.push('| ---: | --- | --- | --- | --- | --- | --- |');
  commits.forEach((commit, i) => {
    lines.push(
      `| ${i + 1} | ${renderSha(commit.sha)} | ${commit.date.slice(0, 10)} | ${mdEscapeCell(commit.author)} | ${renderPr(commit.pr)} | ${renderReleaseTag(commit.releasedIn)} | ${mdEscapeCell(commit.subject)} |`,
    );
  });
  lines.push('');
  return lines.join('\n');
}

const out = [];

out.push('# Release Branch Drift Report');
out.push('');
out.push(`_Generated: ${generatedAt}_`);
out.push('');

// Configuration block
out.push('## Configuration');
out.push('');
out.push('| Setting | Value |');
out.push('| --- | --- |');
out.push(`| Release branch pattern | \`${cfg.branchPattern}\` |`);
out.push(`| Trunk branch | \`${cfg.trunk}\` |`);
out.push(`| Remote | \`${cfg.remote}\` |`);
out.push(cfg.compareAllVsTrunk
  ? '| Trunk comparison scope | every release branch vs trunk |'
  : '| Trunk comparison scope | newest release vs trunk only |');
if (ghSlug) out.push(`| GitHub repository | [\`${ghSlug}\`](https://github.com/${ghSlug}) |`);
out.push('');

// Headline summary
out.push('## Summary');
out.push('');
if (totalDrift === 0) {
  out.push(`**No drift detected** across ${pairs.length} branch pair(s).`);
} else {
  out.push(`**${totalDrift}** commit(s) drifted across **${pairsWithDrift}** of **${pairs.length}** branch pair(s).`);
  out.push('');
  out.push('| Metric | Value |');
  out.push('| --- | --- |');
  out.push(`| Total drifted commits | ${totalDrift} |`);
  out.push(`| Pairs with drift | ${pairsWithDrift} / ${pairs.length} |`);
  out.push(`| Released (in a tagged release) | ${totalReleased} |`);
  out.push(`| Unreleased | ${totalUnreleased} |`);
  if (oldestDrift) out.push(`| Oldest drifted commit | ${oldestDrift.date.slice(0, 10)} (in \`${oldestDrift.pair}\`) |`);
  if (newestDrift) out.push(`| Newest drifted commit | ${newestDrift.date.slice(0, 10)} (in \`${newestDrift.pair}\`) |`);
  out.push('');
  if (ghLatestTag) {
    out.push(`_GitHub "latest" release marker reflects the current \`gh release view --json isLatest\` answer for \`${ghSlug}\`._`);
    out.push('');
  }
}

// Branches table
out.push('## Release branches (semver-sorted)');
out.push('');
out.push('| # | Branch | Latest release | Tip commit |');
out.push('| ---: | --- | --- | --- |');
releaseBranches.forEach((b, i) => {
  const tipSha     = gitOk('rev-parse', `${cfg.remote}/${b}`).trim();
  const tipDate    = gitOk('log', '-1', '--pretty=%aI', `${cfg.remote}/${b}`).trim();
  const tipSubject = gitOk('log', '-1', '--pretty=%s', `${cfg.remote}/${b}`).trim();
  const latestTag  = latestReleaseForBranch(b);
  out.push(
    `| ${i + 1} | \`${b}\` | ${renderReleaseTag(latestTag)} | ${renderSha(tipSha)} · ${tipDate.slice(0, 10)} · ${mdEscapeCell(tipSubject)} |`,
  );
});
out.push('');

// Global top contributors
if (totalDrift > 0) {
  out.push('## Top contributors to drift (all pairs)');
  out.push('');
  out.push('| Commits | Author |');
  out.push('| ---: | --- |');
  for (const [name, count] of counts(allDriftCommits.map((c) => c.author)).slice(0, 10)) {
    out.push(`| ${count} | ${mdEscapeCell(name)} |`);
  }
  out.push('');
}

// Merge feasibility
out.push('## Merge feasibility');
out.push('');
out.push('_Dry-run forward-merges via `git merge-tree` — no branches are modified._');
out.push('');
out.push('| Older | Newer | Result | Conflicting files |');
out.push('| --- | --- | --- | --- |');
const MERGE_CONFLICT_PREVIEW = 5;
for (const r of results) {
  const { older, newer, merge } = r;
  let resultCell, filesCell;
  if (merge.clean === true) {
    resultCell = '✅ clean';
    filesCell = '—';
  } else if (merge.clean === false) {
    resultCell = `⚠️ ${merge.conflicts.length} conflict(s)`;
    const preview = merge.conflicts.slice(0, MERGE_CONFLICT_PREVIEW).map((p) => `\`${mdEscapeCell(p)}\``).join(', ');
    const extra = merge.conflicts.length > MERGE_CONFLICT_PREVIEW
      ? ` _(and ${merge.conflicts.length - MERGE_CONFLICT_PREVIEW} more)_`
      : '';
    filesCell = preview + extra;
  } else {
    resultCell = '❔ unknown';
    filesCell = merge.error ? `_${mdEscapeCell(merge.error)}_` : '—';
  }
  out.push(`| \`${older}\` | \`${newer}\` | ${resultCell} | ${filesCell} |`);
}
out.push('');

// Per-pair detailed sections
out.push('## Findings by branch pair');
out.push('');

if (adjacentPairCount > 0) {
  out.push('### Adjacent release pairs');
  out.push('');
  out.push('_Older release → next release. These commits were never propagated forward to the next semver release._');
  out.push('');
  for (const r of results) {
    if (r.kind === 'adjacent') out.push(renderPair(r));
  }
}

if (trunkPairCount > 0) {
  out.push(`### Release branches vs trunk (\`${cfg.trunk}\`)`);
  out.push('');
  out.push(cfg.compareAllVsTrunk
    ? '_Every release branch is compared against trunk. Commits listed are present on the release branch but missing from trunk — usually fixes that need to be forward-merged._'
    : '_Newest release vs trunk. Commits on the release branch missing from trunk._');
  out.push('');
  for (const r of results) {
    if (r.kind === 'trunk') out.push(renderPair(r));
  }
}

out.push('---');
out.push('');
out.push('_This is a detection-only report. No branches were modified._');
out.push('_Generated by `scripts/check-release-drift.mjs` — see `docs/release-drift.md`._');

writeFileSync(cfg.reportFile, out.join('\n') + '\n');

const mergeStatus = {
  generated_at: generatedAt,
  summary: {
    total_pairs: results.length,
    clean:       results.filter((r) => r.merge.clean === true).length,
    conflicting: results.filter((r) => r.merge.clean === false).length,
    unknown:     results.filter((r) => r.merge.clean === null).length,
  },
  pairs: results.map((r) => ({
    older: r.older,
    newer: r.newer,
    kind:  r.kind,
    clean: r.merge.clean,
    conflicts: r.merge.conflicts ?? [],
    ...(r.merge.error ? { error: r.merge.error } : {}),
  })),
};
writeFileSync(cfg.mergeStatusFile, JSON.stringify(mergeStatus, null, 2) + '\n');

log.ok(`Report written: ${cfg.reportFile}`);
log.ok(`Merge status written: ${cfg.mergeStatusFile}`);
if (totalDrift === 0) log.ok('No drift detected');
else log.warn(`Total drift commits: ${totalDrift} (across ${pairsWithDrift} / ${pairs.length} pairs)`);
log.info(`Mergeability: ${mergeStatus.summary.clean} clean / ${mergeStatus.summary.conflicting} conflicting / ${mergeStatus.summary.unknown} unknown`);

if (cfg.exitNonzeroOnDrift && totalDrift > 0) process.exit(2);
process.exit(0);