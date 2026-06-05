# Tasks: Docs Release Versioning

**Input**: Design documents from `specs/013-docs-release-versioning/`  
**Prerequisites**: [plan.md](plan.md) · [spec.md](spec.md) · [research.md](research.md) · [data-model.md](data-model.md) · [contracts/](contracts/)

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel with other [P]-marked tasks in the same phase
- **[Story]**: User story this task belongs to (US1 / US2 / US3)
- Exact file paths are included in every task description

---

## Phase 1: Setup

**Purpose**: Environment sanity check before writing any code

- [x] T001 Confirm `bash scripts/build-docs.sh --output /tmp/test-docs-013 && grep -r 'pre-release-banner' /tmp/test-docs-013 --include='*.html' && echo FAIL || echo PASS` exits PASS (no `--beta` omits the banner from HTML files; CSS always contains the class selector — scope to `*.html` only); clean up temp dir. Time the run to confirm it completes well under 60s (SC-002 — design-time guarantee; this script only calls fast bash tools)

**Checkpoint**: `build-docs.sh` confirmed to work without `--beta`

---

## Phase 2: Foundational (Script Scaffold)

**Purpose**: Create the script skeleton that all US1 tasks build on

**⚠️ CRITICAL**: US1 pre-flight and build tasks cannot begin until this phase is complete

- [x] T002 Create `scripts/cut-release-docs.sh` with shebang `#!/usr/bin/env bash`, `set -euo pipefail`, and three output helpers: `info()` (green), `warn()` (yellow stderr), `error()` (red stderr + exit 1), plus a `usage()` function that prints synopsis and exits 1
- [x] T003 Add positional argument parsing: accept exactly one arg `VERSION`, validate it matches `^[0-9]+\.[0-9]+\.[0-9]+$`; call `usage` with error message on mismatch or missing arg (FR-001, contracts/script-contract.md §Arguments)

**Checkpoint**: Script scaffold is complete — US1 implementation and US2 (independent) can now proceed in parallel

---

## Phase 3: User Story 1 — Pre-flight Checks & Release Build (Priority: P1) 🎯 MVP

**Goal**: `bash scripts/cut-release-docs.sh 2.7.14` verifies the environment, rebuilds in-app HTML without the pre-release banner, commits, and tags

**Independent Test**: Run `bash scripts/cut-release-docs.sh <MARKETING_VERSION>` on a clean branch. Verify: (1) no `pre-release-banner` in any `Meshtastic/Resources/docs/*.html`, (2) `git log --oneline -1` shows `docs: rebuild for v<version> release`, (3) `git tag -l v<version>` returns the tag

- [x] T004 [US1] Add `check_marketing_version()` function: extract all `MARKETING_VERSION = X.Y.Z` values from `Meshtastic.xcodeproj/project.pbxproj` via `grep -oE '[0-9]+\.[0-9]+\.[0-9]+'`; pipe to `sort -u`; fail if result has >1 unique value (inconsistent project) or the single value ≠ `$VERSION` (FR-011, research.md §R-001)
- [x] T005 [P] [US1] Add `check_tag_available()` function: run `git tag -l "v$VERSION"`; if output is non-empty call `error` with message `tag 'v$VERSION' already exists` (FR-006, contracts/script-contract.md §Pre-conditions check 4)
- [x] T006 [US1] Add `check_docs_clean()` function: run `git status --porcelain -- docs/ Meshtastic/Resources/docs/ scripts/`; if output is non-empty call `error` listing the dirty paths (FR-002, research.md §R-002)
- [x] T007 [US1] In `main()`: call pre-flight functions in order — `check_marketing_version`, `check_tag_available`, `check_docs_clean` — then `info "All pre-flight checks passed"` (contracts/script-contract.md §Execution steps 1–5)
- [x] T008 [US1] Add build step in `main()`: call `bash scripts/build-docs.sh --output Meshtastic/Resources/docs` (no `--beta`); propagation via `set -e` handles failures automatically (FR-003)
- [x] T009 [US1] Add snapshot copy step in `main()`: call `bash scripts/copy-snapshots.sh --output Meshtastic/Resources/docs/assets/screenshots` (FR-004)
- [x] T010 [US1] Add stale PNG check after copy: find newest `.md` under `docs/` and oldest PNG under `Meshtastic/Resources/docs/assets/screenshots/`; if oldest PNG is older than newest `.md`, call `warn` listing **all** stale PNG file names and regeneration advice (FR-004a, research.md §R-003)
- [x] T011 [US1] Add commit step: `git add Meshtastic/Resources/docs/` then `git commit -m "docs: rebuild for v${VERSION} release"`; capture short SHA for summary (FR-005)
- [x] T012 [US1] Add tag step: `git tag -a "v${VERSION}" -m "Release v${VERSION}"` (FR-006, clarification Q1: annotated only)
- [x] T013 [US1] Add success summary: count changed HTML files, print `info` lines for rebuild confirmation, files-changed count, commit SHA, and tag name; print plain-text next-step push commands (FR-009, contracts/script-contract.md §Stdout)

**Checkpoint**: US1 fully functional — `bash scripts/cut-release-docs.sh <version>` should pass all acceptance scenarios from spec.md §User Story 1

---

## Phase 4: User Story 2 — Advisory Gate Workflow (Priority: P2)

**Goal**: Pushing a `v*.*.*` tag triggers a GitHub Actions workflow that fails and lists any bundled HTML files containing `pre-release-banner`

**Independent Test**: On a branch where `Meshtastic/Resources/docs/` HTML still contains `pre-release-banner`, push a test tag (e.g. `v99.99.99`); confirm the workflow job fails and lists the offending files in the step output

> **Note**: This entire phase is [P] with Phase 3 — `.github/workflows/docs-release-gate.yml` is a separate file with no dependency on `scripts/cut-release-docs.sh`

- [x] T014 [P] [US2] Create `.github/workflows/docs-release-gate.yml`: set `name: Release Docs Gate`, trigger on `push: tags: v*.*.*`, one job `validate` on `ubuntu-latest`, `permissions: contents: read`, concurrency group `docs-gate-${{ github.ref }}` with `cancel-in-progress: false`; add `actions/checkout@v4` step (contracts/workflow-contract.md §Trigger, §Runner)
- [x] T015 [US2] Add scan step to `validate` job: run `grep -rl "pre-release-banner" Meshtastic/Resources/docs/ --include="*.html" > /tmp/banner_files.txt 2>&1 || true`; count matches; capture file list for reporting. **Note**: must scope to `*.html` — `docs.css` always contains `.pre-release-banner` as a class selector (contracts/workflow-contract.md §Steps)
- [x] T016 [US2] Add result-reporting step: if `/tmp/banner_files.txt` is non-empty, print `✗ pre-release-banner found in:` followed by the file list and recovery instructions (`bash scripts/cut-release-docs.sh <version>`) then `exit 1`; if empty, print `✓ No pre-release-banner found — scanned N HTML files` (contracts/workflow-contract.md §Outputs)

**Checkpoint**: US2 fully functional — workflow file exists, triggers on tag push, passes/fails correctly per contracts/workflow-contract.md

---

## Phase 5: User Story 3 — Verify Post-Release Pre-release Restoration (Priority: P3)

**Goal**: Confirm that the existing `docs-deploy.yml` workflow already handles the automatic return to pre-release state after a release tag

**Independent Test**: Open `.github/workflows/docs-deploy.yml` and confirm `build-docs.sh` is called with `--beta`; no code changes required for this story to pass

- [x] T017 [P] [US3] Verify `.github/workflows/docs-deploy.yml` line 86 calls `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta`; if `--beta` is absent (it is present as of the plan date), add it (spec.md §User Story 3 acceptance scenario 1)

**Checkpoint**: US3 satisfied with zero or one line change — existing workflow already correct

---

## Phase 6: Polish & Cross-cutting Concerns

- [x] T018 [P] Run `shellcheck scripts/cut-release-docs.sh` and fix any reported warnings; run `chmod +x scripts/cut-release-docs.sh` and stage the executable bit
- [x] T019 [P] Update `RELEASING.md`: insert a "Docs release step" section documenting `bash scripts/cut-release-docs.sh <version>` as a required step before pushing the release tag, with a cross-reference to `specs/013-docs-release-versioning/quickstart.md` (SC-004)

---

## Dependencies

```
T001 → T002 → T003 → T004 → T007 → T008 → T009 → T010 → T011 → T012 → T013
                    ↗ T005 ↗
               (T005 parallel with T004 — both read-only pre-flight, different functions)

T003 → T014 → T015 → T016   (Phase 4 fully parallel with Phase 3 after T003 — different files)

T017, T018, T019 — independent, parallel with each other, begin after Phase 3+4 complete
```

> **[P] marker note**: Within a phase, [P] means parallel with adjacent [P] tasks in the
> same phase (e.g., T004 ∥ T005). Across phases, [P] on a phase header (Phase 4) means
> the entire phase runs concurrently with Phase 3.

## Parallel Execution Examples

**Developer A** (US1 — script logic): T001 → T002 → T003 → T004 + T005 (parallel) → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013  
**Developer B** (US2 — workflow): waits for T003, then T014 → T015 → T016 (runs concurrently with Developer A's T004–T013)  
**Developer C** (Polish): T017 + T018 + T019 (parallel, after Developers A and B complete)

## Implementation Strategy

**MVP (User Story 1 only)**: Complete Phases 1–3. This directly fixes the App Store
pre-release banner bug and is the highest-value deliverable. US2 and US3 are safety
nets, not prerequisites for shipping.

**Full delivery order**: Phase 1 → Phase 2 → Phase 3 + Phase 4 in parallel → Phase 5 → Phase 6
