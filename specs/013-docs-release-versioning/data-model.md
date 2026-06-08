# Data Model: Docs Release Versioning

**Phase 1 output for plan.md**  
**Date**: 2026-06-05

This feature has no database entities or SwiftData models. The "data" is a set
of file-system artifacts whose state transitions are the core concern.

---

## Artifacts & State Transitions

### 1. In-app HTML files (`Meshtastic/Resources/docs/**/*.html`)

| State | Condition | Value of `BETA_FLAG` used to build |
|---|---|---|
| **pre-release** | Default development state | `true` (built with `--beta`) |
| **release** | After `cut-release-docs.sh` is run | `false` (built without `--beta`) |

**Invariant**: Every HTML file in `Meshtastic/Resources/docs/` must be in exactly
one state at any time. Mixed states (some files with banner, some without) are not
permitted and would be caught by the gate workflow.

**Transition: pre-release → release**  
Triggered by: `bash scripts/cut-release-docs.sh <version>`  
Side effects:
- All HTML files rebuilt without `pre-release-banner` div
- Commit created on current branch
- Annotated tag `v<version>` created

**Transition: release → pre-release**  
Triggered by: any subsequent `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta` call (happens automatically on `main` via `docs-deploy.yml` after the next commit)  
Side effects: HTML files rebuilt with `pre-release-banner` div; no tag action

---

### 2. Git tag (`v<version>`)

| Field | Value |
|---|---|
| Format | `v` + `MARKETING_VERSION` (e.g., `v2.7.14`) |
| Type | Annotated (`git tag -a`) |
| Message | `Release v<version>` |
| Target | The commit produced by step 5 of `cut-release-docs.sh` |
| Lifecycle | Created once per release; never moved or deleted by this feature |

**Validation**: The tag name's version component must equal the `MARKETING_VERSION`
extracted from `project.pbxproj`. Enforced by FR-011.

---

### 3. MARKETING_VERSION (read-only entity)

Sourced from `Meshtastic.xcodeproj/project.pbxproj`.

| Property | Value |
|---|---|
| Location | Multiple `MARKETING_VERSION = X.Y.Z;` lines in `project.pbxproj` |
| Cardinality | Multiple entries; all must be identical for a valid release |
| Access | Read-only — the script never writes to `project.pbxproj` |
| Format | Semantic version string matching `[0-9]+\.[0-9]+\.[0-9]+` |

---

### 4. Script pre-flight state (runtime only — not persisted)

Before modifying any file, `cut-release-docs.sh` validates:

| Check | Method | Fail condition |
|---|---|---|
| Version argument format | regex `^[0-9]+\.[0-9]+\.[0-9]+$` | Malformed version string |
| MARKETING_VERSION consistency | `grep` + `sort -u` | Multiple distinct values found |
| MARKETING_VERSION match | string equality | Extracted value ≠ argument |
| Git tag availability | `git tag -l "v<version>"` | Tag already exists |
| Docs-path cleanliness | `git status --porcelain -- docs/ ...` | Non-empty output |

All checks are read-only and run before any file is written.

---

## Sequence Diagram

```
Developer                  cut-release-docs.sh         build-docs.sh     copy-snapshots.sh     git
    |                             |                          |                    |               |
    |-- bash cut-release-docs.sh 2.7.14 -->                 |                    |               |
    |                      pre-flight checks                 |                    |               |
    |                      (version format, MARKETING_VERSION, tag exists, dirty) |               |
    |                      [FAIL → exit non-zero, no changes]|                    |               |
    |                             |                          |                    |               |
    |                      bash build-docs.sh --output ... --|-->                 |               |
    |                             |                    (no --beta flag)           |               |
    |                             |<-- HTML written ---------|                    |               |
    |                             |                          |                    |               |
    |                      bash copy-snapshots.sh -----------|-------------------->               |
    |                             |<-- PNGs copied --------------------------------               |
    |                      stale PNG check (warn only)       |                    |               |
    |                             |                          |                    |               |
    |                      git add Meshtastic/Resources/docs/ |                   |              -->
    |                      git commit -m "docs: rebuild for v2.7.14 release"     |              -->
    |                      git tag -a v2.7.14 -m "Release v2.7.14"              |              -->
    |                             |                          |                    |               |
    |<-- summary (files changed, commit hash, tag) ----------|                    |               |
```
