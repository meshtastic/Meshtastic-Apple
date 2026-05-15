# Tasks: Docs Translation Pipeline

**Input**: Design documents from `/specs/009-docs-translation-pipeline/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
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

**Purpose**: Core components that all user stories depend on

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

## Phase 4: User Story 2 — Download Community Translations (Priority: P1)

**Goal**: Download existing translations from GitHub Pages CDN feed before falling back to on-device translation

**Independent Test**: With a populated `meshtastic/translations` repo and `index.json` feed, open a French docs page → content downloads from CDN instead of using on-device translation

### Implementation for User Story 2

- [x] T028 [P] [US2] Create `Meshtastic/Services/CommunityTranslationFetcher.swift` actor with feed model (`TranslationFeed`, `TranslationSet`)
- [x] T029 [US2] Implement `getFeed()` — fetches `index.json` from GitHub Pages CDN, caches in-memory (once per launch), deduplicates concurrent fetches via `feedFetchTask`
- [x] T030 [US2] Implement `bestMatch(for:in:)` — filters by language + platform (`apple`), prefers exact app version, falls back to latest available
- [x] T031 [US2] Implement `fetchIfAvailable(page:languageCode:sourceFile:sourceHash:)` — single-page download from raw GitHub URL into `TranslationCache`
- [x] T032 [US2] Implement `prefetchAll(languageCode:pages:)` — bulk download of all available pages for a language, skipping already-cached pages
- [x] T033 [US2] Implement `fetchNavLabels(languageCode:)` — downloads `nav-labels.json` and imports into `DocTranslationService.importUIStringCache()`
- [x] T034 [US2] Wire community fetch into `DocTranslationService` — call `CommunityTranslationFetcher.fetchIfAvailable()` before on-device translation; call `prefetchAll()` at the start of bulk prefetch
- [x] T038 [US2] Implement `fetchSearchIndex(languageCode:)` in `CommunityTranslationFetcher` — downloads `search-index.json` and imports into `DocBundle`

**Checkpoint**: User Story 2 complete — community translations download from CDN, fallback to on-device

---

## Phase 5: User Story 3 — Auto-Upload Translations (Priority: P2)

**Goal**: After prefetch completes, auto-commit translated `.md` files + manifest + nav labels to `meshtastic/translations` repo

**Independent Test**: After browsing all docs pages in French, check `meshtastic/translations` repo for `apple-apps/fr/{version}/` directory with committed `.md` files, `manifest.json`, and `nav-labels.json`

### Implementation for User Story 3

- [x] T013 [P] [US3] Create `Meshtastic/Services/DocsTranslationUploader.swift` actor with read-only GitHub API checks (`directoryExists`, `fileExists` for public repos, no auth)
- [x] T014 [US3] Implement `checkDocsRepoHasTranslations()` — checks `meshtastic/meshtastic` for `docs/i18n/{lang}/{version}/`
- [x] T015 [US3] Implement `checkTranslationsRepoHasFiles()` — checks `meshtastic/translations` for `apple-apps/{lang}/{version}/manifest.json`
- [x] T016 [US3] Implement `commitFile()` — GitHub Contents API PUT with Bearer token
- [x] T017 [US3] Implement `loadGitHubToken()` — reads from environment variable or `SupportingFiles/secrets.json`
- [x] T018 [US3] Implement `getTranslatedMarkdown()` — reads from `TranslationCache` for upload content
- [x] T019 [US3] Implement `uploadIfNeeded()` — orchestrates checks → token → per-file commit loop with `uploadedFilesThisSession` tracking
- [x] T020 [US3] Wire auto-upload trigger in `DocTranslationService.prefetchAll()` — call `DocsTranslationUploader.shared.uploadIfNeeded()` at `.background` priority after prefetch completes
- [x] T035 [US3] Implement `uploadManifest()` — commits `manifest.json` with language, appVersion, platform, pageCount, pages list, generatedAt
- [x] T036 [US3] Implement `uploadNavLabels()` — exports UI string cache via `DocTranslationService.exportUIStringCache()` and commits `nav-labels.json`
- [x] T037 [US3] Implement `uploadSearchIndex()` — exports translated search index via `DocTranslationService.exportSearchIndex()` and commits `search-index.json`

**Checkpoint**: User Story 3 complete — translations auto-commit with manifest + nav labels to `meshtastic/translations` after prefetch

---

## Phase 6: User Story 4 — Community Translation Review (Priority: P3)

**Goal**: Translated files in `meshtastic/translations` serve as starting point for community review via GitHub Action feed regeneration

**Independent Test**: Verify committed `.md` files are valid markdown, `manifest.json` is well-formed, and `nav-labels.json` contains expected keys

- [ ] ~~T021 [US4] Add README.md to `meshtastic/translations` repo explaining the structure and review process~~ **(out of scope — external repo)**
- [ ] ~~T022 [US4] Add GitHub Action in `meshtastic/translations` to regenerate `index.json` feed and deploy to GitHub Pages~~ **(out of scope — external repo)**

**Checkpoint**: Community review flow documented and discoverable

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Testing, validation, and documentation

- [x] T023 [P] Create `MeshtasticTests/MarkdownConverterTests.swift` — test headings, paragraphs, code fences, tables, callouts, inline formatting, images, HTML passthrough, link rewriting, front matter stripping
- [x] T024 [P] Update `docs/user/translate.md` with markdown translation pipeline description
- [x] T025 [P] Update `docs/developer/architecture.md` with `DocsTranslationUploader`, `CommunityTranslationFetcher`, and `MarkdownConverter` documentation
- [x] T026 Regenerate bundled HTML docs: `bash scripts/build-docs.sh --output Meshtastic/Resources/docs --beta`
- [x] T027 Run `quickstart.md` validation — verify end-to-end flow with French language on iOS 26+ device
- [x] T039 Add `TranslatedSearchEntry` model to `DocModels.swift` and translated search index storage to `DocBundle`
- [x] T040 Add `generateSearchIndex(for:)` and `extractKeywords(from:)` to `DocTranslationService` — generates translated keyword index after prefetch
- [x] T041 Update `DocBrowserView` search filtering to match against translated keywords from search index
- [x] T042 Add `clearAll()` to `TranslationCache` and wire into "Clear App Data" button in `AppSettings.swift`
- [x] T043 Move "Participate in Distributed Translations" toggle to its own section at the bottom of `AppSettings.swift`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) — no other story dependencies
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) — can run in parallel with US1 (different files)
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) + User Story 1 (needs cached translations to upload)
- **User Story 4 (Phase 6)**: Depends on User Story 3 (needs files in translations repo)
- **Polish (Phase 7)**: Can start after Phase 2 for tests; after Phase 5 for docs

### Parallel Opportunities

- T002 + T003 can run in parallel (different files)
- T006 + T007 can run in parallel with T005 (different files)
- T028 can run in parallel with US1 tasks (different file)
- T013 can run in parallel with US1/US2 tasks (different file)
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
2. ✅ US2 → Community translation download from CDN (instant translations)
3. ✅ US3 → Auto-upload with manifest + nav labels (community benefit)
4. ⬜ US4 → Community review flow (out of scope — external repo)
5. ✅ Polish → Tests, docs, validation

---

## Notes

- Feature is **fully implemented** (T001–T020, T023–T027, T028–T043 complete)
- T021–T022 are out of scope (external `meshtastic/translations` repo)
- 41 of 41 in-scope tasks complete
- The system forms a **crowd-sourced translation loop**:
  1. Community translations download from GitHub Pages CDN (`CommunityTranslationFetcher`)
  2. On-device translation as fallback for missing languages/versions
  3. Auto-upload of translated pages + manifest + nav labels to `meshtastic/translations`
  4. GitHub Action regenerates `index.json` feed on Pages
  5. Next user gets translations instantly from CDN — no on-device model needed
- Per-file upload tracking allows within-session retry of failures
- All read-only GitHub checks and CDN downloads use unauthenticated requests
