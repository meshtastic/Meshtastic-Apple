# Quickstart: Automatic Docs Translation

## Prerequisites

- Xcode (latest stable)
- iOS 26+ device or simulator (for translation features)
- Device language set to a non-English locale for testing

## Build & Run

1. Open `Meshtastic.xcworkspace` in Xcode
2. Select an iOS 26+ simulator or device
3. Build and run (⌘R)
4. Change simulator language: Settings → General → Language & Region → add a non-English language as primary
5. Navigate to Settings → Help & Documentation
6. Observe translation loading indicator, then translated content

## Testing Translation

```bash
# Run unit tests
xcodebuild test -workspace Meshtastic.xcworkspace -scheme Meshtastic -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0'
```

## Key Files

| File | Purpose |
|------|---------|
| `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` | Translation orchestration actor |
| `Meshtastic/Services/TranslationCache.swift` | File-based cache with LRU eviction |
| `Meshtastic/Views/Settings/HelpAndDocumentation/DocPageView.swift` | Modified to inject translation layer |
| `MeshtasticTests/DocTranslationTests.swift` | Unit tests |

## Architecture

```
DocPageView
    │
    ▼
DocTranslationService (actor)
    ├── checks locale (skip if English)
    ├── checks cache (return if hit)
    ├── Translation.Session (primary)
    ├── FoundationModels (fallback)
    └── caches result → TranslationCache
         │
         ▼
    TranslationCache (actor)
         ├── manifest.json (metadata)
         ├── LRU eviction at 50 MB
         └── file I/O in Application Support
```

## Fallback Chain

1. Translation framework → translated markdown
2. FoundationModels generative → translated markdown
3. English original (graceful degradation)
