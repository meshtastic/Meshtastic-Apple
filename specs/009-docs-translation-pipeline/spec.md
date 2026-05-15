# Feature Specification: Docs Translation Pipeline

**Feature Branch**: `009-docs-translation-pipeline`  
**Created**: 2026-05-14  
**Status**: Draft  

## Summary

Restructure the on-device documentation translation to operate on markdown source files instead of HTML, then rebuild HTML locally from the translated markdown using the existing `cmark-gfm` pipeline. Additionally, create a service that detects new app version + language combinations and automatically opens PRs against the Meshtastic docs site repo with the translated markdown files.

## User Scenarios & Testing

### User Story 1 — Translate at Markdown Level (Priority: P1)

The current translation engine translates HTML text nodes, which is fragile (must skip tags, attributes, code blocks, picture elements). Translating the markdown source is simpler and produces higher-quality output because markdown structure (headings, links, code fences, tables) is more explicit and easier to preserve.

**Acceptance Scenarios**:

1. **Given** a user opens a docs page in French, **When** the page is not cached, **Then** the system translates the English `.md` source, converts it to HTML using the same pipeline as `build-docs.sh`, and displays it.
2. **Given** a translated `.md` file is cached, **When** the user opens the same page, **Then** the cached markdown is converted to HTML and displayed instantly.
3. **Given** markdown contains code fences, tables, links, images, and `<picture>` elements, **When** translated, **Then** all non-translatable elements are preserved verbatim.

### User Story 2 — Push Translated Docs to Repo via PR (Priority: P2)

When a new app version ships with updated English docs, a service detects that translated markdown files don't exist for a given version + language combination and opens a PR on the Meshtastic docs site repo with the translated files.

**Acceptance Scenarios**:

1. **Given** app version 2.7.13 ships with updated English docs, **When** French translations are generated on-device, **Then** the service checks the target repo for existing `fr/2.7.13` translations.
2. **Given** no translations exist for that combo, **When** the check completes, **Then** the service creates a branch, commits the translated `.md` files, and opens a PR.
3. **Given** translations already exist for that version + language, **When** the check completes, **Then** no PR is created.

### User Story 3 — Community Translation Review (Priority: P3)

The auto-generated PR serves as a starting point for community review. Native speakers can review, edit, and approve the machine-translated docs before they're merged into the docs site.

## Architecture

### Part 1: Markdown-Level Translation (On-Device)

```
Current flow:
  Bundled HTML → translate HTML text nodes → display in WKWebView

New flow:
  Bundled .md source → translate markdown segments → cache translated .md
  → convert to HTML (cmark-gfm equivalent) → display in WKWebView
```

#### Markdown Source Access
The app already bundles the source `.md` files under `docs/user/` and `docs/developer/` (they're in the repo). We need to also copy them into the app bundle so they're available at runtime, OR read them from the bundled HTML by extracting text (current approach, but reversed).

**Recommended**: Bundle the `.md` files alongside the `.html` files in `Meshtastic/Resources/docs/` so the translation service can read the original markdown.

#### Translation Pipeline
1. Read English `.md` source from bundle
2. Segment into translatable vs non-translatable blocks (reuse existing `segmentMarkdown()`)
3. Translate text segments via Translation framework (iOS 26+)
4. Reassemble translated `.md`
5. Convert to HTML using a Swift markdown→HTML converter (since `cmark-gfm` CLI isn't available on-device)
6. Cache both the translated `.md` and the generated `.html`
7. Display HTML in WKWebView

#### Swift Markdown→HTML Options
- **apple/swift-markdown** (`Markdown` package) — Apple's parser, can walk AST and emit HTML
- **Custom lightweight converter** — the existing `markdownToHTML()` in `DocTranslationService` already handles basic conversion
- **Enhance existing converter** — add table support, blockquote callouts, and image passthrough to the existing `markdownToHTML()`

### Part 2: Translation PR Service

#### Option A: On-Device GitHub API (Recommended for MVP)
- After successful translation + cache of all pages for a language:
  1. Check GitHub API: does branch `translations/{version}/{lang}` exist in target repo?
  2. If not, create branch from `main`
  3. Commit translated `.md` files via GitHub Contents API
  4. Open PR via GitHub API
- Requires: GitHub personal access token stored in Keychain or app config
- Rate limit: GitHub API allows 5000 req/hour with token

#### Option B: GitHub Action (Better for Production)
- On-device: upload translated `.md` files to a staging location (e.g., artifact, gist, or branch)
- GitHub Action triggers on new branch/tag, validates files, opens PR
- More robust, doesn't require token on-device

#### Option C: Companion CLI / Script
- A `scripts/push-translations.sh` that takes a directory of translated `.md` files, a version, and a language, and handles the git/GitHub operations
- Run manually or from CI

#### Target Repo Structure
```
meshtastic-docs-site/
  docs/
    en/           ← English originals (source of truth)
    fr/           ← French translations
    es/           ← Spanish translations
    de/           ← German translations
    ...
```

Or versioned:
```
meshtastic-docs-site/
  docs/
    en/2.7.13/
    fr/2.7.13/
    ...
```

## Requirements

### Functional Requirements

- **FR-001**: Translation MUST operate on markdown source files, not HTML.
- **FR-002**: Translated markdown MUST be converted to HTML on-device for display.
- **FR-003**: The markdown→HTML conversion MUST support: headings, paragraphs, lists, code fences, inline code, tables, links, images, `<picture>` elements (HTML passthrough), blockquote callouts (tip/warning), bold, italic, strikethrough.
- **FR-004**: English `.md` source files MUST be bundled in the app alongside the HTML files.
- **FR-005**: Translated `.md` files MUST be cached in Application Support (existing cache infrastructure).
- **FR-006**: A service MUST check whether translated docs exist for a given app version + language in a target GitHub repo.
- **FR-007**: If no translations exist, the service MUST create a PR with the translated `.md` files.
- **FR-008**: The service MUST NOT create duplicate PRs for the same version + language.
- **FR-009**: GitHub authentication token MUST be stored securely (Keychain).
- **FR-010**: The PR creation MUST be opt-in (user-initiated or admin-only), not automatic on every translation.

## Open Questions

1. Which target repo should receive the PRs? (`meshtastic/meshtastic` docs site, or a dedicated translations repo?)
2. Should the PR service run on-device or as a GitHub Action triggered by a release?
3. Should we use `apple/swift-markdown` SPM package or enhance the existing lightweight converter?
4. Should translated `.md` files be versioned by app version, or just track the latest?
5. What's the GitHub auth flow — OAuth app, personal access token, or fine-grained token?

## Assumptions

- The existing `build-docs.sh` pipeline using `cmark-gfm` is the reference implementation for markdown→HTML conversion.
- The Translation framework produces acceptable markdown-aware translations when given properly segmented input.
- A GitHub token with `repo` scope on the target repo is available for PR creation.
- The target docs site can accommodate a `{lang}/` directory structure for translations.
