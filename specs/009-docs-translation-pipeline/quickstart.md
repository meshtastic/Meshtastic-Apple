# Quickstart: Docs Translation Pipeline

**Feature**: 009-docs-translation-pipeline

## How It Works

1. User opens docs with a non-English device language (iOS 26+)
2. App reads bundled English `.md` source → translates via Translation framework → caches translated `.md`
3. `MarkdownConverter` converts translated `.md` to HTML → displayed in WKWebView
4. Background prefetch translates all remaining pages
5. After prefetch completes, `DocsTranslationUploader` auto-commits to `meshtastic/translations`

## Setup

### Xcode Cloud Environment Variable

Add `TRANSLATIONS_GITHUB_TOKEN` in App Store Connect → Xcode Cloud → Workflow → Environment Variables.

Value: Fine-grained PAT scoped to `meshtastic/translations` with `contents:write`.

### Build

```bash
# Rebuild bundled docs (copies .md source files into bundle)
bash scripts/build-docs.sh --output Meshtastic/Resources/docs
```

### Test

```bash
# Run in Xcode — tests are in MeshtasticTests/
# MarkdownConverterTests: verifies markdown→HTML conversion
# DocTranslationTests: existing translation service tests
```

## File Locations

| What | Where |
|------|-------|
| English `.md` source (bundled) | `Meshtastic/Resources/docs/markdown/{section}/` |
| Built `.html` (bundled) | `Meshtastic/Resources/docs/{section}/` |
| Translated `.md` cache | `~/Library/Application Support/translations/` |
| Uploaded translations | `meshtastic/translations` repo at `apple-apps/{lang}/{version}/{section}/{page}.md` |
| Converter | `Meshtastic/Services/MarkdownConverter.swift` |
| Uploader | `Meshtastic/Services/DocsTranslationUploader.swift` |
| Orchestrator | `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` |

## Verify Upload

After a non-English user browses docs, check:
```
https://github.com/meshtastic/translations/tree/main/apple-apps/{lang}/{version}
```
