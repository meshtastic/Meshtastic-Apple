# Feature Specification: Docs Translation Pipeline

**Feature Branch**: `009-docs-translation-pipeline`  
**Created**: 2026-05-14  
**Updated**: 2026-05-14  
**Status**: Implemented  

## Summary

Restructure the on-device documentation translation to operate on markdown source files instead of HTML, then rebuild HTML locally from the translated markdown using an enhanced on-device converter. After all pages for a language are translated, automatically commit the translated markdown files to `meshtastic/translations` for community review. The docs site PR workflow lives in that repo and is out of scope for this spec.

## User Scenarios & Testing

### User Story 1 — Translate at Markdown Level (Priority: P1)

The translation engine operates on markdown source files rather than HTML text nodes. This produces higher-quality output because markdown structure (headings, links, code fences, tables) is more explicit and easier to preserve during translation.

**Acceptance Scenarios**:

1. **Given** a user opens a docs page in French, **When** the page is not cached, **Then** the system translates the English `.md` source, converts it to HTML via `MarkdownConverter`, and displays it.
2. **Given** a translated `.md` file is cached, **When** the user opens the same page, **Then** the cached markdown is converted to HTML and displayed instantly.
3. **Given** markdown contains code fences, tables, links, images, and `<picture>` elements, **When** translated, **Then** all non-translatable elements are preserved verbatim.

### User Story 2 — Auto-Upload Translations to Translations Repo (Priority: P2)

After all pages for a language are translated and cached, the app automatically commits the translated `.md` files to `meshtastic/translations` at `{lang}/{version}/{section}/{page}.md`. A separate GitHub Action in that repo (out of scope) handles PRs to the docs site.

**Acceptance Scenarios**:

1. **Given** prefetch completes for French on app v2.7.13, **When** no French translations exist in `meshtastic/translations` for v2.7.13, **Then** the app commits all translated `.md` files to `fr/2.7.13/{section}/`.
2. **Given** French translations already exist in the translations repo for v2.7.13, **When** prefetch completes, **Then** no upload occurs.
3. **Given** a partial upload failed (e.g., 20 of 27 files committed), **When** the next prefetch completes (same or next session), **Then** only the remaining 7 files are uploaded.
4. **Given** the `TRANSLATIONS_GITHUB_TOKEN` is not configured, **When** prefetch completes, **Then** translations are cached locally but no upload is attempted.

### User Story 3 — Community Translation Review (Priority: P3)

Translated files in `meshtastic/translations` serve as a starting point for community review. Native speakers can edit and improve machine translations before they reach the docs site.

## Architecture

### Markdown-Level Translation (On-Device)

```
Bundled .md source → segment into translatable/non-translatable blocks
  → translate text segments via Translation framework (iOS 26+)
  → reassemble translated .md → cache in Application Support
  → convert to HTML via MarkdownConverter → display in WKWebView
```

### Auto-Upload to Translations Repo

```
Prefetch completes for language
  → Check meshtastic/meshtastic docs site for existing translations (no auth)
  → Check meshtastic/translations for existing files (no auth)
  → If neither exists, commit translated .md files via GitHub API (token required)
  → Track uploaded files per-file to allow retry of failures
```

### File Structure in Translations Repo

```
meshtastic/translations/
  fr/
    2.7.13/
      user/
        getting-started.md
        bluetooth.md
        ...
      developer/
        architecture.md
        ...
  es/
    2.7.13/
      ...
```

### Key Files

| File | Role |
|------|------|
| `Meshtastic/Services/MarkdownConverter.swift` | GFM markdown→HTML converter (tables, callouts, inline formatting, HTML passthrough) |
| `Meshtastic/Services/DocsTranslationUploader.swift` | Read-only docs site checks + auto-commit to translations repo |
| `Meshtastic/Resources/docs/markdown/{section}/*.md` | Bundled English markdown source files |
| `Meshtastic/Views/Settings/HelpAndDocumentation/DocModels.swift` | `DocPage.markdownURL` computed property |
| `Meshtastic/Views/Settings/HelpAndDocumentation/DocTranslationService.swift` | Translation orchestration (markdown path + auto-upload trigger) |
| `scripts/build-docs.sh` | Updated to copy `.md` source files into bundle |

## Requirements

### Functional Requirements

- **FR-001**: Translation MUST operate on markdown source files when available, falling back to HTML translation if `.md` is not bundled.
- **FR-002**: Translated markdown MUST be converted to HTML on-device via `MarkdownConverter` for display.
- **FR-003**: `MarkdownConverter` MUST support: headings, paragraphs, lists (unordered), code fences, inline code, tables, links, images, `<picture>` elements (HTML passthrough), blockquote callouts (tip/warning/note), bold, italic, strikethrough, horizontal rules, and `.md`→`.html` link rewriting.
- **FR-004**: English `.md` source files MUST be bundled at `docs/markdown/{section}/` in the app bundle. `build-docs.sh` MUST copy them during the build.
- **FR-005**: Translated `.md` files MUST be cached in Application Support using the existing `TranslationCache` infrastructure.
- **FR-006**: After prefetch completes for a language, `DocsTranslationUploader` MUST check `meshtastic/meshtastic` (docs site) and `meshtastic/translations` for existing translations. No authentication is needed for these read-only checks against public repos.
- **FR-007**: If no translations exist in either repo, the uploader MUST commit translated `.md` files to `meshtastic/translations` at `{lang}/{version}/{section}/{page}.md`.
- **FR-008**: The uploader MUST NOT create duplicate uploads. It MUST track uploaded files per-file (not per-language) to allow retry of individual failures within the same app session.
- **FR-009**: The GitHub token MUST be stored in `SupportingFiles/secrets.json` as `TRANSLATIONS_GITHUB_TOKEN`, injected by Xcode Cloud via `ci_pre_xcodebuild.sh`. Fine-grained PAT scoped to `meshtastic/translations` with `contents:write` only.
- **FR-010**: Upload MUST be fully automatic — triggered in the background after prefetch completes, at `.background` priority. No user interaction required.
- **FR-011**: Each new app version MUST translate all pages fresh. No diffing against previous version translations.
- **FR-012**: The docs site PR workflow is OUT OF SCOPE for this spec. It lives in the `meshtastic/translations` repo.

### Non-Functional Requirements

- **NFR-001**: Unauthenticated GitHub API checks are rate-limited to 60 req/hour. The uploader MUST NOT exceed this (currently 2 checks per upload attempt).
- **NFR-002**: Upload failures MUST be logged via `Logger.docs` and MUST NOT crash the app or block the UI.
- **NFR-003**: Upload runs at `.background` priority and MUST NOT impact app responsiveness.

## Edge Cases & Failure Handling

- **Token missing**: Upload silently skipped; translations cached locally only. Logged once.
- **Token expired/invalid**: Commit returns HTTP 401/403; logged as error, file skipped, retried next session.
- **Network unavailable**: URLSession throws; logged as error, skipped, retried next session.
- **Partial upload**: Per-file tracking allows retry of failed files within the same session or on next launch.
- **Rate limited**: HTTP 429; logged, remaining files skipped, retried next session.
- **Repo doesn't exist**: HTTP 404 on commit; logged, all files skipped.
- **Translation produces empty/garbled output**: Empty-string guard in `translatedUIString()` falls back to English. Garbled translations are committed as-is for community review/correction.

## Clarifications

### Session 2026-05-14

1. Target repo → `meshtastic/translations` (dedicated repo, not Meshtastic-Apple or docs site)
2. Upload mechanism → Auto-upload from app via GitHub API after prefetch completes
3. Markdown converter → Enhanced existing lightweight converter (not apple/swift-markdown SPM)
4. Versioning → Per app version (`{lang}/{version}/{section}/{page}.md`)
5. Auth → Fine-grained PAT in Secrets.json via Xcode Cloud environment variable
6. Failure handling → Retry remaining files per-file, not per-language
7. Per-file vs per-language tracking → Per-file (allows within-session retry)
8. Version diffing → No diffing; always translate all pages fresh per version
9. Docs site PR → Out of scope; lives in `meshtastic/translations` repo
10. Upload trigger → Fully automatic after prefetch, background priority

## Assumptions

- `meshtastic/translations` is a public repo with a fine-grained PAT configured for writes.
- The existing `build-docs.sh` pipeline using `cmark-gfm` is the reference for markdown→HTML conversion. `MarkdownConverter` replicates its output on-device.
- The Translation framework produces acceptable markdown-aware translations when given properly segmented input.
- Each app version bundles `.md` source files that may differ from the previous version.
- The `meshtastic/translations` repo will have a GitHub Action (maintained separately) to PR translations to the docs site.
