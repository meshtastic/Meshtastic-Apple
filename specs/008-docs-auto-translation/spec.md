# Feature Specification: Automatic Docs Translation

**Feature Branch**: `008-docs-auto-translation`  
**Created**: 2026-05-14  
**Updated**: 2026-05-14  
**Status**: Implemented  
**Input**: User description: "Automatically detect if the user's language is not english and use the foundation model translation to generate a .md file in their language for the docs to use instead of the english file"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Non-English User Views Docs in Their Language (Priority: P1)

A user whose device language is set to a non-English locale (e.g., Spanish, German, Japanese) opens the in-app documentation. The system detects that the user's preferred language differs from English, translates the requested documentation page using the Apple Translation framework (iOS 17.4+), and displays the translated content instead of the English original.

**Why this priority**: This is the core value proposition — non-English speakers can read documentation in their native language without manual translation infrastructure.

**Independent Test**: Can be tested by setting device language to a non-English locale, opening any docs page, and verifying translated content appears.

**Acceptance Scenarios**:

1. **Given** the device language is set to Spanish, **When** the user opens the Help & Documentation section, **Then** documentation pages are displayed in Spanish.
2. **Given** the device language is set to a supported non-English locale, **When** a docs page is loaded, **Then** translated content is generated and cached for that language.
3. **Given** the device language is English, **When** the user opens documentation, **Then** the original English files are used without translation.

---

### User Story 2 - Translated Docs Are Cached for Offline Use (Priority: P2)

Once a documentation page has been translated, the translated content is persisted locally so that subsequent views load instantly without re-running the translation engine.

**Why this priority**: On-device translation can be slow; caching ensures a smooth experience on repeat visits and works offline.

**Independent Test**: Can be tested by translating a page, force-quitting the app, reopening, and verifying the translated page loads instantly without network or model invocation.

**Acceptance Scenarios**:

1. **Given** a translated file already exists for the user's language, **When** the user opens that page, **Then** the cached translation is displayed immediately.
2. **Given** the English source has been updated (new app version), **When** the user opens the page, **Then** the system regenerates the translation from the updated source.

---

### User Story 3 - Graceful Fallback When Translation Unavailable (Priority: P3)

If translation is not available (unsupported device, unsupported language, or language pack not downloaded), the system falls back to displaying the English documentation.

**Why this priority**: Ensures the app never shows a blank or broken docs page regardless of device capabilities.

**Independent Test**: Can be tested by attempting to load docs on a device running iOS < 17.4 and verifying English content displays.

**Acceptance Scenarios**:

1. **Given** the device does not support on-device translation (iOS < 17.4), **When** the user opens docs, **Then** English documentation is displayed.
2. **Given** translation fails mid-process, **When** the error occurs, **Then** English documentation is displayed and the error is logged.
3. **Given** FoundationModels assets are not available on an iOS 26+ device, **When** the FM fallback is attempted, **Then** the system backs off for 15 minutes and falls back to English without flooding the console with error logs.

---

### User Story 4 - Navigation UI Labels Are Translated (Priority: P2)

The documentation browser's navigation title, search prompt, section headers, and page titles are all translated to the user's device language.

**Why this priority**: Partial translation (body only, English nav) creates a jarring experience. Full UI translation is essential for non-English usability.

**Independent Test**: Set device language to a non-English locale, open Help & Docs, and verify section names, page titles, search prompt, and navigation title are all translated.

**Acceptance Scenarios**:

1. **Given** the device language is Spanish, **When** the doc browser loads, **Then** section names ("User Guide" → "Guía del usuario") and page titles are displayed in Spanish.
2. **Given** the device language is English, **When** the doc browser loads, **Then** all labels remain in their original English form.

---

### User Story 5 - App-Wide FoundationModels Backoff (Priority: P2)

When FoundationModels is unavailable on a device, the app suppresses repeated FM calls and their associated console log noise across all FM call sites.

**Why this priority**: Devices without FM assets generate hundreds of PrewarmSession/Model Catalog error logs per session, impacting debugging and performance.

**Acceptance Scenarios**:

1. **Given** FM fails with "model not available" or "asset not found", **When** any FM call site is invoked, **Then** all FM calls are skipped for 15 minutes.
2. **Given** the user taps "Re-run Analysis" in Discovery, **When** the cooldown is active, **Then** the cooldown is reset and FM is retried.

---

### Edge Cases

- **Language change mid-session**: System observes locale change notifications and automatically reloads the current docs page in the new language (using cached translation if available, otherwise triggering a new translation).
- **Right-to-left languages** (Arabic, Hebrew): Handled by the existing `WKWebView` HTML/CSS layer.
- **Duplicate in-flight requests**: The service deduplicates concurrent translation requests for the same page+language+hash combination using an in-flight task map.
- **Translation language pack not installed**: If the Translation framework reports `supported` but not `installed`, a log message advises downloading via Settings. The system falls through to FM fallback (iOS 26+) or English.
- **Cache size growth**: 50 MB per-language LRU eviction enforced by `TranslationCache`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect the user's preferred language from the device locale settings at docs load time.
- **FR-002**: System MUST use the Apple Translation framework (`TranslationSession`) as the primary on-device translation API (**iOS 17.4+**). If the Translation framework is unavailable or the language is not installed, the system MUST fall back to FoundationModels generative model (**iOS 26+ only**) before ultimately falling back to English.
- **FR-003**: System MUST preserve HTML structure during translation — only text nodes are translated; tags, attributes, code blocks, `<pre>`, `<script>`, `<style>`, and `<picture>` elements are preserved verbatim.
- **FR-004**: System MUST cache translated content locally in Application Support, keyed by language code and source file SHA-256 content hash. Each cached file MUST track a last-accessed date for LRU eviction.
- **FR-005**: System MUST invalidate cached translations when the English source file changes (detected via content hash mismatch).
- **FR-005a**: System MUST enforce a 50 MB per-language cache limit using LRU eviction (delete least-recently-accessed translations first when the cap is exceeded).
- **FR-006**: System MUST fall back to English documentation when translation is unavailable or fails.
- **FR-007**: System MUST skip translation when the device language is English.
- **FR-008**: System MUST display a loading indicator while translation is in progress for uncached pages.
- **FR-008a**: System MUST translate the currently viewed page immediately (lazy), then prefetch remaining docs pages in the background at low priority (100ms delay between pages).
- **FR-009**: System MUST log translation errors using `Logger.docs`.
- **FR-010**: System MUST guard Translation framework usage with `@available(iOS 17.4, *)` and FoundationModels usage with `@available(iOS 26, *)` / `#if canImport(FoundationModels)`.
- **FR-011**: System MUST translate doc browser UI labels (navigation title, search prompt, section names, page titles) to the user's device language.
- **FR-012**: System MUST deduplicate concurrent in-flight translation requests for the same page/language/hash using a task map.
- **FR-013**: System MUST provide an app-wide FoundationModels availability gate (`FoundationModelAvailability` actor) that backs off all FM call sites for 15 minutes after a hard failure (model not available, AI not enabled, asset not found in catalog).
- **FR-014**: System MUST apply the FM backoff gate to all FM call sites: `DocTranslationService`, `AIDocAssistantView`, and `DiscoverySummaryView`.
- **FR-015**: User-initiated re-runs (e.g., "Re-run Analysis" in Discovery) MUST reset the FM backoff cooldown.

### Key Entities

- **`DocTranslationService`** (actor): Singleton orchestrator for all doc translation. Manages Translation framework and FM fallback dispatch, in-flight deduplication, UI string translation, and background prefetch.
- **`TranslationCache`** (actor): File-based cache in Application Support. Stores translated content keyed by `sourceFile#languageCode#contentHash`. Tracks last-accessed dates for LRU eviction. Enforces 50 MB per-language limit.
- **`FoundationModelAvailability`** (actor): App-wide singleton tracking FM usability. Disables FM calls for a 15-minute cooldown after hard failures. Provides `isAvailable`, `reportFailure(_:)`, and `reset()` API.
- **`TranslationState`** (enum): View-facing state — `.idle`, `.loading`, `.translated(URL)`, `.english`.

## Architecture

### Translation Cascade

```
Device language ≠ English?
├── No  → Use bundled English HTML
└── Yes → Check cache (sourceFile + lang + SHA-256 hash)
    ├── Cache hit → Return cached translation
    └── Cache miss → Translate
        ├── Translation framework (iOS 17.4+)
        │   ├── Language installed → TranslationSession.translate()
        │   └── Not installed / unsupported → Fall through
        ├── FoundationModels (iOS 26+)
        │   ├── FM available → LanguageModelSession.respond()
        │   └── FM unavailable → reportFailure() + 15min backoff
        └── English fallback
```

### Files

| File | Role |
|------|------|
| `Meshtastic/Services/DocTranslationService.swift` | Translation orchestrator (inside `Views/Settings/HelpAndDocumentation/`) |
| `Meshtastic/Services/TranslationCache.swift` | File-based LRU cache |
| `Meshtastic/Services/FoundationModelAvailability.swift` | App-wide FM backoff gate |
| `Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift` | Consumes translation service for page content |
| `Meshtastic/Views/Settings/HelpAndDocumentation/DocBrowserView.swift` | Consumes translation service for nav/section/page labels |

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Non-English users see documentation in their device language within 10 seconds of first page load.
- **SC-002**: Cached translated pages load in under 1 second on subsequent visits.
- **SC-003**: 100% of documentation pages remain accessible (in English or translated) regardless of device capabilities.
- **SC-004**: HTML structure (headings, links, tables, code blocks, images, picture elements) is preserved in 95%+ of translated output.
- **SC-005**: Translation cache does not exceed 50 MB for any single language.
- **SC-006**: On devices where FM is unavailable, zero repeated PrewarmSession/Model Catalog errors appear after the initial failure.

## Clarifications

### Session 2026-05-14

- Q: Which API — Translation framework, FoundationModels generative, or both? → A: Try Translation framework first (iOS 17.4+), fall back to FoundationModels (iOS 26+), then English.
- Q: Translation trigger strategy — lazy, eager, or hybrid? → A: Lazy with background prefetch (translate current page immediately, prefetch others in background).
- Q: Cache storage location — Caches or Application Support? → A: Application Support directory (persists until explicitly deleted).
- Q: Mid-session language change behavior? → A: Auto-detect and refresh (observe locale change notification, reload current docs page in new language).
- Q: Cache cleanup strategy when 50 MB limit reached? → A: LRU eviction (delete least-recently-accessed translations first).
- Q: Minimum iOS version for Translation framework? → A: iOS 17.4 (not iOS 26). FoundationModels fallback requires iOS 26+.
- Q: How to handle FM console log spam on devices without assets? → A: Shared `FoundationModelAvailability` actor backs off all FM call sites app-wide for 15 minutes after first hard failure.

## Assumptions

- Apple Translation framework is available on iOS 17.4+ and supports a wide range of languages with downloadable language packs.
- FoundationModels translation API is available on iOS 26+ and supports the user's device language (when FM assets are present).
- The existing in-app docs system renders from bundled HTML files in `Meshtastic/Resources/docs/` via `WKWebView`.
- Translation quality from both the Translation framework and FoundationModels is acceptable for documentation content without human review.
- Cache storage uses the app's Application Support directory (persistent, not purgeable by OS). LRU eviction handles cleanup.
- Right-to-left language rendering is handled by the existing `WKWebView` HTML/CSS layer.
