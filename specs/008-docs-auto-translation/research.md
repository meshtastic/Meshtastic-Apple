# Research: Automatic Docs Translation

## R-001: Translation Framework API (iOS 26+)

**Decision**: Use `Translation.Session` as the primary translation engine.

**Rationale**: The Translation framework is Apple's purpose-built API for text translation. It supports:
- Offline operation (language packs downloaded on-demand, then cached by the OS)
- Batch translation via `session.translations(from:)` for multiple strings
- Language availability checking via `LanguageAvailability`
- Automatic language detection

**API surface**:
```swift
import Translation

let session = Translation.Session(from: .english, to: targetLanguage)
let result = try await session.translate(sourceText)
// result.targetText contains the translated string
```

**Language availability check**:
```swift
let availability = LanguageAvailability()
let status = await availability.status(from: .english, to: targetLanguage)
// .installed, .supported (downloadable), .unsupported
```

**Alternatives considered**:
- FoundationModels generative (heavier, less accurate for plain translation, but handles more languages)
- Third-party APIs (requires network, violates offline-first principle)

---

## R-002: FoundationModels Generative Fallback

**Decision**: Use FoundationModels (`LanguageModelSession`) as fallback when Translation framework reports `.unsupported` for the target language.

**Rationale**: Some languages may not be supported by the Translation framework but can be handled by the on-device LLM via prompting. This provides broader language coverage.

**API surface**:
```swift
import FoundationModels

let session = LanguageModelSession()
let prompt = "Translate the following markdown from English to \(languageName). Preserve all markdown formatting exactly. Do not translate code blocks or URLs.\n\n\(sourceMarkdown)"
let response = try await session.respond(to: prompt)
// response.content contains translated markdown
```

**Constraints**:
- Requires iOS 26+ and supported hardware (A17 Pro / M1+)
- Slower than Translation framework
- May not preserve markdown formatting as reliably
- Token limits may require chunking large documents

**Alternatives considered**:
- Skip generative fallback entirely (simpler but fewer languages supported)

---

## R-003: Markdown Preservation Strategy

**Decision**: Translate markdown in segments, preserving structural elements.

**Rationale**: Translating raw markdown risks corrupting formatting. Strategy:
1. Parse markdown into segments: headings, paragraphs, list items, table cells (translatable) vs code blocks, URLs, HTML tags (non-translatable)
2. Translate only text segments
3. Reassemble with original structure

**Implementation approach**:
- Use regex-based segmentation (lightweight, no external parser dependency)
- Protect patterns: `[links](urls)`, `` `code` ``, ```` ```code blocks``` ````, `| table | cells |`, HTML tags
- For Translation framework: translate segment-by-segment
- For FoundationModels: include "preserve markdown formatting" in prompt and translate whole document

**Alternatives considered**:
- Full markdown AST parser (swift-markdown package — adds dependency, overkill for segmentation)
- Translate entire file as-is (risks corrupting links/code)

---

## R-004: File-Based Cache Architecture

**Decision**: Store translations as individual `.md` files in Application Support with a JSON manifest for metadata.

**Rationale**: File-based approach allows:
- Direct file URLs for WKWebView loading (after `cmark-gfm` or runtime conversion)
- Simple size calculation via file system attributes
- LRU eviction without database overhead
- Content-hash keying for invalidation

**Cache structure**:
```
Application Support/
└── TranslatedDocs/
    ├── manifest.json          # Array of TranslatedDocument metadata
    └── {languageCode}/
        └── {contentHash}/
            └── {filename}.md  # Translated markdown
```

**Manifest entry**:
```json
{
  "sourceFile": "user/messages.md",
  "languageCode": "es",
  "contentHash": "sha256-abc123...",
  "translatedAt": "2026-05-14T10:00:00Z",
  "lastAccessedAt": "2026-05-14T12:00:00Z",
  "fileSize": 4096
}
```

**Alternatives considered**:
- SwiftData storage (overkill for regenerable content, large text blobs inefficient)
- UserDefaults (size limits, not appropriate)
- Caches directory (user chose Application Support for persistence)

---

## R-005: HTML Conversion for Translated Markdown

**Decision**: Convert translated markdown to HTML at runtime using the same CSS as bundled docs.

**Rationale**: The existing doc system bundles pre-converted HTML. For translations, we have two options:
1. Run `cmark-gfm` at build time (impossible — translations are runtime-generated)
2. Convert at runtime

**Implementation**: Use a lightweight Swift markdown-to-HTML converter or shell out to bundled `cmark-gfm` binary. Since the app already uses WKWebView, we can:
- Inject the translated markdown into an HTML template (same CSS as bundled docs)
- Use the existing `WKWebView` to render it

Simplest approach: wrap translated markdown in the same HTML shell (head + CSS link + body) that `build-docs.sh` produces, then load as a file URL or via `loadHTMLString`.

**Alternatives considered**:
- Bundle `cmark-gfm` binary in app (large, licensing concerns)
- Use swift-markdown package for rendering (adds dependency)
- Use JavaScript markdown parser in WKWebView (adds complexity)

---

## R-006: Locale Change Detection

**Decision**: Observe `NSLocale.currentLocaleDidChangeNotification` and refresh docs.

**Rationale**: iOS posts this notification when the user changes their language in Settings. The app can observe it and invalidate the current page view.

**Implementation**:
```swift
NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
    .sink { _ in /* reload current doc page with new locale */ }
```

**Alternatives considered**:
- `@Environment(\.locale)` in SwiftUI (doesn't always update live for system locale changes)
- Check on every `onAppear` (sufficient but misses in-session changes)

---

## R-007: Availability Gating

**Decision**: Gate all translation code behind `if #available(iOS 26, *)` with English fallback on older OS.

**Rationale**: Both Translation framework and FoundationModels require iOS 26+. The app supports last two major OS versions (currently iOS 18+). Translation is a progressive enhancement.

**Implementation**:
```swift
if #available(iOS 26, *) {
    // Attempt translation
} else {
    // Load English HTML directly (existing behavior)
}
```

**Alternatives considered**:
- Raise minimum deployment target (violates Platform Parity principle)
- Use older NaturalLanguage framework (doesn't support full document translation)
