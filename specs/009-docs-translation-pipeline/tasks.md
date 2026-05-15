# Tasks: Docs Translation Pipeline

**Input**: Design documents from `/specs/009-docs-translation-pipeline/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Bundle markdown source files and update build pipeline

- [x] T001 Copy English `.md` source files to `Meshtastic/Resources/docs/markdown/user/` and `Meshtastic/Resources/docs/markdown/developer/`
- [x] T002 Update `scripts/build-docs.sh` to create `markdown/` output directories and copy `.md` files during build
- [x] T003 Add `TRANSLATIONS_GITHUB_TOKEN` to `ci_scripts/ci_pre_xcodebuild.sh` secrets.json generation
- [x] T004 Configure `TRANSLATIONS_GITHUB_TOKEN` in Xcode Cloud environment variables

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core components that both user stories depend on

- [x] T005 Add `markdownURL` computed property to `DocPage` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocModels.swift`
- [x] T006 [P] Create `Meshtastic/Services/MarkdownConverter.swift` with GFM markdown→HTML conversion (headings, paragraphs, lists, code fences, inline code, tables, links, images, HTML passthrough, callouts, bold, italic, strikethrough, horizontal rules, `.md`→`.html` link rewriting)
- [x] T007 [P] Add `stripFrontMatter()` to `MarkdownConverter` to remove YAML front matter and Jekyll attributes

**Checkpoint**: Foundation ready — `MarkdownConverter` can convert any bundled `.md` to HTML

---

## Phase 3: User Story 1 — Translate at Markdown Level (Priority: P1) 🎯 MVP

**Goal**: Translate markdown source files on-device instead of HTML, cache translated `.md`, convert to HTML for display

**Independent Test**: Open any docs page with a non-English device language → page content is translated and displays correctly with tables, code blocks, links preserved

### Implementation for User Story 1

- [x] T008 [US1] Add `translateMarkdown(page:targetLanguage:)` method to `DocTranslationService` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift`
- [x] T009 [US1] Add `translateText(_:targetLanguage:)` shared method to `DocTranslationService` for single-string translation via best available engine
- [x] T010 [US1] Refactor `translatedHTMLString(for:)` in `DocTranslationService` to prefer markdown path: read `.md` → translate → cache `.md` → convert via `MarkdownConverter` → return HTML
- [x] T011 [US1] Keep HTML fallback path in `translatedHTMLString(for:)` for pages without bundled `.md`
- [x] T012 [US1] Verify `TranslationCache` stores translated `.md` content with source file key `{section}/{page}.md`

**Checkpoint**: User Story 1 complete — docs pages translate via markdown pipeline with HTML fallback

---

## Phase 4: User Story 2 — Auto-Upload Translations (Priority: P2)

**Goal**: After prefetch completes, auto-commit translated `.md` files to `meshtastic/translations` repo under `apple-apps/`

**Independent Test**: After browsing all docs pages in French, check `meshtastic/translations` repo for `apple-apps/fr/{version}/` directory with committed `.md` files

### Implementation for User Story 2

- [x] T013 [P] [US2] Create `Meshtastic/Services/DocsTranslationUploader.swift` actor with read-only GitHub API checks (`directoryExists` for public repos, no auth)
- [x] T014 [US2] Implement `checkDocsRepoHasTranslations()` — checks `meshtastic/meshtastic` for `docs/i18n/{lang}/{version}/`
- [x] T015 [US2] Implement `checkTranslationsRepoHasFiles()` — checks `meshtastic/translations` for `apple-apps/{lang}/{version}/`
- [x] T016 [US2] Implement `commitFile()` — GitHub Contents API PUT with Bearer token
- [x] T017 [US2] Implement `loadGitHubToken()` — reads `TRANSLATIONS_GITHUB_TOKEN` from `SupportingFiles/secrets.json`
- [x] T018 [US2] Implement `getTranslatedMarkdown()` — reads from `TranslationCache` for upload content
- [x] T019 [US2] Implement `uploadIfNeeded()` — orchestrates checks → token → per-file commit loop with `uploadedFilesThisSession` tracking
- [x] T020 [US2] Wire auto-upload trigger in `DocTranslationService.prefetchAll()` — call `DocsTranslationUploader.shared.uploadIfNeeded()` at `.background` priority after prefetch completes

**Checkpoint**: User Story 2 complete — translations auto-commit to `meshtastic/translations` after prefetch

---

## Phase 5: User Story 3 — Community Translation Review (Priority: P3)

**Goal**: Translated files in `meshtastic/translations` serve as starting point for community review

**Independent Test**: Verify committed `.md` files are valid markdown, readable, and have a machine-translation disclaimer

- [ ] T021 [US3] Add README.md to `meshtastic/translations` repo explaining the structure and review process
- [ ] T022 [US3] Add GitHub Action in `meshtastic/translations` to auto-create PR on `meshtastic/meshtastic` docs site when new translations are pushed (out of scope per spec — deferred to translations repo)

**Checkpoint**: Community review flow documented and discoverable

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Testing, validation, and documentation

- [ ] T023 [P] Create `MeshtasticTests/MarkdownConverterTests.swift` — test headings, paragraphs, code fences, tables, callouts, inline formatting, images, HTML passthrough, link rewriting, front matter stripping
- [ ] T024 [P] Update `docs/user/translate.md` with markdown translation pipeline description
- [ ] T025 [P] Update `docs/developer/architecture.md` with `DocsTranslationUploader` and `MarkdownConverter` documentation
- [ ] T026 Regenerate bundled HTML docs: `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta`
- [ ] T027 Run `quickstart.md` validation — verify end-to-end flow with French language on iOS 26+ device

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) — no other story dependencies
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) + User Story 1 (needs cached translations to upload)
- **User Story 3 (Phase 5)**: Depends on User Story 2 (needs files in translations repo)
- **Polish (Phase 6)**: Can start after Phase 2 for tests; after Phase 4 for docs

### Parallel Opportunities

- T002 + T003 can run in parallel (different files)
- T006 + T007 can run in parallel with T005 (different files)
- T013 can run in parallel with US1 tasks (different file)
- T023 + T024 + T025 can run in parallel (different files)

---

## Implementation Strategy

### MVP (User Story 1 Only)

1. ✅ Phase 1: Setup — bundle `.md` files, update build script
2. ✅ Phase 2: Foundational — `MarkdownConverter`, `DocPage.markdownURL`
3. ✅ Phase 3: User Story 1 — markdown translation pipeline
4. **VALIDATE**: Test with French on iOS 26+ device

### Incremental Delivery

1. ✅ US1 → Markdown translation (core value)
2. ✅ US2 → Auto-upload (community benefit)
3. ⬜ US3 → Community review flow (translations repo setup)
4. ⬜ Polish → Tests, docs, validation

---

## Notes

- Feature is **mostly implemented** (T001–T020 complete)
- Remaining: T021–T027 (community review setup, tests, documentation, validation)
- 20 of 27 tasks complete
- Per-file upload tracking allows within-session retry of failures
- All read-only GitHub checks use unauthenticated API (public repos)
