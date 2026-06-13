# Feature Specification: Docs Release Versioning

**Feature Branch**: `013-docs-release-versioning`  
**Created**: 2026-06-05  
**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Cut a release and ship docs without the pre-release banner (Priority: P1)

A developer (or CI) is ready to submit a new App Store release. They run a single
script (or trigger a single action) that rebuilds all in-app HTML docs without the
`--beta` flag, commits those files, and tags the resulting commit with the version
number. The tagged commit is what gets submitted to App Store.

**Why this priority**: Every App Store release currently ships the "⚠️ Pre-release —
subject to change" banner to real users. That is the primary user-visible bug this
feature fixes.

**Independent Test**: Run the script for a fake version (e.g. `2.7.14-test`). Verify
the committed HTML files contain no `pre-release-banner` div. Verify the git tag
exists. No App Store submission required to validate this story.

**Acceptance Scenarios**:

1. **Given** the current branch is `main` with no uncommitted changes, **When** the
   developer runs `bash scripts/cut-release-docs.sh 2.7.14`, **Then** the script runs
   `build-docs.sh` without `--beta`, commits the updated HTML with message
   `docs: rebuild for v2.7.14 release`, and creates an annotated git tag `v2.7.14`.

2. **Given** the script has completed, **When** any bundled HTML doc page is opened
   in the app, **Then** no element with class `pre-release-banner` is present in the
   HTML.

3. **Given** `main` has uncommitted changes, **When** the script is run, **Then** it
   exits with a non-zero code and a clear error message without modifying anything.

---

### User Story 2 — GitHub Action validates in-app docs are not in pre-release state on a tag push (Priority: P2)

When a `v*.*.*` tag is pushed, a GitHub Action confirms that the bundled HTML files
do not contain the pre-release banner. If they do, the workflow fails visibly so the
release can be corrected before App Store submission.

**Why this priority**: Prevents accidentally shipping the beta banner to the App Store
even if the script in Story 1 was not run (e.g., the tag was pushed manually).

**Independent Test**: Push a test tag on a branch where HTML still has the banner;
confirm the workflow reports a failure. Push a tag after running the release script;
confirm the workflow passes.

**Acceptance Scenarios**:

1. **Given** a `v*.*.*` tag is pushed where bundled HTML contains `pre-release-banner`,
   **When** the validation workflow runs, **Then** the workflow fails with a message
   identifying which HTML files still contain the banner.

2. **Given** a `v*.*.*` tag is pushed after `cut-release-docs.sh` was run, **When**
   the validation workflow runs, **Then** the workflow passes with a green check.

---

### User Story 3 — Return to pre-release state after a release tag (Priority: P3)

After a release tag is cut, the next development cycle should immediately restore the
`--beta` flag so that docs commits on `main` go back to the pre-release state. This
is automatic and requires no manual step.

**Why this priority**: Prevents a window where in-progress post-release changes are
incorrectly presented as stable in TestFlight builds.

**Independent Test**: After tagging, merge one doc change to `main` (triggering the
existing `docs-deploy.yml` action). Confirm the updated HTML contains the
`pre-release-banner` div again.

**Acceptance Scenarios**:

1. **Given** a release tag has been created, **When** a subsequent doc change is
   committed and built on `main` via the normal `build-docs.sh --beta` call,
   **Then** the committed HTML contains the pre-release banner.

---

### Edge Cases

- What if the version argument does not match `MARKETING_VERSION` in `project.pbxproj`?
  → Script exits with a clear mismatch error showing both values before touching anything.
- What if the version argument is missing or malformed (e.g. not `X.Y.Z`)?
  → Script exits with a usage error before modifying anything.
- What if the git tag already exists?
  → Script exits with an error rather than force-overwriting an existing tag.
- What if `build-docs.sh` or `copy-snapshots.sh` fails mid-run?
  → Script exits immediately (`set -e`); no partial commit is created.
- What if the working tree is dirty (uncommitted changes)?
  → Script detects this and exits before touching any files.
- What about the Jekyll/GitHub Pages site — does it also need to drop the banner?
  → The existing `docs-release.yml` already builds the Jekyll site on tag push.
  The script just needs to ensure the in-app HTML (bundled with the app binary) is
  also rebuilt. The Jekyll build is independent and does not use `--beta`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A script `scripts/cut-release-docs.sh` MUST accept a single positional
  argument: the release version string (e.g. `2.7.14`).
- **FR-002**: The script MUST refuse to run if `docs/`, `Meshtastic/Resources/docs/`,
  or `scripts/` contain staged or unstaged **tracked** changes. Untracked files and
  changes to other paths (e.g., Swift source files) do not block the script.
- **FR-003**: The script MUST rebuild the in-app docs by calling
  `bash scripts/build-docs.sh --output Meshtastic/Resources/docs` **without** the
  `--beta` flag.
- **FR-004**: The script MUST call `bash scripts/copy-snapshots.sh` after rebuilding
  so that doc-referenced screenshots are up to date.
- **FR-004a**: After copying, the script MUST check whether any doc-referenced PNG
  under `Meshtastic/Resources/docs/assets/screenshots/` is older than the newest
  `.md` file under `docs/`. If so, it MUST print a **warning** (non-blocking) listing
  the stale files and advising the developer to regenerate snapshots before shipping.
- **FR-005**: The script MUST `git add` only the `Meshtastic/Resources/docs/` subtree
  and commit with a deterministic message: `docs: rebuild for v<version> release`.
- **FR-006**: The script MUST create an annotated git tag `v<version>` (using
  `git tag -a`, not GPG/SSH-signed) pointing at the new commit, with a tag message
  `Release v<version>`.
- **FR-007**: A GitHub Actions workflow (`docs-release-gate.yml`) MUST trigger on
  `push: tags: v*.*.*` and scan every `*.html` file under `Meshtastic/Resources/docs/`
  for the string `pre-release-banner`. The workflow MUST fail if any match is found.
  This is an **advisory check** — it does not block the tag push or App Store
  submission pipeline; it alerts the developer to recut the tag.
- **FR-008**: The validation workflow MUST report which files still contain the banner
  so the developer can act on the output without guessing.
- **FR-009**: The script MUST print a summary of what it did (files changed, commit
  hash, tag name) on success.
- **FR-010**: The script MUST be runnable on macOS (the developer's machine) without
  additional dependencies beyond what is already required by `build-docs.sh`
  (i.e., `cmark-gfm` via Homebrew).
- **FR-011**: Before rebuilding docs, the script MUST extract every `MARKETING_VERSION`
  value from `Meshtastic.xcodeproj/project.pbxproj`. It MUST fail if:
  (a) the values are not all identical (inconsistent project state), or
  (b) the single resolved value does not match the version argument.
  In both cases it MUST exit non-zero with a message showing the found values and
  the argument, and no files are modified.

### Key Entities

- **`scripts/cut-release-docs.sh`**: New shell script that orchestrates the release
  doc build, commit, and tag.
- **`.github/workflows/docs-release-gate.yml`**: New GitHub Actions workflow that
  validates no pre-release banner exists in bundled HTML when a version tag is pushed.
- **`Meshtastic/Resources/docs/` (HTML files)**: In-app bundled docs. These are the
  artefacts whose state changes between beta and release builds.
- **`scripts/build-docs.sh` (existing)**: Already supports `--beta` / no-`--beta`.
  No changes needed to this script.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: App Store builds of `v2.7.14` and later contain zero instances of the
  string `pre-release-banner` in any bundled HTML file.
- **SC-002**: The entire release-cut process (script + tag) completes in under
  60 seconds on a developer machine with an already-built snapshot cache.
- **SC-003**: The validation workflow catches a banner-present tag push 100% of the
  time before the build reaches App Store Connect.
- **SC-004**: Zero additional manual steps are required beyond running
  `bash scripts/cut-release-docs.sh <version>`.

## Clarifications

### Session 2026-06-05

- Q: Should the git tag be GPG/SSH-signed or annotated only? → A: Annotated only (`git tag -a`); no signing key required.
- Q: Should the dirty-tree check block on any uncommitted file or only docs-related paths? → A: Block only on changes within `docs/`, `Meshtastic/Resources/docs/`, or `scripts/`.
- Q: Should stale doc screenshots block the release script or just warn? → A: Warn (non-blocking); list stale PNGs but do not exit non-zero.
- Q: Should `docs-release-gate.yml` be a required status check or advisory? → A: Advisory only; workflow fails loudly but does not block the tag push pipeline.
- Q: Should the script update or verify MARKETING_VERSION? → A: Verify only — the version arg must match the pre-existing MARKETING_VERSION in project.pbxproj; fail if mismatched. All MARKETING_VERSION entries in project.pbxproj will be identical for a valid release.

## Assumptions

- `cmark-gfm` is already installed on the developer's machine (required by
  `build-docs.sh`).
- The release version string matches the `MARKETING_VERSION` in the Xcode project.
  The script verifies this match and fails fast if they differ. `MARKETING_VERSION`
  will have been updated in a prior commit (often weeks earlier, while the build
  was in TestFlight).
- Snapshot images under `Meshtastic/Resources/docs/assets/screenshots/` are already
  current (generated by a prior snapshot test run); the script calls
  `copy-snapshots.sh` to ensure they are in place but does not regenerate them.
- GitHub Pages (Jekyll) docs versioning is out of scope — the existing
  `docs-release.yml` workflow already handles that correctly on tag push.
- Only the in-app bundled HTML (`Meshtastic/Resources/docs/*.html`) requires the
  beta/release distinction; the markdown source files under `docs/` are unaffected.
