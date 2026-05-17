# Data Model: Automatic Docs Translation

## Entities

### TranslationCacheManifest

**Purpose**: Tracks all cached translations for LRU eviction and invalidation.

**Storage**: `Application Support/TranslatedDocs/manifest.json`

| Field | Type | Description |
|-------|------|-------------|
| entries | [TranslatedDocumentEntry] | All cached translation records |

---

### TranslatedDocumentEntry

**Purpose**: Metadata for a single cached translated document.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| sourceFile | String | ✅ | Relative path from docs root (e.g., "user/messages.md") |
| languageCode | String | ✅ | BCP 47 language code (e.g., "es", "de", "ja") |
| contentHash | String | ✅ | SHA-256 hash of the English source file content |
| translatedAt | Date | ✅ | ISO 8601 timestamp of when translation was performed |
| lastAccessedAt | Date | ✅ | ISO 8601 timestamp of last read (for LRU) |
| fileSize | Int | ✅ | Size in bytes of the translated .md file |

**Validation rules**:
- `languageCode` must be a valid BCP 47 code
- `contentHash` must be 64-char hex string (SHA-256)
- `fileSize` must be > 0

**Relationships**:
- Maps 1:1 to a file at `TranslatedDocs/{languageCode}/{contentHash}/{sourceFile basename}.md`

---

### TranslationRequest (in-memory only)

**Purpose**: Represents an in-flight translation job. Not persisted.

| Field | Type | Description |
|-------|------|-------------|
| sourceMarkdown | String | English markdown content to translate |
| sourcePath | String | Relative path of the source file |
| targetLanguage | Locale.Language | Target language for translation |
| contentHash | String | SHA-256 of source content |
| priority | TranslationPriority | `.immediate` (current page) or `.prefetch` (background) |

---

### TranslationPriority (enum)

| Case | Description |
|------|-------------|
| .immediate | Current page — user is waiting |
| .prefetch | Background prefetch — low priority |

---

## State Transitions

```
DocPage requested
    │
    ▼
[Check locale == English?] ──yes──▶ Load bundled HTML (existing flow)
    │ no
    ▼
[Check cache: hash match + language?] ──hit──▶ Update lastAccessedAt → Load cached translation
    │ miss
    ▼
[Show loading indicator]
    │
    ▼
[Check Translation.framework availability] ──available──▶ Translate via Session
    │ unavailable                                              │
    ▼                                                          ▼
[Check FoundationModels availability] ──available──▶ Translate via LLM prompt
    │ unavailable                                        │
    ▼                                                    ▼
[Fallback: load English HTML]              [Cache result → Convert to HTML → Display]
                                                         │
                                                         ▼
                                           [Trigger background prefetch of other pages]
```

## File System Layout

```
{App Support}/TranslatedDocs/
├── manifest.json
├── es/
│   ├── a1b2c3.../messages.md
│   ├── d4e5f6.../nodes.md
│   └── ...
├── de/
│   └── ...
└── ja/
    └── ...
```
