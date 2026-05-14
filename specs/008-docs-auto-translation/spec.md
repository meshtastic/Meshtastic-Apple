# Feature Specification: Automatic Docs Translation

**Feature Branch**: `008-docs-auto-translation`  
**Created**: 2026-05-14  
**Status**: Draft  
**Input**: User description: "Automatically detect if the user's language is not english and use the foundation model translation to generate a .md file in their language for the docs to use instead of the english file"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Non-English User Views Docs in Their Language (Priority: P1)

A user whose device language is set to a non-English locale (e.g., Spanish, German, Japanese) opens the in-app documentation. The system detects that the user's preferred language differs from English, translates the requested documentation page using FoundationModels on-device translation, and displays the translated content instead of the English original.

**Why this priority**: This is the core value proposition — non-English speakers can read documentation in their native language without manual translation infrastructure.

**Independent Test**: Can be tested by setting device language to a non-English locale, opening any docs page, and verifying translated content appears.

**Acceptance Scenarios**:

1. **Given** the device language is set to Spanish, **When** the user opens the Help & Documentation section, **Then** documentation pages are displayed in Spanish.
2. **Given** the device language is set to a supported non-English locale, **When** a docs page is loaded, **Then** a translated `.md` file is generated and cached for that language.
3. **Given** the device language is English, **When** the user opens documentation, **Then** the original English `.md` files are used without translation.

---

### User Story 2 - Translated Docs Are Cached for Offline Use (Priority: P2)

Once a documentation page has been translated, the translated `.md` file is persisted locally so that subsequent views load instantly without re-running the translation model.

**Why this priority**: On-device translation can be slow; caching ensures a smooth experience on repeat visits and works offline.

**Independent Test**: Can be tested by translating a page, force-quitting the app, reopening, and verifying the translated page loads instantly without network or model invocation.

**Acceptance Scenarios**:

1. **Given** a translated `.md` file already exists for the user's language, **When** the user opens that page, **Then** the cached translation is displayed immediately.
2. **Given** the English source `.md` has been updated (new app version), **When** the user opens the page, **Then** the system regenerates the translation from the updated source.

---

### User Story 3 - Graceful Fallback When Translation Unavailable (Priority: P3)

If FoundationModels translation is not available (unsupported device, unsupported language, or model download incomplete), the system falls back to displaying the English documentation.

**Why this priority**: Ensures the app never shows a blank or broken docs page regardless of device capabilities.

**Independent Test**: Can be tested by attempting to load docs on a device/simulator that does not support FoundationModels translation and verifying English content displays.

**Acceptance Scenarios**:

1. **Given** the device does not support on-device translation (e.g., older OS), **When** the user opens docs, **Then** English documentation is displayed.
2. **Given** translation fails mid-process, **When** the error occurs, **Then** English documentation is displayed and the error is logged.

---

### Edge Cases

- **Language change mid-session**: System observes locale change notifications and automatically reloads the current docs page in the new language (using cached translation if available, otherwise triggering a new translation).
- How does the system handle right-to-left languages (Arabic, Hebrew) in the rendered docs?
- What happens if the translation model produces garbled output for a niche language?
- How large can the cached translation files grow, and is there a cleanup mechanism?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect the user's preferred language from the device locale settings at docs load time.
- **FR-002**: System MUST use the Translation framework (`Translation.Session`) as the primary on-device translation API (iOS 26+). If the Translation framework is unavailable or fails for the requested language, the system MUST fall back to FoundationModels generative model (prompt-based translation) before ultimately falling back to English.
- **FR-003**: System MUST preserve markdown formatting (headings, links, code blocks, tables, callouts) during translation.
- **FR-004**: System MUST cache translated `.md` files locally in Application Support, keyed by language code and source file content hash. Each cached file MUST track a last-accessed date for LRU eviction.
- **FR-005**: System MUST invalidate cached translations when the English source file changes (detected via content hash mismatch).
- **FR-005a**: System MUST enforce a 50 MB per-language cache limit using LRU eviction (delete least-recently-accessed translations first when the cap is exceeded).
- **FR-006**: System MUST fall back to English documentation when translation is unavailable or fails.
- **FR-007**: System MUST skip translation when the device language is English.
- **FR-008**: System MUST display a loading indicator while translation is in progress for uncached pages.
- **FR-008a**: System MUST translate the currently viewed page immediately (lazy), then prefetch remaining docs pages in the background at low priority.
- **FR-009**: System MUST log translation errors using the appropriate typed logger.
- **FR-010**: System MUST guard FoundationModels usage with availability checks to support older OS versions.

### Key Entities

- **TranslatedDocument**: Represents a cached translated `.md` file — attributes include source file path, language code, content hash of the English source, translated content, creation date, and last-accessed date (for LRU eviction).
- **TranslationRequest**: A pending translation job — source markdown content, target language, and completion status.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Non-English users see documentation in their device language within 10 seconds of first page load.
- **SC-002**: Cached translated pages load in under 1 second on subsequent visits.
- **SC-003**: 100% of documentation pages remain accessible (in English or translated) regardless of device capabilities.
- **SC-004**: Markdown formatting (headings, links, tables, code blocks) is preserved in 95%+ of translated output.
- **SC-005**: Translation cache does not exceed 50 MB for any single language.

## Clarifications

### Session 2026-05-14

- Q: Which API — Translation framework, FoundationModels generative, or both? → A: Try Translation framework first, fall back to FoundationModels generative model.
- Q: Translation trigger strategy — lazy, eager, or hybrid? → A: Lazy with background prefetch (translate current page immediately, prefetch others in background).
- Q: Cache storage location — Caches or Application Support? → A: Application Support directory (persists until explicitly deleted).
- Q: Mid-session language change behavior? → A: Auto-detect and refresh (observe locale change notification, reload current docs page in new language).
- Q: Cache cleanup strategy when 50 MB limit reached? → A: LRU eviction (delete least-recently-accessed translations first).

## Assumptions

- FoundationModels translation API is available on iOS 26+ and supports the user's device language.
- The existing in-app docs system renders from `.md` files converted to HTML via the build script or at runtime via `WKWebView`.
- Translation quality from FoundationModels is acceptable for documentation content without human review.
- The app already bundles English `.md` source files or their HTML equivalents in `Meshtastic/Resources/docs/`.
- Cache storage uses the app's Application Support directory (persistent, not purgeable by OS). A manual cache-clear option or size cap enforcement (per SC-005) must handle cleanup.
- Right-to-left language rendering is handled by the existing `WKWebView` HTML/CSS layer.
