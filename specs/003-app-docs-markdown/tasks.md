---
description: "Task list for feature: App Documentation (Jekyll Site + In-App AI)"
---

# Tasks: App Documentation (Jekyll Site + In-App AI)

**Input**: Design documents from `specs/003-app-docs-markdown/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Organization**: Tasks grouped by user story — each story is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story label (US1–US5)
- Exact file paths included in every task description

---

## Phase 0: Design Standards Gate (Blocking — UI Work)

**Purpose**: Fetch and review the Meshtastic Client Design Standards before any UI implementation begins. Required by Constitution Principle VIII.

- [X] T000 **[UI-GATE]** Fetch and review the Meshtastic Client Design Standards at `https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md`; record any relevant constraints that affect `DocBrowserView`, `DocPageView`, or `AIDocAssistantView` layout and colour decisions. **Must be complete before T038, T039, T040, T043.**

**Checkpoint**: Design standards reviewed; implementation notes recorded

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repository scaffolding, build tooling, and `Logger.docs` category that every subsequent phase depends on.

- [X] T001 Create `docs/` directory structure with `user/`, `developer/`, `_data/` subdirs (no `.nojekyll` here — written to the build output dir by `build-docs.sh`, see T002)
- [X] T002 [P] Create `scripts/build-docs.sh` — GFM→HTML via `cmark-gfm`, CSS injection, keyword index, size check, write `.nojekyll` to `<output_dir>/` (suppresses native GitHub Pages Jekyll build per FR-003); see contracts/ci-workflow-contract.md for full interface
- [X] T003 [P] Create `scripts/copy-snapshots.sh` — copies PNGs from `MeshtasticTests/__Snapshots__/SwiftUIViewSnapshotTests/` to output dir (see contracts/ci-workflow-contract.md)
- [X] T004 [P] Create `Meshtastic/Resources/docs/assets/docs.css` — `prefers-color-scheme` light/dark variables (`--bg`, `--text`, `--link`, `--code-bg`) per FR-022
- [X] T005 Create `Meshtastic/Resources/docs/` directory tree with `.gitkeep` placeholders for `user/`, `developer/`, `assets/screenshots/` subdirs
- [X] T006 [P] Add `Logger.docs` category to `Meshtastic/Extensions/Logger.swift` — extend existing file, same pattern as `Logger.mesh`
- [X] T007 [P] Add `case helpDocs` to `SettingsNavigationState` in `Meshtastic/Router/NavigationState.swift` — raw value `"helpDocs"` (see contracts/deep-link-contract.md)
- [X] T008 [P] Add Xcode Copy Files build phase for `Meshtastic/Resources/docs/` → bundle `docs/` subdirectory in `Meshtastic.xcodeproj/project.pbxproj` (FR-023)

**Checkpoint**: Scripts exist and are executable, `Logger.docs` compiles, `helpDocs` case compiles, CSS file present

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Swift types and `DocBundle` loader that US2, US3 depend on; Jekyll config that US1 depends on.

- [X] T009 Create `DocSection` enum (`user`/`developer`) in `Meshtastic/Views/Settings/HelpAndDocumentation/DocModels.swift` (new file — keeps model types separate from the view to avoid SwiftLint file-length violations)
- [X] T010 Create `KeywordIndexEntry` Codable struct in `Meshtastic/Views/Settings/HelpAndDocumentation/DocModels.swift` matching `contracts/keyword-index-schema.json`
- [X] T011 Create `DocPage` struct (id, title, section, htmlURL, keywords, charCount) in `Meshtastic/Views/Settings/HelpAndDocumentation/DocModels.swift` per data-model.md
- [X] T012 Implement `DocBundle` singleton in `Meshtastic/Views/Settings/HelpAndDocumentation/DocModels.swift` — loads `docs/index.json` from bundle, decodes `[KeywordIndexEntry]`, constructs `[DocPage]`, falls back to empty on missing index
- [X] T013 [P] Create `docs/_config.yml` — `just-the-docs` theme, `plugins: []`, nav hierarchy for User Guide and Developer Guide sections (FR-004)
- [X] T014 [P] Create `docs/index.md` — site root with `jekyll-redirect-from` front matter redirecting to `/beta/` until first stable release (FR-020)

**Checkpoint**: `DocBundle.shared.pages` loads from a sample `index.json`; Jekyll config parses without errors (`bundle exec jekyll build` dry-run)

---

## Phase 3: User Story 1 — End User Reads Docs on the Web (Priority: P1) 🎯 MVP

**Goal**: Deploy a complete, navigable GitHub Pages Jekyll site with all User Guide and Developer Guide pages, screenshots, and version selector.

**Independent Test**: Navigate the deployed GitHub Pages `/beta/` URL, find "Getting Started", confirm screenshots appear, use the sidebar to reach "Messages & Channels" in two clicks.

### Implementation for User Story 1

- [X] T015 [P] [US1] Author `docs/user/getting-started.md` — device pairing walkthrough, one screenshot reference per major step (FR-014, SC-001)
- [X] T016 [P] [US1] Author `docs/user/bluetooth.md` — BLE connection steps; incorporate `ConnectionTip` title/message as Tips callout (FR-018); incorporate help sheet content if applicable
- [X] T017 [P] [US1] Author `docs/user/messages.md` — channels, direct messages, encryption; incorporate `ChannelsHelp`, `DirectMessagesHelp`, `LockLegend`, `AckErrors` content verbatim/adapted (FR-017); incorporate `ShareChannelsTip`, `CreateChannelsTip`, `AdminChannelTip`, `MessagesTip` as Tips callout (FR-018)
- [X] T018 [P] [US1] Author `docs/user/nodes.md` — node status, device roles, logs; incorporate full `NodeListHelp` content (FR-017) — Node Status, Device Roles enum cases, Logs section
- [X] T019 [P] [US1] Author `docs/user/map.md` — map view, waypoints, layers (FR-014)
- [X] T020 [P] [US1] Author `docs/user/settings.md` — Radio, LoRa, Bluetooth, Display, User config sections (FR-014)
- [X] T021 [P] [US1] Author `docs/user/telemetry.md` — sensor metrics, telemetry channels (FR-014)
- [X] T022 [P] [US1] Author `docs/user/tak.md` — TAK/CoT integration overview (FR-014)
- [X] T023 [P] [US1] Author `docs/user/mqtt.md` — MQTT broker configuration, topic structure (FR-014)
- [X] T024 [P] [US1] Author `docs/user/discovery.md` — Local Mesh Discovery flow; incorporate `DiscoveryScanTip` as Tips callout (FR-018) (FR-014)
- [X] T025 [P] [US1] Author `docs/user/firmware.md` — OTA update flow, version checks (FR-014)
- [X] T026 [P] [US1] Author `docs/developer/architecture.md` — app entry point, state/navigation, connectivity, persistence overview (FR-015)
- [X] T027 [P] [US1] Author `docs/developer/codebase.md` — directory structure, key files, extension patterns (FR-015)
- [X] T028 [P] [US1] Author `docs/developer/adding-features.md` — step-by-step guide to adding a new tab/view/router case (FR-015)
- [X] T029 [P] [US1] Author `docs/developer/transport.md` — BLE/TCP transport architecture, `AccessoryManager` extension map (FR-015)
- [X] T030 [P] [US1] Author `docs/developer/swiftdata.md` — `ModelContainer`, `@Model`, schema migration with `VersionedSchema` (FR-015)
- [X] T031 [P] [US1] Author `docs/developer/testing.md` — Swift Testing setup, snapshot test infrastructure, `renderImage` helper (FR-015)
- [X] T032 [P] [US1] Author `docs/developer/contributing.md` — PR workflow, branch naming, commit message style, SwiftLint rules (FR-015)
- [X] T033 [US1] Run `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta` to produce initial HTML bundle and `index.json`; commit generated output
- [X] T034 [US1] Run `bash scripts/copy-snapshots.sh --output Meshtastic/Resources/docs/assets/screenshots`; commit PNGs
- [X] T035 [US1] Create `docs/_data/versions.yml` with initial beta entry (`version: "beta"`, `path: "/beta/"`, `is_prerelease: true`) (FR-020)
- [X] T036 [US1] Create `.github/workflows/docs-deploy.yml` — trigger: push to `main`; steps: install cmark-gfm, build-docs.sh --beta, copy-snapshots.sh, upload-pages-artifact, deploy-pages (FR-012, contracts/ci-workflow-contract.md)
- [X] T037 [US1] Create `.github/workflows/docs-release.yml` — trigger: tag `v*.*.*`; steps: extract version, install cmark-gfm, build-docs.sh, copy-snapshots.sh, update `_data/versions.yml`, create `/latest/` redirect, deploy-pages (FR-020, contracts/ci-workflow-contract.md)

**Checkpoint**: Push to `main`, CI passes, GitHub Pages `/beta/` shows all 18 pages with screenshots and sidebar navigation

---

## Phase 4: User Story 2 — End User Browses Docs Inside the App (Priority: P2)

**Goal**: SwiftUI `NavigationStack` TOC with search, `WKWebView` page viewer, Settings entry point and deep link — fully offline.

**Independent Test**: Put device in airplane mode, open Settings → Help & Documentation, navigate to "Messages & Channels", confirm screenshots render from bundle.

### Implementation for User Story 2

- [X] T038 [P] [US2] Implement `DocBrowserView` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift` — `NavigationStack` with searchable grouped `List` (by `DocSection`), loads from `DocBundle.shared`, SC-003 (< 1s load)
- [X] T039 [P] [US2] Implement `DocPageView` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift` — `UIViewRepresentable` wrapping `WKWebView`; `loadFileURL(_:allowingReadAccessTo:)` with `docs/` bundle dir as access root; `backgroundColor` + `underPageBackgroundColor` = `.systemBackground` (FR-022)
- [X] T040 [US2] Add navigation destination for `.helpDocs` in `Meshtastic/Views/Settings/Settings.swift` — `NavigationLink(value: SettingsNavigationState.helpDocs)` in a new "Help" `Section` at the bottom; SF Symbol `questionmark.circle`; `.navigationDestination` case pushing `DocBrowserView` (R-007)
- [X] T041 [US2] Update README deep-link table with `meshtastic:///settings/helpDocs` entry (contracts/deep-link-contract.md)
- [X] T042 [US2] Add `DocBundleTests` Swift Testing suite in `MeshtasticTests/DocBundleTests.swift` — `#expect` all 18 expected HTML files present in bundle, `index.json` decodes to non-empty array, all `htmlURL`s resolve (FR-021 size check covered separately in build script)

**Checkpoint**: Build + run on iOS Simulator in airplane mode; TOC loads < 1s; all pages readable; deep link routes correctly

---

## Phase 5: User Story 3 — End User Asks the App a Question with AI (Priority: P3)

**Goal**: iOS 26+ Foundation Models AI assistant embedded in the doc browser; graceful degradation on iOS 17/18.

**Independent Test**: On iOS 26+ simulator, open Help & Documentation, ask "How do I add a waypoint?", receive a relevant answer within 5 seconds.

### Implementation for User Story 3

- [X] T043 [US3] Implement `AIDocAssistantView` in `Meshtastic/Views/Settings/HelpAndDocumentation/AIDocAssistantView.swift` — `#available(iOS 26, *)` gated; `TextField` for question, `Button` to submit, streaming `Text` for response, `ProgressView` while loading; `@State isLoading`, `response`, `error` (FR-009, FR-010)
- [X] T044 [US3] Implement keyword retrieval in `AIDocAssistantView` — tokenize question, match against `DocPage.keywords`, take top 3, trim to 3,000-token budget via `charCount / 3.5` estimate + `SystemLanguageModel.tokenCount(for:)` verification (FR-011)
- [X] T045 [US3] Implement `LanguageModelSession` query in `AIDocAssistantView` — system prompt citing retrieved page titles + text; handle `.exceededContextWindowSize` by dropping to top 1 page and retrying once; handle model unavailability with fallback message + `NavigationLink` to page (FR-009, FR-011)
- [X] T046 [US3] Integrate `AIDocAssistantView` into `DocBrowserView` — show AI input section at top of TOC list when `#available(iOS 26, *)`; hide entirely on iOS 17/18 (FR-010)
- [X] T047 [US3] Add `AIDocAssistantTests` tests in `MeshtasticTests/DocBundleTests.swift` — verify keyword scorer returns top-3 results, verify token budget trimming reduces to ≤ 3,000-token estimate, verify `AIDocAssistantView` body is empty on iOS < 26

**Checkpoint**: On iOS 26+ simulator, AI assistant visible and responsive; on iOS 17/18 simulator, AI section absent

---

## Phase 6: User Story 4 — Developer Reads Architecture Docs (Priority: P4)

**Goal**: Developer Guide section live on the Jekyll site and in-app, with architecture, transport, testing, and contributing pages.

**Independent Test**: Navigate the GitHub Pages `/beta/developer/` section; confirm Architecture, Transport, SwiftData, Testing, and Contributing pages all render with correct content.

### Implementation for User Story 4

*(Note: T026–T032 in Phase 3 authored the Developer Guide markdown. This phase validates content quality and wires up in-app TOC section display.)*

- [X] T048 [P] [US4] Review and polish all 7 developer docs authored in T026–T032 for accuracy against current codebase: verify type names, file paths, and code patterns match `Meshtastic/` source
- [X] T049 [P] [US4] Add snapshot tests for `DocBrowserView` developer section in `MeshtasticTests/SwiftUIViewSnapshotTests.swift` — renders developer pages in TOC without errors
- [X] T050 [US4] Rebuild HTML bundle after content polish: `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta`; commit updated HTML and index

**Checkpoint**: Developer Guide section visible in-app and on GitHub Pages; content accurately describes current architecture

---

## Phase 7: User Story 5 — Docs Stay Current Automatically (Priority: P5)

**Goal**: CI auto-regenerates screenshots on push to `main`, opens a PR for visual review, and publishes updated docs within 10 minutes.

**Independent Test**: Merge a PR that changes any UI string; within 10 minutes observe an auto-PR from `bot/update-snapshots` branch with updated PNG(s) and the GitHub Pages `/beta/` site reflects the change.

### Implementation for User Story 5

- [X] T051 [US5] Extend `.github/workflows/docs-deploy.yml` to include a snapshot regeneration step — run `xcodebuild test` for `SwiftUIViewSnapshotTests` suite on `macos-15` runner before `copy-snapshots.sh` (FR-012a)
- [X] T052 [US5] Add auto-PR logic to `docs-deploy.yml` — after snapshot tests, if any PNG changed (`git diff --name-only`), commit to `bot/update-snapshots` branch and open PR targeting `main` via `gh pr create` (FR-013); skip if no PNGs changed
- [X] T053 [US5] Add workflow failure gate — if `xcodebuild test` exit code is non-zero, skip docs deploy and fail the workflow step (FR-012, SC)
- [X] T054 [US5] Add `DocBundleTests` test verifying `index.json` `charCount` values are within ±10% of actual HTML file sizes — catches stale index after content edits in `MeshtasticTests/DocBundleTests.swift`

**Checkpoint**: Push a UI change to `main`; CI completes < 10 minutes; auto-PR appears with correct changed PNGs; docs deploy succeeds

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Accessibility, Lighthouse score, edge case handling, and final integration.

- [X] T055 [P] Add `accessibilityLabel` and `accessibilityHint` to `DocBrowserView` list rows and search bar in `Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift` (SC-008 Lighthouse proxy for in-app accessibility)
- [X] T056 [P] Add `accessibilityLabel` to `DocPageView` web view container and back button in `Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift`
- [X] T057 [P] Verify `WKWebView` dark-mode flash fix — confirm `backgroundColor` and `underPageBackgroundColor` are `.systemBackground` on all iOS/macOS themes; add snapshot test variant in `MeshtasticTests/SwiftUIViewSnapshotTests.swift`
- [X] T058 Handle missing screenshot gracefully — confirm `cmark-gfm` generates HTML `<img>` tags with `alt` text; verify no broken image placeholder appears when PNG is absent (edge case from spec)
- [X] T059 [P] Add `DocBundleTests` size check test — verify total bytes of all files in bundle `docs/` subdirectory is < 10,485,760 bytes (10 MB) in `MeshtasticTests/DocBundleTests.swift` (FR-021)
- [X] T060 SwiftLint clean pass — run `swiftlint lint` on all new Swift files; fix any warnings; confirm no `print()` statements (use `Logger.docs`)
- [X] T061 Update `README.md` — add "Documentation" section linking to GitHub Pages URL and describing `meshtastic:///settings/helpDocs` deep link (depends on T041; combine into one commit or run after T041 is merged to avoid conflict)
- [ ] T062 [P] [US3] SC-006 timing validation — on iOS 26+ simulator, manually time AI assistant response for a representative question ("How do I add a waypoint?"); confirm ≤ 5 seconds; record result in PR description (SC-006)
- [ ] T063 [US1] SC-008 Lighthouse audit — run Lighthouse CI against deployed `/beta/` GitHub Pages URL after Phase 3 deploy; confirm accessibility score ≥ 90; record score in PR description (SC-008)

**Checkpoint**: Zero SwiftLint warnings; accessibility labels present; bundle size test passes; AI response ≤ 5s verified; Lighthouse ≥ 90 recorded; README updated

---

## Dependency Graph

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundation: DocBundle, Jekyll config)
    ↓
Phase 3 (US1: Jekyll site + docs authored + CI deploy) ← MVP — independently shippable
    ↓
Phase 4 (US2: In-app browser) ← depends on Phase 1 (helpDocs case, CSS), Phase 2 (DocBundle)
    ↓
Phase 5 (US3: AI assistant) ← depends on Phase 4 (DocBrowserView integration point)
    |
Phase 6 (US4: Dev docs quality) ← depends on Phase 3 (authored in T026–T032)
    |
Phase 7 (US5: CI automation) ← depends on Phase 3 (docs-deploy.yml exists)
    ↓
Phase 8 (Polish) ← depends on all phases complete
```

**Parallel opportunities within phases**:
- Phase 3: All 18 doc authoring tasks (T015–T032) can run in parallel — separate files, no dependencies
- Phase 4: T038 and T039 can run in parallel — separate view files
- Phase 8: T055, T056, T057, T059, T062 all parallel — separate concerns; T061 sequential (depends on T041)

---

## Implementation Strategy

**MVP Scope** (deliver US1 first — zero app changes needed):
1. Complete Phase 1 (scripts, CSS, directory structure)
2. Complete Phase 2 (Jekyll config only — skip DocBundle until US2)
3. Complete Phase 3 (author all pages + CI deploy)
4. Merge → GitHub Pages `/beta/` live ✅

**Increment 2** (US2 — in-app browser):
- Complete Phase 2 DocBundle tasks (T009–T012)
- Complete Phase 4 (T038–T042)

**Increment 3** (US3 — AI assistant):
- Complete Phase 5 (T043–T047)

**Increments 4+** (US4, US5, polish):
- Complete Phases 6, 7, 8 in any order after Increment 1

---

## Task Count Summary

| Phase | Story | Tasks | Parallel |
|-------|-------|-------|---------|
| Phase 0: Design Standards Gate | — | 1 (T000) | 0 |
| Phase 1: Setup | — | 8 (T001–T008) | 6 |
| Phase 2: Foundation | — | 6 (T009–T014) | 2 |
| Phase 3: US1 Web Site | US1 (P1) | 23 (T015–T037) | 20 |
| Phase 4: US2 In-App Browser | US2 (P2) | 5 (T038–T042) | 2 |
| Phase 5: US3 AI Assistant | US3 (P3) | 5 (T043–T047) | 0 |
| Phase 6: US4 Dev Docs | US4 (P4) | 3 (T048–T050) | 2 |
| Phase 7: US5 CI Automation | US5 (P5) | 4 (T051–T054) | 0 |
| Phase 8: Polish | — | 9 (T055–T063) | 5 |
| **Total** | | **64** | **37** |
