# Quickstart: Cutting a Docs Release

**Phase 1 output for plan.md**  
**Date**: 2026-06-05

---

## Prerequisites

- `cmark-gfm` installed: `brew install cmark-gfm`
- `MARKETING_VERSION` already updated in Xcode project and committed (this is done
  when the build entered TestFlight, weeks before App Store submission)
- Snapshot tests have been run recently (ideally on CI) — see warning note below
- Working tree has no uncommitted changes to `docs/`, `Meshtastic/Resources/docs/`,
  or `scripts/`

---

## The release-cut workflow

### Step 1 — Verify you are on the correct branch

```bash
git branch          # must NOT be main
git log --oneline -3
```

Typically you will run this on a release branch (e.g., `2.7.14-release`) or on
a dedicated commit just before tagging. The script does not enforce which branch
you are on.

### Step 2 — Run the release docs script

```bash
bash scripts/cut-release-docs.sh 2.7.14
```

Replace `2.7.14` with the actual version matching `MARKETING_VERSION` in Xcode.

**What the script does**:
1. Verifies version format and that it matches `MARKETING_VERSION` in `project.pbxproj`
2. Verifies the git tag `v2.7.14` does not already exist
3. Checks that `docs/`, `Meshtastic/Resources/docs/`, and `scripts/` are clean
4. Rebuilds all bundled HTML **without** the pre-release banner
5. Copies current doc-referenced screenshots
6. Warns (non-blocking) if any screenshots appear stale
7. Creates a git commit: `docs: rebuild for v2.7.14 release`
8. Creates an annotated git tag: `v2.7.14`

**Example output**:
```
✓ Rebuilt in-app docs without pre-release banner
✓ 24 files changed in commit a3f9e21
✓ Tag v2.7.14 created → a3f9e21

Next steps:
  git push origin <branch>
  git push origin v2.7.14
```

### Step 3 — Push the commit and tag

```bash
git push origin <your-branch>
git push origin v2.7.14
```

Pushing the tag triggers:
- `docs-release-gate.yml` — advisory banner check (should pass after step 2)
- `docs-release.yml` — deploys the Jekyll site to GitHub Pages

### Step 4 — Submit to App Store via Xcode Cloud

Xcode Cloud picks up the tag commit for the App Store submission as normal.
The in-app HTML in that build will not contain the pre-release banner.

---

## Handling errors

### "does not match MARKETING_VERSION"

The version you passed to the script does not match what is in `project.pbxproj`.

```
error: argument '2.7.14' does not match MARKETING_VERSION '2.7.13'
```

Fix: Either update `MARKETING_VERSION` in Xcode and commit first, or correct
the version argument.

### "tag 'v2.7.14' already exists"

A tag with this name was already created. If you need to recut it:

```bash
git tag -d v2.7.14          # delete local tag
# optionally: git push origin :refs/tags/v2.7.14  (deletes remote)
bash scripts/cut-release-docs.sh 2.7.14
```

### "docs-related paths have uncommitted changes"

You have unstaged or staged changes in `docs/`, `Meshtastic/Resources/docs/`,
or `scripts/`. Commit or stash them first:

```bash
git status -- docs/ Meshtastic/Resources/docs/ scripts/
# commit or stash the relevant changes, then re-run
bash scripts/cut-release-docs.sh 2.7.14
```

### Stale screenshot warning

```
warning: some doc screenshots may be stale (newest .md is newer than <file>)
```

This is non-blocking. The release script continues. To resolve before shipping:
1. Run the Xcode snapshot test suite: `MeshtasticTests/SwiftUIViewSnapshotTests`
2. The screenshots are updated automatically on the next `docs-deploy.yml` CI run

---

## After the release: returning to pre-release state

After the tag is pushed, the next doc change committed to `main` will be built by
the existing `docs-deploy.yml` workflow using `--beta`, restoring the pre-release
banner automatically. No manual action required.

---

## Notes for reviewers

- The commit created by this script (`docs: rebuild for v<version> release`) should
  be the **last** commit before the App Store build is submitted from Xcode Cloud.
- The script is idempotent for the file changes (re-running with the same version
  after deleting the tag produces the same HTML output); only the commit and tag
  are non-idempotent.
- The `Meshtastic/Resources/docs/` HTML files are committed to the repo and bundled
  via the Xcode Copy Files build phase — they are not generated at Xcode Cloud
  build time. The script ensures they are in the correct state before the tag.
