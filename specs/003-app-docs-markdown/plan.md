# Implementation Plan: App Documentation (Jekyll Site + In-App AI)

**Branch**: `003-app-docs-markdown` | **Date**: 2026-05-05 | **Spec**: [spec.md](spec.md)  
**Status**: Implemented  
**Input**: Feature specification from `specs/003-app-docs-markdown/spec.md`

## Summary

Build a complete documentation system for the Meshtastic Apple app: (1) a GitHub Pages Jekyll site served via GitHub Actions, (2) an in-app offline doc browser (SwiftUI `NavigationStack` + `WKWebView`), and (3) an on-device AI assistant powered by Foundation Models (iOS 26+). Source content is derived from existing in-app help sheet views and TipKit tips. Docs are versioned per App Store release and per beta build. The build pipeline uses `cmark-gfm` to convert GFM markdown to HTML, injects dark-mode CSS, builds a keyword index JSON for AI retrieval, and enforces a 10 MB bundle size ceiling.

**Post-implementation additions (not in original spec):**
- `DocModels.swift` extracted as a dedicated file (DocPage, DocSection, KeywordIndexEntry, DocBundle) — not merged into DocBrowserView.
- `nav_order` field added to `KeywordIndexEntry` and `index.json`; `DocBundle.pagesBySection()` sorts by `navOrder` to preserve intended reading order.
- `build-docs.sh` strips YAML frontmatter and Kramdown `{: .xxx }` attribute lines before piping to `cmark-gfm`; Python post-processing converts blockquotes to `tips-callout` / `warning-callout` divs; beta banner uses `class="pre-release-banner"` instead of inline styles.
- CSS extended with `.tips-callout`, `.warning-callout`, `.pre-release-banner` using CSS custom properties for full dark-mode support; `img` rule added for in-WebView image sizing.
- AI assistant fully branded as **Chirpy**: avatar image header, "Hi, I'm Chirpy!" headline, Chirpy system persona, `.scrollDismissesKeyboard(.interactively)` on the sheet form.
- 57 screenshot PNGs embedded inline in 7 User Guide pages (nodes, messages, mqtt, telemetry, map, firmware, discovery).
- Two new snapshot test suites added: `NodeStatusIconSnapshotTests` (nodeOnline, nodeIdle, hopsAway, channelBadge) and `ChannelLockIconSnapshotTests` (lockClosed, lockOpen, lockOpenRed, lockOpenMqtt, keySlash) — 9 new PNGs generated and embedded.
- **Apple Watch App** page (`docs/user/watch.md`, `nav_order: 12`) added to User Guide covering Foxhunt, compass view, phone connectivity tab, and foxhunt target pinning.
- Total bundle: **19 pages** (was 18 planned), **2.2 MB** (well within 10 MB ceiling).

## Technical Context

**Language/Version**: Swift (latest stable) for app code; bash for build scripts; YAML for GitHub Actions workflows  
**Primary Dependencies**: WebKit (`WKWebView`), FoundationModels (iOS 26+), `cmark-gfm` CLI (Homebrew), GitHub Actions (`actions/deploy-pages`), `just-the-docs` Jekyll theme  
**Storage**: Main app bundle — `Meshtastic/Resources/docs/` copied via Xcode Copy Files build phase; no SwiftData models required  
**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`); existing snapshot test infrastructure for screenshot sourcing  
**Target Platform**: iOS 17.5+ / iPadOS 17.5+ / macOS Catalyst 17.5+ (app); macOS GitHub Actions runner (CI pipeline)  
**Project Type**: Mobile app feature + CI/CD pipeline + static site  
**Performance Goals**: TOC loads within 1 second (SC-003); AI responds within 5 seconds (SC-006); CI pipeline completes within 10 minutes (SC-005)  
**Constraints**: Bundle ≤ 10 MB (FR-021, warn at 8 MB); AI context ≤ 3,000 tokens per query (FR-011); fully offline in-app (FR-007); no new tab bar item (FR-006)  
**Scale/Scope**: ~25 doc pages (12 User Guide + 7 Developer Guide + index), 66 screenshot PNGs, 1 keyword index JSON, 2 GitHub Actions workflows

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. SwiftUI-Native | ✅ PASS | `DocBrowserView`, `AIDocAssistantView`, `DocTOCView` are pure SwiftUI. `WKWebView` is wrapped in a `UIViewRepresentable` — unavoidable, no SwiftUI equivalent. |
| II. SwiftData Persistence | ✅ N/A | No persistent models needed. Doc content lives in the bundle. |
| III. Protocol-Oriented Transport | ✅ N/A | No device transport involved. |
| IV. Structured Logging | ✅ PASS | New `Logger.docs` category added to `Meshtastic/Extensions/Logger.swift`. |
| V. Protobuf Contract Fidelity | ✅ N/A | No protobuf usage. |
| VI. Lint-Clean Commits | ✅ PASS | All Swift code passes SwiftLint. Build scripts are bash (not linted). |
| VII. Platform Parity | ✅ PASS | `WKWebView` is available on iOS and macCatalyst. `FoundationModels` gated with `#available(iOS 26, *)`. macCatalyst shows doc browser without AI input on macOS < 26. |
| VIII. Design Standards | ✅ REQUIRED | Must fetch and review Meshtastic Client Design Standards before implementing any UI. |

**Gate result: PASS.** No constitution violations. Proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/003-app-docs-markdown/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── keyword-index-schema.json   # JSON schema for keyword index
│   ├── deep-link-contract.md       # meshtastic:///settings/help routing contract
│   └── ci-workflow-contract.md     # GitHub Actions workflow interface contract
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# App source additions
Meshtastic/
├── Resources/
│   └── docs/                        # Generated HTML bundle (git-tracked, built by script)
│       ├── index.json               # Keyword index JSON (AI retrieval)
│       ├── user/                    # User Guide HTML pages
│       │   ├── getting-started.html
│       │   ├── bluetooth.html
│       │   ├── messages.html
│       │   ├── nodes.html
│       │   ├── map.html
│       │   ├── settings.html
│       │   ├── telemetry.html
│       │   ├── tak.html
│       │   ├── mqtt.html
│       │   ├── discovery.html
│       │   ├── firmware.html
│       │   └── watch.html           # Apple Watch App (added post-spec, nav_order: 12)
│       ├── developer/               # Developer Guide HTML pages
│       │   ├── architecture.html
│       │   ├── codebase.html
│       │   ├── adding-features.html
│       │   ├── transport.html
│       │   ├── swiftdata.html
│       │   ├── testing.html
│       │   └── contributing.html
│       └── assets/
│           ├── docs.css             # Light/dark CSS (prefers-color-scheme); callout classes; img rule
│           └── screenshots/         # 66 PNGs: 57 original + 9 new icon snapshots
├── Views/
│   └── Settings/
│       └── HelpAndDocumentation/
│           ├── DocModels.swift               # DocPage, DocSection, KeywordIndexEntry, DocBundle (@Observable)
│           ├── DocBrowserView.swift          # NavigationStack TOC + search; destination-form NavigationLink
│           ├── DocPageView.swift             # WKWebView detail view
│           └── AIDocAssistantView.swift      # iOS 26+ Chirpy AI assistant sheet
├── Extensions/
│   └── Logger.swift                 # Add Logger.docs category (extend existing file)
└── Router/
    └── NavigationState.swift        # Add helpDocs case to SettingsNavigationState

# Markdown source (authored content)
docs/
├── _config.yml                      # Jekyll config (just-the-docs theme, .nojekyll)
├── index.md                         # Site root → redirects to latest version
├── user/                            # 12 GFM source pages (11 original + watch.md)
└── developer/                       # 7 GFM source pages

# Build scripts
scripts/
├── build-docs.sh                    # cmark-gfm → HTML, CSS injection, keyword index, size check
└── copy-snapshots.sh                # Copies PNGs from MeshtasticTests/__Snapshots__/ → docs/assets/screenshots/

# GitHub Actions workflows
.github/workflows/
├── docs-deploy.yml                  # Triggers on push to main → builds + deploys /beta/ path
└── docs-release.yml                 # Triggers on v*.*.* tag push → builds + deploys /vX.Y.Z/ path

# Tests
MeshtasticTests/
├── DocBundleTests.swift             # Swift Testing: bundle completeness, keyword index validity, token budget (13 tests)
└── SwiftUIViewSnapshotTests.swift   # Extended with NodeStatusIconSnapshotTests, ChannelLockIconSnapshotTests (+9 tests)
```

**Structure Decision**: Single project (mobile app + scripts + static site). No new SPM packages or separate targets. The doc bundle is a static resource in the main target. The Jekyll site is source-controlled in `docs/` and deployed by GitHub Actions.

## Complexity Tracking

*No constitution violations — table omitted.*
