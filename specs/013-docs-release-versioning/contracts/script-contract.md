# Contract: cut-release-docs.sh

**Phase 1 output for plan.md**  
**Script**: `scripts/cut-release-docs.sh`  
**Date**: 2026-06-05

---

## Invocation

```bash
bash scripts/cut-release-docs.sh <version>
```

### Arguments

| Argument | Type | Required | Format | Example |
|---|---|---|---|---|
| `<version>` | positional | yes | `X.Y.Z` (semantic version, digits only) | `2.7.14` |

### Options

None in v1.

---

## Pre-conditions (checked before any file modification)

All checks are read-only. On any failure the script exits non-zero with a
message to stderr and leaves the working tree unchanged.

| # | Check | Command | Error message pattern |
|---|---|---|---|
| 1 | Version format valid | regex `^[0-9]+\.[0-9]+\.[0-9]+$` | `error: invalid version '<arg>' — expected X.Y.Z` |
| 2 | MARKETING_VERSION consistent | `grep` in `project.pbxproj` + `sort -u` | `error: inconsistent MARKETING_VERSION values: <list>` |
| 3 | MARKETING_VERSION matches arg | string equality | `error: argument '<arg>' does not match MARKETING_VERSION '<found>'` |
| 4 | Tag does not already exist | `git tag -l "v<version>"` | `error: tag 'v<version>' already exists` |
| 5 | Docs paths are clean | `git status --porcelain -- docs/ Meshtastic/Resources/docs/ scripts/` | `error: docs-related paths have uncommitted changes:\n<diff>` |

---

## Execution steps (in order)

1. Validate version argument format (check 1)
2. Extract and validate MARKETING_VERSION (checks 2 & 3)
3. Assert tag does not exist (check 4)
4. Assert docs paths are clean (check 5)
5. `bash scripts/build-docs.sh --output Meshtastic/Resources/docs`  *(no `--beta`)*
6. `bash scripts/copy-snapshots.sh --output Meshtastic/Resources/docs/assets/screenshots`
7. Stale PNG warning (non-blocking) — compare newest `.md` vs oldest PNG mtime
8. `git add Meshtastic/Resources/docs/`
9. `git commit -m "docs: rebuild for v<version> release"`
10. `git tag -a "v<version>" -m "Release v<version>"`
11. Print success summary to stdout

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success — docs rebuilt, committed, and tagged |
| `1` | Pre-condition failure (see error message for detail) |
| `1` | `build-docs.sh` or `copy-snapshots.sh` failed (propagated via `set -e`) |

---

## Stdout (success)

```
✓ Rebuilt in-app docs without pre-release banner
✓ <N> files changed in commit <short-sha>
✓ Tag v<version> created → <short-sha>

Next steps:
  git push origin <branch>
  git push origin v<version>
```

---

## Stderr

Warnings (non-zero exit not triggered):
```
warning: some doc screenshots may be stale (newest .md is newer than <file>)
warning: run snapshot tests and copy-snapshots.sh before submitting to App Store
```

Errors (exit 1):
```
error: <reason>
```

---

## Side effects

| Effect | Reversible? | Notes |
|---|---|---|
| HTML files under `Meshtastic/Resources/docs/` rewritten | Yes — `git checkout` | Only `*.html` and `index.json` change |
| Screenshots copied to `Meshtastic/Resources/docs/assets/screenshots/` | Yes | `copy-snapshots.sh` copies from `docs/assets/screenshots/` |
| Git commit created on current branch | Yes — `git reset HEAD~1` | Message: `docs: rebuild for v<version> release` |
| Annotated git tag created | Yes — `git tag -d v<version>` | Tag is local until explicitly pushed |
| `cleanup-screenshots.sh` may delete orphaned PNGs from `docs/assets/screenshots/` | Recoverable via git | Called internally by `copy-snapshots.sh` |

---

## Non-goals (v1)

- Does NOT push the commit or tag to `origin` (developer pushes explicitly)
- Does NOT update `MARKETING_VERSION` in `project.pbxproj`
- Does NOT regenerate snapshot PNGs (requires Xcode test run)
- Does NOT interact with App Store Connect or Xcode Cloud
