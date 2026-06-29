# Tasks: Automatic Docs Translation

**Input**: Design documents from `/specs/008-docs-auto-translation/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in spec — omitted.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create new files and establish feature structure

- [X] T001 Create `TranslationCache` actor in `Meshtastic/Services/TranslationCache.swift` — define `TranslatedDocumentEntry` Codable struct (sourceFile, languageCode, contentHash, translatedAt, lastAccessedAt, fileSize), manifest load/save to Application Support, SHA-256 hashing helper
- [X] T002 [P] Create `DocTranslationService` actor stub in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — public API: `func translatedHTMLURL(for page: DocPage) async -> URL?`, placeholder implementation returning nil

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core cache infrastructure that all user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Implement `TranslationCache` file I/O in `Meshtastic/Services/TranslationCache.swift` — create Application Support/TranslatedDocs directory, read/write manifest.json, store/retrieve translated .md files by language code and content hash path structure
- [X] T004 Implement SHA-256 content hashing in `Meshtastic/Services/TranslationCache.swift` — hash English source file content using CryptoKit, return 64-char hex string for cache keying
- [X] T005 Implement HTML wrapping utility in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — take translated markdown string, wrap in HTML shell matching bundled docs CSS (reuse existing stylesheet path from DocWebView's docsRoot), write to temp file, return file URL for WKWebView loading

**Checkpoint**: Cache infrastructure ready — user story implementation can begin

---

## Phase 3: User Story 1 — Non-English User Views Docs in Their Language (Priority: P1) 🎯 MVP

**Goal**: Non-English users see documentation translated to their device language via Translation framework with FoundationModels fallback.

**Independent Test**: Set device language to Spanish, open Settings → Help & Documentation, verify translated content appears within 10 seconds.

### Implementation for User Story 1

- [X] T006 [US1] Implement locale detection in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — check `Locale.current.language.languageCode`, return early (nil) if English, otherwise proceed with translation flow (FR-001, FR-007)
- [X] T007 [US1] Implement Translation framework integration in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — gated with `if #available(iOS 26, *)`, create `Translation.Session`, check `LanguageAvailability.status`, translate markdown segments preserving formatting (FR-002, FR-003, FR-010)
- [X] T008 [US1] Implement markdown segmentation in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — split markdown into translatable segments (paragraphs, headings, list items, table cells) and non-translatable segments (code blocks, URLs, HTML tags), translate only text segments, reassemble (FR-003)
- [X] T009 [US1] Implement FoundationModels generative fallback in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — when Translation framework reports `.unsupported`, use `LanguageModelSession` with prompt instructing markdown preservation, gated with `#available(iOS 26, *)` (FR-002)
- [X] T010 [US1] Wire `DocTranslationService` into `DocPageView` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift` — add `@State` for translation state (loading/translated/english), call `translatedHTMLURL(for:)` in `.task {}`, show `ProgressView` while translating (FR-008), load translated URL or fall back to bundled HTML
- [X] T011 [US1] Add structured logging in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — use `Logger.docs` for translation start/complete/error events (FR-009)

**Checkpoint**: User Story 1 functional — non-English users see translated docs, English users see originals unchanged

---

## Phase 4: User Story 2 — Translated Docs Are Cached for Offline Use (Priority: P2)

**Goal**: Translated pages are persisted and load instantly on subsequent visits without re-running translation.

**Independent Test**: Translate a page, force-quit app, reopen, verify cached page loads in <1 second without model invocation.

### Implementation for User Story 2

- [X] T012 [US2] Implement cache write in `DocTranslationService` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — after successful translation, call `TranslationCache.store(translatedMarkdown:for:language:hash:)`, update manifest with entry
- [X] T013 [US2] Implement cache lookup in `DocTranslationService` in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — before translating, check `TranslationCache.retrieve(for:language:)`, compare content hash, update `lastAccessedAt` on hit, return cached HTML URL (FR-004)
- [X] T014 [US2] Implement cache invalidation in `Meshtastic/Services/TranslationCache.swift` — on cache lookup, compare stored contentHash with current source file hash, delete stale entry and return miss if mismatch (FR-005)
- [X] T015 [US2] Implement LRU eviction in `Meshtastic/Services/TranslationCache.swift` — after each write, calculate total size for language, if >50 MB sort entries by lastAccessedAt ascending and delete oldest until under limit (FR-005a, SC-005)
- [X] T016 [US2] Implement background prefetch in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — after current page translation completes, launch low-priority `Task` to iterate remaining `DocBundle.shared.allPages`, translate uncached pages sequentially with `Task.yield()` between each; cancel prefetch task when user navigates away from docs section (store task handle, call `.cancel()` in DocPageView `.onDisappear`); cancel prefetch task when user navigates away from docs section (store task handle, call `.cancel()` in DocPageView `.onDisappear`); cancel prefetch task when user navigates away from docs section (store task handle, call `.cancel()` in DocPageView `.onDisappear`) (FR-008a)

**Checkpoint**: User Stories 1 AND 2 both work — translations cached, instant reload, background prefetch active

---

## Phase 5: User Story 3 — Graceful Fallback When Translation Unavailable (Priority: P3)

**Goal**: App never shows blank or broken docs regardless of device capabilities.

**Independent Test**: Run on iOS 18 simulator (no Translation/FoundationModels), verify English docs display normally.

### Implementation for User Story 3

- [X] T017 [US3] Implement availability gating in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — wrap all translation code in `if #available(iOS 26, *)`, return nil (triggering English fallback) on older OS (FR-006, FR-010)
- [X] T018 [US3] Implement error recovery in `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` — catch all translation errors (Translation.Session failure, FoundationModels timeout, file I/O errors), log with `Logger.docs.error`, return nil to trigger English fallback (FR-006, FR-009)
- [X] T019 [US3] Implement locale change observation in `Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift` — observe `NSLocale.currentLocaleDidChangeNotification`, reset translation state, re-trigger `.task {}` to reload page in new language

**Checkpoint**: All user stories functional — translation works, caches, and degrades gracefully

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, testing, and cleanup

- [X] T020 [P] Update `docs/user/settings.md` — add section documenting automatic translation behavior (language detection, caching, fallback to English)
- [X] T021 [P] Create unit tests in `MeshtasticTests/DocTranslationTests.swift` — test SHA-256 hashing, manifest serialization/deserialization, LRU eviction logic, cache invalidation on hash mismatch, locale detection (English skip)
- [X] T022 Run `bash scripts/build-docs.sh --output Meshtastic/Resources/docs` and commit regenerated HTML

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion
- **User Story 2 (Phase 4)**: Depends on Phase 3 (US1 provides the translation flow to cache)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (US1 provides the code paths to add fallback around)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent after Foundational — core translation flow
- **User Story 2 (P2)**: Builds on US1 — adds caching to the existing translation flow
- **User Story 3 (P3)**: Builds on US1 — adds error handling and availability guards

### Within Each User Story

- Models/structs before services
- Services before view integration
- Core flow before error handling

### Parallel Opportunities

- T001 and T002 can run in parallel (different files)
- T020 and T021 can run in parallel (different files)
- Within US1: T007 and T009 touch same file — must be sequential

---

## Parallel Example: Setup Phase

```bash
# These can run simultaneously:
Task T001: "Create TranslationCache actor in Meshtastic/Services/TranslationCache.swift"
Task T002: "Create DocTranslationService actor stub in Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003–T005)
3. Complete Phase 3: User Story 1 (T006–T011)
4. **STOP and VALIDATE**: Set device to non-English, open docs, verify translation
5. Ship as MVP — non-English users get translated docs

### Incremental Delivery

1. Setup + Foundational → Infrastructure ready
2. Add User Story 1 → Translation works → MVP! 🎯
3. Add User Story 2 → Caching + prefetch → Performance improvement
4. Add User Story 3 → Fallback + resilience → Production-ready
5. Polish → Docs + tests → Ship

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All Translation/FoundationModels code gated behind `#available(iOS 26, *)`
- Use `Logger.docs` for all logging (existing category)
- No SwiftData models — file-based cache in Application Support
- Commit after each task or logical group
