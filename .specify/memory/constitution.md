<!--
  Sync Impact Report
  ==================
  Version change: 0.0.0 → 1.0.0 (initial ratification)
  Modified principles: N/A (initial version)
  Added sections:
    - Core Principles (5 principles)
    - Technology Constraints
    - Development Workflow
    - Governance
  Removed sections: N/A
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ compatible (Constitution Check section
      will be populated from these principles at plan time)
    - .specify/templates/spec-template.md ✅ compatible (no constitution-specific
      references)
    - .specify/templates/tasks-template.md ✅ compatible (no constitution-specific
      references)
  Follow-up TODOs: none
-->

# Meshtastic Apple Constitution

## Core Principles

### I. SwiftUI-First

All user interface code MUST be written in SwiftUI. UIKit or AppKit
MUST NOT be introduced unless a required capability has no SwiftUI
equivalent on any supported OS version. Any UIKit/AppKit bridge
(e.g., `UIViewRepresentable`) MUST be documented with the specific
gap it fills and removed once a SwiftUI API becomes available.

**Rationale**: A single declarative UI framework reduces cognitive
load, keeps the codebase consistent across iOS, iPadOS, and macOS,
and simplifies long-term maintenance.

### II. Minimal Dependencies

External dependencies MUST be avoided unless they satisfy ALL of the
following criteria:

- The capability cannot be reasonably implemented in-house within
  the scope of the feature.
- The dependency is actively maintained and has a compatible license
  (GPL v3 or more permissive).
- No Apple platform framework (SwiftUI, Foundation, CoreBluetooth,
  MapKit, CoreData, CoreLocation, etc.) provides equivalent
  functionality.

Every third-party dependency MUST be justified in the PR that
introduces it. Prefer Swift Package Manager as the sole package
manager. Cocoapods and Carthage MUST NOT be used.

**Rationale**: Fewer dependencies mean fewer supply-chain risks,
faster builds, smaller binaries, and less churn when Apple releases
new OS versions.

### III. Platform-Native Persistence

Core Data MUST be used for all local data persistence. Direct SQLite,
Realm, or other ORM/database layers MUST NOT be introduced. The Core
Data model lives in `Meshtastic.xcdatamodeld` and MUST remain the
single source of truth for the local schema.

**Rationale**: Core Data is the project's established persistence
layer, is tightly integrated with SwiftUI (`@FetchRequest`,
`NSManagedObjectContext`), and adds zero additional dependencies.

### IV. Test Discipline

All new features and bug fixes MUST include corresponding tests
(XCTest or Swift Testing). Tests MUST pass locally before a PR is
opened. Existing tests MUST NOT be deleted or disabled without
maintainer approval and documented justification.

**Rationale**: Automated tests catch regressions early and give
contributors confidence when modifying shared code paths.

### V. Simplicity & YAGNI

Code MUST solve the stated requirement and nothing more. Speculative
abstractions, premature generalization, and unused code paths MUST
NOT be introduced. When two approaches are functionally equivalent,
the simpler one MUST be chosen. SFSymbols MUST be used for all
iconography — custom image assets MUST NOT be added when an
equivalent SFSymbol exists.

**Rationale**: A lean codebase is easier to read, review, and
maintain. Removing unnecessary complexity keeps contribution
barriers low for an open-source project.

## Technology Constraints

- **Languages**: Swift (latest stable) exclusively.
- **UI Framework**: SwiftUI. See Principle I for exceptions.
- **Persistence**: Core Data. See Principle III.
- **Icons**: SFSymbols. Custom assets only when no symbol exists.
- **Linting**: SwiftLint is required and enforced via git hooks
  (`scripts/setup-hooks.sh`).
- **Package Management**: Swift Package Manager only.
- **Supported Platforms**: iOS, iPadOS, macOS — last two major OS
  versions.
- **Protobufs**: Generated via `scripts/gen_protos.sh` from the
  `protobufs/` submodule. Hand-editing generated sources is
  forbidden.
- **License**: GPL v3. All contributions MUST be compatible.

## Development Workflow

- **Branching**: Trunk-based development targeting `main`. Feature
  work MUST happen on short-lived branches with descriptive names.
- **Commits**: Imperative mood, clear subject line. Body explains
  *what* and *why*, not *how*.
- **Pull Requests**: MUST target `main`, include a clear description,
  and pass all CI checks before review. Small, incremental changes
  are preferred over large monolithic PRs.
- **Rebasing**: Feature branches MUST be rebased onto `main` — merge
  commits are discouraged.
- **Code Review**: At least one maintainer approval is required
  before merging.
- **Releases**: Follow the process in `RELEASING.md`. Release
  branches are cut from `main` via
  `scripts/create-release-branch.sh`.

## Governance

This constitution supersedes ad-hoc practices and serves as the
authoritative reference for architectural and process decisions in
the Meshtastic Apple project.

- **Amendments**: Any change to this constitution MUST be proposed
  via PR with a clear rationale. The version MUST be incremented
  per semantic versioning (see below). All dependent templates in
  `.specify/templates/` MUST be checked for consistency after an
  amendment.
- **Versioning Policy**:
  - MAJOR: Principle removal or backward-incompatible redefinition.
  - MINOR: New principle or materially expanded guidance.
  - PATCH: Wording clarifications, typo fixes, non-semantic edits.
- **Compliance**: All PRs and code reviews MUST verify adherence to
  these principles. Violations MUST be flagged and resolved before
  merge.
- **Guidance**: For day-to-day development guidance see `README.md`,
  `CONTRIBUTING.md`, and `RELEASING.md` at the repository root.

**Version**: 1.0.0 | **Ratified**: 2026-04-01 | **Last Amended**: 2026-04-01
