# Research: Docs Release Versioning

**Phase 0 output for plan.md**  
**Date**: 2026-06-05

---

## R-001: Extracting MARKETING_VERSION from project.pbxproj

**Decision**: Use `grep` + `sort -u` to extract all distinct values, then assert
exactly one unique value that matches the version argument.

**Rationale**: `project.pbxproj` is a plain-text file with multiple
`MARKETING_VERSION = X.Y.Z;` entries (one per build configuration × target).
For a correctly-prepared release all entries will be identical, so deduplicating
with `sort -u` produces exactly one line. The script can then compare that single
value to the argument. If `sort -u` yields more than one value, the project is in
an inconsistent state and the script should fail with a clear message showing all
found values.

**Implementation pattern**:
```bash
mapfile -t versions < <(grep -E 'MARKETING_VERSION = [0-9]' \
    Meshtastic.xcodeproj/project.pbxproj \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)

if [[ ${#versions[@]} -ne 1 ]]; then
    echo "error: inconsistent MARKETING_VERSION values: ${versions[*]}" >&2
    exit 1
fi
if [[ "${versions[0]}" != "$VERSION" ]]; then
    echo "error: argument '$VERSION' does not match MARKETING_VERSION '${versions[0]}'" >&2
    exit 1
fi
```

**Alternatives considered**:
- `PlistBuddy` — only works on `.plist` files, not `.pbxproj`
- `xcodebuild -showBuildSettings` — slow (~5s) and requires a full Xcode build
  environment; overkill for a version string read
- `agvtool mktg-version` — depends on `agvtool` being installed; same overhead

---

## R-002: Detecting dirty docs-related paths in git

**Decision**: Use `git status --porcelain` filtered to the three relevant path
prefixes (`docs/`, `Meshtastic/Resources/docs/`, `scripts/`). Any non-empty
output = dirty.

**Rationale**: `git diff --quiet` checks the index vs. working tree but misses
staged changes. `git status --porcelain` covers both staged and unstaged changes
in a single call. Filtering to the three prefixes avoids blocking developers who
have unrelated Swift files modified — consistent with clarification Q2.

**Implementation pattern**:
```bash
dirty=$(git status --porcelain -- docs/ Meshtastic/Resources/docs/ scripts/ \
    | grep -v '^?' || true)
if [[ -n "$dirty" ]]; then
    echo "error: docs-related paths have uncommitted changes:" >&2
    echo "$dirty" >&2
    exit 1
fi
```

Note: `grep -v '^?'` excludes untracked files (the spec only references
"uncommitted changes"; untracked files outside the docs tree are benign).

**Alternatives considered**:
- `git diff --quiet HEAD -- <paths>` — misses staged-but-not-committed changes
- Checking the entire working tree — too strict per clarification Q2

---

## R-003: Stale PNG detection

**Decision**: Compare the modification time of the newest `.md` file under `docs/`
against the oldest doc-referenced PNG under
`Meshtastic/Resources/docs/assets/screenshots/`. If the oldest PNG is older than
the newest `.md`, emit a warning.

**Rationale**: The script should not block on stale PNGs (clarification Q3 — warn
only). The comparison is a `find` + `stat` operation that runs in <1s and gives
the developer actionable information.

**Implementation pattern**:
```bash
newest_md=$(find docs -name '*.md' -newer /dev/null -print0 \
    | xargs -0 stat -f '%m %N' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
oldest_png=$(find Meshtastic/Resources/docs/assets/screenshots -name '*.png' \
    -print0 | xargs -0 stat -f '%m %N' 2>/dev/null | sort -n | head -1 | awk '{print $2}')

if [[ -n "$oldest_png" && "$newest_md" -nt "$oldest_png" ]]; then
    echo "warning: some doc screenshots may be stale (newest .md is newer than $oldest_png)" >&2
    echo "warning: run snapshot tests and copy-snapshots.sh before submitting to App Store" >&2
fi
```

Note: `stat -f` is macOS-specific syntax (GNU `stat -c` on Linux).
The warning path in the script is macOS-only (the script is a dev tool — FR-010).

**Alternatives considered**:
- Date-threshold (e.g., >7 days) — arbitrary and fragile for repos with infrequent
  doc changes; file-relative comparison is more meaningful
- Blocking — rejected per clarification Q3

---

## R-004: Relationship between docs-release.yml and docs-release-gate.yml

**Decision**: Keep the two workflows fully independent. `docs-release.yml` (existing)
deploys the Jekyll/GitHub Pages site. The new `docs-release-gate.yml` checks bundled
HTML. They both trigger on `v*.*.*` tags but have no dependency on each other.

**Rationale**: The Jekyll site build does not use `--beta` and is therefore always
clean — no gate needed for it. The gate is specifically for the in-app HTML that
is committed to the repo. Since the gate is advisory (clarification Q4), there
is no workflow-level dependency to establish.

**Alternatives considered**:
- Adding the gate as a job inside `docs-release.yml` — would couple the two concerns;
  harder to disable independently
- Using `workflow_run` trigger — unnecessary complexity for an advisory check

---

## R-005: copy-snapshots.sh calls cleanup-screenshots.sh — release impact

**Decision**: The `cleanup-screenshots.sh` call at the end of `copy-snapshots.sh`
is safe to run during a release cut. It only removes orphaned PNGs from the source
`docs/assets/screenshots/` directory (files not referenced by any `.md`). It does
not touch `Meshtastic/Resources/docs/assets/screenshots/`.

**Rationale**: Reviewed `copy-snapshots.sh` lines 44-47 — `cleanup-screenshots.sh`
receives no arguments and operates on `docs/assets/screenshots/` (the source
directory), not the output directory. Any files it removes would be orphaned
screenshots that are already not referenced. No risk to release content.

**Alternatives considered**: Skipping `copy-snapshots.sh` for release — rejected
because FR-004 requires it; screenshots must be current in the release bundle.

---

## R-006: Atomic commit strategy

**Decision**: Stage only `Meshtastic/Resources/docs/` with `git add` before
committing. Use `set -euo pipefail` throughout the script so any failure before
the `git commit` call leaves the working tree modified but uncommitted — no partial
state is persisted to history. The developer can simply re-run the script after
fixing the issue.

**Rationale**: The script's dirty-check (FR-002) runs before any files are modified,
so the only way the working tree becomes dirty mid-run is from `build-docs.sh` or
`copy-snapshots.sh` themselves. `set -e` ensures the script exits before `git add`
if those tools fail.

**Alternatives considered**:
- `git stash` / restore on failure — overly complex; not needed given `set -e` ordering
- A separate `--dry-run` flag — nice-to-have but out of scope for v1
