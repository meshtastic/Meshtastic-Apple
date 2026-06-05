# Implementation Plan: Docs Release Versioning

**Branch**: `013-docs-release-versioning` | **Date**: 2026-06-05 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/013-docs-release-versioning/spec.md`

## Summary

Every App Store build currently ships the in-app HTML docs with a
`pre-release-banner` div because `build-docs.sh` is always invoked with `--beta`
during development. This feature adds a `scripts/cut-release-docs.sh` script that
rebuilds the bundled HTML *without* `--beta`, verifies the Xcode project version
matches, commits, and tags — and a lightweight GitHub Actions gate workflow
(`docs-release-gate.yml`) that alerts on a banner-present tag push.

**Technical approach**: Pure bash + GitHub Actions YAML. No Swift changes.
Existing scripts (`build-docs.sh`, `copy-snapshots.sh`) are called as-is;
no modifications to those files are required.

## Technical Context

**Language/Version**: bash 5+ (macOS zsh-compatible), GitHub Actions YAML  
**Primary Dependencies**: `cmark-gfm` (Homebrew, already required by `build-docs.sh`), `git`  
**Storage**: File system — `Meshtastic/Resources/docs/*.html` (in-app bundled HTML)  
**Testing**: Manual script invocation on macOS; GitHub Actions workflow on tag push  
**Target Platform**: macOS (developer machine) + GitHub Actions `ubuntu-latest` runner  
**Project Type**: CLI release script + CI validation workflow  
**Performance Goals**: Script completes in <60 seconds (SC-002) — snapshot regeneration is NOT part of this script  
**Constraints**: Zero new runtime dependencies; bash only; must be idempotent on re-run after fixing a mismatch  
**Scale/Scope**: 2 new files (`scripts/cut-release-docs.sh`, `.github/workflows/docs-release-gate.yml`); no existing files modified

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ N/A | No UI code |
| II. SwiftData Persistence | ✅ N/A | No persistence layer |
| III. Protocol-Oriented Transport | ✅ N/A | No device communication |
| IV. Structured Logging | ✅ N/A | Bash script; uses `echo` to stdout/stderr (appropriate for CLI) |
| V. Protobuf Contract Fidelity | ✅ N/A | No proto changes |
| VI. Lint-Clean Commits | ✅ Pass | No Swift code introduced; bash script should pass `shellcheck` |
| VII. Platform Parity | ✅ N/A | Script targets macOS only (dev tool, not app code) |
| VIII. Design Standards | ✅ N/A | No UI changes |
| Docs Workflow | ✅ Pass | Constitution mandates `--beta` for development; this script adds the authorized release-time exception |

**Gate result**: PASS — no violations. Proceed to Phase 0.

**Post-design re-check**: PASS — confirmed no new Swift, UI, or persistence changes required.

## Project Structure

### Documentation (this feature)

```text
specs/013-docs-release-versioning/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── script-contract.md     # Phase 1 output
│   └── workflow-contract.md   # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
scripts/
└── cut-release-docs.sh            # NEW — release doc build, verify, commit, tag

.github/workflows/
└── docs-release-gate.yml          # NEW — advisory banner check on v*.*.* tag push

# Existing files called but NOT modified:
scripts/build-docs.sh
scripts/copy-snapshots.sh
Meshtastic.xcodeproj/project.pbxproj  (read-only by the script)
Meshtastic/Resources/docs/            (written by build-docs.sh via the script)
```

**Structure Decision**: Single-project layout. Two new standalone files at repo root
level. No new directories in the app source tree.
