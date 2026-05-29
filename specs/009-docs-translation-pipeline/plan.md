# Implementation Plan: Docs Translation Pipeline

**Branch**: `009-docs-translation-pipeline` | **Date**: 2026-05-14 | **Spec**: `specs/009-docs-translation-pipeline/spec.md`
**Input**: Feature specification from `/specs/009-docs-translation-pipeline/spec.md`

## Summary

Restructure on-device doc translation to operate on markdown source files (not HTML), convert to HTML via an on-device `MarkdownConverter`, download existing community translations from a GitHub Pages CDN feed before falling back to on-device translation, and automatically commit translated `.md` files + `manifest.json` + `nav-labels.json` to `meshtastic/translations` (under `apple-apps/`) after background prefetch completes. The result is a crowd-sourced translation loop: each device contributes translations that benefit all future users via the CDN feed.

## Technical Context

**Language/Version**: Swift (latest stable), Swift Concurrency (`async/await`, actors)  
**Primary Dependencies**: SwiftUI, Translation framework (iOS 26+), FoundationModels (iOS 26+), WKWebView, URLSession (GitHub API + GitHub Pages CDN)  
**Storage**: Application Support (TranslationCache — file-based LRU), GitHub API (meshtastic/translations repo), GitHub Pages CDN (index.json feed)  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`)  
**Target Platform**: iOS 16+, iPadOS 16+, macOS (Catalyst). Translation features require iOS 26+.  
**Project Type**: Mobile app (SwiftUI)  
**Performance Goals**: Translation + upload must not impact UI responsiveness (background priority)  
**Constraints**: 60 req/hour unauthenticated GitHub API limit; upload at `.background` priority; no user interaction required; CDN downloads have no practical rate limit  
**Scale/Scope**: 27 doc pages × N languages; per-file upload tracking; crowd-sourced loop

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | No new views; existing DocBrowserView/DocPageView unchanged |
| II. SwiftData Persistence | ✅ PASS | Uses file-based cache (Application Support), not SwiftData — appropriate for translated file storage |
| III. Protocol-Oriented Transport | ✅ N/A | No transport changes |
| IV. Structured Logging | ✅ PASS | All logging via `Logger.docs` |
| V. Protobuf Contract Fidelity | ✅ N/A | No protobuf changes |
| VI. Lint-Clean Commits | ✅ PASS | Must pass SwiftLint |
| VII. Platform Parity | ✅ PASS | Translation guarded with `#available(iOS 26, *)` and `#if !targetEnvironment(macCatalyst)`. Falls back to English on unsupported platforms. |
| VIII. Design Standards | ✅ N/A | No UI changes |

**No violations. Gate passed.**

## Project Structure

### Documentation (this feature)

```text
specs/009-docs-translation-pipeline/
├── plan.md              # This file
├── spec.md              # Feature specification (implemented)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── contracts/           # Phase 1 output
```

### Source Code (repository root)

```text
Meshtastic/
├── Services/
│   ├── MarkdownConverter.swift              # GFM markdown→HTML converter
│   ├── DocsTranslationUploader.swift        # Auto-upload to meshtastic/translations (pages + manifest + nav-labels)
│   ├── CommunityTranslationFetcher.swift    # Downloads community translations from GitHub Pages CDN feed
│   ├── TranslationCache.swift               # Existing file-based LRU cache
│   └── FoundationModelAvailability.swift    # Existing FM backoff gate
├── Views/Settings/HelpAndDocumentation/
│   ├── DocTranslationService.swift          # Updated: markdown translation + community fetch + upload trigger
│   ├── DocModels.swift                      # Updated: DocPage.markdownURL
│   ├── DocPageView.swift                    # Existing (no changes for this feature)
│   └── DocBrowserView.swift                 # Existing (no changes for this feature)
├── Resources/docs/
│   ├── markdown/                            # Bundled English .md source files
│   │   ├── user/*.md
│   │   └── developer/*.md
│   ├── user/*.html                          # Existing built HTML
│   ├── developer/*.html
│   └── index.json
scripts/
└── build-docs.sh                            # Updated: copies .md files into bundle
ci_scripts/
└── ci_pre_xcodebuild.sh                     # Updated: injects TRANSLATIONS_GITHUB_TOKEN

MeshtasticTests/
└── MarkdownConverterTests.swift             # New: tests for markdown→HTML conversion
```

**Structure Decision**: Services in `Meshtastic/Services/`, view-layer orchestration in `Views/Settings/HelpAndDocumentation/`, bundled resources in `Resources/docs/markdown/`. No new directories beyond what's already created.
