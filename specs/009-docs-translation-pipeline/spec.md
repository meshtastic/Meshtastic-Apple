# Feature Specification: Docs Translation Pipeline

**Feature Branch**: `009-docs-translation-pipeline`  
**Created**: 2026-05-14  
**Status**: Implemented  

## Summary

Restructure the on-device documentation translation to operate on markdown source files instead of HTML, rebuild HTML locally via `MarkdownConverter`, download existing community translations from a GitHub Pages CDN feed before falling back to on-device translation, and automatically commit translated markdown + nav labels + manifest back to the `meshtastic/translations` repo — creating a crowd-sourced translation loop where each device contributes translations that benefit all future users.

## User Scenarios & Testing

### User Story 1 — Translate at Markdown Level (Priority: P1)

The translation engine translates markdown source segments rather than HTML text nodes. Markdown structure (headings, links, code fences, tables) is more explicit and easier to preserve during translation.

**Acceptance Scenarios**:

1. **Given** a user opens a docs page in French, **When** the page is not cached, **Then** the system translates the English `.md` source, converts it to HTML via `MarkdownConverter`, and displays it in WKWebView.
2. **Given** a translated `.md` file is cached, **When** the user opens the same page, **Then** the cached markdown is converted to HTML and displayed instantly.
3. **Given** markdown contains code fences, tables, links, images, and `<picture>` elements, **When** translated, **Then** all non-translatable elements are preserved verbatim.

### User Story 2 — Download Community Translations (Priority: P1)

Before falling back to on-device translation, the app checks a GitHub Pages CDN feed (`index.json`) for existing community-contributed translations. If available, pages and nav labels are downloaded into the local cache — no on-device model needed.

**Acceptance Scenarios**:

1. **Given** the feed at `https://meshtastic.github.io/translations/index.json` contains a French translation set for the current app version, **When** the user opens a French docs page, **Then** the translated markdown is downloaded from GitHub and displayed without on-device translation.
2. **Given** the feed exists but does not contain the requested language/version, **When** the user opens a docs page, **Then** the system falls back to on-device translation.
3. **Given** a bulk prefetch is triggered, **When** community translations are available, **Then** all available pages and `nav-labels.json` are downloaded into the local cache before on-device translation begins for any remaining pages.
4. **Given** a page is already cached locally, **When** prefetch runs, **Then** the page is skipped (no redundant download).

### User Story 3 — Commit Translated Docs to Repo (Priority: P2)

After background prefetch completes all pages for a language, the `DocsTranslationUploader` checks two repos (read-only, no auth) and then commits translated files, a `manifest.json`, and a `nav-labels.json` to `meshtastic/translations` under `apple-apps/{lang}/{version}/`.

**Acceptance Scenarios**:

1. **Given** app version 2.7.13 ships with updated English docs, **When** French translations are prefetched, **Then** the uploader checks `meshtastic/meshtastic` at `docs/i18n/fr/2.7.13` and `meshtastic/translations` at `apple-apps/fr/2.7.13/manifest.json` for existing translations.
2. **Given** no translations exist for that combo, **When** the check completes, **Then** the uploader commits each translated `.md` file individually via the GitHub Contents API.
3. **Given** all pages are successfully uploaded, **When** the upload loop completes, **Then** a `manifest.json` and `nav-labels.json` are committed alongside the translated files.
4. **Given** translations already exist for that version + language, **When** the check completes, **Then** no commit is created.
5. **Given** a file upload fails, **When** the next prefetch completes, **Then** only the failed files are retried (per-file tracking via `uploadedFilesThisSession`).

### User Story 4 — Community Translation Review (Priority: P3)

The auto-committed translations in `meshtastic/translations` serve as a staging area. A GitHub Action in that repo regenerates the `index.json` feed on GitHub Pages and can open a PR on the docs site. Native speakers can review and edit the machine-translated docs before they're merged.

## Architecture

### The Crowd-Sourced Translation Loop

```
1. User opens docs in French
2. CommunityTranslationFetcher checks index.json feed on GitHub Pages CDN
3. If translations exist → download pages + nav-labels.json → cache → display
4. If not → on-device translation (Translation framework / FoundationModels)
5. After prefetch completes → DocsTranslationUploader commits to meshtastic/translations
6. GitHub Action regenerates index.json feed on Pages
7. Next user gets translations instantly from CDN (no on-device model needed)
```

### Part 1: Community Translation Download (CDN → Device)

`CommunityTranslationFetcher` (`Meshtastic/Services/CommunityTranslationFetcher.swift`) is an actor that:

1. **Fetches the feed** (once per launch): `https://meshtastic.github.io/translations/index.json`
2. **Finds best match**: Filters by language + platform (`apple`), prefers exact app version, falls back to latest
3. **Downloads pages**: Raw markdown from `https://raw.githubusercontent.com/meshtastic/translations/master/apple-apps/{lang}/{version}/{section}/{page}.md`
4. **Downloads nav labels**: `nav-labels.json` with pre-translated page titles and section names
5. **Stores in local cache**: Via existing `TranslationCache` infrastructure with content-hash invalidation

#### Feed Model (`index.json`)

```json
{
  "generatedAt": "2026-05-14T12:00:00Z",
  "translations": [
    {
      "language": "fr",
      "appVersion": "2.7.13",
      "platform": "apple",
      "pageCount": 27,
      "generatedAt": "2026-05-14T10:00:00Z",
      "pages": ["user/messages.md", "user/nodes.md", "..."]
    }
  ]
}
```

### Part 2: Markdown-Level Translation (On-Device)

```
Bundled .md source → DocTranslationService.translateMarkdown()
  → segmentMarkdown() (translatable vs non-translatable blocks)
  → Translation framework / FoundationModels fallback (iOS 26+)
  → reassemble translated .md
  → TranslationCache.store() (Application Support)
  → MarkdownConverter.convert() → HTML body
  → MarkdownConverter.wrapInHTMLDocument() → full HTML
  → display in WKWebView
```

#### Markdown Source Access
English `.md` files are bundled in `Meshtastic/Resources/docs/markdown/` (copied by `build-docs.sh`). `DocPage.markdownURL` provides the bundle URL. When present, the translation pipeline uses markdown; otherwise it falls back to the legacy HTML translation path.

#### Translation Pipeline
1. **Check community translations** via `CommunityTranslationFetcher.fetchIfAvailable()` — if found, skip on-device translation
2. Read English `.md` source from `page.markdownURL`
3. Segment into translatable vs non-translatable blocks via `segmentMarkdown()`
4. Translate text segments via Translation framework (iOS 26+), with FoundationModels generative fallback
5. Reassemble translated `.md`
6. Cache translated `.md` in Application Support via `TranslationCache`
7. Convert to HTML via `MarkdownConverter.convert()` + `wrapInHTMLDocument()`
8. Display HTML in WKWebView

#### Markdown→HTML Converter
`MarkdownConverter` (`Meshtastic/Services/MarkdownConverter.swift`) is a custom GFM-compatible converter supporting: headings, paragraphs, lists, code fences, inline code, tables, links, images, HTML passthrough (`<picture>`, `<img>`), blockquote callouts (tip/warning), bold, italic, strikethrough, and `.md` → `.html` link rewriting. It strips YAML front matter and Jekyll inline attributes.

### Part 3: Translation Upload Service (On-Device → GitHub)

`DocsTranslationUploader` (`Meshtastic/Services/DocsTranslationUploader.swift`) runs automatically after background prefetch completes:

1. **Read-only check** (no auth): Does `meshtastic/meshtastic` have translations at `docs/i18n/{lang}/{version}`?
2. **Read-only check** (no auth): Does `meshtastic/translations` have a `manifest.json` at `apple-apps/{lang}/{version}/manifest.json`?
3. If neither exists, **commit files** (auth required): PUT each translated `.md` file to `meshtastic/translations` via GitHub Contents API using a fine-grained PAT from `Secrets.json`.
4. Per-file tracking (`uploadedFilesThisSession`) enables retry of failed individual files without re-uploading successes.
5. **Commit manifest** (`manifest.json`): JSON with language, appVersion, platform, pageCount, pages list, and generatedAt timestamp.
6. **Commit nav labels** (`nav-labels.json`): Translated page titles and section names exported from `DocTranslationService.exportUIStringCache()`.

#### Target Repo Structure
```
meshtastic/translations/
  index.json                    ← GitHub Action-generated feed (served via GitHub Pages)
  apple-apps/
    fr/
      2.7.13/
        manifest.json           ← Completeness marker
        nav-labels.json         ← Translated page titles & section names
        search-index.json       ← Translated keywords + titles for localized search
        user/
          messages.md
          nodes.md
          ...
        developer/
          architecture.md
          ...
    es/
      2.7.13/
        ...
```

#### Authentication
- Fine-grained GitHub PAT with write access to `meshtastic/translations`
- Injected via `Secrets.json` by Xcode Cloud `ci_pre_xcodebuild.sh` (key: `TRANSLATIONS_GITHUB_TOKEN`)
- Also loadable from environment variable `TRANSLATIONS_GITHUB_TOKEN` for local testing
- Read-only checks against public repos require no authentication
- Community translation downloads from GitHub Pages CDN require no authentication

## Requirements

### Functional Requirements

- **FR-001**: Translation MUST operate on markdown source files when `DocPage.markdownURL` is available, falling back to HTML translation for pages without bundled markdown.
- **FR-002**: Translated markdown MUST be converted to HTML on-device via `MarkdownConverter` for display in WKWebView.
- **FR-003**: `MarkdownConverter` MUST support: headings, paragraphs, lists, code fences, inline code, tables, links, images, `<picture>` elements (HTML passthrough), blockquote callouts (tip/warning), bold, italic, strikethrough, horizontal rules, and `.md` → `.html` link rewriting.
- **FR-004**: English `.md` source files MUST be bundled in the app at `Meshtastic/Resources/docs/markdown/` (copied by `build-docs.sh`).
- **FR-005**: Translated `.md` files MUST be cached in Application Support via the existing `TranslationCache` infrastructure with SHA-256 content-hash-based invalidation.
- **FR-006**: `CommunityTranslationFetcher` MUST check the GitHub Pages CDN feed (`index.json`) for existing translations before falling back to on-device translation.
- **FR-007**: `CommunityTranslationFetcher` MUST download `nav-labels.json` and import translated page titles into `DocTranslationService`'s UI string cache.
- **FR-008**: The feed MUST be fetched at most once per app launch (cached in-memory).
- **FR-009**: `CommunityTranslationFetcher` MUST prefer exact app version matches, falling back to the latest available version for the requested language.
- **FR-010**: `DocsTranslationUploader` MUST check both `meshtastic/meshtastic` (docs site) and `meshtastic/translations` (staging repo, via `manifest.json`) for existing translations before committing.
- **FR-011**: If no translations exist, the uploader MUST commit each translated `.md` file individually to `meshtastic/translations` under `apple-apps/{lang}/{version}/{section}/{page}.md`.
- **FR-012**: After all pages are uploaded, the uploader MUST commit a `manifest.json`, `nav-labels.json`, and `search-index.json` alongside the translated files.
- **FR-013**: The uploader MUST NOT re-upload files already committed in the current session (per-file tracking via `uploadedFilesThisSession`).
- **FR-014**: The GitHub fine-grained PAT MUST be loaded from `Secrets.json` (key: `TRANSLATIONS_GITHUB_TOKEN`) or the environment variable `TRANSLATIONS_GITHUB_TOKEN`, injected by Xcode Cloud CI.
- **FR-015**: The upload MUST run automatically at `.background` priority after prefetch completes — no user interaction required. It is gated on having a valid token; without a token it silently skips.
- **FR-016**: `DocTranslationService` MUST generate a translated search index after prefetch completes, extracting keywords from translated markdown and combining them with English keywords.
- **FR-017**: `CommunityTranslationFetcher` MUST download `search-index.json` and import it into `DocBundle` for localized search.
- **FR-018**: `DocBrowserView` search MUST match against both English keywords and translated keywords from the search index.
- **FR-019**: The "Clear App Data" button in App Settings MUST clear the translation cache (`TranslationCache.clearAll()`) and UI string cache alongside the database reset.
- **FR-020**: The "Participate in Distributed Translations" toggle MUST be in its own "Documentation Translations" section at the bottom of the App Settings form, defaulting to on. When off, auto-upload is skipped silently.

## Assumptions

- `MarkdownConverter` produces HTML equivalent to the `build-docs.sh` / `cmark-gfm` pipeline for the subset of GFM features used in the docs.
- The Translation framework (and FoundationModels fallback) produces acceptable translations when given properly segmented markdown input.
- A fine-grained GitHub PAT with write access to `meshtastic/translations` is injected via CI into `Secrets.json`.
- A GitHub Action in `meshtastic/translations` regenerates `index.json` on push and deploys to GitHub Pages — that action is outside the scope of this feature.
- Read-only checks against public GitHub repos stay within the 60 req/hour unauthenticated rate limit given the small number of doc pages.
- GitHub Pages CDN downloads are unauthenticated and have no practical rate limit for the volume of doc pages.
