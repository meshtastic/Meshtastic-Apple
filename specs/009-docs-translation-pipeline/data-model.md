# Data Model: Docs Translation Pipeline

**Feature**: 009-docs-translation-pipeline  
**Date**: 2026-05-14

## Entities

### DocPage (updated)

Existing entity with new computed property.

| Field | Type | Description |
|-------|------|-------------|
| id | String | Page slug (e.g., "getting-started") |
| title | String | English page title |
| section | DocSection | `.user` or `.developer` |
| htmlURL | URL | Bundled `.html` file URL |
| markdownURL | URL? | **NEW** — Bundled `.md` source file URL (computed) |
| keywords | [String] | Search keywords |
| charCount | Int | Character count for token budgeting |
| navOrder | Int | Navigation sort order |

### TranslationCache Entry (existing, unchanged)

File-based cache in Application Support.

| Field | Type | Description |
|-------|------|-------------|
| sourceFile | String | e.g., `user/getting-started.md` |
| languageCode | String | e.g., `fr` |
| contentHash | String | SHA-256 of source file (invalidation key) |
| cachedFileURL | URL | Path to translated `.md` file in cache |

### Upload Tracking (in-memory, per-session)

| Field | Type | Description |
|-------|------|-------------|
| uploadedFilesThisSession | Set\<String\> | File paths already committed (e.g., `apple-apps/fr/2.7.13/user/getting-started.md`) |

## Relationships

```
DocPage 1──1 markdownURL (computed from bundle)
DocPage 1──* TranslationCache entries (one per language)
TranslationCache entry 1──1 translated .md file (on disk)
DocsTranslationUploader reads TranslationCache to get translated content for upload
```

## State Transitions

### Translation State (per page per language)

```
Untranslated → Translating → Cached → Uploaded
                    ↓
               Failed (falls back to English)
```

### Upload State (per file)

```
Not Uploaded → Uploading → Uploaded (tracked in uploadedFilesThisSession)
                   ↓
              Failed (retryable — not added to tracking set)
```

## No Schema Changes

This feature does not modify any SwiftData `@Model` types. All data is file-based (Application Support cache + GitHub API).
