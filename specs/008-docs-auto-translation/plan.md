# Implementation Plan: Automatic Docs Translation

**Branch**: `008-docs-auto-translation` | **Date**: 2026-05-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-docs-auto-translation/spec.md`

## Summary

Add automatic on-device translation of bundled documentation pages for non-English users. Uses the Translation framework (`Translation.Session`) as primary API with FoundationModels generative fallback (both iOS 26+). Translates the current page lazily on first view, then prefetches remaining pages in background. Caches translated markdown in Application Support with content-hash invalidation and LRU eviction at 50 MB per language. Falls back to English on older OS or failure.

## Technical Context

**Language/Version**: Swift (latest stable), iOS 26+ for translation APIs  
**Primary Dependencies**: Translation framework, FoundationModels, SwiftUI, WKWebView (existing DocPageView)  
**Storage**: Application Support directory (file-based cache — translated .md files + metadata JSON)  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`)  
**Target Platform**: iOS 18+, iPadOS 18+, macOS (Catalyst) — translation features gated to iOS 26+  
**Project Type**: Mobile app (feature addition)  
**Performance Goals**: <10s first translation, <1s cached page load  
**Constraints**: 50 MB per-language cache cap, offline-capable after initial translation, no network required  
**Scale/Scope**: ~30 docs pages × N languages

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | Loading indicator is SwiftUI; DocPageView remains WKWebView (existing) |
| II. SwiftData Persistence | ⚠️ N/A | Cache is file-based (regenerable content, not app data) — no SwiftData model needed |
| III. Protocol-Oriented Transport | ✅ N/A | No transport changes |
| IV. Structured Logging | ✅ PASS | Will use `Logger.docs` (existing category) |
| V. Protobuf Contract Fidelity | ✅ N/A | No proto changes |
| VI. Lint-Clean Commits | ✅ PASS | Will follow SwiftLint rules |
| VII. Platform Parity | ✅ PASS | Translation gated with `#available(iOS 26, *)`; graceful fallback to English |
| VIII. Design Standards | ✅ PASS | Loading indicator follows existing patterns; no new UI screens |

**SwiftData justification**: The cache stores regenerable translated files (not user data). File-based storage in Application Support is more appropriate than SwiftData for large text blobs that are keyed by path+hash. This aligns with how the existing docs bundle works (files on disk loaded by WKWebView).

## Project Structure

### Documentation (this feature)

```text
specs/008-docs-auto-translation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (speckit.tasks)
```

### Source Code (repository root)

```text
Meshtastic/
├── Views/Settings/HelpAndDocumentation/
│   ├── DocPageView.swift                    # MODIFY — inject translation layer before rendering
│   └── DocTranslationService.swift          # NEW — translation orchestration
├── Services/
│   └── TranslationCache.swift              # NEW — file-based cache with LRU eviction
└── Extensions/
    └── Logger.swift                         # EXISTING — Logger.docs already available

MeshtasticTests/
└── DocTranslationTests.swift               # NEW — unit tests for cache + service
```

**Structure Decision**: Feature code lives alongside the existing HelpAndDocumentation views. The translation service is a standalone actor that DocPageView calls before loading HTML. Cache management is extracted to a separate file for testability.

## Complexity Tracking

No constitution violations requiring justification.
