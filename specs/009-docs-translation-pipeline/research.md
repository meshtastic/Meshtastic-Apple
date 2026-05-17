# Research: Docs Translation Pipeline

**Feature**: 009-docs-translation-pipeline  
**Date**: 2026-05-14

## Research Topics

### 1. Markdown→HTML Conversion On-Device

**Decision**: Enhanced lightweight custom converter (`MarkdownConverter.swift`)  
**Rationale**: The existing `markdownToHTML()` in `DocTranslationService` already handled basic conversion. Adding tables, callouts, inline formatting, and HTML passthrough was straightforward and avoids a new SPM dependency.  
**Alternatives considered**:
- `apple/swift-markdown` SPM package — full AST parser, but adds a dependency for a small feature. Overkill for known-format GFM docs.
- Shell out to `cmark-gfm` — not available on-device (macOS CLI tool only).

### 2. GitHub API for Auto-Upload

**Decision**: GitHub Contents API (`PUT /repos/{owner}/{repo}/contents/{path}`) with fine-grained PAT  
**Rationale**: Simple REST API, one file per request, no git operations needed. Per-file commits work well for incremental/retry scenarios.  
**Alternatives considered**:
- Git Data API (trees + blobs + commits) — more efficient for batch commits but significantly more complex. Not worth it for 27 files.
- GitHub App installation token — requires app registration and JWT generation on-device. Overly complex.

### 3. Token Storage

**Decision**: `SupportingFiles/secrets.json` injected by Xcode Cloud `ci_pre_xcodebuild.sh`  
**Rationale**: Existing pattern used for MQTT credentials. Token never in source code, injected at build time.  
**Alternatives considered**:
- Keychain — runtime storage, but how does the token get there? Requires UI or onboarding step.
- UserDefaults — not secure.
- Environment variable at runtime — not available on iOS.

### 4. Rate Limiting

**Decision**: Acceptable at current scale (2 unauthenticated reads + up to 27 authenticated writes per upload)  
**Rationale**: Unauthenticated limit is 60 req/hour (only 2 used for checks). Authenticated limit is 5,000 req/hour (max 27 used for file commits). Even with multiple languages, well within limits.  
**Risk**: If many users trigger uploads simultaneously for the same language, the Contents API will return 409 (conflict) on duplicate file creates. The per-file tracking and directory-exists check mitigate this.

### 5. Translation Quality at Markdown Level vs HTML Level

**Decision**: Markdown-level translation produces better results  
**Rationale**: Markdown has explicit structural markers (headings, code fences, list items) that are easier to segment and preserve during translation. HTML translation required complex regex to skip tags, attributes, and nested elements — fragile and error-prone.  
**Evidence**: Testing with French translation showed markdown approach preserves code blocks, table structure, and link references more reliably.

### 6. Versioned vs Latest Translations

**Decision**: Versioned by app version (`{lang}/{version}/{section}/{page}.md`)  
**Rationale**: Doc content changes between app versions. Versioning ensures translations match the source. Also enables historical reference and rollback.  
**Alternatives considered**:
- Latest only — simpler directory structure but loses version history and risks serving stale translations for older app versions.
